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

## Emitted when the player clicks the league HUD and requests the F2 tab.
## MainScreen connects to this to handle tab switch (ADR-006: TradingScreen does not call
## GameClock.pause_request directly).
signal league_tab_requested()
## TD-03: Emitted instead of calling GameClock.toggle_pause() directly.
signal pause_toggle_requested()
## TD-03: Emitted instead of calling GameClock.set_speed() directly.
signal speed_change_requested(multiplier: float)

# ── State ──

var _ui_state: UIState = UIState.LOADING
var _selected_stock_id: String = ""
var _order_side: String = "BUY"  ## "BUY" or "SELL"
var _order_type: String = "MARKET"  ## "MARKET" or "LIMIT"
var _stock_ids: Array[String] = []  ## Ordered list for keyboard shortcuts
var _prev_close_prices: Dictionary = {}  ## stock_id -> int (previous day close)
var _settlement_queue: Array[String] = []  ## Sequential reports: "daily", "weekly", "season"

# ── Node References (assigned in _ready) ──

# Status bar
var _lbl_season_info: Label
var _lbl_tick_progress: Label
var _lbl_league_tier: Label    ## 티어명 (e.g. "브론즈", "프리마켓")
var _lbl_season_return: Label  ## 시즌 수익률 (e.g. "시즌 +12.3%")
var _lbl_weekly_return: Label  ## 주간 수익률 (e.g. "주간 +2.1%")
var _progress_bar: ProgressBar
var _lbl_speed: Label
var _lbl_market_index: Label
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
var _radio_market: Button
var _radio_limit: Button
var _spin_quantity: SpinBox
var _spin_limit_price: SpinBox
var _limit_price_row: HBoxContainer
var _lbl_estimated_amount: Label
var _btn_max_qty: Button
var _btn_submit_order: Button
var _btn_cancel_order: Button
var _lbl_order_error: Label
var _error_tween: Tween  ## 주문 에러 메시지 자동 제거 Tween — 누적 방지용 참조 보관
var _pending_orders_container: VBoxContainer

# Bottom tabs
var _btn_tab_news: Button
var _btn_tab_portfolio: Button
var _btn_tab_alerts: Button
var _news_panel: Control
var _portfolio_panel: Control
var _alerts_panel: Control  ## VI/CB alerts panel
var _alerts_container: VBoxContainer  ## VI/CB card list
var _alerts_scroll: ScrollContainer
var _lbl_alerts_badge: Label  ## Unread count on tab

# Chart renderer
var _chart_renderer: Control  ## ChartRenderer instance

# Overlays
var _pause_overlay: Panel
var _settlement_panel: PanelContainer
var _lbl_settlement_title: Label
var _lbl_settlement_body: RichTextLabel
var _btn_settlement_confirm: Button

# Progression UI
var _xp_bar: XpBar
var _level_up_banner: LevelUpBanner
var _skill_tree_overlay: SkillTreeOverlay
var _pending_level_up: Dictionary = {}  ## {old_level, new_level, sp} — deferred until settlement closes
var _last_xp_gained: int = 0   ## XP gained in most recent on_xp_gained signal
var _last_xp_source: String = ""  ## Source of most recent XP gain ("daily_bonus", "season_bonus")
var _weekly_xp_gained: int = 0   ## Accumulated XP gained this week (for weekly report)
var _lbl_sp_alert: Label  ## PRE_MARKET SP reminder (GDD Rule 6)

# Speed buttons
var _btn_speed_1x: Button
var _btn_speed_2x: Button
var _btn_speed_4x: Button
var _btn_pause: Button

# Toast notifications
var _toast_container: VBoxContainer  ## Bottom-center stacking container

# Tab unread state
var _news_unread: int = 0
var _portfolio_unread: int = 0
var _active_tab: int = 0

# ── Lifecycle ──

func _ready() -> void:
	_stock_ids = StockDatabase.get_all_stock_ids()
	_init_prev_close()
	_build_ui()
	_connect_signals()
	_set_order_side("BUY")
	_set_order_type("MARKET")
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
	OrderEngine.on_order_expired.connect(_on_order_expired)
	PortfolioManager.valuation_updated.connect(_on_valuation_updated)
	CurrencySystem.sim_cash_changed.connect(_on_sim_cash_changed)
	XpSystem.on_level_up.connect(_on_level_up)
	XpSystem.on_xp_gained.connect(_on_xp_gained)
	GameClock.on_market_close.connect(_on_market_close_refresh_settlement)
	GameClock.on_season_end.connect(_on_season_end_refresh_settlement)
	NewsEventSystem.on_news_display.connect(_on_system_event_alert)
	SkillTree.on_skill_unlocked.connect(_on_skill_unlocked)
	NewsEventSystem.on_news_display.connect(_on_news_toast)


func _sync_ui_state_from_clock() -> void:
	var ms: GameClock.MarketState = GameClock.get_market_state()
	match ms:
		GameClock.MarketState.PRE_MARKET:
			_set_ui_state(UIState.PRE_MARKET)
		GameClock.MarketState.MARKET_OPEN:
			_set_ui_state(UIState.MARKET_OPEN)
		GameClock.MarketState.PAUSED:
			_set_ui_state(UIState.PAUSED)
		GameClock.MarketState.MARKET_CLOSED, GameClock.MarketState.DAY_TRANSITION:
			_settlement_queue.clear()
			_settlement_queue.append("daily")
			_set_ui_state(UIState.SETTLEMENT)
		GameClock.MarketState.WEEK_END:
			_settlement_queue.clear()
			_settlement_queue.append("weekly")
			_set_ui_state(UIState.SETTLEMENT)
		GameClock.MarketState.SEASON_END:
			_settlement_queue.clear()
			_settlement_queue.append("season")
			_set_ui_state(UIState.SETTLEMENT)


# ── Input Handling (GDD Rule 7) ──

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
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
		KEY_K:
			if not key_event.shift_pressed:
				_toggle_skill_tree()
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
	if _lbl_sp_alert:
		_lbl_sp_alert.visible = false

	# Speed controls: visible only during MARKET_OPEN / PAUSED
	var speed_visible: bool = _ui_state in [UIState.MARKET_OPEN, UIState.PAUSED]
	_btn_speed_1x.visible = speed_visible
	_btn_speed_2x.visible = speed_visible
	_btn_speed_4x.visible = speed_visible
	_btn_pause.visible = speed_visible
	_lbl_speed.visible = speed_visible

	match _ui_state:
		UIState.PRE_MARKET:
			_btn_market_open.visible = true
			# TD-08: first PRE_MARKET shows "시즌 시작", subsequent days show "장 시작"
			if SeasonManager.is_season_active():
				_btn_market_open.text = "장 시작 Enter"
			else:
				_btn_market_open.text = "시즌 시작 Enter"
			_btn_submit_order.text = "주문 예약 Enter"
			# GDD Rule 6: PRE_MARKET SP reminder
			_update_sp_alert()
			# Clear alerts for new day
			_clear_alerts()
		UIState.MARKET_OPEN:
			_btn_submit_order.text = "주문 실행 Enter"
			_update_speed_display()
		UIState.PAUSED:
			_pause_overlay.visible = true
			_btn_submit_order.text = "주문 실행 Enter"
		UIState.SETTLEMENT:
			_btn_submit_order.disabled = true
			# Defer so all state changes (MARKET_CLOSED → WEEK_END → SEASON_END)
			# finish queuing before we show the first report.
			_show_next_settlement.call_deferred()

	_update_status_bar()


# ── Signal Handlers ──

