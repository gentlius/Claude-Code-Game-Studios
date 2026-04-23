## Autoload — Season lifecycle, tier assignment, leaderboard, and ending checks.
## Orchestrates: forced liquidation, prize distribution, XP grants, AI init.
## See: design/gdd/season-manager.md
extends Node

# ── Signals ──

## Emitted when a season officially begins (after tier assignment).
signal on_season_started(tier: int, is_free_market: bool)

## Emitted when a season ends (after all settlements are complete).
signal on_season_ended(final_rank: int, is_free_market: bool, season_return_pct: float)

## Emitted when the player's tier is assigned (or re-confirmed each season).
signal on_tier_assigned(tier: int, tier_name: String)

## Emitted once per day (market close) and once per tick when leaderboard changes.
signal on_leaderboard_updated(tier_rank: int, global_rank: int)

## Emitted when the Investor Master ending condition is met.
signal on_master_ending_triggered()

## Emitted when the Hangang ending condition is met.
signal on_hangang_ending_triggered()

# ── Tier Constants (GDD §3-2) ──

const TIER_FREE_MARKET: int          = -1  ## Below bronze — no official league
const TIER_BRONZE: int               = 0
const TIER_SILVER: int               = 1
const TIER_GOLD: int                 = 2
const TIER_PLATINUM: int             = 3
const TIER_EMERALD: int              = 4
const TIER_DIAMOND: int              = 5
const TIER_MASTER: int               = 6
const TIER_GRANDMASTER: int          = 7
const TIER_CHALLENGER: int           = 8
const TIER_LEGEND: int               = 9
const TIER_MASTER_OF_INVESTMENT: int = 10

const TIER_COUNT: int = 11
## 티어별 참가자 비율 (GDD §3-3). 합 ≈ 1.0. league_screen.gd가 단일 소스로 참조.
const TIER_RATIOS: Array[float] = [
	0.38, 0.20, 0.13, 0.09, 0.06,
	0.045, 0.035, 0.025, 0.015, 0.01, 0.005,
]

## Fiction date — each season maps to one quarter. Seasons cycle Q1→Q2→Q3→Q4→Q1…
## Used to generate realistic-looking news dates without hardcoding a real calendar year.
## Season 1 = 1월, Season 2 = 4월, Season 3 = 7월, Season 4 = 10월, Season 5 = 1월, …
const SEASON_MONTH_STARTS: Array[int] = [1, 4, 7, 10]

## Path to the external config file (assets/data/season_config.json).
const CONFIG_PATH: String = "res://assets/data/season_config.json"

# ── Config — Tier Thresholds (GDD §3-2, Tuning Knob §7-1) ──
## Entry capital threshold for each tier (index = tier constant).
## Loaded from season_config.json — designer adjustable.
var TIER_THRESHOLD: Array[int] = [
	1_000_000,          ## TIER_BRONZE
	3_000_000,          ## TIER_SILVER
	10_000_000,         ## TIER_GOLD
	30_000_000,         ## TIER_PLATINUM
	100_000_000,        ## TIER_EMERALD
	300_000_000,        ## TIER_DIAMOND
	1_000_000_000,      ## TIER_MASTER
	3_000_000_000,      ## TIER_GRANDMASTER
	10_000_000_000,     ## TIER_CHALLENGER
	30_000_000_000,     ## TIER_LEGEND
	100_000_000_000,    ## TIER_MASTER_OF_INVESTMENT
]

var TIER_NAMES: Array[String] = [
	"브론즈", "실버", "골드", "플래티넘", "에메랄드",
	"다이아", "마스터", "그랜드마스터", "챌린저", "레전드", "거장",
]

# ── Config — Prize Rates (GDD §4-6, Tuning Knob §7-2) ──
## Cash prize multiplier per rank (applied to tier entry threshold).
## rank key = 1-indexed finish position within the tier. Loaded from season_config.json.
var PRIZE_RATE: Dictionary = {
	1:  0.50,
	2:  0.30,
	3:  0.15,
	4:  0.08,
	5:  0.05,
	6:  0.03,
	7:  0.03,
	8:  0.03,
	9:  0.03,
	10: 0.03,
}

