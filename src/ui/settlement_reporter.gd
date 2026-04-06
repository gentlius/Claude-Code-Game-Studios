## SettlementReporter — 일일·주간·시즌 정산 팝업 + 순차 큐.
## TradingScreen이 enqueue()로 리포트를 적재하고, settlement_confirmed 시그널로
## 전환 완료를 수신한다. 레벨업이 보류 중이면 needs_level_up 시그널을 먼저 발신.
## See: design/gdd/trading-screen.md §10, §규칙 6 (순차 정산)
class_name SettlementReporter
extends Control

## All reports shown and no pending level-up → caller calls GameClock.confirm_transition().
signal settlement_confirmed
## All reports shown but a level-up is pending → caller shows LevelUpBanner.
signal needs_level_up(data: Dictionary)
## Emitted after a daily popup with XP is dismissed — caller should animate the XP bar.
signal xp_animate_requested

var _settlement_queue: Array[String] = []
var _last_xp_gained: int = 0
var _last_xp_source: String = ""
var _weekly_xp_gained: int = 0
var _pending_level_up: Dictionary = {}
var _season_reveal_step: int = 0
var _season_reveal_timer: Timer

var _panel: PanelContainer
var _lbl_title: Label
var _lbl_body: RichTextLabel
var _btn_confirm: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel()
	XpSystem.on_xp_gained.connect(_on_xp_gained)
	XpSystem.on_level_up.connect(_on_level_up)
	_season_reveal_timer = Timer.new()
	_season_reveal_timer.wait_time = 0.5
	_season_reveal_timer.one_shot = true
	_season_reveal_timer.timeout.connect(_on_season_reveal_tick)
	add_child(_season_reveal_timer)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(460, 380)
	_panel.visible = false
	var style: StyleBoxFlat = ThemeSetup.make_panel_style(ThemeSetup.BG_PANEL, 12, ThemeSetup.BORDER_BRIGHT, 2)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.15)
	style.shadow_size = 8
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)
	_lbl_title = Label.new()
	_lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_title.add_theme_font_size_override("font_size", 22)
	ThemeSetup.style_label_primary(_lbl_title)
	vbox.add_child(_lbl_title)
	vbox.add_child(HSeparator.new())
	_lbl_body = RichTextLabel.new()
	_lbl_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lbl_body.bbcode_enabled = true
	_lbl_body.fit_content = true
	_lbl_body.scroll_active = false
	_lbl_body.add_theme_color_override("default_color", ThemeSetup.TEXT_SECONDARY)
	_lbl_body.add_theme_font_size_override("normal_font_size", 14)
	vbox.add_child(_lbl_body)
	_btn_confirm = Button.new()
	_btn_confirm.text = "확인 Enter"
	ThemeSetup.apply_accent_button(_btn_confirm)
	_btn_confirm.custom_minimum_size.y = 44
	_btn_confirm.add_theme_font_size_override("font_size", 14)
	_btn_confirm.pressed.connect(_confirm)
	vbox.add_child(_btn_confirm)


## TradingScreen calls this when a report type should be shown.
func enqueue(report_type: String) -> void:
	_settlement_queue.append(report_type)


## True when the panel is currently visible.
func is_showing() -> bool:
	return _panel.visible


## Shows next report or finishes settlement sequence.
func show_next() -> void:
	if _settlement_queue.is_empty():
		_panel.visible = false
		if not _pending_level_up.is_empty():
			var data: Dictionary = _pending_level_up.duplicate()
			_pending_level_up = {}
			needs_level_up.emit(data)
			return
		settlement_confirmed.emit()
		return
	var report_type: String = _settlement_queue.pop_front()
	match report_type:
		"daily":  _show_daily()
		"weekly": _show_weekly()
		"season": _show_season()


func _confirm() -> void:
	_season_reveal_timer.stop()
	_season_reveal_step = 0
	_btn_confirm.disabled = false
	_panel.visible = false
	var was_daily_xp: bool = _last_xp_gained > 0 and _last_xp_source == "daily_bonus"
	_last_xp_gained = 0
	_last_xp_source = ""
	if was_daily_xp:
		xp_animate_requested.emit()
	show_next()


func _show_daily() -> void:
	_panel.visible = true
	_lbl_title.text = "일일 정산  Day %d" % (GameClock.get_current_day() + 1)
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	var bbcode: String = _portfolio_summary_section(summary)
	bbcode += _holdings_section(summary)
	bbcode += _daily_trades_section()
	bbcode += _xp_section("daily_bonus")
	_lbl_body.text = bbcode
	_btn_confirm.text = "다음 →  Enter" if not _settlement_queue.is_empty() else "확인  Enter"


