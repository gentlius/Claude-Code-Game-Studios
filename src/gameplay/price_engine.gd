## Autoload — Generates real-time prices for all stocks using a 3-layer algorithm.
## Layer 1: Pattern (Markov chain) | Layer 2: Drift (mean reversion) | Layer 3: Event (news impact)
## See: design/gdd/price-engine.md, prototypes/price-engine/REPORT.md
extends Node

# ── Signals ──

## Emitted after all stock prices are updated for a tick.
signal on_price_updated(tick: int)

## Emitted when a price hits the hard clamp boundary.
signal on_price_clamped(stock_id: String, clamped_price: int, was_raw: float)

## Emitted when a price hits the daily limit (상한가/하한가).
signal on_price_limit_hit(stock_id: String, is_upper: bool, limit_price: int)

## Emitted when VI (Volatility Interruption) triggers for a stock (GDD Rule 2-4).
signal on_vi_triggered(stock_id: String, is_upper: bool, halt_ticks: int)

## Emitted when VI ends and trading resumes for a stock.
signal on_vi_released(stock_id: String)

## Emitted when circuit breaker activates (GDD Rule 2-5).
signal on_circuit_breaker(stage: int, halt_ticks: int)

## Emitted after process_all_ticks() when the C++ EventEngine fires intraday events.
## NewsEventSystem connects to this to resolve headlines and apply news delay (Phase B).
signal on_kernel_news(ui_events: Array)

# ── Enums ──

enum MarkovState {
	STRONG_UP,
	UPTREND,
	SIDEWAYS,
	DOWNTREND,
	STRONG_DOWN,
	BREAKOUT_UP,
	BREAKOUT_DOWN,
}

enum SeasonBias { BULL, NEUTRAL, BEAR }

## Macro trend layer state (ADR-026). Day-granularity upper Markov.
## FLAT(1) is the initial state; transitions driven by _macro_cfg.transitionMatrix.
enum MacroState { TREND_UP = 0, FLAT = 1, TREND_DOWN = 2 }

## Default macro transition matrix. Matches price_engine_config.json macroTrend.transitionMatrix.
## Self-prob 0.96 → avg duration 25d per trend (sufficient to dominate a 20-day month).
const MACRO_TM_DEFAULT: Array = [
	[0.96, 0.03, 0.01],  # TREND_UP
	[0.02, 0.96, 0.02],  # FLAT
	[0.01, 0.03, 0.96],  # TREND_DOWN
]

# ── Engine State Enum ──

enum EngineState { UNINITIALIZED, READY, RUNNING, PAUSED, END_OF_DAY, SEASON_END }

# ── Constants: State Parameters (GDD Rule 1-1) ──
# [bias, mag_min, mag_max, noise_std, min_duration_minutes]
# min_duration_minutes is converted to ticks via GameClock.TICKS_PER_MINUTE at runtime.

const STATE_PARAMS: Dictionary = {
	#                           bias      mag_min   mag_max   noise_std  min_dur(분)
	# bias/mag: per-minute ÷ TICKS_PER_MINUTE(4), noise: per-minute ÷ √4(2)
	MarkovState.STRONG_UP:     [+0.00030, +0.000075, +0.00050, 0.0004, 5],   ## 5분
	MarkovState.UPTREND:       [+0.000125, +0.000025, +0.00025, 0.0003, 8],  ## 8분
	MarkovState.SIDEWAYS:      [ 0.0000, -0.000125, +0.000125, 0.0002, 10],  ## 10분
	MarkovState.DOWNTREND:     [-0.000125, -0.00025, -0.000025, 0.0003, 8],  ## 8분
	MarkovState.STRONG_DOWN:   [-0.00030, -0.00050, -0.000075, 0.0004, 5],   ## 5분
	MarkovState.BREAKOUT_UP:   [+0.00075, +0.00025, +0.00125, 0.00075, 1],   ## 1분
	MarkovState.BREAKOUT_DOWN: [-0.00075, -0.00125, -0.00025, 0.00075, 1],   ## 1분
}

# ── Constants: Transition Matrix (GDD Rule 1-3, MEDIUM baseline) ──

const TRANSITION_MATRIX: Array = [
	#  SU     UT     SW     DT     SD     BU     BD
	[0.980, 0.010, 0.003, 0.001, 0.000, 0.005, 0.001],  # STRONG_UP
	[0.005, 0.985, 0.005, 0.001, 0.000, 0.003, 0.001],  # UPTREND
	[0.003, 0.008, 0.975, 0.008, 0.003, 0.002, 0.001],  # SIDEWAYS
	[0.000, 0.001, 0.005, 0.985, 0.005, 0.001, 0.003],  # DOWNTREND
	[0.000, 0.001, 0.003, 0.010, 0.980, 0.001, 0.005],  # STRONG_DOWN
	[0.075, 0.250, 0.125, 0.040, 0.000, 0.500, 0.010],  # BREAKOUT_UP
	[0.000, 0.040, 0.125, 0.250, 0.075, 0.010, 0.500],  # BREAKOUT_DOWN
]

# ── Constants: Volatility Profile Scaling (GDD Rules 1-4, 1-6) ──

const VOL_SELF_SCALE: Array[float]     = [1.15, 1.00, 0.90, 0.75]  # LOW..EXTREME
const VOL_BREAKOUT_SCALE: Array[float] = [0.30, 1.00, 2.00, 4.00]
const VOL_PATTERN_SCALE: Array[float]  = [0.60, 1.00, 1.30, 1.80]
const VOL_AMPLIFIER: Array[float]      = [0.60, 1.00, 1.40, 2.00]

# ── Constants: Order Book (GDD order-book.md §4) ──

## Daily volume by volatility profile (LOW..EXTREME). Used for base_qty_per_level.
const DAILY_VOLUME_BY_PROFILE: Array[int] = [50_000, 200_000, 800_000, 2_000_000]

## Level weight: index 0 = 호가1 (best), index 4 = 호가5 (far). Far levels have more qty.
const LEVEL_WEIGHT: Array[float] = [1.0, 1.3, 1.6, 2.0, 2.5]

## Tick-level inflow/outflow base rates (GDD §4-2).
const ORDER_BOOK_INFLOW_RATE: float  = 0.08
const ORDER_BOOK_OUTFLOW_RATE: float = 0.06

## Clamp range for volume_factor in order book updates (GDD §4-2).
const ORDER_BOOK_VOLUME_FACTOR_MIN: float = 0.1
const ORDER_BOOK_VOLUME_FACTOR_MAX: float = 5.0

## Player order market impact scale (ADR-019).
## filled_qty / daily_volume * SCALE → next-tick price delta contribution.
## 100% of daily volume filled in one tick moves price by this fraction.
const PLAYER_PRESSURE_SCALE: float = 0.30

## Number of levels on each side of the book.
const ORDER_BOOK_LEVELS: int = 5

# ── Constants: Volume (GDD Rule 4) ──

const BASE_VOLUME_RANGE: Array = [
	[100, 300],   # LOW
	[200, 600],   # MEDIUM
	[400, 1200],  # HIGH
	[800, 3000],  # EXTREME
]

const STATE_VOLUME_MULT: Array[float] = [1.3, 1.1, 0.7, 1.1, 1.3, 2.0, 2.0]

# ── Constants: Volume-Energy Correlation (GDD Rule 4-2) ──

const ENERGY_THRESHOLD: float = 0.01
const ENERGY_MAX_BOOST: float = 4.0

# ── Constants: Limit Proximity Dampening (GDD Rule 4-4) ──

const LIMIT_DAMPEN_START: float = 0.7
const LIMIT_DAMPEN_MIN: float = 0.15

# ── Constants: Time-of-Day Volume Multipliers (GDD Rule 4-5) ──

const TOD_OPEN_VOLUME_MULT: float = 2.5   ## Opening 10 min (ticks 0–39) volume boost
const TOD_CLOSE_VOLUME_MULT: float = 2.0  ## Closing 10 min (ticks 1520–1559) volume boost

# ── Constants: Season Bias (GDD Rule 1-5, updated per prototype) ──

const SEASON_BIAS_UP: Array[float]   = [+0.01, 0.00, -0.01]  # BULL, NEUTRAL, BEAR
const SEASON_BIAS_DOWN: Array[float] = [-0.01, 0.00, +0.01]

# ── Constants: Season Bias Probabilities (GDD Rule 1-5) ──

const BIAS_BULL_PROB: float = 0.4     ## BULL 40%, NEUTRAL 30%, BEAR 30%
const BIAS_NEUTRAL_CUTOFF: float = 0.7  ## cumulative: BULL + NEUTRAL

# ── Constants: Hard Clamp Bounds (GDD Rule 2-3) ──

const HARD_CLAMP_MIN_RATIO: float = 0.15  ## Lifetime min = base_price × 0.15
const HARD_CLAMP_MAX_RATIO: float = 3.0   ## Lifetime max = base_price × 3.0
const HARD_CLAMP_ABS_MIN_PRICE: float = 1000.0  ## Absolute floor (₩1,000); overrides ratio for cheap stocks
const TOD_WINDOW_TICKS: int = 40  ## Opening/closing window ticks = TICKS_PER_MINUTE(4) × 10 min

# ── Tuning Knobs (GDD updated values after prototype) ──

@export var k_drift: float = 0.001
@export var threshold_soft: float = 0.20
@export var threshold_hard: float = 0.50
@export var max_single_impact: float = 0.15
@export var breakout_force_threshold: float = 0.05

## Korean stock market daily price limit (±30% from previous day close)
const DAILY_LIMIT_PCT: float = 0.30

# ── VI / Circuit Breaker Constants (GDD Rules 2-4, 2-5) ──
# Duration values in game-minutes; converted via _minutes_to_ticks() at usage site.

const VI_THRESHOLD: float = 0.15
const VI_HALT_MINUTES: int = 2     ## 2분 거래정지
const VI_MAX_PER_DAY: int = 1
const VI_COOLDOWN_MINUTES: int = 5  ## 5분 쿨다운

const CB_STAGE1_PCT: float = -0.12
const CB_STAGE2_PCT: float = -0.20
const CB_STAGE1_MINUTES: int = 5    ## 5분 거래정지

## Converts game-minutes to ticks using GameClock constant.
static func _minutes_to_ticks(minutes: int) -> int:
	return minutes * GameClock.TICKS_PER_MINUTE

# ── Tick Size Table (data-driven via MarketProfile, ADR-002) ──

## Returns the tick size (호가 단위) for a given price level.
## Table is loaded from the active MarketProfile JSON — DLC markets define their own tables.
## Falls back to hardcoded KRX table when _tick_table is not yet loaded.
## Chart renderer and order engine also use this for grid alignment and order validation.
func get_tick_size(price: int) -> int:
	if not _tick_table.is_empty():
		for entry: Variant in _tick_table:
			var pair: Array = entry as Array
			if price < int(pair[0]):
				return int(pair[1])
		# Last entry catch-all (should always be reached by the loop above,
		# but guard against a malformed table missing INT_MAX as final threshold).
		return int((_tick_table[-1] as Array)[1])
	# Fallback: hardcoded KRX table (before MarketProfile loads or on parse failure).
	if price < 1000:   return 1
	if price < 5000:   return 5
	if price < 10000:  return 10
	if price < 50000:  return 50
	if price < 100000: return 100
	if price < 500000: return 500
	return 1000


## Rounds a raw price to the nearest tick size.
func round_to_tick(raw_price: float) -> int:
	var ts: int = get_tick_size(roundi(raw_price))
	return roundi(raw_price / float(ts)) * ts

# ── Per-Stock Runtime State ──

## Dedicated RNG instance for all price randomness (ADR-018).
## Re-seeded on every session start (game launch, load, new game) with wall-clock time.
## State is NOT persisted — prevents price-scouting via save/reload.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _stock_states: Dictionary = {}  ## stock_id -> _StockState
var _engine_state: EngineState = EngineState.UNINITIALIZED
var _transition_matrices: Dictionary = {}  ## stock_id -> Array[Array[float]]

# ── Market Index (시총가중지수) ──

const INDEX_BASE: float = 1000.0  ## 시즌 시작 시 지수 기준값
var _base_market_cap: float = 0.0  ## 시즌 시작 시 총 시가총액
var _current_index: float = INDEX_BASE  ## 현재 지수값
var _prev_day_index: float = INDEX_BASE  ## 전일 지수 종가
var _index_history: Array[float] = []  ## 틱별 지수 기록

# ── VI / Circuit Breaker Runtime State ──

var _vi_states: Dictionary = {}  ## stock_id -> {halt_remaining: int, count_today: int, cooldown: int}
var _cb_stage: int = 0  ## 0=none, 1=stage1 active, 2=stage2 (early close)
var _cb_halt_remaining: int = 0  ## Stage 1 remaining halt ticks
var _player_pressure: Dictionary = {}  ## stock_id -> float; pending price delta from player fills (ADR-019)
var _rumor_pressure: Dictionary = {}   ## stock_id -> {delta_per_tick: float, ticks_remaining: int} (TD-DR-04)
var _old_prices: Dictionary = {}       ## pre-allocated: stock_id -> int. Reused each tick (TD-CR-07)
var _season_count: int = 0  ## Seasons started since new-game/load. 0=uninitialised; 1=first season. (ADR-025)

