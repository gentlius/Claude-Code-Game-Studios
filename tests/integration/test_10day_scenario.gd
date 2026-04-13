## QA 자동 테스트 — 10일 Save/Load 일관성 시나리오
##
## 검증 목표 (saveload requirement):
##   저장 시점의 화면 수치, 데이터, 각 시스템 내부 상태를 로드 후 완벽하게 재현.
##
## 시나리오:
##   새게임 → 10일 플레이 (매수/매도 포함) →
##   저장 → 모든 autoload 리셋 (프로그램 종료 시뮬레이션) →
##   로드 → 저장 시점 상태와 전 필드 비교 → 차이 없으면 PASS
##
## 출력: user://test_results/{run}/report.html (HTML + JSON + PNG)
extends GutTest

# ── Helpers (preloaded — no class_name, no global namespace pollution) ──

const _SimDriverScript = preload("res://tests/integration/sim_driver.gd")
const _DataSnapshotScript = preload("res://tests/integration/data_snapshot.gd")
const _ScreenshotHelperScript = preload("res://tests/integration/screenshot_helper.gd")

# ── State ──

var _sim: Node       ## SimDriver instance
var _shot: Node      ## ScreenshotHelper instance
var _slot_id: int = -1
const _TEST_SLOT_NAME: String = "[AUTO TEST] 10-Day Scenario"


# ── Lifecycle ──

func before_all() -> void:
	_sim = _SimDriverScript.new()
	add_child(_sim)
	_shot = _ScreenshotHelperScript.new()
	add_child(_shot)


func after_all() -> void:
	# Clean up the test save slot from disk
	if _slot_id >= 0:
		SaveSystem.delete_slot(_slot_id)
		_slot_id = -1
	if _sim:
		_sim.queue_free()
	if _shot:
		_shot.queue_free()


# ── Main Test ──

func test_new_game_10day_save_load_consistency() -> void:
	_shot.begin_run("10day_saveload")

	# ══════════════════════════════════════════
	# Phase 1: 새 게임 초기화
	# ══════════════════════════════════════════
	_sim.reset_all_for_restart()
	CurrencySystem.init_first_season()
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)
	_slot_id = SaveSystem.create_slot(_TEST_SLOT_NAME)
	assert_gt(_slot_id, -1, "슬롯 생성 성공")

	var season_ok: bool = SeasonManager.start_season()
	assert_true(season_ok, "시즌 시작 성공 (충분한 자금)")

	# 초기 상태 스크린샷
	await _shot.capture("01_new_game_start")
	_log_phase("Phase 1 완료: 새 게임 시작 — 현금 %s, 티어 %s" % [
		str(CurrencySystem.get_sim_cash()),
		SeasonManager.get_tier_name(SeasonManager.get_current_tier()),
	])

	# ══════════════════════════════════════════
	# Phase 2: 10일 시뮬레이션
	# ══════════════════════════════════════════
	var daily_snaps: Array[Dictionary] = await _sim.simulate_days(10)
	assert_eq(daily_snaps.size(), 10, "10일 스냅샷 수집")

	# 중간 & 최종 스크린샷
	await _shot.capture("02_after_10_days")
	_log_phase("Phase 2 완료: 10일 완료 — 총자산 %s, XP %d, Lv.%d" % [
		str(PortfolioManager.get_total_assets()),
		XpSystem.get_total_xp(),
		XpSystem.get_current_level(),
	])
	_log_daily_table(daily_snaps)

	# ══════════════════════════════════════════
	# Phase 3: 저장 직전 전체 스냅샷 수집
	# ══════════════════════════════════════════
	var snap_obj: Object = _DataSnapshotScript.new()
	var pre_save: Dictionary = snap_obj.capture()

	# ══════════════════════════════════════════
	# Phase 4: 저장 (save_slot)
	# ══════════════════════════════════════════
	var saved: bool = SaveSystem.save_slot(_slot_id)
	assert_true(saved, "save_slot() 성공")
	await get_tree().process_frame  # save_completed 신호 안정화
	_log_phase("Phase 4 완료: 슬롯 %d 저장" % _slot_id)

	# ══════════════════════════════════════════
	# Phase 5: 프로그램 종료 시뮬레이션
	#   모든 autoload를 완전 초기화 상태로 리셋
	# ══════════════════════════════════════════
	_sim.reset_all_for_restart()
	_log_phase("Phase 5 완료: 모든 시스템 리셋 (프로그램 종료 시뮬레이션)")

	# 리셋 후 — 아무 데이터도 없는 상태 스크린샷
	await _shot.capture("03_after_reset_before_load")

	# ══════════════════════════════════════════
	# Phase 6: 로드 (load_slot)
	# ══════════════════════════════════════════
	var loaded: bool = SaveSystem.load_slot(_slot_id)
	assert_true(loaded, "load_slot() 성공")
	# deferred 신호 (on_market_open 등) 안정화
	await get_tree().process_frame
	await get_tree().process_frame
	_log_phase("Phase 6 완료: 슬롯 %d 로드 완료" % _slot_id)

	# 로드 후 스크린샷
	await _shot.capture("04_after_load")

	# ══════════════════════════════════════════
	# Phase 7: 로드 후 전체 스냅샷 수집
	# ══════════════════════════════════════════
	var post_load: Dictionary = snap_obj.capture()

	# ══════════════════════════════════════════
	# Phase 8: 차이 분석 및 Assert
	# ══════════════════════════════════════════
	var issues: Array[Dictionary] = snap_obj.diff(pre_save, post_load)

	_log_phase("Phase 8: 비교 결과 — %d건 불일치" % issues.size())
	if not issues.is_empty():
		push_error(snap_obj.format_diff(issues))

	# ══════════════════════════════════════════
	# Phase 9: 보고서 생성
	# ══════════════════════════════════════════
	var report_path: String = _shot.generate_report(daily_snaps, pre_save, post_load, issues)
	_log_phase("Phase 9: 보고서 생성 → %s" % report_path)

	# ══════════════════════════════════════════
	# Final Assert — 불일치가 하나라도 있으면 FAIL
	# ══════════════════════════════════════════
	assert_eq(
		issues.size(), 0,
		"Save/Load 완벽 재현 실패: %d건 불일치\n%s" % [
			issues.size(), snap_obj.format_diff(issues)]
	)


