## Main Trading Screen (HUD) — the primary game interface.
## Hosts: status bar, stock list, chart area, order panel, bottom tabs (news/portfolio).
## See: design/gdd/trading-screen.md
extends Control

# ── Enums ──

enum UIState {
	LOADING,
	PRE_MARKET,
	MARKET_OPEN,
	PAUSED,
	SETTLEMENT,
	SEASON_RESULT,
}

# ── Signals ──

## Emitted when the player selects a stock from the list.
signal stock_selected(stock_id: String)

# ── State ──

var _ui_state: UIState = UIState.LOADING
var _selected_stock_id: String = ""
var _order_side: String = "BUY"  ## "BUY" or "SELL"
var _order_type: String = "MARKET"  ## "MARKET" or "LIMIT"
var _stock_ids: Array[String] = []  ## Ordered list for keyboard shortcuts
var _prev_close_prices: Dictionary = {}  ## stock_id -> int (previous day close)

# ── Node References (assigned in _ready) ──

# Status bar
var _lbl_season_info: Label
var _lbl_tick_progress: Label
var _progress_bar: ProgressBar
var _lbl_speed: Label
var _lbl_total_assets: Label
var _lbl_cash: Label
var _btn_market_open: Button

# Stock list
var _stock_list_container: VBoxContainer

# Order panel
var _lbl_order_stock_name: Label
var _lbl_order_current_price: Label
var _btn_buy_tab: Button
var _btn_sell_tab: Button
var _radio_market: CheckBox
var _radio_limit: CheckBox
var _spin_quantity: SpinBox
var _spin_limit_price: SpinBox
var _limit_price_row: HBoxContainer
var _lbl_estimated_amount: Label
var _btn_max_qty: Button
var _btn_submit_order: Button
var _btn_cancel_order: Button
var _lbl_order_error: Label
var _pending_orders_container: VBoxContainer

# Bottom tabs
var _btn_tab_news: Button
var _btn_tab_portfolio: Button
var _news_panel: Control
var _portfolio_panel: Control

# Chart renderer
var _chart_renderer: Control  ## ChartRenderer instance

# Overlays
var _pause_overlay: Panel
var _settlement_panel: PanelContainer
var _lbl_settlement_title: Label
var _lbl_settlement_body: RichTextLabel
var _btn_settlement_confirm: Button

# Speed buttons
var _btn_speed_1x: Button
var _btn_speed_2x: Button
var _btn_speed_4x: Button
var _btn_pause: Button

# ── Lifecycle ──

func _ready() -> void:
	_build_ui()
	_connect_signals()
	_stock_ids = StockDatabase.get_all_stock_ids()
	_init_prev_close()
	if _stock_ids.size() > 0:
		_select_stock(_stock_ids[0])
	_sync_ui_state_from_clock()


func _init_prev_close() -> void:
	for sid: String in _stock_ids:
		var stock: StockData = StockDatabase.get_stock(sid)
		if stock:
			_prev_close_prices[sid] = stock.base_price


func _connect_signals() -> void:
	GameClock.on_tick.connect(_on_tick)
	GameClock.on_market_state_changed.connect(_on_market_state_changed)
	GameClock.on_market_close.connect(_on_market_close)
	PriceEngine.on_price_updated.connect(_on_price_updated)
	OrderEngine.on_order_filled.connect(_on_order_filled)
	OrderEngine.on_order_rejected.connect(_on_order_rejected)
	OrderEngine.on_order_cancelled.connect(_on_order_cancelled)
	PortfolioManager.valuation_updated.connect(_on_valuation_updated)
	CurrencySystem.sim_cash_changed.connect(_on_sim_cash_changed)


func _sync_ui_state_from_clock() -> void:
	var ms: GameClock.MarketState = GameClock.get_market_state()
	match ms:
		GameClock.MarketState.PRE_MARKET:
			_set_ui_state(UIState.PRE_MARKET)
		GameClock.MarketState.MARKET_OPEN:
			_set_ui_state(UIState.MARKET_OPEN)
		GameClock.MarketState.PAUSED:
			_set_ui_state(UIState.PAUSED)
		GameClock.MarketState.MARKET_CLOSED, GameClock.MarketState.DAY_TRANSITION, GameClock.MarketState.WEEK_END:
			_set_ui_state(UIState.SETTLEMENT)
		GameClock.MarketState.SEASON_END:
			_set_ui_state(UIState.SEASON_RESULT)


