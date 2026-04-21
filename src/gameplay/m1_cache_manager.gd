## M1CacheManager — 종목별 1분봉(M1) 프리히스토리 생성·저장·메모리 관리.
##
## 설계 원칙:
##   1. 직전 N_IMMEDIATE_SEASONS 시즌: 종목 선택 시 즉시 생성 (스레드).
##   2. 그 이전 시즌: 차트 스크롤이 해당 구간에 접근할 때 온디맨드 생성.
##   3. 생성된 데이터는 user://m1_cache/{stock_id}_{season_idx}.bin 으로 저장
##      → 동일 시드라도 재생성하지 않아 영구 보존.
##   4. 메모리: LRU 방식으로 MAX_LOADED_SEASONS 개 시즌만 상주.
##      뷰포트 + 마진 구간을 벗어난 시즌은 evict → 필요 시 디스크에서 reload.
##
## 좌표계:
##   - "season_idx": 0 = 가장 오래된 프리히스토리 시즌, history_seasons-1 = 직전 시즌.
##   - "m1_idx": 전체 프리히스토리에서의 M1 캔들 절대 인덱스 (0-based).
##     season_idx s, day d, minute m → m1_idx = s*DAYS_PER_SEASON*MINUTES_PER_DAY + d*MINUTES_PER_DAY + m
##
## See: design/gdd/chart-renderer.md §프리히스토리 M1
## NOTE: class_name 생략 — 오토로드 싱글톤과 동명 클래스 충돌 방지 (Godot 제약).
extends Node

# ── 상수 ──────────────────────────────────────────────────────────────────────

## 종목 선택 시 즉시 생성할 직전 시즌 수.
const N_IMMEDIATE_SEASONS: int = 5
## 메모리에 동시 상주할 최대 시즌 수 (LRU). 시즌당 ~300KB.
const MAX_LOADED_SEASONS: int = 12
## 1 거래일 = 390분 (GameClock.MINUTES_PER_DAY).
const MINUTES_PER_DAY: int = 390
## 1 시즌 = 20 거래일.
const DAYS_PER_SEASON: int = 20
## 분당 최대 변동률 (±0.4%). 일봉 OHLC 엔벨로프 안에서 랜덤 워크.
const M1_VOLATILITY: float = 0.004
## 캐시 디렉토리 (user:// 아래).
const CACHE_DIR: String = "user://m1_cache/"

# ── 상태 ──────────────────────────────────────────────────────────────────────

## 현재 로드된 종목 ID. 다른 종목 선택 시 캐시 전체 초기화.
var _active_stock_id: String = ""
## 현재 종목의 history_seasons.
var _active_history_seasons: int = 0

## 로드된 시즌 데이터. key=season_idx, value={ohlc: PackedInt32Array, vol: PackedFloat32Array}
## ohlc 레이아웃: [open0, high0, low0, close0, open1, ...] (4 int per candle)
var _loaded: Dictionary = {}
## LRU 순서 추적. 가장 최근 접근한 season_idx가 뒤에 위치.
var _lru: Array[int] = []

## 즉시 생성 스레드.
var _thread: Thread = null
## 스레드 작업 완료 시그널.
signal immediate_seasons_ready(stock_id: String)
## 온디맨드 시즌 생성 완료 시그널. (season_idx, stock_id)
signal season_ready(season_idx: int, stock_id: String)

## RNG — 시드 기반 결정론적 생성. OhlcvHistory.history_seed 와 동일 시드 사용.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


# ── Public API ────────────────────────────────────────────────────────────────

## 종목 선택 시 호출. 직전 N_IMMEDIATE_SEASONS 시즌을 스레드로 즉시 생성.
## 다른 종목으로 전환하면 캐시 리셋 후 재시작.
## [param history_seed]: OhlcvHistory.history_seed 와 동일 값 사용.
func load_stock(stock_id: String, history_seasons: int, history_seed: int) -> void:
	if _active_stock_id == stock_id:
		return
	_cancel_thread()
	_loaded.clear()
	_lru.clear()
	_active_stock_id = stock_id
	_active_history_seasons = history_seasons
	_rng.seed = (history_seed ^ hash(stock_id)) & 0x7FFFFFFF
	_ensure_cache_dir()

	var first_immediate: int = maxi(0, history_seasons - N_IMMEDIATE_SEASONS)
	_thread = Thread.new()
	_thread.start(_generate_immediate_range.bind(stock_id, history_seasons, history_seed, first_immediate))


