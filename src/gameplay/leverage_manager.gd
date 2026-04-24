## Autoload — Manages leveraged long positions (TR4).
## Gameplay layer. Depends on: PriceEngine, CurrencySystem, GameClock.
## Called by: OrderEngine (open_position, close_position),
##             GameClock (_process_tick, on_market_close), SeasonManager.
## See: design/gdd/leverage-trading.md
extends Node

# ── Signals ──

## Emitted when equity_ratio drops below margin_call_threshold (warning, not yet liquidated).
signal on_margin_call(stock_id: String, multiplier: int, equity_ratio: float)

## Emitted when a position is forcibly liquidated (equity ≤ 0 or ratio < forced_liq_threshold).
signal on_leverage_forced_liquidation(stock_id: String, multiplier: int, net_proceeds: int)

## Emitted when any leverage position closes (manual, forced, or season-end).
signal on_leverage_position_closed(stock_id: String, multiplier: int, net_proceeds: int)

## Emitted when forced liquidation produces a loss exceeding available sim_cash.
## Connect from GameMain / MainScreen to trigger the loan-shark bad ending screen.
## GDD §3-3, §5 "채무 상환 불능", AC-17.
signal on_loan_shark_ending_triggered(stock_id: String, net_proceeds: int)

# ── Config ──

const CONFIG_PATH: String = "res://assets/data/leverage_config.json"

## Keyed by multiplier as String ("2", "3", "5"). GDD §7 Tuning Knobs.
var _daily_rates: Dictionary = {"2": 0.0004, "3": 0.0006, "5": 0.001}
var _margin_call_thresholds: Dictionary = {"2": 0.30, "3": 0.20, "5": 0.15}
var _forced_liq_thresholds: Dictionary = {"2": 0.10, "3": 0.07, "5": 0.05}
var _available_multipliers: Array[int] = [2, 3, 5]

# ── State ──

## Array of LeveragePosition dicts. Multiple positions per stock allowed (different multipliers).
## Position dict fields: stock_id, quantity, entry_price, multiplier, borrowed,
##                        accrued_interest, open_day
var _positions: Array[Dictionary] = []

# ── Lifecycle ──

func _ready() -> void:
	_load_config()
	GameClock.on_tick.connect(func(_t: int, _d: int, _w: int) -> void: check_margin_calls())
	GameClock.on_market_close.connect(_on_market_close)


func _load_config() -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		push_warning("LeverageManager: config not found at %s — using defaults" % CONFIG_PATH)
		return
	var text: String = f.get_as_text()
	f.close()
	var result: Variant = JSON.parse_string(text)
	if result == null or not result is Dictionary:
		push_warning("LeverageManager: JSON parse failed for %s — using defaults" % CONFIG_PATH)
		return
	if result.has("daily_rates"):
		_daily_rates = result["daily_rates"]
	if result.has("margin_call_thresholds"):
		_margin_call_thresholds = result["margin_call_thresholds"]
	if result.has("forced_liq_thresholds"):
		_forced_liq_thresholds = result["forced_liq_thresholds"]
	if result.has("available_multipliers"):
		_available_multipliers.clear()
		for v: Variant in result["available_multipliers"]:
			_available_multipliers.append(int(v))


func _on_market_close() -> void:
	process_daily_interest(GameClock.get_current_day())

# ── Public API: Query ──

## True if any leverage position exists for the given stock_id.
func has_leverage_position(stock_id: String) -> bool:
	for pos: Dictionary in _positions:
		if pos["stock_id"] == stock_id:
			return true
	return false


## Returns all leverage positions (shallow copies) for UI display.
func get_all_positions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pos: Dictionary in _positions:
		result.append(pos.duplicate())
	return result


## True if multiplier is in the configured available set.
func is_valid_multiplier(multiplier: int) -> bool:
	return _available_multipliers.has(multiplier)


## Returns the margin-call equity ratio threshold for the given multiplier.
## UI should use this instead of accessing _margin_call_thresholds directly.
## Returns 0.20 as a safe default when multiplier is not in config.
func get_margin_call_threshold(multiplier: int) -> float:
	return _margin_call_thresholds.get(str(multiplier), 0.20)


## Net leverage contribution to total assets.
## = Σ(position_market_value − borrowed − accrued_interest) = Σ(equity).
## Positive when profitable; may be negative under heavy losses.
## GDD §6 PortfolioManager dependency.
func get_leverage_net_value() -> int:
	var total: int = 0
	for pos: Dictionary in _positions:
		var market_val: int = PriceEngine.get_current_price(pos["stock_id"]) * pos["quantity"]
		total += market_val - pos["borrowed"] - pos["accrued_interest"]
	return total

# ── Public API: Position Management (called by OrderEngine) ──

