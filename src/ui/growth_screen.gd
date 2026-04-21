## GrowthScreen — F3 탭: 스킬 트리 + 자산 요약.
## 팝업 없음 — 항상 펼쳐진 4브랜치 스킬 트리 + 하단 자산 패널.
## See: design/gdd/growth-screen.md
class_name GrowthScreen
extends Control

# ── Constants ──

const BRANCHES: Array[String] = ["analysis", "sense", "trading", "portfolio"]
const BRANCH_LABELS: Dictionary = {
	"analysis": "분석 도구",
	"sense": "시장 감지",
	"trading": "거래 스킬",
	"portfolio": "포트폴리오",
}

## Node state colors
const COLOR_UNLOCKED: Color = Color(0.20, 0.75, 0.30)   ## 초록 — 해금됨
const COLOR_AVAILABLE: Color = Color(0.85, 0.70, 0.20)   ## 금색 — 해금 가능
const COLOR_LOCKED: Color = Color(0.40, 0.40, 0.40)      ## 회색 — 잠금
const COLOR_PREREQ: Color = Color(0.25, 0.25, 0.25)      ## 어두운 회색 — 선행 조건 미충족

## Residence background art — indexed by LifestyleManager residence tier.
## Mirrors LifestyleManager.RESIDENCE_NAMES order (tier 0 = bronze default).
## Implements: design/gdd/lifestyle-spending.md §3-5 F3 연동
const RESIDENCE_ART: Array[String] = [
	"res://assets/art/housing/bronze_jjokbang.png",
	"res://assets/art/housing/silver_oneroom.png",
	"res://assets/art/housing/gold_officetel.png",
	"res://assets/art/housing/platinum_apartment.png",
	"res://assets/art/housing/emerald_large_apartment.png",
	"res://assets/art/housing/diamond_penthouse.png",
	"res://assets/art/housing/master_mansion.png",
	"res://assets/art/housing/grandmaster_island_villa.png",
	"res://assets/art/housing/challenger_sky_residence.png",
	"res://assets/art/housing/legend_official_residence.png",
	"res://assets/art/housing/grandmaster_ending.png",
]

# ── Node References ──

var _lbl_level: Label
var _xp_bar: ProgressBar
var _lbl_xp: Label
var _lbl_sp: Label

## skill_id → Button
var _skill_buttons: Dictionary = {}

## Selected skill ID for detail panel
var _selected_skill_id: String = ""

var _detail_panel: PanelContainer
var _lbl_detail_name: Label
var _lbl_detail_desc: Label
var _lbl_detail_prereq: Label
var _btn_unlock: Button

var _lbl_total_assets: Label
var _lbl_cash_assets: Label
var _lbl_account_value: Label
var _lbl_tangible: Label
var _lbl_residence: Label

## Background image layer — current residence art (S8-07).
var _bg_texture: TextureRect

# ── Lifecycle ──

func _ready() -> void:
	_build_ui()
	SkillTree.on_skill_unlocked.connect(_on_skill_unlocked)
	LifestyleManager.residence_changed.connect(_on_residence_changed)
	visibility_changed.connect(_on_visibility_changed)
	tree_exiting.connect(_disconnect_signals)
	_refresh()


func _on_visibility_changed() -> void:
	if visible:
		_refresh()


func _on_skill_unlocked(_skill_id: String) -> void:
	_refresh()


func _on_residence_changed(_tier: int, _name: String) -> void:
	_refresh_bg()


func _disconnect_signals() -> void:
	if SkillTree.on_skill_unlocked.is_connected(_on_skill_unlocked):
		SkillTree.on_skill_unlocked.disconnect(_on_skill_unlocked)
	if LifestyleManager.residence_changed.is_connected(_on_residence_changed):
		LifestyleManager.residence_changed.disconnect(_on_residence_changed)

# ── Refresh ──

func _refresh() -> void:
	_refresh_header()
	_refresh_skill_nodes()
	_refresh_assets()
	_refresh_bg()
	if not _selected_skill_id.is_empty():
		_refresh_detail(_selected_skill_id)


## 레벨, 주간 XP, SP 표시 레이블을 현재 XpSystem 값으로 갱신.
func _refresh_header() -> void:
	var level: int = XpSystem.get_current_level()
	_lbl_level.text = "Lv.%d" % level

	var progress: float = XpSystem.get_xp_progress()
	_xp_bar.value = progress * 100.0

	var total_xp: int = XpSystem.get_total_xp()
	var sp: int = XpSystem.get_available_skill_points()
	_lbl_xp.text = "%d XP" % total_xp
	if sp > 0:
		_lbl_sp.text = "SP: %d개" % sp
		_lbl_sp.visible = true
	else:
		_lbl_sp.visible = false


