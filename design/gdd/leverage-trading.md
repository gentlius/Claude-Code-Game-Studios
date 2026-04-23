# TR4 레버리지 거래 (Leverage Trading)

> **Status**: In Review (S10-03 Beta 구현 완료 — Steam 업적·Polish UI·빌드검증 잔여)
> **Author**: user + game-designer
> **Last Updated**: 2026-04-23
> **Implements Pillar**: 판단이 곧 실력 (Judgment is King), 체감있는 성장 (Feel the Growth)
> **Skill Prerequisite**: TR4 (requires TR3 공매도 해금)

---

## 1. Overview

TR4 레버리지 거래는 플레이어가 자기자본의 최대 5배까지 차입하여 매수 포지션을
운용할 수 있는 고위험-고수익 Gameplay 시스템이다. 스킬 트리 거래 브랜치의 최종
단계(TR4)로, TR3(공매도) 해금 이후 접근 가능하다. 플레이어는 배율(2×/3×/5×)을
선택해 자기자본보다 큰 포지션을 취하고, 매 거래일 이자가 자동 차감된다. 포지션
가치가 하락하여 equity 비율이 유지증거금률 아래로 떨어지면 마진콜이 발동하고,
equity가 0 이하로 떨어지면 전량 강제청산이 실행된다. 시즌 종료 시 모든 레버리지
포지션은 자동 청산되며 이자가 최종 정산된다.

---

## 2. Player Fantasy

**MDA 타깃 Aesthetics**: Challenge(긴장), Sensation(짜릿함), Expression(전략 표현)

뉴스가 터졌다. 바이오주 대형 호재 — 근데 내 현금은 200만 원뿐이다. 레버리지 5×를
건다. 1,000만 원어치 매수. 주가가 10% 오르면 평상시의 5배 수익이다.

화면에 "×5 레버리지 — 이자 0.10%/일" 배지가 뜬다. 차트가 올라가는 동안 수익
숫자가 실시간으로 뛴다. "빚으로 버는 돈의 맛"이다.

하지만 주가가 반대 방향으로 가면 손실도 5배다. 마진콜 경고가 뜬다. "지금 일부
청산하겠습니까?" 판단의 무게가 배가된다. 레버리지는 분석의 확신이 만들어낸 배팅이다.
틀리면 더 빠르게 무너진다. 맞으면 시즌 순위가 한번에 뒤집힌다.

필라 "판단이 곧 실력"에 따라, 레버리지는 분석 실력이 수익률을 극대화하는 도구다.
사용 자체가 아닌 **언제, 어떤 배율로, 어느 종목에 쓰느냐**가 실력의 표현이다.

---

## 3. Detailed Design

### 3-1. 레버리지 매수 프로세스

#### 전제 조건 검증

레버리지 매수 주문 제출 시 기존 OrderEngine 검증(9단계) 외 추가 검증:

```
10. 스킬 해금 검증 (레버리지 전용)
    - SkillTree.has_skill("TR4") == false → REJECTED ("레버리지 거래가 해금되지 않았습니다")

11. 배율 유효성
    - leverage_multiplier not in {2, 3, 5} → REJECTED ("유효하지 않은 배율입니다")

12. 레버리지 매수 가능 잔액 검증
    - required_equity = ceil(order_value / leverage_multiplier)
    - required_equity > available_cash → REJECTED ("레버리지 매수에 필요한 증거금이 부족합니다")
    - 여기서 order_value = current_price × quantity (시장가) 또는 limit_price × quantity (지정가)
```

#### 매수 체결 처리

레버리지 매수가 체결되면 OrderEngine은 다음을 수행한다:

```
on leverage_buy filled:
    order_value    = filled_price × quantity
    equity_used    = ceil(order_value / leverage_multiplier)   # 자기자본 투입분
    borrowed       = order_value - equity_used                 # 차입금

    # 1) 자기자본(증거금)만 투자 계좌(sim_cash)에서 차감 (B-01 fix: cash_deduct → sim_deduct)
    CurrencySystem.sim_deduct(equity_used)

    # 2) 포트폴리오에 레버리지 포지션으로 추가
    PortfolioManager.add_leverage_holding(
        stock_id       = order.stock_id,
        quantity       = quantity,
        entry_price    = filled_price,
        multiplier     = leverage_multiplier,
        borrowed       = borrowed
    )
```

#### 레버리지 포지션 데이터 구조

```
LeveragePosition {
    stock_id        : string
    quantity        : int
    entry_price     : int           # 최초 체결가 (원)
    multiplier      : int           # 2 | 3 | 5
    borrowed        : int           # 총 차입금 (원). 추가 매수 시 누적
    accrued_interest: int           # 누적 이자 (원). 매일 가산
    open_day        : int           # 포지션 개설 거래일 (1~20)
}
```

복수의 레버리지 포지션(동일 종목, 다른 배율)은 각각 독립적인 `LeveragePosition`으로 관리한다.
동일 종목에 대해 일반 보유(HoldingEntry)와 레버리지 포지션(LeveragePosition)이
공존할 수 있으며, 매도 시 각각 독립적으로 처리된다.

