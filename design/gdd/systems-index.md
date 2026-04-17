# Systems Index: Seed Money (시드머니)

> **Status**: Draft
> **Created**: 2026-03-25
> **Last Updated**: 2026-04-08
> **Source Concept**: design/gdd/game-concept.md

---

## Overview

시드머니는 실시간 투자 시뮬레이션으로, 시장 시뮬레이션 엔진을 중심으로 매매, 분석,
성장, 경쟁 시스템이 유기적으로 연결된 구조다. 코어 루프는 "뉴스/차트 읽기 → 매매
판단 → 결과 확인"이며, 이를 감싸는 시즌 대회와 스킬 트리가 장기 프로그레션을 제공한다.

게임 필라 "판단이 곧 실력"에 따라 모든 시스템은 플레이어의 분석과 판단을 중심으로
설계되며, "읽는 재미" 필라에 따라 정보 접근성이 UI 설계의 최우선 원칙이다.

총 21개 시스템, 11개 MVP, 6개 Vertical Slice, 2개 Alpha, 2개 Full Vision.

---

## Systems Enumeration

| # | System Name | Category | Priority | GDD | Impl | Design Doc | Depends On |
|---|-------------|----------|----------|-----|------|------------|------------|
| 1 | 게임 시계 (Game Clock) | Core | MVP | In Review | ✅ Done | [game-clock.md](game-clock.md) | — |
| 2 | 종목 데이터베이스 (Stock Database) | Core | MVP | Approved | ✅ Done | [stock-database.md](stock-database.md) | — |
| 3 | 가격 엔진 (Price Engine) | Gameplay | MVP | In Review | ✅ Done | [price-engine.md](price-engine.md) | 게임 시계, 종목 DB |
| 4 | 뉴스/이벤트 시스템 (News & Events) | Gameplay | MVP | In Review | ✅ Done | [news-events.md](news-events.md) | 게임 시계, 종목 DB |
| 5 | 주문 처리 엔진 (Order Engine) | Gameplay | MVP | In Review | ✅ Done | [order-engine.md](order-engine.md) | 종목 DB, 재화 시스템, 가격 엔진, 게임 시계, 포트폴리오 |
| 6 | 포트폴리오 관리 (Portfolio Manager) | Gameplay | MVP | Approved | ✅ Done | [portfolio-manager.md](portfolio-manager.md) | 종목 DB, 재화 시스템 |
| 7 | AI 경쟁자 시스템 (AI Competitors) | Gameplay | V-Slice | Approved | ✅ Done | [ai-competitor.md](ai-competitor.md) | 게임 시계 (TICKS_PER_DAY), 시즌/대회 관리 |
| 8 | 스킬 트리 시스템 (Skill Tree) | Progression | V-Slice | In Review | ✅ Done | [skill-tree.md](skill-tree.md) | 경험치 시스템 |
| 9 | 경험치 시스템 (XP System) | Progression | V-Slice | Approved | ✅ Done | [xp-system.md](xp-system.md) | 주문 엔진, 포트폴리오, 게임 시계 |
| 10 | 시즌/대회 관리 (Season Manager) | Progression | V-Slice | Approved | ✅ Done | [season-manager.md](season-manager.md) | 가격 엔진, 포트폴리오, AI 경쟁자, 재화 |
| 11 | 재화 시스템 (Currency System) | Economy | MVP | In Review | ✅ Done | [currency-system.md](currency-system.md) | — |
| 12 | 트레이딩 스크린 (Main HUD) | UI | MVP | In Review | ✅ Done | [trading-screen.md](trading-screen.md) | 가격 엔진, 주문 엔진, 포트폴리오, 게임 시계 |
| 13 | 차트 렌더러 (Chart Renderer) | UI | MVP | In Review | ✅ Done | [chart-renderer.md](chart-renderer.md) | 가격 엔진, 게임 시계 |
| 14 | 뉴스 피드 UI (News Feed UI) | UI | MVP | In Review | ✅ Done | [news-feed-ui.md](news-feed-ui.md) | 뉴스/이벤트 시스템, 게임 시계 |
| 15 | 포트폴리오 UI (Portfolio UI) | UI | MVP | In Review | ✅ Done | [portfolio-ui.md](portfolio-ui.md) | 포트폴리오 관리, 게임 시계 |
| 16 | 리그/시즌 UI (League & Season UI) | UI | V-Slice | Approved | ✅ Done | [league-ui.md](league-ui.md) | 시즌/대회 관리, AI 경쟁자, 게임 시계 |
| 17 | ~~프로그레션 UI (Progression UI)~~ → **F3 성장 화면** | UI | V-Slice→Beta | In Review | ✅ Done | [growth-screen.md](growth-screen.md) | 경험치 시스템, 스킬 트리, 게임 시계, 트레이딩 스크린 · ⚠️ 구 progression-ui.md → `design/gdd/archive/` |
| 18 | 세이브/로드 (Save/Load) | Persistence | Alpha | Approved | ✅ Done | [save-load.md](save-load.md) | 포트폴리오, 스킬 트리, 시즌, 경험치 |
| 19 | 오디오 시스템 (Audio) | Audio | Alpha | Approved | ✅ Done | [audio.md](audio.md) | 주문 엔진, 뉴스 시스템 |
| 20 | 라이프스타일 소비 (Lifestyle Spending) | Economy | Beta | In Review | ✅ Done | [lifestyle-spending.md](lifestyle-spending.md) | 재화 시스템, 시즌 관리, 세이브/로드 |
| 21 | 수익 실현 팡파레 (Profit Celebration) | UI | Beta | Draft | — | [profit-celebration.md](profit-celebration.md) | 주문 엔진, 오디오, 트레이딩 스크린 |
| 22 | 오더북 (Order Book) | Gameplay | Beta | In Review | ✅ Done | [order-book.md](order-book.md) | 가격 엔진, 주문 엔진 |
| 23 | TR2 손절/익절 (Stop-Loss/Take-Profit) | Gameplay | Beta | In Review | ✅ Done | [stop-loss-take-profit.md](stop-loss-take-profit.md) | 주문 엔진, 스킬 트리 |
| 24 | 스타트 스크린 (Start Screen) | UI | Alpha | In Review | ✅ Done | [start-screen.md](start-screen.md) | 세이브/로드 |
| 25 | 인트로 시퀀스 (Intro Sequence) | UI | Alpha | Approved | ✅ Done | [intro-sequence.md](intro-sequence.md) | — |
| 26 | 크레딧 화면 (Credits Screen) | UI | Full | Draft | — | [credits-screen.md](credits-screen.md) | — |
| 27 | A3 재무제표 (Financial Statements) | UI | Beta | In Review | ✅ Done | [financial-statements.md](financial-statements.md) | 스킬 트리, StockData, 가격 엔진 |
| 28 | S3 루머 채널 (Rumor Channel) | Gameplay | Beta | In Review | ✅ Done | [rumor-channel.md](rumor-channel.md) | 스킬 트리, 뉴스/이벤트, 뉴스 피드 UI |
| 29 | 설정 화면 (Settings Screen) | UI | Beta | Approved | ✅ Done | [settings-screen.md](settings-screen.md) | AudioManager, GameClock |
| 30 | 거래 수수료·세금 (Trading Fees) | Economy | Beta | In Review | ✅ Done | [trading-fees.md](trading-fees.md) | 주문 엔진, 포트폴리오 관리, 재화 시스템, MarketConfig |
| 31 | TR3 공매도 (Short Selling) | Gameplay | Full | In Review | ✅ Done | [short-selling.md](short-selling.md) | 주문 엔진, 포트폴리오 관리, 재화 시스템, 가격 엔진, 스킬 트리, 시즌 관리, 세이브/로드 |
| 32 | TR4 레버리지 거래 (Leverage Trading) | Gameplay | Beta | In Review | ✅ Done | [leverage-trading.md](leverage-trading.md) | 주문 엔진, 포트폴리오 관리, 스킬 트리, 라이프스타일 |
| 33 | 튜토리얼 (Tutorial) | Meta | Full | Not Started | — | — | 전체 게임플레이 시스템 |
| 34 | OHLCV 시즌 간 누적 (OhlcvHistory) | Gameplay | Beta | Approved | ✅ Done | [price-engine.md](price-engine.md) §OHLCV | 가격 엔진, 시즌 관리, 차트 렌더러, 세이브/로드 |