## 모든 스킬 버튼의 해금 상태·활성화 여부를 SkillTree 상태에 맞게 갱신.
func _refresh_skill_nodes() -> void:
	for skill_id: String in _skill_buttons:
		var btn: Button = _skill_buttons[skill_id] as Button
		var state: String = SkillTree.get_skill_state(skill_id)
		match state:
			"UNLOCKED":
				btn.add_theme_color_override("font_color", COLOR_UNLOCKED)
				btn.add_theme_color_override("font_hover_color", COLOR_UNLOCKED)
				btn.disabled = false
			"AVAILABLE":
				btn.add_theme_color_override("font_color", COLOR_AVAILABLE)
				btn.add_theme_color_override("font_hover_color", COLOR_AVAILABLE)
				btn.disabled = false
			"PREREQ_MISSING":
				btn.add_theme_color_override("font_color", COLOR_PREREQ)
				btn.add_theme_color_override("font_hover_color", COLOR_PREREQ)
				btn.disabled = false
			_:  ## LOCKED
				btn.add_theme_color_override("font_color", COLOR_LOCKED)
				btn.add_theme_color_override("font_hover_color", COLOR_LOCKED)
				btn.disabled = false


## [param skill_id] 스킬의 이름·설명·선행조건·SP 비용을 디테일 패널에 표시.
func _refresh_detail(skill_id: String) -> void:
	var skills: Array[Dictionary] = SkillTree.get_all_skills()
	for skill: Dictionary in skills:
		if skill.get("id", "") != skill_id:
			continue
		_lbl_detail_name.text = "%s (%s)" % [skill.get("name", ""), skill_id]
		_lbl_detail_desc.text = skill.get("description", "")

		var state: String = SkillTree.get_skill_state(skill_id)
		var prereqs: Array = skill.get("prerequisites", [])
		if prereqs.is_empty():
			_lbl_detail_prereq.text = "선행 조건: 없음"
		else:
			_lbl_detail_prereq.text = "선행 조건: %s" % ", ".join(prereqs)

		_btn_unlock.disabled = (state != "AVAILABLE")
		match state:
			"UNLOCKED": _btn_unlock.text = "해금됨 ✓"
			"AVAILABLE": _btn_unlock.text = "해금 (SP 1개)"
			"LOCKED": _btn_unlock.text = "잠금 (SP 부족)"
			"PREREQ_MISSING": _btn_unlock.text = "잠금 (선행 조건 미충족)"
		_detail_panel.visible = true
		return


## 현금·평가금액 레이블을 현재 포트폴리오 값으로 갱신.
func _refresh_assets() -> void:
	var cash: int = 0           ## Beta Sprint 9 (B-02): CurrencySystem.get_real_cash() — LifestyleManager 구현 시 활성화
	var portfolio: int = PortfolioManager.get_total_assets()  ## 예수금 + 예약금 + 보유종목 평가액
	var tangible: int = 0       ## Beta Sprint 9 (B-02): LifestyleManager.get_tangible_value()
	var total: int = cash + portfolio + tangible
	_lbl_total_assets.text = tr("총 자산 평가액  %s") % FormatUtils.currency(total)
	_lbl_cash_assets.text = tr("보유 현금  %s") % FormatUtils.currency(cash)
	_lbl_account_value.text = tr("포트폴리오 평가액  %s") % FormatUtils.currency(portfolio)
	_lbl_tangible.text = tr("실물 자산  %s") % FormatUtils.currency(tangible)


## Loads and displays the current residence background image (S8-07).
## Called on _refresh() and _on_residence_changed() — Godot caches the texture after first load.
## Implements: design/gdd/lifestyle-spending.md §3-5 — F3 배경 = 현재 거주지 이미지
func _refresh_bg() -> void:
	var tier: int = clampi(LifestyleManager.get_residence_tier(), 0, RESIDENCE_ART.size() - 1)
	var path: String = RESIDENCE_ART[tier]
	if ResourceLoader.exists(path):
		_bg_texture.texture = load(path) as Texture2D
	_lbl_residence.text = LifestyleManager.get_residence_name()

# ── UI Construction ──

