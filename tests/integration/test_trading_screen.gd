## Automated playtest — verifies TradingScreen loads and runs the full game loop.
## Simulates: season init → market open → buy/sell → tick through → market close.
extends Node

var _screen: Control
var _ticks: int = 0
var _bought: bool = false
var _sold: bool = false


func _ready() -> void:
	print("=== Trading Screen Playtest ===")

	# Init season
	CurrencySystem.init_season_seed()
	GameClock.start_season()
	print("[OK] Season started (PRE_MARKET)")

	# Load TradingScreen
	var scene: PackedScene = load("res://src/ui/TradingScreen.tscn")
	_screen = scene.instantiate()
	add_child(_screen)
	print("[OK] TradingScreen loaded (%d children)" % _screen.get_child_count())

	# Connect signals
	GameClock.on_tick.connect(_on_tick)
	OrderEngine.on_order_filled.connect(_on_filled)
	OrderEngine.on_order_rejected.connect(_on_rejected)
	NewsEventSystem.on_news_display.connect(_on_news)

	# Auto-open market after 1 frame (let UI settle)
	await get_tree().process_frame
	GameClock.confirm_market_open()
	print("[OK] Market opened → MARKET_OPEN")
	print("")


func _on_tick(tick: int, day: int, _week: int) -> void:
	_ticks += 1

	# Buy at tick 10
	if tick == 10 and not _bought:
		var price: int = PriceEngine.get_current_price("KSF")
		print("[TICK %d] Buying KSF 5주 @ ₩%d" % [tick, price])
		var result: Dictionary = OrderEngine.submit_market_order("BUY", "KSF", 5)
		print("  → %s" % result["status"])
		_bought = true

	# Buy another stock at tick 30
	if tick == 30:
		var price: int = PriceEngine.get_current_price("STC")
		print("[TICK %d] Buying STC 3주 @ ₩%d" % [tick, price])
		var result: Dictionary = OrderEngine.submit_market_order("BUY", "STC", 3)
		print("  → %s" % result["status"])

	# Sell at tick 80
	if tick == 80 and not _sold:
		var holding: Variant = PortfolioManager.get_holding("KSF")
		if holding != null:
			var price: int = PriceEngine.get_current_price("KSF")
			print("[TICK %d] Selling KSF 3주 @ ₩%d (avg_buy: %d)" % [tick, price, holding["avg_buy_price"]])
			var result: Dictionary = OrderEngine.submit_market_order("SELL", "KSF", 3)
			print("  → %s" % result["status"])
			_sold = true

	# Status every 50 ticks
	if tick > 0 and tick % 50 == 0:
		_print_status(tick)

	# Test pause/unpause at tick 100
	if tick == 100:
		print("\n[TICK %d] Testing pause..." % tick)
		GameClock.toggle_pause()
		print("  State: %s" % GameClock.MarketState.keys()[GameClock.get_market_state()])
		# Unpause next frame
		await get_tree().process_frame
		GameClock.toggle_pause()
		print("  Resumed: %s" % GameClock.MarketState.keys()[GameClock.get_market_state()])

	# Test speed change at tick 150
	if tick == 150:
		print("\n[TICK %d] Setting speed to 4x" % tick)
		GameClock.set_speed(4.0)

	# End test at tick 200
	if tick == 200:
		_print_final_report()
		get_tree().quit()


func _on_filled(order: Dictionary) -> void:
	print("  [FILLED] %s %s %d주 @ ₩%d" % [
		order["side"], order["stock_id"],
		order["quantity"], order["filled_price"]
	])


func _on_rejected(order: Dictionary) -> void:
	print("  [REJECTED] %s — %s" % [order["stock_id"], order["reject_reason"]])


func _on_news(entry: Dictionary) -> void:
	print("  [NEWS] %s" % entry.get("headline", "?"))


func _print_status(tick: int) -> void:
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	print("\n--- Status @ tick %d ---" % tick)
	print("  Cash: ₩%d | Holdings: %d | Total: ₩%d | Return: %+.1f%%" % [
		summary["sim_cash"], summary["holding_count"],
		summary["total_assets"], summary["return_rate"]
	])

	var holdings: Array[Dictionary] = PortfolioManager.get_all_holdings()
	for h: Dictionary in holdings:
		var price: int = PriceEngine.get_current_price(h["stock_id"])
		print("  %s: %d주 @ avg ₩%d → ₩%d (%+.1f%%)" % [
			h["stock_id"], h["quantity"], h["avg_buy_price"],
			price, h["unrealized_pnl_pct"]
		])


func _print_final_report() -> void:
	print("\n========== PLAYTEST REPORT ==========")
	print("Ticks processed: %d" % _ticks)
	print("Orders: bought=%s, sold=%s" % [str(_bought), str(_sold)])

	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	print("Final assets: ₩%d (return: %+.2f%%)" % [
		summary["total_assets"], summary["return_rate"]
	])
	print("Holdings: %d | Cash: ₩%d" % [
		summary["holding_count"], summary["sim_cash"]
	])

	var tx: Array[Dictionary] = PortfolioManager.get_transaction_history()
	print("Transactions: %d" % tx.size())
	for t: Dictionary in tx:
		print("  %s %s %d주 @ ₩%d (PnL: %+d)" % [
			t["type"], t["stock_id"], t["quantity"], t["price"], t["realized_pnl"]
		])

	var news_stats: Dictionary = NewsEventSystem.get_season_stats()
	print("News delivered: %d" % news_stats["total_events"])

	print("Speed: %.0fx" % GameClock.get_speed_multiplier())
	print("========== TEST COMPLETE ==========")
