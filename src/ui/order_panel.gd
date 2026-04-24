## OrderPanel — 매수/매도 주문 폼 + 미체결 주문 목록.
## 종목 선택 변경 시 TradingScreen이 set_stock() 호출.
## 시장 상태 변경 시 TradingScreen이 set_ui_state() 호출.
## See: design/gdd/trading-screen.md §10, §규칙 4
class_name OrderPanel
extends PanelContainer

var _selected_stock_id: String = ""
var _order_side: String = "BUY"
var _order_type: String = "MARKET"
var _error_tween: Tween

var _lbl_order_stock_name: Label
var _lbl_order_current_price: Label
var _btn_buy_tab: Button
var _btn_sell_tab: Button
var _radio_market: Button
var _radio_limit: Button
var _limit_price_row: HBoxContainer
var _spin_limit_price: SpinBox
var _spin_quantity: SpinBox
var _lbl_estimated_amount: Label
var _btn_submit_order: Button
var _lbl_order_error: Label
var _pending_orders_container: VBoxContainer

## Order book UI — 10 level rows (ask5..ask1, separator, bid1..bid5).
## GDD order-book.md §3-5 (블록 1~5).
var _order_book_rows: Array[HBoxContainer] = []  ## 10 entries: index 0=ask5 ... 4=ask1, 5=bid1 ... 9=bid5
## 블록 1: OHLCV 행
var _lbl_ob_open: Label
var _lbl_ob_high: Label
var _lbl_ob_low: Label
var _lbl_ob_volume: Label
## 블록 2: 매도 총잔량 / 블록 4: 매수 총잔량
var _lbl_ask_total: Label
var _lbl_bid_total: Label
## 블록 3: 현재가 구분행
var _lbl_ob_cur_price: Label
var _lbl_ob_cur_change: Label
## 블록 5: 체결강도
var _fill_strength_container: Control
var _fill_strength_fill: Panel
var _fill_strength_style: StyleBoxFlat = null
var _lbl_fill_pct: Label
var _lbl_fill_side: Label

var _pending_order_ids: Array[int] = []
## 블록 6: 52주 최고/최저 행. GDD order-book.md §3-5 블록6.
var _lbl_week52_high: Label
var _lbl_week52_low: Label

## 호가창 섹션. GDD order-book.md §3-5.
## TR1 미해금 시 트리에서 제거. on_skill_unlocked("TR1") → add_child로 삽입.
var _order_book_section: VBoxContainer
var _vbox: VBoxContainer

## S/T 자동 조건 섹션. GDD stop-loss-take-profit.md.
## TR2 해금 + 보유 종목 선택 시에만 표시.
var _st_section: VBoxContainer
var _spin_stop_loss: SpinBox
var _spin_take_profit: SpinBox
var _spin_st_qty: SpinBox
var _lbl_st_error: Label

## 분석 탭 컨테이너 — A3 / A4 탭 전환. GDD sector-comparison.md §3-1.
## A3 해금 시 탭 바 표시. A4 해금 시 A4 탭 버튼 추가.
var _analysis_tab_bar: HBoxContainer
var _btn_analysis_a3: Button
var _btn_analysis_a4: Button

## A3 재무제표 섹션. GDD financial-statements.md §3.
## A3 미해금 시 숨김. on_skill_unlocked("A3") → 즉시 표시.
var _a3_section: VBoxContainer
var _lbl_per: Label
var _lbl_pbr: Label
var _lbl_roe: Label
var _lbl_dividend: Label

## A4 섹터 비교 뷰. GDD sector-comparison.md.
## A4 해금 시 탭 버튼 표시 + 뷰 활성화.
var _a4_view: SectorComparisonView


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_stretch_ratio = 0.13
	custom_minimum_size.x = 160
	add_theme_stylebox_override("panel", ThemeSetup.make_panel_style(ThemeSetup.BG_DARK))
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	add_child(_vbox)
	_build_header(_vbox)
	_build_order_book_section(_vbox)  # visible=false if TR1 not unlocked
	_build_analysis_section(_vbox)
	_build_side_tabs(_vbox)
	_build_type_row(_vbox)
	_build_qty_row(_vbox)
	_build_submit_area(_vbox)
	_build_st_section(_vbox)
	_build_pending_section(_vbox)
	_set_order_side("BUY")
	_set_order_type("MARKET")
	OrderEngine.on_order_filled.connect(_on_order_filled)
	OrderEngine.on_order_rejected.connect(_on_order_rejected)
	OrderEngine.on_order_cancelled.connect(func(_o: Dictionary) -> void: _update_pending_orders())
	OrderEngine.on_order_expired.connect(func(_o: Dictionary) -> void: _update_pending_orders())
	CurrencySystem.sim_cash_changed.connect(func(_a: int, _d: int) -> void: _update_order_panel_price())
	PriceEngine.on_price_updated.connect(_on_tick)
	PortfolioManager.holding_added.connect(func(_sid: String, _qty: int, _price: int) -> void: _refresh_st_section())
	PortfolioManager.holding_removed.connect(func(_sid: String, _qty: int, _price: int, _pnl: int) -> void: _refresh_st_section())


func _build_header(vbox: VBoxContainer) -> void:
	_lbl_order_stock_name = Label.new()
	_lbl_order_stock_name.text = tr("종목 선택")
	_lbl_order_stock_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_order_stock_name.add_theme_font_size_override("font_size", 15)
	ThemeSetup.style_label_primary(_lbl_order_stock_name)
	vbox.add_child(_lbl_order_stock_name)
	_lbl_order_current_price = Label.new()
	_lbl_order_current_price.text = tr("현재가 ₩0")
	_lbl_order_current_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_order_current_price.add_theme_font_size_override("font_size", 16)
	ThemeSetup.style_label_primary(_lbl_order_current_price)
	vbox.add_child(_lbl_order_current_price)
	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	vbox.add_child(sep)


## Builds the full order book panel: OHLCV + 10-level book + totals + fill strength.
## GDD order-book.md §3-5 (블록 1~5).
## TR1 미해금 시 visible=false. _on_skill_unlocked("TR1") → visible=true.
func _build_order_book_section(vbox: VBoxContainer) -> void:
	_order_book_section = VBoxContainer.new()
	_order_book_section.add_theme_constant_override("separation", 2)
	_order_book_section.visible = SkillTree.is_skill_unlocked("TR1")
	vbox.add_child(_order_book_section)

	var ob_title: Label = Label.new()
	ob_title.text = tr("호가창")
	ob_title.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_secondary(ob_title)
	_order_book_section.add_child(ob_title)

	_build_ob_ohlcv_block()
	_build_ob_price_rows()
	_build_ob_fill_strength_block()

	var sep_end: HSeparator = HSeparator.new()
	sep_end.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	_order_book_section.add_child(sep_end)


