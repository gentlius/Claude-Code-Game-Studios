## Chart Renderer — Draws candlestick chart + volume bars from PriceEngine data.
## Hosted inside TradingScreen's center area. Subscribes to tick signals.
## See: design/gdd/chart-renderer.md
extends Control

# ── Signals ──

## Emitted when player clicks the chart area. Sends the snapped price at click Y.
signal price_clicked(price: int)

# ── Enums ──

enum ChartState { UNLOADED, LOADING, LIVE, PAUSED, STATIC }
## Ticks per candle. Derived from GameClock.TICKS_PER_MINUTE (4).
## M1=4, M5=20, M15=60, D1=TICKS_PER_DAY (enum requires literal values).
enum Timeframe { M1 = 4, M5 = 20, M15 = 60, D1 = 1560 }

# ── Constants (Tuning Knobs from GDD) ──

const DEFAULT_VISIBLE_CANDLES: int = 60
const MIN_VISIBLE_CANDLES: int = 20
const MAX_VISIBLE_CANDLES: int = 200
const Y_AXIS_PADDING: float = 0.05
const MIN_Y_RANGE_RATIO: float = 0.02
const TARGET_GRID_LINES: int = 5
const NICE_MULTIPLIERS: Array[int] = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000]
const CANDLE_UP_COLOR: Color = Color(0.92, 0.22, 0.20)       # #EB3833 red (Toss)
const CANDLE_DOWN_COLOR: Color = Color(0.18, 0.42, 0.90)     # #2E6BE6 blue (Toss)
const CANDLE_NEUTRAL_COLOR: Color = Color(0.65, 0.65, 0.68)  # #A6A6AE
const HEADER_HEIGHT: float = 40.0
const RENDER_SKIP_AT_SPEED: int = 2  ## Skip frames at 2x+ speed

## Moving average periods (candle count) and colors — shown when skill A1 is unlocked.
const MA_PERIODS: Array[int] = [5, 20, 60]
const MA_COLORS: Array[Color] = [
	Color(0.95, 0.60, 0.15),  # MA5: orange
	Color(0.20, 0.70, 0.30),  # MA20: green
	Color(0.55, 0.30, 0.85),  # MA60: purple
]

## RSI / MACD sub-panel constants — shown when skill A2 is unlocked.
const RSI_PERIOD: int = 14
const RSI_OVERBOUGHT: float = 70.0
const RSI_OVERSOLD: float = 30.0
const MACD_FAST: int = 12
const MACD_SLOW: int = 26
const MACD_SIGNAL: int = 9
const RSI_COLOR: Color = Color(0.0, 0.75, 0.85)
const MACD_LINE_COLOR: Color = Color(0.0, 0.60, 0.85)
const MACD_SIGNAL_COLOR: Color = Color(0.90, 0.40, 0.15)

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

## D1 running state — updated O(1) per tick instead of O(n) full scan.
## Reset by _aggregate_candles() and _do_load_stock().
var _d1_open: int = 0
var _d1_high: int = 0
var _d1_low: int = 0
var _d1_volume: float = 0.0

## Indicator caches — computed in _rebuild_indicator_caches() (full) or
## _update_last_indicator() (incremental). _draw_rsi/_draw_macd read these directly.
var _rsi_cache: Array[float] = []
var _macd_line_cache: Array[float] = []
var _signal_line_cache: Array[float] = []
## Running Wilder state — holds the state at the LAST COMPLETE candle for O(1) incremental update.
var _rsi_avg_gain: float = 0.0
var _rsi_avg_loss: float = 0.0
## Running EMA state for MACD — held at last complete candle.
var _ema_fast_state: float = 0.0
var _ema_slow_state: float = 0.0
var _sig_ema_state: float = 0.0
var _indicator_seeded: bool = false  ## True once full seed calculation done

## Debounce for load_stock — prevents full rebuild storms during rapid stock scrolling.
var _pending_stock_id: String = ""
var _load_debounce_timer: Timer

## Pre-allocated draw buffers — cleared and reused each frame to avoid per-draw allocation.
## S5-03: 프레임당 PackedVector2Array 신규 할당 → 0 (zero-alloc hot path, engine-code.md)
var _draw_rsi_points: PackedVector2Array = PackedVector2Array()
var _draw_macd_points: PackedVector2Array = PackedVector2Array()
var _draw_sig_points: PackedVector2Array = PackedVector2Array()
var _draw_ma_points: PackedVector2Array = PackedVector2Array()

# ── Crosshair ──

var _crosshair_pos: Vector2 = Vector2(-1, -1)
var _show_crosshair: bool = false

# ── Chart geometry (computed per draw) ──

