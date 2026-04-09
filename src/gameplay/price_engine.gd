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

# ── Constants: Season Bias (GDD Rule 1-5, updated per prototype) ──

const SEASON_BIAS_UP: Array[float]   = [+0.01, 0.00, -0.01]  # BULL, NEUTRAL, BEAR
const SEASON_BIAS_DOWN: Array[float] = [-0.01, 0.00, +0.01]

# ── Constants: Season Bias Probabilities (GDD Rule 1-5) ──

const BIAS_BULL_PROB: float = 0.4     ## BULL 40%, NEUTRAL 30%, BEAR 30%
const BIAS_NEUTRAL_CUTOFF: float = 0.7  ## cumulative: BULL + NEUTRAL

# ── Constants: Hard Clamp Bounds (GDD Rule 2-3) ──

const HARD_CLAMP_MIN_RATIO: float = 0.15  ## Lifetime min = base_price × 0.15
const HARD_CLAMP_MAX_RATIO: float = 3.0   ## Lifetime max = base_price × 3.0

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

# ── Tick Size Table (KRX-based, GDD Rule 5-3) ──

## Returns the tick size (호가 단위) for a given price level.
## Chart renderer and order engine also use this for grid alignment and order validation.
static func get_tick_size(price: int) -> int:
	if price < 1000:
		return 1
	if price < 5000:
		return 5
	if price < 10000:
		return 10
	if price < 50000:
		return 50
	if price < 100000:
		return 100
	if price < 500000:
		return 500
	return 1000


## Rounds a raw price to the nearest tick size.
static func round_to_tick(raw_price: float) -> int:
	var ts: int = get_tick_size(roundi(raw_price))
	return roundi(raw_price / float(ts)) * ts

# ── Per-Stock Runtime State ──

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

# ── Lifecycle ──

func _ready() -> void:
	# on_tick is NOT connected here — GameClock calls _on_tick directly in
	# _process_tick() to enforce the GDD-mandated News → Price → Order order.
	GameClock.on_season_start.connect(_on_season_start)
	GameClock.on_market_state_changed.connect(_on_market_state_changed)


func _on_season_start() -> void:
	_reset_season_mechanics()


## Called by SaveSystem after loading a save where a season was in progress.
## Rebuilds _stock_states in one pass: StockDatabase for metadata, save_data for
## dynamic fields (prices, season_bias, ohlcv_daily, tick_prices, tick_volumes).
## Does NOT call _reset_season_mechanics() — that would discard the restored state.
## Backward-compat: old saves with "closing_prices" flat dict are still accepted.
## Engine enters READY state; transitions to RUNNING when player opens market.
func initialize_for_load(save_data: Dictionary) -> void:
	_stock_states.clear()
	_transition_matrices.clear()

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
			var r: float = randf()
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

		_stock_states[stock_id] = {
			"stock_id":           stock_id,
			"current_price":      cur_price,
			"base_price":         stock.base_price,
			"prev_day_close":     prev_close,
			"volatility_profile": stock.volatility_profile,
			"macro_sensitivity":  stock.macro_sensitivity,
			"sector_sensitivity": stock.sector_sensitivity,
			"markov_state":       MarkovState.SIDEWAYS,  # session-scoped, not persisted
			"state_duration":     0,
			"season_bias":        bias,
			"tick_prices":        tick_prices,
			"tick_volumes":       tick_volumes,
			"ohlcv_daily":        ohlcv_daily,
			"event_queue":        [] as Array,
			"gradual_events":     [] as Array,
		}
		_transition_matrices[stock_id] = _build_transition_matrix(
			stock.volatility_profile, bias
		)

	_vi_states.clear()
	for stock_id: String in _stock_states:
		_vi_states[stock_id] = {"halt_remaining": 0, "count_today": 0, "cooldown": 0}

	_cb_stage = 0
	_cb_halt_remaining = 0
	_base_market_cap = _compute_total_market_cap()
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
			"current_price":  s.get("current_price",  0),
			"prev_day_close": s.get("prev_day_close", 0),
			"season_bias":    int(s.get("season_bias", SeasonBias.NEUTRAL)),
			"ohlcv_daily":    s.get("ohlcv_daily",    []),
			"tick_prices":    s.get("tick_prices",     []),
			"tick_volumes":   s.get("tick_volumes",    []),
		}
	return {
		"stocks": stocks_data,
		"market_index": _current_index,
		"prev_day_index": _prev_day_index,
	}


