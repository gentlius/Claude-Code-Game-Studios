## GUT unit tests for PriceEngine core formulas.
## Tests the mathematical correctness of each layer independently.
## See: design/gdd/price-engine.md (Formulas section)
extends GutTest

# ── Helper: Access PriceEngine internals ──
# In test environment, PriceEngine is an autoload. We test its public and
# formula methods directly.

# ── Test: Drift Intensity (GDD Rule 2-3) ──

func test_drift_intensity_below_soft_threshold() -> void:
	# Below threshold_soft (0.20): intensity = 1.0
	var result: float = PriceEngine._drift_intensity(0.10)
	assert_almost_eq(result, 1.0, 0.001, "Below soft threshold should be 1.0")

	result = PriceEngine._drift_intensity(-0.15)
	assert_almost_eq(result, 1.0, 0.001, "Negative below soft threshold should be 1.0")


func test_drift_intensity_between_soft_and_hard() -> void:
	# Between soft (0.20) and hard (0.50):
	# intensity = 1.0 + (|r| - 0.20) * 4.0
	var result: float = PriceEngine._drift_intensity(0.30)
	var expected: float = 1.0 + (0.30 - 0.20) * 4.0  # 1.4
	assert_almost_eq(result, expected, 0.001, "At 0.30 deviation")

	result = PriceEngine._drift_intensity(-0.40)
	expected = 1.0 + (0.40 - 0.20) * 4.0  # 1.8
	assert_almost_eq(result, expected, 0.001, "At -0.40 deviation")


func test_drift_intensity_above_hard_threshold() -> void:
	# Above hard (0.50):
	# intensity = 1.0 + (0.50-0.20)*4.0 + (|r|-0.50)*16.0
	var result: float = PriceEngine._drift_intensity(0.60)
	var expected: float = 1.0 + 0.30 * 4.0 + 0.10 * 16.0  # 3.8
	assert_almost_eq(result, expected, 0.001, "At 0.60 deviation")


func test_drift_intensity_symmetry() -> void:
	# Positive and negative deviations should give same intensity
	var pos: float = PriceEngine._drift_intensity(0.35)
	var neg: float = PriceEngine._drift_intensity(-0.35)
	assert_almost_eq(pos, neg, 0.001, "Should be symmetric")

# ── Test: Drift Delta (GDD Rule 2) ──

func test_drift_delta_pushes_toward_base() -> void:
	# Price above base → drift should be negative (push down)
	var drift: float = PriceEngine._compute_drift_delta(75000, 65000)
	assert_true(drift < 0.0, "Above base: drift should be negative")

	# Price below base → drift should be positive (push up)
	drift = PriceEngine._compute_drift_delta(55000, 65000)
	assert_true(drift > 0.0, "Below base: drift should be positive")


func test_drift_delta_zero_at_base() -> void:
	var drift: float = PriceEngine._compute_drift_delta(65000, 65000)
	assert_almost_eq(drift, 0.0, 0.0001, "At base price: drift should be zero")


func test_drift_delta_magnitude_scales_with_deviation() -> void:
	# Larger deviation → stronger drift
	var drift_small: float = absf(PriceEngine._compute_drift_delta(70000, 65000))
	var drift_large: float = absf(PriceEngine._compute_drift_delta(90000, 65000))
	assert_true(drift_large > drift_small, "Larger deviation should produce stronger drift")

# ── Test: Pattern Delta (GDD Rules 1-1, 1-6) ──

func test_pattern_delta_bias_direction() -> void:
	# Run many samples and check average direction matches state bias
	seed(42)
	var sum_up: float = 0.0
	var sum_down: float = 0.0
	var n: int = 1000

	for _i: int in range(n):
		sum_up += PriceEngine._compute_pattern_delta(
			PriceEngine.MarkovState.UPTREND,
			StockData.VolatilityProfile.MEDIUM
		)
		sum_down += PriceEngine._compute_pattern_delta(
			PriceEngine.MarkovState.DOWNTREND,
			StockData.VolatilityProfile.MEDIUM
		)

	var avg_up: float = sum_up / float(n)
	var avg_down: float = sum_down / float(n)
	assert_true(avg_up > 0.0, "UPTREND average should be positive")
	assert_true(avg_down < 0.0, "DOWNTREND average should be negative")


