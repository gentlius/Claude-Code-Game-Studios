## ProfitCelebration — B-13 수익 실현 팡파레 이펙트.
## 매도 체결 후 realized_pnl > 0이면 4등급 시각/청각 이펙트 재생.
## CanvasLayer(layer=5): SavingOverlay(10) 아래, 게임 UI(0) 위.
## See: design/gdd/profit-celebration.md
class_name ProfitCelebration
extends CanvasLayer

# ── Grade Constants ──

## Grade enum — 등급별 이펙트 강도를 결정한다 (GDD §3-2).
enum Grade { NONE, SMALL, MEDIUM, LARGE, JACKPOT }

## pnl_pct 경계값 (튜닝 노브 — GDD §7)
const GRADE_MEDIUM_THRESHOLD: float  = 5.0
const GRADE_LARGE_THRESHOLD: float   = 10.0
const GRADE_JACKPOT_THRESHOLD: float = 15.0

## 등급별 파티클 수 (GDD §3-3)
const COIN_COUNT_SMALL:   int = 10
const COIN_COUNT_MEDIUM:  int = 40
const COIN_COUNT_LARGE:   int = 100
const COIN_COUNT_JACKPOT: int = 200

## 골드 테두리 플래시 폭 (px)
const FLASH_BORDER_WIDTH: float = 40.0

## JACKPOT 화면 진동
const SHAKE_AMPLITUDE: float = 4.0
const SHAKE_DURATION:  float = 0.3

## 4x 배속 이펙트 시간 배율 (GDD §3-6)
const SPEED_4X_DURATION_MULT: float = 0.5
const SPEED_2X_DURATION_MULT: float = 0.70

## 등급별 숫자 롤업 시간 (초) (GDD §3-3)
const ROLLUP_DURATION_SMALL:   float = 0.4
const ROLLUP_DURATION_MEDIUM:  float = 0.6
const ROLLUP_DURATION_LARGE:   float = 1.0
const ROLLUP_DURATION_JACKPOT: float = 1.5
const ROLLUP_HOLD_JACKPOT:     float = 0.5  # 최종값 도달 후 홀드

## 파티클 지속 시간 (초)
const PARTICLE_DURATION_SMALL:   float = 0.8
const PARTICLE_DURATION_MEDIUM:  float = 1.2
const PARTICLE_DURATION_LARGE:   float = 1.8
const PARTICLE_DURATION_JACKPOT: float = 2.5

# ── State ──

var _current_grade: Grade = Grade.NONE
var _is_playing: bool = false

# ── Nodes ──

var _root: Control              ## Root Control — viewport-sized, mouse-ignored
var _particles: CPUParticles2D
var _rollup_label: Label
var _flash_rect: ColorRect
var _banner_label: Label
var _rollup_tween: Tween
var _flash_tween: Tween
var _shake_tween: Tween
var _particle_timer: SceneTreeTimer

# ── Lifecycle ──

func _ready() -> void:
	layer = 5  # above game UI, below SavingOverlay(10)
	_build_ui()
	GameClock.on_market_state_changed.connect(_on_market_state_changed)


func _build_ui() -> void:
	## Root: viewport-filling, mouse-transparent so game input passes through.
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Coin particles — positioned at bottom-right (toast area)
	_particles = CPUParticles2D.new()
	_particles.emitting          = false
	_particles.one_shot          = true
	_particles.position          = Vector2(1200, 600)  # adjusted in play() to viewport size
	_particles.gravity           = Vector2(0, 980)
	_particles.initial_velocity_min = 200.0
	_particles.initial_velocity_max = 400.0
	_particles.direction         = Vector2(0, -1)
	_particles.spread            = 60.0
	_particles.angular_velocity_min = -180.0
	_particles.angular_velocity_max =  180.0
	_particles.scale_amount_min  = 0.6
	_particles.scale_amount_max  = 1.2
	_particles.color             = Color(1.0, 0.84, 0.0)  # gold
	_particles.z_index           = 10
	var texture_path: String = "res://assets/art/vfx/coin_gold.png"
	if ResourceLoader.exists(texture_path):
		_particles.texture = load(texture_path) as Texture2D
	_root.add_child(_particles)

	# Number rollup label
	_rollup_label = Label.new()
	_rollup_label.visible              = false
	_rollup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rollup_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_rollup_label.add_theme_font_size_override("font_size", 28)
	_rollup_label.add_theme_color_override("font_color", ThemeSetup.PRICE_UP)
	# Anchor to bottom-right, above toast area
	_rollup_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_rollup_label.offset_left   = -300
	_rollup_label.offset_top    = -220
	_rollup_label.offset_right  = -20
	_rollup_label.offset_bottom = -170
	_rollup_label.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_rollup_label)

	# Gold border flash ColorRect
	_flash_rect = ColorRect.new()
	_flash_rect.visible      = false
	_flash_rect.color        = Color(1.0, 0.84, 0.0, 0.0)  # gold, transparent
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash_rect)

	# JACKPOT banner
	_banner_label = Label.new()
	_banner_label.visible              = false
	_banner_label.text                 = tr("🎉 수익 실현!")
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 42)
	_banner_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	_banner_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner_label.offset_left   = -200
	_banner_label.offset_right  =  200
	_banner_label.offset_top    = -40
	_banner_label.offset_bottom =  40
	_banner_label.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_banner_label)

