## Autoload — Accepts, validates, and executes buy/sell orders.
## Core layer. Depends on: PriceEngine, CurrencySystem, PortfolioManager, GameClock, StockDatabase, MarketConfig.
## See: design/gdd/order-engine.md, design/gdd/trading-fees.md
extends Node

# ── Signals ──

signal on_order_filled(order: Dictionary)
signal on_order_rejected(order: Dictionary)
signal on_order_cancelled(order: Dictionary)
signal on_order_expired(order: Dictionary)

# ── Constants ──

const MAX_PENDING_LIMIT_ORDERS: int = 10
const PRE_MARKET_BUFFER_PCT: float = 0.15
## 시즌당 주문 히스토리 최대 보관 건수. 초과 시 오래된 항목 제거. Tuning Knob.
const ORDER_HISTORY_MAX_SIZE: int = 500

# ── State ──

var _next_order_id: int = 1
var _market_order_queue: Array[Dictionary] = []       ## Orders waiting for next tick
var _pending_limit_orders: Array[Dictionary] = []     ## Active limit orders
var _pre_market_queue: Array[Dictionary] = []         ## PRE_MARKET orders
var _order_history: Array[Dictionary] = []
var _sell_locks: Dictionary = {}  ## stock_id -> locked_quantity (int)

# ── Lifecycle ──

func _ready() -> void:
	# on_tick is NOT connected here — GameClock calls _on_tick directly in
	# _process_tick() to enforce the GDD-mandated News → Price → Order order.
	GameClock.on_market_state_changed.connect(_on_market_state_changed)
	GameClock.on_season_start.connect(_on_season_start)


func _on_season_start() -> void:
	_market_order_queue.clear()
	_pending_limit_orders.clear()
	_pre_market_queue.clear()
	_order_history.clear()
	_sell_locks.clear()
	_next_order_id = 1


## Resets all order engine state. Called by GameMain (new game) and tests (before_each).
func reset() -> void:
	_next_order_id = 1
	_market_order_queue.clear()
	_pending_limit_orders.clear()
	_pre_market_queue.clear()
	_order_history.clear()
	_sell_locks.clear()

# ── Public API ──

## Submit a market order. Returns the order dict (check status for result).
func submit_market_order(side: String, stock_id: String, quantity: int) -> Dictionary:
	var order: Dictionary = _create_order("MARKET", side, stock_id, quantity, 0)
	var reject: String = _validate_order(order)
	if reject != "":
		return _reject_order(order, reject)
	match GameClock.get_market_state():
		GameClock.MarketState.PRE_MARKET:
			return _handle_pre_market_market_order(order)
		GameClock.MarketState.MARKET_OPEN, GameClock.MarketState.PAUSED:
			return _handle_open_market_order(order)
		_:
			return _reject_order(order, "장이 열려 있지 않습니다")


func _handle_pre_market_market_order(order: Dictionary) -> Dictionary:
	if order["side"] == "BUY":
		var current_price: int = PriceEngine.get_current_price(order["stock_id"])
		var gross_reserved: int = int(ceil(float(current_price) * (1.0 + PRE_MARKET_BUFFER_PCT))) * order["quantity"]
		var reserved: int = MarketConfig.get_buy_cost(gross_reserved)
		if not CurrencySystem.sim_deduct(reserved):
			return _reject_order(order, "잔액 부족")
		order["reserved_cash"] = reserved
	elif order["side"] == "SELL":
		_lock_sell_quantity(order["stock_id"], order["quantity"])
		order["locked_quantity"] = order["quantity"]
	order["status"] = "PENDING"
	_pre_market_queue.append(order)
	return order


func _handle_open_market_order(order: Dictionary) -> Dictionary:
	if order["side"] == "BUY":
		var current_price: int = PriceEngine.get_current_price(order["stock_id"])
		var cost: int = MarketConfig.get_buy_cost(current_price * order["quantity"])
		if not CurrencySystem.sim_deduct(cost):
			return _reject_order(order, "잔액 부족")
		order["reserved_cash"] = cost
	elif order["side"] == "SELL":
		_lock_sell_quantity(order["stock_id"], order["quantity"])
		order["locked_quantity"] = order["quantity"]
	if GameClock.get_market_state() == GameClock.MarketState.PAUSED:
		order["status"] = "PENDING"
		_market_order_queue.append(order)
	else:
		_fill_market_order(order)
	return order


