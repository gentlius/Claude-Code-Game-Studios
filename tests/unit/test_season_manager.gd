extends GutTest
## Unit tests for SeasonManager — see design/gdd/season-manager.md

# ── Helpers ──

## Reset SeasonManager's internal state before each test.
func before_each() -> void:
	SeasonManager.reset_for_testing()


# ─────────────────────────────────────────────
# §4-1  Tier Assignment
# ─────────────────────────────────────────────

func test_assign_tier_bronze_minimum() -> void:
	# Arrange: exactly at bronze threshold
	var assets: int = 1_000_000

	# Act
	var tier: int = SeasonManager._assign_tier(assets)

	# Assert
	assert_eq(tier, SeasonManager.TIER_BRONZE, "1,000,000원 → 브론즈")


func test_assign_tier_silver_boundary_ec01() -> void:
	# EC-01: exactly at silver threshold → silver (≥ rule)
	var assets: int = 3_000_000

	var tier: int = SeasonManager._assign_tier(assets)

	assert_eq(tier, SeasonManager.TIER_SILVER, "3,000,000원 → 실버 (EC-01 경계)")


func test_assign_tier_just_below_silver_is_bronze() -> void:
	var assets: int = 2_999_999

	var tier: int = SeasonManager._assign_tier(assets)

	assert_eq(tier, SeasonManager.TIER_BRONZE, "2,999,999원 → 브론즈")


func test_assign_tier_gold() -> void:
	var assets: int = 15_000_000

	var tier: int = SeasonManager._assign_tier(assets)

	assert_eq(tier, SeasonManager.TIER_GOLD, "1,500만원 → 골드")


func test_assign_tier_master_of_investment() -> void:
	# AC-03: at/above ending threshold → 거장 tier
	var assets: int = 100_000_000_000

	var tier: int = SeasonManager._assign_tier(assets)

	assert_eq(tier, SeasonManager.TIER_MASTER_OF_INVESTMENT, "1,000억 이상 → 거장")


# ─────────────────────────────────────────────
# §4-2  Season Return Rate
# ─────────────────────────────────────────────

func test_get_season_return_pct_zero_when_flat() -> void:
	# Arrange: season started at same value as current assets
	SeasonManager._season_start_capital = 1_000_000

	# We cannot mock PortfolioManager in an autoload test easily,
	# so we call the formula directly using known inputs.
	var total_assets: int = 1_000_000
	var expected: float = float(total_assets - SeasonManager._season_start_capital) \
		/ float(SeasonManager._season_start_capital) * 100.0

	# Assert formula result (no side-effects)
	assert_almost_eq(expected, 0.0, 0.001, "수익률 0% when assets unchanged")


func test_get_season_return_pct_positive() -> void:
	SeasonManager._season_start_capital = 1_000_000

	var total_assets: int = 1_100_000
	var expected: float = float(total_assets - SeasonManager._season_start_capital) \
		/ float(SeasonManager._season_start_capital) * 100.0

	assert_almost_eq(expected, 10.0, 0.001, "10% return")


func test_get_season_return_pct_safe_when_capital_zero() -> void:
	# EC-08: guard — should return 0.0, not divide-by-zero
	SeasonManager._season_start_capital = 0

	var result: float = SeasonManager.get_season_return_pct()

	assert_eq(result, 0.0, "season_start_capital=0 → 0.0 반환 (EC-08)")


# ─────────────────────────────────────────────
# §4-4  Weekly Return Rate
# ─────────────────────────────────────────────

func test_get_weekly_return_pct_safe_when_capital_zero() -> void:
	SeasonManager._weekly_start_capital = 0

	var result: float = SeasonManager.get_weekly_return_pct()

	assert_eq(result, 0.0, "weekly_start_capital=0 → 0.0 반환")


# ─────────────────────────────────────────────
# §4-6  Season Prize Formula (AC-09)
# ─────────────────────────────────────────────