# ── Config — Special Rewards (GDD §3-4, Tuning Knob §7-3) ──
## Weekly top-return prize rate (× tier entry threshold).
var WEEKLY_PRIZE_RATE: float = 0.02
## Minimum weekly fills to qualify for the weekly prize.
var MIN_WEEKLY_TRADES: int = 2
## Most-trades prize rate (× tier entry threshold).
var MOST_TRADES_PRIZE_RATE: float = 0.01
## XP awarded to player for winning the weekly top-return prize (GDD §3-4).
var WEEKLY_PRIZE_XP: int = 50

# ── Config — Season Structure (GDD §7-1) ──
## Minimum season-level fills to qualify for prize payouts.
var MIN_TRADES_FOR_RANK: int = 5
## Total simulated participants (display only — AI object count is in ai-competitor.md).
var TOTAL_PARTICIPANTS: int = 20_000

## 시즌 수익률 등급 임계값 (%). settlement_reporter.gd가 단일 소스로 참조 (TD-CR-23).
## [S≥20%, A≥10%, B≥0%, C≥-10%, D<-10%]. Loaded from season_config.json.
var GRADE_THRESHOLDS: Array[float] = [20.0, 10.0, 0.0, -10.0]

# ── Config — Free Market & Endings (GDD §7-4) ──
## Assets below this threshold at season start → free-market mode.
var FREE_MARKET_THRESHOLD: int = 1_000_000
## Cash below this with no holdings → Hangang ending (free-market only).
var HANGANG_THRESHOLD: int = 10_000
## Total assets at/above this at season end → Master ending.
var ENDING_THRESHOLD: int = 100_000_000_000
## Consecutive free-market seasons required to earn comeback bonus on return (GDD §4-7).
var COMEBACK_BONUS_SEASONS: int = 2
## XP multiplier applied to the comeback season's total XP grant (GDD §4-7).
var COMEBACK_XP_MULTIPLIER: float = 1.20

# ── State ──

var _current_tier: int = TIER_FREE_MARKET
var _is_free_market: bool = true
## Number of seasons started since application launch (increments each start_season call).
var _seasons_played: int = 0
var _season_start_deposit: int = 0
var _weekly_start_capital: int = 0

## Accumulated fill count for the current week (reset each week-end).
var _weekly_trade_count: int = 0

## Snapshot of _weekly_trade_count at the most-recently completed week (for award logic).
var _last_week_trade_count: int = 0

## Whether an ending has already been triggered this session (prevents double-fire).
var _ending_triggered: bool = false

## Consecutive seasons spent in free-market mode (resets when returning to official league).
## Used to determine comeback bonus eligibility (GDD §4-7).
var _consecutive_free_market_seasons: int = 0

## True when this season qualifies for the comeback XP bonus (first official season
## after ≥ COMEBACK_BONUS_SEASONS consecutive free-market seasons).
var _is_comeback_season: bool = false

# ── Lifecycle ──

func _ready() -> void:
	_load_config()
	GameClock.on_season_start.connect(_on_season_start)
	GameClock.on_season_end.connect(_on_season_end)
	GameClock.on_week_end.connect(_on_week_end)
	GameClock.on_market_state_changed.connect(_on_market_state_changed)
	OrderEngine.on_order_filled.connect(_on_order_filled)
	## TD-08: SeasonManager owns the full season-start sequence.
	## GameClock emits on_new_season_requested after SEASON_END confirmation.
	GameClock.on_new_season_requested.connect(func() -> void: start_season())


# ── Config Loading ──