func _portfolio_summary_section(summary: Dictionary) -> String:
	var rate: float = summary["return_rate"]
	var c: String = "EB3833" if rate >= 0.0 else "2E6BE6"
	var sign: String = "+" if rate >= 0.0 else ""
	var bbcode: String = ""
	bbcode += "[b]총 자산[/b]  [color=#%s]₩%s[/color]\n" % [c, FormatUtils.number(summary["total_assets"])]
	bbcode += "[b]수익률[/b]   [color=#%s]%s%.2f%%[/color]\n" % [c, sign, rate]
	bbcode += "[b]현  금[/b]   ₩%s\n" % FormatUtils.number(summary["sim_cash"])
	bbcode += "[b]보유종목[/b] %d개\n" % summary["holding_count"]
	return bbcode


func _holdings_section(summary: Dictionary) -> String:
	var holdings: Array[Dictionary] = PortfolioManager.get_all_holdings()
	if holdings.is_empty() or summary["holding_count"] == 0:
		return ""
	var bbcode: String = "\n"
	for h: Dictionary in holdings:
		var stock: StockData = StockDatabase.get_stock(h["stock_id"])
		var name_str: String = "%s(%s)" % [stock.name_ko, stock.stock_id] if stock else h["stock_id"]
		var pnl_pct: float = h.get("unrealized_pnl_pct", 0.0)
		var c: String = "EB3833" if pnl_pct >= 0.0 else "2E6BE6"
		var sign: String = "+" if pnl_pct >= 0.0 else ""
		bbcode += "  %s  [color=#%s]%s%.1f%%[/color]\n" % [name_str, c, sign, pnl_pct]
	return bbcode


func _daily_trades_section() -> String:
	var today_day: int = GameClock.get_current_day()
	var txs: Array[Dictionary] = PortfolioManager.get_transaction_history(100)
	var buys: int = 0
	var sells: int = 0
	var realized: int = 0
	for tx: Dictionary in txs:
		if tx.get("day", -1) == today_day:
			if tx["type"] == "BUY":
				buys += 1
			elif tx["type"] == "SELL":
				sells += 1
				realized += tx.get("realized_pnl", 0)
	if buys == 0 and sells == 0:
		return ""
	var bbcode: String = "\n[b]오늘의 거래[/b]  매수 %d건 · 매도 %d건" % [buys, sells]
	if realized != 0:
		var c: String = "EB3833" if realized > 0 else "2E6BE6"
		bbcode += "\n[b]실현 손익[/b]  [color=#%s]%+d[/color]" % [c, realized]
	return bbcode


func _xp_section(expected_source: String) -> String:
	var gold: String = "D9B320"
	var dim: String = "5A5A66"
	var bbcode: String = "\n\n[color=#%s]━━━ 경험치 ━━━[/color]\n" % gold
	if _last_xp_gained > 0 and _last_xp_source == expected_source:
		if expected_source == "daily_bonus":
			var bd: Dictionary = XpSystem.get_daily_xp_breakdown()
			# Show alpha = player return − market return so the player understands the tier
			var sign: String = "+" if bd["alpha_pct"] >= 0.0 else ""
			bbcode += "[color=#%s]나 %.1f%%  −  시장 %.1f%%  =  알파 %s%.1f%%[/color]\n" % [
				dim,
				bd["player_return_pct"], bd["market_return_pct"],
				sign, bd["alpha_pct"]]
			# Tier bar: 5 segments, highlight active tier
			var tiers: Array[String] = ["< -1%", "-1~0%", "0~1%", "1~3%", "≥ +3%"]
			var tier_bar: String = ""
			for t: String in tiers:
				if t == bd["return_tier"]:
					tier_bar += "[color=#%s][b][%s][/b][/color] " % [gold, t]
				else:
					tier_bar += "[color=#%s]%s[/color] " % [dim, t]
			bbcode += "알파 구간:  " + tier_bar.strip_edges() + "\n"
			bbcode += "[color=#%s]레벨 기본 XP %d  ×  구간 배율 %.1f  =  [b]+%d XP[/b][/color]\n" % [
				gold, bd["base_xp"], bd["multiplier"], bd["total_xp"]]
		else:
			bbcode += "[color=#%s][b]+%d XP[/b] 획득[/color]\n" % [gold, _last_xp_gained]
	else:
		bbcode += "거래 없음 — XP 미부여\n"
	var level: int = XpSystem.get_current_level()
	var cur_threshold: int = XpSystem.get_cumulative_xp_for_level(level)
	var cur_xp: int = XpSystem.get_total_xp() - cur_threshold
	var need_xp: int = XpSystem.get_cumulative_xp_for_level(level + 1) - cur_threshold
	bbcode += "[color=#%s]Lv.%d[/color]  %d / %d XP" % [gold, level, cur_xp, need_xp]
	var sp: int = XpSystem.get_available_skill_points()
	if sp > 0:
		bbcode += "  [color=#%s]SP %d 사용 가능[/color]" % [gold, sp]
	return bbcode


