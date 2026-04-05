# 재화 시스템 (Currency System)

> **Status**: In Review
> **Author**: user + game-designer
> **Last Updated**: 2026-04-03
> **Implements Pillar**: 체감있는 성장 (Feel the Growth)

## Overview

재화 시스템은 시드머니의 모든 화폐 흐름을 정의하고 관리하는 Foundation 시스템이다.
단일 계좌인 **예수금**을 운영한다. 주문 엔진이 관리하는 `reserved_cash`(지정가/PRE_MARKET 예약금)는 예수금에서 선차감된 내부 구분일 뿐, 별도 계좌가 아니다. 예수금은 보육원 퇴소 청년의 정착지원금 100만원에서
시작하며, 투자 대회에서의 수익/손실이 직접 반영되고, 시즌 상금이 추가 입금되어
복리로 성장한다. 100만원에서 1억까지 — 이것이 장기 성장의 궤적이다.

## Player Fantasy

플레이어의 예수금 100만원은 보육원 퇴소 청년의 전 재산이다. 이 돈을 직접 투자 대회에
걸고 수익을 올린다. 시즌마다 수익이 쌓이고, 순위 상금까지 더해지면서 자본이 복리로
불어난다. "100만원에서 시작해서 1억을 만들었다" — 이것이 플레이어의 성장 서사다.
잃을 수도 있지만, 실력이 늘면 반드시 회복할 수 있다.

## Detailed Design

### Core Rules

1. **계좌 구조**: 단일 계좌.
   - **예수금 (`sim_cash`)**: 플레이어의 전 재산이자 투자 자금. 단위: 원 (₩). 시작: 1,000,000원.
   - API에서 `sim_` 접두어는 "simulation" (게임 경제)을 의미한다.

2. **예수금 규칙**:
   - 게임 시작 시 1,000,000원 (정착지원금).
   - 매수 시 `sim_deduct()`, 매도 시 `sim_add()` — 투자 수익/손실이 직접 반영.
   - 시즌 상금이 여기로 입금된다.
   - 시즌 종료 시 보유 주식은 시장가로 강제 청산. 잔액은 다음 시즌으로 이월.
   - 음수 불가 — 잔액 부족 시 주문 거부.

3. **시즌 전환 규칙**:
   - 시즌 종료 → **미체결 주문 전량 취소** (지정가 매수의 `reserved_cash` 전액 `sim_cash`로 복원, 지정가/PRE_MARKET 매도의 `locked_quantity` 해제) → 보유 주식 전량 시장가 청산 → 청산 대금 예수금 반영 → 순위 확정 → 상금 입금.
   - 다음 시즌 시작 시 예수금 잔액 그대로 투자 재개.
   - 시즌 간 예수금은 리셋되지 않는다 (복리 구조의 핵심).

4. **시즌 상금 규칙**:
   - 시즌 종료 시 순위에 따라 상금 지급.
   - 상금은 **원화**로 예수금에 직접 입금.

5. **총 자산** — 포트폴리오 관리 시스템이 계산:
   - `sim_total_assets = sim_cash + reserved_cash + sum(stock_quantity * current_price)`
   - `reserved_cash` = `OrderEngine.get_total_reserved_cash()` (정규 소유자: 주문 엔진). 지정가 매수 + PRE_MARKET 시장가 매수 예약금 합계. `sim_cash`에서 이미 선차감된 금액이므로 총 자산에 합산.
   - 시즌 순위는 이 값 기준.
   - 재화 시스템은 `sim_cash`만 관리하고, 총 자산 계산은 포트폴리오에 위임.

### States and Transitions

| State | Description | Transition |
|-------|-------------|-----------|
| **SEASON_ACTIVE** | 시즌 진행 중. 예수금으로 매매 가능 | → SEASON_SETTLING (시즌 종료 시) |
| **SEASON_SETTLING** | 보유 주식 강제 청산 중. 총 자산 확정. 상금 계산 | → SEASON_ACTIVE (다음 시즌 시작) |

### Interactions with Other Systems

> **API 접두어 `sim_`**: "simulation"의 약어. 게임 내 시뮬레이션 경제를 의미한다.

| System | Direction | Interface |
|--------|-----------|-----------|
| **주문 처리 엔진** | 주문이 이 시스템에 의존 | `get_sim_cash()` → 잔액 확인. `sim_deduct(amount)` / `sim_add(amount)` → 매수/매도 시 잔액 변동 |
| **포트폴리오 관리** | 포트폴리오가 이 시스템에 의존 | `get_sim_cash()` → 현금 잔액 제공. 총 자산 계산(`sim_cash + 보유 주식 평가액`)은 포트폴리오 시스템이 수행 |
| **시즌/대회 관리** | 시즌이 이 시스템에 의존 | `settle_season()` → 보유 주식 청산 + 상금 입금. `get_sim_cash()` → 시즌 시작 자본 확인 |
| **트레이딩 스크린 (UI)** | UI가 참조 | `get_sim_cash()` → 잔액 표시 |
| **경험치 시스템** | XP가 이 시스템에 의존 | 수익 실현 이벤트 → XP 부여 트리거 |