## Resets all price engine state for unit tests. Call in before_each.
## Resets all price engine state. Called by GameMain (new game) and tests (before_each).
func reset() -> void:
	_stock_states.clear()
	_vi_states.clear()
	_cb_stage = 0
	_cb_halt_remaining = 0
	_prev_day_index = 0.0
	_current_index = 0.0
	_base_market_cap = 0.0
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


## Returns the daily price limits {upper: int, lower: int, prev_close: int}.
func get_daily_limits(stock_id: String) -> Dictionary:
	var state: Dictionary = _stock_states.get(stock_id, {})
	var prev_close: int = state.get("prev_day_close", 0)
	var upper: int = round_to_tick(float(prev_close) * (1.0 + DAILY_LIMIT_PCT))
	var lower: int = round_to_tick(float(prev_close) * (1.0 - DAILY_LIMIT_PCT))
	return {"upper": upper, "lower": lower, "prev_close": prev_close}


## Returns the current Markov state for a stock.
func get_markov_state(stock_id: String) -> MarkovState:
	var state: Dictionary = _stock_states.get(stock_id, {})
	return state.get("markov_state", MarkovState.SIDEWAYS) as MarkovState


## Push an event from the News/Events system.
func push_event(event: MarketEvent) -> void:
	for stock_id: String in event.target_stock_ids:
		if not _stock_states.has(stock_id):
			continue
		var state: Dictionary = _stock_states[stock_id]
		var queue: Array = state["event_queue"]
		queue.append(event)

# ── Season Initialization ──

## Returns a randomly selected SeasonBias (BULL 40%, NEUTRAL 30%, BEAR 30%).
func _random_bias() -> SeasonBias:
	var r: float = randf()
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
	_stock_states.clear()
	_transition_matrices.clear()

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
			"volatility_profile": stock.volatility_profile,
			"macro_sensitivity":  stock.macro_sensitivity,
			"sector_sensitivity": stock.sector_sensitivity,
			"markov_state":       MarkovState.SIDEWAYS,
			"state_duration":     0,
			"season_bias":        bias,
			"tick_prices":        [] as Array[int],
			"tick_volumes":       [] as Array[float],
			"ohlcv_daily":        [] as Array[Dictionary],
			"event_queue":        [] as Array,
			"gradual_events":     [] as Array,
		}
		_transition_matrices[stock_id] = _build_transition_matrix(
			stock.volatility_profile, bias
		)

	_vi_states.clear()
	for stock_id: String in _stock_states:
		_vi_states[stock_id] = {"halt_remaining": 0, "count_today": 0, "cooldown": 0}

	_cb_stage = 0
	_cb_halt_remaining = 0
	_base_market_cap = _compute_total_market_cap()
	_current_index = INDEX_BASE
	_prev_day_index = INDEX_BASE
	_index_history.clear()
	_engine_state = EngineState.READY


