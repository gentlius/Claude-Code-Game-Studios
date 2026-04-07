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


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_stretch_ratio = 0.13
	custom_minimum_size.x = 160
	add_theme_stylebox_override("panel", ThemeSetup.make_panel_style(ThemeSetup.BG_DARK))
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)
	_build_header(vbox)
	_build_side_tabs(vbox)
	_build_type_row(vbox)
	_build_qty_row(vbox)
	_build_submit_area(vbox)
	_build_pending_section(vbox)
	_set_order_side("BUY")
	_set_order_type("MARKET")
	OrderEngine.on_order_filled.connect(_on_order_filled)
	OrderEngine.on_order_rejected.connect(_on_order_rejected)
	OrderEngine.on_order_cancelled.connect(func(_o: Dictionary) -> void: _update_pending_orders())
	OrderEngine.on_order_expired.connect(func(_o: Dictionary) -> void: _update_pending_orders())
	CurrencySystem.sim_cash_changed.connect(func(_a: int, _d: int) -> void: _update_order_panel_price())
	PriceEngine.on_price_updated.connect(func(_t: int) -> void: _update_order_panel_price())


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
	_radio_limit.text = tr("지정가") if SkillTree.is_skill_unlocked("TR1") else tr("지정가 🔒")
	_radio_limit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_radio_limit.custom_minimum_size.y = 26
	_radio_limit.pressed.connect(func() -> void: _set_order_type("LIMIT"))
	hbox.add_child(_radio_limit)
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
	btn_cancel_all.text = "전체 취소 Esc"
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
	_lbl_order_stock_name.text = "%s (%s)" % [stock.name_ko, stock_id]
	refresh_limit_price_bounds()
	_spin_limit_price.value = PriceEngine.get_current_price(stock_id)
	_update_order_panel_price()
	_lbl_order_error.text = ""
	_spin_quantity.value = 0


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
	_radio_limit.text = "지정가" if SkillTree.is_skill_unlocked("TR1") else "지정가 🔒"


## Called by TradingScreen when chart price is clicked.
func set_limit_price_from_chart(price: int) -> void:
	if not SkillTree.is_skill_unlocked("TR1"):
		return
	_set_order_type("LIMIT")
	_spin_limit_price.value = float(price)
	_update_estimated_amount()


func get_pending_quantity() -> int:
	return int(_spin_quantity.value)


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
		_show_order_error("지정가 주문은 TR1 스킬이 필요합니다")
		return
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
	_lbl_order_current_price.text = "현재가 ₩%s" % FormatUtils.number(price)
	_update_estimated_amount()


func _update_estimated_amount() -> void:
	var qty: int = int(_spin_quantity.value)
	var ref_price: int = int(_spin_limit_price.value) if _order_type == "LIMIT" \
		else PriceEngine.get_current_price(_selected_stock_id)
	_lbl_estimated_amount.text = "예상 금액: ₩%s" % FormatUtils.number(qty * ref_price)


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
		_show_order_error("수량을 입력하세요")
		return
	_lbl_order_error.text = ""
	var result: Dictionary
	if _order_type == "LIMIT":
		var limit_price: int = int(_spin_limit_price.value)
		if limit_price <= 0:
			_show_order_error("지정가를 입력하세요")
			return
		result = OrderEngine.submit_limit_order(_order_side, _selected_stock_id, qty, limit_price)
	else:
		result = OrderEngine.submit_market_order(_order_side, _selected_stock_id, qty)
	if result["status"] == "REJECTED":
		_show_order_error(result.get("reject_reason", "주문 거부됨"))
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
	var flash_color: Color = ThemeSetup.PROFIT_RED if side == "BUY" else ThemeSetup.LOSS_BLUE
	var panel: Control = _btn_submit_order.get_parent()
	panel.modulate = flash_color
	var tween: Tween = create_tween()
	tween.tween_property(panel, "modulate", Color.WHITE, 0.5)


func _update_pending_orders() -> void:
	for child: Node in _pending_orders_container.get_children():
		child.queue_free()
	var pending: Array[Dictionary] = OrderEngine.get_pending_orders()
	if pending.size() == 0:
		var lbl: Label = Label.new()
		lbl.text = "미체결 주문 없음"
		lbl.add_theme_color_override("font_color", ThemeSetup.TEXT_DIM)
		_pending_orders_container.add_child(lbl)
		return
	for order: Dictionary in pending:
		_pending_orders_container.add_child(_make_pending_row(order))


func _make_pending_row(order: Dictionary) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var side_str: String = "매수" if order["side"] == "BUY" else "매도"
	var info: Label = Label.new()
	info.text = "%s %s %s×%d주" % [
		side_str, order["stock_id"],
		FormatUtils.number(order.get("limit_price", PriceEngine.get_current_price(order["stock_id"]))),
		order["quantity"]]
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ThemeSetup.style_label_primary(info)
	row.add_child(info)
	var cancel_btn: Button = Button.new()
	cancel_btn.text = "취소"
	ThemeSetup.apply_button_theme(cancel_btn)
	var order_id: int = order["order_id"]
	cancel_btn.pressed.connect(func() -> void:
		OrderEngine.cancel_order(order_id)
		_update_pending_orders()
	)
	row.add_child(cancel_btn)
	return row


func _cancel_all_pending() -> void:
	OrderEngine.cancel_all_pending_orders()
	_update_pending_orders()


func _on_order_filled(order: Dictionary) -> void:
	_flash_order_panel(order["side"])
	_update_pending_orders()
	_update_order_panel_price()


func _on_order_rejected(order: Dictionary) -> void:
	_show_order_error(order.get("reject_reason", "주문 거부됨"))


## Called by TradingScreen for B/S keyboard shortcuts.
func set_order_side(side: String) -> void:
	_set_order_side(side)


## Called by TradingScreen for Enter key — submits only if quantity > 0.
func try_submit() -> void:
	if int(_spin_quantity.value) > 0:
		_submit_order()
