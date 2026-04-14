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


# ── AC-01: Direct-call SFX API 존재 확인 ──
# AudioManager는 신호 연결 방식에서 직접 호출 방식으로 변경됨.
# UI 컴포넌트가 시각 효과 시작 시점에 직접 play_*_sfx()를 호출한다.

func test_autoload_signals_connected() -> void:
	## AudioManager는 direct-call 방식: UI 컴포넌트가 play_*_sfx() 직접 호출.
	## 신호 연결 대신 public SFX API 존재를 확인한다.
	assert_true(AudioManager.has_method("play_order_sfx"),   "play_order_sfx 존재")
	assert_true(AudioManager.has_method("play_level_up_sfx"), "play_level_up_sfx 존재")
	assert_true(AudioManager.has_method("play_vi_sfx"),      "play_vi_sfx 존재")
	assert_true(AudioManager.has_method("play_news_sfx"),    "play_news_sfx 존재")


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
	## When muted, play_order_sfx() should not start playback.
	AudioManager.set_muted(true)
	var was_playing: bool = AudioManager._player_order.playing
	AudioManager.play_order_sfx()
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
