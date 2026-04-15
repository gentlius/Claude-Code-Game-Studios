## Portfolio View — Displays holdings, PnL, and asset summary.
## Hosted in TradingScreen's bottom panel as "포트폴리오" tab.
## See: design/gdd/portfolio-ui.md
extends VBoxContainer

# ── Signals ──

## Emitted when player clicks a stock in the holdings list.
signal stock_clicked(stock_id: String)

# ── Node References ──

var _summary_bar: HBoxContainer
var _lbl_total_assets: Label
var _lbl_return_rate: Label
var _lbl_cash_info: Label
var _lbl_seed_capital: Label
var _lbl_slot_counter: Label  ## "X/5" or "X/10" slot counter (P1/P2)
var _holdings_container: VBoxContainer
var _tx_container: VBoxContainer
## Diff-based cache: stock_id → {lbl_qty, lbl_price, lbl_rate, lbl_value} node refs.
## Avoids full teardown/rebuild on every valuation_updated tick (P3 optimisation).
var _holding_rows: Dictionary = {}
## S7-07: Trigger badge — shows "SL 발동" / "TP 발동" on auto-sell.
var _trigger_badge: Label
var _badge_tween: Tween

# ── Lifecycle ──

func _ready() -> void:
	_build_ui()
	PortfolioManager.valuation_updated.connect(_on_valuation_updated)
	PortfolioManager.holding_added.connect(_on_holding_added)
	PortfolioManager.holding_removed.connect(_on_holding_removed)
	SkillTree.on_skill_unlocked.connect(_on_skill_unlocked_refresh_slots)
	StopTakeSystem.on_stop_take_triggered.connect(_on_stop_take_triggered)
	tree_exiting.connect(_disconnect_signals)
	# Initial render — valuation_updated may have fired during load_slot() before
	# this node existed, so explicitly refresh on entry.
	_refresh()


func _build_ui() -> void:
	# Summary bar
	_summary_bar = HBoxContainer.new()
	_summary_bar.add_theme_constant_override("separation", 16)
	add_child(_summary_bar)

	var title: Label = Label.new()
	title.text = tr("포트폴리오 요약")
	title.add_theme_font_size_override("font_size", 14)
	ThemeSetup.style_label_primary(title)
	_summary_bar.add_child(title)

	_lbl_total_assets = Label.new()
	_lbl_total_assets.text = "총 자산: ₩0"
	ThemeSetup.style_label_primary(_lbl_total_assets)
	_summary_bar.add_child(_lbl_total_assets)

	_lbl_return_rate = Label.new()
	_lbl_return_rate.text = "(0.0%)"
	_summary_bar.add_child(_lbl_return_rate)

	_lbl_cash_info = Label.new()
	_lbl_cash_info.text = ""
	ThemeSetup.style_label_secondary(_lbl_cash_info)
	_summary_bar.add_child(_lbl_cash_info)

	_lbl_seed_capital = Label.new()
	_lbl_seed_capital.text = ""
	ThemeSetup.style_label_dim(_lbl_seed_capital)
	_summary_bar.add_child(_lbl_seed_capital)

	# Slot counter — implements P1/P2 skill UI feedback (design/gdd/skill-tree.md §P1 §P2)
	_lbl_slot_counter = Label.new()
	_lbl_slot_counter.text = ""
	ThemeSetup.style_label_secondary(_lbl_slot_counter)
	_summary_bar.add_child(_lbl_slot_counter)

	var sep: HSeparator = HSeparator.new()
	add_child(sep)

	# S7-07: Trigger badge — visible briefly after auto-sell fires.
	_trigger_badge = Label.new()
	_trigger_badge.visible = false
	_trigger_badge.add_theme_font_size_override("font_size", 12)
	_trigger_badge.add_theme_color_override("font_color", Color(0.95, 0.82, 0.30))
	add_child(_trigger_badge)

	# Holdings scroll area
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var scroll_vbox: VBoxContainer = VBoxContainer.new()
	scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scroll_vbox)

	# Holdings header
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	scroll_vbox.add_child(header)

	for col: String in [tr("종목"), tr("수량"), tr("현재가"), tr("수익률"), tr("평가금액"), tr("S/T")]:
		var lbl: Label = Label.new()
		lbl.text = col
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeSetup.style_label_dim(lbl)
		header.add_child(lbl)

	_holdings_container = VBoxContainer.new()
	_holdings_container.add_theme_constant_override("separation", 2)
	scroll_vbox.add_child(_holdings_container)

	# Transaction history (last 5)
	var tx_sep: HSeparator = HSeparator.new()
	scroll_vbox.add_child(tx_sep)

	var tx_title: Label = Label.new()
	tx_title.text = tr("최근 거래")
	tx_title.add_theme_color_override("font_color", ThemeSetup.TEXT_DIM)
	scroll_vbox.add_child(tx_title)

	_tx_container = VBoxContainer.new()
	_tx_container.add_theme_constant_override("separation", 1)
	scroll_vbox.add_child(_tx_container)


