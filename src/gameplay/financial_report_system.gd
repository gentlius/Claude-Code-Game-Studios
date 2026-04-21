## FinancialReportSystem — Autoload. 분기 실적 발표 시뮬레이션.
## GDD: design/gdd/financial-report-system.md
## Phase 1: 분기 스케줄러, consensus_roe, 3단계 정보 공개,
##           뉴스/이벤트 연동, 세이브/로드, E-09 섹터 파급.
##
## 시장별 보고서 주기/잠정확률은 MarketProfile.get_calendar_param()에서 읽는다. ADR-021.
## 게임 메커닉 튜닝값(노이즈/임계값)은 financial_report_config.json에서 읽는다.
##
## 진입점:
##   SeasonManager.on_season_started → schedule_quarterly_events(season)
##   GameClock.on_market_state_changed(PRE_MARKET) → _on_pre_market(day)
##   GameClock.on_tick(tick, day, week) → _on_tick(tick, day)
##
## See: docs/architecture/ADR-022 — EventSource → NewsEventSystem → PriceEngine
extends Node

# ── Constants ──

const CONFIG_PATH: String = "res://assets/data/financial_report_config.json"

## 헤드라인 템플릿 상수 — TD-CR-13: 리터럴 중복 방지. %s = display_name 자리
const _HL_TARGET_UP:    String = "[%s] 목표주가 상향 — 분기 실적 기대감 반영"
const _HL_TARGET_DOWN:  String = "[%s] 목표주가 하향 — 원가 압박 지속 우려"
const _HL_EARNS_POS:    String = "[%s] 잠정실적 — 영업이익 전분기 대비 개선"
const _HL_EARNS_NEG:    String = "[%s] 잠정실적 — 매출 컨센서스 하회 우려"
const _HL_RUMOR_POS:    String = "[%s] 실적 발표 임박 — 컨센서스 상회 강력 전망"
const _HL_RUMOR_NEG:    String = "[%s] 실적 발표 임박 — 컨센서스 하회 우려 고조"
const _HL_TURNAROUND:   String = "[%s] 흑자 전환 성공 — 시장 예상 크게 상회"
const _HL_RED_TURN:     String = "[%s] 적자 전환 — 실적 대폭 악화"
const _HL_BEAT:         String = "[%s] 어닝서프라이즈 — 컨센서스 대비 대폭 상회"
const _HL_MISS:         String = "[%s] 어닝쇼크 — 컨센서스 크게 하회"

# ── Config (loaded from JSON) ──

## Market-calendar params — loaded from MarketProfile.get_calendar_param() (ADR-021).
## Defaults match KR market; overwritten in _load_from_market_profile().
var REPORT_CYCLE_SEASONS: int = 3
var FISCAL_YEAR_START_SEASON: int = 1
var REPORT_TYPE_SEQUENCE: Array = ["Q1", "H1", "Q3", "Annual"]

var PRELIMINARY_ENABLED: bool = true
var PRELIMINARY_DAY_OFFSET: int = 3
## Probability that a stock gets a preliminary earnings release, by VolatilityProfile name.
var PRELIMINARY_PROBABILITY: Dictionary = {
	"LOW": 0.90, "MEDIUM": 0.70, "HIGH": 0.30, "EXTREME": 0.00
}

var NEWS_STOCK_MIN: int = 8
var NEWS_STOCK_MAX: int = 12
var REPORT_DAY_MIN: int = 5
var REPORT_DAY_MAX: int = 18
var ANALYST_DAY_MIN: int = 3
var ANALYST_DAY_MAX: int = 10
var RUMOR_FIRE_TICK_IN_DAY: int = 40
var RUMOR_FAKE_RATE: float = 0.30

var ROE_NEWS_THRESHOLD: float = 0.03
var SURPRISE_THRESHOLD: float = 0.05
var SHOCK_THRESHOLD: float = 0.05
var CONSENSUS_UNCERTAINTY_MAX: float = 0.08
var UNCERTAINTY_DECAY: float = 8.0
var SECTOR_RIPPLE_RATIO: float = 0.30
var SECTOR_NOISE: float = 0.03
var STOCK_NOISE: float = 0.02
var ROE_MIN: float = -0.30
var ROE_MAX: float = 0.50
var PER_NEGATIVE_SENTINEL: float = -1.0
## Scale factor: sector_bias deviation (bias-1.0) × ROE_DRIFT_SCALE → roe_drift
var ROE_DRIFT_SCALE: float = 0.04
var SECTOR_RIPPLE_IMPACT: float = 0.06
var SECTOR_RIPPLE_DECAY_TICKS: int = 4

