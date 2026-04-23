# 경제 밸런스 (Economy Balance)

> **Status**: Draft
> **Type**: Non-GDD Design Reference (경제 전체 파악용 단일 소스)
> **Owner**: economy-designer + game-designer
> **Created**: 2026-04-23 (4-E: Phase 2 Cross-GDD Review 생성 요청)

---

## 1. Overview

게임 내 모든 자원(resource)의 수도꼭지(faucet)와 배수구(sink)를 한 문서에 정리한다.
각 시스템 GDD는 자체 수지를 기술하지만 전체 경제 균형은 단일 뷰 없이 파악하기 어렵다.
이 문서는 `cash_assets`, `sim_cash`, `XP` 세 가지 핵심 자원의 흐름을 추적하고
위험한 경제 상태(무한 공급, 고갈, 양성 피드백 루프, 지배 전략)를 사전에 식별한다.

---

## 2. 자원 목록 (Resource Inventory)

| 자원 | 단위 | 소유 GDD | 초기값 |
|------|------|---------|--------|
| `cash_assets` | 원(₩) | currency-system.md | ₩1,000,000 (브론즈 시작) |
| `sim_cash` | 원(₩) | currency-system.md | 0 (시즌 시작 시 auto_deposit) |
| `XP` | 포인트 | xp-system.md | 0 |
| `스킬 포인트` | 개 | skill-tree.md | XP → 누적 레벨업 시 지급 |

---

## 3. cash_assets 수지 분석

### Faucet (유입)

| 출처 | 금액 | 빈도 | GDD |
|------|------|------|-----|
| 시즌 순위 상금 (1위) | 티어 진입 기준 × 50% | 시즌당 최대 1회 | season-manager.md §3-4 |
| 시즌 순위 상금 (2~10위) | 티어 진입 기준 × 3~30% | 시즌당 최대 1회 | season-manager.md §4-6 |
| 주간 수익률상 | 티어 진입 기준 × 2% | 주당 최대 1회 (4회/시즌) | season-manager.md §3-4 |
| 최고 단타 수익률상 | 티어 진입 기준 × 1% | 시즌당 최대 1회 | season-manager.md §3-4 |
| 첫 거래상 | — (XP만) | 시즌당 최대 1회 | season-manager.md §3-4 |
| sim_cash 시즌 정산 | 시즌 말 sim_cash 잔액 전액 | 시즌당 1회 | season-manager.md §3-1 ⑤ |
| 부동산 임대 수익 | 매입가 × 임대율 | 시즌당 1회 (시즌 마지막 날) | lifestyle-spending.md §3-2 |
| 스타트업 엑싯 (IPO) | 투자금 × 1.5~10× | 투자 후 3~6시즌 | lifestyle-spending.md §F5 |
| 스타트업 엑싯 (M&A) | 투자금 × 0.8~1.5× | 투자 후 3~6시즌 | lifestyle-spending.md §F5 |

### Sink (유출)

| 출처 | 금액 | 빈도 | GDD |
|------|------|------|-----|
| sim_cash 자동 예치 (시즌 시작) | 티어 진입 기준 자산 전액 | 시즌당 1회 | season-manager.md §4-1 |
| 거주지 업그레이드 | ₩500K ~ ₩300M (티어별) | 일회성 (최대 8단계) | lifestyle-spending.md §3-2 |
| 사치품 구매 | ₩50M ~ ₩500M | 일회성 | lifestyle-spending.md §3-2 |
| 부동산 매입 | ₩200M ~ ₩5B | 일회성 (최대 보유 미정) | lifestyle-spending.md §3-2 |
| 스타트업 투자 | ₩50M ~ ₩500M | 시즌당 최대 3건 | lifestyle-spending.md §3-2 |
| 스타트업 폐업 손실 | 투자금 × 100% | 투자 후 3~6시즌 (30~50% 확률) | lifestyle-spending.md §F5 |
| 네트워크/사회공헌 지출 | ₩1M ~ ₩500M | 일회성 또는 Recurring | lifestyle-spending.md §3-2 |
| Recurring 비용 | ₩10M ~ ₩20M/시즌 | 시즌당 자동 | lifestyle-spending.md §3-2 |

### 경제 분석

**위험 없음**: `cash_assets`는 시즌 상금 → 시즌 예치 → 잉여 cash 사이클로 순환한다.
티어가 높을수록 상금 규모가 크고 예치금도 크므로 상금 전액이 예치된다. 잉여분만 소비 가능.

