## Unit tests for AudioManager autoload.
## GDD: design/gdd/audio.md
## Covers: AC-01 (signal connections), AC-06/07 (mute/volume persistence).
extends GutTest

# ── Helpers ──

func _reload_settings_from_string(cfg_text: String) -> void:
	## Write a ConfigFile string to the settings path so AudioManager._load_settings() can read it.
	var f := FileAccess.open(AudioManager.SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(cfg_text)
		f.close()


func _delete_settings_file() -> void:
	if FileAccess.file_exists(AudioManager.SETTINGS_PATH):
		DirAccess.remove_absolute(AudioManager.SETTINGS_PATH)


# ── AC-01: Signal connections ──

func test_autoload_signals_connected() -> void:
	## AudioManager._ready() connects OrderEngine, XpSystem, NewsEventSystem signals.
	assert_true(
		OrderEngine.on_order_filled.is_connected(AudioManager._on_order_filled),
		"on_order_filled not connected"
	)
	assert_true(
		XpSystem.on_level_up.is_connected(AudioManager._on_level_up),
		"on_level_up not connected"
	)
	assert_true(
		NewsEventSystem.on_news_display.is_connected(AudioManager._on_news_display),
		"on_news_display not connected"
	)


# ── AC-06: Mute persists after reload ──

func test_mute_persists_after_reload() -> void:
	## set_muted(true) saves to disk; _load_settings() restores muted state.
	AudioManager.set_muted(true)
	# Simulate reload by calling _load_settings() directly.
	AudioManager._load_settings()
	assert_true(AudioManager.is_muted(), "muted should persist after reload")
	# Cleanup
	AudioManager.set_muted(false)
	_delete_settings_file()


# ── AC-07: Volume persists after reload ──

func test_volume_persists_after_reload() -> void:
	## set_volume(0.5) saves to disk; _load_settings() restores volume.
	AudioManager.set_volume(0.5)
	AudioManager._load_settings()
	assert_almost_eq(AudioManager.get_volume(), 0.5, 0.001, "volume should persist after reload")
	# Cleanup
	AudioManager.set_volume(1.0)
	_delete_settings_file()


# ── EC-02: Muted skips playback ──

func test_muted_does_not_play() -> void:
	## When muted, _on_order_filled should not start playback.
	AudioManager.set_muted(true)
	var was_playing: bool = AudioManager._player_order.playing
	AudioManager._on_order_filled({})
	assert_false(AudioManager._player_order.playing, "muted: order player should not start")
	# Restore
	AudioManager.set_muted(false)
	if was_playing:
		AudioManager._player_order.play()


# ── EC-03: Missing settings file uses defaults ──

func test_missing_settings_file_uses_defaults() -> void:
	_delete_settings_file()
	AudioManager._load_settings()
	assert_almost_eq(AudioManager.get_volume(), AudioManager.DEFAULT_VOLUME, 0.001,
		"should use DEFAULT_VOLUME when settings missing")
	assert_false(AudioManager.is_muted(), "should not be muted when settings missing")