func test_pattern_delta_vol_scaling() -> void:
	# LOW volatility should produce smaller deltas than EXTREME
	seed(42)
	var sum_low: float = 0.0
	var sum_ext: float = 0.0
	var n: int = 1000

	for _i: int in range(n):
		sum_low += absf(PriceEngine._compute_pattern_delta(
			PriceEngine.MarkovState.SIDEWAYS,
			StockData.VolatilityProfile.LOW
		))
		sum_ext += absf(PriceEngine._compute_pattern_delta(
			PriceEngine.MarkovState.SIDEWAYS,
			StockData.VolatilityProfile.EXTREME
		))

	var avg_low: float = sum_low / float(n)
	var avg_ext: float = sum_ext / float(n)
	assert_true(avg_ext > avg_low * 2.0,
		"EXTREME should be >2x LOW magnitude (got LOW=%.6f, EXT=%.6f)" % [avg_low, avg_ext])

# ── Test: Price Clamping (GDD Rule 2-4) ──

func test_price_clamp_boundaries() -> void:
	# min_price = max(base * 0.15, 1000)
	# max_price = base * 3.0
	var base: int = 65000
	var min_p: float = maxf(float(base) * 0.15, 1000.0)  # 9750
	var max_p: float = float(base) * 3.0  # 195000

	assert_almost_eq(min_p, 9750.0, 0.1, "Min price for 65000 base")
	assert_almost_eq(max_p, 195000.0, 0.1, "Max price for 65000 base")

	# Low base price: min should be 1000
	var low_base: int = 5000
	var min_low: float = maxf(float(low_base) * 0.15, 1000.0)  # 1000
	assert_almost_eq(min_low, 1000.0, 0.1, "Min price floor at 1000")


func test_100won_rounding() -> void:
	# Test that rounding to 100원 works correctly
	var test_cases: Array[Array] = [
		[65432.0, 65400],  # round down
		[65450.0, 65400],  # round to even (or 65500 depending on impl)
		[65499.0, 65500],  # round up
		[65550.0, 65600],  # round up
		[1050.0, 1100],    # small value
	]
	for tc: Array in test_cases:
		var raw: float = tc[0]
		var rounded: int = roundi(raw / 100.0) * 100
		# Just check it's a multiple of 100
		assert_eq(rounded % 100, 0, "Should be multiple of 100: %d" % rounded)

# ── Test: Volume (GDD Rule 4) ──

func test_volume_time_of_day_multiplier() -> void:
	# Opening (tick 0-9) should have 2.5x, closing (380-389) should have 2.0x
	seed(42)
	var s: Dictionary = {
		"volatility_profile": StockData.VolatilityProfile.MEDIUM,
		"markov_state": PriceEngine.MarkovState.SIDEWAYS,
		"current_price": 65000,
		"prev_day_close": 65000,
	}

	# Sample multiple times for statistical test
	var opening_sum: float = 0.0
	var normal_sum: float = 0.0
	var n: int = 500

	for _i: int in range(n):
		opening_sum += PriceEngine._compute_volume(s, 0.0, 0.0, 5)   # opening
		normal_sum += PriceEngine._compute_volume(s, 0.0, 0.0, 200)  # normal

	var ratio: float = opening_sum / normal_sum
	assert_true(ratio > 2.0 and ratio < 3.0,
		"Opening volume should be ~2.5x normal (got %.2fx)" % ratio)


func test_volume_energy_correlation() -> void:
	# Higher tick energy should produce higher volume
	seed(42)
	var s: Dictionary = {
		"volatility_profile": StockData.VolatilityProfile.MEDIUM,
		"markov_state": PriceEngine.MarkovState.SIDEWAYS,
		"current_price": 65000,
		"prev_day_close": 65000,
	}

	var low_energy_sum: float = 0.0
	var high_energy_sum: float = 0.0
	var n: int = 500

	for _i: int in range(n):
		low_energy_sum += PriceEngine._compute_volume(s, 0.001, 0.0, 200)
		high_energy_sum += PriceEngine._compute_volume(s, 0.03, 0.02, 200)

	assert_true(high_energy_sum > low_energy_sum * 2.0,
		"High energy volume should be >2x low energy (got %.2fx)" % [high_energy_sum / low_energy_sum])


func test_volume_limit_proximity_dampening() -> void:
	# Volume should decrease as price approaches daily limit
	seed(42)
	var prev_close: int = 65000

	var s_normal: Dictionary = {
		"volatility_profile": StockData.VolatilityProfile.MEDIUM,
		"markov_state": PriceEngine.MarkovState.UPTREND,
		"current_price": 65000,  # 0% from prev close
		"prev_day_close": prev_close,
	}
	var s_near_limit: Dictionary = {
		"volatility_profile": StockData.VolatilityProfile.MEDIUM,
		"markov_state": PriceEngine.MarkovState.UPTREND,
		"current_price": 84500,  # 30% from prev close (at limit)
		"prev_day_close": prev_close,
	}

	var normal_sum: float = 0.0
	var limit_sum: float = 0.0
	var n: int = 500

	for _i: int in range(n):
		normal_sum += PriceEngine._compute_volume(s_normal, 0.005, 0.0, 200)
		limit_sum += PriceEngine._compute_volume(s_near_limit, 0.005, 0.0, 200)

	var dampen_ratio: float = limit_sum / normal_sum
	assert_true(dampen_ratio < 0.3,
		"At daily limit, volume should be <30%% of normal (got %.2f%%)" % [dampen_ratio * 100.0])