func _show_weekly() -> void:
	_panel.visible = true
	_lbl_title.text = "주간 리포트  Week %d" % (GameClock.get_current_week() + 1)
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	var bbcode: String = _portfolio_summary_section(summary)
	bbcode += _weekly_trades_section()
	bbcode += _holdings_section(summary)
	bbcode += _weekly_theme_hint()
	bbcode += _weekly_xp_section()
	_weekly_xp_gained = 0
	_lbl_body.text = bbcode
	_btn_confirm.text = "다음 →  Enter" if not _settlement_queue.is_empty() else "다음 주  Enter"


func _weekly_trades_section() -> String:
	var day: int = GameClock.get_current_day()
	var week_start: int = day - (GameClock.DAYS_PER_WEEK - 1)
	var all_txs: Array[Dictionary] = PortfolioManager.get_transaction_history(999)
	var buys: int = 0
	var sells: int = 0
	var realized: int = 0
	for tx: Dictionary in all_txs:
		var tx_day: int = tx.get("day", -1)
		if tx_day >= week_start and tx_day <= day:
			if tx["type"] == "BUY":
				buys += 1
			elif tx["type"] == "SELL":
				sells += 1
				realized += tx.get("realized_pnl", 0)
	var bbcode: String = "\n[b]━━━ 주간 거래 요약 ━━━[/b]\n"
	bbcode += "[b]매수[/b] %d건  [b]매도[/b] %d건  [b]합계[/b] %d건\n" % [buys, sells, buys + sells]
	if realized != 0:
		var c: String = "EB3833" if realized > 0 else "2E6BE6"
		bbcode += "[b]주간 실현 손익[/b]  [color=#%s]₩%s[/color]\n" % [c, FormatUtils.number(realized)]
	else:
		bbcode += "[b]주간 실현 손익[/b]  ₩0\n"
	return bbcode


func _weekly_theme_hint() -> String:
	var theme: Dictionary = NewsEventSystem.get_season_theme()
	if theme.is_empty():
		return ""
	var hint: String = theme.get("hint_text", "")
	if hint.is_empty():
		return ""
	return "\n[b]━━━ 다음 주 시장 전망 ━━━[/b]\n[color=#D9B320]💡 %s[/color]\n" % hint


func _weekly_xp_section() -> String:
	var gold: String = "D9B320"
	var bbcode: String = "\n[color=#%s]━━━ 경험치 ━━━[/color]\n" % gold
	if _weekly_xp_gained > 0:
		bbcode += "[color=#%s][b]+%d XP[/b] 주간 획득[/color]\n" % [gold, _weekly_xp_gained]
	else:
		bbcode += "거래 없음 — XP 미부여\n"
	var level: int = XpSystem.get_current_level()
	var cur_threshold: int = XpSystem.get_cumulative_xp_for_level(level)
	var cur_xp: int = XpSystem.get_total_xp() - cur_threshold
	var need_xp: int = XpSystem.get_cumulative_xp_for_level(level + 1) - cur_threshold
	bbcode += "[color=#%s]Lv.%d[/color]  %d / %d XP" % [gold, level, cur_xp, need_xp]
	var sp: int = XpSystem.get_available_skill_points()
	if sp > 0:
		bbcode += "  [color=#%s]SP %d 사용 가능[/color]" % [gold, sp]
	return bbcode


func _show_season() -> void:
	_panel.visible = true
	_lbl_title.text = "시즌 종료"
	var summary: Dictionary = PortfolioManager.get_portfolio_summary()
	_lbl_body.text = _season_grade_header(summary["return_rate"]) \
		+ _portfolio_summary_section(summary) \
		+ _season_trades_section() \
		+ _season_xp_base_line()
	_btn_confirm.text = "다음 시즌  Enter"
	_btn_confirm.disabled = true
	_season_reveal_step = 0
	_season_reveal_timer.start()


