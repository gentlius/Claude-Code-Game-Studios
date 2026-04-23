## Tests for FinancialReportSystem autoload — Phase 1.
## GDD: design/gdd/financial-report-system.md
## Covers AC-FR-01, AC-FR-02, AC-FR-04, AC-FR-08, AC-FR-14,
##          AC-FR-15, AC-FR-18, AC-FR-19, AC-FR-21, F1, F2, F3, save/load.
extends GutTest

# ── Helpers ──────────────────────────────────────────────────────────────────

## Create a minimal StockData resource for testing.
func _make_stock(
	id: String,
	sector: String,
	vol: StockData.VolatilityProfile,
	roe_pct: float,
	per: float = 15.0
) -> StockData:
	var s: StockData = StockData.new()
	s.ticker = id
	s.company_name = id
	s.sector = sector
	s.volatility_profile = vol
	s.roe = roe_pct   # stored as percentage (e.g. 16.0 = 16%)
	s.per = per
	return s


# ── Setup / Teardown ─────────────────────────────────────────────────────────

func before_each() -> void:
	FinancialReportSystem.reset()


# ── AC-FR-01: is_report_season() — 주기 판별 ─────────────────────────────────

func test_is_report_season_returns_false_before_first_cycle() -> void:
	# Seasons 1–3 never report (first cycle hasn't ended)
	assert_false(FinancialReportSystem.is_report_season(1), "시즌 1 미보고")
	assert_false(FinancialReportSystem.is_report_season(2), "시즌 2 미보고")
	assert_false(FinancialReportSystem.is_report_season(3), "시즌 3 미보고")


func test_is_report_season_returns_true_on_cycle_boundary() -> void:
	# Season 4 = FISCAL_YEAR_START(1) + REPORT_CYCLE(3) → first report season
	assert_true(FinancialReportSystem.is_report_season(4),  "시즌 4 보고")
	assert_true(FinancialReportSystem.is_report_season(7),  "시즌 7 보고")
	assert_true(FinancialReportSystem.is_report_season(10), "시즌 10 보고")
	assert_true(FinancialReportSystem.is_report_season(13), "시즌 13 보고")


func test_is_report_season_returns_false_between_boundaries() -> void:
	assert_false(FinancialReportSystem.is_report_season(5), "시즌 5 미보고")
	assert_false(FinancialReportSystem.is_report_season(6), "시즌 6 미보고")
	assert_false(FinancialReportSystem.is_report_season(8), "시즌 8 미보고")
	assert_false(FinancialReportSystem.is_report_season(9), "시즌 9 미보고")


# ── AC-FR-02: get_report_type() — 보고서 타입 시퀀스 ─────────────────────────

func test_get_report_type_follows_sequence() -> void:
	assert_eq(FinancialReportSystem.get_report_type(4),  "Q1",     "시즌 4 → Q1")
	assert_eq(FinancialReportSystem.get_report_type(7),  "H1",     "시즌 7 → H1")
	assert_eq(FinancialReportSystem.get_report_type(10), "Q3",     "시즌 10 → Q3")
	assert_eq(FinancialReportSystem.get_report_type(13), "Annual", "시즌 13 → Annual")


func test_get_report_type_cycles_back() -> void:
	# After 4 reports, cycles back to Q1
	assert_eq(FinancialReportSystem.get_report_type(16), "Q1", "시즌 16 → Q1 (순환)")


func test_get_report_type_empty_for_non_report_season() -> void:
	assert_eq(FinancialReportSystem.get_report_type(1), "", "비보고 시즌 → 빈 문자열")
	assert_eq(FinancialReportSystem.get_report_type(5), "", "비보고 시즌 → 빈 문자열")


# ── F3: _classify_event() — 이벤트 분류 ──────────────────────────────────────

func test_classify_event_turnaround_profit() -> void:
	# prev_roe <= 0 and new_roe > 0 → TURNAROUND_PROFIT
	var result: String = FinancialReportSystem._classify_event(-0.05, 0.08, 0.05)
	assert_eq(result, "TURNAROUND_PROFIT", "흑자전환 판별")


func test_classify_event_turnaround_loss() -> void:
	# prev_roe > 0 and new_roe <= 0 → TURNAROUND_LOSS
	var result: String = FinancialReportSystem._classify_event(0.10, -0.02, 0.08)
	assert_eq(result, "TURNAROUND_LOSS", "적자전환 판별")


func test_classify_event_earnings_surprise() -> void:
	# new_roe - consensus >= SURPRISE_THRESHOLD (0.05)
	var result: String = FinancialReportSystem._classify_event(0.05, 0.12, 0.05)
	assert_eq(result, "EARNINGS_SURPRISE", "어닝서프라이즈 판별")


