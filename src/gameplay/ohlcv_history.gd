## OhlcvHistory — Cross-season daily OHLCV bar accumulator.
## Owns all daily bar history that spans multiple seasons:
##   1. Synthetic pre-history (seeded random walk, never stored as bars).
##   2. Real played season bars (accumulated at each season end).
##   3. Current season bars (delegated to PriceEngine.get_ohlcv_history()).
##
## Use get_candles(stock_id, "W1") or get_candles(stock_id, "MN") for aggregated bars.
## Supports save/load via SaveSystem ("ohlcv_history" section).
## See: design/gdd/price-engine.md §OHLCV, design/gdd/chart-renderer.md §W1/MN
extends Node

## Fallback pre-season count when StockData.history_seasons is unavailable.
## Actual value is per-stock (StockData.history_seasons, range 3~300).
const N_PRE_SEASONS: int = 100
## Daily bar count per season (GameClock.DAYS_PER_WEEK × GameClock.WEEKS_PER_SEASON = 20).
const DAYS_PER_SEASON: int = 20
## Daily volatility per volatility_profile. 평균 회귀가 있으므로 HIGH/EXTREME도 발산 안 함.
## GDD price-engine.md §1-4 변동성 프로필과 일치.
const VOL_BY_PROFILE: Dictionary = {
	"LOW": 0.015, "MEDIUM": 0.025, "HIGH": 0.04, "EXTREME": 0.06
}
## 기본 일별 변동률 (volatility_profile 미지정 fallback).
const PRE_HISTORY_VOLATILITY: float = 0.025
## 평균 회귀 강도 — base_price 방향으로 매 거래일 이 비율만큼 당김.
## 값이 클수록 base_price 근처를 벗어나지 않음. 0.05 = 5%/일 회귀.
const MEAN_REVERSION_STRENGTH: float = 0.05
## Volume range for synthetic bars (shares).
const PRE_HISTORY_VOLUME_MIN: float = 100000.0
const PRE_HISTORY_VOLUME_MAX: float = 2000000.0

## Deterministic seed for synthetic pre-history. 0 means uninitialised.
## Generated once at game start and persisted with the save slot.
var history_seed: int = 0

## stock_id → Array[Dictionary] of {o, h, l, c, v} for all COMPLETED real seasons.
## Current season's bars live in PriceEngine, not here.
var _past_daily: Dictionary = {}

## Lazy cache for _get_all_daily() results — keyed by stock_id.
## Invalidated by reset() and _on_season_ended() (which appends real bars).
var _daily_cache: Dictionary = {}

# ── Lifecycle ──

func _ready() -> void:
	SeasonManager.on_season_ended.connect(_on_season_ended)


## Clears all accumulated history and generates a fresh history_seed.
## Called by GameMain at new-game start before any season begins.
func reset() -> void:
	history_seed = _new_seed()
	_past_daily.clear()
	_daily_cache.clear()


# ── Public API ──

## Returns aggregated W1 (weekly) or MN (monthly/season) candles for [param stock_id].
## [param timeframe]: "W1" = 5 daily bars per candle, "MN" = 20 daily bars (1 season).
func get_candles(stock_id: String, timeframe: String) -> Array[Dictionary]:
	var all_daily: Array[Dictionary] = _get_all_daily(stock_id)
	var group_size: int = GameClock.DAYS_PER_WEEK if timeframe == "W1" else DAYS_PER_SEASON
	return _aggregate(all_daily, group_size)


## Returns all daily bars for [param stock_id]:
## pre-history bars + past played season bars + current season bars.
## Exposed for testing; prefer get_candles() for chart display.
func get_all_daily_bars(stock_id: String) -> Array[Dictionary]:
	return _get_all_daily(stock_id)


## Returns the number of completed real-season bars stored for [param stock_id].
func get_past_bar_count(stock_id: String) -> int:
	if not _past_daily.has(stock_id):
		return 0
	return (_past_daily[stock_id] as Array).size()


## Saves all accumulated history (seed + real-played bars).
## Pre-history is NOT saved — it is regenerated from history_seed on demand.
func get_save_data() -> Dictionary:
	# Ensure seed exists even if reset() was somehow skipped.
	if history_seed == 0:
		history_seed = _new_seed()
	# Deep-duplicate so caller-side mutations do not corrupt internal state.
	return {
		"history_seed": history_seed,
		"past_daily": _past_daily.duplicate(true),
	}


## Restores history from a save slot.
func load_save_data(data: Dictionary) -> void:
	history_seed = data.get("history_seed", 0)
	_past_daily.clear()
	_daily_cache.clear()
	var saved: Dictionary = data.get("past_daily", {})
	for stock_id: String in saved.keys():
		var bars_raw: Variant = saved[stock_id]
		if not bars_raw is Array:
			continue
		var bars: Array = []
		for bar: Variant in (bars_raw as Array):
			if bar is Dictionary:
				bars.append(bar)
		_past_daily[stock_id] = bars


# ── Signal Handlers ──

