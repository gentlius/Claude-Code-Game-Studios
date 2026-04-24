## M1CacheManager — M1-first 배치 프리히스토리 생성·2-tier 캐시 관리.
##
## 설계 원칙 (ADR-024 Phase 1):
##   1. M1-first: Markov M1 직접 생성 → D1 누적 (D1→M1 확장 폐기).
##   2. 2-tier 캐시: M1 7,800 bars (1시즌) + D1 5,200 bars (260시즌) per stock per slot.
##   3. 배치 생성: generate_all() 한 번 호출 → 전 종목 백그라운드 생성 → batch_complete emit.
##   4. 슬롯별 격리: user://m1_cache/slot_{id}/{stock_id}.bin (ADR-024)
##   5. OhlcvHistory 의존성 역전: get_d1_candles() → OhlcvHistory._generate_pre_history() 대체.
##
## See: design/gdd/chart-renderer.md §5-3, docs/architecture/024-price-engine-gdextension.md
## NOTE: class_name 생략 — 오토로드 싱글톤과 동명 클래스 충돌 방지 (Godot 제약).
extends Node

# ── Constants ──────────────────────────────────────────────────────────────────

## M1 캐시 크기: 1시즌 = 20거래일 × 390분. M1/M5/M15 프리히스토리 소스.
const M1_CACHE_BARS: int = 7800
## D1 캐시 크기: 300시즌 × 20거래일. D1/W1/MN 프리히스토리 소스.
const D1_CACHE_BARS: int = 6000
## 1 거래일 분 수 (GameClock.MINUTES_PER_DAY).
const MINUTES_PER_DAY: int = 390
## 1 시즌 거래일 수.
const DAYS_PER_SEASON: int = 20
## 캐시 파일 버전 — 이 값이 변경되면 디스크 캐시 전체 무효화 후 재생성 (ADR-024).
const CACHE_VERSION: int = 9  ## Bumped: Phase E PriceKernel full-kernel simulation replaces MarkovGenerator-only prehistory (ADR-027)
## 캐시 루트 디렉토리 (user:// 아래). 슬롯별 격리 → _cache_dir() 참조.
const CACHE_ROOT: String = "user://m1_cache/"

# ── Signals ────────────────────────────────────────────────────────────────────

## 배치 생성 진행 시그널. (done, total) — 인트로 로딩 바에서 소비.
signal batch_progress(done: int, total: int)
## 배치 생성 완료 시그널 — 전 종목 캐시 메모리 준비 완료.
signal batch_complete

# ── Per-Stock Memory Cache ─────────────────────────────────────────────────────

## stock_id → PackedInt32Array (M1_CACHE_BARS × 4) [open, high, low, close per bar]
var _m1_ohlc: Dictionary = {}
## stock_id → PackedFloat32Array (M1_CACHE_BARS)
var _m1_vol: Dictionary = {}
## stock_id → PackedInt32Array (D1_CACHE_BARS × 4)
var _d1_ohlc: Dictionary = {}
## stock_id → PackedFloat32Array (D1_CACHE_BARS)
var _d1_vol: Dictionary = {}
## stock_id → int (실제 M1 bar 수 ≤ M1_CACHE_BARS)
var _m1_count: Dictionary = {}
## stock_id → int (실제 D1 bar 수 ≤ D1_CACHE_BARS)
var _d1_count: Dictionary = {}

# ── Thread State ───────────────────────────────────────────────────────────────

var _thread: Thread = null
var _batch_done: bool = false
## Phase E: simulation results from main-thread run, consumed by _batch_thread for disk I/O.
var _pending_sim_results: Dictionary = {}

# ── Public API ─────────────────────────────────────────────────────────────────

## 전 종목 M1+D1 프리히스토리를 백그라운드 스레드로 생성.
## [param stocks]: StockData 배열 (StockDatabase.get_all_stocks()).
## [param history_seed]: OhlcvHistory.history_seed.
## 디스크 캐시가 유효하면 (버전·시드 일치) 재생성 없이 디스크에서 로드.
## 완료 시 batch_complete emit. 진행 중 batch_progress(done, total) emit.
## 배치 생성이 완료됐는지 반환. batch_complete 이미 emit된 경우 true.
func is_batch_done() -> bool:
	return _batch_done


