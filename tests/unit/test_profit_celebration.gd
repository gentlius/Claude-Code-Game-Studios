## GUT unit tests for ProfitCelebration — B-13 수익 실현 팡파레.
## Implements: design/gdd/profit-celebration.md §8 AC-01 ~ AC-04, AC-07 ~ AC-09
## AC-05~06, AC-10~11 are manual playtest verification (GDD §9 AC→테스트 매핑)
extends GutTest

# ── Setup ──

var _pc: ProfitCelebration

func before_each() -> void:
	_pc = ProfitCelebration.new()
	add_child_autofree(_pc)
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN


func after_each() -> void:
	pass  # autofree handles cleanup


# ── AC-01: realized_pnl > 0이면 이펙트가 재생된다 ──

func test_play_triggers_on_positive_pnl() -> void:
	# Arrange: SMALL grade (pnl_pct = 2%)
	_pc.play(10000, 2.0)
	# Assert: _is_playing set and some effect visible
	assert_true(_pc._is_playing, "realized_pnl > 0이면 _is_playing = true여야 한다")
	assert_true(_pc._rollup_label.visible, "롤업 레이블이 표시돼야 한다")


# ── AC-02: realized_pnl ≤ 0이면 이펙트가 없다 ──

func test_no_effect_on_zero_pnl() -> void:
	_pc.play(0, 0.0)
	assert_false(_pc._is_playing, "pnl=0이면 _is_playing = false여야 한다")
	assert_false(_pc._rollup_label.visible, "롤업 레이블이 숨겨져야 한다")


func test_no_effect_on_negative_pnl() -> void:
	_pc.play(-5000, -3.0)
	assert_false(_pc._is_playing, "음수 pnl이면 _is_playing = false여야 한다")


# ── AC-03: 매수 체결 시 이펙트 없음 (pnl_pct=0 경로) ──

func test_play_not_called_for_buy_order() -> void:
	## buy never triggers: TradingScreen calls play() only on holding_removed (sell side).
	## Directly verify: play() with 0 pnl does nothing.
	_pc.play(0, 0.0)
	assert_false(_pc._rollup_label.visible, "매수 체결(pnl=0) 시 롤업이 표시되지 않아야 한다")


# ── AC-04: 경계값에서 상위 등급 적용 ──

func test_grade_boundaries() -> void:
	# Exactly at 5.0% → MEDIUM (≥ 5.0)
	var grade_at_5: ProfitCelebration.Grade = _pc._calc_grade(5.0)
	assert_eq(grade_at_5, ProfitCelebration.Grade.MEDIUM,
		"pnl_pct = 5.0%이면 MEDIUM 등급이어야 한다")

	# Just below 5.0% → SMALL
	var grade_below_5: ProfitCelebration.Grade = _pc._calc_grade(4.999)
	assert_eq(grade_below_5, ProfitCelebration.Grade.SMALL,
		"pnl_pct = 4.999%이면 SMALL 등급이어야 한다")

	# Exactly at 10.0% → LARGE
	var grade_at_10: ProfitCelebration.Grade = _pc._calc_grade(10.0)
	assert_eq(grade_at_10, ProfitCelebration.Grade.LARGE,
		"pnl_pct = 10.0%이면 LARGE 등급이어야 한다")

	# Exactly at 15.0% → JACKPOT
	var grade_at_15: ProfitCelebration.Grade = _pc._calc_grade(15.0)
	assert_eq(grade_at_15, ProfitCelebration.Grade.JACKPOT,
		"pnl_pct = 15.0%이면 JACKPOT 등급이어야 한다")

	# pnl_pct = 0 → NONE
	var grade_zero: ProfitCelebration.Grade = _pc._calc_grade(0.0)
	assert_eq(grade_zero, ProfitCelebration.Grade.NONE,
		"pnl_pct = 0이면 NONE 등급이어야 한다")


