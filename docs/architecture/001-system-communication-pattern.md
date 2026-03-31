# ADR-001: System Communication Pattern

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-03-31 |
| **Decision Maker** | user + game-designer |
| **Relates To** | All 11 MVP system GDDs |

## Context

시드머니는 21개 시스템이 유기적으로 연결된 투자 시뮬레이션이다. 틱 처리 순서가
보장되어야 하며 (뉴스 → 가격 → 주문), 시스템 간 의존 방향이 명확해야 한다.
싱글플레이어 싱글스레드 게임이므로 네트워킹/동시성 고려는 불필요하다.

## Decision

**시그널 + 직접 메서드 호출 하이브리드 패턴**을 채택한다.

### 1. 시그널 (Signal) — 이벤트 알림 (1:N)

Game Clock이 발행하는 시그널을 하위 시스템들이 구독한다.
발행자는 구독자를 모르며, 구독자는 자유롭게 추가/제거 가능.

```
Game Clock → on_tick(tick_number, day, week)
Game Clock → on_market_state_changed(new_state, prev_state)
Game Clock → on_season_start(), on_market_open(), on_market_close(), ...
```

**사용 기준**: 발행자가 수신자를 알 필요 없을 때. 1:N 관계.

### 2. 직접 메서드 호출 — 데이터 조회/명령 (1:1)

시스템이 다른 시스템의 public API를 직접 호출한다.
호출자가 피호출자를 알고 있으며, 반환값이 필요할 때 사용.

```
Order Engine → currency.sim_deduct(amount)     # 명령
Order Engine → portfolio.add_holding(...)       # 명령
Portfolio    → price_engine.get_current_price()  # 조회
Portfolio    → currency.get_sim_cash()           # 조회
```

**사용 기준**: 반환값이 필요하거나, 1:1 명령/조회 관계.

### 3. 틱 처리 순서 보장

매 틱 시그널 핸들러의 실행 순서를 고정한다:

```
on_tick 처리 순서:
  1. 뉴스/이벤트 시스템 — 이벤트 평가 및 가격 엔진에 push
  2. 가격 엔진 — 이벤트 반영 후 가격 갱신
  3. 주문 처리 엔진 — 갱신된 가격으로 체결
  4. 포트폴리오 관리 — 평가 갱신 (update_valuation)
```

Godot의 시그널은 기본적으로 연결 순서대로 호출되므로, `connect()` 순서로
틱 처리 순서를 보장한다. 또는 Game Clock이 직접 각 시스템의 `process_tick()`을
순서대로 호출하는 방식도 가능 — 프로토타입에서 검증 후 결정.

### 4. 의존 방향 규칙

```
Foundation (Game Clock, Stock DB, Currency)
    ↑ 의존
Core (Price Engine, News/Events, Order Engine, Portfolio Manager)
    ↑ 의존
Presentation (Trading Screen, Chart, News Feed UI, Portfolio UI)
```

- 하위 레이어 → 상위 레이어 의존 금지 (예: Game Clock이 UI를 참조하면 안 됨)
- 동일 레이어 간 의존은 허용하되 순환 금지
- **유일한 예외**: News/Events → Game Clock.set_speed(1) (이벤트 감속)

## Alternatives Considered

### A. 순수 시그널 (모든 통신을 시그널로)

- 장점: 완전한 디커플링
- 단점: 반환값이 필요한 조회(`get_current_price`)에 부적합. 콜백 지옥 유발.
  틱 처리 순서 보장 어려움

### B. 중앙 이벤트 버스

- 장점: 단일 경유점으로 디버깅 용이
- 단점: 모든 이벤트가 하나의 버스를 거치면 병목. Godot의 시그널 시스템과 이중 구현.
  이 규모(21 시스템)에서는 과도한 추상화

### C. 순수 직접 호출 (시그널 미사용)

- 장점: 명시적, 추적 용이
- 단점: 1:N 관계에서 발행자가 모든 구독자를 알아야 함. 시스템 추가 시 발행자 수정 필요.
  Game Clock이 모든 하위 시스템을 직접 참조해야 하는 강결합 발생

## Consequences

### 긍정적

- Game Clock의 시그널 카탈로그가 시스템 간 계약(contract) 역할
- 새 시스템 추가 시 시그널 구독만으로 연결 (Game Clock 수정 불필요)
- 직접 호출은 타입 안전하고 IDE 자동완성 지원
- 틱 처리 순서가 명확하여 "뉴스 발생 전 가격에 주문 체결" 같은 버그 방지

### 부정적

- 시그널 연결 순서로 틱 순서를 보장하는 것은 암묵적 — 문서화 필수
- 직접 호출 부분은 시스템 간 결합도가 존재 (인터페이스로 완화 가능)
- 하이브리드 패턴이므로 "이건 시그널? 직접 호출?" 판단 기준을 팀 내 공유해야 함

### 판단 기준 요약

| 상황 | 패턴 |
|------|------|
| 이벤트 알림 (발행자가 수신자 모름) | 시그널 |
| 데이터 조회 (반환값 필요) | 직접 호출 |
| 명령 실행 (1:1, 결과 확인 필요) | 직접 호출 |
| 상태 변화 브로드캐스트 (1:N) | 시그널 |
