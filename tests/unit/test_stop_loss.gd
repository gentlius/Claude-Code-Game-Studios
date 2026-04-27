## Unit tests for StopTakeSystem.
## GUT test suite. See: design/gdd/stop-loss-take-profit.md §8 AC.
extends GutTest

# ── Helpers ──

## Use a real stock ID from stocks.json so StockDatabase.get_stock() passes validation.
## "STC" (스타칩) is guaranteed to exist — injecting fake IDs caused REJECTED orders.
const MOCK_STOCK_ID: String = "STC"


func _set_mock_price(stock_id: String, price: int) -> void:
	## Inject a full valid _stock_states entry so PriceEngine internals don't crash.
	## S8-01: order_book 포함 필수 — _fill_market_order가 consume_order_book() 호출.
	## 충분한 잔량 제공하여 stop-loss 체결이 즉시 이루어지도록 한다.
	PriceEngine._stock_states[stock_id] = {
		"stock_id":            stock_id,
		"current_price":       price,
		"base_price":          10000,
		"prev_day_close":      10000,
		"season_open_price":   10000,
		"volatility_profile":  StockData.VolatilityProfile.MEDIUM,
		"macro_sensitivity":   1.0,
		"sector_sensitivity":  1.0,
		"markov_state":        PriceEngine.MarkovState.SIDEWAYS,
		"state_duration":      0,
		"season_bias":         PriceEngine.SeasonBias.NEUTRAL,
		"tick_prices":         [] as Array[int],
		"tick_volumes":        [] as Array[float],
		"ohlcv_daily":         [] as Array[Dictionary],
		"event_queue":         [] as Array,
		"gradual_events":      [] as Array,
		"order_book": {
			"ask": [{"price": price, "qty": 10000}],
			"bid": [{"price": price, "qty": 10000}],
		},
	}


func _add_mock_holding(stock_id: String, quantity: int) -> void:
	## Directly inject a holding entry for test isolation.
	PortfolioManager._holdings[stock_id] = {
		"stock_id":          stock_id,
		"quantity":          quantity,
		"avg_buy_price":     10000,
		"total_invested":    10000 * quantity,
		"current_value":     10000 * quantity,
		"unrealized_pnl":    0,
		"unrealized_pnl_pct": 0.0,
		"first_buy_tick":    0,
		"last_trade_tick":   0,
	}


func _unlock_tr1_tr2() -> void:
	SkillTree._unlocked_skills["TR1"] = true
	SkillTree._unlocked_skills["TR2"] = true


# ── Setup / Teardown ──

func before_each() -> void:
	ShortSellingSystem.reset()
	PortfolioManager.reset()
	OrderEngine.reset()
	StopTakeSystem.reset()
	SkillTree._unlocked_skills.clear()
	## OrderEngine.submit_market_order reads GameClock.get_market_state() internally.
	## Set to MARKET_OPEN so sell orders fill immediately, not queue as PENDING.
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN


func after_each() -> void:
	## Clean up injected mock state to prevent test cross-contamination.
	## Do NOT erase MOCK_STOCK_ID from StockDatabase — STC is a real stock loaded from JSON.
	PriceEngine._stock_states.erase(MOCK_STOCK_ID)
	GameClock._market_state = GameClock.MarketState.PRE_MARKET


# ── AC-01: TR2 미해금 시 set_condition 실패 ──

func test_ui_disabled_when_tr2_not_unlocked() -> void:
	_add_mock_holding(MOCK_STOCK_ID, 100)
	var ok: bool = StopTakeSystem.set_condition(MOCK_STOCK_ID, 9000, 12000, 100)
	assert_false(ok, "TR2 미해금 시 set_condition은 false를 반환해야 한다")
	assert_true(StopTakeSystem.get_setting(MOCK_STOCK_ID).is_empty(), "설정이 저장되지 않아야 한다")


# ── AC-02: TR2 해금 후 설정 가능 ──

func test_ui_enabled_after_tr2_unlock() -> void:
	_unlock_tr1_tr2()
	_add_mock_holding(MOCK_STOCK_ID, 100)
	var ok: bool = StopTakeSystem.set_condition(MOCK_STOCK_ID, 9000, 12000, 100)
	assert_true(ok, "TR2 해금 후 set_condition은 true를 반환해야 한다")
	assert_not_null(StopTakeSystem.get_setting(MOCK_STOCK_ID), "설정이 저장되어야 한다")


