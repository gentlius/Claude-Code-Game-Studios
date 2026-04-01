## Autoload — Manages skill unlocks, prerequisite checks, and skill queries.
## Feature layer. Depends on: XpSystem.
## See: design/gdd/skill-tree.md
extends Node

# ── Signals ──

signal on_skill_unlocked(skill_id: String)

# ── Skill Definition Structure ──
## Each skill is a dictionary with:
##   id: String, branch: String, tier: int,
##   name: String, description: String,
##   prerequisites: Array[String]  (skill IDs)

# ── Config (Tuning Knobs) ──

@export var SKILL_COST: int = 1
@export var NEWS_DELAY_T0: int = 40   ## ticks (~30 seconds)
@export var NEWS_DELAY_T1: int = 20   ## ticks (~15 seconds)
@export var RUMOR_BASE_ACCURACY: float = 0.7
@export var RUMOR_LEAD_TICKS: int = 60
@export var LEVERAGE_RATIO: float = 2.0
@export var MAX_HOLDINGS_T0: int = 3
@export var MAX_HOLDINGS_T1: int = 5
@export var MAX_HOLDINGS_T2: int = 10

# ── Skill Definitions ──

var _skill_definitions: Dictionary = {}  ## skill_id -> definition dict
var _unlocked_skills: Dictionary = {}    ## skill_id -> true (only unlocked ones)

# ── Lifecycle ──

func _ready() -> void:
	_register_all_skills()


# ── Public API: Queries ──

## Check if a specific skill is unlocked
func is_skill_unlocked(skill_id: String) -> bool:
	return _unlocked_skills.has(skill_id)


## Get the state of a skill: "UNLOCKED", "AVAILABLE", "PREREQ_MISSING", "LOCKED"
func get_skill_state(skill_id: String) -> String:
	if not _skill_definitions.has(skill_id):
		return "LOCKED"
	if is_skill_unlocked(skill_id):
		return "UNLOCKED"
	if _are_prerequisites_met(skill_id) and XpSystem.get_available_skill_points() >= SKILL_COST:
		return "AVAILABLE"
	if not _are_prerequisites_met(skill_id):
		return "PREREQ_MISSING"
	return "LOCKED"  # Prerequisites met but not enough points


## Get all skill definitions with their current state
func get_all_skills() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for skill_id: String in _skill_definitions:
		var skill: Dictionary = _skill_definitions[skill_id].duplicate()
		skill["state"] = get_skill_state(skill_id)
		result.append(skill)
	return result


