## API Contract Tests — 외부 메서드 존재 + 시그널 시그니처 검증
## 새 시스템 추가 시 이 파일에 계약 테스트를 추가해야 한다.
## 실패 = "존재하지 않는 메서드를 호출하거나 시그널 타입이 맞지 않음"
## See: .claude/docs/coding-standards.md — Code Review Checklist
extends GutTest

# ── EndingScreen (S10-03) ─────────────────────────────────────
## Implements: design/gdd/endings-achievements.md §3 (3종 엔딩 화면)

func test_ending_screen_api():
	var scr: EndingScreen = EndingScreen.new()
	add_child_autofree(scr)
	assert_true(scr.has_method("show_ending"),   "show_ending 존재")
	assert_true(scr.has_method("is_bad_ending"), "is_bad_ending 존재")
	assert_true(scr.has_signal("new_game_requested"), "new_game_requested 시그널 존재")
	assert_true(scr.has_signal("continue_requested"), "continue_requested 시그널 존재")
	assert_true("_lbl_title" in scr,  "_lbl_title 속성 존재")
	assert_true("_lbl_body" in scr,   "_lbl_body 속성 존재")
	assert_true("_btn_action" in scr, "_btn_action 속성 존재")


# ── MarginCallPopup (S10-03) ──────────────────────────────────
## Implements: design/gdd/leverage-trading.md §3-3 마진콜 팝업

func test_margin_call_popup_api():
	var popup: MarginCallPopup = MarginCallPopup.new()
	add_child_autofree(popup)
	assert_true(popup.has_method("show_warning"), "show_warning 존재")
	assert_true(popup.has_method("cancel"),       "cancel 존재")
	assert_true("_panel" in popup,          "_panel 속성 존재")
	assert_true("_lbl_title" in popup,      "_lbl_title 속성 존재")
	assert_true("_lbl_countdown" in popup,  "_lbl_countdown 속성 존재")

# ── CurrencySystem ──────────────────────────────────────────────────

func test_currency_system_api():
	assert_true(CurrencySystem.has_method("init_first_season"), "init_first_season 존재")
	assert_true(CurrencySystem.has_method("get_sim_cash"),      "get_sim_cash 존재")
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
	assert_true(GameClock.has_method("set_speed"),                  "set_speed 존재")
	assert_true(GameClock.has_method("get_auto_slow_on_event"),     "get_auto_slow_on_event 존재")
	assert_true(GameClock.has_method("set_auto_slow_on_event"),     "set_auto_slow_on_event 존재")


# ── XpSystem ────────────────────────────────────────────────────────

func test_xp_system_api():
	assert_true(XpSystem.has_method("get_total_xp"),                "get_total_xp 존재")
	assert_true(XpSystem.has_method("get_current_level"),           "get_current_level 존재")
	assert_true(XpSystem.has_method("get_xp_progress"),             "get_xp_progress 존재")
	assert_true(XpSystem.has_method("get_available_skill_points"),  "get_available_skill_points 존재")
	assert_true(XpSystem.has_method("get_cumulative_xp_for_level"), "get_cumulative_xp_for_level 존재")
	assert_true(XpSystem.has_method("grant_season_bonus"),          "grant_season_bonus 존재")
	assert_true(XpSystem.has_method("grant_weekly_prize_xp"),       "grant_weekly_prize_xp 존재")
	assert_true(XpSystem.has_method("grant_lifestyle_xp"),          "grant_lifestyle_xp 존재")
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
	assert_true(EtfManager.has_method("reset"),                "EtfManager.reset 존재")
	assert_true(OhlcvHistory.has_method("reset"),              "OhlcvHistory.reset 존재")
	assert_true(FinancialReportSystem.has_method("reset"),     "FinancialReportSystem.reset 존재")
	assert_true(MarketProfile.has_method("load_market"),       "MarketProfile.load_market 존재")


# ── OhlcvHistory (S9-07) ─────────────────────────────────────────────
## Implements: design/gdd/price-engine.md §OHLCV (cross-season history accumulation)