func _reject_order(order: Dictionary, reason: String) -> Dictionary:
	order["status"] = "REJECTED"
	order["reject_reason"] = reason
	_history_append(order)
	on_order_rejected.emit(order)
	return order


## Submit a limit order. Returns the order dict.
func submit_limit_order(
	side: String, stock_id: String, quantity: int, limit_price: int
) -> Dictionary:
	var order: Dictionary = _create_order("LIMIT", side, stock_id, quantity, limit_price)

	var reject: String = _validate_order(order)
	if reject != "":
		order["status"] = "REJECTED"
		order["reject_reason"] = reject
		_history_append(order)
		on_order_rejected.emit(order)
		return order

	# Reserve resources (includes commission via MarketConfig.get_buy_cost)
	if side == "BUY":
		var reserved: int = MarketConfig.get_buy_cost(limit_price * quantity)
		if not CurrencySystem.sim_deduct(reserved):
			order["status"] = "REJECTED"
			order["reject_reason"] = "잔액 부족"
			_history_append(order)
			on_order_rejected.emit(order)
			return order
		order["reserved_cash"] = reserved
	elif side == "SELL":
		_lock_sell_quantity(stock_id, quantity)
		order["locked_quantity"] = quantity

	order["status"] = "PENDING"
	_pending_limit_orders.append(order)
	return order


## Cancel a pending order by order_id.
func cancel_order(order_id: int) -> bool:
	# Check limit orders
	for i: int in range(_pending_limit_orders.size() - 1, -1, -1):
		var order: Dictionary = _pending_limit_orders[i]
		if order["order_id"] == order_id:
			_refund_order(order)
			order["status"] = "CANCELLED"
			_pending_limit_orders.remove_at(i)
			_history_append(order)
			on_order_cancelled.emit(order)
			return true

	# Check pre-market queue
	for i: int in range(_pre_market_queue.size() - 1, -1, -1):
		var order: Dictionary = _pre_market_queue[i]
		if order["order_id"] == order_id:
			_refund_order(order)
			order["status"] = "CANCELLED"
			_pre_market_queue.remove_at(i)
			_history_append(order)
			on_order_cancelled.emit(order)
			return true

	# Check market queue (paused orders)
	for i: int in range(_market_order_queue.size() - 1, -1, -1):
		var order: Dictionary = _market_order_queue[i]
		if order["order_id"] == order_id:
			_refund_order(order)
			order["status"] = "CANCELLED"
			_market_order_queue.remove_at(i)
			_history_append(order)
			on_order_cancelled.emit(order)
			return true

	return false


## Returns all pending orders.
func get_pending_orders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append_array(_pending_limit_orders)
	result.append_array(_pre_market_queue)
	result.append_array(_market_order_queue)
	return result


## Returns total reserved cash across all pending buy orders.
func get_total_reserved_cash() -> int:
	var total: int = 0
	for order: Dictionary in _pending_limit_orders:
		total += order.get("reserved_cash", 0)
	for order: Dictionary in _pre_market_queue:
		total += order.get("reserved_cash", 0)
	for order: Dictionary in _market_order_queue:
		total += order.get("reserved_cash", 0)
	return total


## Returns locked sell quantity for a stock.
func get_locked_quantity(stock_id: String) -> int:
	return _sell_locks.get(stock_id, 0)


## Cancel all PENDING orders and refund reserved cash. Called by SeasonManager at season end.
## See: design/gdd/season-manager.md §3-1 step ②
func cancel_all_pending_orders() -> void:
	var pending: Array[Dictionary] = get_pending_orders()
	for order: Dictionary in pending:
		cancel_order(order["order_id"])


