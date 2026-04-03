# ADR-006: MainScreen이 F1/F2/F3 탭 및 일시정지 단일 진입점 소유

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-04-03 |
| **Decision Maker** | user + technical-director + ux-director |
| **Relates To** | design/gdd/league-ui.md §3-1 |

## Context

게임은 F1(거래), F2(리그/시즌), F3(성장) 세 개의 주요 화면을 탭 방식으로 제공한다.
장 중(`MARKET_OPEN`)에 탭을 전환하면 싱글플레이어 모드에서 일시정지가 필요하다.

씬 구조와 일시정지 제어권을 어떻게 배분할 것인가에 대해 두 가지 이슈가 교차한다:

1. **씬 소유 구조**: 세 화면을 하나의 큰 씬으로 통합할 것인가,
   독립 씬으로 분리하고 부모가 관리할 것인가?

2. **일시정지 소유권**: 탭 전환 외에도 인게임 메뉴, 이벤트 팝업 등
   다양한 UI가 일시정지를 요청할 수 있다. 누가 `GameClock.pause()`를 호출하는가?
   복수 소스가 각자 호출하면, 한 소스가 재개해도 다른 소스가 아직 일시정지 상태인
   경우 시계가 재개되어버리는 충돌이 발생한다.

## Decision

**독립 씬 + MainScreen 부모 패턴**을 채택한다.
탭 전환과 일시정지 호출 모두 `MainScreen`이 **단일 진입점**으로 소유한다.

### 씬 구조

```
MainScreen.tscn                    ← 탭 전환 + 일시정지 소유자
├── TabBar (상단 고정)
├── TradingScreen.tscn             ← F1 독립 씬 인스턴스
├── LeagueScreen.tscn              ← F2 독립 씬 인스턴스
├── GrowthScreen.tscn              ← F3 독립 씬 인스턴스
└── PauseOverlay                   ← 일시정지 배너 (MainScreen 소유)
```

각 탭 씬은 독립적으로 작동하며, 서로를 참조하지 않는다.
autoload(GameClock, PriceEngine 등)는 씬 트리와 무관하게 항상 실행된다.

### 일시정지 소스 ID 패턴

GameClock은 **소스 ID 기반 참조 카운팅** 일시정지 패턴을 지원한다.

```gdscript
## 일시정지 요청. source_id가 중복 호출되어도 1회로 계산.
func pause_request(source_id: String) -> void

## 일시정지 해제. 모든 소스가 해제해야 GameClock이 재개.
func pause_release(source_id: String) -> void
```

예시:

```
탭 전환 (F2 이동):  GameClock.pause_request("tab_switch")
인게임 메뉴 열기:  GameClock.pause_request("menu")

메뉴 닫기:         GameClock.pause_release("menu")
  → "tab_switch" 소스가 남아 있으므로 GameClock 재개 안 됨

F1 복귀:           GameClock.pause_release("tab_switch")
  → 모든 소스 해제 → GameClock 재개
```

### 탭 전환 일시정지 정책

| 상태 | 모드 | 정책 |
|------|------|------|
| MARKET_OPEN + F1 이탈 | 싱글플레이어 | `pause_request("tab_switch")` + PauseOverlay 표시 |
| F1 복귀 | 싱글플레이어 | `pause_release("tab_switch")` + PauseOverlay 숨김 |
| 모든 전환 | 멀티플레이어 | `pause_request` 호출 없이 탭 전환만 |
| PRE_MARKET / MARKET_CLOSED | 모든 모드 | 일시정지 없이 자유 전환 |

탭 전환 일시정지 정책을 결정하는 주체는 항상 MainScreen이다.
TradingScreen, LeagueScreen, GrowthScreen은 일시정지 API를 직접 호출하지 않는다.

## Alternatives Considered

### A. 하나의 큰 씬에 모든 UI 통합

- **설명**: TradingScreen, LeagueScreen, GrowthScreen이 하나의 .tscn에 함께 존재.
  탭 전환 시 해당 Control의 `visible`을 토글.
- **장점**: 씬 로딩 없음. 상태 공유가 단순.
- **단점**: 씬 파일이 수천 노드의 모놀리식 구조가 됨. 씬 복잡도 폭증.
  팀원 간 충돌(merge conflict) 빈발. 각 화면의 독립 개발/테스트 불가.
  Godot 에디터에서 씬 편집이 현실적으로 어려워짐.
