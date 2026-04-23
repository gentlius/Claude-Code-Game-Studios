# 재화 시스템 (Currency System)

> **Status**: Approved
> **Author**: user + game-designer
> **Last Updated**: 2026-04-14
> **Implements Pillar**: 체감있는 성장 (Feel the Growth)

## Overview

재화 시스템은 시드머니의 모든 화폐 흐름을 정의하고 관리하는 Foundation 시스템이다.
**3층 자산 구조**로 운영한다.

| 층 | 명칭 | 변수 | 설명 |
|----|------|------|------|
| 1 | 현금 자산 | `cash_assets` | 플레이어 실생활 자금. 시즌 상금·청산금 입금, 라이프스타일 지출 |
| 2 | 계좌 총 평가금액 | `account_total_value` | 투자 대회 계좌. 예수금(`sim_cash`) + 예약금(`reserved_cash`) + 보유 주식 평가액 |
| 3 | 총 자산 | `total_assets` | 현금 자산 + 계좌 총 평가금액 + 유형자산. F3 화면 표시 기준 |

현금 자산 100만원에서 시작하여, 투자 대회 수익과 라이프스타일 성장을 통해 장기 목표를 달성한다.
목표는 둘 중 하나: **현금 자산 1,000억원** 또는 **총 자산(유형자산 포함) 1조원**.

## Player Fantasy

플레이어의 현금 자산 100만원은 보육원 퇴소 청년의 전 재산이다. 시즌마다 경기 자금(예수금)을
투자 대회에 넣고 수익을 올리면, 청산금과 상금이 현금 자산으로 돌아온다. 현금 자산으로
부동산을 사고, 사치품을 갖추고, 사회공헌을 하면 총 자산이 커진다.
F3 화면에서 커져가는 총 자산을 본다.
"100만원에서 시작해서 현금 1,000억 또는 총 자산 1조" — 이것이 플레이어의 성장 서사다.
잃을 수도 있지만, 실력이 늘면 반드시 회복할 수 있다.

## Detailed Design

### Core Rules

1. **계좌 구조**: 3층 자산 구조.
   - **현금 자산 (`cash_assets`)**: 플레이어 실생활 자금. 단위: 원 (₩). 초기값: 1,000,000원.
     입금: 시즌 청산 후 예수금 잔액 + 상금 환급, 라이프스타일 임대 수익·엑싯.
     출금: 시즌 시작 전 예수금 자동 입금, 라이프스타일 소비 지출.
     API: `get_cash_assets() -> int`, `cash_add(amount: int)`, `cash_deduct(amount: int) -> bool`.
   - **예수금 (`sim_cash`)**: 투자 대회 계좌. 시즌 시작 전 현금 자산에서 티어 기준금액 자동 입금.
     매수 시 `sim_deduct()`, 매도 시 `sim_add()`로 변동. 시즌 종료 시 잔액 → 현금 자산으로 환급. 음수 불가.
     API: `get_sim_cash() -> int`, `sim_deduct(amount: int) -> bool`, `sim_add(amount: int)`.
   - **누적 상금 (`total_prize_earned`)**: 읽기 전용 집계 카운터. 시즌 상금 지급마다 누산.
     UI 통계("지금까지 받은 총 상금")에만 사용. 소비 불가.
     API: `get_total_prize_earned() -> int`, 시그널: `prize_earned(amount: int, new_total: int)`.
   - **유형자산**: 라이프스타일 구매 자산 평가액 (주거·사치품 등). LifestyleManager 소유.
     현금 자산에서 구입. 총 자산 집계(`total_assets`)에만 포함.
   - API에서 `sim_` 접두어는 "simulation" (투자 대회 경제)을 의미한다.