## Returns count of FILLED orders this season. Called by SeasonManager for rank eligibility.
## _order_history is reset at season start in _on_season_start(), so this count is season-scoped.
## See: design/gdd/season-manager.md §4-5
func get_season_trade_count() -> int:
	var count: int = 0
	for order: Dictionary in _order_history:
		if order.get("status", "") == "FILLED":
			count += 1
	return count


## Append order to history, enforcing ORDER_HISTORY_MAX_SIZE cap.
func _history_append(order: Dictionary) -> void:
	_order_history.append(order)
	if _order_history.size() > ORDER_HISTORY_MAX_SIZE:
		_order_history = _order_history.slice(_order_history.size() - ORDER_HISTORY_MAX_SIZE)


## Returns order history.
func get_order_history(limit: int = 50) -> Array[Dictionary]:
	if limit >= _order_history.size():
		return _order_history.duplicate()
	return _order_history.slice(_order_history.size() - limit)

# ── Tick Processing (GDD Rule 4, tick order: 3rd after PriceEngine) ──

## Called by GameClock._process_tick() for deterministic News→Price→Order ordering.
func process_tick(tick_number: int, _day: int, _week: int) -> void:
	# Process queued market orders (from PAUSED state)
	var market_queue: Array[Dictionary] = _market_order_queue.duplicate()
	_market_order_queue.clear()
	for order: Dictionary in market_queue:
		_fill_market_order(order)

	# Check limit orders (skip halted stocks)
	# Collect fills first, then update _pending_limit_orders BEFORE emitting
	# signals — otherwise UI reads stale pending list via get_pending_orders().
	var still_pending: Array[Dictionary] = []
	var to_fill: Array[Array] = []  # [[order, price], ...]
	for order: Dictionary in _pending_limit_orders:
		# Skip fill check if stock is halted by VI or CB Stage 2 (early close).
		# Stage 1 is a temporary halt — once _cb_halt_remaining reaches 0 the
		# stage stays at 1 for the rest of the day, so checking > 0 would
		# permanently block all limit fills after Stage 1 lifts. Only Stage 2
		# (permanent early-close) should suppress fills for the remainder of
		# the session. (R-01 fix)
		if PriceEngine.get_cb_stage() >= 2 or PriceEngine.is_vi_halted(order["stock_id"]):
			still_pending.append(order)
			continue

		var current_price: int = PriceEngine.get_current_price(order["stock_id"])
		var should_fill: bool = false

		if order["side"] == "BUY" and current_price <= order["limit_price"]:
			should_fill = true
		elif order["side"] == "SELL" and current_price >= order["limit_price"]:
			should_fill = true

		if should_fill:
			to_fill.append([order, current_price])
		else:
			still_pending.append(order)

	# Update pending list BEFORE filling — fill emits on_order_filled, and
	# signal handlers (UI) call get_pending_orders() which reads this array.
	_pending_limit_orders = still_pending

	for entry: Array in to_fill:
		_fill_limit_order(entry[0] as Dictionary, entry[1] as int)

	# 3-d. Stop-loss / take-profit auto-sell check (GDD: stop-loss-take-profit.md §규칙 3)
	# Runs after limit fills (3-c) so residual available_quantity is accurate.
	StopTakeSystem.check_and_trigger(GameClock.get_market_state())

	# Update portfolio valuation after order processing
	var reserved: int = get_total_reserved_cash()
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), reserved)


func _on_market_state_changed(
	new_state: GameClock.MarketState, _prev: GameClock.MarketState
) -> void:
	match new_state:
		GameClock.MarketState.MARKET_OPEN:
			_process_pre_market_queue()
		GameClock.MarketState.MARKET_CLOSED:
			_expire_pending_orders()

# ── PRE_MARKET Queue Processing (GDD Rule 4-3a) ──