## 블록 1: OHLCV 행 + 거래량 행. GDD §3-5 블록1.
func _build_ob_ohlcv_block() -> void:
	var ohlcv_vbox: VBoxContainer = VBoxContainer.new()
	ohlcv_vbox.add_theme_constant_override("separation", 1)
	_order_book_section.add_child(ohlcv_vbox)

	var ohlcv_row: HBoxContainer = HBoxContainer.new()
	ohlcv_row.add_theme_constant_override("separation", 4)
	ohlcv_vbox.add_child(ohlcv_row)
	_lbl_ob_open  = _make_ohlcv_label(ohlcv_row, tr("시"))
	_lbl_ob_high  = _make_ohlcv_label(ohlcv_row, tr("고"))
	_lbl_ob_low   = _make_ohlcv_label(ohlcv_row, tr("저"))

	var vol_row: HBoxContainer = HBoxContainer.new()
	ohlcv_vbox.add_child(vol_row)
	var vol_key: Label = Label.new()
	vol_key.text = tr("거래량")
	vol_key.add_theme_font_size_override("font_size", 11)
	ThemeSetup.style_label_secondary(vol_key)
	vol_row.add_child(vol_key)
	_lbl_ob_volume = Label.new()
	_lbl_ob_volume.text = "0"
	_lbl_ob_volume.add_theme_font_size_override("font_size", 11)
	_lbl_ob_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_ob_volume.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ThemeSetup.style_label_primary(_lbl_ob_volume)
	vol_row.add_child(_lbl_ob_volume)

	var sep0: HSeparator = HSeparator.new()
	sep0.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	_order_book_section.add_child(sep0)


## 블록 2~4: 매도 총잔량 → ask5~ask1 rows → 현재가 구분행 → bid1~bid5 rows → 매수 총잔량.
## GDD §3-5 블록2~4.
func _build_ob_price_rows() -> void:
	_lbl_ask_total = _make_total_label(_order_book_section, true)

	_order_book_rows.clear()
	for display_rank: int in range(5):
		var row: HBoxContainer = _make_order_book_row(true, display_rank)
		_order_book_section.add_child(row)
		_order_book_rows.append(row)

	# 현재가 구분 행
	var cur_row: HBoxContainer = HBoxContainer.new()
	cur_row.add_theme_constant_override("separation", 4)
	cur_row.custom_minimum_size.y = 20
	var cur_style: StyleBoxFlat = StyleBoxFlat.new()
	cur_style.bg_color = Color(0.18, 0.22, 0.28)
	cur_row.add_theme_stylebox_override("panel", cur_style)
	_order_book_section.add_child(cur_row)
	_lbl_ob_cur_price = Label.new()
	_lbl_ob_cur_price.text = "₩0"
	_lbl_ob_cur_price.add_theme_font_size_override("font_size", 13)
	_lbl_ob_cur_price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_ob_cur_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ThemeSetup.style_label_primary(_lbl_ob_cur_price)
	cur_row.add_child(_lbl_ob_cur_price)
	_lbl_ob_cur_change = Label.new()
	_lbl_ob_cur_change.text = ""
	_lbl_ob_cur_change.add_theme_font_size_override("font_size", 11)
	_lbl_ob_cur_change.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ThemeSetup.style_label_secondary(_lbl_ob_cur_change)
	cur_row.add_child(_lbl_ob_cur_change)

	for display_rank: int in range(5):
		var row: HBoxContainer = _make_order_book_row(false, display_rank)
		_order_book_section.add_child(row)
		_order_book_rows.append(row)

	_lbl_bid_total = _make_total_label(_order_book_section, false)


## 블록 5: 체결강도 행 레이아웃 (키 레이블 + 바 컨테이너 + pct + side 레이블).
## GDD §3-5 블록5. 바 내부 위젯은 _build_ob_fill_strength_bar()에서 생성.
func _build_ob_fill_strength_block() -> void:
	var fs_row: HBoxContainer = HBoxContainer.new()
	fs_row.add_theme_constant_override("separation", 3)
	_order_book_section.add_child(fs_row)

	var fs_key: Label = Label.new()
	fs_key.text = tr("체결강도")
	fs_key.add_theme_font_size_override("font_size", 11)
	ThemeSetup.style_label_secondary(fs_key)
	fs_row.add_child(fs_key)

	_fill_strength_container = Control.new()
	_fill_strength_container.custom_minimum_size = Vector2(0, 12)
	_fill_strength_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fs_row.add_child(_fill_strength_container)
	_build_ob_fill_strength_bar()

	_lbl_fill_pct = Label.new()
	_lbl_fill_pct.text = "-"
	_lbl_fill_pct.add_theme_font_size_override("font_size", 11)
	_lbl_fill_pct.custom_minimum_size.x = 42
	_lbl_fill_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ThemeSetup.style_label_primary(_lbl_fill_pct)
	fs_row.add_child(_lbl_fill_pct)

	_lbl_fill_side = Label.new()
	_lbl_fill_side.text = ""
	_lbl_fill_side.add_theme_font_size_override("font_size", 11)
	_lbl_fill_side.custom_minimum_size.x = 40
	ThemeSetup.style_label_secondary(_lbl_fill_side)
	fs_row.add_child(_lbl_fill_side)
	_build_ob_week52_block()


## 블록 6: 52주 최고/최저 행. GDD order-book.md §3-5 블록6.
## PriceEngine.get_week52_high/low()로 ohlcv_daily 전체 스캔 + 오늘 장중값 포함.
func _build_ob_week52_block() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	_order_book_section.add_child(row)

	var high_key: Label = Label.new()
	high_key.text = tr("52최고")
	high_key.add_theme_font_size_override("font_size", 10)
	ThemeSetup.style_label_secondary(high_key)
	row.add_child(high_key)

	_lbl_week52_high = Label.new()
	_lbl_week52_high.text = "-"
	_lbl_week52_high.add_theme_font_size_override("font_size", 10)
	_lbl_week52_high.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_week52_high.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lbl_week52_high.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	row.add_child(_lbl_week52_high)

	var sep_v: VSeparator = VSeparator.new()
	sep_v.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	row.add_child(sep_v)

	var low_key: Label = Label.new()
	low_key.text = tr("52최저")
	low_key.add_theme_font_size_override("font_size", 10)
	ThemeSetup.style_label_secondary(low_key)
	row.add_child(low_key)

	_lbl_week52_low = Label.new()
	_lbl_week52_low.text = "-"
	_lbl_week52_low.add_theme_font_size_override("font_size", 10)
	_lbl_week52_low.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_week52_low.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lbl_week52_low.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)
	row.add_child(_lbl_week52_low)