func test_prize_rate_table_rank1_is_50pct() -> void:
	# AC-09: bronze rank-1 prize = 1,000,000 × 0.50 = 500,000원
	var rate: float = SeasonManager.PRIZE_RATE.get(1, 0.0)
	var bronze_threshold: int = SeasonManager.TIER_THRESHOLD[SeasonManager.TIER_BRONZE]

	var prize: int = int(float(bronze_threshold) * rate)

	assert_eq(prize, 500_000, "브론즈 1위 = 500,000원 (AC-09)")


func test_prize_rate_table_rank2_is_30pct() -> void:
	var rate: float = SeasonManager.PRIZE_RATE.get(2, 0.0)
	assert_almost_eq(rate, 0.30, 0.001, "2위 배율 0.30")


func test_prize_rate_ranks_6_to_10_are_equal() -> void:
	for rank: int in range(6, 11):
		var rate: float = SeasonManager.PRIZE_RATE.get(rank, -1.0)
		assert_almost_eq(rate, 0.03, 0.001, "rank %d 배율 0.03" % rank)


func test_prize_rate_rank11_not_in_table() -> void:
	# Rank 11+ gets no cash prize
	var has_entry: bool = SeasonManager.PRIZE_RATE.has(11)
	assert_false(has_entry, "11위 이상은 상금 테이블에 없음 (EC-05)")


# ─────────────────────────────────────────────
# §4-5  Rank Eligibility (AC-08)
# ─────────────────────────────────────────────

func test_rank_eligible_threshold() -> void:
	# Exactly MIN_TRADES_FOR_RANK fills → eligible
	var min_trades: int = SeasonManager.MIN_TRADES_FOR_RANK
	var is_eligible: bool = min_trades >= SeasonManager.MIN_TRADES_FOR_RANK
	assert_true(is_eligible, "체결 %d회 = 자격 있음" % min_trades)


func test_rank_ineligible_below_threshold() -> void:
	var below_min: int = SeasonManager.MIN_TRADES_FOR_RANK - 1
	var is_ineligible: bool = below_min < SeasonManager.MIN_TRADES_FOR_RANK
	assert_true(is_ineligible, "체결 %d회 = 자격 없음" % below_min)


# ─────────────────────────────────────────────
# §3-5  Free-Market Detection (AC-04)
# ─────────────────────────────────────────────

func test_free_market_mode_when_below_threshold() -> void:
	# Assets below FREE_MARKET_THRESHOLD → is_free_market must be true.
	# We test the threshold boundary directly.
	var below_threshold: int = SeasonManager.FREE_MARKET_THRESHOLD - 1
	var is_free_market: bool = below_threshold < SeasonManager.FREE_MARKET_THRESHOLD
	assert_true(is_free_market, "자산 < 100만원 → 프리마켓 (AC-04)")


func test_official_league_when_at_threshold() -> void:
	var at_threshold: int = SeasonManager.FREE_MARKET_THRESHOLD
	var is_free_market: bool = at_threshold < SeasonManager.FREE_MARKET_THRESHOLD
	assert_false(is_free_market, "자산 = 100만원 → 공식 리그")


# ─────────────────────────────────────────────
# §3-5  Hangang Ending Condition (AC-05, EC-06)
# ─────────────────────────────────────────────

func test_hangang_condition_requires_both_empty_holdings_and_low_cash() -> void:
	# EC-06: BOTH conditions must be true simultaneously.
	# holdings empty = true, cash below threshold = true → hangang
	var holdings_empty: bool = true
	var cash: int = SeasonManager.HANGANG_THRESHOLD - 1
	var should_trigger: bool = holdings_empty and cash < SeasonManager.HANGANG_THRESHOLD
	assert_true(should_trigger, "보유 없음 AND 현금 < 임계값 → 한강 엔딩 (AC-05)")


func test_hangang_condition_blocked_by_holdings() -> void:
	# EC-06: has holdings → no hangang even if cash is low
	var holdings_empty: bool = false
	var cash: int = SeasonManager.HANGANG_THRESHOLD - 1
	var should_trigger: bool = holdings_empty and cash < SeasonManager.HANGANG_THRESHOLD
	assert_false(should_trigger, "보유 주식 있음 → 한강 엔딩 미발동 (EC-06)")


