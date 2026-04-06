## XP Bar — Inline widget showing level, XP progress, and skill points.
## Designed to sit inside the status bar HBox (not as a separate row).
## See: design/gdd/progression-ui.md (Rule 1, Rule 6)
class_name XpBar
extends HBoxContainer

# ── Signals ──

signal skill_tree_requested

# ── Config (Tuning Knobs — GDD) ──

const XP_BAR_ANIM_DURATION: float = 1.5
const XP_FLOAT_DURATION: float = 1.2
const SP_PULSE_DURATION: float = 0.8
const GOLD_COLOR: Color = Color(0.85, 0.70, 0.20)
const GOLD_DIM: Color = Color(0.65, 0.50, 0.10)
const GOLD_BG: Color = Color(0.85, 0.70, 0.20, 0.18)
const GOLD_BRIGHT: Color = Color(0.95, 0.80, 0.25)

# ── Node References ──

var _lbl_level: Label
var _progress_bg: Panel
var _progress_fill: ColorRect
var _lbl_xp_text: Label
var _btn_sp_badge: Button
var _float_container: Control  ## Overlay container for floating text
var _sp_visible: bool = false
var _fill_ratio: float = 0.0

# ── Lifecycle ──

func _ready() -> void:
	add_theme_constant_override("separation", 6)

	# Separator before XP section
	var sep: VSeparator = VSeparator.new()
	sep.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	add_child(sep)

	# Level badge — gold with subtle background
	_lbl_level = Label.new()
	_lbl_level.add_theme_font_size_override("font_size", 13)
	_lbl_level.add_theme_color_override("font_color", GOLD_COLOR)
	add_child(_lbl_level)

	# Custom progress bar (Panel background + ColorRect fill) for precise control
	var bar_container: Control = Control.new()
	bar_container.custom_minimum_size = Vector2(120, 12)
	bar_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(bar_container)

	_progress_bg = Panel.new()
	_progress_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_style: StyleBoxFlat = StyleBoxFlat.new()
	bg_style.bg_color = GOLD_BG
	bg_style.set_corner_radius_all(6)
	_progress_bg.add_theme_stylebox_override("panel", bg_style)
	bar_container.add_child(_progress_bg)

	_progress_fill = ColorRect.new()
	_progress_fill.anchor_top = 0.0
	_progress_fill.anchor_bottom = 1.0
	_progress_fill.anchor_left = 0.0
	_progress_fill.anchor_right = 0.0
	_progress_fill.offset_left = 2
	_progress_fill.offset_top = 2
	_progress_fill.offset_bottom = -2
	_progress_fill.color = GOLD_COLOR
	# Round corners via clip (visual only — the bg panel provides the rounded border)
	bar_container.add_child(_progress_fill)

	# XP text — current/max inside the bar
	_lbl_xp_text = Label.new()
	_lbl_xp_text.add_theme_font_size_override("font_size", 10)
	_lbl_xp_text.add_theme_color_override("font_color", GOLD_DIM)
	add_child(_lbl_xp_text)

	# SP badge (clickable) — gold accent with pulse animation
	_btn_sp_badge = Button.new()
	_btn_sp_badge.add_theme_font_size_override("font_size", 12)
	_btn_sp_badge.visible = false
	_btn_sp_badge.pressed.connect(func() -> void: skill_tree_requested.emit())
	var sp_normal: StyleBoxFlat = ThemeSetup.make_button_style(GOLD_BG, 4)
	sp_normal.set_content_margin_all(2)
	sp_normal.content_margin_left = 8
	sp_normal.content_margin_right = 8
	_btn_sp_badge.add_theme_stylebox_override("normal", sp_normal)
	_btn_sp_badge.add_theme_stylebox_override("hover", ThemeSetup.make_button_style(Color(0.85, 0.70, 0.20, 0.3), 4))
	_btn_sp_badge.add_theme_stylebox_override("pressed", ThemeSetup.make_button_style(Color(0.85, 0.70, 0.20, 0.4), 4))
	_btn_sp_badge.add_theme_color_override("font_color", GOLD_COLOR)
	_btn_sp_badge.add_theme_color_override("font_hover_color", GOLD_BRIGHT)
	add_child(_btn_sp_badge)

	# Floating text container (positioned above this widget)
	_float_container = Control.new()
	_float_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_float_container)

	# Connect signals
	XpSystem.on_xp_gained.connect(_on_xp_gained)
	XpSystem.on_level_up.connect(_on_level_up)
	tree_exiting.connect(_disconnect_signals)

	update_display()


