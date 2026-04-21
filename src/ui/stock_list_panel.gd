## StockListPanel — 46종목 실시간 가격/등락률 리스트.
## 성능 설계 (GDD trading-screen.md §10-4):
##   _row_nodes  — _ready() 1회 빌드. 런타임 get_children() 없음.
##   _last_prices — dirty flag. 가격 미변동 행은 틱마다 갱신 skip.
##   _sel_style — StyleBoxFlat _ready() 1회 캐시. 비선택은 remove_theme_stylebox_override (테마 상속).
##   _held_stocks — on_order_filled 시에만 갱신.
class_name StockListPanel
extends VBoxContainer

## Emitted when the user clicks a stock row.
signal stock_selected(stock_id: String)

## Row child indices — _create_row() 빌드 순서와 동기화. 변경 시 양쪽 모두 수정.
const _COL_MARKER: int = 0  ## ▶ selection marker
const _COL_TICKER: int = 1  ## name(ticker) label
const _COL_PRICE: int  = 2  ## price label
const _COL_CHANGE: int = 3  ## change % label
const _COL_HELD: int   = 4  ## ★ held marker

var _stock_ids: Array[String] = []
var _row_nodes: Array[HBoxContainer] = []   ## 인덱스 == _stock_ids 인덱스
var _last_prices: Dictionary = {}           ## stock_id -> int (dirty flag)
var _prev_close_prices: Dictionary = {}     ## stock_id -> int
var _held_stocks: Dictionary = {}           ## stock_id -> true
var _selected_id: String = ""
var _sel_style: StyleBoxFlat               ## 선택 행 강조 — 1회 캐시
var _id_to_index: Dictionary = {}           ## stock_id -> Array index (O(1) lookup)


func _ready() -> void:
	_sel_style = ThemeSetup.make_panel_style(ThemeSetup.BG_SELECTED, 3, ThemeSetup.BORDER_BRIGHT)
	_stock_ids = StockDatabase.get_all_stock_ids()
	for i: int in range(_stock_ids.size()):
		_id_to_index[_stock_ids[i]] = i
	_init_prev_close()
	_build_rows()
	PriceEngine.on_price_updated.connect(_on_price_updated)
	OrderEngine.on_order_filled.connect(_on_order_filled)
	# 생성 시점의 PriceEngine 상태를 한 번 읽어 초기 렌더.
	# 신규 게임: init_first_season() 완료 후 MainScreen이 생성되므로 base_price를 그린다.
	# 로드 게임: initialize_for_load() 완료 후 MainScreen이 생성되므로 복원 가격을 그린다.
	_on_price_updated(0)


func _init_prev_close() -> void:
	for sid: String in _stock_ids:
		var limits: Dictionary = PriceEngine.get_daily_limits(sid)
		_prev_close_prices[sid] = limits.get("prev_close", 0)


func _build_rows() -> void:
	for sid: String in _stock_ids:
		var row: HBoxContainer = _create_row(sid)
		add_child(row)
		_row_nodes.append(row)


func _create_row(stock_id: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.custom_minimum_size.y = 38
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_select(stock_id)
	)
	var lbl_marker: Label = Label.new()
	lbl_marker.text = "  "
	lbl_marker.custom_minimum_size.x = 16
	lbl_marker.add_theme_color_override("font_color", ThemeSetup.BTN_ACCENT_HOVER)
	row.add_child(lbl_marker)           ## [0] ▶ marker
	var lbl_ticker: Label = Label.new()
	var stock_data: StockData = StockDatabase.get_stock(stock_id)
	lbl_ticker.text = stock_data.get_display_name() if stock_data != null else stock_id
	lbl_ticker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ThemeSetup.style_label_primary(lbl_ticker)
	row.add_child(lbl_ticker)           ## [1] name(ticker)
	var lbl_price: Label = Label.new()
	lbl_price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ThemeSetup.style_label_primary(lbl_price)
	row.add_child(lbl_price)            ## [2] price
	var lbl_change: Label = Label.new()
	lbl_change.text = " 0.0%"
	lbl_change.custom_minimum_size.x = 65
	lbl_change.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ThemeSetup.style_label_secondary(lbl_change)
	row.add_child(lbl_change)           ## [3] change %
	var lbl_held: Label = Label.new()
	lbl_held.custom_minimum_size.x = 16
	lbl_held.add_theme_color_override("font_color", Color(0.90, 0.65, 0.05))
	row.add_child(lbl_held)             ## [4] ★ held marker
	return row


