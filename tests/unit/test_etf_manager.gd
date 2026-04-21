## GUT unit tests for EtfManager — ETF pricing, sector flow, rotation, and OrderEngine ETF paths.
## Implements: design/gdd/sector-etf.md §8 AC-01 ~ AC-17
## AC-08/09/10/11 are integration tests in tests/integration/test_etf_integration.gd
extends GutTest

# ── Setup ──

func before_each() -> void:
	# Load ETF config so all _etf_sectors / _sector_archetypes maps are populated
	EtfManager._load_config()
	EtfManager._init_season()

	# Fresh market state + cash
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN
	CurrencySystem._sim_cash = 100_000_000

	# Ensure OrderEngine is clean
	OrderEngine._next_order_id = 1
	OrderEngine._market_order_queue.clear()
	OrderEngine._pending_limit_orders.clear()
	OrderEngine._order_history.clear()
	OrderEngine._sell_locks.clear()

	# Unlock P3 by default; individual tests that check the gate will lock it
	SkillTree._unlocked_skills["P3"] = true


func after_each() -> void:
	EtfManager.reset()
	PortfolioManager.reset()
	CurrencySystem._sim_cash = 0


# ── Helper: set current price for a stock in PriceEngine cache ──

func _set_stock_price(stock_id: String, price: int) -> void:
	if not PriceEngine._stock_states.has(stock_id):
		PriceEngine._stock_states[stock_id] = {
			"stock_id":          stock_id,
			"current_price":     price,
			"base_price":        StockDatabase.get_stock(stock_id).base_price if StockDatabase.get_stock(stock_id) != null else price,
			"prev_day_close":    price,
			"season_open_price": price,
			"tick_prices":       [] as Array[int],
			"tick_volumes":      [] as Array[float],
			"ohlcv_daily":       [] as Array[Dictionary],
			"order_book":        {"ask": [], "bid": []},
			"event_queue":       [],
		}
	else:
		PriceEngine._stock_states[stock_id]["current_price"] = price


# ── AC-01: P3 미해금 시 ETF 주문 거부 ──

func test_etf_order_rejected_without_p3() -> void:
	# Arrange: lock P3
	SkillTree._unlocked_skills["P3"] = false

	# Act
	var order: Dictionary = OrderEngine.submit_market_order("BUY", "ETF_반도체", 1)

	# Assert
	assert_eq(order["status"], "REJECTED", "ETF BUY should be REJECTED without P3")
	assert_true(order["reject_reason"].find("P3") >= 0,
		"Rejection reason should mention P3: " + order["reject_reason"])


# ── AC-02: 시즌 시작 시 11개 ETF 모두 50,000원 초기화 ──

func test_etf_initial_price_50000() -> void:
	var etf_ids: Array[String] = EtfManager.get_all_etf_ids()
	assert_eq(etf_ids.size(), 11, "KR market should have 11 ETFs")

	for etf_id: String in etf_ids:
		var price: float = EtfManager.get_etf_price(etf_id)
		assert_almost_eq(price, 50000.0, 1.0,
			"ETF %s should start at 50,000원, got %.1f" % [etf_id, price])


# ── AC-03: 섹터 구성 종목 전체 +10% → ETF 55,000원 (±10원) ──

func test_etf_price_all_stocks_up_10pct() -> void:
	# Arrange: set all 반도체 stocks to base_price × 1.10
	var stocks: Array[StockData] = StockDatabase.get_stocks_by_sector("반도체")
	assert_false(stocks.is_empty(), "반도체 sector must have stocks")

	for stock: StockData in stocks:
		_set_stock_price(stock.stock_id, roundi(stock.base_price * 1.10))

	# Act: recalculate
	var price: float = EtfManager._calc_etf_price("반도체")

	# Assert: ETF_BASE_PRICE × 1.10 = 55,000
	assert_almost_eq(price, 55000.0, 10.0,
		"All stocks +10% → ETF should be ~55,000원, got %.1f" % price)


# ── AC-04: 혼합 상승/하락 → 시가총액 가중 수익률 정확 반영 ──

func test_etf_weighted_return_mixed() -> void:
	# Arrange: use only first 2 stocks for a controlled calculation
	var stocks: Array[StockData] = StockDatabase.get_stocks_by_sector("반도체")
	assert_true(stocks.size() >= 2, "반도체 must have ≥ 2 stocks for this test")

	var s0: StockData = stocks[0]
	var s1: StockData = stocks[1]
	# Set s0 to +5%, s1 to -5%
	_set_stock_price(s0.stock_id, roundi(s0.base_price * 1.05))
	_set_stock_price(s1.stock_id, roundi(s1.base_price * 0.95))
	# Keep remaining stocks at base price
	for i: int in range(2, stocks.size()):
		_set_stock_price(stocks[i].stock_id, stocks[i].base_price)

	# Act
	var price: float = EtfManager._calc_etf_price("반도체")

	# Manual calculation to verify
	var base_mcap: float = 0.0
	var curr_mcap: float = 0.0
	for stock: StockData in stocks:
		base_mcap += float(stock.base_price) * float(stock.listed_shares)
	curr_mcap += float(roundi(s0.base_price * 1.05)) * float(s0.listed_shares)
	curr_mcap += float(roundi(s1.base_price * 0.95)) * float(s1.listed_shares)
	for i: int in range(2, stocks.size()):
		curr_mcap += float(stocks[i].base_price) * float(stocks[i].listed_shares)

	var expected_return: float = curr_mcap / base_mcap - 1.0
	var expected_price: float = 50000.0 * (1.0 + expected_return)

	assert_almost_eq(price, expected_price, 5.0,
		"Mixed ±5%% should match weighted calc %.1f, got %.1f" % [expected_price, price])


