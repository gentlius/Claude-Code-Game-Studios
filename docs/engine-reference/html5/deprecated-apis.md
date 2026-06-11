# HTML5 / PixiJS — Deprecated API Quick Reference

**Last verified:** 2026-06-11

**Purpose**: Fast "don't use X → use Y" lookup. When in doubt about a PixiJS
API, search this file first. For full context on why each change happened,
see [`breaking-changes.md`](breaking-changes.md).

---

## PixiJS v7 (or earlier) → v8

### Imports

| ❌ Deprecated | ✅ Use Instead |
|--------------|---------------|
| `import { X } from '@pixi/app'` | `import { X } from 'pixi.js'` |
| `import { X } from '@pixi/sprite'` | `import { X } from 'pixi.js'` |
| `import { X } from '@pixi/graphics'` | `import { X } from 'pixi.js'` |
| `import { utils } from 'pixi.js'` | `import { hex2rgb, ... } from 'pixi.js'` (direct) |

### Application Lifecycle

| ❌ Deprecated | ✅ Use Instead |
|--------------|---------------|
| `new Application({ ... })` (with options) | `new Application(); await app.init({ ... });` |
| `app.view` | `app.canvas` |
| `app.renderer.view` | `app.renderer.canvas` |

### Graphics

| ❌ Deprecated | ✅ Use Instead |
|--------------|---------------|
| `.beginFill(c)` | (delete — use `.fill(c)` after shape) |
| `.endFill()` | (delete — `.fill(c)` is terminal) |
| `.drawRect(x,y,w,h)` | `.rect(x,y,w,h)` |
| `.drawCircle(x,y,r)` | `.circle(x,y,r)` |
| `.drawEllipse(x,y,w,h)` | `.ellipse(x,y,w,h)` |
| `.drawPolygon([...])` | `.poly([...])` |
| `.drawRoundedRect(x,y,w,h,r)` | `.roundRect(x,y,w,h,r)` |
| `.drawStar(x,y,points,r)` | `.star(x,y,points,r)` |
| `.lineStyle(w, color)` | `.stroke({ width: w, color })` (after shape) |
| `.lineTo(x,y)` | `.lineTo(x,y)` (unchanged but pair with `.stroke()`) |

### Container & DisplayObject

| ❌ Deprecated | ✅ Use Instead |
|--------------|---------------|
| `extends DisplayObject` | `extends Container` |
| `sprite.addChild(other)` | (removed for `Sprite`/`Mesh`/`Graphics` — wrap in `Container`) |
| `obj.name` | `obj.label` |
| `obj.updateTransform()` override | `obj.onRender = (renderer) => { ... }` |
| `cacheAsBitmap = true` | `cacheAsTexture()` (method call) |
| `getBounds()` (returns Rectangle) | `getBounds().rectangle` (Bounds object → .rectangle) |

### Textures

| ❌ Deprecated | ✅ Use Instead |
|--------------|---------------|
| `Texture.from('url')` (auto-loads) | `await Assets.load('url'); Texture.from('url')` |
| `BaseTexture` | `TextureSource` subclasses: `ImageSource`, `VideoSource`, `CanvasSource` |
| `new BaseTexture(resource)` | `new ImageSource({ resource })` (or matching subclass) |

### Assets

| ❌ Deprecated | ✅ Use Instead |
|--------------|---------------|
| `Loader` (entire class) | `Assets` (already in v7, but now mandatory in v8) |
| `Assets.add('alias', 'url')` | `Assets.add({ alias: 'alias', src: 'url' })` |

### ParticleContainer

| ❌ Deprecated | ✅ Use Instead |
|--------------|---------------|
| `pc.addChild(sprite)` | `pc.addParticle(new Particle({ texture, x, y }))` |
| `pc.children` | `pc.particleChildren` |
| Automatic bounds | `pc.boundsArea = new Rectangle(...)` (required) |
| Sprite-based properties | `Particle` with `dynamicProperties` config |

### Filters

| ❌ Deprecated | ✅ Use Instead |
|--------------|---------------|
| `new Filter(vert, frag, uniforms)` | `new Filter({ glProgram: GlProgram.from({vert, frag}), resources: {...} })` |
| Untyped uniforms `{ uTime: 0 }` | Typed: `{ uTime: { value: 0, type: 'f32' } }` |
| `new BlurFilter(8, 4, 1, 5)` | `new BlurFilter({ strength: 8, quality: 4, resolution: 1, kernelSize: 5 })` |

### Mesh

| ❌ Deprecated | ✅ Use Instead |
|--------------|---------------|
| `SimpleMesh` | `MeshSimple` |
| `SimplePlane` | `MeshPlane` |
| `SimpleRope` | `MeshRope` |
| `NineSlicePlane` | `NineSliceSprite` |

### Ticker

| ❌ Deprecated | ✅ Use Instead |
|--------------|---------------|
| `Ticker.shared.add((delta: number) => ...)` | `Ticker.shared.add((ticker: Ticker) => { ticker.deltaTime })` |

### Constants & Settings

| ❌ Deprecated | ✅ Use Instead |
|--------------|---------------|
| `SCALE_MODES.LINEAR` | `'linear'` (string) |
| `SCALE_MODES.NEAREST` | `'nearest'` |
| `WRAP_MODES.CLAMP` | `'clamp-to-edge'` |
| `WRAP_MODES.REPEAT` | `'repeat'` |
| `BLEND_MODES.NORMAL` | `'normal'` |
| `BLEND_MODES.ADD` | `'add'` |
| `settings.RESOLUTION = N` | `AbstractRenderer.defaultOptions.resolution = N` |
| `settings.ADAPTER = X` | `DOMAdapter.set(X)` |

### Renderer Detection

| ❌ Deprecated | ✅ Use Instead |
|--------------|---------------|
| `autoDetectRenderer({...})` | `await autoDetectRenderer({...})` (now async) |
| Pin to `WebGLRenderer` only | `preference: 'webgl'` in init options |
| Pin to `WebGPURenderer` only | `preference: 'webgpu'` in init options |

---

## Vite 5/6 → 7/8

| ❌ Older Pattern | ✅ Use Instead |
|--------------|---------------|
| `build.target: 'modules'` (Vite 6 default) | `'baseline-widely-available'` (Vite 7+ default) |
| `define: { 'process.env': ... }` | Prefer `import.meta.env.*` directly |
| `optimizeDeps.entries: 'src/**/*.ts'` (glob string) | Use array of explicit paths |
| Single `server` config | `server.environments` (Vite 6+ multi-env) |

For Rolldown-specific (Vite 8) notes, see [`current-best-practices.md`](current-best-practices.md).

---

## Playwright

No major deprecations between 1.40 and 1.49 — mostly additive. Older Playwright
code keeps working; just lacks newer device descriptors and improved touch sim.

---

## TypeScript Patterns to Avoid in PixiJS Code

| ❌ Anti-Pattern | ✅ Use Instead |
|---------------|---------------|
| `(sprite as any).foo` | Cast through proper type guard or extend `Container` properly |
| `any` for Asset return | `Assets.load<Texture>(url)` (typed return) |
| Loose `Container.children` access | Type-narrow with `Container<SpecificChild>` |
| Untyped event handlers | Use `FederatedPointerEvent`, `FederatedWheelEvent`, etc. |

---

## When in Doubt

1. Check this file first
2. If not found, check [`breaking-changes.md`](breaking-changes.md)
3. WebSearch `"pixijs v8 [API name]"` for confirmation
4. Verify against https://pixijs.com/8.x/guides
