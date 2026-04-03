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

# ── Config — Tier Thresholds (GDD §3-2, Tuning Knob §7-1) ──
## Entry capital threshold for each tier (index = tier constant).
## Designer adjustable: align with narrative & daily return targets.
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
## rank key = 1-indexed finish position within the tier.
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
@export var WEEKLY_PRIZE_RATE: float = 0.02
## Minimum weekly fills to qualify for the weekly prize.
@export var MIN_WEEKLY_TRADES: int = 2
## Most-trades prize rate (× tier entry threshold).
@export var MOST_TRADES_PRIZE_RATE: float = 0.01

# ── Config — Season Structure (GDD §7-1) ──
## Minimum season-level fills to qualify for prize payouts.
@export var MIN_TRADES_FOR_RANK: int = 5
## Total simulated participants (display only — AI object count is in ai-competitor.md).
@export var TOTAL_PARTICIPANTS: int = 20_000

# ── Config — Free Market & Endings (GDD §7-4) ──
## Assets below this threshold at season start → free-market mode.
@export var FREE_MARKET_THRESHOLD: int = 1_000_000
## Cash below this with no holdings → Hangang ending (free-market only).
@export var HANGANG_THRESHOLD: int = 10_000
## Total assets at/above this at season end → Master ending.
@export var ENDING_THRESHOLD: int = 100_000_000_000

# ── State ──

var _current_tier: int = TIER_FREE_MARKET
var _is_free_market: bool = true
var _season_start_capital: int = 0
var _weekly_start_capital: int = 0

## Accumulated fill count for the current week (reset each week-end).
var _weekly_trade_count: int = 0

## Snapshot of _weekly_trade_count at the most-recently completed week (for award logic).
var _last_week_trade_count: int = 0

## Whether an ending has already been triggered this session (prevents double-fire).
var _ending_triggered: bool = false

# ── Lifecycle ──

func _ready() -> void:
	GameClock.on_season_start.connect(_on_season_start)
	GameClock.on_season_end.connect(_on_season_end)
	GameClock.on_week_end.connect(_on_week_end)
	GameClock.on_market_state_changed.connect(_on_market_state_changed)
	OrderEngine.on_order_filled.connect(_on_order_filled)


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

	_season_start_capital = total_assets
	_weekly_start_capital = total_assets
	_weekly_trade_count = 0
	_last_week_trade_count = 0
	_ending_triggered = false

	# Determine mode and tier (GDD §3-1, §4-1)
	if total_assets < FREE_MARKET_THRESHOLD:
		_current_tier = TIER_FREE_MARKET
		_is_free_market = true
	else:
		_current_tier = _assign_tier(total_assets)
		_is_free_market = false
		on_tier_assigned.emit(_current_tier, get_tier_name(_current_tier))

		# Initialise AI competitors (GDD §3-3 AI contract)
		var seed_val: int = randi()
		var participant_counts: Dictionary = _build_participant_counts()
		AiCompetitor.init_season(_current_tier, participant_counts, seed_val)

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
## Includes reserved_cash in sim_total_assets.
func get_season_return_pct() -> float:
	if _season_start_capital <= 0:
		return 0.0
	var total_assets: int = PortfolioManager.get_total_assets()
	return float(total_assets - _season_start_capital) / float(_season_start_capital) * 100.0


## Weekly return rate in percent (GDD §4-4).
func get_weekly_return_pct() -> float:
	if _weekly_start_capital <= 0:
		return 0.0
	var total_assets: int = PortfolioManager.get_total_assets()
	return float(total_assets - _weekly_start_capital) / float(_weekly_start_capital) * 100.0


## Season start capital snapshot.
func get_season_start_capital() -> int:
	return _season_start_capital


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

	# Step ②: Forced liquidation — sell all holdings at current price (GDD §3-1).
	_force_liquidate_all()

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
	XpSystem.grant_season_bonus(final_rank, _is_free_market, season_return_pct, season_trade_count)

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
			XpSystem._grant_xp(50, "weekly_prize")

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
		var holdings: Array = PortfolioManager.get_holdings()
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
## Delegates to AiCompetitor for the actual distribution.
func _calculate_player_tier_rank(season_return_pct: float) -> int:
	if _current_tier == TIER_FREE_MARKET:
		return 0
	# AiCompetitor provides sorted return pcts for the same tier.
	# Count how many AI participants in the same tier beat the player's return_pct.
	var tier_returns: Array[float] = AiCompetitor.get_all_return_pcts(_current_tier)
	var players_beaten: int = 0
	for ai_return: float in tier_returns:
		if ai_return < season_return_pct:
			players_beaten += 1
	# Rank = total participants - beaten opponents (1-indexed)
	var tier_participant_count: int = tier_returns.size() + 1  # +1 for the player
	return tier_participant_count - players_beaten


## True if player's weekly return beats all AI in the same tier this week.
func _is_player_weekly_top(weekly_return_pct: float) -> bool:
	if _current_tier == TIER_FREE_MARKET:
		return false
	var tier_returns: Array[float] = AiCompetitor.get_all_return_pcts(_current_tier)
	for ai_return: float in tier_returns:
		if ai_return >= weekly_return_pct:
			return false
	return true


# ── Liquidation ──

## Force-sell all holdings at current price (GDD §3-1 step ②).
func _force_liquidate_all() -> void:
	var holdings: Array = PortfolioManager.get_all_holdings()
	for holding: Dictionary in holdings:
		var stock_id: String = holding["stock_id"]
		var quantity: int = holding["quantity"]
		var price: int = PriceEngine.get_current_price(stock_id)
		var proceeds: int = price * quantity
		CurrencySystem.sim_add(proceeds)
		PortfolioManager.remove_holding(stock_id, quantity, price)


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
	## Tier participant ratios (GDD §3-3). Index = tier constant.
	var TIER_RATIOS: Array[float] = [
		0.38, 0.20, 0.13, 0.09, 0.06,
		0.045, 0.035, 0.025, 0.015, 0.01, 0.005,
	]
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
		"season_start_capital": _season_start_capital,
		"weekly_start_capital": _weekly_start_capital,
		"weekly_trade_count": _weekly_trade_count,
	}


## Restores state from save data.
func load_save_data(data: Dictionary) -> void:
	_current_tier = data.get("current_tier", TIER_FREE_MARKET)
	_is_free_market = data.get("is_free_market", true)
	_season_start_capital = data.get("season_start_capital", 0)
	_weekly_start_capital = data.get("weekly_start_capital", 0)
	_weekly_trade_count = data.get("weekly_trade_count", 0)
