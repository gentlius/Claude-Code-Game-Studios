## DataSnapshot — Captures all verifiable game state from every autoload system.
## Compares before/after save-load to detect any internal state not fully persisted.
## Lives entirely in tests/integration/. Zero modifications to src/.
##
## Verification scope — "화면에 출력하는 모든 수치" (all numbers shown on screen):
##   PortfolioView: cash, total_assets, return_rate, per-holding values
##   StockListPanel: current price, prev_close, change%, change amount
##   StatusBar: day, week, cash, total_assets
##   Daily settlement: XP breakdown, return%, alpha%
##   Weekly settlement: weekly return%, trade count
##   League screen: tier, rank, leaderboard top-10
##   XP bar: total_xp, level, skill_points
extends RefCounted

const FLOAT_TOLERANCE: float = 0.001  ## Max allowed float diff (rounding noise)
const MAX_LEADERBOARD_ROWS: int = 10  ## League screen typically shows top 10


# ── Public API ──

## Capture a complete snapshot of every autoload's verifiable state.
func capture() -> Dictionary:
	return {
		# ── GameClock ──
		"clock_day":  GameClock.get_current_day(),
		"clock_week": GameClock.get_current_week(),

		# ── CurrencySystem ──
		"sim_cash":       CurrencySystem.get_sim_cash(),
		"deposit":        CurrencySystem.get_deposit(),
		"season_active":  GameClock.is_season_active(),

		# ── PortfolioManager (all held fields) ──
		"portfolio_total_assets": PortfolioManager.get_total_assets(),
		"portfolio_return_rate":  PortfolioManager.get_return_rate(),
		"portfolio_holding_count": PortfolioManager.get_holding_count(),
		"portfolio_holdings":     _snapshot_holdings(),
		"portfolio_initial_seed": PortfolioManager._initial_seed,
		"portfolio_tx_count":     PortfolioManager.get_transaction_history(9999).size(),

		# ── XpSystem (all saved fields + computed display values) ──
		"xp_total":               XpSystem.get_total_xp(),
		"xp_level":               XpSystem.get_current_level(),
		"xp_spent_skill_points":  XpSystem._spent_skill_points,
		"xp_prev_close_assets":   XpSystem._prev_close_assets,
		"xp_last_return_pct":     XpSystem._last_daily_return_pct,
		"xp_last_market_pct":     XpSystem._last_market_return_pct,
		"xp_last_alpha_pct":      XpSystem._last_alpha_pct,
		"xp_daily_breakdown":     XpSystem.get_daily_xp_breakdown(),
		"xp_available_sp":        XpSystem.get_available_skill_points(),

		# ── SkillTree ──
		"skills_unlocked": SkillTree._unlocked_skills.keys(),

		# ── SeasonManager ──
		"season_tier":              SeasonManager.get_current_tier(),
		"season_is_free_market":    SeasonManager.get_is_free_market(),
		"season_return_pct":        SeasonManager.get_season_return_pct(),
		"season_weekly_return_pct": SeasonManager.get_weekly_return_pct(),
		"season_start_deposit":     SeasonManager._season_start_deposit,
		"season_weekly_start_cap":  SeasonManager._weekly_start_capital,
		"season_weekly_trades":     SeasonManager.get_weekly_trade_count(),
		"season_seasons_played":    SeasonManager._seasons_played,

		# ── PriceEngine (every stock's current price + prev_close) ──
		"prices": _snapshot_prices(),

		# ── AiCompetitor (via leaderboard) ──
		"leaderboard": _snapshot_leaderboard(),
	}


## Compare two snapshots. Returns Array of discrepancy dicts.
## Empty array = perfectly consistent (pass). Any entry = failure to investigate.
func diff(before: Dictionary, after: Dictionary) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	_compare_recursive(before, after, "", issues)
	return issues


## Human-readable diff report for error output.
func format_diff(issues: Array[Dictionary]) -> String:
	if issues.is_empty():
		return "✅ 모든 값 일치 — save/load 완벽 재현"
	var lines: Array[String] = ["❌ Save/Load 불일치 %d건:" % issues.size()]
	for issue: Dictionary in issues:
		lines.append("  [%s] %s" % [issue.get("type", "?"), issue.get("field", "?")])
		if issue.has("before"):
			lines.append("    저장 전: %s" % str(issue["before"]))
		if issue.has("after"):
			lines.append("    로드 후: %s" % str(issue["after"]))
	return "\n".join(lines)


## Serialise a snapshot to a JSON string for writing to disk.
func to_json(snap: Dictionary) -> String:
	return JSON.stringify(snap, "  ")


# ── Internal ──

func _snapshot_holdings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for h: Dictionary in PortfolioManager.get_all_holdings():
		result.append({
			"stock_id":       h["stock_id"],
			"quantity":       h["quantity"],
			"avg_buy_price":  h["avg_buy_price"],
			"total_invested": h["total_invested"],
			"current_value":  h["current_value"],
			"unrealized_pnl": h["unrealized_pnl"],
		})
	# Sort by stock_id for stable comparison
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["stock_id"] < b["stock_id"]
	)
	return result


func _snapshot_prices() -> Dictionary:
	var result: Dictionary = {}
	for sid: String in StockDatabase.get_all_stock_ids():
		result[sid] = {
			"current":    PriceEngine.get_current_price(sid),
			"prev_close": PriceEngine.get_daily_limits(sid).get("prev_close", 0),
		}
	return result


func _snapshot_leaderboard() -> Array:
	if SeasonManager.get_is_free_market():
		return []
	return SeasonManager.get_leaderboard(
		SeasonManager.get_current_tier(), 1, MAX_LEADERBOARD_ROWS
	)


func _compare_recursive(
	before: Variant, after: Variant, path: String, issues: Array[Dictionary]
) -> void:
	if typeof(before) != typeof(after):
		issues.append({
			"field": path, "type": "TYPE_MISMATCH",
			"before": before, "after": after,
		})
		return

	match typeof(before):
		TYPE_DICTIONARY:
			var b: Dictionary = before as Dictionary
			var a: Dictionary = after as Dictionary
			for key: Variant in b:
				var child_path: String = (path + "." if path else "") + str(key)
				if not a.has(key):
					issues.append({"field": child_path, "type": "KEY_MISSING_AFTER"})
				else:
					_compare_recursive(b[key], a[key], child_path, issues)
			for key: Variant in a:
				if not b.has(key):
					var child_path: String = (path + "." if path else "") + str(key)
					issues.append({"field": child_path, "type": "KEY_MISSING_BEFORE"})

		TYPE_ARRAY:
			var b_arr: Array = before as Array
			var a_arr: Array = after as Array
			if b_arr.size() != a_arr.size():
				issues.append({
					"field": path, "type": "ARRAY_SIZE_MISMATCH",
					"before": b_arr.size(), "after": a_arr.size(),
				})
				return
			for i: int in b_arr.size():
				_compare_recursive(b_arr[i], a_arr[i], "%s[%d]" % [path, i], issues)

		TYPE_FLOAT:
			var diff_val: float = absf(float(before) - float(after))
			if diff_val > FLOAT_TOLERANCE:
				issues.append({
					"field": path, "type": "VALUE_MISMATCH",
					"before": before, "after": after,
					"diff": diff_val,
				})

		_:
			if before != after:
				issues.append({
					"field": path, "type": "VALUE_MISMATCH",
					"before": before, "after": after,
				})