func _process_pre_market_queue() -> void:
	var queue: Array[Dictionary] = _pre_market_queue.duplicate()
	_pre_market_queue.clear()

	for order: Dictionary in queue:
		var filled_price: int = PriceEngine.get_current_price(order["stock_id"])

		if order["side"] == "BUY":
			var actual_cost: int = filled_price * order["quantity"]
			var reserved: int = order["reserved_cash"]

			if actual_cost > reserved:
				# Price exceeded buffer — reject
				CurrencySystem.sim_add(reserved)
				order["status"] = "REJECTED"
				order["reject_reason"] = "장 시작 가격이 예약금을 초과했습니다"
				_history_append(order)
				on_order_rejected.emit(order)
			else:
				# Fill and refund difference (reserved includes fee via get_buy_cost)
				var actual_cost: int = MarketConfig.get_buy_cost(filled_price * order["quantity"])
				var refund: int = reserved - actual_cost
				if refund > 0:
					CurrencySystem.sim_add(refund)
				elif refund < 0:
					CurrencySystem.sim_deduct(-refund)
				PortfolioManager.add_holding(order["stock_id"], order["quantity"], filled_price)
				var buy_breakdown: Dictionary = MarketConfig.get_fee_breakdown(
					"BUY", filled_price * order["quantity"], 0, 0
				)
				order["status"] = "FILLED"
				order["filled_price"] = filled_price
				order["filled_tick"] = GameClock.get_current_tick()
				order["fee_breakdown"] = buy_breakdown
				_history_append(order)
				on_order_filled.emit(order)

		elif order["side"] == "SELL":
			_unlock_sell_quantity(order["stock_id"], order["quantity"])
			var gross: int = filled_price * order["quantity"]
			var realized_pnl: int = PortfolioManager.remove_holding(
				order["stock_id"], order["quantity"], filled_price
			)
			var sell_breakdown: Dictionary = MarketConfig.get_fee_breakdown(
				"SELL", gross, 0, realized_pnl
			)
			CurrencySystem.sim_add(sell_breakdown["net"])
			order["status"] = "FILLED"
			order["filled_price"] = filled_price
			order["filled_tick"] = GameClock.get_current_tick()
			order["fee_breakdown"] = sell_breakdown
			_history_append(order)
			on_order_filled.emit(order)

# ── Fill Helpers ──

## Market order fill —장중(MARKET_OPEN/PAUSED-resume) 체결.
## Sweeps ask/bid levels via consume_order_book() (GDD order-book.md §3-4).
## remaining_qty > 0: re-queue for next tick (GDD §3-4 "시장가 미체결" 규칙).
func _fill_market_order(order: Dictionary) -> void:
	var side_lower: String = order["side"].to_lower()
	var result: Dictionary = PriceEngine.consume_order_book(
		order["stock_id"], side_lower, order["quantity"], -1
	)

	if result["filled_qty"] == 0:
		# No liquidity this tick — re-queue for next tick (market order stays live)
		_market_order_queue.append(order)
		return

	var filled_price: int = result["avg_price"]

	if order["side"] == "BUY":
		var gross_filled: int = filled_price * result["filled_qty"]
		var actual_cost: int = MarketConfig.get_buy_cost(gross_filled)
		var reserved: int = order.get("reserved_cash", 0)
		# reserved covers the original quantity; refund the unconsumed portion proportionally
		var proportional_reserved: int = int(
			float(reserved) * float(result["filled_qty"]) / float(order["quantity"])
		) if order["quantity"] > 0 else reserved
		var refund: int = proportional_reserved - actual_cost
		if refund > 0:
			CurrencySystem.sim_add(refund)
		elif refund < 0:
			if not CurrencySystem.sim_deduct(-refund):
				CurrencySystem.sim_add(proportional_reserved)
				order["status"] = "REJECTED"
				order["reject_reason"] = "잔액 부족 (가격 변동)"
				_history_append(order)
				on_order_rejected.emit(order)
				return
		PortfolioManager.add_holding(order["stock_id"], result["filled_qty"], filled_price)
		order["fee_breakdown"] = MarketConfig.get_fee_breakdown("BUY", gross_filled, 0, 0)

	elif order["side"] == "SELL":
		_unlock_sell_quantity(order["stock_id"], result["filled_qty"])
		var gross: int = filled_price * result["filled_qty"]
		var realized_pnl: int = PortfolioManager.remove_holding(
			order["stock_id"], result["filled_qty"], filled_price
		)
		var sell_breakdown: Dictionary = MarketConfig.get_fee_breakdown(
			"SELL", gross, 0, realized_pnl
		)
		CurrencySystem.sim_add(sell_breakdown["net"])
		order["fee_breakdown"] = sell_breakdown

	order["status"] = "FILLED"
	order["filled_price"] = filled_price
	order["filled_qty"] = result["filled_qty"]
	order["filled_tick"] = GameClock.get_current_tick()
	_history_append(order)
	on_order_filled.emit(order)

	# Partial fill: re-queue remaining quantity for next tick (GDD order-book.md §3-4)
	if result["remaining_qty"] > 0:
		var remainder: Dictionary = order.duplicate()
		remainder["order_id"] = _next_order_id
		_next_order_id += 1
		remainder["quantity"] = result["remaining_qty"]
		remainder["reserved_cash"] = 0  # already deducted in original order
		remainder["status"] = "PENDING"
		_market_order_queue.append(remainder)


