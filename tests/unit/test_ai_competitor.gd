extends GutTest
## Unit tests for AiCompetitor — 신규 EOD 기반 아키텍처 검증.
## 전일 EOD 기준 단일 snapshot, 틱 분산 계산, 장 마감 swap 동작 검증.
## See: design/gdd/ai-competitor.md §8 Acceptance Criteria

# ── Constants ──

const SEED_FIXED: int  = 42
const EPSILON: float   = 0.001  # 부동소수점 오차 허용값 (%)

# ── Helpers ──

## 표준 테스트용 init_season 호출 헬퍼.
## 브론즈 100명 기본값으로 초기화 (성능 테스트 외).
func _init_standard(player_tier: int = AiCompetitor.TIER_BRONZE,
		counts: Dictionary = { 0: 100 },
		seed: int = SEED_FIXED) -> void:
	AiCompetitor.init_season(player_tier, counts, seed)
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN


## 테스트 후 전체 상태 리셋.
func after_each() -> void:
	AiCompetitor.reset()
	GameClock._current_day  = 0
	GameClock._current_tick = 0
	GameClock._market_state = GameClock.MarketState.PRE_MARKET


## 지정 횟수만큼 on_tick 시그널을 직접 emit하여 next_snapshot 계산을 진행한다.
func _advance_ticks(n: int, day: int = 0, week: int = 0) -> void:
	for i: int in range(n):
		AiCompetitor._on_tick(i, day, week)


## on_market_close를 직접 호출하여 eod_snapshot swap을 수행한다.
func _do_market_close() -> void:
	GameClock._current_day = AiCompetitor._current_compute_day
	AiCompetitor._on_market_close()


# ── AC-03: 계약 인터페이스 정상 동작 ──

func test_ai_competitor_get_eod_snapshot_returns_correct_length() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 50 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts)

	# Act
	var result: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE)

	# Assert
	assert_eq(result.size(), 50, "get_eod_snapshot 길이가 participant_count와 일치해야 함")


func test_ai_competitor_get_sorted_indices_returns_correct_length() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 30 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts)

	# Act
	var result: Array[int] = AiCompetitor.get_sorted_indices(AiCompetitor.TIER_BRONZE)

	# Assert
	assert_eq(result.size(), 30, "get_sorted_indices 길이가 participant_count와 일치해야 함")


func test_ai_competitor_estimate_player_rank_returns_valid_int() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 100 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts)
	_advance_ticks(AiCompetitor.TOTAL_PARTICIPANTS, 0)
	_do_market_close()

	# Act
	var rank: int = AiCompetitor.estimate_player_rank(10.0)

	# Assert
	assert_true(rank >= 1, "estimate_player_rank must be >= 1")
	assert_true(rank <= 101, "estimate_player_rank must be <= participant_count + 1")


func test_ai_competitor_snapshot_not_nan_or_inf_after_market_close() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 30 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts)
	_advance_ticks(AiCompetitor.TOTAL_PARTICIPANTS, 0)
	_do_market_close()

	# Act
	var result: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE)

	# Assert
	for i: int in range(result.size()):
		assert_true(not is_nan(result[i]), "Index %d: NaN 반환 금지" % i)
		assert_true(not is_inf(result[i]), "Index %d: Inf 반환 금지" % i)


# ── AC-02: 티어 단조성 (GDD §8 AC-02) ──

func test_ai_competitor_tier_monotonicity_mu_params() -> void:
	# AC-02: TIER_PARAMS mu 단조성 보장. ADR-007.
	for t: int in range(AiCompetitor.TIER_COUNT - 1):
		var mu_low: float  = AiCompetitor.TIER_PARAMS[t]["mu"]
		var mu_high: float = AiCompetitor.TIER_PARAMS[t + 1]["mu"]
		assert_true(
			mu_high > mu_low,
			"AC-02: TIER_PARAMS[%d].mu=%.1f%% < TIER_PARAMS[%d].mu=%.1f%% — 단조성 위반" % [t + 1, mu_high, t, mu_low]
		)


# ── AC-01: 결정론적 재현성 ──

