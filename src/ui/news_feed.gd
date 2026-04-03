## News Feed UI — Displays news cards from NewsEventSystem.
## Hosted in TradingScreen's bottom panel area.
## See: design/gdd/news-feed-ui.md
extends VBoxContainer

# ── Signals ──

## Emitted when player clicks a stock name in a news card.
signal stock_clicked(stock_id: String)

# ── Constants ──

const MAX_VISIBLE_NEWS: int = 30
const SCOPE_COLORS: Dictionary = {
	"MACRO": ThemeSetup.PROFIT_RED,
	"SECTOR": Color(0.85, 0.55, 0.05),
	"INDIVIDUAL": ThemeSetup.LOSS_BLUE,
}
const SCOPE_LABELS: Dictionary = {
	"MACRO": "시장 전체",
	"SECTOR": "업종",
	"INDIVIDUAL": "개별",
}

# ── State ──

var _news_entries: Array[Dictionary] = []  ## All news cards
var _pre_market_entries: Array[Dictionary] = []
var _is_pre_market_mode: bool = false
var _unread_count: int = 0

# ── Node References ──

var _header_bar: HBoxContainer
var _lbl_title: Label
var _lbl_unread_badge: Label
var _scroll: ScrollContainer
var _card_container: VBoxContainer
var _pre_market_panel: VBoxContainer

# ── Lifecycle ──

func _ready() -> void:
	_build_ui()
	NewsEventSystem.on_news_display.connect(_on_news_display)
	NewsEventSystem.on_pre_market_news.connect(_on_pre_market_news)
	NewsEventSystem.on_theme_hint.connect(_on_theme_hint)
	GameClock.on_market_state_changed.connect(_on_market_state_changed)
	SkillTree.on_skill_unlocked.connect(func(_id: String) -> void: _update_title_with_skill())


func _build_ui() -> void:
	# Header
	_header_bar = HBoxContainer.new()
	_header_bar.add_theme_constant_override("separation", 8)
	add_child(_header_bar)

	_lbl_title = Label.new()
	_lbl_title.add_theme_font_size_override("font_size", 14)
	ThemeSetup.style_label_primary(_lbl_title)
	_header_bar.add_child(_lbl_title)

	# Skill feedback: show news speed status
	_update_title_with_skill()

	_lbl_unread_badge = Label.new()
	_lbl_unread_badge.text = ""
	_lbl_unread_badge.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	_header_bar.add_child(_lbl_unread_badge)

	# Pre-market panel (hidden by default)
	_pre_market_panel = VBoxContainer.new()
	_pre_market_panel.visible = false
	add_child(_pre_market_panel)

	# Scroll container for news cards
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)

	_card_container = VBoxContainer.new()
	_card_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_container.add_theme_constant_override("separation", 2)
	_scroll.add_child(_card_container)


# ── Signal Handlers ──

func _on_news_display(entry: Dictionary) -> void:
	# VI/CB system events go to alerts tab, not news feed
	if entry.get("is_system_event", false):
		return

	_news_entries.insert(0, entry)
	entry["is_read"] = false

	# Trim to max
	if _news_entries.size() > MAX_VISIBLE_NEWS:
		_news_entries.resize(MAX_VISIBLE_NEWS)

	_unread_count += 1
	_update_unread_badge()
	_add_news_card(entry, true)


func _on_pre_market_news(entries: Array[Dictionary]) -> void:
	_pre_market_entries = entries
	_is_pre_market_mode = true
	_show_pre_market_bundle()


func _on_theme_hint(hint_text: String) -> void:
	# Show theme hint as a special card
	var hint_entry: Dictionary = {
		"headline": hint_text,
		"body": "",
		"scope": "MACRO",
		"impact_tier": "SMALL",
		"impact_hint": "시즌 테마 힌트",
		"display_tick": GameClock.get_current_tick(),
		"is_read": false,
	}
	_news_entries.insert(0, hint_entry)
	_unread_count += 1
	_update_unread_badge()
	_add_news_card(hint_entry, true)


func _on_market_state_changed(
	new_state: GameClock.MarketState, _prev: GameClock.MarketState
) -> void:
	match new_state:
		GameClock.MarketState.PRE_MARKET:
			# Clear feed for new day
			_news_entries.clear()
			_unread_count = 0
			_clear_cards()
			_update_unread_badge()
		GameClock.MarketState.MARKET_OPEN:
			# Convert pre-market bundle to individual cards
			if _is_pre_market_mode:
				_is_pre_market_mode = false
				_pre_market_panel.visible = false
				for entry: Dictionary in _pre_market_entries:
					entry["is_read"] = false
					_news_entries.insert(0, entry)
					_unread_count += 1
				_pre_market_entries.clear()
				_rebuild_all_cards()
				_update_unread_badge()