## Open or merge a leverage position from a validated LEVERAGE_BUY order.
## Deducts equity_used = ceil(order_value / multiplier) from sim_cash.
## Same-stock same-multiplier positions are merged (weighted avg entry_price). GDD §5.
## Returns filled_price (> 0) on success, 0 on failure.
## GDD §3-1, F1.
func open_position(stock_id: String, quantity: int, multiplier: int) -> int:
	var filled_price: int = PriceEngine.get_current_price(stock_id)
	if filled_price <= 0:
		push_error("LeverageManager.open_position: price=0 for %s" % stock_id)
		return 0

	var order_value: int = filled_price * quantity
	var equity_used: int = int(ceil(float(order_value) / float(multiplier)))
	var borrowed: int = order_value - equity_used

	if not CurrencySystem.sim_deduct(equity_used):
		push_error("LeverageManager.open_position: equity deduction failed for %s" % stock_id)
		return 0

	# Merge into existing position of same stock + same multiplier (GDD §5 Edge Case)
	for pos: Dictionary in _positions:
		if pos["stock_id"] == stock_id and pos["multiplier"] == multiplier:
			var old_qty: int = pos["quantity"]
			var new_qty: int = old_qty + quantity
			pos["entry_price"] = int((pos["entry_price"] * old_qty + filled_price * quantity) / new_qty)
			pos["quantity"] = new_qty
			pos["borrowed"] += borrowed
			return filled_price

	# New independent position (different multiplier = separate record)
	_positions.append({
		"stock_id":         stock_id,
		"quantity":         quantity,
		"entry_price":      filled_price,
		"multiplier":       multiplier,
		"borrowed":         borrowed,
		"accrued_interest": 0,
		"open_day":         GameClock.get_current_day(),
	})
	return filled_price


## Close (partially or fully) a leverage position by stock_id, FIFO order.
## Returns total net_proceeds for the closed quantity (may be negative on heavy loss).
## GDD §3-4, F4.
func close_position(stock_id: String, quantity: int) -> int:
	var matching: Array[Dictionary] = _collect_fifo_positions(stock_id)
	var filled_price: int = PriceEngine.get_current_price(stock_id)
	var total_net: int = _settle_partial_close(matching, filled_price, quantity)
	_prune_exhausted_positions()
	return total_net


## Collect and FIFO-sort all open positions for a given stock (oldest open_day first).
func _collect_fifo_positions(stock_id: String) -> Array[Dictionary]:
	var matching: Array[Dictionary] = []
	for pos: Dictionary in _positions:
		if pos["stock_id"] == stock_id:
			matching.append(pos)
	matching.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["open_day"] < b["open_day"]
	)
	return matching


## Settle up to `quantity` shares across FIFO positions; return total net proceeds.
func _settle_partial_close(
	matching: Array[Dictionary], filled_price: int, quantity: int
) -> int:
	var total_net: int = 0
	var remaining_qty: int = quantity

	for pos: Dictionary in matching:
		if remaining_qty <= 0:
			break
		var take: int = mini(remaining_qty, pos["quantity"])
		var frac: float = float(take) / float(pos["quantity"])

		var proceeds: int = filled_price * take
		var partial_borrowed: int = int(floor(pos["borrowed"] * frac))
		var partial_interest: int = int(floor(pos["accrued_interest"] * frac))
		var net: int = proceeds - partial_borrowed - partial_interest

		if net > 0:
			CurrencySystem.sim_add(net)
		else:
			var loss: int = -net
			CurrencySystem.sim_deduct(mini(loss, CurrencySystem.get_sim_cash()))

		total_net += net
		pos["borrowed"] -= partial_borrowed
		pos["accrued_interest"] -= partial_interest
		pos["quantity"] -= take
		remaining_qty -= take

		if pos["quantity"] <= 0:
			on_leverage_position_closed.emit(pos["stock_id"], pos["multiplier"], net)

	return total_net


## Remove fully-exhausted positions (quantity == 0) from _positions.
func _prune_exhausted_positions() -> void:
	var surviving: Array[Dictionary] = []
	for pos: Dictionary in _positions:
		if pos["quantity"] > 0:
			surviving.append(pos)
	_positions = surviving

# ── Public API: Tick/Day Processing ──

## Called every tick (after OrderEngine.process_tick) to check margin conditions.
## Emits on_margin_call for UI warnings; triggers forced liquidation when
## equity ≤ 0 or equity_ratio < forced_liq_threshold. GDD §3-3.
func check_margin_calls() -> void:
	if _positions.is_empty():
		return

	# Collect before mutating (avoids array-resize-during-iter)
	var to_liquidate: Array[Dictionary] = []
	for pos: Dictionary in _positions:
		var current_price: int = PriceEngine.get_current_price(pos["stock_id"])
		var market_val: int = current_price * pos["quantity"]
		if market_val <= 0:
			continue
		var equity: int = market_val - pos["borrowed"] - pos["accrued_interest"]
		var equity_ratio: float = float(equity) / float(market_val)
		var key: String = str(pos["multiplier"])
		var fl_threshold: float = _forced_liq_thresholds.get(key, 0.07)
		var mc_threshold: float = _margin_call_thresholds.get(key, 0.20)

		if equity <= 0 or equity_ratio < fl_threshold:
			to_liquidate.append(pos)
		elif equity_ratio < mc_threshold:
			on_margin_call.emit(pos["stock_id"], pos["multiplier"], equity_ratio)

	for pos: Dictionary in to_liquidate:
		_forced_liquidation(pos)