# ── Input Handling (GDD Rule 7) ──

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	# Number keys 1-0 → stock selection
	if not key_event.shift_pressed:
		var keycode: int = key_event.keycode
		if keycode >= KEY_1 and keycode <= KEY_9:
			var idx: int = keycode - KEY_1
			if idx < _stock_ids.size():
				_select_stock(_stock_ids[idx])
				get_viewport().set_input_as_handled()
				return
		elif keycode == KEY_0:
			if _stock_ids.size() >= 10:
				_select_stock(_stock_ids[9])
				get_viewport().set_input_as_handled()
				return

	var keycode: int = key_event.keycode

	match keycode:
		KEY_B:
			if not key_event.shift_pressed:
				_set_order_side("BUY")
				get_viewport().set_input_as_handled()
		KEY_S:
			if not key_event.shift_pressed:
				_set_order_side("SELL")
				get_viewport().set_input_as_handled()
		KEY_SPACE:
			_handle_pause_toggle()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			_handle_enter_key()
			get_viewport().set_input_as_handled()
		KEY_TAB:
			_toggle_bottom_tab()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			_handle_escape()
			get_viewport().set_input_as_handled()

	# Shift+1/2/3 → speed change
	if key_event.shift_pressed:
		match keycode:
			KEY_1:
				_set_speed(1.0)
				get_viewport().set_input_as_handled()
			KEY_2:
				_set_speed(2.0)
				get_viewport().set_input_as_handled()
			KEY_3:
				_set_speed(4.0)
				get_viewport().set_input_as_handled()


# ── State Management ──

func _set_ui_state(new_state: UIState) -> void:
	_ui_state = new_state
	_update_ui_for_state()


func _update_ui_for_state() -> void:
	# Default visibility
	_pause_overlay.visible = false
	_settlement_panel.visible = false
	_btn_market_open.visible = false
	_btn_submit_order.disabled = false

	match _ui_state:
		UIState.PRE_MARKET:
			_btn_market_open.visible = true
			_btn_submit_order.text = "주문 예약 Enter"
			_lbl_speed.text = "대기 중"
		UIState.MARKET_OPEN:
			_btn_submit_order.text = "주문 실행 Enter"
			_update_speed_display()
		UIState.PAUSED:
			_pause_overlay.visible = true
			_btn_submit_order.text = "주문 실행 Enter"
		UIState.SETTLEMENT:
			_btn_submit_order.disabled = true
			_show_settlement_report()
		UIState.SEASON_RESULT:
			_btn_submit_order.disabled = true
			_show_season_result()

	_update_status_bar()


# ── Signal Handlers ──

func _on_tick(_tick: int, _day: int, _week: int) -> void:
	_update_status_bar()


func _on_price_updated(_tick: int) -> void:
	_update_stock_list()
	_update_order_panel_price()


func _on_market_state_changed(
	new_state: GameClock.MarketState, _prev: GameClock.MarketState
) -> void:
	match new_state:
		GameClock.MarketState.PRE_MARKET:
			_set_ui_state(UIState.PRE_MARKET)
		GameClock.MarketState.MARKET_OPEN:
			_set_ui_state(UIState.MARKET_OPEN)
		GameClock.MarketState.PAUSED:
			_set_ui_state(UIState.PAUSED)
		GameClock.MarketState.MARKET_CLOSED:
			_set_ui_state(UIState.SETTLEMENT)
		GameClock.MarketState.DAY_TRANSITION:
			pass  # Stay in SETTLEMENT
		GameClock.MarketState.WEEK_END:
			pass  # Stay in SETTLEMENT
		GameClock.MarketState.SEASON_END:
			_set_ui_state(UIState.SEASON_RESULT)


func _on_market_close() -> void:
	# Save closing prices as prev_close for next day
	for sid: String in _stock_ids:
		_prev_close_prices[sid] = PriceEngine.get_current_price(sid)


func _on_order_filled(order: Dictionary) -> void:
	_flash_order_panel(order["side"])
	_update_pending_orders()
	_update_order_panel_price()


func _on_order_rejected(order: Dictionary) -> void:
	_show_order_error(order.get("reject_reason", "주문 거부됨"))
	_update_pending_orders()


func _on_order_cancelled(_order: Dictionary) -> void:
	_update_pending_orders()


func _on_valuation_updated(_total: int, _rate: float) -> void:
	_update_status_bar()


