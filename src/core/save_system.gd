## Autoload — Multi-slot auto-save system.
## Slot index: user://save_index.json. Slot data: user://save_slot_{id}.json.
## Emits save_started/save_completed for SavingOverlay UI.
## GDD: design/gdd/save-load.md
extends Node

# ── Signals ──

## Emitted before file write begins — SavingOverlay listens to show spinner.
signal save_started
## Emitted after file write completes (success or failure).
signal save_completed

# ── Constants ──

const SAVE_VERSION: int = 4
const INDEX_VERSION: int = 1
const SAVE_INDEX_PATH: String = "user://save_index.json"
const LEGACY_SAVE_PATH: String = "user://save_data.json"  ## v1 단일 슬롯 경로 (마이그레이션용)

# ── State ──

## 현재 로드된 슬롯 ID. -1이면 미로드 상태. 외부에서는 get_active_slot_id() 사용.
var _active_slot_id: int = -1

var _save_pending: bool = false


# ── Lifecycle ──

func _ready() -> void:
	_migrate_v1_save()
	# ADR-015 개정: 저장 시점을 MARKET_CLOSED → PRE_MARKET(after DAY_TRANSITION)으로 변경.
	# DAY_TRANSITION 완료 후 PRE_MARKET 진입 시점에는 GameClock.day가 이미 N+1이고
	# overnight 버퍼(매크로/섹터 이벤트 + 공시)가 모두 채워져 있어 보정 코드 없이 저장 가능.
	# NewsEventSystem이 먼저 등록되어(project.godot 순서) PRE_MARKET 핸들러가 먼저 실행되므로
	# 버퍼 deliver 완료 → SaveSystem 저장 순서가 보장된다.
	GameClock.on_market_state_changed.connect(_on_market_state_changed_for_save)
	SeasonManager.on_season_ended.connect(
		func(_rank: int, _free: bool, _ret: float) -> void: _on_auto_save_trigger()
	)


func _on_market_state_changed_for_save(
	new_state: GameClock.MarketState, prev_state: GameClock.MarketState
) -> void:
	if new_state == GameClock.MarketState.PRE_MARKET \
			and prev_state == GameClock.MarketState.DAY_TRANSITION:
		_on_auto_save_trigger()


# ── Public API ──

## Returns the currently active slot ID, or -1 if no slot is loaded.
func get_active_slot_id() -> int:
	return _active_slot_id


## Returns true if a file write is currently in progress.
## Callers use this instead of reading the private _save_pending field directly.
func is_save_pending() -> bool:
	return _save_pending


## Returns Array[Dictionary] of slot metadata sorted by saved_at DESC.
## Each entry: {id, name, level, season_number, fiction_week, fiction_day, portfolio_value, saved_at}
func get_slot_list() -> Array[Dictionary]:
	var index: Dictionary = _read_index()
	var raw: Array = index.get("slots", [])
	raw.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("saved_at", 0) > b.get("saved_at", 0)
	)
	var result: Array[Dictionary] = []
	for item: Variant in raw:
		if item is Dictionary:
			result.append(item as Dictionary)
	return result


## Create a new slot entry in the index. Returns the new slot ID.
## Sets _active_slot_id. Does NOT save game data — call save_slot() after init.
func create_slot(slot_name: String) -> int:
	var index: Dictionary = _read_index()
	var slots: Array = index.get("slots", [])

	# next_id is persisted so deleted slot IDs are never reused (ADR-009).
	var new_id: int = index.get("next_id", 0)

	var meta: Dictionary = {
		"id": new_id,
		"name": slot_name,
		"level": 1,
		"season_number": 1,
		"fiction_week": 0,
		"fiction_day": 0,
		"portfolio_value": 0,
		"saved_at": int(Time.get_unix_time_from_system()),
	}
	slots.append(meta)
	index["slots"] = slots
	index["next_id"] = new_id + 1  # monotonically increment so IDs are never reused
	_write_index(index)
	_active_slot_id = new_id
	return new_id


## Load all system state from save_slot_{id}.json. Returns true on success.
## Sets _active_slot_id on success.
func load_slot(id: int) -> bool:
	var path: String = "user://save_slot_%d.json" % id
	var data: Dictionary = _read_slot_json(path, id)
	if data.is_empty():
		return false
	_restore_core_systems(data)
	var season_active: bool = _restore_clock(data)
	_restore_season_systems(data, season_active)
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)
	_active_slot_id = id
	return true


