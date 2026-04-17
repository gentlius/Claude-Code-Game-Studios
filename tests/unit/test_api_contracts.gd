## API Contract Tests — 외부 메서드 존재 + 시그널 시그니처 검증
## 새 시스템 추가 시 이 파일에 계약 테스트를 추가해야 한다.
## 실패 = "존재하지 않는 메서드를 호출하거나 시그널 타입이 맞지 않음"
## See: .claude/docs/coding-standards.md — Code Review Checklist
extends GutTest

# ── CurrencySystem ──────────────────────────────────────────────────

func test_currency_system_api():
	assert_true(CurrencySystem.has_method("init_first_season"), "init_first_season 존재")
	assert_true(CurrencySystem.has_method("get_sim_cash"),      "get_sim_cash 존재")
	assert_true(CurrencySystem.has_method("get_deposit"),       "get_deposit 존재")
	assert_true(CurrencySystem.has_method("sim_deduct"),        "sim_deduct 존재")
	assert_true(CurrencySystem.has_method("sim_add"),           "sim_add 존재")
	assert_true(CurrencySystem.has_method("settle_to_cash"),    "settle_to_cash 존재")
	assert_true(CurrencySystem.has_method("reset"), "reset 존재")


# ── PortfolioManager ─────────────────────────────────────────────────

func test_portfolio_manager_api():
	assert_true(PortfolioManager.has_method("get_all_holdings"),      "get_all_holdings 존재")
	assert_true(PortfolioManager.has_method("get_holding"),           "get_holding 존재")
	assert_true(PortfolioManager.has_method("get_total_assets"),      "get_total_assets 존재")
	assert_true(PortfolioManager.has_method("get_portfolio_summary"), "get_portfolio_summary 존재")
	assert_true(PortfolioManager.has_method("add_holding"),           "add_holding 존재")
	assert_true(PortfolioManager.has_method("remove_holding"),        "remove_holding 존재")
	assert_true(PortfolioManager.has_method("update_valuation"),      "update_valuation 존재")
	assert_true(PortfolioManager.has_method("force_liquidate"),       "force_liquidate 존재")


# ── OrderEngine ──────────────────────────────────────────────────────

func test_order_engine_api():
	assert_true(OrderEngine.has_method("submit_market_order"),       "submit_market_order 존재")
	assert_true(OrderEngine.has_method("submit_limit_order"),        "submit_limit_order 존재")
	assert_true(OrderEngine.has_method("cancel_order"),              "cancel_order 존재")
	assert_true(OrderEngine.has_method("cancel_all_pending_orders"), "cancel_all_pending_orders 존재")
	assert_true(OrderEngine.has_method("get_pending_orders"),        "get_pending_orders 존재")
	assert_true(OrderEngine.has_method("get_season_trade_count"),    "get_season_trade_count 존재")
	assert_true(OrderEngine.has_method("get_total_reserved_cash"),   "get_total_reserved_cash 존재")


# ── GameClock ────────────────────────────────────────────────────────

func test_game_clock_api():
	assert_true(GameClock.has_method("start_season"),         "start_season 존재")
	assert_true(GameClock.has_method("confirm_market_open"),  "confirm_market_open 존재")
	assert_true(GameClock.has_method("confirm_transition"),   "confirm_transition 존재")
	assert_true(GameClock.has_method("toggle_pause"),         "toggle_pause 존재")
	assert_true(GameClock.has_method("pause_request"),        "pause_request 존재")
	assert_true(GameClock.has_method("pause_release"),        "pause_release 존재")
	assert_true(GameClock.has_method("get_market_state"),     "get_market_state 존재")
	assert_true(GameClock.has_method("is_season_active"),     "is_season_active 존재")
	assert_true(GameClock.has_method("get_current_tick"),     "get_current_tick 존재")
	assert_true(GameClock.has_method("get_current_day"),      "get_current_day 존재")
	assert_true(GameClock.has_method("get_current_week"),     "get_current_week 존재")
	assert_true(GameClock.has_method("set_speed"),            "set_speed 존재")