var _chart_rect: Rect2 = Rect2()  ## Candle area
var _volume_rect: Rect2 = Rect2()  ## Volume bar area
var _rsi_rect: Rect2 = Rect2()
var _macd_rect: Rect2 = Rect2()
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
	_update_tf_buttons()
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameClock.on_tick.connect(_on_tick)
	GameClock.on_market_state_changed.connect(_on_market_state_changed)
	PriceEngine.on_price_updated.connect(_on_price_updated)
	clip_contents = true
	tree_exiting.connect(_disconnect_signals)
	_load_debounce_timer = Timer.new()
	_load_debounce_timer.wait_time = 0.08  # 80ms — absorbs rapid stock-list scrolling
	_load_debounce_timer.one_shot = true
	_load_debounce_timer.timeout.connect(_on_load_debounce_timeout)
	add_child(_load_debounce_timer)


func _build_header() -> void:
	_header_bar = HBoxContainer.new()
	_header_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_header_bar.offset_bottom = HEADER_HEIGHT
	_header_bar.add_theme_constant_override("separation", 8)
	var header_style: StyleBoxFlat = ThemeSetup.make_panel_style(ThemeSetup.BG_PANEL, 0, ThemeSetup.BORDER_DIM)
	_header_bar.add_theme_stylebox_override("panel", header_style)
	add_child(_header_bar)

	_lbl_stock_name = Label.new()
	_lbl_stock_name.text = tr("종목 선택")
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
	_btn_tf_1t.text = tr("1분")
	ThemeSetup.apply_button_theme(_btn_tf_1t)
	_btn_tf_1t.pressed.connect(func() -> void: set_timeframe(Timeframe.M1))
	_header_bar.add_child(_btn_tf_1t)

	_btn_tf_5t = Button.new()
	_btn_tf_5t.text = tr("5분")
	ThemeSetup.apply_button_theme(_btn_tf_5t)
	_btn_tf_5t.pressed.connect(func() -> void: set_timeframe(Timeframe.M5))
	_header_bar.add_child(_btn_tf_5t)

	_btn_tf_15t = Button.new()
	_btn_tf_15t.text = tr("15분")
	ThemeSetup.apply_button_theme(_btn_tf_15t)
	_btn_tf_15t.pressed.connect(func() -> void: set_timeframe(Timeframe.M15))
	_header_bar.add_child(_btn_tf_15t)

	_btn_tf_1d = Button.new()
	_btn_tf_1d.text = tr("일봉")
	ThemeSetup.apply_button_theme(_btn_tf_1d)
	_btn_tf_1d.pressed.connect(func() -> void: set_timeframe(Timeframe.D1))
	_header_bar.add_child(_btn_tf_1d)

	# Go-to-latest button (hidden by default)
	_btn_go_latest = Button.new()
	_btn_go_latest.text = tr("현재로 이동 →")
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

## Load chart data for a stock. Debounced — rapid calls are coalesced into one rebuild.
func load_stock(stock_id: String) -> void:
	_pending_stock_id = stock_id
	_load_debounce_timer.start()


func _on_load_debounce_timeout() -> void:
	_do_load_stock(_pending_stock_id)


func _do_load_stock(stock_id: String) -> void:
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


## Switch the active timeframe and refresh the chart display.
func set_timeframe(tf: Timeframe) -> void:
	_timeframe = tf
	_update_tf_buttons()
	_aggregate_candles()
	_scroll_offset = 0
	_auto_scroll = true
	_dirty = true
	_btn_go_latest.visible = false
	queue_redraw()


## Update timeframe button styles — active button gets accent style.
func _update_tf_buttons() -> void:
	var buttons: Array[Button] = [_btn_tf_1t, _btn_tf_5t, _btn_tf_15t, _btn_tf_1d]
	var timeframes: Array[Timeframe] = [Timeframe.M1, Timeframe.M5, Timeframe.M15, Timeframe.D1]
	for i: int in range(buttons.size()):
		if timeframes[i] == _timeframe:
			ThemeSetup.apply_accent_button(buttons[i])
		else:
			ThemeSetup.apply_button_theme(buttons[i])


# ── Signal Handlers ──

func _on_tick(_tick: int, _day: int, _week: int) -> void:
	if _stock_id == "" or _chart_state == ChartState.UNLOADED:
		return
	_tick_counter += 1