# ── Public API ──

## Main entry point. Called by TradingScreen._on_holding_removed().
## realized_pnl: 원 단위 실현 손익 (> 0 보장)
## pnl_pct: 수익률 (%) = realized_pnl / cost_basis * 100
func play(realized_pnl: int, pnl_pct: float) -> void:
	if realized_pnl <= 0:
		return
	_cancel_current()
	_current_grade = _calc_grade(pnl_pct)
	if _current_grade == Grade.NONE:
		return
	_is_playing = true
	var duration_mult: float = _get_speed_duration_mult()

	_play_particles(_current_grade, duration_mult)
	_play_number_rollup(realized_pnl, _current_grade, duration_mult)
	_play_flash(_current_grade, duration_mult)
	if _current_grade == Grade.JACKPOT:
		_play_banner(duration_mult)
		_play_shake(duration_mult)
	_play_sfx(_current_grade)


# ── Grade Calculation ──

## F1: 수익률 기준 등급 판정 (GDD §4).
func _calc_grade(pnl_pct: float) -> Grade:
	if pnl_pct <= 0.0:
		return Grade.NONE
	if pnl_pct < GRADE_MEDIUM_THRESHOLD:
		return Grade.SMALL
	if pnl_pct < GRADE_LARGE_THRESHOLD:
		return Grade.MEDIUM
	if pnl_pct < GRADE_JACKPOT_THRESHOLD:
		return Grade.LARGE
	return Grade.JACKPOT


# ── Effects ──

func _play_particles(grade: Grade, duration_mult: float) -> void:
	var count: int
	var duration: float
	match grade:
		Grade.SMALL:   count = COIN_COUNT_SMALL;   duration = PARTICLE_DURATION_SMALL
		Grade.MEDIUM:  count = COIN_COUNT_MEDIUM;  duration = PARTICLE_DURATION_MEDIUM
		Grade.LARGE:   count = COIN_COUNT_LARGE;   duration = PARTICLE_DURATION_LARGE
		_:             count = COIN_COUNT_JACKPOT; duration = PARTICLE_DURATION_JACKPOT
	_particles.amount       = count
	_particles.lifetime     = duration * duration_mult
	_particles.explosiveness = 0.3
	# Position at bottom-right (toast region)
	var vp: Viewport = get_viewport()
	if vp:
		_particles.position = Vector2(vp.get_visible_rect().size.x - 60,
									  vp.get_visible_rect().size.y - 120)
	_particles.restart()
	_particles.emitting = true
	# Auto-clear after lifetime
	_particle_timer = get_tree().create_timer(duration * duration_mult + 0.2)
	_particle_timer.timeout.connect(func() -> void:
		if is_instance_valid(_particles):
			_particles.emitting = false
	)


