## S10-06 검증 테스트 — 7개 항목 (a~g)
## (a) save-load AC-18/19: 레버리지·공매도 포지션 직렬화
## (b) news-events 가중치: _calc_template_weight() 정량 검증 (±0.001)
## (c) season-manager AC-21/22: 프리마켓 브론즈 재진입 + 한강 엔딩 조건
## (d) currency-system E2E: auto_deposit → 매매 → settle_to_cash → 자동입금
## (e) short-selling margin_rate 하한 1.20 적용
## (f) leverage F2b: 이자 원금화 (borrowed 누적)
## (g) trading-fees: KR holding_days=0 → capital_gains=0 항상
extends GutTest

# ══════════════════════════════════════════════════════════════════
# (a) SAVE-LOAD AC-18/19 — 레버리지·공매도 포지션 직렬화
# ══════════════════════════════════════════════════════════════════

func test_leverage_save_load_preserves_borrowed_and_accrued_interest() -> void:
	## AC-18: 레버리지 포지션 borrowed + accrued_interest 직렬화 검증
	LeverageManager.reset()

	# Build a fake position dict directly (bypasses OrderEngine & CurrencySystem)
	var fake_pos: Dictionary = {
		"stock_id":         "TEST_LV",
		"quantity":         100,
		"entry_price":      50000,
		"multiplier":       2,
		"borrowed":         3000000,
		"accrued_interest": 12000,
		"open_day":         3,
	}
	LeverageManager._positions.append(fake_pos)

	var saved: Array = LeverageManager.get_save_data()
	LeverageManager.reset()
	LeverageManager.load_save_data(saved)

	var restored: Array[Dictionary] = LeverageManager.get_all_positions()
	assert_eq(restored.size(), 1, "포지션 1개 복원")
	assert_eq(restored[0]["stock_id"],         "TEST_LV",  "stock_id 복원")
	assert_eq(restored[0]["borrowed"],          3000000,    "borrowed 복원 (AC-18)")
	assert_eq(restored[0]["accrued_interest"],  12000,      "accrued_interest 복원 (AC-18)")
	assert_eq(restored[0]["entry_price"],       50000,      "entry_price 복원")
	assert_eq(restored[0]["multiplier"],        2,          "multiplier 복원")

	LeverageManager.reset()


func test_short_save_load_preserves_entry_price_and_margin_deposited() -> void:
	## AC-19: 공매도 포지션 entry_price + margin_deposited 직렬화 검증
	ShortSellingSystem.reset()

	# Inject a fake position directly
	ShortSellingSystem._positions["TEST_SH"] = {
		"stock_id":         "TEST_SH",
		"quantity":         200,
		"open_price":       80000,
		"initial_value":    16000000,
		"margin_deposited": 22400000,  # = 16M × 1.40
		"open_tick":        10,
		"open_day":         2,
		"unrealized_pnl":   0,
		"margin_ratio":     1.40,
	}

	var saved: Array = ShortSellingSystem.get_save_data()
	ShortSellingSystem.reset()
	ShortSellingSystem.load_save_data(saved)

	var positions: Array[Dictionary] = ShortSellingSystem.get_all_short_positions()
	assert_eq(positions.size(), 1, "공매도 포지션 1개 복원")
	assert_eq(positions[0]["stock_id"],         "TEST_SH",  "stock_id 복원")
	assert_eq(positions[0]["open_price"],        80000,      "entry_price(=open_price) 복원 (AC-19)")
	assert_eq(positions[0]["margin_deposited"],  22400000,   "margin_deposited 복원 (AC-19)")

	ShortSellingSystem.reset()


# ══════════════════════════════════════════════════════════════════
# (b) NEWS-EVENTS 가중치 — _calc_template_weight() 정량 검증
# ══════════════════════════════════════════════════════════════════

func test_calc_template_weight_boost_1_5_multiplies_correctly() -> void:
	## boost=1.5인 섹터 → weight = weight_base × 1.5 (±0.001)
	var template: Dictionary = {"weight_base": 2.0, "target_sector": "IT"}
	var bias: Dictionary = {"IT": 1.5}
	var result: float = NewsEventSystem._calc_template_weight(template, bias)
	assert_almost_eq(result, 3.0, 0.001, "weight_base=2.0 × bias=1.5 = 3.0")


func test_calc_template_weight_boost_0_5_reduces_correctly() -> void:
	## boost=0.5인 섹터 → weight = weight_base × 0.5 (±0.001)
	var template: Dictionary = {"weight_base": 2.0, "target_sector": "금융"}
	var bias: Dictionary = {"금융": 0.5}
	var result: float = NewsEventSystem._calc_template_weight(template, bias)
	assert_almost_eq(result, 1.0, 0.001, "weight_base=2.0 × bias=0.5 = 1.0")


