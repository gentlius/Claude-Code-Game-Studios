## Autoload — Manages deposit (permanent) and sim seed (per-season) accounts.
## Foundation layer. See: design/gdd/currency-system.md
## 3층 자산 구조:
##   Layer 1: cash_assets  — 플레이어 실생활 자금 (시즌 청산·상금 입금, 라이프스타일 지출)
##   Layer 2: sim_cash     — 투자 대회 예수금 (시즌 중 매매)
##   Layer 3: total_assets — PortfolioManager가 집계 (cash_assets + 계좌 총 평가금액 + 유형자산)
extends Node

# ── Signals ──

signal sim_cash_changed(new_amount: int, delta: int)
signal deposit_changed(new_amount: int, delta: int)
signal cash_assets_changed(new_amount: int)
signal season_initialized(seed_amount: int)
signal season_settled()
signal prize_earned(amount: int, new_total: int)

# ── Constants ──

const INITIAL_CASH_ASSETS: int = 1_000_000  ## GDD §2-1: 보육원 퇴소 청년 정착지원금
const DEFAULT_SEASON_SEED: int = 1_000_000  ## 브론즈 기준금액 (SeasonManager.TIER_THRESHOLD[0]과 일치)

# ── State ──

var _cash_assets: int = INITIAL_CASH_ASSETS  ## Layer 1: 현금 자산 (플레이어 실생활 자금)
var _sim_cash: int = 0                        ## Layer 2: 예수금 (투자 대회 계좌)
var _total_prize_earned: int = 0             ## 읽기 전용 누적 상금 카운터 (소비 불가)

## Deprecated: _deposit는 _cash_assets로 대체됨. 구버전 세이브 마이그레이션 전용.
## 로드 시 _cash_assets에 흡수 후 사용되지 않음.
@warning_ignore("unused_private_class_variable")
var _deposit: int = 0

# ── Public API: Queries ──

## Returns the current sim cash balance (예수금 — 투자 대회 계좌).
func get_sim_cash() -> int:
	return _sim_cash


## Returns the current cash assets balance (현금 자산 — 플레이어 실생활 자금).
## GDD §2-1: 시즌 청산·상금 입금, 라이프스타일 지출 대상.
func get_cash_assets() -> int:
	return _cash_assets


## Returns total prize money earned across all seasons (읽기 전용 누적 카운터).
## UI 통계 표시 전용 — 소비 불가.
func get_total_prize_earned() -> int:
	return _total_prize_earned


## Returns sim trading account balance (예수금). Kept for UI/test compatibility.
## Note: 라이프스타일 현금 자산은 get_cash_assets() 사용.
func get_deposit() -> int:
	return _sim_cash


# ── Public API: Sim Cash Operations ──

## Deduct from sim cash (매수 시 예수금 차감). Returns true if successful, false if insufficient.
## GDD §2-1: 예수금 음수 불가.
func sim_deduct(amount: int) -> bool:
	if amount <= 0:
		return false
	if _sim_cash < amount:
		return false
	_sim_cash -= amount
	sim_cash_changed.emit(_sim_cash, -amount)
	return true


## Add to sim cash (매도 대금·주문취소 환불·주간상금 입금).
func sim_add(amount: int) -> void:
	if amount <= 0:
		return
	_sim_cash += amount
	sim_cash_changed.emit(_sim_cash, amount)


# ── Public API: Cash Assets Operations ──

## Add to cash assets (시즌 청산·상금·라이프스타일 임대 수익·엑싯 입금).
## GDD §2-1: 라이프스타일 관리 → CurrencySystem.cash_add().
func cash_add(amount: int) -> void:
	if amount <= 0:
		return
	_cash_assets += amount
	cash_assets_changed.emit(_cash_assets)


## Deduct from cash assets (라이프스타일 소비 지출).
## GDD §2-1: 현금 자산 음수 불가. Returns true if successful, false if insufficient.
func cash_deduct(amount: int) -> bool:
	if amount <= 0:
		return false
	if _cash_assets < amount:
		return false
	_cash_assets -= amount
	cash_assets_changed.emit(_cash_assets)
	return true


# ── Public API: Season Lifecycle ──

