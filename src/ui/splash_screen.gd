class_name SplashScreen
extends Control
## 로고 스플래시 화면. SPLASH_DURATION 후 자동 전환 또는 입력으로 즉시 스킵.
## GDD: design/gdd/start-screen.md §3-2

signal splash_finished

## 자동 전환까지 대기 시간(초). GDD §7 튜닝 노브.
const SPLASH_DURATION: float = 2.0
## 페이드아웃 시간(초). GDD §7 튜닝 노브.
const SPLASH_FADE_DURATION: float = 0.3

var _transitioning: bool = false
var _timer: float = 0.0
var _overlay: ColorRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _build_ui() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.039, 0.039, 0.039)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Logo built with native nodes — SVG <text> elements don't render in Godot's nanosvg importer.
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var logo_hbox: HBoxContainer = HBoxContainer.new()
	logo_hbox.add_theme_constant_override("separation", 18)
	logo_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(logo_hbox)

	# Chart bars (ascending)
	var bars_vbox: VBoxContainer = VBoxContainer.new()
	bars_vbox.alignment = BoxContainer.ALIGNMENT_END
	bars_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_hbox.add_child(bars_vbox)

	var bars_row: HBoxContainer = HBoxContainer.new()
	bars_row.add_theme_constant_override("separation", 4)
	bars_row.alignment = BoxContainer.ALIGNMENT_END
	bars_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars_vbox.add_child(bars_row)

	var bar_heights: Array[int] = [32, 52, 76, 98, 120]
	var bar_colors: Array[Color] = [
		Color(0.118, 0.290, 0.478),
		Color(0.141, 0.353, 0.561),
		Color(0.169, 0.416, 0.667),
		Color(0.196, 0.471, 0.753),
		Color(0.290, 0.565, 0.851),
	]
	for i: int in range(bar_heights.size()):
		var bar: ColorRect = ColorRect.new()
		bar.color = bar_colors[i]
		bar.custom_minimum_size = Vector2(14, bar_heights[i])
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bars_row.add_child(bar)

	# Vertical separator
	var vsep: ColorRect = ColorRect.new()
	vsep.color = Color(0.173, 0.173, 0.173)
	vsep.custom_minimum_size = Vector2(2, 130)
	vsep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_hbox.add_child(vsep)

	# Text column
	var text_vbox: VBoxContainer = VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", 0)
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_hbox.add_child(text_vbox)

	var lbl_seed: Label = Label.new()
	lbl_seed.text = "SEED"  ## intentionally NOT wrapped in tr() — brand name, not translated
	lbl_seed.add_theme_font_size_override("font_size", 72)
	lbl_seed.add_theme_color_override("font_color", Color(0.922, 0.922, 0.922))
	lbl_seed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(lbl_seed)

	var lbl_money: Label = Label.new()
	lbl_money.text = "M O N E Y"  ## intentionally NOT wrapped in tr() — brand name stylization
	lbl_money.add_theme_font_size_override("font_size", 28)
	lbl_money.add_theme_color_override("font_color", Color(0.302, 0.431, 0.600))
	lbl_money.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(lbl_money)

	AudioManager.play_sfx("sfx_logo_sting")

	# 페이드 오버레이
	_overlay = ColorRect.new()
	_overlay.color = Color(0.039, 0.039, 0.039)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.modulate.a = 0.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)


func _process(delta: float) -> void:
	if _transitioning:
		return
	_timer += delta
	if _timer >= SPLASH_DURATION:
		_start_transition()


func _input(event: InputEvent) -> void:
	if _transitioning:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_start_transition()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			match ke.keycode:
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					_start_transition()
					get_viewport().set_input_as_handled()


func _start_transition() -> void:
	if _transitioning:
		return
	_transitioning = true
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 1.0, SPLASH_FADE_DURATION)
	tween.tween_callback(func() -> void: splash_finished.emit())
