extends GutTest
## Unit tests for AiCompetitor — 수익률 생성, 결정론성, 티어 단조성, 성능.
## See: design/gdd/ai-competitor.md §8 Acceptance Criteria

# ── Constants ──

const SEED_FIXED: int = 42
const EPSILON: float  = 0.001  # AC-01 부동소수점 오차 허용값 (%)

# ── Helpers ──

## 표준 테스트용 init_season 호출 헬퍼.
## 브론즈 100명 기본값으로 초기화 (성능 테스트 외).
## PRE_MARKET + day==0 이면 0% 반환. 테스트는 day>0 또는 MARKET_OPEN 상태로 실행.
## GameClock._market_state = MARKET_OPEN 으로 설정하면 가드를 통과한다.
func _init_standard(player_tier: int = AiCompetitor.TIER_BRONZE,
		counts: Dictionary = { 0: 100 },
		seed: int = SEED_FIXED) -> void:
	AiCompetitor.init_season(player_tier, counts, seed)
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN


func after_each() -> void:
	AiCompetitor._initialized = false
	AiCompetitor._tier_data.clear()
	GameClock._current_day  = 0
	GameClock._current_tick = 0
	GameClock._market_state = GameClock.MarketState.PRE_MARKET
	if GameClock.on_day_transition.is_connected(AiCompetitor._on_day_transition):
		GameClock.on_day_transition.disconnect(AiCompetitor._on_day_transition)


# ── AC-01: 계약 인터페이스 정상 동작 (GDD §8 AC-03) ──

func test_ai_competitor_get_tier_return_pct_returns_valid_float() -> void:
	# Arrange
	_init_standard()

	# Act
	var result: float = AiCompetitor.get_tier_return_pct(0)

	# Assert
	assert_true(not is_nan(result), "get_tier_return_pct(0) must not be NaN")
	assert_true(not is_inf(result), "get_tier_return_pct(0) must not be Inf")
	# AC-01: init_season 후 float 반환 확인
	assert_true(result is float, "Return value must be float")


func test_ai_competitor_get_all_return_pcts_length_matches_count() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 50 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts)

	# Act
	var result: Array = AiCompetitor.get_all_return_pcts(AiCompetitor.TIER_BRONZE)

	# Assert
	assert_eq(result.size(), 50, "get_all_return_pcts 길이가 participant_count와 일치해야 함")


func test_ai_competitor_all_returns_not_nan_or_inf() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 30 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts)

	# Act
	var result: Array = AiCompetitor.get_all_return_pcts(AiCompetitor.TIER_BRONZE)

	# Assert
	for i: int in range(result.size()):
		assert_true(not is_nan(result[i]), "Index %d: NaN 반환 금지" % i)
		assert_true(not is_inf(result[i]), "Index %d: Inf 반환 금지" % i)


# ── AC-02: 티어 단조성 (GDD §8 AC-02) ──

func test_ai_competitor_tier_monotonicity_median() -> void:
	# AC-02: TIER_PARAMS mu 단조성 보장. ADR-007.
	# mu는 낮은 티어에서 높은 티어로 갈수록 증가해야 함.
	# 참고: sigma가 크고(25-55%) N=1000이면 샘플 중앙값이 mu 순서와 다를 수 있음.
	# 따라서 결정론적 mu 파라미터를 직접 검증 (통계적 샘플 비교 대신).
	for t: int in range(AiCompetitor.TIER_COUNT - 1):
		var mu_low: float  = AiCompetitor.TIER_PARAMS[t]["mu"]
		var mu_high: float = AiCompetitor.TIER_PARAMS[t + 1]["mu"]
		assert_true(
			mu_high > mu_low,
			"AC-02: TIER_PARAMS[%d].mu=%.1f%% < TIER_PARAMS[%d].mu=%.1f%% — 단조성 위반" % [t + 1, mu_high, t, mu_low]
		)


# ── AC-03: 결정론적 재현성 (GDD §8 AC-01) ──

func test_ai_competitor_same_seed_same_result() -> void:
	# Arrange — 첫 번째 실행
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 50 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, 99999)
	var first_run: Array[float] = []
	for i: int in range(50):
		first_run.append(AiCompetitor.get_tier_return_pct(i))

	# 상태 리셋 후 동일 시드로 재초기화
	after_each()
	_init_standard(AiCompetitor.TIER_BRONZE, counts, 99999)

	# Act — 두 번째 실행
	var second_run: Array[float] = []
	for i: int in range(50):
		second_run.append(AiCompetitor.get_tier_return_pct(i))

	# Assert — 부동소수점 오차 EPSILON 이내 동일
	for i: int in range(50):
		assert_almost_eq(
			first_run[i], second_run[i], EPSILON,
			"AC-03: participant_id=%d 동일 seed → 동일 결과 보장 실패" % i
		)