func _on_price_updated(_tick: int) -> void:
	if _stock_id == "" or _chart_state != ChartState.LIVE:
		return

	# Candle data update — always runs every tick so OHLC values are never stale.
	# Skipping this would cause candles to freeze as single-price dojis at high speed.
	var new_prices: Array[int] = PriceEngine.get_tick_buffer(_stock_id)
	var new_volumes: Array[float] = PriceEngine.get_tick_volumes(_stock_id)
	# Safety guard: if buffer ever shrinks unexpectedly, do a full rebuild.
	# Under normal operation (no daily reset), the buffer only grows → this branch
	# should never fire. Kept as a defensive fallback.
	if new_prices.size() < _tick_prices.size():
		_tick_prices = new_prices
		_tick_volumes = new_volumes
		_aggregate_candles()
	else:
		_tick_prices = new_prices
		_tick_volumes = new_volumes
		_update_last_candle()
	_update_header()

	# Render throttle — only queue a redraw at reduced frequency at high speed.
	# Decoupled from data update above so candle OHLC stays current between redraws.
	var speed: float = GameClock.get_speed_multiplier()
	if speed >= 4.0 and _tick_counter % 4 != 0:
		return
	elif speed >= float(RENDER_SKIP_AT_SPEED) and _tick_counter % 2 != 0:
		return

	_dirty = true
	queue_redraw()


func _on_market_state_changed(
	new_state: GameClock.MarketState, _prev: GameClock.MarketState
) -> void:
	match new_state:
		GameClock.MarketState.MARKET_OPEN:
			_chart_state = ChartState.LIVE
			# Re-fetch references and rebuild candles each trading day so that
			# 1m/5m/15m charts show full season history (GDD §5-1 max_tick_history=31200).
			# Also required for D1: _candles must be rebuilt from ohlcv_daily after
			# the previous day's data was appended during DAY_TRANSITION.
			if _stock_id != "":
				_tick_prices = PriceEngine.get_tick_buffer(_stock_id)
				_tick_volumes = PriceEngine.get_tick_volumes(_stock_id)
				_ohlcv_daily = PriceEngine.get_ohlcv_history(_stock_id)
				_aggregate_candles()
				_dirty = true
				queue_redraw()
		GameClock.MarketState.PAUSED:
			_chart_state = ChartState.PAUSED
		GameClock.MarketState.MARKET_CLOSED, GameClock.MarketState.DAY_TRANSITION, \
		GameClock.MarketState.WEEK_END, GameClock.MarketState.SEASON_END, \
		GameClock.MarketState.PRE_MARKET:
			if _chart_state != ChartState.UNLOADED:
				_chart_state = ChartState.STATIC


func _disconnect_signals() -> void:
	if GameClock.on_tick.is_connected(_on_tick):
		GameClock.on_tick.disconnect(_on_tick)
	if GameClock.on_market_state_changed.is_connected(_on_market_state_changed):
		GameClock.on_market_state_changed.disconnect(_on_market_state_changed)
	if PriceEngine.on_price_updated.is_connected(_on_price_updated):
		PriceEngine.on_price_updated.disconnect(_on_price_updated)
	# TD-AUDIT-03: 씬 제거 시 타이머 dangling 방지 — timeout이 freed 객체에서 발화하는 오류 수정
	if is_instance_valid(_load_debounce_timer):
		_load_debounce_timer.stop()
		if _load_debounce_timer.timeout.is_connected(_on_load_debounce_timeout):
			_load_debounce_timer.timeout.disconnect(_on_load_debounce_timeout)


# ── Input ──

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom(-5)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(5)
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				_handle_chart_click(mb.position)
	elif event is InputEventMouseMotion:
		_crosshair_pos = (event as InputEventMouseMotion).position
		_show_crosshair = true
		queue_redraw()


func _handle_chart_click(pos: Vector2) -> void:
	# Only emit price if clicking within the chart price area
	if _chart_rect.size.x <= 0.0 or _chart_rect.size.y <= 0.0:
		return
	if pos.y < _chart_rect.position.y or pos.y > _chart_rect.position.y + _chart_rect.size.y:
		return
	if pos.x < _chart_rect.position.x or pos.x > _chart_rect.position.x + _chart_rect.size.x:
		return
	var raw_price: float = _price_min + (_price_max - _price_min) * (1.0 - (pos.y - _chart_rect.position.y) / _chart_rect.size.y)
	var snapped: int = PriceEngine.round_to_tick(raw_price)
	if snapped > 0:
		price_clicked.emit(snapped)


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
		# Use daily OHLCV from PriceEngine for completed days.
		_candles = _ohlcv_daily.duplicate()
		# today_start: tick index where today begins in the continuous season buffer.
		# _ohlcv_daily.size() = completed days; each day has TICKS_PER_DAY ticks.
		var today_start: int = _ohlcv_daily.size() * GameClock.TICKS_PER_DAY
		# Add today's intra-day candle and seed D1 running state from today's ticks only.
		if _tick_prices.size() > today_start:
			var today_candle: Dictionary = _aggregate_range(today_start, _tick_prices.size() - 1)
			_candles.append(today_candle)
			_d1_open = today_candle["open"]
			_d1_high = today_candle["high"]
			_d1_low = today_candle["low"]
			_d1_volume = float(today_candle["volume"])
		else:
			_d1_open = 0
			_d1_high = 0
			_d1_low = 0
			_d1_volume = 0.0
		_rebuild_indicator_caches()
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
	_rebuild_indicator_caches()


