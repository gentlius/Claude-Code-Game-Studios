extends GutTest
## SaveSystem 유닛 테스트 — 멀티슬롯 API (ADR-009)
## GDD: design/gdd/save-load.md AC-01~AC-14
## Sprint 5 리뉴얼: 단일슬롯(save_game/load_game) → 멀티슬롯(save_slot/load_slot/create_slot)

const INDEX_PATH: String = "user://save_index.json"


func before_each() -> void:
	_clean_save_files()
	SaveSystem.active_slot_id = -1
	XpSystem.reset()
	SkillTree.reset()
	SeasonManager.reset()
	CurrencySystem.reset()
	PortfolioManager.reset()


func after_each() -> void:
	_clean_save_files()
	SaveSystem.active_slot_id = -1
	XpSystem.reset()
	SkillTree.reset()
	SeasonManager.reset()
	CurrencySystem.reset()
	PortfolioManager.reset()


func _clean_save_files() -> void:
	var da := DirAccess.open("user://")
	if da == null:
		return
	if FileAccess.file_exists(INDEX_PATH):
		da.remove("save_index.json")
	if FileAccess.file_exists("user://save_data.json"):
		da.remove("save_data.json")
	# slot 파일 전부 삭제
	for i: int in range(10):
		var path: String = "save_slot_%d.json" % i
		if FileAccess.file_exists("user://" + path):
			da.remove(path)


# ── create_slot ──

func test_create_slot_returns_id_and_creates_index() -> void:
	# Act
	var id: int = SaveSystem.create_slot("테스트 슬롯")

	# Assert
	assert_eq(id, 0, "첫 슬롯 ID는 0이어야 함")
	assert_true(FileAccess.file_exists(INDEX_PATH), "인덱스 파일이 생성되어야 함")
	assert_eq(SaveSystem.active_slot_id, 0, "active_slot_id가 설정되어야 함")


func test_create_slot_ids_monotonically_increase() -> void:
	# Arrange
	var id0: int = SaveSystem.create_slot("슬롯 1")

	# Act
	var id1: int = SaveSystem.create_slot("슬롯 2")

	# Assert
	assert_true(id1 > id0, "ID는 단조 증가해야 함")


func test_create_slot_after_delete_no_id_reuse() -> void:
	# Arrange — 슬롯 0 생성 후 삭제 (GDD AC-03)
	var id0: int = SaveSystem.create_slot("슬롯 1")
	SaveSystem.delete_slot(id0)

	# Act
	var id1: int = SaveSystem.create_slot("슬롯 2")

	# Assert
	assert_true(id1 > id0, "삭제된 ID를 재사용하면 안 됨 (ADR-009)")


# ── get_slot_list ──

func test_get_slot_list_empty_when_no_index() -> void:
	# Act
	var slots: Array[Dictionary] = SaveSystem.get_slot_list()

	# Assert
	assert_eq(slots.size(), 0, "인덱스 없을 때 빈 목록 반환")


func test_get_slot_list_returns_created_slots() -> void:
	# Arrange
	SaveSystem.create_slot("슬롯 A")
	SaveSystem.create_slot("슬롯 B")

	# Act
	var slots: Array[Dictionary] = SaveSystem.get_slot_list()

	# Assert
	assert_eq(slots.size(), 2, "생성한 슬롯 수와 일치해야 함")


func test_get_slot_list_sorted_by_saved_at_desc() -> void:
	# Arrange
	SaveSystem.create_slot("오래된 슬롯")
	OS.delay_msec(10)  # saved_at 차이 보장
	SaveSystem.create_slot("최신 슬롯")

	# Act
	var slots: Array[Dictionary] = SaveSystem.get_slot_list()

	# Assert — 최신순 정렬 (GDD §3-3)
	assert_true(
		slots[0].get("saved_at", 0) >= slots[1].get("saved_at", 0),
		"saved_at 기준 내림차순 정렬"
	)