## 전체 성장 화면 레이아웃(헤더·스킬트리·디테일·자산 패널) 구성 및 노드 캐시 초기화.
func _build_ui() -> void:
	# Solid dark base — project clear color is near-white (#F5F5F8) so GrowthScreen
	# (a plain Control = transparent) would show through as white without this rect.
	var bg_base: ColorRect = ColorRect.new()
	bg_base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_base.color = Color(0.08, 0.08, 0.09)   # matches ThemeSetup.LAYOUT_BG
	bg_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_base)

	# Residence image overlay — drawn on dark base so 25% alpha creates atmosphere.
	_bg_texture = TextureRect.new()
	_bg_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_texture.modulate = Color(1.0, 1.0, 1.0, 0.45)
	_bg_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_texture)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	root.set_custom_minimum_size(Vector2(0, 0))
	scroll.add_child(root)

	_build_header(root)
	root.add_child(HSeparator.new())
	_build_skill_tree(root)
	_build_detail_panel(root)
	root.add_child(HSeparator.new())
	_build_asset_panel(root)


## 레벨·XP 바·SP 레이블을 포함한 상단 헤더 패널을 [param parent]에 추가하고 노드 캐시.
func _build_header(parent: VBoxContainer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.y = 48
	parent.add_child(panel)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	panel.add_child(hbox)

	_lbl_level = Label.new()
	_lbl_level.text = "Lv.1"
	_lbl_level.add_theme_font_size_override("font_size", 18)
	_lbl_level.add_theme_color_override("font_color", Color.WHITE)
	hbox.add_child(_lbl_level)

	_xp_bar = ProgressBar.new()
	_xp_bar.min_value = 0.0
	_xp_bar.max_value = 100.0
	_xp_bar.value = 0.0
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(200, 12)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = COLOR_AVAILABLE
	pb_fill.set_corner_radius_all(3)
	_xp_bar.add_theme_stylebox_override("fill", pb_fill)
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.20, 0.20, 0.25)
	pb_bg.set_corner_radius_all(3)
	_xp_bar.add_theme_stylebox_override("background", pb_bg)
	hbox.add_child(_xp_bar)

	_lbl_xp = Label.new()
	_lbl_xp.text = "0 XP"
	_lbl_xp.add_theme_font_size_override("font_size", 13)
	_lbl_xp.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	hbox.add_child(_lbl_xp)

	_lbl_sp = Label.new()
	_lbl_sp.text = "SP: 0개"
	_lbl_sp.add_theme_font_size_override("font_size", 14)
	_lbl_sp.add_theme_color_override("font_color", COLOR_AVAILABLE)
	_lbl_sp.visible = false
	hbox.add_child(_lbl_sp)


## A/S/TR/P 4개 브랜치 컬럼을 가로로 배치하는 스킬트리 그리드를 구성.
func _build_skill_tree(parent: VBoxContainer) -> void:
	var grid: HBoxContainer = HBoxContainer.new()
	grid.add_theme_constant_override("separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)

	for branch: String in BRANCHES:
		var col: VBoxContainer = _build_branch_column(branch)
		grid.add_child(col)


## [param branch] 브랜치(A/S/TR/P)의 스킬 버튼 컬럼을 생성해 반환. _skill_buttons 캐시 등록.
func _build_branch_column(branch: String) -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)

	var header_panel: PanelContainer = PanelContainer.new()
	var h_style: StyleBoxFlat = StyleBoxFlat.new()
	h_style.bg_color = Color(0.12, 0.12, 0.15)
	header_panel.add_theme_stylebox_override("panel", h_style)
	col.add_child(header_panel)

	var header_lbl: Label = Label.new()
	header_lbl.text = BRANCH_LABELS.get(branch, branch)
	header_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_lbl.add_theme_font_size_override("font_size", 13)
	header_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90))
	header_panel.add_child(header_lbl)

	# Get skills for this branch, sorted by tier
	var skills: Array[Dictionary] = []
	for s: Dictionary in SkillTree.get_branch_skills(branch):
		skills.append(s)
	skills.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("tier", 0) < b.get("tier", 0)
	)

	for skill: Dictionary in skills:
		var skill_id: String = skill.get("id", "")
		var btn: Button = Button.new()
		btn.text = "● %s" % skill.get("name", skill_id)
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.custom_minimum_size.y = 36
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		var btn_style: StyleBoxFlat = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.10, 0.10, 0.12)
		btn_style.set_border_width_all(1)
		btn_style.border_color = Color(0.25, 0.25, 0.30)
		btn.add_theme_stylebox_override("normal", btn_style)
		var hover_style: StyleBoxFlat = StyleBoxFlat.new()
		hover_style.bg_color = Color(0.15, 0.15, 0.18)
		hover_style.set_border_width_all(1)
		hover_style.border_color = Color(0.40, 0.40, 0.50)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("pressed", hover_style)
		btn.add_theme_font_size_override("font_size", 12)
		var captured_id: String = skill_id
		btn.pressed.connect(func() -> void: _on_skill_node_clicked(captured_id))
		col.add_child(btn)
		_skill_buttons[skill_id] = btn

	return col