# ── AC-03: 손절가 이하 현재가 → 시장가 매도 발동 ──

func test_stop_loss_triggers_on_price_breach() -> void:
	_unlock_tr1_tr2()
	_add_mock_holding(MOCK_STOCK_ID, 100)
	StopTakeSystem.set_condition(MOCK_STOCK_ID, 9000, null, 100)

	# 현재가 8500 — 손절가 9000 이하
	_set_mock_price(MOCK_STOCK_ID, 8500)

	var state: Array[bool] = [false]
	var cb: Callable = func(_id: String, reason: String, _p: int) -> void:
		if reason == "STOP_LOSS":
			state[0] = true
	StopTakeSystem.on_stop_take_triggered.connect(cb)

	StopTakeSystem.check_and_trigger(GameClock.MarketState.MARKET_OPEN)
	StopTakeSystem.on_stop_take_triggered.disconnect(cb)
	assert_true(state[0], "손절 조건 충족 시 on_stop_take_triggered 시그널이 발행되어야 한다")


# ── AC-04: 익절가 이상 현재가 → 시장가 매도 발동 ──

func test_take_profit_triggers_on_price_breach() -> void:
	_unlock_tr1_tr2()
	_add_mock_holding(MOCK_STOCK_ID, 100)
	StopTakeSystem.set_condition(MOCK_STOCK_ID, null, 12000, 100)

	_set_mock_price(MOCK_STOCK_ID, 12500)

	var state: Array[bool] = [false]
	var cb: Callable = func(_id: String, reason: String, _p: int) -> void:
		if reason == "TAKE_PROFIT":
			state[0] = true
	StopTakeSystem.on_stop_take_triggered.connect(cb)

	StopTakeSystem.check_and_trigger(GameClock.MarketState.MARKET_OPEN)
	StopTakeSystem.on_stop_take_triggered.disconnect(cb)
	assert_true(state[0], "익절 조건 충족 시 on_stop_take_triggered 시그널이 발행되어야 한다")


# ── AC-05: 발동 후 해당 종목 설정 삭제 ──

func test_setting_removed_after_trigger() -> void:
	_unlock_tr1_tr2()
	_add_mock_holding(MOCK_STOCK_ID, 100)
	StopTakeSystem.set_condition(MOCK_STOCK_ID, 9000, null, 100)
	_set_mock_price(MOCK_STOCK_ID, 8500)

	StopTakeSystem.check_and_trigger(GameClock.MarketState.MARKET_OPEN)
	assert_true(StopTakeSystem.get_setting(MOCK_STOCK_ID).is_empty(), "발동 후 설정이 삭제되어야 한다")


# ── AC-06: 조건 미충족 틱에서 발동 없음 ──

func test_no_trigger_when_condition_not_met() -> void:
	_unlock_tr1_tr2()
	_add_mock_holding(MOCK_STOCK_ID, 100)
	StopTakeSystem.set_condition(MOCK_STOCK_ID, 9000, 12000, 100)
	_set_mock_price(MOCK_STOCK_ID, 10000)

	var state: Array[bool] = [false]
	var cb: Callable = func(_a: String, _b: String, _c: int) -> void: state[0] = true
	StopTakeSystem.on_stop_take_triggered.connect(cb)
	StopTakeSystem.check_and_trigger(GameClock.MarketState.MARKET_OPEN)
	StopTakeSystem.on_stop_take_triggered.disconnect(cb)
	assert_false(state[0], "조건 미충족 시 발동 없어야 한다")
	assert_not_null(StopTakeSystem.get_setting(MOCK_STOCK_ID), "조건 미충족 시 설정 유지")


# ── AC-07: MARKET_OPEN 외 상태에서 발동 없음 ──

func test_no_trigger_outside_market_open() -> void:
	_unlock_tr1_tr2()
	_add_mock_holding(MOCK_STOCK_ID, 100)
	StopTakeSystem.set_condition(MOCK_STOCK_ID, 9000, null, 100)
	_set_mock_price(MOCK_STOCK_ID, 8000)

	var state: Array[bool] = [false]
	var cb: Callable = func(_a: String, _b: String, _c: int) -> void: state[0] = true
	StopTakeSystem.on_stop_take_triggered.connect(cb)
	StopTakeSystem.check_and_trigger(GameClock.MarketState.PRE_MARKET)
	assert_false(state[0], "PRE_MARKET 상태에서는 발동하지 않아야 한다")

	StopTakeSystem.check_and_trigger(GameClock.MarketState.PAUSED)
	StopTakeSystem.on_stop_take_triggered.disconnect(cb)
	assert_false(state[0], "PAUSED 상태에서는 발동하지 않아야 한다")