# ── Config (loaded in _ready) ──

const CONFIG_PATH: String = "res://assets/data/price_engine_config.json"
var _rumor_pressure_strength: float = 0.0005  ## per-tick fractional delta per impact tier unit (GDD §3-5)

## ADR-024 Phase 2: Markov constants loaded from JSON.
## generate_stock_m1_cache() reads these so C++ MarkovGenerator uses the same source.
## Keyed by MarkovState int (0=STRONG_UP … 6=BREAKOUT_DOWN). Populated by _load_config().
var _cfg_state_params: Array = []          ## 7 entries: [bias, mag_min, mag_max, noise_std, min_dur_min]
var _cfg_transition_matrix: Array = []     ## 7×7 float rows
var _cfg_vol_pattern_scale: Array = []     ## 4 floats [LOW..EXTREME]
var _cfg_base_volume_range: Array = []     ## 4 entries: [min_vol, max_vol]
var _cfg_state_volume_mult: Array = []     ## 7 floats [STRONG_UP..BREAKOUT_DOWN]
var _cfg_archetype_matrices: Dictionary = {}  ## ADR-025: per-archetype 7×7 Markov matrices

## ADR-026: Macro trend layer config loaded from price_engine_config.json "macroTrend".
## Keys: transitionMatrix (3×3), biasFactor (float), volMultiplier (Array[3][2]),
##        archetypeMacroMatrices (Dictionary of String→Array[3][3]).
var _macro_cfg: Dictionary = {}

## ADR-024 Phase 3: C++ MarkovGenerator instance. null when GDExtension is not loaded.
## Falls back to GDScript generate_stock_m1_cache() when null.
var _markov: Object = null

## ADR-027 Phase A: C++ PriceKernel — stateful per-tick engine for all non-ETF stocks.
var _kernel: Object = null

## H-01: Dedicated kernel instance for run_historical_simulation().
## Stored as an instance variable so it can be freed after simulation completes.
## null when no historical simulation is in progress.
var _hist_kernel: Object = null

## VI halt countdown tracked GDScript-side for on_vi_released and is_vi_halted() queries.
## Populated from vi_hits returned by _kernel.process_all_ticks(); decremented each tick.
var _vi_halt_remaining: Dictionary = {}  ## stock_id → ticks remaining

## Tick size table loaded from MarketProfile JSON (ADR-002, DLC extensibility).
## Each entry: [exclusiveUpperBound: int, tickSize: int]. Last entry is catch-all.
## Falls back to KRX hardcoded table when empty (before MarketProfile is loaded).
var _tick_table: Array = []

# ── Lifecycle ──

func _ready() -> void:
	GameClock.on_tick.connect(process_tick)
	GameClock.on_season_start.connect(_on_season_start)
	GameClock.on_market_state_changed.connect(_on_market_state_changed)
	NewsEventSystem.on_rumor_hint.connect(_on_rumor_hint)
	_load_config()
	_init_markov_ext()
	_init_kernel_ext()
	_reseed_session()


## Load tuning values from price_engine_config.json. Falls back to in-code defaults.
## ADR-024 Phase 2: Markov constants parsed into _cfg_* vars for C++ parity.
func _load_config() -> void:
	var f: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		_init_cfg_from_consts()
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		_init_cfg_from_consts()
		return

	_rumor_pressure_strength = float(parsed.get("rumorPressureStrength", _rumor_pressure_strength))

	# ── Markov state parameters (stateParams) ──
	# State order mirrors the MarkovState enum (0=STRONG_UP … 6=BREAKOUT_DOWN).
	const STATE_NAMES: Array = [
		"STRONG_UP", "UPTREND", "SIDEWAYS", "DOWNTREND",
		"STRONG_DOWN", "BREAKOUT_UP", "BREAKOUT_DOWN",
	]
	var sp_json: Dictionary = parsed.get("stateParams", {}) as Dictionary
	_cfg_state_params = []
	if sp_json.is_empty():
		_cfg_state_params = _array_copy(STATE_PARAMS.values())
	else:
		for name: String in STATE_NAMES:
			var p: Dictionary = sp_json.get(name, {}) as Dictionary
			_cfg_state_params.append([
				float(p.get("bias",           0.0)),
				float(p.get("magMin",          0.0)),
				float(p.get("magMax",          0.0)),
				float(p.get("noiseStd",        0.0)),
				int(p.get("minDurationMin",    1)),
			])

	# ── Transition matrix ──
	var tm_json: Variant = parsed.get("transitionMatrix", [])
	if tm_json is Array and (tm_json as Array).size() == 7:
		_cfg_transition_matrix = []
		for row: Variant in (tm_json as Array):
			var r: Array[float] = [] as Array[float]
			for v: Variant in (row as Array):
				r.append(float(v))
			_cfg_transition_matrix.append(r)
	else:
		_cfg_transition_matrix = TRANSITION_MATRIX.duplicate(true)

	# ── Volatility and volume arrays ──
	_cfg_vol_pattern_scale = _load_float_array(parsed, "volPatternScale",  VOL_PATTERN_SCALE)
	_cfg_base_volume_range = _load_nested_array(parsed, "baseVolumeRange", BASE_VOLUME_RANGE)
	_cfg_state_volume_mult = _load_float_array(parsed, "stateVolumeMult", STATE_VOLUME_MULT)

	# ── Macro trend layer (ADR-026) ──
	var macro_json: Variant = parsed.get("macroTrend", {})
	if macro_json is Dictionary:
		_macro_cfg = macro_json as Dictionary

	# ── Per-archetype Markov matrices (ADR-025) ──
	var arch_json: Variant = parsed.get("archetypeMatrices", {})
	if arch_json is Dictionary:
		_cfg_archetype_matrices = arch_json as Dictionary

	# ── Tick size table (ADR-002, DLC extensibility) ──
	# Loaded from MarketProfile JSON rather than price_engine_config.json —
	# tick rules are market-specific, not engine-specific.
	_tick_table = MarketProfile.get_tick_table()


## Fallback: populate _cfg_* from compile-time const values when JSON is unavailable.
func _init_cfg_from_consts() -> void:
	_cfg_state_params = _array_copy(STATE_PARAMS.values())
	_cfg_transition_matrix = TRANSITION_MATRIX.duplicate(true)
	_cfg_vol_pattern_scale = VOL_PATTERN_SCALE.duplicate()
	_cfg_base_volume_range = BASE_VOLUME_RANGE.duplicate(true)
	_cfg_state_volume_mult = STATE_VOLUME_MULT.duplicate()


## ADR-024 Phase 3: Instantiate the C++ MarkovGenerator GDExtension.
## GDScript 폴백 없음 — 라이브러리 로드 실패 시 즉시 크래시.
## DLL 없거나 로드 실패하면 gdextension/bin/windows/ 확인 후 Godot 에디터 재시작.
func _init_markov_ext() -> void:
	assert(ClassDB.class_exists("MarkovGenerator"),
		"FATAL: MarkovGenerator GDExtension 미로드. " +
		"gdextension/bin/windows/ DLL 확인 후 Godot 에디터 재시작 필요.")
	_markov = ClassDB.instantiate("MarkovGenerator")
	assert(_markov != null, "FATAL: MarkovGenerator 인스턴스 생성 실패.")
	_markov.set_config(_build_markov_cfg())
	print("PriceEngine: C++ MarkovGenerator 로드 완료.")


## ADR-027 Phase A: Instantiate the C++ PriceKernel GDExtension.
func _init_kernel_ext() -> void:
	assert(ClassDB.class_exists("PriceKernel"),
		"FATAL: PriceKernel GDExtension 미로드. " +
		"gdextension/bin/windows/ DLL 확인 후 Godot 에디터 재시작 필요.")
	_kernel = ClassDB.instantiate("PriceKernel")
	assert(_kernel != null, "FATAL: PriceKernel 인스턴스 생성 실패.")
	_kernel.set_config(_build_kernel_cfg())
	print("PriceEngine: C++ PriceKernel 로드 완료.")


## Assemble the config Dictionary that C++ MarkovGenerator.set_config() expects.
## Keys match price_engine_config.json schema (see assets/data/price_engine_config.json).
func _build_markov_cfg() -> Dictionary:
	var cfg: Dictionary = {}
	cfg["stateParams"]       = _cfg_state_params if not _cfg_state_params.is_empty() \
	                           else _array_copy(STATE_PARAMS.values())
	cfg["transitionMatrix"]  = _cfg_transition_matrix if not _cfg_transition_matrix.is_empty() \
	                           else TRANSITION_MATRIX.duplicate(true)
	cfg["volSelfScale"]      = VOL_SELF_SCALE.duplicate()
	cfg["volBreakoutScale"]  = VOL_BREAKOUT_SCALE.duplicate()
	cfg["volPatternScale"]   = _cfg_vol_pattern_scale if not _cfg_vol_pattern_scale.is_empty() \
	                           else VOL_PATTERN_SCALE.duplicate()
	cfg["baseVolumeRange"]   = _cfg_base_volume_range if not _cfg_base_volume_range.is_empty() \
	                           else BASE_VOLUME_RANGE.duplicate(true)
	cfg["stateVolumeMult"]   = _cfg_state_volume_mult if not _cfg_state_volume_mult.is_empty() \
	                           else STATE_VOLUME_MULT.duplicate()
	if not _macro_cfg.is_empty():
		cfg["macroTrend"] = _macro_cfg
	if not _cfg_archetype_matrices.is_empty():
		cfg["archetypeMatrices"] = _cfg_archetype_matrices  # ADR-025: per-archetype 7×7 matrices
	if not _tick_table.is_empty():
		cfg["tickTable"] = _tick_table.duplicate(true)
	return cfg


## Assemble the config Dictionary for C++ PriceKernel.set_config().
## Extends the MarkovGenerator schema with PriceKernel-specific keys (ADR-027).
func _build_kernel_cfg() -> Dictionary:
	var cfg: Dictionary = _build_markov_cfg()
	cfg["volAmplifier"]           = VOL_AMPLIFIER.duplicate()
	cfg["energyThreshold"]        = ENERGY_THRESHOLD
	cfg["energyMaxBoost"]         = ENERGY_MAX_BOOST
	cfg["limitDampenStart"]       = LIMIT_DAMPEN_START
	cfg["limitDampenMin"]         = LIMIT_DAMPEN_MIN
	cfg["todOpenMult"]            = TOD_OPEN_VOLUME_MULT
	cfg["todCloseMult"]           = TOD_CLOSE_VOLUME_MULT
	cfg["todWindowTicks"]         = TOD_WINDOW_TICKS
	cfg["hardClampMinRatio"]      = HARD_CLAMP_MIN_RATIO
	cfg["hardClampMaxRatio"]      = HARD_CLAMP_MAX_RATIO
	cfg["hardClampAbsMin"]        = HARD_CLAMP_ABS_MIN_PRICE
	cfg["dailyLimitPct"]          = DAILY_LIMIT_PCT
	cfg["kDrift"]                 = k_drift
	cfg["thresholdSoft"]          = threshold_soft
	cfg["thresholdHard"]          = threshold_hard
	cfg["maxSingleImpact"]        = max_single_impact
	cfg["breakoutForceThreshold"] = breakout_force_threshold
	cfg["viThreshold"]            = VI_THRESHOLD
	cfg["viHaltTicks"]            = _minutes_to_ticks(VI_HALT_MINUTES)
	cfg["viMaxPerDay"]            = VI_MAX_PER_DAY
	cfg["viCooldownTicks"]        = _minutes_to_ticks(VI_COOLDOWN_MINUTES)
	cfg["ticksPerDay"]            = GameClock.TICKS_PER_DAY
	cfg["m1CacheBars"]            = M1CacheManager.M1_CACHE_BARS
	cfg["d1CacheBars"]            = M1CacheManager.D1_CACHE_BARS

	# Phase B: EventEngine — pass event_pool templates to C++ kernel.
	# TODO(DLC): filter by active market_id when multi-market support lands (ADR-021).
	var ep_file := FileAccess.open("res://assets/data/event_pool.json", FileAccess.READ)
	if ep_file != null:
		var ep_json := JSON.new()
		if ep_json.parse(ep_file.get_as_text()) == OK:
			var ep_data: Dictionary = ep_json.data
			var all_tpl: Array = ep_data.get("templates", [])
			cfg["event_pool"] = all_tpl.filter(
				func(t: Dictionary) -> bool:
					return t.get("market_id", "KR").to_upper() == "KR"
			)
		ep_file.close()

	# Phase C: EtfEngine — pass etf_config to C++ kernel (ADR-027).
	var etf_file := FileAccess.open("res://assets/data/etf_config.json", FileAccess.READ)
	if etf_file != null:
		var etf_json := JSON.new()
		if etf_json.parse(etf_file.get_as_text()) == OK:
			cfg["etf_config"] = etf_json.data
		etf_file.close()

	# Phase D: ReportEngine — financial_report_config + MarketProfile calendar params (ADR-027).
	var rpt_file := FileAccess.open("res://assets/data/financial_report_config.json", FileAccess.READ)
	if rpt_file != null:
		var rpt_json := JSON.new()
		if rpt_json.parse(rpt_file.get_as_text()) == OK:
			var rpt_cfg: Dictionary = rpt_json.data as Dictionary
			var cycle: Variant = MarketProfile.get_calendar_param("report_cycle_seasons")
			if cycle != null:
				rpt_cfg["reportCycleSeasons"] = int(cycle)
			var rpt_start: Variant = MarketProfile.get_calendar_param("fiscal_year_start_season")
			if rpt_start != null:
				rpt_cfg["fiscalYearStartSeason"] = int(rpt_start)
			var pe: Variant = MarketProfile.get_calendar_param("preliminary_earnings")
			if pe is Dictionary:
				rpt_cfg["preliminaryEarnings"] = pe
			cfg["report_config"] = rpt_cfg
		rpt_file.close()

	return cfg


