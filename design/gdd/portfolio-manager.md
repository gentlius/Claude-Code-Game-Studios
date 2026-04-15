# 포트폴리오 관리 (Portfolio Manager)

> **Status**: In Review

> **Note**: xp-system.md (Approved)가 이 시스템에 Hard 의존. XP 구현 전 리뷰 완료 필요.
> **Author**: user + game-designer
> **Last Updated**: 2026-03-26
> **Implements Pillar**: 판단이 곧 실력 (Judgment is King), 체감있는 성장 (Feel the Growth)

## Overview

포트폴리오 관리는 플레이어의 보유 종목을 추적하고 손익을 계산하는 Core 시스템이다.
주문 처리 엔진에서 체결 통보를 받으면 보유 종목(holdings)을 갱신하고, 가격 엔진의
현재가를 참조하여 매 틱 미실현 손익과 총 자산을 실시간 계산한다. 시즌 순위의
기준이 되는 대회 내 계좌 총 평가금액(`account_total_value = sim_cash + reserved_cash + 보유 주식 평가액`)을
산출하는 핵심 시스템이다. `account_total_value`는 3층 자산 구조의 두 번째 층으로,
현금 자산(`cash_assets`) 및 유형 자산(`tangible_assets`)을 포함하지 않는다.

MVP에서는 단일 포트폴리오(`SimPortfolio`)로 구현한다. `RealPortfolio`는 향후 확장용 스텁이다. 시즌 종료 시 보유 주식을 강제 청산하고,
예수금 잔액은 다음 시즌으로 이월된다 (복리 구조).

## Player Fantasy

내 포트폴리오가 곧 나의 전략 표현이다. "바이오주 한 종목에 올인한 공격적 투자자"
인지 "3개 섹터에 분산한 안정형 투자자"인지 — 포트폴리오를 보면 내 투자 철학이
보인다. 수익률 +15%가 빨갛게 빛날 때의 쾌감, -8%가 파랗게 찍힐 때의 긴장감.
숫자 하나하나가 내 판단의 결과이고, 그 결과가 시즌 순위로 이어진다.

필라 "판단이 곧 실력"에 따라, 포트폴리오의 수익률은 오직 플레이어의 매매 판단에
의해 결정된다. 필라 "체감있는 성장"에 따라, 시즌마다 더 높은 수익률을 달성하고
더 많은 종목을 운용하는 것이 눈에 보이는 성장이다.

## Detailed Design

### Core Rules

#### 규칙 1. 클래스 구조

```
BasePortfolio {
    // 공통 인터페이스
    holdings: Map<stock_id, HoldingEntry>
    transactions: TransactionRecord[]

    add_holding(stock_id, quantity, price)
    remove_holding(stock_id, quantity, price)
    get_holding(stock_id): HoldingEntry | null
    get_all_holdings(): HoldingEntry[]
    get_holding_count(): int                    # 보유 종목 수 (quantity > 0인 종목만)
    get_total_stock_value(price_provider): int
    get_transaction_history(limit): TransactionRecord[]
}

// 트레이딩 스크린 사이드바용 요약 데이터
PortfolioSummary {
    sim_cash: int               # 현금 잔액 (재화 시스템에서 조회)
    reserved_cash: int          # 지정가 매수 예약금 합계 (주문 엔진에서 조회)
    account_total_value: int    # sim_cash + reserved_cash + 보유 주식 평가액 (대회 계좌 평가금액. 3층 구조의 현금 자산·유형 자산 미포함)
    return_rate: float          # 대회 수익률 (%)
    holding_count: int          # 현재 보유 종목 수
    max_holdings: int           # 최대 보유 가능 종목 수 (스킬 레벨 기준)
}

SimPortfolio extends BasePortfolio {  # "Sim" = simulation (게임 경제). 예수금 직접 투자.
    season_id: string
    season_start_deposit: int   # 시즌 시작 시 예수금 스냅샷 (= CurrencySystem.auto_deposit_to_sim() 입금액. 첫 시즌: 1,000,000, 이후 tier_threshold)

    update_valuation(price_provider, sim_cash, reserved_cash)
                                # 틱별 호출. 평가 갱신 + 캐시 갱신
    get_return_rate(): float    # 캐시된 최신 수익률 반환 (파라미터 불필요)
    get_total_assets(): int     # 캐시된 최신 대회 계좌 평가금액 반환 (= account_total_value. 현금·유형 자산 미포함)
    get_portfolio_summary(): PortfolioSummary
                                # 캐시된 값으로 PortfolioSummary 조립.
                                # 내부적으로 SkillTree.get_max_holdings()를 호출하여 슬롯 정보를 조회한다.
                                # sim_cash, reserved_cash는 update_valuation에서
                                # 캐시된 값 사용 (추가 외부 조회 불필요)
    reset()                     # 시즌 종료 시 전체 초기화
}

// 향후 확장: 수수료, 배당, 공매도 등 고급 기능 추가 시
RealPortfolio extends BasePortfolio {
    // 매매 수수료, 배당금, 공매도 잔고 등
}
```

