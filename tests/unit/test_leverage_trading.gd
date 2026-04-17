## Unit tests for LeverageManager and OrderEngine TR4 leverage integration.
## GUT test suite. See: design/gdd/leverage-trading.md §8 AC.
extends GutTest

# ── Constants ──

## Real stock ID guaranteed to exist in stocks.json.
const MOCK_STOCK: String = "STC"
const MOCK_STOCK_2: String = "STC2"  ## Second stock for multi-position tests
const MOCK_PRICE: int = 65_000       ## Entry price for F1/F2/F3 formula examples


# ── Helpers ──

func _set_mock_price(stock_id: String, price: int) -> void:
	## Full _stock_states entry — order_book required for OrderEngine.
	PriceEngine._stock_states[stock_id] = {
		"stock_id":            stock_id,
		"current_price":       price,
		"base_price":          price,
		"prev_day_close":      price,
		"season_open_price":   price,
		"volatility_profile":  StockData.VolatilityProfile.MEDIUM,
		"macro_sensitivity":   1.0,
		"sector_sensitivity":  1.0,
		"markov_state":        PriceEngine.MarkovState.SIDEWAYS,
		"state_duration":      0,
		"season_bias":         PriceEngine.SeasonBias.NEUTRAL,
		"tick_prices":         [] as Array[int],
		"tick_volumes":        [] as Array[float],
		"ohlcv_daily":         [] as Array[Dictionary],
		"event_queue":         [] as Array,
		"gradual_events":      [] as Array,
		"order_book": {
			"ask": [{"price": price, "qty": 10000}],
			"bid": [{"price": price, "qty": 10000}],
		},
	}


func _unlock_tr4() -> void:
	SkillTree._unlocked_skills["TR4"] = true


## Directly inject a leverage position for tests needing an existing position.
func _inject_leverage_position(
	stock_id: String, quantity: int, entry_price: int, multiplier: int,
	borrowed: int = -1, accrued_interest: int = 0, open_day: int = 0
) -> void:
	var order_value: int = entry_price * quantity
	var actual_borrowed: int = borrowed if borrowed >= 0 else (
		order_value - int(ceil(float(order_value) / float(multiplier)))
	)
	LeverageManager._positions.append({
		"stock_id":         stock_id,
		"quantity":         quantity,
		"entry_price":      entry_price,
		"multiplier":       multiplier,
		"borrowed":         actual_borrowed,
		"accrued_interest": accrued_interest,
		"open_day":         open_day,
	})


# ── Setup / Teardown ──

func before_each() -> void:
	LeverageManager.reset()
	ShortSellingSystem.reset()
	PortfolioManager.reset()
	OrderEngine.reset()
	SkillTree._unlocked_skills.clear()
	CurrencySystem.reset()
	CurrencySystem.init_first_season(10_000_000)  ## 1000만원 시작 자금
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN
	_set_mock_price(MOCK_STOCK, MOCK_PRICE)


func after_each() -> void:
	LeverageManager.reset()
	PriceEngine._stock_states.erase(MOCK_STOCK)
	PriceEngine._stock_states.erase(MOCK_STOCK_2)
	GameClock._market_state = GameClock.MarketState.PRE_MARKET


# ── AC-01: 2× 매수 — equity_used만 차감, borrowed 기록 ────────────────