## 선택 스킬의 이름·설명·선행조건·SP 비용·해금 버튼을 표시하는 디테일 패널 구성.
func _build_detail_panel(parent: VBoxContainer) -> void:
	_detail_panel = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.10)
	style.set_border_width_all(1)
	style.border_color = Color(0.20, 0.25, 0.35)
	_detail_panel.add_theme_stylebox_override("panel", style)
	_detail_panel.custom_minimum_size.y = 80
	_detail_panel.visible = false
	parent.add_child(_detail_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_detail_panel.add_child(vbox)

	var top_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(top_row)

	_lbl_detail_name = Label.new()
	_lbl_detail_name.text = ""
	_lbl_detail_name.add_theme_font_size_override("font_size", 14)
	_lbl_detail_name.add_theme_color_override("font_color", Color.WHITE)
	_lbl_detail_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_lbl_detail_name)

	_btn_unlock = Button.new()
	_btn_unlock.text = "해금"
	_btn_unlock.custom_minimum_size.x = 140
	_btn_unlock.pressed.connect(_on_unlock_pressed)
	top_row.add_child(_btn_unlock)

	_lbl_detail_desc = Label.new()
	_lbl_detail_desc.text = ""
	_lbl_detail_desc.add_theme_font_size_override("font_size", 12)
	_lbl_detail_desc.add_theme_color_override("font_color", Color(0.75, 0.75, 0.80))
	_lbl_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_lbl_detail_desc)

	_lbl_detail_prereq = Label.new()
	_lbl_detail_prereq.text = ""
	_lbl_detail_prereq.add_theme_font_size_override("font_size", 11)
	_lbl_detail_prereq.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
	vbox.add_child(_lbl_detail_prereq)


## 현금·평가금액 레이블을 표시하는 하단 자산 패널 구성.
func _build_asset_panel(parent: VBoxContainer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.y = 56
	parent.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	_lbl_total_assets = Label.new()
	_lbl_total_assets.text = "총 자산 평가액  ₩0"
	_lbl_total_assets.add_theme_font_size_override("font_size", 18)
	_lbl_total_assets.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_lbl_total_assets)

	var sub_row: HBoxContainer = HBoxContainer.new()
	sub_row.add_theme_constant_override("separation", 24)
	vbox.add_child(sub_row)

	_lbl_cash_assets = Label.new()
	_lbl_cash_assets.text = "보유 현금  ₩0"
	_lbl_cash_assets.add_theme_font_size_override("font_size", 13)
	_lbl_cash_assets.add_theme_color_override("font_color", Color(0.75, 0.75, 0.80))
	sub_row.add_child(_lbl_cash_assets)

	_lbl_account_value = Label.new()
	_lbl_account_value.text = "포트폴리오 평가액  ₩0"
	_lbl_account_value.add_theme_font_size_override("font_size", 13)
	_lbl_account_value.add_theme_color_override("font_color", Color(0.75, 0.75, 0.80))
	sub_row.add_child(_lbl_account_value)

	_lbl_tangible = Label.new()
	_lbl_tangible.text = "실물 자산  ₩0"
	_lbl_tangible.add_theme_font_size_override("font_size", 13)
	_lbl_tangible.add_theme_color_override("font_color", Color(0.50, 0.50, 0.55))
	sub_row.add_child(_lbl_tangible)

	# Current residence name — updated by _refresh_bg() (S8-07)
	_lbl_residence = Label.new()
	_lbl_residence.text = ""
	_lbl_residence.add_theme_font_size_override("font_size", 12)
	_lbl_residence.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
	vbox.add_child(_lbl_residence)

# ── Interaction ──

func _on_skill_node_clicked(skill_id: String) -> void:
	_selected_skill_id = skill_id
	_refresh_detail(skill_id)


func _on_unlock_pressed() -> void:
	if _selected_skill_id.is_empty():
		return
	var success: bool = SkillTree.unlock_skill(_selected_skill_id)
	if success:
		_refresh()
