extends GutTest
## UI Label.text 검증 — Method 1 (Label 메모리 읽기, 헤드리스 호환)
##
## 목적: 데이터 계층과 화면에 표시되는 텍스트의 일치를 검증한다.
##   - UI가 올바른 필드를 읽는가
##   - FormatUtils.number() / 포맷 문자열이 올바르게 적용되는가
##   - 시그널 수신 후 레이블이 갱신되는가
##
## 헤드리스에서 GPU 없이 Label.text 는 메모리에 보관되므로 읽기 가능.
## 스크린샷 / 텍스처 캡처는 수행하지 않음.
##
## 걷어내기: 이 파일과 .gutconfig.json 에서 tests/integration/ 항목 제거.


# ── Helpers ──

func _reset_autoloads() -> void:
	SaveSystem.active_slot_id = -1
	XpSystem.reset()
	SkillTree.reset()
	SeasonManager.reset()
	CurrencySystem.reset()
	PortfolioManager.reset()


func _add_and_ready(node: Node) -> void:
	add_child(node)
	# _ready() fires at end-of-frame in Godot 4 for dynamically added nodes.
	await get_tree().process_frame


# ── Before / After ──

func before_each() -> void:
	_reset_autoloads()
	CurrencySystem.init_first_season()


func after_each() -> void:
	_reset_autoloads()


# ════════════════════════════════════════════════
# PortfolioView — 레이블 포맷 검증
# ════════════════════════════════════════════════

func test_portfolio_view_total_assets_label_matches_data() -> void:
	## PortfolioView._lbl_total_assets 가 PortfolioManager 요약과 일치하는지 확인.
	# Arrange
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)
	var view: Node = load("res://src/ui/portfolio_view.gd").new()
	await _add_and_ready(view)

	# Act — PortfolioView._ready()가 _refresh()를 즉시 호출하므로 추가 트리거 불필요
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	var expected: String = tr("총 자산: ₩%s") % FormatUtils.number(summary["total_assets"])

	# Assert
	assert_eq(view._lbl_total_assets.text, expected, "_lbl_total_assets 포맷")
	view.queue_free()


func test_portfolio_view_return_rate_label_zero() -> void:
	## 수익률 0.0% → "(+0.0%)" 포맷 확인.
	# Arrange — 신규 게임, 투자 없음 → return_rate = 0.0
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)
	var view: Node = load("res://src/ui/portfolio_view.gd").new()
	await _add_and_ready(view)

	# Assert
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	var expected: String = "(%+.1f%%)" % summary["return_rate"]
	assert_eq(view._lbl_return_rate.text, expected, "_lbl_return_rate 포맷")
	view.queue_free()


func test_portfolio_view_cash_info_no_reserved() -> void:
	## 예약금 없을 때 현금 레이블 포맷: "현금: ₩X | N/M종목"
	# Arrange
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)
	var view: Node = load("res://src/ui/portfolio_view.gd").new()
	await _add_and_ready(view)

	# Act
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	var expected: String = tr("현금: ₩%s | %d/%d종목") % [
		FormatUtils.number(summary["sim_cash"]),
		summary["holding_count"],
		summary["max_holdings"],
	]

	# Assert
	assert_eq(view._lbl_cash_info.text, expected, "_lbl_cash_info 포맷 (예약금 없음)")
	view.queue_free()


func test_portfolio_view_holding_row_quantity_format() -> void:
	## 보유 종목 행: 수량 레이블이 "%d주" 포맷인지 확인.
	# Arrange — 보유 종목 1건 삽입
	var fake_portfolio: Dictionary = {
		"holdings": {
			"005930": {"quantity": 7, "avg_buy_price": 70000, "total_invested": 490000}
		}
	}
	PortfolioManager.load_save_data(fake_portfolio)
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)

	var view: Node = load("res://src/ui/portfolio_view.gd").new()
	await _add_and_ready(view)

	# Act — 보유 행의 두 번째 레이블(index 1)이 수량 표시
	var holdings_container: Node = view._holdings_container
	assert_true(holdings_container.get_child_count() > 0, "보유 행이 렌더링됨")

	var first_row: Node = holdings_container.get_child(0)
	# HBoxContainer 구조: [lbl_stock(0), lbl_qty(1), lbl_price(2), lbl_rate(3), lbl_value(4)]
	var lbl_qty: Label = first_row.get_child(1) as Label

	var expected_qty: String = tr("%d주") % 7
	assert_eq(lbl_qty.text, expected_qty, "수량 레이블 포맷")
	view.queue_free()


