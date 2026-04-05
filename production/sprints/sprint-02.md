# Sprint 2 -- 2026-04-14 to 2026-04-28

## Progress Snapshot (2026-04-04) — **Sprint Closed ✅**

- **계획 작업**: 8/8 완료 (Must Have 4/4, Should Have 2/2, Nice to Have 2/2)
- **비계획 작업**: 6/6 완료 (league-ui GDD, 연동 업데이트, GDD 수정, ADR 4건, 런타임 버그 3건)
- **판정**: Sprint 2 DoD 충족. V-Slice 5/6 구현 완료. Sprint 3로 이월: 리그 F2탭 UI, TD-08(SeasonManager 진입점).

## Sprint Goal

AI 경쟁자 시스템과 시즌/대회 관리(리그 승강제 포함)를 설계 및 구현하여,
"AI와 수익률을 겨루는 시즌 대회"의 핵심 루프를 완성한다.

## Capacity

- Total sessions: 10
- Buffer (20%): 2 sessions (버그 수정, 예기치 않은 작업)
- Available: 8 sessions
- Sprint 1 velocity: 계획 6.75 + 비계획 5.35 = 12.1 sessions 소화 (buffer 초과)
- Sprint 2 비계획 예상: Sprint 1 대비 감소 예상 (기반 시스템 안정화됨), 2 sessions buffer 유지

## Carryover from Sprint 1

| Task | Reason | New Estimate |
|------|--------|-------------|
| S1-04 AI 경쟁자 GDD 작성 | 시즌/대회와 강결합, Sprint 2로 의도적 이동 | S2-01로 재편 |
| S1-05 AI 경쟁자 구현 | S1-04 의존. Sprint 2로 이동 | S2-03으로 재편 |

## Pre-Sprint Requirement: GDD 작성 순서

구현 전 반드시 GDD가 Approved 상태여야 한다 (GDD-first workflow).

1. **ai-competitor.md** -- AI 경쟁자 시스템 GDD (독립적, 먼저 작성 가능)
2. **season-manager.md** -- 시즌/대회 관리 + 리그 승강제 GDD (AI 경쟁자 GDD 참조)

두 GDD 모두 8 필수 섹션 포함: Overview, Player Fantasy, Detailed Design,
Formulas, Edge Cases, Dependencies, Tuning Knobs, Acceptance Criteria.

## Tasks

### Must Have (Critical Path)

| ID | Task | Category | Est. | Dependencies | Status | Acceptance Criteria |
|----|------|----------|------|-------------|--------|---------------------|
| S2-01 | AI 경쟁자 시스템 GDD 작성 (ai-competitor.md) | Design | 1 sess | — | **Completed/Approved** | 8 필수 섹션 완료, AI 성격 유형/매매 로직/난이도 스케일링 정의, Approved 상태 |
| S2-02 | 시즌/대회 관리 + 리그 승강제 GDD 작성 (season-manager.md) | Design | 1.5 sess | S2-01 | **Completed/Approved** | 8 필수 섹션 완료, 시즌 수명주기/리그 티어/승강 조건/상금 공식 정의, Approved 상태 |
| S2-03 | AI 경쟁자 시스템 구현 | Gameplay | 2 sess | S2-01 (Approved) | **Completed** | 통계적 수익률 생성 파이프라인, 11티어 TIER_PARAMS, 유닛 테스트 통과 (AC-01~08, EC-01~12) |
| S2-04 | 시즌/대회 관리 + 리그 승강제 구현 | Gameplay | 2.5 sess | S2-02 (Approved), S2-03 | **Completed** | 시즌 수명주기 구현, 티어 배정, AI 초기화, 상금/XP 지급, 유닛 테스트 23건 통과 |

### Should Have

| ID | Task | Category | Est. | Dependencies | Status | Acceptance Criteria |
|----|------|----------|------|-------------|--------|---------------------|
| S2-05 | TD-01 수정: 틱 처리 순서 보장 | Tech Debt | 0.5 sess | — | **Completed** | GameClock._process_tick()이 NewsEventSystem→PriceEngine→OrderEngine 명시적 순차 호출로 이미 구현됨. S2-03 구현 과정에서 확인 완료 |
| S2-06 | TD-02 수정: reset_for_testing() 메서드 추가 | Tech Debt | 0.5 sess | — | **Completed** | 10개 시스템 전체 추가 완료 (GameClock, PortfolioManager, XpSystem, AiCompetitor, SeasonManager 신규; 나머지 5개 기확보). 계약 테스트 추가 |

