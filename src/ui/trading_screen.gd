## TradingScreen — UIState 기계 + 서브컴포넌트 조율자.
## 5 subcomponents: StockListPanel, StatusBar, OrderPanel, SettlementReporter, ToastManager.
## TradingScreen 자체는 UIState 전환, 키보드 입력, 시그널 중계만 담당한다.
## See: design/gdd/trading-screen.md §10
class_name TradingScreen
extends Control

## 공유 UIState enum 앨리어스 — 중복 정의 제거 (TD-CR-11). 원본: src/core/ui_state_types.gd
const UIState = UIStateTypes.UIState

# ── Signals ──

## Emitted when the player selects a stock from the list.
signal stock_selected(stock_id: String)

## Emitted when the player clicks the league HUD → MainScreen switches tab (ADR-006).
signal league_tab_requested()
## Emitted when SP alert or LevelUpBanner → MainScreen switches to F3 growth tab.
signal growth_tab_requested()
## TD-03: relayed up to MainScreen → GameClock.toggle_pause().
signal pause_toggle_requested()
## TD-03: relayed up to MainScreen → GameClock.set_speed().
signal speed_change_requested(multiplier: float)
## Emitted after all settlement reports are confirmed — GameMain shows LifestyleScreen.
## is_season_end: true when the clock is in SEASON_END (drives button text in LifestyleScreen).
signal spending_screen_requested(is_season_end: bool)

# ── State ──

var _ui_state: int = UIState.LOADING
var _selected_stock_id: String = ""
var _stock_ids: Array[String] = []

# Bottom tab indices
const TAB_NEWS: int = 0
const TAB_ALERTS: int = 1
const TAB_PORTFOLIO: int = 2

const SKILL_TR1: String = "TR1"  ## 기본 거래 해금 스킬 ID

var _active_tab: int = TAB_NEWS
## H-10: stored callable for on_market_close lambda so it can be disconnected.
var _on_market_close_cb: Callable
var _news_unread: int = 0
var _portfolio_unread: int = 0
var _btn_tab_news: Button
var _btn_tab_alerts: Button
var _btn_tab_portfolio: Button
var _news_panel: Control
var _alerts_panel: Control
var _portfolio_panel: Control
var _alerts_container: VBoxContainer

# ── Subcomponents ──

var _stock_list: StockListPanel
var _status_bar: StatusBar
var _order_panel: OrderPanel
var _settlement_reporter: SettlementReporter
var _toast_manager: ToastManager

# ── Other Nodes ──

var _chart_renderer: Control
var _pause_overlay: Panel
var _level_up_banner: LevelUpBanner
var _profit_celebration: ProfitCelebration
var _margin_call_popup: MarginCallPopup

# ── Lifecycle ──

func _ready() -> void:
	_stock_ids = StockDatabase.get_all_stock_ids()
	_build_ui()
	_connect_signals()
	if _stock_ids.size() > 0:
		_select_stock(_stock_ids[0])
	_sync_ui_state_from_clock()


