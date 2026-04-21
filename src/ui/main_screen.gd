## MainScreen — F1/F2/F3 탭 컨테이너 + F4 나가기 + 탭 전환 + 일시정지 단일 진입점.
## ADR-006: MainScreen이 GameClock.pause_request/release()를 소유.
## 각 탭 씬(TradingScreen, LeagueScreen, GrowthScreen)은 pause API를 직접 호출하지 않는다.
## See: docs/architecture/006-tab-scene-ownership.md
extends Control

## F4 나가기 버튼/키 — game_main이 수신해 StartScreen으로 전환. GDD: start-screen.md §3-7
signal exit_to_start_requested
## Relayed from TradingScreen — game_main shows LifestyleScreen. GDD: lifestyle-spending.md §3-1
signal spending_screen_requested(is_season_end: bool)

# ── Constants ──

## pause_request/release 소스 ID. ADR-006 리스크 완화: 상수화로 오타 방지.
const TAB_SWITCH_SOURCE: String = "tab_switch"

const TAB_F1: int = 0
const TAB_F2: int = 1
const TAB_F3: int = 2

# ── State ──

var _active_tab: int = TAB_F1

# ── Node References ──

var _tab_bar: HBoxContainer
var _btn_f1: Button
var _btn_f2: Button
var _btn_f3: Button
var _btn_settings: Button
var _btn_f4_exit: Button

var _trading_screen: Control   ## F1
var _league_screen: Control    ## F2
var _growth_screen: Control    ## F3 (placeholder)
var _settings_screen: SettingsScreen  ## 오버레이 (탭 아님)

var _tab_pause_banner: Panel   ## "장 중 일시정지" 배너 — ADR-006 §씬구조


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()
	_switch_tab(TAB_F1, false)


func _exit_tree() -> void:
	## ADR-006 리스크 완화: 씬 제거 시 누수된 pause_request 강제 해제.
	GameClock.pause_release(TAB_SWITCH_SOURCE)


# ── Public ──

## 현재 활성 탭 인덱스 (TAB_F1 / TAB_F2 / TAB_F3).
func get_active_tab() -> int:
	return _active_tab


# ── Input ──

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	match key_event.keycode:
		KEY_F1:
			_switch_tab(TAB_F1)
			get_viewport().set_input_as_handled()
		KEY_F2:
			_switch_tab(TAB_F2)
			get_viewport().set_input_as_handled()
		KEY_F3:
			_switch_tab(TAB_F3)
			get_viewport().set_input_as_handled()
		KEY_F4:
			_request_exit_to_start()
			get_viewport().set_input_as_handled()


# ── 설정 오버레이 ──

func _toggle_settings() -> void:
	_settings_screen.visible = not _settings_screen.visible


# ── F4 나가기 ──

func _request_exit_to_start() -> void:
	## 저장 중(SavingOverlay visible)이면 무반응. GDD start-screen.md §3-7.
	## SavingOverlay는 CanvasLayer(layer=10)이므로 SaveSystem 시그널로 상태 확인.
	if SaveSystem.is_save_pending():
		return
	exit_to_start_requested.emit()


# ── Internal ──

func _switch_tab(tab: int, handle_pause: bool = true) -> void:
	var leaving_f1: bool = (_active_tab == TAB_F1 and tab != TAB_F1)
	var returning_f1: bool = (_active_tab != TAB_F1 and tab == TAB_F1)

	_active_tab = tab

	_trading_screen.visible = (tab == TAB_F1)
	_league_screen.visible  = (tab == TAB_F2)
	_growth_screen.visible  = (tab == TAB_F3)

	_btn_f1.button_pressed = (tab == TAB_F1)
	_btn_f2.button_pressed = (tab == TAB_F2)
	_btn_f3.button_pressed = (tab == TAB_F3)

	# ADR-006: MARKET_OPEN 중 F1 이탈 → pause_request, F1 복귀 → pause_release.
	# PRE_MARKET / MARKET_CLOSED 등에서는 일시정지 없이 자유 전환.
	if handle_pause:
		var state: GameClock.MarketState = GameClock.get_market_state()
		var is_live: bool = (state == GameClock.MarketState.MARKET_OPEN
			or state == GameClock.MarketState.PAUSED)
		if leaving_f1 and is_live:
			GameClock.pause_request(TAB_SWITCH_SOURCE)
			_tab_pause_banner.visible = true
		elif returning_f1:
			GameClock.pause_release(TAB_SWITCH_SOURCE)
			_tab_pause_banner.visible = false


