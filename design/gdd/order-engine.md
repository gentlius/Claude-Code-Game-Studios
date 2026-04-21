# 주문 처리 엔진 (Order Engine)

> **Status**: Approved
> **Author**: user + game-designer
> **Last Updated**: 2026-04-03
> **Implements Pillar**: 판단이 곧 실력 (Judgment is King), 짧고 굵게 (Quick & Punchy)

## Overview

주문 처리 엔진은 플레이어의 매수/매도 주문을 접수, 검증, 체결하는 Core 시스템이다.
트레이딩 스크린에서 제출된 주문을 받아 잔액/보유량 검증 후 체결하고, 재화 시스템과
포트폴리오 관리 시스템에 결과를 전파한다.

게임 시계의 틱 처리 순서에서 3번째로 실행된다 (뉴스/이벤트 → 가격 엔진 →
**주문 처리 엔진**). 가격 엔진이 갱신한 현재가 기준으로 주문을 체결하므로, 뉴스
발생 후 변동된 가격에 주문이 처리된다.

Beta에서는 세 가지 주문 유형을 지원한다: 시장가 주문(TR0 기본) — 현재가로 즉시
체결, 지정가 주문(TR1 해금) — 조건 충족 시 자동 체결, 손절/익절 자동 주문(TR2
해금) — 보유 종목별 감시 조건 충족 시 시장가 매도 자동 발동 (상세: `stop-loss-take-profit.md`).
공매도(TR3), 레버리지(TR4)는 Sprint 9 이후 구현 예정이다.

**가격 모델**: 오더북(`order-book.md`) 구현 전까지는 **가격 관찰자 모델** — 플레이어
매매가 PriceEngine 가격에 영향을 주지 않으며 현재가로 즉시 체결된다. 오더북 구현 후
호가 잔량 소진 → 슬리피지 → 가격 영향 모델로 전환된다 (현재 오더북 GDD: In Review,
코드 미구현).

## Player Fantasy

뉴스가 떴다. 바이오주 호재다! 시장가 매수 — 체결음이 울린다. 0.77초 후 가격이
오르기 시작한다. "내가 먼저 샀다!" 이 즉각적인 행동→결과 피드백이 매매의 쾌감이다.

혹은 차트를 분석한다. "스타칩이 63,000원까지 내려오면 사야지." 지정가 매수를
걸어둔다. 다른 종목을 보다가 — 체결 알림이 뜬다! 내가 설정한 가격에 정확히
잡혔다. 분석이 맞았다는 확인.

필라 "판단이 곧 실력"에 따라, 매매 판단의 결과가 즉시 포트폴리오에 반영된다.
필라 "짧고 굵게"에 따라, 주문 제출부터 체결까지 지체 없이 처리된다.

## Detailed Design

### Core Rules

#### 규칙 1. 주문 유형

##### 1-1. 시장가 주문 (Market Order) — TR0 기본

```
MarketOrder {
    side: BUY | SELL
    stock_id: string
    quantity: int               # 양의 정수
}
```

- 제출 즉시 **현재 틱의 가격**으로 체결
- 부분 체결 없음 — 전량 체결 또는 전량 거부
- 체결 후 취소 불가
- 일시정지(PAUSED) 중 제출 시: 재개 후 첫 틱에 체결
- **PRE_MARKET 예약**: PRE_MARKET 시장가 매수는 체결까지 가격 변동이 있으므로,
  실제 증권사와 동일하게 상한 기준으로 예약금을 선차감한다:
  ```
  pre_market_reserved = ceil(current_price × (1 + pre_market_buffer_pct)) × quantity
  sim_deduct(pre_market_reserved)
  // 체결 시: refund = pre_market_reserved - (filled_price × quantity)
  // sim_add(refund)
  // 취소 시: sim_add(pre_market_reserved)
  ```
  `pre_market_buffer_pct` 기본값 0.15 (15%). `current_price`는 전일 종가.
  버퍼 근거: MEGA 이벤트의 `max_single_impact`(15%) 대응. 야간 이벤트로 가격이
  상승해도 예약금 범위 내에서 체결되고, 실제 체결가와의 차액은 환불된다.
  MARKET_OPEN/PAUSED 시장가는 기존대로 선차감 없음

##### 1-2. 지정가 주문 (Limit Order) — TR1 해금

```
LimitOrder {
    side: BUY | SELL
    stock_id: string
    quantity: int
    limit_price: int            # 원하는 체결 가격 (원)
}
```

- **매수 조건**: `current_price ≤ limit_price` 시 체결
- **매도 조건**: `current_price ≥ limit_price` 시 체결
- **체결 가격**: `limit_price`가 아닌 **체결 시점의 current_price** (항상 플레이어에게 유리하거나 동일)
- 당일 장 마감 시 미체결 주문은 자동 만료 (EXPIRED)
- 플레이어가 수동 취소 가능 (CANCELLED)

