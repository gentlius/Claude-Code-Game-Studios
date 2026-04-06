## Autoload — AI Competitor System.
## 시즌 내 19,999명의 AI 참가자 수익률을 통계적으로 생성·관리한다.
## 실제 주문 체결 없이 정규분포 기반 수익률 시뮬레이션으로 리더보드를 구성한다.
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
## 순위 추정 버킷 개수. 클수록 정밀하나 재계산 비용 증가.
## Safe range: 20 ~ 500
const RANK_BUCKETS: int = 100

## 시즌 총 거래일 수. game-clock.md SEASON_WEEKS(4) × DAYS_PER_WEEK(5) 와 동기화 필수.
## Safe range: 10 ~ 40
const SEASON_DAYS: int = 20

## 플레이어 티어 매 틱 갱신 여부. false 시 일별 스냅샷만 사용 (성능 비상용).
const PLAYER_TIER_TICK_UPDATE: bool = true

## false 시 시즌 시작 시 전 일수 사전 계산 (메모리 ↑, 글로벌 갱신 지연 ↓).
const LAZY_EVAL_ON_DEMAND: bool = true

# ── Tier Parameter Table ──
## GDD §4-1 티어별 수익률 분포 파라미터.
## 순서: [mu_tier, sigma_tier, r_min, r_max]
## 단위: % (예: 200.0 = 200%)
## Q1 결정: GDScript 상수로 관리 (YAGNI — 추후 Resource로 추출 가능)
## GDD §4-1 티어별 수익률 분포 파라미터.
## mu는 단조 증가 보장 (GDD §3-1 원칙 3 — 티어 단조성).
## r_min도 단조 증가 → 고티어 AI는 저티어 AI보다 항상 높은 하한 수익률.
## 원래 GDD 공식(daily_r 복리)은 홀짝 교대 패턴이었으나,
## AC-02(인접 티어 중앙값 단조성) 보장을 위해 선형 보간 방식으로 재산정.
## 단조성은 mu 단독 보장. r_min은 전 티어 동일(-60%) → 고티어도 손실 가능.
## 이전 설계(r_min 계단 상승)는 "고티어가 항상 고수익"을 강제하는 부작용이 있어 수정.
## 수익률 분포 겹침(overlap)은 sigma로 자연 발생 — ADR 참고.
const TIER_PARAMS: Array[Dictionary] = [
	# TIER_BRONZE (0) — mu 100→25: 0% 수익 플레이어가 하위 5%→37백분위로 개선
	{ "mu": 25.0, "sigma": 55.0, "r_min": -60.0, "r_max": 600.0 },
	# TIER_SILVER (1)
	{ "mu": 40.0, "sigma": 50.0, "r_min": -60.0, "r_max": 650.0 },
	# TIER_GOLD (2)
	{ "mu": 60.0, "sigma": 45.0, "r_min": -60.0, "r_max": 550.0 },
	# TIER_PLATINUM (3)
	{ "mu": 80.0, "sigma": 40.0, "r_min": -60.0, "r_max": 500.0 },
	# TIER_EMERALD (4)
	{ "mu": 105.0, "sigma": 35.0, "r_min": -60.0, "r_max": 450.0 },
	# TIER_DIAMOND (5)
	{ "mu": 130.0, "sigma": 30.0, "r_min": -60.0, "r_max": 420.0 },
	# TIER_MASTER (6)
	{ "mu": 155.0, "sigma": 25.0, "r_min": -60.0, "r_max": 380.0 },
	# TIER_GRANDMASTER (7)
	{ "mu": 180.0, "sigma": 22.0, "r_min": -60.0, "r_max": 360.0 },
	# TIER_CHALLENGER (8)
	{ "mu": 205.0, "sigma": 18.0, "r_min": -60.0, "r_max": 320.0 },
	# TIER_LEGEND (9)
	{ "mu": 225.0, "sigma": 15.0, "r_min": -60.0, "r_max": 300.0 },
	# TIER_MASTER_OF_INVESTMENT (10)
	{ "mu": 250.0, "sigma": 20.0, "r_min": -60.0, "r_max": 500.0 },
]

# ── Internal State ──

## 시즌 시작 여부 플래그. EC-01 가드에 사용.
var _initialized: bool = false
## 장이 최초 개시된 후 true. PRE_MARKET 구간에서 수익률 조회를 차단한다.
## init_season() 시 false → on_market_open 수신 시 true (시즌 내 유지).
var _season_active: bool = false