---

### 3-2. 일별 이자 차감 타이밍

이자는 **매 거래일 장 마감(MARKET_CLOSED) 직후**, GameClock의 `on_market_close` 이벤트에서 처리된다.
`LifestyleManager.process_market_close()` 호출 전에 실행되어 당일 비용이 먼저 정산된다.

```
on_market_close(day, week):
    LeverageManager.process_daily_interest(day)

process_daily_interest(day):
    for each position in all_leverage_positions:
        daily_rate    = get_daily_rate(position.multiplier)
        interest      = floor(position.borrowed × daily_rate)
        position.accrued_interest += interest

        available = CurrencySystem.get_sim_cash()
        if available >= interest:
            CurrencySystem.sim_deduct(interest)   # B-01 fix: 투자 계좌에서 차감
        else:
            # 현금 부족 → 가용 현금 전액 차감 후 부족분을 차입금에 가산
            shortage = interest - available
            CurrencySystem.sim_deduct(available)  # B-01 fix: 투자 계좌에서 차감
            position.borrowed += shortage   # 이자가 원금화 (복리 효과)
            emit leverage_interest_shortage(position.stock_id, shortage)
            # UI: 경고 토스트 "이자 부족 — 차입금에 가산됨"
```

**이자율 테이블** (배율별 일별 이율):

| 배율 | 일별 이율 | 20일 시즌 누적 (단리 근사) |
|------|----------|--------------------------|
| 2×   | 0.04%    | ~0.80%                   |
| 3×   | 0.06%    | ~1.20%                   |
| 5×   | 0.10%    | ~2.00%                   |

---

### 3-3. 마진콜 및 강제청산 흐름

#### Equity 계산

```
position_market_value = current_price × quantity                           # 포지션 현재 시가
equity                = position_market_value - borrowed - accrued_interest # 순자산 (B-02 fix: accrued_interest 포함)
equity_ratio          = equity / position_market_value                      # 유지증거금 비율
```

> **B-02 수정**: 이전에는 `equity = position_market_value - borrowed`로 정의하여 누적 이자(accrued_interest)를 누락했다.
> `skill-tree.md §F4`의 정의 `equity = position_market_value - borrowed - accrued_interest`와 일치시켰다.
> 누적 이자가 클수록 실제 equity가 GDD §3-3 이전 수식보다 낮으므로, 마진콜이 더 일찍 발동한다.

#### 마진콜 발동 조건

```
마진콜 조건: equity_ratio < margin_call_threshold
기본값:
    2× 배율: margin_call_threshold = 0.30  (포지션 가치의 30% 미만)
    3× 배율: margin_call_threshold = 0.20
    5× 배율: margin_call_threshold = 0.15
```

마진콜 발동 시:

1. UI 경고 팝업: "마진콜 — 현재 equity 비율 N%. 유지하려면 증거금을 추가하거나 포지션을 일부 청산하세요."
2. 플레이어 선택 (MARKET_OPEN 상태에서만 가능):
   - **증거금 추가**: 현금 → 차입금 상환 (borrowed 감소). `add_margin(amount)` 호출
   - **일부 청산**: 마진콜 조건을 벗어날 때까지 최소 수량 시장가 매도 자동 실행
   - **무시**: 강제청산 임계값까지 포지션 유지. 추가 하락 시 강제청산 발동

마진콜은 **매 틱** 체크한다 (틱 처리 순서: 뉴스 → 가격 갱신 → 주문 체결 → StopTakeSystem → **마진콜 체크**).

#### 강제청산 발동 조건

```
강제청산 조건: equity ≤ 0  OR  equity_ratio < forced_liquidation_threshold
기본값:
    2× 배율: forced_liquidation_threshold = 0.10
    3× 배율: forced_liquidation_threshold = 0.07
    5× 배율: forced_liquidation_threshold = 0.05
```

강제청산 처리:

```
on_forced_liquidation(position):
    # 현재가로 전량 시장가 매도
    proceeds = current_price × position.quantity
    net_proceeds = proceeds - position.borrowed - position.accrued_interest

    if net_proceeds > 0:
        CurrencySystem.sim_add(net_proceeds)    # 잔여 equity 환원
    else:
        # net_proceeds ≤ 0 → 잔여 손실은 sim_cash에서 추가 차감
        loss = abs(net_proceeds)
        available = CurrencySystem.get_sim_cash()
        CurrencySystem.sim_deduct(min(loss, available))  # 가용 현금 전액 차감
        if loss > available:
            # 초과 손실 — 채무 상환 불능 → 사채업자 엔딩 즉시 발동
            emit on_loan_shark_ending_triggered(position.stock_id, net_proceeds)
            return  # 게임오버 처리는 연결된 핸들러(GameMain/MainScreen)가 담당

    PortfolioManager.remove_leverage_holding(position.stock_id, position.quantity)
    emit leverage_forced_liquidation(position.stock_id, net_proceeds)
    # UI: "강제청산 완료 — [종목명] N주 청산. 손익: ±N원"
```