2. **현금 자산 규칙**:
   - 게임 최초 시작 시 1,000,000원으로 초기화 (정착지원금).
   - 시즌 종료 후: 예수금 청산 잔액 + 시즌 상금 전액이 현금 자산으로 입금. 예수금은 0 리셋.
   - **라이프스타일 소비** (거주지, 사치품, 대안 투자 등)는 `cash_deduct()`로 차감.
     소비는 휴장 시간(장 종료 후)에 발생 (lifestyle-spending.md §3-1 참조).
   - 음수 불가 — 잔액 부족 시 라이프스타일 구매 거부.

3. **예수금 규칙**:
   - 시즌 시작 전: 현금 자산에서 티어 기준금액을 자동 입금. 잔여 현금 자산은 그대로 유지.
     (`cash_deduct(tier_threshold)` + `sim_add(tier_threshold)`)
   - 매수 시 `sim_deduct()`, 매도 시 `sim_add()` — 투자 수익/손실 직접 반영.
   - 음수 불가 — 잔액 부족 시 매수 주문 거부.

4. **시즌 전환 규칙**:

   **[시즌 종료 → 정산]**
   1. 미체결 주문 전량 취소 (`reserved_cash` → `sim_cash` 복원, `locked_quantity` 해제)
   2. 보유 주식 전량 시장가 청산 → `sim_cash` 입금
   3. 순위 확정
   4. 시즌 상금 계산
   5. `sim_cash` 잔액 + 상금 → `cash_assets`로 전환. `sim_cash` = 0.

   **[시즌 시작 전]**
   1. 현재 `cash_assets` 기준으로 진입 가능한 최고 티어의 기준금액 계산
   2. `cash_assets`에서 기준금액을 `sim_cash`로 자동 입금
   3. 잔여 `cash_assets`는 그대로 유지 (라이프스타일 자금)
   4. 투자 대회 시작

5. **시즌 상금 규칙**:
   - 시즌 종료 시 순위에 따라 상금 지급.
   - 상금은 **원화**로 현금 자산(`cash_assets`)에 직접 입금. 누적 상금(`total_prize_earned`)도 동시 갱신.
   - 상금 테이블: `design/gdd/season-manager.md §3-4` 단일 소스.

6. **계좌 총 평가금액 및 총 자산** — 포트폴리오 관리 시스템이 계산:
   - `account_total_value = sim_cash + reserved_cash + sum(stock_quantity * current_price)`
   - `total_assets = cash_assets + account_total_value + LifestyleManager.get_tangible_value()`
   - `reserved_cash` = `OrderEngine.get_total_reserved_cash()` (정규 소유자: 주문 엔진).
     `sim_cash`에서 이미 선차감된 금액 → 합산하여 정확한 계좌 총 평가금액 산출.
   - **시즌 순위 기준**: `account_total_value` (투자 대회 성과만 반영, 라이프스타일 자산 제외)
   - **F3 표시 기준**: `total_assets` (세 층 전부 합산)
   - 재화 시스템은 `cash_assets`와 `sim_cash`만 관리. 나머지 계산은 포트폴리오에 위임.

### States and Transitions

| State | Description | Transition |
|-------|-------------|-----------|
| **SEASON_ACTIVE** | 시즌 진행 중. 예수금(`sim_cash`)으로 매매 가능 | → SEASON_SETTLING (시즌 종료 시) |
| **SEASON_SETTLING** | 보유 주식 강제 청산. 순위·상금 확정. `sim_cash` + 상금 → `cash_assets` 환급. `sim_cash` = 0 | → PRE_SEASON |
| **PRE_SEASON** | 시즌 시작 전. `cash_assets` → `sim_cash` 자동 입금. 휴장 시간: 능동 라이프스타일 구매 가능 | → SEASON_ACTIVE (다음 시즌 시작) |

### Interactions with Other Systems

> **API 접두어 `sim_`**: "simulation"의 약어. 게임 내 시뮬레이션 경제를 의미한다.

