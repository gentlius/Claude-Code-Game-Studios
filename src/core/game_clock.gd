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

## Emitted when SEASON_END settlement is confirmed and a new season should begin.
## SeasonManager connects to this and calls start_season() — keeps Foundation→Gameplay
## dependency direction clean (GameClock never calls SeasonManager directly).
signal on_new_season_requested()

# ── Constants ──

const TICKS_PER_MINUTE: int = 4    ## 기본 단위: 1 game-minute = 4 ticks
const MINUTES_PER_DAY: int = 390    ## 09:00–15:30 KST = 390 game-minutes
const TICKS_PER_DAY: int = TICKS_PER_MINUTE * MINUTES_PER_DAY  ## = 1560
const DAYS_PER_WEEK: int = 5
const WEEKS_PER_SEASON: int = 4
const BASE_TICK_INTERVAL: float = 0.192  ## real seconds per tick at 1x speed (~5min/day)
const SECONDS_PER_TICK: int = 15  ## game-world seconds each tick represents (4 ticks = 1 minute)
## Max ticks fired per frame — prevents death spiral when a slow frame causes tick backlog.
const MAX_TICKS_PER_FRAME: int = 3

# ── State ──

## Runtime trading-hours override — set by configure_trading_hours().
## Defaults to the KR constant. DLC markets call configure_trading_hours() on
## market load so a US/JP market can have fewer or more minutes per day.
## See: TD-DR-08 — GameClock 거래 시간 MarketProfile 동적 로드
var _effective_minutes_per_day: int = MINUTES_PER_DAY
var _effective_ticks_per_day: int = TICKS_PER_DAY

## Auto-slow to 1× when a news event fires above 1×. Configurable via SettingsScreen.
## GDD: design/gdd/settings-screen.md §3-2
var _auto_slow_on_event: bool = true

var _market_state: MarketState = MarketState.PRE_MARKET
var _current_tick: int = 0
var _current_day: int = 0   ## 0-based within season
var _current_week: int = 0  ## 0-based within season
var _speed_multiplier: float = 1.0
var _tick_accumulator: float = 0.0
var _season_active: bool = false
## Reference-counted pause sources. Market resumes only when all sources release.
## Key: source_id (String), Value: true. Dictionary used as a set.
var _pause_sources: Dictionary = {}

# ── Public API ──

## Returns the current market state (PRE_MARKET, MARKET_OPEN, etc.).
func get_market_state() -> MarketState:
	return _market_state


## True after start_season() has been called (i.e. a season is in progress).
## Single source of truth — replaces CurrencySystem.is_season_active().
func is_season_active() -> bool:
	return _season_active


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
## Uses _effective_ticks_per_day so DLC markets with different hours display correctly.
func get_day_progress() -> float:
	if _effective_ticks_per_day == 0:
		return 0.0
	return float(_current_tick) / float(_effective_ticks_per_day)


## Returns the current game speed multiplier (1.0 to 4.0).
func get_speed_multiplier() -> float:
	return _speed_multiplier


## Returns true if today is the final day of the season (TD-CR-17).
## Encapsulates the calendar arithmetic so callers do not depend on raw constants.
func is_season_final_day() -> bool:
	return (
		_current_day % DAYS_PER_WEEK == DAYS_PER_WEEK - 1 and
		_current_week >= WEEKS_PER_SEASON - 1
	)


## Returns true if news events automatically slow the clock to 1×.
func get_auto_slow_on_event() -> bool:
	return _auto_slow_on_event


## Sets whether news events auto-slow the clock to 1×. Called by SettingsScreen.
func set_auto_slow_on_event(value: bool) -> void:
	_auto_slow_on_event = value


## Configures runtime trading hours for the active market.
## Called by the DLC market setup sequence (e.g. SeasonManager after MarketProfile loads).
## [param minutes_per_day] — total trading minutes in one game day.
##   KR default: 390 (09:00–15:30 KST).
##   US example: 390 (09:30–16:00 EST). JP example: 330 (09:00–15:30 JST with lunch break adjusted).
## The const TICKS_PER_DAY remains the KR compile-time value; this method sets
## the runtime override that _process_tick() uses for day-end detection.
## Example: GameClock.configure_trading_hours(MarketProfile.get_calendar_param("trading_minutes"))
func configure_trading_hours(minutes_per_day: int) -> void:
	if minutes_per_day <= 0:
		push_warning("GameClock.configure_trading_hours: invalid minutes_per_day %d — ignoring" % minutes_per_day)
		return
	_effective_minutes_per_day = minutes_per_day
	_effective_ticks_per_day = TICKS_PER_MINUTE * minutes_per_day


## Returns the runtime ticks-per-day value for the currently active market.
## Use this instead of the const TICKS_PER_DAY for any runtime calculation
## that must respect DLC market trading hours.
## Example: float(_current_tick) / float(GameClock.get_effective_ticks_per_day())
func get_effective_ticks_per_day() -> int:
	return _effective_ticks_per_day


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
## Initializes order books for the new trading day before opening (GDD order-book.md §3-1, §9).
func confirm_market_open() -> void:
	if _market_state != MarketState.PRE_MARKET:
		return
	PriceEngine.initialize_order_books()
	_change_state(MarketState.MARKET_OPEN)
	on_market_open.emit()