## PRE_MARKET 버튼 핸들러. 시즌 미시작 시 SeasonManager.start_season() 호출,
## 시즌 진행 중이면 GameClock.confirm_market_open() 호출 (TD-08).
func _on_btn_market_open_pressed() -> void:
	if SeasonManager.is_season_active():
		GameClock.confirm_market_open()
	else:
		SeasonManager.start_season()


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
			_refresh_limit_price_bounds()
			_set_ui_state(UIState.PRE_MARKET)
		GameClock.MarketState.MARKET_OPEN:
			_set_ui_state(UIState.MARKET_OPEN)
		GameClock.MarketState.PAUSED:
			_set_ui_state(UIState.PAUSED)
		GameClock.MarketState.MARKET_CLOSED:
			_settlement_queue.clear()
			_settlement_queue.append("daily")
			_set_ui_state(UIState.SETTLEMENT)
		GameClock.MarketState.DAY_TRANSITION:
			pass  # Stay in SETTLEMENT
		GameClock.MarketState.WEEK_END:
			_settlement_queue.append("weekly")
		GameClock.MarketState.SEASON_END:
			_settlement_queue.append("season")


func _on_market_close() -> void:
	# Save closing prices as prev_close for next day
	for sid: String in _stock_ids:
		_prev_close_prices[sid] = PriceEngine.get_current_price(sid)


func _on_order_filled(order: Dictionary) -> void:
	_flash_order_panel(order["side"])
	_update_pending_orders()
	_update_order_panel_price()
	# Update portfolio tab badge if not viewing portfolio
	if _active_tab != 2:
		_portfolio_unread += 1
		_btn_tab_portfolio.text = "포트폴리오 (%d)" % _portfolio_unread


func _on_order_rejected(order: Dictionary) -> void:
	_show_order_error(order.get("reject_reason", "주문 거부됨"))
	_update_pending_orders()


func _on_order_cancelled(_order: Dictionary) -> void:
	_update_pending_orders()


func _on_order_expired(_order: Dictionary) -> void:
	_update_pending_orders()


func _on_valuation_updated(_total: int, _rate: float) -> void:
	_update_status_bar()


func _on_sim_cash_changed(_amount: int, _delta: int) -> void:
	_update_status_bar()
	_update_order_panel_price()


func _on_level_up(new_level: int, _skill_points: int) -> void:
	# Defer level-up banner until settlement popup closes (GDD Rule 3)
	# Guard: if banner is already showing, accumulate into pending for next cycle
	if _level_up_banner and _level_up_banner.is_showing():
		# Banner already visible — ignore (multi-level in same frame handled below)
		return

	if _pending_level_up.is_empty():
		_pending_level_up = {
			"old_level": new_level - 1,
			"new_level": new_level,
			"sp": 1,
		}
	else:
		# Multi-level-up: accumulate
		_pending_level_up["new_level"] = new_level
		_pending_level_up["sp"] += 1


func _on_xp_gained(amount: int, _new_total: int, source: String) -> void:
	_last_xp_gained = amount
	_last_xp_source = source
	if source == "daily_bonus":
		_weekly_xp_gained += amount
	if _xp_bar:
		_xp_bar.update_display()


## Refresh settlement body after XP is granted (fires after XpSystem._on_market_close).
func _on_market_close_refresh_settlement() -> void:
	if _ui_state == UIState.SETTLEMENT and _settlement_panel.visible:
		# Rebuild the currently visible report with updated XP info
		_show_settlement_report()


## Refresh season result after XP is granted (fires after XpSystem._on_season_end).
func _on_season_end_refresh_settlement() -> void:
	if _ui_state == UIState.SETTLEMENT and _settlement_panel.visible:
		# XP was just granted for season — but we might still be on daily/weekly report.
		# The season report will pick up XP when it's shown from the queue.
		pass


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
	# Style active tab with full color, inactive with dim
	if side == "BUY":
		ThemeSetup.apply_buy_button(_btn_buy_tab)
		ThemeSetup.apply_button_theme(_btn_sell_tab)
	else:
		ThemeSetup.apply_button_theme(_btn_buy_tab)
		ThemeSetup.apply_sell_button(_btn_sell_tab)
	_update_order_panel_for_stock()


func _set_order_type(type: String) -> void:
	# TR1 gate: limit orders require skill unlock
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


func _update_order_panel_for_stock() -> void:
	if _selected_stock_id == "":
		return
	var stock: StockData = StockDatabase.get_stock(_selected_stock_id)
	if stock == null:
		return
	_lbl_order_stock_name.text = "%s (%s)" % [stock.name_ko, _selected_stock_id]
	_refresh_limit_price_bounds()
	_spin_limit_price.value = PriceEngine.get_current_price(_selected_stock_id)
	_update_order_panel_price()
	_lbl_order_error.text = ""
	_spin_quantity.value = 0


func _refresh_limit_price_bounds() -> void:
	if _selected_stock_id == "":
		return
	var limits: Dictionary = PriceEngine.get_daily_limits(_selected_stock_id)
	if limits.size() > 0:
		_spin_limit_price.min_value = limits["lower"]
		_spin_limit_price.max_value = limits["upper"]
	var price: int = PriceEngine.get_current_price(_selected_stock_id)
	_spin_limit_price.step = PriceEngine.get_tick_size(price)


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


func _on_chart_price_clicked(price: int) -> void:
	# Switch to limit order and set price
	if not SkillTree.is_skill_unlocked("TR1"):
		return
	_set_order_type("LIMIT")
	_spin_limit_price.value = float(price)
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
	# Kill previous tween before creating a new one (prevents accumulation)
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


# ── Pending Orders ──

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
		var row: HBoxContainer = HBoxContainer.new()
		var side_str: String = "매수" if order["side"] == "BUY" else "매도"
		var info: Label = Label.new()
		info.text = "%s %s %s×%d주" % [
			side_str, order["stock_id"],
			_format_number(order.get("limit_price", PriceEngine.get_current_price(order["stock_id"]))),
			order["quantity"]
		]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeSetup.style_label_primary(info)
		row.add_child(info)

		var cancel_btn: Button = Button.new()
		cancel_btn.text = "취소"
		ThemeSetup.apply_button_theme(cancel_btn)
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

	# Layout: [0]=marker [1]=ticker [2]=price [3]=change [4]=held
	var children: Array[Node] = []
	for child: Node in row.get_children():
		children.append(child)

	if children.size() < 5:
		return

	# Selection marker
	var lbl_marker: Label = children[0] as Label
	lbl_marker.text = "▶" if is_selected else "  "

	# Price
	var lbl_price: Label = children[2] as Label
	lbl_price.text = "₩%s" % _format_number(price)

	# Change %
	var lbl_change: Label = children[3] as Label
	var arrow: String = "▲" if change_pct > 0.0 else ("▼" if change_pct < 0.0 else "─")
	lbl_change.text = "%s%+.1f%%" % [arrow, change_pct]
	if change_pct > 0.0:
		lbl_change.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	elif change_pct < 0.0:
		lbl_change.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)
	else:
		lbl_change.add_theme_color_override("font_color", ThemeSetup.NEUTRAL_GRAY)

	# Held marker
	var lbl_held: Label = children[4] as Label
	lbl_held.text = "★" if is_held else ""

	# Row background highlight for selected
	if is_selected:
		var sel_style: StyleBoxFlat = ThemeSetup.make_panel_style(ThemeSetup.BG_SELECTED, 3, ThemeSetup.BORDER_BRIGHT)
		row.add_theme_stylebox_override("panel", sel_style)
	else:
		row.remove_theme_stylebox_override("panel")