---

### 3-4. 레버리지 포지션 매도 (플레이어 자발적 청산)

플레이어가 레버리지 포지션을 수동으로 청산할 때:

```
on leverage_sell filled:
    proceeds         = filled_price × quantity
    # 비례 차입금 상환
    partial_borrowed = floor(position.borrowed × (quantity / position.quantity))
    partial_interest = floor(position.accrued_interest × (quantity / position.quantity))
    net              = proceeds - partial_borrowed - partial_interest

    if net > 0:
        CurrencySystem.sim_add(net)               # B-01 fix: 투자 계좌로 입금
    else:
        loss = abs(net)
        available = CurrencySystem.get_sim_cash()
        CurrencySystem.sim_deduct(min(loss, available))  # B-01 fix: 투자 계좌에서 차감

    position.borrowed          -= partial_borrowed
    position.accrued_interest  -= partial_interest
    position.quantity          -= quantity

    if position.quantity == 0:
        PortfolioManager.remove_leverage_holding(position.stock_id)
```

---

### 3-5. 시즌 종료 자동 청산

시즌 종료 시퀀스 내 기존 일반 보유 청산(§SeasonManager Step ②) 직전에 실행:

```
[시즌 종료 Step ①-b] 레버리지 포지션 전량 청산 (종가 기준)
    for each position in all_leverage_positions:
        on_forced_liquidation(position)   # 동일 강제청산 로직 재사용
    # 이자 잔액까지 포함하여 최종 정산
```

---

### 3-6. UI 상태 표시

트레이딩 스크린 포트폴리오 사이드바에 레버리지 포지션 별도 섹션 표시:

| 필드 | 표시 |
|------|------|
| 종목명 (코드) | 예: 스타칩 (ST001) |
| 배율 배지 | ×2 / ×3 / ×5 (색상: 주황) |
| 수량 | N주 |
| 현재 손익 (%) | +N% / -N% (빨강/파랑) |
| equity 비율 | N% (마진콜 임박 시 강조) |
| 누적 이자 | -N원 |

TR4 미해금 시 배율 선택 UI(콤보박스)는 잠금 상태로 표시되며, "TR4 해금 필요" 툴팁을 제공한다.

---

## 4. Formulas

### F1. 레버리지 매수 — 자기자본(증거금) 계산

```
order_value   = filled_price × quantity
equity_used   = ceil(order_value / multiplier)
borrowed      = order_value - equity_used
```

| Variable      | Type  | Range           | Source      | Description          |
|---------------|-------|-----------------|-------------|----------------------|
| `filled_price`| int   | 1+              | 가격 엔진   | 체결 시점 현재가       |
| `quantity`    | int   | 1+              | 플레이어    | 매수 수량              |
| `multiplier`  | int   | {2, 3, 5}       | 플레이어    | 레버리지 배율          |
| `equity_used` | int   | 1+              | calculated  | 자기자본 투입분 (증거금) |
| `borrowed`    | int   | 0+              | calculated  | 차입금                |

**예시 (2× 배율)**:
- 스타칩 100주, 체결가 65,000원
- `order_value = 65,000 × 100 = 6,500,000원`
- `equity_used = ceil(6,500,000 / 2) = 3,250,000원` → 현금 차감
- `borrowed = 6,500,000 - 3,250,000 = 3,250,000원`

**예시 (5× 배율)**:
- 스타칩 100주, 체결가 65,000원
- `order_value = 6,500,000원`
- `equity_used = ceil(6,500,000 / 5) = 1,300,000원` → 현금 차감
- `borrowed = 6,500,000 - 1,300,000 = 5,200,000원`

---

### F2. 일별 이자

```
daily_rate = get_daily_rate(multiplier)
    # 2× → 0.0004, 3× → 0.0006, 5× → 0.001

daily_interest = floor(borrowed × daily_rate)
```

| Variable        | Type  | Range    | Source      | Description        |
|-----------------|-------|----------|-------------|--------------------|
| `borrowed`      | int   | 0+       | 포지션 데이터 | 현재 차입금         |
| `daily_rate`    | float | 0.0001~  | config      | 배율별 일별 이율    |
| `daily_interest`| int   | 0+       | calculated  | 당일 이자 (원, floor) |

**예시 (2× 배율, borrowed=3,250,000원)**:
- `daily_interest = floor(3,250,000 × 0.0004) = floor(1,300) = 1,300원`
- 20거래일 누적 = 26,000원 (단리 근사)

**예시 (5× 배율, borrowed=5,200,000원)**:
- `daily_interest = floor(5,200,000 × 0.001) = 5,200원`
- 20거래일 누적 = 104,000원 (단리 근사)

---

### F2b. 이자 현금 부족 시 차입금 누적 (복리 효과)

