# HTML5 / PixiJS — Build Module

**Last verified:** 2026-06-11

Vite configuration, bundle optimization, asset pipeline, PWA setup, and
deployment patterns for HTML5 games. This module exists because mobile web
games are uniquely bandwidth-sensitive — every kilobyte costs first-load time.

---

## Vite Setup Baseline

```ts
// vite.config.ts
import { defineConfig } from 'vite';

export default defineConfig({
  base: './',                              // relative paths — works on itch.io, GitHub Pages, etc.
  build: {
    target: 'es2022',
    minify: 'esbuild',                     // Vite 7 default; Vite 8 uses Oxc
    sourcemap: true,                        // turn OFF for prod if size critical
    cssCodeSplit: false,                    // games typically have one CSS file
    rollupOptions: {
      output: {
        manualChunks: {
          pixi: ['pixi.js'],
          gsap: ['gsap'],
          howler: ['howler'],
        },
      },
    },
    assetsInlineLimit: 0,                   // never inline binary assets
    chunkSizeWarningLimit: 1500,            // games hit this; raise the threshold
  },
  server: {
    host: '0.0.0.0',                        // mobile device LAN testing
    port: 5173,
  },
  preview: {
    port: 5174,                             // separate from dev to avoid cache confusion
  },
});
```

### Why these settings

| Setting | Reason |
|---------|--------|
| `base: './'` | Relative paths so the build works on any subpath without rebuild |
| `manualChunks` | Pixi (~250KB), GSAP (~70KB), Howler (~30KB) each cache independently from your code |
| `assetsInlineLimit: 0` | Inlined assets break browser HTTP caching for shared atlases |
| `host: '0.0.0.0'` | Critical for testing on real phones over WiFi |
| `cssCodeSplit: false` | Games have minimal CSS — splitting adds requests without benefit |

---

## Bundle Size Targets

| Layer | Target gzipped | Why |
|-------|---------------|-----|
| First HTML | <5 KB | Single round-trip parse |
| First JS (your code + entry) | <50 KB | Show loading screen ASAP |
| Pixi chunk | ~150 KB | Cached separately |
| All vendor chunks combined | <300 KB | Lazy-loaded after init |
| Initial assets (atlas + 1 font) | <500 KB | First playable scene |

**Total time-to-playable target on 4G**: <3 seconds.

To audit: `vite build` produces `dist/`; inspect `dist/assets/*` sizes.
For interactive breakdown: `rollup-plugin-visualizer`:

```bash
npm i -D rollup-plugin-visualizer
```

```ts
import { visualizer } from 'rollup-plugin-visualizer';
export default defineConfig({
  plugins: [visualizer({ open: true, gzipSize: true })],
});
```

---

## Asset Pipeline

### Sprite Atlases

Use TexturePacker or `free-tex-packer` to combine images into atlases:

- One atlas per logical group (UI, characters, environment)
- Power-of-two dimensions (1024×1024, 2048×2048) — best GPU compatibility
- Trim whitespace, rotate where helpful
- Generate PixiJS JSON Hash format (Pixi parses it natively)

### Texture Compression (KTX2)

For projects > 5 MB of art:

1. Use `toktx` or `basisu` to convert PNGs → KTX2 Basis Universal
2. PixiJS 8 supports KTX2 via Assets system
3. 50-75% GPU memory reduction; smaller download too

```bash
# Convert single atlas
basisu -ktx2 -uastc atlas.png -output_path atlas.ktx2
```

### Audio Compression

- BGM: Opus at 64-96kbps → ~1 MB / minute
- SFX: Opus at 48-64kbps via audio sprites → one 200-500 KB file holds all SFX
- See [`audio.md`](audio.md) for full format strategy

### Image Optimization

For non-atlas images (loading screen, splash):

- PNG: use `oxipng` or `pngquant` (lossy palette quantization)
- JPEG: `mozjpeg`
- WebP: 25-35% smaller than equivalent JPEG; universal browser support by 2026
- AVIF: 50% smaller than JPEG; supported but encode is slow — use for static images only

```bash
# Bulk WebP convert
for f in *.png; do cwebp -q 85 "$f" -o "${f%.png}.webp"; done
```

---

## Code Splitting

Lazy-load gameplay code after the menu loads:

```ts
// main.ts — entry, ~10 KB
import { showMenu } from './menu';

showMenu({
  onStart: async () => {
    const { startGame } = await import('./game');  // separate chunk
    startGame();
  },
});
```

Vite automatically code-splits on dynamic `import()`. Your menu loads instantly;
the gameplay code (and its assets) load when the player presses Start.