func generate_all(stocks: Array, history_seed: int) -> void:
	_batch_done = false
	_cancel_thread()
	_ensure_cache_dir()
	_pending_sim_results = {}

	# Phase E: run full-kernel simulation on main thread for stocks with invalid cache.
	# C++ is fast enough (100 seasons, 15 stocks ≈ 1-3 s); disk I/O runs in the thread.
	var needs_regen := false
	for stock in stocks:
		if stock is StockData:
			if not _disk_cache_valid(_stock_cache_path((stock as StockData).stock_id), history_seed):
				needs_regen = true
				break

	if needs_regen:
		var n_seasons := 1
		for stock in stocks:
			if stock is StockData:
				n_seasons = maxi(n_seasons, (stock as StockData).history_seasons)
		# Empty theme dicts → default sector weights (no seasonal bias in prehistory)
		var theme_seq: Array = []
		theme_seq.resize(n_seasons)
		for i in range(n_seasons):
			theme_seq[i] = {}
		_pending_sim_results = PriceEngine.run_historical_simulation(
			n_seasons, DAYS_PER_SEASON, GameClock.TICKS_PER_DAY, theme_seq, history_seed)

	_thread = Thread.new()
	_thread.start(_batch_thread.bind(stocks, history_seed))


## 모든 메모리 캐시 초기화 + 진행 중 스레드 취소.
## 슬롯 전환 또는 새 게임 시작 시 reset() 전에 호출.
func reset() -> void:
	_cancel_thread()
	_batch_done = false
	_m1_ohlc.clear()
	_m1_vol.clear()
	_d1_ohlc.clear()
	_d1_vol.clear()
	_m1_count.clear()
	_d1_count.clear()


## 현재 슬롯의 디스크 캐시 파일 전체 삭제.
## 새 게임 시 이전 슬롯의 캐시가 혼입되는 것을 방지한다.
func clear_slot_cache() -> void:
	var dir: String = _cache_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return
	var da: DirAccess = DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	var fname: String = da.get_next()
	while fname != "":
		if not da.current_is_dir():
			da.remove(fname)
		fname = da.get_next()
	da.list_dir_end()


## stock_id 의 캐시가 메모리에 준비되어 있는지 반환.
## OhlcvHistory._generate_pre_history() 가 이 값으로 준비 상태를 확인한다.
func is_cache_ready(stock_id: String) -> bool:
	return _m1_ohlc.has(stock_id)


## M1 캐시를 m1_per_candle 단위로 집계해 반환. 1=M1, 5=M5, 15=M15.
## PackedArray에서 직접 집계 — 출력 캔들 수만큼만 Dictionary 할당 (zero-alloc inner loop).
func get_aggregated_m1(stock_id: String, m1_per_candle: int) -> Array[Dictionary]:
	if not _m1_ohlc.has(stock_id) or m1_per_candle <= 0:
		return []
	var total_m1: int = _m1_count.get(stock_id, 0)
	return _aggregate_packed(_m1_ohlc[stock_id], _m1_vol[stock_id], total_m1, m1_per_candle)


## D1 캐시를 d1_per_candle 단위로 집계해 반환. 1=D1, 5=W1, 20=MN.
func get_aggregated_d1(stock_id: String, d1_per_candle: int) -> Array[Dictionary]:
	if not _d1_ohlc.has(stock_id) or d1_per_candle <= 0:
		return []
	var total_d1: int = _d1_count.get(stock_id, 0)
	return _aggregate_packed(_d1_ohlc[stock_id], _d1_vol[stock_id], total_d1, d1_per_candle)


## OhlcvHistory 의존성 역전: D1 캔들을 Array[Dictionary] 형태로 반환.
## M1-first 방식으로 생성된 D1 집계 데이터를 OhlcvHistory._generate_pre_history() 에 제공.
func get_d1_candles(stock_id: String) -> Array[Dictionary]:
	return get_aggregated_d1(stock_id, 1)


## M1 캔들을 Array[Dictionary] 형태로 반환.
func get_m1_candles(stock_id: String) -> Array[Dictionary]:
	return get_aggregated_m1(stock_id, 1)