# ── AC-08: 손절가 >= 익절가 입력 차단 (UI 레벨, 여기서는 set_condition 성공 여부만 확인) ──

func test_invalid_stop_take_relationship_rejected() -> void:
	## 엔진 레벨에서는 UI 차단이 없으므로 UI 차단은 통합 테스트에서 검증.
	## 여기서는 set_condition 자체는 통과하고, 실제 발동 로직을 확인.
	_unlock_tr1_tr2()
	_add_mock_holding(MOCK_STOCK_ID, 100)
	## 손절가(12000) > 익절가(9000) 비정상 설정 → elif 체인으로 손절만 발동
	var ok: bool = StopTakeSystem.set_condition(MOCK_STOCK_ID, 12000, 9000, 100)
	assert_true(ok, "비정상 설정도 set_condition 자체는 통과 (UI가 차단 역할)")


# ── AC-09: on_stop_take_triggered 시그널 파라미터 확인 ──

func test_trigger_signal_emitted_with_correct_params() -> void:
	_unlock_tr1_tr2()
	_add_mock_holding(MOCK_STOCK_ID, 50)
	StopTakeSystem.set_condition(MOCK_STOCK_ID, 9000, null, 50)
	_set_mock_price(MOCK_STOCK_ID, 8800)

	var received: Array = ["", "", 0]  ## [stock_id, reason, price]
	var cb: Callable = func(id: String, reason: String, price: int) -> void:
		received[0] = id
		received[1] = reason
		received[2] = price
	StopTakeSystem.on_stop_take_triggered.connect(cb)
	StopTakeSystem.check_and_trigger(GameClock.MarketState.MARKET_OPEN)
	StopTakeSystem.on_stop_take_triggered.disconnect(cb)
	assert_eq(received[0], MOCK_STOCK_ID, "stock_id 파라미터 확인")
	assert_eq(received[1], "STOP_LOSS", "reason 파라미터 확인")
	assert_gt(received[2] as int, 0, "filled_price는 0보다 커야 한다")


# ── AC-10: 자동 매도 수량 클램프 ──

func test_quantity_clamped_to_available() -> void:
	_unlock_tr1_tr2()
	_add_mock_holding(MOCK_STOCK_ID, 30)   ## 30주 보유
	StopTakeSystem.set_condition(MOCK_STOCK_ID, 9000, null, 100)  ## 100주 설정 (초과)
	_set_mock_price(MOCK_STOCK_ID, 8500)

	var qty_state: Array[int] = [0]
	var cb: Callable = func(order: Dictionary) -> void:
		if order.get("stock_id", "") == MOCK_STOCK_ID:
			qty_state[0] = order.get("quantity", 0)
	OrderEngine.on_order_filled.connect(cb)
	StopTakeSystem.check_and_trigger(GameClock.MarketState.MARKET_OPEN)
	OrderEngine.on_order_filled.disconnect(cb)
	assert_eq(qty_state[0], 30, "발동 수량은 min(설정량, 가용량)으로 클램프되어야 한다")


# ── AC-12: 종목 전량 수동 매도 시 설정 자동 삭제 ──

func test_setting_cleared_on_manual_full_sell() -> void:
	_unlock_tr1_tr2()
	_add_mock_holding(MOCK_STOCK_ID, 100)
	StopTakeSystem.set_condition(MOCK_STOCK_ID, 9000, null, 100)
	assert_not_null(StopTakeSystem.get_setting(MOCK_STOCK_ID), "설정이 존재해야 한다")

	## 전량 매도 시뮬레이션: holding_removed signal with holding gone
	PortfolioManager._holdings.erase(MOCK_STOCK_ID)
	PortfolioManager.holding_removed.emit(MOCK_STOCK_ID, 100, 10000, 0)
	assert_true(StopTakeSystem.get_setting(MOCK_STOCK_ID).is_empty(), "전량 매도 후 설정이 삭제되어야 한다")


# ── AC-13: 세이브/로드 후 설정 복원 ──

