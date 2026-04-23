# 손절/익절 자동 주문 (Stop-Loss / Take-Profit)

> **Status**: Approved
> **Author**: game-designer
> **Last Updated**: 2026-04-20
> **Implements Pillar**: 판단이 곧 실력, 체감있는 성장
> **Skill Gate**: TR2 (선행 조건: TR1 지정가 주문)
> **See**: design/gdd/skill-tree.md, design/gdd/order-engine.md

---

## 1. Overview

손절/익절 자동 주문 시스템은 플레이어가 보유 종목별로 손절가(Stop-Loss)와 익절가(Take-Profit)
두 가지 자동 청산 조건을 사전 설정해두면, 매 틱마다 현재가를 감시하다가 조건이 충족되는 순간
OrderEngine을 통해 시장가 주문을 자동 발동하는 TR2 스킬 기능이다. TR1 지정가 주문이
"내가 원하는 가격에 사는" 도구라면, TR2는 "내가 설정한 리스크 한계 밖으로 가격이 이탈하면
자동으로 청산한다"는 감시·보호 도구다. **롱 포지션**에는 SELL(자동 매도)을 발동하고,
**TR3 숏 포지션**에는 가격 방향이 역전된 조건으로 BUY_TO_COVER(자동 환매)를 발동한다.
설정은 종목별로 독립적이며, 하나의 종목에 손절가와 익절가를 동시에 설정할 수 있다.
발동 후 자동으로 해당 종목의 설정이 해제된다.

---

## 2. Player Fantasy

TR2를 해금한 날, 트레이딩 화면이 달라진다. 보유 종목 목록 옆에 새로운 버튼이 생긴다 —
"손절/익절 설정".

스타칩을 65,000원에 샀다. 손절가 62,000원, 익절가 72,000원을 입력한다. 확인. 이제 다른
종목을 분석해도 된다. 시장이 급락해도, 다른 곳을 보고 있어도 — 스타칩이 62,000원을
건드리는 순간 자동으로 팔린다. "나는 이미 판단을 내렸다."

이것이 TR2의 플레이어 판타지다. 지정가 주문(TR1)이 "진입 타이밍을 잡는" 기술이라면,
TR2는 "리스크를 미리 정의하고 실행을 자동화하는" 한 단계 높은 판단이다.
MDA Aesthetic: **숙달(Mastery)** + **통제감(Expression)**.

---

## 3. Detailed Design

### 규칙 1. TR2 해금 조건 및 접근

- TR2 스킬 해금 조건: TR1(지정가 주문) 해금 + 스킬 포인트 1개 소비
- TR1 미해금 시 손절/익절 설정 UI 비활성화(disabled). 마우스오버 시 툴팁:
  "지정가 주문(TR1)을 먼저 해금하세요"
- TR2 해금 즉시 효과 적용 — 이미 보유 중인 종목에도 설정 가능
- 해금은 영구적이며 시즌 리셋에 영향받지 않는다

### 규칙 2. 조건 설정 구조

각 보유 종목마다 독립적인 `StopTakeSetting` 레코드를 보유한다:

```
StopTakeSetting {
    stock_id:          String
    stop_loss_price:   int | null   # 손절가 (원). null = 미설정
    take_profit_price: int | null   # 익절가 (원). null = 미설정
    quantity:          int          # 자동 매도 수량. 기본값: 전량 보유 수량
    enabled:           bool
}
```

- 손절가와 익절가는 독립적으로 설정/해제 가능 (둘 다 null이면 사실상 비활성)
- `quantity`는 설정 시점의 전량 보유 수량으로 초기화되며, 플레이어가 변경 가능
- 이후 추가 매매로 보유 수량이 변경되어도 `quantity`는 자동 갱신 안됨.
  발동 시 `min(quantity, available_quantity)`로 클램프 처리

### 규칙 3. 발동 메커니즘

매 틱의 주문 처리 단계에서, OrderEngine은 지정가 체결 처리 직후에 손절/익절 감시를 실행한다.

**틱 처리 순서 (변경 후)**:

