## Autoload — Manages 11 sector ETFs: price display, sector flow readout, and save/load.
## Phase C (ADR-027): ETF price computation delegated to C++ PriceKernel.
## GDScript side holds display-ready state synced from kernel each tick via sync_from_kernel().
## All configuration is loaded from assets/data/etf_config.json (to be replaced by
## MarketProfile.get_active() in S10-07, ADR-021).
## See: design/gdd/sector-etf.md
extends Node

# ── Constants ──

## Absolute path to the ETF configuration data file.
## In S10-07 this data will be absorbed into market_kr.json / MarketProfile.
const ETF_CONFIG_PATH: String = "res://assets/data/etf_config.json"

# ── State ──

## ETF ID → sector name ("ETF_반도체" → "반도체")
var _etf_sectors: Dictionary = {}
## Sector name → ETF ID ("반도체" → "ETF_반도체")
var _sector_etfs: Dictionary = {}
## ETF ID → current price (float) — synced from C++ kernel each tick
var _etf_prices: Dictionary = {}
## ETF ID → day-open price snapshot (float)
var _etf_open_prices: Dictionary = {}

## Sector → current flow value ∈ [−1.0, +1.0] (F3, A4 display) — synced from kernel
var _sector_flows: Dictionary = {}
## Sector → remaining cooldown ticks (F4 rotation spam guard) — synced from kernel
var _rotation_cooldowns: Dictionary = {}

## Base price loaded from config (KR default: 50,000원)
var _etf_base_price: int = 50000

## Whether config was loaded successfully.
var _initialized: bool = false

# ── Lifecycle ──

func _ready() -> void:
	SeasonManager.on_season_started.connect(_on_season_started)
	GameClock.on_market_open.connect(_on_market_open)


## Called by GameClock._process_tick() immediately after PriceEngine.process_tick().
## Phase C: ETF computation delegated to C++ PriceKernel (ADR-027). PriceEngine.process_tick()
## calls EtfManager.sync_from_kernel() after kernel returns; no GDScript recalculation needed.
func process_tick(_tick: int, _day: int, _week: int) -> void:
	pass


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

	# Phase C: archetype/rivalry/rotation params now read by C++ kernel via etf_config.
	# Rotation headline keys are owned by MarketProfile (ADR-021).


func _init_season() -> void:
	_etf_prices.clear()
	_etf_open_prices.clear()
	_sector_flows.clear()
	_rotation_cooldowns.clear()

	for etf_id: String in _etf_sectors:
		_etf_prices[etf_id]      = float(_etf_base_price)
		_etf_open_prices[etf_id] = float(_etf_base_price)

	for sector: String in _sector_etfs:
		_sector_flows[sector]       = 0.0
		_rotation_cooldowns[sector] = 0

	# Phase C: Register ETFs in PriceEngine so get_current_price() is valid before tick 1.
	# C++ kernel seeds its own return history; per-tick prices come from process_all_ticks().
	for etf_id: String in _etf_sectors:
		PriceEngine.inject_price(etf_id, float(_etf_base_price))

	_initialized = true


## Phase C: Called by PriceEngine.process_tick() with C++ kernel ETF results (ADR-027).
## Updates GDScript ETF state from kernel output; price display reads from _etf_prices.
func sync_from_kernel(
		etf_prices: Dictionary,
		sector_flows: Dictionary,
		rotation_cooldowns: Dictionary
) -> void:
	for etf_id: String in etf_prices:
		_etf_prices[etf_id] = float(etf_prices[etf_id])
	for sector: String in sector_flows:
		_sector_flows[sector] = float(sector_flows[sector])
	for sector: String in rotation_cooldowns:
		_rotation_cooldowns[sector] = int(rotation_cooldowns[sector])


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
	_rotation_cooldowns.clear()
	_initialized = false
