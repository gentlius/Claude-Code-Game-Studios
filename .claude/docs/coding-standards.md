# Coding Standards

- All game code must include doc comments on public APIs
- Every system must have a corresponding architecture decision record in `docs/architecture/`
- Gameplay values must be data-driven (external config), never hardcoded
- All public methods must be unit-testable (dependency injection over singletons)
- Commits must reference the relevant design document or task ID
- **Verification-driven development**: Write tests first when adding gameplay systems.
  For UI changes, verify with screenshots. Compare expected output to actual output
  before marking work complete. Every implementation should have a way to prove it works.

# Code Review Checklist

모든 PR/구현 완료 시 Lead Programmer + QA Lead가 공동 확인. 미통과 항목 있으면 Done 불가.

## 인터페이스 정확성
- [ ] 호출하는 모든 외부 메서드가 해당 파일에 실제로 정의돼 있는가 (Grep으로 확인)
- [ ] 연결하는 시그널의 파라미터 수·타입이 핸들러 시그니처와 일치하는가
- [ ] 새로 참조한 autoload 메서드가 project.godot에 등록된 autoload에 속하는가
- [ ] 구현 범위가 GDD Implementation Checklist의 모든 항목을 커버하는가

## 빌드 검증 (QA Lead 서명 필수)
- [ ] `--export-release` 빌드 성공 (ERROR 없음)
- [ ] 바이너리 실행 후 5초 이상 프로세스 생존
- [ ] 실행 로그에 SCRIPT ERROR 없음

## 테스트
- [ ] 해당 시스템의 API 계약 테스트가 `tests/unit/test_api_contracts.gd`에 추가됐는가
- [ ] 새 public 메서드에 대응하는 유닛 테스트가 존재하는가
- [ ] 기존 테스트 전부 통과하는가

---

# Design Document Standards

- All design docs use Markdown
- Each mechanic has a dedicated document in `design/gdd/`
- Documents must include these **9 required sections** (8 기존 + 1 신규):
  1. **Overview** -- one-paragraph summary
  2. **Player Fantasy** -- intended feeling and experience
  3. **Detailed Design** (or **Detailed Rules**) -- unambiguous mechanics
  4. **Formulas** -- all math defined with variables
  5. **Edge Cases** -- unusual situations handled
  6. **Dependencies** -- other systems listed
  7. **Tuning Knobs** -- configurable values identified
  8. **Acceptance Criteria** -- testable success conditions
  9. **Implementation Checklist** -- Approved 전 필수 (아래 형식)
- Balance values must link to their source formula or rationale

## Implementation Checklist 형식

```markdown
## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
- 이 기능은 어디서 호출되는가: `[파일].[함수]()` → `[이 시스템].[함수]()`

### 호출 경로
- [ ] UI 이벤트/버튼 → 시스템 순서 명시
- [ ] 의존하는 외부 메서드 전부 열거 + 존재 확인

### AC → 테스트 매핑
| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_X.gd` | `test_Y()` |

### 빌드 검증
- [ ] 바이너리 실행 확인: QA Lead 서명 _______
```