# ── Pre-Market Bundle ──

func _show_pre_market_bundle() -> void:
	_pre_market_panel.visible = true

	# Clear previous
	for child: Node in _pre_market_panel.get_children():
		child.queue_free()

	var title: Label = Label.new()
	var day: int = GameClock.get_current_day() + 1
	title.text = "오늘의 시장 전망 (Day %d)" % day
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	ThemeSetup.style_label_primary(title)
	_pre_market_panel.add_child(title)

	var sep: HSeparator = HSeparator.new()
	_pre_market_panel.add_child(sep)

	if _pre_market_entries.size() == 0:
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "오늘은 특별한 시장 전망이 없습니다"
		ThemeSetup.style_label_dim(empty_lbl)
		_pre_market_panel.add_child(empty_lbl)
	else:
		for entry: Dictionary in _pre_market_entries:
			var item: Label = Label.new()
			item.text = "• %s" % entry.get("headline", "")
			item.autowrap_mode = TextServer.AUTOWRAP_WORD
			ThemeSetup.style_label_primary(item)
			_pre_market_panel.add_child(item)


# ── Card Management ──

func _add_news_card(entry: Dictionary, insert_top: bool) -> void:
	var card: PanelContainer = _create_card(entry)
	if insert_top:
		_card_container.add_child(card)
		_card_container.move_child(card, 0)
	else:
		_card_container.add_child(card)


func _create_card(entry: Dictionary) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()

	var is_read: bool = entry.get("is_read", false)
	if is_read:
		style.bg_color = ThemeSetup.BG_DARK
	else:
		style.bg_color = ThemeSetup.BG_CARD
	style.set_corner_radius_all(4)
	style.border_color = ThemeSetup.BORDER_DIM
	style.set_border_width_all(1)
	style.set_content_margin_all(6)
	card.add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# Row 1: [unread marker] [scope badge] [headline]
	var row1: HBoxContainer = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(row1)

	# Unread marker
	var marker: Label = Label.new()
	marker.text = "●" if not is_read else ""
	marker.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	marker.custom_minimum_size.x = 14
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row1.add_child(marker)

	# Scope badge
	var scope: String = str(entry.get("scope", "MACRO"))
	var badge: Label = Label.new()
	var scope_label: String = SCOPE_LABELS.get(scope, scope)
	# For SECTOR, include sector name if available
	var target_sector: Variant = entry.get("target_sector")
	if scope == "SECTOR" and target_sector != null and str(target_sector) != "" and str(target_sector) != "null":
		scope_label = str(target_sector)
	badge.text = "[%s]" % scope_label
	badge.add_theme_color_override("font_color", SCOPE_COLORS.get(scope, Color.WHITE))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row1.add_child(badge)

	# Headline
	var headline: Label = Label.new()
	headline.text = str(entry.get("headline", ""))
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ThemeSetup.style_label_primary(headline)
	row1.add_child(headline)

	# Row 2: [impact hint] | [timestamp]
	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(row2)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size.x = 14
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row2.add_child(spacer)

	var impact: Label = Label.new()
	impact.mouse_filter = Control.MOUSE_FILTER_IGNORE
	impact.text = str(entry.get("impact_hint", ""))
	var impact_tier: String = str(entry.get("impact_tier", "SMALL"))
	match impact_tier:
		"MEGA":
			impact.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
		"LARGE":
			impact.add_theme_color_override("font_color", Color(0.85, 0.55, 0.05))
		"MEDIUM":
			impact.add_theme_color_override("font_color", ThemeSetup.TEXT_SECONDARY)
		_:
			impact.add_theme_color_override("font_color", ThemeSetup.TEXT_DIM)
	row2.add_child(impact)

	var tick_lbl: Label = Label.new()
	tick_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if entry.get("is_pre_market", false):
		tick_lbl.text = "장전"
	else:
		var display_tick: int = int(entry.get("display_tick", 0))
		var period: String = _tick_to_period(display_tick)
		tick_lbl.text = "틱 %d (%s)" % [display_tick, period]
	ThemeSetup.style_label_dim(tick_lbl)
	row2.add_child(tick_lbl)

	# Body (expandable — NOT added to tree until clicked)
	var body_text: String = str(entry.get("body", ""))
	var body_margin: MarginContainer = null
	if not body_text.is_empty():
		var body_lbl: Label = Label.new()
		body_lbl.text = "▸ " + body_text
		body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		body_lbl.add_theme_font_size_override("font_size", 17)
		body_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeSetup.style_label_secondary(body_lbl)
		body_margin = MarginContainer.new()
		body_margin.add_theme_constant_override("margin_left", 20)
		body_margin.add_theme_constant_override("margin_top", 4)
		body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body_margin.add_child(body_lbl)

	# Affected stocks (expandable — NOT added to tree until clicked)
	var target_stocks: Variant = entry.get("target_stock_ids")
	var stocks_margin: MarginContainer = null
	if target_stocks is Array and (target_stocks as Array).size() > 0:
		var names: PackedStringArray = PackedStringArray()
		for sid: Variant in (target_stocks as Array):
			var stock: StockData = StockDatabase.get_stock(str(sid))
			if stock:
				names.append("%s(%s)" % [stock.name_ko, stock.stock_id])
			else:
				names.append(str(sid))
		var stocks_lbl: Label = Label.new()
		stocks_lbl.text = "관련 종목: %s" % ", ".join(names)
		stocks_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		stocks_lbl.add_theme_font_size_override("font_size", 15)
		stocks_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeSetup.style_label_dim(stocks_lbl)
		stocks_margin = MarginContainer.new()
		stocks_margin.add_theme_constant_override("margin_left", 20)
		stocks_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stocks_margin.add_child(stocks_lbl)

	# Click to mark as read + toggle body (add/remove from tree)
	var _body_ref: MarginContainer = body_margin
	var _stocks_ref: MarginContainer = stocks_margin
	var _vbox_ref: VBoxContainer = vbox
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_mark_read(entry, card, marker)
				_toggle_body(_vbox_ref, _body_ref, _stocks_ref)
	)

	return card