##### 1-3. 예약 시스템 (지정가 전용)

지정가 주문 제출 시 자금/수량을 **선점 예약**한다:

**매수 예약**:
```
reserved_cash = limit_price × quantity
sim_deduct(reserved_cash)           # 예약 시점에 선차감
// 체결 시:
refund = reserved_cash - (filled_price × quantity)
sim_add(refund)                     # 유리한 가격 차액 환불
// 만료/취소 시:
sim_add(reserved_cash)              # 전액 복원
```

**매도 예약**:
```
locked_quantity = quantity
// 해당 종목의 가용 수량에서 잠금
// 체결 시: 잠금 해제 + 정상 매도 처리
// 만료/취소 시: 잠금 해제
```

이 방식으로 지정가 주문 간 자원 충돌을 방지한다.

**원자성 보장**: 잔액 검증(`available_cash ≥ reserved_cash`)과 차감(`sim_deduct`)은
단일 원자적 연산으로 수행한다. 싱글스레드 게임 루프에서 자연스럽게 보장되며,
검증-차감 사이에 다른 주문이 끼어들 수 없다.

#### 규칙 2. 주문 데이터 구조

```
Order {
    order_id: int               # 자동 증가 ID
    order_type: MARKET | LIMIT
    side: BUY | SELL
    stock_id: string
    quantity: int
    limit_price: int | null     # LIMIT만

    status: PENDING | FILLED | CANCELLED | EXPIRED | REJECTED
    reject_reason: string | null

    submitted_tick: int
    submitted_day: int
    submitted_market_state: string  # 제출 시점 시장 상태 (MARKET_OPEN / PRE_MARKET / PAUSED)
    filled_price: int | null    # 체결가
    filled_tick: int | null
    reserved_cash: int          # 매수 예약 금액. LIMIT: limit_price×qty. PRE_MARKET MARKET: ceil(price×1.15)×qty. MARKET_OPEN MARKET: 0
    locked_quantity: int        # 매도 예약 수량. LIMIT SELL: quantity. PRE_MARKET MARKET SELL: quantity. PAUSED MARKET SELL: 0 (재개 후 즉시 체결이므로 잠금 불필요). MARKET_OPEN MARKET SELL: 0 (즉시 체결)
}
```

#### 규칙 3. 주문 검증 (10단계)

주문 제출 시 순서대로 검증하며, 첫 번째 실패 시 REJECTED 처리:

```
1. 시장 상태 검증
   - MARKET_OPEN 또는 PAUSED: 허용
   - PRE_MARKET: 허용 (장 시작 시 처리)
   - MARKET_CLOSED / DAY_TRANSITION / SEASON_END: REJECTED ("장이 열려 있지 않습니다")

2. 종목 존재 검증
   - stock_id가 종목 DB에 존재하지 않으면 REJECTED

3. 수량 검증
   - quantity ≤ 0: REJECTED ("수량은 1 이상이어야 합니다")
   - quantity가 정수 아님: REJECTED

4. 스킬 해금 검증
   - LIMIT 주문인데 TR1 미해금 (`is_skill_unlocked("TR1")` = false): REJECTED ("지정가 주문이 해금되지 않았습니다")

5. 미체결 주문 한도 검증 (LIMIT만)
   - pending_limit_orders.count >= max_pending_limit_orders: REJECTED ("미체결 주문 한도 초과")

6. 포트폴리오 슬롯 검증 (BUY만)
   - effective_holding_count = get_holding_count()
       + count(pre_market_queue 및 paused_queue 내 BUY 주문 중
         해당 stock_id가 현재 보유에도 없고 큐 내 선행 주문에도 없는 신규 종목)
   - 새 종목 매수 && effective_holding_count >= max_holdings: REJECTED ("보유 종목 한도 초과")
   - 이미 보유 종목 또는 큐 내 선행 BUY에 동일 종목 존재: 슬롯 검증 면제

7. 잔액 검증 (BUY만)
   - MARKET (MARKET_OPEN/PAUSED): current_price × quantity > available_cash → REJECTED ("잔액 부족")
   - MARKET (PRE_MARKET): ceil(current_price × (1 + pre_market_buffer_pct)) × quantity > available_cash → REJECTED ("잔액 부족")
   - LIMIT: limit_price × quantity > available_cash → REJECTED ("잔액 부족")
   - available_cash = get_sim_cash() (이미 다른 지정가/PRE_MARKET 예약에 차감된 금액은 제외된 상태)

8. 보유 수량 검증 (SELL만)
   - quantity > available_quantity → REJECTED ("보유 수량 부족")
   - available_quantity = holding.quantity - locked_quantity (지정가 매도로 잠긴 수량 제외)

9. 지정가 유효성 (LIMIT만)
   - limit_price ≤ 0: REJECTED

9-1. 상/하한가 검증 (LIMIT만)
   - 가격 엔진의 `get_daily_limits(stock_id)` → `{upper, lower}` 조회
   - limit_price > upper: REJECTED ("상한가(N원) 초과")
   - limit_price < lower: REJECTED ("하한가(N원) 미만")
   - 상/하한가 = 전일 종가 ±30% (가격 엔진 GDD 규칙 2-3 참조)

9-2. 호가 단위 검증 (LIMIT만)
   - `get_tick_size(limit_price)`로 호가 단위 조회
   - limit_price % tick_size ≠ 0: REJECTED ("지정가가 호가 단위(N원)에 맞지 않습니다")

> **UI 레벨 클램프**: 트레이딩 스크린의 지정가 입력 SpinBox는 `min_value = lower`,
> `max_value = upper`, `step = tick_size`로 설정하여 UI에서 선제적으로 범위를
> 제한한다. 8-1, 8-2 검증은 안전망(validation-level safety net)으로 동작한다.
```

