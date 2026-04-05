## LeagueScreen — F2 탭. 티어·순위·수익률·리더보드 대시보드.
## league-ui.md AC-08~AC-15 구현. UI는 계산하지 않고 SeasonManager 게터를 읽는다.
## See: design/gdd/league-ui.md, docs/architecture/006-tab-scene-ownership.md
extends Control

# ── Constants (league-ui.md §7 Tuning Knobs) ──

const LEADERBOARD_FIXED_ROWS: int   = 10
const LEADERBOARD_CONTEXT_RANGE: int = 2
const MERGE_THRESHOLD: int          = LEADERBOARD_FIXED_ROWS + LEADERBOARD_CONTEXT_RANGE

# Colors
const COLOR_POSITIVE: Color  = Color(0.2, 0.85, 0.4, 1.0)
const COLOR_NEGATIVE: Color  = Color(0.95, 0.3, 0.3, 1.0)
const COLOR_NEUTRAL: Color   = Color(0.7, 0.7, 0.7, 1.0)
const COLOR_PLAYER_ROW: Color = Color(0.18, 0.28, 0.45, 1.0)
const COLOR_SEPARATOR: Color  = Color(0.25, 0.25, 0.28, 1.0)
const COLOR_BG_PANEL: Color   = Color(0.10, 0.10, 0.11, 1.0)
const COLOR_BG_CONTENT: Color = Color(0.08, 0.08, 0.09, 1.0)

# ── Node References ──

var _state_layer: Control          ## 상태별 전환 루트 (PRE_SEASON / FREE_MARKET / MAIN)
var _pre_season_panel: Control
var _free_market_panel: Control
var _main_panel: Control

## 좌측 패널 라벨
var _lbl_tier_name: Label
var _lbl_tier_rank: Label
var _lbl_season_return: Label
var _lbl_season_value: Label
var _lbl_weekly_return: Label
var _lbl_weekly_rank: Label
var _lbl_weekly_prize_status: Label

## 우측 리더보드
var _leaderboard_container: VBoxContainer
var _global_rank_label: Label


func _ready() -> void:
	anchor_right  = 1.0
	anchor_bottom = 1.0
	_build_ui()
	_refresh()

	GameClock.on_tick.connect(_on_tick)
	SeasonManager.on_season_started.connect(func(_t, _f) -> void: _refresh())
	SeasonManager.on_season_ended.connect(func(_r, _f, _p) -> void: _refresh())


func _exit_tree() -> void:
	if GameClock.on_tick.is_connected(_on_tick):
		GameClock.on_tick.disconnect(_on_tick)


# ── Refresh ──

func _on_tick(_tick: int, _day: int, _week: int) -> void:
	_refresh()


func _refresh() -> void:
	if not SeasonManager.is_season_active():
		_show_state("pre_season")
		return

	if SeasonManager.get_is_free_market():
		_show_state("free_market")
		return

	_show_state("main")
	_update_left_panel()
	_update_leaderboard()


func _show_state(state: String) -> void:
	_pre_season_panel.visible  = (state == "pre_season")
	_free_market_panel.visible = (state == "free_market")
	_main_panel.visible        = (state == "main")


# ── Left Panel ──

func _update_left_panel() -> void:
	var tier: int    = SeasonManager.get_current_tier()
	var tier_name: String = SeasonManager.get_tier_name(tier)
	var tier_rank: int    = SeasonManager.get_tier_rank()
	var season_pct: float = SeasonManager.get_season_return_pct()
	var weekly_pct: float = SeasonManager.get_weekly_return_pct()
	var weekly_fills: int = SeasonManager.get_weekly_trade_count()

	_lbl_tier_name.text = tier_name

	var tier_participants: int = _estimate_tier_participants(tier)
	_lbl_tier_rank.text = "%d위 / %s명" % [tier_rank, _fmt_comma(tier_participants)]

	_lbl_season_return.text = _fmt_pct(season_pct)
	_lbl_season_return.add_theme_color_override("font_color",
		COLOR_POSITIVE if season_pct >= 0.0 else COLOR_NEGATIVE)

	var start_cap: int = SeasonManager.get_season_start_capital()
	var current_assets: int = PortfolioManager.get_total_assets()
	_lbl_season_value.text = "₩%s → ₩%s" % [_fmt_comma(start_cap), _fmt_comma(current_assets)]

	_lbl_weekly_return.text = _fmt_pct(weekly_pct)
	_lbl_weekly_return.add_theme_color_override("font_color",
		COLOR_POSITIVE if weekly_pct >= 0.0 else COLOR_NEGATIVE)

	# 주간 수익률상 자격 여부
	var eligible: bool = weekly_fills >= SeasonManager.MIN_WEEKLY_TRADES
	var check: String  = "✓" if eligible else "✗"
	var min_t: int     = SeasonManager.MIN_WEEKLY_TRADES
	if eligible:
		_lbl_weekly_prize_status.text = "체결 %d회 %s" % [weekly_fills, check]
		_lbl_weekly_prize_status.add_theme_color_override("font_color", COLOR_POSITIVE)
	else:
		_lbl_weekly_prize_status.text = "체결 %d회 %s (최소 %d회 필요)" % [weekly_fills, check, min_t]
		_lbl_weekly_prize_status.add_theme_color_override("font_color", COLOR_NEGATIVE)