## 절대 M1 인덱스 범위 [start_idx, end_idx] 에 해당하는 캔들 배열 반환.
## 해당 시즌이 메모리에 없으면 디스크 또는 즉시 생성 후 반환.
## 뷰포트 렌더링에서 호출 — 반드시 메인 스레드에서 호출할 것.
func get_m1_candles(stock_id: String, start_idx: int, end_idx: int) -> Array[Dictionary]:
	if stock_id != _active_stock_id or _active_history_seasons == 0:
		return []
	var result: Array[Dictionary] = []
	var total_per_season: int = DAYS_PER_SEASON * MINUTES_PER_DAY
	var s_start: int = start_idx / total_per_season
	var s_end: int = end_idx / total_per_season
	for s: int in range(s_start, mini(s_end + 1, _active_history_seasons)):
		_ensure_season_loaded(stock_id, s, _active_history_seasons, OhlcvHistory.history_seed)
		if not _loaded.has(s):
			continue
		var data: Dictionary = _loaded[s]
		var ohlc: PackedInt32Array = data["ohlc"]
		var vol: PackedFloat32Array = data["vol"]
		var season_start_idx: int = s * total_per_season
		var local_start: int = maxi(0, start_idx - season_start_idx)
		var local_end: int = mini(total_per_season - 1, end_idx - season_start_idx)
		for i: int in range(local_start, local_end + 1):
			var base: int = i * 4
			if base + 3 >= ohlc.size():
				break
			result.append({
				"open":   ohlc[base],
				"high":   ohlc[base + 1],
				"low":    ohlc[base + 2],
				"close":  ohlc[base + 3],
				"volume": vol[i] if i < vol.size() else 0.0,
			})
	return result


## 현재 종목의 전체 프리히스토리 M1 캔들 수.
func get_total_m1_count() -> int:
	return _active_history_seasons * DAYS_PER_SEASON * MINUTES_PER_DAY


## 해당 시즌이 이미 생성(디스크 캐시 또는 메모리)되어 있는지 확인.
func is_season_available(season_idx: int) -> bool:
	if _loaded.has(season_idx):
		return true
	return FileAccess.file_exists(_cache_path(_active_stock_id, season_idx))


## 온디맨드 시즌 생성 트리거. 스크롤이 미생성 구간 접근 시 ChartRenderer가 호출.
## 완료 시 season_ready 시그널 emit.
func request_season(season_idx: int) -> void:
	if is_season_available(season_idx):
		return
	if _thread != null and _thread.is_alive():
		return  # 즉시 생성 스레드 동작 중 — 완료 후 처리
	_thread = Thread.new()
	_thread.start(_generate_single_season.bind(
		_active_stock_id, season_idx, _active_history_seasons, OhlcvHistory.history_seed
	))


# ── 스레드 작업 ───────────────────────────────────────────────────────────────

## 즉시 생성 범위 (직전 N_IMMEDIATE_SEASONS) 생성 후 시그널 emit.
func _generate_immediate_range(
	stock_id: String, history_seasons: int, history_seed: int, first_season: int
) -> void:
	var rng := RandomNumberGenerator.new()
	var d1_bars: Array[Dictionary] = _get_d1_bars(stock_id, history_seasons, history_seed, rng)
	for s: int in range(first_season, history_seasons):
		if not is_season_available(s):
			_generate_and_save(stock_id, s, d1_bars, rng)
	call_deferred("_on_immediate_done", stock_id)


## 단일 시즌 온디맨드 생성.
func _generate_single_season(
	stock_id: String, season_idx: int, history_seasons: int, history_seed: int
) -> void:
	var rng := RandomNumberGenerator.new()
	var d1_bars: Array[Dictionary] = _get_d1_bars(stock_id, history_seasons, history_seed, rng)
	_generate_and_save(stock_id, season_idx, d1_bars, rng)
	call_deferred("_on_season_done", stock_id, season_idx)


