## MarginCallPopup — 증거금 비율 경고 팝업 (TR4 레버리지). GDD leverage-trading.md §3-3.
## CanvasLayer(layer=6). LeverageManager.on_margin_call 시그널 수신 → 표시.
## 비율 < forced_liq_threshold 시 강제청산 카운트다운 표시.
## TradingScreen에서 인스턴스화 + add_child. 세션 동안 상주.
## See: design/gdd/leverage-trading.md §3-3, AC-15, AC-16
class_name MarginCallPopup
extends CanvasLayer

# ── Constants ──

const SHOW_DURATION_SEC: float = 6.0
const FORCED_LIQ_COUNTDOWN_SEC: float = 3.0

# ── Node References ──

var _panel: PanelContainer
var _lbl_title: Label
var _lbl_stock: Label
var _lbl_margin: Label
var _lbl_countdown: Label
var _hide_tween: Tween
var _countdown_tween: Tween

# ── State ──

var _is_forced_liq_mode: bool = false

# ── Lifecycle ──

func _ready() -> void:
	layer = 6
	_build_ui()
	LeverageManager.on_margin_call.connect(_on_margin_call)
	LeverageManager.on_leverage_forced_liquidation.connect(_on_forced_liquidation)
	_panel.visible = false


## 마진콜 경고 오버레이와 강제 청산 안내 팝업 패널을 구성.
func _build_ui() -> void:
	# Dark overlay — subtle, non-blocking
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-320.0, 16.0)
	_panel.custom_minimum_size = Vector2(300.0, 0.0)
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	root.add_child(_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	_lbl_title = Label.new()
	_lbl_title.text = tr("⚠ 마진콜 경고")
	_lbl_title.add_theme_font_size_override("font_size", 14)
	_lbl_title.add_theme_color_override("font_color", Color(0.95, 0.60, 0.10))
	vbox.add_child(_lbl_title)

	_lbl_stock = Label.new()
	_lbl_stock.add_theme_font_size_override("font_size", 12)
	_lbl_stock.add_theme_color_override("font_color", ThemeSetup.TEXT_PRIMARY)
	vbox.add_child(_lbl_stock)

	_lbl_margin = Label.new()
	_lbl_margin.add_theme_font_size_override("font_size", 12)
	_lbl_margin.add_theme_color_override("font_color", ThemeSetup.TEXT_SECONDARY)
	vbox.add_child(_lbl_margin)

	_lbl_countdown = Label.new()
	_lbl_countdown.add_theme_font_size_override("font_size", 13)
	_lbl_countdown.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	_lbl_countdown.visible = false
	vbox.add_child(_lbl_countdown)


func _make_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.06, 0.02, 0.92)
	style.border_color = Color(0.95, 0.60, 0.10)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12.0)
	return style

# ── Public API ──

## Show a margin call warning for [param stock_name] at [param equity_ratio].
## [param forced]: true when in forced-liquidation zone → shows countdown.
func show_warning(stock_name: String, equity_ratio: float, forced: bool = false) -> void:
	_is_forced_liq_mode = forced
	_lbl_title.text = tr("긴급 추가 증거금 납부") if forced else tr("⚠ 마진콜 경고")
	_lbl_title.add_theme_color_override("font_color",
		ThemeSetup.PROFIT_RED if forced else Color(0.95, 0.60, 0.10))
	_lbl_stock.text = stock_name
	_lbl_margin.text = tr("현재 증거금 비율: %.1f%%") % (equity_ratio * 100.0)

	if forced:
		_lbl_countdown.visible = true
		_run_countdown()
	else:
		_lbl_countdown.visible = false

	_panel.visible = true
	_start_hide_timer()


## Hide popup immediately (e.g. on screen change).
func cancel() -> void:
	_cancel_tweens()
	_panel.visible = false

# ── Internal ──

func _start_hide_timer() -> void:
	if _hide_tween and _hide_tween.is_valid():
		_hide_tween.kill()
	_hide_tween = create_tween()
	_hide_tween.tween_interval(SHOW_DURATION_SEC)
	_hide_tween.tween_callback(func() -> void: _panel.visible = false)


func _run_countdown() -> void:
	if _countdown_tween and _countdown_tween.is_valid():
		_countdown_tween.kill()
	var elapsed: float = 0.0
	_lbl_countdown.text = tr("자동 청산까지 %.0f초") % FORCED_LIQ_COUNTDOWN_SEC
	_countdown_tween = create_tween()
	_countdown_tween.tween_method(
		func(t: float) -> void:
			var remaining: float = FORCED_LIQ_COUNTDOWN_SEC - t
			_lbl_countdown.text = tr("자동 청산까지 %.0f초") % maxf(remaining, 0.0),
		elapsed,
		FORCED_LIQ_COUNTDOWN_SEC,
		FORCED_LIQ_COUNTDOWN_SEC
	)


func _cancel_tweens() -> void:
	if _hide_tween and _hide_tween.is_valid():
		_hide_tween.kill()
	if _countdown_tween and _countdown_tween.is_valid():
		_countdown_tween.kill()

# ── Signal Handlers ──

func _on_margin_call(stock_id: String, _multiplier: int, equity_ratio: float) -> void:
	var stock_data: StockData = StockDatabase.get_stock(stock_id)
	var stock_name: String = stock_data.get_display_name() if stock_data != null else stock_id
	show_warning(stock_name, equity_ratio, false)


func _on_forced_liquidation(stock_id: String, _multiplier: int, _net_proceeds: int) -> void:
	var stock_data: StockData = StockDatabase.get_stock(stock_id)
	var stock_name: String = stock_data.get_display_name() if stock_data != null else stock_id
	# Show brief forced-liq notice with red title (countdown already done or n/a here)
	_lbl_title.text = tr("강제 청산 완료")
	_lbl_title.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	_lbl_stock.text = stock_name
	_lbl_margin.text = tr("증거금 부족으로 자동 청산되었습니다.")
	_lbl_countdown.visible = false
	_panel.visible = true
	_start_hide_timer()