static func _load_float_array(d: Dictionary, key: String, fallback: Array) -> Array[float]:
	var raw: Variant = d.get(key, [])
	if not raw is Array or (raw as Array).is_empty():
		return fallback.duplicate() as Array[float]
	var out: Array[float] = [] as Array[float]
	for v: Variant in (raw as Array):
		out.append(float(v))
	return out


static func _load_nested_array(d: Dictionary, key: String, fallback: Array) -> Array:
	var raw: Variant = d.get(key, [])
	if not raw is Array or (raw as Array).is_empty():
		return fallback.duplicate(true)
	var out: Array = []
	for sub: Variant in (raw as Array):
		var inner: Array = []
		if sub is Array:
			for v: Variant in (sub as Array):
				inner.append(v)
		out.append(inner)
	return out


static func _array_copy(arr: Array) -> Array:
	var out: Array = []
	for v: Variant in arr:
		out.append(v)
	return out


## Re-seed the price RNG from wall-clock time (ADR-018).
## Called on every session boundary (game launch, load, new game) so that
## the same save file always produces different intraday prices on each load.
## Tests override _rng.seed directly after calling this.
func _reseed_session() -> void:
	_rng.seed = Time.get_ticks_usec()


func _on_season_start() -> void:
	_season_count += 1  # ADR-025: track which season we are entering (1 = first)
	# ADR-026: persist this season's D1 candles to M1CacheManager ring buffer
	# before _reset_season_mechanics() clears ohlcv_daily / tick_prices.
	# append_season_m1() must be called alongside append_season_d1() so the M1 chart
	# ring buffer stays continuous across season boundaries (chart-renderer.md §5-3).
	if M1CacheManager.is_batch_done():
		for stock_id: String in _stock_states:
			var s: Dictionary = _stock_states[stock_id]
			if s.get("is_etf", false):
				continue
			if not s.get("ohlcv_daily", []).is_empty():
				M1CacheManager.append_season_d1(stock_id, s["ohlcv_daily"])
			var tp: Array = s.get("tick_prices", [])
			if not tp.is_empty():
				M1CacheManager.append_season_m1(stock_id, tp, s.get("tick_volumes", []))
	_reset_season_mechanics()


## Called by SaveSystem after loading a save where a season was in progress.
## Rebuilds _stock_states in one pass: StockDatabase for metadata, save_data for
## dynamic fields (prices, season_bias, ohlcv_daily, tick_prices, tick_volumes).
## Does NOT call _reset_season_mechanics() — that would discard the restored state.
## Backward-compat: old saves with "closing_prices" flat dict are still accepted.
## Engine enters READY state; transitions to RUNNING when player opens market.
func initialize_for_load(save_data: Dictionary) -> void:
	_reseed_session()  # ADR-018: new session → fresh intraday RNG
	_stock_states.clear()
	_transition_matrices.clear()
	_player_pressure.clear()
	_kernel.reset()

	var stocks_saved: Dictionary = save_data.get("stocks", {})
	# Backward compat — pre-v2 saves stored a flat {stock_id: price} dict.
	var legacy_prices: Dictionary = save_data.get("closing_prices", {})

	var stock_ids: Array[String] = StockDatabase.get_all_stock_ids()
	for stock_id: String in stock_ids:
		var stock: StockData = StockDatabase.get_stock(stock_id)
		if stock == null:
			continue

		var saved: Dictionary = stocks_saved.get(stock_id, {})

		# Prices — prefer new format, fall back to legacy, then base_price
		var cur_price: int = saved.get("current_price",
			legacy_prices.get(stock_id, stock.base_price))
		var prev_close: int = saved.get("prev_day_close", cur_price)
		if cur_price  <= 0: cur_price  = stock.base_price
		if prev_close <= 0: prev_close = stock.base_price

		# Season bias — restore if saved, else randomise
		var bias: SeasonBias
		var bias_val: int = saved.get("season_bias", -1)
		if bias_val >= SeasonBias.BULL and bias_val <= SeasonBias.BEAR:
			bias = bias_val as SeasonBias
		else:
			var r: float = _rng.randf()
			if   r < BIAS_BULL_PROB:        bias = SeasonBias.BULL
			elif r < BIAS_NEUTRAL_CUTOFF:   bias = SeasonBias.NEUTRAL
			else:                            bias = SeasonBias.BEAR

		# Tick history (full season) — chart renderer requires the complete buffer
		var tick_prices: Array[int] = [] as Array[int]
		for p: Variant in saved.get("tick_prices", []):
			tick_prices.append(int(p))
		var tick_volumes: Array[float] = [] as Array[float]
		for v: Variant in saved.get("tick_volumes", []):
			tick_volumes.append(float(v))
		var ohlcv_daily: Array[Dictionary] = [] as Array[Dictionary]
		for entry: Variant in saved.get("ohlcv_daily", []):
			if entry is Dictionary:
				ohlcv_daily.append(entry)

		# ADR-025: Prefer saved base_price (may be drifted from prior seasons).
		# Fall back to StockData.base_price for saves predating ADR-025.
		var saved_base: int = int(saved.get("base_price", 0))
		var base_price_restored: int = saved_base if saved_base > 0 else stock.base_price

		# ADR-026: restore MacroState (default FLAT for pre-ADR-026 saves)
		var macro_state_restored: int = int(saved.get("macro_state", MacroState.FLAT))
		if macro_state_restored < MacroState.TREND_UP or macro_state_restored > MacroState.TREND_DOWN:
			macro_state_restored = MacroState.FLAT

		_stock_states[stock_id] = {
			"stock_id":           stock_id,
			"current_price":      cur_price,
			"base_price":         base_price_restored,
			"season_open_price":  saved.get("season_open_price", cur_price),
			"prev_day_close":     prev_close,
			"volatility_profile": stock.volatility_profile,
			"macro_sensitivity":  stock.macro_sensitivity,
			"sector_sensitivity": stock.sector_sensitivity,
			"markov_state":       MarkovState.SIDEWAYS,  # session-scoped, not persisted
			"state_duration":     0,
			"season_bias":        bias,
			"macro_state":        macro_state_restored,  # ADR-026: persisted
			"macro_vol_mult":     1.0,                   # ADR-026: redrawn each day
			"tick_prices":        tick_prices,
			"tick_volumes":       tick_volumes,
			"ohlcv_daily":        ohlcv_daily,
			"event_queue":        [] as Array,
			"gradual_events":     [] as Array,
			"order_book":         {"ask": [], "bid": []},
		}
		var base_mat: Array = _build_transition_matrix(stock.volatility_profile, bias)
		_transition_matrices[stock_id] = _apply_macro_bias_to_matrix(
			base_mat, macro_state_restored
		)

	_vi_states.clear()
	_vi_halt_remaining.clear()
	for stock_id: String in _stock_states:
		_vi_states[stock_id] = {"halt_remaining": 0, "count_today": 0, "cooldown": 0}

	_cb_stage = 0
	_cb_halt_remaining = 0
	_base_market_cap = _compute_total_market_cap()

	# ADR-027 Phase A: restore kernel state from saved fields.
	# start_day() is NOT called — macro_state and prev_day_close are already restored.
	for stock_id: String in _stock_states:
		var s: Dictionary = _stock_states[stock_id]
		if s.get("is_etf", false):
			continue
		var stock: StockData = StockDatabase.get_stock(stock_id)
		if stock == null:
			continue
		_kernel.init_stock(stock_id, {
			"base_price":          s["base_price"],
			"current_price":       s["current_price"],
			"prev_day_close":      s["prev_day_close"],
			"vol_profile":         s["volatility_profile"],
			"sector":              stock.sector,
			"archetype":           stock.archetype,
			"macro_sensitivity":   s["macro_sensitivity"],
			"sector_sensitivity":  s["sector_sensitivity"],
			"is_etf":              false,
			"macro_state":         int(s.get("macro_state", MacroState.FLAT)),
			"event_tags":          stock.event_tags,
			"listed_shares":       stock.listed_shares,
			"roe":                 stock.roe,
			"per":                 stock.per,
			"pbr":                 stock.pbr,
		})
	_kernel.start_season(int(save_data.get("season_count", 1)),
		NewsEventSystem.get_season_theme())

	# 저장된 시장지수 복원. 없으면 INDEX_BASE(1000) 유지.
	var saved_index: float = save_data.get("market_index", 0.0)
	var saved_prev:  float = save_data.get("prev_day_index", 0.0)
	if saved_index > 0.0:
		_current_index  = saved_index
		_prev_day_index = saved_prev if saved_prev > 0.0 else saved_index
		# _base_market_cap을 재보정: 현재 시가총액과 저장된 지수로부터 역산
		_base_market_cap = _base_market_cap * INDEX_BASE / saved_index
	else:
		_current_index  = INDEX_BASE
		_prev_day_index = INDEX_BASE
	_index_history.clear()
	_season_count = int(save_data.get("season_count", 1))  ## ADR-025: restore drift counter
	_engine_state = EngineState.READY
	# 로드 후 가격 복원 완료 — UI 일괄 갱신.
	on_price_updated.emit(0)


## Returns full per-stock dynamic state for save system.
## tick_prices/tick_volumes are the full-season buffers (GDD chart-renderer §5-1).
## market_index / prev_day_index: 시장지수 복원용. 없으면 INDEX_BASE(1000)로 초기화됨.
func get_save_data() -> Dictionary:
	var stocks_data: Dictionary = {}
	for stock_id: String in _stock_states:
		var s: Dictionary = _stock_states[stock_id]
		stocks_data[stock_id] = {
			"current_price":     s.get("current_price",     0),
			"prev_day_close":    s.get("prev_day_close",    0),
			"base_price":        s.get("base_price",        0),  ## ADR-025: drifted anchor
			"season_open_price": s.get("season_open_price", s.get("current_price", 0)),
			"season_bias":       int(s.get("season_bias", SeasonBias.NEUTRAL)),
			"macro_state":       int(s.get("macro_state", MacroState.FLAT)),  ## ADR-026
			"ohlcv_daily":       s.get("ohlcv_daily",       []),
			"tick_prices":       s.get("tick_prices",        []),
			"tick_volumes":      s.get("tick_volumes",       []),
		}
	return {
		"stocks":         stocks_data,
		"market_index":   _current_index,
		"prev_day_index": _prev_day_index,
		"season_count":   _season_count,  ## ADR-025: season drift counter
	}


## Returns C++ ReportEngine pending-event state for serialization.
## Called by FinancialReportSystem.get_save_data(). ADR-027 Phase D.
func get_report_state() -> Dictionary:
	return _kernel.get_report_state()


## Restores C++ ReportEngine state from save data.
## Must be called AFTER initialize_for_load() (start_season() resets kernel state first).
## Called by FinancialReportSystem.load_save_data(). ADR-027 Phase D.
func restore_report_state(state: Dictionary) -> void:
	_kernel.restore_report_state(state)


## Runs historical price simulation for all stocks (ADR-027 Phase E).
## Uses a DEDICATED kernel instance — live _kernel is untouched.
## theme_sequence: Array[Dictionary] (len = n_seasons); empty dicts use default weights.
## Returns: {stock_id: {m1_ohlc, m1_vol, d1_ohlc, d1_vol, m1_count, d1_count,
##                      final_price, final_roe, final_per, final_pbr,
##                      final_markov_state, final_macro_state}}
func run_historical_simulation(n_seasons: int, days_per_season: int,
		ticks_per_day: int, theme_sequence: Array,
		seed: int) -> Dictionary:
	# H-01: use instance variable so _hist_kernel can be freed after completion.
	_hist_kernel = ClassDB.instantiate("PriceKernel")
	if _hist_kernel == null:
		push_error("PriceEngine: PriceKernel 인스턴스 생성 실패 (historical sim)")
		return {}
	_hist_kernel.set_config(_build_kernel_cfg())
	for stock_id: String in _stock_states:
		var s: Dictionary = _stock_states[stock_id]
		var stock: StockData = StockDatabase.get_stock(stock_id)
		if stock == null:
			continue
		_hist_kernel.init_stock(stock_id, {
			"base_price":         s.get("base_price",         stock.base_price),
			"current_price":      s.get("current_price",      stock.base_price),
			"prev_day_close":     s.get("prev_day_close",     stock.base_price),
			"vol_profile":        s.get("volatility_profile", stock.volatility_profile),
			"sector":             stock.sector,
			"archetype":          stock.archetype,
			"macro_sensitivity":  s.get("macro_sensitivity",  1.0),
			"sector_sensitivity": s.get("sector_sensitivity", 1.0),
			"is_etf":             s.get("is_etf",             false),
			"listed_shares":      stock.listed_shares,
			"roe":                stock.roe,
			"per":                stock.per,
			"pbr":                stock.pbr,
			"event_tags":         stock.event_tags,
		})
	var result: Dictionary = _hist_kernel.run_historical_simulation(
		n_seasons, days_per_season, ticks_per_day, theme_sequence, seed)
	# H-01: free the kernel immediately after simulation to avoid memory leak.
	_hist_kernel.free()
	_hist_kernel = null
	return result


