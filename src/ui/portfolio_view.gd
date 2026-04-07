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
var _holdings_container: VBoxContainer
var _tx_container: VBoxContainer

# ── Lifecycle ──

func _ready() -> void:
	_build_ui()
	PortfolioManager.valuation_updated.connect(_on_valuation_updated)
	PortfolioManager.holding_added.connect(_on_holding_added)
	PortfolioManager.holding_removed.connect(_on_holding_removed)
	tree_exiting.connect(_disconnect_signals)


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

	var sep: HSeparator = HSeparator.new()
	add_child(sep)

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

	for col: String in [tr("종목"), tr("수량"), tr("현재가"), tr("수익률"), tr("평가금액")]:
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

	_lbl_total_assets.text = tr("총 자산: ₩%s") % _format_number(total)

	_lbl_return_rate.text = "(%+.1f%%)" % rate
	if rate > 0.0:
		_lbl_return_rate.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	elif rate < 0.0:
		_lbl_return_rate.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)
	else:
		_lbl_return_rate.add_theme_color_override("font_color", ThemeSetup.NEUTRAL_GRAY)

	if reserved > 0:
		_lbl_cash_info.text = tr("현금: ₩%s | 예약: ₩%s | %d/%d종목") % [
			_format_number(cash), _format_number(reserved),
			holding_count, max_holdings
		]
	else:
		_lbl_cash_info.text = tr("현금: ₩%s | %d/%d종목") % [
			_format_number(cash), holding_count, max_holdings
		]

	_refresh_holdings()
	_refresh_transactions()


func _refresh_holdings() -> void:
	for child: Node in _holdings_container.get_children():
		child.queue_free()

	var holdings: Array[Dictionary] = PortfolioManager.get_all_holdings()

	if holdings.size() == 0:
		var empty: Label = Label.new()
		empty.text = tr("보유 종목 없음. 첫 매수를 시작하세요!")
		ThemeSetup.style_label_dim(empty)
		_holdings_container.add_child(empty)
		return

	for h: Dictionary in holdings:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_STOP

		# Stock ID
		var sid: String = h["stock_id"]
		var lbl_stock: Label = Label.new()
		lbl_stock.text = sid
		lbl_stock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeSetup.style_label_primary(lbl_stock)
		row.add_child(lbl_stock)

		# Quantity
		var lbl_qty: Label = Label.new()
		lbl_qty.text = tr("%d주") % h["quantity"]
		lbl_qty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeSetup.style_label_secondary(lbl_qty)
		row.add_child(lbl_qty)

		# Current price (derived from cached valuation, no direct PriceEngine call)
		var current_price: int = h.get("current_value", 0) / maxi(h.get("quantity", 1), 1)
		var lbl_price: Label = Label.new()
		lbl_price.text = "₩%s" % _format_number(current_price)
		lbl_price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeSetup.style_label_primary(lbl_price)
		row.add_child(lbl_price)

		# Return rate
		var pnl_pct: float = h.get("unrealized_pnl_pct", 0.0)
		var lbl_rate: Label = Label.new()
		lbl_rate.text = "%+.1f%%" % pnl_pct
		lbl_rate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if pnl_pct > 0.0:
			lbl_rate.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
		elif pnl_pct < 0.0:
			lbl_rate.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)
		else:
			lbl_rate.add_theme_color_override("font_color", ThemeSetup.NEUTRAL_GRAY)
		row.add_child(lbl_rate)

		# Value
		var value: int = h.get("current_value", 0)
		var lbl_value: Label = Label.new()
		lbl_value.text = "₩%s" % _format_number(value)
		lbl_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeSetup.style_label_primary(lbl_value)
		row.add_child(lbl_value)

		# Click to select stock
		var stock_id: String = sid
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton:
				var mb: InputEventMouseButton = event as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					stock_clicked.emit(stock_id)
		)

		_holdings_container.add_child(row)


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
		lbl.text = tr("틱 %d | %s | %s %d주 @ ₩%s%s") % [
			tx.get("tick", 0), type_str, tx["stock_id"],
			tx["quantity"], _format_number(tx["price"]), pnl_str
		]

		if tx["type"] == "BUY":
			lbl.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
		else:
			lbl.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)

		_tx_container.add_child(lbl)


# ── Utility ──

## Delegates to FormatUtils.number() — single source of truth (TD-04 note).
func _format_number(value: int) -> String:
	return FormatUtils.number(value)
