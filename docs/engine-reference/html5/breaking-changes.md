# HTML5 / PixiJS — Breaking Changes by Version

**Last verified:** 2026-06-11

Authoritative source for API changes that will break v7-era or pre-v8 code patterns.
Read before suggesting any PixiJS, Vite, or Playwright API.

---

## PixiJS v7 → v8 (HIGH RISK — Near-complete rewrite)

### Package Structure

| Concept | v7 (DO NOT USE) | v8 (CURRENT) |
|---------|-----------------|--------------|
| Imports | `@pixi/app`, `@pixi/sprite`, etc. | Single `pixi.js` package |

```ts
// v7 — broken
import { Application } from '@pixi/app';
import { Sprite } from '@pixi/sprite';

// v8 — correct
import { Application, Sprite } from 'pixi.js';
```

### Application Initialization

**v7**: synchronous constructor. **v8**: must call `await app.init()` separately.

```ts
// v7 — broken
const app = new Application({ width: 800, height: 600 });

// v8 — correct
const app = new Application();
await app.init({ width: 800, height: 600, preference: 'webgpu' });
document.body.appendChild(app.canvas);  // v7: app.view → v8: app.canvas
```

### Graphics API (Completely Redesigned)

| v7 Pattern | v8 Equivalent |
|-----------|---------------|
| `beginFill(0xff0000)` | (removed — fill is terminal) |
| `endFill()` | `.fill(0xff0000)` after shape |
| `drawRect(x,y,w,h)` | `.rect(x,y,w,h)` |
| `drawCircle(x,y,r)` | `.circle(x,y,r)` |
| `drawEllipse(...)` | `.ellipse(...)` |
| `drawPolygon([...])` | `.poly([...])` |
| `drawRoundedRect(...)` | `.roundRect(...)` |
| `lineStyle(w, color)` | `.stroke({ width: w, color })` after shape |

```ts
// v7 — broken
const g = new Graphics()
  .beginFill(0xff0000)
  .drawRect(50, 50, 100, 100)
  .endFill();

// v8 — correct
const g = new Graphics()
  .rect(50, 50, 100, 100)
  .fill(0xff0000);
```

### Container & DisplayObject

- **`DisplayObject` removed** — `Container` is now the base class for all renderables
- **Leaf nodes no longer accept children**: `Sprite`, `Mesh`, `Graphics` will throw if `addChild` is called
- **`updateTransform()` removed** — use `onRender` callback instead
- **`cacheAsBitmap` → `cacheAsTexture()`** (method, not property)
- **`container.name` → `container.label`**
- **`getBounds()` returns `Bounds` object** — access `Rectangle` via `.rectangle`

```ts
// v7 — broken
sprite.name = 'player';
const rect = sprite.getBounds();

// v8 — correct
sprite.label = 'player';
const rect = sprite.getBounds().rectangle;
```

### Texture & TextureSource Split

**v7**: `BaseTexture` handles resource loading.
**v8**: Resource pre-loading is separate from `Texture`. Use `Assets.load()` for URLs.

```ts
// v7 — broken
const texture = Texture.from('player.png');  // loaded URLs

// v8 — correct
await Assets.load('player.png');
const texture = Texture.from('player.png');  // resolves from Assets cache only
```

For manual texture construction, use `TextureSource` subclasses (`ImageSource`,
`VideoSource`, `CanvasSource`).

### Assets System

```ts
// v7 — broken
Assets.add('bunny', 'bunny.png');

// v8 — correct
Assets.add({ alias: 'bunny', src: 'bunny.png' });
await Assets.load('bunny');
```

### ParticleContainer (Major Rework)

| v7 | v8 |
|----|----|
| Accepts `Sprite` children | Accepts only objects implementing `IParticle` |
| `container.addChild(sprite)` | `container.addParticle(new Particle(texture))` |
| Iterates `children` array | Iterates `particleChildren` array |
| Automatic bounds | **`boundsArea` must be set manually** |

```ts
// v8 — correct
const pc = new ParticleContainer({
  dynamicProperties: { position: true, scale: false, rotation: false },
});
pc.boundsArea = new Rectangle(0, 0, 800, 600);  // REQUIRED in v8
pc.addParticle(new Particle({ texture, x, y }));
```

### Filters