# ── State ──

## stock_id → event dict (see _build_event_entry). Cleared after report fires.
var _pending_events: Dictionary = {}
var _current_season: int = 0
var _is_report_season_active: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _consensus_rng: RandomNumberGenerator = RandomNumberGenerator.new()

# ── Lifecycle ──

func _ready() -> void:
	_load_config()
	_load_from_market_profile()  # market-specific calendar params override config defaults
	SeasonManager.on_season_started.connect(_on_season_started)
	GameClock.on_market_state_changed.connect(_on_market_state_changed)
	GameClock.on_tick.connect(_on_tick)


func _load_config() -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		push_warning("FinancialReportSystem: config not found at %s — using defaults" % CONFIG_PATH)
		return
	var result: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if result == null or not result is Dictionary:
		push_warning("FinancialReportSystem: JSON parse failed — using defaults")
		return
	var cfg: Dictionary = result as Dictionary
	# reportCycleSeasons / reportTypeSequence 는 _load_from_market_profile()에서
	# MarketProfile로 덮어쓰므로 config.json 값은 무시한다 (ADR-021).
	NEWS_STOCK_MIN              = int(cfg.get("newsStockMin", NEWS_STOCK_MIN))
	NEWS_STOCK_MAX              = int(cfg.get("newsStockMax", NEWS_STOCK_MAX))
	REPORT_DAY_MIN              = int(cfg.get("reportDayMin", REPORT_DAY_MIN))
	REPORT_DAY_MAX              = int(cfg.get("reportDayMax", REPORT_DAY_MAX))
	ANALYST_DAY_MIN             = int(cfg.get("analystDayMin", ANALYST_DAY_MIN))
	ANALYST_DAY_MAX             = int(cfg.get("analystDayMax", ANALYST_DAY_MAX))
	RUMOR_FIRE_TICK_IN_DAY      = int(cfg.get("rumorFireTickInDay", RUMOR_FIRE_TICK_IN_DAY))
	RUMOR_FAKE_RATE             = float(cfg.get("rumorFakerate", RUMOR_FAKE_RATE))
	ROE_NEWS_THRESHOLD          = float(cfg.get("roeNewsThreshold", ROE_NEWS_THRESHOLD))
	SURPRISE_THRESHOLD          = float(cfg.get("surpriseThreshold", SURPRISE_THRESHOLD))
	SHOCK_THRESHOLD             = float(cfg.get("shockThreshold", SHOCK_THRESHOLD))
	CONSENSUS_UNCERTAINTY_MAX   = float(cfg.get("consensusUncertaintyMax", CONSENSUS_UNCERTAINTY_MAX))
	UNCERTAINTY_DECAY           = float(cfg.get("uncertaintyDecay", UNCERTAINTY_DECAY))
	SECTOR_RIPPLE_RATIO         = float(cfg.get("sectorRippleRatio", SECTOR_RIPPLE_RATIO))
	SECTOR_NOISE                = float(cfg.get("sectorNoise", SECTOR_NOISE))
	STOCK_NOISE                 = float(cfg.get("stockNoise", STOCK_NOISE))
	ROE_MIN                     = float(cfg.get("roeMin", ROE_MIN))
	ROE_MAX                     = float(cfg.get("roeMax", ROE_MAX))
	PER_NEGATIVE_SENTINEL       = float(cfg.get("perNegativeSentinel", PER_NEGATIVE_SENTINEL))
	ROE_DRIFT_SCALE             = float(cfg.get("roeDriftScale", ROE_DRIFT_SCALE))
	SECTOR_RIPPLE_IMPACT        = float(cfg.get("sectorRippleImpact", SECTOR_RIPPLE_IMPACT))
	SECTOR_RIPPLE_DECAY_TICKS   = int(cfg.get("sectorRippleDecayTicks", SECTOR_RIPPLE_DECAY_TICKS))
	# preliminaryEarnings 는 _load_from_market_profile()에서 MarketProfile로 덮어쓴다 (ADR-021).


