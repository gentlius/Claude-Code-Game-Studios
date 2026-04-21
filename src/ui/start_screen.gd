class_name StartScreen
extends Control
## 슬롯 선택 화면. 저장된 슬롯 목록 표시, 새 게임 생성, 슬롯 삭제.
## GDD: design/gdd/start-screen.md

## 슬롯 클릭 시 emit — game_main이 수신해 SaveSystem.load_slot() 호출.
signal slot_selected(id: int)
## 새 게임 확인 시 emit — game_main이 수신해 init_first_season() → IntroSequence 실행.
signal new_game_confirmed(slot_id: int)

## 슬롯 이름 최대 글자 수. GDD §7 튜닝 노브.
const SLOT_NAME_MAX_LENGTH: int = 20

var _slot_list: VBoxContainer
var _name_input: LineEdit
var _new_game_popup: AcceptDialog
var _delete_popup: ConfirmationDialog
var _delete_slot_id: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_refresh_slots()
	AudioManager.play_bgm("bgm_start_screen")
	tree_exiting.connect(AudioManager.stop_bgm)


# ── UI Construction ──

func _build_ui() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = ThemeSetup.START_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	_build_header_bar(root_vbox)
	_build_slot_scroll(root_vbox)
	_build_popups()


## Builds the top header panel with the title and [새 게임 +] button.
func _build_header_bar(root_vbox: VBoxContainer) -> void:
	var header_panel: PanelContainer = PanelContainer.new()
	var header_style: StyleBoxFlat = StyleBoxFlat.new()
	header_style.bg_color = ThemeSetup.LAYOUT_BG
	header_panel.add_theme_stylebox_override("panel", header_style)
	root_vbox.add_child(header_panel)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header_panel.add_child(header)

	var left_margin: Control = Control.new()
	left_margin.custom_minimum_size.x = 12
	header.add_child(left_margin)

	var deco_lbl: Label = Label.new()
	deco_lbl.text = "▶"
	deco_lbl.add_theme_font_size_override("font_size", 14)
	deco_lbl.add_theme_color_override("font_color", ThemeSetup.START_PORTFOLIO_VALUE)
	deco_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(deco_lbl)

	var title_lbl: Label = Label.new()
	title_lbl.text = "SEED MONEY"  ## intentionally NOT wrapped in tr() — brand name, not translated
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", ThemeSetup.START_TEXT_BRIGHT)
	header.add_child(title_lbl)

	var btn_new: Button = Button.new()
	btn_new.text = tr("새 게임 +")
	btn_new.custom_minimum_size.x = 120
	btn_new.pressed.connect(_on_new_game_pressed)
	ThemeSetup.apply_accent_button(btn_new)
	header.add_child(btn_new)


## Builds the scrollable slot list area and assigns _slot_list.
func _build_slot_scroll(root_vbox: VBoxContainer) -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(scroll)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	_slot_list = VBoxContainer.new()
	_slot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_list.add_theme_constant_override("separation", 8)
	margin.add_child(_slot_list)


## Builds and registers the new-game and delete confirmation popups.
func _build_popups() -> void:
	_new_game_popup = AcceptDialog.new()
	_new_game_popup.title = tr("새 게임")
	_new_game_popup.ok_button_text = tr("시작")
	_new_game_popup.confirmed.connect(_on_new_game_confirm)
	add_child(_new_game_popup)

	var popup_vbox: VBoxContainer = VBoxContainer.new()
	popup_vbox.add_theme_constant_override("separation", 8)
	_new_game_popup.add_child(popup_vbox)

	var name_hint: Label = Label.new()
	name_hint.text = tr("슬롯 이름")
	popup_vbox.add_child(name_hint)

	_name_input = LineEdit.new()
	_name_input.max_length = SLOT_NAME_MAX_LENGTH
	_name_input.custom_minimum_size.x = 280
	_name_input.text_changed.connect(_on_name_input_changed)
	_name_input.text_submitted.connect(func(_t: String) -> void:
		if not _name_input.text.strip_edges().is_empty():
			_new_game_popup.confirmed.emit()
	)
	popup_vbox.add_child(_name_input)

	_delete_popup = ConfirmationDialog.new()
	_delete_popup.ok_button_text = tr("삭제")
	_delete_popup.confirmed.connect(_on_delete_confirm)
	add_child(_delete_popup)


