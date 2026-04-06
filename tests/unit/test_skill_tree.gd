extends GutTest
## Unit tests for SkillTree — see design/gdd/skill-tree.md

# ── Helpers ──

func before_each() -> void:
	# Reset skill tree and XP state
	SkillTree._unlocked_skills.clear()
	XpSystem._total_xp = 0
	XpSystem._current_level = 1
	XpSystem._spent_skill_points = 0


func _grant_skill_points(count: int) -> void:
	# Grant enough XP to reach level (count + 1) for count skill points
	# Each point requires a level-up, so we need to exceed cumulative thresholds
	for i: int in range(count):
		var needed: int = XpSystem._cumulative_xp_for_level(XpSystem.get_current_level() + 1) - XpSystem.get_total_xp()
		XpSystem._grant_xp(needed, "test")


# ── AC-1: Unlock skill with available points ──

func test_unlock_skill_success() -> void:
	_grant_skill_points(1)
	assert_eq(XpSystem.get_available_skill_points(), 1, "Should have 1 point")
	var result: bool = SkillTree.unlock_skill("A1")
	assert_true(result, "A1 should unlock")
	assert_true(SkillTree.is_skill_unlocked("A1"), "A1 should be unlocked")


# ── AC-2: Prerequisite enforcement (branch-internal) ──

func test_prerequisite_blocks_unlock() -> void:
	_grant_skill_points(1)
	var result: bool = SkillTree.unlock_skill("A2")
	assert_false(result, "A2 should fail without A1")
	assert_false(SkillTree.is_skill_unlocked("A2"), "A2 should stay locked")


func test_prerequisite_chain() -> void:
	_grant_skill_points(2)
	SkillTree.unlock_skill("A1")
	var result: bool = SkillTree.unlock_skill("A2")
	assert_true(result, "A2 should unlock after A1")


# ── AC-3: Cross-branch prerequisite ──

func test_cross_branch_prerequisite() -> void:
	_grant_skill_points(5)
	# TR3 requires TR2 + A2
	SkillTree.unlock_skill("TR1")
	SkillTree.unlock_skill("TR2")
	# Try TR3 without A2
	var result: bool = SkillTree.unlock_skill("TR3")
	assert_false(result, "TR3 should fail without A2")

	# Now unlock A1 and A2
	SkillTree.unlock_skill("A1")
	SkillTree.unlock_skill("A2")
	result = SkillTree.unlock_skill("TR3")
	assert_true(result, "TR3 should unlock with TR2 + A2")


# ── AC-4: Skill point deduction ──

func test_skill_point_deducted() -> void:
	_grant_skill_points(2)
	assert_eq(XpSystem.get_available_skill_points(), 2, "Start with 2 points")
	SkillTree.unlock_skill("A1")
	assert_eq(XpSystem.get_available_skill_points(), 1, "1 point remaining after unlock")


# ── AC-6: News delay changes with skills ──

func test_news_delay_default() -> void:
	assert_eq(SkillTree.get_news_delay_ticks(), 20, "Default delay = 20 ticks (5min×4TPM, reduced from 40 per UX audit)")


func test_news_delay_s1() -> void:
	_grant_skill_points(1)
	SkillTree.unlock_skill("S1")
	assert_eq(SkillTree.get_news_delay_ticks(), 8, "S1 delay = 8 ticks (2min×4TPM, reduced from 20 to preserve S1 upgrade value)")


func test_news_delay_s2() -> void:
	_grant_skill_points(2)
	SkillTree.unlock_skill("S1")
	SkillTree.unlock_skill("S2")
	assert_eq(SkillTree.get_news_delay_ticks(), 0, "S2 delay = 0 ticks")


# ── AC-7: Max holdings changes with skills ──

func test_max_holdings_default() -> void:
	assert_eq(SkillTree.get_max_holdings(), 3, "Default holdings = 3")


func test_max_holdings_p1() -> void:
	_grant_skill_points(1)
	SkillTree.unlock_skill("P1")
	assert_eq(SkillTree.get_max_holdings(), 5, "P1 holdings = 5")


func test_max_holdings_p2() -> void:
	_grant_skill_points(2)
	SkillTree.unlock_skill("P1")
	SkillTree.unlock_skill("P2")
	assert_eq(SkillTree.get_max_holdings(), 10, "P2 holdings = 10")


# ── AC-8: Skills persist across season (no reset logic) ──

func test_skills_persist() -> void:
	_grant_skill_points(1)
	SkillTree.unlock_skill("A1")
	# SkillTree has no season reset — skills are permanent
	assert_true(SkillTree.is_skill_unlocked("A1"), "A1 should persist")


# ── AC-9: No points → unlock fails ──

func test_no_points_blocks_unlock() -> void:
	assert_eq(XpSystem.get_available_skill_points(), 0, "Start with 0 points")
	var result: bool = SkillTree.unlock_skill("A1")
	assert_false(result, "Should fail with 0 points")


# ── Skill state queries ──

func test_skill_state_locked() -> void:
	assert_eq(SkillTree.get_skill_state("A1"), "LOCKED", "A1 locked with no points")


func test_skill_state_available() -> void:
	_grant_skill_points(1)
	assert_eq(SkillTree.get_skill_state("A1"), "AVAILABLE", "A1 available with points")


func test_skill_state_prereq_missing() -> void:
	_grant_skill_points(1)
	assert_eq(SkillTree.get_skill_state("A2"), "PREREQ_MISSING", "A2 prereq missing")


func test_skill_state_unlocked() -> void:
	_grant_skill_points(1)
	SkillTree.unlock_skill("A1")
	assert_eq(SkillTree.get_skill_state("A1"), "UNLOCKED", "A1 unlocked")


# ── Missing prerequisites query ──

func test_get_missing_prerequisites() -> void:
	var missing: Array[String] = SkillTree.get_missing_prerequisites("TR3")
	assert_true(missing.has("TR2"), "TR3 needs TR2")
	assert_true(missing.has("A2"), "TR3 needs A2")


# ── Serialization ──

func test_save_load() -> void:
	_grant_skill_points(2)
	SkillTree.unlock_skill("A1")
	SkillTree.unlock_skill("S1")
	var data: Dictionary = SkillTree.get_save_data()

	SkillTree._unlocked_skills.clear()
	assert_false(SkillTree.is_skill_unlocked("A1"), "Cleared")

	SkillTree.load_save_data(data)
	assert_true(SkillTree.is_skill_unlocked("A1"), "A1 restored")
	assert_true(SkillTree.is_skill_unlocked("S1"), "S1 restored")


func test_load_ignores_unknown_skills() -> void:
	SkillTree.load_save_data({"unlocked_skills": ["NONEXISTENT", "A1"]})
	assert_true(SkillTree.is_skill_unlocked("A1"), "A1 loaded")
	assert_false(SkillTree.is_skill_unlocked("NONEXISTENT"), "Unknown skill ignored")


# ── get_all_skills returns all 15 ──

func test_all_skills_count() -> void:
	var skills: Array[Dictionary] = SkillTree.get_all_skills()
	assert_eq(skills.size(), 14, "Should have 14 unlockable skills (T0 excluded)")


# ── Double unlock prevention ──

func test_double_unlock_fails() -> void:
	_grant_skill_points(2)
	SkillTree.unlock_skill("A1")
	var result: bool = SkillTree.unlock_skill("A1")
	assert_false(result, "Double unlock should fail")
	assert_eq(XpSystem.get_available_skill_points(), 1, "Should not consume extra point")