# ── Signal Handlers ──

func _on_holding_added(_s: String, _q: int, _p: int) -> void:
	_refresh()


func _on_holding_removed(_s: String, _q: int, _p: int, _pnl: int) -> void:
	_refresh()


func _disconnect_signals() -> void:
	if PortfolioManager.valuation_updated.is_connected(_on_valuation_updated):
		PortfolioManager.valuation_updated.disconnect(_on_valuation_updated)
	if PortfolioManager.holding_added.is_connected(_on_holding_added):
		PortfolioManager.holding_added.disconnect(_on_holding_added)
	if PortfolioManager.holding_removed.is_connected(_on_holding_removed):
		PortfolioManager.holding_removed.disconnect(_on_holding_removed)
	if SkillTree.on_skill_unlocked.is_connected(_on_skill_unlocked_refresh_slots):
		SkillTree.on_skill_unlocked.disconnect(_on_skill_unlocked_refresh_slots)
	if StopTakeSystem.on_stop_take_triggered.is_connected(_on_stop_take_triggered):
		StopTakeSystem.on_stop_take_triggered.disconnect(_on_stop_take_triggered)


## Refreshes slot counter when P1 or P2 is unlocked; enables S/T buttons when TR2 unlocked.
## Implements: design/gdd/skill-tree.md §P1 §P2 §TR2 — immediate UI update on unlock.
func _on_skill_unlocked_refresh_slots(skill_id: String) -> void:
	if skill_id == "P1" or skill_id == "P2" or skill_id == "TR2":
		_refresh()


func _on_valuation_updated(_total: int, _rate: float) -> void:
	_refresh()


func _refresh() -> void:
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	var total: int = summary["total_assets"]
	var rate: float = summary["return_rate"]
	var cash: int = summary["sim_cash"]
	var reserved: int = summary["reserved_cash"]
	var holding_count: int = summary["holding_count"]
	var max_holdings: int = summary["max_holdings"]

	_lbl_total_assets.text = tr("총 평가금액: ₩%s") % _format_number(total)

	_lbl_return_rate.text = "(%+.1f%%)" % rate
	if rate > 0.0:
		_lbl_return_rate.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	elif rate < 0.0:
		_lbl_return_rate.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)
	else:
		_lbl_return_rate.add_theme_color_override("font_color", ThemeSetup.NEUTRAL_GRAY)

	if reserved > 0:
		_lbl_cash_info.text = tr("예수금: ₩%s | 미체결예약: ₩%s") % [
			_format_number(cash), _format_number(reserved)
		]
	else:
		_lbl_cash_info.text = tr("예수금: ₩%s") % _format_number(cash)

	# Slot counter — separate label for P1/P2 skill feedback
	_lbl_slot_counter.text = tr("슬롯: %d/%d") % [holding_count, max_holdings]

	var seed: int = SeasonManager.get_season_start_deposit()
	if seed > 0:
		_lbl_seed_capital.text = tr("시드: ₩%s") % _format_number(seed)
	else:
		_lbl_seed_capital.text = ""

	_refresh_holdings()
	_refresh_transactions()