## 체결강도 바 내부: 회색 배경 Panel + 채움 Panel. _fill_strength_container에 추가.
func _build_ob_fill_strength_bar() -> void:
	var fs_bg: Panel = Panel.new()
	fs_bg.anchor_right = 1.0
	fs_bg.anchor_bottom = 1.0
	var fs_bg_style: StyleBoxFlat = StyleBoxFlat.new()
	fs_bg_style.bg_color = Color(0.15, 0.15, 0.15)
	fs_bg.add_theme_stylebox_override("panel", fs_bg_style)
	_fill_strength_container.add_child(fs_bg)

	_fill_strength_fill = Panel.new()
	_fill_strength_fill.anchor_top = 0.0
	_fill_strength_fill.anchor_bottom = 1.0
	_fill_strength_fill.anchor_left = 0.0
	_fill_strength_fill.anchor_right = 0.5  # 100% = 50% bar width
	_fill_strength_fill.offset_left = 0
	_fill_strength_fill.offset_right = 0
	_fill_strength_style = StyleBoxFlat.new()
	_fill_strength_style.bg_color = ThemeSetup.LOSS_BLUE.darkened(0.3)
	_fill_strength_fill.add_theme_stylebox_override("panel", _fill_strength_style)
	_fill_strength_container.add_child(_fill_strength_fill)


func _make_ohlcv_label(parent: HBoxContainer, key: String) -> Label:
	var key_lbl: Label = Label.new()
	key_lbl.text = key
	key_lbl.add_theme_font_size_override("font_size", 11)
	ThemeSetup.style_label_secondary(key_lbl)
	parent.add_child(key_lbl)
	var val_lbl: Label = Label.new()
	val_lbl.text = "-"
	val_lbl.add_theme_font_size_override("font_size", 11)
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ThemeSetup.style_label_primary(val_lbl)
	parent.add_child(val_lbl)
	return val_lbl


func _make_total_label(parent: VBoxContainer, ask_side: bool) -> Label:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	var key: Label = Label.new()
	key.text = tr("매도잔량") if ask_side else tr("매수잔량")
	key.add_theme_font_size_override("font_size", 11)
	ThemeSetup.style_label_secondary(key)
	row.add_child(key)
	var val: Label = Label.new()
	val.text = "-"
	val.add_theme_font_size_override("font_size", 11)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if ask_side:
		val.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	else:
		val.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)
	row.add_child(val)
	return val


