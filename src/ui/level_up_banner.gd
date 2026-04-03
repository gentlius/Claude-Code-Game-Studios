## Level Up Banner — Top slide-in notification on level up.
## Shows old→new level, SP gained, and CTA to open skill tree.
## See: design/gdd/progression-ui.md (Rule 3)
class_name LevelUpBanner
extends Control

# ── Signals ──

signal skill_tree_requested
signal banner_closed

# ── Config (Tuning Knobs — GDD) ──

const BANNER_HEIGHT: int = 100
const DIM_ALPHA: float = 0.35
const SLIDE_DURATION: float = 0.5
const GOLD_COLOR: Color = Color(0.85, 0.70, 0.20)
const GOLD_BRIGHT: Color = Color(0.95, 0.82, 0.30)
const GOLD_BG: Color = Color(0.85, 0.70, 0.20, 0.10)
const FLASH_COLOR: Color = Color(0.95, 0.85, 0.40, 0.25)

# ── Node References ──

var _dim_overlay: ColorRect
var _flash_rect: ColorRect
var _banner_panel: PanelContainer
var _lbl_star: Label
var _lbl_title: Label
var _lbl_level_number: Label
var _lbl_detail: Label
var _btn_skill_tree: Button
var _btn_close: Button
var _is_showing: bool = false

# ── Lifecycle ──

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	# Full-screen flash (golden burst on level up)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = FLASH_COLOR
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.modulate.a = 0.0
	add_child(_flash_rect)

	# Dim overlay (click to close)
	_dim_overlay = ColorRect.new()
	_dim_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim_overlay.color = Color(0.0, 0.0, 0.0, DIM_ALPHA)
	_dim_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim_overlay.modulate.a = 0.0
	_dim_overlay.gui_input.connect(_on_dim_clicked)
	add_child(_dim_overlay)

	# Banner panel (top, full width)
	_banner_panel = PanelContainer.new()
	_banner_panel.anchor_right = 1.0
	_banner_panel.offset_bottom = BANNER_HEIGHT
	_banner_panel.offset_top = -BANNER_HEIGHT  # Start off-screen
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(1.0, 1.0, 1.0, 0.97)
	panel_style.border_color = GOLD_COLOR
	panel_style.set_border_width_all(0)
	panel_style.border_width_bottom = 3
	panel_style.set_content_margin_all(12)
	panel_style.content_margin_top = 16
	_banner_panel.add_theme_stylebox_override("panel", panel_style)
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_banner_panel)

	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	_banner_panel.add_child(main_vbox)

	# Top row: star + LEVEL UP + level number
	var top_row: HBoxContainer = HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_theme_constant_override("separation", 12)
	main_vbox.add_child(top_row)

	_lbl_star = Label.new()
	_lbl_star.text = "★"
	_lbl_star.add_theme_font_size_override("font_size", 22)
	_lbl_star.add_theme_color_override("font_color", GOLD_COLOR)
	top_row.add_child(_lbl_star)

	_lbl_title = Label.new()
	_lbl_title.text = "LEVEL UP"
	_lbl_title.add_theme_font_size_override("font_size", 14)
	_lbl_title.add_theme_color_override("font_color", ThemeSetup.TEXT_SECONDARY)
	top_row.add_child(_lbl_title)

	_lbl_level_number = Label.new()
	_lbl_level_number.add_theme_font_size_override("font_size", 28)
	_lbl_level_number.add_theme_color_override("font_color", GOLD_COLOR)
	top_row.add_child(_lbl_level_number)

	var star2: Label = Label.new()
	star2.text = "★"
	star2.add_theme_font_size_override("font_size", 22)
	star2.add_theme_color_override("font_color", GOLD_COLOR)
	top_row.add_child(star2)

	# Bottom row: detail + buttons
	var bottom_row: HBoxContainer = HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 12)
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(bottom_row)

	_lbl_detail = Label.new()
	_lbl_detail.add_theme_font_size_override("font_size", 13)
	_lbl_detail.add_theme_color_override("font_color", GOLD_COLOR)
	bottom_row.add_child(_lbl_detail)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(spacer)

	_btn_skill_tree = Button.new()
	_btn_skill_tree.text = "스킬 트리 열기  K"
	_btn_skill_tree.add_theme_font_size_override("font_size", 12)
	_btn_skill_tree.pressed.connect(func() -> void:
		hide_banner()
		skill_tree_requested.emit()
	)
	var btn_style: StyleBoxFlat = ThemeSetup.make_button_style(GOLD_COLOR, 4)
	btn_style.set_content_margin_all(4)
	btn_style.content_margin_left = 12
	btn_style.content_margin_right = 12
	_btn_skill_tree.add_theme_stylebox_override("normal", btn_style)
	_btn_skill_tree.add_theme_stylebox_override("hover", ThemeSetup.make_button_style(Color(0.75, 0.60, 0.15), 4))
	_btn_skill_tree.add_theme_color_override("font_color", Color.WHITE)
	_btn_skill_tree.add_theme_color_override("font_hover_color", Color.WHITE)
	bottom_row.add_child(_btn_skill_tree)

	_btn_close = Button.new()
	_btn_close.text = "닫기  Esc"
	_btn_close.add_theme_font_size_override("font_size", 12)
	_btn_close.pressed.connect(hide_banner)
	ThemeSetup.apply_button_theme(_btn_close)
	bottom_row.add_child(_btn_close)