| System | Direction | Interface |
|--------|-----------|-----------|
| **주문 처리 엔진** | 주문이 이 시스템에 의존 | `get_sim_cash()` → 예수금 잔액 확인. `sim_deduct(amount)` / `sim_add(amount)` → 매수/매도 시 예수금 변동 |
| **포트폴리오 관리** | 포트폴리오가 이 시스템에 의존 | `get_sim_cash()` / `get_cash_assets()` → 잔액 제공. `account_total_value` 및 `total_assets` 계산은 포트폴리오 시스템이 수행 |
| **시즌/대회 관리** | 시즌이 이 시스템에 의존 | `settle_to_cash(prize)` → 청산 + `sim_cash` → `cash_assets` 환급 + 상금 입금. `auto_deposit_to_sim(amount)` → 시즌 시작 전 예수금 입금 |
| **라이프스타일 관리** | 라이프스타일이 이 시스템에 의존 | `cash_deduct(amount)` → 소비 지출. `cash_add(amount)` → 임대 수익·엑싯 입금 |
| **트레이딩 스크린 (UI)** | UI가 참조 | `get_sim_cash()` → 예수금 잔액 표시. `get_cash_assets()` → 현금 자산 표시 (F3 참조) |
| **경험치 시스템** | XP가 이 시스템에 의존 | 수익 실현 이벤트 → XP 부여 트리거 |

## Formulas

### 계좌 총 평가금액 및 총 자산 (참고 — 포트폴리오 관리 시스템 소유)

아래 공식은 포트폴리오 관리 시스템이 수행하는 계산이다. 재화 시스템은
`cash_assets`와 `sim_cash`를 제공하며, 총 자산 집계는 포트폴리오가 담당한다.
상세 공식은 포트폴리오 관리 GDD 및 lifestyle-spending.md §4에서 정의한다.

```
# 계좌 총 평가금액 (시즌 순위 산정 기준)
account_total_value = sim_cash + reserved_cash + sum(holdings[i].quantity * holdings[i].current_price)

# 총 자산 (F3 표시 기준)
total_assets = cash_assets + account_total_value + LifestyleManager.get_tangible_value()

# 시즌 수익률 (F2 리그 순위 기준)
season_return_rate = (account_total_value - season_start_deposit) / season_start_deposit * 100
```

> **주의**: `reserved_cash`는 `sim_cash`에서 **이미 선차감된** 금액이다.
> 따라서 `sim_cash + reserved_cash`는 이중 계산이 아니라 "유동 예수금 + 잠긴 예수금 = 총 예수금"이다.
> 예: 예수금 100만, 지정가 예약 20만 → `sim_cash=80만`, `reserved_cash=20만`, 합계=100만.

> `reserved_cash` = `OrderEngine.get_total_reserved_cash()` (정규 소유자: 주문 엔진).
> 지정가 매수 + PRE_MARKET 시장가 매수 예약금 합계. `sim_cash`에서 이미 선차감된 금액이므로, 계좌 총 평가금액에 합산하여 정확한 값을 산출한다.

> `season_start_deposit` = 시즌 시작 전 `cash_assets`에서 자동 입금된 예수금 금액 (스냅샷).
> **캡처 시점**: `on_season_start` 시그널 수신 시 `get_sim_cash()` 값을 저장.
> 시즌 수익률 계산 기준. (구 `season_start_cash`에서 이름 변경 — 현금 자산과의 혼동 방지)

### 시즌 상금 테이블

