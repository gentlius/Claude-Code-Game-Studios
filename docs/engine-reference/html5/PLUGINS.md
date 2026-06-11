# HTML5 / PixiJS — Optional Packages & Libraries

**Last verified:** 2026-06-11

This document indexes **optional libraries** commonly paired with PixiJS 8 for
specific game genres. These are NOT part of PixiJS core but solve recurring
problems (audio, physics, animation, mobile UX) where the browser's native
APIs are too low-level.

---

## How to Use This Guide

- **✅ Production-Ready** — Widely used, maintained, recommended
- **🟡 Brief Overview Only** — Use WebSearch for current state
- **⚠️ Caveat** — Specific concern noted
- **📦 Package Required** — Install via npm

---

## Production-Ready Libraries

### ✅ pixi-filters
- **Purpose**: Extra filters not in core PixiJS (Bloom, Glitch, Outline, CRT, Godray, etc.)
- **When to use**: Visual polish — stylization, post-FX, retro effects
- **Knowledge Gap**: Some filters rewritten for v8 — verify each filter against the v8 package version
- **Status**: Production-Ready
- **Package**: `pixi-filters` (peer dep on `pixi.js@^8`)
- **Official**: https://github.com/pixijs/filters

---

### ✅ Howler.js
- **Purpose**: WebAudio wrapper — sprites, fade, spatial, mobile audio unlock
- **When to use**: Any game needing >2-3 sounds. WebAudio raw is painful for sprite-based sound (cutting one sample out of a loop).
- **Why over native WebAudio**: Automatic mobile audio context unlock on first touch (the iOS/Android requirement that crashes naive `new Audio()` code), built-in audio sprites (sub-clips of a long file), cross-format fallback
- **Status**: Production-Ready (stable, low-churn)
- **Package**: `howler` + `@types/howler`
- **Official**: https://howlerjs.com/

---

### ✅ GSAP (GreenSock)
- **Purpose**: Tweening engine — smooth UI animations, eased motion, sequence chains
- **When to use**: Anywhere PixiJS's built-in linear interpolation isn't enough — menu transitions, card flips, juice/feedback animations
- **PixiJS-specific tip**: GSAP doesn't need a Pixi plugin — just tween `sprite.x`, `sprite.scale.x`, `sprite.alpha` directly. GSAP picks them up via property access.
- **Licensing**: Standard license is free for most use; commercial features (SplitText, MotionPath full) require Club GreenSock membership
- **Status**: Production-Ready
- **Package**: `gsap`
- **Official**: https://gsap.com/

---

### ✅ Matter.js
- **Purpose**: 2D rigid-body physics (gravity, collision, constraints)
- **When to use**: Physics-driven gameplay — Angry Birds style, ragdoll, sandbox. NOT needed for simple AABB collision (write your own).
- **Pairing with PixiJS**: Run Matter as a separate world; in each Ticker tick, copy `body.position` → `sprite.position` and `body.angle` → `sprite.rotation`
- **Status**: Production-Ready
- **Package**: `matter-js` + `@types/matter-js`
- **Official**: https://brm.io/matter-js/

---

### ✅ Box2D (via wasm)
- **Purpose**: Industry-standard 2D physics (more accurate than Matter, used by Angry Birds, Limbo)
- **When to use**: When physics quality is core to the game feel and Matter's solver isn't tight enough
- **Caveat**: ⚠️ WASM build adds ~500KB to bundle. Don't reach for this unless physics is the game.
- **Status**: Production-Ready (multiple WASM ports — `box2d-wasm` is current)
- **Package**: `box2d-wasm`

---

### ✅ Spine / DragonBones (Skeletal Animation)
- **Purpose**: 2D skeletal animation runtimes
- **When to use**: Character animation more complex than sprite sheets (smooth IK, weighted meshes, deformation)
- **PixiJS integration**: `@esotericsoftware/spine-pixi-v8` (official Spine runtime for PixiJS 8)
- **Caveat**: ⚠️ Spine requires a paid editor license for commercial use ($69 Essential / $399 Professional). DragonBones is free but less actively maintained.
- **Status**: Production-Ready
- **Package**: `@esotericsoftware/spine-pixi-v8`

---