# ── Slot List ──

func _refresh_slots() -> void:
	for child: Node in _slot_list.get_children():
		child.queue_free()

	var slots: Array = SaveSystem.get_slot_list()

	if slots.is_empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.text = tr("저장된 게임이 없습니다. 새 게임을 시작하세요.")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 15)
		empty_lbl.add_theme_color_override("font_color", ThemeSetup.START_TEXT_EMPTY)
		_slot_list.add_child(empty_lbl)
		return

	for slot: Dictionary in slots:
		_slot_list.add_child(_build_slot_card(slot))


func _build_slot_card(slot: Dictionary) -> Control:
	var id: int = slot.get("id", -1)
	var is_valid: bool = SaveSystem.is_slot_valid(id)

	var card: PanelContainer = PanelContainer.new()
	var card_style: StyleBoxFlat = StyleBoxFlat.new()
	card_style.bg_color = ThemeSetup.START_CARD_BG
	card_style.border_color = ThemeSetup.START_CARD_BORDER
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(4)
	card.add_theme_stylebox_override("panel", card_style)

	if is_valid:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.mouse_entered.connect(func() -> void: AudioManager.play_sfx("sfx_slot_hover"))
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
				AudioManager.play_sfx("sfx_slot_select")
				slot_selected.emit(id)
		)

	var card_margin: MarginContainer = MarginContainer.new()
	card_margin.add_theme_constant_override("margin_left", 12)
	card_margin.add_theme_constant_override("margin_right", 8)
	card_margin.add_theme_constant_override("margin_top", 8)
	card_margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(card_margin)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card_margin.add_child(hbox)

	var info_vbox: VBoxContainer = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(info_vbox)

	if not is_valid:
		_build_slot_card_invalid(info_vbox, slot)
	else:
		_build_slot_card_valid(info_vbox, slot, id)

	var btn_del: Button = Button.new()
	btn_del.text = tr("삭제")
	btn_del.custom_minimum_size = Vector2(60, 0)
	btn_del.pressed.connect(func() -> void:
		_on_delete_pressed(id, slot.get("name", "?"))
	)
	ThemeSetup.apply_button_theme(btn_del)
	hbox.add_child(btn_del)

	return card


## Populates info_vbox with a corrupted-file warning label for an invalid slot.
func _build_slot_card_invalid(info_vbox: VBoxContainer, slot: Dictionary) -> void:
	var warn_lbl: Label = Label.new()
	warn_lbl.text = tr("⚠ 손상된 파일 — %s") % slot.get("name", "?")
	warn_lbl.add_theme_color_override("font_color", ThemeSetup.START_WARN)
	warn_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(warn_lbl)


