# HTML5 / PixiJS — Animation Module

**Last verified:** 2026-06-11

Sprite animation, tweening with GSAP, Pixi Ticker integration, skeletal
animation (Spine), and timing patterns for game feel.

---

## Three Layers of Animation

| Layer | Tool | Use For |
|-------|------|---------|
| Frame animation (sprite sheets) | `AnimatedSprite` | Character walk cycles, explosions |
| Tweening (interpolation) | GSAP or manual | Menu transitions, card flips, UI motion |
| Skeletal | Spine / DragonBones | Complex character animation, IK |

---

## AnimatedSprite (Frame Animation)

```ts
import { Assets, AnimatedSprite, Texture } from 'pixi.js';

const sheet = await Assets.load('assets/player.json');   // spritesheet

const idleFrames = Object.values(sheet.animations.idle);  // Texture[]
const player = new AnimatedSprite(idleFrames);
player.animationSpeed = 0.15;
player.loop = true;
player.play();

// Switch animation
function setAnim(name: 'idle' | 'walk' | 'jump') {
  player.textures = sheet.animations[name];
  player.play();
}
```

### Spritesheet Format

Use TexturePacker JSON Hash with named animation groups, or Aseprite export
with explicit frame tags:

```json
{
  "frames": { "player_idle_01.png": { ... }, "player_walk_01.png": { ... } },
  "animations": {
    "idle": ["player_idle_01.png", "player_idle_02.png"],
    "walk": ["player_walk_01.png", "player_walk_02.png", "player_walk_03.png"]
  }
}
```

PixiJS parses `animations` directly into `sheet.animations[name]`.

---

## GSAP Tweening

GSAP picks up Pixi properties via direct property access — no plugin needed.

```ts
import { gsap } from 'gsap';

// Simple tween
gsap.to(card, { x: 400, duration: 0.5, ease: 'power2.out' });

// Chained sequence
gsap.timeline()
  .to(card, { scale: 1.2, duration: 0.2 })
  .to(card, { rotation: Math.PI, duration: 0.4 })
  .to(card, { scale: 1.0, duration: 0.2 });

// Pixi-specific properties
gsap.to(sprite.scale, { x: 1.5, y: 1.5, duration: 0.3 });
gsap.to(sprite, { alpha: 0, duration: 0.3, onComplete: () => sprite.destroy() });
```

### Eases for Game Feel

| Ease | Use |
|------|-----|
| `'power2.out'` | Most UI motion (decelerating arrival) |
| `'back.out(1.7)'` | Overshoot landing (bouncy cards) |
| `'elastic.out(1, 0.3)'` | Spring effect (button press release) |
| `'expo.in'` | Whoosh-out (exit transitions) |
| `'sine.inOut'` | Continuous loops (bobbing, floating) |
| `'steps(N)'` | Choppy / 8-bit style |

### Ticker Integration

GSAP runs on its own RAF loop by default. To synchronize with Pixi's Ticker
(for pause/resume in sync with game time):

```ts
import { gsap } from 'gsap';
import { Ticker } from 'pixi.js';

gsap.ticker.lagSmoothing(0);   // disable GSAP's own smoothing
gsap.ticker.remove(gsap.updateRoot);  // stop GSAP's auto-tick

Ticker.shared.add((ticker) => {
  gsap.updateRoot(ticker.lastTime / 1000);  // drive GSAP from Pixi
});
```

Now `Ticker.shared.stop()` pauses both Pixi rendering AND GSAP tweens.

---

## Manual Tweening (No Library)

For simple cases or when you want full control:

```ts
class Tween {
  private elapsed = 0;
  constructor(
    private target: any,
    private prop: string,
    private from: number,
    private to: number,
    private duration: number,
    private ease: (t: number) => number = (t) => t,
  ) {}

  update(dt: number): boolean {
    this.elapsed += dt;
    const t = Math.min(this.elapsed / this.duration, 1);
    this.target[this.prop] = this.from + (this.to - this.from) * this.ease(t);
    return t < 1;
  }
}

// Easing functions
const easeOutCubic = (t: number) => 1 - Math.pow(1 - t, 3);
const easeInOutQuad = (t: number) => t < 0.5 ? 2*t*t : 1 - Math.pow(-2*t+2, 2)/2;
```

When tween count > ~20, switch to GSAP — its scheduler is far more efficient
than naive arrays of tweens.

---

## Pixi Ticker

