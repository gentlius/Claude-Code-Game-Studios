## Autoload — Manages 11 sector ETFs: price calculation, sector flow, and rotation events.
## ETF prices are injected into PriceEngine each tick after stock prices are updated.
## Sector rotation events are dispatched through NewsEventSystem (ADR-022).
## All configuration is loaded from assets/data/etf_config.json (to be replaced by
## MarketProfile.get_active() in S10-07, ADR-021).
## See: design/gdd/sector-etf.md
extends Node

# ── Constants ──

## Absolute path to the ETF configuration data file.
## In S10-07 this data will be absorbed into market_kr.json / MarketProfile.
const ETF_CONFIG_PATH: String = "res://assets/data/etf_config.json"

## Rolling window length (ticks) for F3 momentum calculation (GDD §4 F3).
const FLOW_LOOKBACK_DEFAULT: int = 5

# ── State ──

## ETF ID → sector name ("ETF_반도체" → "반도체")
var _etf_sectors: Dictionary = {}
## Sector name → ETF ID ("반도체" → "ETF_반도체")
var _sector_etfs: Dictionary = {}
## ETF ID → current price (float)
var _etf_prices: Dictionary = {}
## ETF ID → day-open price snapshot (float)
var _etf_open_prices: Dictionary = {}

## Sector → current flow value ∈ [−1.0, +1.0] (F3, A4 display)
var _sector_flows: Dictionary = {}
## Sector → flow value from previous tick (F4 delta calculation)
var _sector_flows_prev: Dictionary = {}
## Sector → remaining cooldown ticks (F4 rotation spam guard)
var _rotation_cooldowns: Dictionary = {}
## Sector → rolling Array[float] of recent sector_return values (F3 lookback)
var _sector_return_history: Dictionary = {}

## Base price loaded from config (KR default: 50,000원)
var _etf_base_price: int = 50000

## Sector → archetype string (e.g. "반도체" → "TECH")
var _sector_archetypes: Dictionary = {}
## Archetype → Array[String] of sector names in that archetype
var _archetype_to_sectors: Dictionary = {}
## Archetype → Dictionary{rival_archetype → weight} (weights sum to 1.0)
var _rivalry_weights: Dictionary = {}

# ── Rotation params (loaded from config) ──
var _flow_sensitivity: float = 0.5
var _flow_decay: float = 0.1
var _rotation_threshold: float = 0.03
var _rotation_cooldown_ticks: int = 5
var _inflow_impact_min: float = 0.04
var _inflow_impact_max: float = 0.07
var _outflow_impact_min: float = 0.02
var _outflow_impact_max: float = 0.03
var _rotation_decay_ticks: int = 8
var _flow_lookback_ticks: int = FLOW_LOOKBACK_DEFAULT

## Rotation headline keys loaded from config
var _headline_inflow_key: String = "ROTATION_KR_INFLOW"
var _headline_outflow_key: String = "ROTATION_KR_OUTFLOW"

## RNG for rotation impact sampling and rival-sector selection.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Whether config was loaded successfully.
var _initialized: bool = false

# ── Lifecycle ──

func _ready() -> void:
	_rng.randomize()
	SeasonManager.on_season_started.connect(_on_season_started)
	GameClock.on_market_open.connect(_on_market_open)


## Called by GameClock._process_tick() immediately after PriceEngine.process_tick().
## Recalculates all ETF prices from updated stock prices, updates sector flows,
## and fires rotation events when thresholds are crossed.
func process_tick(_tick: int, _day: int, _week: int) -> void:
	if not _initialized:
		return
	_recalculate_all_etf_prices()
	_update_all_sector_flows()
	_check_all_rotation_triggers()


# ── Season / Day Callbacks ──

func _on_season_started(_tier: int, _is_free_market: bool) -> void:
	_load_config()
	_init_season()


## Snapshot open prices when the market opens each day.
func _on_market_open() -> void:
	if not _initialized:
		return
	for etf_id: String in _etf_prices:
		_etf_open_prices[etf_id] = _etf_prices[etf_id]


# ── Config & Initialisation ──

