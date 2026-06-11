# HTML5 / PixiJS — Input Module

**Last verified:** 2026-06-11

PixiJS 8 Federated Events, native Pointer/Touch/Gamepad APIs, and
mobile-web-specific input concerns.

---

## Federated Events (v8 unified pointer model)

PixiJS 8 replaces v7's `interactive: true` with `eventMode`:

```ts
sprite.eventMode = 'static';   // hit-testable, doesn't move
sprite.cursor = 'pointer';

sprite.on('pointertap', (e: FederatedPointerEvent) => {
  console.log('tap at', e.global.x, e.global.y);
});
```

### `eventMode` Values

| Mode | Hit-Testable | Performance | Use For |
|------|--------------|-------------|---------|
| `'static'` | ✅ | Best | UI buttons, fixed game objects |
| `'dynamic'` | ✅ | OK | Game objects that move every tick |
| `'passive'` | Children only | Best | Container that holds interactive children but is not itself a target |
| `'auto'` | Inherits | OK | Default — rarely set explicitly |
| `'none'` | ❌ | Best | Pure-visual layers (background, particles) |

**Performance rule**: Default everything to `'none'` or `'passive'`; opt in
to `'static'` / `'dynamic'` only for things that need clicks. Hit testing is
not free.

---

## Event Types

| Event | When |
|-------|------|
| `pointerdown` | Touch start / mouse down |
| `pointerup` | Touch end / mouse up |
| `pointertap` | Down + up on same target without dragging |
| `pointermove` | Move during interaction |
| `pointerover` | Cursor entered (mouse only) |
| `pointerout` | Cursor left (mouse only) |
| `pointerupoutside` | Released outside the original target |
| `globalpointermove` | Move anywhere on stage (more expensive — opt-in via `Container.eventMode = 'static'` + listening on stage) |
| `wheel` | Scroll wheel — `FederatedWheelEvent` |

```ts
import { FederatedPointerEvent } from 'pixi.js';

button.on('pointertap', (e: FederatedPointerEvent) => {
  e.stopPropagation();   // don't bubble to parent containers
});
```

---

## Globals — `e.global` vs `e.local`

```ts
sprite.on('pointertap', (e) => {
  e.global    // stage coordinates (CSS pixel space adjusted for renderer)
  e.client    // viewport (window) coordinates
  e.screen    // physical screen pixels
  e.getLocalPosition(targetContainer)  // local coordinates of any container
});
```

Most game code wants `e.global` for "where on the play field did this happen?"

---

## Mobile Web Input

### iOS / Android Quirks

| Quirk | Cause | Fix |
|-------|-------|-----|
| Audio doesn't play until first tap | Browser autoplay policy | Initialize WebAudio (or Howler) only after first `pointerdown` |
| Tap delay (~300ms) on old WebViews | Legacy double-tap-to-zoom | Set viewport meta with `user-scalable=no` (use cautiously — accessibility tradeoff) |
| Pinch zoom interferes with game | Default browser gesture | `touch-action: none` CSS on canvas |
| Scroll bounce on iOS Safari | Overscroll | `overscroll-behavior: none` on body |
| Address bar resize mid-play | URL bar collapses | Use `visualViewport.height` not `window.innerHeight` |

### Required CSS Baseline

```css
html, body {
  margin: 0;
  padding: 0;
  width: 100%;
  height: 100%;
  overflow: hidden;
  overscroll-behavior: none;
  -webkit-tap-highlight-color: transparent;
  user-select: none;
  -webkit-user-select: none;
  touch-action: none;
}

canvas {
  display: block;
  touch-action: none;
}
```

### Tap Target Size

WCAG 2.5.5 recommends ≥48×48 CSS pixels. Mobile games should:
- Visible button: ≥48×48 px
- Game world tap target: hit area can be wider than sprite via `sprite.hitArea = new Rectangle(...)`

```ts
button.hitArea = new Rectangle(-20, -20, 140, 140);  // 100x100 sprite + 20px padding
```

---

## Multi-Touch

```ts
const activePointers = new Map<number, { x: number; y: number }>();

sprite.on('pointerdown', (e) => {
  activePointers.set(e.pointerId, { x: e.global.x, y: e.global.y });
});

sprite.on('pointermove', (e) => {
  if (activePointers.has(e.pointerId)) {
    activePointers.set(e.pointerId, { x: e.global.x, y: e.global.y });
  }
});

sprite.on('pointerup', (e) => activePointers.delete(e.pointerId));
sprite.on('pointerupoutside', (e) => activePointers.delete(e.pointerId));
```