> **라이프스타일 소비 (Sprint 8 B-12 완료)**: `LifestyleManager` 구현 완료. 매일 장 마감 시 `process_market_close(day, week)` 호출. 시즌 마지막 날에만 임대 수익·스타트업 엑싯·Recurring 비용 처리. 소비 화면은 매일 장 마감 후 표시. 실물 자산(`get_tangible_value()`)은 Sprint 9 B-02 이월.

---

## Categories

| Category | Description | Systems |
|----------|-------------|---------|
| **Core** | 모든 시스템이 의존하는 기반 시스템 | 게임 시계, 종목 DB |
| **Gameplay** | 게임을 재미있게 만드는 핵심 메카닉 | 가격 엔진, 뉴스/이벤트, 주문 엔진, 포트폴리오, AI 경쟁자 |
| **Progression** | 플레이어의 장기 성장 | 스킬 트리, 경험치, 시즌/대회 |
| **Economy** | 재화 생성과 소비 | 재화 시스템 |
| **UI** | 정보 표시와 플레이어 인터페이스 | 트레이딩 스크린, 차트, 뉴스 UI, 포트폴리오 UI, 리더보드 UI, 스킬 트리 UI |
| **Persistence** | 게임 상태 저장 | 세이브/로드 |
| **Audio** | 사운드와 음악 | 오디오 시스템 |
| **Meta** | 코어 루프 밖의 시스템 | 튜토리얼, 설정 |

