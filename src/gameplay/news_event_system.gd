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

# ── Constants: Slot Configuration (GDD Rule 2-1) ──

## Slot ranges in game-minutes (resolved to ticks at runtime via _build_slot_config).
## max_min 390 = GameClock.MINUTES_PER_DAY (const cannot reference autoload).
const SLOT_CONFIG_MINUTES: Array[Dictionary] = [
	{"name": "opening", "min_min": 1, "max_min": 100, "probability": 0.70},
	{"name": "midday_1", "min_min": 101, "max_min": 190, "probability": 0.55},
	{"name": "midday_2", "min_min": 191, "max_min": 280, "probability": 0.55},
	{"name": "closing", "min_min": 281, "max_min": 390, "probability": 0.60},
]

## Resolved at _ready(): minute ranges × TICKS_PER_MINUTE.
var _slot_config: Array[Dictionary] = []

const DAILY_HARD_CAP: int = 5

## Scope weights (GDD Rule 2-2)
const BASE_SCOPE_WEIGHTS: Dictionary = {
	"INDIVIDUAL": 0.55,
	"SECTOR": 0.35,
	"MACRO": 0.10,
}

## Impact tier weights (GDD Rule 2-3)
const IMPACT_TIER_WEIGHTS: Dictionary = {
	"SMALL": 0.35,
	"MEDIUM": 0.40,
	"LARGE": 0.20,
	"MEGA": 0.05,
}

## Volatility weight for INDIVIDUAL stock selection (GDD Rule 4-2)
const VOL_WEIGHT: Dictionary = {
	StockData.VolatilityProfile.LOW: 0.7,
	StockData.VolatilityProfile.MEDIUM: 1.0,
	StockData.VolatilityProfile.HIGH: 1.2,
	StockData.VolatilityProfile.EXTREME: 1.5,
}

## Individual target cooldown: minimum minutes between events targeting the same stock.
const INDIVIDUAL_TARGET_COOLDOWN_MIN: int = 22  ## ~22 game-minutes

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

var _daily_schedule: Array[Dictionary] = []   ## Pre-generated slots for today
var _daily_event_count: int = 0               ## Events fired today
var _daily_mega_fired: bool = false            ## MEGA already fired today

var _news_delay_queue: Array[Dictionary] = [] ## Pending news items awaiting display
var _overnight_buffer: Array[Dictionary] = [] ## Events for next morning

## Display-only entries restored from a save. Delivered to NewsFeed when it calls
## get_and_clear_loaded_news() in _ready(). MarketEvent objects are NOT re-pushed
## (price effects are already reflected in PriceEngine's saved state).
var _loaded_news_bundle: Array[Dictionary] = []

## Active market ID — used to filter event_pool templates by market_id field (TD-DR-05).
## Uppercase (e.g. "KR", "US"). DLC markets call set_active_market() before season start.
var _active_market_id: String = "KR"

## Cooldown tracking: template_id (or template_id+stock_id) -> last_used_tick
var _cooldown_tracker: Dictionary = {}
## Recent INDIVIDUAL targets: stock_id -> last_event_tick
var _recent_individual_targets: Dictionary = {}
## Last slot scope for clustering prevention
var _last_slot_scope: String = ""
## Mutex group tracking: resolved_mutex_key -> template_id (GDD Rule 3-1)
var _daily_mutex: Dictionary = {}

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
	_build_slot_config()
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


## Converts SLOT_CONFIG_MINUTES to tick-based _slot_config using GameClock constants.
func _build_slot_config() -> void:
	_slot_config.clear()
	var tpm: int = GameClock.TICKS_PER_MINUTE
	for slot: Dictionary in SLOT_CONFIG_MINUTES:
		_slot_config.append({
			"name": slot["name"],
			"tick_min": int(slot["min_min"]) * tpm,
			"tick_max": int(slot["max_min"]) * tpm,
			"probability": slot["probability"],
		})


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
	# Must be READY so _on_market_open() calls _generate_daily_schedule() instead of
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
	_daily_mutex.clear()
	_news_delay_queue.clear()
	_daily_event_count = 0
	_loaded_news_bundle.clear()
	_fake_rumor_ticks.clear()
	_state = SystemState.UNINITIALIZED


func _on_season_start() -> void:
	_rng.seed = Time.get_ticks_usec()  ## ADR-018: 시즌 시작마다 새 엔트로피로 재시드
	_load_event_pool()
	_load_themes()
	_select_season_theme()
	_reset_season_stats()
	_cooldown_tracker.clear()
	_recent_individual_targets.clear()
	_news_delay_queue.clear()
	_overnight_buffer.clear()
	_fake_rumor_ticks.clear()
	_daily_mega_fired = false
	_daily_event_count = 0
	_last_slot_scope = ""
	_state = SystemState.READY



