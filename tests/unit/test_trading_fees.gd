## Unit tests for MarketConfig fee calculation system.
## GUT test suite. See: design/gdd/trading-fees.md §8 AC.
extends GutTest

# ── Helpers ──

## Reset MarketConfig internal state by reloading active market params directly.
## Tests manipulate _active dict to simulate different markets without file I/O.
func _set_market(params: Dictionary) -> void:
	MarketConfig._active = params


func _kr_params() -> Dictionary:
	return {
		"buy_tax": 0.0,
		"sell_tax": 0.002,
		"commission": 0.00015,
		"capital_gains": {
			"short_term_rate": 0.0,
			"long_term_rate": 0.0,
			"threshold_days": 365,
		},
	}


func _us_params() -> Dictionary:
	return {
		"buy_tax": 0.0,
		"sell_tax": 0.0,
		"commission": 0.0005,
		"capital_gains": {
			"short_term_rate": 0.22,
			"long_term_rate": 0.15,
			"threshold_days": 365,
		},
	}


func before_each() -> void:
	_set_market(_kr_params())


# ── AC-01: KR 매도 수수료 + 거래세 정확 차감 ──────────────────────────────

func test_kr_sell_fee_deduction() -> void:
	# Arrange — 100만원 매도
	var gross: int = 1_000_000
	# Act
	var result: Dictionary = MarketConfig.get_fee_breakdown("SELL", gross, 0, 0)
	# Assert
	# sell_tax = 1,000,000 × 0.002 = 2,000원 (floor)
	# commission = 1,000,000 × 0.00015 = 150원 (floor)
	# net = 1,000,000 - 2,000 - 150 = 997,850원
	assert_eq(result["sell_tax"], 2000, "sell_tax 2000원")
	assert_eq(result["commission"], 150, "commission 150원")
	assert_eq(result["capital_gains"], 0, "capital_gains 0원 (KR=0)")
	assert_eq(result["net"], 997_850, "net 997,850원")


# ── AC-02: KR 매수 수수료만 추가 차감 ────────────────────────────────────

func test_kr_buy_fee_deduction() -> void:
	# Arrange — 100만원 매수
	var gross: int = 1_000_000
	# Act
	var result: Dictionary = MarketConfig.get_fee_breakdown("BUY", gross, 0, 0)
	# Assert
	# buy_tax = 0
	# commission = 1,000,000 × 0.00015 = 150원
	# net = -(1,000,000 + 0 + 150) = -1,000,150원
	assert_eq(result["buy_tax"], 0, "buy_tax 0원")
	assert_eq(result["commission"], 150, "commission 150원")
	assert_eq(result["net"], -1_000_150, "net -1,000,150원")


## get_buy_cost 검증 — 매수 총비용 (수수료 포함)
func test_kr_get_buy_cost() -> void:
	var gross: int = 1_000_000
	var cost: int = MarketConfig.get_buy_cost(gross)
	# commission = floor(1,000,000 × 0.00015) = floor(150.0) = 150
	# buy_cost = 1,000,000 + 0 + 150 = 1,000,150
	assert_eq(cost, 1_000_150, "buy_cost 1,000,150원")


# ── AC-03: capital_gains_rate=0 시 양도세 없음 ───────────────────────────

func test_zero_capital_gains() -> void:
	var result: Dictionary = MarketConfig.get_fee_breakdown("SELL", 1_000_000, 0, 500_000)
	assert_eq(result["capital_gains"], 0, "KR 양도세 = 0")
	assert_eq(result["net"], 997_850, "net은 거래세+수수료만 차감")


# ── AC-04: 손절 매도(실현이익 < 0) 시 양도세 = 0 ─────────────────────────

func test_loss_sell_no_capital_gains() -> void:
	var result: Dictionary = MarketConfig.get_fee_breakdown("SELL", 1_000_000, 0, -200_000)
	assert_eq(result["capital_gains"], 0, "손절 매도 양도세 = 0")