## 플레이어 배정 티어 (0~10).
var _player_tier: int = 0

## 이 시즌의 글로벌 랜덤 시드.
var _season_seed: int = 0

## 현재 시즌 거래일 (0-based).
var _current_day: int = 0

## 현재 거래일 내 틱 번호 (0-based).
var _current_tick: int = 0

## 티어별 데이터. key = tier(int), value = Dictionary.
## 각 Dictionary 구조:
##   "count": int                        — 해당 티어 AI 인원수
##   "target_r": Array[float]            — 각 AI의 시즌 최종 목표 수익률
##   "daily_snapshots": Array            — day 인덱스별 Array[float] (lazy)
##   "bucket_edges": Array[float]        — 플레이어 티어 버킷 경계 (순위 추정용)
var _tier_data: Dictionary = {}

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
	_current_day = 0
	_current_tick = 0
	_tier_data.clear()

	for tier: int in participant_counts:
		var count: int = participant_counts[tier]
		var params: Dictionary = TIER_PARAMS[tier]
		var target_r: Array[float] = _generate_target_returns(tier, count, params)
		_tier_data[tier] = {
			"count": count,
			"target_r": target_r,
			"daily_snapshots": [],  # lazy evaluation — 글로벌 갱신 시 생성
			"bucket_edges": [],
		}

	# 플레이어 티어 버킷 초기화 (count > 0인 경우에만)
	if _tier_data.has(_player_tier) and _tier_data[_player_tier]["count"] > 0:
		_rebuild_player_tier_buckets()

	_initialized = true
	_season_active = false  # 장 개시 전까지 수익률 미공개

	# GDD §6: on_day_end → 실제: on_day_transition (GameClock에 존재하는 실제 시그널명)
	GameClock.on_day_transition.connect(_on_day_transition)
	GameClock.on_tick.connect(_on_tick)
	if not GameClock.on_market_open.is_connected(_on_market_open):
		GameClock.on_market_open.connect(_on_market_open)


## 매 틱 호출. 플레이어 소속 티어 내 특정 AI의 현재 return_pct를 반환한다.
## [br]participant_id: 0-based 인덱스 (해당 티어 내 순번)
## [br]반환값: float (%), 예) 12.4
## [br]Usage: var r := AiCompetitor.get_tier_return_pct(42)
func get_tier_return_pct(participant_id: int) -> float:
	# 장 개시 전 PRE_MARKET 구간: 수익률 미공개 (GDD §3-1 원칙 6)
	if not _season_active:
		return 0.0
	# EC-01: init_season 미호출 가드
	if not _initialized:
		push_warning("AiCompetitor: init_season not called")
		return 0.0

	if not _tier_data.has(_player_tier):
		push_warning("AiCompetitor: player tier %d has no data" % _player_tier)
		return 0.0

	var td: Dictionary = _tier_data[_player_tier]

	# EC-02: participant_id 범위 초과 가드
	if participant_id < 0 or participant_id >= td["count"]:
		push_warning("AiCompetitor: participant_id %d out of range (count=%d)" % [participant_id, td["count"]])
		return 0.0

	# EC-07: AI 0명인 경우
	if td["count"] == 0:
		push_warning("AiCompetitor: player tier %d has 0 participants" % _player_tier)
		return 0.0

	return _interpolate_return(_player_tier, participant_id)


## 일 1회(글로벌 갱신 시) 호출. 지정 티어 전체 AI의 return_pct 배열을 반환한다.
## [br]tier: 대상 티어 번호 (TIER_BRONZE ~ TIER_MASTER_OF_INVESTMENT)
## [br]반환값: Array[float], 인덱스 = participant_id
## [br]Usage: var all_r := AiCompetitor.get_all_return_pcts(AiCompetitor.TIER_BRONZE)
func get_all_return_pcts(tier: int) -> Array:
	# 장 개시 전 PRE_MARKET 구간: 수익률 미공개 (GDD §3-1 원칙 6)
	if not _season_active:
		return []
	if not _initialized:
		push_warning("AiCompetitor: init_season not called")
		return []

	if not _tier_data.has(tier):
		push_warning("AiCompetitor: tier %d has no data" % tier)
		return []

	var td: Dictionary = _tier_data[tier]

	# EC-07: 0명인 경우
	if td["count"] == 0:
		return []

	# EC-12: lazy evaluation — 당일 스냅샷 확보 (전일 스냅샷도 보간에 필요)
	_ensure_daily_snapshot(tier, _current_day)
	if _current_day > 0:
		_ensure_daily_snapshot(tier, _current_day - 1)

	var snapshots: Array = td["daily_snapshots"]
	var params: Dictionary = TIER_PARAMS[tier]

	# 인트라데이 보간 적용 — 장 시작 시 0%에서 출발해 하루 동안 점진적으로 변화.
	# _current_tick 기준으로 전일 종가(r_prev)와 당일 예상 종가(r_next) 사이를 선형 보간.
	var ticks_per_day: int = GameClock.TICKS_PER_DAY if GameClock.TICKS_PER_DAY > 0 else 1
	var progress: float = float(_current_tick) / float(ticks_per_day)

	var day_snap: Array = snapshots[_current_day]
	var result: Array[float] = []
	result.resize(td["count"])
	for i: int in range(td["count"]):
		var r_prev: float = 0.0
		if _current_day > 0 and (_current_day - 1) < snapshots.size() \
				and snapshots[_current_day - 1] != null:
			r_prev = (snapshots[_current_day - 1] as Array[float])[i]
		var r_next: float = day_snap[i]
		var interpolated: float = r_prev + (r_next - r_prev) * progress
		result[i] = clamp(interpolated, params["r_min"], params["r_max"])
	return result


