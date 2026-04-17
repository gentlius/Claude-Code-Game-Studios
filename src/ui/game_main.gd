## Game entry point. Flow: SplashScreen → StartScreen → (IntroSequence?) → MainScreen.
## Manages top-level scene switching: Splash → Start → Main, and F4 Main → Start.
## GDD: design/gdd/start-screen.md §3-1
extends Node

# ── Node References ──

var _splash: Control = null
var _start_screen: Control = null
var _main_screen: Control = null
var _intro: Control = null
var _lifestyle_screen: Control = null
var _saving_overlay: Node = null

## Track whether the current MainScreen was created via new game (needs initial save).
var _pending_initial_save: bool = false


func _ready() -> void:
	ThemeSetup.apply_base_theme(get_tree())

	# SavingOverlay: CanvasLayer layer=10, stays alive for entire session
	_saving_overlay = load("res://src/ui/saving_overlay.gd").new()
	add_child(_saving_overlay)

	_show_splash()


# ── Splash ──

func _show_splash() -> void:
	_splash = load("res://src/ui/splash_screen.gd").new()
	add_child(_splash)
	_splash.splash_finished.connect(_on_splash_finished)


func _on_splash_finished() -> void:
	_splash.queue_free()
	_splash = null
	_show_start_screen()


# ── Start Screen ──

func _show_start_screen() -> void:
	_start_screen = load("res://src/ui/start_screen.gd").new()
	add_child(_start_screen)
	_start_screen.slot_selected.connect(_on_slot_selected)
	_start_screen.new_game_confirmed.connect(_on_new_game_confirmed)


func _on_slot_selected(id: int) -> void:
	_start_screen.queue_free()
	_start_screen = null
	_pending_initial_save = false

	var ok: bool = SaveSystem.load_slot(id)
	if not ok:
		# 로드 실패 — StartScreen으로 복귀 (EC-10)
		push_error("GameMain: 슬롯 %d 로드 실패 — StartScreen으로 복귀" % id)
		_show_start_screen()
		return

	_load_main_screen()


func _on_new_game_confirmed(slot_id: int) -> void:
	_start_screen.queue_free()
	_start_screen = null
	_pending_initial_save = true

	# Reset ALL autoloads so a new game starts from a clean slate.
	# Order: GameClock first (stops ticks), then gameplay, then economy.
	GameClock.reset()
	NewsEventSystem.reset()
	PriceEngine.reset()
	OrderEngine.reset()
	AiCompetitor.reset()
	XpSystem.reset()
	SkillTree.reset()
	SeasonManager.reset()
	PortfolioManager.reset()
	CurrencySystem.reset()

	# 모든 autoload 리셋 완료 — 가격 데이터를 DB에서 로드해 UI 생성 전에 유효 상태로 만든다.
	# 이후 get_current_price()는 언제나 base_price를 반환하므로 UI fallback 불필요.
	PriceEngine.init_first_season()

	# slot_id는 SaveSystem.create_slot()이 이미 설정했으므로 active_slot_id가 맞음
	CurrencySystem.init_first_season()
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)

	# 인트로 시퀀스 — 새 게임 시 항상 재생 (GDD intro-sequence.md §3-1)
	var IntroScript = load("res://src/ui/intro_sequence.gd")
	_intro = IntroScript.new()
	add_child(_intro)
	_intro.intro_finished.connect(_on_intro_finished)


func _on_intro_finished() -> void:
	_intro.queue_free()
	_intro = null
	_load_main_screen()


# ── Main Screen ──

func _load_main_screen() -> void:
	var screen_scene: PackedScene = load("res://src/ui/MainScreen.tscn")
	_main_screen = screen_scene.instantiate()
	add_child(_main_screen)
	_main_screen.exit_to_start_requested.connect(_on_exit_to_start_requested)
	# Show lifestyle screen only AFTER the player confirms the season-end settlement dialog.
	# offseason_settled fires immediately on SeasonManager.on_season_ended (before confirmation),
	# which would stack the lifestyle screen behind/over the settlement dialog.
	# Instead, watch GameClock leave SEASON_END — that happens on GameClock.confirm_transition()
	# which TradingScreen calls when settlement_confirmed fires.
	# process_offseason() has already run by this point (fired on on_season_ended).
	GameClock.on_market_state_changed.connect(_on_clock_state_for_lifestyle)

	# 새 게임: MainScreen 준비 완료 후 초기 상태 1회 저장 (GDD §3-5 Step 6)
	if _pending_initial_save and SaveSystem.active_slot_id >= 0:
		_pending_initial_save = false
		SaveSystem.save_slot(SaveSystem.active_slot_id)


# ── Lifestyle Screen ──

## Fired on every GameClock state transition while MainScreen is alive.
## Shows LifestyleScreen when the clock leaves SEASON_END (= player confirmed season dialog).
func _on_clock_state_for_lifestyle(
	_new_state: GameClock.MarketState, prev_state: GameClock.MarketState
) -> void:
	if prev_state == GameClock.MarketState.SEASON_END:
		_show_lifestyle_screen()


## Shows LifestyleScreen after the season settlement dialog is confirmed.
## GDD lifestyle-spending.md §3-1. process_offseason() has already run by this point.
func _show_lifestyle_screen() -> void:
	# Guard: don't stack screens if already showing (e.g. load-slot edge case).
	if _lifestyle_screen != null:
		return

	_lifestyle_screen = load("res://src/ui/lifestyle_screen.gd").new()
	add_child(_lifestyle_screen)
	# LifestyleScreen emits lifestyle_screen_closed when the player clicks "다음 시즌 시작".
	_lifestyle_screen.lifestyle_screen_closed.connect(_on_lifestyle_screen_closed)

	# Save immediately on screen entry (GDD §5 EC: 라이프스타일 소비 화면 중 앱 종료 → 화면 진입 시 즉시 세이브)
	if SaveSystem.active_slot_id >= 0:
		SaveSystem.save_slot(SaveSystem.active_slot_id)


func _on_lifestyle_screen_closed() -> void:
	if _lifestyle_screen != null:
		_lifestyle_screen.queue_free()
		_lifestyle_screen = null


func _on_exit_to_start_requested() -> void:
	# F4 나가기: MainScreen 제거 후 StartScreen 표시. 저장 없음(자동 저장 기반).
	if GameClock.on_market_state_changed.is_connected(_on_clock_state_for_lifestyle):
		GameClock.on_market_state_changed.disconnect(_on_clock_state_for_lifestyle)
	_main_screen.queue_free()
	_main_screen = null
	_show_start_screen()
