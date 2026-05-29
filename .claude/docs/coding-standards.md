# Coding Standards

- **문서 수명주기 (Document Lifecycle)**: 새 문서를 작성하면 반드시 그 세션 안에 아래 인덱스 중 하나에 등록한다.
  등록되지 않은 문서는 다음 세션에서 존재를 알 수 없으므로 작성과 동시에 폐기된 것과 같다.
  | 문서 유형 | 인덱스 |
  |---------|--------|
  | GDD (`design/gdd/*.md`) | `design/gdd/systems-index.md` |
  | ADR (`docs/architecture/*.md`) | `.claude/docs/technical-preferences.md` Architecture Decisions Log |
  | 프로덕션 (`production/*.md`) | `production/milestones/beta.md` 또는 해당 스프린트 파일 |
  | 디자인 보조 (`design/*.md`) | `design/gdd/systems-index.md` §Non-GDD Design Documents |
  | 에셋 가이드 (`assets/**/*.md`) | 해당 파일 헤더에 참조 문서 명시 |
  | 스튜디오 거버넌스 (`.claude/docs/studio-*.md`) | `CLAUDE.md`에서 `@.claude/docs/...` 직접 참조 |
  | 승격 제안서 (`docs/studio-promotion-proposal-*.md`) | 머지 후 템플릿 `CHANGELOG.md`에 기록, ledger 갱신 |
  참조 루틴이 없는 문서(어떤 인덱스에도 없고, 어떤 활성 문서도 링크하지 않는 문서)는 폐기한다.

- All game code must include doc comments on public APIs
- Every system must have a corresponding architecture decision record in `docs/architecture/`
- Gameplay values must be data-driven (external config), never hardcoded
- All public methods must be unit-testable (dependency injection over singletons)
- Commits must reference the relevant design document or task ID
- **Commit messages**: Use Conventional Commits format — `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`. Reference the story or task ID in the body (e.g., `Story: EPIC-001-S02`).
- **Verification-driven development**: Write tests first when adding gameplay systems.
  For UI changes, verify with screenshots. Compare expected output to actual output
  before marking work complete. Every implementation should have a way to prove it works.
- **상태 소유권 (State Ownership)**: 모든 상태는 단일 소유자를 가진다. 동일한 사실을 두 곳에서 추적하면
  하나를 제거하고 소유자에게서 읽는다. 상태를 다른 소스로 교체하기 전, 대체 소스가 시스템의
  **모든 가능한 상태(상태머신의 각 노드, 세이브/로드 직후 포함)**에서 동일한 의미를 반환함을
  코드 수정 전에 증명한다. 증명 불가 시 교체하지 않는다.
- **리팩터링 사전 승인**: 여러 파일에 걸친 구조적 변경(변수 제거, 소유권 이전, 인터페이스 변경)은
  Edit 툴 사용 전에 다음을 텍스트로 제시하고 승인을 받는다:
  (1) 제거/이전하는 상태의 현재 의미, (2) 대체 소스의 의미와 동치 증명, (3) 수정 대상 파일 목록,
  (4) **호출자 grep 결과** (호출 위치 수 + 어느 시스템에 분포),
  (5) **test 영향 범위** (영향받는 test 수),
  (6) **임계치 초과 시 phase 분할 계획**: 호출자 ≥5 또는 test ≥10 → 단일 PR 금지,
  phase 분할 + 각 phase 독립 검증 가능하게 설계.
- **표시 포맷 단일 소유 (Display Format Ownership)**: 플레이어에게 노출되는 표시 포맷(종목명, 날짜,
  금액 등)은 반드시 단일 메서드/상수에서 생성한다. 동일한 포맷 문자열을 여러 파일에 복사하지 않는다.
  새 포맷이 필요하면 해당 데이터 클래스(예: `StockData.get_display_name()`) 또는 포맷 유틸에 추가하고
  모든 호출자가 그 메서드를 참조한다. 포맷 변경 시 한 곳만 수정하면 모든 UI에 반영되어야 한다.
- **상수 기반 동적 문자열 (Constant-Driven Strings)**: 튜닝 상수(딜레이 틱 수, 배율, 임계값 등)가
  포함된 플레이어 노출 문자열은 상수값을 직접 참조하여 런타임에 생성한다. 상수를 문자열에
  하드코딩하면 상수 변경 시 문자열이 자동으로 틀려진다. 예: `"뉴스 딜레이 %d분" % NEWS_DELAY_MIN`
  (O) vs `"뉴스 딜레이 5분"` (X).
