# Sprint 1 — 2026-04-01 to 2026-04-14

## Sprint Goal

MVP 보강(VI/서킷브레이커, 지수 HUD, 테스트 환경)을 완료하고,
경험치+스킬 트리를 구현하여 "플레이할수록 도구가 해금되는 성장 루프"를 완성한다.

## Capacity

- Total sessions: 10
- Buffer (20%): 2 sessions (버그 수정, 예기치 않은 작업)
- Available: 8 sessions
- **Unplanned 소요**: 5.35 sessions (섹터/종목 확장, mutex_group, 뉴스 버그/UI, QA)
- **실질 잔여**: 1.40 sessions

## Tasks

### Must Have (Critical Path)

| ID | Task | Category | Est. | Dependencies | Status |
|----|------|----------|------|-------------|--------|
| S1-01 | VI(변동성완화장치) 구현 | Gameplay | 1 sess | GDD 완료 | ✅ Done (pre-sprint `d66fa74`) |
| S1-02 | 서킷브레이커 구현 | Gameplay | 0.5 sess | S1-01 | ✅ Done (pre-sprint `d66fa74`) |
| S1-03 | 시장 지수 HUD 표시 | UI | 0.5 sess | — | ✅ Done (pre-sprint, trading_screen.gd) |
| S1-06 | 경험치 시스템 GDD 작성 | Design | 0.5 sess | — | ✅ Done (pre-sprint, xp-system.md Approved) |
| S1-07 | 경험치 시스템 구현 | Gameplay | 1 sess | S1-06 | ✅ Done (pre-sprint, xp_system.gd + 23 tests) |
| S1-13 | 스킬 트리 시스템 구현 | Gameplay | 2 sess | S1-07, GDD Approved | ✅ Done (pre-sprint, skill_tree.gd + 25 tests) |

### Should Have

| ID | Task | Category | Est. | Dependencies | Status |
|----|------|----------|------|-------------|--------|
| S1-08 | GUT 테스트 프레임워크 설치 | Infra | 0.5 sess | — | ✅ Done (pre-sprint `84000a3`) |
| S1-09 | VI/CB 유닛 테스트 | Test | 0.5 sess | S1-01, S1-02 | ✅ Done (test_vi_cb.gd, 22 tests) |
| S1-10 | 호가 단위 유닛 테스트 | Test | 0.5 sess | — | ✅ Done (test_order_engine.gd) |

### Nice to Have

| ID | Task | Category | Est. | Dependencies | Status |
|----|------|----------|------|-------------|--------|
| S1-11 | ADR 추가 (호가 단위, 에너지-거래량) | Docs | 0.5 sess | — | ✅ Done (ADR-002, ADR-003) |
| S1-12 | 프로토타입 README 작성 | Docs | 0.25 sess | — | ✅ Done (REPORT.md 이미 존재) |

### Moved to Sprint 2

| ID | Task | Reason |
|----|------|--------|
| S1-04 | AI 경쟁자 시스템 GDD 작성 | 시즌/대회 관리와 강결합. Sprint 2에서 함께 설계 |
| S1-05 | AI 경쟁자 시스템 구현 | S1-04에 의존. Sprint 2로 이동 |

### Unplanned (스프린트 중 추가)

| ID | Task | Category | Est. | Dependencies | Status |
|----|------|----------|------|-------------|--------|
| S1-U1 | 섹터 확장 (8→11) + 종목 확장 (10→46) — stock-database.md GDD 전면 개정 | Design | 1 sess | — | ✅ Done |
| S1-U2 | Narrative State Tracker 설계 + mutex_group — news-events.md GDD 개정 | Design | 0.5 sess | — | ✅ Done |
| S1-U3 | event_pool.json 확장 (31→50 템플릿, mutex_group 필드 추가) | Data | 0.5 sess | S1-U2 | ✅ Done |
| S1-U4 | 섹터명 마이그레이션 (season_themes.json, stock_database.gd) | Code | 0.25 sess | S1-U1 | ✅ Done |
| S1-U5 | mutex_group 구현 (news_event_system.gd) + 유닛 테스트 13건 | Gameplay/Test | 0.5 sess | S1-U2 | ✅ Done |
| S1-U6 | 외부 리뷰 반영 — order-engine.md CB 엣지 케이스, news-feed-ui.md Open Questions | Design | 0.25 sess | — | ✅ Done |
| S1-U7 | event_pool.json 파싱 버그 수정 (VARIABLE 미인용) + 뉴스 시스템 디버깅 | Bugfix | 0.5 sess | — | ✅ Done |
| S1-U8 | 토스트 알림 시스템 구현 (하단 중앙, 페이드 애니메이션) | UI | 0.5 sess | S1-U7 | ✅ Done |
| S1-U9 | 하단 3탭 안읽음 뱃지 (뉴스/VI·CB/포트폴리오) + 탭 상태 버그 수정 | UI | 0.25 sess | — | ✅ Done |
| S1-U10 | 주문 패널 축소 (stretch 0.18→0.13, min 160px) | UI | 0.1 sess | — | ✅ Done |
| S1-U11 | 뉴스 카드 본문 확장 기능 구현 (클릭 시 body+관련종목 토글) | UI | 0.25 sess | — | ✅ Done |
| S1-U12 | SECTOR 템플릿 10개 추가 (50→60, 바이오/금융/엔터/반도체/건설/유통/2차전지) | Data | 0.25 sess | — | ✅ Done |
| S1-U13 | GDD vs 구현 QA 검증 (3시스템) + GDD 불일치 수정 (딜레이/토스트/비율/숫자키) | QA/Design | 0.5 sess | — | ✅ Done |

## Capacity Check (조정 후)

| Category | Sessions |
|----------|----------|
| 잔여 Available | 5 |
| Must Have 잔여 | 0 (전부 완료) |
| Should Have 잔여 (S1-09) | 0.5 |
| Nice to Have (S1-11, S1-12) | 0.75 |
| Unplanned 소요 (U7~U13) | 2.35 |
| **여유** | **1.40** |

## Carryover from Previous Sprint

없음 (첫 스프린트)

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| AI 경쟁자 설계가 복잡해져 2세션 초과 | Medium | High | MVP 수준 AI(랜덤+규칙 기반)로 범위 제한. 학습형 AI는 후속 스프린트 |
| VI/CB가 기존 가격 엔진과 충돌 | Low | Medium | 가격 엔진 GDD에 이미 설계 포함. 시그널 기반 분리 |
| GUT 설치 시 Godot 4.6 호환 문제 | Low | Low | GUT 최신 버전 확인. 실패 시 커스텀 테스트 러너 유지 |

## Dependencies on External Factors

- GUT 프레임워크의 Godot 4.6 호환성 (외부 addon)

## Definition of Done for this Sprint

- [x] Must Have 6개 태스크 전부 완료 (S1-01,02,03,06,07,13 모두 pre-sprint)
- [x] VI/CB 발동 시 뉴스 생성 확인 (VI/CB alerts → trading_screen alerts tab)
- [x] 경험치가 장 마감 시 수익률 기반으로 부여되는 것 확인 (xp_system.gd + 23 tests)
- [ ] 헤드리스 테스트 통과 (기존 + 신규)
- [x] GDD 업데이트 완료 (trading-screen, news-feed-ui, news-events 3건 QA 후 수정)
- [ ] 코드 커밋 완료
