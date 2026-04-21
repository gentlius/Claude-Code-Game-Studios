---
paths:
  - "design/gdd/**"
---

# Design Document Rules

- Every design document MUST contain these 9 sections: Overview, Player Fantasy, Detailed Design (or Detailed Rules), Formulas, Edge Cases, Dependencies, Tuning Knobs, Acceptance Criteria, Implementation Checklist
- Formulas must include variable definitions, expected value ranges, and example calculations
- Edge cases must explicitly state what happens, not just "handle gracefully"
- Dependencies must be bidirectional — if system A depends on B, B's doc must mention A
- Tuning knobs must specify safe ranges and what gameplay aspect they affect
- Acceptance criteria must be testable — a QA tester must be able to verify pass/fail
- No hand-waving: "the system should feel good" is not a valid specification
- Balance values must link to their source formula or rationale
- Design documents MUST be written incrementally: create skeleton first, then fill
  each section one at a time with user approval between sections. Write each
  approved section to the file immediately to persist decisions and manage context

## Design Review Rules

리뷰는 문서 형식 검증에 그치지 않는다. 아래 항목을 추가로 확인해야 한다.

### 누락 탐지 (What's Missing)
- 시스템 목록(직렬화 대상, 의존성, AC 등)은 "이 목록에 없는 것은 무엇이고, 빠진 이유가 타당한가?"를 반드시 확인한다
- 저장/로드 GDD는 저장하지 않는 시스템도 표에 포함하고 "기본값 · 게임플레이 영향"을 명시해야 한다. 미명시 = 리뷰 차단 사유

### E2E 시나리오 검증
- 저장/로드·결제·시즌 전환 등 상태 변화가 큰 GDD는 "이벤트 발생 → 각 시스템 상태 변화 → 플레이어 경험"을 시스템별로 순서대로 추적하는 AC가 반드시 있어야 한다
- AC가 파일 생성·API 반환값 확인 수준에 그치고 플레이어가 실제로 경험하는 결과를 검증하지 않으면 불완전한 AC로 지적한다

### 익스플로잇 체크 (경제·진행·가격 관련 GDD 필수)
- 돈·가격·XP·랭크를 다루는 GDD는 "이 동작을 반복하거나 비정상적 순서로 실행하면 어떻게 되는가?"를 Edge Cases 또는 별도 항목으로 명시해야 한다
- 리뷰어는 각 저장 필드에 대해 "세이브/로드 반복으로 이 값을 유리하게 조작할 수 있는가?"를 확인한다

### DLC 시장 확장 호환성 체크 (모든 GDD 필수)

새 GDD를 작성하거나 기존 GDD를 수정할 때, 아래 세 가지를 반드시 확인한다.

1. **하드코딩 금지**: 시장별 규칙(섹터 목록, ETF, 수수료율, 캘린더, 임계값 등)이 코드나 GDD에 리터럴로 박혀 있는가? → `MarketProfile.get_*()`으로 위임해야 한다. `if market == "KR"` 분기는 리뷰 차단 사유.

2. **새 파라미터 발생 시**: 이 GDD에서 새로 도입하는 수치(상수, 비율, 주기 등)가 시장마다 달라질 수 있는가? → 달라질 수 있으면 `market_kr.json`에 추가하고 `MarketProfile.get_trading_param()` / `get_calendar_param()`으로 읽는다.

3. **시장 전환 시나리오**: 플레이어가 시즌 시작 시 다른 시장(예: US)을 선택하면 이 시스템이 올바르게 재초기화되는가? 상태가 이전 시장 값을 유지하는 필드가 없는가?

> 근거: ADR-021. FinancialReportSystem·EtfManager 설계 시 DLC 체크를 늦게 수행해
> 전면 재설계가 필요했던 선례가 있다. 설계 초안 단계에서 차단한다.

### 엔딩·업적 변경 프로토콜 (endings-achievements.md 한정)

- 새 엔딩·업적 아이디어는 반드시 `endings-achievements.md §9 Candidate Pool`에 먼저 등록한다.
- **§3-4 업적 표 또는 §3-1~3-3 엔딩 섹션에 올라간 항목 = 구현 의무 발생.** 미확정 상태로 올리는 것은 금지.
- 승격 절차: Candidate Pool → game-designer 승인 → §3 이동 + §9 체크리스트 추가 + Candidate Pool 항목 제거.
- 이미 Steam에 등록된 업적은 삭제 불가 (Steam 정책). 조건 변경만 허용.

### 리뷰 제외 대상
- `design/gdd/archive/` — Superseded 문서 보관소. 디자인 리뷰 대상에서 제외한다.
  현행 시스템 문서가 아니므로 누락·불일치 지적 불가. 이동 이력은 해당 폴더의 README 또는 대체 문서에 기록한다.
