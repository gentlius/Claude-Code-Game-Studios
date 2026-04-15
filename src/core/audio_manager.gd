## Autoload — Manages SFX playback for game events.
## Phase 1 (Alpha): 4 core SFX events with programmatic placeholder sounds.
## GDD: design/gdd/audio.md
extends Node

# ── Constants ──

const SETTINGS_PATH: String = "user://audio_settings.cfg"
const SAMPLE_RATE: int = 22050
const DEFAULT_VOLUME: float = 1.0

# ── Tuning Knobs (GDD §7) ──

const SFX_ORDER_FREQ: float   = 220.0   ## 체결음 기본 주파수 (Hz)
const SFX_LEVEL_FREQS: Array[float] = [261.6, 329.6, 392.0]  ## 레벨업 아르페지오 C4→E4→G4
const SFX_VI_FREQS: Array[float]    = [330.0, 440.0]          ## VI 경보 E4→A4
const SFX_NEWS_FREQS: Array[float]  = [440.0, 330.0]          ## 뉴스 알림 A4→E4 하강

# ── State ──

var _master_volume: float = DEFAULT_VOLUME
var _muted: bool = false

var _player_order: AudioStreamPlayer
var _player_level: AudioStreamPlayer
var _player_vi: AudioStreamPlayer
var _player_news: AudioStreamPlayer
var _player_bgm: AudioStreamPlayer    ## BGM 전용 (루핑 트랙)
var _player_ui: AudioStreamPlayer     ## 파일 기반 UI SFX (스타트화면 등)
var _sfx_cache: Dictionary = {}       ## "category/name" → AudioStream 캐시


# ── Lifecycle ──

func _ready() -> void:
	_build_players()
	_generate_sfx()
	_load_settings()
	_connect_events()


func _build_players() -> void:
	_player_order = AudioStreamPlayer.new()
	_player_order.bus = "Master"
	add_child(_player_order)

	_player_level = AudioStreamPlayer.new()
	_player_level.bus = "Master"
	add_child(_player_level)

	_player_vi = AudioStreamPlayer.new()
	_player_vi.bus = "Master"
	add_child(_player_vi)

	_player_news = AudioStreamPlayer.new()
	_player_news.bus = "Master"
	add_child(_player_news)

	_player_bgm = AudioStreamPlayer.new()
	_player_bgm.bus = "Master"
	add_child(_player_bgm)

	_player_ui = AudioStreamPlayer.new()
	_player_ui.bus = "Master"
	add_child(_player_ui)


# ── SFX Generation ──

## Generates in-memory AudioStreamWAV placeholders. Real assets replace at Beta.
func _generate_sfx() -> void:
	# 체결음: 220Hz 삼각파 × 2 펄스 (0.08s each, 0.04s gap)
	_player_order.stream = _make_triangle_two_pulse(SFX_ORDER_FREQ, 0.08, 0.04)

	# 레벨업: C4→E4→G4 상승 아르페지오 (각 0.12s)
	_player_level.stream = _make_arpeggio(SFX_LEVEL_FREQS, 0.12)

	# VI 경보: E4→A4 2음 상승 (각 0.15s)
	_player_vi.stream = _make_arpeggio(SFX_VI_FREQS, 0.15)

	# 뉴스 알림: A4→E4 단음 하강 (각 0.1s)
	_player_news.stream = _make_arpeggio(SFX_NEWS_FREQS, 0.10)


## Triangle wave, two pulses with a gap.
func _make_triangle_two_pulse(freq: float, pulse_dur: float, gap_dur: float) -> AudioStreamWAV:
	var total_samples: int = int(SAMPLE_RATE * (pulse_dur * 2.0 + gap_dur))
	var pulse_samples: int = int(SAMPLE_RATE * pulse_dur)
	var gap_samples: int   = int(SAMPLE_RATE * gap_dur)
	var data: PackedByteArray = PackedByteArray()
	data.resize(total_samples * 2)  # 16-bit mono

	for i: int in range(total_samples):
		var sample_val: float = 0.0
		if i < pulse_samples or i >= pulse_samples + gap_samples:
			var local_i: int = i if i < pulse_samples else i - pulse_samples - gap_samples
			var t: float = float(local_i) / float(SAMPLE_RATE)
			# Triangle wave: 2 * abs(fmod(t*freq, 1.0) - 0.5)  scaled to [-1, 1]
			var phase: float = fmod(t * freq, 1.0)
			sample_val = (2.0 * absf(phase - 0.5) - 0.5) * 2.0
			# Fade out last 20% of each pulse
			var fade_start: int = int(pulse_samples * 0.8)
			var local_pulse: int = i if i < pulse_samples else i - pulse_samples - gap_samples
			if local_pulse > fade_start:
				sample_val *= 1.0 - float(local_pulse - fade_start) / float(pulse_samples - fade_start)

		var int_val: int = clampi(int(sample_val * 28000.0), -32768, 32767)
		data[i * 2]     = int_val & 0xFF
		data[i * 2 + 1] = (int_val >> 8) & 0xFF

	return _make_wav_stream(data)