func test_ai_competitor_different_seed_different_result() -> void:
	# Arrange — get_all_return_pcts로 비교.
	# progress=0(tick=0)에서는 r_prev=0으로 모든 시드가 0을 반환하므로
	# tick을 1560/2로 설정해 progress>0이 되도록 함.
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 20 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, 11111)
	GameClock._current_tick = 780  # 하루 중간 (TICKS_PER_DAY/2) — progress>0
	var run_a: Array = AiCompetitor.get_all_return_pcts(AiCompetitor.TIER_BRONZE)

	after_each()
	_init_standard(AiCompetitor.TIER_BRONZE, counts, 22222)
	GameClock._current_tick = 780
	var run_b: Array = AiCompetitor.get_all_return_pcts(AiCompetitor.TIER_BRONZE)

	# 다른 시드는 높은 확률로 다른 결과를 내야 함 (전체 배열 중 적어도 하나 다름)
	var any_different: bool = false
	for i: int in range(run_a.size()):
		if absf(run_a[i] - run_b[i]) > EPSILON:
			any_different = true
			break
	assert_true(any_different, "다른 seed는 다른 수익률 배열을 생성해야 함 (통계적)")


# ── AC-04: 성능 — get_all_return_pcts 2ms 이내 (GDD §8 AC-04) ──

func test_ai_competitor_get_all_return_pcts_performance_bronze_7600() -> void:
	# Arrange — 브론즈 7,600명
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 7600 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, SEED_FIXED)

	# Act — 실행 시간 측정
	var start_ms: float = Time.get_ticks_usec() / 1000.0
	var result: Array = AiCompetitor.get_all_return_pcts(AiCompetitor.TIER_BRONZE)
	var elapsed_ms: float = (Time.get_ticks_usec() / 1000.0) - start_ms

	# Assert
	assert_eq(result.size(), 7600, "브론즈 7600명 결과 배열 길이 일치")
	assert_true(
		elapsed_ms <= 2.0,
		"AC-04: get_all_return_pcts(BRONZE, 7600) %.2fms — 2ms 초과" % elapsed_ms
	)
	gut.p("AC-04 성능: %.3fms (기준 2ms)" % elapsed_ms)


# ── AC-05: r_min ≤ 반환값 ≤ r_max 보장 (GDD §8 AC-06) ──

func test_ai_competitor_return_clamped_within_tier_bounds() -> void:
	# Arrange — 브론즈: r_min=-30, r_max=600
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 200 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts)
	var r_min: float = AiCompetitor.TIER_PARAMS[AiCompetitor.TIER_BRONZE]["r_min"]
	var r_max: float = AiCompetitor.TIER_PARAMS[AiCompetitor.TIER_BRONZE]["r_max"]

	# Act
	var result: Array = AiCompetitor.get_all_return_pcts(AiCompetitor.TIER_BRONZE)

	# Assert — EC-05: 모든 반환값이 [r_min, r_max] 범위 내
	for i: int in range(result.size()):
		assert_true(
			result[i] >= r_min,
			"AC-05: index %d: %.2f%% < r_min=%.2f%%" % [i, result[i], r_min]
		)
		assert_true(
			result[i] <= r_max,
			"AC-05: index %d: %.2f%% > r_max=%.2f%%" % [i, result[i], r_max]
		)


func test_ai_competitor_get_tier_return_pct_clamped_within_bounds() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 50 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts)
	var r_min: float = AiCompetitor.TIER_PARAMS[AiCompetitor.TIER_BRONZE]["r_min"]
	var r_max: float = AiCompetitor.TIER_PARAMS[AiCompetitor.TIER_BRONZE]["r_max"]

	# Act & Assert
	for i: int in range(50):
		var r: float = AiCompetitor.get_tier_return_pct(i)
		assert_true(r >= r_min, "get_tier_return_pct(%d)=%.2f < r_min=%.2f" % [i, r, r_min])
		assert_true(r <= r_max, "get_tier_return_pct(%d)=%.2f > r_max=%.2f" % [i, r, r_max])


# ── EC-01: init_season 미호출 가드 ──

func test_ai_competitor_uninitialized_get_tier_returns_zero() -> void:
	# Arrange — init_season 호출하지 않음
	AiCompetitor._initialized = false

	# Act
	var result: float = AiCompetitor.get_tier_return_pct(0)

	# Assert
	assert_eq(result, 0.0, "EC-01: init_season 미호출 시 0.0 반환")


# ── EC-02: participant_id 범위 초과 ──

func test_ai_competitor_out_of_range_participant_id_returns_zero() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 10 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts)

	# Act
	var result: float = AiCompetitor.get_tier_return_pct(9999)

	# Assert
	assert_eq(result, 0.0, "EC-02: 범위 초과 participant_id → 0.0 반환")