#### 규칙 4. 체결 처리

##### 4-1. 시장가 체결

```
on_tick (틱 처리 순서 3번째):
    for order in market_order_queue:
        filled_price = price_engine.get_current_price(order.stock_id)

        if order.side == BUY:
            total_cost = filled_price × order.quantity
            if order.submitted_market_state == PRE_MARKET:
                # PRE_MARKET 주문: 제출 시 이미 예약금(reserved_cash) 차감됨
                refund = order.reserved_cash - total_cost
                if refund > 0: currency.sim_add(refund)
                elif refund < 0: currency.sim_deduct(-refund)
            else:
                currency.sim_deduct(total_cost)
            portfolio.add_holding(order.stock_id, order.quantity, filled_price)
        else:  # SELL
            total_proceeds = filled_price × order.quantity
            currency.sim_add(total_proceeds)
            portfolio.remove_holding(order.stock_id, order.quantity, filled_price)

        order.status = FILLED
        order.filled_price = filled_price
        order.filled_tick = current_tick
        emit on_order_filled(order)
```

##### 4-2. 지정가 체결

```
on_tick:
    for order in pending_limit_orders:
        current_price = price_engine.get_current_price(order.stock_id)

        should_fill = false
        if order.side == BUY and current_price <= order.limit_price:
            should_fill = true
        if order.side == SELL and current_price >= order.limit_price:
            should_fill = true

        if should_fill:
            if order.side == BUY:
                actual_cost = current_price × order.quantity
                refund = order.reserved_cash - actual_cost
                if refund > 0:
                    currency.sim_add(refund)
                portfolio.add_holding(order.stock_id, order.quantity, current_price)
            else:  # SELL
                // 잠금 해제: Order의 locked_quantity를 0으로 설정
                order.locked_quantity = 0
                total_proceeds = current_price × order.quantity
                currency.sim_add(total_proceeds)
                portfolio.remove_holding(order.stock_id, order.quantity, current_price)

            order.status = FILLED
            order.filled_price = current_price
            order.filled_tick = current_tick
            emit on_order_filled(order)
```

##### 4-3. 손절/익절 자동 주문 처리 (TR2)

```
on_tick (지정가 체결 4-2 직후):
    StopTakeSystem.check_and_trigger(market_state)
    # 내부 처리:
    #   for each (stock_id, setting) in _stop_take_settings:
    #       if not setting.enabled or market_state != MARKET_OPEN: skip
    #       current_price = PriceEngine.get_current_price(stock_id)
    #       if current_price <= setting.stop_loss_price → submit_market_order("SELL", ...)
    #       elif current_price >= setting.take_profit_price → submit_market_order("SELL", ...)
```

이 단계는 지정가 체결(4-2) 이후에 실행되어 지정가가 항상 우선 처리됨을 구조적으로 보장한다.
상세 설계: `design/gdd/stop-loss-take-profit.md`.

##### 4-4. PRE_MARKET 주문 처리

##### 4-3a. PRE_MARKET 큐

PRE_MARKET 동안 제출된 주문은 `pre_market_queue`에 보관. `on_market_open` 시
첫 틱(틱 0)에서 시장가 주문부터 순서대로 처리.

**PRE_MARKET 시장가 체결 절차**:
```
for order in pre_market_queue (FIFO):
    filled_price = price_engine.get_current_price(order.stock_id)  # 틱 0 가격

    if order.order_type == MARKET and order.side == BUY:
        actual_cost = filled_price × order.quantity
        if actual_cost > order.reserved_cash:
            // 버퍼 초과 (15%+ 급등) — 거절
            currency.sim_add(order.reserved_cash)   # 예약금 전액 복원
            order.status = REJECTED
            order.reject_reason = "개장 가격 급변으로 체결 불가"
            continue
        refund = order.reserved_cash - actual_cost
        currency.sim_add(refund)                    # 차액 환불
        portfolio.add_holding(order.stock_id, order.quantity, filled_price)
        order.status = FILLED

    elif order.order_type == MARKET and order.side == SELL:
        // 매도: 제출 시 locked_quantity로 수량 잠금됨 (reserved_cash = 0)
        proceeds = filled_price × order.quantity
        currency.sim_add(proceeds)
        portfolio.remove_holding(order.stock_id, order.quantity)
        order.status = FILLED
        // locked_quantity 자동 해제 (주문 FILLED 전환 시)

    elif order.order_type == LIMIT:
        // 지정가는 pending_limit_orders로 이관, 이후 틱별 체결 체크
        pending_limit_orders.add(order)
```