func _estimate_tier_participants(tier: int) -> int:
	# 플레이어 포함 추정값 — SeasonManager.TOTAL_PARTICIPANTS * 비율 (§3-3)
	var TIER_RATIOS: Array[float] = [
		0.38, 0.20, 0.13, 0.09, 0.06,
		0.045, 0.035, 0.025, 0.015, 0.01, 0.005,
	]
	if tier < 0 or tier >= TIER_RATIOS.size():
		return SeasonManager.TOTAL_PARTICIPANTS
	return maxi(1, int(float(SeasonManager.TOTAL_PARTICIPANTS) * TIER_RATIOS[tier]))


# ── Leaderboard ──

func _update_leaderboard() -> void:
	# 이전 행 전부 제거
	for child in _leaderboard_container.get_children():
		child.queue_free()

	var tier: int    = SeasonManager.get_current_tier()
	var my_rank: int = SeasonManager.get_tier_rank()

	# AC-08: 1~10위 고정
	var fixed: Array = SeasonManager.get_leaderboard(tier, 1, LEADERBOARD_FIXED_ROWS)
	for entry in fixed:
		_add_row(entry)

	# AC-09: 병합 여부 판단
	if my_rank > MERGE_THRESHOLD:
		_add_separator()
		var ctx_from: int = maxi(LEADERBOARD_FIXED_ROWS + 1, my_rank - LEADERBOARD_CONTEXT_RANGE)
		var ctx_to:   int = my_rank + LEADERBOARD_CONTEXT_RANGE
		var context: Array = SeasonManager.get_leaderboard(tier, ctx_from, ctx_to)
		for entry in context:
			_add_row(entry)

	# AC-12: 글로벌 순위 (항상 하단 고정)
	_global_rank_label.text = "글로벌: 집계 전 / %s명" % _fmt_comma(SeasonManager.TOTAL_PARTICIPANTS)
	_global_rank_label.visible = true


