## Unit tests for ShortSellingSystem and OrderEngine TR3 short-selling integration.
## GUT test suite. See: design/gdd/short-selling.md §8 AC.
extends GutTest

# ── Constants ──

## Real stock ID guaranteed to exist in stocks.json (same as test_stop_loss.gd).
const MOCK_STOCK: String = "STC"
const MOCK_PRICE: int = 175_000


# ── Helpers ──

func _set_mock_price(stock_id: String, price: int) -> void:
	## Full _stock_states entry — order_book required for OrderEngine consume_order_book().
	PriceEngine._stock_states[stock_id] = {
		"stock_id":            stock_id,
		"current_price":       price,
		"base_price":          price,
		"prev_day_close":      price,
		"season_open_price":   price,
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


func _unlock_tr3() -> void:
	SkillTree._unlocked_skills["TR3"] = true


func _inject_short_position(stock_id: String, open_price: int, quantity: int) -> void:
	## Directly inject a ShortPosition for tests that need an existing position.
	var initial_value: int = open_price * quantity
	var margin_rate: float = ShortSellingSystem._margin_rate
	var margin_deposited: int = int(ceil(float(initial_value) * margin_rate))
	ShortSellingSystem._positions[stock_id] = {
		"stock_id":           stock_id,
		"quantity":           quantity,
		"open_price":         open_price,
		"initial_value":      initial_value,
		"margin_deposited":   margin_deposited,
		"open_tick":          0,
		"open_day":           0,
		"unrealized_pnl":     0,
		"unrealized_pnl_pct": 0.0,
		"margin_ratio":       margin_rate,
	}


# ── Setup / Teardown ──

func before_each() -> void:
	ShortSellingSystem.reset()
	PortfolioManager.reset()
	OrderEngine.reset()
	SkillTree._unlocked_skills.clear()
	CurrencySystem.reset()
	CurrencySystem.init_first_season(10_000_000)  ## 1000만원 시작 자금
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN
	_set_mock_price(MOCK_STOCK, MOCK_PRICE)


func after_each() -> void:
	PriceEngine._stock_states.erase(MOCK_STOCK)
	GameClock._market_state = GameClock.MarketState.PRE_MARKET


# ── AC-01: TR3 미해금 시 SELL_SHORT REJECTED ──────────────────────────────────

func test_sell_short_rejected_without_tr3() -> void:
	# Arrange — TR3 not unlocked
	# Act
	var order: Dictionary = OrderEngine.submit_market_order("SELL_SHORT", MOCK_STOCK, 10)
	# Assert
	assert_eq(order["status"], "REJECTED", "TR3 미해금 시 REJECTED")
	assert_true(order["reject_reason"].find("해금") >= 0, "reject_reason에 '해금' 포함")


# ── AC-02: SELL_SHORT 체결 시 margin_deposited 예수금 차감 ────────────────────

func test_sell_short_deducts_margin() -> void:
	# Arrange
	_unlock_tr3()
	var cash_before: int = CurrencySystem.get_sim_cash()
	var margin_rate: float = ShortSellingSystem._margin_rate  ## 1.40
	var initial_value: int = MOCK_PRICE * 10
	var margin_deposited: int = int(ceil(float(initial_value) * margin_rate))
	var sale_proceeds: int = initial_value  ## 매도 대금 즉시 추가
	var expected_cash_after: int = cash_before - margin_deposited + sale_proceeds
	# Act
	var order: Dictionary = OrderEngine.submit_market_order("SELL_SHORT", MOCK_STOCK, 10)
	# Assert
	assert_eq(order["status"], "FILLED", "주문 체결")
	assert_eq(CurrencySystem.get_sim_cash(), expected_cash_after,
		"예수금 = 초기 - margin_deposited + sale_proceeds")


# ── AC-03: SELL_SHORT 체결 시 ShortPosition 생성, margin_ratio == margin_rate ─

func test_short_position_created_on_fill() -> void:
	# Arrange
	_unlock_tr3()
	# Act
	OrderEngine.submit_market_order("SELL_SHORT", MOCK_STOCK, 10)
	# Assert
	assert_true(ShortSellingSystem.has_short(MOCK_STOCK), "숏 포지션 생성됨")
	var positions: Array[Dictionary] = ShortSellingSystem.get_all_short_positions()
	assert_eq(positions.size(), 1, "포지션 1개")
	var pos: Dictionary = positions[0]
	assert_eq(pos["open_price"], MOCK_PRICE, "개시가 = MOCK_PRICE")
	assert_almost_eq(
		pos["margin_ratio"], ShortSellingSystem._margin_rate, 0.0001,
		"개시 시 margin_ratio == margin_rate"
	)


# ── AC-04: 매 틱 unrealized_pnl = (open_price - current_price) × qty ─────────

func test_unrealized_pnl_calculated_per_tick() -> void:
	# Arrange — inject position manually
	var open_price: int = 175_000
	var qty: int = 10
	_inject_short_position(MOCK_STOCK, open_price, qty)
	# Move price UP (short loses money)
	var new_price: int = 192_000
	_set_mock_price(MOCK_STOCK, new_price)
	# Act
	ShortSellingSystem.update_and_check_margin(1)
	# Assert
	var pos: Dictionary = ShortSellingSystem._positions[MOCK_STOCK]
	var expected_pnl: int = (open_price - new_price) * qty  ## -170,000
	assert_eq(pos["unrealized_pnl"], expected_pnl,
		"unrealized_pnl = (open-current)*qty = -170,000")


# ── AC-05: 매 틱 margin_ratio = (margin_deposited + unrealized_pnl) / initial_value

func test_margin_ratio_formula() -> void:
	# Arrange
	var open_price: int = 175_000
	var qty: int = 10
	_inject_short_position(MOCK_STOCK, open_price, qty)
	var pos: Dictionary = ShortSellingSystem._positions[MOCK_STOCK]
	var new_price: int = 192_000
	_set_mock_price(MOCK_STOCK, new_price)
	# Act
	ShortSellingSystem.update_and_check_margin(1)
	# Assert
	var expected_pnl: int = (open_price - new_price) * qty          ## -170,000
	var expected_ratio: float = (
		float(pos["margin_deposited"] + expected_pnl) / float(pos["initial_value"])
	)
	assert_almost_eq(pos["margin_ratio"], expected_ratio, 0.0001, "margin_ratio 공식 검증")


# ── AC-06: margin_ratio < 0.2 시 강제청산 ─────────────────────────────────────

func test_forced_liquidation_triggers_below_threshold() -> void:
	# Arrange — price must exceed open_price × (margin_rate + 1 - threshold) = 175000 × 2.20
	var open_price: int = 175_000
	var qty: int = 10
	_inject_short_position(MOCK_STOCK, open_price, qty)
	# Set price to trigger forced liquidation (≥ open × 2.20 = 385,000)
	var liquidation_price: int = 400_000
	_set_mock_price(MOCK_STOCK, liquidation_price)

	var forced_liq_fired: bool = false
	ShortSellingSystem.on_forced_liquidation.connect(
		func(_sid: String, _p: int, _pnl: int) -> void: forced_liq_fired = true
	)
	# Act
	ShortSellingSystem.update_and_check_margin(1)
	# Assert
	assert_false(ShortSellingSystem.has_short(MOCK_STOCK), "포지션 제거됨")
	assert_true(forced_liq_fired, "on_forced_liquidation 시그널 발행")


# ── AC-07: BUY_TO_COVER 체결 시 realized_pnl 예수금 반영 ──────────────────────

func test_buy_to_cover_realized_pnl() -> void:
	# Arrange — open short, then price drops (profitable)
	_unlock_tr3()
	OrderEngine.submit_market_order("SELL_SHORT", MOCK_STOCK, 10)
	var cash_after_open: int = CurrencySystem.get_sim_cash()
	var pos: Dictionary = ShortSellingSystem._positions[MOCK_STOCK]

	var cover_price: int = 163_000  ## 하락 → 수익
	_set_mock_price(MOCK_STOCK, cover_price)

	# Act
	var cover_order: Dictionary = OrderEngine.submit_market_order("BUY_TO_COVER", MOCK_STOCK, 10)

	# Assert
	assert_eq(cover_order["status"], "FILLED", "BUY_TO_COVER 체결")
	assert_false(ShortSellingSystem.has_short(MOCK_STOCK), "포지션 청산됨")

	var pnl: int = (MOCK_PRICE - cover_price) * 10               ## 120,000
	var cover_cost: int = cover_price * 10                        ## 1,630,000
	var expected_cash: int = cash_after_open - cover_cost + maxi(0, pos["margin_deposited"] + pnl)
	assert_eq(CurrencySystem.get_sim_cash(), expected_cash, "예수금 BUY_TO_COVER 정산 정확")


# ── AC-08: 시즌 종료 시 미청산 숏 포지션 전량 자동청산 ───────────────────────

func test_season_end_auto_liquidates_all() -> void:
	# Arrange — inject two positions
	_inject_short_position(MOCK_STOCK, 175_000, 5)
	_inject_short_position("STC", 175_000, 3)  ## same stock, just testing count
	# Act
	ShortSellingSystem.liquidate_all_for_season_end()
	# Assert
	assert_true(ShortSellingSystem._positions.is_empty(), "시즌 종료 후 모든 포지션 청산")


# ── AC-09: 롱 보유 종목에 SELL_SHORT REJECTED ────────────────────────────────

func test_sell_short_rejected_when_long_held() -> void:
	# Arrange — add a long holding for MOCK_STOCK
	_unlock_tr3()
	PortfolioManager._holdings[MOCK_STOCK] = {
		"stock_id": MOCK_STOCK, "quantity": 5, "avg_buy_price": MOCK_PRICE,
		"total_invested": MOCK_PRICE * 5, "current_value": MOCK_PRICE * 5,
		"unrealized_pnl": 0, "unrealized_pnl_pct": 0.0,
		"first_buy_tick": 0, "last_trade_tick": 0,
	}
	# Act
	var order: Dictionary = OrderEngine.submit_market_order("SELL_SHORT", MOCK_STOCK, 10)
	# Assert
	assert_eq(order["status"], "REJECTED", "롱 보유 시 SELL_SHORT REJECTED")
	assert_true(order["reject_reason"].find("보유") >= 0, "reject_reason에 '보유' 포함")


# ── AC-10: 숏 포지션 보유 중 동일 종목 BUY REJECTED ────────────────────────────

func test_buy_rejected_when_short_held() -> void:
	# Arrange
	_unlock_tr3()
	_inject_short_position(MOCK_STOCK, MOCK_PRICE, 5)
	# Act — regular BUY on a stock with open short
	var order: Dictionary = OrderEngine.submit_market_order("BUY", MOCK_STOCK, 1)
	# Assert
	assert_eq(order["status"], "REJECTED", "숏 보유 시 BUY REJECTED")
	assert_true(order["reject_reason"].find("숏") >= 0, "reject_reason에 '숏' 포함")


# ── AC-11: 중복 숏 포지션(동일 종목 SELL_SHORT 2회) REJECTED ────────────────

func test_duplicate_short_rejected() -> void:
	# Arrange — first short succeeds
	_unlock_tr3()
	var first: Dictionary = OrderEngine.submit_market_order("SELL_SHORT", MOCK_STOCK, 5)
	assert_eq(first["status"], "FILLED", "첫 번째 SELL_SHORT 체결")
	# Act — same stock again
	var second: Dictionary = OrderEngine.submit_market_order("SELL_SHORT", MOCK_STOCK, 5)
	# Assert
	assert_eq(second["status"], "REJECTED", "중복 SELL_SHORT REJECTED")
	assert_true(second["reject_reason"].find("이미") >= 0, "reject_reason에 '이미' 포함")


# ── AC-12: PRE_MARKET에서 SELL_SHORT REJECTED ────────────────────────────────

func test_sell_short_rejected_in_pre_market() -> void:
	# Arrange
	_unlock_tr3()
	GameClock._market_state = GameClock.MarketState.PRE_MARKET
	# Act
	var order: Dictionary = OrderEngine.submit_market_order("SELL_SHORT", MOCK_STOCK, 5)
	# Assert
	assert_eq(order["status"], "REJECTED", "PRE_MARKET SELL_SHORT REJECTED")
	assert_true(order["reject_reason"].find("장 중") >= 0, "reject_reason에 '장 중' 포함")


# ── AC-13: 숏 unrealized_pnl이 account_total_value에 올바르게 반영 ───────────

func test_short_net_value_in_total_assets() -> void:
	# Arrange — inject short with known unrealized_pnl
	var open_price: int = 175_000
	var qty: int = 10
	_inject_short_position(MOCK_STOCK, open_price, qty)
	# Set current price lower → positive pnl
	_set_mock_price(MOCK_STOCK, 163_000)
	ShortSellingSystem.update_and_check_margin(1)
	var pos: Dictionary = ShortSellingSystem._positions[MOCK_STOCK]
	var expected_short_net: int = pos["margin_deposited"] + pos["unrealized_pnl"]
	# Act
	assert_eq(ShortSellingSystem.get_short_net_value(), expected_short_net,
		"get_short_net_value() = margin_deposited + unrealized_pnl")


# ── AC-14: 증거금 부족 시 SELL_SHORT REJECTED, 예수금 불변 ─────────────────────

func test_sell_short_rejected_insufficient_margin() -> void:
	# Arrange — cash exactly 100만원, but margin_deposited = ceil(175000 × 10 × 1.40) = 2,450,000
	_unlock_tr3()
	CurrencySystem.reset()
	CurrencySystem.init_first_season(1_000_000)
	var cash_before: int = CurrencySystem.get_sim_cash()
	# Act
	var order: Dictionary = OrderEngine.submit_market_order("SELL_SHORT", MOCK_STOCK, 10)
	# Assert
	assert_eq(order["status"], "REJECTED", "증거금 부족 REJECTED")
	assert_eq(CurrencySystem.get_sim_cash(), cash_before, "예수금 불변")


# ── AC-15: 강제청산 후 BUY_TO_COVER REJECTED ───────────────────────────────

func test_buy_to_cover_rejected_after_forced_liq() -> void:
	# Arrange — force a liquidation, then try to cover
	_inject_short_position(MOCK_STOCK, 175_000, 5)
	_set_mock_price(MOCK_STOCK, 400_000)  ## triggers forced liquidation
	ShortSellingSystem.update_and_check_margin(1)
	assert_false(ShortSellingSystem.has_short(MOCK_STOCK), "강제청산 완료 전제")
	# Act
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN
	var order: Dictionary = OrderEngine.submit_market_order("BUY_TO_COVER", MOCK_STOCK, 5)
	# Assert
	assert_eq(order["status"], "REJECTED", "포지션 없는 BUY_TO_COVER REJECTED")
	assert_true(order["reject_reason"].find("청산할") >= 0, "reject_reason에 '청산할' 포함")


# ── get_short_net_value: 포지션 없을 때 0 ────────────────────────────────────

func test_get_short_net_value_empty() -> void:
	assert_eq(ShortSellingSystem.get_short_net_value(), 0, "포지션 없으면 net_value = 0")


# ── save/load 라운드트립 ─────────────────────────────────────────────────────

func test_save_load_roundtrip() -> void:
	# Arrange — inject position
	var open_price: int = 175_000
	var qty: int = 10
	_inject_short_position(MOCK_STOCK, open_price, qty)
	var orig: Dictionary = ShortSellingSystem._positions[MOCK_STOCK].duplicate()
	# Act — serialize, reset, deserialize
	var data: Array[Dictionary] = ShortSellingSystem.get_save_data()
	ShortSellingSystem.reset()
	assert_false(ShortSellingSystem.has_short(MOCK_STOCK), "reset 후 포지션 없음")
	ShortSellingSystem.load_save_data(data)
	# Assert
	assert_true(ShortSellingSystem.has_short(MOCK_STOCK), "로드 후 포지션 복구")
	var restored: Dictionary = ShortSellingSystem._positions[MOCK_STOCK]
	assert_eq(restored["open_price"],       orig["open_price"],       "open_price 복구")
	assert_eq(restored["quantity"],         orig["quantity"],          "quantity 복구")
	assert_eq(restored["margin_deposited"], orig["margin_deposited"],  "margin_deposited 복구")
	assert_eq(restored["initial_value"],    orig["initial_value"],     "initial_value 복구")