슬롯 재검증: 신규 종목이고 `get_holding_count() >= max_holdings`이면 REJECTED
("보유 종목 한도 초과") + 예약금 복원. FIFO 순서로 처리하므로 앞 주문 체결로
holding_count가 증가한 후 뒷 주문이 슬롯 검증에 실패할 수 있다.

##### 4-3b. PAUSED 큐

PAUSED 중 제출된 주문은 `paused_queue`에 보관. 재개 후 **바로 다음 틱**에서
처리. PAUSED는 MARKET_OPEN의 하위 상태이므로 가격 차이가 적지만,
재개 틱에서 가격이 변동될 수 있다.

두 큐는 별도 관리되며, `submitted_market_state` 필드로 구분된다.

#### 규칙 5. 주문 취소

```
cancel_order(order_id):
    order = find_order(order_id)
    if order.status != PENDING: return false

    if order.side == BUY:
        currency.sim_add(order.reserved_cash)   # 예약 금액 복원
    else:
        order.locked_quantity = 0   # 잠금 해제 (Order Engine이 자체 관리)

    order.status = CANCELLED
    return true
```

#### 규칙 6. 장 마감 처리

```
on_market_close:
    for order in pending_limit_orders:
        if order.side == BUY:
            currency.sim_add(order.reserved_cash)
        else:
            order.locked_quantity = 0   # 잠금 해제 (Order Engine이 자체 관리)
        order.status = EXPIRED
```

모든 미체결 지정가 주문을 만료 처리하고 예약/잠금을 전액 복원한다.

### States and Transitions

#### 주문 상태

| State | Description | Transition |
|-------|-------------|------------|
| **PENDING** | 지정가 주문 접수됨. 체결 조건 대기 중 | → FILLED (조건 충족) / CANCELLED (수동 취소) / EXPIRED (장 마감) |
| **FILLED** | 체결 완료. 최종 상태 | — |
| **CANCELLED** | 플레이어 취소. 최종 상태 | — |
| **EXPIRED** | 장 마감으로 자동 만료. 최종 상태 | — |
| **REJECTED** | 검증 실패. 최종 상태 | — |

시장가 주문은 PENDING을 거치지 않고 즉시 FILLED 또는 REJECTED.

#### 시스템 상태

| State | Description | Transition |
|-------|-------------|------------|
| **INACTIVE** | 장 마감/시즌 종료. 시장가 거부, 지정가 거부 | → PRE_ACCEPTING (프리마켓 시작) / ACCEPTING (장 시작) |
| **ACCEPTING** | 장 열림. 모든 주문 접수 및 체결 | → INACTIVE (장 마감 시) |
| **PRE_ACCEPTING** | 프리마켓. 주문 접수만 가능, 체결은 장 시작까지 대기 | → ACCEPTING (장 시작 시) |

**Game Clock 상태와의 매핑**:

| Game Clock 상태 | Order Engine 상태 | 비고 |
|----------------|------------------|------|
| `PRE_MARKET` | `PRE_ACCEPTING` | 주문 접수만, 체결 대기 |
| `MARKET_OPEN` | `ACCEPTING` | 전체 기능 활성 |
| `PAUSED` | `ACCEPTING` | MARKET_OPEN의 하위 상태. 주문 접수 가능, 체결은 재개 시 |
| `MARKET_CLOSED` | `INACTIVE` | 주문 거부 |
| `DAY_TRANSITION` | `INACTIVE` | 주문 거부 |
| `WEEK_END` | `INACTIVE` | 주문 거부 (주간 리포트 중) |
| `SEASON_END` | `INACTIVE` | 주문 거부 |

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **재화 시스템** | 주문 엔진이 의존 | `get_sim_cash()` — 잔액 확인. `sim_deduct(amount)` — 매수 비용/예약 차감. `sim_add(amount)` — 매도 대금/예약 복원/환불 |
| **가격 엔진** | 주문 엔진이 의존 | `get_current_price(stock_id)` — 시장가 체결가 / 지정가 조건 체크 |
| **종목 DB** | 주문 엔진이 의존 | `stock_exists(stock_id)` — 종목 존재 검증 |
| **포트폴리오 관리** | 양방향 | `get_holding_count()` — 슬롯 검증. `get_holding(stock_id).quantity` — 보유 수량 조회 (매도 가용 수량은 Order Engine이 `quantity - locked_quantity`로 자체 계산). `add_holding()` / `remove_holding()` — 체결 후 **직접 메서드 호출** |
| **스킬 트리** | 주문 엔진이 참조 | `is_skill_unlocked("TR1")` — 지정가 해금. `is_skill_unlocked("TR2")` — 손절/익절 해금. `get_max_holdings()` — 최대 보유 종목 수. (향후: `is_skill_unlocked("TR3/TR4")` — 공매도/레버리지) |
| **StopTakeSystem** | 주문 엔진이 호출 | `check_and_trigger(market_state)` — 틱 4-3 단계. `on_holding_cleared(stock_id)` — 보유 종목 소멸 시 설정 정리 |
| **게임 시계** | 주문 엔진이 의존 | `on_tick` — 지정가 체결 체크. `on_market_open/close` — 상태 전환 |
| **트레이딩 스크린** | UI가 주문 엔진에 의존 | `submit_order(order)` — 주문 제출. `cancel_order(order_id)` — 취소. `get_pending_orders()` — 미체결 목록. `get_total_reserved_cash()` — 전체 미체결 매수 예약금 합계 (`Σ pending_buy.reserved_cash` — 지정가 + PRE_MARKET 시장가 포함) |
| **경험치 시스템** | 경험치가 참조 | `on_order_filled` — 거래 기반 경험치 산출 |
| **오디오 시스템** | 오디오가 참조 | `on_order_filled` — 체결음 재생 |

