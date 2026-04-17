## Tests for OhlcvHistory — cross-season daily OHLCV accumulation.
## Implements: design/gdd/price-engine.md §OHLCV (S9-07)
extends GutTest

const DAYS_PER_SEASON: int = 20  ## GameClock.DAYS_PER_WEEK * GameClock.WEEKS_PER_SEASON
const DAYS_PER_WEEK: int = 5


func before_each() -> void:
	OhlcvHistory.reset()


# ── reset() ──────────────────────────────────────────────────────────

func test_reset_clears_past_daily() -> void:
	# Arrange: inject synthetic past bars
	var fake_bars: Array[Dictionary] = [{"open": 10000, "high": 11000, "low": 9500, "close": 10500, "volume": 500000.0}]
	OhlcvHistory._past_daily["AAPL"] = fake_bars
	# Act
	OhlcvHistory.reset()
	# Assert
	assert_eq(OhlcvHistory.get_past_bar_count("AAPL"), 0, "reset 후 past_daily 비워짐")


func test_reset_generates_nonzero_seed() -> void:
	OhlcvHistory.reset()
	assert_ne(OhlcvHistory.history_seed, 0, "reset 후 history_seed != 0")


# ── _on_season_ended (append path) ────────────────────────────────────

func test_past_bar_count_zero_before_any_season() -> void:
	var count: int = OhlcvHistory.get_past_bar_count("SAMSUNG")
	assert_eq(count, 0, "초기 상태: 누적 없음")


# ── get_all_daily_bars ────────────────────────────────────────────────

func test_get_all_daily_bars_includes_pre_history_when_seed_set() -> void:
	OhlcvHistory.reset()
	# Ensure seed is set (reset() generates one)
	assert_ne(OhlcvHistory.history_seed, 0)
	# Ask for any stock — pre-history should generate bars
	var bars: Array[Dictionary] = OhlcvHistory.get_all_daily_bars("SAMSUNG")
	var expected_pre: int = OhlcvHistory.N_PRE_SEASONS * OhlcvHistory.DAYS_PER_SEASON
	# ≥ expected pre-history bars (current season from PriceEngine may add more)
	assert_true(bars.size() >= expected_pre,
		"pre-history bars >= N_PRE_SEASONS × DAYS_PER_SEASON (%d)" % expected_pre)


func test_pre_history_bars_have_valid_ohlcv_structure() -> void:
	OhlcvHistory.reset()
	var bars: Array[Dictionary] = OhlcvHistory.get_all_daily_bars("SAMSUNG")
	assert_true(bars.size() > 0, "bars 비어 있지 않음")
	var first: Dictionary = bars[0]
	assert_true(first.has("open"),   "open 필드 존재")
	assert_true(first.has("high"),   "high 필드 존재")
	assert_true(first.has("low"),    "low 필드 존재")
	assert_true(first.has("close"),  "close 필드 존재")
	assert_true(first.has("volume"), "volume 필드 존재")
	assert_true(first["high"] >= first["low"], "high >= low 유지")
	assert_true(first["close"] > 0, "close > 0")


func test_pre_history_is_deterministic() -> void:
	OhlcvHistory.reset()
	var seed: int = OhlcvHistory.history_seed
	var bars1: Array[Dictionary] = OhlcvHistory.get_all_daily_bars("SAMSUNG")
	# Re-set same seed and regenerate
	OhlcvHistory.history_seed = seed
	OhlcvHistory._past_daily.clear()
	var bars2: Array[Dictionary] = OhlcvHistory.get_all_daily_bars("SAMSUNG")
	assert_eq(bars1.size(), bars2.size(), "같은 seed → 같은 bar 수")
	if bars1.size() > 0:
		assert_eq(bars1[0]["close"], bars2[0]["close"], "같은 seed → 첫 bar close 동일")


func test_different_stocks_get_different_pre_history() -> void:
	OhlcvHistory.reset()
	var bars_a: Array[Dictionary] = OhlcvHistory.get_all_daily_bars("SAMSUNG")
	var bars_b: Array[Dictionary] = OhlcvHistory.get_all_daily_bars("SK_HYNIX")
	# First bars should differ (different stock hash → different RNG sequence)
	assert_ne(bars_a[0]["close"], bars_b[0]["close"], "종목 다르면 pre-history 다름")


# ── get_candles (W1 / MN) ─────────────────────────────────────────────

func test_get_candles_w1_count_equals_daily_div_5() -> void:
	# Arrange: inject known past daily data (2 seasons = 40 days)
	OhlcvHistory.reset()
	OhlcvHistory.history_seed = 0  # disable pre-history so we control the input
	var stock_id: String = "TEST_STOCK"
	var bars: Array = []
	for i: int in range(40):
		bars.append({"open": 10000, "high": 10500, "low": 9500, "close": 10200, "volume": 100000.0})
	OhlcvHistory._past_daily[stock_id] = bars
	# Act
	var w1_candles: Array[Dictionary] = OhlcvHistory.get_candles(stock_id, "W1")
	# Assert: 40 daily bars / 5 days = 8 weekly candles
	assert_eq(w1_candles.size(), 8, "40 daily bars → 8 W1 candles")


