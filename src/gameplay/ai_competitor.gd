## Autoload — AI Competitor System.
## 시즌 내 19,999명의 AI 참가자 수익률을 통계적으로 생성·관리한다.
## 실제 주문 체결 없이 정규분포 기반 수익률 시뮬레이션으로 리더보드를 구성한다.
##
## 아키텍처 핵심 (2026-04-14 재설계):
##   - 전일 EOD 기준 단일 eod_snapshot — 리더보드와 순위가 동일 데이터 참조 (정합성 보장)
##   - 틱 분산 사전 계산 — 매 틱 ~13명씩 next_snapshot 계산. 장 마감 시 swap만 수행.
##   - 인트라데이 보간 제거 — 장 중 AI 수익률은 변동 없음 (전일 EOD 고정).
##
## See: design/gdd/ai-competitor.md
extends Node

# ── Tier Constants ──

const TIER_BRONZE: int               = 0
const TIER_SILVER: int               = 1
const TIER_GOLD: int                 = 2
const TIER_PLATINUM: int             = 3
const TIER_EMERALD: int              = 4
const TIER_DIAMOND: int              = 5
const TIER_MASTER: int               = 6
const TIER_GRANDMASTER: int          = 7
const TIER_CHALLENGER: int           = 8
const TIER_LEGEND: int               = 9
const TIER_MASTER_OF_INVESTMENT: int = 10

const TIER_COUNT: int = 11

# ── Global Parameters ──

## 시즌 총 거래일 수 — GameClock 상수에서 파생. 수동 동기화 불필요.
const SEASON_DAYS: int = GameClock.DAYS_PER_WEEK * GameClock.WEEKS_PER_SEASON

## 전체 AI 참가자 수. SeasonManager.TOTAL_PARTICIPANTS(@export var) − 1 (플레이어 제외).
## SeasonManager.TOTAL_PARTICIPANTS가 var이므로 const 파생 불가 — _ready()에서 단언 검증.
const TOTAL_PARTICIPANTS: int = 19999

## 틱당 처리 참가자 수. GDD §7-1 PARTICIPANTS_PER_TICK.
## ceil(19999 / 1560) = 13. 이 값 × TICKS_PER_DAY >= TOTAL_PARTICIPANTS 조건 필수.
## Safe range: 10 ~ 30
const PARTICIPANTS_PER_TICK: int = 13

## 장 마감 시 동기 fallback 처리 인원이 이 수를 초과하면 push_warning. GDD §7-3.
const SYNC_FALLBACK_WARN_THRESHOLD: int = 100

# ── Tier Parameter Table ──
## GDD §4-1 티어별 수익률 분포 파라미터.
## 순서: [mu_tier, sigma_tier, r_min, r_max]
## 단위: % (예: 20.0 = 20%)
## 설계 원칙: 티어 = 자본량, 실력 ≠ 티어.
## mu는 생존편향 2%씩 미세 증가만 (동일 실력 분포, 대자본 생존편향 소폭 반영).
## sigma는 티어 상승 시 하락 (대자본 = 분산투자 가능 = 퍼센트 기준 수익률 안정화).
## r_min/r_max는 전 티어 동일 — 고티어도 손실/대박 동일한 상하한.
## 단조성은 mu 단독 보장 (AC-02). ADR-007 참고.
const TIER_PARAMS: Array[Dictionary] = [
	# TIER_BRONZE (0)
	{ "mu": 8.0, "sigma": 55.0, "r_min": -60.0, "r_max": 600.0 },
	# TIER_SILVER (1)
	{ "mu": 10.0, "sigma": 52.0, "r_min": -60.0, "r_max": 600.0 },
	# TIER_GOLD (2)
	{ "mu": 12.0, "sigma": 49.0, "r_min": -60.0, "r_max": 600.0 },
	# TIER_PLATINUM (3)
	{ "mu": 14.0, "sigma": 46.0, "r_min": -60.0, "r_max": 600.0 },
	# TIER_EMERALD (4)
	{ "mu": 16.0, "sigma": 43.0, "r_min": -60.0, "r_max": 600.0 },
	# TIER_DIAMOND (5)
	{ "mu": 18.0, "sigma": 40.0, "r_min": -60.0, "r_max": 600.0 },
	# TIER_MASTER (6)
	{ "mu": 20.0, "sigma": 37.0, "r_min": -60.0, "r_max": 600.0 },
	# TIER_GRANDMASTER (7)
	{ "mu": 22.0, "sigma": 34.0, "r_min": -60.0, "r_max": 600.0 },
	# TIER_CHALLENGER (8)
	{ "mu": 24.0, "sigma": 31.0, "r_min": -60.0, "r_max": 600.0 },
	# TIER_LEGEND (9)
	{ "mu": 26.0, "sigma": 28.0, "r_min": -60.0, "r_max": 600.0 },
	# TIER_MASTER_OF_INVESTMENT (10)
	{ "mu": 28.0, "sigma": 25.0, "r_min": -60.0, "r_max": 600.0 },
]