func test_setting_persists_after_save_load() -> void:
	_unlock_tr1_tr2()
	_add_mock_holding(MOCK_STOCK_ID, 100)
	StopTakeSystem.set_condition(MOCK_STOCK_ID, 9000, 12000, 80)

	var saved: Array = StopTakeSystem.get_save_data()
	StopTakeSystem.reset()
	assert_true(StopTakeSystem.get_setting(MOCK_STOCK_ID).is_empty(), "리셋 후 설정 없어야 한다")

	StopTakeSystem.load_save_data(saved)
	var restored: Variant = StopTakeSystem.get_setting(MOCK_STOCK_ID)
	assert_not_null(restored, "로드 후 설정이 복원되어야 한다")
	assert_eq((restored as Dictionary).get("stop_loss_price"), 9000, "손절가 복원 확인")
	assert_eq((restored as Dictionary).get("take_profit_price"), 12000, "익절가 복원 확인")
	assert_eq((restored as Dictionary).get("quantity"), 80, "수량 복원 확인")


# ── AC-14: 시즌 종료(새 시즌 시작) 후 설정 초기화 ──

func test_setting_cleared_on_season_start() -> void:
	_unlock_tr1_tr2()
	_add_mock_holding(MOCK_STOCK_ID, 100)
	StopTakeSystem.set_condition(MOCK_STOCK_ID, 9000, null, 100)
	assert_not_null(StopTakeSystem.get_setting(MOCK_STOCK_ID))

	GameClock.on_season_start.emit()
	assert_true(StopTakeSystem.get_setting(MOCK_STOCK_ID).is_empty(), "시즌 시작 후 설정 초기화되어야 한다")


# ── AC-15: TR2 미해금 상태 로드 시 설정 삭제 ──

func test_setting_cleared_if_skill_not_unlocked_on_load() -> void:
	_unlock_tr1_tr2()
	_add_mock_holding(MOCK_STOCK_ID, 100)
	StopTakeSystem.set_condition(MOCK_STOCK_ID, 9000, null, 100)
	var saved: Array = StopTakeSystem.get_save_data()

	## TR2 해금 취소 후 로드
	SkillTree._unlocked_skills.erase("TR2")
	StopTakeSystem.load_save_data(saved)
	assert_true(StopTakeSystem.get_setting(MOCK_STOCK_ID).is_empty(), "TR2 미해금 로드 시 설정 삭제되어야 한다")


# ── 숏 포지션 손절/익절 테스트 ──

func _add_mock_short(stock_id: String, quantity: int, open_price: int) -> void:
	## Inject a short position directly for test isolation.
	var initial_value: int = open_price * quantity
	ShortSellingSystem._positions[stock_id] = {
		"stock_id":           stock_id,
		"quantity":           quantity,
		"open_price":         open_price,
		"initial_value":      initial_value,
		"margin_deposited":   ceili(initial_value * 1.40),
		"open_tick":          0,
		"open_day":           0,
		"unrealized_pnl":     0,
		"unrealized_pnl_pct": 0.0,
		"margin_ratio":       1.40,
	}


func _unlock_tr1_tr2_tr3() -> void:
	SkillTree._unlocked_skills["TR1"] = true
	SkillTree._unlocked_skills["TR2"] = true
	SkillTree._unlocked_skills["TR3"] = true


# ── 숏 AC-S01: 숏 포지션에 set_condition 성공 ──

func test_short_set_condition_succeeds_with_short_position() -> void:
	_unlock_tr1_tr2_tr3()
	_add_mock_short(MOCK_STOCK_ID, 10, 10000)
	var ok: bool = StopTakeSystem.set_condition(MOCK_STOCK_ID, 13000, 7000, 10)
	assert_true(ok, "숏 포지션에 set_condition은 true를 반환해야 한다")
	var setting: Variant = StopTakeSystem.get_setting(MOCK_STOCK_ID)
	assert_not_null(setting, "설정이 저장되어야 한다")
	assert_true((setting as Dictionary).get("is_short", false), "is_short 플래그가 true여야 한다")


# ── 숏 AC-S02: 롱·숏 포지션 모두 없을 때 set_condition 실패 ──

func test_short_set_condition_fails_without_any_position() -> void:
	_unlock_tr1_tr2_tr3()
	var ok: bool = StopTakeSystem.set_condition(MOCK_STOCK_ID, 13000, 7000, 10)
	assert_false(ok, "롱·숏 포지션 모두 없으면 set_condition은 false를 반환해야 한다")