# ── AC-05: ETF 1주 매수 → 포트폴리오 슬롯 1 소비 ──

func test_etf_slot_consumed() -> void:
	# Arrange: P3 unlocked, fresh portfolio
	var slots_before: int = PortfolioManager.get_all_holdings().size()

	# Act
	var order: Dictionary = OrderEngine.submit_market_order("BUY", "ETF_반도체", 1)

	# Assert
	assert_eq(order["status"], "FILLED", "ETF BUY should FILL, got: " + order["reject_reason"])
	var slots_after: int = PortfolioManager.get_all_holdings().size()
	assert_eq(slots_after, slots_before + 1, "1 portfolio slot should be consumed")


# ── AC-06: ETF TR3 공매도 거부 ──

func test_etf_short_rejected() -> void:
	SkillTree._unlocked_skills["TR3"] = true

	var order: Dictionary = OrderEngine.submit_market_order("SELL_SHORT", "ETF_반도체", 1)

	assert_eq(order["status"], "REJECTED", "ETF SELL_SHORT should be REJECTED")
	assert_true(
		order["reject_reason"].find("ETF") >= 0 or order["reject_reason"].find("공매도") >= 0,
		"Rejection reason should mention ETF or 공매도: " + order["reject_reason"]
	)


# ── AC-07: ETF TR4 레버리지 거부 ──

func test_etf_leverage_rejected() -> void:
	SkillTree._unlocked_skills["TR4"] = true

	var order: Dictionary = OrderEngine.submit_market_order("LEVERAGE_BUY", "ETF_반도체", 1, 2)

	assert_eq(order["status"], "REJECTED", "ETF LEVERAGE_BUY should be REJECTED")
	assert_true(
		order["reject_reason"].find("ETF") >= 0 or order["reject_reason"].find("레버리지") >= 0,
		"Rejection reason should mention ETF or 레버리지: " + order["reject_reason"]
	)


# ── AC-12: ETF 매도 수수료 = gross × (0.002 + 0.00015) ──

func test_etf_sell_fee_calculation() -> void:
	# Arrange: buy 1 ETF first
	var buy_order: Dictionary = OrderEngine.submit_market_order("BUY", "ETF_반도체", 1)
	assert_eq(buy_order["status"], "FILLED", "Buy must succeed for fee test")

	var etf_price: int = PriceEngine.get_current_price("ETF_반도체")
	var gross: int = etf_price * 1

	# Act: sell
	var cash_before: int = CurrencySystem.get_sim_cash()
	var sell_order: Dictionary = OrderEngine.submit_market_order("SELL", "ETF_반도체", 1)
	assert_eq(sell_order["status"], "FILLED", "ETF SELL should be FILLED")

	var cash_after: int = CurrencySystem.get_sim_cash()
	var net_received: int = cash_after - cash_before

	# Expected: gross - sell_tax - commission
	var expected_tax: float = float(gross) * 0.002
	var expected_commission: float = float(gross) * 0.00015
	var expected_net: float = float(gross) - expected_tax - expected_commission

	assert_almost_eq(float(net_received), expected_net, 5.0,
		"Net proceeds should be gross − tax − commission. Expected %.0f got %d" % [expected_net, net_received])


# ── AC-13: etf_price ≥ 1원 보장 ──

func test_etf_price_floor_1won() -> void:
	# inject_price with 0 or negative should clamp to 1
	PriceEngine.inject_price("ETF_반도체", 0.0)
	assert_eq(PriceEngine.get_current_price("ETF_반도체"), 1,
		"inject_price(0) should clamp to 1")

	PriceEngine.inject_price("ETF_반도체", -100.0)
	assert_eq(PriceEngine.get_current_price("ETF_반도체"), 1,
		"inject_price(-100) should clamp to 1")

	PriceEngine.inject_price("ETF_반도체", 0.4)
	assert_eq(PriceEngine.get_current_price("ETF_반도체"), 1,
		"inject_price(0.4) should round+clamp to 1")


# ── AC-14: sector_flow_delta > ROTATION_THRESHOLD → inject_event 호출 ──

