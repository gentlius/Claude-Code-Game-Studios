## Autoload — Generates market events on a daily slot schedule and delivers news with delay.
## Core layer. Depends on: GameClock, StockDatabase, PriceEngine.
## See: design/gdd/news-events.md
extends Node

# ── Signals ──

## Emitted when a news item becomes visible to the player (after delay).
signal on_news_display(entry: Dictionary)

## Emitted when a pre-market news bundle is ready.
signal on_pre_market_news(entries: Array[Dictionary])

## Emitted when season theme hint is revealed.
signal on_theme_hint(hint_text: String)

## Emitted for debug: when an event is generated (before delay).
signal on_event_generated(event: Dictionary)

## Emitted when S3 rumor channel produces a pre-event hint (advance_ticks before the real event).
## entry keys: headline, body, scope, impact_tier, direction (may be inverted), is_rumor=true, is_fake
signal on_rumor_hint(entry: Dictionary)

# ── Enums ──

enum SystemState { UNINITIALIZED, READY, ACTIVE, DAY_END, SEASON_END }

# ── Constants: Slot/Scope/Impact/VOL weights moved to C++ PriceKernel (Phase B) ──
# EE_SLOTS, EE_INDIVIDUAL_W/SECTOR_W/MACRO_W, EE_IMPACT_W, EE_VOL_W,
# EE_INDIVIDUAL_COOLDOWN_MIN, EE_DAILY_HARD_CAP — see price_kernel.h.

## Overnight event probabilities (GDD Rule 6-1)
const OVERNIGHT_PROBS: Array[float] = [0.40, 0.45, 0.15]  # 0, 1, 2 events
const OVERNIGHT_INDIVIDUAL_PROB: float = 0.05

## Clustering prevention: penalty probability for same-scope repeat (GDD Rule 2-2)
const CLUSTER_PENALTY_PROB: float = 0.5

## Overnight scope/impact split ratios (GDD Rule 6-1)
const OVERNIGHT_MACRO_PROB: float = 0.4   ## MACRO vs SECTOR split
const OVERNIGHT_SMALL_PROB: float = 0.6   ## SMALL vs MEDIUM split

## Minimum valid decay in minutes; values below are clamped to default (GDD Rule 3-2)
const MIN_DECAY_MINUTES: int = 8    ## ~8 game-minutes
const DEFAULT_DECAY_MINUTES: int = 15  ## ~15 game-minutes

## impact_hint 문자열 상수 — TD-CR-14: 이모지/텍스트 일관성 보장
const IMPACT_HINT_POSITIVE: String  = "positive"
const IMPACT_HINT_NEGATIVE: String  = "negative"
const IMPACT_HINT_NEUTRAL:  String  = "neutral"
const IMPACT_HINT_WARNING:  String  = "⚠️"   ## VI 발동 등 경고 시스템 이벤트
const IMPACT_HINT_INFO:     String  = "ℹ️"   ## VI 해제 등 정보성 시스템 이벤트
const IMPACT_HINT_EMERGENCY: String = "🚨"   ## 서킷브레이커 등 긴급 시스템 이벤트

# ── Constants: S3 Rumor Channel (GDD Rule 5-4, F6) ──

## Rumor probability by impact tier: LARGE/MEGA=1.0, MEDIUM=0.3, SMALL=0.0 (GDD F6)
const RUMOR_PROBS: Dictionary = {"LARGE": 1.0, "MEGA": 1.0, "MEDIUM": 0.3, "SMALL": 0.0}

## Number of fake rumors generated per trading day (GDD §5-4, Tuning Knobs)
const FAKE_RUMOR_PER_DAY: int = 2

## Fake rumor tick distribution: placed between tick 30 and 360 (= 7.5–90 game-minutes)
const FAKE_RUMOR_TICK_MIN: int = 30
const FAKE_RUMOR_TICK_MAX: int = 360

## Scope display labels used only inside news_event_system to build rumor headlines.
## UI must NOT import this — UI reads scope field and uses its own mapping.
## (UI no-reference rule: gameplay-code.md §NO direct references to UI code)
const _SCOPE_DISPLAY: Dictionary = {
	"MACRO": "시장 전반",
	"SECTOR": "업종",
	"INDIVIDUAL": "종목",
}

# ── State ──

## ADR-018: 세션별 엔트로피 격리. PriceEngine._rng와 독립된 인스턴스.
## _on_season_start()에서 재시드되어 시즌마다 독립적인 뉴스 시퀀스를 생성.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _state: SystemState = SystemState.UNINITIALIZED
var _event_pool: Array[Dictionary] = []       ## Loaded event templates
var _season_theme: Dictionary = {}            ## Active season theme
var _all_themes: Array[Dictionary] = []       ## All available themes

## Intraday scheduling state is owned by C++ PriceKernel EventEngine (Phase B).
## _daily_schedule / _daily_event_count / _daily_mega_fired removed.

var _news_delay_queue: Array[Dictionary] = [] ## Pending news items awaiting display
var _overnight_buffer: Array[Dictionary] = [] ## Events for next morning

## Display-only entries restored from a save. Delivered to NewsFeed when it calls
## get_and_clear_loaded_news() in _ready(). MarketEvent objects are NOT re-pushed
## (price effects are already reflected in PriceEngine's saved state).
var _loaded_news_bundle: Array[Dictionary] = []

## Active market ID — used to filter event_pool templates by market_id field (TD-DR-05).
## Uppercase (e.g. "KR", "US"). DLC markets call set_active_market() before season start.
var _active_market_id: String = "KR"

## Cooldown / individual-cd / last-slot-scope / daily-mutex owned by C++ kernel (Phase B).

