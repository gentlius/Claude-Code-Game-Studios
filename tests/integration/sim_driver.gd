## SimDriver — Drives game simulation N days without real-time.
## Lives entirely in tests/integration/. Zero modifications to src/.
## To remove test mode: delete tests/integration/ and revert .gutconfig.json.
##
## Coupling points (intentional, documented):
##   - GameClock._process_tick(): only internal API used; drives ticks instantly.
##   - All other calls use public APIs (reset, confirm_*, submit_*).
extends Node

# ── Trade Config ──
# Deterministic trade plan — same stocks/quantities every test run.

const _STOCK_A: String = "KSF"  ## Buy on day 0
const _STOCK_B: String = "STC"  ## Buy on day 5

var _daily_snapshots: Array[Dictionary] = []


# ── Public API ──

## Simulate n full trading days. Returns end-of-day snapshot per day.
## await required — uses process_frame for deferred week/season signals.
func simulate_days(n: int) -> Array[Dictionary]:
	_daily_snapshots.clear()
	for d: int in range(n):
		var snap: Dictionary = await _simulate_one_day(d)
		_daily_snapshots.append(snap)
	return _daily_snapshots.duplicate()


## Access snapshots after simulate_days().
func get_daily_snapshots() -> Array[Dictionary]:
	return _daily_snapshots.duplicate()


## Reset every autoload to a cold-start state (simulates process quit + relaunch).
## Uses only reset() public APIs that already exist in production code.
## Call this before SaveSystem.load_slot() to simulate a full restart.
func reset_all_for_restart() -> void:
	XpSystem.reset()
	SkillTree.reset()
	SeasonManager.reset()
	PortfolioManager.reset()
	CurrencySystem.reset()
	GameClock.reset()
	AiCompetitor.reset()
	NewsEventSystem.reset()
	OrderEngine.reset()
	PriceEngine.reset()


# ── Internal ──

func _simulate_one_day(day_idx: int) -> Dictionary:
	# Open market: PRE_MARKET → MARKET_OPEN
	GameClock.confirm_market_open()

	# Deterministic trade plan
	match day_idx:
		0:
			_place_market_buy(_STOCK_A, 10)
		5:
			_place_market_buy(_STOCK_B, 5)

	# Advance all ticks for the trading day.
	# GameClock._process_tick() is the only internal-API touch point in this file.
	# The last tick call fires _end_trading_day() → MARKET_CLOSED + on_market_close
	# synchronously. Week/season-end signals are deferred (see below).
	for _i: int in GameClock.TICKS_PER_DAY:
		GameClock._process_tick()

	# on_market_close has already fired. Deferred signals need process frames.
	var day: int = GameClock.get_current_day()
	var is_week_end: bool = (day % GameClock.DAYS_PER_WEEK == GameClock.DAYS_PER_WEEK - 1)
	var is_season_end: bool = is_week_end and \
		(GameClock.get_current_week() >= GameClock.WEEKS_PER_SEASON - 1)

	if is_week_end:
		await get_tree().process_frame   # _emit_week_end_deferred fires → WEEK_END
	if is_season_end:
		await get_tree().process_frame   # _emit_season_end_deferred fires → SEASON_END

	# Snapshot BEFORE advancing (captures end-of-day market state)
	var snap: Dictionary = _collect_end_of_day_snapshot(day_idx)

	# Advance clock to next day's PRE_MARKET (or new season for SEASON_END)
	GameClock.confirm_transition()

	return snap


func _place_market_buy(stock_id: String, qty: int) -> void:
	var price: int = PriceEngine.get_current_price(stock_id)
	if price <= 0:
		return
	var cash_needed: int = price * qty
	if CurrencySystem.get_sim_cash() < cash_needed:
		push_warning("SimDriver: insufficient cash for %s x%d (need %d, have %d)" % [
			stock_id, qty, cash_needed, CurrencySystem.get_sim_cash()])
		return
	var result: Dictionary = OrderEngine.submit_market_order("BUY", stock_id, qty)
	if result.get("status") != "FILLED":
		push_warning("SimDriver: buy %s x%d rejected — %s" % [
			stock_id, qty, result.get("reject_reason", "unknown")])


func _collect_end_of_day_snapshot(day_idx: int) -> Dictionary:
	return {
		"sim_day_idx": day_idx,
		"clock_day": GameClock.get_current_day(),
		"clock_week": GameClock.get_current_week(),
		"sim_cash": CurrencySystem.get_sim_cash(),
		"total_assets": PortfolioManager.get_total_assets(),
		"return_rate": PortfolioManager.get_return_rate(),
		"xp_total": XpSystem.get_total_xp(),
		"xp_level": XpSystem.get_current_level(),
		"season_return_pct": SeasonManager.get_season_return_pct(),
		"holding_count": PortfolioManager.get_holding_count(),
		"daily_xp": XpSystem.get_daily_xp_breakdown(),
	}