## 거장 AI 메타데이터 반환 (옵션 인터페이스, LeagueUI 전용).
## [br]반환값: { "is_master_of_investment": bool, "display_name": String }
## [br]Usage: var meta := AiCompetitor.get_participant_meta(AiCompetitor.TIER_MASTER_OF_INVESTMENT, 0)
func get_participant_meta(tier: int, participant_id: int) -> Dictionary:
	return {
		"is_master_of_investment": tier == TIER_MASTER_OF_INVESTMENT,
		"display_name": "AI_%d_%d" % [tier, participant_id],
	}


## 플레이어 수익률을 기반으로 플레이어 티어 내 추정 순위를 반환한다.
## [br]GDD §4-4 버킷 기반 순위 추정 공식 구현.
## [br]player_return_pct: 플레이어 현재 수익률 (%)
## [br]반환값: int — 추정 순위 (1-based)
## [br]Usage: var rank := AiCompetitor.estimate_player_rank(player_return_pct)
func estimate_player_rank(player_return_pct: float) -> int:
	if not _initialized:
		push_error("AiCompetitor: init_season not called")
		return 0

	if not _tier_data.has(_player_tier):
		return 1

	var td: Dictionary = _tier_data[_player_tier]
	var bucket_edges: Array = td["bucket_edges"]

	if bucket_edges.is_empty():
		return 1

	# 이진 탐색 O(log RANK_BUCKETS)
	var bucket_idx: int = bucket_edges.bsearch(player_return_pct)
	var count: int = td["count"]
	return int(float(count) * (1.0 - float(bucket_idx) / float(RANK_BUCKETS))) + 1


## 당일 스냅샷 기준 내림차순 정렬 인덱스를 반환한다 (O(1) 캐시 조회).
## 리더보드 상위 K개 행 구성 시 get_interpolated_return()과 함께 사용.
## [br]반환값: Array[int] — 해당 티어의 participant_id를 종가 내림차순으로 정렬한 배열
func get_sorted_indices(tier: int) -> Array:
	if not _season_active or not _initialized:
		return []
	if not _tier_data.has(tier):
		return []
	_ensure_daily_snapshot(tier, _current_day)
	var td: Dictionary = _tier_data[tier]
	var si: Array = td.get("sorted_indices", [])
	if _current_day < si.size() and si[_current_day] != null:
		return si[_current_day]
	return []


## 지정 티어·참가자의 현재 틱 보간 수익률을 반환한다 (O(1)).
## 리더보드 K행 구성 시 get_sorted_indices()와 조합하여 O(K) 접근 실현.
## [br]tier: 대상 티어 번호
## [br]participant_id: 0-based 인덱스
## [br]반환값: float (%)
func get_interpolated_return(tier: int, participant_id: int) -> float:
	if not _season_active or not _initialized:
		return 0.0
	if not _tier_data.has(tier):
		return 0.0
	var td: Dictionary = _tier_data[tier]
	if participant_id < 0 or participant_id >= td["count"]:
		return 0.0
	return _interpolate_return(tier, participant_id)


## Resets all AI competitor state for unit tests. Call in before_each.
func reset_for_testing() -> void:
	_initialized = false
	_season_active = false
	_player_tier = 0
	_season_seed = 0
	_current_day = 0
	_current_tick = 0
	_tier_data.clear()