func _connect_signals() -> void:
	# Subcomponent → TradingScreen → MainScreen (bubble-up chain)
	_stock_list.stock_selected.connect(_select_stock)
	_status_bar.league_hud_clicked.connect(func() -> void: league_tab_requested.emit())
	_status_bar.pause_toggled.connect(_handle_pause_toggle)
	_status_bar.speed_changed.connect(_set_speed)
	_status_bar.market_open_pressed.connect(_on_btn_market_open_pressed)
	_status_bar.growth_tab_requested.connect(func() -> void: growth_tab_requested.emit())
	_settlement_reporter.settlement_confirmed.connect(func() -> void:
		var is_season_end: bool = (
			GameClock.get_market_state() == GameClock.MarketState.SEASON_END
		)
		spending_screen_requested.emit(is_season_end)
	)
	_settlement_reporter.needs_level_up.connect(_on_settlement_needs_level_up)
	_settlement_reporter.weekly_xp_reset_requested.connect(XpSystem.reset_weekly_xp)
	_toast_manager.news_received.connect(_on_news_received)
	_level_up_banner.skill_tree_requested.connect(func() -> void: growth_tab_requested.emit())
	_level_up_banner.banner_closed.connect(func() -> void: GameClock.confirm_transition())
	if _chart_renderer.has_signal("price_clicked"):
		_chart_renderer.price_clicked.connect(
			func(price: int) -> void: _order_panel.set_price_from_click(price)
		)
	if _news_panel.has_signal("stock_clicked"):
		_news_panel.stock_clicked.connect(_select_stock)
	if _portfolio_panel.has_signal("stock_clicked"):
		_portfolio_panel.stock_clicked.connect(_select_stock)
	# Game events
	GameClock.on_market_state_changed.connect(_on_market_state_changed)
	_on_market_close_cb = func() -> void: _stock_list.snapshot_prev_close()
	GameClock.on_market_close.connect(_on_market_close_cb)
	OrderEngine.on_order_filled.connect(_on_order_filled)
	NewsEventSystem.on_news_display.connect(_on_system_event_alert)
	SkillTree.on_skill_unlocked.connect(_on_skill_unlocked)
	PortfolioManager.holding_removed.connect(_on_holding_removed)


func _exit_tree() -> void:
	# H-10: disconnect all autoload signals connected in _connect_signals().
	if GameClock.on_market_state_changed.is_connected(_on_market_state_changed):
		GameClock.on_market_state_changed.disconnect(_on_market_state_changed)
	if OrderEngine.on_order_filled.is_connected(_on_order_filled):
		OrderEngine.on_order_filled.disconnect(_on_order_filled)
	if NewsEventSystem.on_news_display.is_connected(_on_system_event_alert):
		NewsEventSystem.on_news_display.disconnect(_on_system_event_alert)
	if SkillTree.on_skill_unlocked.is_connected(_on_skill_unlocked):
		SkillTree.on_skill_unlocked.disconnect(_on_skill_unlocked)
	if PortfolioManager.holding_removed.is_connected(_on_holding_removed):
		PortfolioManager.holding_removed.disconnect(_on_holding_removed)
	if GameClock.on_market_close.is_connected(_on_market_close_cb):
		GameClock.on_market_close.disconnect(_on_market_close_cb)


func _sync_ui_state_from_clock() -> void:
	match GameClock.get_market_state():
		GameClock.MarketState.PRE_MARKET:
			_set_ui_state(UIState.PRE_MARKET)
		GameClock.MarketState.MARKET_OPEN:
			_set_ui_state(UIState.MARKET_OPEN)
		GameClock.MarketState.PAUSED:
			_set_ui_state(UIState.PAUSED)
		GameClock.MarketState.MARKET_CLOSED:
			_settlement_reporter.enqueue("daily")
			_set_ui_state(UIState.SETTLEMENT)
		GameClock.MarketState.DAY_TRANSITION:
			# 로드 시 DAY_TRANSITION 복원 경로: settlement는 이미 완료됐으므로 enqueue 없이 UI 상태만 맞춤.
			_set_ui_state(UIState.SETTLEMENT)
		GameClock.MarketState.WEEK_END:
			_settlement_reporter.enqueue("weekly")
			_set_ui_state(UIState.SETTLEMENT)
		GameClock.MarketState.SEASON_END:
			_settlement_reporter.enqueue("season")
			_set_ui_state(UIState.SETTLEMENT)