# ── Public API ──

## Refresh the display from current XpSystem state (no animation).
func update_display() -> void:
	var level: int = XpSystem.get_current_level()
	var progress: float = XpSystem.get_xp_progress()
	var sp: int = XpSystem.get_available_skill_points()

	_lbl_level.text = "Lv.%d" % level

	# Update fill bar width
	_fill_ratio = progress
	_update_fill_rect()

	# XP text: current_in_level / needed_for_next
	var total_xp: int = XpSystem.get_total_xp()
	var current_threshold: int = XpSystem.get_cumulative_xp_for_level(level)
	var next_threshold: int = XpSystem.get_cumulative_xp_for_level(level + 1)
	var xp_in_level: int = total_xp - current_threshold
	var xp_needed: int = next_threshold - current_threshold
	_lbl_xp_text.text = "%d/%d" % [xp_in_level, xp_needed]

	_update_sp_badge(sp)


## Animate XP bar fill from previous value to current (after settlement popup).
func animate_xp_gain() -> void:
	if _reduced_motion():
		update_display()
		return
	var target: float = XpSystem.get_xp_progress()
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(_set_fill_ratio, _fill_ratio, target, XP_BAR_ANIM_DURATION)
	tween.tween_callback(update_display)


# ── Signal Handlers ──

func _on_xp_gained(amount: int, _new_total: int, _source: String) -> void:
	_spawn_float_text("+%d XP" % amount)
	if _reduced_motion():
		update_display()
		return
	# Animate bar fill
	var old_ratio: float = _fill_ratio
	var new_ratio: float = XpSystem.get_xp_progress()
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(_set_fill_ratio, old_ratio, new_ratio, XP_BAR_ANIM_DURATION)
	tween.tween_callback(update_display)


func _on_level_up(new_level: int, _skill_points: int) -> void:
	_lbl_level.text = "Lv.%d" % new_level
	update_display()
	if _reduced_motion():
		return
	# Level badge bounce animation
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)
	_lbl_level.scale = Vector2(1.4, 1.4)
	_lbl_level.add_theme_color_override("font_color", GOLD_BRIGHT)
	tween.tween_property(_lbl_level, "scale", Vector2.ONE, 0.6)
	tween.tween_callback(func() -> void:
		_lbl_level.add_theme_color_override("font_color", GOLD_COLOR)
	)


# ── Internal ──

func _set_fill_ratio(ratio: float) -> void:
	_fill_ratio = ratio
	_update_fill_rect()


func _update_fill_rect() -> void:
	if not is_inside_tree():
		return
	var bar_w: float = _progress_bg.size.x
	if bar_w <= 0:
		return
	var fill_w: float = maxf(0.0, (bar_w - 4) * clampf(_fill_ratio, 0.0, 1.0))
	_progress_fill.offset_right = _progress_fill.offset_left + fill_w


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_fill_rect()


func _update_sp_badge(sp: int) -> void:
	if sp > 0:
		_btn_sp_badge.text = "SP %d" % sp
		if not _sp_visible:
			_sp_visible = true
			_btn_sp_badge.visible = true
			if _reduced_motion():
				return
			# Pulse animation on first appear
			_btn_sp_badge.modulate.a = 0.0
			_btn_sp_badge.scale = Vector2(1.3, 1.3)
			var tween: Tween = create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_BACK)
			tween.tween_property(_btn_sp_badge, "modulate:a", 1.0, SP_PULSE_DURATION)
			tween.parallel().tween_property(_btn_sp_badge, "scale", Vector2.ONE, SP_PULSE_DURATION)
	else:
		_btn_sp_badge.visible = false
		_sp_visible = false


func _reduced_motion() -> bool:
	return ProjectSettings.get_setting("accessibility/reduced_motion", false)


func _disconnect_signals() -> void:
	if XpSystem.on_xp_gained.is_connected(_on_xp_gained):
		XpSystem.on_xp_gained.disconnect(_on_xp_gained)
	if XpSystem.on_level_up.is_connected(_on_level_up):
		XpSystem.on_level_up.disconnect(_on_level_up)


func _spawn_float_text(text: String) -> void:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", GOLD_BRIGHT)
	lbl.position = Vector2(40, -8)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float_container.add_child(lbl)

	if _reduced_motion():
		lbl.queue_free()
		return

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", -30.0, XP_FLOAT_DURATION)
	tween.tween_property(lbl, "modulate:a", 0.0, XP_FLOAT_DURATION).set_delay(0.4)
	tween.chain().tween_callback(lbl.queue_free)