### Nice to Have

| ID | Task | Category | Est. | Dependencies | Status | Acceptance Criteria |
|----|------|----------|------|-------------|--------|---------------------|
| S2-07 | systems-index.md 갱신 (AI, Season GDD 링크 추가) | Docs | 0.25 sess | S2-01, S2-02 | **Completed** | Systems 7, 10 → ✅ Done. V-Slice 구현 5/6으로 갱신 |
| S2-08 | v-slice.md 마일스톤 진행 상태 업데이트 | Docs | 0.1 sess | S2-03, S2-04 | **Completed** | AI 경쟁자·시즌 관리 ✅ Done 반영 |

### Unplanned Work (Sprint 중 발생)

| ID | Task | Category | Est. | Dependencies | Status | Notes |
|----|------|----------|------|-------------|--------|-------|
| S2-U1 | league-ui.md GDD 작성 | Design | ~1 sess | S2-02 | **Completed/Approved** | 시즌/리그 GDD 작성 과정에서 리그 UI 설계 필요성 발견, 별도 GDD로 분리 |
| S2-U2 | xp-system.md, currency-system.md 연동 업데이트 | Design | ~0.5 sess | S2-02 | **Completed** | 시즌 보상 체계와의 연동 반영을 위해 기존 GDD 수정 |
| S2-U3 | trading-screen.md 수정 | Design | ~0.25 sess | S2-U1 | **Completed** | 리그/시즌 관련 UI 요소 반영 |
| S2-U4 | progression-ui.md 수정 | Design | ~0.25 sess | S2-U1 | **Completed** | 리그 승강 관련 프로그레션 UI 반영 |
| S2-U5 | ADR-004~007 작성 | Arch | ~0.5 sess | S2-03, S2-04 | **Completed** | S2-03/S2-04 구현 중 결정된 아키텍처 4건 문서화 (AI 시뮬레이션, XP 소유권, 탭 소유권, 글로벌 순위) |
| S2-U6 | 런타임 버그 3건 수정 (빌드 검증 중 발견) | Bug | ~0.25 sess | S2-03, S2-04 | **Completed** | 바이너리 실행 검증 중 발견: ① CurrencySystem.init_season_seed()→init_first_season(), ② PortfolioManager.get_holdings()→get_all_holdings(), ③ skill_tree_overlay._disconnect_signals 미정의 제거 |

## Capacity Check

| Category | Sessions |
|----------|----------|
| Available (buffer 제외) | 8 |
| Must Have 합계 | 7 |
| Should Have 합계 | 1 |
| Nice to Have 합계 | 0.35 |
| Unplanned 합계 (실제 소화) | 2 |
| **합계** | **10.35** |
| **초과** | **-2.35 (buffer 초과)** |

> 비계획 작업 2 sessions 발생 (league-ui GDD, 연동 업데이트, 기존 GDD 수정).
> S2-02 완료 과정에서 파생된 필수 작업이므로 정당한 scope 추가.
> Sprint 1 비계획 비율(53%) 대비 개선(~20%) -- 기반 시스템 안정화 효과 확인.

## Critical Path

```
S2-01 (AI GDD, 1s) ◀── IN PROGRESS
  └─→ S2-03 (AI 구현, 2s)
        └─→ S2-04 (Season 구현, 2.5s)

S2-02 (Season GDD, 1.5s) ✅ DONE
  └─→ S2-04 (Season 구현, 2.5s) -- S2-02 의존성 해소됨
```

~~S2-04는 S2-02와 S2-03 모두에 의존. AI GDD(S2-01)가 블로커.~~
S2-02 완료로 의존성 1개 해소. S2-04의 남은 블로커는 S2-03 (AI 구현) 완료뿐.
현재 블로커: S2-01 (AI GDD) -- S2-01 Approved 후 S2-03 착수 가능.
S2-05, S2-06 (Tech Debt)은 독립적이므로 S2-01 완료 대기 중 병행 가능.