# ── Input Handling (GDD Rule 7) ──

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.keycode:
			KEY_B:
				if not key.shift_pressed:
					_order_panel.set_order_side("BUY")
					get_viewport().set_input_as_handled()
			KEY_S:
				if not key.shift_pressed:
					_order_panel.set_order_side("SELL")
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
		if key.shift_pressed:
			match key.keycode:
				KEY_1: _set_speed(1.0); get_viewport().set_input_as_handled()
				KEY_2: _set_speed(2.0); get_viewport().set_input_as_handled()
				KEY_3: _set_speed(4.0); get_viewport().set_input_as_handled()

	elif event is InputEventJoypadButton:
		# S5-05: 게임패드 입력 지원. InputMap 액션 사용 — 리맵 지원.
		if not event.is_pressed():
			return
		if event.is_action("game_buy"):
			_order_panel.set_order_side("BUY")
			get_viewport().set_input_as_handled()
		elif event.is_action("game_sell"):
			_order_panel.set_order_side("SELL")
			get_viewport().set_input_as_handled()
		elif event.is_action("game_pause"):
			_handle_pause_toggle()
			get_viewport().set_input_as_handled()
		elif event.is_action("game_confirm"):
			_handle_enter_key()
			get_viewport().set_input_as_handled()
		elif event.is_action("game_tab_switch"):
			_toggle_bottom_tab()
			get_viewport().set_input_as_handled()
		elif event.is_action("game_cancel"):
			_handle_escape()
			get_viewport().set_input_as_handled()

# ── State Management ──

func _set_ui_state(new_state: UIState) -> void:
	_ui_state = new_state
	_pause_overlay.visible = (new_state == UIState.PAUSED)
	_status_bar.set_ui_state(new_state)
	var submit_enabled: bool = new_state not in [UIState.SETTLEMENT, UIState.SEASON_RESULT, UIState.LOADING]
	var submit_text: String = tr("주문 예약 Enter") if new_state == UIState.PRE_MARKET else tr("주문 실행 Enter")
	_order_panel.set_ui_state_submit_enabled(submit_enabled, submit_text)
	if new_state == UIState.PRE_MARKET:
		_order_panel.refresh_limit_price_bounds()
		_clear_alerts()
	if new_state == UIState.SETTLEMENT:
		_settlement_reporter.show_next.call_deferred()

# ── Signal Handlers ──

func _on_btn_market_open_pressed() -> void:
	if SeasonManager.is_season_active():
		GameClock.confirm_market_open()
	else:
		SeasonManager.start_season()


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
			_settlement_reporter.enqueue("daily")
			_set_ui_state(UIState.SETTLEMENT)
		GameClock.MarketState.DAY_TRANSITION:
			pass  ## Stay in SETTLEMENT
		GameClock.MarketState.WEEK_END:
			_settlement_reporter.enqueue("weekly")
			_set_ui_state(UIState.SETTLEMENT)
		GameClock.MarketState.SEASON_END:
			_settlement_reporter.enqueue("season")
			_set_ui_state(UIState.SETTLEMENT)


func _on_order_filled(_order: Dictionary) -> void:
	## OrderPanel handles flash + pending list. TradingScreen tracks portfolio badge.
	if _active_tab != TAB_PORTFOLIO:
		_portfolio_unread += 1
		_btn_tab_portfolio.text = tr("포트폴리오 (%d)") % _portfolio_unread


## PortfolioManager.holding_removed 핸들러 — B-13 팡파레 트리거.
## GDD profit-celebration.md §3-1: cost_basis 계산 → ProfitCelebration.play().
func _on_holding_removed(_stock_id: String, quantity: int, price: int, realized_pnl: int) -> void:
	if realized_pnl <= 0:
		return
	var cost_basis: int = price * quantity - realized_pnl
	var pnl_pct: float
	if cost_basis <= 0:
		pnl_pct = 0.0  # GDD §5 방어 처리 — 이펙트 미발동
	else:
		pnl_pct = float(realized_pnl) / float(cost_basis) * 100.0
	_profit_celebration.play(realized_pnl, pnl_pct)


func _on_settlement_needs_level_up(data: Dictionary) -> void:
	_level_up_banner.show_level_up(data["old_level"], data["new_level"], data["sp"])


func _on_news_received() -> void:
	if GameClock.get_auto_slow_on_event() and GameClock.get_speed_multiplier() > 1.0:
		_set_speed(1.0)
	if _active_tab != TAB_NEWS:
		_news_unread += 1
		_btn_tab_news.text = tr("뉴스 (%d)") % _news_unread