func test_ohlcv_history_api():
	assert_true(OhlcvHistory.has_method("reset"),              "reset 존재")
	assert_true(OhlcvHistory.has_method("get_candles"),        "get_candles 존재")
	assert_true(OhlcvHistory.has_method("get_all_daily_bars"), "get_all_daily_bars 존재")
	assert_true(OhlcvHistory.has_method("get_past_bar_count"), "get_past_bar_count 존재")
	assert_true(OhlcvHistory.has_method("get_save_data"),      "get_save_data 존재")
	assert_true(OhlcvHistory.has_method("load_save_data"),     "load_save_data 존재")
	assert_true("history_seed" in OhlcvHistory,                "history_seed 속성 존재")


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
	assert_true(LeverageManager.has_method("has_leverage_position"),      "has_leverage_position 존재")
	assert_true(LeverageManager.has_method("get_all_positions"),          "get_all_positions 존재")
	assert_true(LeverageManager.has_method("is_valid_multiplier"),        "is_valid_multiplier 존재")
	assert_true(LeverageManager.has_method("get_leverage_net_value"),     "get_leverage_net_value 존재")
	assert_true(LeverageManager.has_method("get_margin_call_threshold"),  "get_margin_call_threshold 존재")
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


# ── AudioManager ─────────────────────────────────────────────────────
## TD-CR-22: BGM/SFX 독립 버스 볼륨 제어 API

func test_audio_manager_bus_volume_api():
	assert_true(AudioManager.has_method("set_bgm_volume"), "set_bgm_volume 존재")
	assert_true(AudioManager.has_method("set_sfx_volume"), "set_sfx_volume 존재")


# ── SaveSystem ───────────────────────────────────────────────────────
## Implements: design/gdd/save-load.md (TD-CR-01 — get_active_slot_id getter)

func test_save_system_api():
	assert_true(SaveSystem.has_method("get_active_slot_id"), "get_active_slot_id 존재")
	assert_true(SaveSystem.has_method("is_save_pending"),    "is_save_pending 존재")
	assert_true(SaveSystem.has_method("get_slot_list"),      "get_slot_list 존재")
	assert_true(SaveSystem.has_method("create_slot"),        "create_slot 존재")
	assert_true(SaveSystem.has_method("load_slot"),          "load_slot 존재")
	assert_true(SaveSystem.has_method("save_slot"),          "save_slot 존재")
	assert_true(SaveSystem.has_method("delete_slot"),        "delete_slot 존재")
	assert_true(SaveSystem.has_method("rename_slot"),        "rename_slot 존재")
	assert_true(SaveSystem.has_method("is_slot_valid"),      "is_slot_valid 존재")


# ── EtfManager (S10-02) ──────────────────────────────────────────────
## Implements: design/gdd/sector-etf.md §3-7 Public API

func test_etf_manager_api():
	assert_true(EtfManager.has_method("get_sector_stocks"),   "get_sector_stocks 존재")
	assert_true(EtfManager.has_method("get_etf_return"),      "get_etf_return 존재")
	assert_true(EtfManager.has_method("get_etf_price"),       "get_etf_price 존재")
	assert_true(EtfManager.has_method("get_etf_open_price"),  "get_etf_open_price 존재")
	assert_true(EtfManager.has_method("get_sector_flow"),     "get_sector_flow 존재")
	assert_true(EtfManager.has_method("is_etf"),              "is_etf 존재")
	assert_true(EtfManager.has_method("get_all_etf_ids"),     "get_all_etf_ids 존재")
	assert_true(EtfManager.has_method("process_tick"),        "process_tick 존재")
	assert_true(EtfManager.has_method("get_save_data"),       "get_save_data 존재")
	assert_true(EtfManager.has_method("load_save_data"),      "load_save_data 존재")
	assert_true(EtfManager.has_method("reset"),               "reset 존재")


# ── PriceEngine.inject_price (S10-02) ────────────────────────────────
## Implements: design/gdd/sector-etf.md §3-2 ETF price injection API

func test_price_engine_inject_price_api():
	assert_true(PriceEngine.has_method("inject_price"), "inject_price 존재")


# ── NewsEventSystem.inject_event (S10-02 / S10-05) ───────────────────
## Implements: ADR-022 EventSource pipeline — external injection endpoint

func test_news_event_system_inject_event_api():
	assert_true(NewsEventSystem.has_method("inject_event"), "inject_event 존재")


# ── ProfitCelebration (S10-04) ───────────────────────────────────────
## Implements: design/gdd/profit-celebration.md §3-7 / §9

func test_profit_celebration_api():
	var pc: ProfitCelebration = ProfitCelebration.new()
	add_child_autofree(pc)
	assert_true(pc.has_method("play"),                   "play 존재")
	assert_true(pc.has_method("_calc_grade"),            "_calc_grade 존재")
	assert_true(pc.has_method("_cancel_current"),        "_cancel_current 존재")
	assert_true(pc.has_method("cancel_from_screen_change"), "cancel_from_screen_change 존재")
	assert_true("_is_playing" in pc,                     "_is_playing 속성 존재")
	assert_true("_current_grade" in pc,                  "_current_grade 속성 존재")
	assert_true("_rollup_label" in pc,                   "_rollup_label 속성 존재")
	assert_true("_flash_rect" in pc,                     "_flash_rect 속성 존재")
	assert_true("_banner_label" in pc,                   "_banner_label 속성 존재")
	assert_true("GRADE_MEDIUM_THRESHOLD" in ProfitCelebration,  "GRADE_MEDIUM_THRESHOLD 상수 존재")
	assert_true("GRADE_LARGE_THRESHOLD" in ProfitCelebration,   "GRADE_LARGE_THRESHOLD 상수 존재")
	assert_true("GRADE_JACKPOT_THRESHOLD" in ProfitCelebration, "GRADE_JACKPOT_THRESHOLD 상수 존재")


