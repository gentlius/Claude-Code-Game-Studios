## Autoload — Manages skill unlocks, prerequisite checks, and skill queries.
## Feature layer. Depends on: XpSystem.
## Skill definitions loaded from assets/data/skill_tree.json.
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
@export var NEWS_DELAY_T0_MIN: int = 5   ## 5 game-minutes delay (no skill) — reduced from 10 per UX audit (40틱→20틱)
@export var NEWS_DELAY_T1_MIN: int = 2   ## 2 game-minutes delay (S1 unlocked) — reduced from 5 to preserve S1 upgrade value
@export var RUMOR_BASE_ACCURACY: float = 0.7
@export var RUMOR_LEAD_MINUTES: int = 15  ## 15 game-minutes rumor lead time
@export var LEVERAGE_RATIO: float = 2.0
@export var MAX_HOLDINGS_T0: int = 3
@export var MAX_HOLDINGS_T1: int = 5
@export var MAX_HOLDINGS_T2: int = 10

# ── Skill Definitions ──

var _skill_definitions: Dictionary = {}  ## skill_id -> definition dict
var _unlocked_skills: Dictionary = {}    ## skill_id -> true (only unlocked ones)

# ── Lifecycle ──

const SKILL_DATA_PATH: String = "res://assets/data/skill_tree.json"

func _ready() -> void:
	_load_skills_from_json()


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


## Get the current news delay in ticks based on unlocked sense skills.
func get_news_delay_ticks() -> int:
	if is_skill_unlocked("S2"):
		return 0
	if is_skill_unlocked("S1"):
		return NEWS_DELAY_T1_MIN * GameClock.TICKS_PER_MINUTE
	return NEWS_DELAY_T0_MIN * GameClock.TICKS_PER_MINUTE


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


# ── Skill Loading ──

func _load_skills_from_json() -> void:
	var file: FileAccess = FileAccess.open(SKILL_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("SkillTree: cannot open %s — error %d" % [SKILL_DATA_PATH, FileAccess.get_open_error()])
		return
	var json_text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if not parsed is Array:
		push_error("SkillTree: %s must be a JSON array" % SKILL_DATA_PATH)
		return
	for entry: Variant in parsed:
		if entry is Dictionary and entry.has("id"):
			var prereqs: Array[String] = []
			for p: Variant in entry.get("prerequisites", []):
				prereqs.append(str(p))
			_skill_definitions[entry["id"]] = {
				"id": entry["id"],
				"branch": entry.get("branch", ""),
				"tier": entry.get("tier", 0),
				"name": entry.get("name", ""),
				"description": entry.get("description", ""),
				"prerequisites": prereqs,
			}


# ── Serialization ──

## Returns serializable state for save system.
func get_save_data() -> Dictionary:
	var keys: Array[String] = []
	keys.assign(_unlocked_skills.keys())
	return {
		"unlocked_skills": keys,
	}


## Restores state from save data.
## Validates prerequisite chains — removes skills whose prerequisites are unmet.
## Repeat until stable to cascade-invalidate multi-level chains (tamper protection).
func load_save_data(data: Dictionary) -> void:
	_unlocked_skills.clear()
	var skill_ids: Array = data.get("unlocked_skills", [])
	for skill_id: String in skill_ids:
		if _skill_definitions.has(skill_id):
			_unlocked_skills[skill_id] = true

	# Prerequisite validation: detect tampered saves where a skill is present
	# but its prerequisites are absent (impossible via normal unlock flow).
	var changed: bool = true
	while changed:
		changed = false
		for skill_id: String in _unlocked_skills.keys():
			if not _are_prerequisites_met(skill_id):
				_unlocked_skills.erase(skill_id)
				push_warning("SkillTree: 선행조건 미충족 스킬 '%s' 제거 — 세이브 파일 변조 감지" % skill_id)
				changed = true
				break  # _unlocked_skills modified — restart iteration


## Resets all unlocked skills for unit tests. Call in before_each.
## Note: skill point balances are owned by XpSystem — reset that separately.
func reset_for_testing() -> void:
	_unlocked_skills.clear()