func _on_skill_unlocked(skill_id: String) -> void:
	if skill_id == SKILL_TR1:
		var enabled: bool = _ui_state not in [UIState.SETTLEMENT, UIState.SEASON_RESULT, UIState.LOADING]
		var text: String = tr("주문 예약 Enter") if _ui_state == UIState.PRE_MARKET else tr("주문 실행 Enter")
		_order_panel.set_ui_state_submit_enabled(enabled, text)


func _on_system_event_alert(entry: Dictionary) -> void:
	if not entry.get("is_system_event", false):
		return
	AudioManager.play_vi_sfx()  # Sound fires when VI/CB tab indicator updates
	var headline: String = str(entry.get("headline", ""))
	var body: String = str(entry.get("body", ""))
	var severity: String = str(entry.get("impact_tier", "MEDIUM"))
	var stock_ids: Array = entry.get("target_stock_ids", [])
	var first_stock: String = str(stock_ids[0]) if stock_ids.size() > 0 else ""
	if entry.get("scope", "") == "MACRO":
		first_stock = ""
	_add_alert_card(headline, body, severity, first_stock)

# ── Stock Selection ──

func _select_stock(stock_id: String) -> void:
	_selected_stock_id = stock_id
	stock_selected.emit(stock_id)
	_stock_list.set_selected(stock_id)
	_order_panel.set_stock(stock_id)
	if _chart_renderer and _chart_renderer.has_method("load_stock"):
		_chart_renderer.load_stock(stock_id)

# ── Speed & Pause ──

func _set_speed(multiplier: float) -> void:
	if _ui_state != UIState.MARKET_OPEN and _ui_state != UIState.PAUSED:
		return
	speed_change_requested.emit(multiplier)
	_status_bar.update_speed(multiplier)


func _handle_pause_toggle() -> void:
	if _ui_state == UIState.MARKET_OPEN or _ui_state == UIState.PAUSED:
		pause_toggle_requested.emit()

# ── Key Handlers ──

func _handle_enter_key() -> void:
	if _ui_state == UIState.PRE_MARKET:
		GameClock.confirm_market_open()
	elif _ui_state == UIState.SETTLEMENT:
		# Guard: only confirm when panel is actually visible.
		# If Enter fires before the deferred show_next() runs, the queue would be
		# drained early and _pending_level_up would emit needs_level_up before
		# the daily panel has ever shown.
		if _settlement_reporter.is_showing():
			_settlement_reporter.confirm_current()
	elif _ui_state in [UIState.MARKET_OPEN, UIState.PAUSED]:
		_order_panel.try_submit()


func _handle_escape() -> void:
	if _level_up_banner and _level_up_banner.is_showing():
		_level_up_banner.hide_banner()
	elif _settlement_reporter.is_showing():
		_settlement_reporter.confirm_current()
	else:
		_order_panel.clear_quantity()


# ── Bottom Tab ──

func _toggle_bottom_tab() -> void:
	if _news_panel.visible:
		_switch_bottom_tab(TAB_ALERTS)
	elif _alerts_panel.visible:
		_switch_bottom_tab(TAB_PORTFOLIO)
	else:
		_switch_bottom_tab(TAB_NEWS)


func _switch_bottom_tab(index: int) -> void:
	_active_tab = index
	_news_panel.visible = (index == TAB_NEWS)
	_alerts_panel.visible = (index == TAB_ALERTS)
	_portfolio_panel.visible = (index == TAB_PORTFOLIO)
	if index == TAB_NEWS:
		_news_unread = 0
		_btn_tab_news.text = tr("뉴스")
	elif index == TAB_ALERTS:
		_btn_tab_alerts.text = tr("VI/CB")
	elif index == TAB_PORTFOLIO:
		_portfolio_unread = 0
		_btn_tab_portfolio.text = tr("포트폴리오")
	var tabs: Array[Button] = [_btn_tab_news, _btn_tab_alerts, _btn_tab_portfolio]
	for i: int in range(tabs.size()):
		tabs[i].remove_theme_color_override("font_color")
		tabs[i].remove_theme_color_override("font_hover_color")
		tabs[i].remove_theme_color_override("font_pressed_color")
		if i == index:
			ThemeSetup.apply_tab_active(tabs[i])
		else:
			ThemeSetup.apply_tab_inactive(tabs[i])

