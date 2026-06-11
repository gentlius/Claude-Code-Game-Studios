# HTML5 (PixiJS) — Version Reference

| Field | Value |
|-------|-------|
| **Engine Family** | HTML5 / Web (PixiJS-based) |
| **Renderer** | PixiJS 8.16.0 (Feb 2026 latest) |
| **Build Tool** | Vite 8.0.0 (Mar 2026) — or 7.3 LTS / 6.4 (security patches only) |
| **Language** | TypeScript 5.x |
| **Test Frameworks** | Vitest (unit) + Playwright 1.49+ (e2e/browser) |
| **Target Runtime** | Modern evergreen browsers (Chrome/Firefox/Safari/Edge), iOS Safari 16+, Android Chrome 110+ |
| **Project Pinned** | 2026-06-11 |
| **Last Docs Verified** | 2026-06-11 |
| **LLM Knowledge Cutoff** | May 2025 |
| **Risk Level** | **HIGH** — PixiJS v8 introduced near-complete API redesign post-cutoff |

## Knowledge Gap Warning

The LLM training data likely covers **PixiJS up to ~v7.x**. PixiJS v8 (released
Feb 2024) was a near-complete API redesign — most v7 code patterns are now
incorrect. Always cross-reference [`breaking-changes.md`](breaking-changes.md)
and [`deprecated-apis.md`](deprecated-apis.md) before writing or reviewing
PixiJS code.

Vite also moved from v5 (training-data-era) → v6 → v7 → **v8 (Rolldown-based,
Mar 2026)**. Vite 8 swaps esbuild + Rollup for Rolldown + Oxc — performance
profile and some configuration semantics differ. If a project is still on Vite 5
or 6, treat it as **legacy** for tooling purposes (PixiJS 8 code itself is
agnostic to the bundler version).

## Post-Cutoff Version Timeline

### PixiJS

| Version | Release | Risk | Key Theme |
|---------|---------|------|-----------|
| 8.0 | Feb 2024 | **HIGH** | Single package, async `Application.init()`, Graphics API redesign, ParticleContainer rework, TextureSource separation |
| 8.6 | Oct 2025 | MEDIUM | Documentation overhaul, WebGPU stability improvements |
| 8.12 | Dec 2025 | LOW | Performance and bugfixes |
| 8.13 | Jan 2026 | LOW | Bugfixes |
| 8.16 | Feb 2026 | LOW | HTMLText word wrapping fix, CubeTexture environment maps, external texture support |

### Vite

| Version | Release | Risk | Key Theme |
|---------|---------|------|-----------|
| 6.0 | Late 2024 | MEDIUM | Environment API, runtime API changes |
| 7.0 | Mid 2025 | MEDIUM | Default targets, Node.js requirement bump |
| 8.0 | Mar 2026 | **HIGH** | **Rolldown** replaces esbuild + Rollup, Oxc-based tooling, ~15 MB larger install size, lightningcss as normal dep |

### Playwright

| Version | Release | Risk | Key Theme |
|---------|---------|------|-----------|
| 1.45+ | 2024+ | LOW | Mobile device descriptor expansion (100+ devices) |
| 1.49+ | 2026 | LOW | Improved touch event handling, better WebKit parity, network condition control |

## BagelMVP Specific Note

The reference project `BagelMVP` (`pop-prototype`) currently pins:
- `pixi.js ^8.0.0` — covered by this reference (use v8.16.0 patterns)
- `vite ^5.0.0` — **legacy**, predates the docs above (`/setup-engine upgrade vite 5 8` to migrate)
- `vitest ^1.0.0` — paired with Vite 5; Vitest 3.x pairs with Vite 8
- `@playwright/test ^1.40.0` — predates 1.49 mobile improvements; upgrade recommended
- `typescript ^5.0.0` — within range

Project may stay on Vite 5 for stability; the PixiJS code itself is bundler-agnostic.

## Verified Sources

- PixiJS v8 migration guide: https://pixijs.com/8.x/guides/migrations/v8
- PixiJS versions index: https://pixijs.com/versions
- PixiJS 8.16 release notes: https://pixijs.com/blog/8.16.0
- Vite 8 release: https://vite.dev/releases
- Vite 8 vs 7 changelog: https://github.com/vitejs/vite/blob/main/packages/vite/CHANGELOG.md
- Playwright emulation: https://playwright.dev/docs/emulation
- Playwright mobile devices: https://playwright.dev/docs/api/class-devices