## Initialize sim seed for the very first season only.
## 새 게임: cash_assets는 INITIAL_CASH_ASSETS(100만원)로 이미 초기화되어 있음.
## sim_cash는 첫 시즌 시작 전 auto_deposit_to_sim()으로 채워진다.
## 현재는 init_first_season()이 직접 sim_cash를 채우는 방식으로 동작 (하위 호환).
func init_first_season(amount: int = DEFAULT_SEASON_SEED) -> void:
	if _sim_cash > 0:
		push_warning("CurrencySystem.init_first_season called on non-zero balance (%d) — ignoring" % _sim_cash)
		return
	_sim_cash = amount
	season_initialized.emit(amount)
	sim_cash_changed.emit(_sim_cash, amount)


## Deposit from cash_assets into sim_cash for season start (시즌 시작 전 예수금 자동 입금).
## GDD §2-3 시즌 시작 전: cash_assets에서 티어 기준금액 차감 → sim_cash 입금.
## EC: cash_assets < amount 이면 전액 입금 (브론즈 하위 프리마켓 티어 진입 허용).
## Returns the actual amount deposited.
func auto_deposit_to_sim(amount: int) -> int:
	if amount <= 0:
		return 0
	var actual: int = mini(amount, _cash_assets)
	_cash_assets -= actual
	_sim_cash += actual
	cash_assets_changed.emit(_cash_assets)
	sim_cash_changed.emit(_sim_cash, actual)
	return actual


## Season settlement: sim_cash + prize → cash_assets, sim_cash = 0.
## GDD §2-4 시즌 전환 [시즌 종료 → 정산] Step 5:
##   _cash_assets += _sim_cash + prize_amount; _sim_cash = 0.
## SeasonManager calls: settle_to_cash(prize_amount) after liquidation + prize calc.
## Also increments _total_prize_earned and emits prize_earned signal.
func settle_to_cash(prize_amount: int = 0) -> void:
	var sim_balance: int = _sim_cash
	_sim_cash = 0

	var total_in: int = sim_balance + prize_amount
	_cash_assets += total_in

	if prize_amount > 0:
		_total_prize_earned += prize_amount
		prize_earned.emit(prize_amount, _total_prize_earned)

	cash_assets_changed.emit(_cash_assets)
	sim_cash_changed.emit(_sim_cash, -sim_balance)
	season_settled.emit()


## Award prize money — legacy path used by SeasonManager._grant_season_prize() when
## prize is added directly to sim_cash (주간 상금 등). This method keeps _deposit_changed
## signal compatibility for any UI still listening to it.
## Note: 시즌 최종 상금은 settle_to_cash(prize_amount)로 처리해야 한다.
func award_prize(amount: int) -> void:
	if amount <= 0:
		return
	# 누적 상금만 증산; 실제 자금 이동은 호출자(SeasonManager._grant_season_prize)가
	# sim_add()로 처리하고 있음. 이 함수는 카운터·시그널만 담당.
	_total_prize_earned += amount
	prize_earned.emit(amount, _total_prize_earned)
	## deposit_changed는 하위 호환 — UI가 아직 구독 중일 수 있음
	deposit_changed.emit(_cash_assets, amount)


## Resets all currency state. Called by GameMain (new game) and tests (before_each).
func reset() -> void:
	_sim_cash = 0
	_cash_assets = INITIAL_CASH_ASSETS
	_total_prize_earned = 0


# ── Serialization ──

## Returns serializable state for save system (GDD: save-load.md, SAVE_VERSION 4)
func get_save_data() -> Dictionary:
	return {
		"sim_cash": _sim_cash,
		"cash_assets": _cash_assets,
		"total_prize_earned": _total_prize_earned,
	}


## Restores state from save data.
## Backward-compatible: v1-v3 saves have "deposit" key instead of "cash_assets".
## GDD §익스플로잇: cash_assets 음수 방지. 상한 없음 (1조+ 달성 가능).
func load_save_data(data: Dictionary) -> void:
	_sim_cash = maxi(data.get("sim_cash", DEFAULT_SEASON_SEED), 0)
	_total_prize_earned = maxi(data.get("total_prize_earned", 0), 0)

	if data.has("cash_assets"):
		# SAVE_VERSION 4+: 정규 경로
		_cash_assets = maxi(data.get("cash_assets", INITIAL_CASH_ASSETS), 0)
	else:
		# SAVE_VERSION 1-3 마이그레이션: deposit → cash_assets
		var legacy_deposit: int = data.get("deposit", INITIAL_CASH_ASSETS)
		_cash_assets = maxi(legacy_deposit, 0)

	sim_cash_changed.emit(_sim_cash, 0)
	cash_assets_changed.emit(_cash_assets)
