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

	var logo: TextureRect = TextureRect.new()
	logo.texture = load("res://assets/ui/logo.svg") as Texture2D
	logo.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
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