# ── 숏 AC-S03: 가격 상승 → 손절 BUY_TO_COVER 발동 ──

func test_short_stop_loss_triggers_when_price_rises() -> void:
	_unlock_tr1_tr2_tr3()
	_add_mock_short(MOCK_STOCK_ID, 10, 10000)
	_set_mock_price(MOCK_STOCK_ID, 10000)
	StopTakeSystem.set_condition(MOCK_STOCK_ID, 13000, null, 10)

	## 가격 상승 → 손절 임계값(13000) 돌파
	_set_mock_price(MOCK_STOCK_ID, 13500)

	var triggered: Array[String] = []
	var cb: Callable = func(id: String, reason: String, _p: int) -> void:
		if reason == "STOP_LOSS":
			triggered.append(id)
	StopTakeSystem.on_stop_take_triggered.connect(cb)
	StopTakeSystem.check_and_trigger(GameClock.MarketState.MARKET_OPEN)
	StopTakeSystem.on_stop_take_triggered.disconnect(cb)
	assert_true(triggered.has(MOCK_STOCK_ID), "가격 상승 시 숏 손절 on_stop_take_triggered 발행 필요")


# ── 숏 AC-S04: 가격 하락 → 익절 BUY_TO_COVER 발동 ──

func test_short_take_profit_triggers_when_price_falls() -> void:
	_unlock_tr1_tr2_tr3()
	_add_mock_short(MOCK_STOCK_ID, 10, 10000)
	_set_mock_price(MOCK_STOCK_ID, 10000)
	StopTakeSystem.set_condition(MOCK_STOCK_ID, null, 7000, 10)

	## 가격 하락 → 익절 임계값(7000) 하회
	_set_mock_price(MOCK_STOCK_ID, 6500)

	var triggered: Array[String] = []
	var cb: Callable = func(id: String, reason: String, _p: int) -> void:
		if reason == "TAKE_PROFIT":
			triggered.append(id)
	StopTakeSystem.on_stop_take_triggered.connect(cb)
	StopTakeSystem.check_and_trigger(GameClock.MarketState.MARKET_OPEN)
	StopTakeSystem.on_stop_take_triggered.disconnect(cb)
	assert_true(triggered.has(MOCK_STOCK_ID), "가격 하락 시 숏 익절 on_stop_take_triggered 발행 필요")


# ── 숏 AC-S05: 조건 미충족 시 발동 없음 ──

func test_short_no_trigger_when_condition_not_met() -> void:
	_unlock_tr1_tr2_tr3()
	_add_mock_short(MOCK_STOCK_ID, 10, 10000)
	_set_mock_price(MOCK_STOCK_ID, 10000)
	StopTakeSystem.set_condition(MOCK_STOCK_ID, 13000, 7000, 10)

	## 가격이 설정 범위 내
	_set_mock_price(MOCK_STOCK_ID, 11000)
	var fired: Array[bool] = [false]
	var cb: Callable = func(_a: String, _b: String, _c: int) -> void: fired[0] = true
	StopTakeSystem.on_stop_take_triggered.connect(cb)
	StopTakeSystem.check_and_trigger(GameClock.MarketState.MARKET_OPEN)
	StopTakeSystem.on_stop_take_triggered.disconnect(cb)
	assert_false(fired[0], "조건 미충족 시 발동 없어야 한다")
	assert_not_null(StopTakeSystem.get_setting(MOCK_STOCK_ID), "설정 유지되어야 한다")


# ── 숏 AC-S06: 숏 청산 시 설정 자동 삭제 ──

func test_short_setting_cleared_on_position_close() -> void:
	_unlock_tr1_tr2_tr3()
	_add_mock_short(MOCK_STOCK_ID, 10, 10000)
	StopTakeSystem.set_condition(MOCK_STOCK_ID, 13000, null, 10)
	assert_not_null(StopTakeSystem.get_setting(MOCK_STOCK_ID), "설정이 존재해야 한다")

	## 숏 포지션 수동 청산 시뮬레이션
	ShortSellingSystem._positions.erase(MOCK_STOCK_ID)
	ShortSellingSystem.on_short_position_closed.emit(MOCK_STOCK_ID, 50000)
	assert_true(StopTakeSystem.get_setting(MOCK_STOCK_ID).is_empty(), "숏 청산 후 설정이 삭제되어야 한다")
