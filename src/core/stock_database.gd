## Autoload — Manages stock definitions for the current season.
## 46 stocks across 11 sectors, loaded from assets/data/stocks.json.
## Foundation layer: no dependencies on other game systems.
extends Node

## Emitted after season stocks are loaded and ready.
signal stocks_loaded

const STOCK_DATA_PATH: String = "res://assets/data/stocks.json"

## Volatility string -> enum mapping for JSON parsing.
const VOL_MAP: Dictionary = {
	"LOW": StockData.VolatilityProfile.LOW,
	"MEDIUM": StockData.VolatilityProfile.MEDIUM,
	"HIGH": StockData.VolatilityProfile.HIGH,
	"EXTREME": StockData.VolatilityProfile.EXTREME,
}

var _stocks: Dictionary = {}  ## stock_id -> StockData


func _ready() -> void:
	_load_stocks_from_json()


## Returns a StockData by ID, or null if not found.
func get_stock(stock_id: String) -> StockData:
	return _stocks.get(stock_id)


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


## Returns all stocks in a given sector.
func get_stocks_by_sector(sector: String) -> Array[StockData]:
	var result: Array[StockData] = []
	for stock: StockData in _stocks.values():
		if stock.sector == sector:
			result.append(stock)
	return result


## Returns stock IDs in a given sector.
func get_stock_ids_by_sector(sector: String) -> Array[String]:
	var result: Array[String] = []
	for stock: StockData in _stocks.values():
		if stock.sector == sector:
			result.append(stock.stock_id)
	return result


## Returns stocks whose event_tags intersect with the given tag.
func get_stocks_by_event_tag(tag: String) -> Array[StockData]:
	var result: Array[StockData] = []
	for stock: StockData in _stocks.values():
		if stock.event_tags.has(tag):
			result.append(stock)
	return result


## Load stocks from JSON data file. See design/gdd/stock-database.md for spec.
func _load_stocks_from_json() -> void:
	_stocks.clear()

	var file: FileAccess = FileAccess.open(STOCK_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("StockDatabase: Failed to open %s — %s" % [STOCK_DATA_PATH, error_string(FileAccess.get_open_error())])
		return

	var json: JSON = JSON.new()
	var err: Error = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("StockDatabase: JSON parse error at line %d — %s" % [json.get_error_line(), json.get_error_message()])
		return

	var data: Dictionary = json.data
	var stock_list: Array = data.get("stocks", [])

	for d: Variant in stock_list:
		var entry: Dictionary = d as Dictionary
		var stock := StockData.new()
		stock.stock_id = entry["id"]
		stock.name_ko = entry["name_ko"]
		stock.name_en = entry["name_en"]
		stock.sector = entry["sector"]
		stock.base_price = int(entry["base_price"])
		stock.volatility_profile = VOL_MAP.get(entry.get("volatility", "MEDIUM"), StockData.VolatilityProfile.MEDIUM)
		stock.macro_sensitivity = float(entry.get("macro_sensitivity", 1.0))
		stock.sector_sensitivity = float(entry.get("sector_sensitivity", 1.0))
		stock.listed_shares = int(entry.get("listed_shares", 1000000))
		stock.per = float(entry.get("per", 0.0))
		var tags: Array = entry.get("event_tags", [])
		stock.event_tags = Array(tags, TYPE_STRING, &"", null)
		stock.description = entry.get("description", "")
		_stocks[stock.stock_id] = stock

	stocks_loaded.emit()