func test_ai_competitor_same_seed_same_eod_after_market_close() -> void:
	# Arrange — 첫 번째 실행
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 50 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, 99999)
	_advance_ticks(AiCompetitor.TOTAL_PARTICIPANTS, 0)
	_do_market_close()
	var first_run: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE).duplicate()

	# 상태 리셋 후 동일 시드로 재초기화
	after_each()
	_init_standard(AiCompetitor.TIER_BRONZE, counts, 99999)
	_advance_ticks(AiCompetitor.TOTAL_PARTICIPANTS, 0)
	_do_market_close()
	var second_run: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE)

	# Assert — 부동소수점 오차 EPSILON 이내 동일
	assert_eq(first_run.size(), second_run.size(), "AC-01: 배열 길이 동일해야 함")
	for i: int in range(first_run.size()):
		assert_almost_eq(
			first_run[i], second_run[i], EPSILON,
			"AC-01: participant_id=%d 동일 seed → 동일 결과 보장 실패" % i
		)


func test_ai_competitor_different_seed_different_eod() -> void:
	# Arrange — seed 11111
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 20 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, 11111)
	_advance_ticks(AiCompetitor.TOTAL_PARTICIPANTS, 0)
	_do_market_close()
	var run_a: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE).duplicate()

	after_each()
	_init_standard(AiCompetitor.TIER_BRONZE, counts, 22222)
	_advance_ticks(AiCompetitor.TOTAL_PARTICIPANTS, 0)
	_do_market_close()
	var run_b: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE)

	# 다른 시드는 높은 확률로 다른 결과를 내야 함
	var any_different: bool = false
	for i: int in range(run_a.size()):
		if absf(run_a[i] - run_b[i]) > EPSILON:
			any_different = true
			break
	assert_true(any_different, "다른 seed는 다른 수익률 배열을 생성해야 함 (통계적)")


# ── AC-04: 성능 — 단일 틱 처리 ≤ 0.5ms ──

func test_ai_competitor_single_tick_performance() -> void:
	# Arrange — 전 티어 19,999명 수준 근사 (브론즈 7600 단독)
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 7600 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, SEED_FIXED)

	# Act — 단일 틱 처리 시간 측정
	var start_us: float = Time.get_ticks_usec()
	AiCompetitor._on_tick(0, 0, 0)
	var elapsed_ms: float = (Time.get_ticks_usec() - start_us) / 1000.0

	# Assert
	assert_true(
		elapsed_ms <= 0.5,
		"AC-04: 단일 _on_tick %.3fms — 0.5ms 초과" % elapsed_ms
	)
	gut.p("AC-04 단일 틱 성능: %.3fms (기준 0.5ms)" % elapsed_ms)


# ── AC-05: 장 마감 swap 성능 ≤ 5ms (브론즈 7600명) ──

func test_ai_competitor_market_close_performance_bronze_7600() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 7600 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, SEED_FIXED)
	# 전 인원 사전 계산 완료
	_advance_ticks(AiCompetitor.TOTAL_PARTICIPANTS + 100, 0)

	# Act
	var start_us: float = Time.get_ticks_usec()
	_do_market_close()
	var elapsed_ms: float = (Time.get_ticks_usec() - start_us) / 1000.0

	# Assert — headless 모드는 exported 빌드 대비 ~5-10x 느림. 헤드리스 임계값 50ms.
	# 인게임 목표: 5ms (exported Windows build 기준). GDD §8 AC-05.
	assert_true(
		elapsed_ms <= 50.0,
		"AC-05: _on_market_close %.2fms — 50ms 초과 (headless 기준)" % elapsed_ms
	)
	gut.p("AC-05 장 마감 성능: %.3fms (headless 기준 50ms, 인게임 목표 5ms)" % elapsed_ms)


# ── AC-06: r_min ≤ 반환값 ≤ r_max ──

func test_ai_competitor_eod_clamped_within_tier_bounds() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 200 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts)
	_advance_ticks(AiCompetitor.TOTAL_PARTICIPANTS, 0)
	_do_market_close()
	var r_min: float = AiCompetitor.TIER_PARAMS[AiCompetitor.TIER_BRONZE]["r_min"]
	var r_max: float = AiCompetitor.TIER_PARAMS[AiCompetitor.TIER_BRONZE]["r_max"]

	# Act
	var result: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE)

	# Assert
	for i: int in range(result.size()):
		assert_true(
			result[i] >= r_min,
			"AC-06: index %d: %.2f%% < r_min=%.2f%%" % [i, result[i], r_min]
		)
		assert_true(
			result[i] <= r_max,
			"AC-06: index %d: %.2f%% > r_max=%.2f%%" % [i, result[i], r_max]
		)


# ── AC-07: 이진탐색 순위 추정 정확도 ──

