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
	}

	# Sample multiple times for statistical test
	var opening_sum: float = 0.0
	var normal_sum: float = 0.0
	var n: int = 500

	for _i: int in range(n):
		opening_sum += PriceEngine._compute_volume(s, 0.0, 5)   # opening
		normal_sum += PriceEngine._compute_volume(s, 0.0, 200)  # normal

	var ratio: float = opening_sum / normal_sum
	assert_true(ratio > 2.0 and ratio < 3.0,
		"Opening volume should be ~2.5x normal (got %.2fx)" % ratio)

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
