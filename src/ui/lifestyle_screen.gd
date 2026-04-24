## LifestyleScreen — Daily spending UI. Shows after every settlement confirmation.
## 5 category tabs: 거주지 | 사치품 | 네트워크 | 사회공헌 | 대안투자
## Displays remaining cash_assets in real time.
## Call set_season_end_context(true) before add_child() on season-end days.
## GDD: design/gdd/lifestyle-spending.md §3-1, §3-3
extends Control

# ── Signals ──

## Emitted when the player presses "다음 날 →" / "다음 시즌 시작 →" to close this screen.
signal lifestyle_screen_closed

# ── Constants ──

## Tab indices matching GDD §3-3 category order.
const TAB_RESIDENCE:     int = 0
const TAB_LUXURY:        int = 1
const TAB_NETWORK:       int = 2
const TAB_SOCIAL:        int = 3
const TAB_ALTERNATIVE:   int = 4

## Free-market warning threshold (GDD §5 EC-1).
const FREE_MARKET_THRESHOLD: int = 1_000_000

# ── State ──

## Set by GameMain before add_child(). True on season-end days.
## Controls button text: "다음 날 →" vs "다음 시즌 시작 →" (GDD §3-1).
var _is_season_end: bool = false

# ── Node References ──

var _tab_bar: TabContainer = null
var _residual_label: Label = null          ## "소비 후 잔여" 실시간 수치
var _start_next_season_btn: Button = null
var _warning_label: Label = null           ## 프리마켓 진입 경고

# ── Lifestyle item data (GDD §3-2) ──

## Residence items: {tier, name, cost, art_file}
const RESIDENCE_ITEMS: Array = [
	## Tier 0 — bronze default, no purchase needed
	{"tier": 0, "name": "쪽방/고시원",         "cost": 0,              "art": "bronze_jjokbang.png"},
	{"tier": 1, "name": "변두리 원룸",          "cost": 500_000,        "art": "silver_oneroom.png"},
	{"tier": 2, "name": "도심 오피스텔",        "cost": 2_000_000,      "art": "gold_officetel.png"},
	{"tier": 3, "name": "강남 아파트 (중형)",   "cost": 10_000_000,     "art": "platinum_apartment.png"},
	{"tier": 4, "name": "도심 대형 아파트",     "cost": 30_000_000,     "art": "emerald_large_apartment.png"},
	{"tier": 5, "name": "초고층 펜트하우스",    "cost": 100_000_000,    "art": "diamond_penthouse.png"},
	{"tier": 6, "name": "교외 대저택",          "cost": 300_000_000,    "art": "master_mansion.png"},
	{"tier": 7, "name": "개인 섬/별장",         "cost": 1_000_000_000,  "art": "grandmaster_island_villa.png"},
	{"tier": 8, "name": "스카이 레지던스",      "cost": 3_000_000_000,  "art": "challenger_sky_residence.png"},
	{"tier": 9, "name": "영빈관급 저택",        "cost": 10_000_000_000, "art": "legend_official_residence.png"},
	{"tier": 10, "name": "(엔딩)",              "cost": 0,              "art": "grandmaster_ending.png"},
]

## Luxury items: {item_id, name, cost, min_tier, title_id, recurring, recurring_cost}
const LUXURY_ITEMS: Array = [
	{"item_id": "luxury_car",   "name": "수입차 (포르쉐 카이엔급)",     "cost": 200_000_000, "min_tier": 4, "title_id": "수입차 애호가", "recurring": false, "recurring_cost": 0},
	{"item_id": "luxury_watch", "name": "명품 시계 (파텍 필립급)",      "cost": 100_000_000, "min_tier": 5, "title_id": "컬렉터",       "recurring": false, "recurring_cost": 0},
	{"item_id": "golf_club",    "name": "프라이빗 골프 클럽 멤버십",    "cost": 50_000_000,  "min_tier": 3, "title_id": "멤버스 온리",  "recurring": true,  "recurring_cost": 10_000_000},
	{"item_id": "yacht_berth",  "name": "요트 계류권",                  "cost": 500_000_000, "min_tier": 6, "title_id": "요트클럽",     "recurring": false, "recurring_cost": 0},
]

