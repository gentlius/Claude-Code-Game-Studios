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

const TICKS_PER_DAY: int = 390
const DAYS_PER_WEEK: int = 5
const WEEKS_PER_SEASON: int = 4
const BASE_TICK_INTERVAL: float = 0.77  ## seconds per tick at 1x speed

# ── State ──

var _market_state: MarketState = MarketState.PRE_MARKET
var _current_tick: int = 0
var _current_day: int = 0   ## 0-based within season
var _current_week: int = 0  ## 0-based within season
var _speed_multiplier: float = 1.0
var _tick_accumulator: float = 0.0
var _season_active: bool = false

# ── Public API ──

func get_market_state() -> MarketState:
	return _market_state


func get_current_tick() -> int:
	return _current_tick


func get_current_day() -> int:
	return _current_day


func get_current_week() -> int:
	return _current_week


func get_day_progress() -> float:
	if TICKS_PER_DAY == 0:
		return 0.0
	return float(_current_tick) / float(TICKS_PER_DAY)


func get_speed_multiplier() -> float:
	return _speed_multiplier


func set_speed(multiplier: float) -> void:
	_speed_multiplier = clampf(multiplier, 1.0, 4.0)


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
	on_tick.emit(_current_tick, _current_day, _current_week)
	_current_tick += 1

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
		# End of week
		_change_state(MarketState.WEEK_END)
		on_week_end.emit()

		var is_last_week := _current_week >= WEEKS_PER_SEASON - 1
		if is_last_week:
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
