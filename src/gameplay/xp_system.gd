## Autoload — Manages XP accumulation, levels, and skill points.
## Feature layer. Depends on: OrderEngine, PortfolioManager, GameClock.
## See: design/gdd/xp-system.md
extends Node

# ── Signals ──

signal on_level_up(new_level: int, skill_points: int)
signal on_xp_gained(amount: int, new_total: int, source: String)

## Path to the external config file (assets/data/xp_config.json).
const CONFIG_PATH: String = "res://assets/data/xp_config.json"

# ── Config (Tuning Knobs — see GDD Tuning Knobs section) ──
## All values loaded from xp_config.json in _ready(). Hardcoded values are fallback defaults.

## Daily bonus XP base value (GDD F1)
var BASE_DAILY_XP: int = 30
## Season completion base XP (GDD F2)
var BASE_SEASON_XP: int = 200
## XP per 1% season return (GDD F2)
var RETURN_XP_SCALE: int = 10
## Level-up base XP unit (GDD F3)
var BASE_LEVEL_XP: int = 100
## Level curve exponent (GDD F3)
var LEVEL_EXPONENT: float = 1.5

## Rank XP table: index 0 = 1st place (GDD F2)
var RANK_XP_TABLE: Array[int] = [500, 350, 250, 150, 150, 50]

## Alpha multiplier thresholds (GDD F1) — alpha = player daily return − market avg return.
## Array of [alpha_threshold_pct, multiplier] — checked in descending order.
## Completion bonus: XP awarded for positive return with enough trades (GDD §3-4, §4-7)
var COMPLETION_BONUS_XP: int = 20
## Completion bonus: minimum filled orders required (mirrors SeasonManager.MIN_TRADES_FOR_RANK concept)
var COMPLETION_MIN_TRADES: int = 5
## Comeback bonus multiplier: applied when returning to official league after ≥ 2 consecutive
## free-market seasons (GDD §4-7). Loaded from xp_config.json.
var COMEBACK_XP_MULTIPLIER: float = 1.20

var DAILY_RETURN_MULTIPLIERS: Array[Array] = [
	[3.0, 3.0],   # alpha ≥ +3%
	[1.0, 2.0],   # alpha +1~3%
	[0.0, 1.5],   # alpha 0~1%
	[-1.0, 1.0],  # alpha -1~0%
	[-INF, 0.5],  # alpha < -1%
]

# ── State ──

var _total_xp: int = 0
var _current_level: int = 1
var _spent_skill_points: int = 0
var _weekly_xp: int = 0  ## XP this week (reset after weekly report via reset_weekly_xp())
var _daily_has_trade: bool = false  ## Tracks if at least 1 fill occurred today
var _prev_close_assets: int = 0     ## Previous day's closing total assets
var _last_daily_return_pct: float = 0.0  ## Player daily return % (before alpha adjustment)
var _last_market_return_pct: float = 0.0 ## Market avg return % on last settlement day
var _last_alpha_pct: float = 0.0         ## Alpha = player_return − market_return
var _last_season_breakdown: Dictionary = {}  ## Breakdown from last grant_season_bonus()

# ── Lifecycle ──

func _ready() -> void:
	_load_config()
	GameClock.on_market_close.connect(_on_market_close)
	GameClock.on_season_start.connect(_on_season_start)
	GameClock.on_market_open.connect(_on_market_open)
	OrderEngine.on_order_filled.connect(_on_order_filled)


# ── Config Loading ──