## Scheduled fake rumor ticks for the current trading day.
## Populated by _schedule_fake_rumors() on each market open.
var _fake_rumor_ticks: Array[int] = []

## Season statistics
var _season_stats: Dictionary = {
	"total_events": 0,
	"by_scope": {"MACRO": 0, "SECTOR": 0, "INDIVIDUAL": 0},
	"by_impact": {"SMALL": 0, "MEDIUM": 0, "LARGE": 0, "MEGA": 0},
}

# ── Lifecycle ──

func _ready() -> void:
	GameClock.on_season_start.connect(_on_season_start)
	# on_tick is NOT connected here — GameClock calls _on_tick directly in
	# _process_tick() to enforce the GDD-mandated News → Price → Order order.
	GameClock.on_market_open.connect(_on_market_open)
	GameClock.on_market_close.connect(_on_market_close)
	GameClock.on_day_transition.connect(_on_day_transition)
	GameClock.on_market_state_changed.connect(_on_market_state_changed)
	GameClock.on_season_end.connect(_on_season_end)
	PriceEngine.on_vi_triggered.connect(_on_vi_triggered)
	PriceEngine.on_vi_released.connect(_on_vi_released)
	PriceEngine.on_circuit_breaker.connect(_on_circuit_breaker)
	# Phase B: receive C++ EventEngine events for headline resolution + display
	PriceEngine.on_kernel_news.connect(_on_kernel_news)


## Converts game-minutes to ticks.
static func _minutes_to_ticks(minutes: int) -> int:
	return minutes * GameClock.TICKS_PER_MINUTE


## Saves pending overnight display entries AND MarketEvent reconstruction data.
## MarketEvent objects cannot be serialized directly; we save the fields needed
## to reconstruct them. On load, load_save_data() pushes reconstructed events to
## PriceEngine so overnight price bias survives save/load.
func get_save_data() -> Dictionary:
	var entries: Array = []
	for e: Dictionary in _overnight_buffer:
		var mev: MarketEvent = e["market_event"]
		entries.append({
			"headline":         e.get("headline",         ""),
			"body":             e.get("body",             ""),
			"impact_hint":      e.get("impact_hint",      ""),
			"scope":            e.get("scope",            "MACRO"),
			"impact_tier":      e.get("impact_tier",      "SMALL"),
			"direction":        e.get("direction",        1),
			"target_stock_ids": e.get("target_stock_ids", []),
			## MarketEvent 재구성 필드 — PriceEngine 가격 바이어스 복원용
			"base_impact":      mev.base_impact,
			"decay_ticks":      mev.decay_ticks,
			"decay_curve":      int(mev.decay_curve),
			"event_type":       int(mev.event_type),
		})
	return {"overnight_display": entries}


## Restores pending overnight news from save.
## Re-pushes reconstructed MarketEvents to PriceEngine so overnight price bias
## survives save/load. NewsFeed._ready() calls get_and_clear_loaded_news() for display.
func load_save_data(data: Dictionary) -> void:
	_loaded_news_bundle.clear()
	for e: Dictionary in data.get("overnight_display", []):
		_loaded_news_bundle.append({
			"headline":         e.get("headline",         ""),
			"body":             e.get("body",             ""),
			"impact_hint":      e.get("impact_hint",      ""),
			"scope":            e.get("scope",            "MACRO"),
			"impact_tier":      e.get("impact_tier",      "SMALL"),
			"direction":        e.get("direction",        1),
			"target_stock_ids": e.get("target_stock_ids", []),
			"display_tick":     0,
			"is_pre_market":    true,
		})
		# Reconstruct MarketEvent and push to PriceEngine.
		# base_impact absent in pre-fix saves → skip gracefully (backward compat).
		var base_impact: float = float(e.get("base_impact", 0.0))
		if base_impact <= 0.0:
			continue
		var direction: int = int(e.get("direction", 1))
		var scope: MarketEvent.EventScope = _scope_str_to_enum(e.get("scope", "MACRO"))
		var targets: Array[String] = [] as Array[String]
		for id: Variant in e.get("target_stock_ids", []):
			targets.append(str(id))
		var decay_ticks: int = int(e.get("decay_ticks", 0))
		var decay_curve: MarketEvent.DecayCurve = \
			int(e.get("decay_curve", MarketEvent.DecayCurve.LINEAR)) as MarketEvent.DecayCurve
		var event_type: int = int(e.get("event_type", MarketEvent.EventType.GRADUAL_SHIFT))
		var market_event: MarketEvent
		if event_type == MarketEvent.EventType.GRADUAL_SHIFT:
			market_event = MarketEvent.gradual_shift(
				base_impact, direction, scope, targets, decay_ticks, decay_curve)
		else:
			market_event = MarketEvent.instant_shock(base_impact, direction, scope, targets)
		PriceEngine.push_event(market_event)
	# Must be READY so _on_market_open() completes initialization instead of
	# returning early. Default UNINITIALIZED silently suppresses all intraday news.
	_state = SystemState.READY


## Returns and clears the news bundle restored from a save.
## Called by NewsFeed._ready() so late-joining UI receives pre-market news.
func get_and_clear_loaded_news() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e: Dictionary in _loaded_news_bundle:
		result.append(e)
	_loaded_news_bundle.clear()
	return result


## Resets all news state. Called by GameMain (new game) and tests (before_each).
func reset() -> void:
	_overnight_buffer.clear()
	_news_delay_queue.clear()
	_loaded_news_bundle.clear()
	_fake_rumor_ticks.clear()
	_state = SystemState.UNINITIALIZED