## Network items: {item_id, name, cost, min_tier, recurring, recurring_cost, xp_bonus}
const NETWORK_ITEMS: Array = [
	{"item_id": "invest_club",  "name": "프라이빗 투자 클럽 연회비", "cost": 20_000_000, "min_tier": 4, "recurring": true,  "xp_bonus": 0},
	{"item_id": "forum_vip",    "name": "경제 포럼 VIP석",           "cost": 30_000_000, "min_tier": 5, "recurring": false, "xp_bonus": 10},
]

## Social contribution items: {item_id, name, min_tier, xp_bonus, is_variable_cost}
const SOCIAL_ITEMS: Array = [
	{"item_id": "scholarship",  "name": "장학재단 설립",     "cost": 500_000_000, "min_tier": 6, "recurring": false, "xp_bonus": 0,  "is_variable_cost": false},  ## GDD: 다음 시즌 첫 거래일 뉴스 딜레이 −5틱 (XP 아님)
	{"item_id": "social_biz",   "name": "사회적 기업 후원",  "cost": 10_000_000,  "min_tier": 4, "recurring": true,  "xp_bonus": 5,  "is_variable_cost": false},
	{"item_id": "donation",     "name": "공익 캠페인 기부",  "cost": 0,           "min_tier": 2, "recurring": false, "xp_bonus": 0,  "is_variable_cost": true},
]

## Alternative investment — property: {property_type, name, cost, rental_rate, min_tier}
const PROPERTY_ITEMS: Array = [
	{"property_type": "officetel", "name": "소형 오피스텔", "cost": 200_000_000,   "rental_rate": 0.025, "min_tier": 4},
	{"property_type": "sangga",    "name": "강남 상가",     "cost": 1_000_000_000, "rental_rate": 0.030, "min_tier": 6},
	{"property_type": "building",  "name": "빌딩",          "cost": 5_000_000_000, "rental_rate": 0.040, "min_tier": 7},
]

## Startup investment amount range (GDD §3-2). Seasons range is LifestyleManager.STARTUP_MIN/MAX_SEASONS.
const STARTUP_MIN_AMOUNT: int = 50_000_000
const STARTUP_MAX_AMOUNT: int = 500_000_000


# ── Setup ──

## Call this before add_child() to set button text context.
## is_season_end=true → "다음 시즌 시작 →", false → "다음 날 →" (GDD §3-1, AC-14).
func set_season_end_context(is_season_end: bool) -> void:
	_is_season_end = is_season_end


# ── Lifecycle ──

func _ready() -> void:
	_build_ui()
	_refresh_residual()
	CurrencySystem.cash_assets_changed.connect(_on_cash_changed)


func _exit_tree() -> void:
	if CurrencySystem.cash_assets_changed.is_connected(_on_cash_changed):
		CurrencySystem.cash_assets_changed.disconnect(_on_cash_changed)


# ── UI Construction ──

func _build_ui() -> void:
	## Root layout: VBox (header) + TabContainer (tabs) + footer
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	## Header
	var header := _build_header()
	vbox.add_child(header)

	## Tab container
	_tab_bar = TabContainer.new()
	_tab_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tab_bar)
	_build_all_tabs()

	## Footer
	var footer := _build_footer()
	vbox.add_child(footer)


func _build_header() -> Control:
	var panel := PanelContainer.new()
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)

	var title := Label.new()
	title.text = "라이프스타일 소비"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(title)

	var residual_hbox := HBoxContainer.new()
	hbox.add_child(residual_hbox)

	var residual_title := Label.new()
	residual_title.text = "소비 후 잔여 (다음 시즌 시드): " if _is_season_end else "소비 후 잔여: "
	residual_hbox.add_child(residual_title)

	_residual_label = Label.new()
	_residual_label.text = _format_amount(CurrencySystem.get_cash_assets())
	residual_hbox.add_child(_residual_label)

	_warning_label = Label.new()
	_warning_label.text = "⚠ 소비 후 프리마켓으로 진입하게 됩니다"
	_warning_label.visible = false
	_warning_label.add_theme_color_override("font_color", Color.ORANGE)
	hbox.add_child(_warning_label)

	return panel