func _on_season_end() -> void:
	_state = SystemState.UNINITIALIZED


func _on_market_open() -> void:
	if _state == SystemState.UNINITIALIZED:
		return
	_generate_daily_schedule()
	_daily_event_count = 0
	_daily_mega_fired = false
	_schedule_fake_rumors()
	_last_slot_scope = ""
	_daily_mutex.clear()
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

	# Check scheduled slots
	_check_scheduled_slots(tick)

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

# ── Daily Schedule Generation (GDD Rule 2-1, States section) ──

func _generate_daily_schedule() -> void:
	_daily_schedule.clear()
	for slot: Dictionary in _slot_config:
		if _rng.randf() > slot["probability"]:
			continue
		var tick: int = _rng.randi_range(slot["tick_min"], slot["tick_max"])
		var scope: String = _pick_scope()
		var impact: String = _pick_impact()
		_daily_schedule.append({
			"tick": tick,
			"scope": scope,
			"impact": impact,
			"fired": false,
		})
	# Sort by tick
	_daily_schedule.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tick"] < b["tick"])


func _check_scheduled_slots(tick: int) -> void:
	if _daily_event_count >= DAILY_HARD_CAP:
		return

	for slot: Dictionary in _daily_schedule:
		if slot["fired"]:
			continue
		if tick >= slot["tick"]:
			slot["fired"] = true
			_fire_event_from_slot(slot["scope"], slot["impact"], tick)
			_daily_event_count += 1
			if _daily_event_count >= DAILY_HARD_CAP:
				break

	# Minimum guarantee: if at mid-day tick and 0 events, force one
	if tick == GameClock.TICKS_PER_DAY / 2 and _daily_event_count == 0:
		_fire_event_from_slot("MACRO", "SMALL", tick)
		_daily_event_count += 1

# ── Event Firing ──

func _fire_event_from_slot(scope: String, impact: String, tick: int) -> void:
	# MEGA cap: only 1 per day
	if impact == "MEGA" and _daily_mega_fired:
		impact = "LARGE"
	if impact == "MEGA":
		_daily_mega_fired = true

	# Clustering prevention: same scope as last → 50% weight penalty, re-pick once
	if scope == _last_slot_scope and _rng.randf() < CLUSTER_PENALTY_PROB:
		scope = _pick_scope()

	var template: Dictionary = _select_template(scope, impact)
	if template.is_empty():
		# Fallback: try SMALL
		template = _select_template(scope, "SMALL")
		if template.is_empty():
			return  # No template available

	_last_slot_scope = scope

	var direction: int = _resolve_direction(template)
	var slot_data: Dictionary = {
		"scope": scope, "impact": impact, "tick": tick,
		"template": template, "direction": direction,
	}

	var target: Dictionary = _resolve_event_target(slot_data)
	if target.is_empty():
		return

	var entry: Dictionary = _create_event_entry(slot_data, target)
	_queue_event(entry)
	_maybe_emit_rumor(entry, target["template"], direction)


## Determine target stock IDs (and selected_stock for INDIVIDUAL scope).
## Returns a dict with "scope", "target_stock_ids", "selected_stock"; empty dict on failure.
func _resolve_event_target(slot_data: Dictionary) -> Dictionary:
	var scope: String = slot_data["scope"]
	var impact: String = slot_data["impact"]
	var tick: int = slot_data["tick"]
	var template: Dictionary = slot_data["template"]

	var target_stock_ids: Array[String] = []
	var selected_stock: StockData = null

	match scope:
		"MACRO":
			target_stock_ids = StockDatabase.get_all_stock_ids()
		"SECTOR":
			var sector: String = str(template.get("target_sector", ""))
			if sector != "" and sector != "null":
				target_stock_ids = StockDatabase.get_stock_ids_by_sector(sector)
		"INDIVIDUAL":
			selected_stock = _select_individual_stock(template, tick)
			if selected_stock == null:
				# Escalate to SECTOR
				scope = "SECTOR"
				template = _select_template("SECTOR", impact)
				if template.is_empty():
					return {}
				var sector2: String = str(template.get("target_sector", ""))
				if sector2 != "" and sector2 != "null":
					target_stock_ids = StockDatabase.get_stock_ids_by_sector(sector2)
			else:
				target_stock_ids = [selected_stock.stock_id]
				# Track recent individual targets
				_recent_individual_targets[selected_stock.stock_id] = tick

	if target_stock_ids.is_empty():
		return {}

	return {
		"scope": scope,
		"template": template,
		"target_stock_ids": target_stock_ids,
		"selected_stock": selected_stock,
	}


