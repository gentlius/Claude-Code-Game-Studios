# Technical Preferences

<!-- Populated by /setup-engine. Updated as the user makes decisions throughout development. -->
<!-- All agents reference this file for project-specific standards and conventions. -->

## Engine & Language

- **Engine**: Godot 4.6
- **Language**: GDScript (primary), C++ via GDExtension (performance-critical)
- **Rendering**: Vulkan (Forward+) — 웹 export 시 Compatibility (OpenGL 3)
- **Physics**: Jolt (4.6 기본)

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
- [ADR-001](../../docs/architecture/001-system-communication-pattern.md) — 시그널 + 직접 호출 하이브리드 통신 패턴
- [ADR-002](../../docs/architecture/002-tick-size-krx-table.md) — KRX 기반 호가 단위 테이블 (static 함수 단일 소스)
- [ADR-003](../../docs/architecture/003-energy-volume-correlation.md) — 에너지-거래량 상관관계 (tick energy 모델)
- [ADR-004](../../docs/architecture/004-ai-competitor-statistical-simulation.md) — AI 경쟁자 통계적 수익률 시뮬레이션 (실매매 없음)
- [ADR-005](../../docs/architecture/005-season-manager-xp-ownership.md) — SeasonManager가 시즌 XP 지급 전권 소유
- [ADR-006](../../docs/architecture/006-tab-scene-ownership.md) — MainScreen이 F1/F2/F3 탭 및 일시정지 단일 진입점
- [ADR-007](../../docs/architecture/007-global-rank-statistical-fairness.md) — 글로벌 순위 return_pct 단일 정렬 + AI 파라미터 단조성 보장
