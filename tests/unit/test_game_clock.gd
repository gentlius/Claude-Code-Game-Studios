extends GutTest
## Unit tests for GameClock — focus on pause_request/pause_release (S3-02).
## See: design/gdd/game-clock.md


func before_each() -> void:
	GameClock.reset_for_testing()


# ─────────────────────────────────────────────
# pause_request / pause_release (S3-02)
# ─────────────────────────────────────────────

func test_pause_request_transitions_market_open_to_paused() -> void:
	# Arrange: simulate MARKET_OPEN state directly
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN

	# Act
	GameClock.pause_request("test_source")

	# Assert
	assert_eq(GameClock.get_market_state(), GameClock.MarketState.PAUSED,
		"pause_request → PAUSED")


func test_pause_release_resumes_when_all_sources_released() -> void:
	# Arrange: two sources holding pause
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN
	GameClock.pause_request("source_a")
	GameClock.pause_request("source_b")

	# Act: release one — should stay paused
	GameClock.pause_release("source_a")
	assert_eq(GameClock.get_market_state(), GameClock.MarketState.PAUSED,
		"한 소스 해제 후 아직 PAUSED 유지")

	# Act: release all — should resume
	GameClock.pause_release("source_b")
	assert_eq(GameClock.get_market_state(), GameClock.MarketState.MARKET_OPEN,
		"모든 소스 해제 후 MARKET_OPEN 재개")


func test_pause_request_duplicate_source_id_is_idempotent() -> void:
	# Arrange
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN
	GameClock.pause_request("dup")
	GameClock.pause_request("dup")  # duplicate — should not double-register

	# Act: one release should be sufficient
	GameClock.pause_release("dup")

	# Assert: resumed (not stuck in paused)
	assert_eq(GameClock.get_market_state(), GameClock.MarketState.MARKET_OPEN,
		"중복 pause_request → 단일 release로 재개")


func test_pause_release_unknown_source_is_noop() -> void:
	# Arrange: not paused, no sources registered
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN

	# Act: release unknown source
	GameClock.pause_release("nonexistent")

	# Assert: state unchanged
	assert_eq(GameClock.get_market_state(), GameClock.MarketState.MARKET_OPEN,
		"알 수 없는 소스 release → 상태 변경 없음")


func test_pause_request_noop_when_not_market_open() -> void:
	# Arrange: PRE_MARKET state
	GameClock._market_state = GameClock.MarketState.PRE_MARKET

	# Act
	GameClock.pause_request("league_screen")

	# Assert: source registered but state unchanged (can't pause PRE_MARKET)
	assert_eq(GameClock.get_market_state(), GameClock.MarketState.PRE_MARKET,
		"PRE_MARKET에서 pause_request → 상태 변경 없음")


func test_reset_for_testing_clears_pause_sources() -> void:
	# Arrange: add a pause source
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN
	GameClock.pause_request("some_source")

	# Act
	GameClock.reset_for_testing()

	# Assert: sources cleared — release after reset should not affect state
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN
	GameClock.pause_release("some_source")  # stale call after reset
	assert_eq(GameClock.get_market_state(), GameClock.MarketState.MARKET_OPEN,
		"reset_for_testing 후 누적된 소스 없음")