## Returns historical simulation progress: 0 (not started) → 1000 (done).
## Thread-safe; poll from a timer during background simulation.
## H-02: reads from _hist_kernel (the simulation kernel), not _kernel (the live kernel).
func get_simulation_progress() -> int:
	if _hist_kernel == null:
		return 0
	return _hist_kernel.get_simulation_progress()


## Resets all price engine state for unit tests. Call in before_each.
## Resets all price engine state. Called by GameMain (new game) and tests (before_each).
func reset() -> void:
	_stock_states.clear()
	_vi_states.clear()
	_vi_halt_remaining.clear()
	_player_pressure.clear()
	_rumor_pressure.clear()
	_cb_stage = 0
	_cb_halt_remaining = 0
	_prev_day_index = 0.0
	_current_index = 0.0
	_base_market_cap = 0.0
	_season_count = 0  ## ADR-025
	_kernel.reset()
	_engine_state = EngineState.UNINITIALIZED


func _on_market_state_changed(
	new_state: GameClock.MarketState, _prev: GameClock.MarketState
) -> void:
	match new_state:
		GameClock.MarketState.MARKET_OPEN:
			if _engine_state == EngineState.READY or _engine_state == EngineState.PAUSED:
				_engine_state = EngineState.RUNNING
		GameClock.MarketState.PAUSED:
			_engine_state = EngineState.PAUSED
		GameClock.MarketState.MARKET_CLOSED:
			_end_trading_day()
		GameClock.MarketState.PRE_MARKET:
			if _engine_state == EngineState.END_OF_DAY:
				_engine_state = EngineState.READY
				# 일일 정산(_end_trading_day)에서 prev_day_close 갱신 완료.
				# on_price_updated로 모든 UI에 알려 등락률·현재가를 일괄 갱신.
				on_price_updated.emit(0)

# ── Public API ──

## Returns the current price of a stock (100원 unit, int).
func get_current_price(stock_id: String) -> int:
	var state: Dictionary = _stock_states.get(stock_id, {})
	return state.get("current_price", 0)


## Returns the tick price buffer for a stock (Array[int]).
func get_tick_buffer(stock_id: String) -> Array[int]:
	var state: Dictionary = _stock_states.get(stock_id, {})
	return state.get("tick_prices", [] as Array[int])


## Returns the tick volume buffer for a stock (Array[float]).
func get_tick_volumes(stock_id: String) -> Array[float]:
	var state: Dictionary = _stock_states.get(stock_id, {})
	return state.get("tick_volumes", [] as Array[float])


## Returns the OHLCV daily history for a stock.
func get_ohlcv_history(stock_id: String) -> Array[Dictionary]:
	var state: Dictionary = _stock_states.get(stock_id, {})
	return state.get("ohlcv_daily", [] as Array[Dictionary])


## Returns today's intraday OHLCV from the tick buffer.
## GDD order-book.md §3-5 블록1 — 호가창 상단 시/고/저/거래량 표시용.
## open  = tick_prices[0] (장 첫 틱), fallback: prev_day_close
## high  = max(tick_prices), low = min(tick_prices), volume = sum(tick_volumes)
func get_today_ohlcv(stock_id: String) -> Dictionary:
	var state: Dictionary = _stock_states.get(stock_id, {})
	var all_prices: Array = state.get("tick_prices", [])
	var all_volumes: Array = state.get("tick_volumes", [])
	var cur: int = state.get("current_price", 0)
	var prev_close: int = state.get("prev_day_close", cur)
	if all_prices.is_empty():
		return {"open": prev_close, "high": cur, "low": cur, "volume": 0}
	# Slice to today's ticks only.
	# get_current_tick() returns 0-based tick within today; +1 = prices added so far today.
	# Using TICKS_PER_DAY here (like _end_trading_day does) is wrong mid-day —
	# it would slide into yesterday's data, making open drift every tick.
	var today_ticks: int = GameClock.get_current_tick() + 1
	var day_start: int = maxi(0, all_prices.size() - today_ticks)
	var tick_prices: Array = all_prices.slice(day_start)
	var tick_volumes: Array = all_volumes.slice(maxi(0, all_volumes.size() - today_ticks))
	var open_price: int = tick_prices[0] as int
	var high_price: int = open_price
	var low_price: int = open_price
	for p: Variant in tick_prices:
		var pi: int = p as int
		if pi > high_price: high_price = pi
		if pi < low_price:  low_price  = pi
	var vol: int = 0
	for v: Variant in tick_volumes:
		vol += int(v as float)
	return {"open": open_price, "high": high_price, "low": low_price, "volume": vol}


## Returns the daily price limits {upper: int, lower: int, prev_close: int}.
func get_daily_limits(stock_id: String) -> Dictionary:
	var state: Dictionary = _stock_states.get(stock_id, {})
	var prev_close: int = state.get("prev_day_close", 0)
	var upper: int = round_to_tick(float(prev_close) * (1.0 + DAILY_LIMIT_PCT))
	var lower: int = round_to_tick(float(prev_close) * (1.0 - DAILY_LIMIT_PCT))
	return {"upper": upper, "lower": lower, "prev_close": prev_close}


## Returns the PER display string adjusted for current price vs season open.
## GDD financial-statements.md §Formulas: PER_display = base_per * (current_price / season_open_price).
## per == 0.0 (적자기업) → "N/A". 표시 포맷 단일 소유.
func get_per_display(stock_id: String) -> String:
	var stock: StockData = StockDatabase.get_stock(stock_id)
	if stock == null or stock.per == 0.0:
		return "N/A"
	var state: Dictionary = _stock_states.get(stock_id, {})
	var open_price: int = state.get("season_open_price", 0)
	var cur_price: int = state.get("current_price", 0)
	if open_price <= 0:
		return "%.1fx" % stock.per
	return "%.1fx" % (stock.per * (float(cur_price) / float(open_price)))


## Returns the PBR display string adjusted for current price vs season open.
## GDD financial-statements.md §Formulas: PBR_display = base_pbr * (current_price / season_open_price).
## pbr == 0.0 (적자/음수 자본) → "N/A". 표시 포맷 단일 소유.
func get_pbr_display(stock_id: String) -> String:
	var stock: StockData = StockDatabase.get_stock(stock_id)
	if stock == null or stock.pbr == 0.0:
		return "N/A"
	var state: Dictionary = _stock_states.get(stock_id, {})
	var open_price: int = state.get("season_open_price", 0)
	var cur_price: int = state.get("current_price", 0)
	if open_price <= 0:
		return "%.1fx" % stock.pbr
	return "%.1fx" % (stock.pbr * (float(cur_price) / float(open_price)))


## Returns the ROE display string. ROE is static — not affected by price movement.
## roe == 0.0 (적자기업) → "N/A". 표시 포맷 단일 소유.
func get_roe_display(stock_id: String) -> String:
	var stock: StockData = StockDatabase.get_stock(stock_id)
	if stock == null or stock.roe == 0.0:
		return "N/A"
	return "%.1f%%" % stock.roe


## Returns the dividend yield display string adjusted for current price vs season open.
## GDD financial-statements.md §Formulas: dividend_display = base_yield / (current_price / season_open_price).
## 표시 포맷 단일 소유.
func get_dividend_display(stock_id: String) -> String:
	var stock: StockData = StockDatabase.get_stock(stock_id)
	if stock == null or stock.dividend_yield <= 0.0:
		return "N/A"
	var state: Dictionary = _stock_states.get(stock_id, {})
	var open_price: int = state.get("season_open_price", 0)
	var cur_price: int = state.get("current_price", 0)
	if open_price <= 0 or cur_price <= 0:
		return "%.1f%%" % (stock.dividend_yield * 100.0)
	var adjusted: float = stock.dividend_yield / (float(cur_price) / float(open_price))
	return "%.1f%%" % (adjusted * 100.0)


## Returns the 52-week high price for a stock.
## GDD order-book.md §3-5 블록6 — 호가창 하단 52주 최고/최저 표시용.
## Scans ohlcv_daily (full season history) for the maximum high across all recorded days,
## then compares with today's intraday high from get_today_ohlcv().
## If no history exists (first day of season), returns today's intraday high or current_price.
func get_week52_high(stock_id: String) -> int:
	var state: Dictionary = _stock_states.get(stock_id, {})
	if state.is_empty():
		return 0
	var daily: Array = state.get("ohlcv_daily", [])
	var result: int = 0
	for entry: Variant in daily:
		var d: Dictionary = entry as Dictionary
		var h: int = d.get("high", 0)
		if h > result:
			result = h
	# Include today's intraday high
	var today: Dictionary = get_today_ohlcv(stock_id)
	var today_high: int = today.get("high", 0)
	if today_high > result:
		result = today_high
	# Fallback to current price when no data at all
	if result == 0:
		result = state.get("current_price", 0)
	return result


## Returns the 52-week low price for a stock.
## GDD order-book.md §3-5 블록6 — 호가창 하단 52주 최고/최저 표시용.
## Scans ohlcv_daily (full season history) for the minimum low across all recorded days,
## then compares with today's intraday low from get_today_ohlcv().
## If no history exists (first day of season), returns today's intraday low or current_price.
func get_week52_low(stock_id: String) -> int:
	var state: Dictionary = _stock_states.get(stock_id, {})
	if state.is_empty():
		return 0
	var daily: Array = state.get("ohlcv_daily", [])
	var result: int = 0
	for entry: Variant in daily:
		var d: Dictionary = entry as Dictionary
		var l: int = d.get("low", 0)
		if l > 0 and (result == 0 or l < result):
			result = l
	# Include today's intraday low
	var today: Dictionary = get_today_ohlcv(stock_id)
	var today_low: int = today.get("low", 0)
	if today_low > 0 and (result == 0 or today_low < result):
		result = today_low
	# Fallback to current price when no data at all
	if result == 0:
		result = state.get("current_price", 0)
	return result


## Returns the current Markov state for a stock.
func get_markov_state(stock_id: String) -> MarkovState:
	var state: Dictionary = _stock_states.get(stock_id, {})
	return state.get("markov_state", MarkovState.SIDEWAYS) as MarkovState


## ADR-024 Phase 1: M1-first batch generation for pre-history cache.
## Simulates M1 bars directly via Markov — no D1→M1 expansion.
## D1 bars are accumulated from M1 (open=first-M1.open, high/low=running max/min, close=last-M1.close).
##
## Keeps rolling buffers: last [param m1_capacity] M1 bars + last [param d1_capacity] D1 bars.
## Reorders buffers to chronological order before returning.
##
## Returns {m1_ohlc: PackedInt32Array (m1_count×4), m1_vol: PackedFloat32Array (m1_count),
##          d1_ohlc: PackedInt32Array (d1_count×4), d1_vol: PackedFloat32Array (d1_count),
##          m1_count: int, d1_count: int}
## Thread-safe: no autoload state mutations. Call from M1CacheManager background thread.
func generate_stock_m1_cache(
	stock: StockData,
	history_seed: int,
	m1_capacity: int,
	d1_capacity: int
) -> Dictionary:
	const DAYS_PER_SEASON: int = 20

	var n_days: int = stock.history_seasons * DAYS_PER_SEASON
	var vol_profile: int = stock.volatility_profile
	var base_price: int = stock.base_price
	var stock_seed: int = (history_seed ^ hash(stock.stock_id)) & 0x7FFFFFFF

	# ADR-024 Phase 3: C++ MarkovGenerator — GDScript 폴백 없음 (_init_markov_ext 참조).
	# ADR-025: pass archetype_key so C++ selects the per-archetype transition matrix.
	assert(_markov != null, "FATAL: generate_stock_m1_cache called before MarkovGenerator loaded.")
	return _markov.generate_stock_m1(
		vol_profile, base_price, n_days, m1_capacity, d1_capacity, stock_seed,
		stock.archetype)


## Rumor hint handler (TD-DR-04, GDD §3-5).
## Converts incoming rumor entry into per-tick fractional price pressure for target stocks.
## Formula: delta_per_tick = direction × strength × tier_mult
## tier_mult: SMALL=1, MEDIUM=2, LARGE=4 (matching GDD §3-5 proportional scaling)
func _on_rumor_hint(rumor: Dictionary) -> void:
	if rumor.get("is_fake", false):
		return  # Fake rumors carry no price signal (GDD §5-4)
	var target_ids: Array = rumor.get("target_stock_ids", [])
	if target_ids.is_empty():
		return
	var direction: int = int(rumor.get("direction", 0))
	var impact_tier: String = rumor.get("impact_tier", "SMALL")
	var tier_mult: float
	match impact_tier:
		"SMALL":  tier_mult = 1.0
		"MEDIUM": tier_mult = 2.0
		_:        tier_mult = 4.0  # LARGE, CRITICAL
	var delta_per_tick: float = float(direction) * _rumor_pressure_strength * tier_mult
	var ticks_remaining: int = SkillTree.RUMOR_LEAD_MINUTES * GameClock.TICKS_PER_MINUTE
	for stock_id: String in target_ids:
		_kernel.set_rumor(stock_id, delta_per_tick, ticks_remaining)


