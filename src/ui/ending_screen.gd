## EndingScreen — 3종 엔딩 화면 (한강/사채업자/거장). GDD endings-achievements.md §3-1~3-3.
## CanvasLayer(layer=20) — 전체 UI 위에 덮인다.
## GameMain에서 3개 시그널 수신 시 show_ending(ending_id) 호출.
##
## ending_id 값:
##   "bankruptcy"      — 한강 엔딩  (sim_cash < HANGANG_THRESHOLD)
##   "leverage_crash"  — 사채업자 엔딩  (레버리지 강제청산 후 채무불능)
##   "win"             — 투자의 거장 엔딩  (total_assets ≥ ENDING_THRESHOLD)
##
## 엔딩 데이터는 MarketProfile.get_ending_param(ending_id, field)에서 읽는다. ADR-021.
## JSON 필드: name_key / body_key / sfx_key / visual / action_label_key / is_bad_ending
## See: design/gdd/endings-achievements.md §9 Implementation Checklist
class_name EndingScreen
extends CanvasLayer

# ── Signals ──

## Emitted when the player presses "새 게임" after a bad ending.
## GameMain handles save reset + StartScreen transition.
signal new_game_requested()

## Emitted when the player presses "계속하기" after the win ending.
## (거장 엔딩 후 리더보드 확인 등 계속 플레이. 현재는 StartScreen 복귀.)
signal continue_requested()

## Fallback ending_id used when MarketProfile has no entry for the given id. ADR-021.
const _FALLBACK_ENDING_ID: String = "bankruptcy"

# ── Node References ──

var _bg: ColorRect
var _panel: PanelContainer
var _lbl_title: Label
var _lbl_body: Label
var _texture_rect: TextureRect
var _btn_action: Button
var _current_ending_id: String = ""

# ── Lifecycle ──

func _ready() -> void:
	layer = 20
	_build_ui()
	visible = false


## 전체 화면 배경, 결말 텍스트, 통계 패널, 재도전 버튼 구성.
func _build_ui() -> void:
	# Full-screen dim
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color(0.0, 0.0, 0.0, 0.85)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	# Center panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(520.0, 0.0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10, 0.97)
	style.set_border_width_all(2)
	style.border_color = Color(0.30, 0.30, 0.35)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(32.0)
	_panel.add_theme_stylebox_override("panel", style)
	_bg.add_child(_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(vbox)

	# Title
	_lbl_title = Label.new()
	_lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_title.add_theme_font_size_override("font_size", 28)
	_lbl_title.add_theme_color_override("font_color", ThemeSetup.TEXT_PRIMARY)
	vbox.add_child(_lbl_title)

	vbox.add_child(HSeparator.new())

	# Visual image (hidden when no asset)
	_texture_rect = TextureRect.new()
	_texture_rect.custom_minimum_size = Vector2(0.0, 200.0)
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	_texture_rect.visible = false
	vbox.add_child(_texture_rect)

	# Body text
	_lbl_body = Label.new()
	_lbl_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_body.add_theme_font_size_override("font_size", 14)
	_lbl_body.add_theme_color_override("font_color", ThemeSetup.TEXT_SECONDARY)
	vbox.add_child(_lbl_body)

	vbox.add_child(HSeparator.new())

	# Action button
	_btn_action = Button.new()
	_btn_action.custom_minimum_size = Vector2(200.0, 48.0)
	_btn_action.add_theme_font_size_override("font_size", 16)
	_btn_action.pressed.connect(_on_action_pressed)
	vbox.add_child(_btn_action)
	# Center button inside vbox
	_btn_action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

# ── Public API ──

## Display the ending screen for [param ending_id].
## Reads all display data from MarketProfile.get_ending_param() (ADR-021).
## Plays sfx if sfx_key is set. Falls back to "bankruptcy" entry if id not found.
func show_ending(ending_id: String) -> void:
	# Resolve to a valid ending entry — fallback guards against unknown ids.
	var valid_id: String = ending_id if MarketProfile.get_ending_param(ending_id, "is_bad_ending") != null \
			else _FALLBACK_ENDING_ID
	_current_ending_id = valid_id

	var name_key: String    = str(MarketProfile.get_ending_param(valid_id, "name_key"))
	var body_key: String    = str(MarketProfile.get_ending_param(valid_id, "body_key"))
	var action_key: String  = str(MarketProfile.get_ending_param(valid_id, "action_label_key"))
	var is_bad: bool        = bool(MarketProfile.get_ending_param(valid_id, "is_bad_ending"))

	_lbl_title.text   = tr(name_key)
	_lbl_body.text    = tr(body_key)
	_btn_action.text  = tr(action_key)

	# Title colour: gold for win, dim-red for bad endings
	if not is_bad:
		_lbl_title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	else:
		_lbl_title.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)

	# Visual
	var visual_path: String = str(MarketProfile.get_ending_param(valid_id, "visual"))
	if not visual_path.is_empty() and ResourceLoader.exists(visual_path):
		_texture_rect.texture = load(visual_path)
		_texture_rect.visible = true
	else:
		_texture_rect.visible = false

	# SFX
	var sfx_id: String = str(MarketProfile.get_ending_param(valid_id, "sfx_key"))
	if not sfx_id.is_empty():
		AudioManager.play_sfx(sfx_id)

	visible = true


## Returns true if the currently-shown ending is a bad ending (bankruptcy / leverage_crash).
func is_bad_ending() -> bool:
	var result: Variant = MarketProfile.get_ending_param(_current_ending_id, "is_bad_ending")
	return bool(result) if result != null else true

# ── Internal ──

func _on_action_pressed() -> void:
	visible = false
	AudioManager.play_sfx("sfx_btn_click")
	if is_bad_ending():
		new_game_requested.emit()
	else:
		continue_requested.emit()