## Incremental update — only rebuilds the last (in-progress) candle. O(1) per tick.
## Called from _on_price_updated when the buffer grew (normal tick, no day boundary).
func _update_last_candle() -> void:
	if _timeframe == Timeframe.D1:
		var n: int = _tick_prices.size()
		if n == 0:
			return
		var p: int = _tick_prices[n - 1]
		var v: float = _tick_volumes[n - 1] if n - 1 < _tick_volumes.size() else 0.0
		# Detect first tick of today using the season-wide continuous tick buffer.
		# today_start = number of completed days × ticks/day.
		# Tick index (n-1) == today_start means this is the very first tick today.
		# This replaces the old `n == 1` check which only worked when the buffer was reset daily.
		var today_start: int = _ohlcv_daily.size() * GameClock.TICKS_PER_DAY
		if n - 1 == today_start:
			# First tick of today — seed running state
			_d1_open = p
			_d1_high = p
			_d1_low = p
			_d1_volume = v
		else:
			if p > _d1_high:
				_d1_high = p
			if p < _d1_low:
				_d1_low = p
			_d1_volume += v
		var today: Dictionary = {
			"open": _d1_open, "high": _d1_high, "low": _d1_low, "close": p,
			"volume": int(_d1_volume), "tick_start": 0, "tick_end": n - 1
		}
		if _candles.size() > _ohlcv_daily.size():
			_candles[_candles.size() - 1] = today
		else:
			_candles.append(today)
		return

	var tf: int = int(_timeframe)
	var n: int = _tick_prices.size()
	if n == 0:
		return

	# Append any newly completed candles (at most 1 per tick in steady state)
	var complete: int = n / tf
	while _candles.size() < complete:
		var idx: int = _candles.size()
		_candles.append(_aggregate_range(idx * tf, (idx + 1) * tf - 1))

	if n % tf == 0 and complete > 0:
		# Exact candle boundary — finalize the last complete candle.
		# Without this, the candle stored as a partial on the previous tick
		# is never updated with the boundary tick's price (close/high/low gap).
		_candles[complete - 1] = _aggregate_range((complete - 1) * tf, complete * tf - 1)
	elif n % tf != 0:
		# Update or append the in-progress partial candle
		var start: int = complete * tf
		var partial: Dictionary = _aggregate_range(start, n - 1)
		if _candles.size() > complete:
			_candles[complete] = partial
		else:
			_candles.append(partial)
	_update_last_indicator()


## Full rebuild of RSI and MACD caches from _candles. Stores running state for
## incremental updates. Called after _aggregate_candles() (stock switch / day boundary).
func _rebuild_indicator_caches() -> void:
	var n: int = _candles.size()
	_rsi_cache.resize(n)
	_macd_line_cache.resize(n)
	_signal_line_cache.resize(n)
	_indicator_seeded = false

	if n == 0:
		return

	# Build close price array
	var closes: Array[float] = []
	closes.resize(n)
	for i: int in range(n):
		closes[i] = float(_candles[i]["close"])

	# ── RSI (Wilder smoothing) ──
	for i: int in range(n):
		_rsi_cache[i] = 0.0
	if n > RSI_PERIOD:
		var gains: Array[float] = []
		var losses: Array[float] = []
		gains.resize(n)
		losses.resize(n)
		gains[0] = 0.0
		losses[0] = 0.0
		for i: int in range(1, n):
			var diff: float = closes[i] - closes[i - 1]
			gains[i] = maxf(diff, 0.0)
			losses[i] = maxf(-diff, 0.0)
		_rsi_avg_gain = 0.0
		_rsi_avg_loss = 0.0
		for i: int in range(1, RSI_PERIOD + 1):
			_rsi_avg_gain += gains[i]
			_rsi_avg_loss += losses[i]
		_rsi_avg_gain /= float(RSI_PERIOD)
		_rsi_avg_loss /= float(RSI_PERIOD)
		var rs: float = _rsi_avg_gain / maxf(_rsi_avg_loss, 0.0001)
		_rsi_cache[RSI_PERIOD] = 100.0 - (100.0 / (1.0 + rs))
		for i: int in range(RSI_PERIOD + 1, n):
			_rsi_avg_gain = (_rsi_avg_gain * float(RSI_PERIOD - 1) + gains[i]) / float(RSI_PERIOD)
			_rsi_avg_loss = (_rsi_avg_loss * float(RSI_PERIOD - 1) + losses[i]) / float(RSI_PERIOD)
			rs = _rsi_avg_gain / maxf(_rsi_avg_loss, 0.0001)
			_rsi_cache[i] = 100.0 - (100.0 / (1.0 + rs))

	# ── MACD (EMA 12/26/9) ──
	for i: int in range(n):
		_macd_line_cache[i] = 0.0
		_signal_line_cache[i] = 0.0
	if n >= MACD_SLOW + MACD_SIGNAL:
		var ema_fast_arr: Array[float] = _calc_ema(closes, MACD_FAST)
		var ema_slow_arr: Array[float] = _calc_ema(closes, MACD_SLOW)
		for i: int in range(n):
			if i < MACD_SLOW - 1:
				_macd_line_cache[i] = 0.0
			else:
				_macd_line_cache[i] = ema_fast_arr[i] - ema_slow_arr[i]
		var signal_start: int = MACD_SLOW - 1
		var seed_end: int = signal_start + MACD_SIGNAL - 1
		if seed_end < n:
			var seed_sum: float = 0.0
			for i: int in range(signal_start, seed_end + 1):
				seed_sum += _macd_line_cache[i]
			_sig_ema_state = seed_sum / float(MACD_SIGNAL)
			_signal_line_cache[seed_end] = _sig_ema_state
			var sig_k: float = 2.0 / float(MACD_SIGNAL + 1)
			for i: int in range(seed_end + 1, n):
				_sig_ema_state = _macd_line_cache[i] * sig_k + _sig_ema_state * (1.0 - sig_k)
				_signal_line_cache[i] = _sig_ema_state
		# Store EMA states for incremental updates
		_ema_fast_state = ema_fast_arr[n - 1]
		_ema_slow_state = ema_slow_arr[n - 1]
		_indicator_seeded = true


