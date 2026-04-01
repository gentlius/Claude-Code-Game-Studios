## Chart Renderer — Draws candlestick chart + volume bars from PriceEngine data.
## Hosted inside TradingScreen's center area. Subscribes to tick signals.
## See: design/gdd/chart-renderer.md
extends Control

# ── Enums ──

enum ChartState { UNLOADED, LOADING, LIVE, PAUSED, STATIC }
## 1 tick = 15 game-seconds → 4 ticks = 1 min, 20 ticks = 5 min, 60 ticks = 15 min
enum Timeframe { M1 = 4, M5 = 20, M15 = 60, D1 = 390 }

# ── Constants (Tuning Knobs from GDD) ──

const DEFAULT_VISIBLE_CANDLES: int = 60
const MIN_VISIBLE_CANDLES: int = 20
const MAX_VISIBLE_CANDLES: int = 200
const Y_AXIS_PADDING: float = 0.05
const MIN_Y_RANGE_RATIO: float = 0.02
const TARGET_GRID_LINES: int = 5
const NICE_MULTIPLIERS: Array[int] = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000]
const CANDLE_UP_COLOR: Color = Color(0.906, 0.298, 0.235)    # #E74C3C red
const CANDLE_DOWN_COLOR: Color = Color(0.204, 0.580, 0.859)  # #3498DB blue
const CANDLE_NEUTRAL_COLOR: Color = Color(0.6, 0.6, 0.6)
const HEADER_HEIGHT: float = 40.0
const RENDER_SKIP_AT_SPEED: int = 2  ## Skip frames at 2x+ speed

# ── State ──

var _chart_state: ChartState = ChartState.UNLOADED
var _stock_id: String = ""
var _timeframe: Timeframe = Timeframe.M1
var _visible_count: int = DEFAULT_VISIBLE_CANDLES
var _scroll_offset: int = 0  ## 0 = latest candles visible
var _auto_scroll: bool = true

# ── Data ──

var _tick_prices: Array[int] = []
var _tick_volumes: Array[float] = []
var _candles: Array[Dictionary] = []  ## Aggregated candle data
var _ohlcv_daily: Array[Dictionary] = []
var _dirty: bool = true
var _tick_counter: int = 0  ## For render skip

# ── Crosshair ──

var _crosshair_pos: Vector2 = Vector2(-1, -1)
var _show_crosshair: bool = false

# ── Chart geometry (computed per draw) ──

var _chart_rect: Rect2 = Rect2()  ## Candle area
var _volume_rect: Rect2 = Rect2()  ## Volume bar area
var _price_min: float = 0.0
var _price_max: float = 0.0
var _volume_max: float = 1.0

# ── Node references ──

var _header_bar: HBoxContainer
var _lbl_stock_name: Label
var _lbl_current_price: Label
var _lbl_change: Label
var _btn_tf_1t: Button
var _btn_tf_5t: Button
var _btn_tf_15t: Button
var _btn_tf_1d: Button
var _btn_go_latest: Button

# ── Lifecycle ──

func _ready() -> void:
	_build_header()
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameClock.on_tick.connect(_on_tick)
	GameClock.on_market_state_changed.connect(_on_market_state_changed)
	PriceEngine.on_price_updated.connect(_on_price_updated)
	clip_contents = true