func _season_xp_base_line() -> String:
	var gold: String = "D9B320"
	var bd: Dictionary = XpSystem.get_season_xp_breakdown()
	if bd.is_empty():
		return ""
	return "\n[color=#%s]━━━ 시즌 XP 정산 ━━━[/color]\n[color=#%s]시즌 완주 보너스:  +%d XP[/color]\n" % [
		gold, gold, bd.get("base_xp", 0)]


func _on_season_reveal_tick() -> void:
	if not _panel.visible:
		return
	var gold: String = "D9B320"
	var bd: Dictionary = XpSystem.get_season_xp_breakdown()
	_season_reveal_step += 1
	match _season_reveal_step:
		1:
			var rank: int = bd.get("final_rank", 0)
			_lbl_body.text += "[color=#%s]순위 보너스 (%d위):  +%d XP[/color]\n" % [
				gold, rank, bd.get("rank_bonus", 0)]
			_season_reveal_timer.start()
		2:
			var ret_pct: float = bd.get("season_return_pct", 0.0)
			var sign: String = "+" if ret_pct >= 0.0 else ""
			_lbl_body.text += "[color=#%s]수익률 보너스 (%s%.1f%%):  +%d XP[/color]\n" % [
				gold, sign, ret_pct, bd.get("return_bonus", 0)]
			_season_reveal_timer.start()
		3:
			_lbl_body.text += "[color=#%s]─────────────────────────────[/color]\n" % gold
			_lbl_body.text += "[color=#%s][b]총 시즌 XP:  +%d XP[/b][/color]\n" % [
				gold, bd.get("total_xp", 0)]
			var level: int = XpSystem.get_current_level()
			var cur_threshold: int = XpSystem.get_cumulative_xp_for_level(level)
			var cur_xp: int = XpSystem.get_total_xp() - cur_threshold
			var need_xp: int = XpSystem.get_cumulative_xp_for_level(level + 1) - cur_threshold
			_lbl_body.text += "[color=#%s]Lv.%d[/color]  %d / %d XP" % [gold, level, cur_xp, need_xp]
			var sp: int = XpSystem.get_available_skill_points()
			if sp > 0:
				_lbl_body.text += "  [color=#%s]SP %d 사용 가능[/color]" % [gold, sp]
			_btn_confirm.disabled = false
			xp_animate_requested.emit()


func _season_grade_header(rate: float) -> String:
	var grade: String
	var c: String
	if rate >= 20.0:
		grade = "S"; c = "FFD700"
	elif rate >= 10.0:
		grade = "A"; c = "EB3833"
	elif rate >= 0.0:
		grade = "B"; c = "5A5A66"
	elif rate >= -10.0:
		grade = "C"; c = "2E6BE6"
	else:
		grade = "D"; c = "2E6BE6"
	return "[center][color=#%s][font_size=36][b]%s[/b][/font_size][/color][/center]\n\n" % [c, grade]


func _season_trades_section() -> String:
	var all_txs: Array[Dictionary] = PortfolioManager.get_transaction_history(999)
	var total_realized: int = 0
	for tx: Dictionary in all_txs:
		if tx["type"] == "SELL":
			total_realized += tx.get("realized_pnl", 0)
	var bbcode: String = "[b]총 거래[/b]    %d건\n" % all_txs.size()
	if total_realized != 0:
		var c: String = "EB3833" if total_realized > 0 else "2E6BE6"
		bbcode += "[b]실현 손익[/b]  [color=#%s]%+d[/color]\n" % [c, total_realized]
	return bbcode


func _on_xp_gained(amount: int, _new_total: int, source: String) -> void:
	_last_xp_gained = amount
	_last_xp_source = source
	if source == "daily_bonus":
		_weekly_xp_gained += amount


func _on_level_up(new_level: int, _skill_points: int) -> void:
	if _pending_level_up.is_empty():
		_pending_level_up = {"old_level": new_level - 1, "new_level": new_level, "sp": 1}
	else:
		_pending_level_up["new_level"] = new_level
		_pending_level_up["sp"] += 1


## Called by TradingScreen for Enter/Escape keyboard shortcut on settlement screen.
func confirm_current() -> void:
	_confirm()
