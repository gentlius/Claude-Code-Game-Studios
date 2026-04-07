## Autoload — Single-slot auto-save system.
## Saves game state to JSON after each market close and season end.
## Loads automatically at app start if a save file exists.
## GDD: design/gdd/save-load.md
extends Node

# ── Constants ──

const SAVE_VERSION: int = 2
const SAVE_PATH: String = "user://save_data.json"

# ── State ──

var _save_pending: bool = false  ## Prevents double-save in same frame


# ── Lifecycle ──

func _ready() -> void:
	GameClock.on_market_close.connect(_on_auto_save_trigger)
	SeasonManager.on_season_ended.connect(
		func(_rank: int, _free: bool, _ret: float) -> void: _on_auto_save_trigger()
	)


# ── Public API ──

## Save all system state to SAVE_PATH. Returns true on success.
func save_game() -> bool:
	if _save_pending:
		return false
	_save_pending = true

	var data: Dictionary = {
		"save_version": SAVE_VERSION,
		"timestamp": int(Time.get_unix_time_from_system()),
		"xp": XpSystem.get_save_data(),
		"skill_tree": SkillTree.get_save_data(),
		"season": SeasonManager.get_save_data(),
		"currency": CurrencySystem.get_save_data(),
		"portfolio": PortfolioManager.get_save_data(),
		"prices": PriceEngine.get_save_data(),
		"clock": GameClock.get_save_data(),
		"ai": AiCompetitor.get_save_data(),
	}

	var json_text: String = JSON.stringify(data, "\t")
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveSystem: 저장 파일 열기 실패 (EC-06) — 경로: %s, 오류: %d" % [SAVE_PATH, FileAccess.get_open_error()])
		_save_pending = false
		return false

	file.store_string(json_text)
	file.close()
	_save_pending = false
	return true


## Load game state from SAVE_PATH. Returns true if a save was found and loaded.
## Returns false if no save exists (new game) or load fails (new game fallback).
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false  # EC-01: no save file — new game

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveSystem: 저장 파일 읽기 실패 (EC-02) — 경로: %s" % SAVE_PATH)
		return false

	var json_text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		push_error("SaveSystem: JSON 파싱 실패 (EC-03) — 새 게임으로 시작")
		return false

	var data: Dictionary = parsed as Dictionary

	# Version check — load known fields only, warn on mismatch (EC-04)
	var saved_version: int = data.get("save_version", 0)
	if saved_version != SAVE_VERSION:
		push_warning("SaveSystem: save_version 불일치 %d → %d (EC-04) — 알려진 필드만 로드" % [saved_version, SAVE_VERSION])

	if data.has("xp"):
		XpSystem.load_save_data(data["xp"])
	if data.has("skill_tree"):
		SkillTree.load_save_data(data["skill_tree"])
	if data.has("season"):
		SeasonManager.load_save_data(data["season"])
	if data.has("currency"):
		CurrencySystem.load_save_data(data["currency"])
	if data.has("portfolio"):
		PortfolioManager.load_save_data(data["portfolio"])

	# If a season was active, restore PriceEngine closing prices so holdings are
	# valued at the actual saved close — not snapped to base_price (GDD §3-3).
	# Also restore GameClock day/week counters so week-end/season-end fire on time.
	if CurrencySystem.is_season_active():
		PriceEngine.initialize_for_load(data.get("prices", {}))
		GameClock.load_save_data(data.get("clock", {}))
		AiCompetitor.load_save_data(data.get("ai", {}))

	# Refresh valuation cache after prices are restored.
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)

	return true


## Delete save file. Used in testing or "새 게임 시작" flow.
func delete_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var da := DirAccess.open("user://")
	if da:
		da.remove("save_data.json")
	else:
		push_warning("SaveSystem: user:// 접근 실패 — 세이브 삭제 안 됨")


## True if a save file exists.
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


# ── Internal ──

func _on_auto_save_trigger() -> void:
	save_game()