# ── Internal State ──

## 시즌 시작 여부 플래그. EC-01 가드에 사용.
var _initialized: bool = false

## 플레이어 배정 티어 (0~10).
var _player_tier: int = 0

## 이 시즌의 글로벌 랜덤 시드.
var _season_seed: int = 0

## 현재 거래일 (0-based). _on_tick에서 틱 분산 계산 진행 추적에 사용.
var _ticks_this_day: int = 0

## 시즌 내 현재 거래일 번호 (0-based). next_snapshot 생성에 사용.
var _current_compute_day: int = 0

## 티어별 데이터. key = tier(int), value = Dictionary.
## 각 Dictionary 구조:
##   "count": int                        — 해당 티어 AI 인원수
##   "target_r": Array[float]            — 각 AI의 시즌 최종 목표 수익률 (init_season 시 생성, 저장 불필요)
##   "eod_snapshot": Array[float]        — 전일 EOD 수익률 (장 마감 시 확정·저장 대상)
##   "next_snapshot": Array[float]       — 오늘 EOD 예정값 (틱 분산 계산 중)
##   "next_computed": int                — next_snapshot 계산 완료 global_participant_id 기준 진행 수
##   "sorted_indices": Array[int]        — eod_snapshot 기준 내림차순 정렬 인덱스
var _tier_data: Dictionary = {}

## 글로벌 participant_id 0~TOTAL_PARTICIPANTS-1 → (tier, local_id) 역산 캐시.
## 틱마다 역산하는 대신 init_season 시 1회 구성한다.
## key = global_id: int, value = { "tier": int, "local_id": int }
var _global_id_to_tier: Dictionary = {}

## 전체 글로벌 참가자 수 (실제 인원 합계, TOTAL_PARTICIPANTS와 다를 수 있음).
var _actual_total: int = 0

# ── Lifecycle ──

func _ready() -> void:
	GameClock.on_tick.connect(_on_tick)
	GameClock.on_market_close.connect(_on_market_close)
	## TOTAL_PARTICIPANTS는 SeasonManager.TOTAL_PARTICIPANTS(@export var) - 1 과 일치해야 함.
	## @export var이므로 const 파생 불가 — 런타임 단언으로 동기화 검증.
	assert(TOTAL_PARTICIPANTS == SeasonManager.TOTAL_PARTICIPANTS - 1,
		"AiCompetitor.TOTAL_PARTICIPANTS(%d) != SeasonManager.TOTAL_PARTICIPANTS-1(%d). Sync required!" \
		% [TOTAL_PARTICIPANTS, SeasonManager.TOTAL_PARTICIPANTS - 1])


# ── Public API ──