func _update_stock_list_highlight() -> void:
	var items: Array[Node] = []
	for child: Node in _stock_list_container.get_children():
		items.append(child)

	for i: int in range(_stock_ids.size()):
		if i >= items.size():
			break
		var sid: String = _stock_ids[i]
		var row: HBoxContainer = items[i] as HBoxContainer
		var is_selected: bool = (sid == _selected_stock_id)
		var marker: Label = row.get_child(0) as Label
		marker.text = "▶" if is_selected else "  "
		if is_selected:
			var sel_style: StyleBoxFlat = ThemeSetup.make_panel_style(ThemeSetup.BG_SELECTED, 3, ThemeSetup.BORDER_BRIGHT)
			row.add_theme_stylebox_override("panel", sel_style)
		else:
			row.remove_theme_stylebox_override("panel")


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
		_lbl_total_assets.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	elif rate < 0.0:
		_lbl_total_assets.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)
	else:
		_lbl_total_assets.add_theme_color_override("font_color", ThemeSetup.NEUTRAL_GRAY)

	# Cash + holdings count display
	var cash: int = CurrencySystem.get_sim_cash()
	var reserved: int = OrderEngine.get_total_reserved_cash()
	var holdings_count: int = PortfolioManager.get_all_holdings().size()
	var max_holdings: int = SkillTree.get_max_holdings()
	if reserved > 0:
		_lbl_cash.text = "시드: ₩%s (예약: ₩%s) | 보유 %d/%d" % [
			_format_number(cash), _format_number(reserved), holdings_count, max_holdings]
	else:
		_lbl_cash.text = "시드: ₩%s | 보유 %d/%d" % [_format_number(cash), holdings_count, max_holdings]

	# Market index display
	var index_val: float = PriceEngine.get_market_index()
	var index_change: float = PriceEngine.get_index_change_pct()
	var sign_str: String = "+" if index_change >= 0.0 else ""
	_lbl_market_index.text = "지수 %s (%s%.2f%%)" % [
		_format_number(roundi(index_val)), sign_str, index_change
	]
	if index_change > 0.0:
		_lbl_market_index.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	elif index_change < 0.0:
		_lbl_market_index.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)
	else:
		_lbl_market_index.add_theme_color_override("font_color", ThemeSetup.NEUTRAL_GRAY)

	_update_speed_display()

	# League HUD (SeasonManager getters — safe to call any time)
	var is_free: bool = SeasonManager.get_is_free_market()
	if is_free:
		_lbl_league_tier.text = "프리마켓"
		_lbl_league_tier.add_theme_color_override("font_color", ThemeSetup.NEUTRAL_GRAY)
	else:
		_lbl_league_tier.text = SeasonManager.get_tier_name(SeasonManager.get_current_tier())
		_lbl_league_tier.add_theme_color_override("font_color", ThemeSetup.NEUTRAL_GRAY)

	var season_ret: float = SeasonManager.get_season_return_pct()
	var s_sign: String = "+" if season_ret >= 0.0 else ""
	_lbl_season_return.text = "시즌 %s%.1f%%" % [s_sign, season_ret]
	if season_ret > 0.0:
		_lbl_season_return.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	elif season_ret < 0.0:
		_lbl_season_return.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)
	else:
		_lbl_season_return.add_theme_color_override("font_color", ThemeSetup.NEUTRAL_GRAY)

	var weekly_ret: float = SeasonManager.get_weekly_return_pct()
	var w_sign: String = "+" if weekly_ret >= 0.0 else ""
	_lbl_weekly_return.text = "주간 %s%.1f%%" % [w_sign, weekly_ret]
	if weekly_ret > 0.0:
		_lbl_weekly_return.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	elif weekly_ret < 0.0:
		_lbl_weekly_return.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)
	else:
		_lbl_weekly_return.add_theme_color_override("font_color", ThemeSetup.NEUTRAL_GRAY)


func _update_speed_display() -> void:
	if _ui_state == UIState.PAUSED:
		_lbl_speed.text = "⏸ 일시정지"
	elif not _lbl_speed.visible:
		return  # Hidden in PRE_MARKET/SETTLEMENT — skip update
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
	speed_change_requested.emit(multiplier)
	_update_speed_display()
	_update_speed_buttons(multiplier)


func _update_speed_buttons(multiplier: float) -> void:
	var btns: Array[Button] = [_btn_speed_1x, _btn_speed_2x, _btn_speed_4x]
	var vals: Array[float] = [1.0, 2.0, 4.0]
	for i: int in range(btns.size()):
		if absf(vals[i] - multiplier) < 0.1:
			ThemeSetup.apply_accent_button(btns[i])
		else:
			ThemeSetup.apply_button_theme(btns[i])


func _handle_pause_toggle() -> void:
	if _ui_state == UIState.MARKET_OPEN or _ui_state == UIState.PAUSED:
		pause_toggle_requested.emit()


func _handle_enter_key() -> void:
	if _ui_state == UIState.PRE_MARKET:
		GameClock.confirm_market_open()
	elif _ui_state == UIState.SETTLEMENT:
		_confirm_settlement()
	elif _ui_state == UIState.MARKET_OPEN or _ui_state == UIState.PAUSED:
		if int(_spin_quantity.value) > 0:
			_submit_order()


func _handle_escape() -> void:
	# Priority: banner > skill tree > settlement > clear order
	if _level_up_banner and _level_up_banner.is_showing():
		_level_up_banner.hide_banner()
	elif _skill_tree_overlay and _skill_tree_overlay.is_open():
		_skill_tree_overlay.close()
	elif _settlement_panel.visible:
		_confirm_settlement()
	else:
		# Clear order input
		_spin_quantity.value = 0
		_lbl_order_error.text = ""


func _toggle_skill_tree() -> void:
	if _skill_tree_overlay.is_open():
		_skill_tree_overlay.close()
	else:
		# Don't open during settlement
		if _settlement_panel.visible:
			return
		_skill_tree_overlay.open()


## GDD Rule 6: Show SP reminder during PRE_MARKET when SP > 0.
func _update_sp_alert() -> void:
	if not _lbl_sp_alert:
		return
	var sp: int = XpSystem.get_available_skill_points()
	if sp > 0:
		_lbl_sp_alert.text = "미사용 스킬 포인트 %d개 — 스킬 트리 열기 K" % sp
		_lbl_sp_alert.visible = true
	else:
		_lbl_sp_alert.visible = false


func _toggle_bottom_tab() -> void:
	# Cycle: 뉴스 → VI/CB → 포트폴리오 → 뉴스
	if _news_panel.visible:
		_switch_bottom_tab(1)
	elif _alerts_panel.visible:
		_switch_bottom_tab(2)
	else:
		_switch_bottom_tab(0)


func _switch_bottom_tab(index: int) -> void:
	_active_tab = index
	_news_panel.visible = (index == 0)
	_alerts_panel.visible = (index == 1)
	_portfolio_panel.visible = (index == 2)
	# Clear unread badge for the viewed tab
	if index == 0:
		_news_unread = 0
		_btn_tab_news.text = "뉴스"
	elif index == 1:
		_btn_tab_alerts.text = "VI/CB"
	elif index == 2:
		_portfolio_unread = 0
		_btn_tab_portfolio.text = "포트폴리오"
	# Apply active/inactive tab styles (clear any leftover color overrides first)
	var tabs: Array[Button] = [_btn_tab_news, _btn_tab_alerts, _btn_tab_portfolio]
	for i: int in range(tabs.size()):
		tabs[i].remove_theme_color_override("font_color")
		tabs[i].remove_theme_color_override("font_hover_color")
		tabs[i].remove_theme_color_override("font_pressed_color")
		if i == index:
			ThemeSetup.apply_tab_active(tabs[i])
		else:
			ThemeSetup.apply_tab_inactive(tabs[i])


# ── Settlement / Season Result ──