# ── SectorComparisonView (S10-01) ────────────────────────────────────
## Implements: design/gdd/sector-comparison.md §8 AC-01 ~ AC-09

func test_sector_comparison_view_api():
	var view: SectorComparisonView = SectorComparisonView.new()
	add_child_autofree(view)
	assert_true(view.has_method("refresh"),              "refresh 존재")
	assert_true(view.has_method("_refresh"),             "_refresh 존재")
	assert_true(view.has_method("_set_sort_mode"),       "_set_sort_mode 존재")
	assert_true(view.has_method("_toggle_drilldown"),    "_toggle_drilldown 존재")
	assert_true(view.has_method("_open_drilldown"),      "_open_drilldown 존재")
	assert_true(view.has_method("_close_drilldown"),     "_close_drilldown 존재")
	assert_true(view.has_method("_calc_today_return"),   "_calc_today_return 존재")
	assert_true(view.has_method("_format_pct"),          "_format_pct 존재")
	assert_true(view.has_method("_format_price"),        "_format_price 존재")
	assert_true("_sort_mode" in view,                    "_sort_mode 속성 존재")
	assert_true("_drilldown_sector" in view,             "_drilldown_sector 속성 존재")
	assert_true("_rows_container" in view,               "_rows_container 속성 존재")
	assert_true("_drilldown_panel" in view,              "_drilldown_panel 속성 존재")
	assert_true("_locked_label" in view,                 "_locked_label 속성 존재")
	assert_true("_main_panel" in view,                   "_main_panel 속성 존재")


# ── FinancialReportSystem (S10-05) ───────────────────────────────────
## Implements: design/gdd/financial-report-system.md §8 AC-FR-01, AC-FR-02

func test_financial_report_system_api():
	assert_true(FinancialReportSystem.has_method("is_report_season"),           "is_report_season 존재")
	assert_true(FinancialReportSystem.has_method("get_report_type"),            "get_report_type 존재")
	assert_true(FinancialReportSystem.has_method("schedule_quarterly_events"),  "schedule_quarterly_events 존재")
	assert_true(FinancialReportSystem.has_method("get_pending_events"),         "get_pending_events 존재")
	assert_true(FinancialReportSystem.has_method("reset"),                      "reset 존재")
	assert_true(FinancialReportSystem.has_method("get_save_data"),              "get_save_data 존재")
	assert_true(FinancialReportSystem.has_method("load_save_data"),             "load_save_data 존재")
	assert_true(FinancialReportSystem.has_method("_load_from_market_profile"),  "_load_from_market_profile 존재")
	assert_true("_pending_events" in FinancialReportSystem,                  "_pending_events 속성 존재")
	assert_true("_current_season" in FinancialReportSystem,                  "_current_season 속성 존재")
	assert_true("REPORT_CYCLE_SEASONS" in FinancialReportSystem,             "REPORT_CYCLE_SEASONS 상수 존재")
	assert_true("REPORT_TYPE_SEQUENCE" in FinancialReportSystem,             "REPORT_TYPE_SEQUENCE 상수 존재")
	assert_true("PRELIMINARY_PROBABILITY" in FinancialReportSystem,          "PRELIMINARY_PROBABILITY 상수 존재")


# ── NewsEventSystem.fire_stock_news (S10-05) ────────────────────────────────
## Implements: ADR-022 — FinancialReportSystem uses fire_stock_news for earnings cards

func test_news_event_system_fire_stock_news_api():
	assert_true(NewsEventSystem.has_method("fire_stock_news"), "fire_stock_news 존재")
	assert_true(NewsEventSystem.has_method("_calc_template_weight"), "_calc_template_weight 존재")


# ── ShortSellingSystem.MIN_MARGIN_RATE (S10-06e) ─────────────────────────────

func test_short_selling_min_margin_rate_api():
	assert_true("MIN_MARGIN_RATE" in ShortSellingSystem, "MIN_MARGIN_RATE 상수 존재")