## Load market-specific calendar params from MarketProfile (ADR-021).
## Called from _ready() after _load_config(). Safe to call again on market switch.
func _load_from_market_profile() -> void:
	var cycle: Variant = MarketProfile.get_calendar_param("report_cycle_seasons")
	if cycle != null:
		REPORT_CYCLE_SEASONS = int(cycle)

	var start: Variant = MarketProfile.get_calendar_param("fiscal_year_start_season")
	if start != null:
		FISCAL_YEAR_START_SEASON = int(start)

	var seq: Variant = MarketProfile.get_calendar_param("report_type_sequence")
	if seq is Array:
		REPORT_TYPE_SEQUENCE = seq

	var pe: Variant = MarketProfile.get_calendar_param("preliminary_earnings")
	if pe is Dictionary:
		PRELIMINARY_ENABLED    = bool(pe.get("enabled", PRELIMINARY_ENABLED))
		PRELIMINARY_DAY_OFFSET = int(pe.get("day_offset", PRELIMINARY_DAY_OFFSET))
		var prob: Variant = pe.get("probability_by_profile", null)
		if prob is Dictionary:
			PRELIMINARY_PROBABILITY = prob


# ── Public API: Season Schedule ──

## Called from SeasonManager.on_season_started. Schedules this season's quarterly events.
## If not a report season, silently updates all A3 data (ROE/PER/PBR) and returns.
func schedule_quarterly_events(season: int) -> void:
	_current_season = season
	_pending_events.clear()

	if not is_report_season(season):
		_is_report_season_active = false
		_do_quiet_update_all(season)
		return

	_is_report_season_active = true
	# Seed RNGs deterministically per season (anti-price-scout: see ADR-018)
	_rng.seed = hash("FRS_season_%d" % season)
	_consensus_rng.seed = hash("FRS_consensus_%d" % season)

	var all_ids: Array[String] = StockDatabase.get_all_stock_ids()
	var newsworthy: Array[String] = _select_newsworthy(all_ids, season)

	for stock_id: String in newsworthy:
		_pending_events[stock_id] = _build_event_entry(stock_id, season)

	# Remaining stocks: schedule silent A3 refresh on season day 1 PRE_MARKET
	for stock_id: String in all_ids:
		if not _pending_events.has(stock_id):
			_pending_events[stock_id] = {"quiet": true, "report_done": false}


## Returns true if [param season] is a reporting season for the KR market.
## KR: every REPORT_CYCLE_SEASONS seasons starting from FISCAL_YEAR_START_SEASON + cycle.
## AC-FR-01.
func is_report_season(season: int) -> bool:
	if season < FISCAL_YEAR_START_SEASON + REPORT_CYCLE_SEASONS:
		return false
	return (season - FISCAL_YEAR_START_SEASON) % REPORT_CYCLE_SEASONS == 0


## Returns the report type string for a given season (e.g. "Q1", "H1", "Q3", "Annual").
## Returns "" for non-report seasons. AC-FR-02.
func get_report_type(season: int) -> String:
	if not is_report_season(season) or REPORT_TYPE_SEQUENCE.is_empty():
		return ""
	var index: int = ((season - FISCAL_YEAR_START_SEASON) / REPORT_CYCLE_SEASONS - 1) \
		% REPORT_TYPE_SEQUENCE.size()
	return str(REPORT_TYPE_SEQUENCE[index])

# ── Public API: Query ──

## Returns all pending event entries (shallow copy). For tests and debugging.
func get_pending_events() -> Dictionary:
	return _pending_events.duplicate(true)


## Resets all state. Called by GameMain (new game) and tests (before_each).
func reset() -> void:
	_pending_events.clear()
	_current_season = 0
	_is_report_season_active = false

# ── Internal: ROE Formula ──

