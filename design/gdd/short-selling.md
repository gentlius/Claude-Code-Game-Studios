# 공매도 (Short Selling)

> **Status**: Approved (구현 완료 2026-04-17 — 빌드 검증 대기)
> **Author**: game-designer
> **Last Updated**: 2026-04-20
> **Implements Pillar**: 판단이 곧 실력 (Judgment is King), 체감있는 성장 (Feel the Growth)
> **Skill Gate**: TR3 (선행 조건: TR2 손절/익절 + A2 보조지표)
> **See**: design/gdd/skill-tree.md, design/gdd/order-engine.md, design/gdd/portfolio-manager.md

---

## 1. Overview

공매도 시스템은 TR3 스킬을 해금한 플레이어가 보유하지 않은 주식을 빌려서 매도하고,
이후 더 낮은 가격에 매수하여 차익을 얻는 하락 베팅 메커니즘이다. 플레이어는
`SELL_SHORT` 주문을 통해 숏 포지션(short position)을 개시하며, `BUY_TO_COVER` 주문으로
포지션을 청산한다. 증거금(margin)은 초기 포지션 가치의 140%를 예수금에서 묶어두며,
`margin_ratio`가 0.2 미만으로 하락하면 강제청산이 자동 실행된다. 시즌 종료 시 미청산
숏 포지션은 자동 청산되어 정산된다. TR3 미해금 상태에서는 SELL_SHORT 주문이 즉시 거부된다.

---

## 2. Player Fantasy

바이오주 메디진이 실적 발표를 앞두고 있다. 차트는 RSI 과열 구간, MACD는 다이버전스.
뉴스는 아직 없지만 A2 보조지표가 과매수를 가리키고 있다. "이건 빠진다."

TR3 해금 후 트레이딩 화면에 새 버튼이 생긴다 — "공매도". 메디진을 10주 공매도한다.
즉시 175,000원 × 10주 × 140% = 2,450,000원이 증거금으로 묶인다. 화면에 빨간 숏
포지션 태그가 붙는다. 이제 주가가 내려갈수록 내 수익이다.

이틀 후 실적이 빗나갔다. 메디진이 -12% 급락. BUY_TO_COVER — 청산 체결음이 울린다.
차익 210,000원. 증거금이 해제되고 수익이 예수금에 더해진다.

하지만 공매도는 양날의 검이다. 가격이 올라가면 손실이 무한정 커진다. margin_ratio가
0.2 아래로 내려가는 순간 시스템이 강제청산을 실행한다. "판단이 맞아야 살아남는다."

MDA Aesthetic: **도전(Challenge)** + **숙달(Mastery)** + **표현(Expression)**.

---

## 3. Detailed Design

### 규칙 1. TR3 해금 조건 및 접근

- TR3 해금 조건: TR2(손절/익절) 해금 **+ A2(보조지표) 해금** + 스킬 포인트 1개 소비
  - A2 조건은 공매도가 리스크 분석 능력을 전제로 한다는 디자인 의도를 반영한다
- TR3 미해금 상태에서 `SELL_SHORT` 주문 제출 시 즉시 REJECTED ("공매도가 해금되지 않았습니다")
- TR3 해금은 영구적이며 시즌 리셋에 영향받지 않는다
- 해금 즉시 트레이딩 화면에 "공매도" 버튼이 활성화되며, 숏 포지션 패널이 노출된다

### 규칙 2. 주문 유형 정의

TR3는 두 가지 새로운 `side` 값을 `OrderEngine`의 주문에 추가한다:

```
side:
  SELL_SHORT   -- 보유하지 않은 주식을 빌려서 매도. 숏 포지션 개시
  BUY_TO_COVER -- 숏 포지션 청산을 위한 매수. 빌린 주식 반환
```

주문 데이터 구조는 기존 `Order`를 그대로 사용하며, `side` 필드만 확장된다.
두 주문 유형 모두 시장가(MARKET)만 지원한다. **숏 포지션에 대한 지정가 주문(TR1)은
MVP에서 지원하지 않는다.**

```
Order {
    order_id:      int
    order_type:    MARKET              # 숏 주문은 항상 시장가
    side:          SELL_SHORT | BUY_TO_COVER
    stock_id:      string
    quantity:      int                 # 양의 정수 (숏 수량)
    status:        PENDING | FILLED | CANCELLED | REJECTED
    reject_reason: string | null
    submitted_tick: int
    submitted_day:  int
    filled_price:   int | null
    filled_tick:    int | null
    reserved_cash:  int                # SELL_SHORT 시 묶인 증거금
    locked_quantity: int               # 미사용 (0 고정)
}
```

### 규칙 3. 숏 포지션 데이터 구조

각 숏 포지션은 `ShortPosition` 레코드로 `ShortSellingSystem`이 독립 관리한다.
포트폴리오 매니저의 `holdings`와는 별개 컬렉션이다.

```
ShortPosition {
    stock_id:            string   # 종목 ID
    quantity:            int      # 숏 포지션 수량 (양의 정수)
    open_price:          int      # SELL_SHORT 체결가 (= 포지션 개시가)
    initial_value:       int      # open_price × quantity (초기 포지션 가치)
    margin_deposited:    int      # 실제로 묶인 증거금 = ceil(initial_value × margin_rate)
    open_tick:           int      # 개시 틱
    open_day:            int      # 개시 거래일
    unrealized_pnl:      int      # 매 틱 갱신: (open_price - current_price) × quantity
    unrealized_pnl_pct:  float   # unrealized_pnl / initial_value × 100
    margin_ratio:        float   # (margin_deposited + unrealized_pnl) / initial_value
                                 # unrealized_pnl은 손실이면 음수
}
```

**동일 종목 중복 숏 포지션**: 동일 종목에 대해 중복 SELL_SHORT는 허용하지 않는다.
이미 숏 포지션이 존재하는 종목에 SELL_SHORT 제출 시 REJECTED ("이미 숏 포지션이 존재합니다").
수량 추가는 지원하지 않는다 (MVP 제한).

**숏 포지션과 롱 포지션 동시 보유**: 동일 종목을 롱(보유)과 숏(공매도) 동시 보유 불가.
- 롱 포지션 보유 중인 종목에 SELL_SHORT 제출 시 REJECTED ("해당 종목을 보유 중입니다. 먼저 매도하세요")
- 숏 포지션 보유 중인 종목에 일반 BUY 제출 시 REJECTED ("해당 종목의 숏 포지션을 먼저 청산하세요")

### 규칙 4. 주문 검증 (SELL_SHORT)

기존 OrderEngine 10단계 검증에 추가되는 숏 전용 검증:

```
검증 순서 (기존 검증 완료 후):

4-S1. TR3 해금 검증
    - SkillTree.has_short_selling() == false → REJECTED ("공매도가 해금되지 않았습니다")

4-S2. 시장 상태 검증
    - MARKET_OPEN만 허용. PRE_MARKET, PAUSED, MARKET_CLOSED, DAY_TRANSITION,
      SEASON_END → REJECTED ("공매도는 장 중에만 가능합니다")
    - 이유: 공매도는 증거금 실시간 감시가 필요. PRE_MARKET 예약 불가.

4-S3. 중복 포지션 검증
    - ShortSellingSystem.has_short(stock_id) == true
      → REJECTED ("이미 숏 포지션이 존재합니다")
    - PortfolioManager.get_holding(stock_id) != null
      → REJECTED ("해당 종목을 보유 중입니다. 먼저 매도하세요")

4-S4. 증거금 검증
    - required_margin = ceil(current_price × quantity × margin_rate)
    - CurrencySystem.get_sim_cash() < required_margin
      → REJECTED ("증거금 부족 (필요: {required_margin}원)")
    - 가용 예수금 = sim_cash (이미 다른 예약에 차감된 후 잔액)
```

### 규칙 5. SELL_SHORT 체결 처리

```
on SELL_SHORT 주문 검증 통과:
    open_price = PriceEngine.get_current_price(stock_id)
    initial_value = open_price × quantity
    margin_deposited = ceil(initial_value × margin_rate)  // margin_rate 기본 1.40

    // 증거금 선차감 (예수금에서 묶어둠)
    CurrencySystem.sim_deduct(margin_deposited)

    // 숏 포지션 레코드 생성
    position = ShortPosition {
        stock_id:         stock_id,
        quantity:         quantity,
        open_price:       open_price,
        initial_value:    initial_value,
        margin_deposited: margin_deposited,
        open_tick:        current_tick,
        open_day:         current_day,
        unrealized_pnl:   0,
        unrealized_pnl_pct: 0.0,
        margin_ratio:     margin_rate  // 개시 시점에는 margin_rate와 동일
    }
    ShortSellingSystem.positions[stock_id] = position

    // 매도 대금은 예수금에 추가 (빌린 주식 매도 수익)
    // 이 금액은 청산 시 매수 비용에 사용되므로 구분 목적으로 기록만 함
    // 실제 sim_cash 처리: 증거금 차감 후 매도 대금 즉시 추가 (= net은 증거금 잠금)
    sale_proceeds = open_price × quantity
    CurrencySystem.sim_add(sale_proceeds)

    order.status = FILLED
    order.filled_price = open_price
    emit on_order_filled(order)
```

> **예수금 흐름 정리**: SELL_SHORT 체결 시 `sim_deduct(margin_deposited)` 후
> `sim_add(sale_proceeds)`. 순 변동 = `sale_proceeds - margin_deposited`
> = `initial_value - ceil(initial_value × 1.40)` = 음수.
> 즉, 플레이어 예수금은 공매도 시 감소한다 (증거금 40%만큼).
>
> **예시**: 메디진 175,000원 × 10주 공매도
> - `initial_value` = 1,750,000원
> - `margin_deposited` = ceil(1,750,000 × 1.40) = 2,450,000원 차감
> - `sale_proceeds` = 1,750,000원 추가
> - 순 변동 = -700,000원 (증거금 추가 부담분)

### 규칙 6. 매 틱 평가 갱신 (margin_ratio 감시)

매 틱 `on_tick` (가격 엔진 갱신 직후, 주문 처리 전):

```
for each position in ShortSellingSystem.positions:
    current_price = PriceEngine.get_current_price(position.stock_id)

    // 공매도 수익 = 개시가 - 현재가. 가격 상승 시 음수(손실)
    position.unrealized_pnl = (position.open_price - current_price) × position.quantity

    position.unrealized_pnl_pct =
        position.unrealized_pnl / position.initial_value × 100

    // margin_ratio: 증거금에서 미실현손실 차감 후 초기 포지션 가치 대비 비율
    position.margin_ratio =
        (position.margin_deposited + position.unrealized_pnl) / position.initial_value
    // unrealized_pnl이 손실(음수)이면 margin_ratio가 감소함

    // 강제청산 조건 체크
    if position.margin_ratio < margin_call_threshold:
        _trigger_forced_liquidation(position)
```

### 규칙 7. BUY_TO_COVER 체결 처리 (수동 청산)

```
on BUY_TO_COVER 주문 검증 통과:
    // 검증: ShortSellingSystem.has_short(stock_id) == true 확인
    //       quantity <= position.quantity 확인 (MVP: 전량 청산만)
    position = ShortSellingSystem.positions[stock_id]
    cover_price = PriceEngine.get_current_price(stock_id)
    cover_cost = cover_price × position.quantity

    // 수익 계산
    pnl = (position.open_price - cover_price) × position.quantity
    // 양수 = 수익 (가격 하락), 음수 = 손실 (가격 상승)

    // 청산 처리
    // 1. 매수 비용 차감
    CurrencySystem.sim_deduct(cover_cost)
    // 2. 증거금 환원 + 손익 반영
    //    실제 반환: margin_deposited + pnl = margin_deposited + open_price×qty - cover_price×qty
    CurrencySystem.sim_add(position.margin_deposited + pnl)
    // 단, sim_add 전에 margin_deposited + pnl > 0 확인 (강제청산 이후 잔존 케이스 방어)

    // 포지션 제거
    ShortSellingSystem.positions.erase(stock_id)

    order.status = FILLED
    order.filled_price = cover_price
    emit on_order_filled(order)
    emit on_short_position_closed(stock_id, pnl)
```

> **예수금 흐름 정리**: BUY_TO_COVER 시 순 변동 = `margin_deposited + pnl - cover_cost`
> = `ceil(initial_value × 1.40) + (open_price - cover_price) × qty - cover_price × qty`
> = `ceil(initial_value × 1.40) + open_price × qty - 2 × cover_price × qty`
>
> **예시 (수익)**: 메디진 175,000원 개시 → 163,000원 청산, 10주
> - `cover_cost` = 1,630,000원 차감
> - `pnl` = (175,000 - 163,000) × 10 = 120,000원
> - `sim_add` = 2,450,000 + 120,000 = 2,570,000원
> - 순 변동 = -1,630,000 + 2,570,000 = +940,000원 (= 초기 증거금 700,000 + 수익 240,000)
>
> **예시 (손실)**: 메디진 175,000원 개시 → 188,000원 청산, 10주
> - `cover_cost` = 1,880,000원 차감
> - `pnl` = (175,000 - 188,000) × 10 = -130,000원
> - `sim_add` = 2,450,000 + (-130,000) = 2,320,000원
> - 순 변동 = -1,880,000 + 2,320,000 = +440,000원 (= 초기 증거금 700,000 - 손실 260,000)

### 규칙 8. 강제청산 (Forced Liquidation)