**설계 의도**: 승급 목표(tier_threshold × 3)에서 시즌 상금(tier_threshold × 50%)을 받으면
잔여 자산이 다음 티어 threshold에 도달하도록 설계됨. 1위 상금이 "1회 승급"을 보장한다.

**잠재적 위험 (중기)**: Recurring 비용 없이 스타트업 투자를 하지 않으면 `cash_assets`가
시즌마다 순증가한다. 장기 운용 시 조기에 거장 엔딩에 도달할 수 있으나 이는 의도된 결과.

---

## 4. sim_cash 수지 분석

### Faucet

| 출처 | 금액 | 빈도 | GDD |
|------|------|------|-----|
| 시즌 시작 auto_deposit | 티어 진입 기준 자산 | 시즌 시작 1회 | season-manager.md §4-1 |
| 매도 체결 | 체결가 × 수량 × (1 - sell_tax) | 매 체결 | trading-fees.md |
| 공매도 청산 (BUY_TO_COVER) | margin_deposited + pnl | 청산 시 | short-selling.md §규칙 7 |
| 레버리지 청산 | equity_value (pmv - borrowed - interest) | 청산 시 | leverage-trading.md §3-4 |
| PRE_MARKET 예약금 환불 | reserved - filled 차액 | 체결 시 | order-engine.md §F2b |
| 지정가 주문 취소 | reserved_cash 전액 | 취소 시 | order-engine.md |

### Sink

| 출처 | 금액 | 빈도 | GDD |
|------|------|------|-----|
| 매수 체결 | 체결가 × 수량 × (1 + buy_tax + commission) | 매 체결 | trading-fees.md |
| 공매도 증거금 차감 | open_price × qty × margin_rate | 개시 시 | short-selling.md §규칙 4 |
| 레버리지 증거금 차감 | equity_portion | 개시 시 | leverage-trading.md §3-1 |
| 레버리지 이자 | borrowed × daily_interest_rate | 매일 | leverage-trading.md §3-2 |
| 시즌 종료 정산 → cash_assets | 잔액 전액 | 시즌 종료 1회 | season-manager.md §3-1 ⑤ |

### 경제 분석

**구조적 보장**: `sim_cash`는 시즌 내 순환 자원이다. 시즌 종료 시 전액 `cash_assets`로 이전.
음수 불가 — `currency-system.md`가 모든 sim_deduct에서 잔액 확인.

**잠재적 위험**: 레버리지 이자 + 일일 청산 불가 상황에서 이자가 누적되면 강제청산 가능.
이는 설계된 위험 (leverage-trading.md §W-18: 의도적 고위험).

---

## 5. XP 수지 분석

### Faucet

| 출처 | XP | 조건 | GDD |
|------|-----|-----|-----|
| 기본 시즌 XP (BASE_SEASON_XP) | 200 | 시즌 완주 | xp-system.md §F2 |
| 순위 보너스 (1위) | 500 | 공식 리그 1위 + is_rank_eligible | season-manager.md §3-4 |
| 순위 보너스 (2위) | 350 | 공식 리그 2위 | season-manager.md §3-4 |
| 순위 보너스 (3위) | 250 | 공식 리그 3위 | season-manager.md §3-4 |
| 순위 보너스 (4~5위) | 150 | — | season-manager.md §3-4 |
| 순위 보너스 (6~10위+) | 50 | — | season-manager.md §3-4 |
| 수익률 보너스 (return_bonus) | ~600 max | 시즌 수익률 기반 | xp-system.md §F2 |
| 완주 보너스 | 20 | 수익률 ≥ 0% AND 체결 ≥ 5회 | xp-system.md §F2 |
| 일일 알파 보너스 | ~20~50/일 (최대) | 일일 수익률 기반 | xp-system.md §F1 |
| 주간 수익률상 XP | 50 | 주간 1위 + MIN_WEEKLY_TRADES | season-manager.md §3-4 |
| 최고 단타 수익률상 XP | 30 | 당일 왕복 1위 | season-manager.md §3-4 |
| 첫 거래상 XP | 30 | Day 1 최초 체결 | season-manager.md §3-4 |
| 장학재단 XP | 50 | 일회성 구매 | lifestyle-spending.md |
| 사회공헌 기부 XP | 최대 5/회 | 기부금 ₩10M당 +1 | lifestyle-spending.md |

### Sink