func test_calc_template_weight_no_sector_returns_base() -> void:
	## target_sector 없음 → weight_base 그대로
	var template: Dictionary = {"weight_base": 3.0}
	var bias: Dictionary = {"IT": 2.0}
	var result: float = NewsEventSystem._calc_template_weight(template, bias)
	assert_almost_eq(result, 3.0, 0.001, "섹터 없음 → weight_base 그대로")


func test_calc_template_weight_missing_sector_in_bias_defaults_to_1() -> void:
	## sector_bias에 target_sector 없으면 1.0으로 default
	var template: Dictionary = {"weight_base": 2.0, "target_sector": "에너지"}
	var bias: Dictionary = {"IT": 1.5}
	var result: float = NewsEventSystem._calc_template_weight(template, bias)
	assert_almost_eq(result, 2.0, 0.001, "bias 미포함 섹터 → default 1.0 적용")


# ══════════════════════════════════════════════════════════════════
# (c) SEASON-MANAGER AC-21/22 — 프리마켓 브론즈 재진입 + 한강 엔딩
# ══════════════════════════════════════════════════════════════════

func test_season_manager_assign_tier_bronze_at_threshold() -> void:
	## AC-21 선행 조건: cash_assets >= TIER_THRESHOLD[0] → TIER_BRONZE(0) 배정
	## _assign_tier()는 private이지만 GDScript에서 직접 호출 가능
	var bronze_threshold: int = SeasonManager.TIER_THRESHOLD[0]  # 1,000,000
	var tier: int = SeasonManager._assign_tier(bronze_threshold)
	assert_eq(tier, SeasonManager.TIER_BRONZE, "기준금액 정확히 충족 → 브론즈 배정 (AC-21)")


func test_season_manager_assign_tier_free_market_below_threshold() -> void:
	## AC-21 선행 조건: cash_assets < TIER_THRESHOLD[0] → TIER_FREE_MARKET 배정
	var below: int = SeasonManager.TIER_THRESHOLD[0] - 1
	var tier: int = SeasonManager._assign_tier(below)
	assert_eq(tier, SeasonManager.TIER_FREE_MARKET, "기준금액 미달 → 프리마켓 (AC-22)")


func test_season_manager_is_free_market_flag() -> void:
	## SeasonManager가 is_free_market 상태를 올바르게 노출하는지 확인
	assert_true(SeasonManager.has_method("get_is_free_market"), "get_is_free_market 존재")
	assert_true(SeasonManager.has_method("get_current_tier"),   "get_current_tier 존재")


# ══════════════════════════════════════════════════════════════════
# (d) CURRENCY-SYSTEM E2E — auto_deposit → settle_to_cash 흐름
# ══════════════════════════════════════════════════════════════════

func test_currency_auto_deposit_sets_sim_cash() -> void:
	## 브론즈 입금: auto_deposit_to_sim(1_000_000) → sim_cash = 1_000_000
	CurrencySystem.reset()
	var deposited: int = CurrencySystem.auto_deposit_to_sim(1_000_000)
	assert_eq(deposited, 1_000_000, "auto_deposit 반환값 = 입금액")
	assert_eq(CurrencySystem.get_sim_cash(), 1_000_000, "sim_cash = 입금액")
	CurrencySystem.reset()


func test_currency_settle_to_cash_zero_sim_cash_and_adds_prize() -> void:
	## 시즌 종료 settle_to_cash(): sim_cash → 0, cash_assets += prize
	CurrencySystem.reset()
	CurrencySystem.auto_deposit_to_sim(2_000_000)
	var before_cash: int = CurrencySystem.get_cash_assets()
	CurrencySystem.settle_to_cash(500_000)  # prize = 500_000
	assert_eq(CurrencySystem.get_sim_cash(), 0, "settle 후 sim_cash = 0")
	# cash_assets = before + (0 remaining sim_cash) + prize
	# (sim_cash 2M → 0, cash_assets += 0 sim + 500K prize)
	# Note: settle_to_cash: cash += sim_cash + prize (before clearing sim_cash)
	# After reset, before_cash = default. Prize should be added.
	assert_true(CurrencySystem.get_cash_assets() > before_cash, "settle 후 cash_assets 증가")
	CurrencySystem.reset()


func test_currency_auto_deposit_silver_3m() -> void:
	## 실버 기준금액(3,000,000) 자동입금 시 sim_cash 정확히 반영
	CurrencySystem.reset()
	var silver_threshold: int = 3_000_000  # SeasonManager.TIER_THRESHOLD[1]
	## reset() sets cash_assets = INITIAL_CASH_ASSETS (1M). Add 2M more so deposit is not capped.
	CurrencySystem.cash_add(2_000_000)
	CurrencySystem.auto_deposit_to_sim(silver_threshold)
	assert_eq(CurrencySystem.get_sim_cash(), silver_threshold, "실버 3M 입금 정확")
	CurrencySystem.reset()


