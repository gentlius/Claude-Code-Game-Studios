# Engine Reference Documentation

This directory contains curated, version-pinned documentation snapshots for the
game engine(s) used in this project. These files exist because **LLM knowledge
has a cutoff date** and game engines update frequently.

## Why This Exists

Claude's training data has a knowledge cutoff (currently May 2025). Game engines
like Godot, Unity, Unreal, and the PixiJS / Vite / Playwright stack ship updates
that introduce breaking API changes, new features, and deprecated patterns.
Without these reference files, agents will suggest outdated code.

## Supported Engine Families

| Family | Directory | Specialist Agents |
|--------|-----------|-------------------|
| Godot 4 | `godot/` | `godot-specialist`, `godot-gdscript-specialist`, `godot-csharp-specialist`, `godot-shader-specialist`, `godot-gdextension-specialist` |
| Unity | `unity/` | `unity-specialist`, `unity-dots-specialist`, `unity-shader-specialist`, `unity-ui-specialist`, `unity-addressables-specialist` |
| Unreal Engine 5 | `unreal/` | `unreal-specialist`, `ue-blueprint-specialist`, `ue-gas-specialist`, `ue-replication-specialist`, `ue-umg-specialist` |
| HTML5 / PixiJS | `html5/` | `html5-specialist`, `pixijs-specialist`, `webgl-shader-specialist`, `web-build-specialist`, `playwright-e2e-specialist` |

## Structure

Each engine gets its own directory:

```
<engine>/
├── VERSION.md              # Pinned version, verification date, knowledge gap window
├── breaking-changes.md     # API changes between versions, organized by risk level
├── deprecated-apis.md      # "Don't use X → Use Y" lookup tables
├── current-best-practices.md  # New practices not in model training data
├── PLUGINS.md              # Optional packages / libraries (unity, unreal, html5)
└── modules/                # Per-subsystem quick references (~150 lines max each)
    ├── rendering.md
    ├── physics.md
    └── ...
```

The `html5/` family is unusual: the "engine" is actually a combined runtime
(browser + PixiJS framework + Vite build tooling + Playwright tests), so its
VERSION.md tracks multiple version pins rather than one product.

## How Agents Use These Files

Engine-specialist agents are instructed to:

1. Read `VERSION.md` to confirm the current engine version
2. Check `deprecated-apis.md` before suggesting any engine API
3. Consult `breaking-changes.md` for version-specific concerns
4. Read relevant `modules/*.md` for subsystem-specific work

## Maintenance

### When to Update

- After upgrading the engine version
- When the LLM model is updated (new knowledge cutoff)
- After running `/refresh-docs` (if available)
- When you discover an API the model gets wrong

### How to Update

1. Update `VERSION.md` with the new engine version and date
2. Add new entries to `breaking-changes.md` for the version transition
3. Move newly deprecated APIs into `deprecated-apis.md`
4. Update `current-best-practices.md` with new patterns
5. Update relevant `modules/*.md` with API changes
6. Set "Last verified" dates on all modified files

### Quality Rules

- Every file must have a "Last verified: YYYY-MM-DD" date
- Keep module files under 150 lines (context budget)
- Include code examples showing correct/incorrect patterns
- Link to official documentation URLs for verification
- Only document things that differ from the model's training data
