## Autoload — Manages short-selling (SELL_SHORT / BUY_TO_COVER) positions.
## Gameplay layer. Depends on: PriceEngine, CurrencySystem, GameClock.
## Called by: OrderEngine (open_position, close_position),
##             GameClock (_process_tick), SeasonManager (_on_season_end),
##             PortfolioManager (update_valuation).
## See: design/gdd/short-selling.md
extends Node

# ── Signals ──

## Emitted when a short position is forcibly closed (margin_ratio < threshold).
signal on_forced_liquidation(stock_id: String, price: int, pnl: int)

## Emitted when any short position closes (manual cover, forced, or season-end).
signal on_short_position_closed(stock_id: String, pnl: int)

# ── Config ──

const CONFIG_PATH: String = "res://assets/data/short_selling_config.json"

var _margin_rate: float = 1.40
var _margin_call_threshold: float = 0.20
var _max_short_positions: int = 3

# ── State ──

## stock_id -> ShortPosition dict
var _positions: Dictionary = {}

# ── Lifecycle ──

func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		push_warning("ShortSellingSystem: config not found at %s — using defaults" % CONFIG_PATH)
		return
	var text: String = f.get_as_text()
	f.close()
	var result: Variant = JSON.parse_string(text)
	if result == null or not result is Dictionary:
		push_warning("ShortSellingSystem: JSON parse failed for %s — using defaults" % CONFIG_PATH)
		return
	_margin_rate = result.get("margin_rate", _margin_rate)
	_margin_call_threshold = result.get("margin_call_threshold", _margin_call_threshold)
	_max_short_positions = result.get("max_short_positions", _max_short_positions)

# ── Public API: Query ──

## True if a short position exists for the given stock.
func has_short(stock_id: String) -> bool:
	return _positions.has(stock_id)


## Number of currently open short positions.
func get_short_count() -> int:
	return _positions.size()


## Maximum simultaneous short positions (from config).
func get_max_short_positions() -> int:
	return _max_short_positions


## Configured margin rate (e.g. 1.40 = 140%). Used by OrderEngine for validation.
func get_margin_rate() -> float:
	return _margin_rate


## Returns all short positions as an array of dicts (for UI display).
## Each dict is a shallow copy of the internal record.
func get_all_short_positions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pos: Dictionary in _positions.values():
		result.append(pos.duplicate())
	return result


## Net short contribution to total assets.
## = Σ(margin_deposited + unrealized_pnl) — corrects for the margin already
## deducted from sim_cash. GDD §규칙 10.
func get_short_net_value() -> int:
	var total: int = 0
	for pos: Dictionary in _positions.values():
		total += pos["margin_deposited"] + pos["unrealized_pnl"]
	return total

# ── Public API: Position Management (called by OrderEngine) ──

## Open a short position from a validated SELL_SHORT order.
## Deducts margin_deposited, adds sale_proceeds, creates ShortPosition record.
## Returns filled_price (> 0) on success, 0 on failure.
## GDD §규칙 5.
func open_position(order: Dictionary) -> int:
	var stock_id: String = order["stock_id"]
	var quantity: int = order["quantity"]
	var open_price: int = PriceEngine.get_current_price(stock_id)
	if open_price <= 0:
		push_error("ShortSellingSystem.open_position: price=0 for %s" % stock_id)
		return 0

	var initial_value: int = open_price * quantity
	var margin_deposited: int = int(ceil(float(initial_value) * _margin_rate))

	# Deduct margin from sim_cash (locks 140% of initial value)
	if not CurrencySystem.sim_deduct(margin_deposited):
		push_error("ShortSellingSystem.open_position: margin deduction failed for %s" % stock_id)
		return 0

	# Add sale proceeds (borrowed shares sold at current price)
	CurrencySystem.sim_add(initial_value)

	_positions[stock_id] = {
		"stock_id":           stock_id,
		"quantity":           quantity,
		"open_price":         open_price,
		"initial_value":      initial_value,
		"margin_deposited":   margin_deposited,
		"open_tick":          GameClock.get_current_tick(),
		"open_day":           GameClock.get_current_day(),
		"unrealized_pnl":     0,
		"unrealized_pnl_pct": 0.0,
		"margin_ratio":       _margin_rate,  ## = margin_deposited / initial_value at open
	}
	return open_price


## Close a short position from a validated BUY_TO_COVER order.
## Returns realized_pnl (positive = profit, negative = loss).
## GDD §규칙 7.
func close_position(order: Dictionary) -> int:
	var stock_id: String = order["stock_id"]
	if not _positions.has(stock_id):
		push_error("ShortSellingSystem.close_position: no position for %s" % stock_id)
		return 0

	var pos: Dictionary = _positions[stock_id]
	var cover_price: int = PriceEngine.get_current_price(stock_id)
	var cover_cost: int = cover_price * pos["quantity"]
	var pnl: int = (pos["open_price"] - cover_price) * pos["quantity"]

	if not CurrencySystem.sim_deduct(cover_cost):
		push_error("ShortSellingSystem.close_position: sim_deduct failed for %s (cost=%d, balance=%d)" \
			% [stock_id, cover_cost, CurrencySystem.get_sim_cash()])
	CurrencySystem.sim_add(maxi(0, pos["margin_deposited"] + pnl))

	_positions.erase(stock_id)
	on_short_position_closed.emit(stock_id, pnl)
	return pnl