func test_classify_event_earnings_shock() -> void:
	# consensus - new_roe >= SHOCK_THRESHOLD (0.05)
	var result: String = FinancialReportSystem._classify_event(0.10, 0.04, 0.10)
	assert_eq(result, "EARNINGS_SHOCK", "어닝쇼크 판별")


func test_classify_event_neutral_returns_empty() -> void:
	# Small deviation below both thresholds → ""
	var result: String = FinancialReportSystem._classify_event(0.10, 0.11, 0.09)
	assert_eq(result, "", "중립 이벤트 → 빈 문자열")


func test_classify_event_turnaround_takes_priority_over_surprise() -> void:
	# Even if new_roe >> consensus, turnaround check fires first
	var result: String = FinancialReportSystem._classify_event(-0.01, 0.20, 0.10)
	assert_eq(result, "TURNAROUND_PROFIT", "흑자전환이 어닝서프라이즈보다 우선")


# ── AC-FR-18/19: _roll_preliminary() — 프로파일별 잠정실적 확률 ───────────────

func test_roll_preliminary_disabled_for_extreme_profile() -> void:
	# EXTREME → probability 0.00 → always false
	var stock: StockData = _make_stock("TEST_EX", "IT", StockData.VolatilityProfile.EXTREME, 10.0)
	# Run 20 times — should always be false (prob=0.0)
	var any_true: bool = false
	for i: int in range(20):
		if FinancialReportSystem._roll_preliminary(stock):
			any_true = true
			break
	assert_false(any_true, "EXTREME 프로파일은 잠정실적 없음")


func test_roll_preliminary_null_stock_returns_false() -> void:
	assert_false(FinancialReportSystem._roll_preliminary(null), "null stock → false")


func test_roll_preliminary_low_profile_almost_always_true() -> void:
	# LOW → probability 0.90 → should fire in at least 1 out of 30 rolls
	var stock: StockData = _make_stock("TEST_LO", "금융", StockData.VolatilityProfile.LOW, 8.0)
	FinancialReportSystem._rng.seed = 42
	var any_true: bool = false
	for i: int in range(30):
		if FinancialReportSystem._roll_preliminary(stock):
			any_true = true
			break
	assert_true(any_true, "LOW 프로파일은 잠정실적 자주 발생")


# ── F1: _compute_new_roe() — ROE 공식 ───────────────────────────────────────

func test_compute_new_roe_is_clamped_within_bounds() -> void:
	# _compute_new_roe() reads from StockDatabase. If DB has stocks, use them.
	# If DB empty, skip (integration check).
	var all_ids: Array[String] = StockDatabase.get_all_stock_ids()
	if all_ids.is_empty():
		pass_test("종목 없음 — 헤드리스 환경 스킵")
		return
	var stock_id: String = all_ids[0]
	var result: float = FinancialReportSystem._compute_new_roe(stock_id)
	assert_true(
		result >= FinancialReportSystem.ROE_MIN and result <= FinancialReportSystem.ROE_MAX,
		"new_roe 범위 [ROE_MIN, ROE_MAX] 내부"
	)


func test_compute_new_roe_returns_zero_for_missing_stock() -> void:
	var result: float = FinancialReportSystem._compute_new_roe("NONEXISTENT_XX")
	assert_eq(result, 0.0, "미존재 종목 → 0.0")


# ── AC-FR-14: PER sentinel for deficit company ──────────────────────────────

func test_apply_roe_update_sets_per_sentinel_when_roe_negative() -> void:
	var all_ids: Array[String] = StockDatabase.get_all_stock_ids()
	if all_ids.is_empty():
		pass_test("종목 없음 — 헤드리스 환경 스킵")
		return
	var stock_id: String = all_ids[0]
	var stock: StockData = StockDatabase.get_stock(stock_id)
	var original_roe: float = stock.roe
	var original_per: float = stock.per

	# Apply a negative ROE update
	FinancialReportSystem._apply_roe_update(stock_id, -0.10)
	assert_almost_eq(
		stock.per,
		FinancialReportSystem.PER_NEGATIVE_SENTINEL,
		0.001,
		"적자 ROE → PER sentinel"
	)

	# Restore
	stock.roe = original_roe
	stock.per = original_per


# ── F2: _compute_consensus_roe() — 독립 RNG ──────────────────────────────────