## Consumes one tick of rumor pressure for the given stock.
## Decrements ticks_remaining and removes the entry when exhausted.
func _consume_rumor_pressure(stock_id: String) -> float:
	if not _rumor_pressure.has(stock_id):
		return 0.0
	var entry: Dictionary = _rumor_pressure[stock_id]
	var delta: float = entry["delta_per_tick"]
	entry["ticks_remaining"] -= 1
	if entry["ticks_remaining"] <= 0:
		_rumor_pressure.erase(stock_id)
	return delta


## Push an event from the News/Events system (ADR-027 Phase A: delegates to C++ kernel).
func push_event(event: MarketEvent) -> void:
	for stock_id: String in event.target_stock_ids:
		if not _stock_states.has(stock_id):
			continue
		_kernel.inject_event({
			"stock_id":    stock_id,
			"scope":       int(event.scope),
			"base_impact": event.base_impact,
			"direction":   int(event.direction),
			"event_type":  int(event.event_type),
			"decay_ticks": event.decay_ticks,
			"decay_curve": int(event.decay_curve),
		})


## Register an ETF in the price cache (sector-etf.md §3-2, ADR-021, ADR-027 Phase C).
## Called by EtfManager at season init and save load to create the _stock_states entry.
## Per-tick ETF prices now come from C++ PriceKernel via process_all_ticks() etf_prices.
## AC-13: price is clamped to ≥ 1원.
##
## Example:
##   PriceEngine.inject_price("ETF_반도체", 50000.0)  # season init
func inject_price(etf_id: String, price: float) -> void:
	var clamped: int = maxi(1, roundi(price))
	if not _stock_states.has(etf_id):
		_stock_states[etf_id] = {
			"stock_id":          etf_id,
			"current_price":     clamped,
			"base_price":        clamped,
			"season_open_price": clamped,
			"prev_day_close":    clamped,
			"tick_prices":       [] as Array[int],
			"tick_volumes":      [] as Array[float],
			"ohlcv_daily":       [] as Array[Dictionary],
			"order_book":        {"ask": [], "bid": []},
			"event_queue":       [],
			"is_etf":            true,
		}
		# Phase C: ETFs are registered with the kernel via etf_config in set_config().
		# No init_stock() call needed here.
	_stock_states[etf_id]["current_price"] = clamped


# ── Season Initialization ──

## Returns a randomly selected SeasonBias (BULL 40%, NEUTRAL 30%, BEAR 30%).
func _random_bias() -> SeasonBias:
	var r: float = _rng.randf()
	if r < BIAS_BULL_PROB:
		return SeasonBias.BULL
	elif r < BIAS_NEUTRAL_CUTOFF:
		return SeasonBias.NEUTRAL
	else:
		return SeasonBias.BEAR


## Called by GameMain after reset(), before MainScreen is shown (new game only).
## Populates _stock_states from StockDatabase so get_current_price() is valid
## before any UI is created. Does NOT emit on_price_updated — StockListPanel._ready()
## performs the initial render by reading PriceEngine directly.
func init_first_season() -> void:
	_reseed_session()  # ADR-018: new game = new session → fresh intraday RNG
	_stock_states.clear()
	_transition_matrices.clear()
	_kernel.reset()

	for stock_id: String in StockDatabase.get_all_stock_ids():
		var stock: StockData = StockDatabase.get_stock(stock_id)
		if stock == null:
			continue
		var bias: SeasonBias = _random_bias()
		_stock_states[stock_id] = {
			"stock_id":           stock_id,
			"current_price":      stock.base_price,
			"base_price":         stock.base_price,
			"prev_day_close":     stock.base_price,
			"season_open_price":  stock.base_price,
			"volatility_profile": stock.volatility_profile,
			"macro_sensitivity":  stock.macro_sensitivity,
			"sector_sensitivity": stock.sector_sensitivity,
			"markov_state":       MarkovState.SIDEWAYS,
			"state_duration":     0,
			"season_bias":        bias,
			"macro_state":        MacroState.FLAT,  # ADR-026: start FLAT, transitions each day
			"macro_vol_mult":     1.0,              # ADR-026: redrawn by _roll_macro_states
			"tick_prices":        [] as Array[int],
			"tick_volumes":       [] as Array[float],
			"ohlcv_daily":        [] as Array[Dictionary],
			"event_queue":        [] as Array,
			"gradual_events":     [] as Array,
			"order_book":         {"ask": [], "bid": []},
		}
		# ADR-026: new-game matrix has no macro bias yet (FLAT = no-op)
		_transition_matrices[stock_id] = _build_transition_matrix(
			stock.volatility_profile, bias
		)

	_vi_states.clear()
	_vi_halt_remaining.clear()
	for stock_id: String in _stock_states:
		_vi_states[stock_id] = {"halt_remaining": 0, "count_today": 0, "cooldown": 0}

	_cb_stage = 0
	_cb_halt_remaining = 0
	_base_market_cap = _compute_total_market_cap()
	_current_index = INDEX_BASE
	_prev_day_index = INDEX_BASE
	_index_history.clear()

	# ADR-027 Phase A: register all stocks with C++ kernel, then arm for day 1.
	for stock_id: String in _stock_states:
		var s: Dictionary = _stock_states[stock_id]
		var stock: StockData = StockDatabase.get_stock(stock_id)
		if stock == null:
			continue
		_kernel.init_stock(stock_id, {
			"base_price":          s["base_price"],
			"current_price":       s["current_price"],
			"prev_day_close":      s["prev_day_close"],
			"vol_profile":         s["volatility_profile"],
			"sector":              stock.sector,
			"archetype":           stock.archetype,
			"macro_sensitivity":   s["macro_sensitivity"],
			"sector_sensitivity":  s["sector_sensitivity"],
			"is_etf":              false,
			"macro_state":         int(s.get("macro_state", MacroState.FLAT)),
			"event_tags":          stock.event_tags,
			"listed_shares":       stock.listed_shares,
			"roe":                 stock.roe,
			"per":                 stock.per,
			"pbr":                 stock.pbr,
		})
	_kernel.start_season(1, NewsEventSystem.get_season_theme())
	_kernel.start_day(1)  # Day 1 = first trading day; ReportEngine events start from ANALYST_DAY_MIN ≥ 3

	_engine_state = EngineState.READY


## 새 게임 시 M1 캐시 배치 생성 완료 후 호출 (로드 게임에서는 호출 금지).
## M1CacheManager._m1_ohlc의 마지막 종가로 current_price / prev_day_close /
## season_open_price / base_price를 덮어써 차트 연속성을 보장한다 (ETF 제외).
## 시즌 2 이후: _on_season_start()의 append_season_m1()이 M1 링 버퍼 마지막 종가를
## 이전 시즌 종가로 갱신하므로, 이 함수는 시즌 간 연속성도 자동으로 보장한다.
## GDD: design/gdd/chart-renderer.md §5-3 "프리히스토리 연속성"
func sync_prices_from_prehistory() -> void:
	for stock_id: String in _stock_states:
		var state: Dictionary = _stock_states[stock_id]
		if state.get("is_etf", false):
			continue
		var last_close: int = M1CacheManager.get_last_prehistory_close(stock_id)
		if last_close <= 0:
			continue
		state["current_price"]     = last_close
		state["prev_day_close"]    = last_close
		state["season_open_price"] = last_close
		state["base_price"]        = last_close

	# ADR-027 Phase A: re-sync kernel with prehistory prices.
	# init_first_season() initialised the kernel with stock.base_price and called
	# start_day(1). The sync above changes GDScript prices to last_close, so the
	# kernel is now out of sync. Re-calling init_stock() overwrites kernel state
	# (current_price, prev_day_close, base_price) to match GDScript, preventing
	# a price discontinuity on the first live tick.
	for stock_id: String in _stock_states:
		var state: Dictionary = _stock_states[stock_id]
		if state.get("is_etf", false):
			continue
		var stock: StockData = StockDatabase.get_stock(stock_id)
		if stock == null:
			continue
		_kernel.init_stock(stock_id, {
			"base_price":         state["base_price"],
			"current_price":      state["current_price"],
			"prev_day_close":     state["prev_day_close"],
			"vol_profile":        state["volatility_profile"],
			"sector":             stock.sector,
			"archetype":          stock.archetype,
			"macro_sensitivity":  state["macro_sensitivity"],
			"sector_sensitivity": state["sector_sensitivity"],
			"is_etf":             false,
			"macro_state":        int(state.get("macro_state", MacroState.FLAT)),
			"event_tags":         stock.event_tags,
			"listed_shares":      stock.listed_shares,
			"roe":                stock.roe,
			"per":                stock.per,
			"pbr":                stock.pbr,
		})


## Resets per-season mechanics (Markov state, season bias, tick/OHLCV history, VI, CB,
## market index baseline) for all stocks. current_price and prev_day_close are preserved
## so prices carry forward naturally across seasons. Called every season start (Season 1
## and N+1). No emit — prices are unchanged so UI dirty flags will not trigger; the chart
## renderer re-fetches its buffers on the next MARKET_OPEN state transition.
## season_open_price is captured here so PER/PBR display methods reflect season-start price.
func _reset_season_mechanics() -> void:
	# ETF entries are managed by EtfManager and will be re-injected after on_season_started.
	# Remove them before the reset loop (cannot erase during iteration — two-pass).
	var etf_keys: Array[String] = []
	for stock_id: String in _stock_states:
		if _stock_states[stock_id].get("is_etf", false):
			etf_keys.append(stock_id)
	for etf_id: String in etf_keys:
		_stock_states.erase(etf_id)

	for stock_id: String in _stock_states:
		var state: Dictionary = _stock_states[stock_id]
		var bias: SeasonBias = _random_bias()
		state["markov_state"]      = MarkovState.SIDEWAYS
		state["state_duration"]    = 0
		state["season_bias"]       = bias
		state["season_open_price"] = state.get("current_price", state.get("base_price", 0))
		state["tick_prices"]       = [] as Array[int]
		state["tick_volumes"]      = [] as Array[float]
		state["ohlcv_daily"]       = [] as Array[Dictionary]
		state["event_queue"]       = [] as Array
		state["gradual_events"]    = [] as Array
		state["order_book"]        = {"ask": [], "bid": []}
		# current_price, prev_day_close: carry forward — not touched

		# ADR-025: Apply per-season base_price drift from season 2 onward.
		# Season 1: base_price already set from StockData (no drift on first season).
		# Season N+1: compound the drift so hard-clamp window and mean-reversion anchor
		#             both shift gradually, preventing guaranteed season-box trading.
		if _season_count > 1:
			var stock: StockData = StockDatabase.get_stock(stock_id)
			if stock != null and stock.season_drift != 0.0:
				state["base_price"] = max(1000,
					round_to_tick(state["base_price"] * (1.0 + stock.season_drift)))

		# ADR-026: Rebuild with macro bias. macro_state persists across season boundaries.
		var base_mat: Array = _build_transition_matrix(state["volatility_profile"], bias)
		_transition_matrices[stock_id] = _apply_macro_bias_to_matrix(
			base_mat, state.get("macro_state", MacroState.FLAT)
		)

	for stock_id: String in _vi_states:
		_vi_states[stock_id] = {"halt_remaining": 0, "count_today": 0, "cooldown": 0}
	_vi_halt_remaining.clear()
	_cb_stage = 0
	_cb_halt_remaining = 0
	_player_pressure.clear()

	# ADR-027 Phase B: notify kernel of season boundary with active season theme.
	_kernel.start_season(_season_count, NewsEventSystem.get_season_theme())

	# Recompute index baseline from current (carried-forward) prices so each season
	# starts fresh at INDEX_BASE regardless of prior season's price level.
	_base_market_cap = _compute_total_market_cap()
	_current_index = INDEX_BASE
	_prev_day_index = INDEX_BASE
	_index_history.clear()

# ── Tick Processing (GDD Rule 5) ──