func _on_season_start() -> void:
	_rng.seed = Time.get_ticks_usec()  ## ADR-018: 시즌 시작마다 새 엔트로피로 재시드
	_load_event_pool()
	_load_themes()
	_select_season_theme()
	_reset_season_stats()
	_news_delay_queue.clear()
	_overnight_buffer.clear()
	_fake_rumor_ticks.clear()
	_state = SystemState.READY



func _on_season_end() -> void:
	_state = SystemState.UNINITIALIZED


func _on_market_open() -> void:
	if _state == SystemState.UNINITIALIZED:
		return
	# Phase B: intraday slot schedule generated by C++ kernel in start_day().
	_schedule_fake_rumors()
	_state = SystemState.ACTIVE

	# Check theme hint reveal
	var current_day: int = GameClock.get_current_day()
	if _season_theme.size() > 0 and current_day == _season_theme.get("hint_revealed_at_day", -1):
		on_theme_hint.emit(_season_theme.get("hint_text", ""))


func _on_market_close() -> void:
	if _state != SystemState.ACTIVE:
		return
	_state = SystemState.DAY_END
	_process_market_close_queue()
	_generate_overnight_events()


func _on_day_transition() -> void:
	if _state == SystemState.UNINITIALIZED:
		return
	_generate_overnight_disclosures()


func _on_market_state_changed(
	new_state: GameClock.MarketState, prev_state: GameClock.MarketState
) -> void:
	# PRE_MARKET after DAY_TRANSITION: deliver overnight buffer
	if new_state == GameClock.MarketState.PRE_MARKET and prev_state == GameClock.MarketState.DAY_TRANSITION:
		_deliver_pre_market_news()
		_state = SystemState.READY


## Called by GameClock._process_tick() for deterministic News→Price→Order ordering.
func process_tick(tick: int, _day: int, _week: int) -> void:
	if _state != SystemState.ACTIVE:
		return

	# Phase B: intraday slot events generated by C++ kernel, received via _on_kernel_news().

	# Check fake rumor schedule (S3 채널 — GDD Rule 5-4)
	_check_fake_rumors(tick)

	# Process news delay queue
	_process_news_delay_queue(tick)

# ── Public API ──

## Returns the active season theme (or empty dict if none).
func get_season_theme() -> Dictionary:
	return _season_theme


## Returns the current system state.
func get_state() -> SystemState:
	return _state


## Returns season statistics.
func get_season_stats() -> Dictionary:
	return _season_stats.duplicate(true)


## Returns the current news delay in ticks based on SkillTree unlocks.
## Applies the 장학재단 scholarship buff (−5 ticks) for the first trading day
## of the season after purchase. See: design/gdd/lifestyle-spending.md §3-2.
func get_news_delay() -> int:
	var base: int = SkillTree.get_news_delay_ticks()
	var reduction: int = LifestyleManager.get_news_delay_buff_ticks()
	return maxi(0, base - reduction)


## External event injection (ADR-022 EventSource pipeline).
## Called by EtfManager (SECTOR_ROTATION) and FinancialReportSystem (SECTOR_RIPPLE).
## Creates a MarketEvent and pushes it to PriceEngine — the only sanctioned path for
## external systems to affect prices. Never call PriceEngine.push_event() directly.
##
## Parameters:
##   event_tag   : Caller-defined label ("SECTOR_ROTATION", "SECTOR_RIPPLE", …).
##                 Used for debug logging; not evaluated at runtime.
##   sector      : Target sector name (e.g. "반도체"). All stocks in sector are targeted.
##   impact      : base_impact [0.0 .. 0.20]. Passed directly to MarketEvent.
##   direction   : +1 (positive shock) or -1 (negative shock).
##   headline_key: Godot .po key. Empty = no player-visible headline.
##   decay_ticks : 0 = INSTANT_SHOCK, > 0 = GRADUAL_SHIFT over that many ticks.
##
## Example:
##   NewsEventSystem.inject_event("SECTOR_ROTATION", "반도체", 0.055, 1,
##       "ROTATION_KR_INFLOW_1", 8)
## headline_key is a tr() msgid from ko.po; {sector} placeholder is substituted automatically.
func inject_event(
		event_tag: String,
		sector: String,
		impact: float,
		direction: int,
		headline_key: String = "",
		decay_ticks: int = 0
) -> void:
	if _state == SystemState.UNINITIALIZED:
		return
	var stocks: Array[StockData] = StockDatabase.get_stocks_by_sector(sector)
	if stocks.is_empty():
		return
	var target_ids: Array[String] = []
	for s: StockData in stocks:
		target_ids.append(s.stock_id)

	var event: MarketEvent
	if decay_ticks > 0:
		event = MarketEvent.gradual_shift(
			impact, direction, MarketEvent.EventScope.SECTOR, target_ids, decay_ticks
		)
	else:
		event = MarketEvent.instant_shock(
			impact, direction, MarketEvent.EventScope.SECTOR, target_ids
		)
	PriceEngine.push_event(event)

	if not headline_key.is_empty():
		var entry: Dictionary = {
			"headline": tr(headline_key).format({"sector": sector}),
			"body":     "",
			"impact_hint": "positive" if direction > 0 else "negative",
			"scope":    "SECTOR",
			"sector":   sector,
			"is_injected": true,
			"event_tag": event_tag,
		}
		on_news_display.emit(entry)