> **단일 소스**: `design/gdd/season-manager.md §3-4`
> 상금 규칙은 season-manager.md §3-4가 권위 문서입니다. 이 문서에서는 중복 정의하지 않습니다.
> 요약: 티어별 진입 기준 자산 × 순위 배율로 산정. 티어가 높을수록 상금 규모 비례 증가.

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
| 계좌 총 평가금액이 0원 (예수금 0, 보유 주식 0) | 시즌 계속 진행 가능. 매매 불가(예수금 부족으로 모든 매수 거부), 차트/뉴스 열람 가능, XP 미부여. 시즌 완주 보너스가 현금 자산으로 입금 → 다음 시즌 브론즈 기준금액 예수금 자동 입금 | 빈손이어도 끝까지 |
| 수익률 1000% 이상 | 허용. 상한선 없음 | 극단적 성공도 재미 |
| 시즌 종료 시 보유 주식 강제 청산 | 시장가로 즉시 전량 매도. 슬리피지 없음 (시스템 청산). 청산 대금은 `sim_cash` 입금 후 `cash_assets`로 환급 | 깔끔한 시즌 정산 |
| 시즌 종료 시 미체결 지정가 주문 존재 | 전량 취소 + `reserved_cash` → `sim_cash` 복원 후 청산 진행 | 예약금이 계좌 총 평가금액에 정확히 반영되어야 함 |
| 현금 자산 < 브론즈 기준금액(100만원)에서 새 시즌 시작 | 현금 자산 전액을 예수금으로 입금. 잔여 현금 자산 = 0. 브론즈 하위 프리마켓 티어로 진입 | 최악의 상황에서도 복귀 경로 존재 |
| 현금 자산 1,000억원 돌파 | 축하 이벤트/업적 트리거 + 엔딩 (목표 조건 A 달성) | 현금 집중 플레이 루트 |
| 총 자산 1조원 돌파 (유형자산 포함) | 축하 이벤트/업적 트리거 + 엔딩 (목표 조건 B 달성) | 라이프스타일 확장 플레이 루트 |

### 익스플로잇 체크

| Exploit | 방어 방법 |
|---------|---------|
| 시즌 상금 직전 저장 → 로드 → 상금 이중 수령 | `settle_to_cash()` 호출 직후 즉시 저장. `season_active = false` 상태로 저장되어 재로드 시 정산 완료 상태로 복원. `SeasonManager`는 `season_active = false` 상태에서 `settle_to_cash()` 재호출 불가 (guard: `if not season_active: return`). |
| `cash_assets` 로드 후 예수금 자동입금 중복 | `auto_deposit_to_sim()` 은 `on_season_start` 시그널 핸들러에서만 호출. 저장 시 `season_active = false` (PRE_SEASON 상태)로 저장되어 재로드 시 `on_season_start`가 재발화되지 않음. 플레이어가 "시즌 시작" 버튼을 다시 눌러야 입금 실행. |
| `cash_assets` 직접 변조 (세이브 파일 편집) | `SkillTree.load_save_data()`의 선행조건 검증 패턴을 참조. `cash_assets` 범위 검증: `maxi(data.get("cash_assets", DEFAULT_START_CASH), 0)`. 음수 방지만 적용; 상한 제한 없음 (1조+ 달성 가능). |
| 라이프스타일 지출 직전 저장 → 로드 → 지출 회피 | 라이프스타일 지출은 `on_season_end` 처리 후 `settle_to_cash()` 전에 발생. 정산 저장은 그 이후. 지출 전 마지막 저장은 전날 `on_market_close` 저장이므로 하루치 재플레이 가능. 수용 가능한 범위로 판단 (완전 회피 불가). |

---

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| 주문 처리 엔진 | 주문이 이 시스템에 의존 | `get_sim_cash()`, `sim_deduct()`, `sim_add()`. **Hard** |
| 포트폴리오 관리 | 포트폴리오가 이 시스템에 의존 | `get_sim_cash()` / `get_cash_assets()`로 잔액 조회. `account_total_value` 및 `total_assets` 계산은 포트폴리오가 수행. **Hard** |
| 시즌/대회 관리 | 시즌이 이 시스템에 의존 | `settle_to_cash(prize)` → 청산 + 환급 + 상금. `auto_deposit_to_sim(amount)` → 시즌 시작 예수금 입금. **Hard** |
| 라이프스타일 소비 | 라이프스타일이 이 시스템에 의존 | 소비 `cash_deduct()`. 임대 수익·스타트업 엑싯 `cash_add()`. **Hard** |
| 트레이딩 스크린 (UI) | UI가 이 시스템에 의존 | 예수금 잔액 표시(`get_sim_cash()`). 현금 자산 표시(`get_cash_assets()`). **Soft** |
| 경험치 시스템 | XP가 이 시스템에 의존 | 수익 실현 이벤트 시 XP 부여. **Soft** |
| 게임 시계 | 재화가 이 시스템에 의존 (시그널만) | `on_season_end` → 시즌 정산 트리거, `on_season_start` → `season_start_deposit` 스냅샷. **Soft** (시그널 구독만) |