## Creates a single order book row with GDD §3-5 column layout.
## ask (매도): [bar_container EXPAND] [qty 38px] [price 50px RED]
## bid (매수): [price 50px BLUE] [qty 38px] [bar_container EXPAND]
## Bar fill uses anchor-based sizing inside bar_container (plain Control).
func _make_order_book_row(ask_side: bool, display_rank: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.custom_minimum_size.y = 20

	# Bar fill color
	var fill_color: Color = Color(0.85, 0.32, 0.32, 0.55) if ask_side \
		else Color(0.32, 0.52, 0.85, 0.55)

	# Shared label factories
	var lbl_price: Label = Label.new()
	lbl_price.text = "-"
	lbl_price.add_theme_font_size_override("font_size", 13)
	lbl_price.custom_minimum_size.x = 56
	lbl_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_price.add_theme_color_override("font_color",
		ThemeSetup.PROFIT_RED if ask_side else ThemeSetup.LOSS_BLUE)

	var lbl_qty: Label = Label.new()
	lbl_qty.text = "-"
	lbl_qty.add_theme_font_size_override("font_size", 13)
	lbl_qty.custom_minimum_size.x = 42
	lbl_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ThemeSetup.style_label_primary(lbl_qty)

	# Bar container: plain Control (not a Container) so children use anchors
	var bar_container: Control = Control.new()
	bar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_container.custom_minimum_size.y = 14

	var bar_fill: Panel = Panel.new()
	bar_fill.anchor_top    = 0.1
	bar_fill.anchor_bottom = 0.9
	# ask: fills right→left (anchor_right=1.0, anchor_left shrinks from 1.0 to 0.0)
	# bid: fills left→right (anchor_left=0.0, anchor_right grows from 0.0 to 1.0)
	bar_fill.anchor_left  = 1.0 if ask_side else 0.0
	bar_fill.anchor_right = 1.0 if ask_side else 0.0
	bar_fill.offset_left  = 0
	bar_fill.offset_right = 0
	var bar_style: StyleBoxFlat = StyleBoxFlat.new()
	bar_style.bg_color = fill_color
	bar_fill.add_theme_stylebox_override("panel", bar_style)
	bar_container.add_child(bar_fill)

	# Column order differs by side (GDD §3-5)
	if ask_side:
		row.add_child(bar_container)
		row.add_child(lbl_qty)
		row.add_child(lbl_price)
	else:
		row.add_child(lbl_price)
		row.add_child(lbl_qty)
		row.add_child(bar_container)

	# Click handler
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var captured_ask: bool = ask_side
	row.gui_input.connect(func(event: InputEvent) -> void:
		if not event is InputEventMouseButton:
			return
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_order_book_row_clicked_price(lbl_price.text, captured_ask)
	)

	row.set_meta("lbl_price",    lbl_price)
	row.set_meta("lbl_qty",      lbl_qty)
	row.set_meta("bar_fill",     bar_fill)
	row.set_meta("ask_side",     ask_side)
	row.set_meta("display_rank", display_rank)
	return row


## Handles a click on an order book row — uses the row's last-displayed price.
## GDD order-book.md §3-5 클릭 인터랙션.
func _on_order_book_row_clicked_price(price_text: String, ask_side: bool) -> void:
	if not SkillTree.is_skill_unlocked("TR1"):
		return
	# FormatUtils.number() uses comma separators — strip them to parse
	var clean: String = price_text.replace(",", "").strip_edges()
	if not clean.is_valid_int():
		return
	var price: int = clean.to_int()
	if price <= 0:
		return
	# Route to focused S/T field if applicable
	if _spin_stop_loss != null and _spin_stop_loss.get_line_edit().has_focus():
		_spin_stop_loss.value = float(price)
		return
	if _spin_take_profit != null and _spin_take_profit.get_line_edit().has_focus():
		_spin_take_profit.value = float(price)
		return
	# ask click → fill limit buy; bid click → fill limit sell
	if ask_side:
		_set_order_side("BUY")
	else:
		_set_order_side("SELL")
	_set_order_type("LIMIT")
	_spin_limit_price.value = float(price)
	_update_estimated_amount()


## Builds analysis section: tab bar (재무 A3 / 섹터 A4) + A3 panel + A4 panel.
## GDD sector-comparison.md §3-1 — A4 탭 추가. financial-statements.md §3 — A3 유지.
## Tab bar visible only when A3 is unlocked. A4 tab button hidden until A4 unlocked.
func _build_analysis_section(vbox: VBoxContainer) -> void:
	var a3_unlocked: bool = SkillTree.is_skill_unlocked("A3")
	var a4_unlocked: bool = SkillTree.is_skill_unlocked("A4")

	# ── Tab bar ──
	_analysis_tab_bar = HBoxContainer.new()
	_analysis_tab_bar.add_theme_constant_override("separation", 2)
	_analysis_tab_bar.visible = a3_unlocked
	vbox.add_child(_analysis_tab_bar)

	_btn_analysis_a3 = Button.new()
	_btn_analysis_a3.text = tr("재무")
	_btn_analysis_a3.add_theme_font_size_override("font_size", 10)
	ThemeSetup.apply_tab_active(_btn_analysis_a3)
	_btn_analysis_a3.pressed.connect(_switch_analysis_tab.bind("A3"))
	_analysis_tab_bar.add_child(_btn_analysis_a3)

	_btn_analysis_a4 = Button.new()
	_btn_analysis_a4.text = tr("섹터")
	_btn_analysis_a4.add_theme_font_size_override("font_size", 10)
	ThemeSetup.apply_tab_inactive(_btn_analysis_a4)
	_btn_analysis_a4.visible = a4_unlocked
	_btn_analysis_a4.pressed.connect(_switch_analysis_tab.bind("A4"))
	_analysis_tab_bar.add_child(_btn_analysis_a4)

	# ── A3 panel ──
	_a3_section = VBoxContainer.new()
	_a3_section.add_theme_constant_override("separation", 2)
	_a3_section.visible = a3_unlocked
	vbox.add_child(_a3_section)

	var title: Label = Label.new()
	title.text = tr("── 재무 지표 (A3) ──")
	title.add_theme_font_size_override("font_size", 11)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ThemeSetup.style_label_secondary(title)
	_a3_section.add_child(title)

	var row1: HBoxContainer = HBoxContainer.new()
	_a3_section.add_child(row1)
	_lbl_per = _make_financial_label(row1, tr("PER"))
	_lbl_pbr = _make_financial_label(row1, tr("PBR"))
	var row2: HBoxContainer = HBoxContainer.new()
	_a3_section.add_child(row2)
	_lbl_roe = _make_financial_label(row2, tr("ROE"))
	_lbl_dividend = _make_financial_label(row2, tr("배당"))

	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	_a3_section.add_child(sep)

	# ── A4 panel ──
	_a4_view = SectorComparisonView.new()
	_a4_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_a4_view.visible = false  # hidden until A4 tab is selected
	vbox.add_child(_a4_view)


## Switches the active analysis tab between "A3" (재무) and "A4" (섹터).
## A4 tab is only reachable after A4 is unlocked.
func _switch_analysis_tab(tab: String) -> void:
	var show_a3: bool = (tab == "A3")
	_a3_section.visible = show_a3
	_a4_view.visible    = not show_a3
	if show_a3:
		ThemeSetup.apply_tab_active(_btn_analysis_a3)
		ThemeSetup.apply_tab_inactive(_btn_analysis_a4)
		_refresh_a3_section()
	else:
		ThemeSetup.apply_tab_inactive(_btn_analysis_a3)
		ThemeSetup.apply_tab_active(_btn_analysis_a4)
		_a4_view.refresh()


func _make_financial_label(parent: HBoxContainer, key_text: String) -> Label:
	var key: Label = Label.new()
	key.text = key_text
	key.add_theme_font_size_override("font_size", 11)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ThemeSetup.style_label_secondary(key)
	parent.add_child(key)
	var val: Label = Label.new()
	val.text = "N/A"
	val.add_theme_font_size_override("font_size", 11)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ThemeSetup.style_label_primary(val)
	parent.add_child(val)
	return val


## Refreshes A3 재무 지표 labels for the currently selected stock.
func _refresh_a3_section() -> void:
	if not _a3_section.visible or _selected_stock_id == "":
		return
	_lbl_per.text     = PriceEngine.get_per_display(_selected_stock_id)
	_lbl_pbr.text     = PriceEngine.get_pbr_display(_selected_stock_id)
	_lbl_roe.text     = PriceEngine.get_roe_display(_selected_stock_id)
	_lbl_dividend.text = PriceEngine.get_dividend_display(_selected_stock_id)


## Called every tick via PriceEngine.on_price_updated.
## GDD order-book.md §3-5, §9 UI 갱신.
func _on_tick(_tick: int) -> void:
	if not is_visible_in_tree():
		return
	_update_order_panel_price()
	_refresh_order_book()
	_refresh_ohlcv()
	_refresh_week52()
	_refresh_a3_section()


## Redraws all 10 order book rows + totals + fill strength. GDD §3-5 블록 2~5.
func _refresh_order_book() -> void:
	if _order_book_section == null or not _order_book_section.visible:
		return
	if _selected_stock_id == "" or _order_book_rows.size() < 10:
		return
	var book: Dictionary = PriceEngine.get_order_book(_selected_stock_id)
	var ask_levels: Array = book.get("ask", [])
	var bid_levels: Array = book.get("bid", [])

	# Max qty across all 10 levels for bar normalization
	var max_qty: int = 1
	for lvl: Dictionary in ask_levels:
		max_qty = maxi(max_qty, lvl.get("qty", 0))
	for lvl: Dictionary in bid_levels:
		max_qty = maxi(max_qty, lvl.get("qty", 0))

	# ask rows: display order ask5(top)→ask1(bottom) = array index 4→0
	for display_rank: int in range(5):
		_update_row(_order_book_rows[display_rank], ask_levels, 4 - display_rank, max_qty)

	# bid rows: display order bid1(top)→bid5(bottom) = array index 0→4
	for display_rank: int in range(5):
		_update_row(_order_book_rows[5 + display_rank], bid_levels, display_rank, max_qty)

	# 현재가 구분행 갱신
	if _lbl_ob_cur_price != null and _selected_stock_id != "":
		var cur: int = PriceEngine.get_current_price(_selected_stock_id)
		var limits: Dictionary = PriceEngine.get_daily_limits(_selected_stock_id)
		var prev: int = limits.get("prev_close", cur)
		_lbl_ob_cur_price.text = FormatUtils.number(cur)
		var diff: int = cur - prev
		var pct: float = float(diff) / float(prev) * 100.0 if prev > 0 else 0.0
		var sign: String = "+" if diff >= 0 else ""
		_lbl_ob_cur_change.text = "%s%s(%.1f%%)" % [sign, FormatUtils.number(diff), pct]
		var chg_color: Color = ThemeSetup.PROFIT_RED if diff >= 0 else ThemeSetup.LOSS_BLUE
		_lbl_ob_cur_change.add_theme_color_override("font_color", chg_color)

	# 블록 2/4: 총잔량 합계
	var ask_total: int = 0
	var bid_total: int = 0
	for lvl: Dictionary in ask_levels:
		ask_total += lvl.get("qty", 0)
	for lvl: Dictionary in bid_levels:
		bid_total += lvl.get("qty", 0)
	if _lbl_ask_total != null:
		_lbl_ask_total.text = FormatUtils.number(ask_total)
	if _lbl_bid_total != null:
		_lbl_bid_total.text = FormatUtils.number(bid_total)

	# 블록 5: 체결강도
	_refresh_fill_strength(ask_total, bid_total)


## Updates a single order book row. ask bar fills right→left; bid bar fills left→right.
## GDD §3-5: anchor_left/right on bar_fill drives visual width proportionally.
func _update_row(row: HBoxContainer, levels: Array, idx: int, max_qty: int) -> void:
	var lbl_price: Label = row.get_meta("lbl_price") as Label
	var lbl_qty:   Label = row.get_meta("lbl_qty")   as Label
	var bar_fill:  Panel = row.get_meta("bar_fill")  as Panel
	var ask_side:  bool  = row.get_meta("ask_side")

	if idx < 0 or idx >= levels.size():
		lbl_price.text    = "-"
		lbl_qty.text      = "-"
		# collapse bar
		if ask_side:
			bar_fill.anchor_left = 1.0; bar_fill.anchor_right = 1.0
		else:
			bar_fill.anchor_left = 0.0; bar_fill.anchor_right = 0.0
		return

	var lvl:   Dictionary = levels[idx]
	var price: int        = lvl.get("price", 0)
	var qty:   int        = lvl.get("qty",   0)
	lbl_price.text = FormatUtils.number(price)
	lbl_qty.text   = FormatUtils.number(qty)

	var ratio: float = float(qty) / float(max_qty) if max_qty > 0 else 0.0
	if ask_side:
		# 오른쪽 정렬: anchor_right=1.0 고정, anchor_left = 1.0 - ratio
		bar_fill.anchor_left  = 1.0 - ratio
		bar_fill.anchor_right = 1.0
	else:
		# 왼쪽 정렬: anchor_left=0.0 고정, anchor_right = ratio
		bar_fill.anchor_left  = 0.0
		bar_fill.anchor_right = ratio
	bar_fill.offset_left  = 0
	bar_fill.offset_right = 0


## 블록 1: 시/고/저/거래량 레이블 갱신. GDD §3-5 블록1.
func _refresh_ohlcv() -> void:
	if _selected_stock_id == "" or _lbl_ob_open == null:
		return
	var ohlcv: Dictionary = PriceEngine.get_today_ohlcv(_selected_stock_id)
	_lbl_ob_open.text   = FormatUtils.number(ohlcv.get("open",   0))
	_lbl_ob_high.text   = FormatUtils.number(ohlcv.get("high",   0))
	_lbl_ob_low.text    = FormatUtils.number(ohlcv.get("low",    0))
	_lbl_ob_volume.text = FormatUtils.number(ohlcv.get("volume", 0))
	var cur: int = PriceEngine.get_current_price(_selected_stock_id)
	_lbl_ob_high.add_theme_color_override("font_color",
		ThemeSetup.PROFIT_RED if ohlcv.get("high", 0) >= cur else ThemeSetup.TEXT_PRIMARY)
	_lbl_ob_low.add_theme_color_override("font_color",
		ThemeSetup.LOSS_BLUE if ohlcv.get("low", 0) <= cur else ThemeSetup.TEXT_PRIMARY)


## 블록 6: 52주 최고/최저 레이블 갱신. GDD order-book.md §3-5 블록6.
## PriceEngine.get_week52_high/low()는 ohlcv_daily 전체 + 오늘 장중값을 포함한다.
func _refresh_week52() -> void:
	if _lbl_week52_high == null or _lbl_week52_low == null:
		return
	if _selected_stock_id == "":
		_lbl_week52_high.text = "-"
		_lbl_week52_low.text  = "-"
		return
	var high: int = PriceEngine.get_week52_high(_selected_stock_id)
	var low: int  = PriceEngine.get_week52_low(_selected_stock_id)
	_lbl_week52_high.text = FormatUtils.number(high) if high > 0 else "-"
	_lbl_week52_low.text  = FormatUtils.number(low)  if low  > 0 else "-"


## 블록 5: 체결강도 바 + 퍼센트 갱신. GDD §3-5 블록5.
## 체결강도 = (매수총잔량 / 매도총잔량) × 100. >100%=매수우위, <100%=매도우위.
func _refresh_fill_strength(ask_total: int, bid_total: int) -> void:
	if _fill_strength_fill == null:
		return
	if ask_total <= 0:
		_lbl_fill_pct.text  = "-"
		_lbl_fill_side.text = ""
		_fill_strength_fill.anchor_right = 0.0
		return
	var strength: float = float(bid_total) / float(ask_total) * 100.0
	_lbl_fill_pct.text = "%.1f%%" % strength

	# 바: 100% = anchor_right 0.5 (중앙). 200%+ = 1.0. 0% = 0.0
	var bar_ratio: float = clampf(strength / 200.0, 0.0, 1.0)
	_fill_strength_fill.anchor_left  = 0.0
	_fill_strength_fill.anchor_right = bar_ratio
	_fill_strength_fill.offset_left  = 0
	_fill_strength_fill.offset_right = 0

	if strength > 100.0:
		_lbl_fill_side.text = tr("매수우위")
		_lbl_fill_side.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)
		_fill_strength_style.bg_color = ThemeSetup.LOSS_BLUE.darkened(0.3)
	elif strength < 100.0:
		_lbl_fill_side.text = tr("매도우위")
		_lbl_fill_side.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
		_fill_strength_style.bg_color = ThemeSetup.PROFIT_RED.darkened(0.3)
	else:
		_lbl_fill_side.text = ""
		_fill_strength_style.bg_color = Color(0.5, 0.5, 0.5, 0.5)