func _on_immediate_done(stock_id: String) -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	# 직전 N_IMMEDIATE_SEASONS 시즌을 메모리에 로드.
	var first: int = maxi(0, _active_history_seasons - N_IMMEDIATE_SEASONS)
	for s: int in range(first, _active_history_seasons):
		_load_season_from_disk(stock_id, s)
	immediate_seasons_ready.emit(stock_id)


func _on_season_done(stock_id: String, season_idx: int) -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_load_season_from_disk(stock_id, season_idx)
	season_ready.emit(season_idx, stock_id)


# ── D1 바 생성 (OhlcvHistory와 동일 알고리즘) ─────────────────────────────────

## stock_id 의 전체 D1 프리히스토리 바 배열 반환. OhlcvHistory._generate_pre_history() 와 동일 시드.
func _get_d1_bars(
	stock_id: String, history_seasons: int, history_seed: int, rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var stock_data: StockData = StockDatabase.get_stock(stock_id)
	var base_price: int = stock_data.base_price if stock_data != null else 10000
	rng.seed = (history_seed ^ hash(stock_id)) & 0x7FFFFFFF
	var result: Array[Dictionary] = []
	var close_prev: float = float(base_price)
	var total_days: int = history_seasons * DAYS_PER_SEASON
	for _i: int in range(total_days):
		var change: float = rng.randf_range(-0.03, 0.03)
		var close: float = maxf(close_prev * (1.0 + change), 100.0)
		var open_off: float = rng.randf_range(-0.015, 0.015)
		var open_price: float = close_prev * (1.0 + open_off)
		var body_high: float = maxf(open_price, close)
		var body_low: float = minf(open_price, close)
		var high: float = body_high * (1.0 + rng.randf_range(0.0, 0.03))
		var low: float = body_low * (1.0 - rng.randf_range(0.0, 0.03))
		var volume: float = rng.randf_range(100000.0, 2000000.0)
		result.append({
			"open": roundi(open_price), "high": roundi(high),
			"low": roundi(low), "close": roundi(close), "volume": volume,
		})
		close_prev = close
	return result


# ── M1 생성 + 저장 ────────────────────────────────────────────────────────────

## D1 바 배열에서 season_idx 에 해당하는 M1 캔들 생성 후 디스크에 저장.
func _generate_and_save(
	stock_id: String, season_idx: int, d1_bars: Array[Dictionary], rng: RandomNumberGenerator
) -> void:
	var total_per_season: int = DAYS_PER_SEASON * MINUTES_PER_DAY
	var ohlc := PackedInt32Array()
	ohlc.resize(total_per_season * 4)
	var vol := PackedFloat32Array()
	vol.resize(total_per_season)
	var day_base: int = season_idx * DAYS_PER_SEASON
	for d: int in range(DAYS_PER_SEASON):
		var bar_idx: int = day_base + d
		if bar_idx >= d1_bars.size():
			break
		var bar: Dictionary = d1_bars[bar_idx]
		var d1_open: int  = bar.get("open",   10000)
		var d1_high: int  = bar.get("high",   10000)
		var d1_low: int   = bar.get("low",    10000)
		var d1_close: int = bar.get("close",  10000)
		var d1_vol: float = bar.get("volume", 0.0)
		_expand_d1_to_m1(
			d1_open, d1_high, d1_low, d1_close, d1_vol,
			d * MINUTES_PER_DAY, ohlc, vol, rng
		)
	# 디스크에 저장.
	var path: String = _cache_path(stock_id, season_idx)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_var(ohlc)
		file.store_var(vol)
		file.close()


## D1 바 1개를 MINUTES_PER_DAY 개의 M1 캔들로 분해. PackedArray에 직접 기록 (zero-alloc).
## 가격 경로: 시가 → 종가로 편향된 랜덤 워크, D1 고가/저가 엔벨로프 내 클램핑.
func _expand_d1_to_m1(
	d1_open: int, d1_high: int, d1_low: int, d1_close: int, d1_vol: float,
	offset: int, ohlc: PackedInt32Array, vol: PackedFloat32Array,
	rng: RandomNumberGenerator
) -> void:
	var price: float = float(d1_open)
	var fhigh: float = float(d1_high)
	var flow: float  = float(d1_low)
	var target: float = float(d1_close)
	var range_size: float = maxf(fhigh - flow, 1.0)
	var vol_per_min: float = d1_vol / float(MINUTES_PER_DAY)

	for m: int in range(MINUTES_PER_DAY):
		var remaining: int = MINUTES_PER_DAY - m
		# 종가 방향으로 편향 (남은 분 수에 반비례하게 강해짐).
		var bias: float = (target - price) / float(remaining) * 0.5
		var noise: float = rng.randf_range(-M1_VOLATILITY, M1_VOLATILITY) * range_size * 0.5
		var next_price: float = price + bias + noise
		next_price = clampf(next_price, flow, fhigh)

		var m1_open: int  = roundi(price)
		var m1_close: int = roundi(next_price)
		var wicks: float  = range_size * rng.randf_range(0.001, 0.005)
		var m1_high: int  = mini(roundi(maxf(price, next_price) + wicks), d1_high)
		var m1_low: int   = maxi(roundi(minf(price, next_price) - wicks), d1_low)
		var m1_vol: float = vol_per_min * rng.randf_range(0.5, 1.5)

		var base: int = (offset + m) * 4
		ohlc[base]     = m1_open
		ohlc[base + 1] = m1_high
		ohlc[base + 2] = m1_low
		ohlc[base + 3] = m1_close
		vol[offset + m] = m1_vol
		price = next_price

	# 마지막 분 종가를 D1 종가로 고정 (연속성 보장).
	var last_base: int = (offset + MINUTES_PER_DAY - 1) * 4
	ohlc[last_base + 3] = d1_close


# ── 메모리 관리 (LRU) ─────────────────────────────────────────────────────────

## 디스크에서 시즌 데이터 로드 후 LRU 캐시에 등록. 초과 시 가장 오래된 시즌 evict.
func _load_season_from_disk(stock_id: String, season_idx: int) -> void:
	if _loaded.has(season_idx):
		_touch_lru(season_idx)
		return
	var path: String = _cache_path(stock_id, season_idx)
	if not FileAccess.file_exists(path):
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var ohlc: Variant = file.get_var()
	var vol: Variant  = file.get_var()
	file.close()
	if not (ohlc is PackedInt32Array and vol is PackedFloat32Array):
		return
	_loaded[season_idx] = {"ohlc": ohlc, "vol": vol}
	_lru.append(season_idx)
	_evict_if_needed()


## season_idx 가 메모리에 없으면 디스크 로드 또는 동기 생성.
func _ensure_season_loaded(
	stock_id: String, season_idx: int, history_seasons: int, history_seed: int
) -> void:
	if _loaded.has(season_idx):
		_touch_lru(season_idx)
		return
	if FileAccess.file_exists(_cache_path(stock_id, season_idx)):
		_load_season_from_disk(stock_id, season_idx)
		return
	# 캐시 없음 — 동기 생성 (스크롤 중 첫 접근 시 한 번만 발생).
	var rng := RandomNumberGenerator.new()
	var d1_bars: Array[Dictionary] = _get_d1_bars(stock_id, history_seasons, history_seed, rng)
	_generate_and_save(stock_id, season_idx, d1_bars, rng)
	_load_season_from_disk(stock_id, season_idx)


func _touch_lru(season_idx: int) -> void:
	_lru.erase(season_idx)
	_lru.append(season_idx)


func _evict_if_needed() -> void:
	while _lru.size() > MAX_LOADED_SEASONS:
		var oldest: int = _lru[0]
		_lru.remove_at(0)
		_loaded.erase(oldest)


# ── 유틸 ──────────────────────────────────────────────────────────────────────

func _cache_path(stock_id: String, season_idx: int) -> String:
	return CACHE_DIR + "%s_%04d.bin" % [stock_id, season_idx]


func _ensure_cache_dir() -> void:
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)


func _cancel_thread() -> void:
	if _thread != null and _thread.is_alive():
		_thread.wait_to_finish()
	_thread = null
