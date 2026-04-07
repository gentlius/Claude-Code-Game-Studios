## Game entry point — initializes season and loads TradingScreen.
## This replaces TestMain.tscn as the main scene for actual gameplay.
extends Node

const IntroSequenceScript = preload("res://src/ui/intro_sequence.gd")
var _intro: Node = null


func _ready() -> void:
	# Apply white-base theme defaults (font colors, panel styles)
	ThemeSetup.apply_base_theme(get_tree())

	# 1. Load save data if present (GDD: save-load.md). Restores currency/portfolio/xp/skills/season.
	#    If no save exists, init_first_season() runs normally below.
	var save_loaded: bool = SaveSystem.load_game()
	if not save_loaded:
		CurrencySystem.init_first_season()

	# 2. Prime PortfolioManager cache so SeasonManager can read total_assets
	#    when the player presses "시즌 시작" (cache is 0 until first tick otherwise).
	#    SaveSystem.load_game() already calls update_valuation internally after price restore,
	#    but call again here to cover the no-save (new game) path.
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)

	# 3. 최초 실행 시 인트로 시퀀스 표시. GDD: design/gdd/intro-sequence.md (S5-06)
	if not IntroSequenceScript.has_been_seen():
		_intro = IntroSequenceScript.new()
		add_child(_intro)
		_intro.intro_finished.connect(_on_intro_finished)
	else:
		_load_main_screen()


func _on_intro_finished() -> void:
	if _intro:
		_intro.queue_free()
		_intro = null
	_load_main_screen()


func _load_main_screen() -> void:
	# 4. Load MainScreen (F1/F2/F3 tabs). Season start is triggered by the
	#    "시즌 시작" button in TradingScreen's PRE_MARKET state (ADR-006, TD-08).
	var screen_scene: PackedScene = load("res://src/ui/MainScreen.tscn")
	var screen: Control = screen_scene.instantiate()
	add_child(screen)