func _build_header() -> void:
	_header_bar = HBoxContainer.new()
	_header_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_header_bar.offset_bottom = HEADER_HEIGHT
	_header_bar.add_theme_constant_override("separation", 8)
	var header_style: StyleBoxFlat = ThemeSetup.make_panel_style(ThemeSetup.BG_PANEL, 0, ThemeSetup.BORDER_DIM)
	_header_bar.add_theme_stylebox_override("panel", header_style)
	add_child(_header_bar)

	_lbl_stock_name = Label.new()
	_lbl_stock_name.text = "종목 선택"
	_lbl_stock_name.add_theme_font_size_override("font_size", 15)
	ThemeSetup.style_label_primary(_lbl_stock_name)
	_header_bar.add_child(_lbl_stock_name)

	_lbl_current_price = Label.new()
	_lbl_current_price.text = ""
	_lbl_current_price.add_theme_font_size_override("font_size", 15)
	ThemeSetup.style_label_primary(_lbl_current_price)
	_header_bar.add_child(_lbl_current_price)

	_lbl_change = Label.new()
	_lbl_change.text = ""
	_header_bar.add_child(_lbl_change)

	# Spacer
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_bar.add_child(spacer)

	# Timeframe buttons
	_btn_tf_1t = Button.new()
	_btn_tf_1t.text = "1분"
	ThemeSetup.apply_button_theme(_btn_tf_1t)
	_btn_tf_1t.pressed.connect(func() -> void: set_timeframe(Timeframe.M1))
	_header_bar.add_child(_btn_tf_1t)

	_btn_tf_5t = Button.new()
	_btn_tf_5t.text = "5분"
	ThemeSetup.apply_button_theme(_btn_tf_5t)
	_btn_tf_5t.pressed.connect(func() -> void: set_timeframe(Timeframe.M5))
	_header_bar.add_child(_btn_tf_5t)

	_btn_tf_15t = Button.new()
	_btn_tf_15t.text = "15분"
	ThemeSetup.apply_button_theme(_btn_tf_15t)
	_btn_tf_15t.pressed.connect(func() -> void: set_timeframe(Timeframe.M15))
	_header_bar.add_child(_btn_tf_15t)

	_btn_tf_1d = Button.new()
	_btn_tf_1d.text = "1일"
	ThemeSetup.apply_button_theme(_btn_tf_1d)
	_btn_tf_1d.pressed.connect(func() -> void: set_timeframe(Timeframe.D1))
	_header_bar.add_child(_btn_tf_1d)

	# Go-to-latest button (hidden by default)
	_btn_go_latest = Button.new()
	_btn_go_latest.text = "현재로 이동 →"
	_btn_go_latest.visible = false
	ThemeSetup.apply_accent_button(_btn_go_latest)
	_btn_go_latest.pressed.connect(func() -> void:
		_auto_scroll = true
		_scroll_offset = 0
		_dirty = true
		_btn_go_latest.visible = false
		queue_redraw()
	)
	_header_bar.add_child(_btn_go_latest)


# ── Public API ──

## Load chart data for a stock. Called when player selects a stock.
func load_stock(stock_id: String) -> void:
	_stock_id = stock_id
	_chart_state = ChartState.LOADING
	_scroll_offset = 0
	_auto_scroll = true

	# Load data from PriceEngine
	_tick_prices = PriceEngine.get_tick_buffer(stock_id)
	_tick_volumes = PriceEngine.get_tick_volumes(stock_id)
	_ohlcv_daily = PriceEngine.get_ohlcv_history(stock_id)

	_aggregate_candles()
	_update_header()

	# Determine initial state from Game Clock
	var ms: GameClock.MarketState = GameClock.get_market_state()
	if ms == GameClock.MarketState.MARKET_OPEN:
		_chart_state = ChartState.LIVE
	elif ms == GameClock.MarketState.PAUSED:
		_chart_state = ChartState.PAUSED
	else:
		_chart_state = ChartState.STATIC

	_dirty = true
	queue_redraw()


func set_timeframe(tf: Timeframe) -> void:
	_timeframe = tf
	_aggregate_candles()
	_scroll_offset = 0
	_auto_scroll = true
	_dirty = true
	_btn_go_latest.visible = false
	queue_redraw()


# ── Signal Handlers ──

func _on_tick(_tick: int, _day: int, _week: int) -> void:
	if _stock_id == "" or _chart_state == ChartState.UNLOADED:
		return
	_tick_counter += 1


func _on_price_updated(_tick: int) -> void:
	if _stock_id == "" or _chart_state != ChartState.LIVE:
		return

	# Render skip at high speed
	var speed: float = GameClock.get_speed_multiplier()
	if speed >= float(RENDER_SKIP_AT_SPEED) and _tick_counter % 2 != 0:
		return

	# Refresh data
	_tick_prices = PriceEngine.get_tick_buffer(_stock_id)
	_tick_volumes = PriceEngine.get_tick_volumes(_stock_id)
	_aggregate_candles()
	_update_header()
	_dirty = true
	queue_redraw()


func _on_market_state_changed(
	new_state: GameClock.MarketState, _prev: GameClock.MarketState
) -> void:
	match new_state:
		GameClock.MarketState.MARKET_OPEN:
			_chart_state = ChartState.LIVE
		GameClock.MarketState.PAUSED:
			_chart_state = ChartState.PAUSED
		GameClock.MarketState.MARKET_CLOSED, GameClock.MarketState.DAY_TRANSITION, \
		GameClock.MarketState.WEEK_END, GameClock.MarketState.SEASON_END, \
		GameClock.MarketState.PRE_MARKET:
			if _chart_state != ChartState.UNLOADED:
				_chart_state = ChartState.STATIC


