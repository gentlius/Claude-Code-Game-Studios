# HTML5 / PixiJS — UI Module

**Last verified:** 2026-06-11

PixiJS-native UI vs DOM overlay, when to use which, text rendering, and
responsive layout for mobile web.

---

## DOM vs Pixi UI — When to Use Which

| Use DOM (HTML overlay) | Use Pixi (canvas) |
|------------------------|-------------------|
| Settings menu, pause menu | HUD (score, health) |
| Long text (story, credits) | Floating combat text |
| Email/text input | Buttons inside game world |
| Tab-able links, anchors | Anything that needs to align with world coords |
| Accessibility-critical (screen reader) | Visual-only ornaments |
| Forms / IAP receipts | Anything animated by Ticker |

**General rule**: DOM for typography-heavy / accessibility-needed UI, Pixi for
game-feel UI integrated with the rendered world.

---

## DOM Overlay Pattern

Place a single transparent DOM container above the canvas:

```html
<div id="app">
  <canvas id="pixi"></canvas>
  <div id="dom-ui"></div>
</div>
```

```css
#app {
  position: fixed;
  inset: 0;
}

#pixi, #dom-ui {
  position: absolute;
  inset: 0;
}

#dom-ui {
  pointer-events: none;     /* canvas catches input by default */
}

#dom-ui > * {
  pointer-events: auto;     /* opt back in for actual UI widgets */
}
```

This keeps DOM elements out of canvas hit-testing unless they explicitly want input.

---

## Pixi Text

```ts
import { Text, TextStyle } from 'pixi.js';

const style = new TextStyle({
  fontFamily: 'Arial',
  fontSize: 24,
  fill: 0xffffff,
  stroke: { width: 2, color: 0x000000 },
  dropShadow: { color: 0x000000, blur: 4, distance: 2 },
});

const label = new Text({ text: 'Score: 0', style });
```

### Performance: Static vs Updating

- **Static text** (title, copyright): use `Text`. Internally rasterizes once.
- **Updating text** (score that changes every frame): use `BitmapText` for performance.

### BitmapText

Pre-rendered bitmap font, much faster than re-rasterizing `Text`:

```ts
import { Assets, BitmapText } from 'pixi.js';

await Assets.load('assets/font.fnt');   // BMFont format

const score = new BitmapText({
  text: '0',
  style: { fontFamily: 'PressStart2P', fontSize: 32, fill: 0xffff00 },
});

// Updating each frame is cheap
Ticker.shared.add(() => { score.text = String(currentScore); });
```