#### 규칙 2. 보유 종목 데이터 구조

```
HoldingEntry {
    stock_id: string            # 종목 고유 ID
    quantity: int               # 보유 수량 (양의 정수)
    avg_buy_price: int          # 평균 매수가 (원, 정수)
    total_invested: int         # 현재 보유분의 투자금 = avg_buy_price × quantity. 매도 시 비례 감소
    first_buy_tick: int         # 최초 매수 틱
    last_trade_tick: int        # 마지막 거래 틱

    // 틱별 평가 갱신 필드 (규칙 6에서 매 틱 갱신)
    current_value: int          # 현재 평가금액 = current_price × quantity
    unrealized_pnl: int         # 미실현 손익 = current_value - total_invested
    unrealized_pnl_pct: float   # 미실현 수익률 (%)
}
```

#### 규칙 3. 평균 매수가 계산

동일 종목을 추가 매수할 때 평균 매수가를 재계산한다.

```
new_total_invested = old_total_invested + (buy_price × buy_quantity)
new_quantity = old_quantity + buy_quantity
new_avg_buy_price = floor(new_total_invested / new_quantity)
```

**예시**: 스타칩 10주 @ 65,000원 보유 중, 5주 @ 70,000원 추가 매수
- `new_total_invested = 650,000 + 350,000 = 1,000,000`
- `new_quantity = 10 + 5 = 15`
- `new_avg_buy_price = floor(1,000,000 / 15) = 66,666원`

매도 시 평균 매수가는 변하지 않는다. 수량과 `total_invested`가 비례 차감된다:

```
new_quantity = old_quantity - sell_quantity
new_total_invested = avg_buy_price × new_quantity
```

이렇게 하면 `total_invested = avg_buy_price × quantity` 항등식이 항상 유지되며,
`unrealized_pnl_pct = unrealized_pnl / total_invested × 100` 계산이 현재 보유분
기준으로 정확하다.

**`remove_holding` 계약**: 매도 수량 차감 후 잔여 수량이 0이 되면 해당 HoldingEntry를
holdings에서 완전히 삭제한다. `get_holding_count()`는 즉시 감소하며, 해당 슬롯은
새 종목 매수에 사용 가능해진다.

**`get_available_quantity` 미제공**: 포트폴리오는 잠금(locked) 개념을 관리하지 않는다.
매도 가능 수량 계산(`holding.quantity - locked_quantity`)은 주문 처리 엔진이 자체적으로
수행한다. 포트폴리오는 `get_holding(stock_id).quantity`만 제공한다.

#### 규칙 4. 거래 내역 기록

```
TransactionRecord {
    transaction_id: int         # 자동 증가 ID
    stock_id: string
    type: BUY | SELL
    quantity: int
    price: int                  # 체결가
    total_amount: int           # price × quantity
    tick: int                   # 체결 틱
    day: int                    # 거래일
    realized_pnl: int | null    # SELL 시에만: (체결가 - avg_buy_price) × quantity
}
```

