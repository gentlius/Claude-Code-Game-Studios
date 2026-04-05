## Skill Tree Overlay — Fullscreen overlay for browsing and unlocking skills.
## Auto-pauses game when open, resumes on close.
## See: design/gdd/progression-ui.md (Rule 4)
class_name SkillTreeOverlay
extends Control

# ── Signals ──

signal closed
## TD-03: Emitted instead of calling GameClock.toggle_pause() directly.
## Parent (TradingScreen) relays to GameClock via signal routing.
signal pause_toggle_requested

# ── Config (Tuning Knobs — GDD) ──

const DIM_ALPHA: float = 0.3
const SKILL_NODE_SIZE: int = 64
const GOLD_COLOR: Color = Color(0.85, 0.70, 0.20)
const GOLD_BG: Color = Color(0.85, 0.70, 0.20, 0.15)
const LOCKED_COLOR: Color = Color(0.40, 0.40, 0.42)
const AVAILABLE_COLOR: Color = Color(0.85, 0.70, 0.20)
const UNLOCKED_COLOR: Color = Color(1.0, 1.0, 1.0)
const PREREQ_MISSING_COLOR: Color = Color(0.55, 0.55, 0.58)
const PULSE_DURATION: float = 1.5

# Branch display order and Korean labels
const BRANCH_ORDER: Array[String] = ["analysis", "sense", "trading", "portfolio"]
const BRANCH_LABELS: Dictionary = {
	"analysis": "분석 도구",
	"sense": "시장 감지",
	"trading": "거래 스킬",
	"portfolio": "포트폴리오",
}

# ── State ──

var _is_open: bool = false
var _was_paused_before: bool = false
var _selected_skill_id: String = ""
var _skill_buttons: Dictionary = {}  ## skill_id -> Button

# ── Node References ──

var _dim_bg: ColorRect
var _main_panel: PanelContainer
var _header_lbl: Label
var _header_sp_lbl: Label
var _branch_container: HBoxContainer
var _detail_panel: PanelContainer
var _detail_name: Label
var _detail_desc: Label
var _detail_prereq: Label
var _btn_unlock: Button
var _btn_close: Button
var _pulse_tweens: Array[Tween] = []

# ── Lifecycle ──

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_ui()
	SkillTree.on_skill_unlocked.connect(_on_skill_unlocked)


# ── Public API ──

## Open the skill tree overlay and pause the game.
func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Pause game (track if already paused)
	_was_paused_before = GameClock.get_market_state() == GameClock.MarketState.PAUSED
	if not _was_paused_before:
		pause_toggle_requested.emit()

	_refresh_all()


## Close the overlay and resume the game.
func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_stop_pulse_tweens()

	# Resume if we paused it
	if not _was_paused_before:
		pause_toggle_requested.emit()

	closed.emit()


## Whether the overlay is currently open.
func is_open() -> bool:
	return _is_open


# ── UI Construction ──

func _build_ui() -> void:
	# Dim background
	_dim_bg = ColorRect.new()
	_dim_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim_bg.color = Color(0.0, 0.0, 0.0, DIM_ALPHA)
	_dim_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim_bg)

	# Main panel
	_main_panel = PanelContainer.new()
	_main_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_panel.offset_left = 40
	_main_panel.offset_right = -40
	_main_panel.offset_top = 30
	_main_panel.offset_bottom = -30
	var panel_style: StyleBoxFlat = ThemeSetup.make_panel_style(ThemeSetup.BG_PANEL, 12, ThemeSetup.BORDER_BRIGHT, 1)
	panel_style.set_content_margin_all(16)
	_main_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_main_panel)

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	_main_panel.add_child(root_vbox)

	# Header
	_build_header(root_vbox)

	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	root_vbox.add_child(sep)

	# Branch columns (scrollable)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root_vbox.add_child(scroll)

	_branch_container = HBoxContainer.new()
	_branch_container.add_theme_constant_override("separation", 24)
	_branch_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_branch_container.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(_branch_container)

	_build_branches()

	var sep2: HSeparator = HSeparator.new()
	sep2.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	root_vbox.add_child(sep2)

	# Detail panel (bottom)
	_build_detail_panel(root_vbox)


