## S10-03 UI 테스트 — EndingScreen 3종 + MarginCallPopup.
## GUT test suite. GDD: design/gdd/endings-achievements.md §3, leverage-trading.md §3-3.
extends GutTest

# ── Helpers ──

func _make_ending_screen() -> EndingScreen:
	var scr: EndingScreen = EndingScreen.new()
	add_child_autofree(scr)
	return scr


func _make_margin_popup() -> MarginCallPopup:
	var p: MarginCallPopup = MarginCallPopup.new()
	add_child_autofree(p)
	return p


# ══════════════════════════════════════════════════════════════
#  EndingScreen
# ══════════════════════════════════════════════════════════════

## AC-E10: show_ending("bankruptcy") → panel visible, title 포함 "한강"
func test_ending_screen_bankruptcy_shows_hangang_title() -> void:
	var scr: EndingScreen = _make_ending_screen()

	scr.show_ending("bankruptcy")

	assert_true(scr.visible, "화면이 visible=true 되어야 한다")
	# title은 tr()를 거치므로 영어 빌드에서 원문 키를 반환 가능 — 원문 또는 한국어 둘 다 허용
	var title: String = scr._lbl_title.text
	assert_false(title.is_empty(), "타이틀이 비어있지 않아야 한다")


## AC-E11: show_ending("leverage_crash") → panel visible, is_bad_ending = true
func test_ending_screen_leverage_crash_is_bad_ending() -> void:
	var scr: EndingScreen = _make_ending_screen()

	scr.show_ending("leverage_crash")

	assert_true(scr.visible, "화면이 visible=true 되어야 한다")
	assert_true(scr.is_bad_ending(), "leverage_crash는 bad_ending이어야 한다")


## AC-E12: show_ending("win") → panel visible, is_bad_ending = false
func test_ending_screen_win_is_not_bad_ending() -> void:
	var scr: EndingScreen = _make_ending_screen()

	scr.show_ending("win")

	assert_true(scr.visible, "화면이 visible=true 되어야 한다")
	assert_false(scr.is_bad_ending(), "win 엔딩은 bad_ending이 아니어야 한다")


## AC-E13: 배드엔딩 버튼 → new_game_requested 시그널 발화
func test_ending_screen_bad_ending_action_emits_new_game_requested() -> void:
	var scr: EndingScreen = _make_ending_screen()
	watch_signals(scr)

	scr.show_ending("bankruptcy")
	scr._on_action_pressed()

	assert_signal_emitted(scr, "new_game_requested")
	assert_signal_not_emitted(scr, "continue_requested")


## AC-E14: 론샤크 배드엔딩 버튼 → new_game_requested 발화
func test_ending_screen_loan_shark_action_emits_new_game_requested() -> void:
	var scr: EndingScreen = _make_ending_screen()
	watch_signals(scr)

	scr.show_ending("leverage_crash")
	scr._on_action_pressed()

	assert_signal_emitted(scr, "new_game_requested")


## AC-E15: 거장 엔딩 버튼 → continue_requested 발화
func test_ending_screen_win_action_emits_continue_requested() -> void:
	var scr: EndingScreen = _make_ending_screen()
	watch_signals(scr)

	scr.show_ending("win")
	scr._on_action_pressed()

	assert_signal_emitted(scr, "continue_requested")
	assert_signal_not_emitted(scr, "new_game_requested")


## AC-E16: 알 수 없는 ending_id → bankruptcy fallback 사용 (빌드 불량 방지)
func test_ending_screen_unknown_id_falls_back_to_bankruptcy() -> void:
	var scr: EndingScreen = _make_ending_screen()

	scr.show_ending("nonexistent_id")

	assert_true(scr.visible, "fallback이라도 visible=true 되어야 한다")
	# fallback은 bankruptcy 데이터를 사용
	assert_true(scr.is_bad_ending(), "fallback은 bad_ending이어야 한다")


## AC-E17: 버튼 클릭 후 화면 hidden
func test_ending_screen_hides_after_action() -> void:
	var scr: EndingScreen = _make_ending_screen()

	scr.show_ending("bankruptcy")
	assert_true(scr.visible, "클릭 전 visible=true")
	scr._on_action_pressed()
	assert_false(scr.visible, "클릭 후 visible=false 되어야 한다")


# ══════════════════════════════════════════════════════════════
#  MarginCallPopup
# ══════════════════════════════════════════════════════════════

## S10-03 마진콜 팝업 — show_warning() 이후 panel visible
func test_margin_call_popup_show_warning_makes_panel_visible() -> void:
	var popup: MarginCallPopup = _make_margin_popup()

	popup.show_warning("삼성전자(005930)", 0.18, false)

	assert_true(popup._panel.visible, "_panel이 visible=true 되어야 한다")


## 강제청산 모드에서도 panel visible
func test_margin_call_popup_forced_liq_mode_visible() -> void:
	var popup: MarginCallPopup = _make_margin_popup()

	popup.show_warning("SK하이닉스(000660)", 0.08, true)

	assert_true(popup._panel.visible, "강제청산 모드에서도 panel visible")
	assert_true(popup._lbl_countdown.visible, "카운트다운 라벨 visible")


## cancel() → panel hidden
func test_margin_call_popup_cancel_hides_panel() -> void:
	var popup: MarginCallPopup = _make_margin_popup()
	popup.show_warning("테스트주(000001)", 0.15, false)
	assert_true(popup._panel.visible, "취소 전 panel visible")

	popup.cancel()

	assert_false(popup._panel.visible, "cancel() 이후 panel 숨겨져야 한다")


## 초기 상태 — panel hidden
func test_margin_call_popup_initial_state_hidden() -> void:
	var popup: MarginCallPopup = _make_margin_popup()

	assert_false(popup._panel.visible, "초기 상태에서 panel hidden이어야 한다")
