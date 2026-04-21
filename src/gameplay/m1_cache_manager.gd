## M1CacheManager — 종목별 1분봉(M1) 프리히스토리 생성·저장·메모리 관리.
##
## 설계 원칙:
##   1. D1 기반: M1 바는 반드시 OhlcvHistory 의 D1 바에서 파생 (가격 일관성 보장).
##      OhlcvHistory._generate_pre_history() 와 동일 시드·알고리즘 — 독립 RNG 없음.
##   2. 직전 N_IMMEDIATE_SEASONS 시즌: 종목 선택 시 스레드로 즉시 생성.
##   3. 그 이전 시즌: 차트 스크롤 접근 시 온디맨드 생성 (request_season()).
##   4. 생성된 데이터는 user://m1_cache/{stock_id}_{season_idx}.bin 에 저장 (영구 보존).
##   5. 메모리: LRU 방식으로 MAX_LOADED_SEASONS 개 시즌만 상주.
##
## 좌표계:
##   - "season_idx": 0 = 가장 오래된 프리히스토리 시즌, history_seasons-1 = 직전 시즌.
##   - "m1_idx": 전체 프리히스토리에서의 M1 캔들 절대 인덱스 (0-based).
##     season_idx s, day d, minute m → m1_idx = s*DAYS_PER_SEASON*MINUTES_PER_DAY + d*MINUTES_PER_DAY + m
##
## See: design/gdd/chart-renderer.md §5-3
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
## 장중 M1 노이즈 크기. D1 OHLC 엔벨로프 안에서만 움직이므로 작게 설정.
const M1_VOLATILITY: float = 0.004
## 캐시 디렉토리 (user:// 아래).
const CACHE_DIR: String = "user://m1_cache/"

# ── 상태 ──────────────────────────────────────────────────────────────────────

## 현재 로드된 종목 ID. 다른 종목 선택 시 캐시 전체 초기화.
var _active_stock_id: String = ""
## 현재 종목의 history_seasons.
var _active_history_seasons: int = 0
## 현재 종목의 D1 바 배열 — OhlcvHistory.get_all_daily_bars()에서 가져옴.
## 스레드에 전달하기 전 메인 스레드에서 채워진다 (thread-safe read-only).
var _d1_bars: Array[Dictionary] = []

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
## 인트로 프리히트 진행 시그널. (stock_id, done_count, total_count)
signal preheat_progress(stock_id: String, done: int, total: int)
## 인트로 프리히트 완료 시그널.
signal preheat_complete


# ── Public API ────────────────────────────────────────────────────────────────

## 종목 선택 시 호출. 직전 N_IMMEDIATE_SEASONS 시즌을 스레드로 즉시 생성.
## 다른 종목으로 전환하면 캐시 리셋 후 재시작.
## D1 bars는 메인 스레드에서 OhlcvHistory 에서 가져온 후 스레드에 전달한다.
func load_stock(stock_id: String, history_seasons: int) -> void:
	if _active_stock_id == stock_id:
		return
	_cancel_thread()
	_loaded.clear()
	_lru.clear()
	_active_stock_id = stock_id
	_active_history_seasons = history_seasons

	# D1 bars는 메인 스레드에서 가져온다 (thread-safe).
	# OhlcvHistory 가 내부 캐시를 가지므로 반복 접근은 O(1).
	_d1_bars = OhlcvHistory.get_all_daily_bars(stock_id)
	_ensure_cache_dir()

	var first_immediate: int = maxi(0, history_seasons - N_IMMEDIATE_SEASONS)
	_thread = Thread.new()
	_thread.start(_generate_immediate_range.bind(stock_id, first_immediate, _d1_bars))


## 인트로 시퀀스 중 백그라운드 프리히트.
## 첫 번째 종목의 즉시 시즌을 미리 생성한다.
## 완료 시 preheat_complete 시그널. 이미 다른 스레드 동작 중이면 무시.
func preheat_first_stock() -> void:
	if _thread != null and _thread.is_alive():
		return
	var all_ids: Array[String] = StockDatabase.get_all_stock_ids()
	if all_ids.is_empty():
		preheat_complete.emit()
		return
	var stock_id: String = all_ids[0]
	var stock: StockData = StockDatabase.get_stock(stock_id)
	if stock == null:
		preheat_complete.emit()
		return
	# 이미 load_stock() 이 같은 종목으로 불린 상태면 skip.
	if _active_stock_id == stock_id:
		preheat_complete.emit()
		return

	_active_stock_id = stock_id
	_active_history_seasons = stock.history_seasons
	_d1_bars = OhlcvHistory.get_all_daily_bars(stock_id)
	_ensure_cache_dir()

	var first_immediate: int = maxi(0, stock.history_seasons - N_IMMEDIATE_SEASONS)
	_thread = Thread.new()
	_thread.start(_generate_preheat.bind(stock_id, first_immediate, _d1_bars))


## 절대 M1 인덱스 범위 [start_idx, end_idx] 에 해당하는 캔들 배열 반환.
## 해당 시즌이 메모리에 없으면 디스크 로드 또는 동기 생성 후 반환.
## 뷰포트 렌더링에서 호출 — 반드시 메인 스레드에서 호출할 것.
func get_m1_candles(stock_id: String, start_idx: int, end_idx: int) -> Array[Dictionary]:
	if stock_id != _active_stock_id or _active_history_seasons == 0:
		return []
	var result: Array[Dictionary] = []
	var total_per_season: int = DAYS_PER_SEASON * MINUTES_PER_DAY
	var s_start: int = start_idx / total_per_season
	var s_end: int = end_idx / total_per_season
	for s: int in range(s_start, mini(s_end + 1, _active_history_seasons)):
		_ensure_season_loaded(stock_id, s)
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


