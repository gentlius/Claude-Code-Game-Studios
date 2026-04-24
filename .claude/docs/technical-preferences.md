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
- [ADR-001](../../docs/architecture/001-system-communication-pattern.md) — 시그널 + 직접 호출 하이브리드 통신 패턴
- [ADR-002](../../docs/architecture/002-tick-size-krx-table.md) — KRX 기반 호가 단위 테이블 (static 함수 단일 소스)
- [ADR-003](../../docs/architecture/003-energy-volume-correlation.md) — 에너지-거래량 상관관계 (tick energy 모델)
- [ADR-004](../../docs/architecture/004-ai-competitor-statistical-simulation.md) — AI 경쟁자 통계적 수익률 시뮬레이션 (실매매 없음)
- [ADR-005](../../docs/architecture/005-season-manager-xp-ownership.md) — SeasonManager가 시즌 XP 지급 전권 소유
- [ADR-006](../../docs/architecture/006-tab-scene-ownership.md) — MainScreen이 F1/F2/F3 탭 및 일시정지 단일 진입점
- [ADR-007](../../docs/architecture/007-global-rank-statistical-fairness.md) — 글로벌 순위 return_pct 단일 정렬 + AI 파라미터 단조성 보장
- [ADR-008](../../docs/architecture/008-leaderboard-sort-cache.md) — 리더보드 정렬·캐시 전략
- [ADR-009](../../docs/architecture/009-multi-slot-save-architecture.md) — 인덱스+슬롯 분리 멀티슬롯 세이브 구조
- [ADR-010](../../docs/architecture/010-game-entry-flow-ownership.md) — GameMain이 모든 최상위 화면 전환 소유
- [ADR-011](../../docs/architecture/011-saving-overlay-canvas-layer.md) — SavingOverlay CanvasLayer(layer=10) 입력 차단 구현
- [ADR-012](../../docs/architecture/012-gameclock-pause-reference-counting.md) — GameClock pause_request/release() 참조 카운팅 일시정지
- [ADR-013](../../docs/architecture/013-trading-screen-component-split.md) — TradingScreen 5-컴포넌트 Facade 분리 (TD-04)
- [ADR-014](../../docs/architecture/014-mainscreen-tab-scene-lifecycle.md) — MainScreen 탭 씬 visibility 토글 상주 방식
- [ADR-015](../../docs/architecture/015-save-trigger-timing.md) — SaveSystem 저장 트리거 타이밍 (시즌/일별/초기 저장 순서)
- [ADR-016](../../docs/architecture/016-qa-10day-scenario-findings.md) — QA 자동화 10일 시나리오 버그 기록
- [ADR-017](../../docs/architecture/017-news-feed-cycling-state-machine.md) — 뉴스 카드 관련종목 순회 클로저 캡처 상태머신
- [ADR-018](../../docs/architecture/018-anti-price-scout-rng-entropy.md) — 가격 정찰 익스플로잇 차단: PriceEngine 세션 RNG 엔트로피 격리
- [ADR-019](../../docs/architecture/019-player-market-impact.md) — 플레이어 주문 시장 충격: 체결량 → tick_volumes 피드백 + 가격 압력 누적(_player_pressure)
- [ADR-020](../../docs/architecture/020-settings-persistence-split.md) — 설정 저장 분할: AudioManager cfg + SettingsScreen game_settings.cfg 각자 소유
- [ADR-021](../../docs/architecture/021-market-profile-data-driven.md) — MarketProfile JSON으로 시장별 규칙 전체 분리 (섹터/ETF/아키타입/로테이션/헤드라인 키/캘린더 포함, DLC 확장성)
- [ADR-022](../../docs/architecture/022-event-source-pipeline.md) — EventSource → NewsEventSystem → PriceEngine 단방향 파이프라인 (PriceEngine 직접 조작 금지)
- [ADR-023](../../docs/architecture/023-price-generation-single-ownership.md) — 가격 생성 규칙 단일 소유: PriceEngine.generate_synthetic_d1()로 프리히스토리 D1 통합, M1 캐시 슬롯별 분리
- [ADR-024](../../docs/architecture/024-price-engine-gdextension.md) — PriceEngine GDExtension 마이그레이션: M1-first 배치 생성(D1→M1 확장 폐기), 2-tier 캐시(M1 7800bars+D1 5200bars), C++ MarkovGenerator(Phase 3)
- [ADR-025](../../docs/architecture/025-stock-archetype-markov-matrices.md) — 종목 아키타입 Markov 행렬: 6종 아키타입별 비대칭 전환 행렬 + seasonDrift, per-stock 행렬 선택(C++ archetype_key 파라미터)
- [ADR-026](../../docs/architecture/026-macro-trend-layer.md) — 매크로 추세 레이어: 일봉 3-state Markov (driftScale + self-prob 0.96 + seasonBias→macro_tm 리다이렉트, CACHE_VERSION=6)
- [ADR-027](../../docs/architecture/027-price-kernel-unification.md) — Price Kernel 통합: 4개 GDScript 가격 시스템 → 단일 C++ PriceKernel (MarkovEngine·EventEngine·EtfEngine·ReportEngine), 히스토리 동일 커널 시뮬

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
