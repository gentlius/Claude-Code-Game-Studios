## SectorComparisonView — A4 섹터 비교 분석 뷰.
## 11개 섹터의 수익률 순위표 + 오늘/시즌 수익률 토글 + 드릴다운 패널.
## A4 미해금 시 잠금 상태 표시. P3 미해금 시 ETF 가격 컬럼 "—" 표시.
## EtfManager.get_etf_return / get_etf_open_price / get_etf_price 단일 소유 원칙 준수.
## See: design/gdd/sector-comparison.md
class_name SectorComparisonView
extends VBoxContainer

# ── Sort Mode ──

## Sort by season return (default) or today return.
enum SortMode { SEASON, TODAY }

# ── State ──

## Current sort mode. season = default per GDD §3-5.
var _sort_mode: SortMode = SortMode.SEASON

## Currently expanded sector (empty = no drilldown open).
var _drilldown_sector: String = ""

# ── UI nodes ──

var _locked_label: Label
var _main_panel: VBoxContainer
var _btn_sort_season: Button
var _btn_sort_today: Button
var _rows_container: VBoxContainer
var _drilldown_panel: VBoxContainer
var _lbl_drilldown_title: Label
var _drilldown_stocks_container: VBoxContainer

# ── Lifecycle ──

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	_build_ui()
	_refresh()

	PriceEngine.on_price_updated.connect(_on_tick)
	SkillTree.on_skill_unlocked.connect(_on_skill_unlocked)


# ── Public API ──

## Rebuild and redraw the sector ranking table.
## Called every tick (via on_price_updated) while the tab is visible,
## and immediately when the tab becomes visible.
func refresh() -> void:
	_refresh()


# ── Build ──

func _build_ui() -> void:
	# ── Locked overlay (shown when A4 not yet unlocked) ──
	_locked_label = Label.new()
	_locked_label.text = tr("🔒 A4 해금 필요 (성장 화면 → A3 선행)")
	_locked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_locked_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_locked_label.autowrap_mode        = TextServer.AUTOWRAP_WORD
	_locked_label.size_flags_vertical  = Control.SIZE_EXPAND_FILL
	_locked_label.add_theme_font_size_override("font_size", 11)
	ThemeSetup.style_label_dim(_locked_label)
	add_child(_locked_label)

	# ── Main panel (shown when A4 unlocked) ──
	_main_panel = VBoxContainer.new()
	_main_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_panel.add_theme_constant_override("separation", 2)
	add_child(_main_panel)

	_build_sort_bar(_main_panel)
	_build_header_row(_main_panel)
	_build_rows_area(_main_panel)
	_build_drilldown_panel(_main_panel)


func _build_sort_bar(parent: VBoxContainer) -> void:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	parent.add_child(bar)

	var lbl: Label = Label.new()
	lbl.text = tr("정렬:")
	lbl.add_theme_font_size_override("font_size", 10)
	ThemeSetup.style_label_dim(lbl)
	bar.add_child(lbl)

	_btn_sort_season = Button.new()
	_btn_sort_season.text = tr("시즌")
	_btn_sort_season.add_theme_font_size_override("font_size", 10)
	ThemeSetup.apply_tab_active(_btn_sort_season)
	_btn_sort_season.pressed.connect(func() -> void: _set_sort_mode(SortMode.SEASON))
	bar.add_child(_btn_sort_season)

	_btn_sort_today = Button.new()
	_btn_sort_today.text = tr("오늘")
	_btn_sort_today.add_theme_font_size_override("font_size", 10)
	ThemeSetup.apply_tab_inactive(_btn_sort_today)
	_btn_sort_today.pressed.connect(func() -> void: _set_sort_mode(SortMode.TODAY))
	bar.add_child(_btn_sort_today)


func _build_header_row(parent: VBoxContainer) -> void:
	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	parent.add_child(sep)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	parent.add_child(header)

	var col_specs: Array[Dictionary] = _get_col_specs()
	for spec: Dictionary in col_specs:
		var lbl: Label = Label.new()
		lbl.text = spec["header"]
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.size_flags_horizontal = spec["flags"]
		lbl.horizontal_alignment  = spec["align"]
		ThemeSetup.style_label_dim(lbl)
		header.add_child(lbl)

	var sep2: HSeparator = HSeparator.new()
	sep2.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	parent.add_child(sep2)


