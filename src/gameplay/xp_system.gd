## Autoload — Manages XP accumulation, levels, and skill points.
## Feature layer. Depends on: OrderEngine, PortfolioManager, GameClock.
## See: design/gdd/xp-system.md
extends Node

# ── Signals ──

signal on_level_up(new_level: int, skill_points: int)
signal on_xp_gained(amount: int, new_total: int)

# ── Config (Tuning Knobs — see GDD Tuning Knobs section) ──

## Daily bonus XP base value (GDD F1)
@export var BASE_DAILY_XP: int = 30
## Season completion base XP (GDD F2)
@export var BASE_SEASON_XP: int = 200
## XP per 1% season return (GDD F2)
@export var RETURN_XP_SCALE: int = 10
## Level-up base XP unit (GDD F3)
@export var BASE_LEVEL_XP: int = 100
## Level curve exponent (GDD F3)
@export var LEVEL_EXPONENT: float = 1.5

## Rank XP table: index 0 = 1st place (GDD F2)
var RANK_XP_TABLE: Array[int] = [500, 350, 250, 150, 150, 50]

## Daily return multiplier thresholds (GDD rule 1-1)
## Array of [threshold_pct, multiplier] — checked in descending order
var DAILY_RETURN_MULTIPLIERS: Array[Array] = [
	[5.0, 3.0],
	[3.0, 2.0],
	[1.0, 1.5],
	[0.0, 1.0],
	[-INF, 0.5],
]

# ── State ──

var _total_xp: int = 0
var _current_level: int = 1
var _spent_skill_points: int = 0
var _daily_has_trade: bool = false  ## Tracks if at least 1 fill occurred today
var _prev_close_assets: int = 0     ## Previous day's closing total assets

# ── Lifecycle ──

func _ready() -> void:
	GameClock.on_market_close.connect(_on_market_close)
	GameClock.on_season_start.connect(_on_season_start)
	GameClock.on_market_open.connect(_on_market_open)
	OrderEngine.on_order_filled.connect(_on_order_filled)


# ── Public API ──

## Total accumulated XP (permanent across seasons)
func get_total_xp() -> int:
	return _total_xp


## Current player level
func get_current_level() -> int:
	return _current_level


## Cumulative XP required to reach a given level (public, for UI display).
func get_cumulative_xp_for_level(level: int) -> int:
	return _cumulative_xp_for_level(level)


## XP progress toward next level as fraction [0.0, 1.0)
func get_xp_progress() -> float:
	var current_threshold: int = _cumulative_xp_for_level(_current_level)
	var next_threshold: int = _cumulative_xp_for_level(_current_level + 1)
	var range_xp: int = next_threshold - current_threshold
	if range_xp <= 0:
		return 0.0
	return float(_total_xp - current_threshold) / float(range_xp)


## Total skill points earned (= level - 1)
func get_total_skill_points() -> int:
	return _current_level - 1


## Skill points available to spend
func get_available_skill_points() -> int:
	return get_total_skill_points() - _spent_skill_points


## Called by SkillTree when a skill point is consumed
func spend_skill_point() -> bool:
	if get_available_skill_points() <= 0:
		return false
	_spent_skill_points += 1
	return true


# ── XP Granting ──

## Add XP and check for level-ups. Returns number of levels gained.
func _grant_xp(amount: int, source: String) -> int:
	if amount <= 0:
		return 0
	_total_xp += amount
	on_xp_gained.emit(amount, _total_xp)
	return _check_level_ups()


## Check and process any pending level-ups
func _check_level_ups() -> int:
	var levels_gained: int = 0
	while _total_xp >= _cumulative_xp_for_level(_current_level + 1):
		_current_level += 1
		levels_gained += 1
		on_level_up.emit(_current_level, get_available_skill_points())
	return levels_gained


# ── Formulas (GDD F1-F4) ──

## Required XP to reach a given level (cumulative from level 1)
## GDD F3: required_xp(level) = floor(BASE_LEVEL_XP × (level ^ LEVEL_EXPONENT))
func _cumulative_xp_for_level(level: int) -> int:
	if level <= 1:
		return 0
	var total: int = 0
	for lv: int in range(2, level + 1):
		total += int(floor(BASE_LEVEL_XP * pow(float(lv - 1), LEVEL_EXPONENT)))
	return total


