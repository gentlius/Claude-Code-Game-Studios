## Autoload — Controls game time flow: ticks, days, weeks, seasons.
## Foundation layer. All gameplay systems subscribe to this clock's signals.
## See: design/gdd/game-clock.md
extends Node

# ── Enums ──

enum MarketState {
	PRE_MARKET,
	MARKET_OPEN,
	PAUSED,
	MARKET_CLOSED,
	DAY_TRANSITION,
	WEEK_END,
	SEASON_END,
}

# ── Signals (Signal Catalog from GDD) ──

## Emitted every tick during MARKET_OPEN. Core processing trigger.
signal on_tick(tick_number: int, day: int, week: int)

## Emitted on any market state transition.
signal on_market_state_changed(new_state: MarketState, prev_state: MarketState)

## Convenience signals for specific transitions.
signal on_season_start()
signal on_market_open()
signal on_market_close()
signal on_day_transition()
signal on_week_end()
signal on_season_end()

# ── Constants ──

const TICKS_PER_MINUTE: int = 4    ## 기본 단위: 1 game-minute = 4 ticks
const MINUTES_PER_DAY: int = 390    ## 09:00–15:30 KST = 390 game-minutes
const TICKS_PER_DAY: int = TICKS_PER_MINUTE * MINUTES_PER_DAY  ## = 1560
const DAYS_PER_WEEK: int = 5
const WEEKS_PER_SEASON: int = 4
const BASE_TICK_INTERVAL: float = 0.192  ## real seconds per tick at 1x speed (~5min/day)
const SECONDS_PER_TICK: int = 15  ## game-world seconds each tick represents (4 ticks = 1 minute)

# ── State ──

var _market_state: MarketState = MarketState.PRE_MARKET
var _current_tick: int = 0
var _current_day: int = 0   ## 0-based within season
var _current_week: int = 0  ## 0-based within season
var _speed_multiplier: float = 1.0
var _tick_accumulator: float = 0.0
var _season_active: bool = false

# ── Public API ──

## Returns the current market state (PRE_MARKET, MARKET_OPEN, etc.).
func get_market_state() -> MarketState:
	return _market_state


## Returns the current tick within the trading day (0 to TICKS_PER_DAY-1).
func get_current_tick() -> int:
	return _current_tick


## Returns the current day within the season (0-indexed).
func get_current_day() -> int:
	return _current_day


## Returns the current week within the season (0-indexed).
## Invariant: during WEEK_END and SEASON_END signal handlers this still returns
## the week that just ended (the pre-increment value), because _current_week is
## only incremented inside _advance_to_next_day(), which runs after the player
## confirms the transition. Subscribers must not assume the value has advanced
## until on_day_transition fires.
func get_current_week() -> int:
	return _current_week


## Returns intraday progress as a fraction [0.0, 1.0].
func get_day_progress() -> float:
	if TICKS_PER_DAY == 0:
		return 0.0
	return float(_current_tick) / float(TICKS_PER_DAY)


## Returns the current game speed multiplier (1.0 to 4.0).
func get_speed_multiplier() -> float:
	return _speed_multiplier


## Sets game speed multiplier. Valid values are the discrete set {1, 2, 4}.
## If an invalid value is passed, a warning is pushed and the nearest valid
## speed is used instead.
func set_speed(multiplier: float) -> void:
	const VALID_SPEEDS: Array[float] = [1.0, 2.0, 4.0]
	if multiplier in VALID_SPEEDS:
		_speed_multiplier = multiplier
		return
	push_warning("GameClock.set_speed: invalid speed %.2f — snapping to nearest valid value" % multiplier)
	var nearest: float = VALID_SPEEDS[0]
	var best_dist: float = absf(multiplier - nearest)
	for speed: float in VALID_SPEEDS:
		var dist: float = absf(multiplier - speed)
		if dist < best_dist:
			best_dist = dist
			nearest = speed
	_speed_multiplier = nearest


## Call to begin a new season. Resets all counters and emits on_season_start.
func start_season() -> void:
	_current_tick = 0
	_current_day = 0
	_current_week = 0
	_tick_accumulator = 0.0
	_season_active = true
	on_season_start.emit()
	_change_state(MarketState.PRE_MARKET)


## Called by UI when player confirms PRE_MARKET → opens the market.
func confirm_market_open() -> void:
	if _market_state != MarketState.PRE_MARKET:
		return
	_change_state(MarketState.MARKET_OPEN)
	on_market_open.emit()


## Toggle pause during MARKET_OPEN.
func toggle_pause() -> void:
	if _market_state == MarketState.MARKET_OPEN:
		_change_state(MarketState.PAUSED)
	elif _market_state == MarketState.PAUSED:
		_change_state(MarketState.MARKET_OPEN)


## Called by UI after player confirms daily/weekly/season report.
func confirm_transition() -> void:
	match _market_state:
		MarketState.MARKET_CLOSED:
			_advance_to_next_day()
		MarketState.WEEK_END:
			_advance_to_next_day()
		MarketState.SEASON_END:
			start_season()

# ── Processing ──

func _process(delta: float) -> void:
	if _market_state != MarketState.MARKET_OPEN:
		return

	var tick_interval := BASE_TICK_INTERVAL / _speed_multiplier
	_tick_accumulator += delta

	while _tick_accumulator >= tick_interval:
		_tick_accumulator -= tick_interval
		_process_tick()


func _process_tick() -> void:
	_current_tick += 1
	# Emit the tick number that was just completed (1-based from the subscriber's
	# perspective). The pre-increment value is passed so that subscribers calling
	# get_current_tick() during on_tick receive the same value as tick_number.
	on_tick.emit(_current_tick, _current_day, _current_week)

	if _current_tick >= TICKS_PER_DAY:
		_end_trading_day()

# ── Internal State Transitions ──

func _change_state(new_state: MarketState) -> void:
	var prev := _market_state
	_market_state = new_state
	on_market_state_changed.emit(new_state, prev)


func _end_trading_day() -> void:
	_change_state(MarketState.MARKET_CLOSED)
	on_market_close.emit()

	var day_in_week := _current_day % DAYS_PER_WEEK
	if day_in_week == DAYS_PER_WEEK - 1:
		# End of week — defer so MARKET_CLOSED state is stable for one frame
		# before subscribers see the WEEK_END transition.
		call_deferred("_emit_week_end_deferred")


## Deferred so MARKET_CLOSED is stable for one full frame before this fires.
func _emit_week_end_deferred() -> void:
	_change_state(MarketState.WEEK_END)
	on_week_end.emit()

	var is_last_week := _current_week >= WEEKS_PER_SEASON - 1
	if is_last_week:
		# Defer again so WEEK_END is stable for one full frame before SEASON_END.
		call_deferred("_emit_season_end_deferred")


## Deferred so WEEK_END is stable for one full frame before this fires.
func _emit_season_end_deferred() -> void:
	_change_state(MarketState.SEASON_END)
	on_season_end.emit()


func _advance_to_next_day() -> void:
	_current_tick = 0
	_tick_accumulator = 0.0
	_current_day += 1

	if _current_day % DAYS_PER_WEEK == 0:
		_current_week += 1

	_change_state(MarketState.DAY_TRANSITION)
	on_day_transition.emit()
	_change_state(MarketState.PRE_MARKET)
