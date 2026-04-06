## StatusBar — 상태바 행 1/2, 진행바, 배속 버튼, 리그 HUD.
## 틱마다 행 1(클럭/틱), 자산 변동 시 행 2(자산/리그) 갱신.
## See: design/gdd/trading-screen.md §10, §규칙 2
class_name StatusBar
extends VBoxContainer

## Emitted when the league HUD label is clicked → TradingScreen relays to league_tab_requested.
signal league_hud_clicked
## Emitted when pause button pressed → TradingScreen relays to pause_toggle_requested.
signal pause_toggled
## Emitted when a speed button pressed → TradingScreen relays to speed_change_requested.
signal speed_changed(multiplier: float)
## Emitted when the market-open / season-start button is pressed.
signal market_open_pressed

## Exposed for TradingScreen to wire skill-tree toggle.
var xp_bar: XpBar

var _lbl_season_info: Label
var _lbl_tick_progress: Label
var _progress_bar: ProgressBar
var _lbl_speed: Label
var _btn_speed_1x: Button
var _btn_speed_2x: Button
var _btn_speed_4x: Button
var _btn_pause: Button
var _btn_market_open: Button
var _lbl_market_index: Label
var _lbl_total_assets: Label
var _lbl_cash: Label
var _lbl_league_tier: Label
var _lbl_season_return: Label
var _lbl_weekly_return: Label
var _lbl_sp_alert: Label
var _ui_state: int = -1   ## mirrors TradingScreen.UIState (int)

## Mirrors TradingScreen.UIState enum values — kept in sync with trading_screen.gd.
const _STATE_PRE_MARKET: int = 1
const _STATE_MARKET_OPEN: int = 2
const _STATE_PAUSED: int = 3


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_build_row1()
	_build_row2()
	_build_sp_alert()
	GameClock.on_tick.connect(_on_tick)
	CurrencySystem.sim_cash_changed.connect(func(_a: int, _d: int) -> void: _update_row2())
	# valuation_updated is intentionally NOT connected here — on_tick already fires _update_row2()
	# after OrderEngine._on_tick() has updated valuation, so connecting both would fire twice per tick.


func _build_row1() -> void:
	var row1_panel: PanelContainer = PanelContainer.new()
	row1_panel.add_theme_stylebox_override("panel", ThemeSetup.make_panel_style(ThemeSetup.BG_PANEL, 0, ThemeSetup.BORDER_DIM))
	add_child(row1_panel)
	var row1: HBoxContainer = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	row1_panel.add_child(row1)
	_lbl_season_info = Label.new()
	_lbl_season_info.text = "1주차 월요일"
	_lbl_season_info.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_primary(_lbl_season_info)
	row1.add_child(_lbl_season_info)
	var sep1: VSeparator = VSeparator.new()
	sep1.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	row1.add_child(sep1)
	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.custom_minimum_size.x = 80
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.show_percentage = false
	row1.add_child(_progress_bar)
	_lbl_tick_progress = Label.new()
	_lbl_tick_progress.text = "틱 0/%d" % GameClock.TICKS_PER_DAY
	_lbl_tick_progress.add_theme_font_size_override("font_size", 11)
	row1.add_child(_lbl_tick_progress)
	row1.add_child(VSeparator.new())
	_build_speed_controls(row1)
	_btn_market_open = Button.new()
	_btn_market_open.text = "시즌 시작 Enter"
	_btn_market_open.visible = false
	_btn_market_open.pressed.connect(func() -> void: market_open_pressed.emit())
	ThemeSetup.apply_accent_button(_btn_market_open)
	row1.add_child(_btn_market_open)


func _build_speed_controls(row: HBoxContainer) -> void:
	_lbl_speed = Label.new()
	_lbl_speed.text = "▶ 1x"
	_lbl_speed.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_primary(_lbl_speed)
	row.add_child(_lbl_speed)
	_btn_speed_1x = Button.new()
	_btn_speed_1x.text = "1x"
	_btn_speed_1x.pressed.connect(func() -> void: speed_changed.emit(1.0))
	ThemeSetup.apply_accent_button(_btn_speed_1x)
	row.add_child(_btn_speed_1x)
	_btn_speed_2x = Button.new()
	_btn_speed_2x.text = "2x"
	_btn_speed_2x.pressed.connect(func() -> void: speed_changed.emit(2.0))
	ThemeSetup.apply_button_theme(_btn_speed_2x)
	row.add_child(_btn_speed_2x)
	_btn_speed_4x = Button.new()
	_btn_speed_4x.text = "4x"
	_btn_speed_4x.pressed.connect(func() -> void: speed_changed.emit(4.0))
	ThemeSetup.apply_button_theme(_btn_speed_4x)
	row.add_child(_btn_speed_4x)
	_btn_pause = Button.new()
	_btn_pause.text = "⏸"
	_btn_pause.pressed.connect(func() -> void: pause_toggled.emit())
	ThemeSetup.apply_button_theme(_btn_pause)
	row.add_child(_btn_pause)