## Called by GameClock._process_tick() for deterministic News→Price→Order ordering.
func process_tick(tick_number: int, _day: int, _week: int) -> void:
	if _engine_state != EngineState.RUNNING:
		return

	# Circuit breaker halt check (GDD Rule 2-5)
	if _cb_halt_remaining > 0:
		_cb_halt_remaining -= 1
		if _cb_halt_remaining == 0:
			# Stage 1 released — resume trading
			pass
		# Still emit price_updated so UI refreshes (prices unchanged)
		on_price_updated.emit(tick_number)
		return

	# Capture old prices before price updates for order book re-anchoring (GDD order-book.md §3-2)
	_old_prices.clear()
	for stock_id: String in _stock_states:
		_old_prices[stock_id] = _stock_states[stock_id].get("current_price", 0)

	# ADR-027 Phase A: decrement GDScript VI countdown BEFORE kernel (so release aligns
	# with the last halted tick, matching the original GDScript behaviour).
	var _vi_released: Array[String] = []
	for stock_id: String in _vi_halt_remaining:
		_vi_halt_remaining[stock_id] -= 1
		if _vi_halt_remaining[stock_id] <= 0:
			_vi_released.append(stock_id)
	for stock_id: String in _vi_released:
		_vi_halt_remaining.erase(stock_id)
		on_vi_released.emit(stock_id)

	# Delegate all per-stock tick logic to C++ PriceKernel (ADR-027 Phase A/B).
	var _tick_result: Dictionary = _kernel.process_all_ticks(tick_number)
	var _k_prices:  Dictionary = _tick_result["prices"]
	var _k_volumes: Dictionary = _tick_result["volumes"]
	var _k_vi_hits: Array     = _tick_result["vi_hits"]

	# Phase B: forward kernel-generated news events to NewsEventSystem for display.
	var _k_ui_events: Array = _tick_result["ui_events"]
	if not _k_ui_events.is_empty():
		on_kernel_news.emit(_k_ui_events)

	# Apply kernel results to GDScript stock states.
	for stock_id: String in _k_prices:
		if not _stock_states.has(stock_id):
			continue
		var s: Dictionary = _stock_states[stock_id]
		var new_price: int = int(_k_prices[stock_id])
		s["current_price"] = new_price
		(s["tick_prices"] as Array[int]).append(new_price)
		if s.get("is_etf", false):
			(s["tick_volumes"] as Array[float]).append(0.0)
		else:
			(s["tick_volumes"] as Array[float]).append(float(_k_volumes.get(stock_id, 0.0)))

	# Phase C: sync EtfManager with kernel ETF results.
	var _k_etf_prices: Dictionary = _tick_result.get("etf_prices", {})
	if not _k_etf_prices.is_empty():
		EtfManager.sync_from_kernel(
			_k_etf_prices,
			_tick_result.get("sector_flows", {}),
			_tick_result.get("rotation_cooldowns", {})
		)

	# Phase D: apply A3 (ROE/PER/PBR) updates from ReportEngine to StockData.
	var _k_a3: Array = _tick_result.get("a3_updates", [])
	if not _k_a3.is_empty():
		FinancialReportSystem._apply_kernel_a3_updates(_k_a3)

	# Emit VI trigger signals from kernel results.
	var _halt_ticks: int = _minutes_to_ticks(VI_HALT_MINUTES)
	for _hit: Dictionary in _k_vi_hits:
		var _hit_id: String = _hit["stock_id"]
		var _is_upper: bool = bool(_hit["is_upper"])
		_vi_halt_remaining[_hit_id] = _halt_ticks
		on_vi_triggered.emit(_hit_id, _is_upper, _halt_ticks)

	# Update order books after all prices are confirmed (GDD order-book.md §3-2)
	_update_order_books(_old_prices)

	_update_index()
	_check_circuit_breaker()
	on_price_updated.emit(tick_number)


func _process_stock_tick(stock_id: String, tick_in_day: int) -> void:
	var s: Dictionary = _stock_states[stock_id]
	var vol: int = s["volatility_profile"]

	# Step 1: Collect events
	var tick_events: Array = s["event_queue"]

	# Step 2: Pattern layer (GDD Rule 1-1 + 1-6)
	var pattern_delta: float = _compute_pattern_delta(s["markov_state"], vol)

	# Step 3: Drift layer (GDD Rule 2) — scaled by MacroState (ADR-026 driftScale)
	var drift_delta: float = _compute_drift_delta(
		s["current_price"], s["base_price"], s.get("macro_state", MacroState.FLAT)
	)

	# Step 4: Event layer (GDD Rule 3)
	var event_result: Dictionary = _compute_event_delta(s, tick_events)
	var event_delta: float = event_result["delta"]
	var forced_breakout: int = event_result["forced_breakout"]  # -1 if none

	# Clear event queue after processing
	s["event_queue"] = [] as Array

	# Step 4b: Player market impact (ADR-019)
	var player_delta: float = _player_pressure.get(stock_id, 0.0)
	_player_pressure.erase(stock_id)

	# Step 4c: Rumor price pressure (GDD §3-5, TD-DR-04)
	var rumor_delta: float = _consume_rumor_pressure(stock_id)

	# Step 5: Additive combination
	var total_delta: float = pattern_delta + drift_delta + event_delta + player_delta + rumor_delta

	# Step 6: Price update
	var raw_price: float = float(s["current_price"]) * (1.0 + total_delta)

	# Hard clamp: lifetime bounds (base_price * 0.15 ~ 3.0)
	var base: int = s["base_price"]
	var min_price: float = maxf(float(base) * HARD_CLAMP_MIN_RATIO, HARD_CLAMP_ABS_MIN_PRICE)
	var max_price: float = float(base) * HARD_CLAMP_MAX_RATIO
	var clamped: float = clampf(raw_price, min_price, max_price)
	if clamped != raw_price:
		on_price_clamped.emit(stock_id, roundi(clamped), raw_price)

	# Daily limit: ±30% from previous day close (상한가/하한가)
	var prev_close: float = float(s["prev_day_close"])
	var upper_limit: float = prev_close * (1.0 + DAILY_LIMIT_PCT)
	var lower_limit: float = prev_close * (1.0 - DAILY_LIMIT_PCT)
	if clamped >= upper_limit:
		if clamped > upper_limit:
			on_price_limit_hit.emit(stock_id, true, round_to_tick(upper_limit))
		clamped = upper_limit
	elif clamped <= lower_limit:
		if clamped < lower_limit:
			on_price_limit_hit.emit(stock_id, false, round_to_tick(lower_limit))
		clamped = lower_limit

	var final_price: int = PriceEngine.round_to_tick(clamped)
	s["current_price"] = final_price

	# Step 7: Markov state transition (GDD Rule 1-2, 1-3)
	if forced_breakout >= 0:
		s["markov_state"] = forced_breakout
		s["state_duration"] = 0
	else:
		var params: Array = STATE_PARAMS[s["markov_state"]]
		var min_dur: int = _minutes_to_ticks(params[4])
		if s["state_duration"] >= min_dur:
			var matrix: Array = _transition_matrices[stock_id]
			var row: Array = matrix[s["markov_state"]]
			var roll: float = _rng.randf()
			var cumulative: float = 0.0
			for j: int in range(7):
				cumulative += row[j]
				if roll <= cumulative:
					if j != s["markov_state"]:
						s["markov_state"] = j
						s["state_duration"] = 0
					else:
						s["state_duration"] += 1
					break
		else:
			s["state_duration"] += 1

	# Step 8: Volume (GDD Rule 4) — energy-correlated
	var volume: float = _compute_volume(s, pattern_delta, event_delta, rumor_delta, tick_in_day)

	# Step 9: Record
	s["tick_prices"].append(final_price)
	s["tick_volumes"].append(volume)

# ── Layer Computations ──

## Pattern layer: (bias + uniform + noise) × vol_pattern_scale
func _compute_pattern_delta(state: MarkovState, vol_profile: int) -> float:
	var params: Array = STATE_PARAMS[state]
	var bias: float = params[0]
	var mag_min: float = params[1]
	var mag_max: float = params[2]
	var noise_std: float = params[3]

	var magnitude: float = _rng.randf_range(mag_min, mag_max)
	var noise: float = _randn() * noise_std
	var raw: float = bias + magnitude + noise

	return raw * VOL_PATTERN_SCALE[vol_profile]


## Drift layer: mean reversion toward base_price (GDD Rule 2).
## macro_state: ADR-026 MacroState (0=TREND_UP, 1=FLAT, 2=TREND_DOWN).
## During TREND_UP/DOWN, k_drift is scaled by driftScale (default 0.2) so price can
## deviate ~11% from base before mean-reversion catches up (vs 0.875% at full k_drift).
func _compute_drift_delta(current_price: int, base_price: int, macro_state: int = MacroState.FLAT) -> float:
	if base_price == 0:
		return 0.0
	var drift_scales: Array = _macro_cfg.get("driftScale", [0.2, 1.0, 0.2]) as Array
	var ds: float = float(drift_scales[macro_state]) if macro_state < drift_scales.size() else 1.0
	var deviation_ratio: float = (float(current_price) - float(base_price)) / float(base_price)
	var intensity: float = _drift_intensity(deviation_ratio)
	return -k_drift * ds * deviation_ratio * intensity


## Non-linear drift intensity (GDD Rule 2-3)
func _drift_intensity(deviation_ratio: float) -> float:
	var r: float = absf(deviation_ratio)
	if r < threshold_soft:
		return 1.0
	elif r < threshold_hard:
		return 1.0 + (r - threshold_soft) * 4.0
	else:
		return (1.0
			+ (threshold_hard - threshold_soft) * 4.0
			+ (r - threshold_hard) * 16.0)


## Event layer: process instant shocks and gradual shifts (GDD Rule 3)
func _compute_event_delta(
	s: Dictionary, tick_events: Array
) -> Dictionary:
	var result: Dictionary = {"delta": 0.0, "forced_breakout": -1}
	_apply_new_events(s, tick_events, result)
	_apply_ongoing_gradual_events(s, result)
	return result


## Apply newly arriving events this tick; mutates result["delta"] and result["forced_breakout"].
func _apply_new_events(s: Dictionary, tick_events: Array, result: Dictionary) -> void:
	var vol: int = s["volatility_profile"]
	var macro_sens: float = s["macro_sensitivity"]
	var sector_sens: float = s["sector_sensitivity"]
	var gradual_events: Array = s["gradual_events"]

	for event: MarketEvent in tick_events:
		var sensitivity: float
		match event.scope:
			MarketEvent.EventScope.MACRO:
				sensitivity = macro_sens
			MarketEvent.EventScope.SECTOR:
				sensitivity = sector_sens
			_:
				sensitivity = 1.0

		var raw: float = event.base_impact * float(event.direction) * sensitivity * VOL_AMPLIFIER[vol]
		var actual: float = clampf(raw, -max_single_impact, max_single_impact)

		if event.event_type == MarketEvent.EventType.INSTANT_SHOCK:
			result["delta"] += actual
			if absf(actual) >= breakout_force_threshold:
				result["forced_breakout"] = MarkovState.BREAKOUT_UP if actual > 0 else MarkovState.BREAKOUT_DOWN

		elif event.event_type == MarketEvent.EventType.GRADUAL_SHIFT:
			var decay_rate: float = 0.0
			if event.decay_curve == MarketEvent.DecayCurve.EXPONENTIAL and event.decay_ticks > 0:
				decay_rate = 1.0 - exp(log(0.01) / float(event.decay_ticks))

			var ge: Dictionary = {
				"actual_impact": actual,
				"remaining_ticks": event.decay_ticks,
				"total_ticks": event.decay_ticks,
				"decay_curve": event.decay_curve,
				"decay_rate": decay_rate,
			}
			# First tick contribution
			result["delta"] += _gradual_tick_impact(ge)
			ge["remaining_ticks"] -= 1
			if ge["remaining_ticks"] > 0:
				gradual_events.append(ge)


## Advance ongoing gradual events; mutates result["delta"] and prunes exhausted entries.
func _apply_ongoing_gradual_events(s: Dictionary, result: Dictionary) -> void:
	var gradual_events: Array = s["gradual_events"]
	var still_active: Array = []
	for ge: Dictionary in gradual_events:
		if ge["remaining_ticks"] > 0:
			result["delta"] += _gradual_tick_impact(ge)
			ge["remaining_ticks"] -= 1
			if ge["remaining_ticks"] > 0:
				still_active.append(ge)
	s["gradual_events"] = still_active


## Calculate per-tick contribution of a gradual event.
func _gradual_tick_impact(ge: Dictionary) -> float:
	if ge["remaining_ticks"] <= 0:
		return 0.0
	var actual: float = ge["actual_impact"]
	var total: int = ge["total_ticks"]

	if ge["decay_curve"] == MarketEvent.DecayCurve.LINEAR:
		return actual / float(total)
	else:
		var elapsed: int = total - ge["remaining_ticks"]
		var rate: float = ge["decay_rate"]
		return actual * pow(1.0 - rate, float(elapsed)) * rate


