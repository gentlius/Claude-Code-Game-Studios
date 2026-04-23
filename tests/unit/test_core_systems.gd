## Core System Unit Tests — S10-08 (TD-CR-05)
## Covers: StockDatabase, FormatUtils, CurrencySystem, PortfolioManager, NewsEventSystem
extends GutTest

# ══════════════════════════════════════════════════════════════════
# FormatUtils (static utility class — no autoload)
# ══════════════════════════════════════════════════════════════════

func test_format_utils_number_basic() -> void:
	assert_eq(FormatUtils.number(1234567), "1,234,567", "숫자 쉼표 포맷")

func test_format_utils_number_small() -> void:
	assert_eq(FormatUtils.number(123), "123", "3자리 이하 — 쉼표 없음")

func test_format_utils_number_negative() -> void:
	assert_eq(FormatUtils.number(-1000), "-1,000", "음수 포맷")

func test_format_utils_number_zero() -> void:
	assert_eq(FormatUtils.number(0), "0", "0 포맷")

func test_format_utils_number_million() -> void:
	assert_eq(FormatUtils.number(1000000), "1,000,000", "백만 포맷")

func test_format_utils_pct_positive() -> void:
	assert_eq(FormatUtils.pct(12.3), "+12.3%", "양수 수익률 포맷")

func test_format_utils_pct_negative() -> void:
	assert_eq(FormatUtils.pct(-5.0), "-5.0%", "음수 수익률 포맷")

func test_format_utils_pct_zero() -> void:
	assert_eq(FormatUtils.pct(0.0), "+0.0%", "0% 포맷")

func test_format_utils_currency_prefix() -> void:
	assert_true(FormatUtils.currency(1000000).begins_with("₩"),
		"통화 포맷 ₩ 접두사")

func test_format_utils_currency_value() -> void:
	assert_eq(FormatUtils.currency(1234567), "₩1,234,567", "통화 포맷 값")


# ══════════════════════════════════════════════════════════════════
# StockDatabase
# ══════════════════════════════════════════════════════════════════

func test_stock_database_has_stocks_loaded() -> void:
	var count: int = StockDatabase.get_stock_count()
	assert_true(count > 0, "종목 1개 이상 로드됨")

func test_stock_database_get_stock_returns_stockdata() -> void:
	var ids: Array[String] = StockDatabase.get_all_stock_ids()
	if ids.is_empty():
		pass_test("종목 없음 — 헤드리스 환경 스킵")
		return
	var stock: StockData = StockDatabase.get_stock(ids[0])
	assert_not_null(stock, "get_stock() → StockData 반환")

func test_stock_database_stock_exists_true() -> void:
	var ids: Array[String] = StockDatabase.get_all_stock_ids()
	if ids.is_empty():
		pass_test("종목 없음 — 헤드리스 환경 스킵")
		return
	assert_true(StockDatabase.stock_exists(ids[0]), "stock_exists() = true for known ID")

func test_stock_database_stock_exists_false_for_unknown() -> void:
	assert_false(StockDatabase.stock_exists("__NONEXISTENT_STOCK__"),
		"stock_exists() = false for unknown ID")

func test_stock_database_get_stock_returns_null_for_unknown() -> void:
	var result: StockData = StockDatabase.get_stock("__NONEXISTENT_STOCK__")
	assert_null(result, "get_stock() 미존재 → null")

func test_stock_database_get_all_stocks_count_matches() -> void:
	var all_stocks: Array[StockData] = StockDatabase.get_all_stocks()
	var all_ids: Array[String] = StockDatabase.get_all_stock_ids()
	assert_eq(all_stocks.size(), all_ids.size(), "get_all_stocks() 수 = get_all_stock_ids() 수")

func test_stock_database_get_stocks_by_sector_returns_array() -> void:
	var sectors: Array[Dictionary] = StockDatabase.get_all_sectors()
	if sectors.is_empty():
		pass_test("섹터 없음 — 헤드리스 환경 스킵")
		return
	var sector_name: String = str(sectors[0]["sector"])
	var stocks: Array[StockData] = StockDatabase.get_stocks_by_sector(sector_name)
	assert_true(stocks.size() > 0, "섹터별 종목 조회 — 1개 이상")

func test_stock_database_get_stocks_by_sector_empty_for_unknown() -> void:
	var result: Array[StockData] = StockDatabase.get_stocks_by_sector("__UNKNOWN_SECTOR__")
	assert_eq(result.size(), 0, "미존재 섹터 → 빈 배열")

func test_stock_database_get_all_sectors_returns_dicts() -> void:
	var sectors: Array[Dictionary] = StockDatabase.get_all_sectors()
	if sectors.is_empty():
		pass_test("섹터 없음 — 헤드리스 환경 스킵")
		return
	assert_true(sectors[0].has("sector"), "섹터 dict에 'sector' 키 존재")


# ══════════════════════════════════════════════════════════════════
# CurrencySystem
# ══════════════════════════════════════════════════════════════════

func before_each() -> void:
	CurrencySystem.reset()
	PortfolioManager.reset()