func test_rotation_event_injected_on_threshold() -> void:
	# Arrange: manually set sector flows so delta exceeds threshold
	# ROTATION_THRESHOLD default = 0.03
	EtfManager._sector_flows["반도체"] = 0.00
	EtfManager._sector_flows_prev["반도체"] = 0.0
	EtfManager._rotation_cooldowns["반도체"] = 0

	# Simulate: prev=0, curr=0.05 → delta=0.05 > 0.03
	EtfManager._sector_flows_prev["반도체"] = 0.0
	EtfManager._sector_flows["반도체"] = 0.05

	# Track if inject_event was called indirectly via NewsEventSystem
	# We verify via the sector flow gate — the rotation should have been triggered.
	# Direct signal observation isn't practical here, so we verify state post-trigger.
	EtfManager._check_rotation_trigger("반도체")

	# Cooldown should now be set (confirms the branch was taken)
	assert_gt(EtfManager._rotation_cooldowns["반도체"], 0,
		"Cooldown should be set after threshold crossed")


# ── AC-15: ROTATION_COOLDOWN 내 연속 임계값 초과 시 이벤트 1회만 발화 ──

func test_rotation_cooldown_prevents_spam() -> void:
	# Arrange: set flows to trigger, fire once
	EtfManager._sector_flows_prev["반도체"] = 0.0
	EtfManager._sector_flows["반도체"] = 0.05
	EtfManager._rotation_cooldowns["반도체"] = 0
	EtfManager._check_rotation_trigger("반도체")  # First trigger

	var cooldown_after_first: int = EtfManager._rotation_cooldowns["반도체"]
	assert_gt(cooldown_after_first, 0, "Cooldown should be > 0 after first trigger")

	# Act: try to trigger again immediately (cooldown still active)
	EtfManager._check_rotation_trigger("반도체")
	var cooldown_unchanged: int = EtfManager._rotation_cooldowns["반도체"]

	# Assert: cooldown should NOT be reset (no second trigger)
	assert_eq(cooldown_unchanged, cooldown_after_first,
		"Second trigger within cooldown should be ignored (cooldown unchanged)")


# ── AC-16: inflow impact 범위 ≥ outflow impact 범위 ──

func test_inflow_impact_greater_than_outflow() -> void:
	# Read from EtfManager's loaded config values
	assert_ge(EtfManager._inflow_impact_min, EtfManager._outflow_impact_min,
		"inflow_impact_min should >= outflow_impact_min")
	assert_ge(EtfManager._inflow_impact_max, EtfManager._outflow_impact_max,
		"inflow_impact_max should >= outflow_impact_max")
	assert_ge(EtfManager._inflow_impact_min, EtfManager._outflow_impact_max,
		"Minimum inflow impact should exceed maximum outflow impact")


# ── AC-17: 소외 섹터가 hot_sector와 다른 아키타입에서 선택됨 ──

func test_rival_sector_different_archetype() -> void:
	# Simulate 1000 picks from a TECH sector and verify all rivals are non-TECH
	const TRIALS: int = 1000
	var all_different: bool = true

	for _i: int in TRIALS:
		var rival: String = EtfManager._pick_rival_sector("반도체")
		if rival.is_empty():
			continue
		var hot_arch: String = EtfManager._sector_archetypes.get("반도체", "")
		var rival_arch: String = EtfManager._sector_archetypes.get(rival, "")
		if hot_arch == rival_arch:
			all_different = false
			gut.p("FAIL: hot=반도체 (TECH), rival=%s (arch=%s)" % [rival, rival_arch])
			break

	assert_true(all_different,
		"rival sector must always come from a different archetype (1000 trials)")


# ── ETF is_etf() API ──

func test_is_etf_returns_true_for_etf_ids() -> void:
	assert_true(EtfManager.is_etf("ETF_반도체"),  "ETF_반도체 should be ETF")
	assert_true(EtfManager.is_etf("ETF_바이오"),  "ETF_바이오 should be ETF")
	assert_true(EtfManager.is_etf("ETF_통신"),    "ETF_통신 should be ETF")


func test_is_etf_returns_false_for_stocks() -> void:
	assert_false(EtfManager.is_etf("SKL"),  "SKL should not be ETF")
	assert_false(EtfManager.is_etf(""),     "Empty string should not be ETF")
	assert_false(EtfManager.is_etf("KSF"),  "KSF should not be ETF")


# ── ETF get_etf_return() ──

func test_get_etf_return_starts_at_zero() -> void:
	# After _init_season, all returns should be 0.0
	for etf_id: String in EtfManager.get_all_etf_ids():
		var ret: float = EtfManager.get_etf_return(etf_id)
		assert_almost_eq(ret, 0.0, 0.001,
			"Initial return for %s should be 0.0, got %.4f" % [etf_id, ret])


# ── ETF limit order rejection ──

func test_etf_limit_order_rejected() -> void:
	SkillTree._unlocked_skills["TR1"] = true
	var order: Dictionary = OrderEngine.submit_limit_order("BUY", "ETF_반도체", 1, 50000)
	assert_eq(order["status"], "REJECTED", "ETF limit order should be REJECTED")
	assert_true(order["reject_reason"].find("즉시 체결") >= 0 or order["reject_reason"].find("ETF") >= 0,
		"Rejection reason should explain immediate-fill-only: " + order["reject_reason"])