## Load tuning values from assets/data/season_config.json.
## Falls back to hardcoded defaults on any read or parse error (design/gdd/season-manager.md §7).
func _load_config() -> void:
	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("SeasonManager._load_config: cannot open %s — using defaults" % CONFIG_PATH)
		return
	var json_text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		push_warning("SeasonManager._load_config: JSON parse error in %s — using defaults" % CONFIG_PATH)
		return
	var cfg: Dictionary = parsed as Dictionary

	# Tier thresholds (Array[int])
	if cfg.has("tierThresholds") and cfg["tierThresholds"] is Array:
		var arr: Array = cfg["tierThresholds"]
		var loaded: Array[int] = []
		for v: Variant in arr:
			loaded.append(int(v))
		if loaded.size() == TIER_COUNT:
			TIER_THRESHOLD = loaded

	# Tier names (Array[String])
	if cfg.has("tierNames") and cfg["tierNames"] is Array:
		var arr: Array = cfg["tierNames"]
		var loaded: Array[String] = []
		for v: Variant in arr:
			loaded.append(str(v))
		if loaded.size() == TIER_COUNT:
			TIER_NAMES = loaded

	# Prize rates — JSON keys are strings; convert to int keys at load time.
	if cfg.has("prizeRates") and cfg["prizeRates"] is Dictionary:
		var raw: Dictionary = cfg["prizeRates"]
		var loaded: Dictionary = {}
		for key: Variant in raw:
			loaded[int(key)] = float(raw[key])
		PRIZE_RATE = loaded

	# Scalar tuning knobs — only override if key present and correct type.
	if cfg.has("weeklyPrizeRate"):    WEEKLY_PRIZE_RATE    = float(cfg["weeklyPrizeRate"])
	if cfg.has("minWeeklyTrades"):    MIN_WEEKLY_TRADES    = int(cfg["minWeeklyTrades"])
	if cfg.has("mostTradesPrizeRate"): MOST_TRADES_PRIZE_RATE = float(cfg["mostTradesPrizeRate"])
	if cfg.has("weeklyPrizeXp"):      WEEKLY_PRIZE_XP      = int(cfg["weeklyPrizeXp"])
	if cfg.has("minTradesForRank"):   MIN_TRADES_FOR_RANK  = int(cfg["minTradesForRank"])
	if cfg.has("totalParticipants"):  TOTAL_PARTICIPANTS   = int(cfg["totalParticipants"])
	if cfg.has("freeMarketThreshold"):  FREE_MARKET_THRESHOLD    = int(cfg["freeMarketThreshold"])
	if cfg.has("hangangThreshold"):    HANGANG_THRESHOLD        = int(cfg["hangangThreshold"])
	if cfg.has("endingThreshold"):     ENDING_THRESHOLD         = int(cfg["endingThreshold"])
	if cfg.has("comebackBonusSeasons"): COMEBACK_BONUS_SEASONS  = int(cfg["comebackBonusSeasons"])
	if cfg.has("comebackXpMultiplier"): COMEBACK_XP_MULTIPLIER  = float(cfg["comebackXpMultiplier"])
	if cfg.has("gradeThresholds") and cfg["gradeThresholds"] is Array:
		var arr: Array = cfg["gradeThresholds"]
		var loaded: Array[float] = []
		for v: Variant in arr:
			loaded.append(float(v))
		if loaded.size() == 4:
			GRADE_THRESHOLDS = loaded


# ── Public API ──

## Start a new season. Called when the player presses the "시즌 시작" button.
## Snapshots assets, assigns tier, initialises AI, and emits on_season_started.
## Returns false if assets == 0 (EC-08 guard).
func start_season() -> bool:
	var total_assets: int = PortfolioManager.get_total_assets()

	# EC-08: guard against zero capital (theoretical, but must not divide by zero later)
	if total_assets <= 0:
		push_error("SeasonManager.start_season: sim_total_assets <= 0, season cannot begin")
		return false

	_seasons_played += 1
	_season_start_deposit = total_assets
	_weekly_start_capital = total_assets
	_weekly_trade_count = 0
	_last_week_trade_count = 0
	_ending_triggered = false

	# Determine mode and tier (GDD §3-1, §4-1)
	if total_assets < FREE_MARKET_THRESHOLD:
		_current_tier = TIER_FREE_MARKET
		_is_free_market = true
		_is_comeback_season = false
		_consecutive_free_market_seasons += 1
	else:
		_current_tier = _assign_tier(total_assets)
		_is_free_market = false
		# Comeback bonus: earned when returning to official league after ≥ COMEBACK_BONUS_SEASONS
		# consecutive free-market seasons (GDD §4-7).
		_is_comeback_season = _consecutive_free_market_seasons >= COMEBACK_BONUS_SEASONS
		_consecutive_free_market_seasons = 0
		on_tier_assigned.emit(_current_tier, get_tier_name(_current_tier))

		# Initialise AI competitors (GDD §3-3 AI contract)
		var seed_val: int = Time.get_ticks_usec()  ## ADR-018: 전역 randi() 대신 고해상도 타임스탬프로 세션별 엔트로피 격리
		var participant_counts: Dictionary = _build_participant_counts()
		AiCompetitor.init_season(_current_tier, participant_counts, seed_val)

	## TD-08: SeasonManager owns GameClock initialisation (tick counters, state).
	## Called BEFORE on_season_started so GameClock._season_active == true
	## when signal handlers call SeasonManager.is_season_active() (Godot signals are sync).
	GameClock.start_season()
	on_season_started.emit(_current_tier, _is_free_market)
	return true