```
3-a. PRE_MARKET 큐 처리
3-b. 시장가 큐 처리
3-c. 지정가 체결 검사 (기존 TR1)
3-d. 손절/익절 발동 검사 (신규 TR2)  ← 이 단계 추가
```

**3-d 발동 검사 상세**:

```
for each stock_id in _stop_take_settings:
    if not enabled or market_state != MARKET_OPEN: skip
    current_price = PriceEngine.get_current_price(stock_id)
    holding = PortfolioManager.get_holding(stock_id)
    if holding == null: 설정 제거 및 skip

    triggered = false
    trigger_reason = ""

    if stop_loss_price != null and current_price <= stop_loss_price:
        triggered = true
        trigger_reason = "STOP_LOSS"
    elif take_profit_price != null and current_price >= take_profit_price:
        triggered = true
        trigger_reason = "TAKE_PROFIT"

    if triggered:
        qty = min(quantity, holding.available_quantity)
        if qty > 0:
            _submit_auto_market_sell(stock_id, qty, trigger_reason)
        _remove_setting(stock_id)
```

**중요**: 손절(<=)과 익절(>=)은 elif 관계. 동일 틱에 두 조건이 동시에 참이 되는
비정상 설정(손절가 >= 익절가)은 Edge Cases 참조.

### 규칙 4. 자동 청산 발동

**롱 포지션** 발동 시 (`_evaluate_long()`):

1. `OrderEngine.submit_market_order("SELL", stock_id, qty)` 호출
2. `on_stop_take_triggered(stock_id, trigger_reason, filled_price)` 시그널 발행 → UI 알림

**숏 포지션** 발동 시 (`_evaluate_short()`) — 가격 방향 역전:

- 손절(STOP_LOSS): `current_price >= stop_loss_price` → `submit_market_order("BUY_TO_COVER", stock_id, qty)`
- 익절(TAKE_PROFIT): `current_price <= take_profit_price` → `submit_market_order("BUY_TO_COVER", stock_id, qty)`

자동 발동 주문은 기존 시장가 주문과 동일한 검증 경로를 거친다.

### 규칙 5. 설정 생명주기

| 이벤트 | 처리 |
|--------|------|
| TR2 해금 | 기존 보유 종목 및 숏 포지션에 설정 가능. 초기 설정 없음 |
| 종목 전량 수동 매도 (롱) | 해당 종목 설정 자동 삭제 |
| 숏 포지션 청산 (수동 BUY_TO_COVER / 강제청산) | 해당 종목 설정 자동 삭제 (`on_short_position_closed` 수신) |
| 발동 후 전량 체결 | 설정 자동 삭제 |
| 장 마감 (MARKET_CLOSED) | 설정 유지. 다음 거래일에 계속 감시 |
| 시즌 종료 | 설정 삭제 (보유 종목 초기화와 함께 정리) |
| 세이브/로드 | 설정 직렬화 보존 |

### 규칙 6. UI 진입점

- **포트폴리오 뷰**: 각 보유 종목 행에 "S/T" 버튼. 설정 상태별 색상
  (손절만: 빨강 / 익절만: 초록 / 양쪽: 주황)
- **설정 팝업**: 종목명, 현재가, 손절가 입력란, 익절가 입력란, 수량 입력란, 확인/취소
- **차트 오버레이**: 선택 종목의 손절가/익절가를 수평선으로 표시
- TR2 미해금 시: 위 UI 요소 전체 disabled

---

## 4. Formulas

### F1. 손절 발동 조건

**롱 포지션** (가격 하락 시 손실):
```
STOP_LOSS 발동 (롱):
    stop_loss_price ≠ null AND current_price <= stop_loss_price AND MARKET_OPEN
```
예시: 보유가 65,000원, 손절가 62,000원. 현재가 61,500원 → **발동** → SELL.

**숏 포지션** (가격 상승 시 손실 — 방향 역전):
```
STOP_LOSS 발동 (숏):
    stop_loss_price ≠ null AND current_price >= stop_loss_price AND MARKET_OPEN
```
예시: 숏 개시가 10,000원, 손절가 13,000원. 현재가 13,500원 → **발동** → BUY_TO_COVER.

### F2. 익절 발동 조건