# ── MarketProfile (S10-07) ─────────────────────────────────────────────────
## Implements: docs/architecture/ADR-021

# ── StockDatabase (S10-08) ──────────────────────────────────────────────────
## Implements: src/core/stock_database.gd public API

func test_stock_database_api():
	assert_true(StockDatabase.has_method("get_stock"),              "get_stock 존재")
	assert_true(StockDatabase.has_method("stock_exists"),           "stock_exists 존재")
	assert_true(StockDatabase.has_method("get_all_stock_ids"),      "get_all_stock_ids 존재")
	assert_true(StockDatabase.has_method("get_all_stocks"),         "get_all_stocks 존재")
	assert_true(StockDatabase.has_method("get_stock_count"),        "get_stock_count 존재")
	assert_true(StockDatabase.has_method("get_all_sectors"),        "get_all_sectors 존재")
	assert_true(StockDatabase.has_method("get_stocks_by_sector"),   "get_stocks_by_sector 존재")
	assert_true(StockDatabase.has_method("get_stock_ids_by_sector"), "get_stock_ids_by_sector 존재")


# ── FormatUtils (S10-08) ────────────────────────────────────────────────────
## FormatUtils는 static class_name (autoload 아님) — 동작 테스트는 test_core_systems.gd에 위임.
## API contracts 파일은 autoload 공개 API 계약만 검증한다.
## 관련 테스트: tests/unit/test_core_systems.gd func test_format_utils_*


# ── PortfolioManager (S10-08) ──────────────────────────────────────────────
## Implements: src/gameplay/portfolio_manager.gd public API

func test_portfolio_manager_extended_api():
	assert_true(PortfolioManager.has_method("get_holding_count"),       "get_holding_count 존재")
	assert_true(PortfolioManager.has_method("get_total_assets"),        "get_total_assets 존재")
	assert_true(PortfolioManager.has_method("get_account_total_value"), "get_account_total_value 존재")
	assert_true(PortfolioManager.has_method("get_return_rate"),         "get_return_rate 존재")
	assert_true(PortfolioManager.has_method("get_transaction_history"), "get_transaction_history 존재")
	assert_true(PortfolioManager.has_method("update_valuation"),        "update_valuation 존재")
	assert_true(PortfolioManager.has_method("get_save_data"),           "get_save_data 존재")
	assert_true(PortfolioManager.has_method("load_save_data"),          "load_save_data 존재")
	assert_true(PortfolioManager.has_method("reset"),                   "reset 존재")


# ── CurrencySystem (S10-08) ────────────────────────────────────────────────
## Implements: src/core/currency_system.gd public API

func test_currency_system_extended_api():
	assert_true(CurrencySystem.has_method("get_cash_assets"),      "get_cash_assets 존재")
	assert_true(CurrencySystem.has_method("auto_deposit_to_sim"),  "auto_deposit_to_sim 존재")
	assert_true(CurrencySystem.has_method("get_save_data"),        "get_save_data 존재")
	assert_true(CurrencySystem.has_method("load_save_data"),       "load_save_data 존재")


# ── MarketProfile (S10-07) ─────────────────────────────────────────────────
## Implements: docs/architecture/ADR-021

func test_market_profile_api():
	assert_true(MarketProfile.has_method("load_market"),              "load_market 존재")
	assert_true(MarketProfile.has_method("get_active_market_id"),     "get_active_market_id 존재")
	assert_true(MarketProfile.has_method("get_active"),               "get_active 존재")
	assert_true(MarketProfile.has_method("get_sectors"),              "get_sectors 존재")
	assert_true(MarketProfile.has_method("get_etfs"),                 "get_etfs 존재")
	assert_true(MarketProfile.has_method("get_archetype"),            "get_archetype 존재")
	assert_true(MarketProfile.has_method("get_sectors_in_archetype"), "get_sectors_in_archetype 존재")
	assert_true(MarketProfile.has_method("get_rivalry_weights"),      "get_rivalry_weights 존재")
	assert_true(MarketProfile.has_method("get_rotation_params"),      "get_rotation_params 존재")
	assert_true(MarketProfile.has_method("get_rotation_headline"),    "get_rotation_headline 존재")
	assert_true(MarketProfile.has_method("get_trading_param"),        "get_trading_param 존재")
	assert_true(MarketProfile.has_method("get_calendar_param"),       "get_calendar_param 존재")
	assert_true(MarketProfile.has_method("get_ending_param"),         "get_ending_param 존재")
	assert_true(MarketProfile.has_method("get_ending_ids"),           "get_ending_ids 존재")
	assert_true(MarketProfile.has_method("get_dlc_achievements"),     "get_dlc_achievements 존재")
