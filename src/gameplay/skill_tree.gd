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

# ── Config (Tuning Knobs — loaded from skill_tree_config.json) ──

const SKILL_TREE_CONFIG_PATH: String = "res://assets/data/skill_tree_config.json"

var SKILL_COST: int = 1
var NEWS_DELAY_T0_MIN: int = 5   ## 5 game-minutes delay (no skill)
var NEWS_DELAY_T1_MIN: int = 2   ## 2 game-minutes delay (S1 unlocked)
var RUMOR_BASE_ACCURACY: float = 0.7
var RUMOR_LEAD_MINUTES: int = 15
var LEVERAGE_RATIO: float = 2.0
var MAX_HOLDINGS_T0: int = 3
var MAX_HOLDINGS_T1: int = 5
var MAX_HOLDINGS_T2: int = 10

# ── Skill Definitions ──

var _skill_definitions: Dictionary = {}  ## skill_id -> definition dict
var _unlocked_skills: Dictionary = {}    ## skill_id -> true (only unlocked ones)

# ── Lifecycle ──

const SKILL_DATA_PATH: String = "res://assets/data/skill_tree.json"

func _ready() -> void:
	_load_config()
	_load_skills_from_json()


func _load_config() -> void:
	var f := FileAccess.open(SKILL_TREE_CONFIG_PATH, FileAccess.READ)
	if f == null:
		push_warning("SkillTree: config not found at %s — using defaults" % SKILL_TREE_CONFIG_PATH)
		return
	var result: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not result is Dictionary:
		push_warning("SkillTree: JSON parse failed for %s — using defaults" % SKILL_TREE_CONFIG_PATH)
		return
	var cfg: Dictionary = result as Dictionary
	if cfg.has("skillCost"):           SKILL_COST           = int(cfg["skillCost"])
	if cfg.has("newsDelayT0Min"):      NEWS_DELAY_T0_MIN    = int(cfg["newsDelayT0Min"])
	if cfg.has("newsDelayT1Min"):      NEWS_DELAY_T1_MIN    = int(cfg["newsDelayT1Min"])
	if cfg.has("rumorBaseAccuracy"):   RUMOR_BASE_ACCURACY  = float(cfg["rumorBaseAccuracy"])
	if cfg.has("rumorLeadMinutes"):    RUMOR_LEAD_MINUTES   = int(cfg["rumorLeadMinutes"])
	if cfg.has("leverageRatio"):       LEVERAGE_RATIO       = float(cfg["leverageRatio"])
	if cfg.has("maxHoldingsT0"):       MAX_HOLDINGS_T0      = int(cfg["maxHoldingsT0"])
	if cfg.has("maxHoldingsT1"):       MAX_HOLDINGS_T1      = int(cfg["maxHoldingsT1"])
	if cfg.has("maxHoldingsT2"):       MAX_HOLDINGS_T2      = int(cfg["maxHoldingsT2"])


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
			var skill_id: String = entry["id"]
			_skill_definitions[skill_id] = {
				"id": skill_id,
				"branch": entry.get("branch", ""),
				"tier": entry.get("tier", 0),
				"name": entry.get("name", ""),
				"description": _compute_description(skill_id, entry.get("description", "")),
				"prerequisites": prereqs,
			}


## 상수 기반 동적 설명 생성. JSON 스트링 하드코딩 대신 실제 상수값을 사용.
## 상수 변경 시 이 함수만 수정하면 됨.
func _compute_description(skill_id: String, fallback: String) -> String:
	match skill_id:
		"S0":
			return "뉴스 %d분 딜레이 (기본 제공)" % NEWS_DELAY_T0_MIN
		"S1":
			return "뉴스 딜레이 %d분으로 단축" % NEWS_DELAY_T1_MIN
		"S2":
			return "뉴스 딜레이 0초 (실시간)"
	return fallback


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
## Resets all skill unlock state for a new game.
## Resets all skill tree state. Called by GameMain (new game) and tests (before_each).
func reset() -> void:
	_unlocked_skills.clear()