func _on_sim_cash_changed(_amount: int, _delta: int) -> void:
	_update_status_bar()
	_update_order_panel_price()


# ── Stock Selection ──

func _select_stock(stock_id: String) -> void:
	_selected_stock_id = stock_id
	stock_selected.emit(stock_id)
	_update_stock_list_highlight()
	_update_order_panel_for_stock()
	if _chart_renderer and _chart_renderer.has_method("load_stock"):
		_chart_renderer.load_stock(stock_id)


# ── Order Panel Logic ──

func _set_order_side(side: String) -> void:
	_order_side = side
	_btn_buy_tab.button_pressed = (side == "BUY")
	_btn_sell_tab.button_pressed = (side == "SELL")
	_update_order_panel_for_stock()


func _set_order_type(type: String) -> void:
	_order_type = type
	_radio_market.button_pressed = (type == "MARKET")
	_radio_limit.button_pressed = (type == "LIMIT")
	_limit_price_row.visible = (type == "LIMIT")
	_update_estimated_amount()


func _update_order_panel_for_stock() -> void:
	if _selected_stock_id == "":
		return
	var stock: StockData = StockDatabase.get_stock(_selected_stock_id)
	if stock == null:
		return
	_lbl_order_stock_name.text = "%s (%s)" % [stock.name_ko, _selected_stock_id]
	_update_order_panel_price()
	_lbl_order_error.text = ""
	_spin_quantity.value = 0


func _update_order_panel_price() -> void:
	if _selected_stock_id == "":
		return
	var price: int = PriceEngine.get_current_price(_selected_stock_id)
	_lbl_order_current_price.text = "현재가 ₩%s" % _format_number(price)
	_update_estimated_amount()


func _update_estimated_amount() -> void:
	var qty: int = int(_spin_quantity.value)
	var ref_price: int
	if _order_type == "LIMIT":
		ref_price = int(_spin_limit_price.value)
	else:
		ref_price = PriceEngine.get_current_price(_selected_stock_id)
	var estimated: int = qty * ref_price
	_lbl_estimated_amount.text = "예상 금액: ₩%s" % _format_number(estimated)


func _calculate_max_quantity() -> void:
	if _selected_stock_id == "":
		return

	if _order_side == "BUY":
		var cash: int = CurrencySystem.get_sim_cash()
		var ref_price: int
		if _order_type == "LIMIT":
			ref_price = int(_spin_limit_price.value)
		else:
			ref_price = PriceEngine.get_current_price(_selected_stock_id)
		if ref_price > 0:
			_spin_quantity.value = float(cash / ref_price)
	else:
		# SELL: max = held quantity - locked
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
	elif result["status"] == "FILLED":
		_flash_order_panel(result["side"])
		_spin_quantity.value = 0
	else:
		# PENDING
		_spin_quantity.value = 0

	_update_pending_orders()


func _show_order_error(msg: String) -> void:
	_lbl_order_error.text = msg
	# Clear after 3 seconds
	var tween: Tween = create_tween()
	tween.tween_interval(3.0)
	tween.tween_callback(func() -> void: _lbl_order_error.text = "")


func _flash_order_panel(side: String) -> void:
	var flash_color: Color = Color(0.2, 0.8, 0.2, 0.3) if side == "BUY" else Color(0.9, 0.5, 0.1, 0.3)
	var panel: Control = _btn_submit_order.get_parent()
	var original: Color = panel.modulate
	panel.modulate = flash_color
	var tween: Tween = create_tween()
	tween.tween_property(panel, "modulate", original, 0.5)


# ── Pending Orders ──

func _update_pending_orders() -> void:
	for child: Node in _pending_orders_container.get_children():
		child.queue_free()

	var pending: Array[Dictionary] = OrderEngine.get_pending_orders()
	if pending.size() == 0:
		var lbl: Label = Label.new()
		lbl.text = "미체결 주문 없음"
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_pending_orders_container.add_child(lbl)
		return

	for order: Dictionary in pending:
		var row: HBoxContainer = HBoxContainer.new()
		var side_str: String = "매수" if order["side"] == "BUY" else "매도"
		var info: Label = Label.new()
		info.text = "%s %s %s×%d주" % [
			side_str, order["stock_id"],
			_format_number(order.get("limit_price", PriceEngine.get_current_price(order["stock_id"]))),
			order["quantity"]
		]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var cancel_btn: Button = Button.new()
		cancel_btn.text = "취소"
		var order_id: int = order["order_id"]
		cancel_btn.pressed.connect(func() -> void: _cancel_pending_order(order_id))
		row.add_child(cancel_btn)

		_pending_orders_container.add_child(row)