## Actual ROE for the season. Generated at official report time. GDD F1.
func _compute_new_roe(stock_id: String) -> float:
	var stock: StockData = StockDatabase.get_stock(stock_id)
	if stock == null:
		return 0.0
	var prev_roe: float = stock.roe / 100.0  # stored as percentage e.g. 16.0 → 0.16
	var theme_drift: float = _get_theme_drift(stock.sector)
	var sector_noise: float = _rng.randf_range(-SECTOR_NOISE, SECTOR_NOISE)
	var stock_noise: float  = _rng.randf_range(-STOCK_NOISE, STOCK_NOISE)
	return clampf(prev_roe + theme_drift + sector_noise + stock_noise, ROE_MIN, ROE_MAX)


## Consensus ROE (market expectation). Independent RNG from new_roe. GDD F2.
func _compute_consensus_roe(stock_id: String, reporting_day: int) -> float:
	var stock: StockData = StockDatabase.get_stock(stock_id)
	if stock == null:
		return 0.0
	var prev_roe: float = stock.roe / 100.0
	var theme_drift: float = _get_theme_drift(stock.sector)
	var uncertainty: float = CONSENSUS_UNCERTAINTY_MAX * exp(-float(reporting_day) / UNCERTAINTY_DECAY)
	var consensus_noise: float = _consensus_rng.randf_range(-uncertainty, uncertainty)
	return clampf(prev_roe + theme_drift + consensus_noise, ROE_MIN, ROE_MAX)


## Derive theme_drift from the active season theme's sector_bias for [param sector].
## Sectors with bias > 1.0 get positive drift; < 1.0 get negative drift.
## Approximates the GDD's `theme.roe_drift × sector_bias` formula.
func _get_theme_drift(sector: String) -> float:
	var theme: Dictionary = NewsEventSystem.get_season_theme()
	if theme.is_empty():
		return 0.0
	var sector_bias_dict: Dictionary = theme.get("sector_bias", {})
	var bias: float = float(sector_bias_dict.get(sector, 1.0))
	return (bias - 1.0) * ROE_DRIFT_SCALE

# ── Internal: Event Classification ──

## Classify earnings result: TURNAROUND_PROFIT/LOSS, EARNINGS_SURPRISE/SHOCK, or "".
## GDD §3-5, F3.
func _classify_event(
	prev_roe_raw: float,  ## normalized (0.16 not 16)
	new_roe: float,
	consensus_roe: float
) -> String:
	# Priority 1: turnaround
	if prev_roe_raw <= 0.0 and new_roe > 0.0:
		return "TURNAROUND_PROFIT"
	if prev_roe_raw > 0.0 and new_roe <= 0.0:
		return "TURNAROUND_LOSS"
	# Priority 2: surprise/shock vs consensus
	if new_roe - consensus_roe >= SURPRISE_THRESHOLD:
		return "EARNINGS_SURPRISE"
	if consensus_roe - new_roe >= SHOCK_THRESHOLD:
		return "EARNINGS_SHOCK"
	return ""


## Returns the event sign (+1 or -1) for scheduling purposes (used to bias rumor direction).
func _get_event_sign(stock_id: String, season: int) -> int:
	var stock: StockData = StockDatabase.get_stock(stock_id)
	if stock == null:
		return 1
	# Snapshot consensus to determine bias (consensus_rng advances here for consistency)
	var reporting_day: int = _rng.randi_range(REPORT_DAY_MIN, REPORT_DAY_MAX)
	var consensus: float = _compute_consensus_roe(stock_id, reporting_day)
	var prev_roe: float = stock.roe / 100.0
	var theme_drift: float = _get_theme_drift(stock.sector)
	# Expected actual ROE ≈ prev + drift (without noise). Compare to consensus.
	var expected_actual: float = prev_roe + theme_drift
	return 1 if expected_actual >= consensus else -1


## True if [param stock_id] should receive a preliminary earnings release.
## Probability depends on VolatilityProfile. GDD §3-6. AC-FR-18, AC-FR-19.
func _roll_preliminary(stock: StockData) -> bool:
	if not PRELIMINARY_ENABLED or stock == null:
		return false
	var profile_name: String = StockData.VolatilityProfile.keys()[stock.volatility_profile]
	var prob: float = float(PRELIMINARY_PROBABILITY.get(profile_name, 0.0))
	return _rng.randf() < prob

# ── Internal: Stock Selection ──