## Current player tier constant.
func get_current_tier() -> int:
	return _current_tier


## Human-readable tier name. Returns "프리마켓" when in free-market mode.
func get_tier_name(tier: int) -> String:
	if tier == TIER_FREE_MARKET:
		return "프리마켓"
	if tier < 0 or tier >= TIER_NAMES.size():
		return "알 수 없음"
	return TIER_NAMES[tier]


## True when the player is in free-market mode this season.
func get_is_free_market() -> bool:
	return _is_free_market


## Season return rate in percent (GDD §4-2).
## Includes reserved_cash in account_total_value.
func get_season_return_pct() -> float:
	if _season_start_deposit <= 0:
		return 0.0
	var total_assets: int = PortfolioManager.get_total_assets()
	return float(total_assets - _season_start_deposit) / float(_season_start_deposit) * 100.0


## Weekly return rate in percent (GDD §4-4).
func get_weekly_return_pct() -> float:
	if _weekly_start_capital <= 0:
		return 0.0
	var total_assets: int = PortfolioManager.get_total_assets()
	return float(total_assets - _weekly_start_capital) / float(_weekly_start_capital) * 100.0


## Season start deposit snapshot (amount in account at season open).
func get_season_start_deposit() -> int:
	return _season_start_deposit


## True when a season has been started (delegates to GameClock — single source of truth).
## Used by TradingScreen to decide whether to show "시즌 시작" or "장 시작" button.
func is_season_active() -> bool:
	return GameClock.is_season_active()


## Fiction calendar date for the current game tick.
## Returns {month: int, day: int} — month cycles Q1→Q2→Q3→Q4 per season.
## day is 1-based within the month (trading day 0 = 1일, day 19 = 20일).
## Used by news headlines so they never show a hardcoded real-world month.
func get_fiction_date() -> Dictionary:
	var quarter_idx: int = (_seasons_played - 1) % SEASON_MONTH_STARTS.size()
	if quarter_idx < 0:
		quarter_idx = 0
	var month: int = SEASON_MONTH_STARTS[quarter_idx]
	var day: int = GameClock.get_current_day() + 1  ## 0-based → 1-based
	return {"month": month, "day": day}


## Player's current rank within their tier (1-based). 0 = unranked (free-market or pre-trade).
## Delegates to _calculate_player_tier_rank with the live season return.
func get_tier_rank() -> int:
	if not is_season_active() or _is_free_market:
		return 0
	# Day 1 PRE_MARKET: 장이 한 번도 열리지 않아 순위 집계 전.
	# get_current_day()는 0-indexed이므로 day 0 = 첫 날 장 시작 전.
	if GameClock.get_current_day() == 0 \
			and GameClock.get_market_state() == GameClock.MarketState.PRE_MARKET:
		return 0
	return _calculate_player_tier_rank(get_season_return_pct())


## Weekly fill count for the current week (resets on on_week_end).
## Used by LeagueScreen to display weekly prize eligibility status.
func get_weekly_trade_count() -> int:
	return _weekly_trade_count


## True when the player has enough season fills for rank eligibility (GDD §4-6).
func is_season_trade_eligible() -> bool:
	return OrderEngine.get_season_trade_count() >= MIN_TRADES_FOR_RANK