| 출처 | XP | GDD |
|------|-----|-----|
| 스킬 해금 비용 | 1 XP/스킬 (SKILL_COST × 스킬 수) | skill-tree.md §F1 |
| 프리마켓 일일 보너스 감면 | × 0.5 배율 | season-manager.md §4-7 |

### 경제 분석

**설계된 XP 플로어**: 시즌당 최소 XP = 200 (BASE) + 20 (완주 보너스 충족 시). 
최대 XP (3위, 4주 모두 주간상, 완주) ≈ 200 + 250 + 600 + 20 + (50×4) + 50 + 30 + 30 = 1,380 XP.
xp-system.md §F4 추정 ~1,900 XP (일일 알파 포함, 3위 기준)와 정합.

**잠재적 위험**: XP sink가 매우 얕다 (스킬 트리 전체 ~10 XP). 중반 이후 XP 잉여 누적.
"XP가 의미 없어지는" 문제 → 향후 XP 소비 채널 추가 검토 필요 (Sprint 12+ 후속 과제).

**프리마켓 패널티**: 일일 알파 XP × 0.5. 기본 시즌/완주 XP는 감면 없음.
재기 플레이어가 지나치게 오래 프리마켓에 묶이지 않도록 설계.

---

## 6. 경제 위험 지도 (Risk Map)

| 위험 유형 | 자원 | 심각도 | 현황 | 대응 |
|---------|------|-------|------|------|
| 지배 전략 (루머+손절) | sim_cash | HIGH | **해결됨 (B-09)**: RUMOR_BASE_ACCURACY 55%로 하향. 단독 EV ≈ 0 | rumor-channel.md 참조 |
| 양성 피드백 (상위 티어 누적 가속) | cash_assets | MEDIUM | 자연 설계. 상위 티어 상금이 더 크므로 격차 확대. 거장 엔딩이 자연 상한 | 의도된 snowball — 거장 엔딩으로 게임 종료 |
| XP 잉여 (중반 이후 의미 소실) | XP | LOW | 현 단계 허용. 스킬 트리 전소 후 XP 의미 감소 | Sprint 12+ XP 소비 채널 추가 검토 |
| 스타트업 C등급 도박 (EV 2.45×) | cash_assets | LOW | 고분산. 50% 폐업 위험이 자연 균형. 동시 3건 한도 | 의도적 고위험 선택지 |
| sim_cash 음수 불가 → 레버리지 이자 강제청산 | sim_cash | DESIGN | 의도된 위험 (W-18). 이자 누적 시 강제청산 | leverage-trading.md §3-2 |
| Recurring 없는 고티어 현금 과잉 축적 | cash_assets | LOW | 거장 엔딩 도달 가속 — 의도된 결과 | 허용 |

---

## 7. 튜닝 가이드라인

경제 조정 시 아래 검증 순서를 따른다:

1. **상금 스케일 변경**: `PRIZE_RATE` 변경 시 → 1위 상금이 "1회 승급"을 보장하는지 검증
   - `TIER_THRESHOLD[T] × PRIZE_RATE[1] + TIER_THRESHOLD[T]` ≥ `TIER_THRESHOLD[T+1]`
2. **루머 정확도 변경**: `RUMOR_BASE_ACCURACY` ≥ 0.65 시 → dominant strategy 재검토 필수
3. **레버리지 배수 변경**: 이자율 및 증거금과 함께 EV 시뮬레이션 재계산
4. **스타트업 확률 변경**: 등급별 EV 재계산 → A등급 EV가 1.0×에 수렴하는지 확인
5. **XP 수지 변경**: BASE_SEASON_XP + 완주 보너스가 스킬 트리 전소에 필요한 XP의 10배 이상 유지

---

## 8. Dependencies

| GDD | 관계 |
|-----|------|
| currency-system.md | cash_assets, sim_cash 소유 및 API 정의 |
| xp-system.md | XP 수지 공식 (F1, F2) |
| season-manager.md | 시즌 상금 및 정산 플로우 |
| lifestyle-spending.md | 비시즌 cash_assets 소비 채널 |
| skill-tree.md | XP 소비 채널 (스킬 해금) |
| leverage-trading.md | sim_cash 고위험 순환 채널 |
| short-selling.md | sim_cash 증거금 순환 채널 |
| rumor-channel.md | 지배 전략 잠재성 (55% 정확도로 통제됨) |

---

*이 문서는 GDD가 아닌 설계 참고 문서다. 각 수치의 단일 소스는 링크된 GDD다.*
*수치 변경 시 해당 GDD를 먼저 변경하고, 이 문서를 갱신한다.*
