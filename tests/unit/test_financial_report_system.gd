## Tests for FinancialReportSystem — ADR-027 Phase D.
## Computation logic moved to C++ PriceKernel; this file tests GDScript-side methods.
## Covers AC-FR-01, AC-FR-02, save/load API contract.
extends GutTest


# ── Setup / Teardown ─────────────────────────────────────────────────────────

func before_each() -> void:
	FinancialReportSystem.reset()


# ── AC-FR-01: is_report_season() — 주기 판별 ─────────────────────────────────

func test_is_report_season_returns_false_before_first_cycle() -> void:
	# Seasons 1–3 never report (first cycle hasn't ended)
	assert_false(FinancialReportSystem.is_report_season(1), "시즌 1 미보고")
	assert_false(FinancialReportSystem.is_report_season(2), "시즌 2 미보고")
	assert_false(FinancialReportSystem.is_report_season(3), "시즌 3 미보고")


func test_is_report_season_returns_true_on_cycle_boundary() -> void:
	assert_true(FinancialReportSystem.is_report_season(4),  "시즌 4 보고")
	assert_true(FinancialReportSystem.is_report_season(7),  "시즌 7 보고")
	assert_true(FinancialReportSystem.is_report_season(10), "시즌 10 보고")
	assert_true(FinancialReportSystem.is_report_season(13), "시즌 13 보고")


func test_is_report_season_returns_false_between_boundaries() -> void:
	assert_false(FinancialReportSystem.is_report_season(5), "시즌 5 미보고")
	assert_false(FinancialReportSystem.is_report_season(6), "시즌 6 미보고")
	assert_false(FinancialReportSystem.is_report_season(8), "시즌 8 미보고")
	assert_false(FinancialReportSystem.is_report_season(9), "시즌 9 미보고")


# ── AC-FR-02: get_report_type() — 보고서 타입 시퀀스 ─────────────────────────

func test_get_report_type_follows_sequence() -> void:
	assert_eq(FinancialReportSystem.get_report_type(4),  "Q1",     "시즌 4 → Q1")
	assert_eq(FinancialReportSystem.get_report_type(7),  "H1",     "시즌 7 → H1")
	assert_eq(FinancialReportSystem.get_report_type(10), "Q3",     "시즌 10 → Q3")
	assert_eq(FinancialReportSystem.get_report_type(13), "Annual", "시즌 13 → Annual")


func test_get_report_type_cycles_back() -> void:
	assert_eq(FinancialReportSystem.get_report_type(16), "Q1", "시즌 16 → Q1 (순환)")


func test_get_report_type_empty_for_non_report_season() -> void:
	assert_eq(FinancialReportSystem.get_report_type(1), "", "비보고 시즌 → 빈 문자열")
	assert_eq(FinancialReportSystem.get_report_type(5), "", "비보고 시즌 → 빈 문자열")


# ── reset() ───────────────────────────────────────────────────────────────────

func test_reset_is_callable_without_error() -> void:
	# ADR-027 Phase D: GDScript state removed — reset() is a no-op that delegates to C++.
	FinancialReportSystem.reset()
	pass_test("reset() 호출 오류 없음")


# ── get_save_data() / load_save_data() ────────────────────────────────────────

func test_get_save_data_returns_dictionary() -> void:
	# Phase D: save data wraps C++ kernel state.
	# PriceEngine may not be fully initialized in headless tests → expect a Dictionary.
	var data: Variant = FinancialReportSystem.get_save_data()
	assert_true(data is Dictionary, "get_save_data() returns Dictionary")


func test_load_save_data_with_empty_dict_is_no_op() -> void:
	# Empty dict → no crash, no state change.
	FinancialReportSystem.load_save_data({})
	pass_test("빈 dict → 오류 없음")


func test_schedule_quarterly_events_is_callable() -> void:
	# No-op in Phase D but must not error (signal handler compatibility).
	FinancialReportSystem.schedule_quarterly_events(4)
	pass_test("schedule_quarterly_events() 호출 오류 없음")