# ── XpSystem ────────────────────────────────────────────────────────

func test_xp_system_api():
	assert_true(XpSystem.has_method("get_total_xp"),                "get_total_xp 존재")
	assert_true(XpSystem.has_method("get_current_level"),           "get_current_level 존재")
	assert_true(XpSystem.has_method("get_xp_progress"),             "get_xp_progress 존재")
	assert_true(XpSystem.has_method("get_available_skill_points"),  "get_available_skill_points 존재")
	assert_true(XpSystem.has_method("get_cumulative_xp_for_level"), "get_cumulative_xp_for_level 존재")
	assert_true(XpSystem.has_method("grant_season_bonus"),          "grant_season_bonus 존재")
	assert_true(XpSystem.has_method("grant_weekly_prize_xp"),       "grant_weekly_prize_xp 존재")
	assert_true(XpSystem.has_method("spend_skill_point"),           "spend_skill_point 존재")
	assert_true(XpSystem.has_method("get_weekly_xp"),               "get_weekly_xp 존재")
	assert_true(XpSystem.has_method("reset_weekly_xp"),             "reset_weekly_xp 존재")


func test_xp_gained_signal_has_source_param():
	## on_xp_gained는 (amount, new_total, source) 3개 파라미터여야 한다.
	## 2개면 trading_screen._on_xp_gained의 source 파라미터가 잘못된 값을 수신한다.
	var signal_list: Array = XpSystem.get_signal_list()
	var sig: Dictionary = {}
	for s: Dictionary in signal_list:
		if s["name"] == "on_xp_gained":
			sig = s
			break
	assert_false(sig.is_empty(), "on_xp_gained 시그널 존재")
	assert_eq(sig["args"].size(), 3, "on_xp_gained 파라미터 3개 (amount, new_total, source)")


# ── SeasonManager ────────────────────────────────────────────────────

func test_season_manager_api():
	assert_true(SeasonManager.has_method("start_season"),           "start_season 존재")
	assert_true(SeasonManager.has_method("get_current_tier"),       "get_current_tier 존재")
	assert_true(SeasonManager.has_method("get_tier_name"),          "get_tier_name 존재")
	assert_true(SeasonManager.has_method("get_is_free_market"),     "get_is_free_market 존재")
	assert_true(SeasonManager.has_method("get_season_return_pct"),  "get_season_return_pct 존재")
	assert_true(SeasonManager.has_method("get_weekly_return_pct"),  "get_weekly_return_pct 존재")
	assert_true(SeasonManager.has_method("get_season_start_deposit"), "get_season_start_deposit 존재")
	assert_true(SeasonManager.has_method("is_season_active"),          "is_season_active 존재")
	assert_true(SeasonManager.has_method("get_leaderboard"),           "get_leaderboard 존재")
	assert_true(SeasonManager.has_method("get_tier_rank"),             "get_tier_rank 존재")
	assert_true(SeasonManager.has_method("get_weekly_trade_count"),    "get_weekly_trade_count 존재")
	assert_true(SeasonManager.has_method("is_season_trade_eligible"),  "is_season_trade_eligible 존재")
	assert_true(SeasonManager.has_method("get_fiction_date"),          "get_fiction_date 존재")


# ── AiCompetitor ─────────────────────────────────────────────────────

func test_ai_competitor_api():
	assert_true(AiCompetitor.has_method("init_season"),            "init_season 존재")
	assert_true(AiCompetitor.has_method("get_eod_snapshot"),       "get_eod_snapshot 존재")
	assert_true(AiCompetitor.has_method("get_sorted_indices"),     "get_sorted_indices 존재")
	assert_true(AiCompetitor.has_method("estimate_player_rank"),   "estimate_player_rank 존재")
	assert_true(AiCompetitor.has_method("get_participant_meta"),   "get_participant_meta 존재")
	assert_true(AiCompetitor.has_method("get_save_data"),          "get_save_data 존재")
	assert_true(AiCompetitor.has_method("load_save_data"),         "load_save_data 존재")
	assert_true(AiCompetitor.has_method("reset"),                  "reset 존재")


