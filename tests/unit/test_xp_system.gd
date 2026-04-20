extends GutTest
## Unit tests for XpSystem — see design/gdd/xp-system.md

# ── Helpers ──

func before_each() -> void:
	# Reset XP state before each test
	XpSystem._total_xp = 0
	XpSystem._current_level = 1
	XpSystem._spent_skill_points = 0
	XpSystem._daily_has_trade = false
	XpSystem._prev_close_assets = 0


# ── AC-1: Trade fills do NOT grant XP ──

func test_trade_fill_does_not_grant_xp() -> void:
	var xp_before: int = XpSystem.get_total_xp()
	# Simulate order filled
	XpSystem._on_order_filled({})
	var xp_after: int = XpSystem.get_total_xp()
	assert_eq(xp_after - xp_before, 0, "Trade fill should not grant XP")


# ── AC-2: Daily bonus XP by alpha bracket (GDD F1) ──
# _calculate_daily_xp() now takes alpha_pct (player return − market return)

func test_daily_xp_alpha_large_loss() -> void:
	var xp: int = XpSystem._calculate_daily_xp(-2.0)
	assert_eq(xp, 15, "alpha -2%: 30 * 0.5 = 15")


func test_daily_xp_alpha_small_loss() -> void:
	var xp: int = XpSystem._calculate_daily_xp(-0.5)
	assert_eq(xp, 30, "alpha -0.5%: 30 * 1.0 = 30")


func test_daily_xp_alpha_zero() -> void:
	var xp: int = XpSystem._calculate_daily_xp(0.0)
	assert_eq(xp, 45, "alpha 0%: 30 * 1.5 = 45")


func test_daily_xp_alpha_moderate() -> void:
	var xp: int = XpSystem._calculate_daily_xp(2.0)
	assert_eq(xp, 60, "alpha 2%: 30 * 2.0 = 60")


func test_daily_xp_alpha_excellent() -> void:
	var xp: int = XpSystem._calculate_daily_xp(3.0)
	assert_eq(xp, 90, "alpha 3%: 30 * 3.0 = 90")


# ── AC-2: Alpha state stored on market close ──

func test_daily_xp_alpha_state_on_market_close() -> void:
	# Arrange — empty _stock_states → market_avg_return = 0.0
	# player return = +2% → alpha = +2% → multiplier 2.0 → 60 XP
	XpSystem._daily_has_trade = true
	XpSystem._prev_close_assets = 1000000
	PortfolioManager._cached_total_assets = 1020000  # +2%
	PriceEngine._stock_states.clear()  # no stocks → market_avg_return = 0.0

	# Act
	XpSystem._on_market_close()

	# Assert
	assert_almost_eq(XpSystem._last_daily_return_pct, 2.0, 0.01, "Player return = +2%")
	assert_almost_eq(XpSystem._last_market_return_pct, 0.0, 0.01, "Market return = 0% (no stocks)")
	assert_almost_eq(XpSystem._last_alpha_pct, 2.0, 0.01, "Alpha = +2%")
	assert_eq(XpSystem.get_total_xp(), 60, "alpha +2% (1~3% bracket) → 30 * 2.0 = 60 XP")


func test_daily_xp_alpha_positive_when_cash_held_in_down_market() -> void:
	# Arrange — player holds cash (total assets flat), market falls → alpha positive
	# Inject one stock with prev_day_close=10000, current_price=9000 → market -10%
	XpSystem._daily_has_trade = true
	XpSystem._prev_close_assets = 1000000
	PortfolioManager._cached_total_assets = 1000000  # 0% (full cash)
	PriceEngine._stock_states["__TEST__"] = {
		"prev_day_close": 10000, "current_price": 9000
	}

	# Act
	XpSystem._on_market_close()

	# Assert — alpha = 0% - (-10%) = +10% → max multiplier 3.0
	assert_true(XpSystem._last_alpha_pct > 0.0, "Holding cash in down market → positive alpha")
	assert_eq(XpSystem.get_total_xp(), 90, "alpha > +3% → 30 * 3.0 = 90 XP")

	# Cleanup
	PriceEngine._stock_states.erase("__TEST__")


# ── AC-3: No trades → no daily XP ──

func test_no_trades_no_daily_xp() -> void:
	XpSystem._daily_has_trade = false
	XpSystem._on_market_close()
	assert_eq(XpSystem.get_total_xp(), 0, "No trades → no daily XP")


# ── AC-4: Season bonus XP ──