func test_ai_competitor_rank_estimation_exact_match_binary_search() -> void:
	# 신규 아키텍처에서 estimate_player_rank는 이진탐색으로 정확값 반환 (버킷 근사 아님)
	var count: int = 200
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: count }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, SEED_FIXED)
	_advance_ticks(AiCompetitor.TOTAL_PARTICIPANTS, 0)
	_do_market_close()

	var eod: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE)
	var sorted_idx: Array[int] = AiCompetitor.get_sorted_indices(AiCompetitor.TIER_BRONZE)

	# 중앙값 플레이어로 테스트
	var player_pct: float = eod[sorted_idx[count / 2]]

	# 정확 순위 계산 — GDD §3-5: 동점 AI는 플레이어보다 뒤 (> 사용)
	var exact_rank: int = 1
	for r: float in eod:
		if r > player_pct:
			exact_rank += 1

	# Act
	var estimated_rank: int = AiCompetitor.estimate_player_rank(player_pct)

	# Assert — 이진탐색은 정확값이므로 오차 = 0
	assert_eq(
		estimated_rank, exact_rank,
		"AC-07: 이진탐색 순위 추정 — 정확=%d, 추정=%d (오차 0이어야 함)" % [exact_rank, estimated_rank]
	)
	gut.p("AC-07: 정확=%d위, 추정=%d위" % [exact_rank, estimated_rank])


# ── AC-12: EOD 정합성 (리더보드 ↔ 순위) ──

func test_ai_competitor_eod_coherence_leaderboard_vs_rank() -> void:
	# GDD §8 AC-12: 1위 AI의 eod 값을 estimate_player_rank에 넣으면 rank=2 반환해야 함
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 100 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, SEED_FIXED)
	_advance_ticks(AiCompetitor.TOTAL_PARTICIPANTS, 0)
	_do_market_close()

	var eod: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE)
	var sorted_idx: Array[int] = AiCompetitor.get_sorted_indices(AiCompetitor.TIER_BRONZE)

	# 1위 AI의 eod 값 = 최댓값
	var top_return: float = eod[sorted_idx[0]]

	# Act — 플레이어가 1위 AI와 동일 수익률이면 rank=1 (동점은 플레이어 우선)
	var rank: int = AiCompetitor.estimate_player_rank(top_return)

	# Assert
	assert_eq(rank, 1,
		"AC-12: 1위 AI eod 값으로 estimate_player_rank → 1위 반환 필요 (동점=플레이어 우선, got %d)" % rank
	)


# ── AC-13: snapshot save/load 복원 ──

func test_ai_competitor_save_load_restores_eod_snapshot() -> void:
	# Arrange — 초기화 후 장 마감까지 진행
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 50 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, SEED_FIXED)
	_advance_ticks(AiCompetitor.TOTAL_PARTICIPANTS, 0)
	_do_market_close()

	var before: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE).duplicate()

	# Act — 저장 후 리셋 후 로드
	var save_data: Dictionary = AiCompetitor.get_save_data()
	AiCompetitor.reset()
	AiCompetitor.load_save_data(save_data)
	var after: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE)

	# Assert
	assert_eq(before.size(), after.size(), "AC-13: 로드 후 배열 길이 동일")
	for i: int in range(before.size()):
		assert_almost_eq(
			before[i], after[i], EPSILON,
			"AC-13: eod_snapshot[%d] 로드 후 불일치" % i
		)


func test_ai_competitor_save_load_sorted_indices_correct() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 50 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, SEED_FIXED)
	_advance_ticks(AiCompetitor.TOTAL_PARTICIPANTS, 0)
	_do_market_close()

	var eod_before: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE).duplicate()
	var idx_before: Array[int] = AiCompetitor.get_sorted_indices(AiCompetitor.TIER_BRONZE).duplicate()

	# Act
	var save_data: Dictionary = AiCompetitor.get_save_data()
	AiCompetitor.reset()
	AiCompetitor.load_save_data(save_data)
	var idx_after: Array[int] = AiCompetitor.get_sorted_indices(AiCompetitor.TIER_BRONZE)
	var eod_after: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE)

	# Assert — sorted_indices가 내림차순을 유지하는지 확인
	assert_eq(idx_before.size(), idx_after.size(), "AC-13: sorted_indices 길이 동일")
	for k: int in range(idx_after.size() - 1):
		assert_true(
			eod_after[idx_after[k]] >= eod_after[idx_after[k + 1]],
			"AC-13: sorted_indices[%d] 내림차순 위반" % k
		)