모든 체결은 거래 내역에 기록된다. 시즌 내 전체 거래 내역을 보존한다.

#### 규칙 5. 보유 종목 수 제한

스킬 트리의 포트폴리오 스킬 레벨에 따라 동시 보유 가능 종목 수가 제한된다.

| 스킬 레벨 | max_holdings | 설명 |
|----------|-------------|------|
| P0 (기본) | 3 | 집중 투자 강제 |
| P1 | 5 | 분산 투자 시작 |
| P2 | 10 | 전 종목 보유 가능 |

- 보유 종목 수 = `holdings.size` (수량 0이 아닌 종목만 카운트)
- 한도 도달 시 새로운 종목 매수 불가. 기존 보유 종목 추가 매수는 허용.
- 한도 체크는 주문 처리 엔진이 주문 검증 시 수행. 포트폴리오는 `get_holding_count()`만 제공.

#### 규칙 6. 틱별 평가 갱신

매 틱 `on_tick` 시 (가격 엔진 갱신 후) `update_valuation(price_provider, sim_cash, reserved_cash)` 호출:

```
update_valuation(price_provider, sim_cash, reserved_cash):
    // Step 1: 개별 보유 종목 평가 갱신
    total_stock_value = 0
    for each holding in holdings:
        current_price = price_provider.get_current_price(holding.stock_id)
        holding.current_value = current_price × holding.quantity
        holding.unrealized_pnl = holding.current_value - holding.total_invested
        holding.unrealized_pnl_pct = holding.unrealized_pnl / holding.total_invested × 100
        total_stock_value += holding.current_value

    // Step 2: 캐시 갱신 (get_total_assets, get_return_rate의 반환값)
    // _cached_total_assets = account_total_value (대회 계좌 평가금액, 현금·유형 자산 미포함)
    _cached_total_assets = sim_cash + reserved_cash + total_stock_value
    _cached_return_rate = (_cached_total_assets - season_start_deposit) / season_start_deposit × 100
    _cached_sim_cash = sim_cash
    _cached_reserved_cash = reserved_cash
```

`get_total_assets()`, `get_return_rate()`는 캐시된 값을 즉시 반환한다 (파라미터 불필요).
평가 갱신은 포트폴리오 UI가 읽어갈 데이터를 준비하는 것이지, 포트폴리오 자체의
상태를 변경하지 않는다. 보유 수량과 평균 매수가는 매매 체결 시에만 변경.

### States and Transitions

| State | Description | Transition |
|-------|-------------|------------|
| **EMPTY** | 보유 종목 0개. 시즌 시작 직후 초기 상태 | → ACTIVE (첫 매수 체결 시) |
| **ACTIVE** | 1개 이상 종목 보유 중. 실시간 평가 진행 | → EMPTY (전체 매도 완료 시) |
| **SEASON_SETTLED** | 시즌 종료. 최종 총 자산 확정 | → EMPTY (다음 시즌 reset 후) |

- ACTIVE ↔ EMPTY 전환은 시즌 중 자유롭게 반복 가능
- SEASON_SETTLED는 시즌 종료 시 진입. 이후 매매 불가

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **주문 처리 엔진** | 주문 엔진 → 포트폴리오 | 주문 엔진이 체결 시 `add_holding()` / `remove_holding()`을 **직접 메서드 호출** (시그널 아님). `get_holding_count()` → 보유 한도 검증. `get_total_reserved_cash()` → 미체결 지정가 매수 예약금 합계 (총 자산 계산용) |
| **가격 엔진** | 포트폴리오가 참조 | `get_current_price(stock_id)` → 틱별 평가 금액 계산 |
| **재화 시스템** | 포트폴리오가 참조 / 포트폴리오가 쓰기 | `get_sim_cash()` → 총 자산 계산의 현금 파트. `sim_add(amount)` → `force_liquidate()` 시 청산 대금 직접 입금 (주문 엔진 우회) |
| **종목 DB** | 포트폴리오가 참조 | `get_stock(stock_id)` → 종목명/섹터 등 표시 정보 |
| **시즌/대회 관리** | 시즌이 참조 | `get_total_assets()`, `get_return_rate()` → 캐시된 값으로 순위 산출. `force_liquidate(price_provider)` → 강제 청산. `reset()` → 시즌 리셋 |
| **포트폴리오 UI** | UI가 참조 | `get_all_holdings()`, `get_total_assets()`, `get_return_rate()`, `get_transaction_history()` |
| **트레이딩 스크린** | UI가 참조 | `get_portfolio_summary()` → 캐시된 값으로 PortfolioSummary 조립. 내부적으로 `SkillTree.get_max_holdings()`를 호출하여 슬롯 정보를 조회한다 |
| **스킬 트리** | 포트폴리오가 참조 | `get_max_holdings()` → max_holdings 결정 |