func _on_price_updated(_tick: int) -> void:
	for i: int in range(_stock_ids.size()):
		var sid: String = _stock_ids[i]
		var price: int = PriceEngine.get_current_price(sid)
		if _last_prices.get(sid, -1) == price:
			continue   ## dirty flag: 가격 미변동 → skip
		_last_prices[sid] = price
		_update_row(i, sid, price)


func _update_row(idx: int, stock_id: String, price: int) -> void:
	var row: HBoxContainer = _row_nodes[idx]
	var prev_close: int = _prev_close_prices.get(stock_id, price)
	var change_pct: float = 0.0
	if prev_close > 0:
		change_pct = float(price - prev_close) / float(prev_close) * 100.0
	(row.get_child(_COL_PRICE) as Label).text = FormatUtils.currency(price)
	_apply_change_label(row.get_child(_COL_CHANGE) as Label, change_pct)
	(row.get_child(_COL_HELD) as Label).text = "★" if _held_stocks.has(stock_id) else ""


func _apply_change_label(lbl: Label, change_pct: float) -> void:
	var arrow: String = "▲" if change_pct > 0.0 else ("▼" if change_pct < 0.0 else "─")
	lbl.text = "%s%+.1f%%" % [arrow, change_pct]
	if change_pct > 0.0:
		lbl.add_theme_color_override("font_color", ThemeSetup.PROFIT_RED)
	elif change_pct < 0.0:
		lbl.add_theme_color_override("font_color", ThemeSetup.LOSS_BLUE)
	else:
		lbl.add_theme_color_override("font_color", ThemeSetup.NEUTRAL_GRAY)


func _select(stock_id: String) -> void:
	var prev_id: String = _selected_id
	_selected_id = stock_id
	_refresh_highlight(prev_id)
	_refresh_highlight(stock_id)
	stock_selected.emit(stock_id)


func _refresh_highlight(stock_id: String) -> void:
	var idx: int = _id_to_index.get(stock_id, -1)
	if idx < 0:
		return
	var row: HBoxContainer = _row_nodes[idx]
	(row.get_child(0) as Label).text = "▶" if stock_id == _selected_id else "  "
	if stock_id == _selected_id:
		row.add_theme_stylebox_override("panel", _sel_style)
	else:
		row.remove_theme_stylebox_override("panel")


## Called by TradingScreen when selection changes externally (keyboard shortcut).
func set_selected(stock_id: String) -> void:
	if stock_id != _selected_id:
		_select(stock_id)


## Called by TradingScreen on market close to snapshot prev-close prices.
## 스냅샷 직후 즉시 재렌더 — 장 종료 시점부터 등락률 0%로 표시 (save/load 후와 동일한 뷰).
func snapshot_prev_close() -> void:
	for sid: String in _stock_ids:
		_prev_close_prices[sid] = PriceEngine.get_current_price(sid)
	_last_prices.clear()   ## dirty flag 초기화 → 모든 행 재렌더 강제
	_on_price_updated(0)   ## 장 종료 즉시 0% 등락률 표시


func _on_order_filled(_order: Dictionary) -> void:
	_held_stocks.clear()
	for h: Dictionary in PortfolioManager.get_all_holdings():
		_held_stocks[h["stock_id"]] = true
	_last_prices.clear()   ## 다음 price_updated에서 보유 마커 포함 전체 재렌더
