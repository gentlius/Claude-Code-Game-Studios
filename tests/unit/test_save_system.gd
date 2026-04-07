extends GutTest
## SaveSystem 유닛 테스트 — GDD save-load.md AC-01~AC-09
## SaveSystem.save_game() / load_game() 및 각 시스템 직렬화 계약 검증.

const SAVE_PATH: String = "user://save_data.json"


func before_each() -> void:
	_clean_save()
	XpSystem.reset_for_testing()
	SkillTree.reset_for_testing()
	SeasonManager.reset_for_testing()
	CurrencySystem.reset_for_testing()
	PortfolioManager.reset_for_testing()


func after_each() -> void:
	_clean_save()
	XpSystem.reset_for_testing()
	SkillTree.reset_for_testing()
	SeasonManager.reset_for_testing()
	CurrencySystem.reset_for_testing()
	PortfolioManager.reset_for_testing()


func _clean_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var da := DirAccess.open("user://")
		if da:
			da.remove("save_data.json")


# ── AC-01: 파일 생성 ──

func test_save_game_creates_file() -> void:
	# Arrange
	CurrencySystem.init_first_season()

	# Act
	var ok: bool = SaveSystem.save_game()

	# Assert
	assert_true(ok, "save_game()은 성공 시 true를 반환해야 함")
	assert_true(FileAccess.file_exists(SAVE_PATH), "저장 파일이 생성되어야 함")


# ── AC-02: XP 복원 ──

func test_load_game_restores_xp() -> void:
	# Arrange — XpSystem 내부 상태를 직접 조작 (직렬화 계약 테스트)
	var fake_xp: Dictionary = {"total_xp": 800, "current_level": 3, "spent_skill_points": 1}
	CurrencySystem.init_first_season()
	XpSystem.load_save_data(fake_xp)
	SaveSystem.save_game()

	# 상태 초기화 후 로드
	XpSystem.reset_for_testing()

	# Act
	SaveSystem.load_game()

	# Assert
	assert_eq(XpSystem.get_total_xp(), 800, "total_xp 복원")
	assert_eq(XpSystem.get_current_level(), 3, "current_level 복원")
	assert_eq(XpSystem.get_available_skill_points(), 2 - 1, "spent_skill_points 복원")


# ── AC-04: 보유 주식 복원 ──

func test_load_game_restores_holdings() -> void:
	# Arrange
	CurrencySystem.init_first_season()
	var fake_portfolio: Dictionary = {
		"holdings": {
			"005930": {"quantity": 5, "avg_buy_price": 70000, "total_invested": 350000}
		}
	}
	PortfolioManager.load_save_data(fake_portfolio)
	SaveSystem.save_game()
	PortfolioManager.reset_for_testing()

	# Act
	SaveSystem.load_game()

	# Assert
	var holding: Variant = PortfolioManager.get_holding("005930")
	assert_not_null(holding, "005930 보유 주식이 복원되어야 함")
	if holding != null:
		assert_eq(holding["quantity"], 5, "quantity 복원")
		assert_eq(holding["avg_buy_price"], 70000, "avg_buy_price 복원")


# ── AC-05: 시즌 상태 복원 ──

func test_load_game_restores_season() -> void:
	# Arrange
	var fake_season: Dictionary = {
		"current_tier": 1,
		"is_free_market": false,
		"season_start_capital": 3000000,
		"weekly_start_capital": 3100000,
		"weekly_trade_count": 4,
	}
	SeasonManager.load_save_data(fake_season)
	CurrencySystem.init_first_season()
	SaveSystem.save_game()
	SeasonManager.reset_for_testing()

	# Act
	SaveSystem.load_game()

	# Assert
	assert_eq(SeasonManager.get_current_tier(), 1, "current_tier 복원")
	assert_false(SeasonManager.get_is_free_market(), "is_free_market 복원")


# ── AC-06: 현금 복원 ──

func test_load_game_restores_currency() -> void:
	# Arrange
	CurrencySystem.init_first_season(1_500_000)
	SaveSystem.save_game()
	CurrencySystem.reset_for_testing()

	# Act
	SaveSystem.load_game()

	# Assert
	assert_eq(CurrencySystem.get_sim_cash(), 1_500_000, "sim_cash 복원")


# ── AC-07: 파일 없을 때 새 게임 시작 ──

func test_load_game_no_file_starts_fresh() -> void:
	# Arrange: 파일 없음 (before_each에서 삭제됨)
	assert_false(FileAccess.file_exists(SAVE_PATH))

	# Act
	var loaded: bool = SaveSystem.load_game()

	# Assert
	assert_false(loaded, "파일 없을 때 load_game()은 false 반환")
	assert_eq(XpSystem.get_total_xp(), 0, "XP는 초기값 유지")


# ── AC-09: 버전 불일치 — 알려진 필드만 로드 ──

func test_load_game_version_mismatch_loads_known_fields() -> void:
	# Arrange: 잘못된 버전으로 저장된 파일 직접 작성
	var bad_data: Dictionary = {
		"save_version": 999,
		"xp": {"total_xp": 300, "current_level": 2, "spent_skill_points": 0},
	}
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(bad_data))
	f.close()

	# Act (push_warning이 출력되지만 게임 차단 없음)
	var loaded: bool = SaveSystem.load_game()

	# Assert
	assert_true(loaded, "버전 불일치여도 load_game()은 true 반환 (알려진 필드 로드)")
	assert_eq(XpSystem.get_total_xp(), 300, "알려진 필드(xp)는 복원되어야 함")


# ── has_save() ──

func test_has_save_false_when_no_file() -> void:
	assert_false(SaveSystem.has_save())


func test_has_save_true_after_save() -> void:
	CurrencySystem.init_first_season()
	SaveSystem.save_game()
	assert_true(SaveSystem.has_save())


# ── delete_save() ──

func test_delete_save_removes_file() -> void:
	CurrencySystem.init_first_season()
	SaveSystem.save_game()
	assert_true(SaveSystem.has_save())
	SaveSystem.delete_save()
	assert_false(SaveSystem.has_save())