```ts
// v7 — broken
new Filter(vertex, fragment, uniforms);

// v8 — correct
new Filter({
  glProgram: GlProgram.from({ vertex, fragment }),
  resources: { uTime: { value: 0, type: 'f32' } },
});
```

Uniforms now require explicit `type` strings (`'f32'`, `'vec2<f32>'`, etc.)

### Constructors — Object-Based

Most filter/effect constructors moved from positional args to options objects:

```ts
// v7 — broken
new BlurFilter(8, 4, 1, 5);

// v8 — correct
new BlurFilter({ strength: 8, quality: 4, resolution: 1, kernelSize: 5 });
```

### Mesh Class Renames

| v7 | v8 |
|----|----|
| `SimpleMesh` | `MeshSimple` |
| `SimplePlane` | `MeshPlane` |
| `SimpleRope` | `MeshRope` |
| `NineSlicePlane` | `NineSliceSprite` |

### Ticker

```ts
// v7 — broken
Ticker.shared.add((delta) => {
  sprite.x += delta * speed;
});

// v8 — correct
Ticker.shared.add((ticker) => {
  sprite.x += ticker.deltaTime * speed;
});
```

Callback receives the `Ticker` instance, not a delta number.

### Settings & Adapters

| v7 | v8 |
|----|----|
| `settings.RESOLUTION = 2` | `AbstractRenderer.defaultOptions.resolution = 2` |
| `settings.ADAPTER = X` | `DOMAdapter.set(X)` |
| `SCALE_MODES.LINEAR` | `'linear'` (plain strings) |
| `WRAP_MODES.CLAMP` | `'clamp-to-edge'` |
| `utils.hex2string(...)` | direct import: `import { hex2string } from 'pixi.js'` |

### `Application.view` → `Application.canvas`

Renamed for clarity.

---

## Vite 5 → 6 → 7 → 8 (HIGH RISK — Toolchain swap)

### Vite 5 → 6 (Late 2024)
- **Environment API** introduced — plugins migrating to multi-environment model
- Server runtime separated from build (`server.environments`, `build.rollupOptions` interactions changed)
- Node.js minimum: 18.x

### Vite 6 → 7 (Mid 2025)
- Default `target` bumped: `'modules'` → `'baseline-widely-available'`
- Node.js minimum: 20.x
- Some plugin hooks renamed in Environment API

### Vite 7 → 8 (Mar 2026) — Rolldown Swap
- **Bundler swap**: esbuild + Rollup → **Rolldown** (Rust-based) + Oxc
- Most user code unaffected, but **custom Rollup plugins may need adaptation**
- `lightningcss` is now a normal dependency (~+15 MB install)
- Some niche `optimizeDeps` flags renamed
- Build output should be byte-similar but not byte-identical to v7

**Strategy for BagelMVP-class projects**: PixiJS game code is bundler-agnostic.
The migration is mostly about `vite.config.ts` and plugin compatibility. Pin
`vite@^7` for stability if Rolldown plugin ecosystem is still catching up;
adopt `vite@^8` for new projects.

---

## Playwright (Lower Risk — Mostly Additive)

### 1.40 → 1.49+ (2025-2026)
- Device descriptor catalog expanded to 100+ devices
- Better touch event simulation (closer to real mobile)
- Improved WebKit parity (Safari rendering)
- Network throttling — finer-grained control
- `page.evaluate()` performance improvements

No major breaking changes; mostly drop-in upgrades. `@playwright/test ^1.40`
in BagelMVP works but lacks newer mobile device profiles.

---

## TypeScript 5.x — Notes

PixiJS 8 uses TypeScript-first design with extensive generics:
- `Container<ChildType extends Container>` — type-narrow child iteration
- `Assets.load<T = Texture>(url)` — typed asset returns
- `Sprite.from<T extends TextureSource>(source)` — generic texture sources

Code targeting `tsconfig` with `strict: true` is the assumed baseline. `any`
escape hatches are a smell — `pixijs-specialist` should flag.

---

## See Also

- [`deprecated-apis.md`](deprecated-apis.md) — quick lookup of v7→v8 patterns
- [`current-best-practices.md`](current-best-practices.md) — idiomatic v8 patterns
- [`modules/rendering.md`](modules/rendering.md) — WebGL vs WebGPU selection