# ── PriceEngine ──────────────────────────────────────────────────────

func test_price_engine_api():
	assert_true(PriceEngine.has_method("get_current_price"),    "get_current_price 존재")
	assert_true(PriceEngine.has_method("get_market_index"),     "get_market_index 존재")
	assert_true(PriceEngine.has_method("get_index_change_pct"), "get_index_change_pct 존재")
	# Order book API (GDD order-book.md §6)
	assert_true(PriceEngine.has_method("initialize_order_books"), "initialize_order_books 존재")
	assert_true(PriceEngine.has_method("get_order_book"),          "get_order_book 존재")
	assert_true(PriceEngine.has_method("consume_order_book"),      "consume_order_book 존재")
	# A3 재무제표 API (GDD financial-statements.md §8)
	assert_true(PriceEngine.has_method("get_per_display"),      "get_per_display 존재")
	assert_true(PriceEngine.has_method("get_pbr_display"),      "get_pbr_display 존재")
	assert_true(PriceEngine.has_method("get_roe_display"),      "get_roe_display 존재")
	assert_true(PriceEngine.has_method("get_dividend_display"), "get_dividend_display 존재")
	# 호가창 OHLCV API (GDD order-book.md §3-5 블록1)
	assert_true(PriceEngine.has_method("get_today_ohlcv"),      "get_today_ohlcv 존재")


# ── SkillTree ────────────────────────────────────────────────────────

func test_skill_tree_api():
	assert_true(SkillTree.has_method("get_max_holdings"),    "get_max_holdings 존재")
	assert_true(SkillTree.has_method("is_skill_unlocked"),   "is_skill_unlocked 존재")


# ── StopTakeSystem ───────────────────────────────────────────────────

func test_stop_take_system_api():
	assert_true(StopTakeSystem.has_method("set_condition"),    "set_condition 존재")
	assert_true(StopTakeSystem.has_method("clear_condition"),  "clear_condition 존재")
	assert_true(StopTakeSystem.has_method("get_setting"),      "get_setting 존재")
	assert_true(StopTakeSystem.has_method("get_all_settings"), "get_all_settings 존재")
	assert_true(StopTakeSystem.has_method("check_and_trigger"),"check_and_trigger 존재")
	assert_true(StopTakeSystem.has_method("get_save_data"),    "get_save_data 존재")
	assert_true(StopTakeSystem.has_method("load_save_data"),   "load_save_data 존재")
	assert_true(StopTakeSystem.has_method("reset"),            "reset 존재")


func test_stop_take_triggered_signal_params():
	## on_stop_take_triggered는 (stock_id, reason, filled_price) 3개 파라미터여야 한다.
	var signal_list: Array = StopTakeSystem.get_signal_list()
	var sig: Dictionary = {}
	for s: Dictionary in signal_list:
		if s["name"] == "on_stop_take_triggered":
			sig = s
			break
	assert_false(sig.is_empty(), "on_stop_take_triggered 시그널 존재")
	assert_eq(sig["args"].size(), 3, "on_stop_take_triggered 파라미터 3개 (stock_id, reason, filled_price)")


# ── NewsEventSystem — S3 루머 채널 시그널 ────────────────────────────
## Implements: design/gdd/rumor-channel.md §9 Implementation Checklist

func test_news_event_system_rumor_signal():
	var signal_list: Array = NewsEventSystem.get_signal_list()
	var sig: Dictionary = {}
	for s: Dictionary in signal_list:
		if s["name"] == "on_rumor_hint":
			sig = s
			break
	assert_false(sig.is_empty(), "on_rumor_hint 시그널 존재")
	assert_eq(sig["args"].size(), 1, "on_rumor_hint 파라미터 1개 (rumor: Dictionary)")


# ── MarketConfig ─────────────────────────────────────────────────────
## Implements: design/gdd/trading-fees.md §4