func test_2x_buy_deducts_equity_only() -> void:
	# GDD F1: equity_used = ceil(order_value / multiplier), borrowed = order_value - equity_used
	_unlock_tr4()
	var cash_before: int = CurrencySystem.get_sim_cash()
	var quantity: int = 100
	# order_value = 65_000 × 100 = 6_500_000
	# equity_used = ceil(6_500_000 / 2) = 3_250_000
	# borrowed = 3_250_000

	var order: Dictionary = OrderEngine.submit_market_order("LEVERAGE_BUY", MOCK_STOCK, quantity, 2)

	assert_eq(order["status"], "FILLED", "레버리지 매수 FILLED")
	assert_eq(order["filled_price"], MOCK_PRICE, "체결가 일치")

	var cash_after: int = CurrencySystem.get_sim_cash()
	var equity_used: int = int(ceil(float(MOCK_PRICE * quantity) / 2.0))
	assert_eq(cash_before - cash_after, equity_used, "equity_used만 차감됨")

	var positions: Array[Dictionary] = LeverageManager.get_all_positions()
	assert_eq(positions.size(), 1, "포지션 1개 생성")
	var pos: Dictionary = positions[0]
	assert_eq(pos["borrowed"], MOCK_PRICE * quantity - equity_used, "borrowed 기록 정확")
	assert_eq(pos["multiplier"], 2, "multiplier 기록")
	assert_eq(pos["quantity"], quantity, "수량 기록")


# ── AC-02: 3×, 5× 배율 공식 검증 ────────────────────────────────────

func test_multiplier_equity_calculation_3x() -> void:
	_unlock_tr4()
	var cash_before: int = CurrencySystem.get_sim_cash()
	var quantity: int = 100
	var order_value: int = MOCK_PRICE * quantity  # 6_500_000
	var equity_expected: int = int(ceil(float(order_value) / 3.0))

	OrderEngine.submit_market_order("LEVERAGE_BUY", MOCK_STOCK, quantity, 3)

	assert_eq(cash_before - CurrencySystem.get_sim_cash(), equity_expected, "3× equity_used 정확")
	var pos: Dictionary = LeverageManager.get_all_positions()[0]
	assert_eq(pos["borrowed"], order_value - equity_expected, "3× borrowed 정확")


func test_multiplier_equity_calculation_5x() -> void:
	_unlock_tr4()
	var cash_before: int = CurrencySystem.get_sim_cash()
	var quantity: int = 100
	var order_value: int = MOCK_PRICE * quantity  # 6_500_000
	var equity_expected: int = int(ceil(float(order_value) / 5.0))

	OrderEngine.submit_market_order("LEVERAGE_BUY", MOCK_STOCK, quantity, 5)

	assert_eq(cash_before - CurrencySystem.get_sim_cash(), equity_expected, "5× equity_used 정확")
	var pos: Dictionary = LeverageManager.get_all_positions()[0]
	assert_eq(pos["borrowed"], order_value - equity_expected, "5× borrowed 정확")


# ── AC-03: 일별 이자 — floor(borrowed × daily_rate) ──────────────────

func test_daily_interest_deducted_on_market_close() -> void:
	# GDD F2: daily_interest = floor(borrowed × daily_rate)
	# 2× borrowed = 3_250_000, daily_rate = 0.0004
	# interest = floor(3_250_000 × 0.0004) = floor(1_300) = 1_300
	_inject_leverage_position(MOCK_STOCK, 100, MOCK_PRICE, 2)
	var pos: Dictionary = LeverageManager.get_all_positions()[0]
	var borrowed: int = pos["borrowed"]
	var expected_interest: int = int(floor(borrowed * 0.0004))

	var cash_before: int = CurrencySystem.get_sim_cash()
	LeverageManager.process_daily_interest(1)

	assert_eq(cash_before - CurrencySystem.get_sim_cash(), expected_interest,
		"일별 이자 정확히 차감됨")
	var updated: Dictionary = LeverageManager.get_all_positions()[0]
	assert_eq(updated["accrued_interest"], expected_interest, "accrued_interest 누적")


# ── AC-04: 이자 > 현금 → 가용 현금 전액 차감 + borrowed 가산 ─────────