func test_portfolio_view_updates_on_valuation_signal() -> void:
	## valuation_updated 시그널 수신 후 레이블이 새 값으로 갱신되는지 확인.
	# Arrange — before_each가 이미 init_first_season() 호출함; 재호출 금지
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)
	var view: Node = load("res://src/ui/portfolio_view.gd").new()
	await _add_and_ready(view)

	# Act — 평가금액 변동 후 시그널 발신으로 갱신 유도 (현금은 유지, 보유 평가액 증가 시뮬레이션)
	var new_total: int = CurrencySystem.get_sim_cash() + 500_000
	PortfolioManager.update_valuation(new_total, 0)
	# valuation_updated는 update_valuation() 내부에서 emit되므로 추가 emit 불필요
	await get_tree().process_frame

	# Assert
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	var expected: String = tr("총 자산: ₩%s") % FormatUtils.number(summary["total_assets"])
	assert_eq(view._lbl_total_assets.text, expected, "갱신 후 _lbl_total_assets")
	view.queue_free()


# ════════════════════════════════════════════════
# StatusBar — 레이블 포맷 검증
# ════════════════════════════════════════════════

func test_status_bar_total_assets_label_matches_data() -> void:
	## on_tick 시그널 수신 후 _lbl_total_assets 가 포트폴리오 요약과 일치하는지 확인.
	# Arrange
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)
	var bar: Node = load("res://src/ui/status_bar.gd").new()
	await _add_and_ready(bar)

	# Act — on_tick emit → _update_row2() → _lbl_total_assets 갱신
	GameClock.on_tick.emit(0, 0, 0)

	# Assert
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	var expected: String = tr("총 자산: ₩%s") % FormatUtils.number(summary["total_assets"])
	assert_eq(bar._lbl_total_assets.text, expected, "_lbl_total_assets 포맷")
	bar.queue_free()


func test_status_bar_cash_label_no_reserved() -> void:
	## 예약금 없을 때 현금 레이블: "시드: ₩X | 보유 N/M"
	# Arrange
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)
	var bar: Node = load("res://src/ui/status_bar.gd").new()
	await _add_and_ready(bar)

	# Act
	GameClock.on_tick.emit(0, 0, 0)

	# Assert
	var cash: int = CurrencySystem.get_sim_cash()
	var holdings_count: int = PortfolioManager.get_all_holdings().size()
	var max_h: int = SkillTree.get_max_holdings()
	var expected: String = tr("시드: ₩%s | 보유 %d/%d") % [
		FormatUtils.number(cash), holdings_count, max_h
	]
	assert_eq(bar._lbl_cash.text, expected, "_lbl_cash 포맷 (예약금 없음)")
	bar.queue_free()


func test_status_bar_season_info_format_after_tick() -> void:
	## on_tick 수신 후 _lbl_season_info 가 GameClock 현재 상태를 올바른 포맷으로 표시하는지 확인.
	## StatusBar._on_tick() 은 시그널 파라미터를 무시하고 GameClock.get_current_day/week() 를 직접 읽음.
	# Arrange
	var bar: Node = load("res://src/ui/status_bar.gd").new()
	await _add_and_ready(bar)

	# Act
	GameClock.on_tick.emit(0, GameClock.get_current_day(), GameClock.get_current_week())

	# Assert — 예상값도 같은 GameClock API에서 도출 (특정 day/week 값에 의존하지 않음)
	var day: int = GameClock.get_current_day()
	var week: int = GameClock.get_current_week()
	var day_names: Array[String] = [tr("월"), tr("화"), tr("수"), tr("목"), tr("금")]
	var day_in_week: int = day % GameClock.DAYS_PER_WEEK
	var day_name: String = day_names[day_in_week] if day_in_week < day_names.size() else "?"
	var expected: String = tr("%d주차 %s요일") % [week + 1, day_name]
	assert_eq(bar._lbl_season_info.text, expected, "_lbl_season_info 포맷")
	bar.queue_free()