## 시즌 시작 시 호출. 티어별 AI 참가자를 초기화한다.
## [br]player_tier: 플레이어 배정 티어 (TIER_BRONZE=0 ~ TIER_MASTER_OF_INVESTMENT=10)
## [br]participant_counts: Dictionary[int, int] — 티어 번호 → AI 인원수
## [br]seed: 결정론적 시드. 0 전달 시 Time.get_ticks_msec() 자동 생성 (EC-03, 비결정론적 — 테스트 금지)
## [br]Usage: AiCompetitor.init_season(0, {0: 7600, 1: 3200, ...}, 12345)
func init_season(player_tier: int, participant_counts: Dictionary, seed: int = 0) -> void:
	_validate_tier_monotonicity()

	# EC-03: seed=0 이면 비결정론적 시드 자동 생성
	if seed == 0:
		_season_seed = Time.get_ticks_msec()
	else:
		_season_seed = seed

	_player_tier = player_tier
	_ticks_this_day = 0
	_current_compute_day = 0
	_tier_data.clear()
	_global_id_to_tier.clear()

	# 티어별 데이터 초기화. target_r 생성, eod_snapshot 0.0으로 초기화 (EC-04: Day 0 기준).
	for tier: int in participant_counts:
		var count: int = participant_counts[tier]
		var target_r: Array[float] = _generate_target_returns(tier, count)
		var eod: Array[float] = []
		eod.resize(count)
		eod.fill(0.0)
		var next: Array[float] = []
		next.resize(count)
		next.fill(0.0)
		var sorted: Array[int] = []
		sorted.resize(count)
		for j: int in range(count):
			sorted[j] = j
		# 초기 정렬: 전부 0.0이므로 순서는 participant_id 오름차순
		# P3 최적화: eod_rng_states — 전일 EOD 직후 RNG 상태 캐시 (0 = 미설정).
		var rng_states: Array[int] = []
		rng_states.resize(count)
		rng_states.fill(0)
		_tier_data[tier] = {
			"count":           count,
			"target_r":        target_r,
			"eod_snapshot":    eod,
			"next_snapshot":   next,
			"next_computed":   0,
			"sorted_indices":  sorted,
			"eod_rng_states":  rng_states,
		}

	# 글로벌 ID → (tier, local_id) 역산 캐시 구성.
	# 순서: tier 오름차순, tier 내 participant_id 오름차순.
	var global_id: int = 0
	for tier: int in range(TIER_COUNT):
		if not _tier_data.has(tier):
			continue
		var count: int = _tier_data[tier]["count"]
		for local_id: int in range(count):
			_global_id_to_tier[global_id] = { "tier": tier, "local_id": local_id }
			global_id += 1
	_actual_total = global_id

	_initialized = true


## 전일 EOD 기준 지정 티어 수익률 배열을 반환한다.
## [br]리더보드 표시용. 장 중에도 변동 없음 (전일 고정).
## [br]tier: 대상 티어 번호 (TIER_BRONZE ~ TIER_MASTER_OF_INVESTMENT)
## [br]반환값: eod_snapshot Array[float] (복사본 아님 — 읽기 전용으로 사용할 것)
## [br]Usage: var snap := AiCompetitor.get_eod_snapshot(AiCompetitor.TIER_BRONZE)
func get_eod_snapshot(tier: int) -> Array[float]:
	if not _initialized:
		push_warning("AiCompetitor: get_eod_snapshot called before init_season")
		return []
	if not _tier_data.has(tier):
		push_warning("AiCompetitor: tier %d has no data" % tier)
		return []
	# EC-07: 0명인 경우 — 빈 배열 반환 (push_error 없음: 테스트 가능 edge case)
	if _tier_data[tier]["count"] == 0:
		return []
	return _tier_data[tier]["eod_snapshot"]


