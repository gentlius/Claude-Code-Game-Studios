## Autoload — Tracks player holdings, calculates PnL, manages portfolio valuation.
## Core layer. Depends on: PriceEngine, CurrencySystem, StockDatabase.
## See: design/gdd/portfolio-manager.md
extends Node

# ── Signals ──

signal holding_added(stock_id: String, quantity: int, price: int)
signal holding_removed(stock_id: String, quantity: int, price: int, realized_pnl: int)
signal valuation_updated(total_assets: int, return_rate: float)

# ── State ──

var _holdings: Dictionary = {}         ## stock_id -> HoldingEntry dict
var _transactions: Array[Dictionary] = []
var _next_tx_id: int = 1
var _initial_seed: int = 0

## Cached valuation (updated per tick via update_valuation)
var _cached_total_assets: int = 0
var _cached_return_rate: float = 0.0
var _cached_sim_cash: int = 0
var _cached_reserved_cash: int = 0

# ── Lifecycle ──

func _ready() -> void:
	GameClock.on_season_start.connect(_on_season_start)


func _on_season_start() -> void:
	reset()
	_initial_seed = CurrencySystem.DEFAULT_SEASON_SEED

# ── Public API: Queries ──

## Returns a holding entry dict, or null if not held.
func get_holding(stock_id: String) -> Variant:
	return _holdings.get(stock_id)


## Returns all held stock entries as an array of dicts.
func get_all_holdings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for h: Dictionary in _holdings.values():
		result.append(h)
	return result


## Returns the number of distinct stocks held (quantity > 0).
func get_holding_count() -> int:
	return _holdings.size()


## Returns cached total assets (updated by update_valuation).
func get_total_assets() -> int:
	return _cached_total_assets


## Returns cached return rate % (updated by update_valuation).
func get_return_rate() -> float:
	return _cached_return_rate


## Returns recent transaction records.
func get_transaction_history(limit: int = 50) -> Array[Dictionary]:
	if limit >= _transactions.size():
		return _transactions.duplicate()
	return _transactions.slice(_transactions.size() - limit)


## Assembles a PortfolioSummary dict from cached values.
## max_holdings defaults to SkillTree.get_max_holdings() (R-12: removed
## duplicate DEFAULT_MAX_HOLDINGS constant — SkillTree.MAX_HOLDINGS_T0 is
## the single source of truth for the base slot count).
func get_portfolio_summary(max_holdings: int = -1) -> Dictionary:
	if max_holdings < 0:
		max_holdings = SkillTree.get_max_holdings()
	return {
		"sim_cash": _cached_sim_cash,
		"reserved_cash": _cached_reserved_cash,
		"total_assets": _cached_total_assets,
		"return_rate": _cached_return_rate,
		"holding_count": _holdings.size(),
		"max_holdings": max_holdings,
	}

# ── Public API: Holding Mutations (called by OrderEngine) ──

## Add shares after a buy order fills. Creates or updates the holding entry.
func add_holding(stock_id: String, quantity: int, price: int) -> void:
	if quantity <= 0 or price <= 0:
		return

	var buy_amount: int = price * quantity

	if _holdings.has(stock_id):
		var h: Dictionary = _holdings[stock_id]
		var new_total_invested: int = h["total_invested"] + buy_amount
		var new_quantity: int = h["quantity"] + quantity
		h["quantity"] = new_quantity
		h["total_invested"] = new_total_invested
		h["avg_buy_price"] = int(floor(float(new_total_invested) / float(new_quantity)))
		h["last_trade_tick"] = GameClock.get_current_tick()
	else:
		_holdings[stock_id] = {
			"stock_id": stock_id,
			"quantity": quantity,
			"avg_buy_price": price,
			"total_invested": buy_amount,
			"first_buy_tick": GameClock.get_current_tick(),
			"last_trade_tick": GameClock.get_current_tick(),
			"current_value": 0,
			"unrealized_pnl": 0,
			"unrealized_pnl_pct": 0.0,
		}

	_record_transaction(stock_id, "BUY", quantity, price, 0)
	holding_added.emit(stock_id, quantity, price)


