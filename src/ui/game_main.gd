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
var _ending_screen: Node = null
var _cache_loading: CanvasLayer = null

## Track whether the current MainScreen was created via new game (needs initial save).
var _pending_initial_save: bool = false


func _ready() -> void:
	ThemeSetup.apply_base_theme(get_tree())

	# SavingOverlay: CanvasLayer layer=10, stays alive for entire session
	_saving_overlay = load("res://src/ui/saving_overlay.gd").new()
	add_child(_saving_overlay)

	_show_splash()


# ── Splash ──

## SplashScreen 인스턴스를 생성·추가하고 splash_finished 시그널에 연결.
func _show_splash() -> void:
	_splash = load("res://src/ui/splash_screen.gd").new()
	add_child(_splash)
	_splash.splash_finished.connect(_on_splash_finished)


func _on_splash_finished() -> void:
	_splash.queue_free()
	_splash = null
	_show_start_screen()


# ── Start Screen ──

## StartScreen 인스턴스를 생성·추가하고 slot_selected/new_game_confirmed 시그널에 연결.
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

	# ADR-024: 로드 후 M1 프리히스토리 캐시 복구.
	# 디스크 캐시가 유효(버전·시드 일치)하면 재생성 없이 로드, 아니면 재생성.
	# 완료 전 메인 화면 진입 차단 — _show_cache_loading()이 batch_complete를 기다린다.
	M1CacheManager.reset()
	M1CacheManager.generate_all(StockDatabase.get_all_stocks(), OhlcvHistory.history_seed)
	_show_cache_loading()


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
	ShortSellingSystem.reset()
	LeverageManager.reset()
	CurrencySystem.reset()
	OhlcvHistory.reset()
	EtfManager.reset()
	FinancialReportSystem.reset()

	# 모든 autoload 리셋 완료 — 가격 데이터를 DB에서 로드해 UI 생성 전에 유효 상태로 만든다.
	# 이후 get_current_price()는 언제나 base_price를 반환하므로 UI fallback 불필요.
	PriceEngine.init_first_season()

	# slot_id는 SaveSystem.create_slot()이 이미 설정했으므로 get_active_slot_id()가 맞음
	CurrencySystem.init_first_season()
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)

	# 인트로 시퀀스 재생 중 전 종목 M1+D1 프리히스토리 배치 생성 (ADR-024 Phase 1).
	# OhlcvHistory.reset() 이후 → history_seed 확정 → 슬롯별 캐시 격리.
	# 인트로 종료 전 완료 안 되면 ChartRenderer가 spinner 표시 후 batch_complete에서 갱신.
	M1CacheManager.clear_slot_cache()
	M1CacheManager.generate_all(StockDatabase.get_all_stocks(), OhlcvHistory.history_seed)

	# 인트로 시퀀스 — 새 게임 시 항상 재생 (GDD intro-sequence.md §3-1)
	var IntroScript = load("res://src/ui/intro_sequence.gd")
	_intro = IntroScript.new()
	add_child(_intro)
	_intro.intro_finished.connect(_on_intro_finished)


func _on_intro_finished() -> void:
	_intro.queue_free()
	_intro = null
	# 인트로 종료 시 배치 생성이 완료됐으면 바로 진입, 아직이면 로딩 화면 대기.
	if M1CacheManager.is_batch_done():
		_load_main_screen()
	else:
		_show_cache_loading()


# ── Cache Loading Screen ──

## 전 종목 M1 배치 생성 완료 전까지 진입을 막는 심플 로딩 화면.
## batch_complete 수신 즉시 자신을 제거하고 _load_main_screen()을 호출한다.
func _show_cache_loading() -> void:
	_cache_loading = CanvasLayer.new()
	_cache_loading.layer = 5
	add_child(_cache_loading)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.07, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cache_loading.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.custom_minimum_size = Vector2(400, 80)
	vbox.offset_left   = -200
	vbox.offset_top    = -40
	vbox.offset_right  = 200
	vbox.offset_bottom = 40
	_cache_loading.add_child(vbox)

	var label := Label.new()
	label.text = tr("시장 데이터 준비 중...")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	bar.custom_minimum_size.y = 12
	vbox.add_child(bar)

	# 진행률 업데이트
	M1CacheManager.batch_progress.connect(
		func(done: int, total: int) -> void:
			if is_instance_valid(bar):
				bar.value = float(done) / float(total) if total > 0 else 0.0
	)
	# 완료 → 로딩 화면 제거 후 메인 화면 진입
	M1CacheManager.batch_complete.connect(_on_cache_loading_done, CONNECT_ONE_SHOT)


func _on_cache_loading_done() -> void:
	if is_instance_valid(_cache_loading):
		_cache_loading.queue_free()
	_cache_loading = null
	_load_main_screen()


# ── Main Screen ──