func _toggle_body(vbox: VBoxContainer, body_ctrl: MarginContainer, stocks_ctrl: MarginContainer) -> void:
	if body_ctrl == null and stocks_ctrl == null:
		return
	# Toggle: if body is in tree, remove it; otherwise add it
	var is_expanded: bool = body_ctrl != null and body_ctrl.get_parent() != null
	if is_expanded:
		# Collapse
		if body_ctrl and body_ctrl.get_parent():
			vbox.remove_child(body_ctrl)
		if stocks_ctrl and stocks_ctrl.get_parent():
			vbox.remove_child(stocks_ctrl)
	else:
		# Expand — add at end of vbox
		if body_ctrl:
			vbox.add_child(body_ctrl)
		if stocks_ctrl:
			vbox.add_child(stocks_ctrl)


func _mark_read(entry: Dictionary, card: PanelContainer, marker: Label) -> void:
	if entry.get("is_read", false):
		return
	entry["is_read"] = true
	marker.text = ""
	_unread_count = maxi(0, _unread_count - 1)
	_update_unread_badge()

	# Update card background
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = ThemeSetup.BG_PANEL
	style.set_corner_radius_all(8)
	style.border_color = ThemeSetup.BORDER_DIM
	style.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", style)

	# Check for stock link
	var target_stocks: Variant = entry.get("target_stock_ids")
	if target_stocks is Array and (target_stocks as Array).size() > 0:
		var first_stock: String = str((target_stocks as Array)[0])
		stock_clicked.emit(first_stock)


func _clear_cards() -> void:
	for child: Node in _card_container.get_children():
		child.queue_free()


func _rebuild_all_cards() -> void:
	_clear_cards()
	for entry: Dictionary in _news_entries:
		_add_news_card(entry, false)


func _update_unread_badge() -> void:
	if _unread_count > 0:
		_lbl_unread_badge.text = "(%d)" % _unread_count
	else:
		_lbl_unread_badge.text = ""


func _tick_to_period(tick: int) -> String:
	var third: int = GameClock.TICKS_PER_DAY / 3
	if tick < third:
		return "장 초반"
	elif tick < third * 2:
		return "장 중반"
	else:
		return "장 후반"


func _update_title_with_skill() -> void:
	if SkillTree.is_skill_unlocked("S2"):
		_lbl_title.text = "뉴스 피드 ⚡실시간"
		_lbl_title.add_theme_color_override("font_color", Color(0.20, 0.80, 0.40))
	elif SkillTree.is_skill_unlocked("S1"):
		_lbl_title.text = "뉴스 피드 ⏱빠른뉴스"
		_lbl_title.add_theme_color_override("font_color", Color(0.85, 0.70, 0.20))
	else:
		_lbl_title.text = "뉴스 피드"