## Leaderboard for the given tier: AI + player entries, sorted by return_pct descending.
## [br]tier: target tier (TIER_BRONZE ~ TIER_MASTER_OF_INVESTMENT). Default = player tier.
## [br]from_rank: first rank to return (1-based). Default 1.
## [br]to_rank: last rank to return inclusive (-1 = all). Default -1.
## [br]Returns: Array[Dictionary] — [{rank, nickname, return_pct, prize_preview, is_player}]
## [br]Returns [] in free-market mode or before season start.
## 리더보드 상위 K행 반환. O(K) — pre-sorted 인덱스 + 행당 O(1) 보간.
## 이전 구현(O(N log N) 매 4틱 정렬)을 ADR-008 캐시 방식으로 대체.
func get_leaderboard(tier: int = -99, from_rank: int = 1, to_rank: int = -1) -> Array:
	var target_tier: int = _current_tier if tier == -99 else tier

	if not is_season_active() or target_tier == TIER_FREE_MARKET:
		return []

	# O(1) — 전일 EOD 기준 정렬 인덱스 캐시 조회 (ADR-008, GDD §3-3 재설계)
	var sorted_indices: Array[int] = AiCompetitor.get_sorted_indices(target_tier)
	var ai_count: int = sorted_indices.size()
	var player_in_tier: bool = target_tier == _current_tier
	var player_return: float = get_season_return_pct()

	# O(log N) — 버킷 이진 탐색으로 플레이어 순위 추정 (ADR-008)
	var player_rank: int = 0
	if player_in_tier:
		player_rank = AiCompetitor.estimate_player_rank(player_return)
		player_rank = clampi(player_rank, 1, ai_count + 1)

	var total_count: int = ai_count + (1 if player_in_tier else 0)
	var start_rank: int = clampi(from_rank, 1, total_count)
	var end_rank: int = total_count if to_rank == -1 else clampi(to_rank, 1, total_count)

	var result: Array = []
	for rank: int in range(start_rank, end_rank + 1):
		if player_in_tier and rank == player_rank:
			result.append({
				"rank": rank,
				"nickname": "나",
				"return_pct": player_return,
				"is_player": true,
				"is_grandmaster_ai": false,
				"prize_preview": _prize_for_rank(rank, target_tier),
			})
		else:
			# 플레이어가 이 순위보다 앞이면 AI 위치 = rank - 1, 뒤면 rank - 2
			var ai_pos: int = rank - 1
			if player_in_tier and rank > player_rank:
				ai_pos = rank - 2
			if ai_pos < 0 or ai_pos >= ai_count:
				continue
			var ai_idx: int = sorted_indices[ai_pos]
			var meta: Dictionary = AiCompetitor.get_participant_meta(target_tier, ai_idx)
			# 전일 EOD 기준 수익률 직접 인덱스 접근 O(1) (ADR-008, GDD §3-3 재설계)
			var eod: Array[float] = AiCompetitor.get_eod_snapshot(target_tier)
			var ai_return: float = eod[ai_idx] if ai_idx < eod.size() else 0.0
			result.append({
				"rank": rank,
				"nickname": meta["display_name"],
				"return_pct": ai_return,
				"is_player": false,
				"is_grandmaster_ai": meta.get("is_master_of_investment", false),
				"prize_preview": _prize_for_rank(rank, target_tier),
			})

	return result


## Prize cash amount for a given finish rank in a given tier.
func _prize_for_rank(rank: int, tier: int) -> int:
	if tier < 0 or tier >= TIER_THRESHOLD.size():
		return 0
	return int(float(TIER_THRESHOLD[tier]) * PRIZE_RATE.get(rank, 0.0))


# ── Signal Handlers ──

func _on_season_start() -> void:
	# GameClock fires on_season_start at the very beginning of the season cycle.
	# The player must call start_season() manually via the UI button; this handler
	# ensures internal counters stay consistent if the clock resets.
	_weekly_trade_count = 0