## Incremental update of indicator caches — only recomputes the last entry.
## Called from _update_last_candle() when the partial candle changes.
## Does NOT modify running state (_rsi_avg_gain etc.) — those only advance on complete candles.
func _update_last_indicator() -> void:
	var n: int = _candles.size()
	if n == 0 or not _indicator_seeded:
		return
	# Resize if a new candle was appended
	if _rsi_cache.size() < n:
		_rsi_cache.resize(n)
		_macd_line_cache.resize(n)
		_signal_line_cache.resize(n)
	var last: int = n - 1
	var close_last: float = float(_candles[last]["close"])
	var close_prev: float = float(_candles[last - 1]["close"]) if last > 0 else close_last

	# RSI: recompute last value using running state + current close delta (no state mutation)
	if last >= RSI_PERIOD:
		var diff: float = close_last - close_prev
		var g: float = maxf(diff, 0.0)
		var l: float = maxf(-diff, 0.0)
		var avg_g: float = (_rsi_avg_gain * float(RSI_PERIOD - 1) + g) / float(RSI_PERIOD)
		var avg_l: float = (_rsi_avg_loss * float(RSI_PERIOD - 1) + l) / float(RSI_PERIOD)
		var rs: float = avg_g / maxf(avg_l, 0.0001)
		_rsi_cache[last] = 100.0 - (100.0 / (1.0 + rs))

	# MACD: recompute last entry using running EMA states (no state mutation)
	if last >= MACD_SLOW - 1:
		var k_fast: float = 2.0 / float(MACD_FAST + 1)
		var k_slow: float = 2.0 / float(MACD_SLOW + 1)
		var ef: float = close_last * k_fast + _ema_fast_state * (1.0 - k_fast)
		var es: float = close_last * k_slow + _ema_slow_state * (1.0 - k_slow)
		_macd_line_cache[last] = ef - es
		var sig_k: float = 2.0 / float(MACD_SIGNAL + 1)
		_signal_line_cache[last] = _macd_line_cache[last] * sig_k + _sig_ema_state * (1.0 - sig_k)


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
		_lbl_stock_name.text = tr("종목 선택")
		_lbl_current_price.text = ""
		_lbl_change.text = ""
		return

	var stock: StockData = StockDatabase.get_stock(_stock_id)
	if stock == null:
		return

	var price: int = PriceEngine.get_current_price(_stock_id)
	_lbl_stock_name.text = stock.get_display_name()
	_lbl_current_price.text = FormatUtils.currency(price)

	# 전일 종가 대비 등락률 (HTS 표준)
	var limits: Dictionary = PriceEngine.get_daily_limits(_stock_id)
	var prev_close: int = limits.get("prev_close", 0)
	if prev_close > 0:
		var diff: int = price - prev_close
		var pct: float = float(diff) / float(prev_close) * 100.0
		_lbl_change.text = "%+.1f%% (%s%s)" % [pct, "+" if diff >= 0 else "", _format_number(diff)]
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
	if SkillTree.is_skill_unlocked("A1"):
		_draw_moving_averages()
	if SkillTree.is_skill_unlocked("A2"):
		_draw_rsi()
		_draw_macd()
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
	var chart_top: float = HEADER_HEIGHT + 4.0
	var total_height: float = size.y - chart_top
	var left: float = 0.0
	var width: float = size.x - 60.0  # Right margin for Y-axis labels

	if SkillTree.is_skill_unlocked("A2"):
		# 4-zone split: chart 55%, RSI 15%, MACD 15%, volume 15%
		var chart_height: float = total_height * 0.55
		var rsi_height: float = total_height * 0.15
		var macd_height: float = total_height * 0.15
		var volume_height: float = total_height * 0.15
		_chart_rect = Rect2(left, chart_top, width, chart_height)
		_rsi_rect = Rect2(left, chart_top + chart_height, width, rsi_height)
		_macd_rect = Rect2(left, chart_top + chart_height + rsi_height, width, macd_height)
		_volume_rect = Rect2(left, chart_top + chart_height + rsi_height + macd_height, width, volume_height)
	else:
		# 2-zone split: chart 70%, volume 30%
		var chart_height: float = total_height * 0.70
		var volume_height: float = total_height * 0.30
		_chart_rect = Rect2(left, chart_top, width, chart_height)
		_rsi_rect = Rect2()
		_macd_rect = Rect2()
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
	draw_rect(_chart_rect, Color.WHITE, true)
	if SkillTree.is_skill_unlocked("A2"):
		draw_rect(_rsi_rect, Color(0.95, 0.97, 0.99), true)
		draw_rect(_macd_rect, Color(0.95, 0.97, 0.99), true)
	draw_rect(_volume_rect, Color(0.97, 0.97, 0.98), true)


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
			-1, 10, ThemeSetup.TEXT_SECONDARY
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