이자 납부 시 가용 현금이 부족하면 부족분이 차입금에 가산된다. 이자가 원금화(capitalised)되어
다음 날 이자 계산 기준이 증가한다.

```
available_cash = CurrencySystem.get_sim_cash()

if daily_interest ≤ available_cash:
    # 정상 이자 차감 (투자 계좌에서)
    CurrencySystem.sim_deduct(daily_interest)     # B-01 fix: cash_deduct → sim_deduct
    position.accrued_interest += daily_interest
else:
    # 현금 부족 → 가용 전액 차감 + 부족분 차입금 가산
    shortage = daily_interest - available_cash
    CurrencySystem.sim_deduct(available_cash)     # B-01 fix: cash_deduct → sim_deduct
    position.borrowed        += shortage  # 원금화: 다음 날 이자 계산 기준 증가
    position.accrued_interest += daily_interest
```

| 변수 | 타입 | 범위 | 출처 | 설명 |
|------|------|------|------|------|
| `available_cash` | int | 0+ | CurrencySystem | 납부 시점 가용 예수금 |
| `shortage` | int | 0+ | calculated | 이자 미납분. `position.borrowed`에 가산 |
| `position.borrowed` | int | 0+ | 포지션 데이터 | 가산 후 다음 틱 이자 계산 기준 증가 |
| `position.accrued_interest` | int | 0+ | 포지션 데이터 | 누적 이자 — 청산 시 상환 기준 |

**예시 (5× 배율, borrowed=5,200,000, 현금 3,000원만 보유)**:
- `daily_interest = 5,200원`, `available_cash = 3,000원`
- `shortage = 2,200원` → `borrowed = 5,202,200원`
- Day+1 이자 = `floor(5,202,200 × 0.001) = 5,202원` (Day 대비 2원 증가)
- 고액·장기 포지션에서 복리 부담이 누적됨

---

### F3. Equity 및 마진콜 조건

```
position_market_value = current_price × quantity
equity                = position_market_value - borrowed - accrued_interest
equity_ratio          = equity / position_market_value
```

| Variable               | Type  | Range    | Source      | Description              |
|------------------------|-------|----------|-------------|--------------------------|
| `current_price`        | int   | 1+       | 가격 엔진   | 현재 시가                 |
| `quantity`             | int   | 1+       | 포지션 데이터 | 보유 수량                |
| `borrowed`             | int   | 0+       | 포지션 데이터 | 미상환 차입금             |
| `accrued_interest`     | int   | 0+       | 포지션 데이터 | 누적 이자                |
| `equity`               | int   | 임의 부호 | calculated  | 순자산. 음수 가능         |
| `equity_ratio`         | float | 0~1      | calculated  | 유지증거금 비율           |

**마진콜 임계 가격 계산** (2× 예시, equity_used=3,250,000, borrowed=3,250,000):
- `margin_call_threshold = 0.30`
- 마진콜 발동 최저가: `P_mc × 100 - 3,250,000 = 0.30 × (P_mc × 100)` → `P_mc = 3,250,000 / (100 × 0.70) = 46,429원`
- 강제청산 최저가(`threshold=0.10`): `P_liq = 3,250,000 / (100 × 0.90) = 36,111원`

**예시 (5× 배율, entry=65,000원, qty=100주)**:
- `equity_used = 1,300,000, borrowed = 5,200,000`
- `margin_call_threshold = 0.15`
- `P_mc = 5,200,000 / (100 × 0.85) = 61,176원` (진입가의 ~5.9% 하락)
- `forced_liq_threshold = 0.05`: `P_liq = 5,200,000 / (100 × 0.95) = 54,737원`

---

### F4. 레버리지 매도 순수익

```
proceeds         = filled_price × quantity
partial_borrowed = floor(position.borrowed × (quantity / position.quantity))
partial_interest = floor(position.accrued_interest × (quantity / position.quantity))
net_proceeds     = proceeds - partial_borrowed - partial_interest
```

**예시**: 2× 포지션, 100주 전량 청산, 체결가 70,000원
- `proceeds = 70,000 × 100 = 7,000,000원`
- `partial_borrowed = 3,250,000원, partial_interest = 26,000원 (20일 누적)`
- `net_proceeds = 7,000,000 - 3,250,000 - 26,000 = 3,724,000원`
- 투입 자기자본 3,250,000원 대비 수익 474,000원 (+14.6%)
- 레버리지 없이 동일 투자 시: (70,000-65,000)×100 = 500,000원 수익, 투입 6,500,000원 대비 +7.7%

---

## 5. Edge Cases