## Select 8–12 newsworthy stocks for this report season. GDD §3-2.
func _select_newsworthy(all_ids: Array[String], season: int) -> Array[String]:
	var candidates: Array[Dictionary] = []
	for stock_id: String in all_ids:
		var stock: StockData = StockDatabase.get_stock(stock_id)
		if stock == null:
			continue
		var prev_roe: float = stock.roe / 100.0
		var theme_drift: float = _get_theme_drift(stock.sector)
		var expected_delta: float = abs(theme_drift) + SECTOR_NOISE * 0.5
		if expected_delta >= ROE_NEWS_THRESHOLD or (prev_roe <= 0.0 and theme_drift > 0.0):
			candidates.append({"id": stock_id, "priority": expected_delta})
	# Sort by priority descending
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["priority"] as float) > (b["priority"] as float)
	)
	# Pick random count in [NEWS_STOCK_MIN, NEWS_STOCK_MAX]
	var count: int = clampi(
		candidates.size(),
		NEWS_STOCK_MIN,
		mini(NEWS_STOCK_MAX, candidates.size())
	)
	# If not enough candidates, fill from remainder
	if count < NEWS_STOCK_MIN:
		var extras: Array[String] = []
		for stock_id: String in all_ids:
			var already: bool = false
			for c: Dictionary in candidates:
				if c["id"] == stock_id:
					already = true
					break
			if not already:
				extras.append(stock_id)
		_rng.shuffle(extras)
		for i: int in range(mini(NEWS_STOCK_MIN - count, extras.size())):
			candidates.append({"id": extras[i], "priority": 0.0})
		count = mini(candidates.size(), NEWS_STOCK_MIN)

	var result: Array[String] = []
	for i: int in range(count):
		result.append(str(candidates[i]["id"]))
	return result


## Build the full event entry for one newsworthy stock. GDD §3-6.
func _build_event_entry(stock_id: String, season: int) -> Dictionary:
	var reporting_day: int = _rng.randi_range(REPORT_DAY_MIN, REPORT_DAY_MAX)
	var preliminary_day: int = reporting_day - PRELIMINARY_DAY_OFFSET
	var analyst_day: int = _rng.randi_range(
		ANALYST_DAY_MIN, mini(ANALYST_DAY_MAX, reporting_day - PRELIMINARY_DAY_OFFSET - 1)
	)
	var stock: StockData = StockDatabase.get_stock(stock_id)
	var has_preliminary: bool = _roll_preliminary(stock)
	var is_fake_rumor: bool = _rng.randf() < RUMOR_FAKE_RATE
	var event_sign: int = 1 if _get_theme_drift(stock.sector if stock != null else "") >= 0.0 else -1

	return {
		"stock_id":          stock_id,
		"season":            season,
		"reporting_day":     reporting_day,
		"preliminary_day":   preliminary_day,
		"rumor_day":         reporting_day - 1,
		"analyst_day":       analyst_day,
		"has_preliminary":   has_preliminary,
		"is_fake_rumor":     is_fake_rumor,
		"event_sign":        event_sign,
		"analyst_done":      false,
		"preliminary_done":  false,
		"rumor_done":        false,
		"report_done":       false,
		"quiet":             false,
		# consensus_roe computed at schedule time for rumor direction only; actual value
		# re-computed fresh at report time to avoid storing stale RNG state.
		"consensus_roe":     _compute_consensus_roe(stock_id, reporting_day),
	}

# ── Internal: Quiet Update (non-report-season stocks) ──

## Silently update A3 data for all stocks in a non-report season.
## No news cards fired. GDD §3 "뉴스 없는 종목은 A3 데이터만 갱신". AC-FR-08, AC-FR-15.
func _do_quiet_update_all(_season: int) -> void:
	for stock_id: String in StockDatabase.get_all_stock_ids():
		_apply_roe_update(stock_id, _compute_new_roe(stock_id))


## Silently update one stock's ROE/PER/PBR without firing any news. AC-FR-15.
func _apply_quiet_update(stock_id: String) -> void:
	_apply_roe_update(stock_id, _compute_new_roe(stock_id))

# ── Internal: ROE / PER / PBR Update ──