func test_grade_full_table() -> void:
	## Validates all four active grades exist and are distinct.
	assert_ne(int(ProfitCelebration.Grade.SMALL),   int(ProfitCelebration.Grade.MEDIUM))
	assert_ne(int(ProfitCelebration.Grade.MEDIUM),  int(ProfitCelebration.Grade.LARGE))
	assert_ne(int(ProfitCelebration.Grade.LARGE),   int(ProfitCelebration.Grade.JACKPOT))
	assert_eq(_pc._calc_grade(1.0),  ProfitCelebration.Grade.SMALL)
	assert_eq(_pc._calc_grade(7.5),  ProfitCelebration.Grade.MEDIUM)
	assert_eq(_pc._calc_grade(12.0), ProfitCelebration.Grade.LARGE)
	assert_eq(_pc._calc_grade(20.0), ProfitCelebration.Grade.JACKPOT)


# ── AC-07: 이펙트 중 _cancel_current() 호출 시 즉시 종료 ──

func test_cancel_stops_effects() -> void:
	# Start an effect
	_pc.play(50000, 8.0)
	assert_true(_pc._rollup_label.visible, "이펙트 시작 후 롤업 레이블이 표시돼야 한다")

	# Act: cancel
	_pc._cancel_current()

	# Assert: all effects cleared
	assert_false(_pc._rollup_label.visible, "취소 후 롤업 레이블이 숨겨져야 한다")
	assert_false(_pc._flash_rect.visible,   "취소 후 플래시가 숨겨져야 한다")
	assert_false(_pc._banner_label.visible, "취소 후 배너가 숨겨져야 한다")
	assert_false(_pc._is_playing,           "취소 후 _is_playing = false여야 한다")


# ── AC-08: 연속 체결 시 이전 이펙트 취소 → 새 이펙트 시작 ──

func test_consecutive_fills_reset_effect() -> void:
	_pc.play(10000, 3.0)  # SMALL
	assert_true(_pc._is_playing)

	# Second play immediately
	_pc.play(200000, 18.0)  # JACKPOT
	assert_true(_pc._is_playing,
		"연속 체결 후 새 이펙트가 재생 중이어야 한다")
	assert_eq(_pc._current_grade, ProfitCelebration.Grade.JACKPOT,
		"마지막 체결(JACKPOT) 등급으로 갱신돼야 한다")
	assert_true(_pc._banner_label.visible,
		"JACKPOT 배너가 표시돼야 한다")


# ── AC-09: MARKET_CLOSED 시 이펙트 즉시 종료 ──

func test_market_closed_cancels_effect() -> void:
	_pc.play(30000, 6.0)
	assert_true(_pc._is_playing)

	# Simulate market close signal
	_pc._on_market_state_changed(
		GameClock.MarketState.MARKET_CLOSED,
		GameClock.MarketState.MARKET_OPEN
	)

	assert_false(_pc._is_playing, "MARKET_CLOSED 시 이펙트가 즉시 종료돼야 한다")
	assert_false(_pc._rollup_label.visible, "MARKET_CLOSED 시 롤업이 숨겨져야 한다")


# ── Tuning constant sanity ──

func test_tuning_constants_in_range() -> void:
	assert_true(ProfitCelebration.GRADE_MEDIUM_THRESHOLD > 0.0,
		"MEDIUM 경계값 > 0")
	assert_true(ProfitCelebration.GRADE_LARGE_THRESHOLD > ProfitCelebration.GRADE_MEDIUM_THRESHOLD,
		"LARGE > MEDIUM 경계값")
	assert_true(ProfitCelebration.GRADE_JACKPOT_THRESHOLD > ProfitCelebration.GRADE_LARGE_THRESHOLD,
		"JACKPOT > LARGE 경계값")
	assert_true(ProfitCelebration.COIN_COUNT_JACKPOT > ProfitCelebration.COIN_COUNT_LARGE,
		"JACKPOT 파티클 수 > LARGE")


# ── Format helper ──

func test_fmt_int_comma() -> void:
	pending("_fmt_int_comma removed — formatting delegated to FormatUtils.number()")