func test_interest_exceeds_cash_adds_to_borrowed() -> void:
	# Set cash very low so interest > available
	CurrencySystem.reset()
	CurrencySystem.init_first_season(100)  ## 100원만
	# 5× borrowed for MOCK_STOCK: large enough that interest > 100
	# order_value=6_500_000, equity=1_300_000, borrowed=5_200_000
	# interest = floor(5_200_000 × 0.001) = 5_200 > 100
	_inject_leverage_position(MOCK_STOCK, 100, MOCK_PRICE, 5)
	var pos_before: Dictionary = LeverageManager.get_all_positions()[0]
	var borrowed_before: int = pos_before["borrowed"]
	var daily_rate: float = 0.001
	var interest: int = int(floor(borrowed_before * daily_rate))

	LeverageManager.process_daily_interest(1)

	assert_eq(CurrencySystem.get_sim_cash(), 0, "현금 전액 차감됨")
	var pos_after: Dictionary = LeverageManager.get_all_positions()[0]
	var shortfall: int = interest - 100
	assert_eq(pos_after["borrowed"], borrowed_before + shortfall, "부족분이 borrowed에 가산됨")


# ── AC-05: 마진콜 — equity_ratio < threshold 시 시그널 발동 ───────────

func test_margin_call_triggered_below_threshold() -> void:
	# 2× margin_call_threshold = 0.30
	# entry=65_000, qty=100, borrowed=3_250_000
	# At price P: equity = P*100 - 3_250_000, equity_ratio = equity / (P*100)
	# At P=46_000: market_val=4_600_000, equity=1_350_000, ratio=0.293 < 0.30 → margin call
	_inject_leverage_position(MOCK_STOCK, 100, MOCK_PRICE, 2)
	_set_mock_price(MOCK_STOCK, 46_000)

	watch_signals(LeverageManager)
	# Not yet in forced liquidation territory (forced_liq_threshold 2× = 0.10)
	# At 46_000: ratio = (4_600_000 - 3_250_000) / 4_600_000 ≈ 0.293 → margin call, not forced
	LeverageManager.check_margin_calls()

	assert_signal_emitted(LeverageManager, "on_margin_call", "마진콜 시그널 발동")
	assert_eq(LeverageManager.get_all_positions().size(), 1, "포지션은 유지됨 (강제청산 아님)")


# ── AC-06: 강제청산 — equity_ratio < forced_liq_threshold ────────────

func test_forced_liquidation_on_zero_equity() -> void:
	# 2× forced_liq_threshold = 0.10
	# equity_used=3_250_000, borrowed=3_250_000
	# At price 36_000: market_val=3_600_000, equity=350_000, ratio=350_000/3_600_000 ≈ 0.097 < 0.10
	_inject_leverage_position(MOCK_STOCK, 100, MOCK_PRICE, 2)
	var pos: Dictionary = LeverageManager.get_all_positions()[0]
	var borrowed: int = pos["borrowed"]
	_set_mock_price(MOCK_STOCK, 36_000)

	var cash_before: int = CurrencySystem.get_sim_cash()
	watch_signals(LeverageManager)

	LeverageManager.check_margin_calls()

	assert_signal_emitted(LeverageManager, "on_leverage_forced_liquidation", "강제청산 시그널 발동")
	assert_eq(LeverageManager.get_all_positions().size(), 0, "포지션 제거됨")

	# proceeds=3_600_000, net=3_600_000 - 3_250_000=350_000 → added back
	var expected_net: int = 36_000 * 100 - borrowed
	assert_eq(CurrencySystem.get_sim_cash(), cash_before + expected_net, "잔여 equity 환원")


# ── AC-07: 강제청산 후 net_proceeds < 0 → sim_cash 0 클램프 ──────────

func test_forced_liquidation_net_loss_clamped_at_zero() -> void:
	# Force a scenario where proceeds < borrowed → negative net
	# Use 5×: equity_used=1_300_000, borrowed=5_200_000
	# At price 10_000: market_val=1_000_000, net=1_000_000-5_200_000=-4_200_000
	_inject_leverage_position(MOCK_STOCK, 100, MOCK_PRICE, 5)
	_set_mock_price(MOCK_STOCK, 10_000)
	# Ensure sim_cash < |net_proceeds| to hit the clamp
	CurrencySystem.reset()
	CurrencySystem.init_first_season(500_000)  ## less than the 4_200_000 loss

	LeverageManager.check_margin_calls()

	assert_eq(CurrencySystem.get_sim_cash(), 0, "sim_cash 0 클램프 — 음수 불가 (GDD §5)")
	assert_eq(LeverageManager.get_all_positions().size(), 0, "포지션 제거됨")