## Formulas

### 총 자산 및 수익률 (참고 — 포트폴리오 관리 시스템 소유)

아래 공식은 포트폴리오 관리 시스템이 수행하는 계산이다. 재화 시스템은
`cash`만 제공하며, 총 자산 집계와 수익률 계산은 포트폴리오가 담당한다.
상세 공식은 포트폴리오 관리 GDD에서 정의한다.

```
sim_total_assets = sim_cash + reserved_cash + sum(holdings[i].quantity * holdings[i].current_price)
season_return_rate = (sim_total_assets - season_start_cash) / season_start_cash * 100
```

> **주의**: `reserved_cash`는 `sim_cash`에서 **이미 선차감된** 금액이다.
> 따라서 `sim_cash + reserved_cash`는 이중 계산이 아니라 "유동 현금 + 잠긴 현금 = 총 현금"이다.
> 예: 예수금 100만, 지정가 예약 20만 → `sim_cash=80만`, `reserved_cash=20만`, 합계=100만.

> `reserved_cash` = `OrderEngine.get_total_reserved_cash()` (정규 소유자: 주문 엔진).
> 지정가 매수 + PRE_MARKET 시장가 매수 예약금 합계. `sim_cash`에서 이미 선차감된 금액이므로, 총 자산에 합산하여 정확한 값을 산출한다.

> `season_start_cash` = 시즌 시작 시 예수금 잔액 (스냅샷). **캡처 시점**: `on_season_start` 시그널 수신 시 `get_sim_cash()` 값을 저장. 시즌 수익률 계산 기준.

> `season_start_cash`는 매 시즌 시작 시 갱신되는 런타임 스냅샷이다. 첫 시즌의 초기값은 튜닝 노브 `first_season_cash`(기본 1,000,000원)에서 설정된다.

### 시즌 상금 테이블

> **⚠️ 이 테이블은 구버전(브론즈 고정값)입니다.**
> 상금 규칙의 단일 소스는 `design/gdd/season-manager.md §3-4`입니다.
> 상금은 티어별 진입 기준 자산 × 배율로 산정됩니다 (티어에 따라 규모가 달라짐).

브론즈 기준 참고값 (티어 진입 기준 자산 = 1,000,000원):

| Season Rank | Prize (₩) |
|-------------|-----------|
| 1위 | 500,000 (× 50%) |
| 2위 | 300,000 (× 30%) |
| 3위 | 150,000 (× 15%) |
| 4위 | 80,000 (× 8%) |
| 5위 | 50,000 (× 5%) |
| 6~10위 | 30,000 (× 3%) |
| 완주 보너스 | — (XP 20 지급, 현금 없음) |

### 복리 성장 시나리오 (예시, 브론즈 기준)

```
시즌 1: 시작 1,000,000 → 수익률 +20% → 청산 후 1,200,000 + 상금(1위) 500,000 = 1,700,000
시즌 2: 시작 1,700,000 → 수익률 +15% → 청산 후 1,955,000 + 상금(2위) 300,000 = 2,255,000
시즌 3: 시작 2,255,000 → 수익률 +25% → 청산 후 2,818,750 + 상금(1위) 500,000 = 3,318,750
...
```

> 실버 이상은 티어 진입 기준 자산이 더 크므로 상금 규모도 비례하여 증가.
> 매 시즌 꾸준한 수익 + 상금 → 복리 효과로 목표 자산 도달 가능.

---

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 잔액 부족으로 매수 불가 | 주문 거부 + "잔액 부족" 메시지 | 빚 매수 불가 |
| 전 예수금을 한 종목에 올인 | 허용. 리스크는 플레이어 판단 | 필라 "판단이 곧 실력" |
| 총 자산이 0원 | 시즌 계속 진행 가능. 매매 불가(잔액 부족으로 모든 매수 거부), 차트/뉴스 열람 가능, XP 미부여(거래 없으므로). 시즌 완주 보너스(30,000원)가 다음 시즌 유일한 시작 자금 | 빈손이어도 끝까지 |
| 수익률 1000% 이상 | 허용. 상한선 없음 | 극단적 성공도 재미 |
| 시즌 종료 시 보유 주식 강제 청산 | 시장가로 즉시 전량 매도. 슬리피지 없음 (시스템 청산) | 깔끔한 시즌 정산 |
| 시즌 종료 시 미체결 지정가 주문 존재 | 전량 취소 + reserved_cash 복원 후 청산 진행 | 예약금이 총 자산에 정확히 반영되어야 함 |
| 예수금 0원 상태에서 새 시즌 시작 | 매매 불가. 시즌 완주 보너스(30,000원)가 유일한 수입원 | 최악의 상황에서도 복귀 경로 존재 |
| 예수금 1억 돌파 | 축하 이벤트/업적 트리거 | 장기 목표 달성 |