- **기각 이유**: 씬 복잡도 + 협업 불가

### B. 각 씬이 독립적으로 일시정지 호출

- **설명**: F2 탭 씬(LeagueScreen)이 활성화될 때 자체적으로
  `GameClock.pause()` 호출. F1 복귀 시 `GameClock.resume()` 호출.
- **장점**: 각 씬이 자신의 일시정지 책임을 소유.
- **단점**: 복수 소스 충돌 발생. LeagueScreen이 pause()를 호출한 상태에서
  메뉴 팝업도 pause()를 호출하면, 메뉴가 닫힐 때 resume()이 호출되어
  아직 F2가 열려 있는데도 시계가 재개됨. 디버깅이 어려운 타이밍 버그.
- **기각 이유**: 복수 일시정지 소스 충돌 → 소스 ID 패턴 필요

### C. 전역 PauseManager 오토로드

- **설명**: 별도 PauseManager autoload가 소스 ID 참조 카운팅을 소유.
  MainScreen 포함 모든 UI가 PauseManager를 호출.
- **장점**: GameClock 외부로 일시정지 상태를 분리.
- **단점**: 이 프로젝트 규모에서 과도한 추상화. GameClock이 자체 일시정지 상태를
  가지는 것이 더 자연스러움 (시계가 멈추는 주체가 시계). 오토로드 추가는
  초기화 순서 복잡성을 증가시킴.
- **기각 이유**: YAGNI. GameClock 내장 소스 ID 패턴으로 충분.

## Consequences

### 긍정적

- 일시정지 소스 ID 패턴으로 복수 소스 충돌이 구조적으로 불가능
- TradingScreen/LeagueScreen/GrowthScreen이 독립 씬이므로 각자 독립 개발·테스트
- 싱글/멀티 일시정지 분기가 MainScreen 한 곳에서만 관리됨
- 씬 계층이 명확하여 Godot 에디터 작업 용이

### 부정적

- MainScreen이 탭 전환 + 일시정지 두 책임을 모두 가짐 (응집도 다소 감소)
- 향후 멀티플레이어 구현 시 MainScreen의 분기 로직을 반드시 수정해야 함
  (GDD §3-1 EC-08 명시)

### 리스크

- **pause_request 누수**: `pause_request` 호출 후 `pause_release` 없이 씬이 제거되면
  영구 일시정지 상태 발생. 완화: MainScreen의 `_exit_tree()`에서 모든 소스 강제 해제.
- **소스 ID 오타**: 문자열 소스 ID 불일치로 release가 동작 안 할 수 있음.
  완화: `const TAB_SWITCH_SOURCE = "tab_switch"` 형태로 상수화.

## Performance Implications

- **CPU**: 탭 전환은 이벤트성. 씬 전환이 아니라 visibility 전환이므로 부하 없음.
- **Memory**: 세 씬이 모두 상주하지만 각각 경량 UI 씬. 512MB 예산 내 안전.
- **Load Time**: 씬 시작 시 세 씬 모두 로딩. 콜드 스타트에 소폭 영향.
  (허용 트레이드오프 — 탭 전환 시 로딩 지연 제거)
- **Network**: 해당 없음.

## Validation Criteria

- **AC-01**: MARKET_OPEN 중 F2 탭 이동 시 GameClock이 일시정지되고
  PauseOverlay가 표시됨. F1 복귀 시 재개.
- **AC-02**: LeagueScreen과 GrowthScreen이 `GameClock.pause_request()` /
  `pause_release()`를 직접 호출하는 코드가 없음 (코드 리뷰 항목).
- **AC-03**: 탭 전환 일시정지 상태에서 메뉴 팝업이 추가 `pause_request`를 호출해도,
  메뉴 닫기(`pause_release("menu")`) 후 시계가 재개되지 않음.
  F1 복귀(`pause_release("tab_switch")`) 후에만 재개.
- **AC-04**: PRE_MARKET 상태에서 탭 전환 시 일시정지 발동 안 됨.

## Related Decisions

- [ADR-001](001-system-communication-pattern.md) — 시그널 + 직접 호출 하이브리드
- design/gdd/league-ui.md §3-1 (씬 소유권 Option B 결정 기록)