# ── AC-08: 시즌 종료 — 전체 포지션 청산 ─────────────────────────────

func test_season_end_liquidates_all_positions() -> void:
	_inject_leverage_position(MOCK_STOCK, 100, MOCK_PRICE, 2)
	_inject_leverage_position(MOCK_STOCK, 50, MOCK_PRICE, 3)
	assert_eq(LeverageManager.get_all_positions().size(), 2, "2개 포지션 주입됨")

	LeverageManager.liquidate_all_positions()

	assert_eq(LeverageManager.get_all_positions().size(), 0, "시즌 종료 후 포지션 0개")


# ── AC-09: TR4 미해금 → REJECTED ─────────────────────────────────────

func test_leverage_rejected_without_tr4_skill() -> void:
	# TR4 not unlocked
	var order: Dictionary = OrderEngine.submit_market_order("LEVERAGE_BUY", MOCK_STOCK, 10, 2)

	assert_eq(order["status"], "REJECTED", "TR4 미해금 시 REJECTED")
	assert_true(order["reject_reason"].contains("해금"), "거부 사유 포함")
	assert_eq(LeverageManager.get_all_positions().size(), 0, "포지션 생성 안 됨")


# ── AC-10: 유효하지 않은 배율 → REJECTED ─────────────────────────────

func test_invalid_multiplier_rejected() -> void:
	_unlock_tr4()
	var order: Dictionary = OrderEngine.submit_market_order("LEVERAGE_BUY", MOCK_STOCK, 10, 4)

	assert_eq(order["status"], "REJECTED", "유효하지 않은 배율 REJECTED")
	assert_true(order["reject_reason"].contains("배율"), "배율 거부 사유")


# ── AC-11: 복수 포지션 독립 마진콜 계산 ───────────────────────────────

func test_multiple_positions_independent_margin_call() -> void:
	# Position 1: 2× at 65_000 → margin_call at ~46_000
	# Position 2: 5× at 65_000 → forced_liq at ~55_000
	_inject_leverage_position(MOCK_STOCK, 100, MOCK_PRICE, 2)  # 2× pos
	_inject_leverage_position(MOCK_STOCK, 10, MOCK_PRICE, 5)   # 5× pos (different multiplier)

	# Set price to 36_000 → both in forced_liq territory (2× ratio≈0.097, 5× equity negative)
	_set_mock_price(MOCK_STOCK, 36_000)
	LeverageManager.check_margin_calls()

	assert_eq(LeverageManager.get_all_positions().size(), 0, "두 포지션 모두 강제청산됨")


# ── AC-12: leverage_net_value → account_total_value 반영 ─────────────

func test_leverage_position_reflected_in_account_total_value() -> void:
	# GDD §6: leverage equity = position_market_value - borrowed - accrued_interest
	# equity_used = ceil(6_500_000 / 2) = 3_250_000 deducted from sim_cash
	# leverage_net_value should add equity back into total assets
	_unlock_tr4()
	var cash_before: int = CurrencySystem.get_sim_cash()

	OrderEngine.submit_market_order("LEVERAGE_BUY", MOCK_STOCK, 100, 2)

	# At the same price, equity = position_market_value - borrowed
	# = 6_500_000 - 3_250_000 = 3_250_000 = equity_used originally
	# total_assets = (cash_before - equity_used) + 0 (no long holdings) + equity = cash_before
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)
	assert_eq(PortfolioManager.get_total_assets(), cash_before,
		"레버리지 equity가 total_assets에 정확히 반영됨 (AC-12)")


# ── 증거금 부족 → REJECTED ────────────────────────────────────────────

