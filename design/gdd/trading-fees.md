# Trading Fees & Tax System

**Status**: In Review (holding_days 계산 · UI 수수료 표시 미구현 — 향후 스프린트 예정)  
**Sprint**: S9-06  
**Owner**: game-designer + gameplay-programmer  
**Last Updated**: 2026-04-17

---

## 1. Overview

플레이어가 주식을 매수·매도할 때 현실 시장과 동일하게 증권사 수수료와 거래세가 부과된다.
세율과 수수료율은 `market_config.json`에 시장별로 정의되어, 향후 해외 시장 DLC 출시 시
파라미터 교체만으로 전체 세금 체계가 전환된다. 양도소득세는 매도 체결 즉시 과세한다.

---

## 2. Player Fantasy

"수익이 났는데 수수료 떼고 나면 얼마지?" — 현실 투자자가 항상 하는 계산을
게임에서도 체험한다. 세금과 수수료를 의식하면서 거래 빈도와 타이밍을 전략적으로 고민하게 된다.
특히 고빈도 단타 전략은 수수료 누적으로 수익이 잠식되는 현실을 직접 경험할 수 있다.

---

## 3. Detailed Design

### 3-1. 적용 시점

매수/매도 주문이 `OrderEngine`에서 체결되는 순간 즉시 적용된다.
별도 정산 단계 없음.

### 3-2. 매수 체결

```
실제 차감액 = 체결금액 × (1 + buy_tax + commission)
```

현재 KR 시장: `buy_tax = 0.0`, `commission = 0.00015`  
→ 100만원 매수 시 1,001,500원 차감

### 3-3. 매도 체결

```
매도 gross   = 체결금액
수수료       = gross × commission
거래세       = gross × sell_tax
양도소득세   = max(0, 실현이익) × capital_gains_rate(holding_days)
실제 수령액  = gross - 수수료 - 거래세 - 양도소득세
```

`capital_gains_rate(holding_days)`:
```
holding_days < threshold_days → short_term_rate
holding_days ≥ threshold_days → long_term_rate
```

현재 KR 시장: `sell_tax = 0.002`, `commission = 0.00015`, `short_rate = long_rate = 0.0`  
→ 100만원 매도 시 997,850원 수령 (거래세 2,000원 + 수수료 150원)

### 3-4. 체결 알림 표시

체결 시 기존 알림 패널에 수수료·세금 항목 추가:
```
[체결] 삼성전자(005930) 매도 10주 × ₩78,000
  수수료  ▼ ₩117
  거래세  ▼ ₩1,560
  실수령  ₩778,323
```

양도소득세가 발생한 경우 (KR 이외 시장):
```
  양도소득세 ▼ ₩125,000
```

---

## 4. Formulas

### MarketConfig 파라미터

| 필드 | 타입 | 설명 |
|------|------|------|
| `buy_tax` | float | 매수 시 거래세율 |
| `sell_tax` | float | 매도 시 거래세율 |
| `commission` | float | 증권사 수수료율 (매수/매도 공통) |
| `capital_gains.short_term_rate` | float | 단기 양도소득세율 |
| `capital_gains.long_term_rate` | float | 장기 양도소득세율 |
| `capital_gains.threshold_days` | int | 단기/장기 구분 보유일 수 |

### 매수 비용

```
buy_cost = quantity × price × (1 + buy_tax + commission)
```

### 매도 수령액

```
gross          = quantity × price
realized_profit = gross - (avg_buy_price × quantity)  # PortfolioManager 계산
cg_rate        = short_rate  if holding_days < threshold_days  else  long_rate
capital_gains  = max(0, realized_profit) × cg_rate
net_proceeds   = gross × (1 - sell_tax - commission) - capital_gains
```

### 변수 정의 (매도 수령액 공식)

| 변수 | 타입 | 현재값 (KR) | 출처 | 설명 |
|------|------|------------|------|------|
| `gross` | int | — | 체결 | 매도 체결금액 = quantity × price |
| `realized_profit` | int | — | PortfolioManager | 실현이익 = gross − (avg_buy_price × quantity). 음수 가능 |
| `sell_tax` | float | 0.002 (0.20%) | market_config.json | 매도 거래세율 |
| `commission` | float | 0.00015 (0.015%) | market_config.json | 증권사 수수료율 (매수/매도 공통) |
| `holding_days` | int | **0 (MVP)** | PortfolioManager | 보유일 수. KR `capital_gains=0`이므로 MVP에서는 상수 0 전달. 비KR 시장(DLC) 구현 시 FIFO 가중평균 계산 필요 (§9 미체크 항목). |
| `cg_rate` | float | 0.0 (KR 단기·장기 동일) | market_config.json | 양도소득세율. `holding_days < threshold_days → short_term_rate` |
| `capital_gains` | int | **0 (KR)** | calculated | 양도소득세 = max(0, realized_profit) × cg_rate |
| `net_proceeds` | int | — | calculated | 실제 수령액 = gross × (1 − sell_tax − commission) − capital_gains |

> **MVP 단순화**: KR 시장은 `short_term_rate = long_term_rate = 0.0`이므로 `capital_gains = 0` 항상 성립.
> OrderEngine은 MVP 기간 `holding_days = 0`을 `get_fee_breakdown()`에 전달한다.
> 비KR 시장(DLC) 구현 시 PortfolioManager의 FIFO 가중평균 보유일 계산이 필요하다 (§9 미체크 항목).

### 변수 정의 (매수 비용 공식)