func test_market_config_api():
	assert_true(MarketConfig.has_method("get_fee_breakdown"), "get_fee_breakdown 존재")
	assert_true(MarketConfig.has_method("get_buy_cost"),      "get_buy_cost 존재")
	assert_true(MarketConfig.has_method("get_active_market"), "get_active_market 존재")


# ── CurrencySystem (S8-06 dual-economy 확장) ─────────────────────────

func test_currency_system_cash_assets_api():
	assert_true(CurrencySystem.has_method("get_cash_assets"),       "get_cash_assets 존재")
	assert_true(CurrencySystem.has_method("get_total_prize_earned"), "get_total_prize_earned 존재")
	assert_true(CurrencySystem.has_method("cash_add"),              "cash_add 존재")
	assert_true(CurrencySystem.has_method("cash_deduct"),           "cash_deduct 존재")
	assert_true(CurrencySystem.has_method("auto_deposit_to_sim"),   "auto_deposit_to_sim 존재")


# ── LifestyleManager ──────────────────────────────────────────────────

func test_lifestyle_manager_api():
	assert_true(LifestyleManager.has_method("get_tangible_value"),      "get_tangible_value 존재")
	assert_true(LifestyleManager.has_method("get_residence_tier"),      "get_residence_tier 존재")
	assert_true(LifestyleManager.has_method("get_residence_name"),      "get_residence_name 존재")
	assert_true(LifestyleManager.has_method("get_titles"),              "get_titles 존재")
	assert_true(LifestyleManager.has_method("has_luxury"),              "has_luxury 존재")
	assert_true(LifestyleManager.has_method("upgrade_residence"),       "upgrade_residence 존재")
	assert_true(LifestyleManager.has_method("purchase_luxury"),         "purchase_luxury 존재")
	assert_true(LifestyleManager.has_method("purchase_property"),       "purchase_property 존재")
	assert_true(LifestyleManager.has_method("add_recurring_cost"),      "add_recurring_cost 존재")
	assert_true(LifestyleManager.has_method("mark_luxury_owned"),       "mark_luxury_owned 존재")
	assert_true(LifestyleManager.has_method("purchase_network_item"),   "purchase_network_item 존재")
	assert_true(LifestyleManager.has_method("purchase_social_item"),    "purchase_social_item 존재")
	assert_true(LifestyleManager.has_method("donate"),                  "donate 존재")
	assert_true(LifestyleManager.has_method("invest_startup"),          "invest_startup 존재")
	assert_true(LifestyleManager.has_method("process_market_close"),    "process_market_close 존재")
	assert_true(LifestyleManager.has_method("reset"),                   "LifestyleManager.reset 존재")


# ── reset() 계약 ─────────────────────────────────────────────────────
## 모든 autoload 시스템이 reset()을 구현해야 한다.
## 실패 = 테스트 격리 불가 → 상태 오염으로 인한 플레이크 테스트

func test_all_systems_have_reset():
	assert_true(GameClock.has_method("reset"),          "GameClock.reset 존재")
	assert_true(CurrencySystem.has_method("reset"),     "CurrencySystem.reset 존재")
	assert_true(PortfolioManager.has_method("reset"),   "PortfolioManager.reset 존재")
	assert_true(OrderEngine.has_method("reset"),        "OrderEngine.reset 존재")
	assert_true(XpSystem.has_method("reset"),           "XpSystem.reset 존재")
	assert_true(SkillTree.has_method("reset"),          "SkillTree.reset 존재")
	assert_true(PriceEngine.has_method("reset"),        "PriceEngine.reset 존재")
	assert_true(NewsEventSystem.has_method("reset"),    "NewsEventSystem.reset 존재")
	assert_true(AiCompetitor.has_method("reset"),       "AiCompetitor.reset 존재")
	assert_true(SeasonManager.has_method("reset"),      "SeasonManager.reset 존재")
	assert_true(StopTakeSystem.has_method("reset"),      "StopTakeSystem.reset 존재")
	assert_true(LifestyleManager.has_method("reset"),   "LifestyleManager.reset 존재")
	assert_true(ShortSellingSystem.has_method("reset"), "ShortSellingSystem.reset 존재")
	assert_true(LeverageManager.has_method("reset"),    "LeverageManager.reset 존재")