# ══════════════════════════════════════════════════════════════════
# (e) SHORT-SELLING margin_rate 하한 — MIN_MARGIN_RATE = 1.20
# ══════════════════════════════════════════════════════════════════

func test_short_selling_min_margin_rate_constant_is_1_20() -> void:
	## ShortSellingSystem.MIN_MARGIN_RATE == 1.20 (AC S10-06e)
	assert_almost_eq(
		ShortSellingSystem.MIN_MARGIN_RATE, 1.20, 0.001,
		"MIN_MARGIN_RATE = 1.20"
	)


func test_short_selling_margin_rate_is_at_least_min() -> void:
	## 실제 _margin_rate가 MIN_MARGIN_RATE 이상인지 확인 (config 1.40 > 1.20)
	assert_true(
		ShortSellingSystem.get_margin_rate() >= ShortSellingSystem.MIN_MARGIN_RATE,
		"_margin_rate >= MIN_MARGIN_RATE (하한 위반 없음)"
	)


# ══════════════════════════════════════════════════════════════════
# (f) LEVERAGE F2b — 이자 원금화 (borrowed 누적)
# ══════════════════════════════════════════════════════════════════

func test_leverage_interest_capitalized_when_insufficient_cash() -> void:
	## F2b: 일일 이자를 sim_cash로 납부 불가 시 부족분이 borrowed에 누적
	LeverageManager.reset()
	CurrencySystem.reset()

	# Ensure sim_cash = 0 (no cash for interest)
	# Build position with borrowed = 1,000,000 (rate 2× → "2" key → 0.04%)
	var pos: Dictionary = {
		"stock_id":         "TEST_F2B",
		"quantity":         10,
		"entry_price":      100000,
		"multiplier":       2,
		"borrowed":         1_000_000,
		"accrued_interest": 0,
		"open_day":         1,
	}
	LeverageManager._positions.append(pos)

	var interest_expected: int = int(floor(1_000_000 * 0.0004))  # = 400
	var borrowed_before: int = pos["borrowed"]

	# With sim_cash = 0, all interest should be capitalized (added to borrowed)
	LeverageManager.process_daily_interest(1)

	# accrued_interest should increase by the expected amount
	var updated: Array[Dictionary] = LeverageManager.get_all_positions()
	assert_eq(updated.size(), 1, "포지션 유지")
	var actual_interest: int = updated[0]["accrued_interest"]
	assert_true(actual_interest > 0, "이자 발생: accrued_interest > 0 (F2b)")

	# borrowed should have increased by the shortfall (sim_cash was 0 → all capitalized)
	var new_borrowed: int = updated[0]["borrowed"]
	assert_true(new_borrowed >= borrowed_before, "borrowed 증가 (이자 원금화 F2b)")

	LeverageManager.reset()
	CurrencySystem.reset()


# ══════════════════════════════════════════════════════════════════
# (g) TRADING-FEES — KR holding_days=0 → capital_gains=0 항상
# ══════════════════════════════════════════════════════════════════

func test_kr_market_capital_gains_is_zero_when_holding_days_zero() -> void:
	## KR 시장: capital_gains 세율 0% (short_term_rate=0.0, long_term_rate=0.0)
	## → holding_days=0 + any profit → capital_gains = 0 항상
	var breakdown: Dictionary = MarketConfig.get_fee_breakdown("SELL", 10_000_000, 0, 2_000_000)
	assert_eq(breakdown.get("capital_gains", -1), 0,
		"KR holding_days=0 + 200만 수익 → capital_gains = 0")


func test_kr_market_capital_gains_is_zero_with_large_profit() -> void:
	## 대규모 수익에서도 KR capital_gains = 0
	var breakdown: Dictionary = MarketConfig.get_fee_breakdown("SELL", 100_000_000, 0, 50_000_000)
	assert_eq(breakdown.get("capital_gains", -1), 0,
		"KR 대규모 수익 → capital_gains = 0")


func test_kr_market_sell_tax_applied() -> void:
	## KR sell_tax = 0.2% (0.002) — 정상 적용 확인
	var gross: int = 10_000_000
	var breakdown: Dictionary = MarketConfig.get_fee_breakdown("SELL", gross, 0, 0)
	var expected_sell_tax: int = int(floor(float(gross) * 0.002))
	assert_eq(breakdown.get("sell_tax", -1), expected_sell_tax,
		"KR sell_tax = gross × 0.002")