func _refresh_holdings() -> void:
	var holdings: Array[Dictionary] = PortfolioManager.get_all_holdings()

	# Build the canonical stock_id set for this frame.
	var current_ids: Array[String] = [] as Array[String]
	for h: Dictionary in holdings:
		current_ids.append(h["stock_id"] as String)

	# Detect structural change (add/remove holdings or order change).
	var cached_ids: Array = _holding_rows.keys()
	var structure_changed: bool = current_ids.size() != cached_ids.size()
	if not structure_changed:
		for i: int in range(current_ids.size()):
			if current_ids[i] != cached_ids[i]:
				structure_changed = true
				break

	if structure_changed:
		# Full rebuild — clear and recreate all rows.
		for child: Node in _holdings_container.get_children():
			child.queue_free()
		_holding_rows.clear()

		if holdings.size() == 0:
			var empty: Label = Label.new()
			empty.text = tr("보유 종목 없음. 첫 매수를 시작하세요!")
			ThemeSetup.style_label_dim(empty)
			_holdings_container.add_child(empty)
			return

		for h: Dictionary in holdings:
			var sid: String = h["stock_id"]
			var sid_data: StockData = StockDatabase.get_stock(sid)
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.mouse_filter = Control.MOUSE_FILTER_STOP

			var lbl_stock: Label = Label.new()
			lbl_stock.text = sid_data.get_display_name() if sid_data != null else sid
			lbl_stock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ThemeSetup.style_label_primary(lbl_stock)
			row.add_child(lbl_stock)

			var lbl_qty: Label = Label.new()
			lbl_qty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ThemeSetup.style_label_secondary(lbl_qty)
			row.add_child(lbl_qty)

			var lbl_price: Label = Label.new()
			lbl_price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ThemeSetup.style_label_primary(lbl_price)
			row.add_child(lbl_price)

			var lbl_rate: Label = Label.new()
			lbl_rate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl_rate)

			var lbl_value: Label = Label.new()
			lbl_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ThemeSetup.style_label_primary(lbl_value)
			row.add_child(lbl_value)

			# S/T button —손절/익절 설정. TR2 미해금 시 disabled.
			var btn_st: Button = Button.new()
			btn_st.text = "S/T"
			btn_st.custom_minimum_size.x = 36
			btn_st.focus_mode = Control.FOCUS_NONE
			btn_st.disabled = not SkillTree.is_skill_unlocked("TR2")
			btn_st.tooltip_text = tr("손절/익절 설정 (TR2 해금 필요)") if not SkillTree.is_skill_unlocked("TR2") else tr("손절/익절 설정")
			var captured_sid: String = sid
			btn_st.pressed.connect(func() -> void: _on_stop_take_btn_pressed(captured_sid))
			row.add_child(btn_st)

			var stock_id: String = sid
			row.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton:
					var mb: InputEventMouseButton = event as InputEventMouseButton
					if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
						stock_clicked.emit(stock_id)
			)
			_holdings_container.add_child(row)
			_holding_rows[sid] = {
				"lbl_qty": lbl_qty, "lbl_price": lbl_price,
				"lbl_rate": lbl_rate, "lbl_value": lbl_value,
				"btn_st": btn_st,
			}

	# Update mutable label values (runs every tick — zero Node allocation).
	for h: Dictionary in holdings:
		var sid: String = h["stock_id"]
		if not _holding_rows.has(sid):
			continue
		var refs: Dictionary = _holding_rows[sid]
		refs["lbl_qty"].text = tr("%d주") % h["quantity"]
		var current_price: int = h.get("current_value", 0) / maxi(h.get("quantity", 1), 1)
		refs["lbl_price"].text = FormatUtils.currency(current_price)
		var pnl_pct: float = h.get("unrealized_pnl_pct", 0.0)
		refs["lbl_rate"].text = "%+.1f%%" % pnl_pct
		if pnl_pct > 0.0:
			refs["lbl_rate"].add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
		elif pnl_pct < 0.0:
			refs["lbl_rate"].add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)
		else:
			refs["lbl_rate"].add_theme_color_override("font_color", ThemeSetup.NEUTRAL_GRAY)
		refs["lbl_value"].text = FormatUtils.currency(h.get("current_value", 0))
		# S/T button color: 손절만=빨강, 익절만=초록, 양쪽=주황, 없음=기본
		if refs.has("btn_st"):
			var btn: Button = refs["btn_st"] as Button
			btn.disabled = not SkillTree.is_skill_unlocked("TR2")
			var st: Variant = StopTakeSystem.get_setting(sid)
			if st == null:
				btn.remove_theme_color_override("font_color")
			else:
				var has_sl: bool = (st as Dictionary).get("stop_loss_price") != null
				var has_tp: bool = (st as Dictionary).get("take_profit_price") != null
				if has_sl and has_tp:
					btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.0))  # 주황
				elif has_sl:
					btn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))   # 빨강
				else:
					btn.add_theme_color_override("font_color", Color(0.3, 0.85, 0.4))  # 초록


