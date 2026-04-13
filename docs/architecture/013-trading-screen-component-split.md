# ADR-013: TradingScreen 5-컴포넌트 분리 구조 (TD-04)

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-04-06 |
| **Decision Maker** | user + lead-programmer |
| **Sprint** | Sprint 4 (S4-01) |
| **Relates To** | src/ui/trading_screen.gd, src/ui/components/, ADR-006 |

## Context

`trading_screen.gd`가 God Object로 성장하여 단일 파일이 주식 목록 렌더링, 상태바 HUD,
주문 패널, 시즌 정산 리포트, 토스트 알림을 모두 처리했다. 이 구조의 문제:

- **성능**: 틱마다 모든 행을 재렌더링. 변경이 없어도 StyleBox 재생성.
- **가독성**: 메서드가 40줄을 초과하고 책임이 혼재. 변경 시 예상치 못한 부작용.
- **확장성**: 새 UI 요소 추가 시 파일이 계속 비대해짐.
- **테스트 가능성**: 단일 파일 내 의존성이 복잡해 유닛 테스트 어려움.

## Decision

**TradingScreen을 5개 독립 컴포넌트로 분리**하며, TradingScreen은 컴포넌트 간
시그널 라우팅과 초기화만 담당하는 Facade로 남는다.

### 컴포넌트 구조

```
src/ui/
├── trading_screen.gd          ← Facade (시그널 라우팅, 초기화)
└── components/
    ├── stock_list_panel.gd    ← 주식 목록 행 렌더링 + dirty flag
    ├── status_bar.gd          ← 상단 HUD (자산/수익률/순위/시즌)
    ├── order_panel.gd         ← 매수/매도 패널 + 수량 입력
    ├── settlement_reporter.gd ← 시즌 정산 결과 팝업 큐
    └── toast_manager.gd       ← 토스트 알림 큐 + 애니메이션
```

### 컴포넌트별 책임

| 컴포넌트 | 책임 | 주요 최적화 |
|---------|------|------------|
| `StockListPanel` | 종목 행 목록 렌더링 | `_row_nodes` Dict 캐시 + dirty flag |
| `StatusBar` | 상단 자산·순위 HUD | 4틱마다 갱신 (GameClock on_tick 구독) |
| `OrderPanel` | 주문 수량/금액 입력 및 제출 | 선택 종목 변경 시에만 재구성 |
| `SettlementReporter` | 시즌 종료 정산 팝업 | 큐 기반 순차 표시 (race condition 방지) |
| `ToastManager` | 하단 토스트 알림 | Tween 풀링, reduced_motion 지원 |

### StockListPanel dirty flag 패턴

```gdscript
# stock_list_panel.gd
var _dirty_rows: Dictionary = {}   # {stock_id: true}
var _row_nodes: Dictionary = {}    # {stock_id: HBoxContainer}
var _style_cache: Dictionary = {}  # {color_key: StyleBoxFlat}

func mark_dirty(stock_id: String) -> void:
    _dirty_rows[stock_id] = true

func _process(_delta: float) -> void:
    if _dirty_rows.is_empty():
        return
    for stock_id in _dirty_rows:
        _update_row(stock_id)
    _dirty_rows.clear()
```

PriceEngine의 `price_updated(stock_id, price)` 시그널 → `mark_dirty(stock_id)`.
변경된 행만 다음 프레임에 업데이트. 변경 없는 행은 `_process()`가 스킵.

### 40줄 메서드 규칙

모든 컴포넌트의 public/private 메서드는 40줄을 초과할 수 없다.
초과 시 하위 private 메서드로 분리.

### TradingScreen Facade 역할

```gdscript
# trading_screen.gd
func _ready() -> void:
    _stock_list_panel = $StockListPanel
    _status_bar = $StatusBar
    _order_panel = $OrderPanel
    _settlement_reporter = $SettlementReporter
    _toast_manager = $ToastManager
    _connect_signals()

func _connect_signals() -> void:
    # 시그널 라우팅만 담당
    PriceEngine.price_updated.connect(_stock_list_panel.mark_dirty)
    _order_panel.order_submitted.connect(_on_order_submitted)
    SeasonManager.season_ended.connect(_settlement_reporter.enqueue_report)
    # ...
```

## Alternatives Considered

### A. God Object 유지 + 최적화만

`trading_screen.gd`를 분리하지 않고 dirty flag와 캐시만 추가.

- **기각 이유**: 책임 혼재 문제 미해결. 메서드 길이 제한 강제 불가. 이후 기능 추가 시
  계속 비대해짐. 테스트 용이성 개선 불가.

### B. Godot 씬 트리로 완전 분리 (각 컴포넌트를 별도 .tscn으로)

각 컴포넌트를 독립 씬으로 만들어 인스턴스화.

- **기각 이유**: 이 컴포넌트들은 TradingScreen에서만 사용되는 전용 UI 요소.
  씬으로 분리하면 씬 참조 관리, 에디터 연결 설정이 추가로 필요해 복잡성 증가.
  GDScript 파일 분리로 충분한 캡슐화 달성 가능.

### C. 플러그인/Addon 구조

UI 컴포넌트를 독립 플러그인으로 구성.

- **기각 이유**: 게임 내부 전용 UI에 플러그인 구조는 과도한 추상화.
  Godot 플러그인은 재배포 가능한 도구 제작에 적합. 이 규모에서 YAGNI.

## Consequences

### 긍정적

- 틱당 StyleBox 재생성 제거 → dirty flag로 변경 행만 업데이트
- 각 컴포넌트가 독립적으로 유닛 테스트 가능
- 40줄 메서드 규칙이 코드 리뷰에서 기계적으로 검증 가능
- 새 UI 기능은 적절한 컴포넌트에만 추가 — TradingScreen 비대화 방지

### 부정적

- 컴포넌트 간 시그널 연결이 TradingScreen Facade에 집중 — `_connect_signals()` 관리 필요
- 새 컴포넌트 추가 시 Facade에 초기화 코드 추가 필수

### 리스크

- **SettlementReporter 정산 큐 race condition**: 시즌 종료 직후 저장이 완료되기 전에
  팝업이 표시되면 미저장 상태에서 결과 노출. (TD-AUDIT-01 등록됨)
  완화: `SaveSystem.save_completed` 시그널 후 팝업 표시.
- **컴포넌트 초기화 순서**: `_ready()`에서 컴포넌트 참조를 할당하기 전에
  시그널 핸들러가 호출되면 null 참조. 완화: `call_deferred()` 또는 순서 보장.

## Validation Criteria

- **AC-01**: 틱당 `stock_list_panel._draw()` 프레임 할당이 변경 행에만 발생 (프로파일러 확인)
- **AC-02**: 모든 컴포넌트 파일의 public/private 메서드가 40줄 이하
- **AC-03**: 기존 테스트 192/192 전부 통과 (분리 전 동일 동작 보장)
- **AC-04**: `trading_screen.gd`가 직접 행 렌더링 로직을 포함하지 않음 (코드 리뷰)

## Related Decisions

- [ADR-001](001-system-communication-pattern.md) — 컴포넌트 간 시그널 라우팅 패턴
- [ADR-006](006-tab-scene-ownership.md) — TradingScreen(F1)이 MainScreen의 탭 중 하나
- Sprint 4 S4-01, tech-debt.md TD-04 (Resolved)
- production/tech-debt.md TD-AUDIT-01 — SettlementReporter race condition (미해결)