## Formulas

### F1. 시장가 매수 비용

```
total_cost = current_price × quantity
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `current_price` | int | 1+ | 가격 엔진 | 체결 시점 현재가 |
| `quantity` | int | 1+ | 플레이어 입력 | 매수 수량 |
| `total_cost` | int | 1+ | calculated | 총 매수 금액 |

**예시**: 스타칩 10주 × 65,000원 = 650,000원

### F2. 지정가 매수 예약 및 환불

```
reserved_cash = limit_price × quantity
refund = reserved_cash - (filled_price × quantity)
```

**예시**: 스타칩 지정가 63,000원 × 10주 = 630,000원 예약
→ 62,500원에 체결 시 refund = 630,000 - 625,000 = 5,000원 환불

### F2b. PRE_MARKET 시장가 매수 예약 및 환불

```
buffered_price = ceil(current_price × (1 + pre_market_buffer_pct))
reserved_cash = buffered_price × quantity
refund = reserved_cash - (filled_price × quantity)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `current_price` | int | 1+ | 가격 엔진 (전일 종가) | PRE_MARKET 시점 현재가 |
| `pre_market_buffer_pct` | float | 0.05~0.30 | config | 가격 변동 버퍼율 (기본 15%) |
| `buffered_price` | int | 1+ | calculated | 예약 기준가 |
| `filled_price` | int | 1+ | 가격 엔진 (틱 0) | 실제 체결가 |

**예시**: 스타칩 전일종가 65,000원, buffer 15%, 15주
- `buffered_price = ceil(65,000 × 1.15) = 74,750원`
- `reserved_cash = 74,750 × 15 = 1,121,250원`
- 틱 0 체결가 66,300원 → `refund = 1,121,250 - 994,500 = 126,750원`

### F3. 최대 매수 가능 수량

```
max_buyable = floor(available_cash / reference_price)
```

- `reference_price`: MARKET_OPEN 시장가면 `current_price`, PRE_MARKET 시장가면 `ceil(current_price × (1 + pre_market_buffer_pct))`, 지정가면 `limit_price`
- UI에서 "최대" 버튼 클릭 시 이 값으로 수량 자동 입력

**예시**: available_cash=500,000, current_price=65,000
→ `max_buyable = floor(500,000 / 65,000) = 7주`

### F4. 수수료 (향후)

```
fee = floor(trade_value × fee_rate)
// MVP: fee_rate = 0
```

### 변수 마스터 테이블

