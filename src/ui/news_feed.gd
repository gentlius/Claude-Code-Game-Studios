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
	"MACRO": Color(0.9, 0.2, 0.2),
	"SECTOR": Color(0.9, 0.5, 0.1),
	"INDIVIDUAL": Color(0.2, 0.4, 0.9),
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


func _build_ui() -> void:
	# Header
	_header_bar = HBoxContainer.new()
	_header_bar.add_theme_constant_override("separation", 8)
	add_child(_header_bar)

	_lbl_title = Label.new()
	_lbl_title.text = "뉴스 피드"
	_header_bar.add_child(_lbl_title)

	_lbl_unread_badge = Label.new()
	_lbl_unread_badge.text = ""
	_lbl_unread_badge.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
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
	_pre_market_panel.add_child(title)

	var sep: HSeparator = HSeparator.new()
	_pre_market_panel.add_child(sep)

	if _pre_market_entries.size() == 0:
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "오늘은 특별한 시장 전망이 없습니다"
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_pre_market_panel.add_child(empty_lbl)
	else:
		for entry: Dictionary in _pre_market_entries:
			var item: Label = Label.new()
			item.text = "• %s" % entry.get("headline", "")
			item.autowrap_mode = TextServer.AUTOWRAP_WORD
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
		style.bg_color = Color(0.12, 0.12, 0.15)
	else:
		style.bg_color = Color(0.15, 0.15, 0.2)
	style.set_corner_radius_all(4)
	card.add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	# Row 1: [unread marker] [scope badge] [headline]
	var row1: HBoxContainer = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	vbox.add_child(row1)

	# Unread marker
	var marker: Label = Label.new()
	marker.text = "●" if not is_read else ""
	marker.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	marker.custom_minimum_size.x = 14
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
	row1.add_child(badge)

	# Headline
	var headline: Label = Label.new()
	headline.text = str(entry.get("headline", ""))
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row1.add_child(headline)

	# Row 2: [impact hint] | [timestamp]
	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	vbox.add_child(row2)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size.x = 14
	row2.add_child(spacer)

	var impact: Label = Label.new()
	impact.text = str(entry.get("impact_hint", ""))
	var impact_tier: String = str(entry.get("impact_tier", "SMALL"))
	match impact_tier:
		"MEGA":
			impact.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
		"LARGE":
			impact.add_theme_color_override("font_color", Color(0.9, 0.6, 0.1))
		"MEDIUM":
			impact.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_:
			impact.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	row2.add_child(impact)

	var tick_lbl: Label = Label.new()
	var display_tick: int = int(entry.get("display_tick", 0))
	var period: String = _tick_to_period(display_tick)
	tick_lbl.text = "틱 %d (%s)" % [display_tick, period]
	tick_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	row2.add_child(tick_lbl)

	# Click to mark as read
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_mark_read(entry, card, marker)
	)

	return card


func _mark_read(entry: Dictionary, card: PanelContainer, marker: Label) -> void:
	if entry.get("is_read", false):
		return
	entry["is_read"] = true
	marker.text = ""
	_unread_count = maxi(0, _unread_count - 1)
	_update_unread_badge()

	# Update card background
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15)
	style.set_corner_radius_all(4)
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
	if tick < 130:
		return "장 초반"
	elif tick < 260:
		return "장 중반"
	else:
		return "장 후반"