## 프리히스토리 마지막 M1 bar의 종가를 반환.
## PriceEngine.sync_prices_from_prehistory()가 호출 — 새 게임 시 프리히스토리 끝 가격으로
## current_price를 맞춰 차트 연속성을 보장한다. append_season_m1() 이후에는
## 마지막 라이브 시즌의 종가를 반환한다 (M1 링 버퍼가 실시간 시즌 데이터를 포함하므로).
## 캐시가 없거나 bar 수가 0이면 0 반환 (호출부에서 0 == skip 처리).
func get_last_prehistory_close(stock_id: String) -> int:
	var count: int = _m1_count.get(stock_id, 0)
	if count == 0 or not _m1_ohlc.has(stock_id):
		return 0
	# PackedInt32Array: 4 ints per bar [open, high, low, close]
	return _m1_ohlc[stock_id][(count - 1) * 4 + 3]


## 런타임 시즌 종료 시 시즌의 tick 데이터를 M1 bar로 집계해 in-memory 캐시에 누적.
## PriceEngine._on_season_start()가 append_season_d1()과 함께 호출한다.
## GameClock.TICKS_PER_MINUTE = 4 틱을 1 M1 bar로 집계한다 (OHLC + vol sum).
## M1_CACHE_BARS 초과분은 오래된 것부터 제거 (링 버퍼 슬라이딩 윈도우).
## 시즌이 완전히 거래되지 않은 경우 (완전하지 않은 틱 그룹) 마지막 불완전 bar는 무시한다.
## [param stock_id]: 종목 ID.
## [param tick_prices]: PriceEngine._stock_states[stock_id]["tick_prices"] — 이번 시즌 틱 가격.
## [param tick_volumes]: PriceEngine._stock_states[stock_id]["tick_volumes"] — 이번 시즌 틱 거래량.
func append_season_m1(stock_id: String, tick_prices: Array, tick_volumes: Array) -> void:
	const TICKS_PER_M1: int = 4  # GameClock.TICKS_PER_MINUTE — 4 ticks per M1 bar
	if tick_prices.size() < TICKS_PER_M1 or not _m1_ohlc.has(stock_id):
		return

	var n_m1: int = tick_prices.size() / TICKS_PER_M1  # complete M1 bars only

	var existing_count: int = _m1_count.get(stock_id, 0)
	var m1_ohlc_arr: PackedInt32Array   = _m1_ohlc.get(stock_id, PackedInt32Array())
	var m1_vol_arr:  PackedFloat32Array = _m1_vol.get(stock_id, PackedFloat32Array())

	# Ring buffer: if appending n_m1 bars would exceed M1_CACHE_BARS, shift out oldest first.
	if existing_count + n_m1 > M1_CACHE_BARS:
		var drop: int = existing_count + n_m1 - M1_CACHE_BARS
		drop = mini(drop, existing_count)
		var keep: int = existing_count - drop
		for i: int in range(keep):
			var src: int = (i + drop) * 4
			var dst: int = i * 4
			m1_ohlc_arr[dst]     = m1_ohlc_arr[src]
			m1_ohlc_arr[dst + 1] = m1_ohlc_arr[src + 1]
			m1_ohlc_arr[dst + 2] = m1_ohlc_arr[src + 2]
			m1_ohlc_arr[dst + 3] = m1_ohlc_arr[src + 3]
			m1_vol_arr[i] = m1_vol_arr[i + drop]
		existing_count = keep

	# Ensure packed arrays are large enough.
	var target: int = mini(existing_count + n_m1, M1_CACHE_BARS)
	if m1_ohlc_arr.size() < target * 4:
		m1_ohlc_arr.resize(target * 4)
	if m1_vol_arr.size() < target:
		m1_vol_arr.resize(target)

	# Append new M1 bars (one per TICKS_PER_M1 ticks).
	# Prices from live tick_prices are already tick-aligned by PriceEngine.round_to_tick()
	# at injection time (process_tick → final_price). No extra rounding needed here.
	var n_ticks: int = tick_prices.size()
	for i: int in range(n_m1):
		if existing_count >= M1_CACHE_BARS:
			break
		var tb: int = i * TICKS_PER_M1
		var t0: int = int(tick_prices[tb])
		var t1: int = int(tick_prices[tb + 1]) if tb + 1 < n_ticks else t0
		var t2: int = int(tick_prices[tb + 2]) if tb + 2 < n_ticks else t0
		var t3: int = int(tick_prices[tb + 3]) if tb + 3 < n_ticks else t0
		var bar_base: int = existing_count * 4
		m1_ohlc_arr[bar_base]     = t0                              # open
		m1_ohlc_arr[bar_base + 1] = maxi(t0, maxi(t1, maxi(t2, t3)))  # high
		m1_ohlc_arr[bar_base + 2] = mini(t0, mini(t1, mini(t2, t3)))  # low
		m1_ohlc_arr[bar_base + 3] = t3                              # close
		var vol: float = 0.0
		for j: int in range(TICKS_PER_M1):
			if tb + j < tick_volumes.size():
				vol += float(tick_volumes[tb + j])
		m1_vol_arr[existing_count] = vol
		existing_count += 1

	_m1_ohlc[stock_id]  = m1_ohlc_arr
	_m1_vol[stock_id]   = m1_vol_arr
	_m1_count[stock_id] = existing_count