## 로드된 시즌 전체를 [param m1_per_candle] M1 단위로 집계해 반환.
## PackedArray에서 직접 집계 — Dictionary 변환 비용 = 출력 캔들 수만큼 (입력 M1 수 아님).
## [param m1_per_candle]: 1=M1, 5=M5, 15=M15
func get_aggregated_candles(stock_id: String, m1_per_candle: int) -> Array[Dictionary]:
	if stock_id != _active_stock_id or _loaded.is_empty():
		return []
	if m1_per_candle <= 0:
		return []
	var result: Array[Dictionary] = []
	# 오름차순으로 처리 (시간순).
	var seasons: Array = _loaded.keys()
	seasons.sort()
	for s: Variant in seasons:
		var data: Dictionary = _loaded[s]
		var ohlc: PackedInt32Array = data["ohlc"]
		var vol: PackedFloat32Array = data["vol"]
		var total_m1: int = ohlc.size() / 4
		var i: int = 0
		while i + m1_per_candle <= total_m1:
			var base0: int = i * 4
			var o: int = ohlc[base0]
			var h: int = ohlc[base0 + 1]
			var l: int = ohlc[base0 + 2]
			var c: int = 0
			var v: float = 0.0
			for j: int in range(m1_per_candle):
				var b: int = (i + j) * 4
				h = maxi(h, ohlc[b + 1])
				l = mini(l, ohlc[b + 2])
				c = ohlc[b + 3]
				v += vol[i + j] if (i + j) < vol.size() else 0.0
			result.append({"open": o, "high": h, "low": l, "close": c, "volume": v})
			i += m1_per_candle
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
		_active_stock_id, season_idx, _d1_bars
	))


# ── 스레드 작업 ───────────────────────────────────────────────────────────────

## 즉시 생성 범위 (직전 N_IMMEDIATE_SEASONS) 생성 후 시그널 emit.
func _generate_immediate_range(
	stock_id: String, first_season: int, d1_bars: Array[Dictionary]
) -> void:
	for s: int in range(first_season, _active_history_seasons):
		if not is_season_available(s):
			_generate_and_save(stock_id, s, d1_bars)
	call_deferred("_on_immediate_done", stock_id)


## 인트로 프리히트 — 즉시 시즌 생성 후 preheat_complete 시그널 emit.
func _generate_preheat(
	stock_id: String, first_season: int, d1_bars: Array[Dictionary]
) -> void:
	var total: int = _active_history_seasons - first_season
	var done: int = 0
	for s: int in range(first_season, _active_history_seasons):
		if not is_season_available(s):
			_generate_and_save(stock_id, s, d1_bars)
		done += 1
		call_deferred("_emit_preheat_progress", stock_id, done, total)
	call_deferred("_on_preheat_done", stock_id)


## 단일 시즌 온디맨드 생성.
func _generate_single_season(
	stock_id: String, season_idx: int, d1_bars: Array[Dictionary]
) -> void:
	_generate_and_save(stock_id, season_idx, d1_bars)
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


func _on_preheat_done(stock_id: String) -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	var first: int = maxi(0, _active_history_seasons - N_IMMEDIATE_SEASONS)
	for s: int in range(first, _active_history_seasons):
		_load_season_from_disk(stock_id, s)
	preheat_complete.emit()


func _on_season_done(stock_id: String, season_idx: int) -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_load_season_from_disk(stock_id, season_idx)
	season_ready.emit(season_idx, stock_id)


func _emit_preheat_progress(stock_id: String, done: int, total: int) -> void:
	preheat_progress.emit(stock_id, done, total)


# ── M1 생성 + 저장 ────────────────────────────────────────────────────────────

## D1 바 배열에서 season_idx 에 해당하는 M1 캔들 생성 후 디스크에 저장.
## D1 bars는 OhlcvHistory.get_all_daily_bars() 에서 가져온 것이어야 한다.
func _generate_and_save(
	stock_id: String, season_idx: int, d1_bars: Array[Dictionary]
) -> void:
	var total_per_season: int = DAYS_PER_SEASON * MINUTES_PER_DAY
	var ohlc := PackedInt32Array()
	ohlc.resize(total_per_season * 4)
	var vol := PackedFloat32Array()
	vol.resize(total_per_season)
	var rng := RandomNumberGenerator.new()
	# season_idx-specific seed — 같은 시드라도 시즌마다 다른 장중 패턴.
	rng.seed = (OhlcvHistory.history_seed ^ hash(stock_id) ^ (season_idx * 9973)) & 0x7FFFFFFF
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
## 메인 스레드에서만 호출 (get_m1_candles 내부).
func _ensure_season_loaded(stock_id: String, season_idx: int) -> void:
	if _loaded.has(season_idx):
		_touch_lru(season_idx)
		return
	if FileAccess.file_exists(_cache_path(stock_id, season_idx)):
		_load_season_from_disk(stock_id, season_idx)
		return
	# 캐시 없음 — 동기 생성 (스크롤 중 첫 접근 시 한 번만 발생).
	_generate_and_save(stock_id, season_idx, _d1_bars)
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