## 전일 EOD 기준 내림차순 정렬 인덱스를 반환한다.
## [br]리더보드 O(K) 접근용. eod_snapshot[sorted_indices[k]] 가 k번째 AI 수익률.
## [br]tier: 대상 티어 번호
## [br]반환값: Array[int] — participant_id를 eod_snapshot 내림차순으로 정렬한 배열
## [br]Usage: var idx := AiCompetitor.get_sorted_indices(AiCompetitor.TIER_BRONZE)
func get_sorted_indices(tier: int) -> Array[int]:
	if not _initialized:
		push_warning("AiCompetitor: get_sorted_indices called before init_season")
		return []
	if not _tier_data.has(tier):
		push_warning("AiCompetitor: tier %d has no data" % tier)
		return []
	if _tier_data[tier]["count"] == 0:
		return []
	return _tier_data[tier]["sorted_indices"]


## 플레이어 수익률을 기반으로 플레이어 티어 내 추정 순위를 반환한다.
## [br]GDD §3-5, §4-4 이진탐색 구현. O(log N).
## [br]player_return_pct: 플레이어 현재 수익률 (%) — 장 중 실시간 값.
## [br]반환값: int — 추정 순위 (1-based). init_season 미호출 시 0.
## [br]Usage: var rank := AiCompetitor.estimate_player_rank(player_return_pct)
func estimate_player_rank(player_return_pct: float) -> int:
	if not _initialized:
		push_warning("AiCompetitor: estimate_player_rank called before init_season")
		return 0
	if not _tier_data.has(_player_tier):
		return 1
	var td: Dictionary = _tier_data[_player_tier]
	# EC-07: 0명 티어
	if td["count"] == 0:
		return 1
	var eod: Array[float] = td["eod_snapshot"]
	var sorted_idx: Array[int] = td["sorted_indices"]
	# GDD §4-4: 이진탐색 — sorted_indices는 eod_snapshot 내림차순이므로
	# 앞쪽 원소가 더 크다. player_return_pct보다 큰 AI 수 = lo = 플레이어보다 앞선 AI 수.
	# > 사용 이유: 동점 AI는 플레이어보다 뒤 (GDD §3-5 "동점은 플레이어 우선").
	var lo: int = 0
	var hi: int = sorted_idx.size()
	while lo < hi:
		var mid: int = (lo + hi) / 2
		if eod[sorted_idx[mid]] > player_return_pct:
			lo = mid + 1
		else:
			hi = mid
	return lo + 1


## 거장 AI 메타데이터 반환 (옵션 인터페이스, LeagueUI 전용).
## [br]반환값: { "is_master_of_investment": bool, "display_name": String }
## [br]Usage: var meta := AiCompetitor.get_participant_meta(AiCompetitor.TIER_MASTER_OF_INVESTMENT, 0)
func get_participant_meta(tier: int, participant_id: int) -> Dictionary:
	return {
		"is_master_of_investment": tier == TIER_MASTER_OF_INVESTMENT,
		"display_name": "AI_%d_%d" % [tier, participant_id],
	}


## 세이브용 직렬화 데이터 반환.
## [br]저장 대상: season_seed, participant_counts, 전 티어 eod_snapshot.
## [br]target_r은 season_seed로 재생성 가능하므로 저장 불필요 (GDD §3-4).
## [br]sorted_indices는 eod_snapshot에서 재정렬 가능하므로 저장 불필요.
func get_save_data() -> Dictionary:
	if not _initialized:
		return {}
	var counts: Dictionary = {}
	var snapshots: Dictionary = {}
	for tier: int in _tier_data:
		counts[str(tier)] = _tier_data[tier]["count"]
		# eod_snapshot 저장 (Array[float] → Array 변환으로 JSON 직렬화 호환)
		var eod: Array[float] = _tier_data[tier]["eod_snapshot"]
		var eod_arr: Array = []
		eod_arr.assign(eod)
		snapshots[str(tier)] = eod_arr
	return {
		"season_seed":        _season_seed,
		"player_tier":        _player_tier,
		"participant_counts": counts,
		"eod_snapshots":      snapshots,
	}


