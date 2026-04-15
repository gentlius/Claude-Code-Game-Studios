## Autoload — Manages per-stock stop-loss / take-profit auto-sell conditions.
## Called from OrderEngine.process_tick() at step 3-d (after limit order check).
## TR2 스킬 기능. See: design/gdd/stop-loss-take-profit.md
extends Node

# ── Signals ──

## Emitted when a stop-loss or take-profit condition triggers and an auto sell fires.
signal on_stop_take_triggered(stock_id: String, reason: String, filled_price: int)

# ── Config (Tuning Knobs) ──
## Loaded from assets/data/stop_take_config.json at startup.

## Maximum simultaneous settings. Hard cap; practical cap is max_holdings.
var STOP_TAKE_MAX_SETTINGS: int = 10
## Whether to show a toast notification on trigger.
var NOTIFY_ON_TRIGGER: bool = true

const CONFIG_PATH: String = "res://assets/data/stop_take_config.json"

# ── State ──

## stock_id → StopTakeSetting dict:
##   { stock_id, stop_loss_price (int|null), take_profit_price (int|null), quantity, enabled }
var _settings: Dictionary = {}

# ── Lifecycle ──

func _ready() -> void:
	_load_config()
	PortfolioManager.holding_removed.connect(_on_holding_removed)
	GameClock.on_season_start.connect(_on_season_start)


func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	var cfg := parsed as Dictionary
	STOP_TAKE_MAX_SETTINGS = cfg.get("stopTakeMaxSettings", STOP_TAKE_MAX_SETTINGS)
	NOTIFY_ON_TRIGGER = cfg.get("notifyOnTrigger", NOTIFY_ON_TRIGGER)


func _on_season_start() -> void:
	_settings.clear()


## Called by PortfolioManager.holding_removed signal — clear setting if stock fully sold.
func _on_holding_removed(stock_id: String, _qty: int, _price: int, _pnl: int) -> void:
	# Only clear if holding is now gone entirely.
	if PortfolioManager.get_holding(stock_id) == null:
		_settings.erase(stock_id)


# ── Public API ──

## Set stop-loss / take-profit condition for a stock.
## stop_loss_price and take_profit_price: pass null to leave unset.
## Returns false if TR2 not unlocked, holding not found, or limit exceeded.
func set_condition(
	stock_id: String,
	stop_loss_price: Variant,   ## int or null
	take_profit_price: Variant, ## int or null
	quantity: int
) -> bool:
	if not SkillTree.is_skill_unlocked("TR2"):
		return false
	if PortfolioManager.get_holding(stock_id) == null:
		return false
	if quantity <= 0:
		return false
	if _settings.size() >= STOP_TAKE_MAX_SETTINGS and not _settings.has(stock_id):
		return false

	_settings[stock_id] = {
		"stock_id": stock_id,
		"stop_loss_price": stop_loss_price,
		"take_profit_price": take_profit_price,
		"quantity": quantity,
		"enabled": true,
	}
	return true


## Remove the stop-take condition for a stock.
func clear_condition(stock_id: String) -> void:
	_settings.erase(stock_id)


## Returns the setting dict for a stock, or null if not set.
func get_setting(stock_id: String) -> Variant:
	return _settings.get(stock_id)


## Returns all active settings as an Array.
func get_all_settings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for s: Dictionary in _settings.values():
		result.append(s)
	return result


## Called from OrderEngine.process_tick() at step 3-d.
## Evaluates all active settings and fires auto market-sell if conditions are met.
func check_and_trigger(market_state: GameClock.MarketState) -> void:
	if market_state != GameClock.MarketState.MARKET_OPEN:
		return

	# Collect triggers first — avoid mutating _settings while iterating.
	var triggers: Array[String] = []

	for stock_id: String in _settings:
		var s: Dictionary = _settings[stock_id]
		if not s.get("enabled", true):
			continue

		var holding: Variant = PortfolioManager.get_holding(stock_id)
		if holding == null:
			triggers.append(stock_id)  # holding gone — remove setting after loop
			continue

		var current_price: int = PriceEngine.get_current_price(stock_id)
		var sl: Variant = s["stop_loss_price"]
		var tp: Variant = s["take_profit_price"]

		# Check stop-loss (sl != null and price breached below)
		var sl_triggered: bool = (sl != null and current_price <= (sl as int))
		# Check take-profit only if stop-loss didn't trigger (elif semantics per GDD §규칙 3)
		var tp_triggered: bool = (not sl_triggered and tp != null and current_price >= (tp as int))

		if sl_triggered or tp_triggered:
			var locked: int = OrderEngine.get_locked_quantity(stock_id)
			var available: int = (holding as Dictionary).get("quantity", 0) - locked
			var qty: int = min(s["quantity"], available)

			if qty > 0:
				var reason: String = "STOP_LOSS" if sl_triggered else "TAKE_PROFIT"
				var order: Dictionary = OrderEngine.submit_market_order("SELL", stock_id, qty)
				if order.get("status", "") == "FILLED":
					var filled_price: int = order.get("filled_price", current_price)
					on_stop_take_triggered.emit(stock_id, reason, filled_price)
			# Setting removed regardless of fill success (GDD §규칙 5)
			triggers.append(stock_id)

	# Remove triggered/cleared settings after iteration
	for stock_id: String in triggers:
		_settings.erase(stock_id)


# ── Serialization ──

## Returns serializable state for SaveSystem (GDD: save-load.md §3-4).
func get_save_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for s: Dictionary in _settings.values():
		result.append(s.duplicate())
	return result


## Restores state from save data. Validates TR2 unlock and existing holdings.
func load_save_data(data: Array) -> void:
	_settings.clear()
	if not SkillTree.is_skill_unlocked("TR2"):
		return  # AC-15: discard settings if TR2 not unlocked on load
	for item: Variant in data:
		if not item is Dictionary:
			continue
		var s := item as Dictionary
		var stock_id: String = str(s.get("stock_id", ""))
		if stock_id.is_empty():
			continue
		# AC-16 (from edge cases): discard if holding no longer exists
		if PortfolioManager.get_holding(stock_id) == null:
			continue
		_settings[stock_id] = {
			"stock_id": stock_id,
			"stop_loss_price": s.get("stop_loss_price"),
			"take_profit_price": s.get("take_profit_price"),
			"quantity": s.get("quantity", 1),
			"enabled": s.get("enabled", true),
		}


## Resets all state. Called by tests.
func reset() -> void:
	_settings.clear()