func _add_row(entry: Dictionary) -> void:
	var is_player: bool     = entry.get("is_player", false)
	var is_gm_ai: bool      = entry.get("is_grandmaster_ai", false)
	var rank: int           = entry.get("rank", 0)
	var nickname: String    = entry.get("nickname", "—")
	var return_pct: float   = entry.get("return_pct", 0.0)
	var prize_raw           = entry.get("prize_preview", 0)

	var row: PanelContainer = PanelContainer.new()
	var row_style: StyleBoxFlat = StyleBoxFlat.new()
	# AC-10: 플레이어 행 강조
	row_style.bg_color = COLOR_PLAYER_ROW if is_player else Color(0.0, 0.0, 0.0, 0.0)
	row.add_theme_stylebox_override("panel", row_style)
	_leaderboard_container.add_child(row)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	# 순위
	var lbl_rank: Label = Label.new()
	var rank_text: String = ("▶ %d" % rank) if is_player else ("%d" % rank)
	lbl_rank.text = rank_text
	lbl_rank.custom_minimum_size = Vector2(48, 0)
	lbl_rank.add_theme_font_size_override("font_size", 12)
	lbl_rank.add_theme_color_override("font_color", COLOR_NEUTRAL)
	hbox.add_child(lbl_rank)

	# 닉네임 (거장 뱃지)
	var nick_text: String = nickname
	if is_gm_ai:
		nick_text = nickname + " [거장]"
	var lbl_nick: Label = Label.new()
	lbl_nick.text = nick_text
	lbl_nick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_nick.add_theme_font_size_override("font_size", 12)
	var nick_color: Color = Color(1.0, 1.0, 0.8, 1.0) if is_player else COLOR_NEUTRAL
	lbl_nick.add_theme_color_override("font_color", nick_color)
	hbox.add_child(lbl_nick)

	# 수익률
	var lbl_ret: Label = Label.new()
	lbl_ret.text = _fmt_pct(return_pct)
	lbl_ret.custom_minimum_size = Vector2(72, 0)
	lbl_ret.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_ret.add_theme_font_size_override("font_size", 12)
	lbl_ret.add_theme_color_override("font_color",
		COLOR_POSITIVE if return_pct >= 0.0 else COLOR_NEGATIVE)
	hbox.add_child(lbl_ret)

	# 상금 예상 — AC-11: is_rank_eligible == false → "체결 부족"
	var lbl_prize: Label = Label.new()
	lbl_prize.custom_minimum_size = Vector2(72, 0)
	lbl_prize.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_prize.add_theme_font_size_override("font_size", 12)
	lbl_prize.add_theme_color_override("font_color", COLOR_NEUTRAL)
	if rank > LEADERBOARD_FIXED_ROWS:
		lbl_prize.text = "—"
	elif is_player and not SeasonManager.is_season_trade_eligible():
		lbl_prize.text = "체결 부족"
		lbl_prize.add_theme_color_override("font_color", COLOR_NEGATIVE)
	elif prize_raw is int and prize_raw > 0:
		lbl_prize.text = "₩%s" % _fmt_comma(prize_raw)
	else:
		lbl_prize.text = "—"
	hbox.add_child(lbl_prize)


func _add_separator() -> void:
	var sep: HSeparator = HSeparator.new()
	var sep_style: StyleBoxFlat = StyleBoxFlat.new()
	sep_style.bg_color = COLOR_SEPARATOR
	sep.add_theme_stylebox_override("separator", sep_style)
	_leaderboard_container.add_child(sep)


# ── UI Construction ──

func _build_ui() -> void:
	# 공유 배경
	var bg_style: StyleBoxFlat = StyleBoxFlat.new()
	bg_style.bg_color = COLOR_BG_CONTENT
	add_theme_stylebox_override("panel", bg_style)

	_state_layer = Control.new()
	_state_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_state_layer)

	_pre_season_panel  = _build_pre_season_panel()
	_free_market_panel = _build_free_market_panel()
	_main_panel        = _build_main_panel()

	_state_layer.add_child(_pre_season_panel)
	_state_layer.add_child(_free_market_panel)
	_state_layer.add_child(_main_panel)

	for p in [_pre_season_panel, _free_market_panel, _main_panel]:
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# ── EC-06: 시즌 시작 전 ──

func _build_pre_season_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_BG_CONTENT
	panel.add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var lbl: Label = Label.new()
	lbl.text = "시즌 시작 전"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	vbox.add_child(lbl)

	var sub: Label = Label.new()
	sub.text = "F1 거래 탭에서 시즌을 시작하세요."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1.0))
	vbox.add_child(sub)

	return panel


# ── EC-05: 프리마켓 ──

func _build_free_market_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_BG_CONTENT
	panel.add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var lbl: Label = Label.new()
	lbl.text = "현재 프리마켓 참여 중"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	vbox.add_child(lbl)

	var sub: Label = Label.new()
	sub.text = "공식 리그 순위 없음\n₩1,000,000 이상으로 시즌을 시작하면 리그에 참가할 수 있습니다."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1.0))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(sub)

	return panel


# ── Main Layout: 좌·우 패널 ──

func _build_main_panel() -> Control:
	var panel: Control = Control.new()

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 0)
	panel.add_child(hbox)

	hbox.add_child(_build_left_panel())
	hbox.add_child(_build_divider())
	hbox.add_child(_build_right_panel())

	return panel


func _build_divider() -> Control:
	var div: PanelContainer = PanelContainer.new()
	div.custom_minimum_size = Vector2(1, 0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.22, 1.0)
	div.add_theme_stylebox_override("panel", style)
	return div


# ── Left Panel ──