### ✅ nipplejs
- **Purpose**: Virtual joystick / d-pad overlay for mobile web
- **When to use**: Any action game targeting mobile web that can't rely on tap-only input
- **Caveat**: ⚠️ The library is DOM-based (renders separately from Pixi canvas) — be careful with z-index and pointer-events: none on the right children
- **Status**: Production-Ready (low churn)
- **Package**: `nipplejs`
- **Official**: https://yoannmoi.net/nipplejs/

---

## Brief Overview Only

### 🟡 PixiJS Sound (`@pixi/sound`)
- **Purpose**: PixiJS's own audio package
- **When to use**: If you want audio integrated with Pixi's Assets system
- **Tradeoff vs Howler**: Tighter Pixi integration, but Howler has more mature mobile-quirk handling. For complex games → Howler. For simple ambient audio integrated with asset bundles → @pixi/sound is fine.
- **Package**: `@pixi/sound`

### 🟡 Tone.js
- **Purpose**: Music synthesis / interactive music
- **When to use**: Games with adaptive music, procedural sound, music-as-mechanic (rhythm games)
- **Caveat**: ⚠️ Heavy (~150KB). Overkill for static music playback — use Howler.

### 🟡 Hammer.js
- **Purpose**: Touch gesture library (pinch, rotate, swipe, multi-touch)
- **When to use**: When Pixi's `FederatedPointerEvent` doesn't cover gesture detection you need
- **Caveat**: ⚠️ Last release was years ago. Consider native Pointer Events with manual gesture detection unless you need Hammer's specific event abstractions.

### 🟡 p2.js
- **Purpose**: Alternative 2D physics engine
- **When to use**: Rarely chosen now over Matter or Box2D. Listed for completeness.

### 🟡 Stats.js / Pixi DevTools
- **Purpose**: FPS counter, draw call inspector
- **When to use**: Development only — strip from production builds
- **Pixi DevTools**: Chrome extension for inspecting the Pixi scene graph at runtime — install during development

### 🟡 i18next
- **Purpose**: i18n for game UI text
- **When to use**: Localized games. Pairs with `react-i18next` if you have React UI overlay, or use core library directly with Pixi `Text` elements.

---

## Networking (for Multiplayer)

### 🟡 Colyseus
- **Purpose**: Authoritative game server with state sync
- **When to use**: Realtime multiplayer (lobby + room-based games)
- **Caveat**: ⚠️ Server-side Node.js component required

### 🟡 PartyKit / Socket.IO
- **Purpose**: Lower-level realtime messaging
- **When to use**: Custom netcode, or hosting on edge (PartyKit on Cloudflare)

### 🟡 WebRTC (native)
- **Purpose**: Peer-to-peer (no server)
- **When to use**: 2-player games where matchmaking can be solved externally (URL share). Avoid for >4 players (mesh complexity).

---

## NOT Recommended

### ❌ Pixi v7 plugins on v8 projects
Many community plugins haven't migrated. Always check the package's
`peerDependencies` for `"pixi.js": "^8"` before installing.

### ❌ `pixi-spine` (old)
Use `@esotericsoftware/spine-pixi-v8` — official runtime, maintained.

### ❌ jQuery / lodash for game code
ESM imports + modern JS (`Object.entries`, `Array.flat`, etc.) cover almost
all utility needs. lodash for one helper = 100KB you didn't need.

### ❌ Web Components / Lit for in-canvas UI
The DOM overlay above the canvas is a valid pattern, but mixing component
frameworks with the WebGL canvas adds layout cost. Use Pixi-native `Container`
hierarchies for in-game UI.

---

## Installation Cheat Sheet

```bash
# Core (most common combo)
npm i pixi.js pixi-filters howler gsap

# Mobile-first action game
npm i pixi.js pixi-filters howler gsap nipplejs

# Physics-driven game
npm i pixi.js pixi-filters howler matter-js

# Animation-heavy character game
npm i pixi.js pixi-filters howler @esotericsoftware/spine-pixi-v8

# Dev / testing
npm i -D vite vitest @playwright/test typescript @types/node @types/howler @types/matter-js
```

---

## See Also

- [`current-best-practices.md`](current-best-practices.md) — How these libraries fit into project structure
- [`modules/audio.md`](modules/audio.md) — Howler patterns in depth
- [`modules/physics.md`](modules/physics.md) — Matter / Box2D patterns
- [`modules/networking.md`](modules/networking.md) — Multiplayer architectures