func _build_side_tabs(vbox: VBoxContainer) -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	vbox.add_child(hbox)
	_btn_buy_tab = Button.new()
	_btn_buy_tab.text = tr("매수 B")
	_btn_buy_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_buy_tab.custom_minimum_size.y = 28
	_btn_buy_tab.pressed.connect(func() -> void: _set_order_side("BUY"))
	hbox.add_child(_btn_buy_tab)
	_btn_sell_tab = Button.new()
	_btn_sell_tab.text = tr("매도 S")
	_btn_sell_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_sell_tab.custom_minimum_size.y = 28
	_btn_sell_tab.pressed.connect(func() -> void: _set_order_side("SELL"))
	hbox.add_child(_btn_sell_tab)


func _build_type_row(vbox: VBoxContainer) -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	vbox.add_child(hbox)
	_radio_market = Button.new()
	_radio_market.text = tr("시장가")
	_radio_market.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_radio_market.custom_minimum_size.y = 26
	_radio_market.pressed.connect(func() -> void: _set_order_type("MARKET"))
	hbox.add_child(_radio_market)
	_radio_limit = Button.new()
	_radio_limit.text = tr("지정가")
	_radio_limit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_radio_limit.custom_minimum_size.y = 26
	_radio_limit.pressed.connect(func() -> void: _set_order_type("LIMIT"))
	hbox.add_child(_radio_limit)
	_refresh_limit_tab_state()
	SkillTree.on_skill_unlocked.connect(_on_skill_unlocked)
	tree_exiting.connect(func() -> void:
		if SkillTree.on_skill_unlocked.is_connected(_on_skill_unlocked):
			SkillTree.on_skill_unlocked.disconnect(_on_skill_unlocked)
	)
	_limit_price_row = HBoxContainer.new()
	_limit_price_row.visible = false
	vbox.add_child(_limit_price_row)
	var limit_lbl: Label = Label.new()
	limit_lbl.text = tr("지정가")
	limit_lbl.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_primary(limit_lbl)
	_limit_price_row.add_child(limit_lbl)
	_spin_limit_price = SpinBox.new()
	_spin_limit_price.min_value = 0
	_spin_limit_price.max_value = 99999999
	_spin_limit_price.step = 100
	_spin_limit_price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_limit_price.custom_minimum_size.x = 70
	_spin_limit_price.value_changed.connect(func(_v: float) -> void: _update_estimated_amount())
	ThemeSetup.apply_spinbox_theme(_spin_limit_price)
	_limit_price_row.add_child(_spin_limit_price)