func _build_footer() -> Control:
	var panel := PanelContainer.new()
	_start_next_season_btn = Button.new()
	_start_next_season_btn.text = "다음 시즌 시작 →" if _is_season_end else "다음 날 →"
	_start_next_season_btn.pressed.connect(_on_next_season_pressed)
	panel.add_child(_start_next_season_btn)
	return panel


func _build_all_tabs() -> void:
	_build_residence_tab()
	_build_luxury_tab()
	_build_network_tab()
	_build_social_tab()
	_build_alternative_tab()


# ── Tab: 거주지 (Residence) ──

func _build_residence_tab() -> void:
	var tab := ScrollContainer.new()
	tab.name = "거주지"
	_tab_bar.add_child(tab)

	var vbox := VBoxContainer.new()
	tab.add_child(vbox)

	var current_tier: int = LifestyleManager.get_residence_tier()
	var player_tier: int  = SeasonManager.get_current_tier()

	for item: Variant in RESIDENCE_ITEMS:
		var data: Dictionary = item as Dictionary
		var tier: int = data["tier"]
		if tier == 10:
			continue  ## 거장 엔딩 — 자동 전환, 구매 불가
		var card := _build_residence_card(data, current_tier, player_tier)
		vbox.add_child(card)


func _build_residence_card(data: Dictionary, current_tier: int, player_tier: int) -> Control:
	var panel := PanelContainer.new()
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)

	var name_label := Label.new()
	name_label.text = data["name"]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)

	var cost_label := Label.new()
	cost_label.text = _format_amount(data["cost"])
	hbox.add_child(cost_label)

	var tier: int = data["tier"]
	var btn := Button.new()

	if tier == current_tier:
		btn.text = "현재 거주지"
		btn.disabled = true
	elif tier < current_tier:
		btn.text = "보유"
		btn.disabled = true
	elif tier > current_tier + 1:
		btn.text = "잠금"
		btn.disabled = true
	elif player_tier < tier:
		btn.text = "티어 미충족"
		btn.disabled = true
	else:
		btn.text = "업그레이드"
		btn.pressed.connect(func() -> void: _on_upgrade_residence(tier, data))
	hbox.add_child(btn)

	return panel


func _on_upgrade_residence(tier: int, data: Dictionary) -> void:
	## GDD §3-4: 2단계 확인 (대금 차감 규모가 크므로 의도적 마찰)
	var confirm_dialog := ConfirmationDialog.new()
	confirm_dialog.title = "거주지 업그레이드 확인"
	confirm_dialog.dialog_text = "%s\n구매 비용: %s\n\n확인하시겠습니까?" % [
		data["name"], _format_amount(data["cost"])
	]
	add_child(confirm_dialog)
	confirm_dialog.confirmed.connect(func() -> void: _do_upgrade_residence(tier))
	confirm_dialog.popup_centered()


func _do_upgrade_residence(tier: int) -> void:
	## Validate tier is exactly next (GDD §3-2: sequential only)
	if tier != LifestyleManager.get_residence_tier() + 1:
		return
	var success: bool = LifestyleManager.upgrade_residence()
	if success:
		## GDD §3-4: 이사 날 연출 — 페이드 블랙 → 새 배경 페이드인 → 타이틀 카드
		_play_moving_day_sequence()
		## Save immediately on purchase (GDD §5 EC: 구매 확정 즉시 세이브)
		if SaveSystem.get_active_slot_id() >= 0:
			SaveSystem.save_slot(SaveSystem.get_active_slot_id())
		_rebuild_residence_tab()
	_refresh_residual()