func test_season_xp_rank_1() -> void:
	var breakdown: Dictionary = XpSystem._calculate_season_xp(1, 30.0)
	# 200 + 500 + floor(30 * 10) = 200 + 500 + 300 = 1000
	assert_eq(breakdown["xp"], 1000, "Rank 1, +30% return")
	assert_eq(breakdown["rank_bonus"], 500, "Rank 1 rank_bonus")
	assert_eq(breakdown["return_bonus"], 300, "Rank 1 return_bonus")


func test_season_xp_rank_3() -> void:
	var breakdown: Dictionary = XpSystem._calculate_season_xp(3, 25.0)
	# 200 + 250 + 250 = 700
	assert_eq(breakdown["xp"], 700, "Rank 3, +25% return")


func test_season_xp_negative_return() -> void:
	var breakdown: Dictionary = XpSystem._calculate_season_xp(6, -10.0)
	# 200 + 50 + 0 = 250
	assert_eq(breakdown["xp"], 250, "Rank 6+, negative return → return_bonus = 0")
	assert_eq(breakdown["return_bonus"], 0, "Negative return → return_bonus = 0")


# ── AC-5: Level-up + skill point ──

func test_level_up_grants_skill_point() -> void:
	# Level 1→2 requires 100 XP
	XpSystem._grant_xp(100, "test")
	assert_eq(XpSystem.get_current_level(), 2, "Should be level 2")
	assert_eq(XpSystem.get_total_skill_points(), 1, "Level 2 = 1 skill point")
	assert_eq(XpSystem.get_available_skill_points(), 1, "1 available skill point")


# ── AC-6: Multi level-up ──

func test_multi_level_up() -> void:
	# Grant enough XP for multiple level-ups
	# Lv1→2: 100, Lv2→3: 283, total for Lv3 = 383
	XpSystem._grant_xp(400, "test")
	assert_eq(XpSystem.get_current_level(), 3, "Should be level 3")
	assert_eq(XpSystem.get_total_skill_points(), 2, "Level 3 = 2 skill points")


# ── AC-7: XP persists across season reset (no reset logic in XP) ──

func test_xp_persists() -> void:
	XpSystem._grant_xp(500, "test")
	var xp_before: int = XpSystem.get_total_xp()
	var level_before: int = XpSystem.get_current_level()
	# Season start should NOT reset XP/level
	XpSystem._on_season_start()
	assert_eq(XpSystem.get_total_xp(), xp_before, "XP should persist")
	assert_eq(XpSystem.get_current_level(), level_before, "Level should persist")


# ── AC-8: on_level_up signal fires exactly once per level ──

func test_level_up_signal_count() -> void:
	var counter: Array[int] = [0]
	var callback: Callable = func(_new_level: int, _sp: int) -> void:
		counter[0] += 1
	XpSystem.on_level_up.connect(callback)

	# Grant 400 XP → levels 2 and 3 (2 level-ups)
	XpSystem._grant_xp(400, "test")
	assert_eq(counter[0], 2, "Should fire on_level_up twice for 2 level-ups")

	XpSystem.on_level_up.disconnect(callback)


# ── Level curve formula ──

func test_level_curve_values() -> void:
	# Lv1→2: floor(100 * 1^1.5) = 100
	assert_eq(XpSystem._cumulative_xp_for_level(2), 100, "Lv2 cumulative = 100")
	# Lv1→3: 100 + floor(100 * 2^1.5) = 100 + 282 = 382
	# Note: 2^1.5 = 2.828..., floor(282.8) = 282
	var lv3: int = XpSystem._cumulative_xp_for_level(3)
	assert_true(lv3 >= 380 and lv3 <= 385, "Lv3 cumulative ~382")


# ── Serialization ──

func test_save_load() -> void:
	XpSystem._grant_xp(500, "test")
	XpSystem._spent_skill_points = 1
	var data: Dictionary = XpSystem.get_save_data()

	# Reset and reload
	XpSystem._total_xp = 0
	XpSystem._current_level = 1
	XpSystem._spent_skill_points = 0
	XpSystem.load_save_data(data)

	assert_eq(XpSystem.get_total_xp(), 500, "XP should be restored")
	assert_eq(XpSystem.get_current_level(), 3, "Level should be restored")
	assert_eq(XpSystem._spent_skill_points, 1, "Spent points should be restored")


# ── Edge case: negative XP clamped ──

func test_negative_xp_clamped() -> void:
	XpSystem.load_save_data({"total_xp": -100, "current_level": -5, "spent_skill_points": -1})
	assert_eq(XpSystem.get_total_xp(), 0, "Negative XP clamped to 0")
	assert_eq(XpSystem.get_current_level(), 1, "Negative level clamped to 1")
	assert_eq(XpSystem._spent_skill_points, 0, "Negative points clamped to 0")
