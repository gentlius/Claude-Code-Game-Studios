## Financial Statements Tests — A3 스킬 PER/PBR/ROE/배당 표시 검증
## Implements: design/gdd/financial-statements.md §8 Acceptance Criteria
extends GutTest


# ── AC-03: 적자기업 N/A 표시 ──────────────────────────────────────────

func test_per_null_display() -> void:
	## per == 0.0 (적자기업) → get_per_display() == "N/A"
	## GDD financial-statements.md §8 AC-03
	var result: String = PriceEngine.get_per_display("MADEUP_DEFICIT_CO")
	## 존재하지 않는 종목 → null guard → "N/A"
	assert_eq(result, "N/A", "존재하지 않는 종목 PER → N/A")


func test_pbr_null_display() -> void:
	## pbr == 0.0 (적자/음수 자본) → "N/A"
	var result: String = PriceEngine.get_pbr_display("MADEUP_DEFICIT_CO")
	assert_eq(result, "N/A", "존재하지 않는 종목 PBR → N/A")


func test_roe_null_display() -> void:
	## roe == 0.0 (적자기업) → "N/A"
	var result: String = PriceEngine.get_roe_display("MADEUP_DEFICIT_CO")
	assert_eq(result, "N/A", "존재하지 않는 종목 ROE → N/A")


# ── AC-01: A3 미해금 시 섹션 숨김 ────────────────────────────────────

func test_a3_skill_not_unlocked_initially() -> void:
	## A3 미해금 상태에서 is_skill_unlocked("A3") == false
	SkillTree.reset()
	assert_false(SkillTree.is_skill_unlocked("A3"), "A3 미해금 시 false")