func _play_moving_day_sequence() -> void:
	## GDD §3-4: 페이드 블랙 1~2초 → 새 거주지 배경 풀스크린 페이드인 3초 → 타이틀 카드 2초
	## Minimal implementation: ColorRect fade-in/out overlay.
	var overlay := ColorRect.new()
	overlay.color = Color.BLACK
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var tween: Tween = create_tween().set_sequential()
	## Fade to black
	tween.tween_property(overlay, "color:a", 1.0, 1.0)
	## Hold black + show residence name card
	tween.tween_interval(1.0)
	tween.tween_callback(func() -> void:
		var card_label := Label.new()
		card_label.text = "%s\n입주" % LifestyleManager.get_residence_name()
		card_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		card_label.modulate.a = 0.0
		overlay.add_child(card_label)
		var inner: Tween = create_tween().set_sequential()
		inner.tween_property(card_label, "modulate:a", 1.0, 0.5)
		inner.tween_interval(2.0)
	)
	## Fade back out
	tween.tween_property(overlay, "color:a", 0.0, 1.5)
	tween.tween_callback(overlay.queue_free)


func _rebuild_residence_tab() -> void:
	var old: Node = _tab_bar.get_child(TAB_RESIDENCE)
	if old:
		_tab_bar.remove_child(old)  # immediate removal so move_child sees correct indices
		old.queue_free()
	_build_residence_tab()
	var new_tab: Node = _tab_bar.get_child(_tab_bar.get_child_count() - 1)
	_tab_bar.move_child(new_tab, TAB_RESIDENCE)


# ── Tab: 사치품 (Luxury) ──

func _build_luxury_tab() -> void:
	var tab := ScrollContainer.new()
	tab.name = "사치품"
	_tab_bar.add_child(tab)

	var vbox := VBoxContainer.new()
	tab.add_child(vbox)

	var player_tier: int = SeasonManager.get_current_tier()

	for item: Variant in LUXURY_ITEMS:
		var data: Dictionary = item as Dictionary
		var card := _build_purchase_card(
			data["name"],
			data["cost"],
			data["min_tier"],
			player_tier,
			LifestyleManager.has_luxury(data["item_id"]),
			func() -> void: _on_buy_luxury(data),
			"Recurring: %s/시즌" % _format_amount(data["recurring_cost"]) if data["recurring"] else ""
		)
		vbox.add_child(card)


func _on_buy_luxury(data: Dictionary) -> void:
	if LifestyleManager.purchase_luxury(data["item_id"], data["cost"]):
		## Register recurring cost after successful purchase (GDD §3-2)
		if data.get("recurring", false) and data.get("recurring_cost", 0) > 0:
			LifestyleManager.add_recurring_cost(data["item_id"], data["recurring_cost"])
		if SaveSystem.get_active_slot_id() >= 0:
			SaveSystem.save_slot(SaveSystem.get_active_slot_id())
		_rebuild_luxury_tab()
	_refresh_residual()


func _rebuild_luxury_tab() -> void:
	var old: Node = _tab_bar.get_child(TAB_LUXURY)
	if old:
		_tab_bar.remove_child(old)
		old.queue_free()
	_build_luxury_tab()
	var new_tab: Node = _tab_bar.get_child(_tab_bar.get_child_count() - 1)
	_tab_bar.move_child(new_tab, TAB_LUXURY)


# ── Tab: 네트워크 (Network) ──

func _build_network_tab() -> void:
	var tab := ScrollContainer.new()
	tab.name = "네트워크"
	_tab_bar.add_child(tab)

	var vbox := VBoxContainer.new()
	tab.add_child(vbox)

	var player_tier: int = SeasonManager.get_current_tier()

	for item: Variant in NETWORK_ITEMS:
		var data: Dictionary = item as Dictionary
		var suffix: String = "/시즌" if data.get("recurring", false) else ""
		var card := _build_purchase_card(
			data["name"],
			data["cost"],
			data["min_tier"],
			player_tier,
			LifestyleManager.has_luxury(data["item_id"]),
			func() -> void: _on_buy_network(data),
			"XP +%d" % data["xp_bonus"] if data["xp_bonus"] > 0 else suffix
		)
		vbox.add_child(card)