func _draw_moving_averages() -> void:
	var visible: Array[Dictionary] = _get_visible_candles()
	if visible.size() < 2:
		return

	# Determine the global start index of the visible window
	var total: int = _candles.size()
	var vis_start_idx: int
	if _auto_scroll:
		vis_start_idx = maxi(0, total - _visible_count)
	else:
		vis_start_idx = maxi(0, total - _visible_count - _scroll_offset)

	var candle_width: float = _chart_rect.size.x / float(_visible_count)

	for ma_idx: int in range(MA_PERIODS.size()):
		var period: int = MA_PERIODS[ma_idx]
		var color: Color = MA_COLORS[ma_idx]

		# Reuse pre-allocated buffer (S5-03: zero-alloc draw path)
		_draw_ma_points.clear()
		for i: int in range(visible.size()):
			var global_i: int = vis_start_idx + i
			# Need at least `period` candles ending at global_i
			if global_i < period - 1:
				continue
			var ma_sum: float = 0.0
			for j: int in range(period):
				ma_sum += float(_candles[global_i - j]["close"])
			var ma_val: float = ma_sum / float(period)
			var x: float = _chart_rect.position.x + (float(i) + 0.5) * candle_width
			var y: float = _price_to_y(ma_val)
			_draw_ma_points.append(Vector2(x, y))

		if _draw_ma_points.size() >= 2:
			draw_polyline(_draw_ma_points, color, 1.5, true)

	# Legend in top-left corner of chart
	var legend_x: float = _chart_rect.position.x + 8.0
	var legend_y: float = _chart_rect.position.y + 14.0
	for ma_idx2: int in range(MA_PERIODS.size()):
		var label_text: String = "MA%d" % MA_PERIODS[ma_idx2]
		draw_string(
			ThemeDB.fallback_font,
			Vector2(legend_x, legend_y),
			label_text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, 10, MA_COLORS[ma_idx2]
		)
		legend_x += 50.0


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
	var axis_color: Color = ThemeSetup.BORDER_DIM
	# Y-axis right border — spans all zones
	draw_line(
		Vector2(_chart_rect.position.x + _chart_rect.size.x, _chart_rect.position.y),
		Vector2(_chart_rect.position.x + _chart_rect.size.x, _volume_rect.position.y + _volume_rect.size.y),
		axis_color
	)
	# Separator between chart and next zone
	draw_line(
		Vector2(_chart_rect.position.x, _volume_rect.position.y),
		Vector2(_chart_rect.position.x + _chart_rect.size.x, _volume_rect.position.y),
		axis_color
	)
	if SkillTree.is_skill_unlocked("A2"):
		# Separator between chart and RSI
		draw_line(
			Vector2(_rsi_rect.position.x, _rsi_rect.position.y),
			Vector2(_rsi_rect.position.x + _rsi_rect.size.x, _rsi_rect.position.y),
			axis_color
		)
		# Separator between RSI and MACD
		draw_line(
			Vector2(_macd_rect.position.x, _macd_rect.position.y),
			Vector2(_macd_rect.position.x + _macd_rect.size.x, _macd_rect.position.y),
			axis_color
		)


