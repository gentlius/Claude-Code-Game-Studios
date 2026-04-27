## GUT unit tests for SectorComparisonView — A4 섹터 비교 분석 뷰.
## Implements: design/gdd/sector-comparison.md §8 AC-01 ~ AC-09
## AC-10 (E2E) is in tests/integration/test_sector_comparison_integration.gd
extends GutTest

# ── Setup / Teardown ──

func before_each() -> void:
	EtfManager._load_config()
	EtfManager._init_season()
	GameClock._market_state = GameClock.MarketState.MARKET_OPEN
	# Default: all relevant skills unlocked; individual tests lock as needed
	SkillTree._unlocked_skills["A3"] = true
	SkillTree._unlocked_skills["A4"] = true
	SkillTree._unlocked_skills["P3"] = true


func after_each() -> void:
	EtfManager.reset()
	SkillTree._unlocked_skills.erase("A4")
	SkillTree._unlocked_skills.erase("P3")


# ── Helper: create a fresh SectorComparisonView in the test tree ──

func _make_view() -> SectorComparisonView:
	var view: SectorComparisonView = SectorComparisonView.new()
	add_child_autofree(view)
	return view


# ── AC-01: A4 미해금 시 잠금 레이블 표시 ──

func test_tab_locked_without_a4() -> void:
	# Arrange: A4 NOT unlocked
	SkillTree._unlocked_skills.erase("A4")

	# Act
	var view: SectorComparisonView = _make_view()

	# Assert: locked label visible, main panel hidden
	assert_true(view._locked_label.visible,
		"잠금 레이블이 A4 미해금 시 표시돼야 한다")
	assert_false(view._main_panel.visible,
		"메인 패널이 A4 미해금 시 숨겨져야 한다")


# ── AC-02: A4 해금 후 11개 섹터 전부 표시 ──

func test_all_11_sectors_displayed() -> void:
	# Arrange: A4 unlocked (default in before_each)
	# Act
	var view: SectorComparisonView = _make_view()

	# Assert: main panel visible, 11 rows
	assert_true(view._main_panel.visible,
		"A4 해금 후 메인 패널이 표시돼야 한다")
	assert_eq(view._rows_container.get_child_count(), 11,
		"11개 섹터 행이 표시돼야 한다")


# ── AC-03: 시즌 수익률 내림차순 정렬 ──

func test_sorted_by_season_return() -> void:
	# Arrange: set distinct ETF prices so season returns differ
	EtfManager._etf_prices["ETF_반도체"]  = 55000.0   # +10%
	EtfManager._etf_prices["ETF_2차전지"] = 52500.0   # +5%
	EtfManager._etf_prices["ETF_바이오"]  = 48000.0   # -4%

	# Act: default sort is SEASON
	var view: SectorComparisonView = _make_view()

	# Assert: first row rank label = "1", and its sector should be 반도체 (highest return)
	assert_eq(view._sort_mode, SectorComparisonView.SortMode.SEASON,
		"기본 정렬 모드는 SEASON이어야 한다")
	# Row 0 → highest return sector
	var first_row: HBoxContainer = view._rows_container.get_child(0) as HBoxContainer
	assert_not_null(first_row, "첫 번째 행이 존재해야 한다")
	var rank_lbl: Label = first_row.get_child(0) as Label
	assert_eq(rank_lbl.text, "1", "첫 번째 행의 순위는 1이어야 한다")
	# Name VBox → first child is sector name label
	var name_vbox: VBoxContainer = first_row.get_child(1) as VBoxContainer
	var sector_lbl: Label = name_vbox.get_child(0) as Label
	assert_eq(sector_lbl.text, "반도체", "최고 시즌 수익률 섹터가 1위여야 한다")


# ── AC-04: 오늘 수익률 기준으로 정렬 토글 ──