# ── VI/CB Alerts Panel ──

func _build_alerts_panel() -> VBoxContainer:
	var panel: VBoxContainer = VBoxContainer.new()
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	panel.add_child(header)
	var title: Label = Label.new()
	title.text = tr("VI / CB 알림")
	title.add_theme_font_size_override("font_size", 14)
	ThemeSetup.style_label_primary(title)
	header.add_child(title)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	_alerts_container = VBoxContainer.new()
	_alerts_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_alerts_container.add_theme_constant_override("separation", 2)
	scroll.add_child(_alerts_container)
	var empty: Label = Label.new()
	empty.text = tr("VI / CB 이벤트가 없습니다")
	empty.name = "EmptyLabel"
	ThemeSetup.style_label_dim(empty)
	_alerts_container.add_child(empty)
	return panel


func _add_alert_card(headline: String, body: String, severity: String, stock_id: String) -> void:
	var empty: Node = _alerts_container.get_node_or_null("EmptyLabel")
	if empty:
		empty.queue_free()
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	match severity:
		"MEGA": style.bg_color = ThemeSetup.ALERT_BG_MEGA; style.border_color = ThemeSetup.ALERT_BORDER_MEGA
		"LARGE": style.bg_color = ThemeSetup.ALERT_BG_LARGE; style.border_color = ThemeSetup.ALERT_BORDER_LARGE
		_: style.bg_color = ThemeSetup.BG_CARD; style.border_color = ThemeSetup.BORDER_DIM
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
	lbl_time.text = tr("틱 %d") % GameClock.get_current_tick()
	ThemeSetup.style_label_dim(lbl_time)
	vbox.add_child(lbl_time)
	_alerts_container.add_child(card)
	_alerts_container.move_child(card, 0)
	if stock_id != "":
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton:
				var mb: InputEventMouseButton = event as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					_select_stock(stock_id)
		)
	if _active_tab != TAB_ALERTS:
		_btn_tab_alerts.text = tr("VI/CB ●")


func _clear_alerts() -> void:
	if not _alerts_container:
		return
	for child: Node in _alerts_container.get_children():
		child.queue_free()
	var empty: Label = Label.new()
	empty.text = tr("VI / CB 이벤트가 없습니다")
	empty.name = "EmptyLabel"
	ThemeSetup.style_label_dim(empty)
	_alerts_container.add_child(empty)
	_btn_tab_alerts.text = tr("VI/CB")

# ── UI Construction ──

func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	var bg_style: StyleBoxFlat = StyleBoxFlat.new()
	bg_style.bg_color = ThemeSetup.BG_DARKEST
	add_theme_stylebox_override("panel", bg_style)

	var main_hbox: HBoxContainer = HBoxContainer.new()
	main_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_hbox.add_theme_constant_override("separation", 2)
	add_child(main_hbox)

	# ── Left: Stock List (15%) ──
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
	stock_title.text = tr("종목 리스트")
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
	_stock_list = StockListPanel.new()
	_stock_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_scroll.add_child(_stock_list)

	# ── Center: Status + Chart + Tabs (60%) ──
	var center_vbox: VBoxContainer = VBoxContainer.new()
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_vbox.size_flags_stretch_ratio = 0.60
	center_vbox.add_theme_constant_override("separation", 2)
	main_hbox.add_child(center_vbox)
	_status_bar = StatusBar.new()
	center_vbox.add_child(_status_bar)
	var chart_script: GDScript = load("res://src/ui/chart_renderer.gd") as GDScript
	_chart_renderer = chart_script.new() as Control
	_chart_renderer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chart_renderer.size_flags_stretch_ratio = 0.65
	center_vbox.add_child(_chart_renderer)
	_build_bottom_panel(center_vbox)

	# ── Right: Order Panel (13%) ──
	_order_panel = OrderPanel.new()
	main_hbox.add_child(_order_panel)

	# ── Overlays ──
	_build_overlays()