---

## Priority Tiers

| Tier | Definition | Target Milestone | Systems Count |
|------|------------|------------------|---------------|
| **MVP** | 코어 루프 검증에 필수. "뉴스/차트 읽고 매매하는 게 재미있는가?" | 첫 플레이 가능 빌드 | 11 |
| **Vertical Slice** | 시즌 대회 + 성장 루프의 완전한 체험 | 완성된 데모 | 6 |
| **Alpha** | 세이브/로드, 오디오 등 전체 기능 | 알파 마일스톤 | 2 |
| **Full Vision** | 튜토리얼, 설정 등 폴리시 | 베타 / 릴리스 | 2 |

---

## Dependency Map

### Foundation Layer (no dependencies)

1. **게임 시계** — 거래일/주/시즌의 시간 흐름을 제어. 실시간 시뮬레이션의 기반
2. **종목 데이터베이스** — 가상 종목의 정의 (이름, 섹터, 기본가치, 특성). 모든 게임플레이의 데이터 원천
3. **재화 시스템** — 예수금(단일 계좌) 관리. 매매와 보상의 기반. 수익/손실 직접 반영, 복리 성장 구조

### Core Layer (depends on Foundation)

1. **가격 엔진** — depends on: 게임 시계, 종목 DB. 가격 변동 알고리즘의 심장
2. **뉴스/이벤트 시스템** — depends on: 게임 시계, 종목 DB. 시장 이벤트 생성 및 가격 엔진에 입력
3. **주문 처리 엔진** — depends on: 종목 DB, 재화 시스템. 매수/매도 주문 접수 및 체결
4. **포트폴리오 관리** — depends on: 종목 DB, 재화 시스템. 보유 종목 추적 및 손익 계산. 시즌 종료 시 강제 청산, 예수금 이월

### Feature Layer (depends on Core)