## Load tuning values from assets/data/xp_config.json.
## Falls back to hardcoded defaults on any read or parse error (design/gdd/xp-system.md §7).
func _load_config() -> void:
	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("XpSystem._load_config: cannot open %s — using defaults" % CONFIG_PATH)
		return
	var json_text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		push_warning("XpSystem._load_config: JSON parse error in %s — using defaults" % CONFIG_PATH)
		return
	var cfg: Dictionary = parsed as Dictionary

	if cfg.has("baseDailyXp"):        BASE_DAILY_XP        = int(cfg["baseDailyXp"])
	if cfg.has("baseSeasonXp"):       BASE_SEASON_XP       = int(cfg["baseSeasonXp"])
	if cfg.has("returnXpScale"):      RETURN_XP_SCALE      = int(cfg["returnXpScale"])
	if cfg.has("baseLevelXp"):        BASE_LEVEL_XP        = int(cfg["baseLevelXp"])
	if cfg.has("levelExponent"):      LEVEL_EXPONENT       = float(cfg["levelExponent"])
	if cfg.has("completionBonusXp"):  COMPLETION_BONUS_XP  = int(cfg["completionBonusXp"])
	if cfg.has("completionMinTrades"): COMPLETION_MIN_TRADES = int(cfg["completionMinTrades"])

	if cfg.has("rankXpTable") and cfg["rankXpTable"] is Array:
		var arr: Array = cfg["rankXpTable"]
		var loaded: Array[int] = []
		for v: Variant in arr:
			loaded.append(int(v))
		if not loaded.is_empty():
			RANK_XP_TABLE = loaded

	# Daily return multipliers: JSON stores "-Inf" as a string sentinel.
	if cfg.has("dailyReturnMultipliers") and cfg["dailyReturnMultipliers"] is Array:
		var arr: Array = cfg["dailyReturnMultipliers"]
		var loaded: Array[Array] = []
		for entry: Variant in arr:
			if entry is Array and (entry as Array).size() == 2:
				var row: Array = entry as Array
				var threshold: float
				if row[0] is String and (row[0] as String).to_lower() == "-inf":
					threshold = -INF
				else:
					threshold = float(row[0])
				loaded.append([threshold, float(row[1])])
		if not loaded.is_empty():
			DAILY_RETURN_MULTIPLIERS = loaded


# ── Public API ──

## Total accumulated XP (permanent across seasons)
func get_total_xp() -> int:
	return _total_xp


## XP gained this week (since last reset_weekly_xp() call).
## SettlementReporter reads this for the weekly report; call reset_weekly_xp() after display.
func get_weekly_xp() -> int:
	return _weekly_xp


## Resets the weekly XP counter. Called by SettlementReporter after the weekly report is shown.
func reset_weekly_xp() -> void:
	_weekly_xp = 0


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


## Called by SeasonManager to grant weekly prize XP (ADR-005).
## Use this instead of calling _grant_xp() directly.
func grant_weekly_prize_xp(amount: int) -> void:
	_grant_xp(amount, "weekly_prize")


## Called by LifestyleManager when a luxury/network/social item grants XP. GDD lifestyle-spending.md §3-2.
func grant_lifestyle_xp(amount: int) -> void:
	_grant_xp(amount, "lifestyle")


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
	_weekly_xp += amount
	on_xp_gained.emit(amount, _total_xp, source)
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


## Returns breakdown of last daily XP grant for settlement popup display (AC-2).
## { base_xp, multiplier, total_xp, return_tier, alpha_pct, player_return_pct, market_return_pct }
## Tier is based on alpha (player daily return − market avg return), not raw return.
func get_daily_xp_breakdown() -> Dictionary:
	var multiplier: float = 0.5
	var tier: String = "< -1%"
	var tiers: Array[String] = ["< -1%", "-1~0%", "0~1%", "1~3%", "≥ +3%"]
	for i: int in range(DAILY_RETURN_MULTIPLIERS.size()):
		if _last_alpha_pct >= DAILY_RETURN_MULTIPLIERS[i][0]:
			multiplier = DAILY_RETURN_MULTIPLIERS[i][1]
			tier = tiers[DAILY_RETURN_MULTIPLIERS.size() - 1 - i]
			break
	var total: int = int(floor(BASE_DAILY_XP * multiplier))
	return {
		"base_xp": BASE_DAILY_XP,
		"multiplier": multiplier,
		"total_xp": total,
		"return_tier": tier,
		"alpha_pct": _last_alpha_pct,
		"player_return_pct": _last_daily_return_pct,
		"market_return_pct": _last_market_return_pct,
	}


## Returns breakdown of last season XP grant for settlement popup sequential reveal (AC-9).
## { base_xp, rank_bonus, return_bonus, total_xp, final_rank, season_return_pct }
func get_season_xp_breakdown() -> Dictionary:
	return _last_season_breakdown.duplicate()


## GDD F2: season_xp = BASE_SEASON_XP + rank_bonus + return_bonus
## Returns { "xp": int, "rank_bonus": int, "return_bonus": int }.
func _calculate_season_xp(final_rank: int, season_return_pct: float) -> Dictionary:
	var rank_index: int = clampi(final_rank - 1, 0, RANK_XP_TABLE.size() - 1)
	var rank_bonus: int = RANK_XP_TABLE[rank_index]
	var return_bonus: int = int(floor(maxf(0.0, season_return_pct) * RETURN_XP_SCALE))
	return {
		"xp": BASE_SEASON_XP + rank_bonus + return_bonus,
		"rank_bonus": rank_bonus,
		"return_bonus": return_bonus,
	}