func _build_row2() -> void:
	var row2_panel: PanelContainer = PanelContainer.new()
	row2_panel.add_theme_stylebox_override("panel", ThemeSetup.make_panel_style(ThemeSetup.BG_DARK, 0, ThemeSetup.BORDER_DIM))
	add_child(row2_panel)
	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	row2_panel.add_child(row2)
	_lbl_market_index = Label.new()
	_lbl_market_index.text = "지수 1,000.0 (0.00%)"
	_lbl_market_index.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_primary(_lbl_market_index)
	row2.add_child(_lbl_market_index)
	var sep_r2: VSeparator = VSeparator.new()
	sep_r2.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	row2.add_child(sep_r2)
	_lbl_total_assets = Label.new()
	_lbl_total_assets.text = "총 자산: ₩0"
	_lbl_total_assets.add_theme_font_size_override("font_size", 13)
	ThemeSetup.style_label_primary(_lbl_total_assets)
	row2.add_child(_lbl_total_assets)
	_lbl_cash = Label.new()
	_lbl_cash.text = "현금: ₩0"
	_lbl_cash.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_secondary(_lbl_cash)
	row2.add_child(_lbl_cash)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(spacer)
	_build_league_hud(row2)
	xp_bar = XpBar.new()
	row2.add_child(xp_bar)


func _build_league_hud(row: HBoxContainer) -> void:
	_lbl_league_tier = Label.new()
	_lbl_league_tier.text = "프리마켓"
	_lbl_league_tier.add_theme_font_size_override("font_size", 12)
	_lbl_league_tier.mouse_filter = Control.MOUSE_FILTER_STOP
	_lbl_league_tier.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_lbl_league_tier.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			league_hud_clicked.emit()
	)
	ThemeSetup.style_label_secondary(_lbl_league_tier)
	row.add_child(_lbl_league_tier)
	var s1: VSeparator = VSeparator.new()
	s1.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	row.add_child(s1)
	_lbl_season_return = Label.new()
	_lbl_season_return.text = "시즌 -"
	_lbl_season_return.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_secondary(_lbl_season_return)
	row.add_child(_lbl_season_return)
	var s2: VSeparator = VSeparator.new()
	s2.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	row.add_child(s2)
	_lbl_weekly_return = Label.new()
	_lbl_weekly_return.text = "주간 -"
	_lbl_weekly_return.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_secondary(_lbl_weekly_return)
	row.add_child(_lbl_weekly_return)
	var s3: VSeparator = VSeparator.new()
	s3.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	row.add_child(s3)


func _build_sp_alert() -> void:
	_lbl_sp_alert = Label.new()
	_lbl_sp_alert.visible = false
	_lbl_sp_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_sp_alert.add_theme_font_size_override("font_size", 12)
	_lbl_sp_alert.add_theme_color_override("font_color", Color(0.85, 0.70, 0.20))
	add_child(_lbl_sp_alert)


func _on_tick(_tick: int, _day: int, _week: int) -> void:
	_update_row1()
	_update_row2()


func _update_row1() -> void:
	var day: int = GameClock.get_current_day()
	var week: int = GameClock.get_current_week()
	var day_names: Array[String] = ["월", "화", "수", "목", "금"]
	var day_in_week: int = day % GameClock.DAYS_PER_WEEK
	var day_name: String = day_names[day_in_week] if day_in_week < day_names.size() else "?"
	_lbl_season_info.text = "%d주차 %s요일" % [week + 1, day_name]
	var tick: int = GameClock.get_current_tick()
	_lbl_tick_progress.text = "틱 %d/%d" % [tick, GameClock.TICKS_PER_DAY]
	_progress_bar.value = GameClock.get_day_progress() * 100.0
	_update_speed_label()


func _update_speed_label() -> void:
	if _ui_state == _STATE_PAUSED:
		_lbl_speed.text = "⏸ 일시정지"
		return
	var spd: float = GameClock.get_speed_multiplier()
	if spd <= 1.0:
		_lbl_speed.text = "▶ 1x"
	elif spd <= 2.0:
		_lbl_speed.text = "▶▶ 2x"
	else:
		_lbl_speed.text = "▶▶▶▶ 4x"


