# Sprint 4 — 2026-04-05 to 2026-04-06

## Sprint Goal

TD-04 trading_screen.gd God Object를 5개 서브컴포넌트로 구조적으로 분리하여
UI 버벅임을 근본 해결하고, V-Slice System 17 E2E 검증으로 V-Slice 마일스톤을 닫는다.

## Capacity

- Total sessions: 10
- Buffer (20%): 2 sessions
- Available: 8 sessions
- Sprint 3 velocity: Must Have 7건 + Should Have 5건 완료 (buffer 초과 소화)

## Tasks

### Must Have (Critical Path)

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S4-01 | TD-04: trading_screen.gd God Object 분리 | lead-programmer | 4 | GDD trading-screen.md §10 승인 | StockListPanel/StatusBar/OrderPanel/SettlementReporter/ToastManager 5개 파일 분리. 40줄 메서드 제한 준수. `_row_nodes` 캐시·dirty flag·StyleBox 캐시 구현. 기존 테스트 전부 통과. `--export-release` 빌드 성공 |
| S4-02 | V-Slice System 17: progression-ui AC 전체 E2E 검증 | qa-lead | 1 | S4-01 | progression-ui.md AC-1~AC-10 전부 Pass. v-slice.md Success Criteria 5개 항목 전부 체크. QA Lead 서명 |

### Should Have

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S4-03 | S3-10 성능 프로파일링 | lead-programmer | 0.5 | S4-01 | Godot 프로파일러로 E2E 플레이 중 측정. 결과를 `docs/profiling/v-slice-baseline.md`에 기록. 16.6ms 초과 함수 목록화 |
| S4-04 | 차트 RSI/MACD 캐싱 | lead-programmer | 1 | S4-03 | 프로파일링 수치 확인 후 처리. 배열 per-frame 재할당 제거. 캐시 무효화 조건 명시 |
| S4-05 | 스킬트리 하드코딩 → 데이터 파일 | gameplay-programmer | 1 | S4-01 | `assets/data/skill_tree.json` 14개 스킬 정의. `SkillTree` autoload JSON 로드. 하드코딩 상수 제거. 기존 테스트 전부 통과 |

### Nice to Have

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S4-06 | TD-06: 게임패드 입력 지원 | ui-programmer | 1 | S4-01 | `InputMap`에 게임패드 액션 등록. 매매/탭 전환/스킬트리 전 액션 커버 |

## Capacity Check

| Category | Sessions |
|----------|----------|
| Available (buffer 제외) | 8 |
| Must Have | 5 |
| Should Have | 2.5 |
| Nice to Have | 1.0 |
| **합계** | **8.5** |
| **여유** | **−0.5 → buffer 2 sessions이 흡수** |

## Critical Path

```
Day 1-4:  S4-01 (TD-04 분리, 하위 순서: StockListPanel → StatusBar → OrderPanel → SettlementReporter → ToastManager → TradingScreen 리팩터)
Day 4-5:  S4-02 (V-Slice E2E 검증, S4-01 완료 후)
          S4-03 (프로파일링, S4-01 완료 후 병행 가능) → S4-04 (RSI/MACD 캐싱)
Day 6+:   S4-05 (스킬트리 데이터 파일)
          S4-06 (게임패드, 여유 있을 때)
```

**분리 순서 원칙**: 독립성 높은 컴포넌트부터 — ToastManager(가장 단순) → StockListPanel → StatusBar → OrderPanel → SettlementReporter(가장 복잡). 각 분리 후 테스트 통과 확인 후 다음 진행.

## Carryover from Sprint 3

| Task | Reason | New Estimate |
|------|--------|-------------|
| S3-10 성능 프로파일링 | Sprint 3 Nice-to-Have 미착수 | S4-03 (0.5 sessions) |

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| TD-04 분리 중 UIState 시그널 연결 끊김 | High | High | 컴포넌트 하나씩 분리 후 테스트. TradingScreen 시그널 라우팅 마지막에 정리 |
| SettlementReporter 정산 큐 로직 복잡도 예상 초과 | Medium | Medium | SettlementReporter는 마지막에 분리. 4 sessions 초과 시 SettlementReporter만 Sprint 5 이관 |
| S4-02 E2E 검증에서 progression-ui AC 실패 | Medium | Medium | AC별 추적. 실패 항목은 S4-01 완료 직후 즉시 수정 |

## Definition of Done for this Sprint

- [x] S4-01~S4-02 Must Have 전부 완료
- [x] v-slice.md Status: **Closed**, Success Criteria 5개 전부 체크
- [x] progression-ui.md AC-1~AC-10 전부 Pass (QA Lead 서명)
- [x] `trading_screen.gd` 포함 모든 UI 파일 40줄 메서드 제한 위반 없음
- [x] StockListPanel dirty flag: 프로파일러에서 틱당 skip 행 확인
- [x] 기존 테스트 전부 통과 (192/192 ✅)
- [x] `--export-release` 빌드 성공 + SCRIPT ERROR 없음 (109.5MB, Apr 6)
- [x] 코드 커밋 완료, main 브랜치 green