func _build_qty_row(vbox: VBoxContainer) -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	vbox.add_child(hbox)
	var qty_lbl: Label = Label.new()
	qty_lbl.text = tr("수량")
	qty_lbl.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_primary(qty_lbl)
	hbox.add_child(qty_lbl)
	_spin_quantity = SpinBox.new()
	_spin_quantity.min_value = 0
	_spin_quantity.max_value = 99999
	_spin_quantity.step = 1
	_spin_quantity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_quantity.custom_minimum_size.x = 70
	_spin_quantity.value_changed.connect(func(_v: float) -> void: _update_estimated_amount())
	ThemeSetup.apply_spinbox_theme(_spin_quantity)
	hbox.add_child(_spin_quantity)
	var btn_max: Button = Button.new()
	btn_max.text = tr("최대")
	btn_max.custom_minimum_size.y = 26
	btn_max.pressed.connect(_calculate_max_quantity)
	ThemeSetup.apply_button_theme(btn_max)
	hbox.add_child(btn_max)
	_lbl_estimated_amount = Label.new()
	_lbl_estimated_amount.text = tr("예상 금액: ₩0")
	ThemeSetup.style_label_secondary(_lbl_estimated_amount)
	vbox.add_child(_lbl_estimated_amount)


func _build_submit_area(vbox: VBoxContainer) -> void:
	_btn_submit_order = Button.new()
	_btn_submit_order.text = tr("주문실행 Enter")
	_btn_submit_order.pressed.connect(_submit_order)
	_btn_submit_order.custom_minimum_size.y = 30
	ThemeSetup.apply_accent_button(_btn_submit_order)
	vbox.add_child(_btn_submit_order)
	_lbl_order_error = Label.new()
	_lbl_order_error.text = ""
	_lbl_order_error.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	_lbl_order_error.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_lbl_order_error)
	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	vbox.add_child(sep)


## Builds the stop-loss / take-profit section. GDD stop-loss-take-profit.md.
## Visible only when TR2 is unlocked and the selected stock is a held position.
## Chart/order-book price clicks route here when a SpinBox line-edit has focus.
func _build_st_section(vbox: VBoxContainer) -> void:
	_st_section = VBoxContainer.new()
	_st_section.add_theme_constant_override("separation", 3)
	_st_section.visible = false
	vbox.add_child(_st_section)

	var title: Label = Label.new()
	title.text = tr("자동 조건 (TR2)")
	title.add_theme_font_size_override("font_size", 11)
	ThemeSetup.style_label_secondary(title)
	_st_section.add_child(title)

	_build_st_spinbox_rows()
	_build_st_button_row()

	var sep: HSeparator = HSeparator.new()
	sep.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	_st_section.add_child(sep)


## 손절가 / 익절가 / 수량 SpinBox 행 3개. GDD stop-loss-take-profit.md.
func _build_st_spinbox_rows() -> void:
	_spin_stop_loss  = _make_st_spinbox_row(tr("손절"), 0,  99999999, 100)
	_spin_take_profit = _make_st_spinbox_row(tr("익절"), 0,  99999999, 100)
	_spin_st_qty     = _make_st_spinbox_row(tr("수량"), 1,  99999,    1)


## Creates a labeled SpinBox row, adds it to _st_section, and returns the SpinBox.
func _make_st_spinbox_row(
	label_text: String, min_val: float, max_val: float, step_val: float
) -> SpinBox:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_st_section.add_child(row)
	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.custom_minimum_size.x = 28
	ThemeSetup.style_label_secondary(lbl)
	row.add_child(lbl)
	var spin: SpinBox = SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step_val
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ThemeSetup.apply_spinbox_theme(spin)
	row.add_child(spin)
	return spin


## 설정/해제 버튼 행 + 에러 레이블. GDD stop-loss-take-profit.md.
func _build_st_button_row() -> void:
	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 2)
	_st_section.add_child(btn_row)
	var btn_set: Button = Button.new()
	btn_set.text = tr("설정")
	btn_set.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_set.custom_minimum_size.y = 24
	ThemeSetup.apply_accent_button(btn_set)
	btn_set.pressed.connect(_submit_st_condition)
	btn_row.add_child(btn_set)
	var btn_clear: Button = Button.new()
	btn_clear.text = tr("해제")
	btn_clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_clear.custom_minimum_size.y = 24
	ThemeSetup.apply_sell_button(btn_clear)
	btn_clear.pressed.connect(_clear_st_condition)
	btn_row.add_child(btn_clear)

	_lbl_st_error = Label.new()
	_lbl_st_error.text = ""
	_lbl_st_error.add_theme_font_size_override("font_size", 11)
	_lbl_st_error.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	_lbl_st_error.autowrap_mode = TextServer.AUTOWRAP_WORD
	_st_section.add_child(_lbl_st_error)


## Refreshes S/T section visibility and SpinBox values for the current stock.
func _refresh_st_section() -> void:
	if _st_section == null:
		return
	var show: bool = (
		SkillTree.is_skill_unlocked("TR2")
		and _selected_stock_id != ""
		and PortfolioManager.get_holding(_selected_stock_id) != null
	)
	_st_section.visible = show
	if not show:
		return
	var holding: Dictionary = PortfolioManager.get_holding(_selected_stock_id) as Dictionary
	var max_qty: int = holding.get("quantity", 1)
	_spin_st_qty.max_value = max_qty
	var cur: Dictionary = StopTakeSystem.get_setting(_selected_stock_id)
	if not cur.is_empty():
		var d: Dictionary = cur
		var sl: Variant = d.get("stop_loss_price")
		var tp: Variant = d.get("take_profit_price")
		_spin_stop_loss.value = float(sl if sl != null else 0)
		_spin_take_profit.value = float(tp if tp != null else 0)
		_spin_st_qty.value = float(d.get("quantity", max_qty))
	else:
		_spin_stop_loss.value = 0.0
		_spin_take_profit.value = 0.0
		_spin_st_qty.value = float(max_qty)
	_lbl_st_error.text = ""