1. **AI 경쟁자 시스템** — depends on: 가격 엔진, 주문 엔진, 포트폴리오. AI 트레이더 매매 행동
2. **경험치 시스템** — depends on: 주문 엔진, 포트폴리오. 거래/수익률 기반 XP 산출
3. **스킬 트리 시스템** — depends on: 경험치 시스템. 스킬 해금 로직 및 효과 적용
4. **시즌/대회 관리** — depends on: 가격 엔진, 포트폴리오, AI 경쟁자, 재화. 시즌 수명주기

### Presentation Layer (depends on Features)

1. **트레이딩 스크린** — depends on: 가격 엔진, 주문 엔진, 포트폴리오. 메인 화면 레이아웃
2. **차트 렌더러** — depends on: 가격 엔진. 캔들차트/거래량/지표 시각화
3. **뉴스 피드 UI** — depends on: 뉴스/이벤트 시스템. 뉴스 표시 및 알림
4. **포트폴리오 UI** — depends on: 포트폴리오 관리. 보유 종목/손익 표시
5. **리더보드 UI** — depends on: 시즌/대회 관리. 순위 표시
6. **스킬 트리 UI** — depends on: 스킬 트리 시스템. 스킬 트리 시각화

### Polish Layer (depends on everything)

1. **세이브/로드** — depends on: 포트폴리오, 스킬 트리, 시즌, 경험치. 전체 상태 직렬화
2. **오디오** — depends on: 주문 엔진, 뉴스 시스템. 이벤트 기반 사운드
3. **튜토리얼** — depends on: 전체 게임플레이 시스템. 플레이어 안내
4. **설정** — 독립적. 게임 옵션 관리

---

## Recommended Design Order

| Order | System | Priority | Layer | Est. Effort |
|-------|--------|----------|-------|-------------|
| 1 | 게임 시계 (Game Clock) | MVP | Foundation | S |
| 2 | 종목 데이터베이스 (Stock Database) | MVP | Foundation | S |
| 3 | 재화 시스템 (Currency System) | MVP | Foundation | S |
| 4 | 가격 엔진 (Price Engine) | MVP | Core | L |
| 5 | 뉴스/이벤트 시스템 (News & Events) | MVP | Core | M |
| 6 | 주문 처리 엔진 (Order Engine) | MVP | Core | M |
| 7 | 포트폴리오 관리 (Portfolio Manager) | MVP | Core | M |
| 8 | 트레이딩 스크린 (Main HUD) | MVP | Presentation | M |
| 9 | 차트 렌더러 (Chart Renderer) | MVP | Presentation | M |
| 10 | 뉴스 피드 UI (News Feed UI) | MVP | Presentation | S |
| 11 | 포트폴리오 UI (Portfolio UI) | MVP | Presentation | S |
| 12 | AI 경쟁자 시스템 (AI Competitors) | V-Slice | Feature | M |
| 13 | 경험치 시스템 (XP System) | V-Slice | Feature | S |
| 14 | 스킬 트리 시스템 (Skill Tree) | V-Slice | Feature | M |
| 15 | 시즌/대회 관리 (Season Manager) | V-Slice | Feature | M |
| 16 | 리더보드 UI (Leaderboard UI) | V-Slice | Presentation | S |
| 17 | 스킬 트리 UI (Skill Tree UI) | V-Slice | Presentation | S |
| 18 | 세이브/로드 (Save/Load) | Alpha | Persistence | M |
| 19 | 오디오 시스템 (Audio) | Alpha | Audio | S |
| 20 | 튜토리얼 (Tutorial) | Full | Meta | M |
| 21 | 설정 (Settings) | Full | Meta | S |

> **Effort**: S = 1 세션, M = 2-3 세션, L = 4+ 세션

---

## Circular Dependencies

