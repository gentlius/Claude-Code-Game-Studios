## SettingsScreen 단위 테스트
## GDD: design/gdd/settings-screen.md — AC-02, AC-03, AC-04, AC-05
extends GutTest

const SETTINGS_PATH: String = "user://game_settings.cfg"
const SettingsScreenScript = preload("res://src/ui/settings_screen.gd")

var _screen


func before_each() -> void:
	GameClock.reset()
	AudioManager.set_volume(1.0)
	AudioManager.set_muted(false)
	# 테스트용 cfg 파일 제거 (격리)
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	_screen = SettingsScreenScript.new()
	add_child_autofree(_screen)


func after_each() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	GameClock.reset()


# ── AC-02: 볼륨 슬라이더 → AudioManager ──────────────────────────────

func test_volume_slider_updates_audio_manager() -> void:
	# Act: 슬라이더 값 변경
	_screen._slider_volume.value = 50.0
	# Assert
	assert_almost_eq(AudioManager.get_volume(), 0.5, 0.001, "볼륨 0.5 반영")


func test_volume_slider_zero_sets_zero() -> void:
	_screen._slider_volume.value = 0.0
	assert_almost_eq(AudioManager.get_volume(), 0.0, 0.001, "볼륨 0 반영")


func test_volume_slider_max_sets_one() -> void:
	_screen._slider_volume.value = 100.0
	assert_almost_eq(AudioManager.get_volume(), 1.0, 0.001, "볼륨 1.0 반영")


# ── AC-03: 음소거 CheckButton → AudioManager ─────────────────────────

func test_mute_toggle_enables_mute() -> void:
	# Arrange: 초기 음소거 OFF
	assert_false(AudioManager.is_muted(), "초기 음소거 OFF")
	# Act
	_screen._chk_mute.button_pressed = true
	# Assert
	assert_true(AudioManager.is_muted(), "음소거 ON")


func test_mute_toggle_disables_mute() -> void:
	AudioManager.set_muted(true)
	_screen._chk_mute.set_pressed_no_signal(true)
	# Act
	_screen._chk_mute.button_pressed = false
	# Assert
	assert_false(AudioManager.is_muted(), "음소거 OFF")


# ── AC-04: 자동 감속 CheckButton → GameClock ─────────────────────────

func test_auto_slow_toggle_disables_auto_slow() -> void:
	# Arrange: 기본 ON
	assert_true(GameClock.get_auto_slow_on_event(), "초기 ON")
	# Act
	_screen._chk_auto_slow.button_pressed = false
	# Assert
	assert_false(GameClock.get_auto_slow_on_event(), "자동 감속 OFF")


func test_auto_slow_toggle_enables_auto_slow() -> void:
	GameClock.set_auto_slow_on_event(false)
	_screen._chk_auto_slow.set_pressed_no_signal(false)
	# Act
	_screen._chk_auto_slow.button_pressed = true
	# Assert
	assert_true(GameClock.get_auto_slow_on_event(), "자동 감속 ON")


# ── AC-05: game_settings.cfg 저장/복원 ───────────────────────────────

func test_auto_slow_persists_false_to_cfg() -> void:
	# Act: OFF로 변경 → cfg 저장됨
	_screen._chk_auto_slow.button_pressed = false
	# 새 인스턴스로 로드 검증
	var screen2 = SettingsScreenScript.new()
	add_child_autofree(screen2)
	assert_false(GameClock.get_auto_slow_on_event(), "로드 후 OFF 복원")


func test_auto_slow_persists_true_to_cfg() -> void:
	# OFF 저장 후 다시 ON으로 저장 → 새 스크린 로드 시 ON
	_screen._chk_auto_slow.button_pressed = false
	_screen._chk_auto_slow.button_pressed = true
	var screen2 = SettingsScreenScript.new()
	add_child_autofree(screen2)
	assert_true(GameClock.get_auto_slow_on_event(), "로드 후 ON 복원")


func test_auto_slow_defaults_true_without_cfg() -> void:
	# cfg 없을 때 기본값 ON
	assert_false(FileAccess.file_exists(SETTINGS_PATH), "cfg 없음 확인")
	var screen2 = SettingsScreenScript.new()
	add_child_autofree(screen2)
	assert_true(GameClock.get_auto_slow_on_event(), "기본값 ON")


# ── GameClock get/set API 계약 ────────────────────────────────────────

func test_game_clock_auto_slow_default_is_true() -> void:
	GameClock.reset()
	assert_true(GameClock.get_auto_slow_on_event(), "reset 후 기본값 true")


func test_game_clock_set_auto_slow_on_event() -> void:
	GameClock.set_auto_slow_on_event(false)
	assert_false(GameClock.get_auto_slow_on_event(), "false 설정")
	GameClock.set_auto_slow_on_event(true)
	assert_true(GameClock.get_auto_slow_on_event(), "true 복원")