## Formulas

### F1. 평균 매수가 (추가 매수 시)

```
avg_buy_price = floor(total_invested / quantity)
total_invested = Σ(buy_price_i × buy_quantity_i) for all buy transactions of this stock
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `total_invested` | int | 1+ | calculated | 이 종목에 투입한 총 금액 |
| `quantity` | int | 1+ | holding | 현재 보유 수량 |
| `avg_buy_price` | int | 1+ | calculated | 주당 평균 매수 단가 |

**예시**: 메디진 3주 @ 180,000 + 2주 @ 190,000
- `total_invested = 540,000 + 380,000 = 920,000`
- `avg_buy_price = floor(920,000 / 5) = 184,000원`

### F2. 미실현 손익 (종목별)

```
unrealized_pnl = (current_price - avg_buy_price) × quantity
unrealized_pnl_pct = unrealized_pnl / total_invested × 100
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `current_price` | int | 1+ | 가격 엔진 | 현재 주가 |
| `unrealized_pnl` | int | 음수 가능 | calculated | 미실현 손익 금액 |
| `unrealized_pnl_pct` | float | -100%~∞ | calculated | 미실현 수익률 |

**예시**: 스타칩 10주, avg=65,000, current=71,500
- `unrealized_pnl = (71,500 - 65,000) × 10 = 65,000원`
- `unrealized_pnl_pct = 65,000 / 650,000 × 100 = 10.0%`

### F3. 실현 손익 (매도 시)

```
realized_pnl = (sell_price - avg_buy_price) × sell_quantity
```

매도 후 잔여 보유분의 avg_buy_price는 변하지 않음.

**예시**: 위 스타칩에서 5주 @ 71,500 매도
- `realized_pnl = (71,500 - 65,000) × 5 = 32,500원`
- 잔여 5주의 avg_buy_price = 여전히 65,000원

### F4. 대회 내 계좌 총 평가금액

```
account_total_value = sim_cash + reserved_cash + Σ(holding_i.quantity × current_price_i)
```

> **주의**: `account_total_value`는 3층 자산 구조의 2층(대회 계좌)만 반영한다.
> 현금 자산(`cash_assets`) 및 유형 자산(`tangible_assets`)은 포함하지 않는다.
> 게임 내 전체 자산 합계는 `cash_assets + account_total_value + tangible_assets`.

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `sim_cash` | int | 0+ | 재화 시스템 | 예수금 잔액 (지정가 예약금 차감 후) |
| `reserved_cash` | int | 0+ | 주문 엔진 | 미체결 지정가 매수 주문의 예약금 합계. `Σ(pending_buy_limit.reserved_cash)` |
| `account_total_value` | int | 0+ | calculated | 현금 + 예약금 + 보유 주식 평가액 (= `get_total_assets()` 반환값) |

`reserved_cash`는 `sim_cash`에서 이미 선차감된 금액이다. 총 자산에 합산하지 않으면
지정가 매수 제출 시 총 자산이 예약금만큼 감소하여 플레이어에게 오해를 줄 수 있다.
체결 시 `reserved_cash` → 주식 평가액으로, 만료/취소 시 `reserved_cash` → `sim_cash`로
전환되므로 총 자산은 항상 일관된다.