func _on_season_end() -> void:
	# Step ①: WEEK_END bonuses for the final week are handled by _on_week_end
	# which fires before on_season_end per GameClock's tick ordering.

	# Step ②: Cancel all pending orders and refund reserved cash.
	OrderEngine.cancel_all_pending_orders()

	# Step ①-A: TR3 숏 포지션 전량 시즌 종료 청산 (GDD short-selling.md §규칙 9).
	# Must run AFTER order cancellation (reserved cash refunded) and BEFORE
	# PortfolioManager.force_liquidate() so currency math is clean.
	ShortSellingSystem.liquidate_all_for_season_end()

	# Step ①-B: TR4 레버리지 포지션 전량 시즌 종료 청산 (GDD leverage-trading.md §3-5).
	# Runs after TR3 short liquidation and before long position force_liquidate.
	LeverageManager.liquidate_all_positions()

	# Step ②: Forced liquidation — sell all holdings at current price (GDD §3-1).
	PortfolioManager.force_liquidate()

	# Step ③: Determine final rank.
	var season_return_pct: float = get_season_return_pct()
	var season_trade_count: int = OrderEngine.get_season_trade_count()
	var is_rank_eligible: bool = season_trade_count >= MIN_TRADES_FOR_RANK

	var final_rank: int = 0  # 0 = unranked (free-market or ineligible display)
	if not _is_free_market:
		final_rank = _calculate_player_tier_rank(season_return_pct)

	# Step ④: Season prize (cash) — official league only, rank-eligible only.
	if not _is_free_market and is_rank_eligible and final_rank >= 1 and final_rank <= 10:
		_grant_season_prize(final_rank)

	# Step ⑤: Season XP — delegated to XpSystem.
	# is_comeback: first official season after ≥ COMEBACK_BONUS_SEASONS consecutive free-market
	# seasons → XP × COMEBACK_XP_MULTIPLIER (GDD §4-7).
	XpSystem.grant_season_bonus(final_rank, _is_free_market, season_return_pct, season_trade_count, _is_comeback_season)

	# Step ⑥: Check Master ending (GDD §3-1, EC-03).
	var post_liquidation_assets: int = CurrencySystem.get_sim_cash()
	if post_liquidation_assets >= ENDING_THRESHOLD and not _ending_triggered:
		_ending_triggered = true
		on_master_ending_triggered.emit()
		on_season_ended.emit(final_rank, _is_free_market, season_return_pct)
		return

	# Step ⑦: Notify UI (GDD §3-1).
	on_season_ended.emit(final_rank, _is_free_market, season_return_pct)


func _on_week_end() -> void:
	# Award weekly top-return prize if player qualifies (GDD §3-4).
	if not _is_free_market and _weekly_trade_count >= MIN_WEEKLY_TRADES:
		var weekly_return_pct: float = get_weekly_return_pct()
		var player_is_weekly_top: bool = _is_player_weekly_top(weekly_return_pct)
		if player_is_weekly_top:
			var prize: int = int(float(TIER_THRESHOLD[_current_tier]) * WEEKLY_PRIZE_RATE)
			CurrencySystem.sim_add(prize)
			XpSystem.grant_weekly_prize_xp(WEEKLY_PRIZE_XP)

	# Snapshot for next week's return calculation, then reset weekly counter (Q4 decision).
	_last_week_trade_count = _weekly_trade_count
	_weekly_start_capital = PortfolioManager.get_total_assets()
	_weekly_trade_count = 0


func _on_order_filled(_order: Dictionary) -> void:
	_weekly_trade_count += 1


func _on_market_state_changed(
	new_state: GameClock.MarketState, _prev: GameClock.MarketState
) -> void:
	# Check Hangang ending on PRE_MARKET transition (Q3 decision).
	# One check per state transition — not every tick.
	if new_state == GameClock.MarketState.PRE_MARKET and _is_free_market and not _ending_triggered:
		var holdings: Array = PortfolioManager.get_all_holdings()
		var cash: int = CurrencySystem.get_sim_cash()
		# EC-06: both conditions must be true simultaneously.
		if holdings.is_empty() and cash < HANGANG_THRESHOLD:
			_ending_triggered = true
			on_hangang_ending_triggered.emit()


# ── Tier Logic ──