```
_trigger_forced_liquidation(position):
    // margin_ratio < margin_call_threshold (기본 0.2) 시 자동 실행
    // 틱 처리 중 동기적으로 실행. 플레이어 확인 없음.

    current_price = PriceEngine.get_current_price(position.stock_id)
    cover_cost = current_price × position.quantity
    pnl = (position.open_price - current_price) × position.quantity

    // sim_add 금액: 증거금에서 손실 차감 후 남은 금액
    remaining = position.margin_deposited + pnl
    // remaining은 margin_ratio < 0.2이므로 initial_value의 20% 미만, 최소 0
    // 이론상 0 이하 불가능 (강제청산이 0.2 임계값에서 발동하므로)
    // 방어 코드: remaining = max(0, remaining)

    CurrencySystem.sim_deduct(cover_cost)
    CurrencySystem.sim_add(max(0, remaining))

    ShortSellingSystem.positions.erase(position.stock_id)

    emit on_forced_liquidation(position.stock_id, current_price, pnl)
    emit on_short_position_closed(position.stock_id, pnl)
    // UI 알림: "숏 포지션 강제청산됨: {stock_id}, 손실 {-pnl}원"
```

**강제청산 시 예수금 흐름**:
- `cover_cost` 차감 후 `remaining = margin_deposited + pnl` 추가
- 순 변동 = `remaining - cover_cost`
  = `(margin_deposited + pnl) - cover_cost`
  = 규칙 7과 동일한 공식
- margin_ratio = 0.2 임계값에서 발동 시 `remaining` = `initial_value × 0.2`
- 즉, 강제청산 시 플레이어는 초기 포지션 가치의 최대 ~80%를 손실로 회수하지 못한다

### 규칙 9. 시즌 종료 시 자동청산

시즌 종료 강제청산 시퀀스(season-manager.md 참조)에서 숏 포지션 청산이 추가된다:

```
// 기존 시즌 종료 시퀀스에 추가 (Step ①-A, 주문 만료 후 즉시):
for each position in ShortSellingSystem.positions:
    cover_price = PriceEngine.get_current_price(position.stock_id)
    cover_cost = cover_price × position.quantity
    pnl = (position.open_price - cover_price) × position.quantity
    remaining = max(0, position.margin_deposited + pnl)
    CurrencySystem.sim_deduct(cover_cost)
    CurrencySystem.sim_add(remaining)
    emit on_short_position_closed(position.stock_id, pnl)

ShortSellingSystem.positions.clear()
// 이후 기존 ② force_liquidate(롱 포지션) 실행
```

**시즌 종료 청산 순서**:
① 주문 엔진: `expire_all_pending()` (미체결 주문 만료)
① -A 숏 포지션 전량 시즌 종료 청산 (위 코드)
② 포트폴리오: `force_liquidate(price_provider)` (롱 포지션 청산)
③ 포트폴리오: `get_total_assets()` 최종 스냅샷
④ 재화 시스템: `settle_to_cash(prize)`
⑤ 포트폴리오: `reset()` + `ShortSellingSystem.reset()`

### 규칙 10. 숏 포지션이 총 자산에 반영되는 방식

숏 포지션의 `unrealized_pnl`은 대회 계좌 평가금액(`account_total_value`)에 반영된다:

```
account_total_value = sim_cash + reserved_cash
                    + Σ(long_holding.quantity × current_price)  // 롱 평가액
                    + Σ(short_position.unrealized_pnl)          // 숏 미실현 손익
                    + Σ(short_position.margin_deposited)        // 묶인 증거금 (시가 기준 조정 전)
```

> **설계 의도**: 증거금은 `sim_cash`에서 차감되어 있으므로, `account_total_value`에서
> `margin_deposited`를 재산입하고 실시간 손익(`unrealized_pnl`)을 반영해야 왜곡 없는
> 총 자산이 계산된다.
>
> 단순화 공식:
> ```
> short_net_value = Σ(position.margin_deposited + position.unrealized_pnl)
> account_total_value = sim_cash + reserved_cash + long_stock_value + short_net_value
> ```

`PortfolioManager.update_valuation()`은 `ShortSellingSystem.get_short_net_value()`를
호출하여 이 값을 총 자산 계산에 포함한다.

### 규칙 11. 숏 포지션 슬롯 제한

숏 포지션은 포트폴리오의 `max_holdings` 슬롯을 **공유하지 않는다**.
숏 포지션 전용 슬롯은 `max_short_positions` (기본 3)로 별도 제한한다.

| 설계 근거 | 내용 |
|----------|------|
| 롱/숏 슬롯 분리 | 롱 투자 전략과 공매도 전략이 서로를 제약하지 않도록 |
| 숏 슬롯 상한 | 증거금 부담 + 손실 리스크를 고려, 초보자 보호 목적 |

숏 포지션 수가 `max_short_positions`에 도달한 상태에서 SELL_SHORT 제출 시:
REJECTED ("숏 포지션 한도 초과 (최대 {max_short_positions}개)")

### 규칙 12. 대차 풀 (Borrow Pool)

각 종목에는 공매도 가능 물량 풀이 존재하며, `ShortSellingSystem`이 독립 관리한다.

#### 풀 초기화

시즌 시작 시 모든 종목의 풀을 초기화한다. `max_pool`은 종목의 `listed_shares`와
`VolatilityProfile`에 따른 `borrowable_ratio`로 산출한다:

```
max_pool   = floor(listed_shares × borrowable_ratio)
current_pool = max_pool   ## 시즌 시작 시 만충
```

`VolatilityProfile → borrowable_ratio` 매핑 (config 외부화):

| VolatilityProfile | 종목 성격 | borrowable_ratio | 설계 의도 |
|-------------------|----------|-----------------|----------|
| LOW | 대형 우량주 | 12% | 사실상 무제한. 마음껏 공매도 가능 |
| MEDIUM | 중형주 | 5% | 적당한 제약. 소수 플레이어가 몰리면 고갈 |
| HIGH | 소형주 | 2% | 체감되는 제약. 전략적 선점 필요 |
| EXTREME | 소형 테마주 | 1% | 조금만 몰려도 고갈. 급등주 무지성 공매도 차단 |

#### 풀 차감 (SELL_SHORT 체결 시)

SELL_SHORT 주문 검증에 **4-S5** 단계를 추가한다:

```
4-S5. 대차 풀 잔량 검증
    - ShortSellingSystem.get_borrow_pool(stock_id) < quantity
      → REJECTED ("대여 가능 물량 부족 (잔량: {current_pool}주)")
    - 통과 시: current_pool -= quantity  (체결과 동시에 차감)
```

부분 체결 없음: 잔량이 요청 수량 미만이면 전량 거부한다.

#### 풀 반환 (포지션 청산 시)

포지션이 닫힐 때마다 차감된 수량을 즉시 풀에 반환한다:

```
on BUY_TO_COVER FILLED | on_forced_liquidation | on_season_end liquidation:
    current_pool = min(current_pool + position.quantity, max_pool)
```

반환 즉시 다른 플레이어가 진입 가능하다 — 숏 스퀴즈 감각의 핵심.

#### AI 경쟁자 풀 미차감

AI 경쟁자(ADR-004 통계 시뮬레이션)는 풀을 소비하지 않는다. 이유: AI는 실매매 없는
통계 시뮬레이션 구조이므로 풀 연동 시 AI 아키텍처 전면 수정이 필요하다. 플레이어 전용 풀로 운영.