func _cancel_pending_order(order_id: int) -> void:
	OrderEngine.cancel_order(order_id)
	_update_pending_orders()


# ── Stock List ──

func _update_stock_list() -> void:
	var items: Array[Node] = []
	for child: Node in _stock_list_container.get_children():
		items.append(child)

	for i: int in range(_stock_ids.size()):
		if i >= items.size():
			break
		var sid: String = _stock_ids[i]
		var row: HBoxContainer = items[i] as HBoxContainer
		_update_stock_row(row, sid)


func _update_stock_row(row: HBoxContainer, stock_id: String) -> void:
	var price: int = PriceEngine.get_current_price(stock_id)
	var prev_close: int = _prev_close_prices.get(stock_id, price)
	var change_pct: float = 0.0
	if prev_close > 0:
		change_pct = float(price - prev_close) / float(prev_close) * 100.0

	var is_held: bool = PortfolioManager.get_holding(stock_id) != null
	var is_selected: bool = (stock_id == _selected_stock_id)

	# Labels: [marker] [ticker] [price] [change%] [arrow] [held]
	var children: Array[Node] = []
	for child: Node in row.get_children():
		children.append(child)

	if children.size() < 4:
		return

	# Marker label (▶ for selected)
	var lbl_marker: Label = children[0] as Label
	lbl_marker.text = "▶" if is_selected else "  "

	# Ticker + price
	var lbl_info: Label = children[1] as Label
	lbl_info.text = "%s  ₩%s" % [stock_id, _format_number(price)]

	# Change %
	var lbl_change: Label = children[2] as Label
	var arrow: String = "▲" if change_pct > 0.0 else ("▼" if change_pct < 0.0 else "─")
	lbl_change.text = "%+.1f%% %s" % [change_pct, arrow]
	if change_pct > 0.0:
		lbl_change.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	elif change_pct < 0.0:
		lbl_change.add_theme_color_override("font_color", Color(0.2, 0.4, 0.9))
	else:
		lbl_change.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

	# Held marker
	var lbl_held: Label = children[3] as Label
	lbl_held.text = "★" if is_held else ""


func _update_stock_list_highlight() -> void:
	var items: Array[Node] = []
	for child: Node in _stock_list_container.get_children():
		items.append(child)

	for i: int in range(_stock_ids.size()):
		if i >= items.size():
			break
		var sid: String = _stock_ids[i]
		var row: HBoxContainer = items[i] as HBoxContainer
		var marker: Label = row.get_child(0) as Label
		marker.text = "▶" if sid == _selected_stock_id else "  "


# ── Status Bar ──

func _update_status_bar() -> void:
	var day: int = GameClock.get_current_day()
	var week: int = GameClock.get_current_week()
	var day_names: Array[String] = ["월", "화", "수", "목", "금"]
	var day_in_week: int = day % GameClock.DAYS_PER_WEEK
	var day_name: String = day_names[day_in_week] if day_in_week < day_names.size() else "?"

	_lbl_season_info.text = "%d주차 %s요일" % [week + 1, day_name]

	var tick: int = GameClock.get_current_tick()
	_lbl_tick_progress.text = "틱 %d/%d" % [tick, GameClock.TICKS_PER_DAY]
	_progress_bar.value = GameClock.get_day_progress() * 100.0

	# Total assets
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	var total: int = summary["total_assets"]
	var rate: float = summary["return_rate"]
	var rate_color: String
	if rate > 0.0:
		rate_color = "ff3333"  # red for profit (Korean convention)
	elif rate < 0.0:
		rate_color = "3366ff"  # blue for loss
	else:
		rate_color = "999999"
	_lbl_total_assets.text = "총 자산: ₩%s" % _format_number(total)
	# Use modulate for color since Label doesn't support inline BBCode
	if rate > 0.0:
		_lbl_total_assets.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	elif rate < 0.0:
		_lbl_total_assets.add_theme_color_override("font_color", Color(0.2, 0.4, 0.9))
	else:
		_lbl_total_assets.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	# Cash display
	var cash: int = CurrencySystem.get_sim_cash()
	var reserved: int = OrderEngine.get_total_reserved_cash()
	if reserved > 0:
		_lbl_cash.text = "시드: ₩%s (예약: ₩%s)" % [_format_number(cash), _format_number(reserved)]
	else:
		_lbl_cash.text = "시드: ₩%s" % _format_number(cash)

	_update_speed_display()