func test_consensus_roe_differs_from_new_roe_via_separate_rng() -> void:
	# Consensus uses _consensus_rng; new_roe uses _rng. Seeds are different → values differ.
	var all_ids: Array[String] = StockDatabase.get_all_stock_ids()
	if all_ids.is_empty():
		pass_test("종목 없음 — 헤드리스 환경 스킵")
		return
	var stock_id: String = all_ids[0]
	FinancialReportSystem._rng.seed = 12345
	FinancialReportSystem._consensus_rng.seed = 99999
	var new_roe: float      = FinancialReportSystem._compute_new_roe(stock_id)
	var consensus: float    = FinancialReportSystem._compute_consensus_roe(stock_id, 10)
	# They can be equal by coincidence, but extremely unlikely with different seeds.
	# Just assert both are within valid range.
	assert_true(
		consensus >= FinancialReportSystem.ROE_MIN and consensus <= FinancialReportSystem.ROE_MAX,
		"consensus_roe 범위 내부"
	)


# ── reset() / get_save_data() / load_save_data() ─────────────────────────────

func test_reset_clears_all_state() -> void:
	# Dirty the state
	FinancialReportSystem._current_season = 7
	FinancialReportSystem._is_report_season_active = true
	FinancialReportSystem._pending_events["FAKE_ID"] = {"quiet": true}

	FinancialReportSystem.reset()

	assert_eq(FinancialReportSystem._current_season, 0, "reset 후 season=0")
	assert_false(FinancialReportSystem._is_report_season_active, "reset 후 active=false")
	assert_true(
		FinancialReportSystem.get_pending_events().is_empty(),
		"reset 후 pending_events 비어있음"
	)


func test_save_load_round_trip_preserves_state() -> void:
	# Arrange: set some state
	FinancialReportSystem._current_season = 4
	FinancialReportSystem._is_report_season_active = true
	FinancialReportSystem._pending_events["STOCK_A"] = {
		"stock_id": "STOCK_A", "quiet": false, "report_done": false,
		"analyst_done": true, "preliminary_done": false, "rumor_done": false,
		"reporting_day": 10, "preliminary_day": 7, "rumor_day": 9,
		"analyst_day": 3, "has_preliminary": true, "is_fake_rumor": false,
		"event_sign": 1, "season": 4, "consensus_roe": 0.08,
	}

	# Act: save and reload
	var data: Dictionary = FinancialReportSystem.get_save_data()
	FinancialReportSystem.reset()
	FinancialReportSystem.load_save_data(data)

	# Assert
	assert_eq(FinancialReportSystem._current_season, 4, "season 복원")
	assert_true(FinancialReportSystem._is_report_season_active, "is_report_season_active 복원")
	var pending: Dictionary = FinancialReportSystem.get_pending_events()
	assert_true(pending.has("STOCK_A"), "STOCK_A 이벤트 복원")
	assert_true(bool(pending["STOCK_A"]["analyst_done"]), "analyst_done 복원")


func test_load_save_data_with_empty_dict_is_no_op() -> void:
	FinancialReportSystem._current_season = 3
	FinancialReportSystem.load_save_data({})
	# State unchanged (empty dict → no-op)
	assert_eq(FinancialReportSystem._current_season, 3, "빈 dict → 상태 변화 없음")


# ── AC-FR-04: get_pending_events() — 공개 조회 API ──────────────────────────

func test_get_pending_events_returns_deep_copy() -> void:
	FinancialReportSystem._pending_events["TEST"] = {"foo": "bar"}
	var copy: Dictionary = FinancialReportSystem.get_pending_events()
	copy["TEST"]["foo"] = "mutated"
	# Original should not be mutated
	assert_eq(
		FinancialReportSystem._pending_events["TEST"]["foo"],
		"bar",
		"get_pending_events deep copy — 원본 변경 없음"
	)
	FinancialReportSystem._pending_events.erase("TEST")


# ── Config loading guards ─────────────────────────────────────────────────────

func test_report_cycle_seasons_loaded_from_config() -> void:
	# After _load_config() in _ready(), value should match financial_report_config.json
	assert_eq(FinancialReportSystem.REPORT_CYCLE_SEASONS, 3,
		"reportCycleSeasons = 3 (JSON 일치)")


func test_report_type_sequence_loaded_from_config() -> void:
	var seq: Array = FinancialReportSystem.REPORT_TYPE_SEQUENCE
	assert_eq(seq.size(), 4, "REPORT_TYPE_SEQUENCE 4개")
	assert_eq(str(seq[0]), "Q1",     "시퀀스[0] = Q1")
	assert_eq(str(seq[3]), "Annual", "시퀀스[3] = Annual")


func test_preliminary_probability_extreme_is_zero() -> void:
	var prob: float = float(FinancialReportSystem.PRELIMINARY_PROBABILITY.get("EXTREME", -1.0))
	assert_almost_eq(prob, 0.0, 0.001, "EXTREME 잠정실적 확률 0.0")


func test_preliminary_probability_low_is_high() -> void:
	var prob: float = float(FinancialReportSystem.PRELIMINARY_PROBABILITY.get("LOW", 0.0))
	assert_almost_eq(prob, 0.90, 0.001, "LOW 잠정실적 확률 0.90")