#### 풀 상태 공개 (UI)

대차 풀 잔량(`current_pool`, `max_pool`)은 트레이딩 화면 공매도 패널에 표시한다:
`대여 가능: 1,200주 / 15,000주`

---

## 4. Formulas

### F1. 증거금 (Margin Deposited)

```
margin_deposited = ceil(open_price × quantity × margin_rate)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `open_price` | int | 1+ | PriceEngine | SELL_SHORT 체결가 (현재가) |
| `quantity` | int | 1+ | 플레이어 입력 | 숏 포지션 수량 |
| `margin_rate` | float | 1.10 ~ 2.00 | config | 증거금 비율 (기본 1.40 = 140%) |
| `margin_deposited` | int | 1+ | calculated | 예수금에서 실제 차감되는 증거금. ceil()로 절상 |

**예시**: 메디진 175,000원 × 10주, margin_rate=1.40
- `margin_deposited = ceil(175,000 × 10 × 1.40) = ceil(2,450,000) = 2,450,000원`

### F2. 미실현 손익 (Unrealized PnL)

```
unrealized_pnl = (open_price - current_price) × quantity
unrealized_pnl_pct = unrealized_pnl / initial_value × 100
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `open_price` | int | 1+ | ShortPosition | 숏 개시 체결가 |
| `current_price` | int | 1+ | PriceEngine | 현재 시장가 |
| `quantity` | int | 1+ | ShortPosition | 숏 수량 |
| `initial_value` | int | 1+ | ShortPosition | `open_price × quantity` |
| `unrealized_pnl` | int | (-∞, +∞) | calculated | 양수 = 수익, 음수 = 손실 |
| `unrealized_pnl_pct` | float | (-∞, +∞) | calculated | 수익률 (%) |

**예시 (수익)**: open=175,000, current=163,000, qty=10
- `unrealized_pnl = (175,000 - 163,000) × 10 = 120,000원`
- `unrealized_pnl_pct = 120,000 / 1,750,000 × 100 = 6.86%`

**예시 (손실)**: open=175,000, current=192,000, qty=10
- `unrealized_pnl = (175,000 - 192,000) × 10 = -170,000원`
- `unrealized_pnl_pct = -170,000 / 1,750,000 × 100 = -9.71%`

### F3. 증거금 비율 (Margin Ratio)

```
margin_ratio = (margin_deposited + unrealized_pnl) / initial_value
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `margin_deposited` | int | 1+ | ShortPosition | 예수금에서 묶인 증거금 |
| `unrealized_pnl` | int | (-∞, +∞) | calculated | 손실 시 음수 |
| `initial_value` | int | 1+ | ShortPosition | `open_price × quantity` |
| `margin_ratio` | float | [0, margin_rate] | calculated | 개시 시 = margin_rate. 손실 시 하락 |

**margin_ratio 계산 전개**:
```
margin_ratio = (margin_deposited + unrealized_pnl) / initial_value
             = (ceil(initial_value × margin_rate) + (open_price - current_price) × qty) / initial_value
             ≈ margin_rate - (current_price - open_price) / open_price
             (ceil() 무시 근사값)
```

**예시 (개시 직후)**: margin_deposited=2,450,000, unrealized_pnl=0, initial_value=1,750,000
- `margin_ratio = 2,450,000 / 1,750,000 = 1.40`

**예시 (가격 상승 후 손실)**: unrealized_pnl=-300,000
- `margin_ratio = (2,450,000 + (-300,000)) / 1,750,000 = 2,150,000 / 1,750,000 = 1.229`

**강제청산 발동 가격 역산** (margin_call_threshold = 0.2):
```
margin_call_price = open_price × (margin_rate - margin_call_threshold) + open_price
                  = open_price × (1 + margin_rate - margin_call_threshold)
                  = open_price × (1 + 1.40 - 0.20)
                  = open_price × 2.20
```
즉, 개시가 대비 120% 상승 시 강제청산.

**예시**: 메디진 175,000원 숏
- 강제청산 발동가 ≈ 175,000 × 2.20 = 385,000원

### F4. 실현 손익 (Realized PnL, 청산 시)

```
realized_pnl = (open_price - cover_price) × quantity
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `cover_price` | int | 1+ | PriceEngine | BUY_TO_COVER 체결가 |
| `realized_pnl` | int | (-∞, +∞) | calculated | 양수 = 수익, 음수 = 손실 |

### F5. 최대 숏 가능 수량

```
max_short_qty = floor(available_sim_cash / (open_price × (margin_rate - 1)))
```

단, `open_price × (margin_rate - 1)` = 초과 증거금 부담분 (공매도 시 순 예수금 감소분).
margin_rate = 1.40이면 `open_price × 0.40`이 주당 예수금 감소.

| Variable | Source | Description |
|----------|--------|-------------|
| `available_sim_cash` | CurrencySystem | 현재 사용 가능 예수금 |
| `max_short_qty` | calculated | 현금으로 개시 가능한 최대 숏 수량 |

**예시**: available_sim_cash=3,000,000, open_price=175,000, margin_rate=1.40
- 주당 증거금 추가 부담 = 175,000 × 0.40 = 70,000원
- `max_short_qty = floor(3,000,000 / 70,000) = 42주`

### F6. 대차 풀 초기화 (Borrow Pool)