## Fire a player-visible news card for an individual stock — no price pressure.
## Called by FinancialReportSystem for analyst reports, preliminary earnings, and official results.
## [param direction]: +1 positive, -1 negative, 0 neutral.
## [param impact_tier]: "SMALL", "MEDIUM", "LARGE" (visual weight in news feed).
## GDD financial-report-system.md §3-7, §3-8, §3-10; ADR-022.
func fire_stock_news(
		stock_id: String,
		headline: String,
		body: String,
		direction: int,
		impact_tier: String = "MEDIUM"
) -> void:
	if _state == SystemState.UNINITIALIZED:
		return
	var hint: String = "positive" if direction > 0 else ("negative" if direction < 0 else "ℹ️")
	var entry: Dictionary = {
		"headline":         headline,
		"body":             body,
		"impact_hint":      hint,
		"scope":            "INDIVIDUAL",
		"impact_tier":      impact_tier,
		"direction":        direction,
		"target_stock_ids": [stock_id],
		"display_tick":     GameClock.get_current_tick(),
		"day":              GameClock.get_current_day(),
		"is_system_event":  true,
	}
	on_news_display.emit(entry)


## Compute effective weight for [param template] given [param sector_bias] dict.
## Extracted for testability. Weight = weight_base × sector_bias[target_sector].
## Sector default bias = 1.0 when not present in [param sector_bias].
## Called internally by _pick_template(); exposed for unit tests (S10-06b).
func _calc_template_weight(template: Dictionary, sector_bias: Dictionary) -> float:
	var w: float = float(template.get("weight_base", 1.0))
	var t_sector: String = str(template.get("target_sector", ""))
	if t_sector != "":
		w *= float(sector_bias.get(t_sector, 1.0))
	return w


# ── Data Loading ──

## Set the active market and reload the event pool filtered to that market.
## Call before season start. [param market_id] is case-insensitive ("kr", "KR" both work).
## DLC markets call this when the player selects a non-KR market.
func set_active_market(market_id: String) -> void:
	_active_market_id = market_id.to_upper()
	_load_event_pool()