## 런타임 시즌 종료 시 D1 캔들을 in-memory 캐시에 누적 (ADR-026).
## PriceEngine._reset_season_mechanics()가 ohlcv_daily를 초기화하기 전에 호출한다.
## 새 D1 bars를 링 버퍼에 append하고 D1_CACHE_BARS 초과분은 오래된 것부터 제거한다.
## 캐시를 디스크에 저장하여 다음 세션에서도 누적 D1 히스토리를 유지한다.
## [param stock_id]: 종목 ID.
## [param ohlcv_daily]: PriceEngine._stock_states[stock_id]["ohlcv_daily"] — 이번 시즌 D1 배열.
func append_season_d1(stock_id: String, ohlcv_daily: Array) -> void:
	if ohlcv_daily.is_empty() or not _d1_ohlc.has(stock_id):
		return

	var existing_count: int = _d1_count.get(stock_id, 0)
	var d1_ohlc_arr: PackedInt32Array   = _d1_ohlc.get(stock_id, PackedInt32Array())
	var d1_vol_arr:  PackedFloat32Array = _d1_vol.get(stock_id, PackedFloat32Array())

	# Expand packed arrays if needed to hold more bars
	var target_count: int = mini(existing_count + ohlcv_daily.size(), D1_CACHE_BARS)
	if d1_ohlc_arr.size() < target_count * 4:
		d1_ohlc_arr.resize(target_count * 4)
	if d1_vol_arr.size() < target_count:
		d1_vol_arr.resize(target_count)

	# If new bars would exceed D1_CACHE_BARS, shift out oldest bars first (ring-buffer semantics)
	var new_bar_count: int = ohlcv_daily.size()
	if existing_count + new_bar_count > D1_CACHE_BARS:
		var drop: int = existing_count + new_bar_count - D1_CACHE_BARS
		# Shift existing bars left by 'drop' positions
		for i: int in range(existing_count - drop):
			var src: int = (i + drop) * 4
			var dst: int = i * 4
			d1_ohlc_arr[dst]     = d1_ohlc_arr[src]
			d1_ohlc_arr[dst + 1] = d1_ohlc_arr[src + 1]
			d1_ohlc_arr[dst + 2] = d1_ohlc_arr[src + 2]
			d1_ohlc_arr[dst + 3] = d1_ohlc_arr[src + 3]
			d1_vol_arr[i] = d1_vol_arr[i + drop]
		existing_count -= drop

	# Append new season bars
	for candle: Dictionary in ohlcv_daily:
		if existing_count >= D1_CACHE_BARS:
			break
		var base: int = existing_count * 4
		if base + 3 >= d1_ohlc_arr.size():
			d1_ohlc_arr.resize(base + 4)
		if existing_count >= d1_vol_arr.size():
			d1_vol_arr.resize(existing_count + 1)
		d1_ohlc_arr[base]     = int(candle.get("open",   0))
		d1_ohlc_arr[base + 1] = int(candle.get("high",   0))
		d1_ohlc_arr[base + 2] = int(candle.get("low",    0))
		d1_ohlc_arr[base + 3] = int(candle.get("close",  0))
		d1_vol_arr[existing_count] = float(candle.get("volume", 0.0))
		existing_count += 1

	_d1_ohlc[stock_id]  = d1_ohlc_arr
	_d1_vol[stock_id]   = d1_vol_arr
	_d1_count[stock_id] = existing_count

	# Persist updated cache to disk so next session loads the accumulated history
	var cache_path: String = _stock_cache_path(stock_id)
	_save_d1_to_disk(cache_path, stock_id)