**롱 포지션** (가격 상승 시 수익):
```
TAKE_PROFIT 발동 (롱):
    take_profit_price ≠ null AND current_price >= take_profit_price AND MARKET_OPEN
```
예시: 보유가 65,000원, 익절가 72,000원. 현재가 72,500원 → **발동** → SELL.

**숏 포지션** (가격 하락 시 수익 — 방향 역전):
```
TAKE_PROFIT 발동 (숏):
    take_profit_price ≠ null AND current_price <= take_profit_price AND MARKET_OPEN
```
예시: 숏 개시가 10,000원, 익절가 7,000원. 현재가 6,500원 → **발동** → BUY_TO_COVER.

### F3. 자동 청산 수량 결정

롱:
```
auto_qty = min(setting.quantity, holding.available_quantity)
```
- `available_quantity`: 지정가 매도 잠금 수량 제외한 가용 수량

숏:
```
auto_qty = min(setting.quantity, short_position.quantity)
```

예시: 설정 100주, 가용 80주 (지정가 잠금 20주) → auto_sell_qty = 80주.

### F4. UI 입력 유효성 (UI 레벨 전용)

```
유효한 손절가:
    lower_limit < stop_loss_price < current_price
    AND stop_loss_price % tick_size == 0

유효한 익절가:
    current_price < take_profit_price <= upper_limit
    AND take_profit_price % tick_size == 0
```

- `lower_limit`, `upper_limit`: `PriceEngine.get_daily_limits(stock_id)` (전일 종가 ±30%)
- `tick_size`: ADR-002 KRX 호가 단위 테이블 기준

엔진 레벨 재검증 없음 — 설정 후 가격이 이동하여 조건이 역전될 수 있기 때문.

### F5. 실현 손익 (참조용)

자동 매도로 발생하는 실현 손익은 기존 시장가와 동일하게 PortfolioManager가 계산:

```
realized_pnl = (filled_price - avg_buy_price) × auto_sell_qty
```

StopTakeSystem은 이 값을 직접 계산하지 않으며, `on_order_filled` 시그널로 수신.

---

## 5. Edge Cases

| 상황 | 처리 |
|------|------|
| 손절가 >= 익절가 설정 | UI 차단 + "손절가는 익절가보다 낮아야 합니다" 오류. 저장 불가 |
| 손절가 >= 현재가 설정 | UI 차단 + 오류 표시 |
| 익절가 <= 현재가 설정 | UI 차단 + 오류 표시 |
| 가격이 갭으로 건너뜀 (예: 61,000 → 59,000) | 59,000 <= 62,000 조건 만족 → 정상 발동. 체결가 = 59,000원. 슬리피지는 의도된 설계 ("판단이 곧 실력") |
| 자동 주문 REJECTED (가용 수량 0 등) | 설정 유지. 토스트: "[종목명] 자동 매도 실패: [reject_reason]" |
| 여러 종목 동시 발동 | `_stop_take_settings` 순서대로 순차 처리. 종목 간 독립 |
| 지정가(3-c)와 손절/익절(3-d) 동일 틱 충족 | 지정가 먼저 체결 → 잔여 가용 수량에만 손절/익절 발동 |
| 수동 전량 매도(3-b)와 동일 틱 발동 조건 | 시장가(3-b) 먼저 처리 → 가용 수량 0 → 3-d 발동 없음, 설정 삭제 |
| PRE_MARKET / PAUSED 중 조건 충족 | 발동 없음, 설정 유지. MARKET_OPEN 복귀 시 재개 |
| 시즌 종료 후 설정 잔존 | 새 시즌 시작 시 `_stop_take_settings.clear()` |
| 로드 후 설정 종목이 보유 목록에 없음 | 로드 후 검증 → 없는 종목 설정 삭제 |
| TR2 미해금 세이브에 설정 잔존 | 로드 후 TR2 미해금 확인 → 설정 삭제 |
| 수량을 0으로 설정 | UI 차단. 최소 1주 |
| 설정 수량 > 보유 수량 | UI 경고 표시 (저장 허용). 발동 시 F3 클램프 적용 |
| **세이브/로드로 손절 회피 시도 (price scout)** | 로드 시 PriceEngine이 세이브 시점 current_price / prev_day_close / tick_prices 배열을 복원한다. 세이브 이후의 가격 변동은 ADR-018 RNG 엔트로피 재격리로 재현되지 않으므로 익스플로잇 성립 불가. 손절/익절 설정도 복원되어 감시 정상 재개. |
| **현재가 == 하한가 (가격 하한 도달)** | 유효한 손절가 설정 범위 없음. UI에서 손절가 입력란 비활성화 + "현재 하한가 도달로 손절가 설정 불가" 표시 |
| **현재가 == 상한가 (가격 상한 도달)** | 유효한 익절가 설정 범위 없음. UI에서 익절가 입력란 비활성화 + "현재 상한가 도달로 익절가 설정 불가" 표시 |
| **동일 틱 내 UI 설정 변경 + 감시 실행** | GDScript 단일 스레드 보장 — 틱 처리(3-d)는 UI 입력 콜백과 동일 프레임 내에서 순차 실행. 플레이어가 UI에서 설정을 변경하더라도 해당 틱의 3-d 단계가 이미 완료된 뒤에 반영되거나, 변경 전 값으로 처리됨. 어느 경우도 undefined behavior 없음 (단일 스레드 보장). |