| 시나리오 | 처리 방식 | 근거 |
|---------|----------|------|
| **이자 > 현금 잔고** | 가용 현금 전액 차감 후 부족분을 `borrowed`에 가산. UI 경고 토스트 표시. | 빚이 빚을 낳는 복리 메커니즘으로 위험 실감. 강제청산은 equity_ratio로 별도 판단. |
| **시즌 종료 시 레버리지 포지션 보유** | 종가 기준 강제청산 → 차입금·이자 상환 → 잔여 proceeds(또는 손실)를 sim_cash 반영 후 SeasonManager Step ②(일반 보유 청산) 진행. | 시즌 정산 전 레버리지 청산 완료 보장. |
| **강제청산 후 net_proceeds < 0 — 손실 ≤ 가용 현금** | 손실분을 sim_cash에서 차감. sim_cash = 0이 됨. 이후 프리마켓에서 한강 엔딩 가능. | 점진적 파산 경로. 한강 엔딩과 동일한 결말로 수렴. |
| **강제청산 후 net_proceeds < 0 — 손실 > 가용 현금 (채무 상환 불능)** | 가용 현금 전액 차감 후 `on_loan_shark_ending_triggered` 발동 → 즉각 게임오버 (사채업자 엔딩). 시즌 종료까지 기다리지 않음. | 레버리지 청산으로 채무 상환 불능 시 더 가혹한 결과. 한강 엔딩(점진적 자산 소진)과 다른 경로. |
| **복수 레버리지 포지션 동일 종목 (다른 배율)** | 각 `LeveragePosition`을 독립 관리. 마진콜·강제청산은 포지션별 독립 계산. 매도 시 FIFO 순서로 포지션 선택. | 복잡도 감소. FIFO는 선입선출로 예측 가능한 동작 보장. |
| **복수 레버리지 포지션 동일 종목 (동일 배율)** | 동일 배율이면 기존 포지션에 `borrowed`·`quantity`·`accrued_interest` 누적. 별도 포지션 추가 없음. | UI 단순화. |
| **마진콜 상태에서 장 마감** | 마진콜 경고 유지. 강제청산 조건 미달이면 다음 거래일에 포지션 유지. 장 마감 전 플레이어가 미조치한 경우 알림 보존. | 강제청산 조건은 별도 임계값. 마진콜은 경고이지 강제청산 아님. |
| **마진콜 발동 시점에 추가 이자 차감** | 이자 처리는 장 마감 시 일괄 처리. 마진콜 체크는 틱마다 실시간. 이자 차감으로 equity_ratio가 강제청산 임계값을 순간 통과하면 다음 틱에 강제청산. | "틱이 진실" 원칙. 이자 차감은 틱 사이(장 마감)에 발생하므로 다음 시장 개장 첫 틱에 강제청산 체크. |
| **TR4 미해금 상태에서 API 직접 호출** | OrderEngine 검증(스텝 10)에서 REJECTED. 서버 측 검증이므로 UI 우회 불가. | 스킬 게이팅 무결성 보장. |
| **PRE_MARKET 상태에서 레버리지 주문** | 기존 PRE_MARKET 시장가 주문 흐름과 동일. 예약금 = `ceil(current_price × 1.15 / multiplier) × quantity` 차감. 틱 0 체결 후 실제 equity 계산. | PRE_MARKET 버퍼 로직 재사용. 증거금만 예약 차감(차입금 아님). |
| **레버리지 + 일반 보유 동일 종목 혼재 매도** | 매도 주문 제출 시 플레이어가 "일반 보유" 또는 "레버리지 포지션" 구분하여 선택. UI에서 별도 섹션으로 표시. | 포지션 혼용 방지. 명시적 선택으로 실수 차단. |
| **equity가 정확히 0** | 강제청산 조건(`equity ≤ 0`)에 해당 → 강제청산 실행. | 경계값 포함 처리. |
| **레버리지 포지션 보유 중 시즌 도중 TR4 스킬 비활성화** | 스킬 해금은 비가역(GDD 스킬 트리 §규칙 2). 해당 케이스 불가. | 스킬 트리 리스펙 없음 원칙. |

---

## 6. Dependencies