func test_get_candles_mn_count_equals_daily_div_20() -> void:
	OhlcvHistory.reset()
	OhlcvHistory.history_seed = 0
	var stock_id: String = "TEST_STOCK"
	var bars: Array = []
	for i: int in range(100):
		bars.append({"open": 10000, "high": 10500, "low": 9500, "close": 10200, "volume": 100000.0})
	OhlcvHistory._past_daily[stock_id] = bars
	var mn_candles: Array[Dictionary] = OhlcvHistory.get_candles(stock_id, "MN")
	# 100 daily bars / 20 = 5 monthly candles
	assert_eq(mn_candles.size(), 5, "100 daily bars → 5 MN candles")


func test_candle_ohlc_aggregation_correctness() -> void:
	OhlcvHistory.reset()
	OhlcvHistory.history_seed = 0
	var stock_id: String = "AGG_TEST"
	# 5 daily bars: first/last close matters for candle O/C
	var bars: Array = [
		{"open": 100, "high": 120, "low":  90, "close": 110, "volume": 1000.0},
		{"open": 110, "high": 130, "low": 100, "close": 120, "volume": 2000.0},
		{"open": 120, "high": 140, "low": 115, "close": 125, "volume": 1500.0},
		{"open": 125, "high": 135, "low": 110, "close": 115, "volume": 1800.0},
		{"open": 115, "high": 125, "low": 105, "close": 108, "volume": 1200.0},
	]
	OhlcvHistory._past_daily[stock_id] = bars
	var w1: Array[Dictionary] = OhlcvHistory.get_candles(stock_id, "W1")
	assert_eq(w1.size(), 1, "5 daily bars = 1 weekly candle")
	var c: Dictionary = w1[0]
	assert_eq(c["open"],  100, "W1 open = first day open")
	assert_eq(c["close"], 108, "W1 close = last day close")
	assert_eq(c["high"],  140, "W1 high = max of all highs")
	assert_eq(c["low"],    90, "W1 low = min of all lows")
	var expected_vol: float = 1000.0 + 2000.0 + 1500.0 + 1800.0 + 1200.0
	assert_eq(c["volume"], expected_vol, "W1 volume = sum of all volumes")


# ── save / load ───────────────────────────────────────────────────────

func test_save_data_contains_seed_and_past_daily() -> void:
	OhlcvHistory.reset()
	var data: Dictionary = OhlcvHistory.get_save_data()
	assert_true(data.has("history_seed"), "save_data에 history_seed 존재")
	assert_true(data.has("past_daily"),   "save_data에 past_daily 존재")
	assert_ne(data["history_seed"], 0,    "저장된 seed != 0")


func test_load_restores_seed_and_past_bars() -> void:
	# Arrange
	var original_seed: int = 999888777
	var original_bars: Array = [{"open": 5000, "high": 5500, "low": 4800, "close": 5200, "volume": 300000.0}]
	var save_data: Dictionary = {
		"history_seed": original_seed,
		"past_daily":   {"KAKAO": original_bars},
	}
	# Act
	OhlcvHistory.load_save_data(save_data)
	# Assert
	assert_eq(OhlcvHistory.history_seed, original_seed, "seed 복원됨")
	assert_eq(OhlcvHistory.get_past_bar_count("KAKAO"), 1, "past bar 1개 복원됨")


func test_save_load_roundtrip_preserves_history() -> void:
	OhlcvHistory.reset()
	var bars_in: Array = []
	for i: int in range(40):
		bars_in.append({"open": 10000 + i, "high": 11000, "low": 9500, "close": 10200, "volume": 100000.0})
	OhlcvHistory._past_daily["ROUNDTRIP"] = bars_in
	var seed_in: int = OhlcvHistory.history_seed

	var saved: Dictionary = OhlcvHistory.get_save_data()
	OhlcvHistory.reset()  ## Clear state
	OhlcvHistory.load_save_data(saved)

	assert_eq(OhlcvHistory.history_seed, seed_in, "seed round-trip 일치")
	assert_eq(OhlcvHistory.get_past_bar_count("ROUNDTRIP"), 40, "past bar 수 round-trip 일치")


# ── 5-season accumulation integration ────────────────────────────────

func test_five_season_simulation_candle_counts() -> void:
	## Simulates 5 seasons of synthetic daily data and verifies W1 / MN candle counts.
	## AC: (5) S9-07 DoD 검증 — 5시즌 후 타임프레임별 캔들 수 정확.
	OhlcvHistory.reset()
	OhlcvHistory.history_seed = 0  ## Disable pre-history for clean count

	var stock_id: String = "SIM_STOCK"
	# Simulate 5 seasons of 20 days each
	var n_seasons: int = 5
	var simulated_bars: Array = []
	for _s: int in range(n_seasons):
		var season_bars: Array = []
		for _d: int in range(DAYS_PER_SEASON):
			season_bars.append({"open": 10000, "high": 10500, "low": 9500, "close": 10200, "volume": 100000.0})
		simulated_bars.append_array(season_bars)
	OhlcvHistory._past_daily[stock_id] = simulated_bars

	var total_days: int = n_seasons * DAYS_PER_SEASON  ## 100
	var w1_candles: Array[Dictionary] = OhlcvHistory.get_candles(stock_id, "W1")
	var mn_candles: Array[Dictionary] = OhlcvHistory.get_candles(stock_id, "MN")

	assert_eq(w1_candles.size(), total_days / DAYS_PER_WEEK,
		"5 시즌 후 W1 캔들 수 = total_days / 5 (%d)" % (total_days / DAYS_PER_WEEK))
	assert_eq(mn_candles.size(), n_seasons,
		"5 시즌 후 MN 캔들 수 = 시즌 수 (%d)" % n_seasons)