func _show_settlement_report() -> void:
	_settlement_panel.visible = true
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	var day: int = GameClock.get_current_day()
	_lbl_settlement_title.text = "일일 정산  Day %d" % (day + 1)

	var rate: float = summary["return_rate"]
	var rate_hex: String = "EB3833" if rate >= 0.0 else "2E6BE6"
	var rate_sign: String = "+" if rate >= 0.0 else ""
	var gold_hex: String = "D9B320"

	# Section 1: Portfolio summary
	var bbcode: String = ""
	bbcode += "[b]총 자산[/b]  [color=#%s]₩%s[/color]\n" % [rate_hex, _format_number(summary["total_assets"])]
	bbcode += "[b]수익률[/b]   [color=#%s]%s%.2f%%[/color]\n" % [rate_hex, rate_sign, rate]
	bbcode += "[b]현  금[/b]   ₩%s\n" % _format_number(summary["sim_cash"])
	bbcode += "[b]보유종목[/b] %d개\n" % summary["holding_count"]

	# Section 2: Holdings detail (if any)
	var holdings: Array[Dictionary] = PortfolioManager.get_all_holdings()
	if holdings.size() > 0:
		bbcode += "\n"
		for h: Dictionary in holdings:
			var stock: StockData = StockDatabase.get_stock(h["stock_id"])
			var name_str: String = "%s(%s)" % [stock.name_ko, stock.stock_id] if stock else h["stock_id"]
			var pnl_pct: float = h.get("unrealized_pnl_pct", 0.0)
			var h_hex: String = "EB3833" if pnl_pct >= 0.0 else "2E6BE6"
			var h_sign: String = "+" if pnl_pct >= 0.0 else ""
			bbcode += "  %s  [color=#%s]%s%.1f%%[/color]\n" % [name_str, h_hex, h_sign, pnl_pct]

	# Section 3: Today's trades count
	var today_day: int = GameClock.get_current_day()
	var txs: Array[Dictionary] = PortfolioManager.get_transaction_history(100)
	var today_buys: int = 0
	var today_sells: int = 0
	var today_realized: int = 0
	for tx: Dictionary in txs:
		if tx.get("day", -1) == today_day:
			if tx["type"] == "BUY":
				today_buys += 1
			elif tx["type"] == "SELL":
				today_sells += 1
				today_realized += tx.get("realized_pnl", 0)
	if today_buys > 0 or today_sells > 0:
		bbcode += "\n[b]오늘의 거래[/b]  매수 %d건 · 매도 %d건" % [today_buys, today_sells]
		if today_realized != 0:
			var real_hex: String = "EB3833" if today_realized > 0 else "2E6BE6"
			bbcode += "\n[b]실현 손익[/b]  [color=#%s]%+d[/color]" % [real_hex, today_realized]

	# Section 4: XP (gold section)
	bbcode += "\n\n[color=#%s]━━━ 경험치 ━━━[/color]\n" % gold_hex
	if _last_xp_gained > 0 and _last_xp_source == "daily_bonus":
		bbcode += "[color=#%s][b]+%d XP[/b] 획득[/color]\n" % [gold_hex, _last_xp_gained]
	else:
		bbcode += "거래 없음 — XP 미부여\n"

	var level: int = XpSystem.get_current_level()
	var cur_xp: int = XpSystem.get_total_xp() - XpSystem.get_cumulative_xp_for_level(level)
	var need_xp: int = XpSystem.get_cumulative_xp_for_level(level + 1) - XpSystem.get_cumulative_xp_for_level(level)
	bbcode += "[color=#%s]Lv.%d[/color]  %d / %d XP" % [gold_hex, level, cur_xp, need_xp]

	var sp: int = XpSystem.get_available_skill_points()
	if sp > 0:
		bbcode += "  [color=#%s]SP %d 사용 가능[/color]" % [gold_hex, sp]

	_lbl_settlement_body.text = bbcode
	if _settlement_queue.size() > 0:
		_btn_settlement_confirm.text = "다음 →  Enter"
	else:
		_btn_settlement_confirm.text = "확인  Enter"


func _show_weekly_report() -> void:
	_settlement_panel.visible = true
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	var week: int = GameClock.get_current_week() + 1
	var day: int = GameClock.get_current_day()
	_lbl_settlement_title.text = "주간 리포트  Week %d" % week

	var rate: float = summary["return_rate"]
	var rate_hex: String = "EB3833" if rate >= 0.0 else "2E6BE6"
	var rate_sign: String = "+" if rate >= 0.0 else ""
	var gold_hex: String = "D9B320"

	var bbcode: String = ""

	# Section 1: Portfolio status
	bbcode += "[b]총 자산[/b]  [color=#%s]₩%s[/color]\n" % [rate_hex, _format_number(summary["total_assets"])]
	bbcode += "[b]시즌 수익률[/b] [color=#%s]%s%.2f%%[/color]\n" % [rate_hex, rate_sign, rate]
	bbcode += "[b]현  금[/b]   ₩%s\n" % _format_number(summary["sim_cash"])
	bbcode += "[b]보유종목[/b] %d개\n" % summary["holding_count"]

	# Section 2: Weekly trade summary (this week = day range)
	var week_start_day: int = day - (GameClock.DAYS_PER_WEEK - 1)
	var all_txs: Array[Dictionary] = PortfolioManager.get_transaction_history(999)
	var week_buys: int = 0
	var week_sells: int = 0
	var week_realized: int = 0
	for tx: Dictionary in all_txs:
		var tx_day: int = tx.get("day", -1)
		if tx_day >= week_start_day and tx_day <= day:
			if tx["type"] == "BUY":
				week_buys += 1
			elif tx["type"] == "SELL":
				week_sells += 1
				week_realized += tx.get("realized_pnl", 0)

	bbcode += "\n[b]━━━ 주간 거래 요약 ━━━[/b]\n"
	bbcode += "[b]매수[/b] %d건  [b]매도[/b] %d건  [b]합계[/b] %d건\n" % [week_buys, week_sells, week_buys + week_sells]
	if week_realized != 0:
		var real_hex: String = "EB3833" if week_realized > 0 else "2E6BE6"
		bbcode += "[b]주간 실현 손익[/b]  [color=#%s]₩%s[/color]\n" % [real_hex, _format_number(week_realized)]
	else:
		bbcode += "[b]주간 실현 손익[/b]  ₩0\n"

	# Section 3: Holdings performance
	var holdings: Array[Dictionary] = PortfolioManager.get_all_holdings()
	if holdings.size() > 0:
		bbcode += "\n[b]━━━ 보유 종목 현황 ━━━[/b]\n"
		for h: Dictionary in holdings:
			var stock: StockData = StockDatabase.get_stock(h["stock_id"])
			var name_str: String = "%s(%s)" % [stock.name_ko, stock.stock_id] if stock else h["stock_id"]
			var pnl_pct: float = h.get("unrealized_pnl_pct", 0.0)
			var h_hex: String = "EB3833" if pnl_pct >= 0.0 else "2E6BE6"
			var h_sign: String = "+" if pnl_pct >= 0.0 else ""
			bbcode += "  %s  [color=#%s]%s%.1f%%[/color]\n" % [name_str, h_hex, h_sign, pnl_pct]

	# Section 4: Next week theme hint
	var theme: Dictionary = NewsEventSystem.get_season_theme()
	if theme.size() > 0:
		var hint: String = theme.get("hint_text", "")
		if hint != "":
			bbcode += "\n[b]━━━ 다음 주 시장 전망 ━━━[/b]\n"
			bbcode += "[color=#%s]💡 %s[/color]\n" % [gold_hex, hint]

	# Section 5: Weekly XP
	bbcode += "\n[color=#%s]━━━ 경험치 ━━━[/color]\n" % gold_hex
	if _weekly_xp_gained > 0:
		bbcode += "[color=#%s][b]+%d XP[/b] 주간 획득[/color]\n" % [gold_hex, _weekly_xp_gained]
	else:
		bbcode += "거래 없음 — XP 미부여\n"

	var level: int = XpSystem.get_current_level()
	var cur_xp: int = XpSystem.get_total_xp() - XpSystem.get_cumulative_xp_for_level(level)
	var need_xp: int = XpSystem.get_cumulative_xp_for_level(level + 1) - XpSystem.get_cumulative_xp_for_level(level)
	bbcode += "[color=#%s]Lv.%d[/color]  %d / %d XP" % [gold_hex, level, cur_xp, need_xp]

	var sp: int = XpSystem.get_available_skill_points()
	if sp > 0:
		bbcode += "  [color=#%s]SP %d 사용 가능[/color]" % [gold_hex, sp]

	_lbl_settlement_body.text = bbcode

	# Reset weekly XP after displaying
	_weekly_xp_gained = 0
	if _settlement_queue.size() > 0:
		_btn_settlement_confirm.text = "다음 →  Enter"
	else:
		_btn_settlement_confirm.text = "다음 주  Enter"