func _build_left_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_BG_PANEL
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# 내 현황 헤더
	var header: Label = Label.new()
	header.text = "내 현황"
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	vbox.add_child(header)

	vbox.add_child(_make_spacer(8))

	# 티어명
	_lbl_tier_name = Label.new()
	_lbl_tier_name.text = "—"
	_lbl_tier_name.add_theme_font_size_override("font_size", 22)
	_lbl_tier_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	vbox.add_child(_lbl_tier_name)

	# 순위
	_lbl_tier_rank = Label.new()
	_lbl_tier_rank.text = "—"
	_lbl_tier_rank.add_theme_font_size_override("font_size", 13)
	_lbl_tier_rank.add_theme_color_override("font_color", COLOR_NEUTRAL)
	vbox.add_child(_lbl_tier_rank)

	vbox.add_child(_make_spacer(12))
	vbox.add_child(_make_section_label("시즌 수익률"))

	_lbl_season_return = Label.new()
	_lbl_season_return.text = "—"
	_lbl_season_return.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_lbl_season_return)

	_lbl_season_value = Label.new()
	_lbl_season_value.text = "—"
	_lbl_season_value.add_theme_font_size_override("font_size", 11)
	_lbl_season_value.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
	vbox.add_child(_lbl_season_value)

	vbox.add_child(_make_spacer(12))
	vbox.add_child(_make_section_label("주간 수익률"))

	_lbl_weekly_return = Label.new()
	_lbl_weekly_return.text = "—"
	_lbl_weekly_return.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_lbl_weekly_return)

	_lbl_weekly_rank = Label.new()
	_lbl_weekly_rank.text = ""
	_lbl_weekly_rank.add_theme_font_size_override("font_size", 11)
	_lbl_weekly_rank.add_theme_color_override("font_color", COLOR_NEUTRAL)
	vbox.add_child(_lbl_weekly_rank)

	vbox.add_child(_make_spacer(12))
	vbox.add_child(_make_section_label("주간 수익률상"))

	_lbl_weekly_prize_status = Label.new()
	_lbl_weekly_prize_status.text = "—"
	_lbl_weekly_prize_status.add_theme_font_size_override("font_size", 12)
	_lbl_weekly_prize_status.add_theme_color_override("font_color", COLOR_NEUTRAL)
	_lbl_weekly_prize_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_lbl_weekly_prize_status)

	return panel


# ── Right Panel: 리더보드 ──

func _build_right_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_BG_CONTENT
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	# 리더보드 헤더 행
	vbox.add_child(_build_leaderboard_header())

	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)

	# 스크롤 없는 고정 컨테이너 (D-03: Option A)
	_leaderboard_container = VBoxContainer.new()
	_leaderboard_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_leaderboard_container.add_theme_constant_override("separation", 2)
	vbox.add_child(_leaderboard_container)

	# AC-12: 글로벌 순위 — 스크롤 영역 외부 하단 고정
	var global_sep: HSeparator = HSeparator.new()
	vbox.add_child(global_sep)

	_global_rank_label = Label.new()
	_global_rank_label.text = "글로벌: 집계 전"
	_global_rank_label.add_theme_font_size_override("font_size", 11)
	_global_rank_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1.0))
	_global_rank_label.add_theme_constant_override("margin_top", 4)
	vbox.add_child(_global_rank_label)

	return panel


func _build_leaderboard_header() -> Control:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var cols: Array[Array] = [
		["#",    48,  HORIZONTAL_ALIGNMENT_LEFT],
		["닉네임", -1, HORIZONTAL_ALIGNMENT_LEFT],
		["수익률", 72, HORIZONTAL_ALIGNMENT_RIGHT],
		["상금예상", 72, HORIZONTAL_ALIGNMENT_RIGHT],
	]
	for col in cols:
		var lbl: Label = Label.new()
		lbl.text = col[0]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
		lbl.horizontal_alignment = col[2]
		if col[1] > 0:
			lbl.custom_minimum_size = Vector2(col[1], 0)
		else:
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(lbl)

	return hbox


# ── Helpers ──

func _make_section_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1.0))
	return lbl


func _make_spacer(height: int) -> Control:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _fmt_pct(pct: float) -> String:
	var sign_str: String = "+" if pct >= 0.0 else ""
	return "%s%.1f%%" % [sign_str, pct]


func _fmt_comma(n: int) -> String:
	return FormatUtils.number(n)