## Remove shares after a sell order fills. Returns realized PnL.
func remove_holding(stock_id: String, quantity: int, price: int) -> int:
	if not _holdings.has(stock_id):
		return 0

	var h: Dictionary = _holdings[stock_id]
	if quantity > h["quantity"]:
		push_error("PortfolioManager: remove_holding quantity %d exceeds held %d for %s" % [quantity, h["quantity"], stock_id])
		quantity = h["quantity"]

	var avg: int = h["avg_buy_price"]
	var realized_pnl: int = (price - avg) * quantity

	var new_quantity: int = h["quantity"] - quantity
	if new_quantity <= 0:
		_holdings.erase(stock_id)
	else:
		h["quantity"] = new_quantity
		h["total_invested"] = avg * new_quantity
		h["last_trade_tick"] = GameClock.get_current_tick()

	_record_transaction(stock_id, "SELL", quantity, price, realized_pnl)
	holding_removed.emit(stock_id, quantity, price, realized_pnl)
	return realized_pnl


## Force liquidate all holdings at current prices (season end).
## Bypasses OrderEngine — calls CurrencySystem.sim_add directly.
## Must be called AFTER OrderEngine._expire_pending_orders() has cleared all
## locks. Called during season-end sequence only. (R-14: _sell_locks in
## OrderEngine will be stale if this runs before pending orders are expired.)
func force_liquidate() -> void:
	var stock_ids: Array[String] = []
	for sid: String in _holdings:
		stock_ids.append(sid)

	for stock_id: String in stock_ids:
		var h: Dictionary = _holdings[stock_id]
		var current_price: int = PriceEngine.get_current_price(stock_id)
		var sell_amount: int = current_price * h["quantity"]
		var realized_pnl: int = (current_price - h["avg_buy_price"]) * h["quantity"]

		CurrencySystem.sim_add(sell_amount)
		_record_transaction(stock_id, "SELL", h["quantity"], current_price, realized_pnl)
		holding_removed.emit(stock_id, h["quantity"], current_price, realized_pnl)

	_holdings.clear()

# ── Public API: Valuation (called per tick after PriceEngine updates) ──

## Update all holding valuations and cache totals.
## Called by the tick processing pipeline after PriceEngine.on_price_updated.
func update_valuation(sim_cash: int, reserved_cash: int) -> void:
	var total_stock_value: int = 0

	for stock_id: String in _holdings:
		var h: Dictionary = _holdings[stock_id]
		var current_price: int = PriceEngine.get_current_price(stock_id)
		h["current_value"] = current_price * h["quantity"]
		h["unrealized_pnl"] = h["current_value"] - h["total_invested"]
		if h["total_invested"] > 0:
			h["unrealized_pnl_pct"] = float(h["unrealized_pnl"]) / float(h["total_invested"]) * 100.0
		else:
			h["unrealized_pnl_pct"] = 0.0
		total_stock_value += h["current_value"]

	_cached_sim_cash = sim_cash
	_cached_reserved_cash = reserved_cash
	_cached_total_assets = sim_cash + reserved_cash + total_stock_value

	if _initial_seed > 0:
		_cached_return_rate = float(_cached_total_assets - _initial_seed) / float(_initial_seed) * 100.0
	else:
		_cached_return_rate = 0.0

	valuation_updated.emit(_cached_total_assets, _cached_return_rate)

# ── Season Lifecycle ──

## Reset portfolio for a new season.
func reset() -> void:
	_holdings.clear()
	_transactions.clear()
	_next_tx_id = 1
	_cached_total_assets = 0
	_cached_return_rate = 0.0
	_cached_sim_cash = 0
	_cached_reserved_cash = 0


## Resets all state including season baseline for unit tests. Call in before_each.
func reset_for_testing() -> void:
	reset()
	_initial_seed = 0

# ── Internal ──

func _record_transaction(
	stock_id: String, type: String, quantity: int, price: int, realized_pnl: int
) -> void:
	_transactions.append({
		"transaction_id": _next_tx_id,
		"stock_id": stock_id,
		"type": type,
		"quantity": quantity,
		"price": price,
		"total_amount": price * quantity,
		"tick": GameClock.get_current_tick(),
		"day": GameClock.get_current_day(),
		"realized_pnl": realized_pnl if type == "SELL" else 0,
	})
	_next_tx_id += 1