# ── AC-06: US 가상 설정 short_rate=0.22 → 이익의 22% 즉시 차감 ────────────

func test_us_capital_gains_immediate() -> void:
	_set_market(_us_params())
	# Arrange — 200만원 매도, 실현이익 100만원, 보유 30일(단기)
	var gross: int = 2_000_000
	var realized_profit: int = 1_000_000
	var holding_days: int = 30  # < 365 → short term
	# Act
	var result: Dictionary = MarketConfig.get_fee_breakdown(
		"SELL", gross, holding_days, realized_profit
	)
	# Assert
	# capital_gains = floor(1,000,000 × 0.22) = 220,000원
	# commission = floor(2,000,000 × 0.0005) = 1,000원
	# sell_tax = 0 (US)
	# net = 2,000,000 - 0 - 1,000 - 220,000 = 1,779,000원
	assert_eq(result["capital_gains"], 220_000, "US 단기 양도세 22% = 220,000원")
	assert_eq(result["commission"], 1_000, "US 수수료 1,000원")
	assert_eq(result["sell_tax"], 0, "US 거래세 없음")
	assert_eq(result["net"], 1_779_000, "US 실수령 1,779,000원")


## US 장기 보유(≥365일) → 15% 세율 적용
func test_us_long_term_capital_gains() -> void:
	_set_market(_us_params())
	var realized_profit: int = 1_000_000
	var result: Dictionary = MarketConfig.get_fee_breakdown(
		"SELL", 2_000_000, 365, realized_profit
	)
	# long_term_rate = 0.15 → floor(1,000,000 × 0.15) = 150,000원
	assert_eq(result["capital_gains"], 150_000, "US 장기 양도세 15% = 150,000원")


# ── AC-08: 잔고 부족 시 주문 거부 — get_buy_cost 포함 가격 검증 ───────────

func test_insufficient_balance_rejected() -> void:
	# Arrange — sim_cash 정확히 100만원이면 buy_cost=1,000,150원이므로 부족
	CurrencySystem.reset()
	CurrencySystem.init_first_season(1_000_000)
	# Act — 현금을 딱 예수금(sim_cash)으로만 채워 limit 주문 제출
	# 수수료 포함 총비용 = get_buy_cost(1,000,000) = 1,000,150 > 1,000,000 → REJECTED
	var cost: int = MarketConfig.get_buy_cost(1_000_000)
	var can_deduct: bool = CurrencySystem.sim_deduct(cost)
	assert_false(can_deduct, "수수료 포함 총비용이 잔고 초과 → 차감 실패")


# ── fee_breakdown 딕셔너리 키 완전성 ─────────────────────────────────────

func test_fee_breakdown_keys_complete() -> void:
	var result: Dictionary = MarketConfig.get_fee_breakdown("SELL", 1_000_000, 0, 0)
	assert_true(result.has("commission"),    "commission 키 존재")
	assert_true(result.has("buy_tax"),       "buy_tax 키 존재")
	assert_true(result.has("sell_tax"),      "sell_tax 키 존재")
	assert_true(result.has("capital_gains"), "capital_gains 키 존재")
	assert_true(result.has("net"),           "net 키 존재")


## BUY breakdown 키 완전성
func test_buy_fee_breakdown_keys_complete() -> void:
	var result: Dictionary = MarketConfig.get_fee_breakdown("BUY", 1_000_000, 0, 0)
	assert_true(result.has("commission"), "commission 키 존재")
	assert_true(result.has("buy_tax"),    "buy_tax 키 존재")
	assert_true(result.has("sell_tax"),   "sell_tax 키 존재")
	assert_true(result.has("net"),        "net 키 존재")


# ── get_active_market ────────────────────────────────────────────────────

func test_get_active_market_returns_string() -> void:
	var market: String = MarketConfig.get_active_market()
	assert_eq(market, "KR", "기본 활성 시장 = KR")