| 시스템 | 방향 | 의존 성격 | 인터페이스 |
|--------|------|----------|-----------|
| **OrderEngine** | 레버리지가 의존 | Hard | `submit_order()` 확장: `leverage_multiplier` 파라미터 추가. 기존 9단계 검증 + 레버리지 10-12단계 추가. |
| **PortfolioManager** | 양방향 | Hard | `add_leverage_holding(stock_id, qty, entry_price, multiplier, borrowed)` 추가. `remove_leverage_holding(stock_id, qty)` 추가. `get_all_leverage_positions()` 추가. PortfolioManager는 레버리지 포지션의 `account_total_value` 기여분 계산 시 `position_market_value`(총 포지션 가치)를 포함하고 `borrowed`를 부채로 차감한다. |
| **CurrencySystem** | 레버리지가 의존 | Hard | `sim_deduct(equity_used)` — 증거금 차감 (투자 계좌). `sim_add(net_proceeds)` — 청산 순수익 입금 (투자 계좌). `get_sim_cash()` — 이자 지급 가용 현금 조회. **주의: cash_deduct/cash_add(실생활 자금)는 사용하지 않는다. 레버리지는 전부 sim(투자 계좌) 트랜잭션이다.** |
| **SkillTree** | 레버리지가 참조 | Soft | `has_skill("TR4") -> bool` — 진입 게이팅. |
| **GameClock** | 레버리지가 의존 | Hard | `on_market_close(day, week)` — 일별 이자 차감 트리거. `on_tick` — 마진콜 체크 트리거 (틱 처리 5번째 단계, StopTakeSystem.check_and_trigger 이후). |
| **SeasonManager** | 시즌이 레버리지 호출 | Soft | 시즌 종료 Step ①-b에서 `LeverageManager.liquidate_all_positions()` 호출. SeasonManager GDD(§3-1)의 종료 시퀀스에 이 단계 추가 필요. |
| **PriceEngine** | 레버리지가 의존 | Hard | `get_current_price(stock_id)` — 매 틱 equity 계산 및 마진콜 체크. |
| **TradingScreen** | UI가 레버리지 참조 | Soft | 레버리지 포지션 섹션 표시. 배율 선택 콤보박스(TR4 미해금 시 잠금). 마진콜 경고 팝업. |
| **LifestyleManager** | 간접 (순서 의존) | Soft | 이자 차감(`process_daily_interest`)은 `LifestyleManager.process_market_close()` 호출보다 먼저 실행. 순서 의존성만 존재. |
| **XPSystem** | XP가 레버리지 참조 | Soft | `on_order_filled` 이벤트 — 레버리지 거래도 기존 XP 산출 적용. 추가 XP 보정은 미정 (Open Question). |

**역방향 의존성 고지**:
- OrderEngine GDD에 "레버리지 파라미터 확장" 내용 추가 필요 (Open Question에서 Resolved로 전환).
- SeasonManager GDD Step ②에 레버리지 청산 단계(①-b) 삽입 필요.
- PortfolioManager GDD에 `LeveragePosition` 데이터 구조 및 `account_total_value` 기여분 계산 방식 추가 필요.

---

## 7. Tuning Knobs

| Parameter | Category | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|----------|--------------|------------|-------------------|-------------------|
| `leverage_daily_rate_2x` | Curve | 0.0004 (0.04%/일) | 0.0001~0.001 | 이자 부담 증가 → 장기 보유 억제. 단타 유도. | 장기 보유 유리. 이자 전략 고려 감소. |
| `leverage_daily_rate_3x` | Curve | 0.0006 (0.06%/일) | 0.0002~0.002 | 위와 동일, 3× 포지션 단기화 | 3× 장기 보유 증가 |
| `leverage_daily_rate_5x` | Curve | 0.001  (0.10%/일) | 0.0005~0.003 | 5× 이자 부담 폭증 → 초단기 사용만 의미 있음 | 5× 남용 가능성 증가 |
| `margin_call_threshold_2x` | Gate | 0.30 | 0.15~0.45 | 마진콜 빈도 증가 → 변동성 체감 강화 | 마진콜 희소 → 위험 과소 인식 |
| `margin_call_threshold_3x` | Gate | 0.20 | 0.10~0.35 | 위와 동일 | 위와 동일 |
| `margin_call_threshold_5x` | Gate | 0.15 | 0.05~0.25 | 위와 동일 | 위와 동일 |
| `forced_liq_threshold_2x` | Gate | 0.10 | 0.05~0.20 | 강제청산 빈도 증가 → 리스크 체감 강화 | 손실 확대 허용 → 더 깊이 무너짐 |
| `forced_liq_threshold_3x` | Gate | 0.07 | 0.03~0.15 | 위와 동일 | 위와 동일 |
| `forced_liq_threshold_5x` | Gate | 0.05 | 0.02~0.10 | 위와 동일 | 위와 동일 |
| `available_multipliers` | Gate | {2, 3, 5} | 부분 집합 | 고배율 접근 허용 시 리스크 노출 증가 | 고배율 제거 시 위험도 감소, 다양성 감소 |

모든 수치는 `assets/data/leverage_config.json`에 외부화. 하드코딩 금지.

> **설계 의도 명시 (W-18)**: 현재 이자율(0.04~0.10%/일)은 20일 시즌 기준 최대 누적 비용 2.0%(5×)로,
> "확신 있는 포지션에는 5× 레버리지가 합리적 선택"이 되는 수준이다. 이는 의도된 설계다.
> "고위험 도구"보다는 "분석에 자신 있을 때 쓰는 증폭기"로 포지셔닝한다.
> 만약 레버리지를 더 고위험 도구로 재포지셔닝하려면 이자율을 0.15~0.25%/일 수준으로 상향한다.
> 현재 값으로는 5× 이자 20일 = 2.0%, 단 1%만 맞아도 5% 수익이므로 이자를 크게 상회한다.

---

## 8. Acceptance Criteria

### 기능적 기준 (Functional)

