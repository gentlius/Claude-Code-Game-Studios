## SettingsScreen — 볼륨, 뉴스 자동 감속, 색각 모드(와이어프레임), 키 리맵(와이어프레임).
## MainScreen 탭바 ⚙ 버튼으로 오버레이 형태 열기/닫기.
## GDD: design/gdd/settings-screen.md
class_name SettingsScreen
extends Control

# ── Constants ──

const SETTINGS_PATH: String = "user://game_settings.cfg"
const DEFAULT_AUTO_SLOW: bool = true
const PANEL_MIN_WIDTH: int = 360

# ── Node References ──

var _slider_volume: HSlider
var _chk_mute: CheckButton
var _chk_auto_slow: CheckButton


# ── Lifecycle ──

func _ready() -> void:
	_build_ui()
	_load_settings()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			hide()
			get_viewport().set_input_as_handled()


# ── Persistence ──

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	var auto_slow: bool = DEFAULT_AUTO_SLOW
	if cfg.load(SETTINGS_PATH) == OK:
		auto_slow = cfg.get_value("gameplay", "auto_slow_on_news", DEFAULT_AUTO_SLOW)
	GameClock.set_auto_slow_on_event(auto_slow)
	_chk_auto_slow.set_pressed_no_signal(auto_slow)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("gameplay", "auto_slow_on_news", GameClock.get_auto_slow_on_event())
	cfg.save(SETTINGS_PATH)


# ── UI Construction ──

func _build_ui() -> void:
	# Dimmed full-area backdrop
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var backdrop_style := StyleBoxFlat.new()
	backdrop_style.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	add_theme_stylebox_override("panel", backdrop_style)

	# Centered panel
	var panel := PanelContainer.new()
	var panel_style := ThemeSetup.make_panel_style(ThemeSetup.BG_PANEL, 8, ThemeSetup.BORDER_DIM, 1)
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(PANEL_MIN_WIDTH, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   20)
	margin.add_theme_constant_override("margin_right",  20)
	margin.add_theme_constant_override("margin_top",    16)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_build_ui_header(vbox)
	_build_ui_sections(vbox)


## Builds the settings panel header row (title label + close button + separator).
func _build_ui_header(vbox: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = tr("설정")
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", ThemeSetup.TEXT_PRIMARY)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.add_theme_color_override("font_color", ThemeSetup.TEXT_SECONDARY)
	close_btn.pressed.connect(hide)
	header.add_child(close_btn)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)


## Builds all settings sections (audio, gameplay, accessibility, key remap).
func _build_ui_sections(vbox: VBoxContainer) -> void:
	_add_section_label(vbox, tr("오디오"))
	_add_volume_row(vbox)
	_add_mute_row(vbox)

	_add_section_label(vbox, tr("게임플레이"))
	_add_auto_slow_row(vbox)

	_add_section_label(vbox, tr("접근성"))
	_add_colorblind_row(vbox)

	_add_section_label(vbox, tr("키 리맵"))
	_add_keymap_row(vbox)


func _add_section_label(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", ThemeSetup.TEXT_DIM)
	parent.add_child(lbl)


func _add_volume_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = tr("마스터 볼륨")
	lbl.custom_minimum_size = Vector2(110, 0)
	lbl.add_theme_color_override("font_color", ThemeSetup.TEXT_PRIMARY)
	row.add_child(lbl)

	_slider_volume = HSlider.new()
	_slider_volume.min_value = 0.0
	_slider_volume.max_value = 100.0
	_slider_volume.step = 1.0
	_slider_volume.value = round(AudioManager.get_volume() * 100.0)
	_slider_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider_volume.value_changed.connect(func(v: float) -> void:
		AudioManager.set_volume(v / 100.0)
	)
	row.add_child(_slider_volume)

	var vol_lbl := Label.new()
	vol_lbl.text = "%d" % int(_slider_volume.value)
	vol_lbl.custom_minimum_size = Vector2(28, 0)
	vol_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vol_lbl.add_theme_color_override("font_color", ThemeSetup.TEXT_SECONDARY)
	_slider_volume.value_changed.connect(func(v: float) -> void:
		vol_lbl.text = "%d" % int(v)
	)
	row.add_child(vol_lbl)


func _add_mute_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = tr("음소거")
	lbl.custom_minimum_size = Vector2(110, 0)
	lbl.add_theme_color_override("font_color", ThemeSetup.TEXT_PRIMARY)
	row.add_child(lbl)

	_chk_mute = CheckButton.new()
	_chk_mute.focus_mode = Control.FOCUS_NONE
	_chk_mute.set_pressed_no_signal(AudioManager.is_muted())
	_chk_mute.toggled.connect(func(b: bool) -> void:
		AudioManager.set_muted(b)
	)
	row.add_child(_chk_mute)


func _add_auto_slow_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = tr("뉴스 자동 감속")
	lbl.custom_minimum_size = Vector2(110, 0)
	lbl.add_theme_color_override("font_color", ThemeSetup.TEXT_PRIMARY)
	row.add_child(lbl)

	_chk_auto_slow = CheckButton.new()
	_chk_auto_slow.focus_mode = Control.FOCUS_NONE
	# Initial value set in _load_settings() after _build_ui()
	_chk_auto_slow.toggled.connect(func(b: bool) -> void:
		GameClock.set_auto_slow_on_event(b)
		_save_settings()
	)
	row.add_child(_chk_auto_slow)


func _add_colorblind_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = tr("색각 모드")
	lbl.custom_minimum_size = Vector2(110, 0)
	lbl.add_theme_color_override("font_color", ThemeSetup.TEXT_DIM)
	row.add_child(lbl)

	var opt := OptionButton.new()
	opt.add_item(tr("기본"))
	opt.disabled = true
	opt.focus_mode = Control.FOCUS_NONE
	opt.tooltip_text = tr("색각 모드 — 추후 업데이트 예정")
	row.add_child(opt)


func _add_keymap_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = tr("키 리맵")
	lbl.custom_minimum_size = Vector2(110, 0)
	lbl.add_theme_color_override("font_color", ThemeSetup.TEXT_DIM)
	row.add_child(lbl)

	var btn := Button.new()
	btn.text = tr("설정 →  (예정)")
	btn.disabled = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.flat = true
	btn.tooltip_text = tr("키 리맵 — 추후 업데이트 예정")
	row.add_child(btn)