## Build the MarketEvent, push it to PriceEngine, track cooldown/mutex, and
## assemble the news_entry dict. Returns the completed news entry.
func _create_event_entry(slot_data: Dictionary, target: Dictionary) -> Dictionary:
	var tick: int = slot_data["tick"]
	var direction: int = slot_data["direction"]
	var impact: String = slot_data["impact"]
	var scope: String = target["scope"]
	var template: Dictionary = target["template"]
	var target_stock_ids: Array[String] = target["target_stock_ids"]
	var selected_stock: StockData = target["selected_stock"]

	# Compute actual impact magnitude
	var base_impact: float = _rng.randf_range(
		template.get("impact_min", 0.01),
		template.get("impact_max", 0.03)
	)

	# Build and push MarketEvent
	var event_type_str: String = template.get("event_type", "INSTANT_SHOCK")
	var decay_minutes: int = int(template.get("decay_minutes", 0))
	var decay_ticks: int = _minutes_to_ticks(decay_minutes)
	var decay_curve: MarketEvent.DecayCurve = MarketEvent.DecayCurve.LINEAR
	if template.get("decay_curve", "LINEAR") == "EXPONENTIAL":
		decay_curve = MarketEvent.DecayCurve.EXPONENTIAL

	var market_event: MarketEvent
	if event_type_str == "INSTANT_SHOCK" or decay_minutes == 0:
		market_event = MarketEvent.instant_shock(
			base_impact, direction,
			_scope_str_to_enum(scope), target_stock_ids
		)
	else:
		market_event = MarketEvent.gradual_shift(
			base_impact, direction,
			_scope_str_to_enum(scope), target_stock_ids,
			decay_ticks, decay_curve
		)
	PriceEngine.push_event(market_event)

	# Track cooldown and mutex
	var cooldown_key: String = template["template_id"]
	if scope == "INDIVIDUAL" and selected_stock != null:
		cooldown_key = template["template_id"] + "+" + selected_stock.stock_id
	_cooldown_tracker[cooldown_key] = tick + GameClock.get_current_day() * GameClock.TICKS_PER_DAY
	_register_mutex(template, selected_stock)

	# Build and return news entry dict
	var delay_ticks: int = get_news_delay()
	return {
		"template_id": template["template_id"],
		"scope": scope,
		"impact_tier": template.get("impact_tier", impact),
		"direction": direction,
		"headline": _resolve_text(template, direction, "headline", selected_stock),
		"body": _resolve_text(template, direction, "body", selected_stock),
		"impact_hint": template.get("impact_hint", ""),
		"target_stock_ids": target_stock_ids,
		"created_tick": tick,
		"display_tick": tick + delay_ticks,
		"day": GameClock.get_current_day(),
	}


## Append entry to the delay queue, update season stats, and emit on_event_generated.
func _queue_event(entry: Dictionary) -> void:
	_news_delay_queue.append(entry)
	_season_stats["total_events"] += 1
	_season_stats["by_scope"][entry["scope"]] = _season_stats["by_scope"].get(entry["scope"], 0) + 1
	var tier_key: String = entry["impact_tier"]
	_season_stats["by_impact"][tier_key] = _season_stats["by_impact"].get(tier_key, 0) + 1
	on_event_generated.emit(entry)


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
## checked each tick in process_tick() → _check_scheduled_slots().
func _schedule_fake_rumors() -> void:
	_fake_rumor_ticks.clear()
	if not SkillTree.has_rumor_channel():
		return
	for _i: int in range(FAKE_RUMOR_PER_DAY):
		var t: int = _rng.randi_range(FAKE_RUMOR_TICK_MIN, FAKE_RUMOR_TICK_MAX)
		_fake_rumor_ticks.append(t)


## Emits on_rumor_hint if S3 is unlocked and the event's impact tier qualifies.
## Called at the end of _fire_event_from_slot() for each real intra-day event.
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
			var scope: String = _pick_scope()
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

# ── Template Selection (GDD Rule 2-5) ──