## Populates info_vbox with the full slot details (name, stats, value, date) for a valid slot.
func _build_slot_card_valid(info_vbox: VBoxContainer, slot: Dictionary, id: int) -> void:
	# 슬롯 이름 (인라인 편집 가능)
	var name_str: String = slot.get("name", tr("슬롯 %d") % (id + 1))
	var name_lbl: Label = Label.new()
	name_lbl.text = name_str
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", ThemeSetup.START_TEXT_BRIGHT)
	name_lbl.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	name_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	name_lbl.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			_start_name_edit(name_lbl, id, name_str)
			get_viewport().set_input_as_handled()
	)
	info_vbox.add_child(name_lbl)

	# Lv · 시즌 · 날짜
	var level: int = slot.get("level", 1)
	var season: int = slot.get("season_number", 1)
	var week: int = slot.get("fiction_week", 0) + 1
	var day: int = slot.get("fiction_day", 0) + 1
	var stats_lbl: Label = Label.new()
	stats_lbl.text = tr("Lv.%d  ·  시즌 %d  ·  %d주차 %d일") % [level, season, week, day]
	stats_lbl.add_theme_font_size_override("font_size", 13)
	stats_lbl.add_theme_color_override("font_color", ThemeSetup.LAYOUT_EXIT_TEXT)
	stats_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(stats_lbl)

	# 평가금액
	var pf_val: int = slot.get("portfolio_value", 0)
	var pf_lbl: Label = Label.new()
	pf_lbl.text = tr("평가금액  ₩%s") % FormatUtils.number(pf_val)
	pf_lbl.add_theme_font_size_override("font_size", 15)
	pf_lbl.add_theme_color_override("font_color", ThemeSetup.START_PORTFOLIO_VALUE)
	pf_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(pf_lbl)

	# 저장 시각
	var saved_at: int = slot.get("saved_at", 0)
	var date_lbl: Label = Label.new()
	if saved_at > 0:
		var dt: Dictionary = Time.get_datetime_dict_from_unix_time(saved_at)
		date_lbl.text = tr("저장: %04d-%02d-%02d") % [dt["year"], dt["month"], dt["day"]]
	else:
		date_lbl.text = tr("저장: -")
	date_lbl.add_theme_font_size_override("font_size", 12)
	date_lbl.add_theme_color_override("font_color", ThemeSetup.START_TEXT_DIM)
	date_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(date_lbl)


# ── Slot Name Inline Edit ──

func _start_name_edit(name_lbl: Label, id: int, current_name: String) -> void:
	var edit: LineEdit = LineEdit.new()
	edit.text = current_name
	edit.max_length = SLOT_NAME_MAX_LENGTH
	edit.add_theme_font_size_override("font_size", 15)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var parent: Node = name_lbl.get_parent()
	var idx: int = name_lbl.get_index()
	name_lbl.hide()
	parent.add_child(edit)
	parent.move_child(edit, idx)
	edit.grab_focus()
	edit.select_all()

	var commit: Callable = func() -> void:
		var new_name: String = edit.text.strip_edges()
		if new_name.is_empty():
			new_name = current_name
		SaveSystem.rename_slot(id, new_name)
		name_lbl.text = new_name
		name_lbl.show()
		edit.queue_free()

	edit.focus_exited.connect(commit)
	edit.text_submitted.connect(func(_t: String) -> void: commit.call())


# ── New Game ──

func _on_new_game_pressed() -> void:
	var slots: Array = SaveSystem.get_slot_list()
	_name_input.text = tr("슬롯 %d") % (slots.size() + 1)
	_new_game_popup.get_ok_button().disabled = false
	_new_game_popup.popup_centered()
	_name_input.grab_focus()
	_name_input.select_all()


func _on_name_input_changed(new_text: String) -> void:
	_new_game_popup.get_ok_button().disabled = new_text.strip_edges().is_empty()


func _on_new_game_confirm() -> void:
	var name: String = _name_input.text.strip_edges()
	if name.is_empty():
		return
	var new_id: int = SaveSystem.create_slot(name)
	new_game_confirmed.emit(new_id)


# ── Delete ──

func _on_delete_pressed(id: int, slot_name: String) -> void:
	_delete_slot_id = id
	_delete_popup.dialog_text = tr("'%s' 슬롯을 삭제합니다.\n복구할 수 없습니다.") % slot_name
	_delete_popup.popup_centered()
	AudioManager.play_sfx("sfx_delete_confirm")


func _on_delete_confirm() -> void:
	if _delete_slot_id < 0:
		return
	SaveSystem.delete_slot(_delete_slot_id)
	_delete_slot_id = -1
	_refresh_slots()