func _load_config() -> void:
	var file := FileAccess.open(ETF_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("EtfManager: cannot open " + ETF_CONFIG_PATH)
		return
	var json := JSON.new()
	var err: Error = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("EtfManager: JSON parse error in " + ETF_CONFIG_PATH)
		return

	var cfg: Dictionary = json.get_data()

	_etf_base_price = cfg.get("basePriceWon", 50000)

	# Build ETF ↔ sector lookup tables
	_etf_sectors.clear()
	_sector_etfs.clear()
	for entry: Dictionary in cfg.get("etfs", []):
		var etf_id: String = entry["id"]
		var sector: String = entry["sector"]
		_etf_sectors[etf_id] = sector
		_sector_etfs[sector] = etf_id

	# Build archetype maps
	_sector_archetypes = cfg.get("sectorArchetypes", {})
	_archetype_to_sectors.clear()
	for sector: String in _sector_archetypes:
		var archetype: String = _sector_archetypes[sector]
		if not _archetype_to_sectors.has(archetype):
			_archetype_to_sectors[archetype] = []
		(_archetype_to_sectors[archetype] as Array).append(sector)

	_rivalry_weights = cfg.get("rivalryWeights", {})

	# Validate rivalry_weights sums (GDD §3-1 integrity check)
	for arch: String in _rivalry_weights:
		var row: Dictionary = _rivalry_weights[arch]
		var total: float = 0.0
		for w: float in row.values():
			total += w
		if absf(total - 1.0) > 0.01:
			push_warning("EtfManager: rivalryWeights[%s] sums to %.3f (expected 1.0)" % [arch, total])

	var rp: Dictionary = cfg.get("rotationParams", {})
	_flow_sensitivity      = rp.get("flowSensitivity", 0.5)
	_flow_decay            = rp.get("flowDecay", 0.1)
	_rotation_threshold    = rp.get("rotationThreshold", 0.03)
	_rotation_cooldown_ticks = rp.get("rotationCooldownTicks", 5)
	_inflow_impact_min     = rp.get("inflowImpactMin", 0.04)
	_inflow_impact_max     = rp.get("inflowImpactMax", 0.07)
	_outflow_impact_min    = rp.get("outflowImpactMin", 0.02)
	_outflow_impact_max    = rp.get("outflowImpactMax", 0.03)
	_rotation_decay_ticks  = rp.get("rotationDecayTicks", 8)
	_flow_lookback_ticks   = rp.get("flowLookbackTicks", FLOW_LOOKBACK_DEFAULT)

	var hk: Dictionary = cfg.get("rotationHeadlineKeys", {})
	_headline_inflow_key  = hk.get("inflow", "ROTATION_KR_INFLOW")
	_headline_outflow_key = hk.get("outflow", "ROTATION_KR_OUTFLOW")


func _init_season() -> void:
	_etf_prices.clear()
	_etf_open_prices.clear()
	_sector_flows.clear()
	_sector_flows_prev.clear()
	_rotation_cooldowns.clear()
	_sector_return_history.clear()

	for etf_id: String in _etf_sectors:
		_etf_prices[etf_id]      = float(_etf_base_price)
		_etf_open_prices[etf_id] = float(_etf_base_price)

	for sector: String in _sector_etfs:
		_sector_flows[sector]       = 0.0
		_sector_flows_prev[sector]  = 0.0
		_rotation_cooldowns[sector] = 0
		_sector_return_history[sector] = [] as Array[float]

	# Inject initial ETF prices into PriceEngine cache
	for etf_id: String in _etf_prices:
		PriceEngine.inject_price(etf_id, _etf_prices[etf_id])

	_initialized = true


# ── Price Calculation (F1) ──

## Recalculate and inject all ETF prices from current stock prices.
func _recalculate_all_etf_prices() -> void:
	for etf_id: String in _etf_sectors:
		var sector: String = _etf_sectors[etf_id]
		var price: float = _calc_etf_price(sector)
		_etf_prices[etf_id] = price
		PriceEngine.inject_price(etf_id, price)


## F1: sector market-cap weighted return → ETF price.
## sector_return(t) = curr_mcap / base_mcap − 1.0
## etf_price(t) = ETF_BASE_PRICE × (1.0 + sector_return(t)), clamped ≥ 1.0
func _calc_etf_price(sector: String) -> float:
	var stocks: Array[StockData] = StockDatabase.get_stocks_by_sector(sector)
	if stocks.is_empty():
		return float(_etf_base_price)

	var base_mcap: float = 0.0
	var curr_mcap: float = 0.0
	for stock: StockData in stocks:
		var base_f: float = float(stock.base_price) * float(stock.listed_shares)
		var curr_f: float = float(PriceEngine.get_current_price(stock.stock_id)) * float(stock.listed_shares)
		base_mcap += base_f
		curr_mcap += curr_f

	if base_mcap <= 0.0:
		return float(_etf_base_price)

	var sector_return: float = curr_mcap / base_mcap - 1.0
	return maxf(1.0, float(_etf_base_price) * (1.0 + sector_return))


## Returns the sector return for a given sector (used internally and by A4 view).
func _get_sector_return(sector: String) -> float:
	var etf_id: String = _sector_etfs.get(sector, "")
	if etf_id.is_empty():
		return 0.0
	var price: float = _etf_prices.get(etf_id, float(_etf_base_price))
	return price / float(_etf_base_price) - 1.0


# ── Sector Flow (F3) ──

## F3: Update sector_flow for all sectors after recalculating ETF prices this tick.
func _update_all_sector_flows() -> void:
	for sector: String in _sector_etfs:
		_update_sector_flow(sector)


## F3:
## momentum = sector_return(t) − sector_return_avg(t-N .. t-1)
## sector_flow += momentum × FLOW_SENSITIVITY
## sector_flow *= (1 − FLOW_DECAY)
## sector_flow = clamp(sector_flow, −1.0, 1.0)
func _update_sector_flow(sector: String) -> void:
	var current_return: float = _get_sector_return(sector)

	# Maintain rolling history
	var history: Array = _sector_return_history[sector]
	history.append(current_return)
	if history.size() > _flow_lookback_ticks:
		history = history.slice(history.size() - _flow_lookback_ticks)
		_sector_return_history[sector] = history

	# Compute momentum (need at least 2 samples for a meaningful average)
	var prev_avg: float = 0.0
	if history.size() >= 2:
		var sum: float = 0.0
		for r: float in history.slice(0, history.size() - 1):
			sum += r
		prev_avg = sum / float(history.size() - 1)

	var momentum: float = current_return - prev_avg

	var prev_flow: float = _sector_flows.get(sector, 0.0)
	_sector_flows_prev[sector] = prev_flow

	var new_flow: float = prev_flow + momentum * _flow_sensitivity
	new_flow *= (1.0 - _flow_decay)
	_sector_flows[sector] = clampf(new_flow, -1.0, 1.0)

	# Decrement cooldown
	if _rotation_cooldowns[sector] > 0:
		_rotation_cooldowns[sector] -= 1


# ── Rotation Trigger (F4) ──

## F4: Check all sectors for rotation events after sector flows are updated.
func _check_all_rotation_triggers() -> void:
	for sector: String in _sector_etfs:
		_check_rotation_trigger(sector)


## F4: Fire a rotation event if flow delta exceeds threshold and cooldown has elapsed.
func _check_rotation_trigger(sector: String) -> void:
	if _rotation_cooldowns[sector] > 0:
		return
	var prev_flow: float = _sector_flows_prev.get(sector, 0.0)
	var curr_flow: float = _sector_flows.get(sector, 0.0)
	var delta: float = curr_flow - prev_flow

	if absf(delta) <= _rotation_threshold:
		return

	_rotation_cooldowns[sector] = _rotation_cooldown_ticks

	if delta > 0.0:
		_fire_rotation_event(sector, "inflow")
	else:
		_fire_rotation_event(sector, "outflow")
		var rival: String = _pick_rival_sector(sector)
		if not rival.is_empty():
			_fire_rotation_event(rival, "outflow")


## Dispatch a SECTOR event through NewsEventSystem (ADR-022 — no direct PriceEngine calls).
func _fire_rotation_event(sector: String, direction: String) -> void:
	var impact: float
	var dir_int: int
	var headline_key: String
	if direction == "inflow":
		impact = _rng.randf_range(_inflow_impact_min, _inflow_impact_max)
		dir_int = 1
		headline_key = _headline_inflow_key
	else:
		impact = _rng.randf_range(_outflow_impact_min, _outflow_impact_max)
		dir_int = -1
		headline_key = _headline_outflow_key
	NewsEventSystem.inject_event(
		"SECTOR_ROTATION", sector, impact, dir_int,
		headline_key + "_" + sector, _rotation_decay_ticks
	)


## F4 (§4): Pick a rival sector from a different archetype using weighted random.
## Returns empty string if no valid rival can be found.
func _pick_rival_sector(hot_sector: String) -> String:
	var archetype: String = _sector_archetypes.get(hot_sector, "")
	if archetype.is_empty() or not _rivalry_weights.has(archetype):
		return ""

	# Weighted random pick of a rival archetype (must be different from hot_sector's)
	var weights_dict: Dictionary = _rivalry_weights[archetype]
	var archetypes: Array = weights_dict.keys()
	var weights: Array[float] = []
	for a: String in archetypes:
		weights.append(weights_dict[a] as float)

	var rival_archetype: String = _weighted_random_pick(archetypes, weights)
	if rival_archetype.is_empty():
		return ""

	# Pick a random sector within the rival archetype, excluding hot_sector itself
	var candidates: Array = (_archetype_to_sectors.get(rival_archetype, []) as Array).duplicate()
	candidates.erase(hot_sector)
	if candidates.is_empty():
		return ""

	return candidates[_rng.randi() % candidates.size()] as String


## Weighted random selection from a parallel items/weights array.
func _weighted_random_pick(items: Array, weights: Array[float]) -> String:
	if items.is_empty():
		return ""
	var total: float = 0.0
	for w: float in weights:
		total += w
	var r: float = _rng.randf() * total
	var cumulative: float = 0.0
	for i: int in items.size():
		cumulative += weights[i]
		if r <= cumulative:
			return items[i] as String
	return items[-1] as String


# ── Public API (sector-etf.md §3-7) ──

## Returns stock IDs for all stocks in the given sector.
## Used by SectorComparisonView and tests.
##
## Example:
##   EtfManager.get_sector_stocks("반도체")  # → ["SKL", "STC", ...]
func get_sector_stocks(sector: String) -> Array[String]:
	var stocks: Array[StockData] = StockDatabase.get_stocks_by_sector(sector)
	var ids: Array[String] = []
	for s: StockData in stocks:
		ids.append(s.stock_id)
	return ids


## Returns the season-to-date return fraction for an ETF (0.05 = +5%).
##
## Example:
##   EtfManager.get_etf_return("ETF_반도체")  # → 0.0245
func get_etf_return(etf_id: String) -> float:
	var price: float = _etf_prices.get(etf_id, float(_etf_base_price))
	return price / float(_etf_base_price) - 1.0


## Returns the current ETF price (float won).
##
## Example:
##   EtfManager.get_etf_price("ETF_반도체")  # → 51224.0
func get_etf_price(etf_id: String) -> float:
	return _etf_prices.get(etf_id, float(_etf_base_price))


## Returns the day-open ETF price snapshot.
##
## Example:
##   EtfManager.get_etf_open_price("ETF_반도체")  # → 50000.0
func get_etf_open_price(etf_id: String) -> float:
	return _etf_open_prices.get(etf_id, float(_etf_base_price))


## Returns the current sector flow index ∈ [−1.0, +1.0] for A4 display.
##
## Example:
##   EtfManager.get_sector_flow("반도체")  # → 0.12
func get_sector_flow(sector: String) -> float:
	return _sector_flows.get(sector, 0.0)


## Returns true if the given stock_id is a managed ETF.
## Used by OrderEngine to route ETF orders to the immediate-fill path.
##
## Example:
##   EtfManager.is_etf("ETF_반도체")  # → true
##   EtfManager.is_etf("SKL")         # → false
func is_etf(stock_id: String) -> bool:
	return _etf_sectors.has(stock_id)


## Returns all known ETF IDs (for save/load enumeration).
func get_all_etf_ids() -> Array[String]:
	var ids: Array[String] = []
	for k: String in _etf_sectors:
		ids.append(k)
	return ids


## Returns serializable state for save system (save-load.md §3-5).
## ETF price/flow state is saved; config is re-loaded from etf_config.json on restore.
func get_save_data() -> Dictionary:
	if not _initialized:
		return {}
	return {
		"etf_prices":          _etf_prices.duplicate(),
		"etf_open_prices":     _etf_open_prices.duplicate(),
		"sector_flows":        _sector_flows.duplicate(),
		"rotation_cooldowns":  _rotation_cooldowns.duplicate(),
	}


## Restores EtfManager state after a save load.
## Called by SaveSystem._restore_season_systems().
## Rebuilds config maps from etf_config.json, then injects saved prices into PriceEngine.
func load_save_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	_load_config()

	_etf_prices = data.get("etf_prices", {})
	_etf_open_prices = data.get("etf_open_prices", {})
	_sector_flows = data.get("sector_flows", {})
	_rotation_cooldowns = data.get("rotation_cooldowns", {})

	# Restore state arrays not saved (will rebuild on first tick)
	_sector_flows_prev.clear()
	_sector_return_history.clear()
	for sector: String in _sector_etfs:
		_sector_flows_prev[sector] = _sector_flows.get(sector, 0.0)
		_sector_return_history[sector] = [] as Array[float]

	# Re-inject ETF prices into PriceEngine (initialize_for_load clears _stock_states)
	for etf_id: String in _etf_prices:
		PriceEngine.inject_price(etf_id, _etf_prices[etf_id])

	_initialized = true


## Resets all state. Called by GameMain (new game) and tests (before_each).
func reset() -> void:
	_etf_sectors.clear()
	_sector_etfs.clear()
	_etf_prices.clear()
	_etf_open_prices.clear()
	_sector_flows.clear()
	_sector_flows_prev.clear()
	_rotation_cooldowns.clear()
	_sector_return_history.clear()
	_initialized = false
