# ADR-011: SavingOverlay CanvasLayer 구현 방식

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-04-07 |
| **Decision Maker** | user + technical-director |
| **Relates To** | src/ui/saving_overlay.gd, src/ui/game_main.gd, ADR-010 |

## Context

세이브 시스템이 비동기로 동작(save_started → save_completed 시그널)하는 동안,
플레이어가 다른 버튼을 누르거나 F4로 화면을 전환하는 것을 막아야 한다.

설계 결정이 필요한 질문:
1. 저장 중 입력 차단을 어떻게 구현하는가?
2. SavingOverlay는 어느 노드가 소유하고 언제 생성하는가?
3. CanvasLayer의 레이어 번호는 얼마로 설정하는가?

## Decision

**SavingOverlay를 CanvasLayer(layer=10)로 구현하고, GameMain이 _ready()에서 생성해 평생 유지한다.**

### 구현 명세

```gdscript
# saving_overlay.gd
class_name SavingOverlay
extends CanvasLayer

const LAYER: int = 10

func _ready() -> void:
    layer = LAYER
    # 전체 화면 ColorRect — MOUSE_FILTER_STOP으로 하위 모든 입력 흡수
    var bg := ColorRect.new()
    bg.color = Color(0, 0, 0, 0.5)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(bg)
    visible = false   # 초기에는 숨겨짐

func show_overlay() -> void:
    visible = true

func hide_overlay() -> void:
    visible = false
```

```gdscript
# game_main.gd — _ready() 내
func _ready() -> void:
    _saving_overlay = SavingOverlay.new()
    add_child(_saving_overlay)
    SaveSystem.save_started.connect(_saving_overlay.show_overlay)
    SaveSystem.save_completed.connect(_saving_overlay.hide_overlay)
    _show_splash()
```

### 레이어 번호 10 선택 근거

| 레이어 | 용도 |
|--------|------|
| 0 (기본) | 게임 월드, UI 기본 레이어 |
| 1~4 | 탭 UI, 팝업, 토스트 |
| 5~9 | 예약 (향후 확장) |
| **10** | **SavingOverlay — 모든 UI 위, 디버그 레이어 아래** |
| 128+ | 디버그/개발자 오버레이 |

### 입력 차단 메커니즘

- `MOUSE_FILTER_STOP`: ColorRect가 전체 화면을 덮어 마우스 이벤트를 완전 흡수
- `CanvasLayer.layer=10`: 모든 일반 UI(탭, 팝업, 토스트) 위에 렌더링
- F4 키 차단: `SaveSystem._save_pending` 플래그로 `trading_screen.gd`에서 직접 차단
  (CanvasLayer는 키보드 이벤트를 흡수하지 않으므로 이중 방어 필요)

### 생명주기

```
GameMain._ready()
  └─ SavingOverlay 생성 → add_child() → 평생 유지
     SaveSystem.save_started  → show_overlay()   [visible = true]
     SaveSystem.save_completed → hide_overlay()  [visible = false]

씬 전환(SplashScreen → StartScreen → MainScreen)이 발생해도
SavingOverlay는 GameMain 자식으로 계속 존재.
```

## Alternatives Considered

### A. 각 화면(MainScreen 등)이 자체 SavingOverlay를 소유

각 화면 씬에 SavingOverlay를 포함시켜 화면 전환 시 함께 소멸·재생성.

- **기각 이유**: 화면 전환 중 저장이 진행 중이면 오버레이가 소멸될 수 있음.
  저장 시작 → 씬 전환 → 저장 완료 순서에서 overlay.hide()를 호출할 객체가 없어짐.
  저장과 씬 전환이 겹치는 race condition을 유발.

### B. 저장 중 모든 입력을 SceneTree.paused로 일시정지

`SceneTree.paused = true`로 게임 전체 일시정지 → 저장 완료 후 재개.

- **기각 이유**: Godot에서 `process_mode = PROCESS_MODE_ALWAYS`가 아닌 노드는
  일시정지 시 `_process()` / `_input()` 전부 중단됨. 저장 자체가 비동기 처리되므로
  일시정지 중 signal emit이 정상 동작하지 않을 수 있음.
  또한 `SceneTree.paused`는 게임 로직을 모두 멈추는 강한 부작용을 가짐.

### C. 저장 중 각 버튼을 개별 disabled 처리

모든 UI 버튼의 `disabled` 프로퍼티를 SaveSystem 시그널에 연결해 저장 중 비활성화.

- **기각 이유**: 버튼 목록 관리 부담 (새 버튼 추가 시 연결 누락 가능).
  키보드 단축키, 드래그 등 비버튼 입력은 차단 불가. CanvasLayer 방식이 단일 구현으로 모든 마우스 입력 차단.

## Consequences

### 긍정적

- SavingOverlay가 씬 전환에 무관하게 항상 살아있어 저장 중 상태 유지 보장
- 단일 ColorRect MOUSE_FILTER_STOP으로 전체 마우스 입력 차단 (버튼별 연결 불필요)
- CanvasLayer 특성상 씬 트리 내 어디서든 렌더링 레이어 독립 보장

### 부정적

- F4 키보드 입력은 CanvasLayer가 차단 못함 → `_save_pending` 플래그 이중 방어 필수
- CanvasLayer layer=10 값이 SavingOverlay 전용임을 팀 전체가 숙지해야 함 (다른 UI가 layer≥10 사용 금지)

### 리스크

- **_save_pending 동기화**: `save_started` 시그널 발신 전 `_save_pending = true` 설정,
  `save_completed` 시그널 발신 후 `_save_pending = false` 설정이 SaveSystem에서 보장돼야 함.
  완화: SaveSystem.save_slot() 내에서 `_save_pending` 플래그 → 시그널 순서를 단일 함수에서 관리.

## Validation Criteria

- **AC-01**: 저장 시작 시 반투명 오버레이가 전체 화면을 덮고 모든 버튼 클릭이 무반응
- **AC-02**: 저장 완료 시 오버레이가 사라지고 UI가 정상 반응
- **AC-03**: SplashScreen → StartScreen → MainScreen 전환을 거쳐도 저장 중 오버레이가 유지됨
- **AC-04**: 저장 중 F4 입력 시 MainScreen 씬 전환 없음 (`_save_pending` 플래그 확인)

## Related Decisions

- [ADR-009](009-multi-slot-save-architecture.md) — SaveSystem.save_started / save_completed 시그널 정의
- [ADR-010](010-game-entry-flow-ownership.md) — GameMain이 SavingOverlay 소유 및 씬 전환 제어
- [ADR-006](006-tab-scene-ownership.md) — F4 키 처리가 MainScreen(trading_screen.gd)에 위치