func _play_number_rollup(realized_pnl: int, grade: Grade, duration_mult: float) -> void:
	var duration: float
	var hold_time: float = 0.0
	match grade:
		Grade.SMALL:   duration = ROLLUP_DURATION_SMALL
		Grade.MEDIUM:  duration = ROLLUP_DURATION_MEDIUM
		Grade.LARGE:   duration = ROLLUP_DURATION_LARGE
		_:
			duration  = ROLLUP_DURATION_JACKPOT
			hold_time = ROLLUP_HOLD_JACKPOT
	duration *= duration_mult

	_rollup_label.text    = "+₩0"
	_rollup_label.visible = true
	_rollup_label.modulate.a = 1.0

	if _rollup_tween:
		_rollup_tween.kill()
	_rollup_tween = create_tween()
	_rollup_tween.tween_method(
		func(pct: float) -> void:
			var val: int = roundi(float(realized_pnl) * pct)
			_rollup_label.text = "+₩%s" % FormatUtils.number(val),
		0.0, 1.0, duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_rollup_tween.tween_interval(hold_time)
	_rollup_tween.tween_property(_rollup_label, "modulate:a", 0.0, 0.3)
	_rollup_tween.tween_callback(func() -> void: _rollup_label.visible = false)


func _play_flash(grade: Grade, duration_mult: float) -> void:
	if grade == Grade.SMALL:
		return

	var flash_count: int = 1
	match grade:
		Grade.MEDIUM:  flash_count = 1
		Grade.LARGE:   flash_count = 2
		Grade.JACKPOT: flash_count = 3

	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_rect.visible = true

	# Apply border mask — only edges, not center
	# We fake border by using modulate on a full-rect; real border masking would need shader.
	# For now, a semi-transparent full overlay (GDD §3-3: "화면 테두리 영역만" — border-only).
	# A lightweight border approach: use _flash_rect as 4 thin rectangles.
	# Simplified: use a global overlay with low alpha (α=0.15 as in GDD).
	for _i: int in flash_count:
		_flash_tween.tween_property(_flash_rect, "color",
			Color(1.0, 0.84, 0.0, 0.15), 0.05 * duration_mult)
		_flash_tween.tween_property(_flash_rect, "color",
			Color(1.0, 0.84, 0.0, 0.0),  0.20 * duration_mult)

	if grade == Grade.JACKPOT:
		# Additional pulse
		_flash_tween.tween_property(_flash_rect, "color",
			Color(1.0, 0.84, 0.0, 0.10), 0.25 * duration_mult)
		_flash_tween.tween_property(_flash_rect, "color",
			Color(1.0, 0.84, 0.0, 0.0),  0.25 * duration_mult)

	_flash_tween.tween_callback(func() -> void: _flash_rect.visible = false)


func _play_banner(duration_mult: float) -> void:
	_banner_label.visible    = true
	_banner_label.modulate.a = 0.0
	var hold: float = 1.5 * duration_mult
	var tween: Tween = create_tween()
	tween.tween_property(_banner_label, "modulate:a", 1.0, 0.2)
	tween.tween_interval(hold)
	tween.tween_property(_banner_label, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func() -> void: _banner_label.visible = false)


func _play_shake(duration_mult: float) -> void:
	var vp: SubViewport = get_viewport() as SubViewport
	if vp == null:
		return
	var original: Vector2 = _root.position
	var amp: float = SHAKE_AMPLITUDE
	var dur: float = SHAKE_DURATION * duration_mult
	var steps: int  = 8

	if _shake_tween:
		_shake_tween.kill()
	_shake_tween = create_tween()
	for i: int in steps:
		var offset: Vector2 = Vector2(
			randf_range(-amp, amp),
			randf_range(-amp, amp)
		)
		_shake_tween.tween_property(_root, "position", original + offset, dur / float(steps))
	_shake_tween.tween_property(_root, "position", original, 0.05)


func _play_sfx(grade: Grade) -> void:
	var sfx_name: String
	match grade:
		Grade.SMALL:   sfx_name = "sfx_profit_small"
		Grade.MEDIUM:  sfx_name = "sfx_profit_medium"
		Grade.LARGE:   sfx_name = "sfx_profit_large"
		_:             sfx_name = "sfx_profit_jackpot"
	AudioManager.play_sfx(sfx_name)


# ── Cancel ──

## Cancels all active effects immediately.
## Called at start of play() or on market close / screen change.
func _cancel_current() -> void:
	_is_playing = false
	if _rollup_tween:
		_rollup_tween.kill()
		_rollup_tween = null
	if _flash_tween:
		_flash_tween.kill()
		_flash_tween = null
	if _shake_tween:
		_shake_tween.kill()
		_shake_tween = null
	_rollup_label.visible = false
	_flash_rect.visible   = false
	_banner_label.visible = false
	if _particles:
		_particles.emitting = false
	if _root:
		_root.position = Vector2.ZERO


# ── Event Handlers ──

func _on_market_state_changed(new_state: GameClock.MarketState, _prev: GameClock.MarketState) -> void:
	## GDD §3-5: 장 마감 시 이펙트 즉시 종료.
	if new_state == GameClock.MarketState.MARKET_CLOSED:
		_cancel_current()


## GDD §3-5: 화면 클릭 시 즉시 종료 (이펙트 레이어에서 클릭 캡처 불가 — TradingScreen에서 처리).
## 이 메서드는 TradingScreen이 화면 탭 전환 등을 감지할 때 외부에서 호출.
func cancel_from_screen_change() -> void:
	_cancel_current()


# ── Speed Multiplier ──

func _get_speed_duration_mult() -> float:
	var speed: float = GameClock.get_speed_multiplier() if GameClock.has_method("get_speed_multiplier") else 1.0
	if speed >= 4.0:
		return SPEED_4X_DURATION_MULT
	if speed >= 2.0:
		return SPEED_2X_DURATION_MULT
	return 1.0