func _build_header(parent: VBoxContainer) -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	parent.add_child(hbox)

	var title: Label = Label.new()
	title.text = "스킬 트리"
	title.add_theme_font_size_override("font_size", 20)
	ThemeSetup.style_label_primary(title)
	hbox.add_child(title)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	_header_lbl = Label.new()
	_header_lbl.add_theme_font_size_override("font_size", 14)
	ThemeSetup.style_label_secondary(_header_lbl)
	hbox.add_child(_header_lbl)

	_header_sp_lbl = Label.new()
	_header_sp_lbl.add_theme_font_size_override("font_size", 14)
	_header_sp_lbl.add_theme_color_override("font_color", GOLD_COLOR)
	hbox.add_child(_header_sp_lbl)

	_btn_close = Button.new()
	_btn_close.text = "닫기 Esc"
	_btn_close.pressed.connect(close)
	ThemeSetup.apply_button_theme(_btn_close)
	hbox.add_child(_btn_close)


func _build_branches() -> void:
	for branch: String in BRANCH_ORDER:
		var branch_vbox: VBoxContainer = VBoxContainer.new()
		branch_vbox.add_theme_constant_override("separation", 8)
		branch_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		branch_vbox.custom_minimum_size.x = 140
		_branch_container.add_child(branch_vbox)

		# Branch title
		var title: Label = Label.new()
		title.text = BRANCH_LABELS.get(branch, branch)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 13)
		ThemeSetup.style_label_secondary(title)
		branch_vbox.add_child(title)

		# Skill nodes for this branch (sorted by tier)
		var skills: Array[Dictionary] = SkillTree.get_branch_skills(branch)
		skills.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tier"] < b["tier"])

		for skill: Dictionary in skills:
			var skill_id: String = skill["id"]
			var btn: Button = Button.new()
			btn.text = "%s %s" % [skill_id, skill["name"]]
			btn.custom_minimum_size = Vector2(140, 36)
			btn.pressed.connect(_on_skill_node_clicked.bind(skill_id))
			branch_vbox.add_child(btn)
			_skill_buttons[skill_id] = btn


func _build_detail_panel(parent: VBoxContainer) -> void:
	_detail_panel = PanelContainer.new()
	_detail_panel.custom_minimum_size.y = 80
	var style: StyleBoxFlat = ThemeSetup.make_panel_style(ThemeSetup.BG_DARK, 6, ThemeSetup.BORDER_DIM)
	style.set_content_margin_all(12)
	_detail_panel.add_theme_stylebox_override("panel", style)
	parent.add_child(_detail_panel)

	var detail_vbox: VBoxContainer = VBoxContainer.new()
	detail_vbox.add_theme_constant_override("separation", 4)
	_detail_panel.add_child(detail_vbox)

	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 15)
	ThemeSetup.style_label_primary(_detail_name)
	detail_vbox.add_child(_detail_name)

	_detail_desc = Label.new()
	_detail_desc.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_secondary(_detail_desc)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	detail_vbox.add_child(_detail_desc)

	_detail_prereq = Label.new()
	_detail_prereq.add_theme_font_size_override("font_size", 11)
	_detail_prereq.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	detail_vbox.add_child(_detail_prereq)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	detail_vbox.add_child(btn_row)

	_btn_unlock = Button.new()
	_btn_unlock.text = "해금하기 — 1 SP"
	_btn_unlock.visible = false
	_btn_unlock.pressed.connect(_on_unlock_pressed)
	var unlock_style: StyleBoxFlat = ThemeSetup.make_button_style(GOLD_COLOR, 6)
	unlock_style.set_content_margin_all(6)
	unlock_style.content_margin_left = 16
	unlock_style.content_margin_right = 16
	_btn_unlock.add_theme_stylebox_override("normal", unlock_style)
	_btn_unlock.add_theme_stylebox_override("hover", ThemeSetup.make_button_style(Color(0.75, 0.60, 0.15), 6))
	_btn_unlock.add_theme_color_override("font_color", Color.WHITE)
	_btn_unlock.add_theme_color_override("font_hover_color", Color.WHITE)
	btn_row.add_child(_btn_unlock)

	# Default text
	_detail_name.text = "스킬을 선택하세요"
	_detail_desc.text = ""
	_detail_prereq.text = ""


# ── Refresh ──

func _refresh_all() -> void:
	_update_header()
	_update_all_nodes()
	_update_detail()


func _update_header() -> void:
	_header_lbl.text = "Lv %d" % XpSystem.get_current_level()
	var sp: int = XpSystem.get_available_skill_points()
	_header_sp_lbl.text = "| SP: %d" % sp if sp > 0 else ""


func _update_all_nodes() -> void:
	_stop_pulse_tweens()

	for skill_id: String in _skill_buttons:
		var btn: Button = _skill_buttons[skill_id]
		var state: String = SkillTree.get_skill_state(skill_id)

		match state:
			"UNLOCKED":
				_style_node_unlocked(btn)
			"AVAILABLE":
				_style_node_available(btn)
				_start_pulse(btn)
			"LOCKED":
				_style_node_locked(btn)
			"PREREQ_MISSING":
				_style_node_prereq_missing(btn)


