## FinancialReportSystem — ADR-027 Phase D: UI display layer for earnings reports.
## Computation (ROE scheduling, event generation, A3 update) moved to C++ PriceKernel.
## GDD: design/gdd/financial-report-system.md
##
## Entry points:
##   NewsEventSystem._queue_kernel_event(REPORT) → _on_kernel_report(ev)
##   PriceEngine.process_tick() a3_updates → _apply_kernel_a3_updates(updates)
##
## See: docs/architecture/027-price-kernel-unification.md (Phase D)
extends Node

# ── Headline Template Constants (ADR: 표시 포맷 단일 소유) ──

## TD-CR-13: 리터럴 중복 방지. %s = display_name 자리.
const _HL_TARGET_UP:   String = "[%s] 목표주가 상향 — 분기 실적 기대감 반영"
const _HL_TARGET_DOWN: String = "[%s] 목표주가 하향 — 원가 압박 지속 우려"
const _HL_EARNS_POS:   String = "[%s] 잠정실적 — 영업이익 전분기 대비 개선"
const _HL_EARNS_NEG:   String = "[%s] 잠정실적 — 매출 컨센서스 하회 우려"
const _HL_RUMOR_POS:   String = "[%s] 실적 발표 임박 — 컨센서스 상회 강력 전망"
const _HL_RUMOR_NEG:   String = "[%s] 실적 발표 임박 — 컨센서스 하회 우려 고조"
const _HL_TURNAROUND:  String = "[%s] 흑자 전환 성공 — 시장 예상 크게 상회"
const _HL_RED_TURN:    String = "[%s] 적자 전환 — 실적 대폭 악화"
const _HL_BEAT:        String = "[%s] 어닝서프라이즈 — 컨센서스 대비 대폭 상회"
const _HL_MISS:        String = "[%s] 어닝쇼크 — 컨센서스 크게 하회"

# ── Lifecycle ──

func _ready() -> void:
	pass  # C++ PriceKernel drives all scheduling — no signal connections needed.

# ── Public API: Kernel Integration ──

## Dispatches a REPORT kernel event to the appropriate display method.
## Called by NewsEventSystem._queue_kernel_event() for type=="REPORT" ui_events.
## subtypes: ANALYST_UP/DOWN, PRELIM_POS/NEG, RUMOR_POS/NEG,
##           TURNAROUND_PROFIT/LOSS, EARNINGS_SURPRISE/SHOCK.
func _on_kernel_report(ev: Dictionary) -> void:
	var subtype: String  = str(ev.get("subtype",     ""))
	var stock_id: String = str(ev.get("stock_id",    ""))
	var direction: int   = int(ev.get("direction",    1))
	var impact_tier: String = str(ev.get("impact_tier", "SMALL"))
	match subtype:
		"ANALYST_UP", "ANALYST_DOWN":
			_fire_display_analyst(stock_id, direction)
		"PRELIM_POS", "PRELIM_NEG":
			_fire_display_preliminary(stock_id, direction)
		"RUMOR_POS", "RUMOR_NEG":
			_fire_display_rumor(stock_id, direction)
		"TURNAROUND_PROFIT", "TURNAROUND_LOSS", "EARNINGS_SURPRISE", "EARNINGS_SHOCK":
			_publish_earnings_news(stock_id, subtype, direction, impact_tier)
		# Neutral official result: no display card


## Applies A3 (ROE/PER/PBR) updates from C++ ReportEngine to StockData.
## Called by PriceEngine.process_tick() when a3_updates is non-empty. ADR-027 Phase D.
## a3_updates entries: {stock_id, new_roe (pct), new_per, new_pbr}.
func _apply_kernel_a3_updates(updates: Array) -> void:
	for u: Dictionary in updates:
		var stock: StockData = StockDatabase.get_stock(str(u.get("stock_id", "")))
		if stock == null:
			continue
		stock.roe = float(u.get("new_roe", stock.roe))
		stock.per = float(u.get("new_per", stock.per))
		stock.pbr = float(u.get("new_pbr", stock.pbr))

# ── Public API: Query (pure formula methods) ──

## Returns true if [param season] is a reporting season. Reads from MarketProfile.
## AC-FR-01. Cycle and start defaults match KR market (ADR-021).
func is_report_season(season: int) -> bool:
	var cycle: int = _calendar_int("report_cycle_seasons",      3)
	var start: int = _calendar_int("fiscal_year_start_season",  1)
	if season < start + cycle:
		return false
	return (season - start) % cycle == 0


## Returns the report type string for a given season (e.g. "Q1", "H1", "Q3", "Annual").
## Returns "" for non-report seasons. AC-FR-02.
func get_report_type(season: int) -> String:
	if not is_report_season(season):
		return ""
	var seq: Variant = MarketProfile.get_calendar_param("report_type_sequence")
	if not seq is Array or (seq as Array).is_empty():
		return ""
	var cycle: int = _calendar_int("report_cycle_seasons",     3)
	var start: int = _calendar_int("fiscal_year_start_season", 1)
	var index: int = ((season - start) / cycle - 1) % (seq as Array).size()
	return str((seq as Array)[index])