func _build_bottom_panel(parent: VBoxContainer) -> void:
	var bottom: VBoxContainer = VBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.size_flags_stretch_ratio = 0.35
	parent.add_child(bottom)
	var tab_bar: HBoxContainer = HBoxContainer.new()
	bottom.add_child(tab_bar)
	_btn_tab_news = Button.new(); _btn_tab_news.text = tr("뉴스")
	ThemeSetup.apply_tab_active(_btn_tab_news)
	_btn_tab_news.pressed.connect(func() -> void: _switch_bottom_tab(TAB_NEWS))
	tab_bar.add_child(_btn_tab_news)
	_btn_tab_alerts = Button.new(); _btn_tab_alerts.text = tr("VI/CB")
	ThemeSetup.apply_tab_inactive(_btn_tab_alerts)
	_btn_tab_alerts.pressed.connect(func() -> void: _switch_bottom_tab(TAB_ALERTS))
	tab_bar.add_child(_btn_tab_alerts)
	_btn_tab_portfolio = Button.new(); _btn_tab_portfolio.text = tr("포트폴리오")
	ThemeSetup.apply_tab_inactive(_btn_tab_portfolio)
	_btn_tab_portfolio.pressed.connect(func() -> void: _switch_bottom_tab(TAB_PORTFOLIO))
	tab_bar.add_child(_btn_tab_portfolio)
	var news_script: GDScript = load("res://src/ui/news_feed.gd") as GDScript
	_news_panel = news_script.new() as Control
	_news_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_child(_news_panel)
	_alerts_panel = _build_alerts_panel()
	_alerts_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_alerts_panel.visible = false
	bottom.add_child(_alerts_panel)
	var port_script: GDScript = load("res://src/ui/portfolio_view.gd") as GDScript
	_portfolio_panel = port_script.new() as Control
	_portfolio_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portfolio_panel.visible = false
	bottom.add_child(_portfolio_panel)


func _build_overlays() -> void:
	_pause_overlay = Panel.new()
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.visible = false
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pause_overlay)
	var pause_style: StyleBoxFlat = StyleBoxFlat.new()
	pause_style.bg_color = Color(0.0, 0.0, 0.0, 0.3)
	_pause_overlay.add_theme_stylebox_override("panel", pause_style)
	var pause_lbl: Label = Label.new()
	pause_lbl.text = tr("⏸ 일시정지")
	pause_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_lbl.add_theme_font_size_override("font_size", 48)
	pause_lbl.add_theme_color_override("font_color", ThemeSetup.TEXT_PRIMARY)
	_pause_overlay.add_child(pause_lbl)

	_settlement_reporter = SettlementReporter.new()
	add_child(_settlement_reporter)

	_level_up_banner = LevelUpBanner.new()
	add_child(_level_up_banner)

	_toast_manager = ToastManager.new()
	_toast_manager.anchor_left = 0.25
	_toast_manager.anchor_right = 0.75
	_toast_manager.anchor_top = 1.0
	_toast_manager.anchor_bottom = 1.0
	_toast_manager.offset_top = -200
	_toast_manager.offset_bottom = -30
	_toast_manager.add_theme_constant_override("separation", 6)
	_toast_manager.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_manager)

	# B-13 profit celebration effect — CanvasLayer(layer=5), added to TradingScreen tree
	# GDD: design/gdd/profit-celebration.md §3-7
	_profit_celebration = ProfitCelebration.new()
	add_child(_profit_celebration)

	# TR4 margin call warning popup — CanvasLayer(layer=6)
	# Self-connects to LeverageManager.on_margin_call in its _ready(). GDD leverage-trading.md §3-3.
	_margin_call_popup = MarginCallPopup.new()
	add_child(_margin_call_popup)
