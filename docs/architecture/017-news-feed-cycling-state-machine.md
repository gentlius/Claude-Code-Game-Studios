# ADR-017: 뉴스 카드 관련종목 순회 — 클로저 캡처 상태머신

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-04-14 |
| **Decision Maker** | user + lead-programmer |
| **Relates To** | src/ui/news_feed.gd, design/gdd/news-events.md |

## Context

뉴스 카드를 클릭할 때 관련 종목을 순회하여 TradingScreen에 포커스를 전달하는 기능이
필요하다. 관련 종목 수(N)가 0인 경우와 1 이상인 경우 동작이 다르다:

- **N = 0**: 클릭 → 펼침 / 재클릭 → 접힘 (단순 토글)
- **N ≥ 1**: 첫 클릭 → 펼침 + 종목[0] emit, 두 번째 → 종목[1] emit, …, N+1번째 → 접힘

추가 제약:
- 뉴스 카드는 씬이 아닌 코드로 동적 생성된다. 카드마다 독립 상태가 필요하다.
- `stock_clicked` 시그널은 NewsFeed 노드 전체에 하나만 존재한다.

두 가지 구현 방식이 검토됐다:

**A. 공유 Dictionary**: `{card_id: cycle_index}` 딕셔너리를 NewsFeed에 두고
   시그널 핸들러에서 card_id로 조회.

**B. 클로저 캡처**: `gui_input.connect(func(...) -> void:)` 내부에 `var _cycle_index: int = 0`
   을 선언하여 카드별로 독립 캡처. 딕셔너리나 외부 상태 없이 카드가 자신의 상태를 소유.

## Decision

**클로저 캡처 방식 (B)**을 채택한다.

### 상태머신 설계

```
cycle_index 초기값 = 0
클릭 시:
  if cycle_index >= max(stock_ids.size(), 1):   # N=0이면 max(0,1)=1, N>=1이면 max(N,1)=N
      접힘 + cycle_index = 0
  else:
      펼침
      if cycle_index < stock_ids.size():
          stock_clicked.emit(stock_ids[cycle_index])
      cycle_index += 1
```

`max(stock_ids.size(), 1)` 단일 표현식이 N=0(1이 임계값)과 N≥1(N이 임계값) 두 경우를
통합한다. 별도 분기 없음.

### N별 동작 흐름

| 클릭 횟수 | N=0 | N=1 | N=2 |
|-----------|-----|-----|-----|
| 1 | 펼침(emit 없음), index→1 | 펼침+emit[0], index→1 | 펼침+emit[0], index→1 |
| 2 | 접힘, index→0 | 접힘, index→0 | 펼침+emit[1], index→2 |
| 3 | — | — | 접힘, index→0 |

## Rationale

- **상태 소유권 명확성**: 카드가 자신의 cycle_index를 소유한다. 외부 딕셔너리 룩업 없음.
- **생성/소멸 대칭**: 카드 Control 노드가 queue_free될 때 클로저도 함께 소멸.
  딕셔너리 방식에서 발생하는 stale key 누수가 없다.
- **코드 밀집도**: 관련 로직이 카드 생성 코드에 인접하여 읽기 쉬움.

## Alternatives Considered

### A. 공유 Dictionary `{card: cycle_index}`

- **기각 이유**: 카드 소멸 시 딕셔너리에서 명시적으로 제거해야 함.
  `tree_exiting` 연결이 추가로 필요하고, 관리 포인트가 분산된다.
  GDScript Dictionary는 WeakRef가 아니므로 소멸된 카드 참조가 남으면 메모리 누수 위험.

## Implementation Notes (2026-04-16)

### int 클로저 캡처 버그 → Array[int] 박스 패턴

초기 구현에서 `var _cycle_index: int = 0`을 클로저에 캡처했으나, 실제 게임에서
클릭해도 순환 상태가 유지되지 않는 버그가 확인됐다. 원인: GDScript 클로저는 int
(값 타입)를 캡처할 때 변이(mutation)가 호출 간에 보장되지 않는다.

**수정 패턴**: `Array[int]` 단일 원소 박스로 래핑.
- `var _cycle_box: Array[int] = [0]`
- 람다 내부에서 `_cycle_box[0] += 1` / `_cycle_box[0] = 0`
- Array는 참조 타입이므로 클로저가 동일 힙 객체를 공유 → 변이 영속 보장

또한 PanelContainer는 `mouse_filter`를 MOUSE_FILTER_STOP으로 기본값을 가지지만,
명시적 설정 없이는 Godot 4.6에서 입력 이벤트 수신이 불안정할 수 있다.
→ `card.mouse_filter = Control.MOUSE_FILTER_STOP` 명시 추가.
→ `card.accept_event()` 추가로 ScrollContainer의 드래그-스크롤 재처리 방지.

**일반 규칙**: GDScript 클로저에서 변이 가능한 카운터/플래그가 필요하면
항상 `Array[T]` 단일 원소 박스 패턴을 사용한다. `int`/`bool`/`float` 직접 캡처 금지.

## Consequences

### 긍정적
- 카드 수가 늘어도 NewsFeed 클래스에 상태가 축적되지 않음
- N=0 / N≥1 분기 없는 단일 코드 경로

### 부정적
- `Array[int]` 박스 패턴은 직관적이지 않음 — 위 Implementation Notes에 이유 기록됨.
- 향후 "현재 어떤 카드가 열려 있는가"를 NewsFeed에서 조회해야 할 경우
  클로저 캡처 방식으로는 직접 접근 불가 → 그 시점에 Dictionary 방식으로 전환 고려.

## Related Decisions

- [ADR-001](001-system-communication-pattern.md) — 시그널 통신 패턴
- design/gdd/news-events.md — 뉴스 이벤트 시스템 설계
