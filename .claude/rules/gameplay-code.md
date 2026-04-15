---
paths:
  - "src/gameplay/**"
---

# Gameplay Code Rules

- ALL gameplay values MUST come from external config/data files, NEVER hardcoded
- Use delta time for ALL time-dependent calculations (frame-rate independence)
- NO direct references to UI code — use events/signals for cross-system communication
- Every gameplay system must implement a clear interface
- State machines must have explicit transition tables with documented states
- Write unit tests for all gameplay logic — separate logic from presentation
- Document which design doc each feature implements in code comments
- No static singletons for game state — use dependency injection

## 상태 소유권 (State Ownership)

모든 상태는 단일 소유자를 가진다. 동일한 사실을 두 곳에서 추적하면 하나를 제거하고 소유자에게서 읽는다.

상태를 다른 소스로 교체하기 전, 대체 소스가 시스템의 **모든 가능한 상태(상태머신의 각 노드, 세이브/로드 직후 포함)**에서 동일한 의미를 반환함을 코드 수정 전에 증명한다. 증명 불가 시 교체하지 않는다.

## 리팩터링 사전 승인

여러 파일에 걸친 구조적 변경(변수 제거, 소유권 이전, 인터페이스 변경)은 Edit 툴 사용 전에 다음을 텍스트로 제시하고 승인을 받는다:
1. 제거/이전하는 상태의 현재 의미
2. 대체 소스의 의미와 동치 증명
3. 수정 대상 파일 목록

## 표시 포맷 단일 소유 (Display Format Ownership)

플레이어에게 노출되는 표시 포맷(종목명, 날짜, 금액 등)은 반드시 단일 메서드/상수에서 생성한다. 동일한 포맷 문자열을 여러 파일에 복사하지 않는다. 새 포맷이 필요하면 해당 데이터 클래스 또는 포맷 유틸에 추가하고 모든 호출자가 그 메서드를 참조한다.

## 상수 기반 동적 문자열 (Constant-Driven Strings)

튜닝 상수(딜레이 틱 수, 배율, 임계값 등)가 포함된 플레이어 노출 문자열은 상수값을 직접 참조하여 런타임에 생성한다.

```gdscript
# 올바름
"뉴스 딜레이 %d분" % NEWS_DELAY_MIN
# 틀림 — 상수 변경 시 문자열이 자동으로 틀려진다
"뉴스 딜레이 5분"
```

## API Contracts 즉시 등록

public 메서드를 추가하는 순간 `tests/unit/test_api_contracts.gd`를 같은 편집 세션에서 업데이트한다. "나중에 체크리스트에서 확인"은 무조건 빠뜨린다. **코드 수정 → API contracts 등록 → 커밋은 하나의 원자적 행동이다.**

이 파일을 편집하기 전에 반드시:
1. 수정 대상 파일을 읽어 현재 public 메서드 목록을 파악한다
2. `tests/unit/test_api_contracts.gd`를 읽어 어떤 메서드가 이미 등록됐는지 확인한다

## Examples

**Correct** (data-driven):

```gdscript
var damage: float = config.get_value("combat", "base_damage", 10.0)
var speed: float = stats_resource.movement_speed * delta
```

**Incorrect** (hardcoded):

```gdscript
var damage: float = 25.0   # VIOLATION: hardcoded gameplay value
var speed: float = 5.0      # VIOLATION: not from config, not using delta
```