func _load_main_screen() -> void:
	var screen_scene: PackedScene = load("res://src/ui/MainScreen.tscn")
	_main_screen = screen_scene.instantiate()
	add_child(_main_screen)
	_main_screen.exit_to_start_requested.connect(_on_exit_to_start_requested)
	# Show lifestyle screen after every settlement confirmation (매일 장 마감 후).
	# TradingScreen emits spending_screen_requested once all reports for the day are confirmed.
	# GameClock.confirm_transition() is called from _on_lifestyle_screen_closed() instead of
	# directly in TradingScreen, so the clock only advances after the player closes the screen.
	# GDD: lifestyle-spending.md §3-1, trading-screen.md §규칙 6
	_main_screen.spending_screen_requested.connect(_on_spending_screen_requested)

	# ── Ending screens (S10-03) — GDD endings-achievements.md §3-1~3-3 ──
	# Single EndingScreen instance shared across all 3 endings.
	_ending_screen = load("res://src/ui/ending_screen.gd").new()
	add_child(_ending_screen)
	_ending_screen.new_game_requested.connect(_on_ending_new_game_requested)
	_ending_screen.continue_requested.connect(_on_ending_continue_requested)

	SeasonManager.on_hangang_ending_triggered.connect(
		func() -> void: _show_ending("bankruptcy")
	)
	SeasonManager.on_master_ending_triggered.connect(
		func() -> void: _show_ending("win")
	)
	LeverageManager.on_loan_shark_ending_triggered.connect(
		func(_stock_id: String, _net: int) -> void: _show_ending("leverage_crash")
	)

	# 새 게임: MainScreen 준비 완료 후 초기 상태 1회 저장 (GDD §3-5 Step 6)
	if _pending_initial_save and SaveSystem.get_active_slot_id() >= 0:
		_pending_initial_save = false
		SaveSystem.save_slot(SaveSystem.get_active_slot_id())


# ── Lifestyle Screen ──

## Called after all settlement reports for the day are confirmed (매일 장 마감 후).
## is_season_end: true when clock is SEASON_END — LifestyleScreen uses this for button text.
## GDD lifestyle-spending.md §3-1, trading-screen.md §규칙 6
func _on_spending_screen_requested(is_season_end: bool) -> void:
	_show_lifestyle_screen(is_season_end)


## Shows LifestyleScreen after settlement reports. Called every day after market close.
## GDD lifestyle-spending.md §3-1. process_market_close() has already run before reports confirmed.
func _show_lifestyle_screen(is_season_end: bool) -> void:
	# Guard: don't stack screens if already showing (e.g. load-slot edge case).
	if _lifestyle_screen != null:
		return

	_lifestyle_screen = load("res://src/ui/lifestyle_screen.gd").new()
	_lifestyle_screen.set_season_end_context(is_season_end)
	add_child(_lifestyle_screen)
	# LifestyleScreen emits lifestyle_screen_closed when the player clicks "다음 날/시즌".
	_lifestyle_screen.lifestyle_screen_closed.connect(_on_lifestyle_screen_closed)

	# Save immediately on screen entry (GDD §5 EC: 라이프스타일 소비 화면 중 앱 종료 → 화면 진입 시 즉시 세이브)
	if SaveSystem.get_active_slot_id() >= 0:
		SaveSystem.save_slot(SaveSystem.get_active_slot_id())


func _on_lifestyle_screen_closed() -> void:
	if _lifestyle_screen != null:
		_lifestyle_screen.queue_free()
		_lifestyle_screen = null
	# Advance the clock now that the spending window is closed (GDD: trading-screen.md §규칙 6).
	# This was previously called directly in TradingScreen on settlement_confirmed.
	GameClock.confirm_transition()


# ── Ending Screens ──

## Shows EndingScreen for [param ending_id]. Pauses the game clock during display.
## Called from SeasonManager / LeverageManager signal handlers. GDD endings-achievements.md.
func _show_ending(ending_id: String) -> void:
	GameClock.pause_request("ending_screen")
	_ending_screen.show_ending(ending_id)


## Player confirmed bad ending — delete save, return to StartScreen.
func _on_ending_new_game_requested() -> void:
	GameClock.release()
	var slot_id: int = SaveSystem.get_active_slot_id()
	if slot_id >= 0:
		SaveSystem.delete_slot(slot_id)

	# Tear down current session
	if _lifestyle_screen != null:
		_lifestyle_screen.queue_free()
		_lifestyle_screen = null
	if _ending_screen != null:
		_ending_screen.queue_free()
		_ending_screen = null
	if _main_screen != null:
		_main_screen.queue_free()
		_main_screen = null

	_show_start_screen()


## Player confirmed win ending — dismiss and resume (StartScreen or continue).
func _on_ending_continue_requested() -> void:
	GameClock.release()
	# Resume game after win ending: return to start screen (player may start a new run).
	if _lifestyle_screen != null:
		_lifestyle_screen.queue_free()
		_lifestyle_screen = null
	if _ending_screen != null:
		_ending_screen.queue_free()
		_ending_screen = null
	if _main_screen != null:
		_main_screen.queue_free()
		_main_screen = null

	_show_start_screen()


func _on_exit_to_start_requested() -> void:
	# F4 나가기: MainScreen 제거 후 StartScreen 표시. 저장 없음(자동 저장 기반).
	if _lifestyle_screen != null:
		_lifestyle_screen.queue_free()
		_lifestyle_screen = null
	_main_screen.queue_free()
	_main_screen = null
	_show_start_screen()
