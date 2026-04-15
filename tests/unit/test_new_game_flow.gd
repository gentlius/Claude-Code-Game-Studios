extends GutTest
## 새 게임 플로우 회귀 테스트.
## F4 나가기 → 새 게임, 또는 새 게임 직후 시즌 시작까지의 자산 상태를 검증한다.
## 이 테스트가 있었다면 2026-04-09 버그 3건을 코드 배포 전에 잡을 수 있었다:
##   - CurrencySystem.reset() 미호출 → 이전 게임 자산 잔존
##   - CurrencySystem._deposit 미초기화 → 예수금 누적
##   - PortfolioManager._on_season_start() reset() → total_assets 일시 0


func before_each() -> void:
	GameClock.reset()
	NewsEventSystem.reset()
	PriceEngine.reset()
	OrderEngine.reset()
	AiCompetitor.reset()
	XpSystem.reset()
	SkillTree.reset()
	SeasonManager.reset()
	PortfolioManager.reset()
	CurrencySystem.reset()


# ── 새 게임 초기화 시퀀스 ────────────────────────────────────────────

func test_new_game_currency_initialized_to_seed() -> void:
	# GameMain._on_new_game_confirmed() 시퀀스 재현
	CurrencySystem.init_first_season()

	assert_eq(CurrencySystem.get_sim_cash(), CurrencySystem.DEFAULT_SEASON_SEED,
		"새 게임 sim_cash = DEFAULT_SEASON_SEED")


func test_new_game_portfolio_total_assets_matches_seed() -> void:
	CurrencySystem.init_first_season()
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)

	assert_eq(PortfolioManager.get_total_assets(), CurrencySystem.DEFAULT_SEASON_SEED,
		"새 게임 total_assets = DEFAULT_SEASON_SEED")


func test_new_game_after_previous_game_has_clean_currency() -> void:
	# 이전 게임 상태 시뮬레이션 — 자산이 쌓인 상태
	CurrencySystem.init_first_season()
	CurrencySystem.sim_add(5_000_000)  # 이전 게임에서 수익 발생
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)

	# 새 게임 시작 (GameMain 리셋 시퀀스)
	GameClock.reset()
	XpSystem.reset()
	SkillTree.reset()
	SeasonManager.reset()
	PortfolioManager.reset()
	CurrencySystem.reset()

	CurrencySystem.init_first_season()
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)

	assert_eq(CurrencySystem.get_sim_cash(), CurrencySystem.DEFAULT_SEASON_SEED,
		"이전 게임 이후 새 게임 sim_cash = DEFAULT_SEASON_SEED (이전 잔액 잔존 없음)")
	assert_eq(PortfolioManager.get_total_assets(), CurrencySystem.DEFAULT_SEASON_SEED,
		"이전 게임 이후 새 게임 total_assets = DEFAULT_SEASON_SEED")


func test_new_game_deposit_is_zero_after_reset() -> void:
	# 이전 게임에서 deposit이 쌓인 상태
	CurrencySystem.init_first_season()
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)

	# 새 게임 리셋
	CurrencySystem.reset()

	assert_eq(CurrencySystem.get_deposit(), 0,
		"reset() 후 deposit = 0 (이전 게임 예수금 잔존 없음)")


# ── 시즌 시작 후 자산 상태 ───────────────────────────────────────────

func test_total_assets_not_zero_after_season_start() -> void:
	# 새 게임 초기화
	CurrencySystem.init_first_season()
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)

	# 시즌 시작 (GameClock.start_season() → on_season_start 발생 → PortfolioManager._on_season_start())
	GameClock.start_season()

	assert_gt(PortfolioManager.get_total_assets(), 0,
		"시즌 시작 직후 total_assets > 0 (on_season_start이 캐시를 0으로 밀면 안 됨)")


func test_total_assets_equals_seed_after_season_start() -> void:
	CurrencySystem.init_first_season()
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)
	SeasonManager.start_season()

	assert_eq(PortfolioManager.get_total_assets(), CurrencySystem.DEFAULT_SEASON_SEED,
		"시즌 시작 직후 total_assets = DEFAULT_SEASON_SEED")


func test_sim_cash_preserved_after_season_start() -> void:
	CurrencySystem.init_first_season()
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)
	SeasonManager.start_season()

	assert_eq(CurrencySystem.get_sim_cash(), CurrencySystem.DEFAULT_SEASON_SEED,
		"시즌 시작 후 sim_cash 보존됨")


# ── 2시즌 이후 initial_seed 기준선 ──────────────────────────────────

func test_initial_seed_uses_season_start_deposit_not_hardcoded() -> void:
	# 2시즌: 이전 시즌 수익 200만으로 시작
	CurrencySystem.init_first_season()
	CurrencySystem.sim_add(1_000_000)  # 수익 100만 추가 → 총 200만
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)

	SeasonManager.start_season()

	# 수익률 0% 기준선 = 시즌 시작 자산 (2,000,000)
	var start_cap: int = SeasonManager.get_season_start_deposit()
	assert_eq(start_cap, 2_000_000, "시즌 시작 자본 = 2,000,000")

	# total_assets == start_cap일 때 return_rate == 0%
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)
	assert_almost_eq(PortfolioManager.get_return_rate(), 0.0, 0.01,
		"시즌 시작 직후 수익률 = 0% (initial_seed = season_start_deposit)")