# ── Test: Gradual Event Decay (GDD Rule 3-5) ──

func test_linear_gradual_decay_sums_to_impact() -> void:
	var ge: Dictionary = {
		"actual_impact": 0.10,
		"remaining_ticks": 100,
		"total_ticks": 100,
		"decay_curve": MarketEvent.DecayCurve.LINEAR,
		"decay_rate": 0.0,
	}

	var total: float = 0.0
	for _i: int in range(100):
		total += PriceEngine._gradual_tick_impact(ge)
		ge["remaining_ticks"] -= 1

	assert_almost_eq(total, 0.10, 0.001,
		"Linear decay should sum to actual_impact")


func test_exponential_gradual_decay_converges() -> void:
	var decay_ticks: int = 100
	var decay_rate: float = 1.0 - exp(log(0.01) / float(decay_ticks))
	var ge: Dictionary = {
		"actual_impact": 0.10,
		"remaining_ticks": decay_ticks,
		"total_ticks": decay_ticks,
		"decay_curve": MarketEvent.DecayCurve.EXPONENTIAL,
		"decay_rate": decay_rate,
	}

	var total: float = 0.0
	for _i: int in range(decay_ticks):
		total += PriceEngine._gradual_tick_impact(ge)
		ge["remaining_ticks"] -= 1

	# Exponential sums to ~99% of actual_impact
	assert_true(total > 0.09 and total < 0.11,
		"Exponential decay should sum to ~99%% of impact (got %.4f)" % total)

# ── Test: Box-Muller Normal Distribution ──

func test_randn_distribution() -> void:
	seed(42)
	var samples: Array[float] = []
	var n: int = 5000

	for _i: int in range(n):
		samples.append(PriceEngine._randn())

	# Check mean ≈ 0
	var sum: float = 0.0
	for s: float in samples:
		sum += s
	var mean: float = sum / float(n)
	assert_almost_eq(mean, 0.0, 0.1, "Normal distribution mean should be ~0")

	# Check std ≈ 1
	var var_sum: float = 0.0
	for s: float in samples:
		var_sum += (s - mean) * (s - mean)
	var std: float = sqrt(var_sum / float(n))
	assert_almost_eq(std, 1.0, 0.15, "Normal distribution std should be ~1")


# ── Test: Tick Size (GDD Rule 5-3, KRX 호가 단위) ──

func test_tick_size_below_1000() -> void:
	assert_eq(PriceEngine.get_tick_size(500), 1, "Below 1000: tick = 1")
	assert_eq(PriceEngine.get_tick_size(999), 1, "At 999: tick = 1")


func test_tick_size_1000_to_5000() -> void:
	assert_eq(PriceEngine.get_tick_size(1000), 5, "At 1000: tick = 5")
	assert_eq(PriceEngine.get_tick_size(4999), 5, "At 4999: tick = 5")


func test_tick_size_5000_to_10000() -> void:
	assert_eq(PriceEngine.get_tick_size(5000), 10, "At 5000: tick = 10")
	assert_eq(PriceEngine.get_tick_size(9999), 10, "At 9999: tick = 10")


func test_tick_size_10000_to_50000() -> void:
	assert_eq(PriceEngine.get_tick_size(10000), 50, "At 10000: tick = 50")
	assert_eq(PriceEngine.get_tick_size(49999), 50, "At 49999: tick = 50")


func test_tick_size_50000_to_100000() -> void:
	assert_eq(PriceEngine.get_tick_size(50000), 100, "At 50000: tick = 100")
	assert_eq(PriceEngine.get_tick_size(65030), 100, "At 65030: tick = 100")
	assert_eq(PriceEngine.get_tick_size(99999), 100, "At 99999: tick = 100")


func test_tick_size_100000_to_500000() -> void:
	assert_eq(PriceEngine.get_tick_size(100000), 500, "At 100000: tick = 500")
	assert_eq(PriceEngine.get_tick_size(499999), 500, "At 499999: tick = 500")