---

## 6. Dependencies

### 상위 의존 (이 시스템이 필요로 하는 것)

| 시스템 | 인터페이스 |
|--------|-----------|
| SkillTree | `is_skill_unlocked("TR2")`, `is_skill_unlocked("TR1")` |
| PriceEngine | `get_current_price(stock_id: String) -> int` |
| PriceEngine | `get_daily_limits(stock_id: String) -> Dictionary` |
| OrderEngine | `submit_market_order(side, stock_id, quantity) -> Dictionary` |
| PortfolioManager | `get_holding(stock_id) -> Variant` |
| ShortSellingSystem | `has_short(stock_id) -> bool`, `get_all_short_positions() -> Array[Dictionary]`, `on_short_position_closed` 시그널 |
| GameClock | `get_market_state() -> MarketState`, `on_tick` (OrderEngine 경유) |
| SaveSystem | `_stop_take_settings` 직렬화/역직렬화 |

### 하위 의존 (이 시스템에 의존하는 것)

| 시스템 | 의존 내용 |
|--------|----------|
| OrderEngine | TR2 감시 루프를 `_on_tick()` 3-d에서 호출 |
| PortfolioView | `on_stop_take_triggered` 시그널 수신 → 알림 표시 |
| TradingScreen 차트 | `get_setting(stock_id)` → 수평선 오버레이 |

> **GDD 동기화 완료 (2026-04-23)**:
> - `design/gdd/order-engine.md` — 틱 처리 순서 3-d 단계 반영됨
> - `design/gdd/skill-tree.md` — Dependencies 테이블 StopTakeSystem 등록됨

---

## 7. Tuning Knobs

외부화 파일: `assets/data/stop_take_config.json`

| 변수명 | 기본값 | 범위 | 설명 |
|--------|--------|------|------|
| `STOP_TAKE_MAX_SETTINGS` | 10 | 3~20 | 동시 설정 가능 종목 수 상한. 실질 상한 = min(STOP_TAKE_MAX_SETTINGS, current_max_holdings). 보유 종목 초과 설정은 생성 불가이므로 이 값은 하드 상한 역할만 함. MAX_HOLDINGS 최대값(10)에 맞춰 기본값 10으로 설정. |
| `STOP_LOSS_MIN_GAP_PCT` | 0.0 | 0.0~0.05 | 현재가 대비 손절가 최소 이격 비율 (UX 경고 임계값) |
| `TAKE_PROFIT_MIN_GAP_PCT` | 0.0 | 0.0~0.05 | 현재가 대비 익절가 최소 이격 비율 |
| `AUTO_SELL_APPLIES_TICK_LOCK` | false | bool | 자동 매도 후 같은 틱 재매수 차단 여부 |
| `NOTIFY_ON_TRIGGER` | true | bool | 발동 시 토스트 알림 표시 여부 |

---