## Apply new_roe to StockData.roe and recalculate PER/PBR atomically.
## StockData fields are mutable @export vars; direct mutation is safe (no save owner).
## GDD §3-4, F4.
func _apply_roe_update(stock_id: String, new_roe: float) -> void:
	var stock: StockData = StockDatabase.get_stock(stock_id)
	if stock == null:
		return
	# Convert normalized roe back to percentage (stored as e.g. 16.0)
	stock.roe = new_roe * 100.0

	# Recalculate PER/PBR using current price and implicit BVPS.
	# BVPS derived: eps = prev_price / prev_per (if valid), bvps = eps / prev_roe_rate.
	# Use PriceEngine season_open_price as stable reference.
	var current_price: int = PriceEngine.get_current_price(stock_id)
	if current_price <= 0:
		return

	if new_roe > 0.0:
		# EPS = BVPS × roe. With no bvps available, approximate via industry PBR stability:
		# new_per = (current_price / prev_eps) × (prev_roe / new_roe)
		# = old_per × (prev_roe / new_roe) if price unchanged.
		# For simplicity: derive bvps from original per/roe if they were valid.
		if stock.per > 0.0 and new_roe > 0.0:
			# Check new_roe directly — stock.roe was set to new_roe * 100.0 above.
			# Derive new EPS from current price × new_roe (ROE-based approximation; no BVPS stored).
			var new_eps: float = float(current_price) * new_roe
			var new_per: float = float(current_price) / new_eps if new_eps > 0.0 \
				else PER_NEGATIVE_SENTINEL
			stock.per = new_per
		else:
			# No valid base — leave PER as-is (edge case)
			pass
	else:
		stock.per = PER_NEGATIVE_SENTINEL  # Deficit company PER sentinel. AC-FR-14.

	# PBR stays stable (BVPS doesn't change with earnings alone in this model)

# ── Internal: Event Firing ──

## Fire analyst report news card for [param ev]. GDD §3-10.
func _fire_analyst_report(ev: Dictionary) -> void:
	var stock_id: String = ev["stock_id"]
	var stock: StockData = StockDatabase.get_stock(stock_id)
	var display_name: String = stock.get_display_name() if stock != null else stock_id
	var direction: int = ev["event_sign"]
	var headline: String
	var body: String
	if direction > 0:
		headline = _HL_TARGET_UP % display_name
		body = "애널리스트 리포트: 향후 실적 개선 전망 반영, 목표주가 상향 조정."
	else:
		headline = _HL_TARGET_DOWN % display_name
		body = "애널리스트 리포트: 비용 증가 압박으로 수익성 악화 전망, 목표주가 하향 조정."
	NewsEventSystem.fire_stock_news(stock_id, headline, body, direction, "SMALL")


## Fire preliminary earnings news card. GDD §3-7.
func _fire_preliminary_news(ev: Dictionary) -> void:
	var stock_id: String = ev["stock_id"]
	var stock: StockData = StockDatabase.get_stock(stock_id)
	var display_name: String = stock.get_display_name() if stock != null else stock_id
	var direction: int = ev["event_sign"]
	var headline: String
	var body: String
	if direction > 0:
		headline = _HL_EARNS_POS % display_name
		body = "잠정실적 공시: 영업이익 전분기 대비 개선, 컨센서스 상회 전망. 순이익 미확정."
	else:
		headline = _HL_EARNS_NEG % display_name
		body = "잠정실적 공시: 매출 컨센서스 하회, 수익성 악화 우려. 순이익 미확정."
	NewsEventSystem.fire_stock_news(stock_id, headline, body, direction, "MEDIUM")