# ── save_slot / load_slot ──

func test_save_slot_creates_slot_file() -> void:
	# Arrange
	var id: int = SaveSystem.create_slot("저장 테스트")
	CurrencySystem.init_first_season()

	# Act
	var ok: bool = SaveSystem.save_slot(id)

	# Assert
	assert_true(ok, "save_slot()은 성공 시 true 반환")
	assert_true(
		FileAccess.file_exists("user://save_slot_%d.json" % id),
		"슬롯 파일이 생성되어야 함"
	)


func test_load_slot_restores_currency() -> void:
	# Arrange — GDD AC-05
	var id: int = SaveSystem.create_slot("현금 복원 테스트")
	CurrencySystem.init_first_season(1_500_000)
	SaveSystem.save_slot(id)
	CurrencySystem.reset()

	# Act
	var ok: bool = SaveSystem.load_slot(id)

	# Assert
	assert_true(ok, "load_slot()은 성공 시 true 반환")
	assert_eq(CurrencySystem.get_sim_cash(), 1_500_000, "sim_cash 복원")


func test_load_slot_restores_xp() -> void:
	# Arrange
	var id: int = SaveSystem.create_slot("XP 복원 테스트")
	CurrencySystem.init_first_season()
	var fake_xp: Dictionary = {"total_xp": 800, "current_level": 3, "spent_skill_points": 1}
	XpSystem.load_save_data(fake_xp)
	SaveSystem.save_slot(id)
	XpSystem.reset()

	# Act
	SaveSystem.load_slot(id)

	# Assert
	assert_eq(XpSystem.get_total_xp(), 800, "total_xp 복원")
	assert_eq(XpSystem.get_current_level(), 3, "current_level 복원")


func test_load_slot_restores_holdings() -> void:
	# Arrange — GDD AC-06
	var id: int = SaveSystem.create_slot("보유주식 복원 테스트")
	CurrencySystem.init_first_season()
	var fake_portfolio: Dictionary = {
		"holdings": {
			"005930": {"quantity": 5, "avg_buy_price": 70000, "total_invested": 350000}
		}
	}
	PortfolioManager.load_save_data(fake_portfolio)
	SaveSystem.save_slot(id)
	PortfolioManager.reset()

	# Act
	SaveSystem.load_slot(id)

	# Assert
	var holding: Variant = PortfolioManager.get_holding("005930")
	assert_not_null(holding, "005930 보유 주식이 복원되어야 함")
	if holding != null:
		assert_eq(holding["quantity"], 5, "quantity 복원")


func test_load_slot_nonexistent_returns_false() -> void:
	# Act — GDD EC-02
	var ok: bool = SaveSystem.load_slot(999)

	# Assert
	assert_false(ok, "존재하지 않는 슬롯 로드 시 false 반환")


func test_load_slot_corrupted_returns_false() -> void:
	# Arrange — GDD EC-03
	var path: String = "user://save_slot_0.json"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ invalid json }")
	f.close()

	# 인덱스에 슬롯 0 등록
	SaveSystem.create_slot("손상 슬롯")

	# Act
	var ok: bool = SaveSystem.load_slot(0)

	# Assert
	assert_false(ok, "손상된 슬롯 로드 시 false 반환")


# ── delete_slot ──

func test_delete_slot_removes_file_and_index_entry() -> void:
	# Arrange — GDD AC-10
	var id: int = SaveSystem.create_slot("삭제 테스트")
	CurrencySystem.init_first_season()
	SaveSystem.save_slot(id)

	# Act
	SaveSystem.delete_slot(id)

	# Assert
	assert_false(
		FileAccess.file_exists("user://save_slot_%d.json" % id),
		"슬롯 파일이 삭제되어야 함"
	)
	var slots: Array[Dictionary] = SaveSystem.get_slot_list()
	var found: bool = false
	for s: Dictionary in slots:
		if s.get("id", -1) == id:
			found = true
	assert_false(found, "인덱스에서도 제거되어야 함")


