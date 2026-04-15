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
	# Arrange / Act — grant_weekly_prize_xp → _grant_xp → _weekly_xp++
	XpSystem.grant_weekly_prize_xp(30)

	# Assert
	assert_eq(XpSystem.get_weekly_xp(), 30, "주간 XP 30 누산")


func test_weekly_xp_increments_with_each_grant() -> void:
	# Arrange
	XpSystem.grant_weekly_prize_xp(20)
	XpSystem.grant_weekly_prize_xp(15)

	# Assert
	assert_eq(XpSystem.get_weekly_xp(), 35, "두 번 누산: 20 + 15 = 35")


func test_reset_weekly_xp_clears_counter() -> void:
	# Arrange
	XpSystem.grant_weekly_prize_xp(50)
	assert_eq(XpSystem.get_weekly_xp(), 50, "전제: 50 누산")

	# Act
	XpSystem.reset_weekly_xp()

	# Assert
	assert_eq(XpSystem.get_weekly_xp(), 0, "reset_weekly_xp() 후 0이어야 함")


func test_total_xp_unaffected_by_reset_weekly_xp() -> void:
	# Arrange
	XpSystem.grant_weekly_prize_xp(50)
	var total_before: int = XpSystem.get_total_xp()

	# Act
	XpSystem.reset_weekly_xp()

	# Assert — total XP 불변
	assert_eq(XpSystem.get_total_xp(), total_before,
		"reset_weekly_xp()는 total_xp에 영향 없어야 함")


# ── Tests: save / load round-trip ──

func test_get_save_data_includes_weekly_xp() -> void:
	# Arrange
	XpSystem.grant_weekly_prize_xp(40)

	# Act
	var data: Dictionary = XpSystem.get_save_data()

	# Assert
	assert_true(data.has("weekly_xp"), "get_save_data()에 weekly_xp 키 있어야 함")
	assert_eq(data["weekly_xp"], 40, "저장값이 현재 weekly_xp와 일치해야 함")


func test_load_save_data_restores_weekly_xp() -> void:
	# Arrange — grant XP, save, reset, load
	XpSystem.grant_weekly_prize_xp(40)
	var data: Dictionary = XpSystem.get_save_data()
	XpSystem.reset()
	assert_eq(XpSystem.get_weekly_xp(), 0, "reset 후 0")

	# Act
	XpSystem.load_save_data(data)

	# Assert
	assert_eq(XpSystem.get_weekly_xp(), 40,
		"로드 후 weekly_xp 40 복원")


func test_weekly_xp_survives_mid_week_save_load() -> void:
	## Core regression: simulate Mon-Wed play → save → quit → load → Thu-Fri play
	## Weekly XP after reload must include Mon-Wed XP, not just Thu-Fri.

	# "월화수" 3일치 XP
	XpSystem.grant_weekly_prize_xp(20)  # Day 1
	XpSystem.grant_weekly_prize_xp(15)  # Day 2
	XpSystem.grant_weekly_prize_xp(25)  # Day 3
	var xp_after_wed: int = XpSystem.get_weekly_xp()  # 60
	assert_eq(xp_after_wed, 60, "전제: 월화수 XP = 60")

	# 세이브 → 리셋 (세션 종료 시뮬레이션)
	var saved: Dictionary = XpSystem.get_save_data()
	XpSystem.reset()
	assert_eq(XpSystem.get_weekly_xp(), 0, "reset 후 0")

	# 로드 (세션 재개 시뮬레이션)
	XpSystem.load_save_data(saved)
	assert_eq(XpSystem.get_weekly_xp(), 60, "로드 직후 60 복원")

	# "목금" 추가 XP
	XpSystem.grant_weekly_prize_xp(10)  # Day 4
	XpSystem.grant_weekly_prize_xp(10)  # Day 5

	# Assert — 월화수 포함한 주간 합산
	assert_eq(XpSystem.get_weekly_xp(), 80,
		"로드 후 주간 XP에 월화수 포함: 60 + 10 + 10 = 80")


func test_weekly_xp_resets_after_weekly_report() -> void:
	# Arrange
	XpSystem.grant_weekly_prize_xp(50)
	assert_eq(XpSystem.get_weekly_xp(), 50, "전제: 주간 XP 50")

	# Act — simulate weekly settlement calling reset_weekly_xp()
	XpSystem.reset_weekly_xp()
	assert_eq(XpSystem.get_weekly_xp(), 0, "주간 리포트 후 weekly XP 초기화")

	# Next week starts fresh
	XpSystem.grant_weekly_prize_xp(30)
	assert_eq(XpSystem.get_weekly_xp(), 30, "다음 주 XP는 리셋 후부터 누산")


func test_load_save_data_weekly_xp_clamped_non_negative() -> void:
	# Arrange — malformed save data with negative weekly_xp
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
	XpSystem.grant_weekly_prize_xp(50)
	assert_eq(XpSystem.get_weekly_xp(), 50)

	# Act
	XpSystem.reset()

	# Assert
	assert_eq(XpSystem.get_weekly_xp(), 0, "reset() 후 weekly_xp도 0이어야 함")