## Limit order fill — 장중 체결. Sweeps order book for actual avg price (GDD order-book.md §3-4).
## remaining_qty > 0: order goes back to _pending_limit_orders (GDD §3-4 "지정가 미체결" 규칙).
func _fill_limit_order(order: Dictionary, _current_price: int) -> void:
	var side_lower: String = order["side"].to_lower()
	var limit_price: int = order.get("limit_price", -1)
	var result: Dictionary = PriceEngine.consume_order_book(
		order["stock_id"], side_lower, order["quantity"], limit_price
	)

	if result["filled_qty"] == 0:
		# Price condition not met at book level — keep in pending
		_pending_limit_orders.append(order)
		return

	var filled_price: int = result["avg_price"]

	if order["side"] == "BUY":
		var gross_filled: int = filled_price * result["filled_qty"]
		var actual_cost: int = MarketConfig.get_buy_cost(gross_filled)
		var reserved: int = order.get("reserved_cash", 0)
		var proportional_reserved: int = int(
			float(reserved) * float(result["filled_qty"]) / float(order["quantity"])
		) if order["quantity"] > 0 else reserved
		var refund: int = proportional_reserved - actual_cost
		if refund > 0:
			CurrencySystem.sim_add(refund)
		elif refund < 0:
			CurrencySystem.sim_deduct(-refund)
		PortfolioManager.add_holding(order["stock_id"], result["filled_qty"], filled_price)
		order["fee_breakdown"] = MarketConfig.get_fee_breakdown("BUY", gross_filled, 0, 0)

	elif order["side"] == "SELL":
		_unlock_sell_quantity(order["stock_id"], result["filled_qty"])
		var gross: int = filled_price * result["filled_qty"]
		var realized_pnl: int = PortfolioManager.remove_holding(
			order["stock_id"], result["filled_qty"], filled_price
		)
		var sell_breakdown: Dictionary = MarketConfig.get_fee_breakdown(
			"SELL", gross, 0, realized_pnl
		)
		CurrencySystem.sim_add(sell_breakdown["net"])
		order["fee_breakdown"] = sell_breakdown

	order["status"] = "FILLED"
	order["filled_price"] = filled_price
	order["filled_qty"] = result["filled_qty"]
	order["filled_tick"] = GameClock.get_current_tick()
	_history_append(order)
	on_order_filled.emit(order)

	# Partial fill: remaining stays in pending with reduced quantity (GDD §3-4)
	if result["remaining_qty"] > 0:
		var remainder: Dictionary = order.duplicate()
		remainder["order_id"] = _next_order_id
		_next_order_id += 1
		remainder["quantity"] = result["remaining_qty"]
		remainder["reserved_cash"] = 0  # already deducted
		remainder["status"] = "PENDING"
		_pending_limit_orders.append(remainder)

# ── Expiry ──

func _expire_pending_orders() -> void:
	# Clear ALL queues BEFORE emitting signals — UI reads get_pending_orders()
	# inside signal handlers, so the lists must already be empty.
	# Covers: limit orders, PAUSED market orders, and PRE_MARKET orders
	# (PRE_MARKET/PAUSED queues may have residual orders on CB Stage 2 early close)
	var to_expire: Array[Dictionary] = []
	to_expire.append_array(_pending_limit_orders)
	to_expire.append_array(_market_order_queue)
	to_expire.append_array(_pre_market_queue)
	_pending_limit_orders.clear()
	_market_order_queue.clear()
	_pre_market_queue.clear()
	for order: Dictionary in to_expire:
		_refund_order(order)
		order["status"] = "EXPIRED"
		_history_append(order)
		on_order_expired.emit(order)