func _show_season_result() -> void:
	_settlement_panel.visible = true
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	_lbl_settlement_title.text = "시즌 종료"

	var rate: float = summary["return_rate"]
	var rate_hex: String = "EB3833" if rate >= 0.0 else "2E6BE6"
	var rate_sign: String = "+" if rate >= 0.0 else ""
	var gold_hex: String = "D9B320"

	# Grade based on return rate
	var grade: String
	var grade_hex: String
	if rate >= 20.0:
		grade = "S"
		grade_hex = "FFD700"
	elif rate >= 10.0:
		grade = "A"
		grade_hex = "EB3833"
	elif rate >= 0.0:
		grade = "B"
		grade_hex = "5A5A66"
	elif rate >= -10.0:
		grade = "C"
		grade_hex = "2E6BE6"
	else:
		grade = "D"
		grade_hex = "2E6BE6"

	var bbcode: String = ""
	bbcode += "[center][color=#%s][font_size=36][b]%s[/b][/font_size][/color][/center]\n\n" % [grade_hex, grade]

	bbcode += "[b]최종 자산[/b]  [color=#%s]₩%s[/color]\n" % [rate_hex, _format_number(summary["total_assets"])]
	bbcode += "[b]시즌 수익률[/b] [color=#%s]%s%.2f%%[/color]\n" % [rate_hex, rate_sign, rate]

	# Season trade summary
	var all_txs: Array[Dictionary] = PortfolioManager.get_transaction_history(999)
	var total_trades: int = all_txs.size()
	var total_realized: int = 0
	for tx: Dictionary in all_txs:
		if tx["type"] == "SELL":
			total_realized += tx.get("realized_pnl", 0)
	bbcode += "[b]총 거래[/b]    %d건\n" % total_trades
	if total_realized != 0:
		var real_hex: String = "EB3833" if total_realized > 0 else "2E6BE6"
		bbcode += "[b]실현 손익[/b]  [color=#%s]%+d[/color]\n" % [real_hex, total_realized]

	# XP section
	bbcode += "\n[color=#%s]━━━ 시즌 경험치 ━━━[/color]\n" % gold_hex
	if _last_xp_gained > 0 and _last_xp_source == "season_bonus":
		bbcode += "[color=#%s][b]+%d XP[/b] 획득[/color]\n" % [gold_hex, _last_xp_gained]

	var level: int = XpSystem.get_current_level()
	var cur_xp: int = XpSystem.get_total_xp() - XpSystem.get_cumulative_xp_for_level(level)
	var need_xp: int = XpSystem.get_cumulative_xp_for_level(level + 1) - XpSystem.get_cumulative_xp_for_level(level)
	bbcode += "[color=#%s]Lv.%d[/color]  %d / %d XP\n" % [gold_hex, level, cur_xp, need_xp]

	var sp: int = XpSystem.get_available_skill_points()
	if sp > 0:
		bbcode += "[color=#%s]미사용 스킬 포인트: %d[/color]" % [gold_hex, sp]

	_lbl_settlement_body.text = bbcode
	_btn_settlement_confirm.text = "다음 시즌  Enter"


## Show the next report in the settlement queue.
func _show_next_settlement() -> void:
	if _settlement_queue.is_empty():
		_settlement_panel.visible = false
		# All reports shown — proceed with transition
		if not _pending_level_up.is_empty():
			_level_up_banner.show_level_up(
				_pending_level_up["old_level"],
				_pending_level_up["new_level"],
				_pending_level_up["sp"],
			)
			_pending_level_up = {}
			return
		GameClock.confirm_transition()
		return

	var report_type: String = _settlement_queue.pop_front()
	match report_type:
		"daily":
			_show_settlement_report()
		"weekly":
			_show_weekly_report()
		"season":
			_show_season_result()


func _confirm_settlement() -> void:
	_settlement_panel.visible = false

	# Reset XP tracking after each report
	_last_xp_gained = 0
	_last_xp_source = ""

	# Show next report in queue, or finish
	_show_next_settlement()


# ── UI Construction (code-built for now, .tscn later) ──

func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	# Dark background
	var bg_style: StyleBoxFlat = StyleBoxFlat.new()
	bg_style.bg_color = ThemeSetup.BG_DARKEST
	add_theme_stylebox_override("panel", bg_style)

	# Main HBoxContainer: [stock_list | center_area | order_panel]
	var main_hbox: HBoxContainer = HBoxContainer.new()
	main_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_hbox.add_theme_constant_override("separation", 2)
	add_child(main_hbox)

	# Toast notification container (bottom-center overlay)
	_toast_container = VBoxContainer.new()
	_toast_container.anchor_left = 0.25
	_toast_container.anchor_right = 0.75
	_toast_container.anchor_top = 1.0
	_toast_container.anchor_bottom = 1.0
	_toast_container.offset_top = -200
	_toast_container.offset_bottom = -30
	_toast_container.add_theme_constant_override("separation", 6)
	_toast_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_container)

	# ── Left: Stock List (15%, min 220px) ──
	var stock_panel: PanelContainer = PanelContainer.new()
	stock_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_panel.size_flags_stretch_ratio = 0.15
	stock_panel.custom_minimum_size.x = 180
	stock_panel.add_theme_stylebox_override("panel", ThemeSetup.make_panel_style(ThemeSetup.BG_DARK))
	main_hbox.add_child(stock_panel)

	var stock_vbox: VBoxContainer = VBoxContainer.new()
	stock_vbox.add_theme_constant_override("separation", 2)
	stock_panel.add_child(stock_vbox)

	var stock_title: Label = Label.new()
	stock_title.text = "종목 리스트"
	stock_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stock_title.add_theme_font_size_override("font_size", 13)
	ThemeSetup.style_label_secondary(stock_title)
	stock_vbox.add_child(stock_title)

	var stock_sep: HSeparator = HSeparator.new()
	stock_sep.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	stock_vbox.add_child(stock_sep)

	var stock_scroll: ScrollContainer = ScrollContainer.new()
	stock_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stock_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stock_vbox.add_child(stock_scroll)

	_stock_list_container = VBoxContainer.new()
	_stock_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_scroll.add_child(_stock_list_container)

	# Populate stock rows
	for i: int in range(_stock_ids.size()):
		var sid: String = _stock_ids[i]
		var row: HBoxContainer = _create_stock_row(sid)
		_stock_list_container.add_child(row)

	# ── Center: Status bar + Chart + Bottom tabs (50%) ──
	var center_vbox: VBoxContainer = VBoxContainer.new()
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_vbox.size_flags_stretch_ratio = 0.60
	center_vbox.add_theme_constant_override("separation", 2)
	main_hbox.add_child(center_vbox)

	# Status bar
	_build_status_bar(center_vbox)

	# Chart renderer
	var chart_script: GDScript = load("res://src/ui/chart_renderer.gd") as GDScript
	_chart_renderer = chart_script.new() as Control
	_chart_renderer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chart_renderer.size_flags_stretch_ratio = 0.65
	center_vbox.add_child(_chart_renderer)
	if _chart_renderer.has_signal("price_clicked"):
		_chart_renderer.price_clicked.connect(_on_chart_price_clicked)

	# Bottom panel with tabs
	_build_bottom_panel(center_vbox)

	# ── Right: Order Panel (20%) ──
	_build_order_panel(main_hbox)

	# ── Overlays ──
	_build_overlays()