For pinch / rotate gestures, track two pointers and compute delta distance / angle.

---

## Virtual Joystick (Mobile)

For action games on mobile web, neither tap nor swipe is enough — use a virtual
joystick. Either:

1. **Library**: `nipplejs` (DOM overlay) — see [`../PLUGINS.md`](../PLUGINS.md)
2. **Pixi-native**: draw the joystick as a `Container` with a base and a knob
   sprite; track pointerdown/move/up and compute the angle/distance

Pixi-native pattern:

```ts
class VirtualStick extends Container {
  private base: Sprite;
  private knob: Sprite;
  private pointerId: number | null = null;
  private radius = 60;

  public vector = { x: 0, y: 0 };  // normalized -1..1

  constructor(baseTex: Texture, knobTex: Texture) {
    super();
    this.base = new Sprite(baseTex);
    this.knob = new Sprite(knobTex);
    this.addChild(this.base, this.knob);
    this.eventMode = 'static';
    this.on('pointerdown', this.onDown);
    this.on('globalpointermove', this.onMove);
    this.on('pointerup', this.onUp);
    this.on('pointerupoutside', this.onUp);
  }

  private onDown = (e: FederatedPointerEvent) => {
    if (this.pointerId !== null) return;
    this.pointerId = e.pointerId;
  };

  private onMove = (e: FederatedPointerEvent) => {
    if (e.pointerId !== this.pointerId) return;
    const local = this.toLocal(e.global);
    const dist = Math.hypot(local.x, local.y);
    const clamped = Math.min(dist, this.radius);
    const angle = Math.atan2(local.y, local.x);
    this.knob.x = Math.cos(angle) * clamped;
    this.knob.y = Math.sin(angle) * clamped;
    this.vector.x = this.knob.x / this.radius;
    this.vector.y = this.knob.y / this.radius;
  };

  private onUp = (e: FederatedPointerEvent) => {
    if (e.pointerId !== this.pointerId) return;
    this.pointerId = null;
    this.knob.x = 0;
    this.knob.y = 0;
    this.vector.x = 0;
    this.vector.y = 0;
  };
}
```

---

## Keyboard (Desktop)

Pixi has NO built-in keyboard handling. Use native `window.addEventListener`:

```ts
const keys = new Set<string>();
window.addEventListener('keydown', (e) => keys.add(e.code));
window.addEventListener('keyup', (e) => keys.delete(e.code));

Ticker.shared.add(() => {
  if (keys.has('ArrowLeft')) player.x -= 5;
  if (keys.has('ArrowRight')) player.x += 5;
});
```

Use `KeyboardEvent.code` (layout-independent: `KeyW`, `Space`, `ArrowUp`)
not `KeyboardEvent.key` (layout-dependent).

---

## Gamepad API

Modern browsers support Xbox/PS controllers via the Gamepad API:

```ts
function pollGamepad() {
  const pads = navigator.getGamepads();
  for (const pad of pads) {
    if (!pad) continue;
    const lx = pad.axes[0];   // -1..1
    const ly = pad.axes[1];
    const aButton = pad.buttons[0].pressed;
    // ...
  }
}

Ticker.shared.add(pollGamepad);
```

Gamepad events DO NOT fire — must poll each frame.

---

## Pointer Lock (FPS-style mouse)

```ts
canvas.requestPointerLock();  // browser must accept after user gesture

document.addEventListener('mousemove', (e) => {
  if (document.pointerLockElement) {
    yaw -= e.movementX * sensitivity;
    pitch -= e.movementY * sensitivity;
  }
});
```

Rarely used in 2D PixiJS games; included for completeness.

---

## Visual Viewport (Mobile URL Bar)

The `window.innerHeight` is unreliable on mobile because of the collapsing
address bar. Use `visualViewport`:

```ts
function getViewportHeight(): number {
  return window.visualViewport?.height ?? window.innerHeight;
}

window.visualViewport?.addEventListener('resize', onResize);
```

---

## See Also

- [`rendering.md`](rendering.md) — Resize handling
- [`../current-best-practices.md`](../current-best-practices.md) — Mobile-specific CSS
- [`../PLUGINS.md`](../PLUGINS.md) — nipplejs, Hammer.js