# ── Public API: Tick Processing (called by GameClock) ──

## Called after PriceEngine.process_tick(), before OrderEngine.process_tick().
## Updates unrealized_pnl and margin_ratio; triggers forced liquidation when
## margin_ratio < _margin_call_threshold. GDD §규칙 6.
func update_and_check_margin(_tick: int) -> void:
	if _positions.is_empty():
		return

	# Collect stocks to liquidate BEFORE mutating _positions (avoids dict-resize-during-iter)
	var to_liquidate: Array[String] = []
	for stock_id: String in _positions:
		var pos: Dictionary = _positions[stock_id]
		var current_price: int = PriceEngine.get_current_price(stock_id)

		pos["unrealized_pnl"] = (pos["open_price"] - current_price) * pos["quantity"]
		if pos["initial_value"] > 0:
			pos["unrealized_pnl_pct"] = (
				float(pos["unrealized_pnl"]) / float(pos["initial_value"]) * 100.0
			)
		pos["margin_ratio"] = (
			float(pos["margin_deposited"] + pos["unrealized_pnl"]) / float(pos["initial_value"])
		)

		if pos["margin_ratio"] < _margin_call_threshold:
			to_liquidate.append(stock_id)

	for stock_id: String in to_liquidate:
		_trigger_forced_liquidation(stock_id)


## Season-end liquidation of all open short positions. Called by SeasonManager
## before PortfolioManager.force_liquidate() (Step ①-A). GDD §규칙 9.
func liquidate_all_for_season_end() -> void:
	var stock_ids: Array[String] = []
	for sid: String in _positions:
		stock_ids.append(sid)

	for stock_id: String in stock_ids:
		var pos: Dictionary = _positions[stock_id]
		var cover_price: int = PriceEngine.get_current_price(stock_id)
		var cover_cost: int = cover_price * pos["quantity"]
		var pnl: int = (pos["open_price"] - cover_price) * pos["quantity"]
		var remaining: int = maxi(0, pos["margin_deposited"] + pnl)

		if not CurrencySystem.sim_deduct(cover_cost):
			push_error("ShortSellingSystem.liquidate_all_for_season_end: sim_deduct failed (stock=%s, cost=%d)" \
				% [stock_id, cover_cost])
		CurrencySystem.sim_add(remaining)
		on_short_position_closed.emit(stock_id, pnl)

	_positions.clear()


## Resets all state. Called by GameMain (new game) and tests (before_each).
func reset() -> void:
	_positions.clear()

# ── Serialization ──

## Returns serializable state for SaveSystem.
## Excludes derived fields (unrealized_pnl, margin_ratio) — recomputed on first tick.
func get_save_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for stock_id: String in _positions:
		var pos: Dictionary = _positions[stock_id]
		result.append({
			"stock_id":         pos["stock_id"],
			"quantity":         pos["quantity"],
			"open_price":       pos["open_price"],
			"initial_value":    pos["initial_value"],
			"margin_deposited": pos["margin_deposited"],
			"open_tick":        pos["open_tick"],
			"open_day":         pos["open_day"],
		})
	return result


## Restores positions from save data.
## margin_ratio and unrealized_pnl are 0 until first update_and_check_margin() call.
func load_save_data(data: Array) -> void:
	_positions.clear()
	for item: Dictionary in data:
		var stock_id: String = item.get("stock_id", "")
		if stock_id.is_empty():
			continue
		_positions[stock_id] = {
			"stock_id":           stock_id,
			"quantity":           item.get("quantity", 0),
			"open_price":         item.get("open_price", 0),
			"initial_value":      item.get("initial_value", 0),
			"margin_deposited":   item.get("margin_deposited", 0),
			"open_tick":          item.get("open_tick", 0),
			"open_day":           item.get("open_day", 0),
			"unrealized_pnl":     0,
			"unrealized_pnl_pct": 0.0,
			"margin_ratio":       _margin_rate,  ## recomputed on first tick
		}

# ── Internal ──

func _trigger_forced_liquidation(stock_id: String) -> void:
	if not _positions.has(stock_id):
		return
	var pos: Dictionary = _positions[stock_id]
	var current_price: int = PriceEngine.get_current_price(stock_id)
	var cover_cost: int = current_price * pos["quantity"]
	var pnl: int = (pos["open_price"] - current_price) * pos["quantity"]
	var remaining: int = maxi(0, pos["margin_deposited"] + pnl)

	if not CurrencySystem.sim_deduct(cover_cost):
		push_error("ShortSellingSystem._trigger_forced_liquidation: sim_deduct failed (stock=%s, cost=%d)" \
			% [stock_id, cover_cost])
	CurrencySystem.sim_add(remaining)
	_positions.erase(stock_id)

	on_forced_liquidation.emit(stock_id, current_price, pnl)
	on_short_position_closed.emit(stock_id, pnl)