## Resets per-season mechanics (Markov state, season bias, tick/OHLCV history, VI, CB,
## market index baseline) for all stocks. current_price and prev_day_close are preserved
## so prices carry forward naturally across seasons. Called every season start (Season 1
## and N+1). No emit — prices are unchanged so UI dirty flags will not trigger; the chart
## renderer re-fetches its buffers on the next MARKET_OPEN state transition.
func _reset_season_mechanics() -> void:
	for stock_id: String in _stock_states:
		var state: Dictionary = _stock_states[stock_id]
		var bias: SeasonBias = _random_bias()
		state["markov_state"]   = MarkovState.SIDEWAYS
		state["state_duration"] = 0
		state["season_bias"]    = bias
		state["tick_prices"]    = [] as Array[int]
		state["tick_volumes"]   = [] as Array[float]
		state["ohlcv_daily"]    = [] as Array[Dictionary]
		state["event_queue"]    = [] as Array
		state["gradual_events"] = [] as Array
		# current_price, prev_day_close: carry forward — not touched
		_transition_matrices[stock_id] = _build_transition_matrix(
			state["volatility_profile"], bias
		)

	for stock_id: String in _vi_states:
		_vi_states[stock_id] = {"halt_remaining": 0, "count_today": 0, "cooldown": 0}
	_cb_stage = 0
	_cb_halt_remaining = 0

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

	for stock_id: String in _stock_states:
		# VI halt check (GDD Rule 2-4)
		var vi: Dictionary = _vi_states.get(stock_id, {})
		if vi.get("halt_remaining", 0) > 0:
			vi["halt_remaining"] -= 1
			if vi["halt_remaining"] == 0:
				vi["cooldown"] = _minutes_to_ticks(VI_COOLDOWN_MINUTES)
				on_vi_released.emit(stock_id)
			# Record frozen price/volume to keep buffers aligned
			var s: Dictionary = _stock_states[stock_id]
			s["tick_prices"].append(s["current_price"])
			s["tick_volumes"].append(0.0)
			continue
		# VI cooldown decrement
		if vi.get("cooldown", 0) > 0:
			vi["cooldown"] -= 1
		_process_stock_tick(stock_id, tick_number)
		# Skip VI check on tick 0: prev_day_close == base_price at season/day
		# start, so the first random delta can falsely exceed VI_THRESHOLD.
		if tick_number > 0:
			_check_vi(stock_id)

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

	# Step 3: Drift layer (GDD Rule 2)
	var drift_delta: float = _compute_drift_delta(
		s["current_price"], s["base_price"]
	)

	# Step 4: Event layer (GDD Rule 3)
	var event_result: Dictionary = _compute_event_delta(s, tick_events)
	var event_delta: float = event_result["delta"]
	var forced_breakout: int = event_result["forced_breakout"]  # -1 if none

	# Clear event queue after processing
	s["event_queue"] = [] as Array

	# Step 5: Additive combination
	var total_delta: float = pattern_delta + drift_delta + event_delta

	# Step 6: Price update
	var raw_price: float = float(s["current_price"]) * (1.0 + total_delta)

	# Hard clamp: lifetime bounds (base_price * 0.15 ~ 3.0)
	var base: int = s["base_price"]
	var min_price: float = maxf(float(base) * HARD_CLAMP_MIN_RATIO, 1000.0)
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
			var roll: float = randf()
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
	var volume: float = _compute_volume(s, pattern_delta, event_delta, tick_in_day)

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

	var magnitude: float = randf_range(mag_min, mag_max)
	var noise: float = _randn() * noise_std
	var raw: float = bias + magnitude + noise

	return raw * VOL_PATTERN_SCALE[vol_profile]


