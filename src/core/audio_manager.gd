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
		return  # EC-03: 기본값 사용
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
	for player: AudioStreamPlayer in [_player_order, _player_level, _player_vi, _player_news]:
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


func get_volume() -> float:
	return _master_volume


func is_muted() -> bool:
	return _muted


# ── Event Connections ──

func _connect_events() -> void:
	OrderEngine.on_order_filled.connect(_on_order_filled)
	XpSystem.on_level_up.connect(_on_level_up)
	PriceEngine.on_vi_triggered.connect(_on_vi_triggered)
	NewsEventSystem.on_news_display.connect(_on_news_display)


# ── Signal Handlers ──

func _on_order_filled(_order: Dictionary) -> void:
	if _muted:
		return  # EC-02
	_player_order.play()


func _on_level_up(_level: int, _skill_points: int) -> void:
	if _muted:
		return
	_player_level.play()


func _on_vi_triggered(_stock_id: String, _is_upper: bool, _halt_ticks: int) -> void:
	if _muted:
		return
	_player_vi.play()


func _on_news_display(_entry: Dictionary) -> void:
	if _muted:
		return
	_player_news.play()