## 8. Acceptance Criteria

| AC | 기준 | 검증 방법 |
|----|------|----------|
| AC-01 | TR2 미해금 시 설정 UI 비활성화 | 통합 테스트 |
| AC-02 | TR2 해금 즉시 설정 UI 활성화 | 통합 테스트 |
| AC-03 | 손절가 이하 현재가 → 시장가 매도 자동 발동 | 유닛 테스트 |
| AC-04 | 익절가 이상 현재가 → 시장가 매도 자동 발동 | 유닛 테스트 |
| AC-05 | 발동 후 해당 종목 설정 삭제 | 유닛 테스트 |
| AC-06 | 조건 미충족 틱에서 발동 없음 | 유닛 테스트 |
| AC-07 | MARKET_OPEN 외 상태에서 발동 없음 | 유닛 테스트 |
| AC-08 | 손절가 >= 익절가 입력 시 UI 차단 | 통합 테스트 |
| AC-09 | 발동 시 `on_stop_take_triggered(stock_id, reason, filled_price)` 시그널 발행 | 유닛 테스트 |
| AC-10 | 발동 수량이 `min(설정량, 가용량)`으로 클램프됨 | 유닛 테스트 |
| AC-11 | 지정가(3-c) 처리 후 잔여 수량에만 손절/익절(3-d) 발동 | 유닛 테스트 |
| AC-12 | 종목 전량 수동 매도 시 설정 자동 삭제 | 유닛 테스트 |
| AC-13 | 세이브/로드 후 설정 복원 | 통합 테스트 |
| AC-14 | 시즌 종료(새 시즌 시작) 후 설정 초기화 | 통합 테스트 |
| AC-15 | TR2 미해금 상태 로드 시 설정 삭제 | 유닛 테스트 |
| AC-16 | 세이브/로드 후 PriceEngine RNG가 세이브 이후 가격 변동을 재현하지 않음 (price scout 불가) | 유닛 테스트: 세이브 시점 가격 고정, 로드 후 동일 틱에서 다른 시드 적용 확인 (ADR-018) |
| AC-S01 | 숏 포지션에 set_condition 성공, is_short 플래그 true | 유닛 테스트 |
| AC-S02 | 롱·숏 모두 없을 때 set_condition 실패 | 유닛 테스트 |
| AC-S03 | 숏: 가격 상승으로 stop_loss_price 도달 → BUY_TO_COVER 자동 발동 | 유닛 테스트 |
| AC-S04 | 숏: 가격 하락으로 take_profit_price 도달 → BUY_TO_COVER 자동 발동 | 유닛 테스트 |
| AC-S05 | 숏: 조건 미충족 시 발동 없음 | 유닛 테스트 |
| AC-S06 | 숏 포지션 청산 시 설정 자동 삭제 (on_short_position_closed 수신) | 유닛 테스트 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 기능 | 진입점 |
|------|--------|
| 설정 저장 | `portfolio_view.gd._on_stop_take_confirmed()` → `StopTakeSystem.set_condition()` |
| 설정 해제 | `portfolio_view.gd._on_stop_take_clear()` → `StopTakeSystem.clear_condition()` |
| 매 틱 감시 발동 | `order_engine.gd._on_tick()` 3-d → `StopTakeSystem.check_and_trigger(market_state)` |
| 보유 소멸 시 정리 | `PortfolioManager.holding_removed` 시그널 → `StopTakeSystem._on_holding_removed()` (private callback) |

### 호출 경로