func _build_rows_area(parent: VBoxContainer) -> void:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical          = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode       = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode         = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_container.add_theme_constant_override("separation", 1)
	scroll.add_child(_rows_container)


func _build_drilldown_panel(parent: VBoxContainer) -> void:
	_drilldown_panel = VBoxContainer.new()
	_drilldown_panel.visible = false
	_drilldown_panel.add_theme_constant_override("separation", 2)
	parent.add_child(_drilldown_panel)

	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	_drilldown_panel.add_child(sep)

	var title_row: HBoxContainer = HBoxContainer.new()
	_drilldown_panel.add_child(title_row)

	_lbl_drilldown_title = Label.new()
	_lbl_drilldown_title.text = ""
	_lbl_drilldown_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_drilldown_title.add_theme_font_size_override("font_size", 11)
	ThemeSetup.style_label_primary(_lbl_drilldown_title)
	title_row.add_child(_lbl_drilldown_title)

	var btn_close: Button = Button.new()
	btn_close.text = tr("✕")
	btn_close.add_theme_font_size_override("font_size", 10)
	ThemeSetup.apply_tab_inactive(btn_close)
	btn_close.pressed.connect(_close_drilldown)
	title_row.add_child(btn_close)

	var drill_scroll: ScrollContainer = ScrollContainer.new()
	drill_scroll.custom_minimum_size.y = 60
	drill_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_drilldown_panel.add_child(drill_scroll)

	_drilldown_stocks_container = VBoxContainer.new()
	_drilldown_stocks_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drilldown_stocks_container.add_theme_constant_override("separation", 1)
	drill_scroll.add_child(_drilldown_stocks_container)


# ── Refresh ──

func _refresh() -> void:
	var a4_unlocked: bool = SkillTree.is_skill_unlocked("A4")
	_locked_label.visible = not a4_unlocked
	_main_panel.visible   = a4_unlocked
	if not a4_unlocked:
		return

	var etf_ids: Array[String] = EtfManager.get_all_etf_ids()
	if etf_ids.is_empty():
		return

	# Build data rows
	var rows: Array[Dictionary] = []
	var p3_unlocked: bool = SkillTree.is_skill_unlocked("P3")
	for etf_id: String in etf_ids:
		var sector: String = etf_id.trim_prefix("ETF_")
		var season_ret: float = EtfManager.get_etf_return(etf_id)
		var today_ret: float  = _calc_today_return(etf_id)
		var etf_price: float  = EtfManager.get_etf_price(etf_id)
		rows.append({
			"etf_id":     etf_id,
			"sector":     sector,
			"season_ret": season_ret,
			"today_ret":  today_ret,
			"etf_price":  etf_price,
			"p3_unlocked": p3_unlocked,
		})

	# Sort — GDD §3-5: primary by selected metric (desc), tiebreak by sector name asc
	var sort_key: String = "season_ret" if _sort_mode == SortMode.SEASON else "today_ret"
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a[sort_key]) - float(b[sort_key])) > 0.000001:
			return float(a[sort_key]) > float(b[sort_key])
		return str(a["sector"]) < str(b["sector"])
	)

	# Rebuild row widgets
	for child: Node in _rows_container.get_children():
		child.queue_free()

	for rank: int in rows.size():
		_add_sector_row(_rows_container, rank + 1, rows[rank])


func _calc_today_return(etf_id: String) -> float:
	var open_price: float = EtfManager.get_etf_open_price(etf_id)
	if open_price <= 0.0:
		return 0.0
	var cur_price: float = EtfManager.get_etf_price(etf_id)
	return cur_price / open_price - 1.0


# ── Row Building ──