func test_toggle_sort_today_return() -> void:
	# Arrange: 반도체 has better season return but worse today return
	EtfManager._etf_prices["ETF_반도체"]  = 55000.0  # season +10%
	EtfManager._etf_prices["ETF_2차전지"] = 52500.0  # season +5%
	# Set open prices so today returns differ inversely
	EtfManager._etf_open_prices["ETF_반도체"]  = 54000.0  # today ≈ +1.9%
	EtfManager._etf_open_prices["ETF_2차전지"] = 50000.0  # today = +5.0%

	var view: SectorComparisonView = _make_view()
	# Sanity: 반도체 is first in SEASON mode
	var first_season: Label = (view._rows_container.get_child(0) as HBoxContainer).get_child(1).get_child(0) as Label
	assert_eq(first_season.text, "반도체", "SEASON 모드에서 반도체가 1위여야 한다")

	# Act: toggle to TODAY mode
	view._set_sort_mode(SectorComparisonView.SortMode.TODAY)

	# Assert: now 2차전지 should be first (today = +5%)
	# Note: queue_free() is deferred so we check _sorted_etf_ids instead of get_child()
	assert_eq(view._sorted_etf_ids[0], "ETF_2차전지", "TODAY 모드에서 2차전지가 1위여야 한다")
	assert_eq(view._sort_mode, SectorComparisonView.SortMode.TODAY,
		"정렬 모드가 TODAY로 전환돼야 한다")


# ── AC-05: 섹터 클릭 → 드릴다운 표시 ──

func test_drilldown_shows_sector_stocks() -> void:
	# Arrange
	var view: SectorComparisonView = _make_view()
	assert_false(view._drilldown_panel.visible, "드릴다운은 처음에 숨겨져야 한다")

	# Act: open drilldown for 반도체
	view._toggle_drilldown("반도체")

	# Assert
	assert_true(view._drilldown_panel.visible, "드릴다운 패널이 표시돼야 한다")
	assert_eq(view._drilldown_sector, "반도체", "열린 섹터가 반도체여야 한다")
	# Title should contain the sector name
	assert_true(view._lbl_drilldown_title.text.find("반도체") >= 0,
		"드릴다운 타이틀에 섹터명이 포함돼야 한다")
	# Stock rows + summary line — at least 1 child (summary)
	assert_gt(view._drilldown_stocks_container.get_child_count(), 0,
		"드릴다운에 종목 또는 요약 행이 있어야 한다")


func test_drilldown_closes_on_second_click() -> void:
	var view: SectorComparisonView = _make_view()
	view._toggle_drilldown("반도체")
	assert_true(view._drilldown_panel.visible)

	# Act: click same sector again
	view._toggle_drilldown("반도체")

	assert_false(view._drilldown_panel.visible, "동일 섹터 재클릭 시 드릴다운이 닫혀야 한다")
	assert_eq(view._drilldown_sector, "", "닫힌 후 drilldown_sector가 빈 문자열이어야 한다")


# ── AC-06: P3 미해금 시 ETF 가격 컬럼 "—" 표시 ──

func test_etf_price_hidden_without_p3() -> void:
	# Arrange: P3 NOT unlocked
	SkillTree._unlocked_skills.erase("P3")

	# Act
	var view: SectorComparisonView = _make_view()

	# Assert: every row's last label (ETF price column) should show "—"
	for i: int in view._rows_container.get_child_count():
		var row: HBoxContainer = view._rows_container.get_child(i) as HBoxContainer
		var etf_lbl: Label = row.get_child(row.get_child_count() - 1) as Label
		assert_eq(etf_lbl.text, "—",
			"P3 미해금 시 행 %d의 ETF 가격이 '—'이어야 한다" % i)


# ── AC-07: P3 해금 후 ETF 가격 표시 ──

func test_etf_price_shown_with_p3() -> void:
	# Arrange: P3 unlocked (default), set a distinct ETF price
	EtfManager._etf_prices["ETF_반도체"] = 53250.0

	# Act
	var view: SectorComparisonView = _make_view()

	# Assert: find the 반도체 row and check its ETF price label is not "—"
	var found: bool = false
	for i: int in view._rows_container.get_child_count():
		var row: HBoxContainer = view._rows_container.get_child(i) as HBoxContainer
		var name_vbox: VBoxContainer = row.get_child(1) as VBoxContainer
		var sector_lbl: Label = name_vbox.get_child(0) as Label
		if sector_lbl.text == "반도체":
			var etf_lbl: Label = row.get_child(row.get_child_count() - 1) as Label
			assert_ne(etf_lbl.text, "—",
				"P3 해금 시 ETF 가격이 '—'이 아니어야 한다")
			assert_true(etf_lbl.text.find("원") >= 0,
				"P3 해금 시 ETF 가격에 '원' 단위가 포함돼야 한다")
			found = true
			break
	assert_true(found, "반도체 행을 찾아야 한다")


# ── AC-08: 섹터 수익률 = EtfManager.get_etf_return 값과 일치 ──