func test_status_bar_season_info_reads_game_clock_not_signal_params() -> void:
	## StatusBar 가 시그널 파라미터 대신 GameClock API 를 읽는 설계를 검증.
	## on_tick emit 시 전달한 day/week 값과 관계없이 GameClock.get_current_*() 결과를 표시해야 함.
	# Arrange
	var bar: Node = load("res://src/ui/status_bar.gd").new()
	await _add_and_ready(bar)

	# Act — 임의 파라미터로 시그널 발신
	GameClock.on_tick.emit(99, 99, 99)

	# Assert — 레이블은 GameClock 실제 상태를 반영 (signal param 99 가 아님)
	var day: int = GameClock.get_current_day()
	var week: int = GameClock.get_current_week()
	var day_names: Array[String] = [tr("월"), tr("화"), tr("수"), tr("목"), tr("금")]
	var day_in_week: int = day % GameClock.DAYS_PER_WEEK
	var day_name: String = day_names[day_in_week] if day_in_week < day_names.size() else "?"
	var expected: String = tr("%d주차 %s요일") % [week + 1, day_name]
	assert_eq(bar._lbl_season_info.text, expected, "시그널 파라미터 무시 확인")
	bar.queue_free()


# ════════════════════════════════════════════════
# StockListPanel — 가격/등락률 레이블 포맷 검증
# ════════════════════════════════════════════════

func test_stock_list_panel_price_label_format() -> void:
	## 첫 종목 행의 가격 레이블이 "₩X,XXX" 포맷인지 확인.
	# Arrange
	var panel: Node = load("res://src/ui/stock_list_panel.gd").new()
	await _add_and_ready(panel)
	# on_price_updated(0) 은 _ready() 에서 직접 호출됨 → 레이블 이미 설정됨

	# Act
	var stock_ids: Array[String] = StockDatabase.get_all_stock_ids()
	assert_true(stock_ids.size() > 0, "종목이 1개 이상 존재")

	var first_id: String = stock_ids[0]
	var price: int = PriceEngine.get_current_price(first_id)
	var expected_price_text: String = "₩%s" % FormatUtils.number(price)

	# Assert — row[0], child(2) = price Label
	var first_row: HBoxContainer = panel._row_nodes[0]
	var lbl_price: Label = first_row.get_child(2) as Label
	assert_eq(lbl_price.text, expected_price_text, "가격 레이블 포맷")
	panel.queue_free()


func test_stock_list_panel_change_pct_zero_format() -> void:
	## 등락률 0% → "─+0.0%" 포맷 확인 (전일 종가 == 현재가).
	# Arrange — 신규 시즌 첫 틱: 현재가 == prev_close → 등락률 0%
	var panel: Node = load("res://src/ui/stock_list_panel.gd").new()
	await _add_and_ready(panel)

	# Assert — row[0], child(3) = change Label
	var first_row: HBoxContainer = panel._row_nodes[0]
	var lbl_change: Label = first_row.get_child(3) as Label
	# 가격 미변동 시 arrow="─", format="%s%+.1f%%" → "─+0.0%"
	assert_eq(lbl_change.text, "─+0.0%", "등락률 0% 포맷")
	panel.queue_free()


func test_stock_list_panel_price_updates_on_price_signal() -> void:
	## on_price_updated 시그널 재발신 후 레이블이 PriceEngine 값을 읽는지 확인.
	# Arrange
	var panel: Node = load("res://src/ui/stock_list_panel.gd").new()
	await _add_and_ready(panel)

	# Act — 가격 변동 시뮬레이션: 더티 플래그를 초기화하기 위해 _last_prices 클리어
	panel._last_prices.clear()
	PriceEngine.on_price_updated.emit(1)  # 틱 1로 갱신 트리거

	# Assert — 첫 종목 가격 레이블이 PriceEngine 현재가와 일치
	var stock_ids: Array[String] = StockDatabase.get_all_stock_ids()
	var first_id: String = stock_ids[0]
	var expected_text: String = "₩%s" % FormatUtils.number(PriceEngine.get_current_price(first_id))
	var lbl_price: Label = (panel._row_nodes[0] as HBoxContainer).get_child(2) as Label
	assert_eq(lbl_price.text, expected_text, "price_updated 후 가격 레이블 갱신")
	panel.queue_free()