# ── Signal Handlers ──

## GameClock.on_market_open 핸들러. 시즌 내 첫 장 개시 시 수익률 공개 시작.
## PRE_MARKET 구간에서 수익률이 표시되는 것을 막기 위해 이 시점부터 활성화.
func _on_market_open() -> void:
	_season_active = true


## GameClock.on_tick 연결 핸들러. 플레이어 티어 틱 내 보간 상태 갱신.
func _on_tick(tick_number: int, _day: int, _week: int) -> void:
	_current_tick = tick_number


## GameClock.on_day_transition 연결 핸들러.
## GDD §6: on_day_end → 실제: on_day_transition (GameClock 실제 시그널명)
func _on_day_transition() -> void:
	_current_day += 1
	_current_tick = 0

	# 플레이어 티어 버킷 재계산 (하루 1회)
	if _tier_data.has(_player_tier):
		_ensure_daily_snapshot(_player_tier, _current_day)
		_rebuild_player_tier_buckets()

# ── Internal Generation ──

## GDD §4-1, §4-5: 시즌 최종 목표 수익률 배열 생성.
## participant_rng_seed = (season_seed × 1000003) XOR (participant_id × 998244353)
func _generate_target_returns(tier: int, count: int, params: Dictionary) -> Array[float]:
	var result: Array[float] = []
	result.resize(count)
	var mu: float    = params["mu"]
	var sigma: float = params["sigma"]
	var r_min: float = params["r_min"]
	var r_max: float = params["r_max"]
	var rng := RandomNumberGenerator.new()

	for i: int in range(count):
		# GDD §4-5 시드 생성 공식
		var p_seed: int = (_season_seed * 1000003) ^ (i * 998244353)
		# tier 오프셋 추가하여 같은 participant_id라도 티어별로 다른 수익률 생성
		p_seed = p_seed ^ (tier * 7919)
		rng.seed = p_seed
		# GDD §4-1: 정규분포 샘플링
		var raw: float = rng.randfn(mu, sigma)
		# EC-05 결정: target_r은 여기서 클램프 (중간 경로 cumulative_r은 무클램프)
		result[i] = clamp(raw, r_min, r_max)

	return result


## GDD §3-3 단계 2: 특정 티어·참가자의 일별 cumulative_r 배열 생성.
## 중간값은 PriceEngine.DAILY_LIMIT_PCT 기반 선형 누적 상한으로 클램프.
## 이유: AI 수익률은 실제 가격 움직임에서 도출되므로 상/하한가(±30%/일)를
##       초과하는 일별 누적 수익은 물리적으로 불가능.
## day D 최대: ±DAILY_LIMIT_PCT×(D+1) = ±30%×1, ±60%×2, …, ±600%×20
func _generate_cumulative_returns(tier: int, participant_id: int) -> Array[float]:
	var td: Dictionary = _tier_data[tier]
	var params: Dictionary = TIER_PARAMS[tier]
	var target_r: float = td["target_r"][participant_id]
	var sigma_daily: float = params["sigma"] / sqrt(float(SEASON_DAYS))
	var drift_per_day: float = target_r / float(SEASON_DAYS)

	# 이 참가자 전용 일별 RNG — 시드 추가 오프셋으로 target_r RNG와 분리
	var p_seed: int = (_season_seed * 1000003) ^ (participant_id * 998244353)
	p_seed = p_seed ^ (tier * 7919)
	p_seed = p_seed ^ 0xDEAD_BEEF  # daily RNG 분리 상수
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed

	# 일간 가격제한: PriceEngine.DAILY_LIMIT_PCT = 0.30 → 30%/일
	var daily_limit_pct: float = PriceEngine.DAILY_LIMIT_PCT * 100.0

	var cumulative: Array[float] = []
	cumulative.resize(SEASON_DAYS)
	var running: float = 0.0
	for d: int in range(SEASON_DAYS):
		# GDD §4-2: daily_return = drift + N(0, sigma_daily)
		var daily: float = drift_per_day + rng.randfn(0.0, sigma_daily)
		running += daily
		# day D 누적 수익은 D+1일치 상/하한가 이동량을 초과 불가
		var day_max: float = daily_limit_pct * float(d + 1)
		cumulative[d] = clampf(running, -day_max, day_max)

	return cumulative