func _build_status_bar(parent: VBoxContainer) -> void:
	var bar_vbox: VBoxContainer = VBoxContainer.new()
	bar_vbox.add_theme_constant_override("separation", 0)
	parent.add_child(bar_vbox)

	# ── Row 1: Market info + Speed controls ──
	var row1_panel: PanelContainer = PanelContainer.new()
	row1_panel.add_theme_stylebox_override("panel", ThemeSetup.make_panel_style(ThemeSetup.BG_PANEL, 0, ThemeSetup.BORDER_DIM))
	bar_vbox.add_child(row1_panel)

	var row1: HBoxContainer = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	row1_panel.add_child(row1)

	_lbl_season_info = Label.new()
	_lbl_season_info.text = "1주차 월요일"
	_lbl_season_info.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_primary(_lbl_season_info)
	row1.add_child(_lbl_season_info)

	var sep1: VSeparator = VSeparator.new()
	sep1.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	row1.add_child(sep1)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.custom_minimum_size.x = 80
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.show_percentage = false
	row1.add_child(_progress_bar)

	_lbl_tick_progress = Label.new()
	_lbl_tick_progress.text = "틱 0/%d" % GameClock.TICKS_PER_DAY
	_lbl_tick_progress.add_theme_font_size_override("font_size", 11)
	row1.add_child(_lbl_tick_progress)

	var sep2: VSeparator = VSeparator.new()
	row1.add_child(sep2)

	_lbl_speed = Label.new()
	_lbl_speed.text = "▶ 1x"
	_lbl_speed.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_primary(_lbl_speed)
	row1.add_child(_lbl_speed)

	_btn_speed_1x = Button.new()
	_btn_speed_1x.text = "1x"
	_btn_speed_1x.pressed.connect(func() -> void: _set_speed(1.0))
	ThemeSetup.apply_accent_button(_btn_speed_1x)
	row1.add_child(_btn_speed_1x)

	_btn_speed_2x = Button.new()
	_btn_speed_2x.text = "2x"
	_btn_speed_2x.pressed.connect(func() -> void: _set_speed(2.0))
	ThemeSetup.apply_button_theme(_btn_speed_2x)
	row1.add_child(_btn_speed_2x)

	_btn_speed_4x = Button.new()
	_btn_speed_4x.text = "4x"
	_btn_speed_4x.pressed.connect(func() -> void: _set_speed(4.0))
	ThemeSetup.apply_button_theme(_btn_speed_4x)
	row1.add_child(_btn_speed_4x)

	_btn_pause = Button.new()
	_btn_pause.text = "⏸"
	_btn_pause.pressed.connect(_handle_pause_toggle)
	ThemeSetup.apply_button_theme(_btn_pause)
	row1.add_child(_btn_pause)

	# Market open / season start button (PRE_MARKET only) — in row 1
	# Text and action update in _set_ui_state based on SeasonManager.is_season_active().
	_btn_market_open = Button.new()
	_btn_market_open.text = "시즌 시작 Enter"
	_btn_market_open.visible = false
	_btn_market_open.pressed.connect(_on_btn_market_open_pressed)
	ThemeSetup.apply_accent_button(_btn_market_open)
	row1.add_child(_btn_market_open)

	# ── Row 2: Index + Assets + XP ──
	var row2_panel: PanelContainer = PanelContainer.new()
	row2_panel.add_theme_stylebox_override("panel", ThemeSetup.make_panel_style(ThemeSetup.BG_DARK, 0, ThemeSetup.BORDER_DIM))
	bar_vbox.add_child(row2_panel)

	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	row2_panel.add_child(row2)

	_lbl_market_index = Label.new()
	_lbl_market_index.text = "지수 1,000.0 (0.00%)"
	_lbl_market_index.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_primary(_lbl_market_index)
	row2.add_child(_lbl_market_index)

	var sep_r2: VSeparator = VSeparator.new()
	sep_r2.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	row2.add_child(sep_r2)

	_lbl_total_assets = Label.new()
	_lbl_total_assets.text = "총 자산: ₩0"
	_lbl_total_assets.add_theme_font_size_override("font_size", 13)
	ThemeSetup.style_label_primary(_lbl_total_assets)
	row2.add_child(_lbl_total_assets)

	_lbl_cash = Label.new()
	_lbl_cash.text = "현금: ₩0"
	_lbl_cash.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_secondary(_lbl_cash)
	row2.add_child(_lbl_cash)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(spacer)

	# League HUD — tier name (clickable → F2 tab, league-ui.md AC-01)
	_lbl_league_tier = Label.new()
	_lbl_league_tier.text = "프리마켓"
	_lbl_league_tier.add_theme_font_size_override("font_size", 12)
	_lbl_league_tier.mouse_filter = Control.MOUSE_FILTER_STOP
	_lbl_league_tier.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_lbl_league_tier.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			league_tab_requested.emit()
	)
	ThemeSetup.style_label_secondary(_lbl_league_tier)
	row2.add_child(_lbl_league_tier)

	var sep_league1: VSeparator = VSeparator.new()
	sep_league1.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	row2.add_child(sep_league1)

	_lbl_season_return = Label.new()
	_lbl_season_return.text = "시즌 -"
	_lbl_season_return.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_secondary(_lbl_season_return)
	row2.add_child(_lbl_season_return)

	var sep_league2: VSeparator = VSeparator.new()
	sep_league2.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	row2.add_child(sep_league2)

	_lbl_weekly_return = Label.new()
	_lbl_weekly_return.text = "주간 -"
	_lbl_weekly_return.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_secondary(_lbl_weekly_return)
	row2.add_child(_lbl_weekly_return)

	var sep_league3: VSeparator = VSeparator.new()
	sep_league3.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	row2.add_child(sep_league3)

	# XP Bar — right-aligned in row 2
	_xp_bar = XpBar.new()
	_xp_bar.skill_tree_requested.connect(_toggle_skill_tree)
	row2.add_child(_xp_bar)

	# SP alert label — PRE_MARKET reminder (GDD Rule 6)
	_lbl_sp_alert = Label.new()
	_lbl_sp_alert.visible = false
	_lbl_sp_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_sp_alert.add_theme_font_size_override("font_size", 12)
	_lbl_sp_alert.add_theme_color_override("font_color", Color(0.85, 0.70, 0.20))
	parent.add_child(_lbl_sp_alert)