## Fire rumor (장중). GDD §3-9.
func _fire_rumor(ev: Dictionary) -> void:
	var stock_id: String = ev["stock_id"]
	var stock: StockData = StockDatabase.get_stock(stock_id)
	var display_name: String = stock.get_display_name() if stock != null else stock_id
	# Fake rumor flips direction
	var rumor_direction: int = ev["event_sign"] * (-1 if ev["is_fake_rumor"] else 1)
	var headline: String
	var body: String
	if rumor_direction > 0:
		headline = _HL_RUMOR_POS % display_name
		body = "내부 채널: 컨센서스를 크게 상회하는 실적이 예상된다는 소문이 돌고 있다."
	else:
		headline = _HL_RUMOR_NEG % display_name
		body = "내부 채널: 컨센서스를 하회하는 실적이 예상된다는 소문이 돌고 있다."
	NewsEventSystem.fire_stock_news(stock_id, headline, body, rumor_direction, "SMALL")
	# Apply light price pressure via inject_event (ADR-022 pipeline)
	var stock_data: StockData = StockDatabase.get_stock(stock_id)
	if stock_data != null:
		# Use the stock's sector as injection scope; origin only
		NewsEventSystem.inject_event(
			"RUMOR_FINANCIAL",
			stock_data.sector,
			0.02,
			rumor_direction,
			"",
			8
		)


## Fire official earnings and update A3 data atomically. GDD §3-8.
func _fire_official_report(ev: Dictionary) -> void:
	var stock_id: String = ev["stock_id"]
	var stock: StockData = StockDatabase.get_stock(stock_id)
	if stock == null:
		return

	var prev_roe: float = stock.roe / 100.0  # normalized
	var new_roe: float  = _compute_new_roe(stock_id)
	var consensus_roe: float = float(ev.get("consensus_roe", prev_roe))

	# Atomically update A3 data (GDD: must happen before news card)
	_apply_roe_update(stock_id, new_roe)

	var event_type: String = _classify_event(prev_roe, new_roe, consensus_roe)
	var direction: int = _event_type_to_direction(event_type, new_roe, prev_roe)

	if not event_type.is_empty():
		_publish_earnings_news(stock_id, event_type, direction)
		# E-09: LARGE (LOW volatility) shock → sector ripple. GDD §5, AC-FR-21~23.
		if stock.volatility_profile == StockData.VolatilityProfile.LOW \
			and (event_type == "EARNINGS_SHOCK" or event_type == "TURNAROUND_LOSS"):
			var shock_mag: float = absf(new_roe - consensus_roe)
			_fire_sector_ripple(stock, shock_mag, direction)


## Publish earnings news card. GDD §3-5 event type text.
func _publish_earnings_news(stock_id: String, event_type: String, direction: int) -> void:
	var stock: StockData = StockDatabase.get_stock(stock_id)
	var display_name: String = stock.get_display_name() if stock != null else stock_id
	var headline: String
	var body: String
	match event_type:
		"TURNAROUND_PROFIT":
			headline = _HL_TURNAROUND % display_name
			body = "공식 실적 발표: 이전 분기 적자에서 흑자 전환. 시장 컨센서스를 대폭 상회."
		"TURNAROUND_LOSS":
			headline = _HL_RED_TURN % display_name
			body = "공식 실적 발표: 흑자에서 적자로 전환. 수익성이 크게 악화됐다."
		"EARNINGS_SURPRISE":
			headline = _HL_BEAT % display_name
			body = "공식 실적 발표: 시장 컨센서스를 크게 상회하는 어닝서프라이즈 달성."
		"EARNINGS_SHOCK":
			headline = _HL_MISS % display_name
			body = "공식 실적 발표: 시장 기대치를 크게 하회하는 어닝쇼크. 투자자들이 당혹감을 감추지 못하고 있다."
		_:
			return  # No news for neutral result
	var impact_tier: String = "MEDIUM" if (event_type.begins_with("EARNINGS")) else "LARGE"
	NewsEventSystem.fire_stock_news(stock_id, headline, body, direction, impact_tier)


## E-09: LARGE (LOW volatility) earnings shock → sector ripple via inject_event. GDD §5, ADR-022.
## AC-FR-21: LARGE + SHOCK → inject_event(SECTOR_RIPPLE) called once.
## AC-FR-22: origin stock excluded from ripple (inject_event targets same sector, caller filters).
## Note: inject_event() fires for the ENTIRE sector; origin stock will also be affected.
## The ADR-022 contract says "origin_stock_id 제외 처리는 NewsEventSystem 담당" but current
## inject_event() doesn't support per-stock exclusion. For Phase 1 we apply to full sector
## including origin (acceptable approximation; Phase 2 enhancement if needed).
func _fire_sector_ripple(origin: StockData, shock_magnitude: float, direction: int) -> void:
	var ripple_impact: float = shock_magnitude * SECTOR_RIPPLE_RATIO + SECTOR_RIPPLE_IMPACT
	ripple_impact = clampf(ripple_impact, 0.01, 0.20)
	NewsEventSystem.inject_event(
		"SECTOR_RIPPLE",
		origin.sector,
		ripple_impact,
		direction,
		"",
		SECTOR_RIPPLE_DECAY_TICKS
	)