| ID | 조건 | 검증 방법 |
|----|------|----------|
| AC-01 | 2× 레버리지 매수 시 `equity_used = ceil(order_value/2)` 만큼만 현금 차감되고 포지션에 `borrowed = order_value - equity_used` 기록됨 | 단위 테스트: 차감 전후 현금 비교 |
| AC-02 | 3×, 5× 배율도 동일 공식 적용. 각 배율별 `equity_used`, `borrowed` 값이 공식과 일치 | 단위 테스트: 파라미터화 테스트 |
| AC-03 | 매 거래일 장 마감 시 `floor(borrowed × daily_rate)` 이자가 정확히 차감됨 | 단위 테스트: 20일 누적 이자 검증 |
| AC-04 | 이자 > 현금 잔고 시: 가용 현금 전액 차감 + 부족분이 `borrowed`에 가산됨 | 단위 테스트: 잔고 부족 케이스 |
| AC-05 | `equity_ratio < margin_call_threshold` 조건에서 마진콜 경고 UI 발동 | 플레이테스트: 마진콜 시나리오 수동 확인 |
| AC-06 | `equity ≤ 0 OR equity_ratio < forced_liq_threshold` 조건에서 강제청산 실행 및 proceeds 정확히 정산 | 단위 테스트: 강제청산 후 현금 잔고 검증 |
| AC-07 | 강제청산 후 `net_proceeds < 0`이고 손실 ≤ 가용 현금인 경우 손실분이 `sim_cash`에서 차감되어 0이 됨 | 단위 테스트: 손실 ≤ 현금 케이스 |
| AC-17 | 강제청산 후 `net_proceeds < 0`이고 손실 > 가용 현금인 경우 가용 현금 전액 차감 후 `on_loan_shark_ending_triggered` 시그널 발동 | 단위 테스트: 시그널 수신 + sim_cash == 0 확인 |
| AC-08 | 시즌 종료 시 전체 레버리지 포지션이 종가 기준으로 청산되고 차입금·이자 상환 후 잔여 proceeds가 `sim_cash`에 반영됨 | 단위 테스트: 시즌 종료 후 포지션 0개 확인 |
| AC-09 | TR4 미해금 상태에서 레버리지 주문 시 REJECTED ("레버리지 거래가 해금되지 않았습니다") | 단위 테스트: 스킬 미해금 케이스 |
| AC-10 | 유효하지 않은 배율(예: 4×) 요청 시 REJECTED | 단위 테스트: 유효성 검증 |
| AC-11 | 복수 레버리지 포지션(동일 종목, 다른 배율) 각각 독립 마진콜 계산 | 단위 테스트: 혼합 포지션 시나리오 |
| AC-12 | 레버리지 포지션이 `account_total_value`에 `position_market_value - borrowed`로 반영됨 | 단위 테스트: ATV 계산 검증 |

### 체험적 기준 (Experiential — 플레이테스트 검증)

| ID | 조건 |
|----|------|
| AC-13 | 5× 레버리지 진입 가격에서 약 6% 하락하면 마진콜 경고가 체감 가능한 시점에 뜬다 |
| AC-14 | 마진콜 경고 UI가 충분히 눈에 띄어 플레이어가 놓치지 않는다 |
| AC-15 | 레버리지 수익/손실이 일반 포지션 대비 배율만큼 빠르게 변동하는 것을 포트폴리오 UI에서 실시간 확인 가능하다 |
| AC-16 | 이자 비용이 장기 보유 전략에 실질적 압박이 됨을 플레이어가 인식한다 (세션 내 인터뷰 확인) |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 기능 | 진입점 |
|------|--------|
| 레버리지 매수 주문 | `trading_screen.gd._submit_leverage_order()` → `OrderEngine.submit_order(side, stock_id, qty, type, price, leverage_multiplier)` |
| 일별 이자 차감 | `game_clock.gd._on_market_close(day, week)` → `LeverageManager.process_daily_interest(day)` |
| 마진콜 체크 | `game_clock.gd._process_tick()` 5번째 단계 (StopTakeSystem.check_and_trigger 이후) → `LeverageManager.check_margin_calls()` |
| 레버리지 청산 (수동) | `trading_screen.gd._close_leverage_position()` → `OrderEngine.submit_order(SELL, ..., leverage=true)` |
| 시즌 종료 강제청산 | `season_manager.gd._on_season_end()` Step ①-b → `LeverageManager.liquidate_all_positions()` |

### 호출 경로