# ── ShortSellingSystem (TR3) ─────────────────────────────────────────
## Implements: design/gdd/short-selling.md §9 Implementation Checklist

func test_short_selling_system_api():
	assert_true(ShortSellingSystem.has_method("has_short"),                    "has_short 존재")
	assert_true(ShortSellingSystem.has_method("get_short_count"),              "get_short_count 존재")
	assert_true(ShortSellingSystem.has_method("get_max_short_positions"),      "get_max_short_positions 존재")
	assert_true(ShortSellingSystem.has_method("get_margin_rate"),              "get_margin_rate 존재")
	assert_true(ShortSellingSystem.has_method("get_all_short_positions"),      "get_all_short_positions 존재")
	assert_true(ShortSellingSystem.has_method("get_short_net_value"),          "get_short_net_value 존재")
	assert_true(ShortSellingSystem.has_method("open_position"),                "open_position 존재")
	assert_true(ShortSellingSystem.has_method("close_position"),               "close_position 존재")
	assert_true(ShortSellingSystem.has_method("update_and_check_margin"),      "update_and_check_margin 존재")
	assert_true(ShortSellingSystem.has_method("liquidate_all_for_season_end"), "liquidate_all_for_season_end 존재")
	assert_true(ShortSellingSystem.has_method("get_save_data"),                "get_save_data 존재")
	assert_true(ShortSellingSystem.has_method("load_save_data"),               "load_save_data 존재")
	assert_true(ShortSellingSystem.has_method("reset"),                        "reset 존재")


func test_short_selling_signals():
	var signal_list: Array = ShortSellingSystem.get_signal_list()
	var signal_names: Array[String] = []
	for s: Dictionary in signal_list:
		signal_names.append(s["name"])
	assert_true("on_forced_liquidation" in signal_names,    "on_forced_liquidation 시그널 존재")
	assert_true("on_short_position_closed" in signal_names, "on_short_position_closed 시그널 존재")


# ── LeverageManager (TR4) ────────────────────────────────────────────
## Implements: design/gdd/leverage-trading.md §9 Implementation Checklist

func test_leverage_manager_api():
	assert_true(LeverageManager.has_method("has_leverage_position"),   "has_leverage_position 존재")
	assert_true(LeverageManager.has_method("get_all_positions"),       "get_all_positions 존재")
	assert_true(LeverageManager.has_method("is_valid_multiplier"),     "is_valid_multiplier 존재")
	assert_true(LeverageManager.has_method("get_leverage_net_value"),  "get_leverage_net_value 존재")
	assert_true(LeverageManager.has_method("open_position"),           "open_position 존재")
	assert_true(LeverageManager.has_method("close_position"),          "close_position 존재")
	assert_true(LeverageManager.has_method("check_margin_calls"),      "check_margin_calls 존재")
	assert_true(LeverageManager.has_method("process_daily_interest"),  "process_daily_interest 존재")
	assert_true(LeverageManager.has_method("liquidate_all_positions"), "liquidate_all_positions 존재")
	assert_true(LeverageManager.has_method("add_margin"),              "add_margin 존재")
	assert_true(LeverageManager.has_method("get_save_data"),           "get_save_data 존재")
	assert_true(LeverageManager.has_method("load_save_data"),          "load_save_data 존재")
	assert_true(LeverageManager.has_method("reset"),                   "reset 존재")


func test_leverage_manager_signals():
	var signal_list: Array = LeverageManager.get_signal_list()
	var signal_names: Array[String] = []
	for s: Dictionary in signal_list:
		signal_names.append(s["name"])
	assert_true("on_margin_call" in signal_names,                "on_margin_call 시그널 존재")
	assert_true("on_leverage_forced_liquidation" in signal_names, "on_leverage_forced_liquidation 시그널 존재")
	assert_true("on_leverage_position_closed" in signal_names,   "on_leverage_position_closed 시그널 존재")
