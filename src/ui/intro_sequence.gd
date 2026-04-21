class_name IntroSequence
extends Control
## 새 게임 시작 시 표시되는 5장 슬라이드 카드 인트로.
## StartScreen이 새 게임 확인 후 game_main을 통해 인스턴스화.
## GDD: design/gdd/intro-sequence.md

signal intro_finished

## 타이프라이터 속도 (초당 문자 수). GDD §7 튜닝 노브. EC-05: 반드시 양수.
const TYPEWRITER_SPEED: float = 28.0
## 카드 전환 페이드 지속 시간 (초, 편도). GDD §7 튜닝 노브.
const CARD_FADE_DURATION: float = 0.2
## 마지막 카드 후 페이드아웃 지속 시간 (초). GDD §7 튜닝 노브.
const FINISH_FADE_DURATION: float = 1.2

## GDD §3-2 카드 텍스트 5장. tr()로 래핑됨 (S5-04).
## 수치 리터럴 대신 상수 참조 (TD-CR-15): CurrencySystem / SeasonManager 상수를 직접 읽어 빌드.
## const → 함수로 변경: 상수가 업데이트되면 인트로 텍스트가 자동으로 따라간다.
static func _build_card_texts() -> Array[String]:
	var start_cash: String = FormatUtils.currency(CurrencySystem.INITIAL_CASH_ASSETS)
	var floor_cash: String = FormatUtils.currency(SeasonManager.HANGANG_THRESHOLD)
	var target_cash: String = FormatUtils.currency(SeasonManager.ENDING_THRESHOLD)
	return [
		"오늘, 퇴소했다.\n\n보육원 문이 닫혔다.\n뒤돌아보지 않았다.\n\n손에 쥔 건 전부다.\n정착지원금 %s.\n\n이게 시작이다." % start_cash,
		"같은 날, 공고 하나가 올라왔다.\n\n제1회 시드머니 투자 대회\n기간: 20거래일  /  참가자: 20,000명  /  무기: 당신의 판단\n\n19,999명이 이미 접속 중이다.\n모두 같은 돈으로 시작한다.\n모두 같은 시장을 본다.\n\n결과는 다를 것이다.",
		"오늘 밤은 쪽방이다.\n\n벽이 얇다. 창이 없다.\n괜찮다. 여기가 출발선이다.\n\n자산이 오르면, 거처가 바뀐다.\n고층이 보이고, 나중엔 수평선이 보인다.\n개인 섬을 가진 사람들이 있다. 당신도 갈 수 있다.\n\n반대 방향도 있다.\n자산이 %s 아래로 떨어지면 — 끝이다.\n\n그러니까, 오르는 방향으로만 간다." % floor_cash,
		"무기가 없다고 생각하지 마라.\n\n거래할수록 배운다.\n차트를 읽는 눈이 열리고,\n뉴스보다 빨리 움직이는 법을 익힌다.\n\n판단이 무기다. 분석이 수익이다.\n시즌 수익은 다음 시드머니가 된다.\n\n복리는 당신 편이다 — 방향이 맞다면.",
		"브론즈에서 거장까지.\n\n%s에서 %s까지.\n\n쪽방에서 수평선까지.\n\n시장이 열린다." % [start_cash, target_cash],
	]

## Path to the persistent flag that records whether the intro has been seen.
const SEEN_FLAG_PATH: String = "user://intro_seen.flag"


## Returns true if the player has already seen the intro at least once.
static func has_been_seen() -> bool:
	return FileAccess.file_exists(SEEN_FLAG_PATH)


## Removes the intro-seen flag so the intro plays again on next new game.
static func clear_seen_flag() -> void:
	if FileAccess.file_exists(SEEN_FLAG_PATH):
		DirAccess.remove_absolute(SEEN_FLAG_PATH)


var _card_texts: Array[String] = []  ## Built in _ready() from _build_card_texts()
var _current_card: int = 0
var _typewriter_active: bool = false
var _finishing: bool = false
var _typewriter_tween: Tween = null

var _bg: ColorRect
var _card_text: RichTextLabel
var _prompt_label: Label
var _skip_button: Button
var _counter_label: Label
var _overlay: ColorRect


