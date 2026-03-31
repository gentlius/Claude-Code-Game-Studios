## Autoload — Generates real-time prices for all 10 stocks using a 3-layer algorithm.
## Layer 1: Pattern (Markov chain) | Layer 2: Drift (mean reversion) | Layer 3: Event (news impact)
## See: design/gdd/price-engine.md, prototypes/price-engine/REPORT.md
extends Node

# ── Signals ──

## Emitted after all stock prices are updated for a tick.
signal on_price_updated(tick: int)

## Emitted when a price hits the hard clamp boundary.
signal on_price_clamped(stock_id: String, clamped_price: int, was_raw: float)

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
# [bias, mag_min, mag_max, noise_std, min_duration]

const STATE_PARAMS: Dictionary = {
	MarkovState.STRONG_UP:     [+0.0012, +0.0003, +0.0020, 0.0008, 20],
	MarkovState.UPTREND:       [+0.0005, +0.0001, +0.0010, 0.0006, 30],
	MarkovState.SIDEWAYS:      [ 0.0000, -0.0005, +0.0005, 0.0004, 40],
	MarkovState.DOWNTREND:     [-0.0005, -0.0010, -0.0001, 0.0006, 30],
	MarkovState.STRONG_DOWN:   [-0.0012, -0.0020, -0.0003, 0.0008, 20],
	MarkovState.BREAKOUT_UP:   [+0.0030, +0.0010, +0.0050, 0.0015, 5],
	MarkovState.BREAKOUT_DOWN: [-0.0030, -0.0050, -0.0010, 0.0015, 5],
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

const STATE_VOLUME_MULT: Array[float] = [1.5, 1.2, 0.8, 1.2, 1.5, -1.0, -1.0]
# -1.0 for BREAKOUT means sample uniform(3.0, 5.0)

# ── Constants: Season Bias (GDD Rule 1-5, updated per prototype) ──

const SEASON_BIAS_UP: Array[float]   = [+0.01, 0.00, -0.01]  # BULL, NEUTRAL, BEAR
const SEASON_BIAS_DOWN: Array[float] = [-0.01, 0.00, +0.01]

# ── Tuning Knobs (GDD updated values after prototype) ──

@export var k_drift: float = 0.001
@export var threshold_soft: float = 0.20
@export var threshold_hard: float = 0.50
@export var max_single_impact: float = 0.25
@export var breakout_force_threshold: float = 0.05

# ── Per-Stock Runtime State ──

var _stock_states: Dictionary = {}  ## stock_id -> _StockState
var _engine_state: EngineState = EngineState.UNINITIALIZED
var _transition_matrices: Dictionary = {}  ## stock_id -> Array[Array[float]]

# ── Lifecycle ──

func _ready() -> void:
	GameClock.on_tick.connect(_on_tick)
	GameClock.on_season_start.connect(_on_season_start)
	GameClock.on_market_state_changed.connect(_on_market_state_changed)


func _on_season_start() -> void:
	_initialize_season()


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

# ── Season Initialization (GDD: UNINITIALIZED → READY) ──

func _initialize_season() -> void:
	_stock_states.clear()
	_transition_matrices.clear()

	var stock_ids: Array[String] = StockDatabase.get_all_stock_ids()
	for stock_id: String in stock_ids:
		var stock: StockData = StockDatabase.get_stock(stock_id)
		if stock == null:
			continue

		# Assign random season bias (BULL 40%, NEUTRAL 30%, BEAR 30%)
		var r: float = randf()
		var bias: SeasonBias
		if r < 0.4:
			bias = SeasonBias.BULL
		elif r < 0.7:
			bias = SeasonBias.NEUTRAL
		else:
			bias = SeasonBias.BEAR

		_stock_states[stock_id] = {
			"stock_id": stock_id,
			"current_price": stock.base_price,
			"base_price": stock.base_price,
			"volatility_profile": stock.volatility_profile,
			"macro_sensitivity": stock.macro_sensitivity,
			"sector_sensitivity": stock.sector_sensitivity,
			"markov_state": MarkovState.SIDEWAYS,
			"state_duration": 0,
			"season_bias": bias,
			"tick_prices": [] as Array[int],
			"tick_volumes": [] as Array[float],
			"ohlcv_daily": [] as Array[Dictionary],
			"event_queue": [] as Array,
			"gradual_events": [] as Array,
		}

		_transition_matrices[stock_id] = _build_transition_matrix(
			stock.volatility_profile, bias
		)

	_engine_state = EngineState.READY

# ── Tick Processing (GDD Rule 5) ──

func _on_tick(tick_number: int, _day: int, _week: int) -> void:
	if _engine_state != EngineState.RUNNING:
		return

	for stock_id: String in _stock_states:
		_process_stock_tick(stock_id, tick_number)

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
	var base: int = s["base_price"]
	var min_price: float = maxf(float(base) * 0.15, 1000.0)
	var max_price: float = float(base) * 3.0

	var clamped: float = clampf(raw_price, min_price, max_price)
	if clamped != raw_price:
		on_price_clamped.emit(stock_id, roundi(clamped), raw_price)

	var final_price: int = roundi(clamped / 100.0) * 100
	s["current_price"] = final_price

	# Step 7: Markov state transition (GDD Rule 1-2, 1-3)
	if forced_breakout >= 0:
		s["markov_state"] = forced_breakout
		s["state_duration"] = 0
	else:
		var params: Array = STATE_PARAMS[s["markov_state"]]
		var min_dur: int = params[4]
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

	# Step 8: Volume (GDD Rule 4)
	var volume: float = _compute_volume(s, event_delta, tick_in_day)

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
func _compute_volume(s: Dictionary, event_delta: float, tick_in_day: int) -> float:
	var vol: int = s["volatility_profile"]
	var vol_range: Array = BASE_VOLUME_RANGE[vol]
	var base_vol: float = randf_range(float(vol_range[0]), float(vol_range[1]))

	var state: int = s["markov_state"]
	var mult: float = STATE_VOLUME_MULT[state]
	if mult < 0.0:  # BREAKOUT
		mult = randf_range(3.0, 5.0)
	var state_vol: float = base_vol * mult

	var event_spike: float = 0.0
	if absf(event_delta) > 0.0:
		var spike_mult: float = clampf(absf(event_delta) * 30.0, 1.0, 10.0)
		event_spike = base_vol * spike_mult

	var tod_mult: float = 1.0
	if tick_in_day < 10:
		tod_mult = 2.5
	elif tick_in_day >= 380:
		tod_mult = 2.0

	return (state_vol + event_spike) * tod_mult

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

		var ohlcv: Dictionary = {
			"open": day_prices[0],
			"high": high,
			"low": low,
			"close": day_prices[day_prices.size() - 1],
			"volume": total_vol,
		}
		s["ohlcv_daily"].append(ohlcv)

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