## Sequential tones at given frequencies, each of `note_dur` seconds.
func _make_arpeggio(freqs: Array[float], note_dur: float) -> AudioStreamWAV:
	var note_samples: int = int(SAMPLE_RATE * note_dur)
	var total_samples: int = note_samples * freqs.size()
	var data: PackedByteArray = PackedByteArray()
	data.resize(total_samples * 2)

	for note_idx: int in range(freqs.size()):
		var freq: float = float(freqs[note_idx])
		var base: int = note_idx * note_samples
		var fade_start: int = int(note_samples * 0.75)
		for i: int in range(note_samples):
			var t: float = float(i) / float(SAMPLE_RATE)
			var val: float = sin(TAU * freq * t)
			if i > fade_start:
				val *= 1.0 - float(i - fade_start) / float(note_samples - fade_start)
			var int_val: int = clampi(int(val * 28000.0), -32768, 32767)
			data[(base + i) * 2]     = int_val & 0xFF
			data[(base + i) * 2 + 1] = (int_val >> 8) & 0xFF

	return _make_wav_stream(data)


func _make_wav_stream(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format   = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo   = false
	stream.data     = data
	return stream


# ── Settings ──

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		# EC-03: 설정 파일 없으면 기본값으로 초기화 (상태가 이전 값으로 오염되지 않도록)
		_master_volume = DEFAULT_VOLUME
		_muted = false
		_apply_volume()
		return
	_master_volume = cfg.get_value("audio", "master_volume", DEFAULT_VOLUME)
	_muted         = cfg.get_value("audio", "muted", false)
	_apply_volume()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", _master_volume)
	cfg.set_value("audio", "muted", _muted)
	cfg.save(SETTINGS_PATH)


func _apply_volume() -> void:
	var db: float = linear_to_db(_master_volume) if not _muted else -80.0
	for player: AudioStreamPlayer in [_player_order, _player_level, _player_vi, _player_news,
			_player_bgm, _player_ui]:
		player.volume_db = db


# ── Public API ──

## Set master volume [0.0, 1.0] and persist.
func set_volume(volume: float) -> void:
	_master_volume = clampf(volume, 0.0, 1.0)
	_apply_volume()
	_save_settings()


## Toggle or set mute and persist.
func set_muted(muted: bool) -> void:
	_muted = muted
	_apply_volume()
	_save_settings()


## Returns the master volume (0.0–1.0).
func get_volume() -> float:
	return _master_volume


## Returns true if audio is currently muted.
func is_muted() -> bool:
	return _muted


# ── Public SFX API ──
## Called directly by UI components at the moment the visual effect starts,
## so sound and animation are frame-accurate. AudioManager no longer connects
## to engine-level signals; the UI is the authoritative trigger source.

## Play order-fill SFX. Call from OrderPanel._flash_order_panel().
func play_order_sfx() -> void:
	if _muted:
		return  # EC-02
	_player_order.play()


## Play level-up SFX. Call from LevelUpBanner.show_level_up() at Phase 1 flash.
func play_level_up_sfx() -> void:
	if _muted:
		return
	_player_level.play()


## Play VI/CB alert SFX. Call from TradingScreen._on_system_event_alert().
func play_vi_sfx() -> void:
	if _muted:
		return
	_player_vi.play()


## Play news toast SFX. Call from ToastManager._show_toast().
func play_news_sfx() -> void:
	if _muted:
		return
	_player_news.play()


## Play BGM track from assets/audio/bgm/{track_name}.ogg. Loops automatically.
## Call from StartScreen._ready() and any screen with persistent background music.
func play_bgm(track_name: String) -> void:
	var stream: AudioStream = _load_audio_file("bgm", track_name)
	if stream == null:
		return
	if _player_bgm.stream == stream and _player_bgm.playing:
		return  # 이미 같은 트랙 재생 중
	_player_bgm.stream = stream
	_player_bgm.play()  # volume_db가 muted 시 -80dB이므로 play()는 항상 호출
	# muted 상태에서도 play()를 호출해야 unmute 즉시 소리가 난다. (volume_db로 음소거 처리)


## Stop BGM playback.
func stop_bgm() -> void:
	_player_bgm.stop()


## Play a one-shot SFX from assets/audio/sfx/{sfx_name}.ogg.
## Call from UI components at the moment the visual effect starts.
func play_sfx(sfx_name: String) -> void:
	if _muted:
		return
	var stream: AudioStream = _load_audio_file("sfx", sfx_name)
	if stream == null:
		return
	_player_ui.stream = stream
	_player_ui.play()


## Load audio file with cache. Returns null and logs warning on miss.
func _load_audio_file(category: String, name: String) -> AudioStream:
	var key: String = "%s/%s" % [category, name]
	if _sfx_cache.has(key):
		return _sfx_cache[key]
	var path: String = "res://assets/audio/%s/%s.ogg" % [category, name]
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: 파일 없음 — %s" % path)
		return null
	var stream: AudioStream = ResourceLoader.load(path) as AudioStream
	_sfx_cache[key] = stream
	return stream


# ── Event Connections ──
# Intentionally empty — sounds are triggered by UI components via the public
# SFX API above, not by engine-level signals. This ensures sound fires at the
# same frame as the visual effect, not one or more ticks earlier.
func _connect_events() -> void:
	pass