## GDD F1: daily_xp = floor(BASE_DAILY_XP × daily_return_multiplier)
func _calculate_daily_xp(daily_return_pct: float) -> int:
	var multiplier: float = 0.5  # default fallback
	for entry: Array in DAILY_RETURN_MULTIPLIERS:
		if daily_return_pct >= entry[0]:
			multiplier = entry[1]
			break
	return int(floor(BASE_DAILY_XP * multiplier))


## GDD F2: season_xp = BASE_SEASON_XP + rank_bonus + return_bonus
func _calculate_season_xp(final_rank: int, season_return_pct: float) -> int:
	var rank_index: int = clampi(final_rank - 1, 0, RANK_XP_TABLE.size() - 1)
	var rank_bonus: int = RANK_XP_TABLE[rank_index]
	var return_bonus: int = int(floor(maxf(0.0, season_return_pct) * RETURN_XP_SCALE))
	return BASE_SEASON_XP + rank_bonus + return_bonus


# ── Signal Handlers ──

func _on_season_start() -> void:
	_daily_has_trade = false
	# Use actual current cash rather than the hardcoded constant so that
	# carry-over cash from a previous season (or test setup) is reflected
	# correctly as the day-1 baseline. (R-07 fix)
	_prev_close_assets = CurrencySystem.get_sim_cash()


func _on_market_open() -> void:
	_daily_has_trade = false


func _on_order_filled(_order: Dictionary) -> void:
	# Track that at least one trade happened today (activity condition for daily XP)
	_daily_has_trade = true


func _on_market_close() -> void:
	if not _daily_has_trade:
		return  # No trades today → no daily bonus XP

	var current_assets: int = PortfolioManager.get_total_assets()
	var base_assets: int = _prev_close_assets if _prev_close_assets > 0 else CurrencySystem.DEFAULT_SEASON_SEED
	var daily_return_pct: float = float(current_assets - base_assets) / float(base_assets) * 100.0

	var daily_xp: int = _calculate_daily_xp(daily_return_pct)
	_grant_xp(daily_xp, "daily_bonus")

	# Update previous close for next day's calculation
	_prev_close_assets = current_assets


## Called by SeasonManager at season end. Grants season bonus XP.
## Implements GDD §3-1 step ⑤ and §4-7 free-market XP penalty rules.
## See: design/gdd/season-manager.md §3-4, §4-7
func grant_season_bonus(
	final_rank: int,
	is_free_market: bool,
	season_return_pct: float,
	season_trade_count: int
) -> void:
	# Free-market participants receive no rank bonus XP (no official ranking).
	# Official league participants receive full season XP based on rank + return.
	if not is_free_market:
		var season_xp: int = _calculate_season_xp(final_rank, season_return_pct)
		_grant_xp(season_xp, "season_bonus")

	# Completion bonus: 20 XP for any participant (free-market or official)
	# who finishes with return_pct >= 0% AND at least 5 filled orders.
	# No XP penalty applies to the completion bonus (GDD §3-4, §4-7).
	# See: design/gdd/season-manager.md AC-12, AC-19
	if season_return_pct >= 0.0 and season_trade_count >= 5:
		_grant_xp(20, "completion_bonus")


# ── Serialization ──

## Returns serializable state for save system.
func get_save_data() -> Dictionary:
	return {
		"total_xp": _total_xp,
		"current_level": _current_level,
		"spent_skill_points": _spent_skill_points,
	}


## Restores state from save data, clamping to prevent invalid values.
func load_save_data(data: Dictionary) -> void:
	_total_xp = data.get("total_xp", 0)
	_current_level = data.get("current_level", 1)
	_spent_skill_points = data.get("spent_skill_points", 0)
	# Clamp to prevent negative values (GDD edge case)
	_total_xp = maxi(_total_xp, 0)
	_current_level = maxi(_current_level, 1)
	_spent_skill_points = maxi(_spent_skill_points, 0)
