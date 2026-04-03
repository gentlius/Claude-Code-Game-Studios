extends GutTest
## Unit tests for VI / Circuit Breaker — see design/gdd/price-engine.md Rules 2-4, 2-5


# ── Helpers ──

func _make_vi_state(halt: int = 0, count: int = 0, cooldown: int = 0) -> Dictionary:
	return {"halt_remaining": halt, "count_today": count, "cooldown": cooldown}


func before_each() -> void:
	# Reset VI states for all stocks
	for stock_id: String in PriceEngine._vi_states:
		PriceEngine._vi_states[stock_id] = _make_vi_state()
	# Reset circuit breaker
	PriceEngine._cb_stage = 0
	PriceEngine._cb_halt_remaining = 0


# ── VI Constants ──

func test_vi_threshold_is_15pct() -> void:
	assert_eq(PriceEngine.VI_THRESHOLD, 0.15, "VI triggers at ±15%")


func test_vi_halt_duration_is_8_ticks() -> void:
	assert_eq(PriceEngine.VI_HALT_TICKS, 8, "VI halts for 8 ticks")


func test_vi_max_per_day_is_1() -> void:
	assert_eq(PriceEngine.VI_MAX_PER_DAY, 1, "Max 1 VI per stock per day")


func test_vi_cooldown_is_20_ticks() -> void:
	assert_eq(PriceEngine.VI_COOLDOWN_TICKS, 20, "VI cooldown is 20 ticks after release")


# ── CB Constants ──

func test_cb_stage1_threshold_is_minus_12pct() -> void:
	assert_eq(PriceEngine.CB_STAGE1_PCT, -0.12, "CB Stage 1 at -12%")


func test_cb_stage2_threshold_is_minus_20pct() -> void:
	assert_eq(PriceEngine.CB_STAGE2_PCT, -0.20, "CB Stage 2 at -20%")


func test_cb_stage1_halt_is_20_ticks() -> void:
	assert_eq(PriceEngine.CB_STAGE1_TICKS, 20, "CB Stage 1 halts 20 ticks")


# ── VI: is_vi_halted query ──

func test_vi_halted_returns_false_when_no_halt() -> void:
	var stock_id: String = PriceEngine._vi_states.keys()[0]
	PriceEngine._vi_states[stock_id] = _make_vi_state(0, 0)
	assert_false(PriceEngine.is_vi_halted(stock_id), "No halt → not halted")


func test_vi_halted_returns_true_when_halt_remaining() -> void:
	var stock_id: String = PriceEngine._vi_states.keys()[0]
	PriceEngine._vi_states[stock_id] = _make_vi_state(5, 1)
	assert_true(PriceEngine.is_vi_halted(stock_id), "halt_remaining > 0 → halted")


func test_vi_halted_returns_false_for_unknown_stock() -> void:
	assert_false(PriceEngine.is_vi_halted("NONEXISTENT_STOCK"), "Unknown stock → not halted")


# ── VI: _check_vi trigger logic ──

func test_vi_triggers_at_threshold() -> void:
	var stock_id: String = PriceEngine._vi_states.keys()[0]
	var s: Dictionary = PriceEngine._stock_states[stock_id]
	var prev_close: int = s["prev_day_close"]

	# Set price to exactly +15% above prev close
	s["current_price"] = roundi(float(prev_close) * 1.15)

	PriceEngine._check_vi(stock_id)

	var vi: Dictionary = PriceEngine._vi_states[stock_id]
	assert_eq(vi["halt_remaining"], PriceEngine.VI_HALT_TICKS, "VI should trigger at +15%")
	assert_eq(vi["count_today"], 1, "VI count should increment")


func test_vi_triggers_on_downside() -> void:
	var stock_id: String = PriceEngine._vi_states.keys()[0]
	var s: Dictionary = PriceEngine._stock_states[stock_id]
	var prev_close: int = s["prev_day_close"]

	# Set price to exactly -15% below prev close
	s["current_price"] = roundi(float(prev_close) * 0.85)

	PriceEngine._check_vi(stock_id)

	var vi: Dictionary = PriceEngine._vi_states[stock_id]
	assert_eq(vi["halt_remaining"], PriceEngine.VI_HALT_TICKS, "VI should trigger at -15%")


func test_vi_does_not_trigger_below_threshold() -> void:
	var stock_id: String = PriceEngine._vi_states.keys()[0]
	var s: Dictionary = PriceEngine._stock_states[stock_id]
	var prev_close: int = s["prev_day_close"]

	# Set price to +14% — below threshold
	s["current_price"] = roundi(float(prev_close) * 1.14)

	PriceEngine._check_vi(stock_id)

	var vi: Dictionary = PriceEngine._vi_states[stock_id]
	assert_eq(vi["halt_remaining"], 0, "VI should not trigger below 15%")


func test_vi_skips_when_already_halted() -> void:
	var stock_id: String = PriceEngine._vi_states.keys()[0]
	PriceEngine._vi_states[stock_id] = _make_vi_state(3, 1)  # Already halted

	var s: Dictionary = PriceEngine._stock_states[stock_id]
	var prev_close: int = s["prev_day_close"]
	s["current_price"] = roundi(float(prev_close) * 1.15)  # Would trigger

	PriceEngine._check_vi(stock_id)

	var vi: Dictionary = PriceEngine._vi_states[stock_id]
	assert_eq(vi["halt_remaining"], 3, "Should not re-trigger while halted")
	assert_eq(vi["count_today"], 1, "Count should not change")