- **테스트 수정 방향 (Test Fix Direction)**: 테스트가 실패할 때 **절대 테스트에 프로덕션 코드를 맞추지 않는다.**
  올바른 순서: GDD → 코드 → 테스트. 테스트 실패 시 반드시 다음 순서로 판단한다:
  (1) GDD를 확인한다. (2) 코드가 GDD와 일치하는가? 일치하면 → **테스트를 수정**한다.
  불일치하면 → **코드를 수정**한다. "테스트가 빨간불이니까 코드를 고쳐서 초록 만든다"는
  GDD를 파괴하는 행위다. 테스트는 스펙의 증거이지 스펙 자체가 아니다.
- **코드·GDD 변경 시 테스트 동시 갱신**: GDD 또는 프로덕션 코드를 변경할 때 해당 변경을 검증하는
  테스트를 **같은 커밋에서** 갱신한다. 별도 커밋으로 미루면 테스트가 stale 상태로 남아 다음 세션에서
  방향 판단 오류를 유발한다. "accumulated changes" 방식의 몰아치기 커밋은 이 규칙을 사실상 불가능하게
  만드므로 금지한다.

# Code Review Checklist

모든 PR/구현 완료 시 Lead Programmer + QA Lead가 공동 확인. 미통과 항목 있으면 Done 불가.

## ADR 동기화 (Technical Director 서명 필수 — 미통과 시 Done 불가)
- [ ] 이 구현에서 내린 아키텍처 결정(API 설계, 소유권, 패턴 선택)이 기존 ADR로 커버되는가
- [ ] 커버되지 않는 결정이 있으면 새 ADR을 `docs/architecture/NNN-*.md`로 작성했는가
- [ ] 새 ADR이 `technical-preferences.md` Architecture Decisions Log에 추가됐는가
- [ ] 기존 ADR과 충돌하는 결정이 있으면 해당 ADR의 Status를 Superseded로 갱신했는가

**ADR 작성 기준**: 다음 중 하나라도 해당하면 ADR 필수
- 새 파일/모듈의 소유권 또는 생명주기를 결정할 때
- 두 가지 이상의 구현 방식을 검토하고 하나를 선택할 때
- 향후 개발자가 "왜 이렇게 했지?"라고 물을 것 같은 결정일 때
- 기존 ADR에 정의된 패턴의 예외를 허용할 때

## GDD 동기화 (Lead Programmer 서명 필수 — 미통과 시 Done 불가)
- [ ] 이 구현과 관련된 GDD 파일을 특정했는가
- [ ] 해당 GDD의 Implementation Checklist 항목이 전부 [x] 체크됐는가
- [ ] 해당 GDD의 Status가 구현 완료를 반영하는가 (완료 → Approved, 부분 → In Review + 미완 항목 명시)
- [ ] GDD에 기술된 API / 파일 경로 / 시그널명이 실제 코드와 일치하는가

## 인터페이스 정확성
- [ ] 호출하는 모든 외부 메서드가 해당 파일에 실제로 정의돼 있는가 (Grep으로 확인)
- [ ] 연결하는 시그널의 파라미터 수·타입이 핸들러 시그니처와 일치하는가
- [ ] 새로 참조한 autoload 메서드가 project.godot에 등록된 autoload에 속하는가
- [ ] 구현 범위가 GDD Implementation Checklist의 모든 항목을 커버하는가

## 표시 포맷 / 문자열 중복 (Lead Programmer 확인)
- [ ] 이 PR에서 추가한 플레이어 노출 포맷 문자열(종목명, 금액, 날짜 등)이 이미 다른 파일에
      동일하게 존재하는가? `grep -r "해당패턴" src/`으로 확인. 중복 발견 시 단일 메서드로 추출하고
      모든 호출자를 교체한다. PR 범위를 벗어나면 tech-debt 등록 후 즉시 수정.
- [ ] 이 PR에서 추가한 플레이어 노출 문자열 안에 튜닝 상수값이 리터럴로 박혀 있는가?
      (예: `"5분 딜레이"`, `"최대 10종목"`, `"±30% 제한"`) → 상수 변경 시 문자열이 자동으로
      따라가야 한다. 리터럴 발견 즉시 반려.

## 빌드 검증 (QA Lead 서명 필수)
- [ ] `--export-release` 빌드 성공 (ERROR 없음)
- [ ] 바이너리 실행 후 5초 이상 프로세스 생존
- [ ] 실행 로그에 SCRIPT ERROR 없음