## 세이브 데이터에서 상태를 복원한다.
## [br]eod_snapshot 직접 복원. target_r은 season_seed 기반 재생성. sorted_indices 재정렬.
## [br]EC-13: 특정 티어 키 누락 시 해당 티어 eod_snapshot을 0.0 배열로 초기화.
func load_save_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	var counts_raw: Dictionary = data.get("participant_counts", {})
	if counts_raw.is_empty():
		return
	var counts: Dictionary = {}
	for key: String in counts_raw:
		counts[int(key)] = counts_raw[key]

	# init_season으로 target_r 재생성 + eod_snapshot 0.0 초기화
	init_season(data.get("player_tier", 0), counts, data.get("season_seed", 0))

	# eod_snapshot 직접 복원 (init_season이 0.0으로 초기화한 것을 덮어쓴다)
	var snapshots_raw: Dictionary = data.get("eod_snapshots", {})
	for tier_str: String in snapshots_raw:
		var tier: int = int(tier_str)
		if not _tier_data.has(tier):
			continue
		var arr_raw: Array = snapshots_raw[tier_str]
		var td: Dictionary = _tier_data[tier]
		var count: int = td["count"]
		var eod: Array[float] = td["eod_snapshot"]
		# 길이가 맞지 않으면 EC-13: 0.0 초기화 유지
		if arr_raw.size() != count:
			push_warning("AiCompetitor.load_save_data: tier %d snapshot size mismatch (expected %d, got %d) — using 0.0" % [tier, count, arr_raw.size()])
			continue
		for i: int in range(count):
			eod[i] = float(arr_raw[i])
		# sorted_indices 재정렬 (eod_snapshot 복원 후)
		_rebuild_sorted_indices(tier)

	# next_computed / ticks 초기화 (로드 후 당일 분산 계산은 처음부터 재시작)
	for tier: int in _tier_data:
		_tier_data[tier]["next_computed"] = 0
	_ticks_this_day = 0


## 전체 AI 상태를 초기값으로 리셋한다. GameMain(신규 게임) 및 테스트 before_each에서 호출.
func reset() -> void:
	_initialized = false
	_player_tier = 0
	_season_seed = 0
	_ticks_this_day = 0
	_current_compute_day = 0
	_actual_total = 0
	_tier_data.clear()
	_global_id_to_tier.clear()


# ── Signal Handlers ──

## GameClock.on_tick 핸들러. 전 티어 통합 global_id 기준으로 next_snapshot 분산 계산.
## [br]틱당 PARTICIPANTS_PER_TICK(≈13)명씩 처리. 프레임 예산 영향 최소화.
func _on_tick(_tick_number: int, day: int, _week: int) -> void:
	if not _initialized:
		return
	# 새 날에 진입하면 ticks_this_day 리셋
	if day != _current_compute_day:
		_current_compute_day = day
		_ticks_this_day = 0

	# EC-10: TICKS_PER_DAY=0 방지
	var ticks_per_day: int = GameClock.TICKS_PER_DAY
	if ticks_per_day == 0:
		push_error("AiCompetitor: TICKS_PER_DAY is 0 — GameClock error")
		return

	# 이미 전체 완료된 경우 스킵
	if _actual_total == 0:
		return

	# 이번 틱에서 계산할 global_id 범위: [tick_start, tick_end)
	var tick_start: int = _ticks_this_day * PARTICIPANTS_PER_TICK
	var tick_end: int = mini(tick_start + PARTICIPANTS_PER_TICK, _actual_total)
	_ticks_this_day += 1

	if tick_start >= _actual_total:
		return

	for gid: int in range(tick_start, tick_end):
		var entry: Dictionary = _global_id_to_tier.get(gid, {})
		if entry.is_empty():
			continue
		var tier: int = entry["tier"]
		var local_id: int = entry["local_id"]
		if not _tier_data.has(tier):
			continue
		var td: Dictionary = _tier_data[tier]
		td["next_snapshot"][local_id] = _compute_eod_for(tier, local_id, day)
		td["next_computed"] += 1