func _add_sector_row(parent: VBoxContainer, rank: int, data: Dictionary) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(row)

	var season_ret: float = data["season_ret"]
	var today_ret:  float = data["today_ret"]
	var sector:     String = data["sector"]

	# Rank label
	var lbl_rank: Label = Label.new()
	lbl_rank.text = str(rank)
	lbl_rank.add_theme_font_size_override("font_size", 11)
	lbl_rank.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lbl_rank.custom_minimum_size.x = 18
	lbl_rank.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	ThemeSetup.style_label_dim(lbl_rank)
	row.add_child(lbl_rank)

	# Sector name + bar
	var name_vbox: VBoxContainer = VBoxContainer.new()
	name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_vbox.add_theme_constant_override("separation", 1)
	row.add_child(name_vbox)

	var lbl_name: Label = Label.new()
	lbl_name.text = sector
	lbl_name.add_theme_font_size_override("font_size", 11)
	ThemeSetup.style_label_primary(lbl_name)
	name_vbox.add_child(lbl_name)

	# Mini bar — tuning knob MAX_BAR_PCT ±20% (GDD §7)
	var bar_pct: float = clampf(season_ret / 0.20, -1.0, 1.0)
	_add_mini_bar(name_vbox, bar_pct)

	# Today return
	var lbl_today: Label = Label.new()
	lbl_today.text = _format_pct(today_ret)
	lbl_today.add_theme_font_size_override("font_size", 11)
	lbl_today.size_flags_horizontal = Control.SIZE_SHRINK_END
	lbl_today.custom_minimum_size.x = 44
	lbl_today.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	_color_return_label(lbl_today, today_ret)
	row.add_child(lbl_today)

	# Season return
	var lbl_season: Label = Label.new()
	lbl_season.text = _format_pct(season_ret)
	lbl_season.add_theme_font_size_override("font_size", 11)
	lbl_season.size_flags_horizontal = Control.SIZE_SHRINK_END
	lbl_season.custom_minimum_size.x = 44
	lbl_season.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	_color_return_label(lbl_season, season_ret)
	row.add_child(lbl_season)

	# ETF price (P3 gate — GDD §3-2 / Edge Case §5)
	var lbl_etf: Label = Label.new()
	lbl_etf.add_theme_font_size_override("font_size", 10)
	lbl_etf.size_flags_horizontal = Control.SIZE_SHRINK_END
	lbl_etf.custom_minimum_size.x = 48
	lbl_etf.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	if data["p3_unlocked"]:
		lbl_etf.text = _format_price(data["etf_price"])
		ThemeSetup.style_label_primary(lbl_etf)
	else:
		lbl_etf.text = "—"
		ThemeSetup.style_label_dim(lbl_etf)
	row.add_child(lbl_etf)

	# Click → drilldown
	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_toggle_drilldown(sector)
	)


func _add_mini_bar(parent: VBoxContainer, pct: float) -> void:
	## pct ∈ [-1, 1] — positive=blue fill right, negative=red fill left
	var bar_container: Control = Control.new()
	bar_container.custom_minimum_size = Vector2(0, 4)
	bar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(bar_container)

	if absf(pct) < 0.001:
		return

	var fill: Panel = Panel.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_corner_radius_all(2)
	if pct > 0.0:
		style.bg_color = ThemeSetup.PRICE_UP
		fill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
		fill.anchor_right  = pct
		fill.anchor_bottom = 1.0
	else:
		style.bg_color = ThemeSetup.PRICE_DOWN
		fill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		fill.anchor_left   = 1.0 + pct  # pct is negative
		fill.anchor_bottom = 1.0
	fill.add_theme_stylebox_override("panel", style)
	bar_container.add_child(fill)


# ── Drilldown ──

func _toggle_drilldown(sector: String) -> void:
	## Click same sector twice → close. GDD §3-2 drilldown.
	## Drilldown view is a click-time snapshot — not updated on tick (GDD §5 Edge Case).
	if _drilldown_sector == sector:
		_close_drilldown()
		return
	_drilldown_sector = sector
	_open_drilldown(sector)