```
max_pool     = floor(listed_shares × borrowable_ratio)
current_pool = max_pool   ## 시즌 시작 시 만충
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `listed_shares` | int | 1+ | StockDatabase | 종목 상장주식수 (stocks.json에서 로드) |
| `borrowable_ratio` | float | 0.01 ~ 0.15 | config | VolatilityProfile별 대여 비율 |
| `max_pool` | int | 1+ | calculated | 시즌 내 최대 공매도 가능 물량 |
| `current_pool` | int | [0, max_pool] | ShortSellingSystem | 현재 잔여 대차 물량 |

**예시 (EXTREME 소형 테마주)**: listed_shares=150,000, borrowable_ratio=0.01
- `max_pool = floor(150,000 × 0.01) = 1,500주`
- 플레이어가 1,000주 숏 → `current_pool = 500주`
- 남은 500주 이상 요청 시 REJECTED

**예시 (LOW 대형 우량주)**: listed_shares=2,500,000, borrowable_ratio=0.12
- `max_pool = floor(2,500,000 × 0.12) = 300,000주`
- 사실상 무제한 수준

---

## 5. Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|-----------------|-----------|
| 가격 급등으로 margin_ratio < 0 | 이론상 불가. margin_ratio는 강제청산 임계값(0.2)에서 발동하므로 margin_deposited + unrealized_pnl ≥ 0 항상 보장. 방어 코드로 `remaining = max(0, remaining)` 적용 | 강제청산이 0 이전에 개입 |
| 강제청산과 BUY_TO_COVER 동일 틱 충돌 | 틱 처리 순서: margin_ratio 감시 → 강제청산 → 이후 주문 처리. BUY_TO_COVER가 큐에 있더라도 강제청산이 먼저 포지션을 제거. BUY_TO_COVER는 포지션 없음 → REJECTED ("청산할 숏 포지션이 없습니다"). 예약금 없으므로 플레이어 손실 없음 | "틱이 진실" 원칙 |
| 시즌 종료 시 숏 포지션이 수익 상태 | 수익이더라도 자동 청산. realized_pnl > 0. sim_add = margin_deposited + pnl > margin_deposited. 수익은 예수금을 통해 현금 자산으로 이월 | 시즌 종료는 모든 포지션을 청산 |
| 시즌 종료 시 숏 포지션이 손실 상태 | 자동 청산. realized_pnl < 0. 손실은 증거금에서 차감. margin_ratio ≥ 0.2 보장으로 증거금은 partial 환원 | 강제청산과 동일 메커니즘 |
| SELL_SHORT 후 해당 종목 상한가 도달 (+30%) | 가격 엔진이 일별 ±30% 상한을 적용. 이 범위 내에서는 강제청산 임계값(개시가 +120%) 도달 불가. 상한가 연속 발생 시 다음 날 margin_ratio 재평가 | 가격 엔진의 일별 상한 참조 |
| 상한가 3연속 시 margin_ratio 변화 | 일별 +30% 상한 3일 연속 시 가격 = open_price × 1.3³ ≈ open_price × 2.197. 이 시점 margin_ratio ≈ 1.40 − 1.197 = 0.203으로 강제청산 임계값(0.2)에 근접. 4일 연속 상한가(×1.3⁴ ≈ ×2.856)에 도달하면 임계값 하회 → 강제청산 발동. 실제 발동은 틱 단위 감시 기준이며, 상한가 당일 시가부터 가격 엔진 상한이 적용되므로 청산은 다음 영업일 첫 틱 이전에는 발생하지 않음 | 극단 이벤트 범위 내이나 실현 가능. forced_liquidation_warning_ratio 설정 시 3일 연속 상한가 시점에서 경고가 표시되도록 튜닝 권장 |
| SELL_SHORT 후 해당 종목 VI 발동 | 가격 동결. margin_ratio 변화 없음. VI 해제 후 가격 갱신 시 margin_ratio 재평가. 강제청산 위험은 VI 해제 틱에서 처리 | 가격 동결 = margin_ratio 동결 |
| SELL_SHORT 후 해당 종목 CB(서킷브레이커) | CB Stage 1: 가격 동결, margin_ratio 변화 없음. CB Stage 2(조기 마감): 시즌 종료 청산 시퀀스 동일하게 적용 (숏 자동 청산 후 롱 청산) | CB 처리는 시즌 종료와 동일 시퀀스 |
| 예수금이 증거금보다 적은 상태에서 SELL_SHORT | 4-S4 증거금 검증에서 REJECTED. 예수금 불변 | 사전 차단 |
| BUY_TO_COVER인데 숏 포지션 없음 | REJECTED ("청산할 숏 포지션이 없습니다"). 예수금 불변 | 포지션 존재 검증 |
| 세이브/로드 후 숏 포지션 복구 | `ShortPosition` 배열 전체를 세이브 데이터에 직렬화. 로드 후 동일 포지션으로 재개. margin_ratio는 로드 후 첫 틱에 재계산 | 세이브/로드 GDD 직렬화 대상에 추가 필요 |
| 숏 포지션 보유 중 일시정지(PAUSED) | 가격 동결 아님 (PAUSED는 플레이어 일시정지). margin_ratio 감시는 틱 기반이므로 PAUSED 중 틱이 발생하지 않아 강제청산 없음. 재개 후 첫 틱에 재평가 | GameClock pause 참조 |
| BUY_TO_COVER를 PRE_MARKET에 제출 | REJECTED ("공매도는 장 중에만 가능합니다"). PRE_MARKET에서는 숏 관련 주문 일체 불가 | 규칙 4-S2 |
| 세이브/로드 반복으로 증거금 조작 시도 | 저장 시점의 margin_deposited가 그대로 복원. 로드 후 첫 틱에 현재가 기준으로 unrealized_pnl과 margin_ratio 재계산. 세이브/로드로 포지션 상태 유리하게 변경 불가 | 익스플로잇 방어 |
| 숏 포지션 중 동일 종목 일반 BUY 시도 | REJECTED ("해당 종목의 숏 포지션을 먼저 청산하세요"). 롱/숏 동시 보유 불가 | 규칙 3 |
| 대차 풀 잔량 = 0 상태에서 SELL_SHORT | REJECTED ("대여 가능 물량 부족 (잔량: 0주)"). 예수금 불변, 포지션 미생성 | 4-S5 |
| 요청 수량 > 잔여 풀 (부분 가능 상황) | 부분 체결 없음. 전량 거부. 플레이어가 수량을 줄여 재시도해야 함 | 설계 원칙: 단순성 우선 |
| 강제청산 후 풀 반환 타이밍 | 강제청산 발동 틱 내에서 즉시 반환. 동일 틱 내 다른 플레이어가 진입 가능 (GDScript 단일 스레드이므로 실제 동일 틱 경합 없음) | "틱이 진실" 원칙 |
| 시즌 종료 시 풀 반환 | 시즌 종료 청산(Step ①-A) 완료 후 모든 풀이 0→max_pool로 자동 리셋. 다음 시즌 시작 시 재초기화와 동일 | 시즌 시작 시 `_init_pools()` 재호출 |
| 세이브/로드 후 풀 상태 복원 | `current_pool` 전체를 세이브 데이터에 직렬화. 로드 후 동일 잔량 복원. 로드/세이브 반복으로 풀 조작 불가 (보유 포지션과 차감량이 연동) | 익스플로잇 방어 |
| borrowable_ratio 변경 시 진행 중 풀 처리 | 시즌 중 config 변경은 다음 시즌 시작 시 `_init_pools()` 재호출로 반영. 현재 시즌은 변경 없음 | 튜닝 안정성 |

---

## 6. Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **OrderEngine** | 공매도 시스템이 의존 / OrderEngine이 위임 | `SELL_SHORT`, `BUY_TO_COVER` 주문 유형 추가. OrderEngine이 검증 후 ShortSellingSystem으로 처리 위임. `on_order_filled` 시그널 재사용. **Hard** |
| **PriceEngine** | 공매도 시스템이 의존 | `get_current_price(stock_id)` — 개시가, 매 틱 평가, 청산가 산출. **Hard** |
| **CurrencySystem** | 공매도 시스템이 의존 | `sim_deduct(amount)` — 증거금 차감, 매수 비용 차감. `sim_add(amount)` — 매도 대금 추가, 증거금 환원. `get_sim_cash()` — 증거금 검증. **Hard** |
| **PortfolioManager** | 양방향 | `get_holding(stock_id)` — 롱/숏 동시 보유 방지. `update_valuation()` — `ShortSellingSystem.get_short_net_value()` 호출하여 총 자산에 숏 손익 반영. **Hard** |
| **SkillTree** | 공매도 시스템이 참조 | `has_short_selling()` — TR3 해금 확인. `has_indicators()` — A2 해금 확인 (해금 조건용. 실제 검증은 SkillTree가 포인트 소비 시 처리). **Soft** |
| **GameClock** | 공매도 시스템이 의존 | `on_tick` — 매 틱 margin_ratio 감시. `on_season_end` — 시즌 종료 자동청산 트리거. `on_market_open/close` — 주문 수락 상태 전환. **Hard** |
| **SeasonManager** | 시즌이 위임 | 시즌 종료 청산 시퀀스에서 Step ①-A로 숏 포지션 전량 청산 호출. `ShortSellingSystem.liquidate_all_for_season_end(price_provider)`. **Hard** |
| **TradingScreen** | UI가 참조 | 숏 포지션 패널 표시. `ShortSellingSystem.get_all_short_positions()` 조회. 강제청산 알림 수신. **Soft** |
| **XPSystem** | XP가 참조 | `on_short_position_closed(stock_id, pnl)` — 숏 청산 시 XP 산출 (수익 청산 시 추가 XP). **Soft** |
| **AudioSystem** | 오디오가 참조 | `on_order_filled` (SELL_SHORT/BUY_TO_COVER), `on_forced_liquidation` — 효과음 재생. **Soft** |
| **SaveLoad** | 세이브/로드가 참조 | `ShortPosition` 배열 + `borrow_pool` dict 직렬화/역직렬화 대상 추가 필요. **Hard** |
| **StockDatabase** | 공매도 시스템이 의존 | `get_stock(stock_id).listed_shares` — 대차 풀 초기화 시 상장주식수 조회. `get_stock(stock_id).volatility_profile` — borrowable_ratio 결정. **Hard** |

> **역방향 의존성 알림**:
> - `PortfolioManager.update_valuation()`은 `ShortSellingSystem.get_short_net_value()`를 호출하도록 수정 필요
> - `SeasonManager`의 시즌 종료 청산 시퀀스에 Step ①-A 삽입 필요 (season-manager.md 갱신 대상)
> - `OrderEngine`의 주문 검증 10단계에 SELL_SHORT/BUY_TO_COVER 분기 추가 필요 (order-engine.md 갱신 대상)
> - `save-load.md`의 직렬화 대상 표에 `ShortPosition[]` 추가 필요
>
> **대차 풀 설계 결정 (2026-04-20)**:
> - **주식 차입(Locate) 구현**: 규칙 12 대차 풀로 구현. `listed_shares × borrowable_ratio`로 종목별 공매도 가능 물량을 제한한다.
>   PriceEngine과 호가창을 건드리지 않는 독립 레이어로 구현하여 원래 제외 이유(유동성 모델 충돌)를 해소.
>   AI 경쟁자는 풀 미차감 (ADR-004 통계 시뮬레이션 아키텍처 유지).
>
> **TR2 연동 상태**: `StopTakeSystem`이 숏 포지션을 지원한다. 가격 방향 역전 조건으로
> 자동 BUY_TO_COVER를 발동하며, `on_short_position_closed` 수신 시 설정이 자동 삭제된다.
> 상세: `design/gdd/stop-loss-take-profit.md` §규칙 4, AC-S01~S06 참조.

---

## 7. Tuning Knobs

| Parameter | Current Value | Safe Range | Category | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|----------|-------------------|-------------------|
| `borrowable_ratio_low` | 0.12 (12%) | 0.05 ~ 0.20 | Gate | 대형주 공매도 가능 물량 증가. 사실상 무제한에 가까워짐 | 대형주도 물량 제약 체감 |
| `borrowable_ratio_medium` | 0.05 (5%) | 0.02 ~ 0.10 | Gate | 중형주 공매도 여유 증가 | 중형주 진입 경쟁 심화 |
| `borrowable_ratio_high` | 0.02 (2%) | 0.01 ~ 0.05 | Gate | 소형주 여유 확대. 전략적 선점 의미 약화 | 소형주 소수 진입 시 고갈. 경쟁 극대화 |
| `borrowable_ratio_extreme` | 0.01 (1%) | 0.005 ~ 0.03 | Gate | 테마주 여유 확대. 급등주 공매도 진입 허용 범위 확대 | 1~2명만 숏 쳐도 즉시 고갈. 선점 압박 극대화 |
| `margin_rate` | 1.40 (140%) | **1.20 ~ 2.00** | Curve | 공매도 진입 장벽 상승. 소규모 계좌 진입 어려움. 강제청산 버퍼 증가 | 진입 장벽 감소. 소규모 계좌도 공매도 가능. 강제청산 리스크 증가 |
| `margin_call_threshold` | 0.20 (20%) | 0.05 ~ 0.40 | Gate | 강제청산 발동 빨라짐 (더 작은 가격 상승에서 청산). 플레이어 보호 강화 | 강제청산 늦어짐. 더 큰 손실 허용. 리스크 허용도 증가 |
| `max_short_positions` | 3 | 1 ~ 5 | Gate | 동시 공매도 포지션 증가. 전략 다양성 증가 | 공매도 집중도 강제. 분산 공매도 불가 |
| `forced_liquidation_warning_ratio` | 0.35 (35%) | `margin_call_threshold` ~ 0.60 | Feel | 경고 UI 더 일찍 표시. 플레이어 대응 시간 증가 | 경고 늦게 표시. 긴장감 증가 |

> **margin_rate 근거**: 한국 실제 공매도 증거금은 120~140% 수준. 140%는 게임 내 리스크
> 의식 유도를 위한 기본값. **하한 1.20(120%)**: FSC 규정 최저 증거금률. 이 아래로 낮추면
> 레버리지 매수에 가까워지므로 TR4와의 기능적 차별화가 흐려진다. 1.20 미만 설정 금지.
>
> **margin_call_threshold 근거**: 0.2 = 증거금이 초기 포지션 가치의 20%만 남은 상태.
> F3 강제청산 발동가 역산: `open_price × (1 + margin_rate - margin_call_threshold) = open_price × 2.20`
> 즉, 개시가 대비 120% 상승 시 강제청산. 일별 ±30% 상한 하에서 이 가격에 도달하려면
> **3일 연속 상한가(×1.3³ ≈ ×2.197)**가 필요하며, 4일 연속(×1.3⁴ ≈ ×2.856)에 임계값을 하회한다.
> 실제 공매도(30~40% 상승 시 청산)와 비교해 게임 내 임계값이 관대한 이유: 게임 플로우 상
> 조기 강제청산은 플레이어 경험을 저해한다. 20거래일 시즌에서 3연속 상한가는 극단적 이벤트
> 수준이므로 의도적으로 이 범위를 허용 구간으로 유지한다.
>
> **forced_liquidation_warning_ratio 조정 검토**: 현재값 0.35는 강제청산 임계값(0.2) 대비
> margin_ratio 버퍼가 0.15(=15%p)에서 경고를 표시한다. 3연속 상한가 시점(margin_ratio ≈ 0.203)에서
> 경고가 이미 활성화되도록 하려면 **0.50 이상**으로 상향 조정이 권장된다. 0.50이면
> 2연속 상한가(×1.3² ≈ ×1.69, margin_ratio ≈ 0.71) 이후부터 경고가 시작되어
> 플레이어에게 충분한 대응 시간을 제공한다.
>
> **대차 수수료(Borrow Fee) 미적용 근거**: 실제 공매도에서 차입 기간에 비례하는 대차 수수료가
> 발생한다. 게임에서는 이를 제외한다. 이유: (1) 일별 수수료 과금은 "보유 기간 페널티"로 작동하여
> 장기 숏 전략보다 단기 트레이딩을 강제하게 됨 — 전략 다양성 저해, (2) 수수료 계산이 복잡도를
> 높이고 초보 플레이어에게 설명 부담이 큼. 대신, 증거금 140%와 max_short_positions 3개 제한으로
> 공매도 규모를 간접 제어한다.

---

## 8. Acceptance Criteria

| AC-ID | 조건 | 검증 방법 |
|-------|------|-----------|
| AC-01 | TR3 미해금 시 SELL_SHORT 주문 REJECTED | 단위 테스트: TR3 없는 상태에서 SELL_SHORT 제출 → status == REJECTED |
| AC-02 | SELL_SHORT 체결 시 `margin_deposited = ceil(price × qty × margin_rate)` 예수금에서 차감 | 단위 테스트: 체결 전후 sim_cash 차분 검증 |
| AC-03 | SELL_SHORT 체결 시 ShortPosition 레코드 생성, margin_ratio == margin_rate | 단위 테스트: 체결 후 positions[stock_id] 존재 및 margin_ratio 확인 |
| AC-04 | 매 틱 unrealized_pnl = (open_price - current_price) × qty | 단위 테스트: 틱 처리 후 pnl 값 검증 |
| AC-05 | 매 틱 margin_ratio = (margin_deposited + unrealized_pnl) / initial_value | 단위 테스트: margin_ratio 공식 검증 |
| AC-06 | margin_ratio < 0.2 시 강제청산 자동 실행, 포지션 제거, on_forced_liquidation 시그널 발행 | 단위 테스트: 가격을 강제청산 임계값 이상으로 올린 후 틱 처리 |
| AC-07 | BUY_TO_COVER 체결 시 realized_pnl = (open_price - cover_price) × qty 예수금에 반영 | 단위 테스트: 청산 전후 sim_cash 차분이 예측값과 일치 |
| AC-08 | 시즌 종료 시 미청산 숏 포지션 전량 자동청산 | 통합 테스트: season_end 신호 후 positions.is_empty() == true |
| AC-09 | 롱 보유 종목에 SELL_SHORT REJECTED | 단위 테스트: 롱 보유 후 SELL_SHORT 제출 → REJECTED |
| AC-10 | 숏 포지션 보유 중 동일 종목 BUY REJECTED | 단위 테스트: 숏 보유 후 BUY 제출 → REJECTED |
| AC-11 | 중복 숏 포지션(동일 종목 SELL_SHORT 2회) REJECTED | 단위 테스트: 첫 숏 체결 후 동일 종목 SELL_SHORT → REJECTED |
| AC-12 | PRE_MARKET에서 SELL_SHORT REJECTED | 단위 테스트: PRE_MARKET 상태에서 SELL_SHORT → REJECTED |
| AC-13 | 숏 포지션의 unrealized_pnl이 account_total_value에 올바르게 반영 | 단위 테스트: short_net_value = margin_deposited + unrealized_pnl. portfolio 총 자산 확인 |
| AC-14 | 증거금 부족 시 SELL_SHORT REJECTED, 예수금 불변 | 단위 테스트: sim_cash < margin_deposited 조건에서 제출 |
| AC-15 | 강제청산 후 BUY_TO_COVER 제출 시 REJECTED ("청산할 숏 포지션이 없습니다") | 단위 테스트: 강제청산 실행 후 BUY_TO_COVER 제출 |
| AC-16 | 세이브/로드 후 ShortPosition 상태 완전 복구, 로드 후 첫 틱에 margin_ratio 재계산 | 통합 테스트: 숏 포지션 보유 중 세이브 → 로드 → 포지션 확인 |
| AC-17 | 시즌 시작 시 모든 종목 풀이 `floor(listed_shares × borrowable_ratio)`로 초기화 | 단위 테스트: 시즌 시작 후 get_borrow_pool(stock_id) == max_pool |
| AC-18 | SELL_SHORT 체결 시 `current_pool -= quantity` | 단위 테스트: 체결 전후 pool 차분 검증 |
| AC-19 | `current_pool < quantity` 시 SELL_SHORT REJECTED ("대여 가능 물량 부족") | 단위 테스트: 풀 고갈 후 SELL_SHORT 제출 → REJECTED |
| AC-20 | BUY_TO_COVER / 강제청산 시 `current_pool += quantity` (max_pool 초과 불가) | 단위 테스트: 청산 후 pool 반환 검증 |
| AC-21 | 세이브/로드 후 `current_pool` 복원 | 통합 테스트: 풀 차감 상태 세이브 → 로드 → pool 값 동일 확인 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 기능 | 진입점 |
|------|--------|
| 공매도 주문 제출 | `trading_screen.gd._submit_short_order()` → `OrderEngine.submit_order(SELL_SHORT, stock_id, qty)` → `ShortSellingSystem.open_position(order)` |
| 공매도 청산 주문 | `trading_screen.gd._submit_cover_order()` → `OrderEngine.submit_order(BUY_TO_COVER, stock_id, qty)` → `ShortSellingSystem.close_position(order)` |
| 매 틱 margin_ratio 감시 | `game_clock.gd._process_tick()` → `ShortSellingSystem.update_and_check_margin(tick)` (틱 순서: 가격 엔진 갱신 → 숏 감시 → 주문 처리) |
| 시즌 종료 자동청산 | `season_manager.gd._on_season_end()` → `ShortSellingSystem.liquidate_all_for_season_end(price_provider)` (Step ①-A) |
| 총 자산 반영 | `portfolio_manager.gd.update_valuation()` → `ShortSellingSystem.get_short_net_value()` |
| 대차 풀 초기화 | `GameClock.on_season_start` → `ShortSellingSystem._init_pools()` _(TD-DR-06, 미구현)_ |
| 대차 풀 잔량 조회 (UI) | `trading_screen.gd` → `ShortSellingSystem.get_borrow_pool(stock_id) -> Dictionary` (`{current, max}`) _(TD-DR-06, 미구현)_ |

### 호출 경로

- [x] `ShortSellingSystem.open_position(order: Dictionary) -> int` 존재 (filled_price 반환)
- [x] `ShortSellingSystem.close_position(order: Dictionary) -> int` 존재 (realized_pnl 반환)
- [x] `ShortSellingSystem.update_and_check_margin(tick: int)` 존재
- [x] `ShortSellingSystem.liquidate_all_for_season_end() -> void` 존재
- [x] `ShortSellingSystem.get_short_net_value() -> int` 존재
- [x] `ShortSellingSystem.get_all_short_positions() -> Array[Dictionary]` 존재
- [x] `ShortSellingSystem.has_short(stock_id: String) -> bool` 존재
- [x] `ShortSellingSystem.reset() -> void` 존재
- [x] `OrderEngine.submit_market_order()` 의 side에 `SELL_SHORT`, `BUY_TO_COVER` 처리 추가
- [x] `SkillTree.has_short_selling() -> bool` 존재
- [x] `PortfolioManager.update_valuation()` 내부에서 `ShortSellingSystem.get_short_net_value()` 호출
- [x] `SeasonManager._on_season_end()` 시퀀스에 Step ①-A 추가
- [x] `on_forced_liquidation(stock_id: String, price: int, pnl: int)` 시그널 존재
- [x] `on_short_position_closed(stock_id: String, pnl: int)` 시그널 존재
- [x] `assets/data/short_selling_config.json` 에 margin_rate, margin_call_threshold, max_short_positions 정의
- [x] `SaveSystem`: `get_save_data()` + `load_save_data()` 에 `short_positions` 키 추가
- [x] `ShortSellingSystem` autoload `project.godot` 등록
- [x] `StockDatabase.get_stock(stock_id)` 에서 `listed_shares`, `volatility_profile` 접근 확인

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_short_selling.gd` | `test_sell_short_rejected_without_tr3()` |
| AC-02 | `tests/unit/test_short_selling.gd` | `test_sell_short_deducts_margin()` |
| AC-03 | `tests/unit/test_short_selling.gd` | `test_short_position_created_on_fill()` |
| AC-04 | `tests/unit/test_short_selling.gd` | `test_unrealized_pnl_calculated_per_tick()` |
| AC-05 | `tests/unit/test_short_selling.gd` | `test_margin_ratio_formula()` |
| AC-06 | `tests/unit/test_short_selling.gd` | `test_forced_liquidation_triggers_below_threshold()` |
| AC-07 | `tests/unit/test_short_selling.gd` | `test_buy_to_cover_realized_pnl()` |
| AC-08 | `tests/unit/test_short_selling.gd` | `test_season_end_auto_liquidates_all()` |
| AC-09 | `tests/unit/test_short_selling.gd` | `test_sell_short_rejected_when_long_held()` |
| AC-10 | `tests/unit/test_short_selling.gd` | `test_buy_rejected_when_short_held()` |
| AC-11 | `tests/unit/test_short_selling.gd` | `test_duplicate_short_rejected()` |
| AC-12 | `tests/unit/test_short_selling.gd` | `test_sell_short_rejected_in_pre_market()` |
| AC-13 | `tests/unit/test_short_selling.gd` | `test_short_net_value_in_total_assets()` |
| AC-14 | `tests/unit/test_short_selling.gd` | `test_sell_short_rejected_insufficient_margin()` |
| AC-15 | `tests/unit/test_short_selling.gd` | `test_buy_to_cover_rejected_after_forced_liq()` |
| AC-16 | `tests/integration/test_short_selling_save_load.gd` | `test_short_position_survives_save_load()` |
| AC-17 | `tests/unit/test_short_selling.gd` | `test_borrow_pool_initialized_on_season_start()` |
| AC-18 | `tests/unit/test_short_selling.gd` | `test_borrow_pool_decrements_on_sell_short()` |
| AC-19 | `tests/unit/test_short_selling.gd` | `test_sell_short_rejected_when_pool_exhausted()` |
| AC-20 | `tests/unit/test_short_selling.gd` | `test_borrow_pool_restored_on_cover()` |
| AC-21 | `tests/integration/test_short_selling_save_load.gd` | `test_borrow_pool_survives_save_load()` |
| API 계약 | `tests/unit/test_api_contracts.gd` | `test_short_selling_system_api()` |