## 버그 수정 검증 (버그 수정 PR에만 적용)
- [ ] 이 수정은 **증상 억제(guard/patch)**인가, **원인 제거**인가?
      증상 억제인 경우: 왜 근본 수정이 불가능한지 해당 코드에 주석으로 명시
- [ ] 발견한 버그 패턴을 전체 codebase에서 grep해 동일 패턴이 다른 파일에 없는지 확인했는가?
      (버그 1건 발견 → 동일 패턴 전수 검색 → 없으면 ✅, 있으면 함께 수정)

## 방어적 분기 (Lead Programmer 확인)
- [ ] 이 PR의 null/0 가드(`if x != null`, `if x > 0`)가 초기화 시점 sentinel 값으로
      제거 가능한가? 제거 불가 사유가 없으면 초기화 수정.
- [ ] `elif` 체인이 3개 이상 분기를 가지는가?
      Dictionary 디스패치 또는 단일 표현식으로 대체 가능한지 검토.
- [ ] `flag = false` → 여러 `if` 블록에서 `flag = true` 패턴이 있는가?
      단일 불리언 표현식 `flag = (cond_A or cond_B)` 으로 대체.
- [ ] 이 PR에서 추가한 if-else 분기 중 대응하는 유닛 테스트가 없는 분기가 있는가?
      없으면 dead code이거나 미검증 edge case — 둘 다 수정 대상.

## 테스트
- [ ] 해당 시스템의 API 계약 테스트가 `tests/unit/test_api_contracts.gd`에 추가됐는가
- [ ] 새 public 메서드에 대응하는 유닛 테스트가 존재하는가
- [ ] 기존 테스트 전부 통과하는가

> **⚠ API Contracts 즉시 등록 (구현 직후, 별도 단계 없음)**
> public 메서드를 추가하는 순간 `test_api_contracts.gd`를 같은 편집 세션에서 업데이트한다.
> "나중에 체크리스트에서 확인"은 무조건 빠뜨린다. 코드 수정 → API contracts 등록 → 커밋은 하나의 원자적 행동이다.

## 리뷰 제외 대상
- `src/deprecated/` — 폐기 코드 보관소. 코드 리뷰 대상에서 제외한다.
  현행 코드베이스와 무관하므로 스타일·테스트·API 지적 불가. 이동 이력은 tech-debt.md 또는 ADR에 기록한다.

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

---

# Testing Standards

## Test Evidence by Story Type

All stories must have appropriate test evidence before they can be marked Done:

| Story Type | Required Evidence | Location | Gate Level |
|---|---|---|---|
| **Logic** (formulas, AI, state machines) | Automated unit test — must pass | `tests/unit/[system]/` | BLOCKING |
| **Integration** (multi-system) | Integration test OR documented playtest | `tests/integration/[system]/` | BLOCKING |
| **Visual/Feel** (animation, VFX, feel) | Screenshot + lead sign-off | `production/qa/evidence/` | ADVISORY |
| **UI** (menus, HUD, screens) | Manual walkthrough doc OR interaction test | `production/qa/evidence/` | ADVISORY |
| **Config/Data** (balance tuning) | Smoke check pass | `production/qa/smoke-[date].md` | ADVISORY |

## Automated Test Rules

- **Naming**: `[system]_[feature]_test.[ext]` for files; `test_[scenario]_[expected]` for functions
- **Determinism**: Tests must produce the same result every run — no random seeds, no time-dependent assertions
- **Isolation**: Each test sets up and tears down its own state; tests must not depend on execution order
- **No hardcoded data**: Test fixtures use constant files or factory functions, not inline magic numbers
  (exception: boundary value tests where the exact number IS the point)
- **Independence**: Unit tests do not call external APIs, databases, or file I/O — use dependency injection

## What NOT to Automate

- Visual fidelity (shader output, VFX appearance, animation curves)
- "Feel" qualities (input responsiveness, perceived weight, timing)
- Platform-specific rendering (test on target hardware, not headlessly)
- Full gameplay sessions (covered by playtesting, not automation)

## CI/CD Rules

- Automated test suite runs on every push to main and every PR
- No merge if tests fail — tests are a blocking gate in CI
- Never disable or skip failing tests to make CI pass — fix the underlying issue
- Engine-specific CI commands:
  - **Godot**: `godot --headless --script tests/gdunit4_runner.gd`
  - **Unity**: `game-ci/unity-test-runner@v4` (GitHub Actions)
  - **Unreal**: headless runner with `-nullrhi` flag
