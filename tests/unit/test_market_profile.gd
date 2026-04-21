## Tests for MarketProfile autoload — S10-07.
## Phase 1: market_kr.json 로드 + API 검증
## Phase 3: market_us.json DLC 테스트
## ADR-021: docs/architecture/ADR-021
extends GutTest

# ── Setup ──────────────────────────────────────────────────────────────────

func before_each() -> void:
	# Always reset to KR before each test
	MarketProfile.load_market("KR")


# ── Phase 1: market_kr.json 로드 + API ────────────────────────────────────

func test_load_market_kr_returns_true() -> void:
	var ok: bool = MarketProfile.load_market("KR")
	assert_true(ok, "market_kr.json 로드 성공")


func test_active_market_id_is_kr() -> void:
	assert_eq(MarketProfile.get_active_market_id(), "KR", "활성 시장 = KR")


func test_get_sectors_returns_11_kr_sectors() -> void:
	var sectors: Array[String] = MarketProfile.get_sectors()
	assert_eq(sectors.size(), 11, "KR 섹터 11개")
	assert_true(sectors.has("반도체"), "반도체 포함")
	assert_true(sectors.has("금융"),   "금융 포함")
	assert_true(sectors.has("바이오"), "바이오 포함")


func test_get_etfs_returns_11_etfs() -> void:
	var etfs: Dictionary = MarketProfile.get_etfs()
	assert_eq(etfs.size(), 11, "KR ETF 11개")
	assert_true(etfs.has("ETF_반도체"), "ETF_반도체 존재")
	assert_true(etfs.has("ETF_금융"),   "ETF_금융 존재")


func test_get_etf_sector_mapping() -> void:
	var etfs: Dictionary = MarketProfile.get_etfs()
	assert_eq(str(etfs["ETF_반도체"]["sector"]), "반도체", "ETF_반도체 → 반도체")
	assert_eq(str(etfs["ETF_금융"]["sector"]),   "금융",   "ETF_금융 → 금융")


func test_get_archetype_returns_correct_value() -> void:
	assert_eq(MarketProfile.get_archetype("반도체"), "TECH",       "반도체 → TECH")
	assert_eq(MarketProfile.get_archetype("금융"),   "FINANCE",    "금융 → FINANCE")
	assert_eq(MarketProfile.get_archetype("자동차"), "INDUSTRIAL", "자동차 → INDUSTRIAL")


func test_get_archetype_unknown_returns_empty() -> void:
	assert_eq(MarketProfile.get_archetype("UNKNOWN_SECTOR"), "", "미등록 섹터 → 빈 문자열")


func test_get_sectors_in_archetype_tech() -> void:
	var tech_sectors: Array[String] = MarketProfile.get_sectors_in_archetype("TECH")
	assert_true(tech_sectors.has("반도체"), "TECH ⊃ 반도체")
	assert_true(tech_sectors.has("게임"),   "TECH ⊃ 게임")
	assert_true(tech_sectors.has("2차전지"), "TECH ⊃ 2차전지")


func test_rivalry_weights_sum_to_1_for_all_archetypes() -> void:
	for archetype: String in ["TECH", "INDUSTRIAL", "CONSUMER", "HEALTHCARE", "FINANCE"]:
		var row: Dictionary = MarketProfile.get_rivalry_weights(archetype)
		var total: float = 0.0
		for v: Variant in row.values():
			total += float(v)
		assert_almost_eq(total, 1.0, 0.011, "%s rivalry_weights 합산 = 1.0" % archetype)


func test_get_rotation_params_has_required_keys() -> void:
	var params: Dictionary = MarketProfile.get_rotation_params()
	assert_true(params.has("flow_sensitivity"), "flow_sensitivity 키 존재")
	assert_true(params.has("threshold"),        "threshold 키 존재")
	assert_true(params.has("cooldown_ticks"),   "cooldown_ticks 키 존재")
	assert_true(params.has("inflow_impact"),    "inflow_impact 키 존재")
	assert_true(params.has("outflow_impact"),   "outflow_impact 키 존재")


func test_get_rotation_headline_inflow_returns_valid_key() -> void:
	var key: String = MarketProfile.get_rotation_headline("inflow")
	assert_true(key.begins_with("ROTATION_KR_INFLOW_"),
		"inflow 헤드라인 키 = ROTATION_KR_INFLOW_*")


func test_get_rotation_headline_outflow_returns_valid_key() -> void:
	var key: String = MarketProfile.get_rotation_headline("outflow")
	assert_true(key.begins_with("ROTATION_KR_OUTFLOW_"),
		"outflow 헤드라인 키 = ROTATION_KR_OUTFLOW_*")


