class_name SavingOverlay
extends CanvasLayer
## 저장 진행 중 전체화면 오버레이 + 스피너. 유저 입력 차단.
## SaveSystem.save_started / save_completed 시그널 구독.
## GDD: design/gdd/save-load.md §3-8

const SPINNER_SPEED_DEG: float = 300.0  ## 회전 속도 (도/초)

var _spinner: Control
var _spinner_angle: float = 0.0


func _ready() -> void:
	layer = 10
	visible = false
	_build_ui()
	SaveSystem.save_started.connect(_on_save_started)
	SaveSystem.save_completed.connect(_on_save_completed)


func _build_ui() -> void:
	# 반투명 전체 차단 패널
	var panel: Panel = Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	_spinner = TextureRect.new()
	_spinner.texture = load("res://assets/ui/ui_spinner_ring_default.svg")
	_spinner.custom_minimum_size = Vector2(48.0, 48.0)
	_spinner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spinner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_spinner.pivot_offset = Vector2(24.0, 24.0)
	_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_spinner)

	var lbl: Label = Label.new()
	lbl.text = tr("저장 중...")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.918, 0.918, 0.918))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lbl)


func _process(delta: float) -> void:
	if not visible:
		return
	_spinner_angle = fmod(_spinner_angle + SPINNER_SPEED_DEG * delta, 360.0)
	_spinner.rotation_degrees = _spinner_angle


func _on_save_started() -> void:
	visible = true


func _on_save_completed() -> void:
	visible = false
	AudioManager.play_sfx("sfx_save_complete")