| 변수 | 타입 | 현재값 (KR) | 출처 | 설명 |
|------|------|------------|------|------|
| `buy_tax` | float | 0.0 (KR 면제) | market_config.json | 매수 거래세율 |
| `commission` | float | 0.00015 (0.015%) | market_config.json | 증권사 수수료율 |
| `buy_cost` | int | — | calculated | 실제 차감액 = quantity × price × (1 + buy_tax + commission) |

### 수수료·세금 내역 반환 구조체

```gdscript
# MarketConfig.get_fee_breakdown() 반환값
{
    "commission":      float,  # 수수료 금액
    "sell_tax":        float,  # 거래세 금액
    "buy_tax":         float,  # 매수세 금액 (KR=0)
    "capital_gains":   float,  # 양도소득세 금액
    "net":             float,  # 최종 수령/차감액
}
```

---

## 5. Edge Cases

| 케이스 | 처리 |
|--------|------|
| 실현이익 ≤ 0 (손절 매도) | `capital_gains = 0` — 세금 없음 |
| holding_days 추적 불가 (FIFO 혼합) | 가중평균 보유일 사용 |
| KR 시장 capital_gains_rate = 0 | 양도소득세 항목 = 0, 코드 분기 없음 |
| 수수료 차감 후 잔고 부족 | 체결 전 `CurrencySystem`에서 잔고 검증 — 부족 시 주문 거부 |
| 배율 다른 다중 슬롯 | 슬롯별 독립 MarketConfig 로드 (현재 단일 시장이므로 동일) |

---

## 6. Dependencies

| 시스템 | 의존 내용 |
|--------|-----------|
| `OrderEngine` | 체결 시 `MarketConfig.get_fee_breakdown()` 호출 |
| `PortfolioManager` | 실현이익·보유일 제공 |
| `CurrencySystem` | `cash_deduct()` / `cash_add()` |
| `MarketConfig` | JSON 로드, fee_breakdown 계산 |
| `assets/data/market_config.json` | 시장별 파라미터 |

---

## 7. Tuning Knobs

| 파라미터 | 현재값 (KR) | 설명 |
|----------|------------|------|
| `buy_tax` | 0.0 | 매수 거래세 |
| `sell_tax` | 0.002 | 매도 거래세 (증권거래세 0.20%) |
| `commission` | 0.00015 | 수수료 (0.015%, 온라인 기준) |
| `short_term_rate` | 0.0 | 단기 양도세 (KR 개인 면제) |
| `long_term_rate` | 0.0 | 장기 양도세 (KR 개인 면제) |
| `threshold_days` | 365 | 단기/장기 구분일 (DLC용 예약) |

---

## 8. Acceptance Criteria

| ID | 조건 |
|----|------|
| AC-01 | KR 매도 체결 시 `sell_tax(0.20%) + commission(0.015%)` 정확히 차감 |
| AC-02 | KR 매수 체결 시 `commission(0.015%)` 만 추가 차감 |
| AC-03 | `capital_gains_rate = 0` 일 때 양도세 차감 없음 |
| AC-04 | 손절 매도(실현이익 < 0) 시 양도세 = 0 |
| AC-05 | 체결 알림에 수수료·거래세 금액 표시 |
| AC-06 | US 가상 설정(short_rate=0.22) 적용 시 이익의 22% 즉시 차감 |
| AC-07 | `market_config.json` 로드 실패 시 에러 로그 + 게임 중단 |
| AC-08 | 잔고 부족(수수료 포함 체결금 > 현금) 시 주문 거부 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
- 이 기능은 어디서 호출되는가: `OrderEngine._execute_order()` → `MarketConfig.get_fee_breakdown()` → `CurrencySystem.cash_deduct(net)`

### 호출 경로
- [x] `assets/data/market_config.json` 생성 — KR 파라미터 + US/JP/HK/CN 예약 슬롯
- [x] `src/core/market_config.gd` autoload 등록 (`project.godot`)
- [x] `MarketConfig.get_fee_breakdown(side, gross, holding_days, realized_profit) → Dictionary`
- [x] `OrderEngine._execute_buy()`: `buy_cost = MarketConfig.get_buy_cost(gross)` → 예약금 포함 차감. 체결 시 actual_cost 기준 정산
- [x] `OrderEngine._execute_sell()`: `get_fee_breakdown()` → `CurrencySystem.sim_add(net)` (3개 체결 경로 모두)
- [ ] `PortfolioManager`: 매도 시 `holding_days` 계산 (FIFO 가중평균) → `OrderEngine`에 전달 — KR capital_gains=0이므로 현재 holding_days=0 전달, 향후 비KR 시장에서 구현
- [ ] 체결 알림 패널에 수수료·세금 내역 표시 — AC-05, 수동 검증 대상. UI 구현은 S9-06 후속 작업

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_trading_fees.gd` | `test_kr_sell_fee_deduction()` |
| AC-02 | `tests/unit/test_trading_fees.gd` | `test_kr_buy_fee_deduction()` |
| AC-03 | `tests/unit/test_trading_fees.gd` | `test_zero_capital_gains()` |
| AC-04 | `tests/unit/test_trading_fees.gd` | `test_loss_sell_no_capital_gains()` |
| AC-06 | `tests/unit/test_trading_fees.gd` | `test_us_capital_gains_immediate()` |
| AC-07 | `tests/unit/test_trading_fees.gd` | `test_missing_config_error()` |
| AC-08 | `tests/unit/test_trading_fees.gd` | `test_insufficient_balance_rejected()` |

### 빌드 검증
- [x] 바이너리 실행 확인: QA Lead 서명 — 내부 감사 2026-04-17 (GUT 전체 통과, test_trading_fees.gd 11/11, SCRIPT ERROR 없음)