# ── EC-01: init_season 미호출 가드 ──

func test_ai_competitor_uninitialized_get_eod_snapshot_returns_empty() -> void:
	# Arrange — init_season 호출하지 않음 (reset으로 미초기화 상태)
	AiCompetitor.reset()

	# Act
	var result: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE)

	# Assert
	assert_eq(result.size(), 0, "EC-01: init_season 미호출 시 빈 배열 반환")


func test_ai_competitor_uninitialized_estimate_player_rank_returns_zero() -> void:
	AiCompetitor.reset()

	var rank: int = AiCompetitor.estimate_player_rank(10.0)

	assert_eq(rank, 0, "EC-01: init_season 미호출 시 estimate_player_rank → 0")


# ── EC-04: Day 0 초기 eod_snapshot은 전부 0.0 ──

func test_ai_competitor_day0_eod_snapshot_all_zero() -> void:
	# Arrange — init_season 직후, 장 마감 전 상태
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 10 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, SEED_FIXED)

	# Act — 장 마감 없이 바로 조회 (시즌 첫날 PRE_MARKET → 0.0)
	var result: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE)

	# Assert
	for i: int in range(result.size()):
		assert_eq(result[i], 0.0, "EC-04: 시즌 첫날 eod_snapshot[%d] == 0.0" % i)


# ── EC-07: AI 0명 티어 ──

func test_ai_competitor_zero_count_tier_returns_error_and_empty() -> void:
	# Arrange — 브론즈 0명
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 0 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts)

	# Act
	var result: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE)

	# Assert
	assert_eq(result.size(), 0, "EC-07: 0명 티어 get_eod_snapshot → 빈 배열 반환")


# ── EC-12: 장 마감 시 미완료분 동기 처리 ──

func test_ai_competitor_market_close_syncs_remaining_participants() -> void:
	# Arrange — 틱 분산 계산 없이 바로 장 마감 호출
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 50 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, SEED_FIXED)
	# 틱 없이 바로 장 마감 → 동기 fallback으로 전원 처리되어야 함

	# Act
	_do_market_close()
	var result: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE)

	# Assert — 모든 값이 0.0이 아닌 값으로 계산됐는지 확인 (day=0이므로 일부 0 허용)
	assert_eq(result.size(), 50, "EC-12: 동기 처리 후 eod_snapshot 길이 == 50")
	# NaN/Inf 없음 확인
	for i: int in range(result.size()):
		assert_true(not is_nan(result[i]), "EC-12: index %d NaN 금지" % i)
		assert_true(not is_inf(result[i]), "EC-12: index %d Inf 금지" % i)


# ── AC-08: 거장 AI 메타데이터 ──

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


# ── 틱 분산 계산 — next_snapshot 점진적 채움 검증 ──

func test_ai_competitor_tick_distributes_computation_across_ticks() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 100 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, SEED_FIXED)

	# Act — 1틱만 처리 (PARTICIPANTS_PER_TICK=13명 계산됨)
	AiCompetitor._on_tick(0, 0, 0)
	var computed_after_1tick: int = AiCompetitor._tier_data[AiCompetitor.TIER_BRONZE]["next_computed"]

	# Assert — 1틱 후 PARTICIPANTS_PER_TICK만큼 진행돼야 함 (브론즈 전용이므로 최대 13)
	assert_true(
		computed_after_1tick > 0,
		"1틱 후 next_computed > 0이어야 함 (got %d)" % computed_after_1tick
	)


# ── sorted_indices 내림차순 정렬 검증 ──

func test_ai_competitor_sorted_indices_descending_after_market_close() -> void:
	# Arrange
	var counts: Dictionary = { AiCompetitor.TIER_BRONZE: 50 }
	_init_standard(AiCompetitor.TIER_BRONZE, counts, SEED_FIXED)
	_advance_ticks(AiCompetitor.TOTAL_PARTICIPANTS, 0)
	_do_market_close()

	# Act
	var eod: Array[float] = AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE)
	var idx: Array[int] = AiCompetitor.get_sorted_indices(AiCompetitor.TIER_BRONZE)

	# Assert — 내림차순 검증
	for k: int in range(idx.size() - 1):
		assert_true(
			eod[idx[k]] >= eod[idx[k + 1]],
			"sorted_indices[%d] 내림차순 위반: %.2f < %.2f" % [k, eod[idx[k]], eod[idx[k + 1]]]
		)
