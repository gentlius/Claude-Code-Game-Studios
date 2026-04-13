# ADR-014: MainScreen 탭 씬 생명주기 — visibility 토글 상주 방식

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-04-04 |
| **Decision Maker** | user + lead-programmer |
| **Sprint** | Sprint 3 (S3-04) |
| **Relates To** | src/ui/main_screen.gd, ADR-006 |

## Context

ADR-006은 MainScreen이 F1/F2/F3 탭을 소유한다고 결정했다.
남은 질문: 세 탭 씬(TradingScreen, LeagueScreen, GrowthScreen)을
**언제 생성/소멸**시키고, **어떻게 표시/숨김**하는가?

선택지:
- **A** — `_ready()`에서 3개 전부 생성, 이후 visibility 토글만
- **B** — 탭 전환 시 on-demand 생성, 이탈 시 `queue_free()`
- **C** — 첫 진입 시 생성(lazy), 이후 상주

## Decision

**방식 A: `_ready()`에서 3개 전부 생성, visibility 토글로 전환.**

```gdscript
# main_screen.gd
func _ready() -> void:
    _trading_screen = $TradingScreen     # 씬 트리에 미리 배치
    _league_screen  = $LeagueScreen
    _growth_screen  = $GrowthScreen
    _show_tab(Tab.TRADING)               # F1 기본

func _show_tab(tab: Tab) -> void:
    _trading_screen.visible = (tab == Tab.TRADING)
    _league_screen.visible  = (tab == Tab.LEAGUE)
    _growth_screen.visible  = (tab == Tab.GROWTH)
    _handle_pause_for_tab(tab)
```

### 비활성 탭의 _process() 차단

Godot은 `visible = false`인 Control 노드의 `_process()`를 기본적으로 실행한다.
비활성 탭이 틱 연산을 낭비하는 것을 막기 위해:

```gdscript
func _show_tab(tab: Tab) -> void:
    for screen in [_trading_screen, _league_screen, _growth_screen]:
        screen.visible = false
        screen.process_mode = Node.PROCESS_MODE_DISABLED
    var active := _get_screen(tab)
    active.visible = true
    active.process_mode = Node.PROCESS_MODE_INHERIT
```

### 장 중 탭 전환 pause 연동

F2/F3 진입 시 `GameClock.pause_request(source_id)` 호출.
F1 복귀 시 `GameClock.pause_release(source_id)` 호출.
(ADR-012 참조)

## Alternatives Considered

### B. on-demand 생성 + queue_free()

탭 전환 시마다 씬 인스턴스화 → 이탈 시 `queue_free()`.

- **기각 이유**: 탭 전환마다 씬 초기화 비용 발생. LeagueScreen은 `_ready()`에서
  리더보드 데이터를 로드하므로 전환할 때마다 API 호출 반복. 탭 전환이 빈번한
  게임 루프에서 UX 버벅임 유발. 탭 내부 상태(스크롤 위치 등)가 초기화됨.

### C. Lazy 생성 (첫 진입 시 생성, 이후 상주)

처음 F2를 누를 때 LeagueScreen을 생성하고, 이후 visibility 토글.

- **기각 이유**: 첫 탭 전환 시에만 느리고 이후엔 빠른 불균일한 UX 제공.
  방식 A와 메모리 사용량 동일하지만 첫 전환 시 지연만 추가됨. 이득 없음.

## Consequences

### 긍정적

- 탭 전환이 즉각적 (씬 초기화 없음)
- 탭 내부 상태(스크롤 위치, 선택 항목) 탭 전환 후에도 유지
- `process_mode = DISABLED`로 비활성 탭의 CPU 사용 차단

### 부정적

- 3개 씬이 항상 메모리 상주 — 씬이 많아지면 메모리 증가
- `_ready()`에서 3개 씬을 동시 초기화하므로 게임 시작 시 초기 부하 집중

### 리스크

- **메모리 임계치**: 씬이 3개를 초과해 탭이 추가될 경우 재검토 필요.
  현재 3탭은 512MB 메모리 예산 내 여유. (ADR-001 §Performance Budgets 참조)
- **GrowthScreen placeholder**: GrowthScreen이 Beta까지 placeholder인 동안
  불필요한 씬 로드 발생. 완화: placeholder는 최소한의 빈 Control 노드로 구성.

## Validation Criteria

- **AC-01**: F1→F2→F3→F1 탭 전환이 모두 60fps 유지 (버벅임 없음)
- **AC-02**: F2 이탈 후 재진입 시 LeagueScreen 스크롤 위치 유지
- **AC-03**: 비활성 탭의 `_process()`가 실행되지 않음 (Godot 프로파일러 확인)
- **AC-04**: 장 중 F2/F3 전환 시 GameClock 일시정지 확인 (ADR-012)

## Related Decisions

- [ADR-006](006-tab-scene-ownership.md) — MainScreen이 탭 소유 (소유권)
- [ADR-012](012-gameclock-pause-reference-counting.md) — 탭 전환 시 pause_request/release
- Sprint 3 S3-04
