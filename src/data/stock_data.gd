## Data resource defining a single stock's static properties.
## Loaded from stock_database at season start. Immutable during gameplay.
class_name StockData
extends Resource

enum VolatilityProfile { LOW, MEDIUM, HIGH, EXTREME }

@export var stock_id: String
@export var name_ko: String
@export var name_en: String
@export var sector: String
@export var base_price: int
@export var volatility_profile: VolatilityProfile
@export var macro_sensitivity: float = 1.0
@export var sector_sensitivity: float = 1.0
@export var listed_shares: int = 1000000  ## 상장주식수
@export var per: float = 0.0  ## 0.0 indicates deficit company (null equivalent)
@export var dividend_yield: float = 0.0  ## Annual dividend yield as a decimal (e.g. 0.02 = 2%). 0.0 = no dividend.
@export var event_tags: Array[String] = []  ## Tags for INDIVIDUAL event matching
@export var description: String = ""