**현재 실행 순서** (업데이트):
1. ~~S2-01 (AI GDD) + S2-05/S2-06 (Tech Debt) 병행~~ → S2-01 진행 중
2. ~~S2-02 (Season GDD)~~ → **완료**
3. S2-03 (AI 구현) -- S2-01 Approved 후 바로 시작
4. S2-04 (Season 구현) -- S2-03 완료 후 (S2-02 의존성은 이미 해소)

## Risks

| Risk | Probability | Impact | Status | Mitigation |
|------|------------|--------|--------|------------|
| 리그 승강제 설계 복잡도가 예상 초과 | Medium | High | **해소** | season-manager.md GDD에서 5티어 설계 완료. 구현 복잡도는 S2-04에서 재평가 |
| AI 매매 로직 밸런싱에 시간 소모 | Medium | Medium | 유지 | MVP 수준 AI(규칙 기반 3종 성격)로 시작. 학습형/적응형 AI는 후속 |
| GDD 승인에 예상보다 많은 반복 필요 | Low | High | **부분 해소** | S2-02 승인 완료. S2-01은 현재 작성 중 -- 반복 가능성 잔존 |
| Season Manager가 GameClock/Portfolio에 대규모 변경 요구 | Low | Medium | **해소** | season-manager.md 설계에서 orchestrator 패턴 확정, 기존 시스템 최소 수정 확인 |
| Sprint 1 수준의 비계획 작업 발생 (5+ sessions) | Low | High | **완화** | 비계획 작업 ~2 sessions 발생 (Sprint 1의 5.35 대비 대폭 감소). Buffer 내 관리 가능 |
| S2-01 (AI GDD) 완료 지연으로 S2-03/S2-04 착수 불가 | **Medium** | **High** | **신규** | S2-01이 유일한 블로커. 지연 시 S2-05/S2-06 (Tech Debt)을 선행 처리하여 유휴 시간 최소화 |
| 비계획 GDD 수정 추가 발생 (AI GDD 파생) | Low | Medium | **신규** | S2-02에서 league-ui.md 등 파생 작업 경험. S2-01에서도 유사 패턴 가능. Buffer 잔여분으로 대응 |

## Key Design Questions (Sprint 시작 전 합의 필요)

리그 승강제 GDD 작성 전에 다음 질문에 대한 방향을 정해야 한다.

### AI 경쟁자 관련
1. **AI 성격 유형 수**: 몇 종류? (예: 공격형/안정형/밸류형 3종 vs 5종+)
2. **AI 난이도와 리그 연동**: 상위 리그일수록 AI가 더 잘하는가?
3. **AI 매매 빈도/전략 가시성**: 플레이어가 AI의 매매를 관찰할 수 있는가? (리더보드에서 수익률만 vs 포트폴리오 공개)

### 리그 승강제 관련
4. **리그 티어 수**: 3티어(하/중/상) vs 5티어(브론즈~다이아) vs 한국 스포츠식(3부/2부/1부)?
5. **승강 기준**: 상위 N% 승격 + 하위 N% 강등? 절대 수익률 기준? 순위 기반?
6. **시즌 간 상태**: 시즌 종료 시 보유주식 청산(확정), 예수금 이월(확정), 리그 티어 이월 — 맞는가?
7. **시작 리그**: 신규 플레이어는 최하위 리그에서 시작하는가?
8. **리그별 상금 차등**: 상위 리그일수록 상금이 큰가? (복리 성장 가속 = 성장 필라)
9. **리그별 참가자 수**: 각 리그에 AI 몇 명? (하위 리그 10명 vs 상위 리그 5명 등)

### 시즌 구조 관련
10. **시즌 길이**: 게임 내 몇 주(거래일)? (game-concept.md는 4-8주 언급)
11. **시즌 간 전환**: 즉시 다음 시즌 vs 시즌 종료 화면(결과/보상/승강 연출) 후 전환?

## Dependencies on External Factors

- 없음 (외부 라이브러리 추가 없음, 기존 시스템 위에 구축)

## GDD 작성 계획 (상세)

### 1. ai-competitor.md (S2-01)