# ── Public API ──

## Show the level-up banner with golden flash and slide-in animation.
## Handles multi-level-up: old_level → new_level with total SP gained.
func show_level_up(old_level: int, new_level: int, skill_points: int) -> void:
	var levels_gained: int = new_level - old_level

	_lbl_level_number.text = "Lv.%d" % new_level
	if levels_gained > 1:
		_lbl_title.text = "LEVEL UP  ×%d" % levels_gained
	else:
		_lbl_title.text = "LEVEL UP"
	_lbl_detail.text = "스킬 포인트 +%d 획득" % skill_points

	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_is_showing = true

	# Phase 1: Golden flash burst
	_flash_rect.modulate.a = 1.0
	var flash_tween: Tween = create_tween()
	flash_tween.tween_property(_flash_rect, "modulate:a", 0.0, 0.6)

	# Phase 2: Dim overlay fade in
	var dim_tween: Tween = create_tween()
	dim_tween.tween_property(_dim_overlay, "modulate:a", 1.0, 0.3)

	# Phase 3: Banner slide in
	_banner_panel.offset_top = -BANNER_HEIGHT
	_banner_panel.offset_bottom = 0
	var slide_tween: Tween = create_tween()
	slide_tween.set_ease(Tween.EASE_OUT)
	slide_tween.set_trans(Tween.TRANS_BACK)
	slide_tween.tween_property(_banner_panel, "offset_top", 0.0, SLIDE_DURATION)
	slide_tween.parallel().tween_property(_banner_panel, "offset_bottom", float(BANNER_HEIGHT), SLIDE_DURATION)

	# Phase 4: Level number scale-up punch
	_lbl_level_number.scale = Vector2(0.3, 0.3)
	_lbl_level_number.pivot_offset = _lbl_level_number.size / 2.0
	var punch_tween: Tween = create_tween()
	punch_tween.set_ease(Tween.EASE_OUT)
	punch_tween.set_trans(Tween.TRANS_ELASTIC)
	punch_tween.tween_property(_lbl_level_number, "scale", Vector2.ONE, 0.7).set_delay(0.2)

	# Phase 5: Stars pulse
	_pulse_star(_lbl_star, 0.3)


## Hide the banner with slide-out animation.
func hide_banner() -> void:
	if not _is_showing:
		return
	_is_showing = false

	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_banner_panel, "offset_top", float(-BANNER_HEIGHT), 0.3)
	tween.parallel().tween_property(_banner_panel, "offset_bottom", 0.0, 0.3)
	tween.parallel().tween_property(_dim_overlay, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func() -> void:
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner_closed.emit()
	)


## Whether the banner is currently visible.
func is_showing() -> bool:
	return _is_showing


# ── Internal ──

func _on_dim_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			hide_banner()


func _pulse_star(star: Label, delay: float) -> void:
	star.scale = Vector2.ONE
	star.pivot_offset = star.size / 2.0
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(star, "scale", Vector2(1.4, 1.4), 0.4).set_delay(delay)
	tween.tween_property(star, "scale", Vector2.ONE, 0.3)
