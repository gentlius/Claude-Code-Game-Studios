# HTML5 / PixiJS — Audio Module

**Last verified:** 2026-06-11

WebAudio basics, Howler.js patterns, mobile audio unlock, audio sprites, and
common pitfalls.

---

## The Mobile Audio Problem

Browsers (Chrome, Safari, mobile especially) block audio playback until
**the user makes a gesture** (tap, click, key). Naive code like
`new Audio('bgm.mp3').play()` will fail silently on first load.

**Solution**: Initialize audio after the first `pointerdown` event, OR use
a library (Howler) that handles the unlock automatically.

---

## Recommendation: Howler.js

For anything beyond a single ambient track, **use Howler**. See
[`../PLUGINS.md`](../PLUGINS.md) for rationale.

### Basic Setup

```ts
import { Howl, Howler } from 'howler';

const bgm = new Howl({
  src: ['assets/bgm.webm', 'assets/bgm.mp3'],   // fallback chain
  loop: true,
  volume: 0.5,
  html5: false,  // false = WebAudio (lower latency); true = HTML5 streaming (less RAM, higher latency)
});

const sfx_jump = new Howl({
  src: ['assets/sfx.webm', 'assets/sfx.mp3'],
  sprite: {
    jump: [0, 300],         // [start_ms, duration_ms]
    hit:  [500, 200],
    coin: [800, 250],
  },
});

// Wait for first user gesture before playing
window.addEventListener('pointerdown', () => {
  bgm.play();
}, { once: true });
```

### Audio Sprites (Critical for Mobile)

A single audio file with multiple sub-clips. Saves HTTP requests AND decode
work. Tool: [audiosprite](https://github.com/tonistiigi/audiosprite) generates
JSON config; pass it to Howler:

```ts
const sfx = new Howl({
  src: ['sfx.webm', 'sfx.mp3'],
  sprite: { /* generated */ },
});

sfx.play('jump');
sfx.play('coin');
```

### Volume Categories

```ts
// Global mixer
Howler.volume(0.8);                  // 0..1

// Per-category (manual via your own grouping)
const sfxHowls: Howl[] = [];
function setSfxVolume(v: number) {
  sfxHowls.forEach((h) => h.volume(v));
}
```

For complex mixing, build a simple mixer wrapper:

```ts
class AudioMixer {
  private masterVol = 1;
  private bgmVol = 0.5;
  private sfxVol = 0.8;

  private bgm: Howl | null = null;
  private sfx: Howl[] = [];

  setMaster(v: number) { this.masterVol = v; this.applyAll(); }
  setBgm(v: number)    { this.bgmVol = v;    this.applyBgm(); }
  setSfx(v: number)    { this.sfxVol = v;    this.applySfx(); }

  private applyAll()  { Howler.volume(this.masterVol); }
  private applyBgm()  { this.bgm?.volume(this.bgmVol); }
  private applySfx()  { this.sfx.forEach((h) => h.volume(this.sfxVol)); }
}
```

---

## Native WebAudio (No Library)

Use only when:
- You need procedural synthesis (oscillators, Tone.js territory)
- You have ONE ambient track and don't want a dependency
- You're building a rhythm game with sample-accurate scheduling

```ts
let ctx: AudioContext | null = null;

function initAudio() {
  if (ctx) return;
  ctx = new AudioContext();
}

window.addEventListener('pointerdown', initAudio, { once: true });

async function playSample(url: string) {
  if (!ctx) return;
  const buf = await fetch(url).then((r) => r.arrayBuffer());
  const audioBuf = await ctx.decodeAudioData(buf);
  const src = ctx.createBufferSource();
  src.buffer = audioBuf;
  src.connect(ctx.destination);
  src.start();
}
```

For "play same sound 100 times rapid" — pre-decode once, then reuse the
`AudioBuffer`. Don't re-decode each time.

---

## Format Strategy

| Format | Browser Support | Compression | Use |
|--------|----------------|-------------|-----|
| WebM (Opus) | Chrome/Firefox/Edge/Safari 14.1+ | Excellent | Primary |
| MP3 | Universal | Good | Fallback for older Safari |
| OGG | Firefox/Chrome (NOT Safari) | Excellent | Skip — WebM covers same niche |
| WAV | Universal | None | Dev only, never ship |

**Pattern**: provide WebM + MP3 in Howler's `src` array — Howler picks the
first the browser accepts.

```bash
# Convert with ffmpeg
ffmpeg -i bgm.wav -c:a libopus -b:a 96k bgm.webm
ffmpeg -i bgm.wav -c:a libmp3lame -b:a 128k bgm.mp3
```

---

## Bitrate Recommendations

| Content | Format | Bitrate | Notes |
|---------|--------|---------|-------|
| BGM (mono) | Opus / MP3 | 64-96 kbps | Mobile-friendly |
| BGM (stereo) | Opus | 96-128 kbps | Most mobile games are mono |
| SFX (short) | Opus | 64 kbps | Often imperceptible at lower |
| Voice | Opus | 32-64 kbps | Speech codec is efficient |

**Mobile total audio budget**: 3-5 MB for entire game. Each MB of audio is
seconds added to first-load on a 4G connection.

---

## Latency

WebAudio: ~20-50ms typical latency on modern devices. Acceptable for casual
games. NOT acceptable for rhythm games — those need:

- AudioWorklet for precise scheduling
- `audioContext.outputLatency` to compensate timings
- Visual cues offset by latency (don't show "tap now" at the same moment
  the user should hear)

For rhythm/music games, consider Tone.js (built on AudioWorklet) over Howler.

---

## Common Pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| Audio silent on mobile | No user gesture yet | Init Howler / AudioContext after first `pointerdown` |
| iOS Safari plays only one sound | WebAudio context suspended | Call `Howler.ctx.resume()` after each unlock event |
| BGM cut off when minimizing | Browser suspends inactive tabs | Use `Howler.autoSuspend = false` (drain battery — opt-in) |
| Clicking sound on play | Volume snaps from 0 to N | Use Howler `fade()` for ramps |
| SFX delayed on first play | First decode happens during play | Pre-warm: `sfx.play('jump'); sfx.stop();` at load |
| Stuttering on Android | Multiple Howl instances of same sound | Use one Howl with sprites, not multiple Howls |

---

## Volume Persistence

```ts
// Save
localStorage.setItem('vol_master', String(mixer.masterVol));
localStorage.setItem('vol_bgm',    String(mixer.bgmVol));
localStorage.setItem('vol_sfx',    String(mixer.sfxVol));

// Load on init
const masterVol = parseFloat(localStorage.getItem('vol_master') ?? '0.8');
```

For richer persistence, use IndexedDB (e.g., `idb-keyval` library).

---

## Testing Audio in Playwright

Playwright disables audio by default in headless mode. To test audio paths:

```ts
test.use({
  launchOptions: {
    args: ['--autoplay-policy=no-user-gesture-required'],
  },
});
```

Or just assert that the `play()` call was made (mock Howler in tests).

---

## See Also

- [`../PLUGINS.md`](../PLUGINS.md) — Howler, Tone.js, @pixi/sound
- [`input.md`](input.md) — First-gesture pattern
- [`../current-best-practices.md`](../current-best-practices.md) — Mobile loading strategy
