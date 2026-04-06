extends GutTest
## Unit tests for VI / Circuit Breaker — see design/gdd/price-engine.md Rules 2-4, 2-5


# ── Helpers ──

const TEST_STOCK_ID: String = "KSF"

func _make_vi_state(halt: int = 0, count: int = 0, cooldown: int = 0) -> Dictionary:
	return {"halt_remaining": halt, "count_today": count, "cooldown": cooldown}


func _make_stock_state(price: int = 50000, prev_close: int = 50000) -> Dictionary:
	return {
		"stock_id": TEST_STOCK_ID,
		"current_price": price,
		"base_price": prev_close,
		"prev_day_close": prev_close,
		"volatility_profile": StockData.VolatilityProfile.MEDIUM,
		"macro_sensitivity": 1.0,
		"sector_sensitivity": 1.0,
		"markov_state": PriceEngine.MarkovState.SIDEWAYS,
		"state_duration": 0,
		"season_bias": PriceEngine.SeasonBias.NEUTRAL,
		"tick_prices": [] as Array[int],
		"tick_volumes": [] as Array[float],
		"ohlcv_daily": [] as Array[Dictionary],
		"event_queue": [] as Array,
		"gradual_events": [] as Array,
	}


func before_each() -> void:
	# Ensure test stock exists in both state dictionaries
	PriceEngine._stock_states[TEST_STOCK_ID] = _make_stock_state()
	PriceEngine._vi_states[TEST_STOCK_ID] = _make_vi_state()
	# Reset circuit breaker
	PriceEngine._cb_stage = 0
	PriceEngine._cb_halt_remaining = 0


# ── VI Constants ──

func test_vi_threshold_is_15pct() -> void:
	assert_eq(PriceEngine.VI_THRESHOLD, 0.15, "VI triggers at ±15%")


func test_vi_halt_duration_is_2_minutes() -> void:
	assert_eq(PriceEngine.VI_HALT_MINUTES, 2, "VI halts for 2 game-minutes")


func test_vi_max_per_day_is_1() -> void:
	assert_eq(PriceEngine.VI_MAX_PER_DAY, 1, "Max 1 VI per stock per day")


func test_vi_cooldown_is_5_minutes() -> void:
	assert_eq(PriceEngine.VI_COOLDOWN_MINUTES, 5, "VI cooldown is 5 game-minutes after release")


# ── CB Constants ──

func test_cb_stage1_threshold_is_minus_12pct() -> void:
	assert_eq(PriceEngine.CB_STAGE1_PCT, -0.12, "CB Stage 1 at -12%")


func test_cb_stage2_threshold_is_minus_20pct() -> void:
	assert_eq(PriceEngine.CB_STAGE2_PCT, -0.20, "CB Stage 2 at -20%")


func test_cb_stage1_halt_is_5_minutes() -> void:
	assert_eq(PriceEngine.CB_STAGE1_MINUTES, 5, "CB Stage 1 halts 5 game-minutes")


# ── VI: is_vi_halted query ──

func test_vi_halted_returns_false_when_no_halt() -> void:
	PriceEngine._vi_states[TEST_STOCK_ID] = _make_vi_state(0, 0)
	assert_false(PriceEngine.is_vi_halted(TEST_STOCK_ID), "No halt → not halted")


func test_vi_halted_returns_true_when_halt_remaining() -> void:
	PriceEngine._vi_states[TEST_STOCK_ID] = _make_vi_state(5, 1)
	assert_true(PriceEngine.is_vi_halted(TEST_STOCK_ID), "halt_remaining > 0 → halted")


func test_vi_halted_returns_false_for_unknown_stock() -> void:
	assert_false(PriceEngine.is_vi_halted("NONEXISTENT_STOCK"), "Unknown stock → not halted")


# ── VI: _check_vi trigger logic ──