func _ready() -> void:
	_card_texts = _build_card_texts()
	_build_ui()
	# 뷰포트 연결 후 Tween이 정상 동작하도록 한 프레임 뒤에 시작
	call_deferred("_show_card", 0)


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 검은 배경
	_bg = ColorRect.new()
	_bg.color = Color(0.063, 0.078, 0.118)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# 카드 텍스트 (수직 중앙)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 200.0
	center.offset_right = -200.0
	center.offset_top = 60.0
	center.offset_bottom = -80.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card_text = RichTextLabel.new()
	_card_text.bbcode_enabled = false
	_card_text.fit_content = true
	_card_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_text.custom_minimum_size = Vector2(900.0, 0.0)
	_card_text.add_theme_font_size_override("normal_font_size", 22)
	_card_text.add_theme_color_override("default_color", Color(0.918, 0.918, 0.918))
	_card_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_card_text)

	# "클릭하여 계속" 안내 (우하단)
	_prompt_label = Label.new()
	_prompt_label.text = tr("클릭하여 계속")
	_prompt_label.add_theme_font_size_override("font_size", 13)
	_prompt_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_prompt_label.anchor_left = 1.0
	_prompt_label.anchor_top = 1.0
	_prompt_label.anchor_right = 1.0
	_prompt_label.anchor_bottom = 1.0
	_prompt_label.offset_left = -180.0
	_prompt_label.offset_top = -48.0
	_prompt_label.offset_right = -24.0
	_prompt_label.offset_bottom = -24.0
	_prompt_label.modulate.a = 0.0
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt_label)

	# 카드 번호 (좌하단)
	_counter_label = Label.new()
	_counter_label.add_theme_font_size_override("font_size", 12)
	_counter_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
	_counter_label.anchor_top = 1.0
	_counter_label.anchor_bottom = 1.0
	_counter_label.offset_left = 24.0
	_counter_label.offset_top = -48.0
	_counter_label.offset_right = 120.0
	_counter_label.offset_bottom = -24.0
	_counter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_counter_label)

	# 스킵 버튼 (우상단)
	_skip_button = Button.new()
	_skip_button.text = tr("건너뛰기")
	_skip_button.flat = true
	_skip_button.anchor_left = 1.0
	_skip_button.anchor_right = 1.0
	_skip_button.offset_left = -108.0
	_skip_button.offset_right = -16.0
	_skip_button.offset_top = 16.0
	_skip_button.offset_bottom = 44.0
	_skip_button.add_theme_color_override("font_color", Color(0.42, 0.42, 0.42))
	_skip_button.add_theme_font_size_override("font_size", 13)
	_skip_button.pressed.connect(_on_skip_pressed)
	add_child(_skip_button)

	# 페이드 오버레이 (카드 전환 + 종료 페이드)
	_overlay = ColorRect.new()
	_overlay.color = Color(0.04, 0.04, 0.04)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.modulate.a = 0.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)


func _show_card(index: int) -> void:
	_current_card = index
	_typewriter_active = true
	_prompt_label.modulate.a = 0.0
	_counter_label.text = "%d / %d" % [index + 1, _card_texts.size()]

	var full_text: String = tr(_card_texts[index])
	_card_text.text = full_text
	_card_text.visible_characters = 0

	if _typewriter_tween:
		_typewriter_tween.kill()
		_typewriter_tween = null

	# EC-05: 분모 0 방지
	var speed: float = maxf(TYPEWRITER_SPEED, 1.0)
	var duration: float = full_text.length() / speed

	_typewriter_tween = create_tween()
	_typewriter_tween.tween_property(
		_card_text, "visible_characters", full_text.length(), duration
	)
	_typewriter_tween.tween_callback(_on_typewriter_finished)


func _on_typewriter_finished() -> void:
	_typewriter_active = false
	_card_text.visible_characters = -1
	_show_prompt()


func _show_prompt() -> void:
	var tween := create_tween()
	tween.tween_property(_prompt_label, "modulate:a", 1.0, 0.5)


func _advance() -> void:
	if _finishing:
		return

	# 타이프라이터 진행 중 → 즉시 완성 (GDD §3-3)
	if _typewriter_active:
		if _typewriter_tween:
			_typewriter_tween.kill()
			_typewriter_tween = null
		_typewriter_active = false
		_card_text.visible_characters = -1
		_show_prompt()
		return

	# 마지막 카드 → 종료
	if _current_card >= _card_texts.size() - 1:
		_finish()
		return

	# 다음 카드로 전환. 전환 중 입력 차단을 위해 _typewriter_active 임시 사용.
	_typewriter_active = true
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 1.0, CARD_FADE_DURATION)
	tween.tween_callback(func() -> void: _show_card(_current_card + 1))
	tween.tween_property(_overlay, "modulate:a", 0.0, CARD_FADE_DURATION)


func _finish() -> void:
	# EC-01: 이중 종료 방지
	if _finishing:
		return
	_finishing = true
	_skip_button.hide()
	_prompt_label.hide()

	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 1.0, FINISH_FADE_DURATION)
	tween.tween_callback(func() -> void: intro_finished.emit())


func _on_skip_pressed() -> void:
	# EC-02: 이중 emit 방지
	if _finishing:
		return
	if _typewriter_tween:
		_typewriter_tween.kill()
		_typewriter_tween = null
	_typewriter_active = false
	_finishing = true
	intro_finished.emit()


func _input(event: InputEvent) -> void:
	if _finishing:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_advance()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			match ke.keycode:
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					_advance()
					get_viewport().set_input_as_handled()
				KEY_ESCAPE:
					_on_skip_pressed()
					get_viewport().set_input_as_handled()