## Called on market close by GameClock.on_market_close signal.
## Deducts floor(borrowed × daily_rate) as accrued_interest per position.
## If interest > available sim_cash, charges all available and adds the shortfall
## to borrowed (debt spiral). GDD §3-2, F2, §5 Edge Case.
func process_daily_interest(_day: int) -> void:
	if _positions.is_empty():
		return

	for pos: Dictionary in _positions:
		var key: String = str(pos["multiplier"])
		var daily_rate: float = _daily_rates.get(key, 0.0004)
		var interest: int = int(floor(pos["borrowed"] * daily_rate))
		if interest <= 0:
			continue

		var available: int = CurrencySystem.get_sim_cash()
		if available >= interest:
			CurrencySystem.sim_deduct(interest)
		else:
			# Charge available cash; add shortfall to borrowed (GDD §5)
			if available > 0:
				CurrencySystem.sim_deduct(available)
			pos["borrowed"] += interest - available

		pos["accrued_interest"] += interest


## Season-end forced liquidation of all leverage positions at current prices.
## Called by SeasonManager Step ①-b, after short liquidation and before
## PortfolioManager.force_liquidate(). GDD §3-5.
func liquidate_all_positions() -> void:
	var snapshot: Array[Dictionary] = _positions.duplicate()
	for pos: Dictionary in snapshot:
		_forced_liquidation(pos)


## Add cash margin to reduce borrowed for a specific position.
## Returns true if deduction succeeded, false if insufficient cash or no matching position.
## GDD §3-3 증거금 추가.
func add_margin(stock_id: String, multiplier: int, amount: int) -> bool:
	if amount <= 0:
		return false
	for pos: Dictionary in _positions:
		if pos["stock_id"] == stock_id and pos["multiplier"] == multiplier:
			if not CurrencySystem.sim_deduct(amount):
				return false
			pos["borrowed"] = maxi(0, pos["borrowed"] - amount)
			return true
	return false


## Resets all state. Called by GameMain (new game) and tests (before_each).
func reset() -> void:
	_positions.clear()

# ── Internal ──

## Forced-liquidate one position at current market price.
## Returns equity to sim_cash if positive; deducts loss (clamped at 0) if negative.
## GDD §3-3 강제청산 처리, §5 Edge Cases (equity ≤ 0, sim_cash < 0 clamp).
func _forced_liquidation(pos: Dictionary) -> void:
	var current_price: int = PriceEngine.get_current_price(pos["stock_id"])
	var proceeds: int = current_price * pos["quantity"]
	var net_proceeds: int = proceeds - pos["borrowed"] - pos["accrued_interest"]

	if net_proceeds > 0:
		CurrencySystem.sim_add(net_proceeds)
	else:
		var loss: int = -net_proceeds
		var available: int = CurrencySystem.get_sim_cash()
		CurrencySystem.sim_deduct(mini(loss, available))  # 가용 현금 전액 차감
		if loss > available:
			# 초과 손실 — 채무 상환 불능 → 사채업자 엔딩 (GDD §3-3, AC-17)
			on_loan_shark_ending_triggered.emit(pos["stock_id"], net_proceeds)
			return  # 게임오버 처리는 GameMain/MainScreen이 담당

	# Remove by unique key (stock_id + multiplier) rather than dict value equality.
	# Dict value comparison would silently remove a second position with identical values.
	_positions = _positions.filter(func(p: Dictionary) -> bool:
		return p["stock_id"] != pos["stock_id"] or p["multiplier"] != pos["multiplier"]
	)
	on_leverage_forced_liquidation.emit(pos["stock_id"], pos["multiplier"], net_proceeds)
	on_leverage_position_closed.emit(pos["stock_id"], pos["multiplier"], net_proceeds)

# ── Serialization ──

## Returns serializable state for SaveSystem.
func get_save_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pos: Dictionary in _positions:
		result.append({
			"stock_id":         pos["stock_id"],
			"quantity":         pos["quantity"],
			"entry_price":      pos["entry_price"],
			"multiplier":       pos["multiplier"],
			"borrowed":         pos["borrowed"],
			"accrued_interest": pos["accrued_interest"],
			"open_day":         pos["open_day"],
		})
	return result


## Restores leverage positions from save data.
func load_save_data(data: Array) -> void:
	_positions.clear()
	for item: Variant in data:
		if not item is Dictionary:
			continue
		var d: Dictionary = item as Dictionary
		var stock_id: String = d.get("stock_id", "")
		if stock_id.is_empty():
			continue
		_positions.append({
			"stock_id":         stock_id,
			"quantity":         d.get("quantity", 0),
			"entry_price":      d.get("entry_price", 0),
			"multiplier":       d.get("multiplier", 2),
			"borrowed":         d.get("borrowed", 0),
			"accrued_interest": d.get("accrued_interest", 0),
			"open_day":         d.get("open_day", 0),
		})