func _open_drilldown(sector: String) -> void:
	_lbl_drilldown_title.text = tr("%s 구성 종목") % sector
	_drilldown_panel.visible = true

	for child: Node in _drilldown_stocks_container.get_children():
		child.queue_free()

	var stock_ids: Array[String] = EtfManager.get_sector_stocks(sector)
	var up_count: int   = 0
	var down_count: int = 0

	for stock_id: String in stock_ids:
		var stock: StockData = StockDatabase.get_stock(stock_id)
		if stock == null:
			continue
		var cur_price: int  = PriceEngine.get_current_price(stock_id)
		var base_price: int = stock.base_price
		var today_chg: float = 0.0
		if base_price > 0:
			today_chg = float(cur_price) / float(base_price) - 1.0
		if today_chg > 0.0:
			up_count += 1
		elif today_chg < 0.0:
			down_count += 1

		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_drilldown_stocks_container.add_child(row)

		var lbl_name: Label = Label.new()
		lbl_name.text = stock.get_display_name() if stock.has_method("get_display_name") else stock_id
		lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_name.add_theme_font_size_override("font_size", 10)
		ThemeSetup.style_label_primary(lbl_name)
		row.add_child(lbl_name)

		var lbl_chg: Label = Label.new()
		lbl_chg.text = _format_pct(today_chg)
		lbl_chg.add_theme_font_size_override("font_size", 10)
		lbl_chg.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_color_return_label(lbl_chg, today_chg)
		row.add_child(lbl_chg)

	# Summary line: 상승 N개 / 하락 M개 (GDD §3-2)
	var lbl_summary: Label = Label.new()
	lbl_summary.text = tr("상승 %d개 / 하락 %d개") % [up_count, down_count]
	lbl_summary.add_theme_font_size_override("font_size", 10)
	ThemeSetup.style_label_dim(lbl_summary)
	_drilldown_stocks_container.add_child(lbl_summary)


func _close_drilldown() -> void:
	_drilldown_sector = ""
	_drilldown_panel.visible = false


# ── Sort ──

func _set_sort_mode(mode: SortMode) -> void:
	_sort_mode = mode
	if mode == SortMode.SEASON:
		ThemeSetup.apply_tab_active(_btn_sort_season)
		ThemeSetup.apply_tab_inactive(_btn_sort_today)
	else:
		ThemeSetup.apply_tab_inactive(_btn_sort_season)
		ThemeSetup.apply_tab_active(_btn_sort_today)
	_refresh()


# ── Event Handlers ──

func _on_tick(_tick: int) -> void:
	if not visible:
		return
	_refresh()


func _on_skill_unlocked(skill_id: String) -> void:
	if skill_id in ["A4", "P3"]:
		_refresh()


# ── Format Helpers ──

## Formats a return fraction (0.05 → "+5.0%", -0.02 → "-2.0%")
func _format_pct(value: float) -> String:
	var sign: String = "+" if value >= 0.0 else ""
	return "%s%.1f%%" % [sign, value * 100.0]


## Formats an ETF price (won, float → "53,240원")
func _format_price(price: float) -> String:
	return "%s원" % FormatUtils.number(roundi(price))


## Colors a return label: positive=PRICE_UP, negative=PRICE_DOWN, zero=dim.
func _color_return_label(lbl: Label, value: float) -> void:
	if value > 0.0001:
		lbl.add_theme_color_override("font_color", ThemeSetup.PRICE_UP)
	elif value < -0.0001:
		lbl.add_theme_color_override("font_color", ThemeSetup.PRICE_DOWN)
	else:
		ThemeSetup.style_label_dim(lbl)


# ── Column Specs (used for header row) ──

func _get_col_specs() -> Array[Dictionary]:
	return [
		{"header": tr("#"),    "flags": Control.SIZE_SHRINK_BEGIN, "align": HORIZONTAL_ALIGNMENT_CENTER},
		{"header": tr("섹터"),  "flags": Control.SIZE_EXPAND_FILL,  "align": HORIZONTAL_ALIGNMENT_LEFT},
		{"header": tr("오늘"),  "flags": Control.SIZE_SHRINK_END,   "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"header": tr("시즌"),  "flags": Control.SIZE_SHRINK_END,   "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"header": tr("ETF"),  "flags": Control.SIZE_SHRINK_END,   "align": HORIZONTAL_ALIGNMENT_RIGHT},
	]