func _build_bottom_panel(parent: VBoxContainer) -> void:
	var bottom: VBoxContainer = VBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.size_flags_stretch_ratio = 0.35
	parent.add_child(bottom)

	# Tab buttons
	var tab_bar: HBoxContainer = HBoxContainer.new()
	bottom.add_child(tab_bar)

	_btn_tab_news = Button.new()
	_btn_tab_news.text = "뉴스"
	ThemeSetup.apply_tab_active(_btn_tab_news)
	_btn_tab_news.pressed.connect(func() -> void: _switch_bottom_tab(0))
	tab_bar.add_child(_btn_tab_news)

	_btn_tab_alerts = Button.new()
	_btn_tab_alerts.text = "VI/CB"
	ThemeSetup.apply_tab_inactive(_btn_tab_alerts)
	_btn_tab_alerts.pressed.connect(func() -> void: _switch_bottom_tab(1))
	tab_bar.add_child(_btn_tab_alerts)

	_btn_tab_portfolio = Button.new()
	_btn_tab_portfolio.text = "포트폴리오"
	ThemeSetup.apply_tab_inactive(_btn_tab_portfolio)
	_btn_tab_portfolio.pressed.connect(func() -> void: _switch_bottom_tab(2))
	tab_bar.add_child(_btn_tab_portfolio)

	# News feed panel (real component)
	var news_script: GDScript = load("res://src/ui/news_feed.gd") as GDScript
	_news_panel = news_script.new() as Control
	_news_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_child(_news_panel)
	if _news_panel.has_signal("stock_clicked"):
		_news_panel.stock_clicked.connect(_select_stock)

	# VI/CB alerts panel
	_alerts_panel = _build_alerts_panel()
	_alerts_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_alerts_panel.visible = false
	bottom.add_child(_alerts_panel)

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
	panel.size_flags_stretch_ratio = 0.13
	panel.custom_minimum_size.x = 160
	panel.add_theme_stylebox_override("panel", ThemeSetup.make_panel_style(ThemeSetup.BG_DARK))
	parent.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Stock name + price
	_lbl_order_stock_name = Label.new()
	_lbl_order_stock_name.text = "종목 선택"
	_lbl_order_stock_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_order_stock_name.add_theme_font_size_override("font_size", 15)
	ThemeSetup.style_label_primary(_lbl_order_stock_name)
	vbox.add_child(_lbl_order_stock_name)

	_lbl_order_current_price = Label.new()
	_lbl_order_current_price.text = "현재가 ₩0"
	_lbl_order_current_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_order_current_price.add_theme_font_size_override("font_size", 16)
	ThemeSetup.style_label_primary(_lbl_order_current_price)
	vbox.add_child(_lbl_order_current_price)

	var sep1: HSeparator = HSeparator.new()
	sep1.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	vbox.add_child(sep1)

	# Buy/Sell tabs
	var side_hbox: HBoxContainer = HBoxContainer.new()
	side_hbox.add_theme_constant_override("separation", 2)
	vbox.add_child(side_hbox)

	_btn_buy_tab = Button.new()
	_btn_buy_tab.text = "매수 B"
	_btn_buy_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_buy_tab.custom_minimum_size.y = 28
	_btn_buy_tab.pressed.connect(func() -> void: _set_order_side("BUY"))
	side_hbox.add_child(_btn_buy_tab)

	_btn_sell_tab = Button.new()
	_btn_sell_tab.text = "매도 S"
	_btn_sell_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_sell_tab.custom_minimum_size.y = 28
	_btn_sell_tab.pressed.connect(func() -> void: _set_order_side("SELL"))
	side_hbox.add_child(_btn_sell_tab)

	# Order type
	var type_hbox: HBoxContainer = HBoxContainer.new()
	type_hbox.add_theme_constant_override("separation", 2)
	vbox.add_child(type_hbox)

	_radio_market = Button.new()
	_radio_market.text = "시장가"
	_radio_market.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_radio_market.custom_minimum_size.y = 26
	_radio_market.pressed.connect(func() -> void: _set_order_type("MARKET"))
	type_hbox.add_child(_radio_market)

	_radio_limit = Button.new()
	if SkillTree.is_skill_unlocked("TR1"):
		_radio_limit.text = "지정가"
	else:
		_radio_limit.text = "지정가 🔒"
	_radio_limit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_radio_limit.custom_minimum_size.y = 26
	_radio_limit.pressed.connect(func() -> void: _set_order_type("LIMIT"))
	type_hbox.add_child(_radio_limit)

	# Limit price row (hidden by default)
	_limit_price_row = HBoxContainer.new()
	_limit_price_row.visible = false
	vbox.add_child(_limit_price_row)

	var limit_lbl: Label = Label.new()
	limit_lbl.text = "지정가"
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

	# Quantity
	var qty_hbox: HBoxContainer = HBoxContainer.new()
	qty_hbox.add_theme_constant_override("separation", 2)
	vbox.add_child(qty_hbox)

	var qty_lbl: Label = Label.new()
	qty_lbl.text = "수량"
	qty_lbl.add_theme_font_size_override("font_size", 12)
	ThemeSetup.style_label_primary(qty_lbl)
	qty_hbox.add_child(qty_lbl)

	_spin_quantity = SpinBox.new()
	_spin_quantity.min_value = 0
	_spin_quantity.max_value = 99999
	_spin_quantity.step = 1
	_spin_quantity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin_quantity.custom_minimum_size.x = 70
	_spin_quantity.value_changed.connect(func(_v: float) -> void: _update_estimated_amount())
	ThemeSetup.apply_spinbox_theme(_spin_quantity)
	qty_hbox.add_child(_spin_quantity)

	_btn_max_qty = Button.new()
	_btn_max_qty.text = "최대"
	_btn_max_qty.custom_minimum_size.y = 26
	_btn_max_qty.pressed.connect(_calculate_max_quantity)
	ThemeSetup.apply_button_theme(_btn_max_qty)
	qty_hbox.add_child(_btn_max_qty)

	# Estimated amount
	_lbl_estimated_amount = Label.new()
	_lbl_estimated_amount.text = "예상 금액: ₩0"
	ThemeSetup.style_label_secondary(_lbl_estimated_amount)
	vbox.add_child(_lbl_estimated_amount)

	# Submit button
	_btn_submit_order = Button.new()
	_btn_submit_order.text = "주문실행 Enter"
	_btn_submit_order.pressed.connect(_submit_order)
	_btn_submit_order.custom_minimum_size.y = 30
	ThemeSetup.apply_accent_button(_btn_submit_order)
	vbox.add_child(_btn_submit_order)

	# Error label
	_lbl_order_error = Label.new()
	_lbl_order_error.text = ""
	_lbl_order_error.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	_lbl_order_error.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_lbl_order_error)

	var sep2: HSeparator = HSeparator.new()
	sep2.add_theme_color_override("separator", ThemeSetup.SEPARATOR)
	vbox.add_child(sep2)

	# Pending orders
	var pending_title: Label = Label.new()
	pending_title.text = "미체결 주문"
	ThemeSetup.style_label_secondary(pending_title)
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
	ThemeSetup.apply_sell_button(_btn_cancel_order)
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

	var pause_style: StyleBoxFlat = StyleBoxFlat.new()
	pause_style.bg_color = Color(0.0, 0.0, 0.0, 0.3)
	_pause_overlay.add_theme_stylebox_override("panel", pause_style)

	var pause_lbl: Label = Label.new()
	pause_lbl.text = "⏸ 일시정지"
	pause_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_lbl.add_theme_font_size_override("font_size", 48)
	pause_lbl.add_theme_color_override("font_color", ThemeSetup.TEXT_PRIMARY)
	_pause_overlay.add_child(pause_lbl)

	# Level-up banner (GDD Rule 3)
	_level_up_banner = LevelUpBanner.new()
	_level_up_banner.skill_tree_requested.connect(_toggle_skill_tree)
	_level_up_banner.banner_closed.connect(func() -> void:
		# After banner closes, proceed with transition
		GameClock.confirm_transition()
	)
	add_child(_level_up_banner)

	# Skill tree overlay (GDD Rule 4)
	_skill_tree_overlay = SkillTreeOverlay.new()
	add_child(_skill_tree_overlay)
	# TD-03: relay overlay pause signal upward so MainScreen routes to GameClock
	_skill_tree_overlay.pause_toggle_requested.connect(func() -> void: pause_toggle_requested.emit())

	# Settlement panel — centered modal with structured layout
	_settlement_panel = PanelContainer.new()
	_settlement_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_settlement_panel.custom_minimum_size = Vector2(460, 380)
	_settlement_panel.visible = false
	var settle_style: StyleBoxFlat = ThemeSetup.make_panel_style(ThemeSetup.BG_PANEL, 12, ThemeSetup.BORDER_BRIGHT, 2)
	settle_style.shadow_color = Color(0.0, 0.0, 0.0, 0.15)
	settle_style.shadow_size = 8
	_settlement_panel.add_theme_stylebox_override("panel", settle_style)
	add_child(_settlement_panel)

	var settle_vbox: VBoxContainer = VBoxContainer.new()
	settle_vbox.add_theme_constant_override("separation", 12)
	_settlement_panel.add_child(settle_vbox)

	_lbl_settlement_title = Label.new()
	_lbl_settlement_title.text = "정산"
	_lbl_settlement_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_settlement_title.add_theme_font_size_override("font_size", 22)
	ThemeSetup.style_label_primary(_lbl_settlement_title)
	settle_vbox.add_child(_lbl_settlement_title)

	# Separator line
	var settle_sep: HSeparator = HSeparator.new()
	settle_vbox.add_child(settle_sep)

	_lbl_settlement_body = RichTextLabel.new()
	_lbl_settlement_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lbl_settlement_body.bbcode_enabled = true
	_lbl_settlement_body.fit_content = true
	_lbl_settlement_body.scroll_active = false
	_lbl_settlement_body.add_theme_color_override("default_color", ThemeSetup.TEXT_SECONDARY)
	_lbl_settlement_body.add_theme_font_size_override("normal_font_size", 14)
	settle_vbox.add_child(_lbl_settlement_body)

	_btn_settlement_confirm = Button.new()
	_btn_settlement_confirm.text = "확인 Enter"
	ThemeSetup.apply_accent_button(_btn_settlement_confirm)
	_btn_settlement_confirm.custom_minimum_size.y = 44
	_btn_settlement_confirm.add_theme_font_size_override("font_size", 14)
	_btn_settlement_confirm.pressed.connect(_confirm_settlement)
	settle_vbox.add_child(_btn_settlement_confirm)


