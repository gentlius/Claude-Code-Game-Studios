## Autoload — Manages stock definitions for the current season.
## 46 stocks across 11 sectors, loaded from assets/data/stocks_kr.json (KR default).
## DLC markets supply their own stocks_[market_id].json files.
## Foundation layer: no dependencies on other game systems.
## See: TD-DR-07 — StockDatabase DLC 동적 로드
extends Node

## Emitted after season stocks are loaded and ready.
signal stocks_loaded

## Base path pattern — %s is replaced by the lowercase market_id.
## KR loads stocks_kr.json, US loads stocks_us.json, etc.
const STOCK_DATA_PATH_TEMPLATE: String = "res://assets/data/stocks_%s.json"

## Backwards-compat alias kept so any external code holding the old const path
## does not break at parse time. Points to the KR default.
const STOCK_DATA_PATH: String = "res://assets/data/stocks_kr.json"

## Lowercase market identifier that controls which stocks_*.json file is loaded.
## Default "kr" matches the Korean base game.
var _active_market_id: String = "kr"

## Volatility string -> enum mapping for JSON parsing.
const VOL_MAP: Dictionary = {
	"LOW": StockData.VolatilityProfile.LOW,
	"MEDIUM": StockData.VolatilityProfile.MEDIUM,
	"HIGH": StockData.VolatilityProfile.HIGH,
	"EXTREME": StockData.VolatilityProfile.EXTREME,
}

var _stocks: Dictionary = {}  ## stock_id -> StockData
## 사전 계산 인덱스 — 매 틱 O(n) 스캔 방지 (S3-09).
var _sector_index: Dictionary = {}  ## sector -> Array[StockData]
var _tag_index: Dictionary = {}     ## event_tag -> Array[StockData]


func _ready() -> void:
	_load_stocks_from_json()


## Sets the active market and reloads stocks from the corresponding JSON file.
## [param market_id] must be lowercase (e.g. "kr", "us", "jp") to match
## the stocks_*.json filename convention.
## Example: StockDatabase.set_active_market("us")
func set_active_market(market_id: String) -> void:
	_active_market_id = market_id.to_lower()
	_load_stocks_from_json()


## Returns a StockData by ID, or null if not found.
func get_stock(stock_id: String) -> StockData:
	if not _stocks.has(stock_id):
		push_warning("StockDatabase: stock_id '%s' not found" % stock_id)
		return null
	return _stocks.get(stock_id)


## Returns true if a stock with the given ID exists in the database.
func stock_exists(stock_id: String) -> bool:
	return _stocks.has(stock_id)


## Returns all stock IDs as an array.
func get_all_stock_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: String in _stocks:
		ids.append(key)
	return ids


## Returns all StockData resources.
func get_all_stocks() -> Array[StockData]:
	var result: Array[StockData] = []
	for stock: StockData in _stocks.values():
		result.append(stock)
	return result


## Returns the number of stocks.
func get_stock_count() -> int:
	return _stocks.size()


## Returns unique sector names with stock counts.
func get_all_sectors() -> Array[Dictionary]:
	var sector_map: Dictionary = {}
	for stock: StockData in _stocks.values():
		if not sector_map.has(stock.sector):
			sector_map[stock.sector] = 0
		sector_map[stock.sector] += 1

	var result: Array[Dictionary] = []
	for sector_name: String in sector_map:
		result.append({
			"name": sector_name,
			"stock_count": sector_map[sector_name],
		})
	return result


## Returns all stocks in a given sector. O(1) via precomputed index.
## Returns a shallow duplicate so callers cannot mutate the internal index array.
func get_stocks_by_sector(sector: String) -> Array[StockData]:
	if not _sector_index.has(sector):
		return []
	return (_sector_index[sector] as Array[StockData]).duplicate()


## Returns stock IDs in a given sector. O(k) where k = sector size.
func get_stock_ids_by_sector(sector: String) -> Array[String]:
	var ids: Array[String] = []
	if _sector_index.has(sector):
		for stock: StockData in _sector_index[sector]:
			ids.append(stock.stock_id)
	return ids


## Returns stocks whose event_tags intersect with the given tag. O(1) via precomputed index.
func get_stocks_by_event_tag(tag: String) -> Array[StockData]:
	if not _tag_index.has(tag):
		return []
	return _tag_index[tag]


## Load stocks from JSON data file. See design/gdd/stock-database.md for spec.
## File loaded is determined by _active_market_id (e.g. "kr" → stocks_kr.json).
func _load_stocks_from_json() -> void:
	_stocks.clear()

	var path: String = STOCK_DATA_PATH_TEMPLATE % _active_market_id
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("StockDatabase: Failed to open %s — %s" % [path, error_string(FileAccess.get_open_error())])
		return

	var json: JSON = JSON.new()
	var err: Error = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("StockDatabase: JSON parse error in '%s' at line %d — %s" % [path, json.get_error_line(), json.get_error_message()])
		return

	var data: Dictionary = json.data
	var stock_list: Array = data.get("stocks", [])

	for d: Variant in stock_list:
		if not d is Dictionary:
			push_error("StockDatabase: unexpected entry type %s — skipping" % typeof(d))
			continue
		var entry: Dictionary = d as Dictionary

		# Validate required fields before accessing them.
		const REQUIRED_FIELDS: Array[String] = ["id", "name_ko", "name_en", "sector", "base_price"]
		var missing_field := false
		for field: String in REQUIRED_FIELDS:
			if not entry.has(field):
				push_error("StockDatabase: entry missing required field '%s' — skipping entry" % field)
				missing_field = true
				break
		if missing_field:
			continue

		var stock := StockData.new()
		stock.stock_id = entry.get("id", "")
		stock.name_ko = entry.get("name_ko", "")
		stock.name_en = entry.get("name_en", "")
		stock.sector = entry.get("sector", "")
		stock.base_price = int(entry.get("base_price", 0))
		stock.volatility_profile = VOL_MAP.get(entry.get("volatility", "MEDIUM"), StockData.VolatilityProfile.MEDIUM)
		stock.macro_sensitivity = float(entry.get("macro_sensitivity", 1.0))
		stock.sector_sensitivity = float(entry.get("sector_sensitivity", 1.0))
		stock.listed_shares = int(entry.get("listed_shares", 1000000))
		stock.per = float(entry.get("per", 0.0))
		stock.pbr = float(entry.get("pbr", 0.0))
		stock.roe = float(entry.get("roe", 0.0))
		stock.dividend_yield = float(entry.get("dividend_yield", 0.0))
		var tags: Array = entry.get("event_tags", [])
		stock.event_tags = Array(tags, TYPE_STRING, &"", null)
		stock.description = entry.get("description", "")
		stock.archetype = str(entry.get("archetype", ""))
		stock.season_drift = float(entry.get("seasonDrift", 0.0))
		_stocks[stock.stock_id] = stock

	_build_indexes()
	stocks_loaded.emit()


## Build sector and tag lookup indexes after JSON load. Called once per season load.
func _build_indexes() -> void:
	_sector_index.clear()
	_tag_index.clear()
	for stock: StockData in _stocks.values():
		if not _sector_index.has(stock.sector):
			var sector_arr: Array[StockData] = []
			_sector_index[stock.sector] = sector_arr
		_sector_index[stock.sector].append(stock)
		for tag: String in stock.event_tags:
			if not _tag_index.has(tag):
				var tag_arr: Array[StockData] = []
				_tag_index[tag] = tag_arr
			_tag_index[tag].append(stock)