## Collects all stocks' ohlcv_daily from PriceEngine before it resets for the next season.
func _on_season_ended(_final_rank: int, _is_free_market: bool, _season_return_pct: float) -> void:
	var stock_ids: Array[String] = StockDatabase.get_all_stock_ids()
	for sid: String in stock_ids:
		var bars: Array[Dictionary] = PriceEngine.get_ohlcv_history(sid)
		if bars.is_empty():
			continue
		if not _past_daily.has(sid):
			_past_daily[sid] = []
		(_past_daily[sid] as Array).append_array(bars)
	# Invalidate cache — _past_daily now contains new bars.
	_daily_cache.clear()


# ── Private Helpers ──

func _get_all_daily(stock_id: String) -> Array[Dictionary]:
	if _daily_cache.has(stock_id):
		return _daily_cache[stock_id] as Array[Dictionary]

	var result: Array[Dictionary] = [] as Array[Dictionary]
	# 1. Synthetic pre-history (deterministic, generated on demand).
	if history_seed != 0:
		result.append_array(_generate_pre_history(stock_id))
	# 2. Real past seasons.
	if _past_daily.has(stock_id):
		var past: Array = _past_daily[stock_id]
		for bar: Variant in past:
			result.append(bar as Dictionary)
	# 3. Current season from PriceEngine.
	result.append_array(PriceEngine.get_ohlcv_history(stock_id))

	_daily_cache[stock_id] = result
	return result


## Generates stock.history_seasons × DAYS_PER_SEASON daily bars using a seeded random walk.
## Deterministic: same history_seed + stock_id always produces the same bars.
##
## 가격 모델:
##   - 일별 변동률은 stock.volatility_profile 에 따라 다름 (GDD price-engine.md §1-4).
##   - MEAN_REVERSION_STRENGTH 비율로 base_price 방향으로 매일 당김 (발산 방지).
##   - M1CacheManager 가 이 바를 기반으로 M1 캔들을 생성하므로 반드시 같은 시드 사용.
func _generate_pre_history(stock_id: String) -> Array[Dictionary]:
	var stock_data: StockData = StockDatabase.get_stock(stock_id)
	var base_price: int = stock_data.base_price if stock_data != null else 10000
	var n_seasons: int = stock_data.history_seasons if stock_data != null else N_PRE_SEASONS

	# Volatility lookup by profile enum value (int) → string → constant.
	var volatility: float = PRE_HISTORY_VOLATILITY
	if stock_data != null:
		match stock_data.volatility_profile:
			StockData.VolatilityProfile.LOW:     volatility = VOL_BY_PROFILE["LOW"]
			StockData.VolatilityProfile.MEDIUM:  volatility = VOL_BY_PROFILE["MEDIUM"]
			StockData.VolatilityProfile.HIGH:    volatility = VOL_BY_PROFILE["HIGH"]
			StockData.VolatilityProfile.EXTREME: volatility = VOL_BY_PROFILE["EXTREME"]

	var rng := RandomNumberGenerator.new()
	# XOR with stock hash for stock-specific but reproducible sequences.
	rng.seed = (history_seed ^ hash(stock_id)) & 0x7FFFFFFF
	var result: Array[Dictionary] = [] as Array[Dictionary]
	var close_prev: float = float(base_price)
	var total_days: int = n_seasons * DAYS_PER_SEASON
	for _i: int in range(total_days):
		# 평균 회귀: base_price 방향으로 편향 추가.
		var reversion: float = (float(base_price) - close_prev) / close_prev * MEAN_REVERSION_STRENGTH
		var change: float = rng.randf_range(-volatility, volatility) + reversion
		var close: float = maxf(close_prev * (1.0 + change), 100.0)
		var open_off: float = rng.randf_range(-volatility * 0.5, volatility * 0.5)
		var open_price: float = close_prev * (1.0 + open_off)
		var body_high: float = maxf(open_price, close)
		var body_low: float = minf(open_price, close)
		var high: float = body_high * (1.0 + rng.randf_range(0.0, volatility))
		var low: float = body_low * (1.0 - rng.randf_range(0.0, volatility))
		var volume: float = rng.randf_range(PRE_HISTORY_VOLUME_MIN, PRE_HISTORY_VOLUME_MAX)
		result.append({
			"open":   roundi(open_price),
			"high":   roundi(high),
			"low":    roundi(low),
			"close":  roundi(close),
			"volume": volume,
		})
		close_prev = close
	return result


## Aggregates a flat array of daily bars into candles of [param group_size] bars each.
func _aggregate(daily_bars: Array[Dictionary], group_size: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = [] as Array[Dictionary]
	var i: int = 0
	while i < daily_bars.size():
		var end: int = mini(i + group_size - 1, daily_bars.size() - 1)
		var o: int = daily_bars[i].get("open", 0)
		var h: int = daily_bars[i].get("high", 0)
		var l: int = daily_bars[i].get("low", 0)
		var c: int = daily_bars[end].get("close", 0)
		var v: float = 0.0
		for j: int in range(i, end + 1):
			h = maxi(h, daily_bars[j].get("high", 0))
			l = mini(l, daily_bars[j].get("low", 0))
			v += float(daily_bars[j].get("volume", 0.0))
		result.append({"open": o, "high": h, "low": l, "close": c, "volume": v})
		i += group_size
	return result


## Generates a non-zero seed from the high-resolution timer.
static func _new_seed() -> int:
	var s: int = Time.get_ticks_usec()
	return s if s != 0 else 1
