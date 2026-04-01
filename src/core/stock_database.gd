## Autoload — Manages stock definitions for the current season.
## MVP: 10 stocks across 8 sectors. V-Slice: 46 stocks across 11 sectors.
## Foundation layer: no dependencies on other game systems.
extends Node

## Emitted after season stocks are loaded and ready.
signal stocks_loaded

var _stocks: Dictionary = {}  ## stock_id -> StockData


func _ready() -> void:
	_load_default_stocks()


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


## Hardcoded MVP stocks. Future: load from JSON/Resource files.
func _load_default_stocks() -> void:
	_stocks.clear()

	var defs: Array[Dictionary] = [
		# 시총 = base_price × listed_shares
		# SK(스카이로직)이 최대 시총, BF/MG(바이오)는 소형
		{"id": "KF", "name_ko": "코스모푸드", "name_en": "CosmoFood",
		 "sector": "유통", "base_price": 65000, "listed_shares": 800000,  # 시총 520억
		 "vol": StockData.VolatilityProfile.MEDIUM,
		 "macro": 0.8, "sector_sens": 1.0, "per": 12.5,
		 "tags": ["consumption", "season", "retail", "earnings"],
		 "desc": "국내 1위 종합식품기업. 안정적 매출 성장."},

		{"id": "SC", "name_ko": "스타칩", "name_en": "StarChip",
		 "sector": "반도체", "base_price": 120000, "listed_shares": 1500000,  # 시총 1800억
		 "vol": StockData.VolatilityProfile.HIGH,
		 "macro": 1.2, "sector_sens": 1.5, "per": 18.3,
		 "tags": ["semiconductor", "export", "ai_chip", "earnings"],
		 "desc": "AI 반도체 설계 전문기업. 수출 비중 80%."},

		{"id": "KB", "name_ko": "코리아뱅크", "name_en": "KoreaBank",
		 "sector": "금융", "base_price": 52000, "listed_shares": 2000000,  # 시총 1040억
		 "vol": StockData.VolatilityProfile.LOW,
		 "macro": 1.5, "sector_sens": 0.5, "per": 6.8,
		 "tags": ["interest_rate", "banking", "dividend", "earnings"],
		 "desc": "국내 최대 시중은행. 금리 변동에 민감."},

		{"id": "NE", "name_ko": "넥스트엔터", "name_en": "NextEnter",
		 "sector": "엔터", "base_price": 42000, "listed_shares": 600000,  # 시총 252억
		 "vol": StockData.VolatilityProfile.HIGH,
		 "macro": 0.6, "sector_sens": 0.8, "per": 25.1,
		 "tags": ["entertainment", "comeback", "streaming", "contract"],
		 "desc": "글로벌 K-POP 엔터사. 아티스트 컴백 시즌에 급등."},

		{"id": "MG", "name_ko": "메디진", "name_en": "MediGene",
		 "sector": "바이오", "base_price": 180000, "listed_shares": 200000,  # 시총 360억
		 "vol": StockData.VolatilityProfile.EXTREME,
		 "macro": 1.0, "sector_sens": 1.8, "per": 0.0,
		 "tags": ["clinical_trial", "fda", "drug_development", "patent"],
		 "desc": "신약 개발 바이오벤처. 임상 결과에 극단적 반응."},

		{"id": "GC", "name_ko": "그린케미", "name_en": "GreenChem",
		 "sector": "에너지", "base_price": 38000, "listed_shares": 1200000,  # 시총 456억
		 "vol": StockData.VolatilityProfile.MEDIUM,
		 "macro": 1.0, "sector_sens": 1.2, "per": 9.7,
		 "tags": ["chemical", "raw_material", "oil_price", "earnings"],
		 "desc": "친환경 화학소재 전문. 환경규제 수혜주."},

		{"id": "DH", "name_ko": "대한중공업", "name_en": "DaehanHeavy",
		 "sector": "건설", "base_price": 95000, "listed_shares": 1000000,  # 시총 950억
		 "vol": StockData.VolatilityProfile.LOW,
		 "macro": 1.3, "sector_sens": 1.0, "per": 8.2,
		 "tags": ["shipbuilding", "export", "infrastructure", "defense"],
		 "desc": "국내 2위 조선사. 수주 잔고 3년치 확보."},

		{"id": "PT", "name_ko": "피플텔레콤", "name_en": "PeopleTelecom",
		 "sector": "통신", "base_price": 78000, "listed_shares": 900000,  # 시총 702억
		 "vol": StockData.VolatilityProfile.MEDIUM,
		 "macro": 1.0, "sector_sens": 1.0, "per": 11.0,
		 "tags": ["telecom", "5g", "infrastructure", "dividend"],
		 "desc": "통신 3사 중 하나. 5G 인프라 투자 진행 중."},

		{"id": "SK", "name_ko": "스카이로직", "name_en": "SkyLogic",
		 "sector": "반도체", "base_price": 210000, "listed_shares": 2500000,  # 시총 5250억 (최대)
		 "vol": StockData.VolatilityProfile.HIGH,
		 "macro": 0.9, "sector_sens": 1.3, "per": 22.0,
		 "tags": ["semiconductor", "foundry", "export", "earnings"],
		 "desc": "파운드리(반도체 위탁생산) 전문. 글로벌 고객사 다수."},

		{"id": "BF", "name_ko": "블루팜", "name_en": "BluePharma",
		 "sector": "바이오", "base_price": 320000, "listed_shares": 150000,  # 시총 480억
		 "vol": StockData.VolatilityProfile.EXTREME,
		 "macro": 0.7, "sector_sens": 2.0, "per": 0.0,
		 "tags": ["clinical_trial", "fda", "patent", "drug_development"],
		 "desc": "항암제 파이프라인 보유. FDA 승인 대기 중."},
	]

	for d: Dictionary in defs:
		var stock := StockData.new()
		stock.stock_id = d["id"]
		stock.name_ko = d["name_ko"]
		stock.name_en = d["name_en"]
		stock.sector = d["sector"]
		stock.base_price = d["base_price"]
		stock.volatility_profile = d["vol"]
		stock.macro_sensitivity = d["macro"]
		stock.sector_sensitivity = d["sector_sens"]
		stock.listed_shares = d.get("listed_shares", 1000000)
		stock.per = d["per"]
		stock.event_tags = Array(d["tags"], TYPE_STRING, &"", null)
		stock.description = d["desc"]
		_stocks[stock.stock_id] = stock

	stocks_loaded.emit()
