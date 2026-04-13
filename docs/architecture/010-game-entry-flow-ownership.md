# ADR-010: 게임 진입 흐름 소유권 (GameMain)

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-04-07 |
| **Decision Maker** | user + technical-director |
| **Relates To** | design/gdd/start-screen.md, src/ui/game_main.gd |

## Context

Alpha 마일스톤에서 게임 진입 흐름이 재설계됐다.
기존: 단일 저장 파일 로딩 → 바로 MainScreen
신규: SplashScreen → StartScreen(슬롯 선택) → IntroSequence(새 게임만) → MainScreen

설계 결정이 필요한 질문:
1. 화면 전환 로직을 어느 노드가 소유하는가?
2. SavingOverlay(저장 중 UI)는 언제 생성되고 누가 소유하는가?
3. F4 나가기(MainScreen → StartScreen)의 신호 흐름은?

## Decision

**GameMain이 모든 최상위 화면 전환을 소유**한다.

### 씬 소유 계층

```
GameMain (Node — autoload 아님, 씬 루트)
├── SavingOverlay (CanvasLayer, layer=10)  ← GameMain._ready()에서 생성, 평생 유지
│
├── [전환 화면들 — 한 번에 하나만 존재]
│   SplashScreen     →  StartScreen     →  MainScreen
│   (2초 후 자동)       (슬롯 선택)         (F1/F2/F3 탭)
│
└── [새 게임 전용]
    IntroSequence  (StartScreen → MainScreen 사이에 삽입)
```

### 화면 전환 흐름

```
_ready()
  └─ SavingOverlay 생성 (평생 유지)
  └─ _show_splash()

SplashScreen.splash_finished
  └─ _on_splash_finished() → _show_start_screen()

StartScreen.slot_selected(id)
  └─ _on_slot_selected(id)
     SaveSystem.load_slot(id) → _load_main_screen()

StartScreen.new_game_confirmed(slot_id)
  └─ _on_new_game_confirmed(slot_id)
     CurrencySystem.init_first_season()
     PortfolioManager.update_valuation()
     IntroSequence → intro_finished → _on_intro_finished() → _load_main_screen()

MainScreen.exit_to_start_requested
  └─ _on_exit_to_start_requested()
     _main_screen.queue_free() → _show_start_screen()
```

### F4 나가기 신호 경로

```
[키보드 F4 또는 탭바 F4 버튼]
  └─ MainScreen._request_exit_to_start()
       SaveSystem._save_pending 체크 → 저장 중이면 무반응
       exit_to_start_requested.emit()
  └─ GameMain._on_exit_to_start_requested()
       _main_screen.queue_free()
       _show_start_screen()
```

F4 버튼은 MainScreen 탭 바(F1/F2/F3 옆)에 위치. 씬 전환 버튼이지 탭이 아님.

### 초기 저장 타이밍

새 게임 생성 시, `_load_main_screen()` 완료 후 첫 저장:
```gdscript
var _pending_initial_save: bool = false
# new_game_confirmed 시 _pending_initial_save = true 설정
# _load_main_screen()에서: if _pending_initial_save → SaveSystem.save_slot()
```
GameClock 및 모든 시스템 초기화 완료 후 저장 → race condition 방지.

## Alternatives Considered

### A. 각 화면이 다음 화면을 직접 생성

SplashScreen이 StartScreen을 생성하고, StartScreen이 MainScreen을 생성.

- **기각 이유**: 화면 간 결합도 증가. SplashScreen이 StartScreen을 알아야 함.
  F4 나가기(MainScreen → StartScreen) 구현 시 역방향 참조 필요. 순환 의존성 위험.

### B. SceneTree.change_scene_to_file() 사용

Godot 내장 씬 전환 API로 SplashScreen.tscn → StartScreen.tscn → MainScreen.tscn 전환.

- **기각 이유**: SavingOverlay가 씬 전환 시마다 소멸/재생성됨.
  저장 중 씬 전환 발생 시 오버레이 소실 위험. GameMain이 지속 유지하는 방식이 안전.

### C. GameMain을 autoload로 등록

- **기각 이유**: autoload는 항상 씬 트리 최상위에 존재하여 씬 전환과 독립적으로 동작.
  GameMain은 씬 루트 노드로서 씬 트리에 명시적으로 존재해야 SavingOverlay 등
  자식 노드 계층 관리가 직관적. autoload 남발 방지 (ADR-001 원칙).

## Consequences

### 긍정적

- 화면 전환 로직이 GameMain 한 곳에서만 관리됨 (단일 책임)
- SavingOverlay가 모든 화면 전환에서 살아있어 저장 중 상태가 유지됨
- F4 신호 경로가 명확: MainScreen → GameMain (단방향, 역참조 없음)

### 부정적

- GameMain의 `_show_*` 메서드가 화면 수만큼 증가
- 새 화면 추가 시 GameMain 수정 필수

### 리스크

- **새 게임 race condition**: 초기 저장이 너무 이르면 미초기화 데이터 저장.
  완화: `_pending_initial_save` 플래그로 `_load_main_screen()` 완료 후 저장.

## Validation Criteria

- **AC-01**: SplashScreen(2초) → StartScreen → 슬롯 선택 → MainScreen 전환 오류 없음
- **AC-02**: 새 게임 → IntroSequence 5장 → MainScreen → 초기 저장 완료
- **AC-03**: F4 → StartScreen 복귀. SavingOverlay 재생성 없이 유지됨.
- **AC-04**: 저장 중(SavingOverlay 표시) F4 입력 시 무반응

## Related Decisions

- [ADR-006](006-tab-scene-ownership.md) — MainScreen이 F1/F2/F3 탭 소유 (GameMain과 역할 분리)
- [ADR-009](009-multi-slot-save-architecture.md) — 멀티슬롯 저장 구조
- [ADR-011](011-saving-overlay-canvas-layer.md) — SavingOverlay 구현 방식
- design/gdd/start-screen.md — 진입 흐름 전체 명세