func test_currency_system_initial_sim_cash_is_zero() -> void:
	assert_eq(CurrencySystem.get_sim_cash(), 0, "초기 sim_cash = 0")


func test_currency_system_auto_deposit_increases_sim_cash() -> void:
	CurrencySystem.auto_deposit_to_sim(1_000_000)
	assert_eq(CurrencySystem.get_sim_cash(), 1_000_000, "auto_deposit 후 sim_cash 증가")


func test_currency_system_sim_deduct_reduces_cash() -> void:
	CurrencySystem.auto_deposit_to_sim(1_000_000)
	var ok: bool = CurrencySystem.sim_deduct(200_000)
	assert_true(ok, "sim_deduct 성공")
	assert_eq(CurrencySystem.get_sim_cash(), 800_000, "deduct 후 sim_cash = 800,000")


func test_currency_system_sim_deduct_fails_when_insufficient() -> void:
	# sim_cash = 0 → deduct should fail
	var ok: bool = CurrencySystem.sim_deduct(1)
	assert_false(ok, "잔액 부족 → sim_deduct 실패")


func test_currency_system_sim_add_increases_cash() -> void:
	CurrencySystem.sim_add(500_000)
	assert_eq(CurrencySystem.get_sim_cash(), 500_000, "sim_add 후 sim_cash 증가")


func test_currency_system_settle_to_cash_zeroes_sim_cash() -> void:
	CurrencySystem.auto_deposit_to_sim(2_000_000)
	CurrencySystem.settle_to_cash(0)
	assert_eq(CurrencySystem.get_sim_cash(), 0, "settle_to_cash 후 sim_cash = 0")


func test_currency_system_reset_zeroes_sim_cash() -> void:
	CurrencySystem.auto_deposit_to_sim(5_000_000)
	CurrencySystem.reset()
	assert_eq(CurrencySystem.get_sim_cash(), 0, "reset 후 sim_cash = 0")


# ══════════════════════════════════════════════════════════════════
# PortfolioManager
# ══════════════════════════════════════════════════════════════════

func test_portfolio_manager_initial_holdings_empty() -> void:
	assert_eq(PortfolioManager.get_all_holdings().size(), 0, "초기 holdings 비어있음")


func test_portfolio_manager_get_holding_nonexistent_returns_null() -> void:
	var result: Variant = PortfolioManager.get_holding("__NO_STOCK__")
	assert_null(result, "미보유 종목 → null")


func test_portfolio_manager_get_holding_count_zero() -> void:
	assert_eq(PortfolioManager.get_holding_count(), 0, "초기 holding_count = 0")


func test_portfolio_manager_get_return_rate_zero_on_empty() -> void:
	var rate: float = PortfolioManager.get_return_rate()
	assert_almost_eq(rate, 0.0, 0.001, "빈 포트폴리오 수익률 = 0")


func test_portfolio_manager_reset_clears_holdings() -> void:
	# Inject a holding directly
	PortfolioManager.add_holding("TEST_STOCK", 10, 50000)
	assert_true(PortfolioManager.get_holding_count() > 0, "추가 후 holding_count > 0")
	PortfolioManager.reset()
	assert_eq(PortfolioManager.get_holding_count(), 0, "reset 후 holding_count = 0")


func test_portfolio_manager_get_portfolio_summary_has_keys() -> void:
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	assert_true(summary.has("holdings_count"), "holdings_count 키 존재")
	assert_true(summary.has("total_value"),    "total_value 키 존재")


# ══════════════════════════════════════════════════════════════════
# NewsEventSystem — save/load and fire_stock_news API
# ══════════════════════════════════════════════════════════════════

func test_news_event_system_get_save_data_returns_dict() -> void:
	var data: Dictionary = NewsEventSystem.get_save_data()
	assert_true(data is Dictionary, "get_save_data() → Dictionary")


func test_news_event_system_get_season_theme_returns_dict() -> void:
	var theme: Dictionary = NewsEventSystem.get_season_theme()
	assert_true(theme is Dictionary, "get_season_theme() → Dictionary")


func test_news_event_system_has_inject_event() -> void:
	assert_true(NewsEventSystem.has_method("inject_event"), "inject_event 존재")


func test_news_event_system_has_fire_stock_news() -> void:
	assert_true(NewsEventSystem.has_method("fire_stock_news"), "fire_stock_news 존재")


func test_news_event_system_has_reset() -> void:
	assert_true(NewsEventSystem.has_method("reset"), "reset 존재")


func test_news_event_system_fire_stock_news_emits_signal() -> void:
	# reset() sets _state to READY so fire_stock_news doesn't early-exit
	NewsEventSystem.reset()
	var received: Array = []
	var conn: Callable = func(entry: Dictionary) -> void:
		received.append(entry)
	NewsEventSystem.on_news_display.connect(conn)

	NewsEventSystem.fire_stock_news("TEST_STOCK", "테스트 헤드라인", "본문", 1, "MEDIUM")

	NewsEventSystem.on_news_display.disconnect(conn)
	assert_eq(received.size(), 1, "fire_stock_news → on_news_display 시그널 발생")
	assert_eq(str(received[0].get("headline", "")), "테스트 헤드라인", "헤드라인 일치")