# ── Input ──

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom(-5)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(5)
	elif event is InputEventMouseMotion:
		_crosshair_pos = (event as InputEventMouseMotion).position
		_show_crosshair = true
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_show_crosshair = false
		queue_redraw()


func _zoom(delta: int) -> void:
	_visible_count = clampi(_visible_count + delta, MIN_VISIBLE_CANDLES, MAX_VISIBLE_CANDLES)
	_dirty = true
	queue_redraw()


# ── Candle Aggregation ──

func _aggregate_candles() -> void:
	_candles.clear()

	if _timeframe == Timeframe.D1:
		# Use daily OHLCV from PriceEngine
		_candles = _ohlcv_daily.duplicate()
		# Add today's intra-day candle if we have tick data
		if _tick_prices.size() > 0:
			var today_candle: Dictionary = _aggregate_range(0, _tick_prices.size() - 1)
			_candles.append(today_candle)
		return

	# For intra-day timeframes, aggregate from tick data
	var tf: int = int(_timeframe)
	if _tick_prices.size() == 0:
		return

	var i: int = 0
	while i < _tick_prices.size():
		var end: int = mini(i + tf - 1, _tick_prices.size() - 1)
		var candle: Dictionary = _aggregate_range(i, end)
		_candles.append(candle)
		i += tf


func _aggregate_range(start: int, end: int) -> Dictionary:
	var open_price: int = _tick_prices[start]
	var close_price: int = _tick_prices[end]
	var high_price: int = open_price
	var low_price: int = open_price
	var volume: float = 0.0

	for j: int in range(start, end + 1):
		var p: int = _tick_prices[j]
		if p > high_price:
			high_price = p
		if p < low_price:
			low_price = p
		if j < _tick_volumes.size():
			volume += _tick_volumes[j]

	return {
		"open": open_price,
		"high": high_price,
		"low": low_price,
		"close": close_price,
		"volume": int(volume),
		"tick_start": start,
		"tick_end": end,
	}


# ── Header Update ──

func _update_header() -> void:
	if _stock_id == "":
		_lbl_stock_name.text = "종목 선택"
		_lbl_current_price.text = ""
		_lbl_change.text = ""
		return

	var stock: StockData = StockDatabase.get_stock(_stock_id)
	if stock == null:
		return

	var price: int = PriceEngine.get_current_price(_stock_id)
	_lbl_stock_name.text = "%s (%s)" % [stock.name_ko, _stock_id]
	_lbl_current_price.text = "₩%s" % _format_number(price)

	var base: int = stock.base_price
	if base > 0:
		var pct: float = float(price - base) / float(base) * 100.0
		_lbl_change.text = "%+.1f%%" % pct
		if pct > 0.0:
			_lbl_change.add_theme_color_override("font_color", CANDLE_UP_COLOR)
		elif pct < 0.0:
			_lbl_change.add_theme_color_override("font_color", CANDLE_DOWN_COLOR)
		else:
			_lbl_change.add_theme_color_override("font_color", CANDLE_NEUTRAL_COLOR)


# ── Rendering ──

func _draw() -> void:
	if _candles.size() == 0:
		_draw_empty_chart()
		return

	_compute_layout()
	_compute_price_range()
	_draw_background()
	_draw_grid()
	_draw_candles()
	_draw_volume_bars()
	_draw_axes()

	if _show_crosshair:
		_draw_crosshair()


func _draw_empty_chart() -> void:
	var center: Vector2 = size / 2.0
	draw_string(
		ThemeDB.fallback_font, center - Vector2(60, 0),
		"차트 데이터 없음", HORIZONTAL_ALIGNMENT_CENTER,
		-1, 14, CANDLE_NEUTRAL_COLOR
	)


func _compute_layout() -> void:
	# Chart area: from header to 70% height
	# Volume area: 70% to 100% height
	var chart_top: float = HEADER_HEIGHT + 4.0
	var total_height: float = size.y - chart_top
	var chart_height: float = total_height * 0.70
	var volume_height: float = total_height * 0.30
	var left: float = 0.0
	var width: float = size.x - 60.0  # Right margin for Y-axis labels

	_chart_rect = Rect2(left, chart_top, width, chart_height)
	_volume_rect = Rect2(left, chart_top + chart_height, width, volume_height)