## GDD F1: daily_xp = floor(BASE_DAILY_XP × daily_return_multiplier)
func _calculate_daily_xp(daily_return_pct: float) -> int:
	var multiplier: float = 0.5  # default fallback
	for entry: Array in DAILY_RETURN_MULTIPLIERS:
		if daily_return_pct >= entry[0]:
			multiplier = entry[1]
			break
	return int(floor(BASE_DAILY_XP * multiplier))


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
	var market_return_pct: float = PriceEngine.get_market_avg_return_pct()
	var alpha_pct: float = daily_return_pct - market_return_pct

	_last_daily_return_pct = daily_return_pct
	_last_market_return_pct = market_return_pct
	_last_alpha_pct = alpha_pct
	var daily_xp: int = _calculate_daily_xp(alpha_pct)
	_grant_xp(daily_xp, "daily_bonus")

	# Update previous close for next day's calculation
	_prev_close_assets = current_assets


## Called by SeasonManager at season end. Grants season bonus XP.
## Implements GDD §3-1 step ⑤ and §4-7 free-market XP rules.
## is_comeback: True when player is returning to official league after ≥ 2 consecutive
## free-market seasons — that season's total rank+return XP is multiplied by COMEBACK_XP_MULTIPLIER.
## See: design/gdd/season-manager.md §3-4, §4-7
func grant_season_bonus(
	final_rank: int,
	is_free_market: bool,
	season_return_pct: float,
	season_trade_count: int,
	is_comeback: bool = false
) -> void:
	# Free-market participants receive no rank bonus XP (no official ranking).
	# Official league participants receive full season XP based on rank + return.
	if not is_free_market:
		var breakdown: Dictionary = _calculate_season_xp(final_rank, season_return_pct)
		var total_xp: int = breakdown["xp"]
		# Comeback bonus: ×COMEBACK_XP_MULTIPLIER on first official season after 2+ free-market
		# seasons (GDD §4-7). Applied to rank+return XP only, not the completion bonus.
		if is_comeback:
			total_xp = int(floor(float(total_xp) * COMEBACK_XP_MULTIPLIER))
		_last_season_breakdown = {
			"base_xp": BASE_SEASON_XP,
			"rank_bonus": breakdown["rank_bonus"],
			"return_bonus": breakdown["return_bonus"],
			"total_xp": total_xp,
			"final_rank": final_rank,
			"season_return_pct": season_return_pct,
			"is_comeback": is_comeback,
		}
		_grant_xp(total_xp, "season_bonus")

	# Completion bonus: 20 XP for any participant (free-market or official)
	# who finishes with return_pct >= 0% AND at least 5 filled orders.
	# No comeback multiplier applies to the completion bonus (GDD §3-4, §4-7).
	# See: design/gdd/season-manager.md AC-12, AC-19
	if season_return_pct >= 0.0 and season_trade_count >= COMPLETION_MIN_TRADES:
		_grant_xp(COMPLETION_BONUS_XP, "completion_bonus")


# ── Serialization ──

## Returns serializable state for save system.
## Includes daily settlement display fields so the popup shows correct values after load.
func get_save_data() -> Dictionary:
	return {
		"total_xp": _total_xp,
		"current_level": _current_level,
		"spent_skill_points": _spent_skill_points,
		"prev_close_assets": _prev_close_assets,
		"last_daily_return_pct": _last_daily_return_pct,
		"last_market_return_pct": _last_market_return_pct,
		"last_alpha_pct": _last_alpha_pct,
		"weekly_xp": _weekly_xp,
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
	_prev_close_assets = maxi(data.get("prev_close_assets", 0), 0)
	_last_daily_return_pct  = data.get("last_daily_return_pct", 0.0)
	_last_market_return_pct = data.get("last_market_return_pct", 0.0)
	_last_alpha_pct         = data.get("last_alpha_pct", 0.0)
	_weekly_xp = maxi(data.get("weekly_xp", 0), 0)


## Resets all XP state to initial values for a new game.
## Resets all XP state. Called by GameMain (new game) and tests (before_each).
func reset() -> void:
	_total_xp = 0
	_current_level = 1
	_spent_skill_points = 0
	_daily_has_trade = false
	_prev_close_assets = 0
	_last_daily_return_pct = 0.0
	_last_market_return_pct = 0.0
	_last_alpha_pct = 0.0
	_last_season_breakdown = {}
	_weekly_xp = 0