# ── Validation (GDD Rule 3, 8 steps) ──

func _validate_order(order: Dictionary) -> String:
	var err: String = _validate_order_state_and_stock(order)
	if err: return err
	err = _validate_order_quantity_and_skills(order)
	if err: return err
	err = _validate_order_buy_constraints(order)
	if err: return err
	err = _validate_order_sell_constraints(order)
	if err: return err
	return _validate_order_limit_price(order)


func _validate_order_state_and_stock(order: Dictionary) -> String:
	# 1. Market state (MARKET and LIMIT share the same valid states)
	var ms: GameClock.MarketState = GameClock.get_market_state()
	var valid_states: bool = (
		ms == GameClock.MarketState.MARKET_OPEN or
		ms == GameClock.MarketState.PAUSED or
		ms == GameClock.MarketState.PRE_MARKET
	)
	if not valid_states:
		return "장이 열려 있지 않습니다"
	# 2. Stock exists + VI/CB halt check (GDD Rules 2-4, 2-5)
	if StockDatabase.get_stock(order["stock_id"]) == null:
		return "존재하지 않는 종목입니다"
	# Stage 1 is a temporary halt; _cb_stage stays at 1 after it lifts.
	# Only reject new orders during Stage 2 (permanent early close). (R-01 fix)
	if PriceEngine.get_cb_stage() >= 2:
		return "CB 2단계 발동 중 — 조기 장 마감"
	if PriceEngine.is_vi_halted(order["stock_id"]):
		return "변동성완화장치(VI) 발동 중입니다"
	return ""


func _validate_order_quantity_and_skills(order: Dictionary) -> String:
	# 3. Quantity
	if order["quantity"] <= 0:
		return "수량은 1 이상이어야 합니다"
	# 4. Skill unlock — TR1 required for limit orders
	if order["order_type"] == "LIMIT" and not SkillTree.is_skill_unlocked("TR1"):
		return "지정가 주문 스킬을 해금하세요 (TR1: 지정가 주문)"
	# 4.5. Pending limit order count
	if order["order_type"] == "LIMIT" and _pending_limit_orders.size() >= MAX_PENDING_LIMIT_ORDERS:
		return "미체결 주문 한도 초과"
	return ""


func _validate_order_buy_constraints(order: Dictionary) -> String:
	if order["side"] != "BUY":
		return ""
	# 5. Portfolio slot — new stock requires an open slot
	var holding: Variant = PortfolioManager.get_holding(order["stock_id"])
	if holding == null:
		var effective_count: int = _get_effective_holding_count(order["stock_id"])
		if effective_count >= SkillTree.get_max_holdings():
			return "보유 종목 한도 초과"
	# 6. Balance check — actual deduction happens in submit.
	# Note: balance check and deduction are not atomic. Safe because GDScript is
	# single-threaded and no signal is emitted between _validate_order and the
	# CurrencySystem.sim_deduct call in submit_market_order / submit_limit_order.
	# (R-03: TOCTOU is benign under GDScript's cooperative execution model)
	var ms: GameClock.MarketState = GameClock.get_market_state()
	var required: int
	if order["order_type"] == "LIMIT":
		required = order["limit_price"] * order["quantity"]
	elif ms == GameClock.MarketState.PRE_MARKET:
		var price: int = PriceEngine.get_current_price(order["stock_id"])
		required = int(ceil(float(price) * (1.0 + PRE_MARKET_BUFFER_PCT))) * order["quantity"]
	else:
		var price: int = PriceEngine.get_current_price(order["stock_id"])
		required = price * order["quantity"]
	if CurrencySystem.get_sim_cash() < required:
		return "잔액 부족"
	return ""