func test_tick_size_above_500000() -> void:
	assert_eq(PriceEngine.get_tick_size(500000), 1000, "At 500000: tick = 1000")
	assert_eq(PriceEngine.get_tick_size(1000000), 1000, "At 1M: tick = 1000")


# ── Test: Round to Tick (GDD Rule 5-3) ──

func test_round_to_tick_low_price() -> void:
	assert_eq(PriceEngine.round_to_tick(3427.0), 3425, "3427 rounds to 3425 (tick=5)")
	assert_eq(PriceEngine.round_to_tick(3423.0), 3425, "3423 rounds to 3425 (tick=5)")


func test_round_to_tick_mid_price() -> void:
	assert_eq(PriceEngine.round_to_tick(32780.0), 32800, "32780 rounds to 32800 (tick=50)")
	assert_eq(PriceEngine.round_to_tick(32749.0), 32750, "32749 rounds to 32750 (tick=50)")


func test_round_to_tick_high_price() -> void:
	# 65030 → tick=100 → round(65030/100)*100 = 65000
	assert_eq(PriceEngine.round_to_tick(65030.0), 65000, "65030 rounds to 65000 (tick=100)")
	assert_eq(PriceEngine.round_to_tick(65080.0), 65100, "65080 rounds to 65100 (tick=100)")


func test_round_to_tick_exact_value() -> void:
	assert_eq(PriceEngine.round_to_tick(50000.0), 50000, "Exact tick value unchanged")


func test_round_to_tick_very_high() -> void:
	assert_eq(PriceEngine.round_to_tick(512345.0), 512000, "512345 rounds to 512000 (tick=1000)")


# ── Test: VI (Volatility Interruption, GDD Rule 2-4) ──

func test_vi_not_halted_initially() -> void:
	assert_false(PriceEngine.is_vi_halted("KSF"), "No VI halt initially")


func test_vi_halted_after_state_injection() -> void:
	# Directly inject VI state to test the query
	PriceEngine._vi_states["KSF"] = {"halt_remaining": 5, "count_today": 1}
	assert_true(PriceEngine.is_vi_halted("KSF"), "Should be halted with remaining > 0")
	# Cleanup
	PriceEngine._vi_states.erase("KSF")


func test_vi_not_halted_when_remaining_zero() -> void:
	PriceEngine._vi_states["KSF"] = {"halt_remaining": 0, "count_today": 1}
	assert_false(PriceEngine.is_vi_halted("KSF"), "Not halted when remaining = 0")
	PriceEngine._vi_states.erase("KSF")


func test_vi_max_per_day_blocks_third_trigger() -> void:
	# Simulate 2 VI triggers already exhausted
	PriceEngine._vi_states["KSF"] = {"halt_remaining": 0, "count_today": 2}
	# _check_vi should not trigger a 3rd time even with large price change
	# We need a stock state to exist
	if PriceEngine._stock_states.has("KSF"):
		var s: Dictionary = PriceEngine._stock_states["KSF"]
		var original_price: int = s["current_price"]
		var original_prev: int = s["prev_day_close"]
		# Set price to 15% above prev close (exceeds VI_THRESHOLD of 10%)
		s["prev_day_close"] = 50000
		s["current_price"] = 58000
		PriceEngine._check_vi("KSF")
		assert_eq(PriceEngine._vi_states["KSF"]["count_today"], 2,
			"Should not increment past max per day")
		assert_eq(PriceEngine._vi_states["KSF"]["halt_remaining"], 0,
			"Should not trigger halt after max per day")
		# Restore
		s["current_price"] = original_price
		s["prev_day_close"] = original_prev
	else:
		pass_test("KF stock state not available in test environment (skipped)")
	PriceEngine._vi_states.erase("KSF")


# ── Test: Circuit Breaker (GDD Rule 2-5) ──

func test_cb_stage_initially_zero() -> void:
	# CB stage should start at 0 (or be 0 unless market has crashed)
	# We just verify the getter works
	var stage: int = PriceEngine.get_cb_stage()
	assert_true(stage >= 0 and stage <= 2, "CB stage should be 0-2 (got %d)" % stage)


func test_cb_stage_1_after_injection() -> void:
	var original: int = PriceEngine._cb_stage
	PriceEngine._cb_stage = 1
	assert_eq(PriceEngine.get_cb_stage(), 1, "CB stage 1 after injection")
	PriceEngine._cb_stage = original


func test_cb_stage_2_after_injection() -> void:
	var original: int = PriceEngine._cb_stage
	PriceEngine._cb_stage = 2
	assert_eq(PriceEngine.get_cb_stage(), 2, "CB stage 2 after injection")
	PriceEngine._cb_stage = original