- [x] `StopTakeSystem.set_condition(stock_id, stop_loss_price, take_profit_price, quantity) -> bool`
- [x] `StopTakeSystem.clear_condition(stock_id) -> void`
- [x] `StopTakeSystem.get_setting(stock_id) -> Variant` (null = 미설정)
- [x] `StopTakeSystem.get_all_settings() -> Array[Dictionary]`
- [x] `StopTakeSystem.check_and_trigger(market_state: GameClock.MarketState) -> void`
- [x] 롱 소멸 시 설정 정리 — `PortfolioManager.holding_removed` → `StopTakeSystem._on_holding_removed()`
- [x] 숏 소멸 시 설정 정리 — `ShortSellingSystem.on_short_position_closed` → `StopTakeSystem._on_short_position_closed()`
- [x] `ShortSellingSystem.has_short(stock_id)` / `get_all_short_positions()` 존재 확인
- [x] 숏 발동: `OrderEngine.submit_market_order("BUY_TO_COVER", stock_id, qty)`
- [x] `StopTakeSystem.on_stop_take_triggered` 시그널 (stock_id, reason, filled_price)
- [x] `SkillTree.is_skill_unlocked("TR1")` / `("TR2")` 존재 확인
- [x] `PriceEngine.get_daily_limits(stock_id)` 존재 확인
- [x] `OrderEngine.submit_market_order("SELL", stock_id, qty)` 존재 확인
- [x] `PortfolioManager.get_holding(stock_id)` 존재 확인
- [x] `order_engine.gd._on_tick()` 내부 3-d 단계 삽입
- [x] `order-engine.md` 틱 처리 순서 섹션 개정 (3-d 단계 명시)
- [x] `stop_take_config.json` `assets/data/`에 생성
- [x] `SaveSystem` 직렬화 대상에 StopTakeSystem 추가

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_stop_loss.gd` | `test_ui_disabled_when_tr2_not_unlocked()` |
| AC-02 | `tests/unit/test_stop_loss.gd` | `test_ui_enabled_after_tr2_unlock()` |
| AC-03 | `tests/unit/test_stop_loss.gd` | `test_stop_loss_triggers_on_price_breach()` |
| AC-04 | `tests/unit/test_stop_loss.gd` | `test_take_profit_triggers_on_price_breach()` |
| AC-05 | `tests/unit/test_stop_loss.gd` | `test_setting_removed_after_trigger()` |
| AC-06 | `tests/unit/test_stop_loss.gd` | `test_no_trigger_when_condition_not_met()` |
| AC-07 | `tests/unit/test_stop_loss.gd` | `test_no_trigger_outside_market_open()` |
| AC-08 | `tests/unit/test_stop_loss.gd` | `test_invalid_stop_take_relationship_rejected()` |
| AC-09 | `tests/unit/test_stop_loss.gd` | `test_trigger_signal_emitted_with_correct_params()` |
| AC-10 | `tests/unit/test_stop_loss.gd` | `test_quantity_clamped_to_available()` |
| AC-11 | `tests/unit/test_stop_loss.gd` | `test_limit_order_takes_priority_same_tick()` |
| AC-12 | `tests/unit/test_stop_loss.gd` | `test_setting_cleared_on_manual_full_sell()` |
| AC-13 | `tests/unit/test_stop_loss.gd` | `test_setting_persists_after_save_load()` |
| AC-14 | `tests/unit/test_stop_loss.gd` | `test_setting_cleared_on_season_start()` |
| AC-15 | `tests/unit/test_stop_loss.gd` | `test_setting_cleared_if_skill_not_unlocked_on_load()` |
| AC-16 | `tests/unit/test_price_engine.gd` | `test_price_scout_exploit_blocked()` (ADR-018 엔트로피 재격리 검증) |
| AC-S01 | `tests/unit/test_stop_loss.gd` | `test_short_set_condition_succeeds_with_short_position()` |
| AC-S02 | `tests/unit/test_stop_loss.gd` | `test_short_set_condition_fails_without_any_position()` |
| AC-S03 | `tests/unit/test_stop_loss.gd` | `test_short_stop_loss_triggers_when_price_rises()` |
| AC-S04 | `tests/unit/test_stop_loss.gd` | `test_short_take_profit_triggers_when_price_falls()` |
| AC-S05 | `tests/unit/test_stop_loss.gd` | `test_short_no_trigger_when_condition_not_met()` |
| AC-S06 | `tests/unit/test_stop_loss.gd` | `test_short_setting_cleared_on_position_close()` |

### 빌드 검증

- [x] 바이너리 실행 확인: QA Lead 서명 — 내부 감사 2026-04-15 (Sprint 7 완료, 274/274 테스트 통과)
- [x] 숏 포지션 손절/익절 추가 후 빌드 재검증 필요
