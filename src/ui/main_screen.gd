## MainScreen — F1/F2/F3 탭 컨테이너 + 탭 전환 + 일시정지 단일 진입점.
## ADR-006: MainScreen이 GameClock.pause_request/release()를 소유.
## 각 탭 씬(TradingScreen, LeagueScreen, GrowthScreen)은 pause API를 직접 호출하지 않는다.
## See: docs/architecture/006-tab-scene-ownership.md
extends Control

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

var _trading_screen: Control   ## F1
var _league_screen: Control    ## F2
var _growth_screen: Control    ## F3 (placeholder)

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

func _build_ui() -> void:
	var bg_style: StyleBoxFlat = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.09, 1.0)
	add_theme_stylebox_override("panel", bg_style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	# ── Tab Bar ──
	var tab_bar_panel: PanelContainer = PanelContainer.new()
	var tab_bar_style: StyleBoxFlat = StyleBoxFlat.new()
	tab_bar_style.bg_color = Color(0.12, 0.12, 0.13, 1.0)
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

	# ── Tab Content Container ──
	var content: Control = Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(content)

	# F1 — TradingScreen
	var trading_scene: PackedScene = load("res://src/ui/TradingScreen.tscn")
	_trading_screen = trading_scene.instantiate()
	_trading_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(_trading_screen)
	# AC-01 (league-ui.md): 리그 HUD 클릭 → F2 이동. MainScreen이 탭 전환 소유 (ADR-006).
	_trading_screen.league_tab_requested.connect(func() -> void: _switch_tab(TAB_F2))
	# TD-03: TradingScreen/SkillTreeOverlay → MainScreen → GameClock (단일 라우팅 경로)
	_trading_screen.pause_toggle_requested.connect(func() -> void: GameClock.toggle_pause())
	_trading_screen.speed_change_requested.connect(func(m: float) -> void: GameClock.set_speed(m))

	# F2 — LeagueScreen (S3-05)
	var league_scene: PackedScene = load("res://src/ui/LeagueScreen.tscn")
	_league_screen = league_scene.instantiate()
	_league_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(_league_screen)

	# F3 — GrowthScreen (placeholder)
	_growth_screen = _build_placeholder(tr("F3  성장 화면"), tr("준비 중"))
	_growth_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(_growth_screen)

	# ── Tab Pause Banner (ADR-006) ──
	_tab_pause_banner = Panel.new()
	_tab_pause_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tab_pause_banner.visible = false
	_tab_pause_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tab_pause_banner)

	var banner_style: StyleBoxFlat = StyleBoxFlat.new()
	banner_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # 투명 — 탭 자체가 시각 피드백
	_tab_pause_banner.add_theme_stylebox_override("panel", banner_style)


func _make_tab_button(label: String, tab_idx: int) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 13)
	btn.custom_minimum_size = Vector2(120, 32)

	var normal_style: StyleBoxFlat = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.12, 0.12, 0.13, 1.0)
	normal_style.set_border_width_all(0)
	var active_style: StyleBoxFlat = StyleBoxFlat.new()
	active_style.bg_color = Color(0.18, 0.18, 0.20, 1.0)
	active_style.border_color = Color(0.3, 0.6, 1.0, 1.0)
	active_style.set_border_width(SIDE_BOTTOM, 2)

	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("pressed", active_style)
	btn.add_theme_stylebox_override("hover", active_style)
	btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))

	btn.pressed.connect(func() -> void: _switch_tab(tab_idx))
	return btn


func _build_placeholder(title: String, subtitle: String) -> Control:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.09, 1.0)
	panel.add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var lbl_title: Label = Label.new()
	lbl_title.text = title
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 24)
	lbl_title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
	vbox.add_child(lbl_title)

	var lbl_sub: Label = Label.new()
	lbl_sub.text = subtitle
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub.add_theme_font_size_override("font_size", 14)
	lbl_sub.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35, 1.0))
	vbox.add_child(lbl_sub)

	return panel