---

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| 주문 처리 엔진 | 주문이 이 시스템에 의존 | `get_sim_cash()`, `sim_deduct()`, `sim_add()`. **Hard** |
| 포트폴리오 관리 | 포트폴리오가 이 시스템에 의존 | `get_sim_cash()`로 현금 잔액 조회. 총 자산 계산은 포트폴리오가 수행. **Hard** |
| 시즌/대회 관리 | 시즌이 이 시스템에 의존 | 시즌 청산/상금 입금. **Hard** |
| 트레이딩 스크린 (UI) | UI가 이 시스템에 의존 | 잔액 표시. **Soft** |
| 경험치 시스템 | XP가 이 시스템에 의존 | 수익 실현 이벤트 시 XP 부여. **Soft** |
| 게임 시계 | 재화가 이 시스템에 의존 (시그널만) | `on_season_end` → 시즌 정산 트리거, `on_season_start` → `season_start_cash` 스냅샷. **Soft** (시그널 구독만) |

이 시스템은 Foundation 시스템이다. 게임 시계의 시그널(`on_season_end`, `on_season_start`)을 구독하여 시즌 전환을 트리거받지만, 게임 시계의 데이터를 직접 읽지는 않는다 (시그널 구독만).

---

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `first_season_cash` (첫 시즌) | 1,000,000 | 100,000-10,000,000 | 여유로운 시작, 1억까지 거리 감소 | 더 절박한 시작, 복리 성장 체감 증가 |
| `prize_1st` | ~~500,000~~ | — | **폐기됨**: 상금은 티어별 진입 기준 자산 × 배율로 산정. `design/gdd/season-manager.md §3-4` 참조 |
| `prize_completion` | ~~30,000~~ | — | **폐기됨**: 완주 보너스는 현금 없음, XP 20만 지급. `design/gdd/season-manager.md §3-4` 참조 |

---

## Acceptance Criteria

- [ ] 게임 시작 시 예수금이 정확히 1,000,000원으로 초기화됨
- [ ] 매수 시 `sim_deduct()`로 예수금 정확히 차감, 매도 시 `sim_add()`로 정확히 증가
- [ ] 예수금이 음수가 되는 경우가 절대 없음
- [ ] 시즌 종료 시 보유 주식이 시장가로 전량 청산되어 예수금에 반영됨
- [ ] 시즌 종료 시 순위에 맞는 상금이 예수금에 정확히 입금됨
- [ ] 예수금은 시즌 전환 시 리셋되지 않고 이월됨 (복리 구조)
- [ ] 포트폴리오 시스템이 계산하는 총 자산에 `get_sim_cash()` 값이 정확히 반영됨
- [ ] 예수금 0원 상태에서도 시즌 참가 가능 (관전 + 완주 보너스로 복귀)
- [ ] 성능: 잔액 조회/변경이 1ms 이내
- [ ] 모든 재화 값은 정수 (원 단위, 소수점 없음)

---

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| 시즌 참가비 도입 여부 (예수금에서 차감) | game-designer | 확장 시점 | 미정 |
| 수수료 시스템 도입 여부 (매매 수수료) | systems-designer | 확장 시점 | MVP 0% 확정 |
| 예수금 이자 시스템 도입 여부 | economy-designer | 확장 시점 | 향후 |
| 상금 스케일링: 참가자 수에 따른 상금 조정 필요 여부 | economy-designer | 시즌 관리 GDD 시 | 미정 |
| 1억 달성 시 엔딩/특별 콘텐츠 | game-designer | 확장 시점 | 미정 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 기능 | 진입점 |
|------|--------|
| 시즌 초기 자금 설정 | `game_main.gd._ready()` → `CurrencySystem.init_first_season()` |
| 매수 예수금 차감 | `order_engine.gd.submit_order()` → `CurrencySystem.sim_deduct(amount)` |
| 매도/상금 입금 | `order_engine.gd._fill_*()` / `season_manager.gd._grant_season_prize()` → `CurrencySystem.sim_add(amount)` |

### 호출 경로

- [x] `CurrencySystem.get_sim_cash() -> int` 존재
- [x] `CurrencySystem.sim_add(amount: int)` 존재
- [x] `CurrencySystem.sim_deduct(amount: int) -> bool` 존재
- [x] `CurrencySystem.init_first_season()` 존재
- [x] `CurrencySystem.reset_for_testing()` 존재

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 | 상태 |
|----|------------|------------|------|
| API 계약 | `tests/unit/test_api_contracts.gd` | `test_currency_system_api()` | ✅ |
| 잔액 부족 시 false 반환 | `tests/unit/test_order_engine.gd` | `test_buy_rejected_insufficient_cash()` | ✅ (간접) |

### 빌드 검증

- [ ] 바이너리 실행 확인: QA Lead 서명 _______