## D1 캐시만 디스크에 저장 (append_season_d1 전용 — M1은 변경 없으므로 생략).
## 기존 파일에서 버전·시드를 읽어 헤더를 재사용한다. 파일 없으면 skip.
func _save_d1_to_disk(path: String, stock_id: String) -> void:
	# Read existing header (version + seed) to preserve them
	if not FileAccess.file_exists(path):
		return
	var rf: FileAccess = FileAccess.open(path, FileAccess.READ)
	if rf == null:
		return
	var version: Variant  = rf.get_var()
	var seed_val: Variant = rf.get_var()
	var _m1c: Variant     = rf.get_var()
	var m1_ohlc: Variant  = rf.get_var()
	var m1_vol: Variant   = rf.get_var()
	rf.close()

	var wf: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if wf == null:
		push_error("M1CacheManager: D1 append 저장 실패 — %s" % path)
		return
	wf.store_var(version)
	wf.store_var(seed_val)
	wf.store_var(_m1c)
	wf.store_var(m1_ohlc if m1_ohlc is PackedInt32Array else _m1_ohlc.get(stock_id, PackedInt32Array()))
	wf.store_var(m1_vol  if m1_vol  is PackedFloat32Array else _m1_vol.get(stock_id, PackedFloat32Array()))
	wf.store_var(_d1_count.get(stock_id, 0))
	wf.store_var(_d1_ohlc.get(stock_id,  PackedInt32Array()))
	wf.store_var(_d1_vol.get(stock_id,   PackedFloat32Array()))
	wf.close()


# ── Thread Work ────────────────────────────────────────────────────────────────

## 백그라운드 스레드 메인 루프.
## Phase E: 캐시 히트 → 디스크 로드. 캐시 미스 → _pending_sim_results에서 읽어 디스크 저장.
## _pending_sim_results은 generate_all()이 main thread에서 미리 채워둔다.
## 완료 후 call_deferred로 메모리 로드 + 시그널 emit.
func _batch_thread(stocks: Array, history_seed: int) -> void:
	var total: int = stocks.size()
	var batch_results: Dictionary = {}

	for i: int in range(total):
		var stock: StockData = stocks[i] as StockData
		if stock == null:
			call_deferred("_on_stock_progress", i + 1, total)
			continue

		var cache_path: String = _stock_cache_path(stock.stock_id)
		var result: Dictionary

		if _disk_cache_valid(cache_path, history_seed):
			result = _load_from_disk(cache_path)
		elif _pending_sim_results.has(stock.stock_id):
			# Phase E: use pre-computed simulation result, then persist to disk
			result = _pending_sim_results[stock.stock_id]
			_save_to_disk(cache_path, history_seed, result)
		# else: simulation failed or stock wasn't registered — result stays empty

		if not result.is_empty():
			batch_results[stock.stock_id] = result

		call_deferred("_on_stock_progress", i + 1, total)

	call_deferred("_on_batch_done", batch_results)


func _on_stock_progress(done: int, total: int) -> void:
	batch_progress.emit(done, total)


func _on_batch_done(results: Dictionary) -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

	for stock_id: String in results:
		var data: Dictionary = results[stock_id]
		_m1_ohlc[stock_id]  = data.get("m1_ohlc",  PackedInt32Array())
		_m1_vol[stock_id]   = data.get("m1_vol",   PackedFloat32Array())
		_d1_ohlc[stock_id]  = data.get("d1_ohlc",  PackedInt32Array())
		_d1_vol[stock_id]   = data.get("d1_vol",   PackedFloat32Array())
		_m1_count[stock_id] = data.get("m1_count", 0)
		_d1_count[stock_id] = data.get("d1_count", 0)

	_batch_done = true
	batch_complete.emit()