## Parse save file at path. Returns empty Dict on any error.
func _read_slot_json(path: String, id: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("SaveSystem: 슬롯 파일 없음 — %s (EC-02)" % path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SaveSystem: 슬롯 파일 읽기 실패 (EC-02) — %s" % path)
		return {}
	var json_text: String = file.get_as_text()
	file.close()
	var _json := JSON.new()
	if _json.parse(json_text) != OK or not _json.get_data() is Dictionary:
		push_warning("SaveSystem: JSON 파싱 실패 (EC-03) — 슬롯 %d" % id)
		return {}
	var data: Dictionary = _json.get_data() as Dictionary
	var saved_version: int = data.get("save_version", 0)
	if saved_version != SAVE_VERSION:
		push_warning("SaveSystem: save_version 불일치 %d → %d (EC-04) — 알려진 필드만 로드" % [
			saved_version, SAVE_VERSION])
	return data


## Restore XP, skills, season, currency, portfolio, lifestyle.
func _restore_core_systems(data: Dictionary) -> void:
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
	if data.has("lifestyle"):
		LifestyleManager.load_save_data(data["lifestyle"])


## Restore GameClock. Returns true if season was active.
## Must be called after _restore_core_systems (clock owns is_season_active authority).
func _restore_clock(data: Dictionary) -> bool:
	GameClock.load_save_data(data.get("clock", {}))
	var season_active: bool = GameClock.is_season_active()
	# 구버전 세이브 호환: clock 섹션에 season_active가 없으면 currency 섹션 fallback.
	if not season_active:
		season_active = data.get("currency", {}).get("season_active", false)
		if season_active:
			GameClock.load_save_data({"season_active": true,
				"market_state": GameClock.MarketState.PRE_MARKET})
	return season_active


## Restore in-season systems (prices, AI, news, positions). Safe to call with season_active=false.
func _restore_season_systems(data: Dictionary, season_active: bool) -> void:
	if season_active:
		PriceEngine.initialize_for_load(data.get("prices", {}))
		AiCompetitor.load_save_data(data.get("ai", {}))
		NewsEventSystem.load_save_data(data.get("news", {}))
	# StopTakeSystem은 holding 복원 이후에 로드해야 holding 유효성 검사가 가능 (EC-16)
	StopTakeSystem.load_save_data(data.get("stop_take", []))
	# TR3: 숏 포지션 복원 (holding 복원 이후 — margin_ratio는 첫 틱에 재계산)
	ShortSellingSystem.load_save_data(data.get("short_positions", []))
	ShortSellingSystem.load_borrow_pool_data(data.get("borrow_pool", {}))
	# TR4: 레버리지 포지션 복원 (holding 복원 이후)
	LeverageManager.load_save_data(data.get("leverage_positions", []))
	# OHLCV 시즌 간 누적 히스토리 복원 (S9-07)
	OhlcvHistory.load_save_data(data.get("ohlcv_history", {}))
	# P3 ETF 가격/플로우 복원 (S10-02)
	EtfManager.load_save_data(data.get("etf", {}))
	# S10-05 분기 실적 스케줄러 복원
	FinancialReportSystem.load_save_data(data.get("financial_report", {}))


## Save all system state to save_slot_{id}.json and update index metadata.
## Emits save_started / save_completed. Returns true on success.
func save_slot(id: int) -> bool:
	if _save_pending:
		return false
	_save_pending = true
	save_started.emit()

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
		"news": NewsEventSystem.get_save_data(),
		"stop_take": StopTakeSystem.get_save_data(),
		"lifestyle": LifestyleManager.get_save_data(),
		"short_positions": ShortSellingSystem.get_save_data(),
		"borrow_pool": ShortSellingSystem.get_borrow_pool_data(),
		"leverage_positions": LeverageManager.get_save_data(),
		"ohlcv_history": OhlcvHistory.get_save_data(),
		"etf": EtfManager.get_save_data(),
		"financial_report": FinancialReportSystem.get_save_data(),
	}

	var path: String = "user://save_slot_%d.json" % id
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveSystem: 슬롯 저장 실패 (EC-06) — %s" % path)
		_save_pending = false
		save_completed.emit()
		return false

	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	_update_slot_meta(id, data)
	_save_pending = false
	save_completed.emit()
	return true


## Delete save_slot_{id}.json and remove from index.
func delete_slot(id: int) -> void:
	var path: String = "user://save_slot_%d.json" % id
	var da := DirAccess.open("user://")
	if da and FileAccess.file_exists(path):
		da.remove("save_slot_%d.json" % id)

	var index: Dictionary = _read_index()
	var slots: Array = index.get("slots", [])
	var new_slots: Array = []
	for s: Variant in slots:
		if s is Dictionary and (s as Dictionary).get("id", -1) != id:
			new_slots.append(s)
	index["slots"] = new_slots
	_write_index(index)

	if _active_slot_id == id:
		_active_slot_id = -1


## Update slot name in index immediately. No-op if new_name is empty.
func rename_slot(id: int, new_name: String) -> void:
	if new_name.strip_edges().is_empty():
		return
	var index: Dictionary = _read_index()
	var slots: Array = index.get("slots", [])
	for s: Variant in slots:
		if s is Dictionary and (s as Dictionary).get("id", -1) == id:
			(s as Dictionary)["name"] = new_name
			break
	index["slots"] = slots
	_write_index(index)


## Returns true if save_slot_{id}.json exists and parses as a valid Dictionary.
func is_slot_valid(id: int) -> bool:
	var path: String = "user://save_slot_%d.json" % id
	if not FileAccess.file_exists(path):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text: String = file.get_as_text()
	file.close()
	var _json := JSON.new()
	return _json.parse(text) == OK and _json.get_data() is Dictionary


# ── Internal ──

func _on_auto_save_trigger() -> void:
	if _active_slot_id >= 0:
		save_slot(_active_slot_id)


func _read_index() -> Dictionary:
	if not FileAccess.file_exists(SAVE_INDEX_PATH):
		return {"index_version": INDEX_VERSION, "slots": []}
	var file: FileAccess = FileAccess.open(SAVE_INDEX_PATH, FileAccess.READ)
	if file == null:
		return {"index_version": INDEX_VERSION, "slots": []}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {"index_version": INDEX_VERSION, "slots": []}
	return parsed as Dictionary


func _write_index(index: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(SAVE_INDEX_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveSystem: index 파일 쓰기 실패")
		return
	file.store_string(JSON.stringify(index, "\t"))
	file.close()


func _update_slot_meta(id: int, data: Dictionary) -> void:
	var index: Dictionary = _read_index()
	var slots: Array = index.get("slots", [])
	var pf_value: int = _compute_portfolio_value()
	var season_data: Dictionary = data.get("season", {})
	var xp_data: Dictionary = data.get("xp", {})
	var clock_data: Dictionary = data.get("clock", {})
	for s: Variant in slots:
		if not s is Dictionary:
			continue
		var sd: Dictionary = s as Dictionary
		if sd.get("id", -1) == id:
			sd["level"] = xp_data.get("current_level", 1)
			sd["season_number"] = season_data.get("seasons_played", 0) + 1
			sd["fiction_week"] = clock_data.get("current_week", 0)
			sd["fiction_day"] = clock_data.get("current_day", 0)
			sd["portfolio_value"] = pf_value
			sd["saved_at"] = int(Time.get_unix_time_from_system())
			break
	index["slots"] = slots
	_write_index(index)


func _compute_portfolio_value() -> int:
	var total: int = CurrencySystem.get_sim_cash()
	var holdings: Array[Dictionary] = PortfolioManager.get_all_holdings()
	for h: Dictionary in holdings:
		var stock_id: String = h.get("stock_id", "")
		if stock_id.is_empty():
			continue
		total += h.get("quantity", 0) * PriceEngine.get_current_price(stock_id)
	# TR3/TR4 포지션 net equity 포함 — 슬롯 메타데이터 총자산 정확도
	total += ShortSellingSystem.get_short_net_value()
	total += LeverageManager.get_leverage_net_value()
	return total


## v1 단일 슬롯 세이브(save_data.json) 감지 시 slot_0으로 자동 마이그레이션. GDD §3-7.
func _migrate_v1_save() -> void:
	if not FileAccess.file_exists(LEGACY_SAVE_PATH):
		return
	if FileAccess.file_exists(SAVE_INDEX_PATH):
		return  # 이미 마이그레이션됨

	push_warning("SaveSystem: v1 단일 슬롯 세이브 감지 — slot_0으로 마이그레이션 (EC-08)")

	var da := DirAccess.open("user://")
	if da == null:
		return
	da.copy(LEGACY_SAVE_PATH, "user://save_slot_0.json")

	# 구파일에서 메타 추출
	var level: int = 1
	var season_num: int = 1
	var week: int = 0
	var day: int = 0
	var file: FileAccess = FileAccess.open(LEGACY_SAVE_PATH, FileAccess.READ)
	if file:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			var d: Dictionary = parsed as Dictionary
			level = d.get("xp", {}).get("current_level", 1)
			season_num = d.get("season", {}).get("seasons_played", 0) + 1
			week = d.get("clock", {}).get("current_week", 0)
			day = d.get("clock", {}).get("current_day", 0)

	var index: Dictionary = {
		"index_version": INDEX_VERSION,
		"slots": [{
			"id": 0,
			"name": tr("슬롯 1"),
			"level": level,
			"season_number": season_num,
			"fiction_week": week,
			"fiction_day": day,
			"portfolio_value": 0,
			"saved_at": int(Time.get_unix_time_from_system()),
		}]
	}
	_write_index(index)
	da.remove("save_data.json")