- [x] `OrderEngine.submit_market_order()` 시그니처에 `leverage_multiplier: int = 1` 파라미터 추가 + "LEVERAGE_BUY"/"LEVERAGE_SELL" 사이드 추가
- [x] `LeverageManager` 신규 파일 생성: `src/gameplay/leverage_manager.gd`
- [x] `LeverageManager.process_daily_interest(day: int)` 구현 (on_market_close 연결)
- [x] `LeverageManager.check_margin_calls()` 구현 (GameClock._process_tick() 4번째 단계 명시 호출)
- [x] `LeverageManager.liquidate_all_positions()` 구현 (시즌 종료 시)
- [x] `LeverageManager.add_margin(stock_id, multiplier, amount)` 구현 (증거금 추가)
- [x] `PortfolioManager.update_valuation()` 계산에 `LeverageManager.get_leverage_net_value()` 반영 (단일 소유권 패턴 — ShortSellingSystem과 동일, PortfolioManager에 중복 보유 추적 없음)
- [x] `SkillTree.has_leverage()` 기존 API 사용 (is_skill_unlocked("TR4"))
- [x] `assets/data/leverage_config.json` 생성 및 모든 튜닝 수치 외부화
- [x] `SeasonManager._on_season_end()` Step ①-b에 `LeverageManager.liquidate_all_positions()` 호출 삽입
- [x] `LeverageManager` autoload 등록 (project.godot)
- [x] `SaveSystem` save/load에 leverage_positions 직렬화 추가
- [x] `GameMain` 신규 게임 리셋 시 `LeverageManager.reset()` 추가
- [x] `LeverageManager.on_loan_shark_ending_triggered` 시그널 추가 (사채업자 엔딩)
- [x] `LeverageManager._forced_liquidation()` — 0-클램프 제거 + 초과 손실 시 시그널 발동
- [x] GameMain — `on_loan_shark_ending_triggered` 연결 → `EndingScreen.show_ending("leverage_crash")` (S10-03)
- [x] `src/ui/portfolio_view.gd` — TR4 레버리지 포지션 섹션 (배율·손익·증거금비율 실시간 표시)
- [x] `src/ui/margin_call_popup.gd` — 마진콜 경고 팝업 (CanvasLayer layer=6, 자동 숨김 6초)
- [x] TradingScreen — `MarginCallPopup` 인스턴스화 (LeverageManager.on_margin_call 자체 연결)
- [ ] Steam 업적 "빚의 무게" 등록 (숨겨진 업적, Polish 스프린트)
- [ ] 배율 선택 콤보박스: TR4 미해금 시 잠금 처리 (Polish 스프린트)
- [ ] 강제청산 알림 토스트 구현 (Polish 스프린트)

### AC → 테스트 매핑

> **AC-17 사채업자 엔딩 상세 명세**: UX·Steam 업적·미구현 항목은
> [endings-achievements.md](endings-achievements.md) §3-2 및 §8을 참조한다.

| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_leverage_trading.gd` | `test_2x_buy_deducts_equity_only()` |
| AC-02 | `tests/unit/test_leverage_trading.gd` | `test_multiplier_equity_calculation_3x()`, `test_multiplier_equity_calculation_5x()` |
| AC-03 | `tests/unit/test_leverage_trading.gd` | `test_daily_interest_deducted_on_market_close()` |
| AC-04 | `tests/unit/test_leverage_trading.gd` | `test_interest_exceeds_cash_adds_to_borrowed()` |
| AC-05 | `tests/unit/test_leverage_trading.gd` | `test_margin_call_triggered_below_threshold()` |
| AC-06 | `tests/unit/test_leverage_trading.gd` | `test_forced_liquidation_on_zero_equity()` |
| AC-07 | `tests/unit/test_leverage_trading.gd` | `test_forced_liquidation_net_loss_within_cash()` |
| AC-17 | `tests/unit/test_leverage_trading.gd` | `test_forced_liquidation_excess_loss_triggers_loan_shark_ending()` |
| AC-08 | `tests/unit/test_leverage_trading.gd` | `test_season_end_liquidates_all_positions()` |
| AC-09 | `tests/unit/test_leverage_trading.gd` | `test_leverage_rejected_without_tr4_skill()` |
| AC-10 | `tests/unit/test_leverage_trading.gd` | `test_invalid_multiplier_rejected()` |
| AC-11 | `tests/unit/test_leverage_trading.gd` | `test_multiple_positions_independent_margin_call()` |
| AC-12 | `tests/unit/test_leverage_trading.gd` | `test_leverage_position_reflected_in_account_total_value()` |
| API 계약 | `tests/unit/test_api_contracts.gd` | `test_leverage_manager_api()` |

### 빌드 검증

- [ ] `--export-release` 빌드 성공 (ERROR 없음)
- [ ] 바이너리 실행 후 5초 이상 프로세스 생존
- [ ] 실행 로그에 SCRIPT ERROR 없음
- [ ] 바이너리 실행 확인: QA Lead 서명 _______

---

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|------------|
| 레버리지 거래에 XP 보정 적용 여부 (고위험 고수익 거래에 추가 XP?) | game-designer + xp-designer | TR4 구현 시 | 미정 |
| 공매도(TR3)와 레버리지(TR4) 동시 보유 허용 여부 | game-designer | TR3 GDD 작성 시 | 미정 |
| 증거금 추가(add_margin) UI — 현금 입력 방식 vs 슬라이더 방식 | ux-designer | TR4 구현 시 | 미정 |
| 레버리지 포지션 save/load 직렬화 — `LeveragePosition` 필드 전체 저장 대상 확인 | save-load + lead-programmer | TR4 구현 시 | 미정. save-load.md 업데이트 필요. |
