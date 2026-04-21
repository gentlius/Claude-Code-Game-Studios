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
## Volume range for synthetic bars (shares). Retained as fallback only; actual volume
## is computed by PriceEngine.generate_synthetic_d1() using STATE_VOLUME_MULT × BASE_VOLUME_RANGE.
## ADR-023: 가격 생성 규칙은 PriceEngine 단일 소유. OhlcvHistory는 저장/조회/집계만 담당.

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


## Generates stock.history_seasons × DAYS_PER_SEASON daily bars.
## ADR-023: 자체 알고리즘 제거 — PriceEngine.generate_synthetic_d1() 위임.
## 가격 생성 규칙(Markov, 변동성 프로필, 드리프트)은 PriceEngine 단일 소유.
func _generate_pre_history(stock_id: String) -> Array[Dictionary]:
	var stock_data: StockData = StockDatabase.get_stock(stock_id)
	if stock_data == null:
		return []
	var n_seasons: int = stock_data.history_seasons if stock_data != null else N_PRE_SEASONS
	var total_days: int = n_seasons * DAYS_PER_SEASON

	var rng := RandomNumberGenerator.new()
	# XOR with stock hash — 같은 history_seed라도 종목마다 다른 시퀀스, 재현 가능.
	rng.seed = (history_seed ^ hash(stock_id)) & 0x7FFFFFFF

	return PriceEngine.generate_synthetic_d1(stock_data, total_days, rng)


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