| Variable | Default | Range | Owner | Description |
|----------|---------|-------|-------|-------------|
| `fee_rate` | 0.0 | 0~0.003 | config | 매매 수수료율. MVP=0 |
| `max_pending_limit_orders` | 10 | 3~20 | config | 동시 미체결 지정가 한도 |
| `limit_order_expiry` | DAILY | DAILY (MVP 고정. GTC 확장은 Open Questions 참조) | config | 지정가 만료 정책. MVP=당일 |
| `limit_price_warn_range` | 0.30 | 0.10~0.50 | config | 지정가 경고 범위 (현재가 대비 ±%) |
| `pre_market_buffer_pct` | 0.15 | 0.05~0.30 | config | PRE_MARKET 시장가 매수 예약 버퍼율 |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 잔액 부족으로 매수 불가 | REJECTED + "잔액 부족" 메시지. 잔액 불변 | 빚 매수 불가 |
| 보유 한도 초과 (새 종목 매수) | REJECTED + "보유 종목 한도 초과" | 스킬 트리 게이팅 |
| 이미 보유 종목 추가 매수 | 슬롯 검증 면제. 잔액만 확인 | 물타기 허용 |
| 보유 수량 초과 매도 | REJECTED + "보유 수량 부족" | 공매도 불가 (MVP) |
| 일시정지 중 주문 제출 | 접수. 재개 후 첫 틱에 처리 | PAUSED 중 분석→주문 허용 |
| PAUSED 중 시장가 매도 제출 | locked_quantity = 0. 재개 후 첫 틱에 즉시 체결 | PAUSED는 MARKET_OPEN 하위 상태이므로 재개 시 즉시 체결 보장. 잠금 불필요 |
| 장 마감 후 주문 제출 | REJECTED + "장이 열려 있지 않습니다" | 장 마감 = 매매 중단 |
| PRE_MARKET 주문 | 큐에 보관. 장 시작 첫 틱(틱 0)에 처리 | 프리마켓 분석 후 선제 주문 |
| 장 마감 시 미체결 지정가 | 전량 EXPIRED. 예약 금액/잠금 수량 전액 복원 | 일일 리셋 원칙 |
| 지정가 매수 체결 시 현재가 < limit_price | filled_price = current_price (더 유리한 가격) | 플레이어 유리 원칙 |
| 지정가 매도 잠금 중 같은 종목 추가 매도 | available_quantity = quantity - locked_quantity. 가용분만 허용 | 이중 매도 방지 |
| 같은 틱에 시장가 + 지정가 동시 체결 | 시장가 먼저 처리, 지정가 후처리 | 시장가 우선 원칙. 동일 종목의 경우 잔액/수량 계산에 영향. 시장가 먼저 처리하여 잔액이 충분한 상태에서 지정가 체결 여부를 판단한다. |
| 가격 급변으로 지정가 조건 순간 통과 | 해당 틱에 체결 확정. 다음 틱 가격 무관 | "틱이 진실" 원칙 |
| max_pending_limit_orders 초과 | REJECTED + "미체결 주문 한도 초과" | 주문 남발 방지 |
| 시즌 종료 시 미체결 주문 | 장 마감 처리(EXPIRED) 후 시즌 종료 순서 보장 | 정산 선행 |
| PRE_MARKET 시장가 매수 → 야간 이벤트로 가격 상승 | 예약금 = `ceil(전일종가 × 1.15) × quantity`로 선차감됨. 틱 0 체결가가 예약금 범위 내이면 정상 체결 + 차액 환불. 예: 전일종가 65,000 → 예약금 74,750×15=1,121,250원 선차감 → 틱 0 가격 66,300원 → 체결 994,500원 → 126,750원 환불. 실제 증권사의 상한가 예약 방식과 동일 | 가격 변동에도 체결 보장 (버퍼 내) |
| PRE_MARKET 시장가 매수 → 버퍼 초과 급등 (15%+) | 예약금 범위 초과 → REJECTED ("개장 가격 급변으로 체결 불가") + 예약금 전액 복원. 극히 드문 케이스 (15% 버퍼는 야간 복수 이벤트에도 대응) | 버퍼 초과 시 안전 거절. 복수 주문도 예약금이 각각 선차감되므로 자원 충돌 없음 |
| PRE_MARKET 복수 시장가 매수 → 잔액 부족 | 각 주문마다 예약금이 제출 시점에 선차감되므로, 잔액 부족 시 **제출 시점에** REJECTED. 틱 1이 아닌 주문 제출 시 즉시 차단됨 | 예약 방식으로 기존 "틱 1 서프라이즈 거절" 문제 해결 |
| PRE_MARKET에서 슬롯 한도까지 신규 종목 주문 제출 후 추가 신규 종목 주문 | PRE_MARKET 주문 제출 시 `effective_holding_count`로 슬롯 검증 — 큐 내 미체결 신규 종목도 카운트에 포함. 예: max_holdings=3, 현재 보유 1종목, 큐에 신규 2종목 → effective=3 → 추가 신규 종목 REJECTED. 이미 큐에 있는 종목의 추가 매수는 슬롯 면제 | 큐 반영 슬롯 검증. 체결 시점 서프라이즈 방지 |
| **ETF 종목 주문 — P3 미해금** | REJECTED + "섹터 ETF 미해금" | P3 스킬 해금 게이팅 |
| **ETF 종목 주문 — P3 해금, 시장가** | 슬리피지 없음. 즉시 체결 (현재가 = 체결가). 지정가/손절익절 주문도 허용하나 ETF는 PriceEngine이 직접 가격 결정하므로 슬리피지 개념 없음 | ETF는 실물 지수 추종 상품 — 가격 왜곡 없음 |
| **ETF 종목 주문 — TR3(공매도) 또는 TR4(레버리지) 시도** | REJECTED + "ETF는 공매도/레버리지 불가" | ETF 상품 특성상 단순 매수/매도만 허용 |
| VI 발동 중 해당 종목 지정가 체결 | VI 정지 기간 동안 해당 종목 가격이 동결되므로 지정가 조건 체크는 계속하되, 가격 변동이 없어 새로운 체결은 사실상 없음. VI 해제 후 첫 틱에 가격이 갱신되면 조건 재평가 | 가격 동결 = 체결 조건 변화 없음 |
| CB Stage 1 정지 중 PRE_MARKET 큐 및 지정가 처리 | CB 발동 시 Order Engine은 ACCEPTING 상태를 유지하나, 가격 엔진이 전 종목 가격을 동결하므로 시장가/지정가 모두 **체결 유예**. 정지 해제 후 첫 틱에 가격 갱신 → 큐 순서대로 처리 재개. 단, CB가 틱 0에 발동되는 경우(극히 드문 케이스): pre_market_queue는 가격 엔진 갱신 후 처리되므로, 갱신된 가격으로 체결 시도 → CB 발동으로 가격 동결 → 다음 틱으로 이월 | CB는 가격 엔진 레벨에서 동결. 주문 엔진은 간접적으로 유예됨 |
| CB Stage 2 (조기 마감) 시 미체결 주문 | 즉시 장 마감 처리: 전체 미체결 지정가 EXPIRED + 예약/잠금 복원. pre_market_queue에 잔여 주문이 있으면 REJECTED ("장 조기 마감") + 예약금 복원 | Stage 2 = 당일 거래 종료. 정산 안전 우선 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| 재화 시스템 | 주문 엔진이 의존 | 잔액 확인/차감/추가. **Hard** |
| 가격 엔진 | 주문 엔진이 의존 | 현재가로 체결. **Hard** |
| 종목 DB | 주문 엔진이 의존 | 종목 존재 검증. **Hard** |
| 포트폴리오 관리 | 양방향 | 슬롯/수량 검증 + 체결 결과 전달. **Hard** |
| 게임 시계 | 주문 엔진이 의존 | 틱 처리, 시장 상태 판단. **Hard** |
| 스킬 트리 | 주문 엔진이 참조 | 주문 유형 해금, max_holdings. **Soft** (미구현 시 TR0 기본) |
| 트레이딩 스크린 | UI가 주문 엔진에 의존 | 주문 제출/취소/조회. **Soft** |
| 경험치 시스템 | 경험치가 참조 | on_order_filled 이벤트. **Soft** |
| 오디오 시스템 | 오디오가 참조 | on_order_filled 이벤트. **Soft** |
| 포트폴리오 UI | 간접 참조 | `get_total_reserved_cash()` → PortfolioManager 캐시 경유로 예약금 표시. **Soft** |
| 시즌/대회 관리 | 시즌이 참조 | `expire_all_pending()` — 시즌 종료 강제 청산 시퀀스 Step ①. **Soft** (V-Slice) |
| 뉴스/이벤트 시스템 | 설계 참조 (런타임 의존 없음) | `pre_market_buffer_pct = 0.15`는 `news-events.md`의 MEGA 이벤트 `max_single_impact = 0.15` (15%)에 맞춰 설계됨. 런타임 API 호출 없음. `max_single_impact` 변경 시 `pre_market_buffer_pct`도 동일하게 갱신 필요. **Design-time Soft** |
| 세이브/로드 | 설계 참조 | 예약금·잠금 수량은 장 마감 시 전량 초기화되므로 시즌 간 저장 불필요. `save-load.md §3-4` 협의 결과. **Design-time Note** |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `fee_rate` | 0% | 0~0.3% | 거래 비용 증가. 단타 억제 | 자유로운 매매 |
| `max_pending_limit_orders` | 10 | 3~20 | 복잡한 전략 가능 | 주문 관리 단순화 |
| `limit_order_expiry` | DAILY | DAILY | — | — |
| `limit_price_warn_range` | 30% | 10~50% | 비현실적 지정가 허용 | 근접 지정가만 허용 |
| `pre_market_buffer_pct` | 0.15 (15%) | 0.05~0.30 | PRE_MARKET 시장가 예약 여유 증가 → 거절 빈도 감소, 자금 묶임 증가 | 예약 여유 감소 → 거절 빈도 증가, 자금 효율 증가. 근거: MEGA `max_single_impact`(15%) 대응 |