func test_get_trading_param_commission() -> void:
	var commission: Variant = MarketProfile.get_trading_param("commission")
	assert_almost_eq(float(commission), 0.00015, 0.000001, "commission = 0.00015")


func test_get_trading_param_sell_tax() -> void:
	var sell_tax: Variant = MarketProfile.get_trading_param("sell_tax")
	assert_almost_eq(float(sell_tax), 0.002, 0.0001, "sell_tax = 0.002")


func test_get_trading_param_margin_rate_min() -> void:
	var floor_val: Variant = MarketProfile.get_trading_param("margin_rate_min")
	assert_almost_eq(float(floor_val), 1.20, 0.001, "margin_rate_min = 1.20")


func test_get_calendar_param_report_cycle() -> void:
	var cycle: Variant = MarketProfile.get_calendar_param("report_cycle_seasons")
	assert_eq(int(cycle), 3, "report_cycle_seasons = 3")


func test_get_calendar_param_report_type_sequence() -> void:
	var seq: Variant = MarketProfile.get_calendar_param("report_type_sequence")
	assert_true(seq is Array, "report_type_sequence is Array")
	assert_eq((seq as Array).size(), 4, "4개 보고서 타입")


func test_get_ending_param_bankruptcy_visual() -> void:
	var visual: Variant = MarketProfile.get_ending_param("bankruptcy", "visual")
	assert_eq(str(visual), "res://assets/endings/kr_hangang.png",
		"bankruptcy visual = kr_hangang.png")


func test_get_ending_param_bankruptcy_is_bad_ending() -> void:
	var is_bad: Variant = MarketProfile.get_ending_param("bankruptcy", "is_bad_ending")
	assert_true(bool(is_bad), "bankruptcy is_bad_ending = true")


func test_get_ending_param_win_is_not_bad_ending() -> void:
	var is_bad: Variant = MarketProfile.get_ending_param("win", "is_bad_ending")
	assert_false(bool(is_bad), "win is_bad_ending = false")


func test_get_ending_param_unknown_returns_null() -> void:
	var result: Variant = MarketProfile.get_ending_param("UNKNOWN_ENDING", "visual")
	assert_eq(result, null, "미등록 엔딩 → null")


func test_get_ending_ids_contains_all_3_kr_endings() -> void:
	var ids: Array[String] = MarketProfile.get_ending_ids()
	assert_true(ids.has("bankruptcy"),     "bankruptcy 엔딩 존재")
	assert_true(ids.has("leverage_crash"), "leverage_crash 엔딩 존재")
	assert_true(ids.has("win"),            "win 엔딩 존재")


func test_get_active_returns_full_profile() -> void:
	var profile: Dictionary = MarketProfile.get_active()
	assert_true(profile.has("market_id"), "market_id 키 존재")
	assert_true(profile.has("sectors"),   "sectors 키 존재")
	assert_true(profile.has("etfs"),      "etfs 키 존재")
	assert_true(profile.has("endings"),   "endings 키 존재")


# ── Phase 3: market_us.json DLC 테스트 ──────────────────────────────────────

func test_load_market_us_returns_true() -> void:
	var ok: bool = MarketProfile.load_market("US")
	assert_true(ok, "market_us.json 로드 성공 (DLC stub)")


func test_us_market_id_is_us() -> void:
	MarketProfile.load_market("US")
	assert_eq(MarketProfile.get_active_market_id(), "US", "활성 시장 = US (after load)")
	MarketProfile.load_market("KR")  # restore


func test_us_sectors_are_different_from_kr() -> void:
	MarketProfile.load_market("US")
	var us_sectors: Array[String] = MarketProfile.get_sectors()
	assert_false(us_sectors.has("반도체"), "US 섹터에 반도체 없음 (KR 데이터 혼입 없음)")
	assert_true(us_sectors.has("Tech"),    "US 섹터 = Tech")
	MarketProfile.load_market("KR")  # restore


func test_us_report_type_sequence_is_quarterly() -> void:
	MarketProfile.load_market("US")
	var seq: Variant = MarketProfile.get_calendar_param("report_type_sequence")
	assert_eq(str((seq as Array)[0]), "Q1", "US 첫 보고서 = Q1")
	assert_eq(str((seq as Array)[3]), "Q4", "US 네 번째 보고서 = Q4")
	MarketProfile.load_market("KR")  # restore


func test_load_nonexistent_market_returns_false() -> void:
	var ok: bool = MarketProfile.load_market("ZZ")
	assert_false(ok, "존재하지 않는 시장 로드 → false")
	# Profile should not have changed to ZZ
	# After failed load, _active_profile might be empty or previous — either is acceptable
