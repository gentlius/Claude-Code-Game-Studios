# 주문 처리 엔진 (Order Engine)

> **Status**: In Design
> **Author**: user + game-designer
> **Last Updated**: 2026-03-26
> **Implements Pillar**: 판단이 곧 실력 (Judgment is King), 짧고 굵게 (Quick & Punchy)

## Overview

주문 처리 엔진은 플레이어의 매수/매도 주문을 접수, 검증, 체결하는 Core 시스템이다.
트레이딩 스크린에서 제출된 주문을 받아 잔액/보유량 검증 후 체결하고, 재화 시스템과
포트폴리오 관리 시스템에 결과를 전파한다.

게임 시계의 틱 처리 순서에서 3번째로 실행된다 (뉴스/이벤트 → 가격 엔진 →
**주문 처리 엔진**). 가격 엔진이 갱신한 현재가 기준으로 주문을 체결하므로, 뉴스
발생 후 변동된 가격에 주문이 처리된다.

MVP에서는 두 가지 주문 유형을 지원한다: 시장가 주문(Lv1 기본) — 현재가로 즉시
체결, 지정가 주문(Lv2 해금) — 조건 충족 시 자동 체결. 손절/익절(Lv3), 공매도(Lv4),
레버리지(Lv5)는 MVP 범위 밖이다. 플레이어의 매매는 가격에 영향을 주지 않는다
(가격 관찰자 모델).

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

##### 1-1. 시장가 주문 (Market Order) — Lv1 기본

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

##### 1-2. 지정가 주문 (Limit Order) — Lv2 해금

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
    reserved_cash: int          # 매수 예약 금액 (MARKET은 0)
    locked_quantity: int        # 매도 예약 수량 (MARKET은 0)
}
```

#### 규칙 3. 주문 검증 (8단계)

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
   - LIMIT 주문인데 거래 스킬 Lv2 미해금: REJECTED ("지정가 주문이 해금되지 않았습니다")

4.5. 미체결 주문 한도 검증 (LIMIT만)
   - pending_limit_orders.count >= max_pending_limit_orders: REJECTED ("미체결 주문 한도 초과")

5. 포트폴리오 슬롯 검증 (BUY만)
   - 새 종목 매수 && holding_count >= max_holdings: REJECTED ("보유 종목 한도 초과")
   - 이미 보유 종목 추가 매수: 슬롯 검증 면제

6. 잔액 검증 (BUY만)
   - MARKET: current_price × quantity > available_cash → REJECTED ("잔액 부족")
   - LIMIT: limit_price × quantity > available_cash → REJECTED ("잔액 부족")
   - available_cash = get_sim_cash() (이미 다른 지정가에 예약된 금액은 차감된 상태)

7. 보유 수량 검증 (SELL만)
   - quantity > available_quantity → REJECTED ("보유 수량 부족")
   - available_quantity = holding.quantity - locked_quantity (지정가 매도로 잠긴 수량 제외)

8. 지정가 유효성 (LIMIT만)
   - limit_price ≤ 0: REJECTED
   - 매수: limit_price < current_price × 0.7 → 경고 확인 대화상자 표시 ("지정가가 현재가와 30% 이상 차이납니다. 계속하시겠습니까?" [확인/취소]). 거부는 아님
   - 매도: limit_price > current_price × 1.3 → 동일 경고 확인 대화상자
```

#### 규칙 4. 체결 처리

##### 4-1. 시장가 체결

