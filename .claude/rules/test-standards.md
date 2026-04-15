---
paths:
  - "tests/**"
---

# Test Standards

- Test naming: `test_[system]_[scenario]_[expected_result]` pattern
- Every test must have a clear arrange/act/assert structure
- Unit tests must not depend on external state (filesystem, network, database)
- Integration tests must clean up after themselves
- Performance tests must specify acceptable thresholds and fail if exceeded
- Test data must be defined in the test or in dedicated fixtures, never shared mutable state
- Mock external dependencies — tests should be fast and deterministic
- Every bug fix must have a regression test that would have caught the original bug

## 테스트 작성 전 필수 확인 (이 프로젝트 규칙)

테스트 파일을 작성하기 전에 반드시:
1. **수정 대상 소스 파일을 읽는다** — 존재하는 public 메서드 목록을 직접 확인한다. 상상으로 함수명을 쓰지 않는다.
2. **`tests/unit/test_api_contracts.gd`를 읽는다** — 이미 등록된 메서드가 무엇인지 확인한다.

`has_method("X")`로 테스트하는 메서드 X가 실제로 `src/`에 존재하는지 커밋 전 체크된다. 없으면 커밋이 차단된다.

## 테스트 수정 방향 (Test Fix Direction)

테스트가 실패할 때 **절대 테스트에 프로덕션 코드를 맞추지 않는다.** 올바른 판단 순서:
1. GDD를 확인한다
2. 코드가 GDD와 일치하는가?
   - 일치하면 → **테스트를 수정**한다
   - 불일치하면 → **코드를 수정**한다

"테스트가 빨간불이니까 코드를 고쳐서 초록 만든다"는 GDD를 파괴하는 행위다.

## API Contracts 즉시 등록

public 메서드를 추가하는 순간 `tests/unit/test_api_contracts.gd`를 **같은 커밋**에서 업데이트한다.

## 코드·GDD 변경 시 테스트 동시 갱신

GDD 또는 프로덕션 코드를 변경할 때 해당 변경을 검증하는 테스트를 **같은 커밋에서** 갱신한다. 별도 커밋으로 미루면 테스트가 stale 상태로 남아 다음 세션에서 방향 판단 오류를 유발한다.

## Examples

**Correct** (proper naming + Arrange/Act/Assert):

```gdscript
func test_health_system_take_damage_reduces_health() -> void:
    # Arrange
    var health := HealthComponent.new()
    health.max_health = 100
    health.current_health = 100

    # Act
    health.take_damage(25)

    # Assert
    assert_eq(health.current_health, 75)
```

**Incorrect**:

```gdscript
func test1() -> void:  # VIOLATION: no descriptive name
    var h := HealthComponent.new()
    h.take_damage(25)  # VIOLATION: no arrange step, no clear assert
    assert_true(h.current_health < 100)  # VIOLATION: imprecise assertion
```