func test_sector_return_matches_etf_manager() -> void:
	# Arrange: set a specific price for 금융 ETF
	EtfManager._etf_prices["ETF_금융"] = 51500.0
	var expected_return: float = EtfManager.get_etf_return("ETF_금융")  # = 0.03

	# Act: view reads data via get_etf_return
	var view: SectorComparisonView = _make_view()
	view.refresh()

	# Assert: check the displayed return text for 금융 sector
	# Format: "+X.X%" or "-X.X%"
	var expected_text: String = "+3.0%"  # 51500/50000 - 1 = 0.03 → +3.0%
	assert_almost_eq(expected_return, 0.03, 0.001, "EtfManager.get_etf_return('ETF_금융') ≈ 0.03")
	# Find 금융 row and verify season return label
	for i: int in view._rows_container.get_child_count():
		var row: HBoxContainer = view._rows_container.get_child(i) as HBoxContainer
		var name_vbox: VBoxContainer = row.get_child(1) as VBoxContainer
		var sector_lbl: Label = name_vbox.get_child(0) as Label
		if sector_lbl.text == "금융":
			# season return label is the 4th child (index 3): rank(0), name_vbox(1), today(2), season(3), etf(4)
			var season_lbl: Label = row.get_child(3) as Label
			assert_eq(season_lbl.text, expected_text,
				"시즌 수익률 레이블이 EtfManager 값과 일치해야 한다")
			break


# ── AC-09: 당일 수익률 = 장 시작 스냅샷 대비 현재 변동률 ──

func test_today_return_from_open_snapshot() -> void:
	# Arrange: set open price and current price for 게임 ETF
	EtfManager._etf_open_prices["ETF_게임"] = 50000.0
	EtfManager._etf_prices["ETF_게임"]      = 51000.0
	# Expected today return: 51000/50000 - 1 = 0.02 → "+2.0%"

	# Act
	var view: SectorComparisonView = _make_view()

	# Assert: find 게임 row's today return label
	for i: int in view._rows_container.get_child_count():
		var row: HBoxContainer = view._rows_container.get_child(i) as HBoxContainer
		var name_vbox: VBoxContainer = row.get_child(1) as VBoxContainer
		var sector_lbl: Label = name_vbox.get_child(0) as Label
		if sector_lbl.text == "게임":
			# today return label is 3rd child (index 2)
			var today_lbl: Label = row.get_child(2) as Label
			assert_eq(today_lbl.text, "+2.0%",
				"당일 수익률이 장 시작 스냅샷 대비 +2.0%여야 한다")
			break


func test_today_return_zero_when_no_open_snapshot() -> void:
	# Arrange: open price is 0 (uninitialized / first tick of season)
	EtfManager._etf_open_prices["ETF_게임"] = 0.0

	var view: SectorComparisonView = _make_view()

	# Assert: today return shown as 0.0% when open_price <= 0 (GDD §5 Edge Case)
	for i: int in view._rows_container.get_child_count():
		var row: HBoxContainer = view._rows_container.get_child(i) as HBoxContainer
		var name_vbox: VBoxContainer = row.get_child(1) as VBoxContainer
		var sector_lbl: Label = name_vbox.get_child(0) as Label
		if sector_lbl.text == "게임":
			var today_lbl: Label = row.get_child(2) as Label
			assert_eq(today_lbl.text, "+0.0%",
				"open_price=0일 때 당일 수익률은 0.0%이어야 한다 (GDD §5)")
			break


# ── Same-return tiebreak: sector name alphabetical (GDD §5) ──

func test_same_return_tiebreak_by_sector_name() -> void:
	# Arrange: all ETFs at same price (they start at 50000 after _init_season)
	# All season returns = 0.0, all today returns = 0.0
	# Expected order: alphabetical by Korean sector name
	var view: SectorComparisonView = _make_view()

	var sector_names: Array[String] = []
	for i: int in view._rows_container.get_child_count():
		var row: HBoxContainer = view._rows_container.get_child(i) as HBoxContainer
		var name_vbox: VBoxContainer = row.get_child(1) as VBoxContainer
		sector_names.append((name_vbox.get_child(0) as Label).text)

	# Verify the list is in ascending Korean alphabetical order
	for i: int in range(sector_names.size() - 1):
		assert_true(sector_names[i] <= sector_names[i + 1],
			"동일 수익률 시 가나다순 정렬: '%s' <= '%s'" % [sector_names[i], sector_names[i + 1]])
