## StatusBar — 상태바 행 1/2, 진행바, 배속 버튼, 리그 HUD.
## 틱마다 행 1(클럭/틱), 자산 변동 시 행 2(자산/리그) 갱신.
## See: design/gdd/trading-screen.md §10, §규칙 2
class_name StatusBar
extends VBoxContainer

## Mirrors TradingScreen.UIState to break circular class_name dependency.
## Both enums must have identical values — if TradingScreen.UIState changes, update here too.
enum UIState {
	LOADING,
	PRE_MARKET,
	MARKET_OPEN,
	PAUSED,
	SETTLEMENT,
	SEASON_RESULT,
}

## Emitted when the league HUD label is clicked → TradingScreen relays to league_tab_requested.
signal league_hud_clicked
## Emitted when pause button pressed → TradingScreen relays to pause_toggle_requested.
signal pause_toggled
## Emitted when a speed button pressed → TradingScreen relays to speed_change_requested.
signal speed_changed(multiplier: float)
## Emitted when the market-open / season-start button is pressed.
signal market_open_pressed
## Emitted when SP alert button clicked — MainScreen switches to F3 growth tab.
signal growth_tab_requested

var _lbl_season_info: Label
var _lbl_tick_progress: Label
var _progress_bar: ProgressBar
var _lbl_speed: Label
var _btn_speed_1x: Button
var _btn_speed_2x: Button
var _btn_speed_4x: Button
var _btn_pause: Button
var _btn_market_open: Button
var _speed_box: HBoxContainer  ## speed controls group — fixed-width sibling of _btn_market_open
var _lbl_market_index: Label
var _lbl_total_assets: Label
var _lbl_cash: Label
var _lbl_league_tier: Label
var _lbl_season_return: Label
var _lbl_weekly_return: Label
var _btn_sp_alert: Button
var _ui_state: UIState = UIState.LOADING


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	_build_row1()
	_build_row2()
	_build_sp_alert()
	GameClock.on_tick.connect(_on_tick)
	CurrencySystem.sim_cash_changed.connect(func(_a: int, _d: int) -> void: _update_row2())
	# valuation_updated is intentionally NOT connected here — on_tick already fires _update_row2()
	# after OrderEngine._on_tick() has updated valuation, so connecting both would fire twice per tick.
	var _sp_alert_handler: Callable = func(_id: String) -> void: _update_sp_alert()
	SkillTree.on_skill_unlocked.connect(_sp_alert_handler)
	tree_exiting.connect(func() -> void:
		if SkillTree.on_skill_unlocked.is_connected(_sp_alert_handler):
			SkillTree.on_skill_unlocked.disconnect(_sp_alert_handler)
	)


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

	# Progress bar — custom-styled so it's visible on a light background
	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.custom_minimum_size = Vector2(80, 10)
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress_bar.show_percentage = false
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = ThemeSetup.BTN_ACCENT
	pb_fill.set_corner_radius_all(3)
	_progress_bar.add_theme_stylebox_override("fill", pb_fill)
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.82, 0.82, 0.85)
	pb_bg.set_corner_radius_all(3)
	_progress_bar.add_theme_stylebox_override("background", pb_bg)
	row1.add_child(_progress_bar)

	_lbl_tick_progress = Label.new()
	_lbl_tick_progress.text = "틱 0/%d" % GameClock.TICKS_PER_DAY
	_lbl_tick_progress.add_theme_font_size_override("font_size", 11)
	row1.add_child(_lbl_tick_progress)

	row1.add_child(VSeparator.new())

	# Right section: _speed_box and _btn_market_open are same-width siblings.
	# Exactly one is visible at a time → total right-side width never changes.
	const RIGHT_MIN_W: int = 210
	_speed_box = HBoxContainer.new()
	_speed_box.add_theme_constant_override("separation", 4)
	_speed_box.custom_minimum_size.x = RIGHT_MIN_W
	_speed_box.alignment = BoxContainer.ALIGNMENT_END
	row1.add_child(_speed_box)
	_build_speed_controls(_speed_box)

	_btn_market_open = Button.new()
	_btn_market_open.text = "시즌 시작 Enter"
	_btn_market_open.custom_minimum_size.x = RIGHT_MIN_W
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
	row2_panel.custom_minimum_size.y = 42
	row2_panel.add_theme_stylebox_override("panel", ThemeSetup.make_panel_style(ThemeSetup.BG_DARK, 0, ThemeSetup.BORDER_DIM))
	add_child(row2_panel)
	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	row2_panel.add_child(row2)
	_lbl_market_index = Label.new()
	_lbl_market_index.text = "지수 1,000.0 (0.00%)"
	_lbl_market_index.add_theme_font_size_override("font_size", 14)
	ThemeSetup.style_label_primary(_lbl_market_index)
	row2.add_child(_lbl_market_index)
	var sep_r2: VSeparator = VSeparator.new()
	sep_r2.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	row2.add_child(sep_r2)
	_lbl_total_assets = Label.new()
	_lbl_total_assets.text = "총 평가금액: ₩0"
	_lbl_total_assets.add_theme_font_size_override("font_size", 17)
	ThemeSetup.style_label_primary(_lbl_total_assets)
	row2.add_child(_lbl_total_assets)
	_lbl_cash = Label.new()
	_lbl_cash.text = "예수금: ₩0"
	_lbl_cash.add_theme_font_size_override("font_size", 15)
	ThemeSetup.style_label_secondary(_lbl_cash)
	row2.add_child(_lbl_cash)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(spacer)
	_build_league_hud(row2)


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
	_btn_sp_alert = Button.new()
	_btn_sp_alert.visible = false
	_btn_sp_alert.flat = true
	_btn_sp_alert.add_theme_font_size_override("font_size", 12)
	_btn_sp_alert.add_theme_color_override("font_color", Color(0.85, 0.70, 0.20))
	_btn_sp_alert.pressed.connect(func() -> void: growth_tab_requested.emit())
	add_child(_btn_sp_alert)