## Acceptance Criteria

- [x] 시장가 매수 시 current_price × quantity가 sim_cash에서 정확히 차감됨
- [x] 시장가 매도 시 current_price × quantity가 sim_cash에 정확히 추가됨
- [x] 지정가 매수 제출 시 limit_price × quantity가 선차감됨
- [ ] 지정가 체결 시 유리한 가격 차액이 정확히 환불됨 — S10-12 매뉴얼 QA 대기
- [x] 지정가 만료/취소 시 예약 금액이 전액 복원됨
- [x] 지정가 매도 제출 시 수량이 잠금 처리됨
- [x] 잠금 수량이 다른 매도 주문에서 가용 수량에서 제외됨
- [x] 잔액 부족 시 REJECTED 처리되고 잔액 불변
- [ ] 보유 한도 초과 시 REJECTED (이미 보유 종목 추가 매수는 허용) — S10-12 매뉴얼 QA 대기
- [ ] 장 마감 시 전체 미체결 주문 EXPIRED + 예약/잠금 복원 — S10-12 매뉴얼 QA 대기
- [x] PAUSED 중 주문 접수 → 재개 후 첫 틱에 정상 체결
- [ ] PRE_MARKET 주문 → 장 시작 첫 틱(틱 0)에 정상 체결되며, 예약금 차액이 정확히 환불됨 — S10-12 매뉴얼 QA 대기
- [x] 체결 시 포트폴리오에 정확히 반영 (add_holding / remove_holding)
- [x] 모든 금액이 정수 (원 단위)
- [ ] 성능: 10개 종목 전체 지정가 체크 + 체결 처리 1ms 이내 — S10-12 프로파일러 검증 대기

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|------------|
| 수수료 도입 시점 및 요율 | systems-designer | 확장 시점 | MVP=0%. 향후 결정 |
| 지정가 유효기간 확장 (GTC 등) | game-designer | V-Slice | MVP=DAILY만 |
| 손절/익절 자동 주문 구현 상세 | game-designer | TR2 구현 시 | **Resolved (2026-04-15)** — `design/gdd/stop-loss-take-profit.md` 참조. 틱 처리 4-3 단계로 구현. |
| 공매도 로직 (마이너스 보유, 숏 스퀴즈 등) | systems-designer | TR3 구현 시 | **Resolved (2026-04-17)** — `design/gdd/short-selling.md` 참조. SELL_SHORT/BUY_TO_COVER 주문 유형 추가. 틱 처리 순서: 공매도 margin_ratio 감시는 주문 체결(3단계) 직후(4단계)에 ShortSellingSystem이 수행. |
| AI 경쟁자의 주문 처리 — 같은 엔진 사용 여부 | game-designer | AI 경쟁자 GDD 시 | 미정 |
| 슬리피지 도입 — 대량 주문 시 평균 체결가 악화 모델. 스킬 해금(TR3+)과 연동 검토. 가격 관찰자 모델 전환 필요 | game-designer + systems-designer | Post-MVP | MVP=없음. 외부 감사 권고 (2026-04-03) |
| 볼륨 기반 지정가 체결 우선순위 — 거래량 부족 시 미체결. 미체결 시 "가격 도달 — 대기 중" 피드백 추가 | game-designer + ux-designer | Post-MVP | MVP=가격 조건만 체크. 외부 감사 권고 (2026-04-03) |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 기능 | 진입점 |
|------|--------|
| 시장가/지정가 주문 접수 | `trading_screen.gd._submit_order()` → `OrderEngine.submit_order(side, stock_id, qty, type, price)` |
| 틱 체결 처리 | `game_clock.gd._process_tick()` → `OrderEngine._on_tick(tick, day, week)` (틱 순서 3번째) |
| 주문 취소 | `trading_screen.gd` → `OrderEngine.cancel_order(order_id)` |
| 시즌 종료 전량 취소 | `season_manager.gd._on_season_end()` → `OrderEngine.cancel_all_pending_orders()` |

