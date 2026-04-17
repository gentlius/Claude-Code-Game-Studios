## MarketConfig — 시장별 수수료·세금 파라미터 로드 및 계산
## GDD: design/gdd/trading-fees.md §3, §4
## Autoload 등록: project.godot
extends Node

const CONFIG_PATH: String = "res://assets/data/market_config.json"
const DEFAULT_MARKET: String = "KR"

var _raw: Dictionary = {}
var _active: Dictionary = {}
var _market_id: String = ""


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		push_error("MarketConfig: 설정 파일 로드 실패 — %s" % CONFIG_PATH)
		get_tree().quit(1)
		return
	var text: String = f.get_as_text()
	f.close()
	var result: Variant = JSON.parse_string(text)
	if result == null or not result is Dictionary:
		push_error("MarketConfig: JSON 파싱 실패 — %s" % CONFIG_PATH)
		get_tree().quit(1)
		return
	_raw = result
	_market_id = _raw.get("active_market", DEFAULT_MARKET)
	_active = _raw.get("markets", {}).get(_market_id, {})
	if _active.is_empty():
		push_error("MarketConfig: 시장 설정 없음 — %s" % _market_id)
		get_tree().quit(1)


## GDD §4: 체결 수수료·세금 내역 반환
## side: "BUY" | "SELL"
## gross: 체결금액 (int, 원)
## holding_days: 보유 일수 (양도소득세 구분용; KR=0이므로 영향 없음)
## realized_profit: 실현손익 (양도소득세 과세표준; 음수면 0으로 처리)
func get_fee_breakdown(
	side: String, gross: int, holding_days: int, realized_profit: int
) -> Dictionary:
	var buy_tax_rate: float = _active.get("buy_tax", 0.0)
	var sell_tax_rate: float = _active.get("sell_tax", 0.0)
	var commission_rate: float = _active.get("commission", 0.0)
	var cg_config: Dictionary = _active.get("capital_gains", {})
	var cg_rate: float = _capital_gains_rate(holding_days, cg_config)

	var commission_amount: int = int(floor(float(gross) * commission_rate))
	var buy_tax_amount: int = 0
	var sell_tax_amount: int = 0
	var capital_gains_amount: int = 0
	var net: int = 0

	if side == "BUY":
		buy_tax_amount = int(floor(float(gross) * buy_tax_rate))
		net = -(gross + buy_tax_amount + commission_amount)
	else:  # SELL
		sell_tax_amount = int(floor(float(gross) * sell_tax_rate))
		capital_gains_amount = int(floor(float(maxi(0, realized_profit)) * cg_rate))
		net = gross - sell_tax_amount - commission_amount - capital_gains_amount

	return {
		"commission": commission_amount,
		"buy_tax": buy_tax_amount,
		"sell_tax": sell_tax_amount,
		"capital_gains": capital_gains_amount,
		"net": net,
	}


## 매수 주문 예약금 산정 — 수수료·매수세 포함 총 비용
## GDD §3-2: buy_cost = gross × (1 + buy_tax + commission)
func get_buy_cost(gross: int) -> int:
	var buy_tax_rate: float = _active.get("buy_tax", 0.0)
	var commission_rate: float = _active.get("commission", 0.0)
	return int(ceil(float(gross) * (1.0 + buy_tax_rate + commission_rate)))


## 현재 활성 시장 ID 반환
func get_active_market() -> String:
	return _market_id


## 보유일에 따른 양도소득세율 반환
func _capital_gains_rate(holding_days: int, cg_config: Dictionary) -> float:
	var threshold: int = cg_config.get("threshold_days", 365)
	if holding_days < threshold:
		return cg_config.get("short_term_rate", 0.0)
	return cg_config.get("long_term_rate", 0.0)