## Toggle pause during MARKET_OPEN. Kept for backwards-compat with existing UI callers.
## New code should prefer pause_request/pause_release for multi-source pause safety.
func toggle_pause() -> void:
	if _market_state == MarketState.MARKET_OPEN:
		_change_state(MarketState.PAUSED)
	elif _market_state == MarketState.PAUSED:
		_change_state(MarketState.MARKET_OPEN)


## Reference-counted pause request (S3-02). Market pauses on the first call.
## Multiple callers (e.g. league screen + skill overlay) each hold their own source_id.
## Duplicate source_id calls are idempotent (no double-pause).
## [br]Usage: GameClock.pause_request("league_screen")
func pause_request(source_id: String) -> void:
	_pause_sources[source_id] = true
	if _market_state == MarketState.MARKET_OPEN:
		_change_state(MarketState.PAUSED)


## Release one pause source. Market resumes only when _pause_sources is empty.
## Calling release for an unknown source_id is a no-op.
## [br]Usage: GameClock.pause_release("league_screen")
func pause_release(source_id: String) -> void:
	_pause_sources.erase(source_id)
	if _market_state == MarketState.PAUSED and _pause_sources.is_empty():
		_change_state(MarketState.MARKET_OPEN)


## Called by UI after player confirms daily/weekly/season report.
func confirm_transition() -> void:
	match _market_state:
		MarketState.MARKET_CLOSED:
			_advance_to_next_day()
		MarketState.WEEK_END:
			_advance_to_next_day()
		MarketState.SEASON_END:
			## TD-08: SeasonManager owns the full season-start sequence.
			## Signal keeps Foundation→Gameplay dependency direction clean.
			on_new_season_requested.emit()


## Returns serializable clock state for save system.
## Saves day and week counters so week-end/season-end fire at the correct time after load.
## _current_tick is NOT saved — saves occur at PRE_MARKET (after DAY_TRANSITION), where
## _current_day is already advanced by _advance_to_next_day(). No +1 compensation needed.
func get_save_data() -> Dictionary:
	return {
		"current_day":   _current_day,
		"current_week":  _current_week,
		"season_active": _season_active,
		"market_state":  int(_market_state),
	}


## Restores clock state from save data. Must be called before the season-active
## check in SaveSystem so GameClock.is_season_active() returns the correct value.
func load_save_data(data: Dictionary) -> void:
	_current_day   = maxi(data.get("current_day",  0), 0)
	_current_week  = maxi(data.get("current_week", 0), 0)
	_season_active = data.get("season_active", false)
	var state_int: int = data.get("market_state", MarketState.PRE_MARKET)
	if state_int >= 0 and state_int < MarketState.size():
		_market_state = state_int as MarketState
	else:
		_market_state = MarketState.PRE_MARKET


## Resets all runtime state. Called by GameMain (new game) and tests (before_each).
func reset() -> void:
	_market_state = MarketState.PRE_MARKET
	_current_tick = 0
	_current_day = 0
	_current_week = 0
	_speed_multiplier = 1.0
	_tick_accumulator = 0.0
	_season_active = false
	_pause_sources.clear()
	_auto_slow_on_event = true

# ── Processing ──

func _process(delta: float) -> void:
	if _market_state != MarketState.MARKET_OPEN:
		return

	var tick_interval := BASE_TICK_INTERVAL / _speed_multiplier
	_tick_accumulator += delta

	var ticks_this_frame: int = 0
	while _tick_accumulator >= tick_interval and ticks_this_frame < MAX_TICKS_PER_FRAME:
		_tick_accumulator -= tick_interval
		_process_tick()
		ticks_this_frame += 1


func _process_tick() -> void:
	_current_tick += 1
	# GDD-mandated tick processing order: News → Price → Short-margin → Order.
	# Explicit calls guarantee deterministic ordering regardless of signal
	# connection order. The general on_tick signal fires afterwards for any
	# other subscribers (UI, analytics, etc.) that have no ordering requirement.
	NewsEventSystem.process_tick(_current_tick, _current_day, _current_week)
	PriceEngine.process_tick(_current_tick, _current_day, _current_week)
	# P3 ETF: recalculate ETF prices from updated stock prices (sector-etf.md §3-2)
	EtfManager.process_tick(_current_tick, _current_day, _current_week)
	# TR3: margin monitoring after price update, before order matching (GDD short-selling.md §규칙 6)
	ShortSellingSystem.update_and_check_margin(_current_tick)
	OrderEngine.process_tick(_current_tick, _current_day, _current_week)
	# TR4: leverage margin check after order matching (GDD leverage-trading.md §6 GameClock dependency)
	LeverageManager.check_margin_calls()
	# Emit the tick number that was just completed (1-based from the subscriber's
	# perspective). The pre-increment value is passed so that subscribers calling
	# get_current_tick() during on_tick receive the same value as tick_number.
	on_tick.emit(_current_tick, _current_day, _current_week)

	if _current_tick >= _effective_ticks_per_day:
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