### 호출 경로

- [x] `OrderEngine.submit_order(side, stock_id, qty, type, price) -> Dictionary` 존재
- [x] `OrderEngine.cancel_order(order_id) -> bool` 존재
- [x] `OrderEngine.cancel_all_pending_orders()` 존재
- [x] `OrderEngine.get_season_trade_count() -> int` 존재
- [x] `OrderEngine.get_order_history(limit) -> Array[Dictionary]` 존재
- [x] `OrderEngine.on_order_filled(order)` 시그널 존재
- [x] `OrderEngine.reset()` 존재
- [x] `ORDER_HISTORY_MAX_SIZE = 500` 상수 존재 (S3-09 cap 추가)

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 | 상태 |
|----|------------|------------|------|
| 시장가 매수 체결 | `tests/unit/test_order_engine.gd` | `test_market_buy_fills_at_current_price()` | ✅ |
| 지정가 체결 조건 | `tests/unit/test_order_engine.gd` | `test_limit_order_fills_when_price_reached()` | ✅ |
| 잔액 부족 거부 | `tests/unit/test_order_engine.gd` | `test_buy_rejected_insufficient_cash()` | ✅ |
| API 계약 | `tests/unit/test_api_contracts.gd` | `test_order_engine_api()` | ✅ |

### 빌드 검증

- [x] 바이너리 실행 확인: QA Lead 서명 — 내부 감사 2026-04-15 (Alpha 완료 빌드, SCRIPT ERROR 없음)