이 시스템은 Foundation 시스템이다. 게임 시계의 시그널(`on_season_end`, `on_season_start`)을 구독하여 시즌 전환을 트리거받지만, 게임 시계의 데이터를 직접 읽지는 않는다 (시그널 구독만).

---

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `first_cash_assets` (첫 현금 자산) | 1,000,000 | 100,000-10,000,000 | 여유로운 시작, 목표까지 거리 감소 | 더 절박한 시작, 복리 성장 체감 증가 |
| ~~`prize_1st`~~ | 폐기됨 | — | 상금 파라미터는 `season-manager.md §3-4` 단일 소스로 이관됨 |
| ~~`prize_completion`~~ | 폐기됨 | — | 완주 보너스 XP 20만 — `season-manager.md §3-4` 참조 |
| `TIER_THRESHOLD[]` (티어 기준금액) | `season-manager.md §3-2` 참조 | `season-manager.md §7-1` 참조 | 이 값이 변경되면 `auto_deposit_to_sim()` 입금액과 `season_start_deposit` 스냅샷이 연동 변경됨. 재화 시스템은 단일 소스가 아니며 season-manager가 권위 문서. |

---

## Acceptance Criteria

- [x] 게임 최초 시작 시 현금 자산이 정확히 1,000,000원으로 초기화됨
- [x] 시즌 시작 전 현금 자산에서 티어 기준금액이 예수금으로 자동 입금됨 (잔여 현금 자산 유지)
- [x] 매수 시 `sim_deduct()`로 예수금 정확히 차감, 매도 시 `sim_add()`로 정확히 증가
- [x] 예수금이 음수가 되는 경우가 절대 없음
- [x] 현금 자산이 음수가 되는 경우가 절대 없음
- [x] 시즌 종료 시 보유 주식이 시장가로 전량 청산되어 예수금에 반영됨
- [x] 시즌 종료 시 예수금 잔액 + 상금 전액이 현금 자산으로 입금됨. 예수금은 0으로 리셋됨
- [x] 시즌 종료 시 순위에 맞는 상금이 현금 자산에 정확히 입금됨
- [x] 라이프스타일 소비 시 `cash_deduct()`로 현금 자산에서 차감됨 (예수금 영향 없음)
- [x] 포트폴리오 시스템이 계산하는 총 자산에 `get_cash_assets()` + `get_sim_cash()` 값이 정확히 반영됨
- [x] 현금 자산 < 브론즈 기준금액 상태에서도 시즌 참가 가능 (전액 예수금 입금 → 프리마켓 티어)
- [x] 성능: 잔액 조회/변경이 1ms 이내
- [x] 모든 재화 값은 정수 (원 단위, 소수점 없음)
- [x] E2E AC: 브론즈 시즌 진입(`cash_deduct` → `sim_cash=1,000,000`) → 수익 매매 후 시즌 종료 → `settle_to_cash(prize)` 호출 → `cash_assets` 정확히 갱신 → 다음 시즌 시작 버튼 시점에 실버 기준금액(3,000,000) 충족 시 `auto_deposit_to_sim(3,000,000)` 자동 실행 → 잔여 `cash_assets` 보존까지 전 흐름 정확히 작동