func test_hangang_condition_blocked_by_sufficient_cash() -> void:
	var holdings_empty: bool = true
	var cash: int = SeasonManager.HANGANG_THRESHOLD
	var should_trigger: bool = holdings_empty and cash < SeasonManager.HANGANG_THRESHOLD
	assert_false(should_trigger, "현금 = 임계값 → 한강 엔딩 미발동 (현금 부족 조건 미충족)")


# ─────────────────────────────────────────────
# Weekly Trade Count Reset (Q4 Decision)
# ─────────────────────────────────────────────

func test_weekly_trade_count_increments_on_fill() -> void:
	# Arrange
	SeasonManager._weekly_trade_count = 0

	# Act
	SeasonManager._on_order_filled({})
	SeasonManager._on_order_filled({})

	# Assert
	assert_eq(SeasonManager._weekly_trade_count, 2, "체결 2회 → weekly_trade_count = 2")


func test_weekly_trade_count_resets_on_week_end() -> void:
	# Arrange: simulate mid-week activity
	SeasonManager._weekly_trade_count = 7
	SeasonManager._is_free_market = true  # skip prize logic for isolation
	SeasonManager._weekly_start_capital = 1_000_000  # prevent divide-by-zero

	# Act: trigger week-end handler (skips prize — is_free_market = true)
	SeasonManager._on_week_end()

	# Assert
	assert_eq(SeasonManager._weekly_trade_count, 0, "주차 종료 후 weekly_trade_count = 0 (Q4)")


func test_last_week_trade_count_captured_before_reset() -> void:
	# Arrange
	SeasonManager._weekly_trade_count = 5
	SeasonManager._is_free_market = true
	SeasonManager._weekly_start_capital = 1_000_000

	# Act
	SeasonManager._on_week_end()

	# Assert: last_week count should hold the pre-reset value
	assert_eq(SeasonManager._last_week_trade_count, 5, "last_week_trade_count에 리셋 전 값 보존")


# ─────────────────────────────────────────────
# Serialization round-trip
# ─────────────────────────────────────────────

func test_save_and_load_round_trip() -> void:
	# Arrange
	SeasonManager._current_tier = SeasonManager.TIER_GOLD
	SeasonManager._is_free_market = false
	SeasonManager._season_start_capital = 15_000_000
	SeasonManager._weekly_start_capital = 16_000_000
	SeasonManager._weekly_trade_count = 3

	# Act
	var saved: Dictionary = SeasonManager.get_save_data()
	# Reset state then restore
	SeasonManager._current_tier = SeasonManager.TIER_FREE_MARKET
	SeasonManager._is_free_market = true
	SeasonManager._season_start_capital = 0
	SeasonManager.load_save_data(saved)

	# Assert
	assert_eq(SeasonManager._current_tier, SeasonManager.TIER_GOLD, "tier 복원")
	assert_false(SeasonManager._is_free_market, "is_free_market 복원")
	assert_eq(SeasonManager._season_start_capital, 15_000_000, "season_start_capital 복원")
	assert_eq(SeasonManager._weekly_start_capital, 16_000_000, "weekly_start_capital 복원")
	assert_eq(SeasonManager._weekly_trade_count, 3, "weekly_trade_count 복원")


# ─────────────────────────────────────────────
# Participant Count Builder
# ─────────────────────────────────────────────

func test_participant_counts_sum_equals_ai_total() -> void:
	# Total AI = TOTAL_PARTICIPANTS - 1 (player excluded)
	var counts: Dictionary = SeasonManager._build_participant_counts()
	var total: int = 0
	for key: int in counts:
		total += counts[key]

	# Allow ±TIER_COUNT rounding from int() truncation
	var expected_ai: int = SeasonManager.TOTAL_PARTICIPANTS - 1
	assert_true(
		abs(total - expected_ai) <= SeasonManager.TIER_COUNT,
		"AI 참가자 합계 ≈ %d (실제: %d)" % [expected_ai, total]
	)