func _update_speed_display() -> void:
	if _ui_state == UIState.PAUSED:
		_lbl_speed.text = "⏸ 일시정지"
	elif _ui_state == UIState.PRE_MARKET:
		_lbl_speed.text = "대기 중"
	else:
		var spd: float = GameClock.get_speed_multiplier()
		if spd <= 1.0:
			_lbl_speed.text = "▶ 1x"
		elif spd <= 2.0:
			_lbl_speed.text = "▶▶ 2x"
		else:
			_lbl_speed.text = "▶▶▶▶ 4x"


# ── Speed & Pause Controls ──

func _set_speed(multiplier: float) -> void:
	if _ui_state != UIState.MARKET_OPEN and _ui_state != UIState.PAUSED:
		return
	GameClock.set_speed(multiplier)
	_update_speed_display()


func _handle_pause_toggle() -> void:
	if _ui_state == UIState.MARKET_OPEN or _ui_state == UIState.PAUSED:
		GameClock.toggle_pause()


func _handle_enter_key() -> void:
	if _ui_state == UIState.PRE_MARKET:
		GameClock.confirm_market_open()
	elif _ui_state == UIState.SETTLEMENT or _ui_state == UIState.SEASON_RESULT:
		_confirm_settlement()
	elif _ui_state == UIState.MARKET_OPEN or _ui_state == UIState.PAUSED:
		if int(_spin_quantity.value) > 0:
			_submit_order()


func _handle_escape() -> void:
	if _settlement_panel.visible:
		_confirm_settlement()
	else:
		# Clear order input
		_spin_quantity.value = 0
		_lbl_order_error.text = ""


func _toggle_bottom_tab() -> void:
	if _news_panel.visible:
		_news_panel.visible = false
		_portfolio_panel.visible = true
		_btn_tab_news.button_pressed = false
		_btn_tab_portfolio.button_pressed = true
	else:
		_news_panel.visible = true
		_portfolio_panel.visible = false
		_btn_tab_news.button_pressed = true
		_btn_tab_portfolio.button_pressed = false


# ── Settlement / Season Result ──

func _show_settlement_report() -> void:
	_settlement_panel.visible = true
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	var day: int = GameClock.get_current_day()
	_lbl_settlement_title.text = "일일 정산 (Day %d)" % (day + 1)
	_lbl_settlement_body.text = "총 자산: ₩%s\n수익률: %+.2f%%\n보유 종목: %d\n현금: ₩%s" % [
		_format_number(summary["total_assets"]),
		summary["return_rate"],
		summary["holding_count"],
		_format_number(summary["sim_cash"]),
	]
	_btn_settlement_confirm.text = "확인 Enter"


func _show_season_result() -> void:
	_settlement_panel.visible = true
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	_lbl_settlement_title.text = "시즌 결과"
	_lbl_settlement_body.text = "최종 자산: ₩%s\n수익률: %+.2f%%\n\n시즌이 종료되었습니다." % [
		_format_number(summary["total_assets"]),
		summary["return_rate"],
	]
	_btn_settlement_confirm.text = "다음 시즌 Enter"


func _confirm_settlement() -> void:
	_settlement_panel.visible = false
	GameClock.confirm_transition()


# ── UI Construction (code-built for now, .tscn later) ──

func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	# Main HBoxContainer: [stock_list | center_area | order_panel]
	var main_hbox: HBoxContainer = HBoxContainer.new()
	main_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_hbox.add_theme_constant_override("separation", 4)
	add_child(main_hbox)

	# ── Left: Stock List (15%) ──
	var stock_panel: PanelContainer = PanelContainer.new()
	stock_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_panel.size_flags_stretch_ratio = 0.15
	main_hbox.add_child(stock_panel)

	var stock_vbox: VBoxContainer = VBoxContainer.new()
	stock_panel.add_child(stock_vbox)

	var stock_title: Label = Label.new()
	stock_title.text = "종목 리스트"
	stock_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stock_vbox.add_child(stock_title)

	var stock_sep: HSeparator = HSeparator.new()
	stock_vbox.add_child(stock_sep)

	_stock_list_container = VBoxContainer.new()
	_stock_list_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stock_vbox.add_child(_stock_list_container)

	# Populate stock rows
	for i: int in range(_stock_ids.size()):
		var sid: String = _stock_ids[i]
		var row: HBoxContainer = _create_stock_row(sid, i)
		_stock_list_container.add_child(row)

	# ── Center: Status bar + Chart + Bottom tabs (45%) ──
	var center_vbox: VBoxContainer = VBoxContainer.new()
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_vbox.size_flags_stretch_ratio = 0.50
	main_hbox.add_child(center_vbox)

	# Status bar
	_build_status_bar(center_vbox)

	# Chart renderer
	var chart_script: GDScript = load("res://src/ui/chart_renderer.gd") as GDScript
	_chart_renderer = chart_script.new() as Control
	_chart_renderer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chart_renderer.size_flags_stretch_ratio = 0.65
	center_vbox.add_child(_chart_renderer)

	# Bottom panel with tabs
	_build_bottom_panel(center_vbox)

	# ── Right: Order Panel (20%) ──
	_build_order_panel(main_hbox)

	# ── Overlays ──
	_build_overlays()