```
on_tick (틱 처리 순서 3번째):
    for order in market_order_queue:
        filled_price = price_engine.get_current_price(order.stock_id)

        if order.side == BUY:
            total_cost = filled_price × order.quantity
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

##### 4-3. PRE_MARKET 주문 처리

##### 4-3a. PRE_MARKET 큐

PRE_MARKET 동안 제출된 주문은 `pre_market_queue`에 보관. `on_market_open` 시
첫 틱(틱 1)에서 시장가 주문부터 순서대로 처리. PRE_MARKET 시장가 주문은 **틱 1의
가격으로 체결**되며, 제출 시점 가격과 다를 수 있다 (M5 대응: 체결 시 잔액 재검증,
부족 시 REJECTED).

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
| **스킬 트리** | 주문 엔진이 참조 | `get_trading_level()` — 주문 유형 해금 여부. `get_portfolio_level()` — max_holdings |
| **게임 시계** | 주문 엔진이 의존 | `on_tick` — 지정가 체결 체크. `on_market_open/close` — 상태 전환 |
| **트레이딩 스크린** | UI가 주문 엔진에 의존 | `submit_order(order)` — 주문 제출. `cancel_order(order_id)` — 취소. `get_pending_orders()` — 미체결 목록 |
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

### F3. 최대 매수 가능 수량

```
max_buyable = floor(available_cash / reference_price)
```

- `reference_price`: 시장가면 `current_price`, 지정가면 `limit_price`
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
| `limit_order_expiry` | DAILY | DAILY | config | 지정가 만료 정책. MVP=당일 |
| `limit_price_warn_range` | 0.30 | 0.10~0.50 | config | 지정가 경고 범위 (현재가 대비 ±%) |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 잔액 부족으로 매수 불가 | REJECTED + "잔액 부족" 메시지. 잔액 불변 | 빚 매수 불가 |
| 보유 한도 초과 (새 종목 매수) | REJECTED + "보유 종목 한도 초과" | 스킬 트리 게이팅 |
| 이미 보유 종목 추가 매수 | 슬롯 검증 면제. 잔액만 확인 | 물타기 허용 |
| 보유 수량 초과 매도 | REJECTED + "보유 수량 부족" | 공매도 불가 (MVP) |
| 일시정지 중 주문 제출 | 접수. 재개 후 첫 틱에 처리 | PAUSED 중 분석→주문 허용 |
| 장 마감 후 주문 제출 | REJECTED + "장이 열려 있지 않습니다" | 장 마감 = 매매 중단 |
| PRE_MARKET 주문 | 큐에 보관. 장 시작 첫 틱(틱 1)에 처리 | 프리마켓 분석 후 선제 주문 |
| 장 마감 시 미체결 지정가 | 전량 EXPIRED. 예약 금액/잠금 수량 전액 복원 | 일일 리셋 원칙 |
| 지정가 매수 체결 시 현재가 < limit_price | filled_price = current_price (더 유리한 가격) | 플레이어 유리 원칙 |
| 지정가 매도 잠금 중 같은 종목 추가 매도 | available_quantity = quantity - locked_quantity. 가용분만 허용 | 이중 매도 방지 |
| 같은 틱에 시장가 + 지정가 동시 체결 | 시장가 먼저 처리, 지정가 후처리 | 시장가 우선 원칙 |
| 가격 급변으로 지정가 조건 순간 통과 | 해당 틱에 체결 확정. 다음 틱 가격 무관 | "틱이 진실" 원칙 |
| max_pending_limit_orders 초과 | REJECTED + "미체결 주문 한도 초과" | 주문 남발 방지 |
| 시즌 종료 시 미체결 주문 | 장 마감 처리(EXPIRED) 후 시즌 종료 순서 보장 | 정산 선행 |
| PRE_MARKET 시장가 주문 → 틱 1에서 가격 변동으로 잔액 부족 | 체결 시 잔액 재검증. 부족 시 REJECTED ("잔액 부족 — 가격 변동"). 예약 금액은 시장가에 없으므로 잔액 차감 없음 | PRE_MARKET 가격은 참고용, 체결가는 틱 1 가격 |
| PRE_MARKET에서 슬롯 한도까지 신규 종목 주문 제출 후 추가 신규 종목 주문 | PRE_MARKET 주문은 제출 시 슬롯 검증 수행. 이미 한도 도달 시 즉시 REJECTED. 틱 1 체결 시에는 제출 순서대로 처리하므로 슬롯 충돌 없음 | 선입선출 원칙 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| 재화 시스템 | 주문 엔진이 의존 | 잔액 확인/차감/추가. **Hard** |
| 가격 엔진 | 주문 엔진이 의존 | 현재가로 체결. **Hard** |
| 종목 DB | 주문 엔진이 의존 | 종목 존재 검증. **Hard** |
| 포트폴리오 관리 | 양방향 | 슬롯/수량 검증 + 체결 결과 전달. **Hard** |
| 게임 시계 | 주문 엔진이 의존 | 틱 처리, 시장 상태 판단. **Hard** |
| 스킬 트리 | 주문 엔진이 참조 | 주문 유형 해금, max_holdings. **Soft** (미구현 시 Lv1 기본) |
| 트레이딩 스크린 | UI가 주문 엔진에 의존 | 주문 제출/취소/조회. **Soft** |
| 경험치 시스템 | 경험치가 참조 | on_order_filled 이벤트. **Soft** |
| 오디오 시스템 | 오디오가 참조 | on_order_filled 이벤트. **Soft** |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `fee_rate` | 0% | 0~0.3% | 거래 비용 증가. 단타 억제 | 자유로운 매매 |
| `max_pending_limit_orders` | 10 | 3~20 | 복잡한 전략 가능 | 주문 관리 단순화 |
| `limit_order_expiry` | DAILY | DAILY | — | — |
| `limit_price_warn_range` | 30% | 10~50% | 비현실적 지정가 허용 | 근접 지정가만 허용 |

## Acceptance Criteria

- [ ] 시장가 매수 시 current_price × quantity가 sim_cash에서 정확히 차감됨
- [ ] 시장가 매도 시 current_price × quantity가 sim_cash에 정확히 추가됨
- [ ] 지정가 매수 제출 시 limit_price × quantity가 선차감됨
- [ ] 지정가 체결 시 유리한 가격 차액이 정확히 환불됨
- [ ] 지정가 만료/취소 시 예약 금액이 전액 복원됨
- [ ] 지정가 매도 제출 시 수량이 잠금 처리됨
- [ ] 잠금 수량이 다른 매도 주문에서 가용 수량에서 제외됨
- [ ] 잔액 부족 시 REJECTED 처리되고 잔액 불변
- [ ] 보유 한도 초과 시 REJECTED (이미 보유 종목 추가 매수는 허용)
- [ ] 장 마감 시 전체 미체결 주문 EXPIRED + 예약/잠금 복원
- [ ] PAUSED 중 주문 접수 → 재개 후 첫 틱에 정상 체결
- [ ] PRE_MARKET 주문 → 장 시작 첫 틱에 정상 체결
- [ ] 체결 시 포트폴리오에 정확히 반영 (add_holding / remove_holding)
- [ ] 모든 금액이 정수 (원 단위)
- [ ] 성능: 10개 종목 전체 지정가 체크 + 체결 처리 1ms 이내

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|------------|
| 수수료 도입 시점 및 요율 | systems-designer | 확장 시점 | MVP=0%. 향후 결정 |
| 지정가 유효기간 확장 (GTC 등) | game-designer | V-Slice | MVP=DAILY만 |
| 손절/익절 자동 주문 구현 상세 | game-designer | Lv3 구현 시 | 향후 |
| 공매도 로직 (마이너스 보유, 숏 스퀴즈 등) | systems-designer | Lv4 구현 시 | 향후 |
| AI 경쟁자의 주문 처리 — 같은 엔진 사용 여부 | game-designer | AI 경쟁자 GDD 시 | 미정 |
