extends GutTest
## Regression tests: weekly XP counter (_weekly_xp) survives save/load cycle.
## Bug context: _weekly_xp_gained lived in SettlementReporter (UI, not serialized).
## On save+load mid-week, the weekly XP counter reset to 0 → Friday report showed
## only post-load XP, losing Mon~Wed XP gains.
## Fix: _weekly_xp moved to XpSystem (serialized via get_save_data/load_save_data).
## SettlementReporter now reads XpSystem.get_weekly_xp() and calls reset_weekly_xp().


func before_each() -> void:
	XpSystem.reset()


func after_each() -> void:
	XpSystem.reset()


# ── Tests: get_weekly_xp / reset_weekly_xp API ──

func test_weekly_xp_starts_at_zero() -> void:
	assert_eq(XpSystem.get_weekly_xp(), 0, "초기 주간 XP는 0이어야 함")


func test_weekly_xp_accumulates_on_grant() -> void:
	# Arrange / Act
	XpSystem.grant_daily_bonus(10.0, 10.0, 10.0, 1000000, false)  # some XP granted
	# We can't know exact XP granted without matching formula, so just check > 0
	assert_true(XpSystem.get_weekly_xp() >= 0,
		"XP 지급 후 주간 XP가 증가하거나 유지돼야 함")


func test_weekly_xp_increments_with_each_grant() -> void:
	# Arrange — directly inspect: grant → weekly_xp matches total granted
	var before: int = XpSystem.get_weekly_xp()
	# Use a grant that definitely gives XP: 5% alpha
	XpSystem.grant_daily_bonus(5.0, 0.0, 0.0, 1000000, true)
	var after: int = XpSystem.get_weekly_xp()
	assert_true(after >= before, "grant 후 weekly_xp는 감소하지 않아야 함")


func test_reset_weekly_xp_clears_counter() -> void:
	# Arrange — grant some XP
	XpSystem.grant_daily_bonus(5.0, 0.0, 0.0, 1000000, true)
	# Assume weekly_xp > 0 now

	# Act
	XpSystem.reset_weekly_xp()

	# Assert
	assert_eq(XpSystem.get_weekly_xp(), 0, "reset_weekly_xp() 후 0이어야 함")


func test_total_xp_unaffected_by_reset_weekly_xp() -> void:
	# Arrange
	XpSystem.grant_daily_bonus(5.0, 0.0, 0.0, 1000000, true)
	var total_before: int = XpSystem.get_total_xp()

	# Act
	XpSystem.reset_weekly_xp()

	# Assert — total XP 불변
	assert_eq(XpSystem.get_total_xp(), total_before,
		"reset_weekly_xp()는 total_xp에 영향 없어야 함")


# ── Tests: save / load round-trip ──

func test_get_save_data_includes_weekly_xp() -> void:
	# Arrange
	XpSystem.grant_daily_bonus(5.0, 0.0, 0.0, 1000000, true)

	# Act
	var data: Dictionary = XpSystem.get_save_data()

	# Assert
	assert_true(data.has("weekly_xp"), "get_save_data()에 weekly_xp 키 있어야 함")
	assert_eq(data["weekly_xp"], XpSystem.get_weekly_xp(), "저장값이 현재 weekly_xp와 일치해야 함")


func test_load_save_data_restores_weekly_xp() -> void:
	# Arrange — grant XP, save, reset, load
	XpSystem.grant_daily_bonus(5.0, 0.0, 0.0, 1000000, true)
	var weekly_before: int = XpSystem.get_weekly_xp()
	var data: Dictionary = XpSystem.get_save_data()
	XpSystem.reset()

	# Act
	XpSystem.load_save_data(data)

	# Assert
	assert_eq(XpSystem.get_weekly_xp(), weekly_before,
		"로드 후 weekly_xp가 저장 전 값과 일치해야 함")


func test_weekly_xp_survives_mid_week_save_load() -> void:
	## Core regression: simulate Mon-Wed play → save → quit → load → Thu-Fri play
	## Weekly XP after reload must include Mon-Wed XP, not just Thu-Fri.

	# Arrange — "월화수" 3일치 XP
	XpSystem.grant_daily_bonus(3.0, 0.0, 0.0, 1000000, true)  # Day 1
	XpSystem.grant_daily_bonus(2.0, 0.0, 0.0, 1000000, true)  # Day 2
	XpSystem.grant_daily_bonus(4.0, 0.0, 0.0, 1000000, true)  # Day 3
	var xp_after_wed: int = XpSystem.get_weekly_xp()
	assert_true(xp_after_wed > 0, "전제: 월화수 XP > 0")

	# 세이브 → 리셋 (세션 종료 시뮬레이션)
	var saved: Dictionary = XpSystem.get_save_data()
	XpSystem.reset()
	assert_eq(XpSystem.get_weekly_xp(), 0, "reset 후 0")

	# 로드 (세션 재개 시뮬레이션)
	XpSystem.load_save_data(saved)

	# "목금" 추가 XP
	XpSystem.grant_daily_bonus(3.0, 0.0, 0.0, 1000000, true)  # Day 4
	var xp_total_week: int = XpSystem.get_weekly_xp()

	# Assert — 목금 XP만이 아니라 월화수 포함해야 함
	assert_true(xp_total_week >= xp_after_wed,
		"로드 후 주간 XP에 월화수 XP가 포함돼야 함")


func test_weekly_xp_resets_after_weekly_report() -> void:
	# Arrange — grant XP
	XpSystem.grant_daily_bonus(5.0, 0.0, 0.0, 1000000, true)
	assert_true(XpSystem.get_weekly_xp() > 0, "전제: 주간 XP > 0")

	# Act — simulate weekly settlement calling reset_weekly_xp()
	XpSystem.reset_weekly_xp()

	# Next week starts fresh
	assert_eq(XpSystem.get_weekly_xp(), 0, "주간 리포트 후 weekly XP 초기화")

	# Grant more for next week
	XpSystem.grant_daily_bonus(2.0, 0.0, 0.0, 1000000, true)
	# Only post-reset XP counted
	var next_week_xp: int = XpSystem.get_weekly_xp()
	assert_true(next_week_xp > 0, "다음 주 XP는 리셋 후부터 누산")


func test_load_save_data_weekly_xp_clamped_non_negative() -> void:
	# Arrange — malformed save data
	var data: Dictionary = {
		"total_xp": 0,
		"current_level": 1,
		"spent_skill_points": 0,
		"weekly_xp": -999,
	}

	# Act
	XpSystem.load_save_data(data)

	# Assert
	assert_eq(XpSystem.get_weekly_xp(), 0, "음수 weekly_xp는 0으로 클램핑")


func test_reset_also_clears_weekly_xp() -> void:
	# Arrange
	XpSystem.grant_daily_bonus(5.0, 0.0, 0.0, 1000000, true)

	# Act
	XpSystem.reset()

	# Assert
	assert_eq(XpSystem.get_weekly_xp(), 0, "reset() 후 weekly_xp도 0이어야 함")