## Standard Exponential Moving Average over a float array.
## Returns an array of the same length; indices before (period-1) are 0.0.
func _calc_ema(data: Array[float], period: int) -> Array[float]:
	var result: Array[float] = []
	result.resize(data.size())
	if data.size() == 0 or period <= 0:
		return result
	var k: float = 2.0 / float(period + 1)
	var ema: float = 0.0
	for i: int in range(data.size()):
		if i < period - 1:
			result[i] = 0.0
		elif i == period - 1:
			# Seed with simple average of first `period` values
			var sum: float = 0.0
			for j: int in range(period):
				sum += data[j]
			ema = sum / float(period)
			result[i] = ema
		else:
			ema = data[i] * k + ema * (1.0 - k)
			result[i] = ema
	return result


## Draw RSI(14) sub-panel. Uses _rsi_cache (pre-computed). O(visible) per draw.
func _draw_rsi() -> void:
	if _rsi_rect.size.y <= 0.0 or _rsi_cache.size() < RSI_PERIOD + 1:
		return

	var total: int = _candles.size()
	var vis_start_idx: int
	if _auto_scroll:
		vis_start_idx = maxi(0, total - _visible_count)
	else:
		vis_start_idx = maxi(0, total - _visible_count - _scroll_offset)
	var vis_end_idx: int = mini(total, vis_start_idx + _visible_count)

	var candle_width: float = _rsi_rect.size.x / float(_visible_count)

	# Dashed overbought/oversold lines (inlined to avoid Callable allocation per frame)
	var dash_len: float = 6.0
	var gap_len: float = 4.0
	var rsi_right: float = _rsi_rect.position.x + _rsi_rect.size.x
	for _dashed_info: Array in [
		[_rsi_rect.position.y + _rsi_rect.size.y * (1.0 - RSI_OVERBOUGHT / 100.0), Color(0.85, 0.25, 0.25, 0.7)],
		[_rsi_rect.position.y + _rsi_rect.size.y * (1.0 - RSI_OVERSOLD / 100.0),   Color(0.25, 0.45, 0.85, 0.7)],
	]:
		var dy: float = _dashed_info[0]
		var dc: Color = _dashed_info[1]
		var dx: float = _rsi_rect.position.x
		while dx < rsi_right:
			draw_line(Vector2(dx, dy), Vector2(minf(dx + dash_len, rsi_right), dy), dc, 1.0)
			dx += dash_len + gap_len

	# Reuse pre-allocated buffer (S5-03: zero-alloc draw path)
	_draw_rsi_points.clear()
	for i: int in range(vis_start_idx, vis_end_idx):
		if i < RSI_PERIOD or i >= _rsi_cache.size():
			continue
		var vis_i: int = i - vis_start_idx
		var x: float = _rsi_rect.position.x + (float(vis_i) + 0.5) * candle_width
		var y: float = _rsi_rect.position.y + _rsi_rect.size.y * (1.0 - _rsi_cache[i] / 100.0)
		_draw_rsi_points.append(Vector2(x, y))

	if _draw_rsi_points.size() >= 2:
		draw_polyline(_draw_rsi_points, RSI_COLOR, 1.5, true)

	var current_rsi: float = _rsi_cache[vis_end_idx - 1] if vis_end_idx > RSI_PERIOD and vis_end_idx <= _rsi_cache.size() else 0.0
	var label: String = "RSI(%d)  %.1f" % [RSI_PERIOD, current_rsi]
	draw_string(
		ThemeDB.fallback_font,
		Vector2(_rsi_rect.position.x + 6.0, _rsi_rect.position.y + 12.0),
		label, HORIZONTAL_ALIGNMENT_LEFT,
		-1, 10, RSI_COLOR
	)