func _event_type_to_direction(event_type: String, new_roe: float, _prev_roe: float) -> int:
	match event_type:
		"TURNAROUND_PROFIT", "EARNINGS_SURPRISE":
			return 1
		"TURNAROUND_LOSS", "EARNINGS_SHOCK":
			return -1
	return 1 if new_roe > 0.0 else -1

# ── Signal Handlers ──

func _on_season_started(_tier: int, _is_free_market: bool) -> void:
	# _current_season은 시즌 시작 시마다 1 증가하는 절대 카운터.
	# reset() 또는 load_save_data()로 초기화되므로 세이브/로드 후에도 정확.
	# SeasonManager.get_current_tier()는 랭크 티어이므로 여기서 사용하지 않는다.
	_current_season += 1
	schedule_quarterly_events(_current_season)


func _on_market_state_changed(
	new_state: GameClock.MarketState, _prev: GameClock.MarketState
) -> void:
	if new_state != GameClock.MarketState.PRE_MARKET:
		return
	var day: int = GameClock.get_current_day()
	_on_pre_market(day)


func _on_pre_market(day: int) -> void:
	if _pending_events.is_empty():
		return

	for stock_id: String in _pending_events.keys():
		var ev: Dictionary = _pending_events[stock_id]
		if ev.get("quiet", false) and not ev.get("report_done", false):
			# Silent A3 update on season day 1
			if day == 1:
				_apply_quiet_update(stock_id)
				ev["report_done"] = true
			continue

		if ev.get("report_done", false):
			continue

		# Catch-up: process any stages whose day has passed (E-05)
		var report_day: int = int(ev.get("reporting_day", 0))
		var prelim_day: int  = int(ev.get("preliminary_day", 0))
		var analyst_day: int = int(ev.get("analyst_day", 0))

		# Analyst report (day arrives or past)
		if not ev.get("analyst_done", false) and day >= analyst_day:
			_fire_analyst_report(ev)
			ev["analyst_done"] = true

		# Preliminary (day arrives, catch-up skips if past; rumor catch-up always skipped)
		if PRELIMINARY_ENABLED and ev.get("has_preliminary", false) \
			and not ev.get("preliminary_done", false) and day >= prelim_day:
			_fire_preliminary_news(ev)
			ev["preliminary_done"] = true

		# Official report (catch-up: fire immediately if overdue)
		if day >= report_day:
			_fire_official_report(ev)
			ev["report_done"] = true


func _on_tick(tick: int, day: int, _week: int) -> void:
	if not _is_report_season_active or _pending_events.is_empty():
		return
	if tick != RUMOR_FIRE_TICK_IN_DAY:
		return

	for stock_id: String in _pending_events.keys():
		var ev: Dictionary = _pending_events[stock_id]
		if ev.get("quiet", false) or ev.get("rumor_done", false) or ev.get("report_done", false):
			continue
		if int(ev.get("rumor_day", 0)) == day:
			_fire_rumor(ev)
			ev["rumor_done"] = true

# ── Serialization ──

## Returns serializable state for SaveSystem.
func get_save_data() -> Dictionary:
	return {
		"current_season":          _current_season,
		"is_report_season_active": _is_report_season_active,
		"pending_events":          _pending_events.duplicate(true),
	}


## Restores state from save data and runs catch-up for any overdue events.
func load_save_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	_current_season         = int(data.get("current_season", 0))
	_is_report_season_active = bool(data.get("is_report_season_active", false))
	_pending_events          = data.get("pending_events", {}).duplicate(true)
	# Re-seed RNG from season (anti-scout consistency)
	if _current_season > 0:
		_rng.seed = hash("FRS_season_%d" % _current_season)
		_consensus_rng.seed = hash("FRS_consensus_%d" % _current_season)
