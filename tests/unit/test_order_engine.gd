extends GutTest
## Unit tests for OrderEngine — tick size validation and order rejection.
## See: design/gdd/order-engine.md

# ── Helpers ──

func before_each() -> void:
	# Reset order engine state
	OrderEngine._next_order_id = 1
	OrderEngine._market_order_queue.clear()
	OrderEngine._pending_limit_orders.clear()
	OrderEngine._pre_market_queue.clear()
	OrderEngine._order_history.clear()
	OrderEngine._sell_locks.clear()
	# Ensure limit order skill (TR1) is unlocked so tests exercise tick size logic
	SkillTree._unlocked_skills["TR1"] = true


# ── Tick Size Validation in Limit Orders ──

func test_limit_order_rejected_bad_tick_size() -> void:
	# Set market open so validation passes market state check
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN
	# Give enough cash
	CurrencySystem._sim_cash = 10_000_000

	# 65030 is not a valid tick (tick=100 at this price level)
	var order: Dictionary = OrderEngine.submit_limit_order("BUY", "KSF", 1, 65030)
	assert_eq(order["status"], "REJECTED", "Should reject bad tick size")
	assert_true(order["reject_reason"].find("호가 단위") >= 0, "Reason should mention tick size")


func test_limit_order_accepted_valid_tick_size() -> void:
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN
	CurrencySystem._sim_cash = 10_000_000

	# 65000 is valid (tick=100 at this price level)
	var order: Dictionary = OrderEngine.submit_limit_order("BUY", "KSF", 1, 65000)
	assert_eq(order["status"], "PENDING", "Valid tick size order should be accepted")
	assert_ne(order["reject_reason"], "지정가가 호가 단위(100원)에 맞지 않습니다",
		"Valid tick should not be rejected for tick size")


func test_limit_order_tick_size_low_price() -> void:
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN
	CurrencySystem._sim_cash = 10_000_000

	# At price 3000, tick=5. 3003 is invalid.
	var order: Dictionary = OrderEngine.submit_limit_order("BUY", "KSF", 1, 3003)
	assert_eq(order["status"], "REJECTED", "3003 should be rejected (tick=5)")
	assert_true(order["reject_reason"].find("호가 단위") >= 0, "Reason should mention tick size")


func test_limit_order_tick_size_boundary() -> void:
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN
	CurrencySystem._sim_cash = 10_000_000

	# At price 5000, tick=10. 5000 is valid.
	var order: Dictionary = OrderEngine.submit_limit_order("BUY", "KSF", 1, 5000)
	assert_eq(order["status"], "PENDING", "Valid tick size boundary order should be accepted")
	assert_ne(order["reject_reason"], "지정가가 호가 단위(10원)에 맞지 않습니다",
		"5000 should be valid (tick=10)")
