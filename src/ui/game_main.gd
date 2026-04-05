## Game entry point — initializes season and loads TradingScreen.
## This replaces TestMain.tscn as the main scene for actual gameplay.
extends Node


func _ready() -> void:
	# Apply white-base theme defaults (font colors, panel styles)
	ThemeSetup.apply_base_theme(get_tree())

	# 1. Set initial sim cash
	CurrencySystem.init_first_season()

	# 2. Prime PortfolioManager cache so SeasonManager can read total_assets
	#    when the player presses "시즌 시작" (cache is 0 until first tick otherwise).
	PortfolioManager.update_valuation(CurrencySystem.get_sim_cash(), 0)

	# 3. Load MainScreen (F1/F2/F3 tabs). Season start is triggered by the
	#    "시즌 시작" button in TradingScreen's PRE_MARKET state (ADR-006, TD-08).
	var screen_scene: PackedScene = load("res://src/ui/MainScreen.tscn")
	var screen: Control = screen_scene.instantiate()
	add_child(screen)