## GameClock.on_market_close 핸들러.
## [br]EC-12: 미완료분 동기 처리 → eod_snapshot ← next_snapshot swap → sorted_indices 재정렬.
func _on_market_close() -> void:
	if not _initialized:
		return

	# EC-12: next_computed 총합 < _actual_total 이면 나머지 동기 일괄 처리
	var day: int = GameClock.get_current_day()
	var remaining: int = 0
	for tier: int in _tier_data:
		var td: Dictionary = _tier_data[tier]
		var computed: int = td["next_computed"]
		var count: int = td["count"]
		remaining += maxi(0, count - computed)

	if remaining > 0:
		if remaining > SYNC_FALLBACK_WARN_THRESHOLD:
			push_warning("AiCompetitor: EC-12 — %d participants not computed before market_close. Sync fallback triggered. Check PARTICIPANTS_PER_TICK." % remaining)
		# 동기 처리: next_computed 기준으로 나머지 global_id 처리
		for gid: int in range(_actual_total):
			var entry: Dictionary = _global_id_to_tier.get(gid, {})
			if entry.is_empty():
				continue
			var tier: int = entry["tier"]
			var local_id: int = entry["local_id"]
			if not _tier_data.has(tier):
				continue
			var td: Dictionary = _tier_data[tier]
			var computed: int = td["next_computed"]
			var count: int = td["count"]
			# next_computed는 전역 카운터가 아니라 tier별이므로,
			# 아직 계산되지 않은 local_id를 직접 판별해야 한다.
			# _on_tick에서는 global_id 순서대로 처리하므로,
			# 각 tier의 next_computed 이후 local_id가 미처리 상태다.
			if local_id >= computed and local_id < count:
				td["next_snapshot"][local_id] = _compute_eod_for(tier, local_id, day)

	# eod_snapshot ← next_snapshot swap (전 티어)
	for tier: int in _tier_data:
		var td: Dictionary = _tier_data[tier]
		var count: int = td["count"]
		# 직접 교체 (복사 최소화)
		for i: int in range(count):
			td["eod_snapshot"][i] = td["next_snapshot"][i]
		# next_snapshot / next_computed 초기화
		td["next_snapshot"].fill(0.0)
		td["next_computed"] = 0
		# sorted_indices 재정렬
		_rebuild_sorted_indices(tier)

	# ticks_this_day 리셋 (다음 날 분산 계산 준비)
	_ticks_this_day = 0


# ── Internal Generation ──

## GDD §4-1, §4-5: 시즌 최종 목표 수익률 배열 생성.
## participant_rng_seed = (season_seed × 1000003) XOR (participant_id × 998244353) XOR (tier × 7919)
func _generate_target_returns(tier: int, count: int) -> Array[float]:
	var result: Array[float] = []
	result.resize(count)
	var params: Dictionary = TIER_PARAMS[tier]
	var mu: float    = params["mu"]
	var sigma: float = params["sigma"]
	var r_min: float = params["r_min"]
	var r_max: float = params["r_max"]
	var rng := RandomNumberGenerator.new()

	for i: int in range(count):
		# GDD §4-5 시드 생성 공식
		var p_seed: int = (_season_seed * 1000003) ^ (i * 998244353)
		p_seed = p_seed ^ (tier * 7919)
		rng.seed = p_seed
		# GDD §4-1: 정규분포 샘플링
		var raw: float = rng.randfn(mu, sigma)
		# EC-05: target_r 클램프
		result[i] = clamp(raw, r_min, r_max)

	return result