## No-op. Scheduling is now handled by C++ PriceKernel.start_season() (ADR-027 Phase D).
## Kept for API compatibility and SeasonManager.on_season_started signal compatibility.
func schedule_quarterly_events(_season: int) -> void:
	pass


## Resets report display state. C++ kernel state is reset via PriceEngine.reset().
func reset() -> void:
	pass

# ── Internal: Display Dispatch ──

func _fire_display_analyst(stock_id: String, direction: int) -> void:
	var stock: StockData = StockDatabase.get_stock(stock_id)
	var name: String = stock.get_display_name() if stock != null else stock_id
	var headline: String
	var body: String
	if direction > 0:
		headline = _HL_TARGET_UP % name
		body = "애널리스트 리포트: 향후 실적 개선 전망 반영, 목표주가 상향 조정."
	else:
		headline = _HL_TARGET_DOWN % name
		body = "애널리스트 리포트: 비용 증가 압박으로 수익성 악화 전망, 목표주가 하향 조정."
	NewsEventSystem.fire_stock_news(stock_id, headline, body, direction, "SMALL")


func _fire_display_preliminary(stock_id: String, direction: int) -> void:
	var stock: StockData = StockDatabase.get_stock(stock_id)
	var name: String = stock.get_display_name() if stock != null else stock_id
	var headline: String
	var body: String
	if direction > 0:
		headline = _HL_EARNS_POS % name
		body = "잠정실적 공시: 영업이익 전분기 대비 개선, 컨센서스 상회 전망. 순이익 미확정."
	else:
		headline = _HL_EARNS_NEG % name
		body = "잠정실적 공시: 매출 컨센서스 하회, 수익성 악화 우려. 순이익 미확정."
	NewsEventSystem.fire_stock_news(stock_id, headline, body, direction, "MEDIUM")


func _fire_display_rumor(stock_id: String, direction: int) -> void:
	var stock: StockData = StockDatabase.get_stock(stock_id)
	var name: String = stock.get_display_name() if stock != null else stock_id
	var headline: String
	var body: String
	if direction > 0:
		headline = _HL_RUMOR_POS % name
		body = "내부 채널: 컨센서스를 크게 상회하는 실적이 예상된다는 소문이 돌고 있다."
	else:
		headline = _HL_RUMOR_NEG % name
		body = "내부 채널: 컨센서스를 하회하는 실적이 예상된다는 소문이 돌고 있다."
	# Display only — price pressure is already applied by C++ ReportEngine._re_fire_rumor()
	NewsEventSystem.fire_stock_news(stock_id, headline, body, direction, "SMALL")


func _publish_earnings_news(
	stock_id: String, event_type: String, direction: int, impact_tier: String
) -> void:
	var stock: StockData = StockDatabase.get_stock(stock_id)
	var name: String = stock.get_display_name() if stock != null else stock_id
	var headline: String
	var body: String
	match event_type:
		"TURNAROUND_PROFIT":
			headline = _HL_TURNAROUND % name
			body = "공식 실적 발표: 이전 분기 적자에서 흑자 전환. 시장 컨센서스를 대폭 상회."
		"TURNAROUND_LOSS":
			headline = _HL_RED_TURN % name
			body = "공식 실적 발표: 흑자에서 적자로 전환. 수익성이 크게 악화됐다."
		"EARNINGS_SURPRISE":
			headline = _HL_BEAT % name
			body = "공식 실적 발표: 시장 컨센서스를 크게 상회하는 어닝서프라이즈 달성."
		"EARNINGS_SHOCK":
			headline = _HL_MISS % name
			body = "공식 실적 발표: 시장 기대치를 크게 하회하는 어닝쇼크. 투자자들이 당혹감을 감추지 못하고 있다."
		_:
			return  # No card for neutral result
	NewsEventSystem.fire_stock_news(stock_id, headline, body, direction, impact_tier)


## Helper: read int calendar param from MarketProfile with fallback. ADR-021.
func _calendar_int(param: String, fallback: int) -> int:
	var v: Variant = MarketProfile.get_calendar_param(param)
	return int(v) if v != null else fallback

# ── Serialization ──

## Returns C++ ReportEngine state for the save system.
func get_save_data() -> Dictionary:
	return {"kernel_report_state": PriceEngine.get_report_state()}


## Restores C++ ReportEngine state from a save. Must be called after PriceEngine.initialize_for_load().
func load_save_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	var state: Variant = data.get("kernel_report_state", {})
	if state is Dictionary and not (state as Dictionary).is_empty():
		PriceEngine.restore_report_state(state as Dictionary)
	# Legacy saves (pre-Phase D) have "pending_events" key — kernel generates fresh state, no restore.