# ── UI Construction ──

## 다크 프레임 배경, 탭 바, F4 나가기 버튼, 콘텐츠 영역, 탭 씬 3종, 일시정지 배너 전체 구성.
func _build_ui() -> void:
	var bg_style: StyleBoxFlat = StyleBoxFlat.new()
	bg_style.bg_color = ThemeSetup.LAYOUT_BG
	add_theme_stylebox_override("panel", bg_style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	_build_tab_bar(vbox)

	var content: Control = _build_content_area(vbox)
	_build_tab_scenes(content)
	_build_tab_pause_banner()


## Builds the top tab bar (F1/F2/F3 tabs, settings button, F4 exit button).
func _build_tab_bar(vbox: VBoxContainer) -> void:
	var tab_bar_panel: PanelContainer = PanelContainer.new()
	var tab_bar_style: StyleBoxFlat = StyleBoxFlat.new()
	tab_bar_style.bg_color = ThemeSetup.LAYOUT_PANEL
	tab_bar_panel.add_theme_stylebox_override("panel", tab_bar_style)
	tab_bar_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(tab_bar_panel)

	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 0)
	tab_bar_panel.add_child(_tab_bar)

	_btn_f1 = _make_tab_button(tr("F1  거래"), TAB_F1)
	_btn_f2 = _make_tab_button(tr("F2  리그"), TAB_F2)
	_btn_f3 = _make_tab_button(tr("F3  성장"), TAB_F3)
	_tab_bar.add_child(_btn_f1)
	_tab_bar.add_child(_btn_f2)
	_tab_bar.add_child(_btn_f3)

	_build_settings_button()
	_build_f4_exit_button()


## Builds and adds the settings (⚙) overlay toggle button to _tab_bar.
func _build_settings_button() -> void:
	_btn_settings = Button.new()
	_btn_settings.text = tr("설정")
	_btn_settings.focus_mode = Control.FOCUS_NONE
	_btn_settings.add_theme_font_size_override("font_size", 13)
	_btn_settings.custom_minimum_size = Vector2(80, 32)
	_btn_settings.tooltip_text = tr("설정")
	var settings_normal: StyleBoxFlat = StyleBoxFlat.new()
	settings_normal.bg_color = ThemeSetup.LAYOUT_PANEL
	settings_normal.set_border_width_all(0)
	var settings_hover: StyleBoxFlat = StyleBoxFlat.new()
	settings_hover.bg_color = ThemeSetup.LAYOUT_TAB_ACTIVE_BG
	settings_hover.set_border_width_all(0)
	_btn_settings.add_theme_stylebox_override("normal", settings_normal)
	_btn_settings.add_theme_stylebox_override("hover", settings_hover)
	_btn_settings.add_theme_stylebox_override("pressed", settings_hover)
	_btn_settings.add_theme_color_override("font_color", ThemeSetup.LAYOUT_TAB_TEXT)
	_btn_settings.add_theme_color_override("font_hover_color", Color.WHITE)
	_btn_settings.pressed.connect(_toggle_settings)
	_tab_bar.add_child(_btn_settings)


## Builds and adds the F4 exit button (right-aligned) to _tab_bar.
func _build_f4_exit_button() -> void:
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_bar.add_child(spacer)

	_btn_f4_exit = Button.new()
	_btn_f4_exit.text = tr("F4  나가기")
	_btn_f4_exit.focus_mode = Control.FOCUS_NONE
	_btn_f4_exit.add_theme_font_size_override("font_size", 13)
	_btn_f4_exit.custom_minimum_size = Vector2(120, 32)
	var exit_normal: StyleBoxFlat = StyleBoxFlat.new()
	exit_normal.bg_color = ThemeSetup.LAYOUT_PANEL
	exit_normal.set_border_width_all(0)
	var exit_hover: StyleBoxFlat = StyleBoxFlat.new()
	exit_hover.bg_color = ThemeSetup.LAYOUT_EXIT_HOVER_BG
	exit_hover.set_border_width_all(0)
	_btn_f4_exit.add_theme_stylebox_override("normal", exit_normal)
	_btn_f4_exit.add_theme_stylebox_override("hover", exit_hover)
	_btn_f4_exit.add_theme_stylebox_override("pressed", exit_hover)
	_btn_f4_exit.add_theme_color_override("font_color", ThemeSetup.LAYOUT_EXIT_TEXT)
	_btn_f4_exit.add_theme_color_override("font_hover_color", ThemeSetup.LAYOUT_EXIT_TEXT_HOVER)
	_btn_f4_exit.pressed.connect(_request_exit_to_start)
	_tab_bar.add_child(_btn_f4_exit)


