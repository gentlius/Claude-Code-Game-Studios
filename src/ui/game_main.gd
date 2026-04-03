## Game entry point — initializes season and loads TradingScreen.
## This replaces TestMain.tscn as the main scene for actual gameplay.
extends Node


func _ready() -> void:
	# Apply white-base theme defaults (font colors, panel styles)
	ThemeSetup.apply_base_theme(get_tree())

	# Initialize season systems
	CurrencySystem.init_season_seed()
	GameClock.start_season()

	# Load and add the TradingScreen
	var screen_scene: PackedScene = load("res://src/ui/TradingScreen.tscn")
	var screen: Control = screen_scene.instantiate()
	add_child(screen)