func _update_detail() -> void:
	if _selected_skill_id == "":
		_detail_name.text = "스킬을 선택하세요"
		_detail_desc.text = ""
		_detail_prereq.text = ""
		_btn_unlock.visible = false
		return

	var skills: Array[Dictionary] = SkillTree.get_all_skills()
	var skill: Dictionary = {}
	for s: Dictionary in skills:
		if s["id"] == _selected_skill_id:
			skill = s
			break

	if skill.is_empty():
		return

	var state: String = skill.get("state", "LOCKED")
	var state_label: String
	match state:
		"UNLOCKED":
			state_label = "✓ 해금됨"
		"AVAILABLE":
			state_label = "■ 해금 가능"
		"LOCKED":
			state_label = "□ SP 부족"
		"PREREQ_MISSING":
			state_label = "○ 잠김"
		_:
			state_label = state

	_detail_name.text = "%s %s  [%s]" % [skill["id"], skill["name"], state_label]
	_detail_desc.text = skill["description"]

	# Prerequisites
	var missing: Array[String] = SkillTree.get_missing_prerequisites(_selected_skill_id)
	if missing.size() > 0:
		var names: PackedStringArray = PackedStringArray()
		for mid: String in missing:
			names.append(mid)
		_detail_prereq.text = "선행 조건 미충족: %s" % ", ".join(names)
	else:
		_detail_prereq.text = ""

	# Unlock button
	_btn_unlock.visible = (state == "AVAILABLE")


# ── Node Styling ──

func _style_node_unlocked(btn: Button) -> void:
	var s: StyleBoxFlat = ThemeSetup.make_button_style(Color(0.85, 0.70, 0.20, 0.25), 6)
	s.border_color = GOLD_COLOR
	s.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_color_override("font_color", UNLOCKED_COLOR)
	btn.add_theme_color_override("font_hover_color", UNLOCKED_COLOR)


func _style_node_available(btn: Button) -> void:
	var s: StyleBoxFlat = ThemeSetup.make_button_style(Color(0.85, 0.70, 0.20, 0.1), 6)
	s.border_color = AVAILABLE_COLOR
	s.set_border_width_all(2)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", ThemeSetup.make_button_style(Color(0.85, 0.70, 0.20, 0.25), 6))
	btn.add_theme_color_override("font_color", AVAILABLE_COLOR)
	btn.add_theme_color_override("font_hover_color", AVAILABLE_COLOR)


func _style_node_locked(btn: Button) -> void:
	var s: StyleBoxFlat = ThemeSetup.make_button_style(ThemeSetup.BG_DARK, 6)
	s.border_color = PREREQ_MISSING_COLOR
	s.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_color_override("font_color", PREREQ_MISSING_COLOR)
	btn.add_theme_color_override("font_hover_color", PREREQ_MISSING_COLOR)


func _style_node_prereq_missing(btn: Button) -> void:
	var s: StyleBoxFlat = ThemeSetup.make_button_style(ThemeSetup.BG_DARKEST, 6)
	s.border_color = LOCKED_COLOR
	s.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_color_override("font_color", LOCKED_COLOR)
	btn.add_theme_color_override("font_hover_color", LOCKED_COLOR)


# ── Pulse Animation ──

func _start_pulse(btn: Button) -> void:
	var tween: Tween = create_tween()
	tween.set_loops()
	tween.tween_property(btn, "modulate:a", 0.6, PULSE_DURATION / 2.0)
	tween.tween_property(btn, "modulate:a", 1.0, PULSE_DURATION / 2.0)
	_pulse_tweens.append(tween)


func _stop_pulse_tweens() -> void:
	for tween: Tween in _pulse_tweens:
		if tween.is_valid():
			tween.kill()
	_pulse_tweens.clear()

	# Reset modulate on all buttons
	for skill_id: String in _skill_buttons:
		_skill_buttons[skill_id].modulate.a = 1.0


# ── Signal Handlers ──

func _on_skill_node_clicked(skill_id: String) -> void:
	_selected_skill_id = skill_id
	_update_detail()


func _on_unlock_pressed() -> void:
	if _selected_skill_id == "":
		return
	var success: bool = SkillTree.unlock_skill(_selected_skill_id)
	if success:
		_refresh_all()


func _on_skill_unlocked(_skill_id: String) -> void:
	if _is_open:
		_refresh_all()