---

## Pre-compression

Configure your host or build to serve pre-compressed assets:

```ts
import { compression } from 'vite-plugin-compression2';

export default defineConfig({
  plugins: [
    compression({ algorithm: 'gzip' }),
    compression({ algorithm: 'brotliCompress', ext: '.br' }),
  ],
});
```

Produces `.gz` and `.br` alongside originals. Configure your CDN / web server
to serve them when `Accept-Encoding` matches.

**Brotli is ~15% smaller than gzip** for text. For binary assets (PNG, MP3),
already-compressed formats won't gain — only enable for JS/CSS/HTML/JSON.

---

## PWA — Progressive Web App

For installable, offline-capable HTML5 games:

```bash
npm i -D vite-plugin-pwa
```

```ts
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  plugins: [
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.png', 'apple-touch-icon.png'],
      manifest: {
        name: 'Your Game',
        short_name: 'Game',
        theme_color: '#000000',
        background_color: '#000000',
        display: 'fullscreen',
        orientation: 'portrait',
        start_url: '/',
        icons: [
          { src: 'icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png' },
        ],
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,png,webp,mp3,webm,woff2,json}'],
        maximumFileSizeToCacheInBytes: 10 * 1024 * 1024,
      },
    }),
  ],
});
```

**Benefits**:
- Installable to homescreen (iOS, Android)
- Offline play after first load
- Push notifications (with consent)
- Full-screen presentation (no browser chrome)

**Caveat**: iOS PWA support has historically lagged. By 2026 the gap has
narrowed, but Web Push on iOS still requires the user to install the PWA
first (not just visit). Verify on actual devices.

---

## Service Worker Caching Strategy

For games, the default Workbox "precache everything" works well — it's exactly
what you want for offline-capable games. The downside: every code change
busts the entire cache on next visit. Mitigate by splitting:

- Vendor chunks (Pixi, GSAP) — long-cached, only invalidates on dep upgrade
- App chunks — hash-named, invalidate when your code changes
- Asset chunks — also hash-named

Vite handles content hashing automatically.

---

## Mobile Performance Headers

Configure your host to send:

```
Cache-Control: public, max-age=31536000, immutable  # for hashed assets
Cache-Control: no-cache                             # for index.html
Content-Encoding: br                                # if Brotli pre-compressed
```

`immutable` is critical — tells the browser to never revalidate hashed asset
URLs even on hard refresh.

---

## Deployment Targets

| Target | Strategy |
|--------|----------|
| Itch.io | `vite build`, zip `dist/`, upload — done |
| GitHub Pages | `vite build --base=/repo-name/`, push `dist/` to `gh-pages` branch |
| Netlify / Vercel | `vite build`, configure publish dir = `dist/` |
| Cloudflare Pages | Same as Netlify; better edge perf for global audiences |
| Custom CDN | Build, sync `dist/` to S3/R2, point CDN at bucket |
| Mobile app store (wrapped) | Capacitor (preferred 2026) or Cordova → builds native binary |

### itch.io Specific

- Game must be in a `.zip` with `index.html` at root
- Set viewport in itch.io project settings (matches your game canvas)
- "Frame your game" → choose Fullscreen for mobile
- Use `--base=./` (relative paths) so the zip works without absolute URLs

---

## CI Build

GitHub Actions example:

```yaml
name: Build
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm ci
      - run: npm run typecheck
      - run: npm test
      - run: npm run build
      - uses: actions/upload-artifact@v4
        with: { name: dist, path: dist/ }
```

For Playwright e2e (see [`../current-best-practices.md`](../current-best-practices.md)):

```yaml
      - run: npx playwright install --with-deps
      - run: npx playwright test
      - if: failure()
        uses: actions/upload-artifact@v4
        with: { name: playwright-report, path: playwright-report/ }
```

---

## Vite 7 → 8 Migration

Vite 8 (Mar 2026) swaps esbuild + Rollup for Rolldown + Oxc. For most game
projects, the migration is:

1. Bump `vite` to `^8`
2. Update plugin versions to ones declaring `vite: '^8'` peer dep
3. Test the build output — should be byte-similar but not identical
4. If you have custom Rollup plugins, check Rolldown compatibility

**Hold off** if you have ecosystem dependencies that haven't released v8-compatible
versions. Vite 7.3 will get security patches through 2026.

---

## See Also

- [`../PLUGINS.md`](../PLUGINS.md) — Optional libraries with bundle size notes
- [`../current-best-practices.md`](../current-best-practices.md) — Test patterns
- [`audio.md`](audio.md) — Audio format / size strategy