- **없음**. 뉴스/이벤트 → 가격 엔진은 단방향 이벤트 입력으로 설계.

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| 가격 엔진 | Design + Technical | 게임 전체 재미를 좌우. "패턴 있되 예측불가"한 균형점 설계가 가장 어려운 과제. 너무 랜덤하면 도박, 너무 패턴화되면 퍼즐이 됨 | 프로토타입으로 반복 검증 (`/prototype price-engine`). 복수 알고리즘 A/B 테스트 |
| 차트 렌더러 | Technical | 실시간 캔들차트 + 거래량을 웹에서 부드럽게 렌더링. Godot 웹 export의 UI 성능 미검증 | 기술 프로토타입으로 웹 성능 확인. 대안: Canvas 2D 직접 그리기 |
| 트레이딩 스크린 | Design | 차트/호가창/뉴스/포트폴리오를 한 화면에 깔끔하게 배치하는 UX. 정보 과부하 vs 접근성 균형 | UX 와이어프레임 먼저 설계. 실제 증권 HTS 레이아웃 참고 |

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | 23 |
| Design docs started | 17 |
| Design docs reviewed (2차 리뷰 완료) | 17 |
| Design docs approved | 9 (종목 DB, 포트폴리오, XP, AI 경쟁자, 시즌/대회 관리, 리그/시즌 UI, currency-system, save-load, audio) |
| Design docs in review | 8 |
| **Implemented** | **20** (MVP 11/11 + V-Slice 6 + Alpha 2: 세이브/로드, 오디오) |
| MVP systems designed | 11/11 |
| MVP systems implemented | 11/11 |
| Vertical Slice systems designed | 6/6 ✅ (XP, Skill Tree, Progression UI, AI 경쟁자, 시즌 관리, 리그 UI) |
| Vertical Slice systems implemented | 6/6 ✅ |
| Alpha systems implemented | 2/2 ✅ (세이브/로드, 오디오) |
| GDD vs 구현 QA 완료 | **17/17** ✅ (전체 구현 시스템 검증 완료, GDD 갱신 완료) |
| 컨셉 변경 | 모의투자→실전투자 (단일 계좌, 복리 구조) 반영 완료 |

---

## Next Steps

- [x] Design MVP-tier systems (11/11 complete — all Approved)
- [x] Foundation: 게임 시계 → 종목 DB → 재화 시스템 (complete)
- [x] Core: 가격 엔진 → 뉴스/이벤트 → 주문 엔진 → 포트폴리오 (complete)
- [x] Prototype price engine (`prototypes/price-engine/`)
- [x] V-Slice progression: XP 시스템, 스킬 트리, 프로그레션 UI (3/6 complete)
- [x] **GDD vs 구현 QA**: 15/15 전체 완료 (2026-04-02). game-clock.md 대폭 갱신, price-engine/chart-renderer/stock-database 소폭 갱신
- [x] **2차 전체 GDD 리뷰** (2026-04-03): 47개 이슈 발견 → 수정 완료. Lv→스킬ID 표기 통일, 수치 오류 수정, API 일관성 확보
- [x] **컨셉 변경** (2026-04-03): 모의투자→실전투자. 단일 계좌(예수금 직접 투자), 복리 성장 구조. currency-system.md 전면 재작성
- [x] Design remaining V-Slice systems: AI 경쟁자 (Approved), 시즌/대회 관리 (Approved), 리그/시즌 UI (Approved) — Sprint 2, 2026-04-03
- [ ] Run `/gate-check pre-production` when ready
- [ ] Run `/design-review` on each new GDD

---

## Non-GDD Design Documents

GDD가 아닌 디자인 보조 문서. 여기에 없는 `design/*.md` 파일은 참조 루틴이 없는 것이므로 폐기 대상.

| 파일 | 목적 | 최종 갱신 | 상태 |
|------|------|----------|------|
| [art-bible.md](../art-bible.md) | 색상 팔레트, 타이포그래피, UI 컴포넌트 스타일 가이드 | 2026-04-15 | Draft |
| [audio-plan.md](../audio-plan.md) | 시장 상태별 BGM 방향, SFX 가이드 | 2026-04-15 | Draft |
| [residence-art-direction.md](../residence-art-direction.md) | 거주지 배경 이미지 스타일 기준 + 에셋 현황 | 2026-04-15 | Draft |
| [residence-image-prompts.md](../residence-image-prompts.md) | 11티어 거주지 AI 이미지 생성 프롬프트 | 2026-04-15 | Active |