func test_insufficient_equity_rejected() -> void:
	_unlock_tr4()
	# Set cash too low for 5× equity_used = ceil(6_500_000 / 5) = 1_300_000
	CurrencySystem.reset()
	CurrencySystem.init_first_season(500_000)  ## less than 1_300_000

	var order: Dictionary = OrderEngine.submit_market_order("LEVERAGE_BUY", MOCK_STOCK, 100, 5)

	assert_eq(order["status"], "REJECTED", "증거금 부족 REJECTED")
	assert_true(order["reject_reason"].contains("부족"), "부족 사유 포함")


# ── PRE_MARKET 상태에서 레버리지 주문 거부 ─────────────────────────────

func test_leverage_buy_rejected_in_pre_market() -> void:
	_unlock_tr4()
	GameClock._market_state = GameClock.MarketState.PRE_MARKET

	var order: Dictionary = OrderEngine.submit_market_order("LEVERAGE_BUY", MOCK_STOCK, 10, 2)

	assert_eq(order["status"], "REJECTED", "PRE_MARKET에서 레버리지 REJECTED")


# ── LEVERAGE_SELL — 포지션 청산 + net_proceeds ────────────────────────

func test_leverage_sell_closes_position_and_returns_net() -> void:
	# Open 2× position, then sell all at same price → net = equity_used
	_unlock_tr4()
	OrderEngine.submit_market_order("LEVERAGE_BUY", MOCK_STOCK, 100, 2)
	var equity_used: int = int(ceil(float(MOCK_PRICE * 100) / 2.0))
	var cash_after_buy: int = CurrencySystem.get_sim_cash()

	var sell_order: Dictionary = OrderEngine.submit_market_order("LEVERAGE_SELL", MOCK_STOCK, 100)

	assert_eq(sell_order["status"], "FILLED", "LEVERAGE_SELL FILLED")
	assert_eq(LeverageManager.get_all_positions().size(), 0, "포지션 제거됨")
	# net_proceeds = proceeds - borrowed = 6_500_000 - 3_250_000 = 3_250_000 = equity_used
	assert_eq(CurrencySystem.get_sim_cash(), cash_after_buy + equity_used, "equity 환원됨")


# ── Save/Load 라운드트립 ──────────────────────────────────────────────

func test_save_load_roundtrip() -> void:
	_inject_leverage_position(MOCK_STOCK, 100, MOCK_PRICE, 2, -1, 1_300, 3)

	var saved: Array[Dictionary] = LeverageManager.get_save_data()
	LeverageManager.reset()
	assert_eq(LeverageManager.get_all_positions().size(), 0, "리셋 후 비어있음")

	LeverageManager.load_save_data(saved)

	var restored: Array[Dictionary] = LeverageManager.get_all_positions()
	assert_eq(restored.size(), 1, "포지션 복원됨")
	var pos: Dictionary = restored[0]
	assert_eq(pos["stock_id"], MOCK_STOCK, "stock_id 복원")
	assert_eq(pos["quantity"], 100, "quantity 복원")
	assert_eq(pos["multiplier"], 2, "multiplier 복원")
	assert_eq(pos["accrued_interest"], 1_300, "accrued_interest 복원")
	assert_eq(pos["open_day"], 3, "open_day 복원")


# ── get_leverage_net_value — 빈 포지션 ────────────────────────────────

func test_get_leverage_net_value_empty() -> void:
	assert_eq(LeverageManager.get_leverage_net_value(), 0, "포지션 없으면 net_value=0")


# ── 동일 종목 동일 배율 → 포지션 병합 ───────────────────────────────

func test_same_stock_same_multiplier_merges() -> void:
	_unlock_tr4()
	OrderEngine.submit_market_order("LEVERAGE_BUY", MOCK_STOCK, 50, 2)
	OrderEngine.submit_market_order("LEVERAGE_BUY", MOCK_STOCK, 50, 2)

	assert_eq(LeverageManager.get_all_positions().size(), 1, "동일 배율은 단일 포지션으로 병합")
	var pos: Dictionary = LeverageManager.get_all_positions()[0]
	assert_eq(pos["quantity"], 100, "병합 후 총 수량 = 100")