## Drift layer: mean reversion toward base_price (GDD Rule 2)
func _compute_drift_delta(current_price: int, base_price: int) -> float:
	if base_price == 0:
		return 0.0
	var deviation_ratio: float = (float(current_price) - float(base_price)) / float(base_price)
	var intensity: float = _drift_intensity(deviation_ratio)
	return -k_drift * deviation_ratio * intensity


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
	var event_delta: float = 0.0
	var forced_breakout: int = -1
	var vol: int = s["volatility_profile"]
	var macro_sens: float = s["macro_sensitivity"]
	var sector_sens: float = s["sector_sensitivity"]
	var gradual_events: Array = s["gradual_events"]

	# Process new events
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
			event_delta += actual
			if absf(actual) >= breakout_force_threshold:
				if actual > 0:
					forced_breakout = MarkovState.BREAKOUT_UP
				else:
					forced_breakout = MarkovState.BREAKOUT_DOWN

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
			event_delta += _gradual_tick_impact(ge)
			ge["remaining_ticks"] -= 1
			if ge["remaining_ticks"] > 0:
				gradual_events.append(ge)

	# Process ongoing gradual events
	var still_active: Array = []
	for ge: Dictionary in gradual_events:
		if ge["remaining_ticks"] > 0:
			event_delta += _gradual_tick_impact(ge)
			ge["remaining_ticks"] -= 1
			if ge["remaining_ticks"] > 0:
				still_active.append(ge)
	s["gradual_events"] = still_active

	return {"delta": event_delta, "forced_breakout": forced_breakout}


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
## tick_energy = |pattern_delta| + |event_delta| measures total force before cancellation.
func _compute_volume(
	s: Dictionary, pattern_delta: float, event_delta: float, tick_in_day: int
) -> float:
	var vol: int = s["volatility_profile"]
	var vol_range: Array = BASE_VOLUME_RANGE[vol]
	var base_vol: float = randf_range(float(vol_range[0]), float(vol_range[1]))

	# 4-2: Tick energy — correlation between price movement forces and volume
	var tick_energy: float = absf(pattern_delta) + absf(event_delta)
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
	# 1 day = 1560 ticks (4 ticks/min × 390 min)
	# Opening 10 min = ticks 0-39, Closing 10 min = ticks 1520-1559
	var tod_mult: float = 1.0
	if tick_in_day < 40:
		tod_mult = 2.5
	elif tick_in_day >= 1520:
		tod_mult = 2.0

	# 4-6: Final volume
	return base_vol * state_mult * energy_mult * limit_dampen * tod_mult

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
	var vi: Dictionary = _vi_states.get(stock_id, {})
	return vi.get("halt_remaining", 0) > 0


## Returns current circuit breaker stage (0=none, 1=halt, 2=early close).
func get_cb_stage() -> int:
	return _cb_stage


# ── End of Day ──

func _end_trading_day() -> void:
	_engine_state = EngineState.END_OF_DAY

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
		var ohlcv: Dictionary = {
			"open": day_prices[0],
			"high": high,
			"low": low,
			"close": close_price,
			"volume": total_vol,
		}
		s["ohlcv_daily"].append(ohlcv)

		# Update prev_day_close for next day's daily limit calculation
		s["prev_day_close"] = close_price

		# tick_prices/tick_volumes는 리셋하지 않는다.
		# GDD chart-renderer.md §5-1: max_tick_history = 31200 (시즌 전체 보관).
		# 31200틱 × 46종목 × 12 bytes ≈ 17 MB — 허용 범위.
		# chart_renderer는 MARKET_OPEN마다 _aggregate_candles()로 전체 재집계하여
		# 1분/5분/15분봉에서 과거 일자 스크롤을 지원한다.

	# Reset VI daily counters (GDD Rule 2-4: max 1 per day resets each day)
	for stock_id: String in _vi_states:
		_vi_states[stock_id]["count_today"] = 0
		_vi_states[stock_id]["halt_remaining"] = 0
		_vi_states[stock_id]["cooldown"] = 0

	# Reset circuit breaker for next day (GDD Rule 2-5)
	_cb_stage = 0
	_cb_halt_remaining = 0

	# Save end-of-day index
	_prev_day_index = _current_index

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
		var row: Array[float] = []
		for j: int in range(7):
			row.append(TRANSITION_MATRIX[i][j])

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

		# Step 4: Season bias
		for j: int in range(7):
			if j == i:
				continue
			if j in up_states:
				row[j] += up_bonus / float(up_states.size())
			elif j in down_states:
				row[j] += down_penalty / float(down_states.size())

		# Clamp negatives and renormalize
		var total: float = 0.0
		for j: int in range(7):
			row[j] = maxf(0.0, row[j])
			total += row[j]
		if total > 0.0:
			for j: int in range(7):
				row[j] = row[j] / total

		matrix.append(row)

	return matrix

# ── Utility ──

## Box-Muller transform for normal distribution sampling.
func _randn() -> float:
	var u1: float = randf()
	var u2: float = randf()
	if u1 < 1e-10:
		u1 = 1e-10
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2)