```ts
import { Ticker } from 'pixi.js';

// Add update (default: 60fps target)
Ticker.shared.add((ticker) => {
  const dt = ticker.deltaMS / 1000;   // seconds since last frame
  player.x += player.vx * dt;
});

// Limit FPS (battery saving)
Ticker.shared.maxFPS = 30;

// Pause / resume
Ticker.shared.stop();
Ticker.shared.start();

// Priority (run before/after default updates)
Ticker.shared.add(updateInput,   { priority: UPDATE_PRIORITY.HIGH });
Ticker.shared.add(updatePhysics, { priority: UPDATE_PRIORITY.NORMAL });
Ticker.shared.add(updateRender,  { priority: UPDATE_PRIORITY.LOW });
```

### Time-Based vs Frame-Based

| Approach | When | Pros / Cons |
|----------|------|-------------|
| `ticker.deltaMS / 1000` | Physics, movement | Frame-rate independent. Required for any time-sensitive logic. |
| `ticker.deltaTime` | Visual tweens, animations | Normalized to 60fps frames. Convenient for "advance by 1 frame" logic. |

**Default rule**: use `deltaMS` for game logic. Use `deltaTime` only for legacy
60fps-locked animations.

### Fixed Timestep Game Loop

```ts
const FIXED_DT = 1 / 60;  // 60 game updates per second
let accumulator = 0;

Ticker.shared.add((ticker) => {
  accumulator += ticker.deltaMS / 1000;
  while (accumulator >= FIXED_DT) {
    updateGameLogic(FIXED_DT);    // deterministic
    accumulator -= FIXED_DT;
  }
  const alpha = accumulator / FIXED_DT;
  interpolateRender(alpha);       // smooth interpolation between game states
});
```

Use this when:
- Physics needs determinism (replays, multiplayer)
- Game logic must be reproducible
- High-refresh-rate displays (120Hz, 144Hz) should not run logic faster

---

## Particles

For 100s-1000s of particles, use `ParticleContainer`:

```ts
import { ParticleContainer, Particle, Texture } from 'pixi.js';

const pc = new ParticleContainer({
  dynamicProperties: {
    position: true,
    scale: false,
    rotation: false,
    color: false,
  },
});
pc.boundsArea = new Rectangle(0, 0, app.renderer.width, app.renderer.height);

interface MyParticle {
  particle: Particle;
  vx: number; vy: number; life: number;
}

const particles: MyParticle[] = [];

function spawn(x: number, y: number, texture: Texture) {
  const p = new Particle({ texture, x, y });
  pc.addParticle(p);
  particles.push({ particle: p, vx: (Math.random()-0.5)*200, vy: -200, life: 1 });
}

Ticker.shared.add((ticker) => {
  const dt = ticker.deltaMS / 1000;
  for (let i = particles.length - 1; i >= 0; i--) {
    const p = particles[i];
    p.particle.x += p.vx * dt;
    p.particle.y += p.vy * dt;
    p.vy += 500 * dt;   // gravity
    p.life -= dt;
    if (p.life <= 0) {
      pc.removeParticle(p.particle);
      particles.splice(i, 1);
    }
  }
});
```

**Why `ParticleContainer`**: Explicit batching, no per-particle bounds check,
no per-particle event system. 10-50x faster than `Container<Sprite>` for >500
particles.

---

## Spine (Skeletal)

For character animation more complex than sprite sheets, see
[`../PLUGINS.md`](../PLUGINS.md) for `@esotericsoftware/spine-pixi-v8`.

Basic usage:

```ts
import { Spine } from '@esotericsoftware/spine-pixi-v8';

const spineboy = Spine.from({ skeleton: 'spineboy.json', atlas: 'spineboy.atlas' });
spineboy.state.setAnimation(0, 'walk', true);
spineboy.skeleton.scaleX = 1;
app.stage.addChild(spineboy);
```

---

## Animation State Machines

For character logic, separate "what animation is playing" from "what the
character should be doing":

```ts
type AnimState = 'idle' | 'walk' | 'jump' | 'attack';

class Character {
  private state: AnimState = 'idle';
  private sprite: AnimatedSprite;

  setState(next: AnimState) {
    if (this.state === next) return;
    this.state = next;
    this.sprite.textures = sheet.animations[next];
    this.sprite.play();
  }
}
```

For complex behavior trees, use a library like XState — but for typical game
characters, an enum + switch is sufficient.

---

## Common Pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| Tween snaps to end on resume | Ticker stop doesn't pause GSAP | Drive GSAP from Pixi Ticker (above) |
| Animation jumps when switching | New textures applied mid-frame | Set `sprite.currentFrame = 0` after swap |
| AnimatedSprite stuck on last frame | `loop: false` and no callback | Use `onComplete: () => ...` to advance state |
| Particle "popcorn" snapping | Particle position not interpolated | Use fixed timestep + interpolation alpha |

---

## See Also

- [`rendering.md`](rendering.md) — Container hierarchy
- [`../PLUGINS.md`](../PLUGINS.md) — GSAP, Spine
- [`../current-best-practices.md`](../current-best-practices.md) — Ticker patterns
