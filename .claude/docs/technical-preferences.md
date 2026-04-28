# Technical Preferences

<!-- Populated by /setup-engine. Updated as the user makes decisions throughout development. -->
<!-- All agents reference this file for project-specific standards and conventions. -->

## Engine & Language

- **Engine**: Godot 4.6
- **Language**: GDScript (primary), C++ via GDExtension (performance-critical)
- **Rendering**: Vulkan (Forward+) — 웹 export 시 Compatibility (OpenGL 3)
- **Physics**: Jolt (4.6 기본)

## Input & Platform

<!-- Written by /setup-engine. Read by /ux-design, /ux-review, /test-setup, /team-ui, and /dev-story -->
<!-- to scope interaction specs, test helpers, and implementation to the correct input methods. -->

- **Target Platforms**: [TO BE CONFIGURED — e.g., PC, Console, Mobile, Web]
- **Input Methods**: [TO BE CONFIGURED — e.g., Keyboard/Mouse, Gamepad, Touch, Mixed]
- **Primary Input**: [TO BE CONFIGURED — the dominant input for this game]
- **Gamepad Support**: [TO BE CONFIGURED — Full / Partial / None]
- **Touch Support**: [TO BE CONFIGURED — Full / Partial / None]
- **Platform Notes**: [TO BE CONFIGURED — any platform-specific UX constraints]

## Naming Conventions

- **Classes**: PascalCase (e.g., `GameClock`, `PriceEngine`)
- **Variables/Functions**: snake_case (e.g., `move_speed`, `get_current_price()`)
- **Signals**: snake_case past tense (e.g., `tick_processed`, `market_state_changed`)
- **Files**: snake_case matching class (e.g., `game_clock.gd`)
- **Scenes/Prefabs**: PascalCase matching root node (e.g., `GameClock.tscn`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_HOLDINGS`, `TICKS_PER_DAY`)

## Performance Budgets

- **Target Framerate**: 60fps
- **Frame Budget**: 16.6ms
- **Draw Calls**: [TO BE CONFIGURED] (UI 중심이므로 상대적 여유)
- **Memory Ceiling**: 512MB (웹 빌드 고려)

## Testing

- **Framework**: GUT (Godot Unit Test)
- **Minimum Coverage**: Balance formulas 100%, gameplay systems 80%
- **Required Tests**: Balance formulas, gameplay systems

## Forbidden Patterns

<!-- Add patterns that should never appear in this project's codebase -->
- [None configured yet — add as architectural decisions are made]

## Allowed Libraries / Addons

<!-- Add approved third-party dependencies here -->
- [None configured yet — add as dependencies are approved]

## Architecture Decisions Log

<!-- Quick reference linking to full ADRs in docs/architecture/ -->
<!-- Add entries here as architectural decisions are made in this project. -->
<!-- Format: - [ADR-NNN](../../docs/architecture/NNN-slug.md) — 한 줄 설명 -->
- [None yet — add as decisions are made]

## Engine Specialists

<!-- Written by /setup-engine when engine is configured. -->
<!-- Read by /code-review, /architecture-decision, /architecture-review, and team skills -->
<!-- to know which specialist to spawn for engine-specific validation. -->

- **Primary**: godot-specialist
- **Language/Code Specialist**: godot-gdscript-specialist
- **Shader Specialist**: godot-shader-specialist
- **UI Specialist**: godot-specialist (UI/Control nodes)
- **Additional Specialists**: godot-gdextension-specialist (C++/GDExtension)
- **Routing Notes**: GDScript files → gdscript-specialist; .cpp/.h in gdextension/ → gdextension-specialist; .gdshader → shader-specialist; all others → godot-specialist

### File Extension Routing

<!-- Skills use this table to select the right specialist per file type. -->
<!-- If a row says [TO BE CONFIGURED], fall back to Primary for that file type. -->

| File Extension / Type | Specialist to Spawn |
|-----------------------|---------------------|
| Game code (`.gd`) | godot-gdscript-specialist |
| Shader / material files (`.gdshader`) | godot-shader-specialist |
| UI / screen files (`.tscn` with Control root) | godot-specialist |
| Scene / prefab / level files (`.tscn`, `.tres`) | godot-specialist |
| Native extension / plugin files (`.cpp`, `.h`, `SConstruct`) | godot-gdextension-specialist |
| General architecture review | godot-specialist |