**예시**: sim_cash=300,000, reserved_cash=200,000, 스타칩 10주×71,500=715,000
- `account_total_value = 300,000 + 200,000 + 715,000 = 1,215,000원`

### F5. 대회 수익률

```
return_rate = (account_total_value - season_start_deposit) / season_start_deposit × 100
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `season_start_deposit` | int | 변동 (첫 시즌 1,000,000) | 재화 시스템 | 시즌 시작 시 예수금 자동 입금액 스냅샷 (= `CurrencySystem.season_start_deposit`) |
| `return_rate` | float | -100%~∞ | calculated | 대회 수익률 (%) |

**예시**: `return_rate = (1,015,000 - 1,000,000) / 1,000,000 × 100 = 1.5%`

### F6. 포트폴리오 비중

```
if account_total_value == 0:
    weight_i = 0.0
    cash_weight = 0.0
    reserved_weight = 0.0
else:
    weight_i = (holding_i.quantity × current_price_i) / account_total_value × 100
    cash_weight = sim_cash / account_total_value × 100
    reserved_weight = reserved_cash / account_total_value × 100
```

전 보유 종목의 weight + cash_weight + reserved_weight = 100%.
`reserved_cash`는 `OrderEngine.get_total_reserved_cash()`에서 조회한다.
`reserved_cash = 0`이면 reserved_weight가 0이 되어 UI에 표시하지 않는다.
`account_total_value = 0`은 예수금 전액 손실 시 발생할 수 있다.
방어 코드로 weight 0% 반환, 빈 상태 메시지 표시.

### 변수 마스터 테이블

| Variable | Default | Range | Owner | Description |
|----------|---------|-------|-------|-------------|
| `max_holdings_p0` | 3 | 1~5 | config | P0 동시 보유 종목 수 |
| `max_holdings_p1` | 5 | 3~7 | config | P1 동시 보유 종목 수 |
| `max_holdings_p2` | 10 | 5~15 | config | P2 동시 보유 종목 수 |
| `season_start_deposit` | 변동 (tier_threshold) | N/A | 재화 시스템 | 시즌 시작 시 예수금 자동 입금액 (= `CurrencySystem.auto_deposit_to_sim()` 결과, 첫 시즌 1,000,000) |

> **초기화 순서**: `season_start_deposit`는 `on_season_start` 시그널 수신 시 `CurrencySystem.get_season_start_deposit()`을 호출하여 스냅샷한다. XP 시스템도 동일 시점에 동일 값을 스냅샷하므로 단일 소스(CurrencySystem)에서 읽어 일관성을 보장한다.

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 전량 매도 후 동일 종목 재매수 | 새로운 HoldingEntry 생성. 이전 평균 매수가는 무관 | 청산 후 재진입은 새 포지션 |
| 동일 종목 반복 매수 (5회 연속) | 매번 avg_buy_price 재계산. 모든 거래 TransactionRecord에 기록 | 물타기/불타기 전략 지원 |
| 전량 매도 시 holdings 정리 | holdings에서 해당 종목 제거. holding_count 감소. 새 종목 매수 가능 | 슬롯 즉시 해제 |
| 시즌 종료 시 보유 종목 존재 | **오케스트레이터: 시즌/대회 관리 시스템** (Game Clock `on_season_end` 수신 후 실행). 강제 청산 시퀀스: ①시즌 관리가 주문 엔진에 `expire_all_pending()` 호출 → 미체결 전량 EXPIRED + 예약/잠금 복원 → ②시즌 관리가 포트폴리오에 `force_liquidate(price_provider)` 호출 → 아래 상세 참조 → ③포트폴리오 `get_total_assets()` → account_total_value 최종 스냅샷 (순위용) → ④시즌 관리가 재화 시스템 `settle_to_cash(prize)` 호출 → sim_cash + 상금 → cash_assets, sim_cash = 0 → ⑤시즌 관리가 포트폴리오 `reset()` 호출. **트리거 시점**: MARKET_CLOSED 직후, 플레이어에게 리포트를 표시하기 전에 ①~③ 실행하여 최종 자산 확정. 리포트 확인 후 ④~⑤ 실행. **`force_liquidate(price_provider)` 상세**: 주문 엔진을 거치지 않고 직접 처리. `for each holding: sell_price = price_provider.get_current_price(stock_id)` → `realized_pnl = (sell_price - avg_buy_price) × quantity` → TransactionRecord(type=SELL) 기록 → `currency.sim_add(sell_price × quantity)` 직접 호출 → `holdings.remove(stock_id)`. `on_order_filled` 시그널 미발행 (주문 엔진 비경유). | 순위 확정 필요. 가격 엔진은 마지막 틱 가격을 리셋 전까지 유지. 시즌/대회 관리가 V-Slice에서 구현 시 상세 설계 |
| ①~③ 실행 중 게임 크래시 | **MVP 미대응**. 재시작 시 시즌 종료 직전 세이브에서 복구, ①부터 재실행. 원자성 보장은 세이브/로드 GDD에서 설계 | 시즌 정산은 단일 프레임 내 완료 가능 (46종목 청산 ~1ms). 크래시 확률 극히 낮음 |
| 보유 종목 0개 상태에서 총 자산 조회 | account_total_value = sim_cash. 보유 주식 평가액 = 0 | 정상 작동 |
| 가격이 매우 높은 종목 (320,000원) 1주 매수 | 정상 처리. 금액 제한은 주문 엔진이 sim_cash 기준으로 검증 | 포트폴리오는 체결 후만 관여 |
| floor() 반올림으로 1원 오차 | 허용. 모든 금액은 floor() 후 정수. 누적 오차 최대 보유 종목 수만큼 | 정수 원칙 일관 유지 |
| get_return_rate() 호출 시 season_start_deposit가 0 | 예수금 전액 손실 후 새 시즌 시작 시 발생 가능. 방어 코드로 return_rate = 0% 반환 | 0으로 나누기 방지. 완주 보너스(30,000원)로 복귀 |
| 스킬 레벨 다운그레이드 (현재 보유 > 새 한도) | 발생 불가 (스킬은 영구 해금). 만약 발생 시 기존 보유 유지, 추가 매수만 차단 | 플레이어 자산 보호 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| 주문 처리 엔진 | 주문 엔진 → 포트폴리오 | 체결 통보로 보유 종목 갱신. **Hard** |
| 가격 엔진 | 포트폴리오가 참조 | 현재가로 평가 금액 계산. **Hard** |
| 재화 시스템 | 포트폴리오가 참조 | `get_sim_cash()` → 현금 잔액 조회. `sim_add(amount)` → `force_liquidate()` 시 청산 대금 직접 입금 (주문 엔진 우회). **Hard** |
| 종목 DB | 포트폴리오가 참조 | 종목 정보 표시용. **Soft** |
| 시즌/대회 관리 | 시즌이 참조 | `get_total_assets()`, `get_return_rate()` → 순위 산출. `force_liquidate(price_provider)` → 강제 청산 (Step ②). `reset()` → 시즌 리셋 (Step ⑤). **Hard** (시즌 입장) |
| 포트폴리오 UI | UI가 참조 | 보유 종목/손익 표시. **Soft** |
| 트레이딩 스크린 | UI가 참조 | 사이드바 요약 표시. **Soft** |
| 스킬 트리 | 포트폴리오가 참조 | `get_max_holdings()` → max_holdings 결정. **Soft** (미구현 시 P0 기본값 3) |
| 경험치 시스템 | XP가 참조 | `get_return_rate()` → 일일/시즌 수익률 산출. **Soft** |

이 시스템은 재화 시스템, 종목 DB에 의존하는 Core 시스템이다.

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `max_holdings_p0` | 3 | 1~5 | 초보자도 분산 가능 | 극단적 집중 투자 강제 |
| `max_holdings_p1` | 5 | 3~7 | P1 해금 가치 감소 | P1 해금 가치 증가 |
| `max_holdings_p2` | 10 | 5~15 | 전 종목 보유 가능 | 고레벨에서도 선택 필요 |
| `transaction_history_limit` | 200 | 50~500 | 메모리 사용 증가 | 오래된 거래 조회 불가 |
| `valuation_update_interval` | 1틱 | 1~5틱 | UI 갱신 빈도 감소. 성능 개선 | 실시간 피드백 향상. 성능 부담 증가 |

## Acceptance Criteria

- [ ] 매수 체결 시 HoldingEntry가 정확히 생성/갱신됨
- [ ] 매도 체결 시 보유 수량이 정확히 차감됨
- [ ] 전량 매도 시 holdings에서 종목이 완전히 제거됨
- [ ] 추가 매수 시 avg_buy_price가 가중평균으로 정확히 재계산됨
- [ ] 매도 시 avg_buy_price가 변하지 않음
- [ ] unrealized_pnl이 (current_price - avg_buy_price) × quantity와 일치
- [ ] realized_pnl이 (sell_price - avg_buy_price) × sell_quantity와 일치
- [ ] account_total_value = sim_cash + reserved_cash + Σ(quantity × current_price)  (= get_total_assets() 반환값)
- [ ] return_rate = (account_total_value - season_start_deposit) / season_start_deposit × 100
- [ ] 보유 종목 수가 max_holdings를 초과하지 않음
- [ ] 시즌 종료 시 종가 기준 강제 청산 후 전체 리셋
- [ ] 시즌 리셋 후 holdings 빈 상태, 거래 내역 초기화
- [ ] 모든 금액이 정수(원 단위) — 소수점 없음
- [ ] 모든 체결이 TransactionRecord에 기록됨
- [ ] 성능: 틱당 전체 보유 종목 평가 갱신 0.5ms 이내

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|------------|
| 시즌 종료 강제 청산의 정확한 시점 — 마지막 틱 종가 vs 장 마감 후 별도 처리 | game-designer | 시즌 관리 GDD 시 | 잠정 결정: MARKET_CLOSED 직후 ①~③(청산+스냅샷) 실행, 리포트 확인 후 ④~⑤(리셋). 시즌/대회 관리가 오케스트레이터. 시즌 관리 GDD에서 최종 확정 |
| 거래 내역 시즌 간 보존 여부 — 이전 시즌 기록 열람 가능? | game-designer | 세이브/로드 GDD 시 | 미정. 영향: TransactionRecord 보관 범위 (현 설계: 시즌 내 전체 보존). 세이브/로드 GDD에서 결정 전까지 현 범위 유지. |
| RealPortfolio 확장 시 수수료/배당 처리 | systems-designer | 확장 시점 | 향후 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 기능 | 진입점 |
|------|--------|
| 보유 추가 | `order_engine.gd._fill_*_order()` → `PortfolioManager.add_holding(stock_id, qty, price)` |
| 보유 제거 | `order_engine.gd._fill_*_order()` → `PortfolioManager.remove_holding(stock_id, qty, price)` |
| 강제 청산 | `season_manager.gd._force_liquidate_all()` → `PortfolioManager.remove_holding(...)` |
| 총 자산 계산 | `season_manager.gd.get_season_return_pct()` → `PortfolioManager.get_total_assets()` |

### 호출 경로

- [x] `PortfolioManager.add_holding(stock_id, qty, price)` 존재
- [x] `PortfolioManager.remove_holding(stock_id, qty, price)` 존재
- [x] `PortfolioManager.get_total_assets() -> int` 존재
- [x] `PortfolioManager.get_all_holdings() -> Array[Dictionary]` 존재
- [x] `PortfolioManager.update_valuation(cash, reserved)` 존재
- [x] `PortfolioManager.reset()` 존재

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 | 상태 |
|----|------------|------------|------|
| 보유 추가/조회 | `tests/unit/test_api_contracts.gd` | `test_portfolio_manager_api()` | ✅ |
| 총 자산 계산 | 통합 — OrderEngine 테스트 내 | — | ⬜ 단독 테스트 없음 |

### 빌드 검증

- [ ] 바이너리 실행 확인: QA Lead 서명 _______