func _build_status_bar(parent: VBoxContainer) -> void:
	var bar: PanelContainer = PanelContainer.new()
	parent.add_child(bar)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	bar.add_child(hbox)

	_lbl_season_info = Label.new()
	_lbl_season_info.text = "1주차 월요일"
	hbox.add_child(_lbl_season_info)

	var sep1: VSeparator = VSeparator.new()
	hbox.add_child(sep1)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.custom_minimum_size.x = 100
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.show_percentage = false
	hbox.add_child(_progress_bar)

	_lbl_tick_progress = Label.new()
	_lbl_tick_progress.text = "틱 0/390"
	hbox.add_child(_lbl_tick_progress)

	var sep2: VSeparator = VSeparator.new()
	hbox.add_child(sep2)

	_lbl_speed = Label.new()
	_lbl_speed.text = "▶ 1x"
	hbox.add_child(_lbl_speed)

	# Speed buttons
	_btn_speed_1x = Button.new()
	_btn_speed_1x.text = "1x"
	_btn_speed_1x.pressed.connect(func() -> void: _set_speed(1.0))
	hbox.add_child(_btn_speed_1x)

	_btn_speed_2x = Button.new()
	_btn_speed_2x.text = "2x"
	_btn_speed_2x.pressed.connect(func() -> void: _set_speed(2.0))
	hbox.add_child(_btn_speed_2x)

	_btn_speed_4x = Button.new()
	_btn_speed_4x.text = "4x"
	_btn_speed_4x.pressed.connect(func() -> void: _set_speed(4.0))
	hbox.add_child(_btn_speed_4x)

	_btn_pause = Button.new()
	_btn_pause.text = "⏸ Space"
	_btn_pause.pressed.connect(_handle_pause_toggle)
	hbox.add_child(_btn_pause)

	var sep3: VSeparator = VSeparator.new()
	hbox.add_child(sep3)

	_lbl_total_assets = Label.new()
	_lbl_total_assets.text = "총 자산: ₩0"
	hbox.add_child(_lbl_total_assets)

	_lbl_cash = Label.new()
	_lbl_cash.text = "시드: ₩0"
	hbox.add_child(_lbl_cash)

	# Market open button (PRE_MARKET only)
	_btn_market_open = Button.new()
	_btn_market_open.text = "장 시작 Enter"
	_btn_market_open.visible = false
	_btn_market_open.pressed.connect(func() -> void: GameClock.confirm_market_open())
	hbox.add_child(_btn_market_open)