## Volume generation (GDD Rule 4)
## Volume calculation using shared tick energy (GDD Rule 4-2 ~ 4-6).
## tick_energy = |pattern_delta| + |event_delta| + |rumor_delta| measures total force before cancellation.
func _compute_volume(
	s: Dictionary, pattern_delta: float, event_delta: float, rumor_delta: float, tick_in_day: int
) -> float:
	var vol: int = s["volatility_profile"]
	var vol_range: Array = BASE_VOLUME_RANGE[vol]
	var base_vol: float = _rng.randf_range(float(vol_range[0]), float(vol_range[1]))

	# 4-2: Tick energy — correlation between price movement forces and volume
	var tick_energy: float = absf(pattern_delta) + absf(event_delta) + absf(rumor_delta)
	var energy_mult: float = 1.0 + clampf(
		tick_energy / ENERGY_THRESHOLD, 0.0, ENERGY_MAX_BOOST
	)

	# 4-3: State multiplier
	var state_mult: float = STATE_VOLUME_MULT[s["markov_state"]]

	# 4-4: Limit proximity dampening (호가 고갈)
	var limit_dampen: float = 1.0
	var prev_close: float = float(s["prev_day_close"])
	if prev_close > 0.0:
		var proximity: float = absf(
			float(s["current_price"]) - prev_close
		) / (prev_close * DAILY_LIMIT_PCT)
		if proximity >= LIMIT_DAMPEN_START:
			var t: float = (proximity - LIMIT_DAMPEN_START) / (1.0 - LIMIT_DAMPEN_START)
			limit_dampen = lerpf(1.0, LIMIT_DAMPEN_MIN, clampf(t, 0.0, 1.0))

	# 4-5: Time-of-day multiplier (GDD Rule 4-5)
	# TOD_WINDOW_TICKS = TICKS_PER_MINUTE(4) × 10 min = 40 ticks
	# Closing window start = TICKS_PER_DAY(1560) − TOD_WINDOW_TICKS = 1520
	var tod_mult: float = 1.0
	if tick_in_day < TOD_WINDOW_TICKS:
		tod_mult = TOD_OPEN_VOLUME_MULT
	elif tick_in_day >= GameClock.TICKS_PER_DAY - TOD_WINDOW_TICKS:
		tod_mult = TOD_CLOSE_VOLUME_MULT

	# 4-6: Final volume (ADR-026: macro volume multiplier — drawn once per day in _roll_macro_states)
	var macro_vol_mult: float = s.get("macro_vol_mult", 1.0)
	return base_vol * state_mult * energy_mult * limit_dampen * tod_mult * macro_vol_mult

# ── VI / Circuit Breaker (GDD Rules 2-4, 2-5) ──

## Check if a stock should trigger VI after its price update.
func _check_vi(stock_id: String) -> void:
	var s: Dictionary = _stock_states[stock_id]
	var vi: Dictionary = _vi_states.get(stock_id, {"halt_remaining": 0, "count_today": 0, "cooldown": 0})

	# Already halted, daily limit reached, or in cooldown
	if vi["halt_remaining"] > 0:
		return
	if vi["count_today"] >= VI_MAX_PER_DAY:
		return
	if vi.get("cooldown", 0) > 0:
		return

	var prev_close: float = float(s["prev_day_close"])
	if prev_close <= 0.0:
		return

	var change_pct: float = absf(float(s["current_price"]) - prev_close) / prev_close
	if change_pct >= VI_THRESHOLD:
		var is_upper: bool = s["current_price"] > roundi(prev_close)
		var halt_ticks: int = _minutes_to_ticks(VI_HALT_MINUTES)
		vi["halt_remaining"] = halt_ticks
		vi["count_today"] += 1
		_vi_states[stock_id] = vi
		on_vi_triggered.emit(stock_id, is_upper, halt_ticks)


## Check if circuit breaker should trigger based on market index.
func _check_circuit_breaker() -> void:
	if _prev_day_index <= 0.0:
		return

	var index_change: float = (_current_index - _prev_day_index) / _prev_day_index

	if index_change <= CB_STAGE2_PCT and _cb_stage < 2:
		_cb_stage = 2
		on_circuit_breaker.emit(2, 0)
		_end_trading_day()  # Early close
		return

	if index_change <= CB_STAGE1_PCT and _cb_stage < 1:
		_cb_stage = 1
		var cb_halt: int = _minutes_to_ticks(CB_STAGE1_MINUTES)
		_cb_halt_remaining = cb_halt
		on_circuit_breaker.emit(1, cb_halt)


## Returns whether a stock is currently halted by VI.
func is_vi_halted(stock_id: String) -> bool:
	return _vi_halt_remaining.has(stock_id)


## Returns current circuit breaker stage (0=none, 1=halt, 2=early close).
func get_cb_stage() -> int:
	return _cb_stage


# ── End of Day ──

func _end_trading_day() -> void:
	_engine_state = EngineState.END_OF_DAY
	_generate_daily_ohlcv()
	# ADR-027: kernel owns macro_state roll (prev_day_close, Markov, VI).
	# Pass next day's number so ReportEngine _re_process_pre_market fires on the correct day.
	_kernel.start_day(GameClock.get_current_day() + 1)
	# Sync macro_state back to _stock_states so save_game_data() persists the correct value.
	# Single ownership: C++ rolls, GDScript reads. (ADR-026 + ADR-027)
	var _kernel_macros: Dictionary = _kernel.get_macro_states()
	for _sid: String in _kernel_macros:
		if _stock_states.has(_sid):
			_stock_states[_sid]["macro_state"] = int(_kernel_macros[_sid])
	_reset_order_books()
	_reset_vi_and_circuit_breaker()
	_vi_halt_remaining.clear()
	_prev_day_index = _current_index
	_rumor_pressure.clear()  # TD-DR-04: stale rumor pressure does not carry over to next day


## Build OHLCV candle from today's tick arrays and append to each stock's history.
func _generate_daily_ohlcv() -> void:
	for stock_id: String in _stock_states:
		var s: Dictionary = _stock_states[stock_id]
		var prices: Array[int] = s["tick_prices"]
		var volumes: Array[float] = s["tick_volumes"]

		if prices.is_empty():
			continue

		# Generate OHLCV summary from today's ticks
		var day_start: int = prices.size() - GameClock.TICKS_PER_DAY
		if day_start < 0:
			day_start = 0

		var day_prices: Array[int] = prices.slice(day_start)
		var day_volumes: Array[float] = volumes.slice(day_start)

		var high: int = day_prices[0]
		var low: int = day_prices[0]
		var total_vol: float = 0.0
		for p: int in day_prices:
			if p > high:
				high = p
			if p < low:
				low = p
		for v: float in day_volumes:
			total_vol += v

		var close_price: int = day_prices[day_prices.size() - 1]
		s["ohlcv_daily"].append({
			"open": day_prices[0],
			"high": high,
			"low": low,
			"close": close_price,
			"volume": total_vol,
		})

		# Update prev_day_close for next day's daily limit calculation
		s["prev_day_close"] = close_price

		# tick_prices/tick_volumes는 리셋하지 않는다.
		# GDD chart-renderer.md §5-1: max_tick_history = 31200 (시즌 전체 보관).
		# 31200틱 × 46종목 × 12 bytes ≈ 17 MB — 허용 범위.
		# chart_renderer는 MARKET_OPEN마다 _aggregate_candles()로 전체 재집계하여
		# 1분/5분/15분봉에서 과거 일자 스크롤을 지원한다.


## Clear order books at market close — KRX 미체결 잔량 장 마감 시 전량 초기화 (GDD order-book.md §3-1)
func _reset_order_books() -> void:
	for stock_id: String in _stock_states:
		_stock_states[stock_id]["order_book"] = {"ask": [], "bid": []}


## Reset VI daily counters and circuit breaker state for the next trading day.
func _reset_vi_and_circuit_breaker() -> void:
	# Reset VI daily counters (GDD Rule 2-4: max 1 per day resets each day)
	for stock_id: String in _vi_states:
		_vi_states[stock_id]["count_today"] = 0
		_vi_states[stock_id]["halt_remaining"] = 0
		_vi_states[stock_id]["cooldown"] = 0

	# Reset circuit breaker for next day (GDD Rule 2-5)
	_cb_stage = 0
	_cb_halt_remaining = 0

# ── Order Book (GDD order-book.md) ──

## Initializes 10-level order books for all stocks.
## Called by GameClock.confirm_market_open() — GDD §3-1, §9 진입점.
## Books are NOT saved/loaded; they are rebuilt fresh each trading day.
func initialize_order_books() -> void:
	for stock_id: String in _stock_states:
		var s: Dictionary = _stock_states[stock_id]
		# ETF entries have no order book — skip (sector-etf.md §3-3 "즉시 체결")
		if s.get("is_etf", false):
			continue
		var vol: int = s["volatility_profile"]
		var price: int = s["current_price"]
		var base_qty: float = _order_book_base_qty(vol)
		var ask_levels: Array = []
		var bid_levels: Array = []
		# ask: price + (level+1)*tick_size, level 0..4
		for level: int in range(ORDER_BOOK_LEVELS):
			var level_price: int = price
			for _i: int in range(level + 1):
				level_price += get_tick_size(level_price)
			var qty: int = maxi(1, int(base_qty * LEVEL_WEIGHT[level] * _rng.randf_range(0.7, 1.3)))
			ask_levels.append({"price": level_price, "qty": qty})
		# bid: price - level*tick_size, level 0..4
		for level: int in range(ORDER_BOOK_LEVELS):
			var level_price: int = price
			for _i: int in range(level):
				level_price -= get_tick_size(level_price)
				level_price = maxi(1, level_price)
			var qty: int = maxi(1, int(base_qty * LEVEL_WEIGHT[level] * _rng.randf_range(0.7, 1.3)))
			bid_levels.append({"price": level_price, "qty": qty})
		s["order_book"] = {"ask": ask_levels, "bid": bid_levels}


## Returns the order book for a stock as {ask: [{price, qty}...], bid: [{price, qty}...]}.
## ask[0] = best ask (lowest sell), bid[0] = best bid (highest buy = current price).
## Returns empty book if stock not found. GDD §6 — UI·OrderEngine 조회용.
func get_order_book(stock_id: String) -> Dictionary:
	var s: Dictionary = _stock_states.get(stock_id, {})
	return s.get("order_book", {"ask": [], "bid": []})


## Consume order book for a buy or sell order. Returns {filled_qty, avg_price, remaining_qty}.
## side = "buy" sweeps ask levels from best to worst; side = "sell" sweeps bid levels.
## limit_price = -1 for market order (no price limit). GDD §3-4.
func consume_order_book(
	stock_id: String, side: String, order_qty: int, limit_price: int
) -> Dictionary:
	var s: Dictionary = _stock_states.get(stock_id, {})
	if s.is_empty():
		return {"filled_qty": 0, "avg_price": 0, "remaining_qty": order_qty}
	var book: Dictionary = s.get("order_book", {"ask": [], "bid": []})
	var levels: Array = book["ask"] if side == "buy" else book["bid"]
	var remaining: int = order_qty
	var total_cost: int = 0
	var filled_qty: int = 0
	var vol: int = s["volatility_profile"]
	var prev_close: int = s.get("prev_day_close", 0)

	# Use while loop so remove_at(i) does not cause index skip (for-range iterates
	# a fixed snapshot of size; removing an element shifts subsequent elements left).
	var i: int = 0
	while i < levels.size() and remaining > 0:
		var level: Dictionary = levels[i]
		# Limit price check (GDD §3-4)
		if limit_price != -1:
			if side == "buy" and level["price"] > limit_price:
				break
			elif side == "sell" and level["price"] < limit_price:
				break
		var fill: int = mini(remaining, level["qty"])
		total_cost += fill * level["price"]
		filled_qty += fill
		remaining -= fill
		level["qty"] -= fill
		# Level exhausted → remove and add new far level (GDD §3-3)
		if level["qty"] == 0:
			levels.remove_at(i)
			_add_far_level(levels, side, book, vol, prev_close)
			# Do NOT increment i — next element has shifted into position i
		else:
			i += 1

	var avg_price: int = 0
	if filled_qty > 0:
		avg_price = round_to_tick(float(total_cost) / float(filled_qty))
		# Fix 1: volume feedback — player fills count toward tick volume (ADR-019)
		var vols: Array = s.get("tick_volumes", [])
		if not vols.is_empty():
			vols[vols.size() - 1] += float(filled_qty)
		# Fix 2: price pressure — pass to C++ kernel for next tick (ADR-019, ADR-027)
		var daily_vol: float = float(DAILY_VOLUME_BY_PROFILE[s["volatility_profile"]])
		var pressure: float = float(filled_qty) / daily_vol * PLAYER_PRESSURE_SCALE
		if side == "sell":
			pressure = -pressure
		_kernel.add_player_pressure(stock_id, pressure)
	return {"filled_qty": filled_qty, "avg_price": avg_price, "remaining_qty": remaining}