### 빌드 검증

- [x] 바이너리 실행 확인: QA Lead 서명 — S9 완료 빌드 (2026-04-17, SCRIPT ERROR 없음)

---

## 미구현 — 대차 풀 시스템 (TD-DR-06, Sprint 11)

> 핵심 공매도 기능(증거금/청산)과 별개. Sprint 11 구현 예정. tech-debt TD-DR-06 참조.

- [ ] `assets/data/short_selling_config.json` 에 `borrowableRatioByVolatility` 추가 (LOW/MEDIUM/HIGH/EXTREME → ratio)
- [ ] `SaveSystem`: `borrow_pool` dict 직렬화 추가 (`short_selling_config.json`의 `borrow_pool` 키)
- [ ] `ShortSellingSystem._init_pools()` — 시즌 시작 시 종목별 max_pool 계산 및 current_pool 초기화
- [ ] `ShortSellingSystem.get_borrow_pool(stock_id) -> Dictionary` — `{current, max}` 반환
- [ ] `OrderEngine` SELL_SHORT 검증 4-S5 단계 추가 (pool 잔량 체크 → REJECTED)
- [ ] `GameClock.on_season_start` → `ShortSellingSystem._init_pools()` 연결
- [ ] 빌드 재검증: QA Lead 서명 (대차 풀 구현 완료 후)