## Validates and submits the S/T condition for the current stock.
func _submit_st_condition() -> void:
	if _selected_stock_id == "":
		return
	var sl: int = int(_spin_stop_loss.value)
	var tp: int = int(_spin_take_profit.value)
	var sl_val: Variant = sl if sl > 0 else null
	var tp_val: Variant = tp if tp > 0 else null
	if sl_val == null and tp_val == null:
		_lbl_st_error.text = tr("손절가 또는 익절가를 입력하세요")
		return
	var cur: int = PriceEngine.get_current_price(_selected_stock_id)
	if sl_val != null and (sl_val as int) >= cur:
		_lbl_st_error.text = tr("손절가는 현재가보다 낮아야 합니다")
		return
	if tp_val != null and (tp_val as int) <= cur:
		_lbl_st_error.text = tr("익절가는 현재가보다 높아야 합니다")
		return
	if sl_val != null and tp_val != null and (sl_val as int) >= (tp_val as int):
		_lbl_st_error.text = tr("손절가는 익절가보다 낮아야 합니다")
		return
	if not StopTakeSystem.set_condition(_selected_stock_id, sl_val, tp_val, int(_spin_st_qty.value)):
		_lbl_st_error.text = tr("설정 실패 (한도 초과 또는 TR2 미해금)")
		return
	_lbl_st_error.text = ""


## Clears the S/T condition for the current stock.
func _clear_st_condition() -> void:
	if _selected_stock_id == "":
		return
	StopTakeSystem.clear_condition(_selected_stock_id)
	_refresh_st_section()


func _build_pending_section(vbox: VBoxContainer) -> void:
	var pending_title: Label = Label.new()
	pending_title.text = tr("미체결 주문")
	ThemeSetup.style_label_secondary(pending_title)
	vbox.add_child(pending_title)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_pending_orders_container = VBoxContainer.new()
	_pending_orders_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_pending_orders_container)
	var btn_cancel_all: Button = Button.new()
	btn_cancel_all.text = tr("전체 취소 Esc")
	ThemeSetup.apply_sell_button(btn_cancel_all)
	btn_cancel_all.pressed.connect(_cancel_all_pending)
	vbox.add_child(btn_cancel_all)


## Called by TradingScreen when the selected stock changes.
func set_stock(stock_id: String) -> void:
	_selected_stock_id = stock_id
	if stock_id == "":
		return
	var stock: StockData = StockDatabase.get_stock(stock_id)
	if stock == null:
		return
	_lbl_order_stock_name.text = stock.get_display_name()
	refresh_limit_price_bounds()
	_spin_limit_price.value = PriceEngine.get_current_price(stock_id)
	_update_order_panel_price()
	_refresh_order_book()
	_refresh_ohlcv()
	_refresh_week52()
	_refresh_a3_section()
	_lbl_order_error.text = ""
	_spin_quantity.value = 0
	_refresh_st_section()


## Called by TradingScreen on PRE_MARKET state enter.
func refresh_limit_price_bounds() -> void:
	if _selected_stock_id == "":
		return
	var limits: Dictionary = PriceEngine.get_daily_limits(_selected_stock_id)
	if limits.size() > 0:
		_spin_limit_price.min_value = limits["lower"]
		_spin_limit_price.max_value = limits["upper"]
	var price: int = PriceEngine.get_current_price(_selected_stock_id)
	_spin_limit_price.step = PriceEngine.get_tick_size(price)


## Called by TradingScreen when UIState changes (enable/disable submit).
func set_ui_state_submit_enabled(enabled: bool, btn_text: String) -> void:
	_btn_submit_order.disabled = not enabled
	_btn_submit_order.text = btn_text
	_refresh_limit_tab_state()


## Routes a price click from chart or order book to the focused input.
## Priority: focused S/T SpinBox → limit price (TR1 behavior).
## GDD stop-loss-take-profit.md, order-book.md §3-5.
func set_price_from_click(price: int) -> void:
	if _spin_stop_loss != null and _spin_stop_loss.get_line_edit().has_focus():
		_spin_stop_loss.value = float(price)
		return
	if _spin_take_profit != null and _spin_take_profit.get_line_edit().has_focus():
		_spin_take_profit.value = float(price)
		return
	set_limit_price_from_chart(price)


## Called by TradingScreen when chart price is clicked (direct limit-price path).
func set_limit_price_from_chart(price: int) -> void:
	if not SkillTree.is_skill_unlocked("TR1"):
		return
	_set_order_type("LIMIT")
	_spin_limit_price.value = float(price)
	_update_estimated_amount()


## Returns the quantity currently entered in the order form.
func get_pending_quantity() -> int:
	return int(_spin_quantity.value)


## Resets the quantity field and clears any order error message.
func clear_quantity() -> void:
	_spin_quantity.value = 0
	_lbl_order_error.text = ""


func _set_order_side(side: String) -> void:
	_order_side = side
	if side == "BUY":
		ThemeSetup.apply_buy_button(_btn_buy_tab)
		ThemeSetup.apply_button_theme(_btn_sell_tab)
	else:
		ThemeSetup.apply_button_theme(_btn_buy_tab)
		ThemeSetup.apply_sell_button(_btn_sell_tab)
	_update_order_panel_price()


func _set_order_type(type: String) -> void:
	if type == "LIMIT" and not SkillTree.is_skill_unlocked("TR1"):
		return  # 버튼이 disabled 상태여야 하므로 여기까지 오면 안 됨 — 안전망
	_order_type = type
	if type == "MARKET":
		ThemeSetup.apply_accent_button(_radio_market)
		ThemeSetup.apply_button_theme(_radio_limit)
	else:
		ThemeSetup.apply_button_theme(_radio_market)
		ThemeSetup.apply_accent_button(_radio_limit)
	_limit_price_row.visible = (type == "LIMIT")
	_update_estimated_amount()


func _update_order_panel_price() -> void:
	if _selected_stock_id == "":
		return
	var price: int = PriceEngine.get_current_price(_selected_stock_id)
	_lbl_order_current_price.text = tr("현재가 ₩%s") % FormatUtils.number(price)
	_update_estimated_amount()


func _update_estimated_amount() -> void:
	var qty: int = int(_spin_quantity.value)
	var ref_price: int = int(_spin_limit_price.value) if _order_type == "LIMIT" \
		else PriceEngine.get_current_price(_selected_stock_id)
	_lbl_estimated_amount.text = tr("예상 금액: ₩%s") % FormatUtils.number(qty * ref_price)


func _calculate_max_quantity() -> void:
	if _selected_stock_id == "":
		return
	if _order_side == "BUY":
		var cash: int = CurrencySystem.get_sim_cash()
		var ref_price: int = int(_spin_limit_price.value) if _order_type == "LIMIT" \
			else PriceEngine.get_current_price(_selected_stock_id)
		if ref_price > 0:
			_spin_quantity.value = float(cash / ref_price)
	else:
		var holding: Variant = PortfolioManager.get_holding(_selected_stock_id)
		if holding != null:
			var available: int = holding["quantity"] - OrderEngine.get_locked_quantity(_selected_stock_id)
			_spin_quantity.value = float(maxi(0, available))
		else:
			_spin_quantity.value = 0
	_update_estimated_amount()


