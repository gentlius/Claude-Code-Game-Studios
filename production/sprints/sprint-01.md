# Sprint 1 — 2026-04-01 to 2026-04-14

## Sprint Goal

MVP 보강(VI/서킷브레이커, 지수 HUD, 테스트 환경)을 완료하고,
경험치+스킬 트리를 구현하여 "플레이할수록 도구가 해금되는 성장 루프"를 완성한다.

## Capacity

- Total sessions: 10
- Buffer (20%): 2 sessions (버그 수정, 예기치 않은 작업)
- Available: 8 sessions
- **Unplanned 소요**: 3 sessions (섹터/종목 확장, mutex_group)
- **실질 잔여**: 5 sessions

## Tasks

### Must Have (Critical Path)

| ID | Task | Category | Est. | Dependencies | Status |
|----|------|----------|------|-------------|--------|
| S1-01 | VI(변동성완화장치) 구현 | Gameplay | 1 sess | GDD 완료 | ✅ Done (pre-sprint `d66fa74`) |
| S1-02 | 서킷브레이커 구현 | Gameplay | 0.5 sess | S1-01 | ✅ Done (pre-sprint `d66fa74`) |
| S1-03 | 시장 지수 HUD 표시 | UI | 0.5 sess | — | ⬜ UI 연결만 남음 |
| S1-06 | 경험치 시스템 GDD 작성 | Design | 0.5 sess | — | ⬜ |
| S1-07 | 경험치 시스템 구현 | Gameplay | 1 sess | S1-06 | ⬜ |
| S1-13 | 스킬 트리 시스템 구현 | Gameplay | 2 sess | S1-07, GDD Approved | ⬜ (GDD 이미 Approved) |

### Should Have

| ID | Task | Category | Est. | Dependencies | Status |
|----|------|----------|------|-------------|--------|
| S1-08 | GUT 테스트 프레임워크 설치 | Infra | 0.5 sess | — | ✅ Done (pre-sprint `84000a3`) |
| S1-09 | VI/CB 유닛 테스트 | Test | 0.5 sess | S1-01, S1-02 | ⬜ |
| S1-10 | 호가 단위 유닛 테스트 | Test | 0.5 sess | — | ✅ Done (test_order_engine.gd) |

### Nice to Have

| ID | Task | Category | Est. | Dependencies | Status |
|----|------|----------|------|-------------|--------|
| S1-11 | ADR 추가 (호가 단위, 에너지-거래량) | Docs | 0.5 sess | — | ⬜ |
| S1-12 | 프로토타입 README 작성 | Docs | 0.25 sess | — | ⬜ |

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

## Capacity Check (조정 후)

| Category | Sessions |
|----------|----------|
| 잔여 Available | 5 |
| Must Have 잔여 (S1-03 + S1-06 + S1-07 + S1-13) | 4 |
| Should Have 잔여 (S1-09) | 0.5 |
| **여유** | **0.5** |

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

- [ ] Must Have 7개 태스크 전부 완료
- [ ] VI/CB 발동 시 뉴스 생성 확인
- [ ] AI 경쟁자가 시즌 동안 매매하고 포트폴리오 변동 확인
- [ ] 경험치가 거래 시 증가하는 것 확인
- [ ] 헤드리스 테스트 통과 (기존 + 신규)
- [ ] GDD 업데이트 완료 (변경사항 반영)
- [ ] 코드 커밋 완료