# ── Disk I/O ───────────────────────────────────────────────────────────────────

## 캐시 파일의 버전·시드가 현재 값과 일치하는지 확인. 일치해야만 로드한다.
func _disk_cache_valid(path: String, history_seed: int) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var version: Variant = file.get_var()
	var seed: Variant    = file.get_var()
	file.close()
	return (version is int and version == CACHE_VERSION
		and seed is int and seed == history_seed)


## 디스크에서 캐시 데이터 로드 (버전·시드 검증은 _disk_cache_valid에서 완료된 상태).
func _load_from_disk(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var _ver: Variant     = file.get_var()  # skip: already validated
	var _seed: Variant    = file.get_var()  # skip: already validated
	var m1_count: Variant = file.get_var()
	var m1_ohlc: Variant  = file.get_var()
	var m1_vol: Variant   = file.get_var()
	var d1_count: Variant = file.get_var()
	var d1_ohlc: Variant  = file.get_var()
	var d1_vol: Variant   = file.get_var()
	file.close()
	if not (m1_ohlc is PackedInt32Array and m1_vol is PackedFloat32Array
			and d1_ohlc is PackedInt32Array and d1_vol is PackedFloat32Array):
		return {}
	return {
		"m1_count": int(m1_count) if m1_count is int else 0,
		"m1_ohlc":  m1_ohlc as PackedInt32Array,
		"m1_vol":   m1_vol  as PackedFloat32Array,
		"d1_count": int(d1_count) if d1_count is int else 0,
		"d1_ohlc":  d1_ohlc as PackedInt32Array,
		"d1_vol":   d1_vol  as PackedFloat32Array,
	}


## 생성된 캐시 데이터를 디스크에 저장.
func _save_to_disk(path: String, history_seed: int, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("M1CacheManager: 캐시 저장 실패 — %s" % path)
		return
	file.store_var(CACHE_VERSION)
	file.store_var(history_seed)
	file.store_var(data.get("m1_count", 0))
	file.store_var(data.get("m1_ohlc",  PackedInt32Array()))
	file.store_var(data.get("m1_vol",   PackedFloat32Array()))
	file.store_var(data.get("d1_count", 0))
	file.store_var(data.get("d1_ohlc",  PackedInt32Array()))
	file.store_var(data.get("d1_vol",   PackedFloat32Array()))
	file.close()


# ── Aggregation ────────────────────────────────────────────────────────────────

## PackedArray를 bars_per_candle 단위로 집계. 입력 bar 수 아닌 출력 수만큼 Dictionary 할당.
func _aggregate_packed(
	ohlc: PackedInt32Array,
	vol: PackedFloat32Array,
	bar_count: int,
	bars_per_candle: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var i: int = 0
	while i + bars_per_candle <= bar_count:
		var base0: int = i * 4
		var o: int = ohlc[base0]
		var h: int = ohlc[base0 + 1]
		var l: int = ohlc[base0 + 2]
		var c: int = 0
		var v: float = 0.0
		for j: int in range(bars_per_candle):
			var b: int = (i + j) * 4
			h  = maxi(h, ohlc[b + 1])
			l  = mini(l, ohlc[b + 2])
			c  = ohlc[b + 3]
			v += vol[i + j] if (i + j) < vol.size() else 0.0
		result.append({"open": o, "high": h, "low": l, "close": c, "volume": v})
		i += bars_per_candle
	return result


# ── Utils ──────────────────────────────────────────────────────────────────────

func _cache_dir() -> String:
	return CACHE_ROOT + "slot_%d/" % SaveSystem.get_active_slot_id()


func _stock_cache_path(stock_id: String) -> String:
	return _cache_dir() + "%s.bin" % stock_id


func _ensure_cache_dir() -> void:
	var dir: String = _cache_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)


func _cancel_thread() -> void:
	if _thread != null and _thread.is_alive():
		_thread.wait_to_finish()
	_thread = null