func _refresh_transactions() -> void:
	for child: Node in _tx_container.get_children():
		child.queue_free()

	var tx_list: Array[Dictionary] = PortfolioManager.get_transaction_history(5)

	if tx_list.size() == 0:
		var empty: Label = Label.new()
		empty.text = tr("거래 내역 없음")
		ThemeSetup.style_label_dim(empty)
		_tx_container.add_child(empty)
		return

	# Show most recent first
	for i: int in range(tx_list.size() - 1, -1, -1):
		var tx: Dictionary = tx_list[i]
		var lbl: Label = Label.new()
		var type_str: String = tr("매수") if tx["type"] == "BUY" else tr("매도")
		var pnl_str: String = ""
		if tx["type"] == "SELL" and tx.get("realized_pnl", 0) != 0:
			pnl_str = " (손익: %+d)" % tx["realized_pnl"]
		var tx_sid: String = tx["stock_id"]
		var tx_stock: StockData = StockDatabase.get_stock(tx_sid)
		var tx_name: String = tx_stock.get_display_name() if tx_stock != null else tx_sid
		lbl.text = tr("틱 %d | %s | %s(%s) %d주 @ ₩%s%s") % [
			tx.get("tick", 0), type_str, tx_name, tx_sid,
			tx["quantity"], _format_number(tx["price"]), pnl_str
		]

		if tx["type"] == "BUY":
			lbl.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
		else:
			lbl.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)

		_tx_container.add_child(lbl)


# ── Utility ──

