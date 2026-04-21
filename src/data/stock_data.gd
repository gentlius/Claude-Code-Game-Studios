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
@export var pbr: float = 0.0  ## Price-to-Book Ratio. 0.0 indicates deficit/negative book value (null equivalent)
@export var roe: float = 0.0  ## Return on Equity (%). 0.0 indicates deficit company (null equivalent)
@export var dividend_yield: float = 0.0  ## Annual dividend yield as a decimal (e.g. 0.02 = 2%). 0.0 = no dividend.
@export var event_tags: Array[String] = []  ## Tags for INDIVIDUAL event matching
@export var description: String = ""
## 이 종목의 상장 역사 시즌 수 (3~300). 프리히스토리 생성 범위를 결정한다.
## 3 = 신생 상장주, 300 = 대형 우량주. OhlcvHistory / M1CacheManager가 참조.
@export var history_seasons: int = 100

## 종목 표시용 통합 포맷. 전체 코드에서 이 메서드만 사용한다.
## 포맷 변경 시 이 한 곳만 수정하면 된다.
func get_display_name() -> String:
	return "%s(%s)" % [name_ko, stock_id]


## 배당수익률 표시 문자열. dividend_yield == 0.0이면 "N/A" 반환.
## 표시 포맷 단일 소유 — 호출자는 이 메서드만 사용한다.
func get_dividend_display() -> String:
	if dividend_yield == 0.0:
		return "N/A"
	return "%.1f%%" % (dividend_yield * 100.0)