func _create_stock_row(stock_id: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.custom_minimum_size.y = 38

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
	lbl_marker.custom_minimum_size.x = 16
	lbl_marker.add_theme_color_override("font_color", ThemeSetup.BTN_ACCENT_HOVER)
	row.add_child(lbl_marker)

	# Stock ticker
	var lbl_info: Label = Label.new()
	var stock: StockData = StockDatabase.get_stock(stock_id)
	var price: int = stock.base_price if stock else 0
	lbl_info.text = "%s" % stock_id
	lbl_info.custom_minimum_size.x = 32
	ThemeSetup.style_label_primary(lbl_info)
	row.add_child(lbl_info)

	# Price
	var lbl_price: Label = Label.new()
	lbl_price.text = "₩%s" % _format_number(price)
	lbl_price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ThemeSetup.style_label_primary(lbl_price)
	row.add_child(lbl_price)

	# Change %
	var lbl_change: Label = Label.new()
	lbl_change.text = " 0.0%"
	lbl_change.custom_minimum_size.x = 65
	lbl_change.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ThemeSetup.style_label_secondary(lbl_change)
	row.add_child(lbl_change)

	# Held marker
	var lbl_held: Label = Label.new()
	lbl_held.text = ""
	lbl_held.custom_minimum_size.x = 16
	lbl_held.add_theme_color_override("font_color", Color(0.90, 0.65, 0.05))
	row.add_child(lbl_held)

	return row


# ── VI/CB Alerts Panel ──

func _build_alerts_panel() -> VBoxContainer:
	var panel: VBoxContainer = VBoxContainer.new()

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	panel.add_child(header)

	var title: Label = Label.new()
	title.text = "VI / CB 알림"
	title.add_theme_font_size_override("font_size", 14)
	ThemeSetup.style_label_primary(title)
	header.add_child(title)

	_lbl_alerts_badge = Label.new()
	_lbl_alerts_badge.text = ""
	_lbl_alerts_badge.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	header.add_child(_lbl_alerts_badge)

	_alerts_scroll = ScrollContainer.new()
	_alerts_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_alerts_scroll)

	_alerts_container = VBoxContainer.new()
	_alerts_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_alerts_container.add_theme_constant_override("separation", 2)
	_alerts_scroll.add_child(_alerts_container)

	# Empty state
	var empty: Label = Label.new()
	empty.text = "VI / CB 이벤트가 없습니다"
	empty.name = "EmptyLabel"
	ThemeSetup.style_label_dim(empty)
	_alerts_container.add_child(empty)

	return panel


func _add_alert_card(headline: String, body: String, severity: String, stock_id: String) -> void:
	# Remove empty label
	var empty: Node = _alerts_container.get_node_or_null("EmptyLabel")
	if empty:
		empty.queue_free()

	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	match severity:
		"MEGA":
			style.bg_color = ThemeSetup.ALERT_BG_MEGA
			style.border_color = ThemeSetup.ALERT_BORDER_MEGA
		"LARGE":
			style.bg_color = ThemeSetup.ALERT_BG_LARGE
			style.border_color = ThemeSetup.ALERT_BORDER_LARGE
		_:
			style.bg_color = ThemeSetup.BG_CARD
			style.border_color = ThemeSetup.BORDER_DIM
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.set_content_margin_all(6)
	card.add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	var lbl_head: Label = Label.new()
	lbl_head.text = headline
	lbl_head.autowrap_mode = TextServer.AUTOWRAP_WORD
	ThemeSetup.style_label_primary(lbl_head)
	vbox.add_child(lbl_head)

	if body != "":
		var lbl_body: Label = Label.new()
		lbl_body.text = body
		lbl_body.autowrap_mode = TextServer.AUTOWRAP_WORD
		ThemeSetup.style_label_dim(lbl_body)
		vbox.add_child(lbl_body)

	var lbl_time: Label = Label.new()
	var tick: int = GameClock.get_current_tick()
	lbl_time.text = "틱 %d" % tick
	ThemeSetup.style_label_dim(lbl_time)
	vbox.add_child(lbl_time)

	_alerts_container.add_child(card)
	_alerts_container.move_child(card, 0)

	# Click to select stock
	if stock_id != "":
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton:
				var mb: InputEventMouseButton = event as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					_select_stock(stock_id)
		)

	# Flash the tab if not on alerts
	if _active_tab != 1:
		_btn_tab_alerts.text = "VI/CB ●"


func _on_system_event_alert(entry: Dictionary) -> void:
	if not entry.get("is_system_event", false):
		return
	var headline: String = str(entry.get("headline", ""))
	var body: String = str(entry.get("body", ""))
	var severity: String = str(entry.get("impact_tier", "MEDIUM"))
	var stock_ids: Array = entry.get("target_stock_ids", [])
	var first_stock: String = str(stock_ids[0]) if stock_ids.size() > 0 else ""
	# MACRO events (CB) don't link to individual stock
	if entry.get("scope", "") == "MACRO":
		first_stock = ""
	_add_alert_card(headline, body, severity, first_stock)


func _clear_alerts() -> void:
	if not _alerts_container:
		return
	for child: Node in _alerts_container.get_children():
		child.queue_free()
	var empty: Label = Label.new()
	empty.text = "VI / CB 이벤트가 없습니다"
	empty.name = "EmptyLabel"
	ThemeSetup.style_label_dim(empty)
	_alerts_container.add_child(empty)
	_btn_tab_alerts.text = "VI/CB"


func _on_skill_unlocked(skill_id: String) -> void:
	match skill_id:
		"TR1":
			_radio_limit.text = "지정가"
		"P1", "P2":
			_update_status_bar()




# ── Toast Notifications ──

const TOAST_DURATION: float = 3.5
const TOAST_MAX: int = 4
const TOAST_SCOPE_LABELS: Dictionary = {
	"MACRO": "시장",
	"SECTOR": "업종",
	"INDIVIDUAL": "개별",
}

func _on_news_toast(entry: Dictionary) -> void:
	# Skip system events (VI/CB already have their own alerts)
	if entry.get("is_system_event", false):
		return
	var scope: String = str(entry.get("scope", "MACRO"))
	var headline: String = str(entry.get("headline", ""))
	if headline.is_empty():
		return
	var tag: String = TOAST_SCOPE_LABELS.get(scope, scope)
	_show_toast("[%s] %s" % [tag, headline], scope)
	# Update news tab badge if not viewing news
	if _active_tab != 0:
		_news_unread += 1
		_btn_tab_news.text = "뉴스 (%d)" % _news_unread


func _show_toast(text: String, scope: String) -> void:
	# Cap max visible toasts
	while _toast_container.get_child_count() >= TOAST_MAX:
		var oldest: Node = _toast_container.get_child(0)
		_toast_container.remove_child(oldest)
		oldest.queue_free()

	var toast: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.12, 0.95)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	style.content_margin_left = 18
	style.content_margin_right = 18

	style.border_color = Color.TRANSPARENT
	style.set_border_width_all(0)

	toast.add_theme_stylebox_override("panel", style)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(lbl)

	_toast_container.add_child(toast)

	# Fade-in
	toast.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(toast, "modulate:a", 1.0, 0.2)
	# Hold, then fade-out and remove
	tween.tween_interval(TOAST_DURATION)
	tween.tween_property(toast, "modulate:a", 0.0, 0.4)
	tween.tween_callback(toast.queue_free)


# ── Utility ──

## Delegates to FormatUtils.number() — single source of truth (TD-04 note).
func _format_number(value: int) -> String:
	return FormatUtils.number(value)
