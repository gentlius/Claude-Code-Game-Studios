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
	ShortSellingSystem.on_short_position_closed.connect(_on_short_position_closed)
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


## Called by ShortSellingSystem.on_short_position_closed — clear setting when short is closed.
func _on_short_position_closed(stock_id: String, _pnl: int) -> void:
	if _settings.has(stock_id) and _settings[stock_id].get("is_short", false):
		_settings.erase(stock_id)


# ── Public API ──

## Set stop-loss / take-profit condition for a long or short position.
## stop_loss_price and take_profit_price: pass null to leave unset.
## For shorts: stop_loss fires when price RISES above threshold; take_profit when it FALLS below.
## Returns false if TR2 not unlocked, no position found, or limit exceeded.
func set_condition(
	stock_id: String,
	stop_loss_price: Variant,   ## int or null
	take_profit_price: Variant, ## int or null
	quantity: int
) -> bool:
	if not SkillTree.is_skill_unlocked("TR2"):
		return false
	var has_long: bool = PortfolioManager.get_holding(stock_id) != null
	var has_short: bool = ShortSellingSystem.has_short(stock_id)
	if not has_long and not has_short:
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
		"is_short": has_short,
	}
	return true


## Remove the stop-take condition for a stock.
func clear_condition(stock_id: String) -> void:
	_settings.erase(stock_id)


## Returns the setting dict for a stock, or {} if not set.
func get_setting(stock_id: String) -> Dictionary:
	return _settings.get(stock_id, {})


## Returns all active settings as an Array.
func get_all_settings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for s: Dictionary in _settings.values():
		result.append(s)
	return result


## Called from OrderEngine.process_tick() at step 3-d.
## Evaluates all active settings and fires auto order if conditions are met.
## Longs: SELL when price breaches sl (below) or tp (above).
## Shorts: BUY_TO_COVER when price breaches sl (above) or tp (below) — inverted direction.
func check_and_trigger(market_state: GameClock.MarketState) -> void:
	if market_state != GameClock.MarketState.MARKET_OPEN:
		return
	# Collect triggers first — avoid mutating _settings while iterating.
	var triggers: Array[String] = []
	for stock_id: String in _settings:
		var s: Dictionary = _settings[stock_id]
		if not s.get("enabled", true):
			continue
		if s.get("is_short", false):
			_evaluate_short(stock_id, s, triggers)
		else:
			_evaluate_long(stock_id, s, triggers)
	for stock_id: String in triggers:
		_settings.erase(stock_id)


func _evaluate_long(stock_id: String, s: Dictionary, triggers: Array[String]) -> void:
	var holding: Variant = PortfolioManager.get_holding(stock_id)
	if holding == null:
		triggers.append(stock_id)  # holding gone — remove stale setting
		return
	var current_price: int = PriceEngine.get_current_price(stock_id)
	var sl: Variant = s["stop_loss_price"]
	var tp: Variant = s["take_profit_price"]
	var sl_triggered: bool = (sl != null and current_price <= (sl as int))
	var tp_triggered: bool = (not sl_triggered and tp != null and current_price >= (tp as int))
	if not sl_triggered and not tp_triggered:
		return
	var locked: int = OrderEngine.get_locked_quantity(stock_id)
	var available: int = (holding as Dictionary).get("quantity", 0) - locked
	var qty: int = mini(s["quantity"], available)
	if qty > 0:
		var reason: String = "STOP_LOSS" if sl_triggered else "TAKE_PROFIT"
		var order: Dictionary = OrderEngine.submit_market_order("SELL", stock_id, qty)
		if order.get("status", "") == "FILLED":
			on_stop_take_triggered.emit(stock_id, reason, order.get("filled_price", current_price))
	triggers.append(stock_id)  # remove regardless of fill (GDD §규칙 5)


func _evaluate_short(stock_id: String, s: Dictionary, triggers: Array[String]) -> void:
	if not ShortSellingSystem.has_short(stock_id):
		triggers.append(stock_id)  # position gone — remove stale setting
		return
	var current_price: int = PriceEngine.get_current_price(stock_id)
	var sl: Variant = s["stop_loss_price"]
	var tp: Variant = s["take_profit_price"]
	# 숏 방향 역전: 손절 = 가격 상승(sl 이상), 익절 = 가격 하락(tp 이하)
	var sl_triggered: bool = (sl != null and current_price >= (sl as int))
	var tp_triggered: bool = (not sl_triggered and tp != null and current_price <= (tp as int))
	if not sl_triggered and not tp_triggered:
		return
	var short_qty: int = _get_short_quantity(stock_id)
	var qty: int = mini(s["quantity"], short_qty)
	if qty > 0:
		var reason: String = "STOP_LOSS" if sl_triggered else "TAKE_PROFIT"
		var order: Dictionary = OrderEngine.submit_market_order("BUY_TO_COVER", stock_id, qty)
		if order.get("status", "") == "FILLED":
			on_stop_take_triggered.emit(stock_id, reason, order.get("filled_price", current_price))
	triggers.append(stock_id)


## Returns the quantity of the current short position, or 0 if none.
func _get_short_quantity(stock_id: String) -> int:
	for pos: Dictionary in ShortSellingSystem.get_all_short_positions():
		if pos.get("stock_id", "") == stock_id:
			return pos.get("quantity", 0)
	return 0


# ── Serialization ──

## Returns serializable state for SaveSystem (GDD: save-load.md §3-4).
func get_save_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for s: Dictionary in _settings.values():
		result.append(s.duplicate())
	return result


## Restores state from save data. Validates TR2 unlock and existing positions.
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
		var is_short: bool = s.get("is_short", false)
		# AC-16: discard if the underlying position no longer exists
		if is_short:
			if not ShortSellingSystem.has_short(stock_id):
				continue
		else:
			if PortfolioManager.get_holding(stock_id) == null:
				continue
		_settings[stock_id] = {
			"stock_id": stock_id,
			"stop_loss_price": s.get("stop_loss_price"),
			"take_profit_price": s.get("take_profit_price"),
			"quantity": s.get("quantity", 1),
			"enabled": s.get("enabled", true),
			"is_short": is_short,
		}


## Resets all state. Called by tests.
func reset() -> void:
	_settings.clear()