## Get skills for a specific branch
func get_branch_skills(branch: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for skill_id: String in _skill_definitions:
		var skill: Dictionary = _skill_definitions[skill_id]
		if skill["branch"] == branch:
			var s: Dictionary = skill.duplicate()
			s["state"] = get_skill_state(skill_id)
			result.append(s)
	return result


## Get the current news delay in ticks based on unlocked sense skills
func get_news_delay_ticks() -> int:
	if is_skill_unlocked("S2"):
		return 0
	if is_skill_unlocked("S1"):
		return NEWS_DELAY_T1
	return NEWS_DELAY_T0


## Get the maximum number of holdings based on unlocked portfolio skills
func get_max_holdings() -> int:
	if is_skill_unlocked("P2"):
		return MAX_HOLDINGS_T2
	if is_skill_unlocked("P1"):
		return MAX_HOLDINGS_T1
	return MAX_HOLDINGS_T0


## Check if rumor channel is available
func has_rumor_channel() -> bool:
	return is_skill_unlocked("S3")


## Check if leverage trading is available
func has_leverage() -> bool:
	return is_skill_unlocked("TR4")


## Check if short selling is available
func has_short_selling() -> bool:
	return is_skill_unlocked("TR3")


# ── Public API: Actions ──

## Attempt to unlock a skill. Returns true on success.
func unlock_skill(skill_id: String) -> bool:
	if not _skill_definitions.has(skill_id):
		return false
	if is_skill_unlocked(skill_id):
		return false
	if not _are_prerequisites_met(skill_id):
		return false
	if XpSystem.get_available_skill_points() < SKILL_COST:
		return false

	# Spend skill point(s)
	for i: int in range(SKILL_COST):
		if not XpSystem.spend_skill_point():
			return false

	_unlocked_skills[skill_id] = true
	on_skill_unlocked.emit(skill_id)
	return true


# ── Prerequisite Logic ──

func _are_prerequisites_met(skill_id: String) -> bool:
	var skill: Dictionary = _skill_definitions.get(skill_id, {})
	var prereqs: Array = skill.get("prerequisites", [])
	for prereq_id: String in prereqs:
		if not is_skill_unlocked(prereq_id):
			return false
	return true


## Get the missing prerequisites for a skill (for UI display)
func get_missing_prerequisites(skill_id: String) -> Array[String]:
	var skill: Dictionary = _skill_definitions.get(skill_id, {})
	var prereqs: Array = skill.get("prerequisites", [])
	var missing: Array[String] = []
	for prereq_id: String in prereqs:
		if not is_skill_unlocked(prereq_id):
			missing.append(prereq_id)
	return missing


# ── Skill Registration (GDD Detailed Design) ──

func _register_all_skills() -> void:
	# Branch 1: Analysis Tools
	_register_skill("A1", "analysis", 1, "이동평균선",
		"5/20/60일 이동평균선 차트 오버레이", [])
	_register_skill("A2", "analysis", 2, "보조지표",
		"RSI(14), MACD(12,26,9) 하단 패널 표시", ["A1"])
	_register_skill("A3", "analysis", 3, "재무제표",
		"PER, PBR, ROE 기업정보 패널 표시", ["A2"])
	_register_skill("A4", "analysis", 4, "섹터 비교 분석",
		"업종별 상대강도 비교 뷰", ["A3"])

	# Branch 2: Market Sense
	_register_skill("S1", "sense", 1, "빠른 뉴스",
		"뉴스 딜레이 15초로 단축", [])
	_register_skill("S2", "sense", 2, "실시간 뉴스",
		"뉴스 딜레이 0초", ["S1"])
	_register_skill("S3", "sense", 3, "루머 채널",
		"뉴스 발생 전 확률적 힌트 (정확도 70%)", ["S2"])

	# Branch 3: Trading Skills
	_register_skill("TR1", "trading", 1, "지정가 주문",
		"목표가 설정, 조건 충족 시 자동 체결", [])
	_register_skill("TR2", "trading", 2, "손절/익절",
		"보유 종목에 자동 매도 조건 설정", ["TR1"])
	_register_skill("TR3", "trading", 3, "공매도",
		"주가 하락 시 수익. 보유 없이 매도 후 매수로 청산", ["TR2", "A2"])
	_register_skill("TR4", "trading", 4, "레버리지",
		"2x 배율 거래. 수익/손실 2배", ["TR3"])

	# Branch 4: Portfolio
	_register_skill("P1", "portfolio", 1, "5종목 보유",
		"동시 보유 종목 수 5로 확장", [])
	_register_skill("P2", "portfolio", 2, "10종목 보유",
		"동시 보유 종목 수 10으로 확장", ["P1"])
	_register_skill("P3", "portfolio", 3, "섹터 ETF",
		"섹터 단위 투자 가능", ["P2", "A4"])


func _register_skill(id: String, branch: String, tier: int,
		skill_name: String, description: String,
		prerequisites: Array) -> void:
	_skill_definitions[id] = {
		"id": id,
		"branch": branch,
		"tier": tier,
		"name": skill_name,
		"description": description,
		"prerequisites": prerequisites,
	}


# ── Serialization ──

func get_save_data() -> Dictionary:
	return {
		"unlocked_skills": _unlocked_skills.keys(),
	}


func load_save_data(data: Dictionary) -> void:
	_unlocked_skills.clear()
	var skill_ids: Array = data.get("unlocked_skills", [])
	for skill_id: String in skill_ids:
		# Only load skills that still exist in definitions (GDD edge case)
		if _skill_definitions.has(skill_id):
			_unlocked_skills[skill_id] = true