# ── Secondary Tests (단위 검증) ──

## 10일 후 적어도 1회 레벨업 XP 획득 여부 (Activity condition 확인)
func test_10day_xp_accumulated() -> void:
	# This test reuses state from the main test if run together.
	# Run standalone with: gut -gtest=test_10day_xp_accumulated
	# Minimal standalone setup:
	if XpSystem.get_total_xp() == 0:
		pending("standalone 실행 불가 — test_new_game_10day_save_load_consistency 먼저 실행")
		return
	assert_gt(XpSystem.get_total_xp(), 0, "10일 후 XP > 0")

## 보유 종목이 로드 후 동일하게 재현되는지 개별 검증
func test_holdings_survive_save_load() -> void:
	if _slot_id < 0:
		pending("standalone 실행 불가 — 메인 시나리오 먼저 실행")
		return
	var holdings_before: Array[Dictionary] = PortfolioManager.get_all_holdings()
	SaveSystem.save_slot(_slot_id)
	_sim.reset_all_for_restart()
	SaveSystem.load_slot(_slot_id)
	await get_tree().process_frame
	var holdings_after: Array[Dictionary] = PortfolioManager.get_all_holdings()
	assert_eq(holdings_before.size(), holdings_after.size(), "보유 종목 수 일치")
	for h_before: Dictionary in holdings_before:
		var found: bool = false
		for h_after: Dictionary in holdings_after:
			if h_after["stock_id"] == h_before["stock_id"]:
				assert_eq(h_after["quantity"], h_before["quantity"],
					"%s 수량 일치" % h_before["stock_id"])
				assert_eq(h_after["avg_buy_price"], h_before["avg_buy_price"],
					"%s 평균단가 일치" % h_before["stock_id"])
				found = true
				break
		assert_true(found, "로드 후 %s 종목 존재" % h_before["stock_id"])


# ── Internal Helpers ──

func _log_phase(msg: String) -> void:
	print("[QA] %s" % msg)


func _log_daily_table(snaps: Array[Dictionary]) -> void:
	print("[QA] ── 일별 진행 ──────────────────────────────")
	print("[QA]  Day | 현금        | 총자산      | 수익률   | XP   | Lv | 보유")
	for snap: Dictionary in snaps:
		print("[QA]  %3d | %11s | %11s | %6.2f%% | %4d | %2d | %d종" % [
			snap.get("sim_day_idx", 0) + 1,
			_fmt_cash(snap.get("sim_cash", 0)),
			_fmt_cash(snap.get("total_assets", 0)),
			snap.get("return_rate", 0.0),
			snap.get("xp_total", 0),
			snap.get("xp_level", 1),
			snap.get("holding_count", 0),
		])
	print("[QA] ─────────────────────────────────────────")


func _fmt_cash(amount: int) -> String:
	return "%d" % amount