func test_vi_triggers_at_threshold() -> void:
	var s: Dictionary = PriceEngine._stock_states[TEST_STOCK_ID]
	var prev_close: int = s["prev_day_close"]

	# Set price to exactly +15% above prev close
	s["current_price"] = roundi(float(prev_close) * 1.15)

	PriceEngine._check_vi(TEST_STOCK_ID)

	var vi: Dictionary = PriceEngine._vi_states[TEST_STOCK_ID]
	var expected_halt_ticks: int = PriceEngine.VI_HALT_MINUTES * GameClock.TICKS_PER_MINUTE
	assert_eq(vi["halt_remaining"], expected_halt_ticks, "VI should trigger at +15%")
	assert_eq(vi["count_today"], 1, "VI count should increment")


func test_vi_triggers_on_downside() -> void:
	var s: Dictionary = PriceEngine._stock_states[TEST_STOCK_ID]
	var prev_close: int = s["prev_day_close"]

	# Set price to exactly -15% below prev close
	s["current_price"] = roundi(float(prev_close) * 0.85)

	PriceEngine._check_vi(TEST_STOCK_ID)

	var vi: Dictionary = PriceEngine._vi_states[TEST_STOCK_ID]
	var expected_halt_ticks: int = PriceEngine.VI_HALT_MINUTES * GameClock.TICKS_PER_MINUTE
	assert_eq(vi["halt_remaining"], expected_halt_ticks, "VI should trigger at -15%")


func test_vi_does_not_trigger_below_threshold() -> void:
	var s: Dictionary = PriceEngine._stock_states[TEST_STOCK_ID]
	var prev_close: int = s["prev_day_close"]

	# Set price to +14% — below threshold
	s["current_price"] = roundi(float(prev_close) * 1.14)

	PriceEngine._check_vi(TEST_STOCK_ID)

	var vi: Dictionary = PriceEngine._vi_states[TEST_STOCK_ID]
	assert_eq(vi["halt_remaining"], 0, "VI should not trigger below 15%")


func test_vi_skips_when_already_halted() -> void:
	PriceEngine._vi_states[TEST_STOCK_ID] = _make_vi_state(3, 1)  # Already halted

	var s: Dictionary = PriceEngine._stock_states[TEST_STOCK_ID]
	var prev_close: int = s["prev_day_close"]
	s["current_price"] = roundi(float(prev_close) * 1.15)  # Would trigger

	PriceEngine._check_vi(TEST_STOCK_ID)

	var vi: Dictionary = PriceEngine._vi_states[TEST_STOCK_ID]
	assert_eq(vi["halt_remaining"], 3, "Should not re-trigger while halted")
	assert_eq(vi["count_today"], 1, "Count should not change")


func test_vi_respects_daily_limit() -> void:
	PriceEngine._vi_states[TEST_STOCK_ID] = _make_vi_state(0, 1)  # Already hit daily max (1)

	var s: Dictionary = PriceEngine._stock_states[TEST_STOCK_ID]
	var prev_close: int = s["prev_day_close"]
	s["current_price"] = roundi(float(prev_close) * 1.20)  # Would trigger

	PriceEngine._check_vi(TEST_STOCK_ID)

	var vi: Dictionary = PriceEngine._vi_states[TEST_STOCK_ID]
	assert_eq(vi["halt_remaining"], 0, "Should not trigger after daily max reached")


func test_vi_skips_zero_prev_close() -> void:
	var s: Dictionary = PriceEngine._stock_states[TEST_STOCK_ID]
	s["prev_day_close"] = 0  # Edge case: no previous close

	s["current_price"] = 10000

	PriceEngine._check_vi(TEST_STOCK_ID)

	var vi: Dictionary = PriceEngine._vi_states[TEST_STOCK_ID]
	assert_eq(vi["halt_remaining"], 0, "Should skip when prev_close is 0")


# ── CB: get_cb_stage query ──

func test_cb_stage_default_is_zero() -> void:
	assert_eq(PriceEngine.get_cb_stage(), 0, "Default CB stage is 0 (none)")


# ── CB: _check_circuit_breaker trigger logic ──