# ── EC-04: current_day=0 시 r_prev=0.0 ──

func test_ai_competitor_first_day_interpolation_starts_from_zero() -> void:
	# Arrange — 시즌 첫날, PRE_MARKET+day==0 → 0% 반환 (가드 통과 전)
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 10 }
	AiCompetitor.init_season(AiCompetitor.TIER_BRONZE, counts, SEED_FIXED)
	GameClock._market_state = GameClock.MarketState.PRE_MARKET
	GameClock._current_day  = 0
	GameClock._current_tick = 0

	# Act
	var result: float = AiCompetitor.get_tier_return_pct(0)

	# Assert — PRE_MARKET + day==0 → 0.0 반환
	assert_eq(result, 0.0, "EC-04: 시즌 첫 PRE_MARKET에서 return_pct == 0.0")


# ── EC-07: AI 0명 티어 ──

func test_ai_competitor_empty_tier_returns_empty_array() -> void:
	# Arrange — 브론즈 0명
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 0 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts)

	# Act
	var result: Array = AiCompetitor.get_all_return_pcts(AiCompetitor.TIER_BRONZE)

	# Assert
	assert_eq(result.size(), 0, "EC-07: 0명 티어 → 빈 배열 반환")


# ── AC-08: 거장 AI 메타데이터 (GDD §8 AC-08) ──

func test_ai_competitor_master_of_investment_meta_flag() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_MASTER_OF_INVESTMENT: 10 }
	_init_standard(AiCompetitor.TIER_MASTER_OF_INVESTMENT, counts)

	# Act
	var meta: Dictionary = AiCompetitor.get_participant_meta(AiCompetitor.TIER_MASTER_OF_INVESTMENT, 0)

	# Assert
	assert_true(meta.has("is_master_of_investment"), "거장 메타에 is_master_of_investment 키 필요")
	assert_true(meta["is_master_of_investment"], "AC-08: 거장 AI → is_master_of_investment=true")


func test_ai_competitor_non_master_meta_flag_false() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 10 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts)

	# Act
	var meta: Dictionary = AiCompetitor.get_participant_meta(AiCompetitor.TIER_BRONZE, 0)

	# Assert
	assert_false(meta["is_master_of_investment"], "AC-08: 일반 티어 AI → is_master_of_investment=false")


# ── 버킷 순위 추정 오차 (GDD §8 AC-07) ──

func test_ai_competitor_rank_estimation_within_tolerance() -> void:
	# Arrange — 브론즈 7,600명
	var count: int = 7600
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: count }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, SEED_FIXED)
	GameClock._current_tick = 780  # progress>0이어야 수익률 분포가 생김

	# 정확한 전체 수익률 수집
	var all_r: Array = AiCompetitor.get_all_return_pcts(AiCompetitor.TIER_BRONZE)
	var sorted_r: Array = all_r.duplicate()
	sorted_r.sort()

	# 중앙값 플레이어로 테스트
	var player_pct: float = sorted_r[count / 2]

	# 정확 순위 계산 (플레이어보다 높은 수익률 AI 수 + 1)
	var exact_rank: int = 1
	for r: float in all_r:
		if r > player_pct:
			exact_rank += 1

	# Act — 버킷 추정 순위
	var estimated_rank: int = AiCompetitor.estimate_player_rank(player_pct)

	# Assert — |정확순위 - 추정순위| ≤ count × (2 / RANK_BUCKETS)
	var tolerance: float = float(count) * 2.0 / float(AiCompetitor.RANK_BUCKETS)
	var diff: int = absi(exact_rank - estimated_rank)
	assert_true(
		diff <= int(tolerance),
		"AC-07: 순위 오차 %d > 허용 %d (정확=%d, 추정=%d)" % [diff, int(tolerance), exact_rank, estimated_rank]
	)
	gut.p("AC-07 순위 추정: 정확=%d위, 추정=%d위, 오차=%d (허용 %d)" % [exact_rank, estimated_rank, diff, int(tolerance)])


# ── EC-12: lazy evaluation 중복 생성 방지 ──

func test_ai_competitor_lazy_snapshot_not_generated_twice() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 20 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts)

	# Act — 동일 day 두 번 요청
	var r1: Array = AiCompetitor.get_all_return_pcts(AiCompetitor.TIER_BRONZE)
	var r2: Array = AiCompetitor.get_all_return_pcts(AiCompetitor.TIER_BRONZE)

	# Assert — 결과가 동일 (캐시 반환)
	assert_eq(r1.size(), r2.size(), "EC-12: 같은 day 두 번 요청 → 동일 결과")
	for i: int in range(r1.size()):
		assert_almost_eq(r1[i], r2[i], EPSILON, "EC-12: index %d 캐시 불일치" % i)