## Assign tier based on total assets (GDD §4-1, EC-01).
func _assign_tier(total_assets: int) -> int:
	# Walk from highest to lowest — first match wins.
	for t: int in range(TIER_COUNT - 1, -1, -1):
		if total_assets >= TIER_THRESHOLD[t]:
			return t
	return TIER_BRONZE  # fallback (should be unreachable if total_assets >= FREE_MARKET_THRESHOLD)


## Estimate player's rank within the current tier (GDD §4-3).
## O(log N) — AiCompetitor 버킷 이진 탐색 위임 (ADR-008). 시즌 종료 시 1회 호출.
func _calculate_player_tier_rank(season_return_pct: float) -> int:
	if _current_tier == TIER_FREE_MARKET:
		return 0
	return AiCompetitor.estimate_player_rank(season_return_pct)


## True if player's weekly return beats all AI in the same tier this week.
## O(1) — 전일 EOD 기준 정렬 인덱스[0] (최고 AI 수익률)과 비교 (ADR-008, GDD §3-3 재설계).
func _is_player_weekly_top(weekly_return_pct: float) -> bool:
	if _current_tier == TIER_FREE_MARKET:
		return false
	var sorted_indices: Array[int] = AiCompetitor.get_sorted_indices(_current_tier)
	if sorted_indices.is_empty():
		return true
	var eod: Array[float] = AiCompetitor.get_eod_snapshot(_current_tier)
	var top_idx: int = sorted_indices[0]
	var top_ai_return: float = eod[top_idx] if top_idx < eod.size() else 0.0
	return weekly_return_pct > top_ai_return


# ── Prize Distribution ──

## Grant cash prize for the player's season rank (GDD §4-6).
func _grant_season_prize(final_rank: int) -> void:
	if _current_tier == TIER_FREE_MARKET or _current_tier < 0 or _current_tier >= TIER_COUNT:
		return
	if not PRIZE_RATE.has(final_rank):
		return
	var rate: float = PRIZE_RATE[final_rank]
	var prize: int = int(float(TIER_THRESHOLD[_current_tier]) * rate)
	CurrencySystem.sim_add(prize)


# ── Participant Count Helper ──

## Build tier → participant count dictionary for AiCompetitor.init_season().
## Ratios from GDD §3-3 — player is excluded (AI count = total - 1).
func _build_participant_counts() -> Dictionary:
	var counts: Dictionary = {}
	var ai_total: int = TOTAL_PARTICIPANTS - 1
	var assigned: int = 0
	for t: int in range(TIER_COUNT - 1):
		counts[t] = int(float(ai_total) * TIER_RATIOS[t])
		assigned += counts[t]
	# 마지막 티어에 나머지 배정 (int() 트런케이션 오차 흡수)
	counts[TIER_COUNT - 1] = ai_total - assigned
	return counts


# ── Serialization ──

## Returns serializable state for the save system.
func get_save_data() -> Dictionary:
	return {
		"current_tier": _current_tier,
		"is_free_market": _is_free_market,
		"season_start_deposit": _season_start_deposit,
		"weekly_start_capital": _weekly_start_capital,
		"weekly_trade_count": _weekly_trade_count,
		"seasons_played": _seasons_played,
	}


## Restores state from save data.
func load_save_data(data: Dictionary) -> void:
	_current_tier = data.get("current_tier", TIER_FREE_MARKET)
	_is_free_market = data.get("is_free_market", true)
	_season_start_deposit = data.get("season_start_deposit", data.get("season_start_capital", 0))  ## 구버전 키 마이그레이션
	_weekly_start_capital = data.get("weekly_start_capital", 0)
	_weekly_trade_count = data.get("weekly_trade_count", 0)
	_seasons_played = data.get("seasons_played", 0)  # 픽션 날짜 복원용 (EC: 구버전 세이브 → 0)


## Resets all season state. Called by GameMain (new game) and tests (before_each).
func reset() -> void:
	_current_tier = TIER_FREE_MARKET
	_is_free_market = true
	_season_start_deposit = 0
	_weekly_start_capital = 0
	_weekly_trade_count = 0
	_last_week_trade_count = 0
	_ending_triggered = false
	_seasons_played = 0