---

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| 시즌 참가비 도입 여부 (예수금에서 차감) | game-designer | 확장 시점 | 미정 |
| 수수료 시스템 도입 여부 (매매 수수료) | systems-designer | 확장 시점 | MVP 0% 확정 |
| 예수금 이자 시스템 도입 여부 | economy-designer | 확장 시점 | 향후 |
| 상금 스케일링: 참가자 수에 따른 상금 조정 필요 여부 | economy-designer | 시즌 관리 GDD 시 | **확정 (4-B)**: 고정 배율 방식 채택. 참가자 수 연동 없음. season-manager.md §4-6 PRIZE_RATE 표가 단일 소스. |
| 목표 달성 시 엔딩/특별 콘텐츠 (조건 A: 현금 자산 1,000억 / 조건 B: 총 자산 1조) | game-designer | 확장 시점 | **확정 (4-B)**: 조건 A 채택. `cash_assets ≥ 100,000,000,000원` 시 "투자의 거장" 엔딩 발동. season-manager.md §3-5, endings-achievements.md §3-1 참조. 조건 B(총 자산 1조)는 미채택. |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 기능 | 진입점 |
|------|--------|
| 게임 최초 현금 자산 설정 | `game_main.gd._ready()` → `CurrencySystem.init_first_season()` |
| 시즌 시작 전 예수금 자동 입금 | `season_manager.gd._on_pre_season()` → `CurrencySystem.auto_deposit_to_sim(tier_threshold)` |
| 매수 예수금 차감 | `order_engine.gd.submit_order()` → `CurrencySystem.sim_deduct(amount)` |
| 매도 예수금 입금 | `order_engine.gd._fill_*()` → `CurrencySystem.sim_add(amount)` |
| 시즌 상금 + 예수금 → 현금 자산 환급 | `season_manager.gd._grant_season_prize()` → `CurrencySystem.settle_to_cash(prize_amount)` |
| 라이프스타일 지출 | `lifestyle_manager.gd._on_purchase()` → `CurrencySystem.cash_deduct(amount)` |
| 임대 수익·엑싯 입금 | `lifestyle_manager.gd._on_income()` → `CurrencySystem.cash_add(amount)` |

### 호출 경로

- [x] `CurrencySystem.get_sim_cash() -> int` 존재
- [x] `CurrencySystem.sim_add(amount: int)` 존재
- [x] `CurrencySystem.sim_deduct(amount: int) -> bool` 존재
- [x] `CurrencySystem.init_first_season()` 존재
- [x] `CurrencySystem.reset()` 존재
- [x] `CurrencySystem.get_cash_assets() -> int` — 구현 완료 (`src/core/currency_system.gd:37`)
- [x] `CurrencySystem.cash_add(amount: int)` — 구현 완료 (`src/core/currency_system.gd:85`, S9-05)
- [x] `CurrencySystem.cash_deduct(amount: int) -> bool` — 구현 완료 (`src/core/currency_system.gd:94`, S9-05)
- [x] `CurrencySystem.settle_to_cash(prize_amount: int)` — 구현 완료 (`src/core/currency_system.gd:78`)
- [x] `CurrencySystem.auto_deposit_to_sim(amount: int)` — 구현 완료 (`src/core/currency_system.gd:123`, S9-05)
- [x] `CurrencySystem.get_total_prize_earned() -> int` — 구현 완료 (`src/core/currency_system.gd:49`, S9-05)
- [x] `CurrencySystem.prize_earned(amount: int, new_total: int)` 시그널 — 구현 완료 (`src/core/currency_system.gd:16`, S9-05)

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 | 상태 |
|----|------------|------------|------|
| API 계약 | `tests/unit/test_api_contracts.gd` | `test_currency_system_api()` | ✅ |
| 잔액 부족 시 false 반환 | `tests/unit/test_order_engine.gd` | `test_buy_rejected_insufficient_cash()` | ✅ (간접) |

### 빌드 검증

- [x] 바이너리 실행 확인: QA Lead 서명 — S9 완료 빌드 (2026-04-17, SCRIPT ERROR 없음)