## Creates and adds the full-screen content container to vbox. Returns it.
func _build_content_area(vbox: VBoxContainer) -> Control:
	var content: Control = Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(content)
	return content


## Instantiates F1/F2/F3 tab scenes and the settings overlay into content.
func _build_tab_scenes(content: Control) -> void:
	# F1 — TradingScreen
	var trading_scene: PackedScene = load("res://src/ui/TradingScreen.tscn")
	_trading_screen = trading_scene.instantiate()
	_trading_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(_trading_screen)
	# AC-01 (league-ui.md): 리그 HUD 클릭 → F2 이동. MainScreen이 탭 전환 소유 (ADR-006).
	_trading_screen.league_tab_requested.connect(func() -> void: _switch_tab(TAB_F2))
	# SP 알림 / LevelUpBanner → F3 성장 화면 전환 (GDD: growth-screen.md §3-6)
	_trading_screen.growth_tab_requested.connect(func() -> void: _switch_tab(TAB_F3))
	# TD-03: TradingScreen/SkillTreeOverlay → MainScreen → GameClock (단일 라우팅 경로)
	_trading_screen.pause_toggle_requested.connect(func() -> void: GameClock.toggle_pause())
	_trading_screen.speed_change_requested.connect(func(m: float) -> void: GameClock.set_speed(m))
	# Relay spending screen request to GameMain (GDD: lifestyle-spending.md §3-1)
	_trading_screen.spending_screen_requested.connect(
		func(b: bool) -> void: spending_screen_requested.emit(b)
	)

	# F2 — LeagueScreen (S3-05)
	var league_scene: PackedScene = load("res://src/ui/LeagueScreen.tscn")
	_league_screen = league_scene.instantiate()
	_league_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(_league_screen)

	# F3 — GrowthScreen (B-03: growth-screen.md)
	_growth_screen = GrowthScreen.new()
	_growth_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(_growth_screen)

	# Settings Overlay (GDD: settings-screen.md)
	_settings_screen = SettingsScreen.new()
	_settings_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_screen.visible = false
	content.add_child(_settings_screen)


## Builds the transparent pause banner overlay (ADR-006). Added directly to self.
func _build_tab_pause_banner() -> void:
	_tab_pause_banner = Panel.new()
	_tab_pause_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tab_pause_banner.visible = false
	_tab_pause_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tab_pause_banner)

	var banner_style: StyleBoxFlat = StyleBoxFlat.new()
	banner_style.bg_color = Color.TRANSPARENT  # 탭 자체가 시각 피드백
	_tab_pause_banner.add_theme_stylebox_override("panel", banner_style)


func _make_tab_button(label: String, tab_idx: int) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 13)
	btn.custom_minimum_size = Vector2(120, 32)

	var normal_style: StyleBoxFlat = StyleBoxFlat.new()
	normal_style.bg_color = ThemeSetup.LAYOUT_PANEL
	normal_style.set_border_width_all(0)
	var active_style: StyleBoxFlat = StyleBoxFlat.new()
	active_style.bg_color = ThemeSetup.LAYOUT_TAB_ACTIVE_BG
	active_style.border_color = ThemeSetup.LAYOUT_TAB_BORDER
	active_style.set_border_width(SIDE_BOTTOM, 2)

	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("pressed", active_style)
	btn.add_theme_stylebox_override("hover", active_style)
	btn.add_theme_color_override("font_color", ThemeSetup.LAYOUT_TAB_TEXT)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)

	btn.pressed.connect(func() -> void: _switch_tab(tab_idx))
	return btn



