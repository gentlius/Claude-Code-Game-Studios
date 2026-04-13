# ADR-012: GameClock 일시정지 참조 카운팅 패턴

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-04-04 |
| **Decision Maker** | user + lead-programmer |
| **Sprint** | Sprint 3 (S3-02) |
| **Relates To** | src/core/game_clock.gd, src/ui/trading_screen.gd, ADR-001 |

## Context

V-Slice에서 MainScreen에 F1/F2/F3 탭이 추가됐다. 장 중 플레이어가 F2(리그)나
F3(성장) 탭으로 이동하면 가격 갱신이 멈춰야 한다. 여러 곳에서 동시에 일시정지를
요청할 수 있는 상황이 발생했다:

- **SkillTreeOverlay**: 스킬 트리 열람 중 일시정지 필요
- **MainScreen 탭 전환**: F2/F3 탭에서 장 중 일시정지 필요
- **향후 확장**: 설정 화면, 튜토리얼, 이벤트 연출 등

기존 `toggle_pause()` (단순 bool 토글)로는 두 소스가 각각 resume을 호출할 때
실제로 멈춰 있어야 할 때 재개되는 버그가 발생한다.

예시:
1. SkillTreeOverlay → `toggle_pause()` → 정지
2. MainScreen 탭 전환 → `toggle_pause()` → 재개 ❌ (아직 스킬트리가 열려 있음)

## Decision

**`pause_request(source_id)` / `pause_release(source_id)` 참조 카운팅 방식**을 채택한다.

### API 계약

```gdscript
## 일시정지 요청. source_id가 이미 요청 중이면 무시.
## source_id: 요청자 식별 문자열 (예: "skill_tree", "f2_tab")
func pause_request(source_id: String) -> void

## 일시정지 해제. 모든 소스가 해제해야 게임 재개.
## source_id가 목록에 없으면 무시.
func pause_release(source_id: String) -> void

## 현재 일시정지 소스 목록 (디버그용)
func get_pause_sources() -> Array[String]
```

### 내부 구현

```gdscript
var _pause_sources: Dictionary = {}  # {source_id: true}

func pause_request(source_id: String) -> void:
    if _pause_sources.has(source_id):
        return
    _pause_sources[source_id] = true
    _apply_pause_state()

func pause_release(source_id: String) -> void:
    if not _pause_sources.has(source_id):
        return
    _pause_sources.erase(source_id)
    _apply_pause_state()

func _apply_pause_state() -> void:
    var should_pause := not _pause_sources.is_empty()
    if _paused == should_pause:
        return
    _paused = should_pause
    on_pause_changed.emit(_paused)
```

### 기존 toggle_pause() 처리

- `toggle_pause()`는 deprecated 마킹. 내부적으로 `"legacy_toggle"` source_id 사용.
- 점진적 마이그레이션: 신규 코드는 모두 `pause_request/release` 사용.
- 기존 테스트 하위 호환 유지.

### source_id 표준값

| 값 | 사용처 |
|----|--------|
| `"skill_tree"` | SkillTreeOverlay 열림/닫힘 |
| `"f2_tab"` | LeagueScreen 진입/이탈 |
| `"f3_tab"` | GrowthScreen 진입/이탈 |
| `"tutorial"` | (향후) 튜토리얼 단계 |
| `"settings"` | (향후) 설정 화면 |

## Alternatives Considered

### A. 단순 bool 토글 (toggle_pause)

- **기각 이유**: 두 소스가 독립적으로 pause/resume하면 교차 해제 시 재개 버그 발생.
  N개 소스 중 하나만 해제해도 재개되는 경쟁 조건 존재.

### B. SceneTree.paused = true

- **기각 이유**: Godot SceneTree 전체 일시정지는 `PROCESS_MODE_ALWAYS`가 아닌
  모든 노드를 멈춤. `_process()`, `_physics_process()`, 시그널 등이 일괄 중단되어
  저장, 오버레이 애니메이션 등 일시정지 중에도 동작해야 하는 시스템까지 멈춤.
  게임 로직만 선택적으로 멈추는 세밀한 제어 불가.

### C. 카운터 (int) 방식

```gdscript
var _pause_count: int = 0
func pause_request(): _pause_count += 1
func pause_release(): _pause_count = max(0, _pause_count - 1)
```

- **기각 이유**: 동일 소스가 `pause_request()`를 실수로 두 번 호출하면 `pause_release()`도
  두 번 호출해야 함 — 누출(leak) 발생 가능. source_id Dictionary는 동일 소스 중복 요청을
  자동으로 멱등(idempotent) 처리하므로 더 안전.

## Consequences

### 긍정적

- 어떤 소스가 일시정지 중인지 `get_pause_sources()`로 추적 가능 (디버그 용이)
- 동일 소스 중복 호출 자동 방어 (멱등성)
- 새 일시정지 소스 추가 시 GameClock 코드 수정 불필요 — source_id만 정의하면 됨

### 부정적

- `pause_request` 호출 후 `pause_release`를 반드시 호출해야 함 (누출 방지 책임)
- 기존 `toggle_pause()` 사용 코드를 점진적으로 마이그레이션해야 함

### 리스크

- **pause_release 누출**: 씬 종료 시 `queue_free()` 호출 전에 `pause_release()` 미호출 시
  source_id가 영구 잔류. 완화: 소스 노드의 `_exit_tree()`에서 `pause_release()` 호출 보장.
- **unknown source_id**: 타이핑 오류로 잘못된 source_id가 영구 잔류.
  완화: 상수화 (`const PAUSE_SOURCE_SKILL_TREE = "skill_tree"`) 권장.

## Validation Criteria

- **AC-01**: SkillTreeOverlay와 F2 탭이 동시에 pause_request 중일 때, 하나만 release해도 게임이 재개되지 않음
- **AC-02**: 두 소스 모두 release 후 게임 재개
- **AC-03**: 동일 source_id로 pause_request 2회 호출 시 pause_release 1회로 해제됨
- **AC-04**: `get_pause_sources()` 반환값이 현재 활성 소스 목록과 일치

## Related Decisions

- [ADR-001](001-system-communication-pattern.md) — on_pause_changed 시그널 발행 (이벤트 알림)
- [ADR-006](006-tab-scene-ownership.md) — F2/F3 탭 전환이 pause_request/release 호출 주체
- Sprint 3 S3-02, Sprint 3 S3-13 (TD-03 시그널화)