## Draw MACD(12,26,9) sub-panel. Uses _macd_line_cache/_signal_line_cache. O(visible) per draw.
func _draw_macd() -> void:
	if _macd_rect.size.y <= 0.0 or _macd_line_cache.size() < MACD_SLOW + MACD_SIGNAL:
		return

	var total: int = _candles.size()
	var vis_start_idx: int
	if _auto_scroll:
		vis_start_idx = maxi(0, total - _visible_count)
	else:
		vis_start_idx = maxi(0, total - _visible_count - _scroll_offset)
	var vis_end_idx: int = mini(total, vis_start_idx + _visible_count)

	var valid_start: int = MACD_SLOW - 1 + MACD_SIGNAL - 1
	var y_min: float = INF
	var y_max: float = -INF
	for i: int in range(vis_start_idx, vis_end_idx):
		if i < valid_start or i >= _macd_line_cache.size():
			continue
		var hist: float = _macd_line_cache[i] - _signal_line_cache[i]
		y_min = minf(y_min, minf(_macd_line_cache[i], minf(_signal_line_cache[i], hist)))
		y_max = maxf(y_max, maxf(_macd_line_cache[i], maxf(_signal_line_cache[i], hist)))

	if y_min == INF or y_max == -INF:
		return
	var y_range: float = maxf(y_max - y_min, 1.0)
	var y_pad: float = y_range * 0.1
	y_min -= y_pad
	y_max += y_pad

	# Inline y-mapping constants (avoids Callable allocation per frame, S5-03)
	var macd_y_scale: float = _macd_rect.size.y / (y_max - y_min)
	var macd_y_base: float  = _macd_rect.position.y + _macd_rect.size.y

	var candle_width: float = _macd_rect.size.x / float(_visible_count)
	var bar_width: float = maxf(candle_width * 0.6, 1.0)

	# Zero line (thin gray)
	var zero_y: float = macd_y_base - (0.0 - y_min) * macd_y_scale
	draw_line(
		Vector2(_macd_rect.position.x, zero_y),
		Vector2(_macd_rect.position.x + _macd_rect.size.x, zero_y),
		Color(0.60, 0.60, 0.62, 0.5), 1.0
	)

	# Histogram bars
	for i: int in range(vis_start_idx, vis_end_idx):
		if i < valid_start or i >= _macd_line_cache.size():
			continue
		var vis_i: int = i - vis_start_idx
		var hist: float = _macd_line_cache[i] - _signal_line_cache[i]
		var x_center: float = _macd_rect.position.x + (float(vis_i) + 0.5) * candle_width
		var hist_y: float = macd_y_base - (hist - y_min) * macd_y_scale
		var bar_top: float = minf(hist_y, zero_y)
		var bar_bot: float = maxf(hist_y, zero_y)
		var bar_h: float = maxf(bar_bot - bar_top, 1.0)
		var hist_color: Color = Color(0.20, 0.70, 0.30, 0.6) if hist >= 0.0 else Color(0.85, 0.25, 0.25, 0.6)
		draw_rect(Rect2(x_center - bar_width * 0.5, bar_top, bar_width, bar_h), hist_color, true)

	# MACD line — reuse pre-allocated buffer (S5-03: zero-alloc draw path)
	_draw_macd_points.clear()
	for i: int in range(vis_start_idx, vis_end_idx):
		if i < valid_start or i >= _macd_line_cache.size():
			continue
		var vis_i: int = i - vis_start_idx
		var x: float = _macd_rect.position.x + (float(vis_i) + 0.5) * candle_width
		_draw_macd_points.append(Vector2(x, macd_y_base - (_macd_line_cache[i] - y_min) * macd_y_scale))
	if _draw_macd_points.size() >= 2:
		draw_polyline(_draw_macd_points, MACD_LINE_COLOR, 1.5, true)

	# Signal line — reuse pre-allocated buffer
	_draw_sig_points.clear()
	for i: int in range(vis_start_idx, vis_end_idx):
		if i < valid_start or i >= _signal_line_cache.size():
			continue
		var vis_i: int = i - vis_start_idx
		var x: float = _macd_rect.position.x + (float(vis_i) + 0.5) * candle_width
		_draw_sig_points.append(Vector2(x, macd_y_base - (_signal_line_cache[i] - y_min) * macd_y_scale))
	if _draw_sig_points.size() >= 2:
		draw_polyline(_draw_sig_points, MACD_SIGNAL_COLOR, 1.5, true)

	# Label "MACD" in top-left
	draw_string(
		ThemeDB.fallback_font,
		Vector2(_macd_rect.position.x + 6.0, _macd_rect.position.y + 12.0),
		"MACD", HORIZONTAL_ALIGNMENT_LEFT,
		-1, 10, MACD_LINE_COLOR
	)


func _draw_crosshair() -> void:
	if _crosshair_pos.x < _chart_rect.position.x or _crosshair_pos.x > _chart_rect.position.x + _chart_rect.size.x:
		return
	if _crosshair_pos.y < _chart_rect.position.y or _crosshair_pos.y > _volume_rect.position.y + _volume_rect.size.y:
		return

	var ch_color: Color = Color(0.40, 0.40, 0.45, 0.5)

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
			FormatUtils.currency(snapped_price), HORIZONTAL_ALIGNMENT_LEFT,
			-1, 10, ThemeSetup.TEXT_PRIMARY
		)


# ── Utility ──

## Delegates to FormatUtils.number() — single source of truth (TD-04 note).
func _format_number(value: int) -> String:
	return FormatUtils.number(value)