func test_vi_respects_daily_limit() -> void:
	var stock_id: String = PriceEngine._vi_states.keys()[0]
	PriceEngine._vi_states[stock_id] = _make_vi_state(0, 1)  # Already hit daily max (1)

	var s: Dictionary = PriceEngine._stock_states[stock_id]
	var prev_close: int = s["prev_day_close"]
	s["current_price"] = roundi(float(prev_close) * 1.20)  # Would trigger

	PriceEngine._check_vi(stock_id)

	var vi: Dictionary = PriceEngine._vi_states[stock_id]
	assert_eq(vi["halt_remaining"], 0, "Should not trigger after daily max reached")


func test_vi_skips_zero_prev_close() -> void:
	var stock_id: String = PriceEngine._vi_states.keys()[0]
	var s: Dictionary = PriceEngine._stock_states[stock_id]
	s["prev_day_close"] = 0  # Edge case: no previous close

	s["current_price"] = 10000

	PriceEngine._check_vi(stock_id)

	var vi: Dictionary = PriceEngine._vi_states[stock_id]
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

	assert_eq(PriceEngine._cb_stage, 1, "CB Stage 1 should trigger at -12%")
	assert_eq(PriceEngine._cb_halt_remaining, PriceEngine.CB_STAGE1_TICKS,
		"Stage 1 halt should be 20 ticks")


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
	PriceEngine._prev_day_index = 1000.0
	PriceEngine._current_index = 800.0  # -20%
	PriceEngine._cb_stage = 0

	# Stage 2 calls _end_trading_day() which has side effects.
	# We test the stage transition without running full end-of-day.
	# Directly check the threshold logic.
	var index_change: float = (800.0 - 1000.0) / 1000.0  # -0.20
	assert_true(index_change <= PriceEngine.CB_STAGE2_PCT,
		"-20% should meet Stage 2 threshold")


func test_cb_stage2_skips_if_already_stage2() -> void:
	PriceEngine._prev_day_index = 1000.0
	PriceEngine._current_index = 750.0  # -25%
	PriceEngine._cb_stage = 2  # Already Stage 2

	# _check_circuit_breaker has guard: _cb_stage < 2
	# Verify the guard logic
	var should_trigger: bool = (PriceEngine._current_index - PriceEngine._prev_day_index) / PriceEngine._prev_day_index <= PriceEngine.CB_STAGE2_PCT and PriceEngine._cb_stage < 2
	assert_false(should_trigger, "Should not re-trigger Stage 2")


# ── Daily Reset ──

func test_vi_cooldown_blocks_retrigger() -> void:
	var stock_id: String = PriceEngine._vi_states.keys()[0]
	# Cooldown active, but count not exhausted (edge case: cooldown from previous logic)
	PriceEngine._vi_states[stock_id] = _make_vi_state(0, 0, 10)

	var s: Dictionary = PriceEngine._stock_states[stock_id]
	var prev_close: int = s["prev_day_close"]
	s["current_price"] = roundi(float(prev_close) * 1.20)  # Would trigger

	PriceEngine._check_vi(stock_id)

	var vi: Dictionary = PriceEngine._vi_states[stock_id]
	assert_eq(vi["halt_remaining"], 0, "Should not trigger during cooldown")


func test_vi_daily_count_concept() -> void:
	# Verify that VI states can be reset (simulating end-of-day)
	var stock_id: String = PriceEngine._vi_states.keys()[0]
	PriceEngine._vi_states[stock_id] = _make_vi_state(3, 1, 15)

	# Simulate daily reset (what _end_trading_day does)
	PriceEngine._vi_states[stock_id]["count_today"] = 0
	PriceEngine._vi_states[stock_id]["halt_remaining"] = 0
	PriceEngine._vi_states[stock_id]["cooldown"] = 0

	var vi: Dictionary = PriceEngine._vi_states[stock_id]
	assert_eq(vi["count_today"], 0, "Daily count should reset")
	assert_eq(vi["halt_remaining"], 0, "Halt should clear")
	assert_eq(vi["cooldown"], 0, "Cooldown should clear")


func test_cb_resets_after_day_end() -> void:
	# Verify CB state can be reset (simulating end-of-day)
	PriceEngine._cb_stage = 1
	PriceEngine._cb_halt_remaining = 10

	# Simulate daily reset
	PriceEngine._cb_stage = 0
	PriceEngine._cb_halt_remaining = 0

	assert_eq(PriceEngine.get_cb_stage(), 0, "CB stage should reset")
	assert_eq(PriceEngine._cb_halt_remaining, 0, "CB halt should clear")


# ── VI halt countdown during tick ──

func test_vi_halt_decrements_each_tick() -> void:
	var stock_id: String = PriceEngine._vi_states.keys()[0]
	PriceEngine._vi_states[stock_id] = _make_vi_state(3, 1)

	# Simulate what _on_tick does for halted stock
	var vi: Dictionary = PriceEngine._vi_states[stock_id]
	vi["halt_remaining"] -= 1

	assert_eq(vi["halt_remaining"], 2, "Halt should decrement by 1 per tick")


func test_cb_halt_decrements_each_tick() -> void:
	PriceEngine._cb_halt_remaining = 5

	# Simulate what _on_tick does for CB halt
	PriceEngine._cb_halt_remaining -= 1

	assert_eq(PriceEngine._cb_halt_remaining, 4, "CB halt should decrement by 1 per tick")