func _compute_price_range() -> void:
	var visible: Array[Dictionary] = _get_visible_candles()
	if visible.size() == 0:
		_price_min = 0.0
		_price_max = 100.0
		_volume_max = 1.0
		return

	_price_min = INF
	_price_max = -INF
	_volume_max = 1.0

	for c: Dictionary in visible:
		if float(c["low"]) < _price_min:
			_price_min = float(c["low"])
		if float(c["high"]) > _price_max:
			_price_max = float(c["high"])
		if float(c["volume"]) > _volume_max:
			_volume_max = float(c["volume"])

	var price_range: float = _price_max - _price_min
	var min_range: float = _price_min * MIN_Y_RANGE_RATIO
	var effective_range: float = maxf(price_range, min_range)
	_price_min -= effective_range * Y_AXIS_PADDING
	_price_max += effective_range * Y_AXIS_PADDING


func _get_visible_candles() -> Array[Dictionary]:
	var total: int = _candles.size()
	if total == 0:
		return []

	var start_idx: int
	var end_idx: int

	if _auto_scroll:
		end_idx = total
		start_idx = maxi(0, end_idx - _visible_count)
	else:
		start_idx = maxi(0, total - _visible_count - _scroll_offset)
		end_idx = mini(total, start_idx + _visible_count)

	var result: Array[Dictionary] = []
	for i: int in range(start_idx, end_idx):
		result.append(_candles[i])
	return result


func _price_to_y(price: float) -> float:
	if _price_max <= _price_min:
		return _chart_rect.position.y + _chart_rect.size.y * 0.5
	return _chart_rect.position.y + _chart_rect.size.y * (1.0 - (price - _price_min) / (_price_max - _price_min))


func _volume_to_y(volume: float) -> float:
	if _volume_max <= 0.0:
		return _volume_rect.position.y + _volume_rect.size.y
	var ratio: float = volume / _volume_max
	return _volume_rect.position.y + _volume_rect.size.y * (1.0 - ratio)


func _draw_background() -> void:
	draw_rect(_chart_rect, ThemeSetup.BG_DARKEST, true)
	draw_rect(_volume_rect, Color(0.06, 0.06, 0.08), true)


func _draw_grid() -> void:
	var grid_color: Color = ThemeSetup.BORDER_DIM

	# Horizontal price grid lines — aligned to tick size multiples (GDD 2-2)
	var nice_step: int = _compute_nice_step()
	if nice_step <= 0:
		return

	var first_line: int = ceili(_price_min / float(nice_step)) * nice_step
	var line_price: int = first_line
	while float(line_price) <= _price_max:
		var y: float = _price_to_y(float(line_price))
		draw_line(
			Vector2(_chart_rect.position.x, y),
			Vector2(_chart_rect.position.x + _chart_rect.size.x, y),
			grid_color
		)
		# Price label on right
		draw_string(
			ThemeDB.fallback_font,
			Vector2(_chart_rect.position.x + _chart_rect.size.x + 4, y + 4),
			_format_number(line_price), HORIZONTAL_ALIGNMENT_LEFT,
			-1, 10, Color(0.5, 0.5, 0.5)
		)
		line_price += nice_step


## Finds a "nice" grid step that is a multiple of the current tick size (GDD 2-2).
func _compute_nice_step() -> int:
	var price_range: float = _price_max - _price_min
	if price_range <= 0.0:
		return 100
	var raw_step: float = price_range / float(TARGET_GRID_LINES)
	var price_mid: int = roundi((_price_min + _price_max) / 2.0)
	var tick_size: int = PriceEngine.get_tick_size(price_mid)

	for m: int in NICE_MULTIPLIERS:
		var candidate: int = tick_size * m
		if float(candidate) >= raw_step:
			return candidate

	return tick_size * NICE_MULTIPLIERS[NICE_MULTIPLIERS.size() - 1]