func _on_buy_network(data: Dictionary) -> void:
	## GDD §3-2: 네트워크 구매는 LifestyleManager.purchase_network_item()으로 위임
	if LifestyleManager.purchase_network_item(
		data["item_id"], data["cost"],
		data.get("xp_bonus", 0),
		data.get("recurring", false)
	):
		if SaveSystem.get_active_slot_id() >= 0:
			SaveSystem.save_slot(SaveSystem.get_active_slot_id())
		_rebuild_network_tab()
	_refresh_residual()


func _rebuild_network_tab() -> void:
	var old: Node = _tab_bar.get_child(TAB_NETWORK)
	if old:
		_tab_bar.remove_child(old)
		old.queue_free()
	_build_network_tab()
	var new_tab: Node = _tab_bar.get_child(_tab_bar.get_child_count() - 1)
	_tab_bar.move_child(new_tab, TAB_NETWORK)


# ── Tab: 사회공헌 (Social Contribution) ──

func _build_social_tab() -> void:
	var tab := ScrollContainer.new()
	tab.name = "사회공헌"
	_tab_bar.add_child(tab)

	var vbox := VBoxContainer.new()
	tab.add_child(vbox)

	var player_tier: int = SeasonManager.get_current_tier()

	for item: Variant in SOCIAL_ITEMS:
		var data: Dictionary = item as Dictionary
		if data.get("is_variable_cost", false):
			## 공익 캠페인 기부 — player inputs amount
			vbox.add_child(_build_donation_card(data, player_tier))
		else:
			var is_owned: bool = LifestyleManager.has_luxury(data["item_id"])
			var suffix: String = "XP +%d" % data["xp_bonus"] if data["xp_bonus"] > 0 else ""
			var card := _build_purchase_card(
				data["name"], data["cost"], data["min_tier"], player_tier, is_owned,
				func() -> void: _on_buy_social(data), suffix
			)
			vbox.add_child(card)


func _build_donation_card(data: Dictionary, player_tier: int) -> Control:
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title_label := Label.new()
	title_label.text = data["name"] + " (₩1,000,000 ~ ₩50,000,000)"
	vbox.add_child(title_label)

	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	var input := LineEdit.new()
	input.placeholder_text = "기부 금액 입력"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(input)

	var btn := Button.new()
	btn.text = "기부"
	if player_tier < data["min_tier"]:
		btn.disabled = true
	btn.pressed.connect(func() -> void: _on_donate(input.text))
	hbox.add_child(btn)

	return panel


func _on_donate(text: String) -> void:
	## GDD §3-2: 공익 캠페인 기부는 LifestyleManager.donate()로 위임
	var amount: int = int(text.strip_edges())
	if LifestyleManager.donate(amount):
		if SaveSystem.get_active_slot_id() >= 0:
			SaveSystem.save_slot(SaveSystem.get_active_slot_id())
	_refresh_residual()


func _on_buy_social(data: Dictionary) -> void:
	## GDD §3-2: 사회공헌 구매는 LifestyleManager.purchase_social_item()으로 위임
	if LifestyleManager.purchase_social_item(
		data["item_id"], data["cost"],
		data.get("xp_bonus", 0),
		data.get("recurring", false)
	):
		if SaveSystem.get_active_slot_id() >= 0:
			SaveSystem.save_slot(SaveSystem.get_active_slot_id())
	_refresh_residual()


# ── Tab: 대안투자 (Alternative Investments) ──