func test_cb_stage1_triggers_at_minus_12pct() -> void:
	# Set index to -12% from prev day
	PriceEngine._prev_day_index = 1000.0
	PriceEngine._current_index = 880.0  # -12%
	PriceEngine._cb_stage = 0

	PriceEngine._check_circuit_breaker()

	var expected_halt_ticks: int = PriceEngine.CB_STAGE1_MINUTES * GameClock.TICKS_PER_MINUTE
	assert_eq(PriceEngine._cb_stage, 1, "CB Stage 1 should trigger at -12%")
	assert_eq(PriceEngine._cb_halt_remaining, expected_halt_ticks,
		"Stage 1 halt should be %d ticks" % expected_halt_ticks)


func test_cb_does_not_trigger_above_threshold() -> void:
	PriceEngine._prev_day_index = 1000.0
	PriceEngine._current_index = 890.0  # -11%, above threshold
	PriceEngine._cb_stage = 0

	PriceEngine._check_circuit_breaker()

	assert_eq(PriceEngine._cb_stage, 0, "CB should not trigger above -12%")


func test_cb_stage1_does_not_retrigger() -> void:
	PriceEngine._prev_day_index = 1000.0
	PriceEngine._current_index = 850.0  # -15%
	PriceEngine._cb_stage = 1  # Already in Stage 1
	PriceEngine._cb_halt_remaining = 5

	PriceEngine._check_circuit_breaker()

	assert_eq(PriceEngine._cb_stage, 1, "Should not re-trigger Stage 1")
	assert_eq(PriceEngine._cb_halt_remaining, 5, "Halt ticks should not reset")


func test_cb_skips_when_prev_day_index_zero() -> void:
	PriceEngine._prev_day_index = 0.0
	PriceEngine._current_index = 500.0
	PriceEngine._cb_stage = 0

	PriceEngine._check_circuit_breaker()

	assert_eq(PriceEngine._cb_stage, 0, "Should skip when prev_day_index is 0")


# ── CB Stage 2 (early close) ──

func test_cb_stage2_triggers_at_minus_20pct() -> void:
	# Arrange
	watch_signals(PriceEngine)
	PriceEngine._prev_day_index = 1000.0
	PriceEngine._current_index = 800.0  # -20%
	PriceEngine._cb_stage = 0

	# Act
	PriceEngine._check_circuit_breaker()

	# Assert — _end_trading_day() resets _cb_stage to 0, so verify via signal instead
	assert_signal_emitted(PriceEngine, "on_circuit_breaker",
		"CB Stage 2 should emit on_circuit_breaker signal")


func test_cb_stage2_skips_if_already_stage2() -> void:
	# Arrange
	PriceEngine._prev_day_index = 1000.0
	PriceEngine._current_index = 750.0  # -25%
	PriceEngine._cb_stage = 2  # Already Stage 2

	# Act
	PriceEngine._check_circuit_breaker()

	# Assert — stage should not advance past 2 or re-run end_trading_day
	assert_eq(PriceEngine._cb_stage, 2, "Should not re-trigger Stage 2")


# ── Daily Reset ──

func test_vi_cooldown_blocks_retrigger() -> void:
	# Cooldown active, but count not exhausted (edge case: cooldown from previous logic)
	PriceEngine._vi_states[TEST_STOCK_ID] = _make_vi_state(0, 0, 10)

	var s: Dictionary = PriceEngine._stock_states[TEST_STOCK_ID]
	var prev_close: int = s["prev_day_close"]
	s["current_price"] = roundi(float(prev_close) * 1.20)  # Would trigger

	PriceEngine._check_vi(TEST_STOCK_ID)

	var vi: Dictionary = PriceEngine._vi_states[TEST_STOCK_ID]
	assert_eq(vi["halt_remaining"], 0, "Should not trigger during cooldown")