## GDD §3-3 단계 2: 티어 전체 일별 스냅샷 생성 (lazy evaluation, EC-12).
## daily_snapshots[day] = Array[float] 길이 count
func _ensure_daily_snapshot(tier: int, day: int) -> void:
	if not _tier_data.has(tier):
		return

	var td: Dictionary = _tier_data[tier]
	var snapshots: Array = td["daily_snapshots"]

	# 이미 해당 일 스냅샷이 있으면 캐시 반환 (EC-12 이중 생성 방지)
	if day < snapshots.size() and snapshots[day] != null:
		return

	# 필요 일수만큼 슬롯 확장 (null로 채워 미계산 상태 표시)
	while snapshots.size() <= day:
		snapshots.append(null)

	var count: int = td["count"]
	var day_snap: Array[float] = []
	day_snap.resize(count)

	for i: int in range(count):
		var cumulative: Array[float] = _generate_cumulative_returns(tier, i)
		day_snap[i] = cumulative[day] if day < cumulative.size() else 0.0

	snapshots[day] = day_snap
	td["daily_snapshots"] = snapshots

	# 정렬 인덱스 캐시 — 종가 기준 내림차순. 리더보드 O(K) 접근에 사용.
	# 선형 보간은 순서를 보존하므로 종가 기준 정렬 = 인트라데이 정렬과 근사적으로 동일.
	var sorted_idx: Array[int] = []
	sorted_idx.resize(count)
	for j: int in range(count):
		sorted_idx[j] = j
	sorted_idx.sort_custom(func(a: int, b: int) -> bool: return day_snap[a] > day_snap[b])
	var si: Array = td.get("sorted_indices", [])
	while si.size() <= day:
		si.append(null)
	si[day] = sorted_idx
	td["sorted_indices"] = si


## GDD §3-3 단계 3: 틱 내 보간. 플레이어 티어 AI에 한정.
## return_pct(tick) = r_prev + (r_next - r_prev) × (tick / TICKS_PER_DAY)
func _interpolate_return(tier: int, participant_id: int) -> float:
	var td: Dictionary = _tier_data[tier]
	var params: Dictionary = TIER_PARAMS[tier]

	# EC-12: 당일 스냅샷 확보
	_ensure_daily_snapshot(tier, _current_day)

	var snapshots: Array = td["daily_snapshots"]

	# EC-04: current_day=0이면 r_prev=0.0 (첫날은 0%에서 출발)
	var r_prev: float = 0.0
	if _current_day > 0 and (_current_day - 1) < snapshots.size() and snapshots[_current_day - 1] != null:
		r_prev = (snapshots[_current_day - 1] as Array[float])[participant_id]

	var r_next: float = 0.0
	if _current_day < snapshots.size() and snapshots[_current_day] != null:
		r_next = (snapshots[_current_day] as Array[float])[participant_id]

	# EC-10: TICKS_PER_DAY=0 분모 0 방지
	var ticks_per_day: int = GameClock.TICKS_PER_DAY
	if ticks_per_day == 0:
		push_error("AiCompetitor: TICKS_PER_DAY is 0 — GameClock error")
		ticks_per_day = 1

	var progress: float = float(_current_tick) / float(ticks_per_day)
	var interpolated: float = r_prev + (r_next - r_prev) * progress

	# Q3 결정: 외부 반환값에만 clamp 적용 (EC-05)
	return clamp(interpolated, params["r_min"], params["r_max"])


## GDD §4-4: 플레이어 티어 버킷 경계 배열 재계산. 일 1회 갱신.
func _rebuild_player_tier_buckets() -> void:
	if not _tier_data.has(_player_tier):
		return

	var td: Dictionary = _tier_data[_player_tier]
	_ensure_daily_snapshot(_player_tier, _current_day)
	var snapshots: Array = td["daily_snapshots"]

	if _current_day >= snapshots.size() or snapshots[_current_day] == null:
		return

	var sorted_returns: Array[float] = (snapshots[_current_day] as Array[float]).duplicate()
	sorted_returns.sort()

	var count: int = sorted_returns.size()
	if count == 0:
		td["bucket_edges"] = []
		return

	var bucket_edges: Array[float] = []
	bucket_edges.resize(RANK_BUCKETS)

	for b: int in range(RANK_BUCKETS):
		var idx: int = clampi(b * count / RANK_BUCKETS, 0, count - 1)
		bucket_edges[b] = sorted_returns[idx]

	td["bucket_edges"] = bucket_edges


## GDD §7-2: 단조성 검증. init_season 호출 시 TIER_PARAMS 유효성 검사.
## 단조성은 mu 단독으로 보장 — r_min은 전 티어 동일값(-60%)이므로 r_min 검증 불필요.
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