func _load_event_pool() -> void:
	_event_pool.clear()
	var file := FileAccess.open("res://assets/data/event_pool.json", FileAccess.READ)
	if file == null:
		push_warning("NewsEventSystem: event_pool.json not found")
		return
	var json := JSON.new()
	var err: Error = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_warning("NewsEventSystem: event_pool.json parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return
	var data: Dictionary = json.data
	var all_templates: Array[Dictionary] = Array(data.get("templates", []), TYPE_DICTIONARY, &"", null)
	## TD-DR-05: filter by market_id — only load templates matching the active market.
	## Templates without a market_id field default to "KR" (backwards-compat).
	_event_pool = all_templates.filter(
		func(t: Dictionary) -> bool:
			return t.get("market_id", "KR").to_upper() == _active_market_id
	)


func _load_themes() -> void:
	_all_themes.clear()
	var file := FileAccess.open("res://assets/data/season_themes.json", FileAccess.READ)
	if file == null:
		push_warning("NewsEventSystem: season_themes.json not found")
		return
	var json := JSON.new()
	var err: Error = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_warning("NewsEventSystem: season_themes.json parse error")
		return
	var data: Dictionary = json.data
	_all_themes = Array(data.get("themes", []), TYPE_DICTIONARY, &"", null)


func _select_season_theme() -> void:
	if _all_themes.is_empty():
		_season_theme = {}
		return
	_season_theme = _all_themes[_rng.randi() % _all_themes.size()]

# ── Phase B: C++ EventEngine → GDScript display handler ──────────────────────
# Slot schedule generation / event selection / price injection moved to C++.
# GDScript receives ui_events[], resolves headlines, and applies news delay.

## Scope and tier name tables for C++ integer → GDScript string conversion.
const _SCOPE_NAMES: Array[String]  = ["INDIVIDUAL", "SECTOR", "MACRO"]
const _TIER_NAMES:  Array[String]  = ["SMALL", "MEDIUM", "LARGE", "MEGA"]


## Receives kernel-generated ui_events from PriceEngine.on_kernel_news.
## Each ui_event dict: template_id, scope (int), impact_tier (int), direction,
## tick (abs), selected_stock_id, target_stock_ids.
func _on_kernel_news(ui_events: Array) -> void:
	if _state != SystemState.ACTIVE:
		return
	for ui_event: Dictionary in ui_events:
		_queue_kernel_event(ui_event)


## Resolve a kernel ui_event to a display news entry and push to the delay queue.
func _queue_kernel_event(ui_event: Dictionary) -> void:
	# Phase C: ROTATION events have a separate display path (no template lookup).
	if ui_event.get("type", "EVENT") == "ROTATION":
		_queue_rotation_headline(ui_event)
		return
	var template_id: String = str(ui_event.get("template_id", ""))
	var scope_idx:   int    = clampi(int(ui_event.get("scope", 2)), 0, 2)
	var tier_idx:    int    = clampi(int(ui_event.get("impact_tier", 0)), 0, 3)
	var direction:   int    = int(ui_event.get("direction", 1))
	var abs_tick:    int    = int(ui_event.get("tick", 0))
	var sel_id:      String = str(ui_event.get("selected_stock_id", ""))
	var target_ids:  Array  = ui_event.get("target_stock_ids", [])

	var scope_str: String = _SCOPE_NAMES[scope_idx]
	var tier_str:  String = _TIER_NAMES[tier_idx]
	var tick_in_day: int  = abs_tick % GameClock.TICKS_PER_DAY

	# Look up template for text resolution
	var template: Dictionary = {}
	for t: Dictionary in _event_pool:
		if t.get("template_id", "") == template_id:
			template = t
			break
	if template.is_empty():
		return  # Unknown template — skip display

	var selected_stock: StockData = null
	if not sel_id.is_empty():
		selected_stock = StockDatabase.get_stock(sel_id)

	var headline: String = _resolve_text(template, direction, "headline", selected_stock)
	var body:     String = _resolve_text(template, direction, "body", selected_stock)

	var delay_ticks: int = get_news_delay()
	var entry: Dictionary = {
		"template_id":      template_id,
		"scope":            scope_str,
		"impact_tier":      tier_str,
		"direction":        direction,
		"headline":         headline,
		"body":             body,
		"impact_hint":      template.get("impact_hint", ""),
		"target_stock_ids": target_ids,
		"created_tick":     tick_in_day,
		"display_tick":     tick_in_day + delay_ticks,
		"day":              GameClock.get_current_day(),
	}
	_news_delay_queue.append(entry)
	_season_stats["total_events"] += 1
	_season_stats["by_scope"][scope_str] = _season_stats["by_scope"].get(scope_str, 0) + 1
	_season_stats["by_impact"][tier_str] = _season_stats["by_impact"].get(tier_str, 0) + 1
	on_event_generated.emit(entry)
	_maybe_emit_rumor(entry, template, direction)


## Phase C: Build a display headline for a ROTATION ui_event from the C++ ETF engine.
## Price impact is already applied by C++ (no MarketEvent created here).
func _queue_rotation_headline(ui_event: Dictionary) -> void:
	var sector:      String = str(ui_event.get("sector", ""))
	var direction:   String = str(ui_event.get("direction", "inflow"))
	var impact:      float  = float(ui_event.get("impact", 0.0))
	var tick_in_day: int    = int(ui_event.get("tick", 0))
	if sector.is_empty():
		return
	var headline_key: String = MarketProfile.get_rotation_headline(direction)
	if headline_key.is_empty():
		return
	var dir_int: int = 1 if direction == "inflow" else -1
	var delay_ticks: int = get_news_delay()
	var stocks: Array[StockData] = StockDatabase.get_stocks_by_sector(sector)
	var target_ids: Array = []
	for s: StockData in stocks:
		target_ids.append(s.stock_id)
	var entry: Dictionary = {
		"headline":         tr(headline_key).format({"sector": sector}),
		"body":             "",
		"impact_hint":      "positive" if dir_int > 0 else "negative",
		"scope":            "SECTOR",
		"impact_tier":      "MEDIUM",
		"direction":        dir_int,
		"sector":           sector,
		"target_stock_ids": target_ids,
		"created_tick":     tick_in_day,
		"display_tick":     tick_in_day + delay_ticks,
		"day":              GameClock.get_current_day(),
		"is_kernel":        true,
		"impact":           impact,
	}
	_news_delay_queue.append(entry)
	_season_stats["total_events"] += 1
	on_event_generated.emit(entry)


# ── Removed: _generate_daily_schedule / _check_scheduled_slots / _fire_event_from_slot ──
# ── Removed: _pick_scope / _pick_impact / _select_template / _select_individual_stock ────
# ── Removed: _resolve_event_target / _create_event_entry — all moved to C++ (Phase B) ────



## S3 루머 채널: 이벤트 발생 후 rumor_advance_ticks 전에 루머 힌트 발행 (GDD Rule 5-4, F6)
func _maybe_emit_rumor(entry: Dictionary, template: Dictionary, direction: int) -> void:
	_emit_rumor_if_eligible(entry, template, direction, entry["created_tick"])

# ── S3 Rumor Channel (GDD Rule 5-4, F6) ──

## Number of ticks a rumor leads the real event.
## Derived at runtime: SkillTree.RUMOR_LEAD_MINUTES × GameClock.TICKS_PER_MINUTE.
## (SkillTree.RUMOR_LEAD_MINUTES is @export var — cannot be used in a GDScript const.)
func _get_rumor_advance_ticks() -> int:
	return SkillTree.RUMOR_LEAD_MINUTES * GameClock.TICKS_PER_MINUTE

## Direction accuracy: 55% chance rumor direction matches real event (GDD F6).
## was: 0.70 before B-09 fix (2026-04-20)
const RUMOR_ACCURACY: float = 0.55

## Schedules FAKE_RUMOR_PER_DAY fake rumor ticks for the current trading day.
## Called by _on_market_open(). Ticks are stored in _fake_rumor_ticks and
## checked each tick in process_tick() → _check_fake_rumors().
func _schedule_fake_rumors() -> void:
	_fake_rumor_ticks.clear()
	if not SkillTree.has_rumor_channel():
		return
	for _i: int in range(FAKE_RUMOR_PER_DAY):
		var t: int = _rng.randi_range(FAKE_RUMOR_TICK_MIN, FAKE_RUMOR_TICK_MAX)
		_fake_rumor_ticks.append(t)


## Emits on_rumor_hint if S3 is unlocked and the event's impact tier qualifies.
## Called by _queue_kernel_event() for each real intra-day event from C++ kernel.
## GDD F6: rumor_tick = event_tick - _get_rumor_advance_ticks() (clamped to 0).
func _emit_rumor_if_eligible(
	news_entry: Dictionary, template: Dictionary, real_direction: int, event_tick: int
) -> void:
	if not SkillTree.has_rumor_channel():
		return

	var impact_tier: String = str(template.get("impact_tier", "SMALL"))
	var prob: float = float(RUMOR_PROBS.get(impact_tier, 0.0))
	if prob <= 0.0:
		return
	if _rng.randf() > prob:
		return

	# Direction: 55% accurate, 45% inverted (GDD F6 rumor_accuracy = 0.55)
	var rumor_direction: int = real_direction
	if _rng.randf() > RUMOR_ACCURACY:
		rumor_direction = -real_direction

	var scope: String = str(news_entry.get("scope", "MACRO"))
	var scope_label: String = _SCOPE_DISPLAY.get(scope, scope)

	# Vague headline — no specific company/template details revealed
	var rumor_headline: String = "[루머] %s 관련 중요 공시 임박 — 출처 미확인" % scope_label

	var rumor_entry: Dictionary = {
		"headline": rumor_headline,
		"body": "S3 루머 채널: 이벤트 발생 약 %d틱 전 힌트. 방향 및 규모 불확실." % _get_rumor_advance_ticks(),
		"scope": scope,
		"impact_tier": impact_tier,
		"direction": rumor_direction,
		"is_rumor": true,
		"is_fake": false,
		"display_tick": maxi(0, event_tick - _get_rumor_advance_ticks()),
		"day": GameClock.get_current_day(),
		"target_stock_ids": news_entry.get("target_stock_ids", []),
	}
	on_rumor_hint.emit(rumor_entry)


## Checks whether any fake rumor should fire at this tick and emits it.
## Called from process_tick(). Fake rumors have is_fake=true (GDD §5-4).
func _check_fake_rumors(tick: int) -> void:
	if not SkillTree.has_rumor_channel():
		return
	for i: int in range(_fake_rumor_ticks.size() - 1, -1, -1):
		if tick >= _fake_rumor_ticks[i]:
			_fake_rumor_ticks.remove_at(i)
			var scope: String = _SCOPE_NAMES[_rng.randi() % _SCOPE_NAMES.size()]
			var scope_label: String = _SCOPE_DISPLAY.get(scope, scope)
			var rumor_entry: Dictionary = {
				"headline": "[루머] %s 관련 이상 징후 — 미확인 정보" % scope_label,
				"body": "S3 루머 채널: 출처 불명. 신뢰도 낮음.",
				"scope": scope,
				"impact_tier": "SMALL",
				"direction": 1 if _rng.randf() < 0.5 else -1,
				"is_rumor": true,
				"is_fake": true,
				"display_tick": tick,
				"day": GameClock.get_current_day(),
			}
			on_rumor_hint.emit(rumor_entry)


# ── Text Resolution (GDD Rule 4-1) ──

func _resolve_text(
	template: Dictionary, direction: int, field: String, stock: StockData
) -> String:
	var text: String = ""

	# Check direction-specific fields first
	var dir_val = template.get("direction", 1)
	if dir_val is String and dir_val == "VARIABLE":
		if direction > 0:
			text = str(template.get(field + "_positive", ""))
		else:
			text = str(template.get(field + "_negative", ""))

	if text == "" or text == "null" or text == "<null>":
		text = str(template.get(field + "_template", ""))

	if text == "" or text == "null" or text == "<null>":
		return ""

	# System variables
	if stock != null:
		text = text.replace("{company}", stock.get_display_name())
		text = text.replace("{ticker}", stock.stock_id)
		text = text.replace("{sector_name}", stock.sector)

	var fiction_date: Dictionary = SeasonManager.get_fiction_date()
	text = text.replace("{date}", "%d월 %d일" % [fiction_date["month"], fiction_date["day"]])

	# Template-specific variables
	var variables: Dictionary = template.get("variables", {})
	for var_name: String in variables:
		var candidates: Array = variables[var_name]
		if not candidates.is_empty():
			var picked: String = candidates[_rng.randi() % candidates.size()]
			text = text.replace("{" + var_name + "}", picked)

	return text

# ── News Delay Queue Processing (GDD Rule 5) ──

func _process_news_delay_queue(tick: int) -> void:
	var to_display: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []

	for entry: Dictionary in _news_delay_queue:
		if tick >= entry["display_tick"]:
			to_display.append(entry)
		else:
			remaining.append(entry)

	_news_delay_queue = remaining

	for entry: Dictionary in to_display:
		on_news_display.emit(entry)


func _process_market_close_queue() -> void:
	## GDD Rule 5-3: INDIVIDUAL/SECTOR → discard, MACRO → summary
	var macro_pending: Array[Dictionary] = []

	for entry: Dictionary in _news_delay_queue:
		if entry["scope"] == "MACRO":
			macro_pending.append(entry)

	_news_delay_queue.clear()

	# Emit macro summaries immediately
	for entry: Dictionary in macro_pending:
		on_news_display.emit(entry)

# ── Overnight Events (GDD Rule 7) ──

func _generate_overnight_events() -> void:
	_overnight_buffer.clear()

	# Determine overnight event count (0, 1, or 2)
	var r: float = _rng.randf()
	var count: int = 0
	if r < OVERNIGHT_PROBS[0]:
		count = 0
	elif r < OVERNIGHT_PROBS[0] + OVERNIGHT_PROBS[1]:
		count = 1
	else:
		count = 2

	# Track mutex within this overnight batch to prevent same-group repeats
	var overnight_mutex: Dictionary = {}

	for _i: int in range(count):
		# Overnight: MACRO or SECTOR only, SMALL/MEDIUM only, GRADUAL_SHIFT only
		var scope: String = "MACRO" if _rng.randf() < OVERNIGHT_MACRO_PROB else "SECTOR"
		var impact: String = "SMALL" if _rng.randf() < OVERNIGHT_SMALL_PROB else "MEDIUM"

		var template: Dictionary = _select_overnight_template(scope, impact, overnight_mutex)
		if template.is_empty():
			continue

		# Register mutex to prevent same-group template in the next overnight slot
		var mg: Variant = template.get("mutex_group")
		if mg != null and mg is String and str(mg) != "":
			overnight_mutex[str(mg)] = template["template_id"]

		var direction: int = _resolve_direction(template)
		var target_ids: Array[String] = []

		if scope == "MACRO":
			target_ids = StockDatabase.get_all_stock_ids()
		else:
			var sector: String = str(template.get("target_sector", ""))
			if sector != "" and sector != "null":
				target_ids = StockDatabase.get_stock_ids_by_sector(sector)

		if target_ids.is_empty():
			continue

		var base_impact: float = _rng.randf_range(
			float(template.get("impact_min", 0.01)),
			float(template.get("impact_max", 0.03))
		)
		var decay_min: int = int(template.get("decay_minutes", DEFAULT_DECAY_MINUTES))
		if decay_min < MIN_DECAY_MINUTES:
			decay_min = DEFAULT_DECAY_MINUTES
		var decay_ticks: int = _minutes_to_ticks(decay_min)

		var decay_curve: MarketEvent.DecayCurve = MarketEvent.DecayCurve.LINEAR
		if template.get("decay_curve", "LINEAR") == "EXPONENTIAL":
			decay_curve = MarketEvent.DecayCurve.EXPONENTIAL

		var market_event: MarketEvent = MarketEvent.gradual_shift(
			base_impact, direction,
			_scope_str_to_enum(scope), target_ids,
			decay_ticks, decay_curve
		)

		var stock: StockData = null
		var headline: String = _resolve_text(template, direction, "headline", stock)
		var body: String = _resolve_text(template, direction, "body", stock)

		_overnight_buffer.append({
			"market_event": market_event,
			"headline": headline,
			"body": body,
			"impact_hint": template.get("impact_hint", ""),
			"scope": scope,
			"impact_tier": template.get("impact_tier", impact),
			"direction": direction,
			"target_stock_ids": target_ids,
		})


func _generate_overnight_disclosures() -> void:
	## GDD Rule 7-2: Per-stock 5% chance of INDIVIDUAL overnight disclosure
	for stock_id: String in StockDatabase.get_all_stock_ids():
		if _rng.randf() >= OVERNIGHT_INDIVIDUAL_PROB:
			continue

		var stock: StockData = StockDatabase.get_stock(stock_id)
		if stock == null:
			continue

		var direction: int = 1 if _rng.randf() < 0.5 else -1
		const OVERNIGHT_DISCLOSURE_IMPACT_MIN: float = 0.01
		const OVERNIGHT_DISCLOSURE_IMPACT_MAX: float = 0.05
		const OVERNIGHT_DISCLOSURE_DECAY_TICKS: int = 60  ## 15분 = 60틱 (TICKS_PER_MINUTE × 15)
		var base_impact: float = _rng.randf_range(OVERNIGHT_DISCLOSURE_IMPACT_MIN, OVERNIGHT_DISCLOSURE_IMPACT_MAX)

		var market_event: MarketEvent = MarketEvent.gradual_shift(
			base_impact, direction,
			MarketEvent.EventScope.INDIVIDUAL, [stock_id],
			OVERNIGHT_DISCLOSURE_DECAY_TICKS, MarketEvent.DecayCurve.LINEAR
		)

		var display_name: String = stock.get_display_name()
		var headline: String
		if direction > 0:
			headline = "%s, 호실적 잠정공시 발표" % display_name
		else:
			headline = "%s, 실적 부진 잠정공시" % display_name

		_overnight_buffer.append({
			"market_event": market_event,
			"headline": headline,
			"body": "%s의 잠정 실적이 발표됐다." % display_name,
			"impact_hint": "개별 공시",
			"scope": "INDIVIDUAL",
			"impact_tier": "SMALL",
			"direction": direction,
			"target_stock_ids": [stock_id],
		})


func _deliver_pre_market_news() -> void:
	if _overnight_buffer.is_empty():
		return

	var news_bundle: Array[Dictionary] = []

	for entry: Dictionary in _overnight_buffer:
		# Push event to PriceEngine
		var evt: MarketEvent = entry["market_event"]
		PriceEngine.push_event(evt)

		var news_entry: Dictionary = {
			"headline": entry["headline"],
			"body": entry["body"],
			"impact_hint": entry["impact_hint"],
			"scope": entry["scope"],
			"impact_tier": entry["impact_tier"],
			"direction": entry["direction"],
			"target_stock_ids": entry["target_stock_ids"],
			"display_tick": 0,
			"day": GameClock.get_current_day(),
			"is_pre_market": true,
		}
		news_bundle.append(news_entry)

		_season_stats["total_events"] += 1
		_season_stats["by_scope"][entry["scope"]] = _season_stats["by_scope"].get(entry["scope"], 0) + 1
		_season_stats["by_impact"][entry["impact_tier"]] = _season_stats["by_impact"].get(entry["impact_tier"], 0) + 1

	on_pre_market_news.emit(news_bundle)
	# _overnight_buffer는 여기서 clear하지 않는다 (ADR-015 개정).
	# 저장 시점이 PRE_MARKET(deliver 직후)이므로, 버퍼가 살아있어야
	# get_save_data()가 당일 뉴스를 overnight_display에 포함할 수 있다.
	# 버퍼 클리어는 다음 날 _generate_overnight_events() 첫 줄이 담당한다.


func _select_overnight_template(scope: String, impact: String, overnight_mutex: Dictionary) -> Dictionary:
	## Only GRADUAL_SHIFT templates for overnight; respects mutex to prevent same-group repeats.
	var candidates: Array[Dictionary] = []
	var weights: Array[float] = []

	for t: Dictionary in _event_pool:
		if t["scope"] != scope:
			continue
		if t.get("impact_tier", "") != impact:
			continue
		if t.get("event_type", "") != "GRADUAL_SHIFT":
			continue
		# Mutex check: skip if same mutex_group already used in this overnight batch
		var mg: Variant = t.get("mutex_group")
		if mg != null and mg is String and str(mg) != "":
			if overnight_mutex.has(str(mg)):
				continue
		candidates.append(t)
		weights.append(float(t.get("weight_base", 1.0)))

	if candidates.is_empty():
		return {}
	return _weighted_random_pick(candidates, weights)

# ── Utilities ──

func _resolve_direction(template: Dictionary) -> int:
	var dir_val = template.get("direction", 1)
	if dir_val is String and dir_val == "VARIABLE":
		return 1 if _rng.randf() < 0.5 else -1
	return int(dir_val)


func _scope_str_to_enum(scope: String) -> MarketEvent.EventScope:
	match scope:
		"MACRO":
			return MarketEvent.EventScope.MACRO
		"SECTOR":
			return MarketEvent.EventScope.SECTOR
		"INDIVIDUAL":
			return MarketEvent.EventScope.INDIVIDUAL
	return MarketEvent.EventScope.MACRO


func _weighted_random_pick(items: Array, weights: Array[float]) -> Variant:
	var total: float = 0.0
	for w: float in weights:
		total += w
	if total <= 0.0:
		return items[_rng.randi() % items.size()]

	var r: float = _rng.randf() * total
	var cumulative: float = 0.0
	for i: int in range(items.size()):
		cumulative += weights[i]
		if r <= cumulative:
			return items[i]
	return items[items.size() - 1]


func _reset_season_stats() -> void:
	_season_stats = {
		"total_events": 0,
		"by_scope": {"MACRO": 0, "SECTOR": 0, "INDIVIDUAL": 0},
		"by_impact": {"SMALL": 0, "MEDIUM": 0, "LARGE": 0, "MEGA": 0},
	}

# ── VI / Circuit Breaker News (GDD Rules 2-4, 2-5) ──

func _on_vi_triggered(stock_id: String, is_upper: bool, halt_ticks: int) -> void:
	var stock: StockData = StockDatabase.get_stock(stock_id)
	var display_name: String = stock.get_display_name() if stock else stock_id
	var direction_text: String = "상승" if is_upper else "하락"
	var halt_min: int = halt_ticks / GameClock.TICKS_PER_MINUTE
	var headline: String = "⚠️ [VI발동] %s %s — %d분 거래정지" % [display_name, direction_text, halt_min]
	var limit_type: String = "상한가" if is_upper else "하한가"
	var entry: Dictionary = {
		"headline": headline,
		"body": "단기 급%s으로 VI가 발동됐다. %s 전후 %d분간 단일가 매매로 전환, 이후 거래 재개." % [direction_text, limit_type, halt_min],
		"impact_hint": IMPACT_HINT_WARNING,
		"scope": "INDIVIDUAL",
		"impact_tier": "LARGE",
		"direction": 1 if is_upper else -1,
		"target_stock_ids": [stock_id],
		"display_tick": GameClock.get_current_tick(),
		"day": GameClock.get_current_day(),
		"is_system_event": true,
	}
	on_news_display.emit(entry)


func _on_vi_released(stock_id: String) -> void:
	var stock: StockData = StockDatabase.get_stock(stock_id)
	var display_name: String = stock.get_display_name() if stock else stock_id
	var headline: String = "ℹ️ [VI해제] %s 거래 재개" % display_name
	var entry: Dictionary = {
		"headline": headline,
		"body": "변동성 완화 확인 후 VI가 해제됐다. %s 정규 연속 매매가 재개된다." % display_name,
		"impact_hint": IMPACT_HINT_INFO,
		"scope": "INDIVIDUAL",
		"impact_tier": "MEDIUM",
		"direction": 0,
		"target_stock_ids": [stock_id],
		"display_tick": GameClock.get_current_tick(),
		"day": GameClock.get_current_day(),
		"is_system_event": true,
	}
	on_news_display.emit(entry)


func _on_circuit_breaker(stage: int, halt_ticks: int) -> void:
	var headline: String
	var cb_body: String
	if stage == 1:
		var halt_min: int = halt_ticks / GameClock.TICKS_PER_MINUTE
		var cb1_pct: int = int(absf(PriceEngine.CB_STAGE1_PCT) * 100)
		headline = "🚨 [CB 1단계] 시장 지수 -%d%% — %d분 전종목 거래정지" % [cb1_pct, halt_min]
		cb_body = "시장 지수가 전일 대비 %d%% 이상 하락해 서킷브레이커 1단계가 발동됐다. 전 종목 %d분간 거래가 정지된다." % [cb1_pct, halt_min]
	else:
		var cb2_pct: int = int(absf(PriceEngine.CB_STAGE2_PCT) * 100)
		headline = "🚨 [CB 2단계] 시장 지수 -%d%% — 당일 장 조기 마감" % cb2_pct
		cb_body = "시장 지수가 전일 대비 %d%% 이상 하락해 서킷브레이커 2단계가 발동됐다. 당일 장이 즉시 마감된다." % cb2_pct
	var entry: Dictionary = {
		"headline": headline,
		"body": cb_body,
		"impact_hint": IMPACT_HINT_EMERGENCY,
		"scope": "MACRO",
		"impact_tier": "MEGA",
		"direction": -1,
		"target_stock_ids": StockDatabase.get_all_stock_ids(),
		"display_tick": GameClock.get_current_tick(),
		"day": GameClock.get_current_day(),
		"is_system_event": true,
	}
	on_news_display.emit(entry)
