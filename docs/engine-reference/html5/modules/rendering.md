# HTML5 / PixiJS — Rendering Module

**Last verified:** 2026-06-11

Renderer choice, Application lifecycle, scene graph, and v8-specific rendering
concerns. Read alongside [`../breaking-changes.md`](../breaking-changes.md).

---

## WebGL2 vs WebGPU (v8 Choice)

PixiJS 8 supports both backends through a unified `Renderer` interface.

| Backend | Browser Support (2026) | Performance | When to Use |
|---------|------------------------|-------------|-------------|
| WebGPU | Chrome/Edge/Firefox stable; Safari 17.5+ (gated on iOS) | Best | Default for new projects |
| WebGL2 | Universal | Excellent | Fallback / iOS Safari < 17.5 / older Android |
| WebGL1 | Universal | Adequate | Last-resort fallback (don't pin to it) |

```ts
const app = new Application();
await app.init({
  preference: 'webgpu',           // try first, fall back to WebGL2
  preferWebGLVersion: 2,           // never WebGL1 if avoidable
  powerPreference: 'high-performance',
});

// Check which renderer was actually selected
console.log(app.renderer.type);   // 'webgl' | 'webgpu'
```

**Don't** assume one backend or the other in custom shaders — use Pixi's
`Filter` API which generates both GLSL (WebGL) and WGSL (WebGPU). See
[`../current-best-practices.md`](../current-best-practices.md) Filters section.

---

## Application Lifecycle

```ts
// 1. Construct
const app = new Application();

// 2. Init (async, REQUIRED in v8)
await app.init({
  resizeTo: window,                 // auto-resize to viewport
  backgroundColor: 0x000000,
  antialias: true,
  resolution: window.devicePixelRatio || 1,
  autoDensity: true,                // CSS-pixel-aware sizing
  preference: 'webgpu',
});

// 3. Attach to DOM
document.body.appendChild(app.canvas);   // not app.view

// 4. Add scene
const root = new Container();
app.stage.addChild(root);

// 5. Tick (optional — Pixi starts the shared ticker by default)
app.ticker.add((ticker) => {
  // game update
});

// 6. Teardown (SPA navigation, hot-reload)
app.destroy(true, { children: true, texture: true, textureSource: true });
```

### Hot Reload Pitfalls (Vite Dev)

Vite HMR can leave orphaned WebGL contexts. Always call `app.destroy(true)`
before re-creating in dev. Pattern:

```ts
if (import.meta.hot) {
  import.meta.hot.dispose(() => {
    app.destroy(true, { children: true, texture: true, textureSource: true });
  });
}
```

---

## Resolution & High-DPI

```ts
await app.init({
  resolution: window.devicePixelRatio || 1,
  autoDensity: true,
});
```

- `resolution: 2` on a retina iPhone → renderer draws at 2x then CSS scales to logical size
- `autoDensity: true` → Pixi sets `canvas.style.width/height` to the CSS size automatically
- Without these, sprites look blurry on high-DPI displays

**Mobile perf tradeoff**: `resolution: 2` doubles fragment work. On low-end
phones, consider `resolution: Math.min(window.devicePixelRatio, 1.5)` to cap.

---

## Scene Graph (`Container` Tree)

```
app.stage (Container)
├── world (Container)             — game world, scaled/scrolled
│   ├── background (Sprite)
│   ├── entities (Container<Sprite>)
│   │   ├── player (Sprite)
│   │   └── enemies[i] (Sprite)
│   └── effects (ParticleContainer)
└── ui (Container)                — fixed overlay, unscaled
    ├── hud (Container)
    └── menu (Container)
```

**Why two top-level containers**: world transforms (camera, zoom) apply to
`world` only. UI stays unaffected by camera. Cleaner than untangling per-element
transforms.

### Children Limits (v8)

- `Sprite`, `Mesh`, `Graphics`: **NO children** (throws on `.addChild`)
- `Container`: unlimited
- `ParticleContainer`: holds `Particle` (NOT `Sprite`) via `addParticle()`

To group a Sprite with children, wrap both in a `Container`:

```ts
const entity = new Container();
entity.addChild(new Sprite(bodyTex));
entity.addChild(new Sprite(weaponTex));
```

---

## Batching & Draw Calls

PixiJS auto-batches sprites that share a texture (or atlas) within the same
container. Rules:

1. **Use spritesheets** — sprites from the same atlas batch automatically
2. **Avoid mid-batch state changes** — alternating filters, blend modes, or mask boundaries breaks batches
3. **`ParticleContainer` over `Container<Sprite>` for >500 similar sprites** — explicit batching, faster
4. **Profile with Pixi DevTools** — look at draw call count, not just FPS

### When Batching Breaks

| Action | Result |
|--------|--------|
| Different texture (no atlas) | New batch |
| Sprite with filter | New batch (filter render target) |
| Sprite with mask | New batch |
| Sprite with non-default blend mode | New batch |
| Adding a Graphics in the middle | New batch (Graphics uses different pipeline) |

---

## Camera / World Transform

PixiJS has no built-in camera — you transform the world container:

```ts
const world = new Container();
app.stage.addChild(world);

// "Camera" controls
function setCamera(targetX: number, targetY: number, zoom: number) {
  world.scale.set(zoom);
  world.x = app.renderer.width / 2 - targetX * zoom;
  world.y = app.renderer.height / 2 - targetY * zoom;
}
```

Lerp toward target each tick for smooth follow.

---

## Resizing & Letterboxing

For fixed-aspect-ratio games (most casual mobile):

```ts
const GAME_W = 720;
const GAME_H = 1280;

function fitGame() {
  const scale = Math.min(window.innerWidth / GAME_W, window.innerHeight / GAME_H);
  app.renderer.resize(GAME_W * scale, GAME_H * scale);
  world.scale.set(scale);
}

window.addEventListener('resize', fitGame);
fitGame();
```

For full-bleed games: `resizeTo: window` in init handles it.

---

## RenderTexture (Off-Screen Rendering)

```ts
const rt = RenderTexture.create({ width: 256, height: 256 });
app.renderer.render({ container: someScene, target: rt });

const cached = new Sprite(rt);
app.stage.addChild(cached);
```

Use for: minimap, paint-style mechanics, baking complex graphics once.

`Container.cacheAsTexture()` is the high-level convenience for "render me once
and reuse the result until I change."

---

## Common Pitfalls

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Blurry sprites on retina | `resolution: 1` ignored DPR | Set `resolution: window.devicePixelRatio`, `autoDensity: true` |
| Black screen on init | Forgot `await app.init()` | v8 init is async |
| `addChild` throws on sprite | Sprite cannot have children in v8 | Wrap in `Container` |
| FPS tanks with many sprites | Each sprite uses a different texture | Atlas into spritesheet |
| `Texture.from(url)` returns blank | URL not pre-loaded | `await Assets.load(url)` first |
| Filter looks broken | Old v7 filter constructor | Use `{ glProgram, resources }` object form |

---

## See Also

- [`../current-best-practices.md`](../current-best-practices.md) — Application bootstrap pattern
- [`../breaking-changes.md`](../breaking-changes.md) — v7→v8 rendering changes
- [`input.md`](input.md) — Federated event system
- [`animation.md`](animation.md) — Ticker integration