func _on_tick(_tick: int, _day: int, _week: int) -> void:
	_update_row1()
	_update_row2()


func _update_row1() -> void:
	var day: int = GameClock.get_current_day()
	var week: int = GameClock.get_current_week()
	var day_names: Array[String] = [tr("월"), tr("화"), tr("수"), tr("목"), tr("금")]
	var day_in_week: int = day % GameClock.DAYS_PER_WEEK
	var day_name: String = day_names[day_in_week] if day_in_week < day_names.size() else "?"
	_lbl_season_info.text = tr("%d주차 %s요일") % [week + 1, day_name]
	var tick: int = GameClock.get_current_tick()
	_lbl_tick_progress.text = tr("틱 %d/%d") % [tick, GameClock.TICKS_PER_DAY]
	_progress_bar.value = GameClock.get_day_progress() * 100.0
	_update_speed_label()


func _update_speed_label() -> void:
	if _ui_state == UIState.PAUSED:
		_lbl_speed.text = tr("⏸ 일시정지")
		return
	var spd: float = GameClock.get_speed_multiplier()
	if spd <= 1.0:
		_lbl_speed.text = tr("▶ 1x")
	elif spd <= 2.0:
		_lbl_speed.text = tr("▶▶ 2x")
	else:
		_lbl_speed.text = tr("▶▶▶▶ 4x")


func _update_row2() -> void:
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	var total: int = summary["total_assets"]
	var rate: float = summary["return_rate"]
	_lbl_total_assets.text = tr("총 평가금액: ₩%s") % FormatUtils.number(total)
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
		_lbl_cash.text = tr("예수금: ₩%s (미체결예약: ₩%s) | 보유 %d/%d") % [
			FormatUtils.number(cash), FormatUtils.number(reserved), holdings_count, max_holdings]
	else:
		_lbl_cash.text = tr("예수금: ₩%s | 보유 %d/%d") % [FormatUtils.number(cash), holdings_count, max_holdings]


func _update_index_label() -> void:
	var index_val: float = PriceEngine.get_market_index()
	# 시즌 초기화 전(또는 초기화 직후 첫 틱 전)에는 지수가 0 → 미표시.
	if index_val <= 0.0:
		_lbl_market_index.text = tr("지수 ---")
		return
	var index_change: float = PriceEngine.get_index_change_pct()
	var sign_str: String = "+" if index_change >= 0.0 else ""
	_lbl_market_index.text = "지수 %s (%s%.2f%%)" % [
		FormatUtils.number(roundi(index_val)), sign_str, index_change]


func _update_league_hud() -> void:
	if SeasonManager.get_is_free_market():
		_lbl_league_tier.text = tr("프리마켓")
		_lbl_season_return.text = tr("시즌 -")
		_lbl_weekly_return.text = tr("주간 -")
		return
	var tier_rank: int = SeasonManager.get_tier_rank()
	var tier_name: String = SeasonManager.get_tier_name(SeasonManager.get_current_tier())
	_lbl_league_tier.text = tr("%s %d위") % [tier_name, tier_rank] if tier_rank > 0 else tier_name
	var s_ret: float = SeasonManager.get_season_return_pct()
	var w_ret: float = SeasonManager.get_weekly_return_pct()
	_lbl_season_return.text = tr("시즌 %+.1f%%") % s_ret
	_lbl_weekly_return.text = tr("주간 %+.1f%%") % w_ret
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
## _speed_box and _btn_market_open are same-width siblings — toggling one at a time keeps layout stable.
func set_ui_state(state: int) -> void:
	_ui_state = state as UIState
	var speed_visible: bool = state == UIState.MARKET_OPEN or state == UIState.PAUSED
	_speed_box.visible = speed_visible
	_btn_market_open.visible = (state == UIState.PRE_MARKET)
	if state == UIState.PRE_MARKET:
		_btn_market_open.text = tr("장 시작 Enter") if SeasonManager.is_season_active() else tr("시즌 시작 Enter")
		_update_sp_alert()
	else:
		_btn_sp_alert.visible = false
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
		_btn_sp_alert.text = tr("미사용 스킬 포인트 %d개 — F3 성장 화면에서 해금") % sp
		_btn_sp_alert.visible = true
	else:
		_btn_sp_alert.visible = false


## Called by TradingScreen after speed changes via keyboard.
func update_speed(multiplier: float) -> void:
	_update_speed_buttons(multiplier)
	_update_speed_label()