func test_vi_daily_count_concept() -> void:
	# Arrange — pre-set a stock with VI state that would max it out
	PriceEngine._vi_states[TEST_STOCK_ID] = _make_vi_state(0, 1, 0)  # count_today = 1 (daily max)
	var s: Dictionary = PriceEngine._stock_states[TEST_STOCK_ID]
	s["prev_day_close"] = 50000
	s["current_price"] = roundi(50000.0 * 1.20)  # +20%, would trigger VI

	# Confirm VI is blocked by daily count before reset
	PriceEngine._check_vi(TEST_STOCK_ID)
	var vi_before: Dictionary = PriceEngine._vi_states[TEST_STOCK_ID]
	assert_eq(vi_before["halt_remaining"], 0, "Precondition: VI blocked by daily count")

	# Act — call end-of-day to reset daily counters
	PriceEngine._end_trading_day()

	# Assert — count resets, VI can now trigger again
	var vi_after: Dictionary = PriceEngine._vi_states[TEST_STOCK_ID]
	assert_eq(vi_after["count_today"], 0, "Daily count should reset after _end_trading_day()")
	assert_eq(vi_after["halt_remaining"], 0, "Halt should clear on day end")
	assert_eq(vi_after["cooldown"], 0, "Cooldown should clear on day end")


func test_cb_resets_after_day_end() -> void:
	# Arrange — put CB in Stage 1
	PriceEngine._cb_stage = 1
	PriceEngine._cb_halt_remaining = 10

	# Act — call the production end-of-day handler
	PriceEngine._end_trading_day()

	# Assert — CB state clears for the next day
	assert_eq(PriceEngine.get_cb_stage(), 0, "CB stage should reset after _end_trading_day()")
	assert_eq(PriceEngine._cb_halt_remaining, 0, "CB halt should clear after _end_trading_day()")


# ── VI halt countdown during tick ──

func test_vi_halt_decrements_each_tick() -> void:
	# Arrange — stock halted for 3 ticks, engine in RUNNING state
	PriceEngine._vi_states[TEST_STOCK_ID] = _make_vi_state(3, 1)
	var original_engine_state: PriceEngine.EngineState = PriceEngine._engine_state
	PriceEngine._engine_state = PriceEngine.EngineState.RUNNING
	PriceEngine._cb_halt_remaining = 0

	# Act — call _on_tick once (tick_number > 0 to skip VI check on tick 0)
	PriceEngine.process_tick(1, 1, 1)

	# Assert — halt_remaining decremented by 1
	var vi: Dictionary = PriceEngine._vi_states[TEST_STOCK_ID]
	assert_eq(vi["halt_remaining"], 2, "Halt should decrement by 1 per tick")

	# Cleanup
	PriceEngine._engine_state = original_engine_state


func test_cb_halt_decrements_each_tick() -> void:
	# Arrange — CB halt active, engine in RUNNING state
	PriceEngine._cb_halt_remaining = 5
	var original_engine_state: PriceEngine.EngineState = PriceEngine._engine_state
	PriceEngine._engine_state = PriceEngine.EngineState.RUNNING

	# Act — call _on_tick once
	PriceEngine.process_tick(1, 1, 1)

	# Assert — CB halt_remaining decremented by 1
	assert_eq(PriceEngine._cb_halt_remaining, 4, "CB halt should decrement by 1 per tick")

	# Cleanup
	PriceEngine._engine_state = original_engine_state


# ── VI max per day blocks additional triggers ──

func test_vi_max_per_day_blocks_third_trigger() -> void:
	# Arrange — inject VI state showing 2 triggers already used (VI_MAX_PER_DAY = 1,
	# so count_today = 1 is already at the limit; use count_today = 1 to test the guard)
	PriceEngine._vi_states[TEST_STOCK_ID] = _make_vi_state(0, PriceEngine.VI_MAX_PER_DAY)
	var s: Dictionary = PriceEngine._stock_states[TEST_STOCK_ID]
	s["prev_day_close"] = 50000
	s["current_price"] = roundi(50000.0 * 1.20)  # +20%, would exceed VI_THRESHOLD

	# Act
	PriceEngine._check_vi(TEST_STOCK_ID)

	# Assert — no additional trigger past the daily max
	assert_eq(PriceEngine._vi_states[TEST_STOCK_ID]["count_today"], PriceEngine.VI_MAX_PER_DAY,
		"Should not increment past VI_MAX_PER_DAY")
	assert_eq(PriceEngine._vi_states[TEST_STOCK_ID]["halt_remaining"], 0,
		"Should not trigger halt after reaching daily max")