예상 섹션 구성:
- **Overview**: AI 트레이더의 역할 (경쟁 상대, 시장 활성화)
- **Player Fantasy**: "나보다 잘하는 AI를 이기는 쾌감"
- **Detailed Design**: AI 성격 유형, 매매 로직, 포트폴리오 관리 규칙
- **Formulas**: AI 수익률 목표 공식, 매매 빈도 공식, 난이도 스케일링
- **Edge Cases**: AI가 파산할 때, 모든 AI가 같은 종목에 몰릴 때, 시즌 중 AI 추가/제거
- **Dependencies**: 가격 엔진, 주문 엔진, 포트폴리오, 시즌/대회(역참조)
- **Tuning Knobs**: AI 공격성, 매매 빈도, 정보 딜레이, 난이도 계수
- **Acceptance Criteria**: AI 5명이 독립적 매매 실행, 수익률 추적, 테스트 통과

### 2. season-manager.md (S2-02)

예상 섹션 구성:
- **Overview**: 시즌 대회 + 리그 승강제 = 장기 프로그레션의 뼈대
- **Player Fantasy**: "리그를 올라가며 더 강한 상대와 겨루는 성장감"
- **Detailed Design**: 시즌 수명주기 (대기→진행→정산→승강), 리그 티어 정의, 승강 조건, 상금 체계
- **Formulas**: 승격/강등 컷라인, 리그별 상금 공식, AI 난이도 스케일링 공식
- **Edge Cases**: 동률 처리, 최하위 리그 강등 불가, 최상위 리그 승격 불가, 첫 시즌 특수 처리
- **Dependencies**: AI 경쟁자, 가격 엔진, 포트폴리오, 재화, 게임 시계
- **Tuning Knobs**: 시즌 길이, 티어 수, 승격/강등 비율, 상금 배율
- **Acceptance Criteria**: 시즌 시작→종료 전체 흐름, 리그 승격/강등 정상 동작, 상금 지급 확인

## Definition of Done for this Sprint

- [x] ai-competitor.md GDD Approved (S2-01)
- [x] season-manager.md GDD Approved — 리그 승강제 포함 (S2-02)
- [x] league-ui.md GDD Approved — 비계획 추가 (S2-U1)
- [x] xp-system.md, currency-system.md 연동 업데이트 완료 (S2-U2)
- [x] trading-screen.md, progression-ui.md 수정 완료 (S2-U3, S2-U4)
- [x] AI 경쟁자 시스템 구현 완료 — ai_competitor.gd + 유닛 테스트 (S2-03)
- [x] 시즌/대회 관리 시스템 구현 완료 — season_manager.gd + 유닛 테스트 (S2-04)
- [x] 리그 승강 로직 구현 및 테스트 통과 (S2-04)
- [x] 기존 테스트 전체 통과 — regression 없음
- [x] TD-01 해결 (기확인, S2-05), TD-02 해결 (S2-06)
- [x] GDD에 정의된 acceptance criteria 전부 충족
- [x] 코드 커밋 완료 (e63806b, 1c739ee 외)

## Sprint 2 → Sprint 3 핸드오프

Sprint 2 완료 시 Sprint 3에서 바로 착수할 수 있어야 하는 것:
- 리더보드 UI (System 16) -- season_manager.gd가 순위 데이터 API 제공
- 스킬 트리 UI (System 17) -- 이미 skill_tree.gd 완료 상태
- End-to-end 플레이 테스트 가능한 상태

## Notes

- Sprint 1에서 비계획 작업이 53% (5.35/10 sessions)를 차지했다. Sprint 2는 기반 시스템이
  안정화되어 비계획 작업이 줄어들 것으로 예상하나, GDD 작성 과정에서 기존 시스템 수정이
  발견될 수 있다 (예: GameClock에 시즌 단위 추가, Portfolio에 시즌 청산 로직).
- 리그 승강제는 V-Slice 원래 범위에 없던 추가 scope이다. Must Have에 포함했지만,
  구현이 지연되면 "리그 없는 단일 대회" 형태로 fallback 가능 (시즌 반복만 유지).
- AI 경쟁자 GDD가 Sprint 전체의 블로커이므로, 스프린트 시작 첫 세션에 착수해야 한다.
