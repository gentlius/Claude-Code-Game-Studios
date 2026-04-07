---
paths:
  - "design/gdd/**"
---

# Design Document Rules

- Every design document MUST contain these 8 sections: Overview, Player Fantasy, Detailed Design (or Detailed Rules), Formulas, Edge Cases, Dependencies, Tuning Knobs, Acceptance Criteria
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