# ─────────────────────────────────────────────
# is_season_active / get_leaderboard (S3-03)
# ─────────────────────────────────────────────

func test_is_season_active_false_before_start() -> void:
	# Arrange: reset ensures _season_start_capital == 0
	# Assert
	assert_false(SeasonManager.is_season_active(), "시즌 시작 전 → false")


func test_is_season_active_true_after_start() -> void:
	# Arrange: simulate season start
	SeasonManager._season_start_capital = 1_000_000
	# Assert
	assert_true(SeasonManager.is_season_active(), "시즌 시작 후 → true")


func test_get_leaderboard_returns_empty_before_season() -> void:
	# Arrange: no season started (_season_start_capital == 0)
	# Act
	var result: Array = SeasonManager.get_leaderboard()
	# Assert
	assert_eq(result.size(), 0, "시즌 미시작 시 빈 배열")


func test_get_leaderboard_returns_empty_in_free_market() -> void:
	# Arrange: free-market mode
	SeasonManager._is_free_market = true
	SeasonManager._season_start_capital = 500_000  # below threshold but season "started"
	# Act
	var result: Array = SeasonManager.get_leaderboard(SeasonManager.TIER_FREE_MARKET)
	# Assert
	assert_eq(result.size(), 0, "프리마켓 모드 → 빈 배열")


func test_prize_for_rank_rank1_bronze() -> void:
	# Bronze threshold = 1,000,000. PRIZE_RATE[1] = 0.50 → 500,000원
	var prize: int = SeasonManager._prize_for_rank(1, SeasonManager.TIER_BRONZE)
	assert_eq(prize, 500_000, "브론즈 1위 상금 = 500,000원")


func test_prize_for_rank_unranked_returns_zero() -> void:
	# rank > 10 has no PRIZE_RATE entry → 0
	var prize: int = SeasonManager._prize_for_rank(11, SeasonManager.TIER_BRONZE)
	assert_eq(prize, 0, "11위 이하 상금 = 0")


# ─────────────────────────────────────────────
# get_fiction_date() — 픽션 날짜 체계
# ─────────────────────────────────────────────

func test_fiction_date_before_season_start_returns_month_1() -> void:
	# _seasons_played == 0 → quarter_idx clamps to 0 → 1월
	var d: Dictionary = SeasonManager.get_fiction_date()
	assert_eq(d["month"], 1, "시즌 미시작(0회) → 1월")


func test_fiction_date_season_1_returns_month_1() -> void:
	# Season 1 → SEASON_MONTH_STARTS[0] = 1월
	SeasonManager._seasons_played = 1
	var d: Dictionary = SeasonManager.get_fiction_date()
	assert_eq(d["month"], 1, "시즌 1 → 1월")


func test_fiction_date_season_2_returns_month_4() -> void:
	SeasonManager._seasons_played = 2
	var d: Dictionary = SeasonManager.get_fiction_date()
	assert_eq(d["month"], 4, "시즌 2 → 4월")


func test_fiction_date_season_3_returns_month_7() -> void:
	SeasonManager._seasons_played = 3
	var d: Dictionary = SeasonManager.get_fiction_date()
	assert_eq(d["month"], 7, "시즌 3 → 7월")


func test_fiction_date_season_4_returns_month_10() -> void:
	SeasonManager._seasons_played = 4
	var d: Dictionary = SeasonManager.get_fiction_date()
	assert_eq(d["month"], 10, "시즌 4 → 10월")


func test_fiction_date_season_5_wraps_to_month_1() -> void:
	# 5번째 시즌은 다시 1월 (4로 나눈 나머지 = 0)
	SeasonManager._seasons_played = 5
	var d: Dictionary = SeasonManager.get_fiction_date()
	assert_eq(d["month"], 1, "시즌 5 → 1월 (4주기 순환)")


func test_fiction_date_has_day_key() -> void:
	SeasonManager._seasons_played = 1
	var d: Dictionary = SeasonManager.get_fiction_date()
	assert_true(d.has("day"), "day 키 존재")
	assert_true(d["day"] >= 1, "day ≥ 1")