func _build_bottom_panel(parent: VBoxContainer) -> void:
	var bottom: VBoxContainer = VBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.size_flags_stretch_ratio = 0.35
	parent.add_child(bottom)

	# Tab buttons
	var tab_bar: HBoxContainer = HBoxContainer.new()
	bottom.add_child(tab_bar)

	_btn_tab_news = Button.new()
	_btn_tab_news.text = "뉴스 Tab"
	_btn_tab_news.toggle_mode = true
	_btn_tab_news.button_pressed = true
	_btn_tab_news.pressed.connect(func() -> void:
		_news_panel.visible = true
		_portfolio_panel.visible = false
		_btn_tab_news.button_pressed = true
		_btn_tab_portfolio.button_pressed = false
	)
	tab_bar.add_child(_btn_tab_news)

	_btn_tab_portfolio = Button.new()
	_btn_tab_portfolio.text = "포트폴리오 Tab"
	_btn_tab_portfolio.toggle_mode = true
	_btn_tab_portfolio.button_pressed = false
	_btn_tab_portfolio.pressed.connect(func() -> void:
		_news_panel.visible = false
		_portfolio_panel.visible = true
		_btn_tab_news.button_pressed = false
		_btn_tab_portfolio.button_pressed = true
	)
	tab_bar.add_child(_btn_tab_portfolio)

	# News feed panel (real component)
	var news_script: GDScript = load("res://src/ui/news_feed.gd") as GDScript
	_news_panel = news_script.new() as Control
	_news_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_child(_news_panel)
	if _news_panel.has_signal("stock_clicked"):
		_news_panel.stock_clicked.connect(_select_stock)

	# Portfolio view panel (real component)
	var port_script: GDScript = load("res://src/ui/portfolio_view.gd") as GDScript
	_portfolio_panel = port_script.new() as Control
	_portfolio_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portfolio_panel.visible = false
	bottom.add_child(_portfolio_panel)
	if _portfolio_panel.has_signal("stock_clicked"):
		_portfolio_panel.stock_clicked.connect(_select_stock)


func _build_order_panel(parent: HBoxContainer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.20
	parent.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Stock name + price
	_lbl_order_stock_name = Label.new()
	_lbl_order_stock_name.text = "종목 선택"
	_lbl_order_stock_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_lbl_order_stock_name)

	_lbl_order_current_price = Label.new()
	_lbl_order_current_price.text = "현재가 ₩0"
	_lbl_order_current_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_lbl_order_current_price)

	var sep1: HSeparator = HSeparator.new()
	vbox.add_child(sep1)

	# Buy/Sell tabs
	var side_hbox: HBoxContainer = HBoxContainer.new()
	vbox.add_child(side_hbox)

	_btn_buy_tab = Button.new()
	_btn_buy_tab.text = "매수 B"
	_btn_buy_tab.toggle_mode = true
	_btn_buy_tab.button_pressed = true
	_btn_buy_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_buy_tab.pressed.connect(func() -> void: _set_order_side("BUY"))
	side_hbox.add_child(_btn_buy_tab)

	_btn_sell_tab = Button.new()
	_btn_sell_tab.text = "매도 S"
	_btn_sell_tab.toggle_mode = true
	_btn_sell_tab.button_pressed = false
	_btn_sell_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_sell_tab.pressed.connect(func() -> void: _set_order_side("SELL"))
	side_hbox.add_child(_btn_sell_tab)

	# Order type
	var type_hbox: HBoxContainer = HBoxContainer.new()
	vbox.add_child(type_hbox)

	_radio_market = CheckBox.new()
	_radio_market.text = "시장가"
	_radio_market.button_pressed = true
	_radio_market.pressed.connect(func() -> void: _set_order_type("MARKET"))
	type_hbox.add_child(_radio_market)

	_radio_limit = CheckBox.new()
	_radio_limit.text = "지정가"
	_radio_limit.button_pressed = false
	_radio_limit.pressed.connect(func() -> void: _set_order_type("LIMIT"))
	type_hbox.add_child(_radio_limit)

	# Limit price row (hidden by default)
	_limit_price_row = HBoxContainer.new()
	_limit_price_row.visible = false
	vbox.add_child(_limit_price_row)

	var limit_lbl: Label = Label.new()
	limit_lbl.text = "지정가:"
	_limit_price_row.add_child(limit_lbl)

	_spin_limit_price = SpinBox.new()
	_spin_limit_price.min_value = 0
	_spin_limit_price.max_value = 99999999
	_spin_limit_price.step = 100
	_spin_limit_price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_limit_price.value_changed.connect(func(_v: float) -> void: _update_estimated_amount())
	_limit_price_row.add_child(_spin_limit_price)

	# Quantity
	var qty_hbox: HBoxContainer = HBoxContainer.new()
	vbox.add_child(qty_hbox)

	var qty_lbl: Label = Label.new()
	qty_lbl.text = "수량:"
	qty_hbox.add_child(qty_lbl)

	_spin_quantity = SpinBox.new()
	_spin_quantity.min_value = 0
	_spin_quantity.max_value = 99999
	_spin_quantity.step = 1
	_spin_quantity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_quantity.value_changed.connect(func(_v: float) -> void: _update_estimated_amount())
	qty_hbox.add_child(_spin_quantity)

	_btn_max_qty = Button.new()
	_btn_max_qty.text = "최대"
	_btn_max_qty.pressed.connect(_calculate_max_quantity)
	qty_hbox.add_child(_btn_max_qty)

	# Estimated amount
	_lbl_estimated_amount = Label.new()
	_lbl_estimated_amount.text = "예상 금액: ₩0"
	vbox.add_child(_lbl_estimated_amount)

	# Submit button
	_btn_submit_order = Button.new()
	_btn_submit_order.text = "주문 실행 Enter"
	_btn_submit_order.pressed.connect(_submit_order)
	vbox.add_child(_btn_submit_order)

	# Error label
	_lbl_order_error = Label.new()
	_lbl_order_error.text = ""
	_lbl_order_error.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	_lbl_order_error.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_lbl_order_error)

	var sep2: HSeparator = HSeparator.new()
	vbox.add_child(sep2)

	# Pending orders
	var pending_title: Label = Label.new()
	pending_title.text = "미체결 주문"
	vbox.add_child(pending_title)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_pending_orders_container = VBoxContainer.new()
	_pending_orders_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_pending_orders_container)

	# Cancel all button
	_btn_cancel_order = Button.new()
	_btn_cancel_order.text = "전체 취소 Esc"
	_btn_cancel_order.pressed.connect(func() -> void:
		var pending: Array[Dictionary] = OrderEngine.get_pending_orders()
		for order: Dictionary in pending:
			OrderEngine.cancel_order(order["order_id"])
		_update_pending_orders()
	)
	vbox.add_child(_btn_cancel_order)


