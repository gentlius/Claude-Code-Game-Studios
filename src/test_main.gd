## Minimal test scene — verifies the full core loop runs without errors.
## Attach to a Node in TestMain.tscn, run, and watch console output.
## NOT a unit test — a smoke test for autoload wiring and tick flow.
extends Node

var _ticks_processed: int = 0
var _test_stock_id: String = "KF"
var _buy_placed: bool = false
var _sell_placed: bool = false


func _ready() -> void:
	print("=== Core Loop Smoke Test ===")
	_verify_autoloads()
	_connect_signals()
	_start_season()


func _verify_autoloads() -> void:
	assert(GameClock != null, "GameClock autoload missing")
	assert(StockDatabase != null, "StockDatabase autoload missing")
	assert(CurrencySystem != null, "CurrencySystem autoload missing")
	assert(PriceEngine != null, "PriceEngine autoload missing")
	assert(PortfolioManager != null, "PortfolioManager autoload missing")
	assert(OrderEngine != null, "OrderEngine autoload missing")
	print("[OK] All 6 autoloads loaded")

	var stock_count: int = StockDatabase.get_stock_count()
	assert(stock_count == 10, "Expected 10 stocks, got %d" % stock_count)
	print("[OK] StockDatabase: %d stocks loaded" % stock_count)


func _connect_signals() -> void:
	GameClock.on_tick.connect(_on_tick)
	GameClock.on_market_open.connect(_on_market_open)
	GameClock.on_market_close.connect(_on_market_close)
	GameClock.on_day_transition.connect(_on_day_transition)
	GameClock.on_season_end.connect(_on_season_end)
	PriceEngine.on_price_updated.connect(_on_price_updated)
	CurrencySystem.sim_cash_changed.connect(_on_sim_cash_changed)
	PortfolioManager.holding_added.connect(_on_holding_added)
	PortfolioManager.holding_removed.connect(_on_holding_removed)
	print("[OK] Signals connected")


func _start_season() -> void:
	print("\n--- Starting Season ---")
	GameClock.start_season()
	print("[OK] Season started, market state: %s" % GameClock.MarketState.keys()[GameClock.get_market_state()])
	print("[OK] Sim cash: %d" % CurrencySystem.get_sim_cash())
	print("[OK] PriceEngine state: %s" % PriceEngine.EngineState.keys()[PriceEngine._state])

	# Transition to market open
	GameClock.confirm_market_open()
	print("[OK] Market opened")


func _on_tick(tick: int) -> void:
	_ticks_processed += 1

	# Place a buy order on tick 5
	if tick == 5 and not _buy_placed:
		var price: int = PriceEngine.get_current_price(_test_stock_id)
		print("\n--- Placing BUY order at tick %d ---" % tick)
		print("  %s current price: %d" % [_test_stock_id, price])
		var result: Dictionary = OrderEngine.place_order(
			_test_stock_id, OrderEngine.OrderSide.BUY, 10,
			OrderEngine.OrderType.MARKET
		)
		print("  Order result: %s (id: %s)" % [
			"SUCCESS" if result["success"] else "FAILED: " + result.get("reason", ""),
			str(result.get("order_id", -1))
		])
		_buy_placed = true

	# Place a sell order on tick 50
	if tick == 50 and not _sell_placed and _buy_placed:
		var holding: Variant = PortfolioManager.get_holding(_test_stock_id)
		if holding != null:
			var price: int = PriceEngine.get_current_price(_test_stock_id)
			print("\n--- Placing SELL order at tick %d ---" % tick)
			print("  %s current price: %d (avg_buy: %d)" % [_test_stock_id, price, holding["avg_buy_price"]])
			var result: Dictionary = OrderEngine.place_order(
				_test_stock_id, OrderEngine.OrderSide.SELL, 5,
				OrderEngine.OrderType.MARKET
			)
			print("  Order result: %s" % [
				"SUCCESS" if result["success"] else "FAILED: " + result.get("reason", "")
			])
			_sell_placed = true

	# Print status every 100 ticks
	if tick % 100 == 0 and tick > 0:
		_print_status(tick)

	# End test after 200 ticks (don't need to run full day)
	if tick == 200:
		_print_final_report()
		get_tree().quit()


func _on_price_updated(_stock_id: String, _new_price: int, _delta_pct: float) -> void:
	pass  # High frequency — don't log


func _on_market_open() -> void:
	print("[EVENT] Market opened")


func _on_market_close() -> void:
	print("[EVENT] Market closed")


func _on_day_transition(_day: int) -> void:
	print("[EVENT] Day transition: day %d" % _day)


func _on_season_end() -> void:
	print("[EVENT] Season ended")


func _on_sim_cash_changed(new_amount: int, delta: int) -> void:
	if absi(delta) > 0:
		print("  [CASH] %+d → %d" % [delta, new_amount])


func _on_holding_added(stock_id: String, quantity: int, price: int) -> void:
	print("  [HOLDING+] %s x%d @ %d" % [stock_id, quantity, price])


func _on_holding_removed(stock_id: String, quantity: int, price: int, realized_pnl: int) -> void:
	print("  [HOLDING-] %s x%d @ %d (PnL: %+d)" % [stock_id, quantity, price, realized_pnl])


func _print_status(tick: int) -> void:
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	print("\n--- Status at tick %d ---" % tick)
	print("  Cash: %d | Holdings: %d | Total assets: %d | Return: %.1f%%" % [
		summary["sim_cash"], summary["holding_count"],
		summary["total_assets"], summary["return_rate"]
	])
	# Print a few stock prices
	for sid: String in ["KF", "SC", "MG"]:
		var price: int = PriceEngine.get_current_price(sid)
		var stock: StockData = StockDatabase.get_stock(sid)
		var pct: float = (float(price) - float(stock.base_price)) / float(stock.base_price) * 100.0
		print("  %s: %d (%+.1f%%)" % [sid, price, pct])


func _print_final_report() -> void:
	print("\n========== SMOKE TEST REPORT ==========")
	print("Ticks processed: %d" % _ticks_processed)
	print("Buy placed: %s | Sell placed: %s" % [str(_buy_placed), str(_sell_placed)])

	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	print("Final cash: %d" % summary["sim_cash"])
	print("Holdings: %d" % summary["holding_count"])
	print("Total assets: %d" % summary["total_assets"])
	print("Return rate: %.2f%%" % summary["return_rate"])

	var tx_history: Array[Dictionary] = PortfolioManager.get_transaction_history()
	print("Transactions: %d" % tx_history.size())
	for tx: Dictionary in tx_history:
		print("  #%d %s %s x%d @ %d (PnL: %+d)" % [
			tx["transaction_id"], tx["type"], tx["stock_id"],
			tx["quantity"], tx["price"], tx["realized_pnl"]
		])

	print("\nAll stock prices:")
	for sid: String in StockDatabase.get_all_stock_ids():
		var price: int = PriceEngine.get_current_price(sid)
		var stock: StockData = StockDatabase.get_stock(sid)
		var pct: float = (float(price) - float(stock.base_price)) / float(stock.base_price) * 100.0
		print("  %s (%s): %d (%+.1f%%)" % [sid, stock.name_ko, price, pct])

	print("========== TEST COMPLETE ==========")