## GDD §3-3 단계 2: 특정 tier·local_id의 당일(day) EOD 수익률을 계산한다.
## random walk with drift 모델.
## P3 최적화: eod_rng_states에 전일 RNG 상태를 캐시해 O(day) → O(1)로 단축.
## 첫 호출 또는 시즌 시작(day=0)에는 O(day) 재계산. 이후 O(1) 한 스텝만 진행.
func _compute_eod_for(tier: int, local_id: int, day: int) -> float:
	var td: Dictionary = _tier_data[tier]
	var params: Dictionary = TIER_PARAMS[tier]
	var target_r: float = (td["target_r"] as Array[float])[local_id]
	var sigma_daily: float = params["sigma"] / sqrt(float(SEASON_DAYS))
	var drift_per_day: float = target_r / float(SEASON_DAYS)

	# 이 참가자 전용 일별 RNG — target_r RNG와 시드 분리 (0xDEAD_BEEF 상수)
	var p_seed: int = (_season_seed * 1000003) ^ (local_id * 998244353)
	p_seed = p_seed ^ (tier * 7919)
	p_seed = p_seed ^ 0xDEAD_BEEF
	var rng := RandomNumberGenerator.new()

	# 일간 가격제한: PriceEngine.DAILY_LIMIT_PCT = 0.30 → 30%/일
	var daily_limit_pct: float = PriceEngine.DAILY_LIMIT_PCT * 100.0

	var start_day: int = 0
	var running: float = 0.0

	# P3 캐시 복원: eod_rng_states[local_id] != 0 이고 day > 0이면
	# 전일 EOD 직후 RNG 상태로 복원 후 한 스텝만 진행 (O(1)).
	# day == 0 이면 항상 시드부터 재시작 (이전 시즌 캐시 오염 방지).
	var rng_states: Array[int] = td["eod_rng_states"]
	if day > 0 and rng_states[local_id] != 0:
		running = (td["eod_snapshot"] as Array[float])[local_id]
		rng.state = rng_states[local_id]
		start_day = day
	else:
		rng.seed = p_seed

	# day까지의 누적 수익률 계산 (GDD §4-2)
	for d: int in range(start_day, day + 1):
		var daily: float = drift_per_day + rng.randfn(0.0, sigma_daily)
		running += daily
		var day_max: float = daily_limit_pct * float(d + 1)
		running = clampf(running, -day_max, day_max)

	# 다음 호출을 위해 현재 RNG 상태 저장 (eod_snapshot 스왑 후에도 유효).
	rng_states[local_id] = rng.state

	return running


## eod_snapshot 기준 sorted_indices 재정렬 (내림차순).
func _rebuild_sorted_indices(tier: int) -> void:
	if not _tier_data.has(tier):
		return
	var td: Dictionary = _tier_data[tier]
	var count: int = td["count"]
	var eod: Array[float] = td["eod_snapshot"]
	var sorted: Array[int] = td["sorted_indices"]
	# 길이 보장
	if sorted.size() != count:
		sorted.resize(count)
		for j: int in range(count):
			sorted[j] = j
	else:
		for j: int in range(count):
			sorted[j] = j
	sorted.sort_custom(func(a: int, b: int) -> bool: return eod[a] > eod[b])
	td["sorted_indices"] = sorted


## GDD §7-2: 단조성 검증. init_season 호출 시 TIER_PARAMS 유효성 검사.
## 단조성은 mu 단독으로 보장. r_min은 전 티어 동일(-60%)이므로 검증 불필요.
func _validate_tier_monotonicity() -> void:
	for t: int in range(TIER_COUNT - 1):
		var curr: Dictionary = TIER_PARAMS[t]
		var next: Dictionary = TIER_PARAMS[t + 1]
		# mu 단조성 검증 (AC-02의 실제 보장 수단)
		if next["mu"] <= curr["mu"]:
			push_error("AiCompetitor: mu 단조성 위반 — mu[%d]=%.1f <= mu[%d]=%.1f" % [t + 1, next["mu"], t, curr["mu"]])
		# EC-09: sigma_tier >= 5.0 하한 강제
		if curr["sigma"] < 5.0:
			push_error("AiCompetitor: EC-09 — sigma[%d]=%.1f < 5.0 하한" % [t, curr["sigma"]])