func _select_template(scope: String, impact: String) -> Dictionary:
	var current_tick: int = GameClock.get_current_tick()
	var abs_tick: int = current_tick + GameClock.get_current_day() * GameClock.TICKS_PER_DAY
	var theme_tags: Array = _season_theme.get("active_season_tags", [])

	var candidates: Array[Dictionary] = []
	var weights: Array[float] = []

	for t: Dictionary in _event_pool:
		# Scope filter
		if t["scope"] != scope:
			continue
		# Impact filter
		if t.get("impact_tier", "") != impact:
			continue
		# Cooldown check
		var cd_key: String = t["template_id"]
		if _cooldown_tracker.has(cd_key):
			var last_tick: int = _cooldown_tracker[cd_key]
			if abs_tick - last_tick < _minutes_to_ticks(int(t.get("cooldown_minutes", 0))):
				continue
		# Season tag filter
		var s_tags: Array = t.get("season_tags", [])
		if not s_tags.is_empty():
			var match_found: bool = false
			for st: String in s_tags:
				if theme_tags.has(st):
					match_found = true
					break
			if not match_found:
				continue

		# Mutex group filter (GDD Rule 3-1)
		var mutex: Variant = t.get("mutex_group")
		if mutex != null and mutex is String and str(mutex) != "":
			# For MACRO/SECTOR scope, no {stock_id} placeholder to resolve yet.
			# For INDIVIDUAL, we check all possible resolved keys.
			var mutex_str: String = str(mutex)
			if not mutex_str.contains("{stock_id}"):
				# Fixed mutex key (MACRO/SECTOR) — check directly
				if _daily_mutex.has(mutex_str):
					continue
			# INDIVIDUAL with {stock_id}: defer check to _is_mutex_blocked_for_stock()

		# Compute weight
		var w: float = float(t.get("weight_base", 1.0))
		# Apply sector bias from theme
		var t_sector: String = str(t.get("target_sector", ""))
		if t_sector != "" and _season_theme.size() > 0:
			var bias: Dictionary = _season_theme.get("sector_bias", {})
			w *= float(bias.get(t_sector, 1.0))

		candidates.append(t)
		weights.append(w)

	if candidates.is_empty():
		return {}

	return _weighted_random_pick(candidates, weights)

# ── Scope & Impact Selection ──

func _pick_scope() -> String:
	var adjusted: Dictionary = {}
	for scope: String in BASE_SCOPE_WEIGHTS:
		var scale_key: String = scope.to_lower() + "_weight_scale"
		var scale: float = float(_season_theme.get(scale_key, 1.0))
		adjusted[scope] = float(BASE_SCOPE_WEIGHTS[scope]) * scale

	# Normalize
	var total: float = 0.0
	for v: float in adjusted.values():
		total += v

	var r: float = _rng.randf() * total
	var cumulative: float = 0.0
	for scope: String in adjusted:
		cumulative += adjusted[scope]
		if r <= cumulative:
			return scope
	return "INDIVIDUAL"


func _pick_impact() -> String:
	var r: float = _rng.randf()
	var cumulative: float = 0.0
	for impact: String in IMPACT_TIER_WEIGHTS:
		cumulative += float(IMPACT_TIER_WEIGHTS[impact])
		if r <= cumulative:
			return impact
	return "SMALL"

# ── INDIVIDUAL Stock Selection (GDD Rule 4-2) ──

func _select_individual_stock(template: Dictionary, tick: int) -> StockData:
	var tags: Array = template.get("event_tags", [])
	var abs_tick: int = tick + GameClock.get_current_day() * GameClock.TICKS_PER_DAY

	# Find candidate stocks with matching tags
	var candidates: Array[StockData] = []
	var weights: Array[float] = []

	for tag in tags:
		for stock: StockData in StockDatabase.get_stocks_by_event_tag(tag):
			# Skip if already in candidates
			var already: bool = false
			for c: StockData in candidates:
				if c.stock_id == stock.stock_id:
					already = true
					break
			if already:
				continue

			# Skip if recently targeted (cooldown protection)
			if _recent_individual_targets.has(stock.stock_id):
				var last_t: int = _recent_individual_targets[stock.stock_id]
				if abs_tick - last_t < _minutes_to_ticks(INDIVIDUAL_TARGET_COOLDOWN_MIN):
					continue

			# Mutex check for INDIVIDUAL templates with {stock_id} placeholder
			if _is_mutex_blocked_for_stock(template, stock.stock_id):
				continue

			var w: float = stock.sector_sensitivity * float(VOL_WEIGHT.get(stock.volatility_profile, 1.0))
			candidates.append(stock)
			weights.append(w)

	if candidates.is_empty():
		return null

	return _weighted_random_pick(candidates, weights)

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

# ── Mutex Group (GDD Rule 3-1) ──

## Checks if a template is mutex-blocked for a specific stock.
func _is_mutex_blocked_for_stock(template: Dictionary, stock_id: String) -> bool:
	var mutex: Variant = template.get("mutex_group")
	if mutex == null or not (mutex is String) or str(mutex) == "":
		return false
	var key: String = str(mutex).replace("{stock_id}", stock_id)
	return _daily_mutex.has(key)


## Registers a mutex key after an event fires.
func _register_mutex(template: Dictionary, stock: StockData) -> void:
	var mutex: Variant = template.get("mutex_group")
	if mutex == null or not (mutex is String) or str(mutex) == "":
		return
	var key: String = str(mutex)
	if stock != null:
		key = key.replace("{stock_id}", stock.stock_id)
	_daily_mutex[key] = template["template_id"]


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