## Update order books for all stocks after price changes. Called from process_tick().
## Two-phase: 1) re-anchor levels to new price, 2) volume-correlated qty fluctuation.
## GDD order-book.md §3-2.
func _update_order_books(old_prices: Dictionary) -> void:
	for stock_id: String in _stock_states:
		var s: Dictionary = _stock_states[stock_id]
		var book: Dictionary = s.get("order_book", {"ask": [], "bid": []})
		if book["ask"].is_empty() and book["bid"].is_empty():
			continue  # Not yet initialized (before confirm_market_open)
		# VI-halted stocks: freeze the book (GDD EC-05, AC-11)
		if is_vi_halted(stock_id):
			continue
		var new_price: int = s["current_price"]
		var old_price: int = old_prices.get(stock_id, new_price)
		var vol: int = s["volatility_profile"]
		var prev_close: int = s.get("prev_day_close", 0)
		var ask_levels: Array = book["ask"]
		var bid_levels: Array = book["bid"]

		# ── Phase 1: Re-anchor on price movement ──
		if new_price > old_price:
			# ask: remove levels where price <= new_price (bought through)
			var removed_count: int = 0
			var i: int = 0
			while i < ask_levels.size():
				if ask_levels[i]["price"] <= new_price:
					ask_levels.remove_at(i)
					removed_count += 1
				else:
					i += 1
			# Add new far ask levels to restore 5 levels
			for _j: int in range(removed_count):
				_add_far_level(ask_levels, "buy", book, vol, prev_close)
			# bid: insert new_price as new bid1
			var ts_new: int = get_tick_size(new_price)
			var base_q: float = _order_book_base_qty(vol)
			var new_bid_qty: int = maxi(1, int(base_q * LEVEL_WEIGHT[4] * _rng.randf_range(0.7, 1.3)))
			bid_levels.insert(0, {"price": new_price, "qty": new_bid_qty})
			if bid_levels.size() > ORDER_BOOK_LEVELS:
				bid_levels.resize(ORDER_BOOK_LEVELS)
			# Verify invariant: ask1 must be > new_price
			if not ask_levels.is_empty() and ask_levels[0]["price"] <= new_price:
				ask_levels[0]["price"] = new_price + ts_new
		elif new_price < old_price:
			# bid: remove levels where price > new_price (sold through)
			var removed_count: int = 0
			var i: int = 0
			while i < bid_levels.size():
				if bid_levels[i]["price"] > new_price:
					bid_levels.remove_at(i)
					removed_count += 1
				else:
					i += 1
			# Add new far bid levels
			for _j: int in range(removed_count):
				_add_far_level(bid_levels, "sell", book, vol, prev_close)
			# ask: insert new_price + tick_size as new ask1
			var ts: int = get_tick_size(new_price)
			var base_q: float = _order_book_base_qty(vol)
			var new_ask_qty: int = maxi(1, int(base_q * LEVEL_WEIGHT[4] * _rng.randf_range(0.7, 1.3)))
			ask_levels.insert(0, {"price": new_price + ts, "qty": new_ask_qty})
			if ask_levels.size() > ORDER_BOOK_LEVELS:
				ask_levels.resize(ORDER_BOOK_LEVELS)
			# Verify invariant: bid1 must not exceed new_price
			if not bid_levels.is_empty() and bid_levels[0]["price"] > new_price:
				bid_levels[0]["price"] = new_price

		# ── Phase 2: Volume-correlated qty fluctuation ──
		var daily_vol: int = maxi(1, DAILY_VOLUME_BY_PROFILE[vol])
		var tick_volume: float = 0.0
		if not s["tick_volumes"].is_empty():
			tick_volume = s["tick_volumes"][s["tick_volumes"].size() - 1]
		var volume_factor: float = clampf(
			tick_volume / (float(daily_vol) / float(maxi(1, GameClock.TICKS_PER_DAY))),
			ORDER_BOOK_VOLUME_FACTOR_MIN, ORDER_BOOK_VOLUME_FACTOR_MAX
		)
		var base_qty: float = _order_book_base_qty(vol)
		## while loop — remove_at(rank) shifts later elements down; don't increment rank
		## so the element that slid into this position is processed next (fix: for-range skip bug).
		var rank: int = 0
		while rank < ask_levels.size():
			var level: Dictionary = ask_levels[rank]
			var base_q: float = base_qty * LEVEL_WEIGHT[mini(rank, ORDER_BOOK_LEVELS - 1)]
			var inflow: int = int(base_q * ORDER_BOOK_INFLOW_RATE * volume_factor * _rng.randf_range(0.5, 1.5))
			var outflow: int = int(base_q * ORDER_BOOK_OUTFLOW_RATE * volume_factor * _rng.randf_range(0.5, 1.5))
			level["qty"] = maxi(0, level["qty"] + inflow - outflow)
			if level["qty"] == 0:
				ask_levels.remove_at(rank)
				_add_far_level(ask_levels, "buy", book, vol, prev_close)
			else:
				rank += 1
		rank = 0
		while rank < bid_levels.size():
			var level: Dictionary = bid_levels[rank]
			var base_q: float = base_qty * LEVEL_WEIGHT[mini(rank, ORDER_BOOK_LEVELS - 1)]
			var inflow: int = int(base_q * ORDER_BOOK_INFLOW_RATE * volume_factor * _rng.randf_range(0.5, 1.5))
			var outflow: int = int(base_q * ORDER_BOOK_OUTFLOW_RATE * volume_factor * _rng.randf_range(0.5, 1.5))
			level["qty"] = maxi(0, level["qty"] + inflow - outflow)
			if level["qty"] == 0:
				bid_levels.remove_at(rank)
				_add_far_level(bid_levels, "sell", book, vol, prev_close)
			else:
				rank += 1


## Compute base qty per level from daily volume profile (GDD §4-1).
func _order_book_base_qty(vol: int) -> float:
	return maxf(1.0, float(DAILY_VOLUME_BY_PROFILE[vol]) / float(maxi(1, GameClock.TICKS_PER_DAY)) / 5.0)


## Add a new far-end level to the given levels array.
## For ask ("buy" sweep), new level goes at price beyond the current farthest ask.
## For bid ("sell" sweep), new level goes at price below the current farthest bid.
## Respects upper/lower daily limits (GDD §4-4, EC-01, EC-02).
func _add_far_level(
	levels: Array, side: String, _book: Dictionary, vol: int, prev_close: int
) -> void:
	var base_qty: float = _order_book_base_qty(vol)
	var new_qty: int = maxi(1, int(base_qty * LEVEL_WEIGHT[ORDER_BOOK_LEVELS - 1] * _rng.randf_range(0.7, 1.3)))
	if side == "buy":  # ask side
		var upper_limit: int = round_to_tick(float(prev_close) * (1.0 + DAILY_LIMIT_PCT)) if prev_close > 0 else 999_999_999
		var new_price: int
		if levels.is_empty():
			return  # Cannot determine anchor without existing levels
		var far_price: int = levels[levels.size() - 1]["price"]
		new_price = far_price + get_tick_size(far_price)
		if new_price <= upper_limit:
			levels.append({"price": new_price, "qty": new_qty})
	else:  # bid side
		var lower_limit: int = round_to_tick(float(prev_close) * (1.0 - DAILY_LIMIT_PCT)) if prev_close > 0 else 1
		if levels.is_empty():
			return
		var far_price: int = levels[levels.size() - 1]["price"]
		var ts: int = get_tick_size(far_price)
		var new_price: int = maxi(1, far_price - ts)
		if new_price >= lower_limit:
			levels.append({"price": new_price, "qty": new_qty})


# ── Market Index (시총가중지수) ──

func _compute_total_market_cap() -> float:
	var total: float = 0.0
	for stock_id: String in _stock_states:
		var stock: StockData = StockDatabase.get_stock(stock_id)
		if stock:
			total += float(_stock_states[stock_id]["current_price"]) * float(stock.listed_shares)
	return total


func _update_index() -> void:
	if _base_market_cap <= 0.0:
		return
	var current_cap: float = _compute_total_market_cap()
	_current_index = (current_cap / _base_market_cap) * INDEX_BASE
	_index_history.append(_current_index)


## Returns the current market index value.
func get_market_index() -> float:
	return _current_index


## Returns the previous day's closing index value.
func get_prev_day_index() -> float:
	return _prev_day_index


## Returns the index change from previous day close (%).
func get_index_change_pct() -> float:
	if _prev_day_index <= 0.0:
		return 0.0
	return (_current_index - _prev_day_index) / _prev_day_index * 100.0


## Returns the equal-weighted average daily return (%) across all active stocks.
## Used by XpSystem to compute player alpha (player_return − market_return).
## Returns 0.0 if no stocks have a valid previous close.
func get_market_avg_return_pct() -> float:
	var total: float = 0.0
	var count: int = 0
	for stock_id: String in _stock_states:
		var s: Dictionary = _stock_states[stock_id]
		var prev_close: int = s.get("prev_day_close", 0)
		if prev_close <= 0:
			continue
		var cur: int = s.get("current_price", prev_close)
		total += float(cur - prev_close) / float(prev_close) * 100.0
		count += 1
	return total / float(count) if count > 0 else 0.0


## Returns the market cap of a stock (current_price × listed_shares).
func get_market_cap(stock_id: String) -> int:
	var s: Dictionary = _stock_states.get(stock_id, {})
	var stock: StockData = StockDatabase.get_stock(stock_id)
	if s.is_empty() or stock == null:
		return 0
	return s["current_price"] * stock.listed_shares


## Returns the full index tick history.
func get_index_history() -> Array[float]:
	return _index_history

# ── Transition Matrix Builder (GDD Rules 1-3, 1-4, 1-5) ──

func _build_transition_matrix(
	vol_profile: StockData.VolatilityProfile, bias: SeasonBias
) -> Array:
	var self_scale: float = VOL_SELF_SCALE[vol_profile]
	var breakout_scale: float = VOL_BREAKOUT_SCALE[vol_profile]
	var up_bonus: float = SEASON_BIAS_UP[bias]
	var down_penalty: float = SEASON_BIAS_DOWN[bias]

	var up_states: Array[int] = [MarkovState.STRONG_UP, MarkovState.UPTREND, MarkovState.BREAKOUT_UP]
	var down_states: Array[int] = [MarkovState.STRONG_DOWN, MarkovState.DOWNTREND, MarkovState.BREAKOUT_DOWN]

	var matrix: Array = []
	for i: int in range(7):
		var row: Array[float] = _build_matrix_row(i, self_scale, breakout_scale)
		_apply_season_bias_to_row(row, i, up_states, down_states, up_bonus, down_penalty)
		_renormalize_row(row)
		matrix.append(row)

	return matrix


## Build and scale a single transition matrix row for state i (Steps 1-3).
## Uses _cfg_transition_matrix (JSON-loaded, Phase 2) when available; falls back to const.
func _build_matrix_row(
	i: int, self_scale: float, breakout_scale: float
) -> Array[float]:
	var base_matrix: Array = _cfg_transition_matrix if not _cfg_transition_matrix.is_empty() else TRANSITION_MATRIX
	var row: Array[float] = []
	for j: int in range(7):
		row.append(float(base_matrix[i][j]))

	# Step 1: Scale self-transition
	var adjusted_self: float = minf(row[i] * self_scale, 0.98)

	# Step 2: Scale breakout transitions
	var breakout_indices: Array[int] = []
	for bi: int in [5, 6]:
		if bi != i:
			breakout_indices.append(bi)

	var breakout_original: float = 0.0
	for bi: int in breakout_indices:
		breakout_original += row[bi]

	var remaining: float = 1.0 - adjusted_self
	var breakout_adjusted: float = minf(breakout_original * breakout_scale, remaining * 0.5)

	if breakout_indices.size() == 2 and breakout_original > 0.0:
		var ratio: float = row[5] / breakout_original
		row[5] = breakout_adjusted * ratio
		row[6] = breakout_adjusted * (1.0 - ratio)
	elif breakout_indices.size() == 1:
		row[breakout_indices[0]] = breakout_adjusted

	# Step 3: Distribute remaining to non-self, non-breakout
	var non_self_non_breakout: float = remaining - breakout_adjusted
	var others: Array[int] = []
	var others_sum: float = 0.0
	for j: int in range(7):
		if j != i and j != 5 and j != 6:
			others.append(j)
			others_sum += row[j]
	if others_sum > 0.0:
		for j: int in others:
			row[j] = row[j] / others_sum * non_self_non_breakout

	row[i] = adjusted_self
	return row


## Apply season bias nudges to non-self transitions (Step 4).
func _apply_season_bias_to_row(
	row: Array[float], self_idx: int,
	up_states: Array[int], down_states: Array[int],
	up_bonus: float, down_penalty: float
) -> void:
	for j: int in range(7):
		if j == self_idx:
			continue
		if j in up_states:
			row[j] += up_bonus / float(up_states.size())
		elif j in down_states:
			row[j] += down_penalty / float(down_states.size())


## Apply MacroState column bias to a 7×7 transition matrix (ADR-026).
## TREND_UP(0): multiply STRONG_UP(0) + UPTREND(1) columns by biasFactor then renormalize.
## FLAT(1): returns matrix unchanged (no allocation — identity op).
## TREND_DOWN(2): multiply DOWNTREND(3) + STRONG_DOWN(4) columns by biasFactor.
func _apply_macro_bias_to_matrix(matrix: Array, macro_state: int) -> Array:
	if macro_state == MacroState.FLAT:
		return matrix
	var bias_factor: float = float(_macro_cfg.get("biasFactor", 3.0))
	var boost_cols: Array[int]
	if macro_state == MacroState.TREND_UP:
		boost_cols = [MarkovState.STRONG_UP, MarkovState.UPTREND]
	else:
		boost_cols = [MarkovState.DOWNTREND, MarkovState.STRONG_DOWN]
	var result: Array = []
	for i: int in range(7):
		var row: Array[float] = []
		for j: int in range(7):
			row.append(float(matrix[i][j]))
		for col: int in boost_cols:
			row[col] *= bias_factor
		_renormalize_row(row)
		result.append(row)
	return result


## Clamp negatives and renormalize a probability row to sum to 1.
func _renormalize_row(row: Array[float]) -> void:
	var total: float = 0.0
	for j: int in range(7):
		row[j] = maxf(0.0, row[j])
		total += row[j]
	if total > 0.0:
		for j: int in range(7):
			row[j] = row[j] / total

# ── Utility ──

## Box-Muller transform for normal distribution sampling.
func _randn() -> float:
	var u1: float = _rng.randf()
	var u2: float = _rng.randf()
	if u1 < 1e-10:
		u1 = 1e-10
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2)