func _validate_order_sell_constraints(order: Dictionary) -> String:
	if order["side"] != "SELL":
		return ""
	# 7. Holdings check
	var holding: Variant = PortfolioManager.get_holding(order["stock_id"])
	if holding == null:
		return "보유 수량 부족"
	var available: int = holding["quantity"] - get_locked_quantity(order["stock_id"])
	if order["quantity"] > available:
		return "보유 수량 부족"
	return ""


func _validate_order_limit_price(order: Dictionary) -> String:
	if order["order_type"] != "LIMIT":
		return ""
	# 8. Limit price positivity
	if order["limit_price"] <= 0:
		return "지정가는 0보다 커야 합니다"
	# 8-1. Daily limit (상/하한가) validation
	var limits: Dictionary = PriceEngine.get_daily_limits(order["stock_id"])
	if limits.size() > 0:
		if order["limit_price"] > limits["upper"]:
			return "상한가(%d원) 초과" % limits["upper"]
		if order["limit_price"] < limits["lower"]:
			return "하한가(%d원) 미만" % limits["lower"]
	# 9. Tick size validation (GDD Rule 5-3)
	var tick_size: int = PriceEngine.get_tick_size(order["limit_price"])
	if order["limit_price"] % tick_size != 0:
		return "지정가가 호가 단위(%d원)에 맞지 않습니다" % tick_size
	return ""

# ── Helpers ──

func _create_order(
	order_type: String, side: String, stock_id: String,
	quantity: int, limit_price: int
) -> Dictionary:
	var order: Dictionary = {
		"order_id": _next_order_id,
		"order_type": order_type,
		"side": side,
		"stock_id": stock_id,
		"quantity": quantity,
		"limit_price": limit_price if order_type == "LIMIT" else 0,
		"status": "PENDING",
		"reject_reason": "",
		"submitted_tick": GameClock.get_current_tick(),
		"submitted_day": GameClock.get_current_day(),
		"filled_price": 0,
		"filled_tick": 0,
		"reserved_cash": 0,
		"locked_quantity": 0,
	}
	_next_order_id += 1
	return order


func _refund_order(order: Dictionary) -> void:
	if order["side"] == "BUY" and order["reserved_cash"] > 0:
		CurrencySystem.sim_add(order["reserved_cash"])
		order["reserved_cash"] = 0
	elif order["side"] == "SELL" and order["locked_quantity"] > 0:
		_unlock_sell_quantity(order["stock_id"], order["locked_quantity"])
		order["locked_quantity"] = 0


func _lock_sell_quantity(stock_id: String, quantity: int) -> void:
	_sell_locks[stock_id] = _sell_locks.get(stock_id, 0) + quantity


func _unlock_sell_quantity(stock_id: String, quantity: int) -> void:
	var current: int = _sell_locks.get(stock_id, 0)
	var new_val: int = maxi(0, current - quantity)
	if new_val == 0:
		_sell_locks.erase(stock_id)
	else:
		_sell_locks[stock_id] = new_val


func _get_effective_holding_count(new_stock_id: String) -> int:
	var count: int = PortfolioManager.get_holding_count()

	# Count queued BUY orders for new stocks
	var known_stocks: Dictionary = {}
	for h: Dictionary in PortfolioManager.get_all_holdings():
		known_stocks[h["stock_id"]] = true

	for order: Dictionary in _pre_market_queue:
		if order["side"] == "BUY" and not known_stocks.has(order["stock_id"]):
			known_stocks[order["stock_id"]] = true
			count += 1

	for order: Dictionary in _market_order_queue:
		if order["side"] == "BUY" and not known_stocks.has(order["stock_id"]):
			known_stocks[order["stock_id"]] = true
			count += 1

	# Count pending limit BUY orders for new stocks (R-04 fix: was missing this
	# queue, allowing slot limit bypass via limit orders on unseen stocks).
	for order: Dictionary in _pending_limit_orders:
		if order["side"] == "BUY" and not known_stocks.has(order["stock_id"]):
			known_stocks[order["stock_id"]] = true
			count += 1

	# Count the new stock if not already known
	if not known_stocks.has(new_stock_id):
		count += 1

	return count
