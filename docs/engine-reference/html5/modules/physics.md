# HTML5 / PixiJS — Physics Module

**Last verified:** 2026-06-11

When to use a physics engine vs roll-your-own, integration patterns with PixiJS
scene graph, and tradeoffs between Matter.js / Box2D / no-physics.

---

## Decision Tree

```
Need physics?
├── No (most casual games)        → AABB / circle collision yourself
├── Light (bouncing, gravity)     → Matter.js
└── Heavy (constraints, joints)
    ├── Quality matters           → Box2D (WASM)
    └── Speed of integration      → Matter.js
```

**Rule of thumb**: If you can implement the collision in < 50 lines, do it
yourself. Physics engines add 50-500 KB to the bundle.

---

## Roll-Your-Own — AABB Collision

For grid games, platformers with rectangular bodies, or simple shooters:

```ts
interface AABB {
  x: number; y: number; w: number; h: number;
}

function intersects(a: AABB, b: AABB): boolean {
  return a.x < b.x + b.w && a.x + a.w > b.x &&
         a.y < b.y + b.h && a.y + a.h > b.y;
}

function sweepX(body: AABB, dx: number, solids: AABB[]): number {
  // Simple swept AABB — clamp dx if a collision occurs
  body.x += dx;
  for (const s of solids) {
    if (intersects(body, s)) {
      if (dx > 0) body.x = s.x - body.w;
      else        body.x = s.x + s.w;
      return 0;
    }
  }
  return dx;
}
```

For circles: distance check `(dx*dx + dy*dy) < (r1+r2)**2`. Faster than AABB
when both shapes are round.

---

## Spatial Partitioning

When entity count > ~50, naive N×N collision becomes the bottleneck. Options:

| Approach | Complexity | When |
|----------|-----------|------|
| None (N²) | O(n²) | < 50 entities |
| Uniform grid | O(n) avg | Many small entities, even distribution |
| Quadtree | O(n log n) | Wide range of entity sizes |
| Sweep & prune | O(n log n) | Entities mostly stationary |

```ts
// Uniform grid example
class Grid {
  private cells = new Map<string, AABB[]>();
  constructor(private cellSize: number) {}

  add(body: AABB) {
    const x0 = Math.floor(body.x / this.cellSize);
    const y0 = Math.floor(body.y / this.cellSize);
    const x1 = Math.floor((body.x + body.w) / this.cellSize);
    const y1 = Math.floor((body.y + body.h) / this.cellSize);
    for (let cx = x0; cx <= x1; cx++) {
      for (let cy = y0; cy <= y1; cy++) {
        const key = `${cx},${cy}`;
        if (!this.cells.has(key)) this.cells.set(key, []);
        this.cells.get(key)!.push(body);
      }
    }
  }

  query(body: AABB): AABB[] {
    const out = new Set<AABB>();
    // ... iterate overlapping cells, collect candidates
    return [...out];
  }

  clear() { this.cells.clear(); }
}
```

---

## Matter.js Integration

Best for: bouncing, gravity, joints, simple ragdoll, constraint puzzles.

```ts
import Matter from 'matter-js';
import { Container, Sprite, Ticker } from 'pixi.js';

const engine = Matter.Engine.create({
  gravity: { x: 0, y: 1 },
});

// One Matter body per game entity
const ball = Matter.Bodies.circle(100, 0, 20, { restitution: 0.8 });
Matter.Composite.add(engine.world, ball);

// One Pixi sprite per body
const ballSprite = new Sprite(ballTexture);
ballSprite.anchor.set(0.5);

// Sync each tick
Ticker.shared.add((ticker) => {
  Matter.Engine.update(engine, ticker.deltaMS);
  ballSprite.x = ball.position.x;
  ballSprite.y = ball.position.y;
  ballSprite.rotation = ball.angle;
});
```

### Pattern: Entity wraps both body and sprite

```ts
class Ball {
  body: Matter.Body;
  sprite: Sprite;

  constructor(x: number, y: number, texture: Texture) {
    this.body = Matter.Bodies.circle(x, y, 20, { restitution: 0.8 });
    this.sprite = new Sprite(texture);
    this.sprite.anchor.set(0.5);
  }

  sync() {
    this.sprite.x = this.body.position.x;
    this.sprite.y = this.body.position.y;
    this.sprite.rotation = this.body.angle;
  }
}
```

### Collision Events

```ts
Matter.Events.on(engine, 'collisionStart', (e) => {
  for (const pair of e.pairs) {
    const a = pair.bodyA;
    const b = pair.bodyB;
    // identify via body.label or custom property
  }
});
```

### Fixed Timestep

For deterministic physics (replays, network sync), use a fixed timestep:

```ts
let accumulator = 0;
const STEP_MS = 1000 / 60;

Ticker.shared.add((ticker) => {
  accumulator += ticker.deltaMS;
  while (accumulator >= STEP_MS) {
    Matter.Engine.update(engine, STEP_MS);
    accumulator -= STEP_MS;
  }
  // sync sprites once per render frame, not per physics step
  for (const e of entities) e.sync();
});
```

---

## Box2D (WASM)

Use when physics quality is core to gameplay (Angry Birds class).

```ts
import { Box2D } from 'box2d-wasm';

const Box2DInstance = await Box2D();
const world = new Box2DInstance.b2World(new Box2DInstance.b2Vec2(0, 10));

// ... heavier API surface, see box2d-wasm docs
```

**Tradeoffs vs Matter**:
- ✅ More accurate solver, fewer artifacts
- ✅ Better continuous collision detection (no tunneling at high speed)
- ❌ WASM blob adds ~400-500KB to bundle
- ❌ Steeper API
- ❌ Async init (`await Box2D()`)

---

## Pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| Sprite snaps far each frame | Physics ms ≠ render ms | Use `ticker.deltaMS`, not a fixed 16.6 |
| Bodies tunneling through walls | Frame too long, body too fast | Cap `deltaMS` at e.g. 32, or use continuous collision |
| Jitter at rest | Floating-point noise | Set `sleepThreshold` lower, or freeze when velocity < epsilon |
| Wrong rotation direction | Pixi y-down vs physics y-up | Most JS physics engines also y-down — usually fine; verify with one test body |
| Restitution doesn't bounce | Both bodies need restitution | `restitution` from contact uses max of both bodies |

---

## When NOT to Use Physics

- Tap puzzles (Bejeweled-class) — board logic, no physics needed
- Tile-based platformers — write a `move_x(amount)` + `move_y(amount)` with AABB cast
- Card games — animations via GSAP, no physics
- Top-down shooters with fixed-speed bullets — write yourself
- Simple particle systems — `ParticleContainer` + manual velocity + gravity is faster than Matter for 1000s of particles

---

## See Also

- [`../PLUGINS.md`](../PLUGINS.md) — Matter, Box2D package info
- [`rendering.md`](rendering.md) — ParticleContainer for non-physics particles