func _submit_order() -> void:
	if _selected_stock_id == "":
		return
	var qty: int = int(_spin_quantity.value)
	if qty <= 0:
		_show_order_error(tr("수량을 입력하세요"))
		return
	_lbl_order_error.text = ""
	var result: Dictionary
	if _order_type == "LIMIT":
		var limit_price: int = int(_spin_limit_price.value)
		if limit_price <= 0:
			_show_order_error(tr("지정가를 입력하세요"))
			return
		result = OrderEngine.submit_limit_order(_order_side, _selected_stock_id, qty, limit_price)
	else:
		result = OrderEngine.submit_market_order(_order_side, _selected_stock_id, qty)
	if result["status"] == "REJECTED":
		_show_order_error(result.get("reject_reason", tr("주문 거부됨")))
	else:
		_spin_quantity.value = 0
	_update_pending_orders()


func _show_order_error(msg: String) -> void:
	_lbl_order_error.text = msg
	if _error_tween and _error_tween.is_valid():
		_error_tween.kill()
	_error_tween = create_tween()
	_error_tween.tween_interval(3.0)
	_error_tween.tween_callback(func() -> void: _lbl_order_error.text = "")


func _flash_order_panel(side: String) -> void:
	AudioManager.play_order_sfx()  # Sound fires with visual flash start
	var flash_color: Color = ThemeSetup.PROFIT_RED if side == "BUY" else ThemeSetup.LOSS_BLUE
	var panel: Control = _btn_submit_order.get_parent()
	panel.modulate = flash_color
	var tween: Tween = create_tween()
	tween.tween_property(panel, "modulate", Color.WHITE, 0.5)


func _update_pending_orders() -> void:
	var pending: Array[Dictionary] = OrderEngine.get_pending_orders()
	var new_ids: Array[int] = []
	for o: Dictionary in pending:
		new_ids.append(o["order_id"] as int)

	if new_ids == _pending_order_ids and pending.size() > 0:
		# Same orders — update detail labels in-place (partial fill qty may change)
		var children: Array[Node] = _pending_orders_container.get_children()
		for i: int in range(mini(children.size(), pending.size())):
			var row: Node = children[i]
			if row.has_meta("detail_lbl"):
				var o: Dictionary = pending[i]
				var price_val: int = o.get("limit_price", PriceEngine.get_current_price(o["stock_id"]))
				(row.get_meta("detail_lbl") as Label).text = "₩%s × %d주" % [FormatUtils.number(price_val), o["quantity"]]
		return

	_pending_order_ids = new_ids
	for child: Node in _pending_orders_container.get_children():
		child.queue_free()
	if pending.size() == 0:
		var lbl: Label = Label.new()
		lbl.text = tr("미체결 주문 없음")
		lbl.add_theme_color_override("font_color", ThemeSetup.TEXT_DIM)
		_pending_orders_container.add_child(lbl)
		return
	for order: Dictionary in pending:
		_pending_orders_container.add_child(_make_pending_row(order))


func _make_pending_row(order: Dictionary) -> Control:
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 1)

	var pending_sid: String = order["stock_id"]
	var pending_stock: StockData = StockDatabase.get_stock(pending_sid)
	var pending_name: String = pending_stock.get_display_name() if pending_stock != null else pending_sid
	var side_str: String = "매수" if order["side"] == "BUY" else "매도"

	# 1줄: [매수/매도 종목명]  [× 취소]
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 2)
	outer.add_child(top)

	var name_lbl: Label = Label.new()
	name_lbl.text = "%s %s" % [side_str, pending_name]
	name_lbl.clip_text = true
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 11)
	ThemeSetup.style_label_primary(name_lbl)
	top.add_child(name_lbl)

	var cancel_btn: Button = Button.new()
	cancel_btn.text = "×"
	cancel_btn.custom_minimum_size = Vector2(22, 20)
	ThemeSetup.apply_button_theme(cancel_btn)
	var order_id: int = order["order_id"]
	cancel_btn.pressed.connect(func() -> void:
		OrderEngine.cancel_order(order_id)
		_update_pending_orders()
	)
	top.add_child(cancel_btn)

	# 2줄: ₩가격 × 수량주 (오른쪽 정렬, 보조색)
	var detail_lbl: Label = Label.new()
	var price_val: int = order.get("limit_price", PriceEngine.get_current_price(pending_sid))
	detail_lbl.text = "₩%s × %d주" % [FormatUtils.number(price_val), order["quantity"]]
	detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	detail_lbl.add_theme_font_size_override("font_size", 11)
	ThemeSetup.style_label_secondary(detail_lbl)
	outer.add_child(detail_lbl)
	outer.set_meta("detail_lbl", detail_lbl)

	return outer


func _cancel_all_pending() -> void:
	OrderEngine.cancel_all_pending_orders()
	_update_pending_orders()


func _on_order_filled(order: Dictionary) -> void:
	_flash_order_panel(order["side"])
	_update_pending_orders()
	_update_order_panel_price()


func _on_order_rejected(order: Dictionary) -> void:
	_show_order_error(order.get("reject_reason", tr("주문 거부됨")))


## TR1 해금 상태에 따라 지정가 버튼 활성/비활성 + 툴팁 갱신.
func _refresh_limit_tab_state() -> void:
	var unlocked: bool = SkillTree.is_skill_unlocked("TR1")
	_radio_limit.disabled = not unlocked
	_radio_limit.tooltip_text = "" if unlocked else tr("TR1 해금 필요")


## SkillTree.on_skill_unlocked 핸들러.
## TR1 해금: 호가창 섹션 즉시 표시 + 지정가 버튼 활성.
## A3 해금: 재무 섹션 즉시 표시 + 분석 탭 바 표시.
## A4 해금: 섹터 탭 버튼 표시.
func _on_skill_unlocked(skill_id: String) -> void:
	if skill_id == "TR1":
		_order_book_section.visible = true
		_refresh_order_book()
		_refresh_ohlcv()
		_refresh_week52()
		_refresh_limit_tab_state()
	elif skill_id == "TR2":
		_refresh_st_section()
	elif skill_id == "A3":
		_analysis_tab_bar.visible = true
		_a3_section.visible = true
		_refresh_a3_section()
	elif skill_id == "A4":
		_btn_analysis_a4.visible = true


## Called by TradingScreen for B/S keyboard shortcuts.
func set_order_side(side: String) -> void:
	_set_order_side(side)


## Called by TradingScreen for Enter key — submits only if quantity > 0.
func try_submit() -> void:
	if int(_spin_quantity.value) > 0:
		_submit_order()