func test_delete_slot_resets_active_slot_id() -> void:
	# Arrange
	var id: int = SaveSystem.create_slot("활성 슬롯")
	assert_eq(SaveSystem.active_slot_id, id)

	# Act
	SaveSystem.delete_slot(id)

	# Assert
	assert_eq(SaveSystem.active_slot_id, -1, "삭제 후 active_slot_id = -1")


# ── is_slot_valid ──

func test_is_slot_valid_false_when_no_file() -> void:
	assert_false(SaveSystem.is_slot_valid(0))


func test_is_slot_valid_true_after_save() -> void:
	var id: int = SaveSystem.create_slot("유효 슬롯")
	CurrencySystem.init_first_season()
	SaveSystem.save_slot(id)
	assert_true(SaveSystem.is_slot_valid(id))


func test_is_slot_valid_false_for_corrupted_file() -> void:
	# Arrange
	var f: FileAccess = FileAccess.open("user://save_slot_77.json", FileAccess.WRITE)
	f.store_string("not json")
	f.close()

	# Assert
	assert_false(SaveSystem.is_slot_valid(77))


# ── rename_slot ──

func test_rename_slot_updates_index() -> void:
	# Arrange — GDD AC-09
	var id: int = SaveSystem.create_slot("원래 이름")

	# Act
	SaveSystem.rename_slot(id, "새 이름")

	# Assert
	var slots: Array[Dictionary] = SaveSystem.get_slot_list()
	var found_name: String = ""
	for s: Dictionary in slots:
		if s.get("id", -1) == id:
			found_name = s.get("name", "")
	assert_eq(found_name, "새 이름", "인덱스의 이름이 갱신되어야 함")


func test_rename_slot_empty_string_is_noop() -> void:
	# Arrange — GDD EC-08
	var id: int = SaveSystem.create_slot("원래 이름")

	# Act
	SaveSystem.rename_slot(id, "")

	# Assert
	var slots: Array[Dictionary] = SaveSystem.get_slot_list()
	for s: Dictionary in slots:
		if s.get("id", -1) == id:
			assert_eq(s.get("name", ""), "원래 이름", "빈 문자열로 이름 변경 불가")


# ── save_pending 중복 차단 ──

func test_save_slot_ignores_while_pending() -> void:
	# Arrange — ADR-015 중복 저장 방지
	var id: int = SaveSystem.create_slot("중복 테스트")
	CurrencySystem.init_first_season()
	SaveSystem._save_pending = true  # 강제로 pending 상태 설정

	# Act
	var ok: bool = SaveSystem.save_slot(id)

	# Assert
	assert_false(ok, "_save_pending 중 save_slot()은 false 반환")

	# Cleanup
	SaveSystem._save_pending = false


# ── v1 마이그레이션 ──

func test_v1_migration_converts_legacy_save() -> void:
	# Arrange — GDD §3-7 / ADR-009
	var legacy_data: Dictionary = {
		"save_version": 1,
		"xp": {"total_xp": 200, "current_level": 2, "spent_skill_points": 0},
		"currency": {"sim_cash": 1_200_000}
	}
	var f: FileAccess = FileAccess.open("user://save_data.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(legacy_data))
	f.close()

	# Act — SaveSystem._migrate_v1_save()를 직접 호출
	SaveSystem._migrate_v1_save()

	# Assert
	assert_false(FileAccess.file_exists("user://save_data.json"), "레거시 파일이 제거되어야 함")
	assert_true(FileAccess.file_exists("user://save_slot_0.json"), "slot_0으로 마이그레이션")
	assert_true(FileAccess.file_exists(INDEX_PATH), "인덱스가 생성되어야 함")

	var slots: Array[Dictionary] = SaveSystem.get_slot_list()
	assert_eq(slots.size(), 1, "슬롯 1개")
	assert_eq(slots[0].get("id", -1), 0, "슬롯 ID = 0")