func _draw_candles() -> void:
	var visible: Array[Dictionary] = _get_visible_candles()
	if visible.size() == 0:
		return

	var candle_width: float = _chart_rect.size.x / float(_visible_count)
	var body_width: float = maxf(candle_width * 0.6, 1.0)
	var wick_width: float = maxf(1.0, candle_width * 0.1)

	var prev_close_price: float = -1.0
	for i: int in range(visible.size()):
		var c: Dictionary = visible[i]
		var x_center: float = _chart_rect.position.x + (float(i) + 0.5) * candle_width

		var open_price: float = float(c["open"])
		var close_price: float = float(c["close"])
		var high_price: float = float(c["high"])
		var low_price: float = float(c["low"])

		var y_open: float = _price_to_y(open_price)
		var y_close: float = _price_to_y(close_price)
		var y_high: float = _price_to_y(high_price)
		var y_low: float = _price_to_y(low_price)

		var color: Color
		var is_flat: bool = absf(close_price - open_price) < 0.01
		if is_flat and prev_close_price >= 0.0:
			# 1T candles: open==close, so compare against previous candle
			if close_price > prev_close_price:
				color = CANDLE_UP_COLOR
			elif close_price < prev_close_price:
				color = CANDLE_DOWN_COLOR
			else:
				color = CANDLE_NEUTRAL_COLOR
		elif close_price > open_price:
			color = CANDLE_UP_COLOR
		elif close_price < open_price:
			color = CANDLE_DOWN_COLOR
		else:
			color = CANDLE_NEUTRAL_COLOR
		prev_close_price = close_price

		# Wick (high to low) — enforce minimum height for visibility
		var wick_h: float = maxf(y_low - y_high, 3.0)
		var wick_top: float = y_high if y_low > y_high else y_high - 1.5
		draw_rect(
			Rect2(x_center - wick_width * 0.5, wick_top, wick_width, wick_h),
			color, true
		)

		# Body — enforce minimum height so 1T candles are visible bars, not dots
		var body_top: float = minf(y_open, y_close)
		var body_height: float = maxf(absf(y_open - y_close), 4.0)
		if is_flat:
			body_top -= 2.0  # Center the minimum-height bar on the price level
		draw_rect(
			Rect2(x_center - body_width * 0.5, body_top, body_width, body_height),
			color, true
		)


func _draw_volume_bars() -> void:
	var visible: Array[Dictionary] = _get_visible_candles()
	if visible.size() == 0:
		return

	var bar_width: float = _chart_rect.size.x / float(_visible_count)
	var actual_width: float = maxf(bar_width * 0.6, 1.0)
	var bottom_y: float = _volume_rect.position.y + _volume_rect.size.y

	for i: int in range(visible.size()):
		var c: Dictionary = visible[i]
		var x_center: float = _volume_rect.position.x + (float(i) + 0.5) * bar_width
		var vol: float = float(c["volume"])

		if vol <= 0.0:
			continue

		var y_top: float = _volume_to_y(vol)
		var color: Color
		if float(c["close"]) >= float(c["open"]):
			color = CANDLE_UP_COLOR
		else:
			color = CANDLE_DOWN_COLOR
		color.a = 0.5

		draw_rect(
			Rect2(x_center - actual_width * 0.5, y_top, actual_width, bottom_y - y_top),
			color, true
		)


func _draw_axes() -> void:
	var axis_color: Color = Color(0.3, 0.3, 0.35)
	# Y-axis right border
	draw_line(
		Vector2(_chart_rect.position.x + _chart_rect.size.x, _chart_rect.position.y),
		Vector2(_chart_rect.position.x + _chart_rect.size.x, _volume_rect.position.y + _volume_rect.size.y),
		axis_color
	)
	# Separator between chart and volume
	draw_line(
		Vector2(_chart_rect.position.x, _volume_rect.position.y),
		Vector2(_chart_rect.position.x + _chart_rect.size.x, _volume_rect.position.y),
		axis_color
	)


func _draw_crosshair() -> void:
	if _crosshair_pos.x < _chart_rect.position.x or _crosshair_pos.x > _chart_rect.position.x + _chart_rect.size.x:
		return
	if _crosshair_pos.y < _chart_rect.position.y or _crosshair_pos.y > _volume_rect.position.y + _volume_rect.size.y:
		return

	var ch_color: Color = Color(0.5, 0.5, 0.5, 0.5)

	# Horizontal line
	draw_line(
		Vector2(_chart_rect.position.x, _crosshair_pos.y),
		Vector2(_chart_rect.position.x + _chart_rect.size.x, _crosshair_pos.y),
		ch_color
	)
	# Vertical line
	draw_line(
		Vector2(_crosshair_pos.x, _chart_rect.position.y),
		Vector2(_crosshair_pos.x, _volume_rect.position.y + _volume_rect.size.y),
		ch_color
	)

	# Price label at crosshair Y
	if _crosshair_pos.y >= _chart_rect.position.y and _crosshair_pos.y <= _chart_rect.position.y + _chart_rect.size.y:
		var raw_price: float = _price_min + (_price_max - _price_min) * (1.0 - (_crosshair_pos.y - _chart_rect.position.y) / _chart_rect.size.y)
		var snapped_price: int = PriceEngine.round_to_tick(raw_price)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(_chart_rect.position.x + _chart_rect.size.x + 4, _crosshair_pos.y + 4),
			"₩%s" % _format_number(snapped_price), HORIZONTAL_ALIGNMENT_LEFT,
			-1, 10, Color(0.9, 0.9, 0.2)
		)


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