func _build_alternative_tab() -> void:
	var tab := ScrollContainer.new()
	tab.name = "대안투자"
	_tab_bar.add_child(tab)

	var vbox := VBoxContainer.new()
	tab.add_child(vbox)

	var player_tier: int = SeasonManager.get_current_tier()

	## Properties
	var property_header := Label.new()
	property_header.text = "── 부동산 (임대 수익형) ──"
	vbox.add_child(property_header)

	for item: Variant in PROPERTY_ITEMS:
		var data: Dictionary = item as Dictionary
		var yield_label: String = "임대 수익: %s/시즌 (%.1f%%)" % [
			_format_amount(int(float(data["cost"]) * data["rental_rate"])),
			data["rental_rate"] * 100.0
		]
		var card := _build_purchase_card(
			data["name"], data["cost"], data["min_tier"], player_tier, false,
			func() -> void: _on_buy_property(data), yield_label
		)
		vbox.add_child(card)

	## Startup investment
	var startup_header := Label.new()
	startup_header.text = "── 스타트업 엔젤 투자 ──"
	vbox.add_child(startup_header)
	vbox.add_child(_build_startup_card(player_tier))


func _build_startup_card(player_tier: int) -> Control:
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var info := Label.new()
	info.text = "스타트업 엔젤 투자 (₩%s ~ ₩%s, 만기 %d~%d시즌)" % [
		_format_amount(STARTUP_MIN_AMOUNT),
		_format_amount(STARTUP_MAX_AMOUNT),
		LifestyleManager.STARTUP_MIN_SEASONS, LifestyleManager.STARTUP_MAX_SEASONS
	]
	vbox.add_child(info)

	var prob_label := Label.new()
	prob_label.text = "IPO 20%(×2~5) | M&A 50%(×1~1.5) | 폐업 30%(×0)"
	vbox.add_child(prob_label)

	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	var input := LineEdit.new()
	input.placeholder_text = "투자금 입력"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(input)

	var btn := Button.new()
	btn.text = "투자"
	## GDD §3-2: 에메랄드+ 해금 (tier 4)
	if player_tier < 4:
		btn.disabled = true
	btn.pressed.connect(func() -> void: _on_invest_startup(input.text))
	hbox.add_child(btn)

	return panel


func _on_buy_property(data: Dictionary) -> void:
	if not LifestyleManager.purchase_property(data["property_type"], data["cost"]):
		return
	if SaveSystem.get_active_slot_id() >= 0:
		SaveSystem.save_slot(SaveSystem.get_active_slot_id())
	_refresh_residual()


func _on_invest_startup(text: String) -> void:
	var amount: int = int(text.strip_edges())
	if amount < STARTUP_MIN_AMOUNT or amount > STARTUP_MAX_AMOUNT:
		return
	if not LifestyleManager.invest_startup(amount):
		return
	if SaveSystem.get_active_slot_id() >= 0:
		SaveSystem.save_slot(SaveSystem.get_active_slot_id())
	_refresh_residual()


# ── Shared Card Builder ──

func _build_purchase_card(
	item_name: String,
	cost: int,
	min_tier: int,
	player_tier: int,
	is_owned: bool,
	on_press: Callable,
	suffix: String
) -> Control:
	var panel := PanelContainer.new()
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)

	var name_label := Label.new()
	name_label.text = item_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)

	if not suffix.is_empty():
		var suffix_label := Label.new()
		suffix_label.text = suffix
		hbox.add_child(suffix_label)

	var cost_label := Label.new()
	cost_label.text = _format_amount(cost)
	hbox.add_child(cost_label)

	var btn := Button.new()
	if is_owned:
		btn.text = "보유중"
		btn.disabled = true
	elif player_tier < min_tier:
		btn.text = "잠금 (티어 미충족)"
		btn.disabled = true
	else:
		btn.text = "구매"
		btn.pressed.connect(on_press)
	hbox.add_child(btn)

	return panel


# ── Residual / Warning ──

func _refresh_residual() -> void:
	var remaining: int = CurrencySystem.get_cash_assets()
	_residual_label.text = _format_amount(remaining)
	_warning_label.visible = remaining < FREE_MARKET_THRESHOLD


func _on_cash_changed(_new_amount: int) -> void:
	_refresh_residual()


# ── Footer Actions ──

func _on_next_season_pressed() -> void:
	lifestyle_screen_closed.emit()


# ── Utilities ──

func _format_amount(amount: int) -> String:
	return FormatUtils.currency(amount)