func _update_row2() -> void:
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	var total: int = summary["total_assets"]
	var rate: float = summary["return_rate"]
	_lbl_total_assets.text = "총 자산: ₩%s" % FormatUtils.number(total)
	if rate > 0.0:
		_lbl_total_assets.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	elif rate < 0.0:
		_lbl_total_assets.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)
	else:
		_lbl_total_assets.add_theme_color_override("font_color", ThemeSetup.NEUTRAL_GRAY)
	_update_cash_label()
	_update_index_label()
	_update_league_hud()


func _update_cash_label() -> void:
	var cash: int = CurrencySystem.get_sim_cash()
	var reserved: int = OrderEngine.get_total_reserved_cash()
	var holdings_count: int = PortfolioManager.get_all_holdings().size()
	var max_holdings: int = SkillTree.get_max_holdings()
	if reserved > 0:
		_lbl_cash.text = "시드: ₩%s (예약: ₩%s) | 보유 %d/%d" % [
			FormatUtils.number(cash), FormatUtils.number(reserved), holdings_count, max_holdings]
	else:
		_lbl_cash.text = "시드: ₩%s | 보유 %d/%d" % [FormatUtils.number(cash), holdings_count, max_holdings]


func _update_index_label() -> void:
	var index_val: float = PriceEngine.get_market_index()
	var index_change: float = PriceEngine.get_index_change_pct()
	var sign_str: String = "+" if index_change >= 0.0 else ""
	_lbl_market_index.text = "지수 %s (%s%.2f%%)" % [
		FormatUtils.number(roundi(index_val)), sign_str, index_change]


func _update_league_hud() -> void:
	if SeasonManager.get_is_free_market():
		_lbl_league_tier.text = "프리마켓"
		_lbl_season_return.text = "시즌 -"
		_lbl_weekly_return.text = "주간 -"
		return
	var tier_rank: int = SeasonManager.get_tier_rank()
	var tier_name: String = SeasonManager.get_tier_name(SeasonManager.get_current_tier())
	_lbl_league_tier.text = "%s %d위" % [tier_name, tier_rank] if tier_rank > 0 else tier_name
	var s_ret: float = SeasonManager.get_season_return_pct()
	var w_ret: float = SeasonManager.get_weekly_return_pct()
	_lbl_season_return.text = "시즌 %+.1f%%" % s_ret
	_lbl_weekly_return.text = "주간 %+.1f%%" % w_ret
	_apply_return_color(_lbl_season_return, s_ret)
	_apply_return_color(_lbl_weekly_return, w_ret)


func _apply_return_color(lbl: Label, value: float) -> void:
	if value > 0.0:
		lbl.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	elif value < 0.0:
		lbl.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)
	else:
		lbl.add_theme_color_override("font_color", ThemeSetup.NEUTRAL_GRAY)


## Called by TradingScreen when UIState changes. Controls speed/pause visibility and SP alert.
func set_ui_state(state: int) -> void:
	_ui_state = state
	var speed_visible: bool = state == _STATE_MARKET_OPEN or state == _STATE_PAUSED
	_btn_speed_1x.visible = speed_visible
	_btn_speed_2x.visible = speed_visible
	_btn_speed_4x.visible = speed_visible
	_btn_pause.visible = speed_visible
	_lbl_speed.visible = speed_visible
	_btn_market_open.visible = (state == _STATE_PRE_MARKET)
	if state == _STATE_PRE_MARKET:
		_btn_market_open.text = "장 시작 Enter" if SeasonManager.is_season_active() else "시즌 시작 Enter"
		_update_sp_alert()
	else:
		_lbl_sp_alert.visible = false
	if speed_visible:
		_update_speed_buttons(GameClock.get_speed_multiplier())
	_update_row1()
	_update_row2()


func _update_speed_buttons(multiplier: float) -> void:
	var btns: Array[Button] = [_btn_speed_1x, _btn_speed_2x, _btn_speed_4x]
	var vals: Array[float] = [1.0, 2.0, 4.0]
	for i: int in range(btns.size()):
		if absf(vals[i] - multiplier) < 0.1:
			ThemeSetup.apply_accent_button(btns[i])
		else:
			ThemeSetup.apply_button_theme(btns[i])


func _update_sp_alert() -> void:
	var sp: int = XpSystem.get_available_skill_points()
	if sp > 0:
		_lbl_sp_alert.text = "미사용 스킬 포인트 %d개 — 스킬 트리 열기 K" % sp
		_lbl_sp_alert.visible = true
	else:
		_lbl_sp_alert.visible = false


## Called by TradingScreen after speed changes via keyboard.
func update_speed(multiplier: float) -> void:
	_update_speed_buttons(multiplier)
	_update_speed_label()