Tools: [SnowB BMFont](http://www.angelcode.com/products/bmfont/) or
[bmfont-online](https://snowb.org/) to generate `.fnt` + atlas PNG.

### Sources of Text Performance Bugs

| Bug | Cause |
|-----|-------|
| Score text drops FPS | Using `Text` instead of `BitmapText` for per-frame updates |
| Text blurry on retina | Resolution mismatch — set `style.resolution = window.devicePixelRatio` or use `BitmapText` |
| Korean / Chinese text broken | Font not loaded yet — `await document.fonts.ready` before creating `Text` |
| Text jitters during animation | Sub-pixel position — round to integer or use `Math.round(x)` for text positions |

---

## HTMLText (v8 New)

Renders HTML via SVG foreignObject. Use when you need rich text (bold, italic,
mixed colors inline):

```ts
import { HTMLText } from 'pixi.js';

const rich = new HTMLText({
  text: '<b>Score:</b> <span style="color:red">100</span>',
  style: { fontSize: 24, fill: 0xffffff },
});
```

**Caveat**: HTMLText has higher cost than regular Text. Use for static or
infrequently-updated rich text only.

---

## Buttons in Pixi

Pixi has no `Button` class. Roll your own:

```ts
import { Container, Sprite, Text } from 'pixi.js';

class Button extends Container {
  constructor(label: string, bgTexture: Texture, onTap: () => void) {
    super();
    const bg = new Sprite(bgTexture);
    bg.anchor.set(0.5);
    const text = new Text({ text: label, style: { fontSize: 20, fill: 0xffffff } });
    text.anchor.set(0.5);
    this.addChild(bg, text);

    this.eventMode = 'static';
    this.cursor = 'pointer';

    this.on('pointerdown', () => { bg.tint = 0xcccccc; });
    this.on('pointerup',   () => { bg.tint = 0xffffff; onTap(); });
    this.on('pointerupoutside', () => { bg.tint = 0xffffff; });
  }
}
```

### Tap Target Padding

WCAG ≥48×48 px:

```ts
button.hitArea = new Rectangle(-24, -24, button.width + 48, button.height + 48);
```

---

## Layout — Constraint-Based (Anchors)

Pixi has no layout engine — you compute positions manually on resize:

```ts
function layout() {
  const { width: W, height: H } = app.renderer;

  scoreLabel.x = 20;
  scoreLabel.y = 20;

  pauseButton.x = W - 60;
  pauseButton.y = 20;

  joystick.x = 100;
  joystick.y = H - 100;
}

window.addEventListener('resize', layout);
layout();
```

For complex UI, consider [@pixi/layout](https://github.com/pixijs/layout)
(flex-style layout for Pixi containers — production-ready in 2026).

---

## Safe Area (iOS Notch)

iOS notch / Dynamic Island intrudes on the top of the canvas. Use CSS env
variables in the DOM:

```css
#app {
  padding-top: env(safe-area-inset-top);
  padding-bottom: env(safe-area-inset-bottom);
}
```

For canvas-based UI, read the safe area via JS:

```ts
function getSafeArea() {
  const s = getComputedStyle(document.documentElement);
  return {
    top:    parseInt(s.getPropertyValue('--sat') ?? '0', 10),
    bottom: parseInt(s.getPropertyValue('--sab') ?? '0', 10),
  };
}
```

After setting CSS custom props:

```css
:root {
  --sat: env(safe-area-inset-top);
  --sab: env(safe-area-inset-bottom);
}
```

---

## Modals / Dialogs

Pattern: full-screen `Container` with semi-transparent background, eats input:

```ts
class Modal extends Container {
  constructor(content: Container) {
    super();
    const bg = new Graphics()
      .rect(0, 0, app.renderer.width, app.renderer.height)
      .fill({ color: 0x000000, alpha: 0.5 });
    bg.eventMode = 'static';   // eat clicks behind the modal
    this.addChild(bg, content);
  }
}
```

---

## Accessibility — Limits & Strategy

PixiJS canvas is opaque to screen readers. For accessible games:

1. **Mirror critical UI in DOM** — keep score, menu, settings in HTML overlays
2. **ARIA labels** on canvas itself: `<canvas aria-label="Game playfield">`
3. **Keyboard alternatives** for every touch/click action
4. **High-contrast mode**: detect via `prefers-contrast: more` media query

Pixi's `accessibility` plugin (legacy) attempts to inject DOM elements for
focusable canvas objects, but it's brittle. For real accessibility, mirror
the menu/HUD in DOM.

---

## Internationalization

For multi-language games:

1. Use a font that supports the target script (e.g., `Noto Sans` covers most scripts)
2. Or use `BitmapText` with the script-specific font generated upfront
3. Pre-load font via `document.fonts.add(new FontFace(...))` and `await document.fonts.ready` before showing text

```ts
const font = new FontFace('NotoSansKR', 'url(fonts/NotoSansKR.woff2)');
await font.load();
document.fonts.add(font);
await document.fonts.ready;
// now safe to create Text with fontFamily: 'NotoSansKR'
```

---

## See Also

- [`input.md`](input.md) — Button event handling
- [`rendering.md`](rendering.md) — Scene graph hierarchy
- [`../current-best-practices.md`](../current-best-practices.md) — Mobile CSS baseline