## Called when the S/T button is pressed for a holding row.
## Opens a simple stop-loss / take-profit setup dialog.
func _on_stop_take_btn_pressed(stock_id: String) -> void:
	if not SkillTree.is_skill_unlocked("TR2"):
		return
	var holding: Variant = PortfolioManager.get_holding(stock_id)
	if holding == null:
		return

	var current: Variant = StopTakeSystem.get_setting(stock_id)
	var current_price: int = PriceEngine.get_current_price(stock_id)
	var qty: int = (holding as Dictionary).get("quantity", 1)
	var sl: Variant = null
	var tp: Variant = null
	if current != null:
		sl = (current as Dictionary).get("stop_loss_price")
		tp = (current as Dictionary).get("take_profit_price")
		qty = (current as Dictionary).get("quantity", qty)

	# Build a simple popup Window for the stop-take form
	var win := Window.new()
	var stock_data: StockData = StockDatabase.get_stock(stock_id)
	var stock_name: String = stock_data.get_display_name() if stock_data != null else stock_id
	win.title = "손절/익절 설정 — %s" % stock_name
	win.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_SCREEN_WITH_MOUSE_FOCUS
	win.size = Vector2i(360, 260)
	win.unresizable = true
	win.exclusive = true

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	win.add_child(vbox)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	win.add_child(margin)
	vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var lbl_price := Label.new()
	lbl_price.text = "현재가: ₩%s" % FormatUtils.number(current_price)
	vbox.add_child(lbl_price)

	var row_sl := HBoxContainer.new()
	var lbl_sl := Label.new()
	lbl_sl.text = "손절가 (원):"
	lbl_sl.custom_minimum_size.x = 100
	row_sl.add_child(lbl_sl)
	var edit_sl := LineEdit.new()
	edit_sl.text = str(sl) if sl != null else ""
	edit_sl.placeholder_text = "미설정"
	edit_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_sl.add_child(edit_sl)
	vbox.add_child(row_sl)

	var row_tp := HBoxContainer.new()
	var lbl_tp := Label.new()
	lbl_tp.text = "익절가 (원):"
	lbl_tp.custom_minimum_size.x = 100
	row_tp.add_child(lbl_tp)
	var edit_tp := LineEdit.new()
	edit_tp.text = str(tp) if tp != null else ""
	edit_tp.placeholder_text = "미설정"
	edit_tp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_tp.add_child(edit_tp)
	vbox.add_child(row_tp)

	var row_qty := HBoxContainer.new()
	var lbl_qty_lbl := Label.new()
	lbl_qty_lbl.text = "수량:"
	lbl_qty_lbl.custom_minimum_size.x = 100
	row_qty.add_child(lbl_qty_lbl)
	var spin_qty := SpinBox.new()
	spin_qty.min_value = 1
	spin_qty.max_value = (holding as Dictionary).get("quantity", 1)
	spin_qty.step = 1
	spin_qty.value = qty
	spin_qty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_qty.add_child(spin_qty)
	vbox.add_child(row_qty)

	var lbl_err := Label.new()
	lbl_err.text = ""
	lbl_err.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	lbl_err.add_theme_font_size_override("font_size", 12)
	vbox.add_child(lbl_err)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var btn_clear := Button.new()
	btn_clear.text = "설정 해제"
	btn_row.add_child(btn_clear)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	var btn_cancel := Button.new()
	btn_cancel.text = "취소"
	btn_row.add_child(btn_cancel)

	var btn_confirm := Button.new()
	btn_confirm.text = "확인"
	btn_row.add_child(btn_confirm)

	get_tree().root.add_child(win)
	win.popup()

	btn_cancel.pressed.connect(func() -> void: win.queue_free())
	win.close_requested.connect(func() -> void: win.queue_free())

	btn_clear.pressed.connect(func() -> void:
		StopTakeSystem.clear_condition(stock_id)
		win.queue_free()
		_refresh()
	)

	btn_confirm.pressed.connect(func() -> void:
		var sl_text: String = edit_sl.text.strip_edges()
		var tp_text: String = edit_tp.text.strip_edges()
		var sl_val: Variant = null
		var tp_val: Variant = null

		if sl_text != "" and sl_text != "미설정":
			if not sl_text.is_valid_int():
				lbl_err.text = "손절가는 정수여야 합니다"
				return
			sl_val = sl_text.to_int()

		if tp_text != "" and tp_text != "미설정":
			if not tp_text.is_valid_int():
				lbl_err.text = "익절가는 정수여야 합니다"
				return
			tp_val = tp_text.to_int()

		if sl_val != null and tp_val != null and (sl_val as int) >= (tp_val as int):
			lbl_err.text = "손절가는 익절가보다 낮아야 합니다"
			return

		if sl_val != null and (sl_val as int) >= current_price:
			lbl_err.text = "손절가는 현재가보다 낮아야 합니다"
			return

		if tp_val != null and (tp_val as int) <= current_price:
			lbl_err.text = "익절가는 현재가보다 높아야 합니다"
			return

		var set_qty: int = int(spin_qty.value)
		if not StopTakeSystem.set_condition(stock_id, sl_val, tp_val, set_qty):
			lbl_err.text = "설정 실패 (TR2 해금 여부 및 한도 확인)"
			return

		win.queue_free()
		_refresh()
	)


## S7-07: Shows "SL 발동" / "TP 발동" badge briefly after auto-sell.
## reason is "STOP_LOSS" or "TAKE_PROFIT" (from StopTakeSystem.on_stop_take_triggered).
func _on_stop_take_triggered(stock_id: String, reason: String, filled_price: int) -> void:
	var stock_data: StockData = StockDatabase.get_stock(stock_id)
	var stock_name: String = stock_data.get_display_name() if stock_data != null else stock_id
	var badge_label: String = tr("SL 발동") if reason == "STOP_LOSS" else tr("TP 발동")
	var badge_color: Color = Color(0.9, 0.3, 0.3) if reason == "STOP_LOSS" else Color(0.3, 0.85, 0.4)
	_trigger_badge.text = tr("● %s %s — ₩%s에 자동 매도") % [stock_name, badge_label, _format_number(filled_price)]
	_trigger_badge.add_theme_color_override("font_color", badge_color)
	_trigger_badge.visible = true
	if _badge_tween and _badge_tween.is_valid():
		_badge_tween.kill()
	_badge_tween = create_tween()
	_badge_tween.tween_interval(4.0)
	_badge_tween.tween_callback(func() -> void: _trigger_badge.visible = false)


## Delegates to FormatUtils.number() — single source of truth (TD-04 note).
func _format_number(value: int) -> String:
	return FormatUtils.number(value)