func _build_overlays() -> void:
	# Pause overlay
	_pause_overlay = Panel.new()
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.visible = false
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pause_overlay)

	# Make it semi-transparent
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.3)
	_pause_overlay.add_theme_stylebox_override("panel", style)

	var pause_lbl: Label = Label.new()
	pause_lbl.text = "⏸ 일시정지"
	pause_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_lbl.add_theme_font_size_override("font_size", 48)
	_pause_overlay.add_child(pause_lbl)

	# Settlement panel
	_settlement_panel = PanelContainer.new()
	_settlement_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_settlement_panel.custom_minimum_size = Vector2(400, 300)
	_settlement_panel.visible = false
	add_child(_settlement_panel)

	var settle_vbox: VBoxContainer = VBoxContainer.new()
	settle_vbox.add_theme_constant_override("separation", 16)
	_settlement_panel.add_child(settle_vbox)

	_lbl_settlement_title = Label.new()
	_lbl_settlement_title.text = "정산"
	_lbl_settlement_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_settlement_title.add_theme_font_size_override("font_size", 24)
	settle_vbox.add_child(_lbl_settlement_title)

	_lbl_settlement_body = RichTextLabel.new()
	_lbl_settlement_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lbl_settlement_body.bbcode_enabled = false
	settle_vbox.add_child(_lbl_settlement_body)

	_btn_settlement_confirm = Button.new()
	_btn_settlement_confirm.text = "확인 Enter"
	_btn_settlement_confirm.pressed.connect(_confirm_settlement)
	settle_vbox.add_child(_btn_settlement_confirm)


func _create_stock_row(stock_id: String, index: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	# Click handler via gui_input
	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_select_stock(stock_id)
	)

	# Selection marker
	var lbl_marker: Label = Label.new()
	lbl_marker.text = "  "
	lbl_marker.custom_minimum_size.x = 20
	row.add_child(lbl_marker)

	# Stock info (ticker + price)
	var lbl_info: Label = Label.new()
	var stock: StockData = StockDatabase.get_stock(stock_id)
	var price: int = stock.base_price if stock else 0
	lbl_info.text = "%s  ₩%s" % [stock_id, _format_number(price)]
	lbl_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl_info)

	# Change %
	var lbl_change: Label = Label.new()
	lbl_change.text = "+0.0% ─"
	lbl_change.custom_minimum_size.x = 80
	row.add_child(lbl_change)

	# Held marker
	var lbl_held: Label = Label.new()
	lbl_held.text = ""
	lbl_held.custom_minimum_size.x = 20
	row.add_child(lbl_held)

	# Shortcut hint
	var shortcut_key: String = str((index + 1) % 10)
	var lbl_key: Label = Label.new()
	lbl_key.text = shortcut_key
	lbl_key.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.6))
	row.add_child(lbl_key)

	return row


# ── Utility ──

func _format_number(value: int) -> String:
	var s: String = str(absi(value))
	var result: String = ""
	var count: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	if value < 0:
		result = "-" + result
	return result