## DLC 확장성 — MarketProfile 추상화

> 한국 시장 Approved 조건과 별개. DLC 그린라이트 시 구현. tech-debt TD-DR-06 참조.  
> 근거: [ADR-021](../../docs/architecture/021-market-profile-data-driven.md) / 감사 항목: **H-01, H-02**

**H-01. 공매도 증거금 비율**
- [ ] `margin_rate = 1.40` (140%, FSC 기준) → `_profile.short_margin_rate` 로드로 교체
- [ ] `margin_call_threshold` → `_profile.short_margin_call_threshold` 로드로 교체
- [ ] `assets/data/market_profiles/market_kr.json` — `"short_margin_rate": 1.40`, `"short_margin_call_threshold": 0.20` 등록
- [ ] 강제청산 임계값이 `PriceEngine.daily_limit_pct`(C-03)와 연동되는 부분 재검토 — 상한가 변경 시 청산 조건 자동 반영 확인
- [ ] 테스트: `test_short_selling.gd` — `test_margin_rate_loaded_from_market_profile()` 추가

**H-02. 대차 풀 비율**
- [ ] `borrowable_ratio` (LARGE 12% 등) → `_profile.borrow_pool_ratios` 딕셔너리 로드로 교체
- [ ] `assets/data/market_profiles/market_kr.json` — `"borrow_pool_ratios": {"LARGE": 0.12, "MEDIUM": 0.05, "SMALL": 0.02, "VOLATILE": 0.01}` 등록
- [ ] `market_us.json`에는 `"borrow_pool_enabled": false` 플래그로 시스템 전체 비활성화 경로 설계
- [ ] 테스트: `test_short_selling.gd` — `test_borrow_pool_ratios_from_market_profile()` 추가
