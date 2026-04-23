# P3 섹터 ETF (Sector ETF)

> **Status**: Approved (구현 완료 2026-04-23 — S10-02)
> **Priority**: Beta (Sprint 10)
> **Skill Gate**: T3 — P3 해금 필요 (P2 + A4 선행)
> **Created**: 2026-04-20
> **Last Updated**: 2026-04-23

---

## 1. Overview

P3 섹터 ETF는 개별 종목이 아닌 **업종 단위**로 투자할 수 있는 상품이다.
11개 섹터별로 ETF 1종씩 존재하며, 시즌 시작 시 기준가 50,000원에서 출발한다.
ETF 가격은 해당 섹터 구성 종목의 시가총액 가중 수익률로 산출되며,
PriceEngine이 제공하는 동일한 캐시 인터페이스를 통해 조회된다.

P3는 "섹터 분석 → ETF 매매"의 새로운 판단 루프를 추가하여
개별 종목 리스크 없이 섹터 방향성에 베팅하는 경험을 제공한다.

---

## 2. Player Fantasy

"반도체 업종 전체가 오를 것 같은데, 어떤 종목을 고를지 모르겠다."
→ ETF_반도체를 한 주 매수하면 된다.

플레이어는 거시경제 뉴스나 A4 섹터 비교 뷰에서 강세 섹터를 파악하고,
ETF로 간단하게 방향성 베팅을 한다. 개별 종목 선택의 복잡성 없이
"섹터 레벨의 통찰"이 수익으로 이어지는 쾌감을 제공한다.

---

## 3. Detailed Design

### 3-1 ETF 목록

ETF 목록과 ETF_BASE_PRICE는 `MarketProfile.get_active()`에서 로드한다. 하드코딩 금지.
DLC 시장 추가 시 `market_us.json` 등 MarketProfile만 추가하면 EtfManager 코드 변경 없음.

**KR 시장 기본 (11종)**

| ETF ID | 이름 | 섹터 | 구성 종목 수 |
|--------|------|------|------------|
| ETF_반도체 | 반도체 ETF | 반도체 | 5 |
| ETF_2차전지 | 2차전지 ETF | 2차전지 | 4 |
| ETF_바이오 | 바이오 ETF | 바이오 | 5 |
| ETF_자동차 | 자동차 ETF | 자동차 | 4 |
| ETF_에너지 | 에너지 ETF | 에너지 | 4 |
| ETF_금융 | 금융 ETF | 금융 | 4 |
| ETF_게임 | 게임 ETF | 게임 | 5 |
| ETF_엔터 | 엔터 ETF | 엔터 | 4 |
| ETF_건설 | 건설 ETF | 건설 | 4 |
| ETF_유통 | 유통 ETF | 유통 | 4 |
| ETF_통신 | 통신 ETF | 통신 | 3 |

### 3-2 가격 산출 방식

ETF 가격은 EtfManager가 매 틱마다 계산하여 PriceEngine 캐시에 직접 주입한다.

**시즌 시작 시**: 모든 ETF 가격 = ETF_BASE_PRICE (50,000원)

**매 틱 이후**: 섹터 구성 종목의 시가총액 가중 수익률을 기준가에 곱한다.

```
sector_return(t) = Σ( price(stock_i, t) × listed_shares(i) ) / Σ( base_price(i) × listed_shares(i) ) - 1.0

etf_price(t) = ETF_BASE_PRICE × (1.0 + sector_return(t))
```

시즌 기준가(`base_price`)는 stocks.json의 `base_price` 필드를 사용한다 (시즌마다 고정).

### 3-3 거래 방식

- **즉시 체결**: 호가창(OrderBook) 없음. 주문 즉시 현재 ETF 가격에 체결.
- **슬리피지 없음**: ETF는 유동성이 무한한 인덱스 상품으로 간주.
- **주문 단위**: 1주 단위. 분할 매수 가능.
- **거래 수수료**: trading-fees.md 동일 적용 (매수: 수수료 0.015%, 매도: 수수료 + 증권거래세 0.2%).
- **숏/레버리지 불가**: ETF에는 TR3·TR4 적용 불가. OrderEngine에서 ETF ID 감지 시 거부.
- **TR2 적용 가능**: 손절/익절 자동 주문 적용 가능 (stop-loss-take-profit.md 동일).

### 3-4 포트폴리오 슬롯

ETF는 일반 종목과 동일한 슬롯을 소비한다.
P2 MAX_HOLDINGS = 10슬롯 공유. ETF 1종 = 1슬롯.

플레이어는 최대 10슬롯 내에서 개별 종목과 ETF를 자유롭게 혼합 보유할 수 있다.

### 3-5 진입 조건

- 스킬 트리에서 **T3 — P3** 해금 필요
- P2 해금 선행 필수
- A4 섹터 비교 분석 해금 선행 필수 (sector-comparison.md)

### 3-6 차트 / 정보 표시

- ETF도 일반 종목과 동일하게 OHLCV 캔들차트 제공 (PriceEngine 캐시 기반).
- 재무제표(PER/PBR/ROE) 표시 없음 — ETF는 개별 기업이 아니므로.
- A4 섹터 비교 뷰에서 해당 ETF의 현재 수익률 확인 가능.

### 3-7 EtfManager 책임

`EtfManager` (autoload). 모든 설정은 `MarketProfile.get_active()`에서 로드.

**가격 계산 (매 틱)**
- `tick_processed` 신호 수신 → 각 ETF 가격 재계산 → `PriceEngine.inject_price(etf_id, price)` 호출.
- 당일 시가 스냅샷 (`day_started` 신호 수신 시 저장).

**섹터 로테이션 이벤트 (ADR-022 EventSource 패턴)**
- 매 틱 `sector_flow[sector]`를 갱신 (F4 공식).
- `sector_flow_delta`가 `ROTATION_THRESHOLD`를 초과하고 쿨다운이 경과하면:
  - 유입 섹터 → `NewsEventSystem.inject_event(SECTOR_ROTATION, inflow)` 호출
  - 아키타입 기반 가중 랜덤으로 소외 섹터 선택 → `inject_event(SECTOR_ROTATION, outflow)` 호출
  - 헤드라인 키는 `MarketProfile.get_rotation_headline(direction)` — 실제 문자열은 Godot `.po` 파이프라인
- **PriceEngine 직접 조작 금지** — 시장 영향은 반드시 NewsEventSystem을 통한다 (ADR-022).

**공개 API**
- `get_sector_stocks(sector: String) -> Array[String]` — 섹터 구성 종목 ID
- `get_etf_return(etf_id: String) -> float` — 시즌 시작 대비 수익률
- `get_etf_price(etf_id: String) -> float` — 현재 ETF 가격
- `get_etf_open_price(etf_id: String) -> float` — 당일 시가 스냅샷
- `get_sector_flow(sector: String) -> float` — 현재 flow 인덱스 (A4 표시용)

**시장별 설정 로드 (DLC 지원)**
- 시즌 시작 시 `MarketProfile.get_active()`에서 ETF 목록, sector_archetypes, rivalry_weights, rotation_params 전부 로드.
- 시장이 바뀌면 (`SeasonManager.season_started`) 전체 재초기화.

---

## 4. Formulas

### F1 섹터 시가총액 가중 수익률

```
# 변수 정의
# base_price(i)    : stocks.json base_price — 시즌 기준가 (고정)
# listed_shares(i) : stocks.json listed_shares
# price(i, t)      : PriceEngine.get_price(stock_id) — 현재 틱 가격
# N                : 섹터 구성 종목 수

base_mcap_sector = Σ_{i=1}^{N} base_price(i) × listed_shares(i)
curr_mcap_sector = Σ_{i=1}^{N} price(i, t) × listed_shares(i)

sector_return(t)  = curr_mcap_sector / base_mcap_sector - 1.0
etf_price(t)      = ETF_BASE_PRICE × (1.0 + sector_return(t))
```

| 변수 | 타입 | 범위/값 | 출처 |
|------|------|---------|------|
| ETF_BASE_PRICE | int | 50,000원 | EtfManager 상수 |
| base_price(i) | int | stocks.json | 시즌 고정 |
| listed_shares(i) | int | stocks.json | 시즌 고정 |
| price(i, t) | float | PriceEngine.get_price() | 틱마다 갱신 |
| sector_return(t) | float | 이론상 −1.0 ~ +무한 | 계산값 |
| etf_price(t) | float | ≥ 0 | 계산값 (하한 1원) |

**예시 계산 (반도체 ETF, 2개 종목 단순화)**

| 항목 | SKL | STC | 합계 |
|------|-----|-----|------|
| base_price | 210,000 | 120,000 | — |
| listed_shares | 2,500,000 | 1,500,000 | — |
| base_mcap | 525,000,000,000 | 180,000,000,000 | 705,000,000,000 |
| price(t) | 220,500 (+5%) | 114,000 (−5%) | — |
| curr_mcap | 551,250,000,000 | 171,000,000,000 | 722,250,000,000 |
| sector_return | | | +0.02447 (+2.45%) |
| ETF_반도체 가격 | | | 51,224원 |

### F2 ETF 매도 수령액

trading-fees.md의 일반 매도 공식 그대로 적용.

```
gross = quantity × price
sell_tax = gross × 0.002
commission = gross × 0.00015
net_proceeds = gross - sell_tax - commission
```

### F3 sector_flow 갱신 (매 틱)

```
# 변수 정의
# sector_return_prev_window(sector, N) : 최근 N틱 섹터 수익률 평균
# FLOW_SENSITIVITY : flow가 momentum에 반응하는 강도
# FLOW_DECAY       : 평균 회귀 계수 (1에 가까울수록 빠르게 소멸)
# N = 5 (lookback 틱 수)

momentum = sector_return(t) - sector_return_avg(t-N .. t-1)
sector_flow[sector] += momentum × FLOW_SENSITIVITY
sector_flow[sector] *= (1.0 - FLOW_DECAY)
sector_flow[sector]  = clamp(sector_flow[sector], -1.0, 1.0)
```

| 변수 | 값 | 출처 |
|------|---|------|
| FLOW_SENSITIVITY | 0.5 | MarketProfile rotation_params |
| FLOW_DECAY | 0.1 | MarketProfile rotation_params |
| sector_flow 범위 | [−1.0, +1.0] | clamp 보장 |

### F4 섹터 로테이션 이벤트 트리거

```
# 매 틱 실행
sector_flow_delta = sector_flow[sector] - sector_flow_prev[sector]

if abs(sector_flow_delta) > ROTATION_THRESHOLD:
    if ticks_since_last_rotation[sector] >= ROTATION_COOLDOWN:
        direction = "inflow" if sector_flow_delta > 0 else "outflow"
        inject_rotation_event(sector, direction)
        ticks_since_last_rotation[sector] = 0

# 소외 섹터 선택 (inflow 이벤트 발화 시만)
func _pick_rival_sector(hot_sector: String) -> String:
    archetype = MarketProfile.get_archetype(hot_sector)
    rival_archetype = weighted_random(MarketProfile.rivalry_weights[archetype])
    candidates = MarketProfile.get_sectors_in_archetype(rival_archetype)
    candidates.erase(hot_sector)  # 자기 자신 제외
    return uniform_random(candidates)
```

| 파라미터 | KR 기본값 | 출처 |
|---------|---------|------|
| ROTATION_THRESHOLD | 0.03 | MarketProfile rotation_params |
| ROTATION_COOLDOWN | 5틱 | MarketProfile rotation_params |
| inflow_impact 범위 | [0.04, 0.07] | MarketProfile rotation_params |
| outflow_impact 범위 | [0.02, 0.03] | MarketProfile rotation_params |

### F5 ETF 매수 비용

```
buy_cost = quantity × price × (1.0 + 0.00015)
```

---

## 5. Edge Cases

| 케이스 | 처리 방식 |
|--------|---------|
| 섹터 종목 전체 거래 정지 | 마지막 유효 가격 유지 (ETF 가격 동결). 거래 정지 플래그가 있는 종목은 base_mcap 비율 계산에서 제외 |
| etf_price < 1원 | 하한 1원으로 클램프. 극단적 섹터 하락 방어 |
| 슬롯 부족 (보유 10종목) | OrderEngine이 거부 — 개별 종목과 동일 로직 |
| 시즌 종료 시 ETF 보유 | 다른 종목과 동일하게 현재 etf_price로 강제 청산 → cash_assets 지급 |
| P3 미해금 상태에서 ETF 주문 | OrderEngine이 거부 (SkillTree.is_unlocked("P3") 확인) |
| TR3 공매도 시도 | OrderEngine이 ETF_로 시작하는 stock_id 감지 → 즉시 거부 |
| TR4 레버리지 시도 | 동일하게 거부 |
| A4 미해금 상태 | P3도 해금 불가 (스킬 트리 순서 강제) — EtfManager는 작동하지 않음 |

---

## 6. Dependencies

| 시스템 | 방향 | 내용 |
|--------|------|------|
| PriceEngine | Hard | ETF 가격 캐시 주입 (`inject_price`) + OHLCV 기록 |
| NewsEventSystem | Hard | 섹터 로테이션 이벤트 주입 (`inject_event`) — ADR-022 EventSource 패턴. 시장 영향은 이 경로만 사용 |
| MarketProfile | Hard | ETF 목록, ETF_BASE_PRICE, sector_archetypes, rivalry_weights, rotation_params, rotation_headline_keys 로드 |
| OrderEngine | Hard | ETF 주문 체결 (즉시 체결, 슬리피지 없음), TR3/TR4 거부 |
| PortfolioManager | Hard | ETF 보유 슬롯 관리 (MAX_HOLDINGS 공유) |
| SkillTree | Hard | P3 해금 확인 (`is_unlocked("P3")`) |
| StockDatabase | Hard | 섹터 구성 종목 목록 + base_price + listed_shares 조회 |
| GameClock | Hard | `tick_processed` + `day_started` 신호 수신 |
| TradingFees | Soft | 수수료 계산 공식 (일반 종목과 동일) |
| A4 섹터 비교 | Design-time | P3 해금 선행 조건 — sector-comparison.md. `get_sector_flow()` API 소비자 |
| SaveSystem | Hard | ETF 보유 포지션 저장/로드 (save-load.md §3-5 portfolio 블록 동일) |
| **역방향**: PriceEngine | Hard | `inject_price` API 제공 의무 |
| **역방향**: NewsEventSystem | Hard | SECTOR_ROTATION 이벤트 타입 지원 의무 (news-events.md §3-8) |

---

## 7. Tuning Knobs

모든 로테이션 파라미터는 `MarketProfile.rotation_params`에서 로드. 코드 내 상수 하드코딩 금지.

| 파라미터 | KR 기본값 | 안전 범위 | 영향 |
|---------|--------|---------|------|
| ETF_BASE_PRICE | 50,000원 | 10,000 ~ 100,000 | 진입 장벽 + 수익 가시성 |
| 수수료율 | 0.015% (매수), 0.2% + 0.015% (매도) | trading-fees.md 동일 | 단타 억제 |
| MAX_HOLDINGS | 10 (P2와 공유) | 변경 불가 (P2 정의) | 분산 한계 |
| ETF 하한가 | 1원 | 0 ~ 100 | 극단적 폭락 시 계좌 보호 |
| FLOW_SENSITIVITY | 0.5 | 0.1 ~ 1.0 | 낮을수록 둔한 반응, 높을수록 급격한 쏠림 |
| FLOW_DECAY | 0.1 | 0.05 ~ 0.3 | 높을수록 빠른 평균 회귀 (회전 주기 단축) |
| ROTATION_THRESHOLD | 0.03 | 0.01 ~ 0.08 | 낮을수록 잦은 이벤트, 높을수록 큰 변화에만 반응 |
| ROTATION_COOLDOWN | 5틱 | 3 ~ 10틱 | 뉴스 피드 스팸 방지 |
| inflow_impact 범위 | [0.04, 0.07] | [0.02, 0.12] | 유입 섹터 가격 충격 강도 |
| outflow_impact 범위 | [0.02, 0.03] | [0.01, 0.06] | 소외 섹터 압력 강도 (inflow보다 항상 약하게) |

---

## 8. Acceptance Criteria

| AC # | 설명 | 유형 |
|------|------|------|
| AC-01 | P3 미해금 상태에서 ETF 주문 시 OrderEngine이 거부 메시지 반환 | Unit |
| AC-02 | 시즌 시작 시 11개 ETF 모두 50,000원으로 초기화 | Unit |
| AC-03 | 섹터 구성 종목 전체가 +10% 상승했을 때 해당 ETF 가격이 50,000 × 1.10 = 55,000원 (±10원) | Unit |
| AC-04 | 섹터 구성 종목 일부 상승/일부 하락 시 시가총액 가중 수익률 정확히 반영 | Unit |
| AC-05 | ETF 1주 매수 → 포트폴리오 슬롯 1 소비 확인 | Unit |
| AC-06 | ETF TR3 공매도 주문 시 OrderEngine이 즉시 거부 | Unit |
| AC-07 | ETF TR4 레버리지 주문 시 OrderEngine이 즉시 거부 | Unit |
| AC-08 | ETF TR2 손절 설정 → 가격 도달 시 자동 체결 확인 | Integration |
| AC-09 | 시즌 종료 시 ETF 보유분 강제 청산 → cash_assets 정확 지급 | Integration |
| AC-10 | ETF 보유 상태 세이브 → 로드 후 보유 수량·평균 단가 동일 | Integration |
| AC-11 | (E2E) A4 해금 → P3 해금 → ETF_반도체 매수 → 반도체 섹터 상승 → ETF 가격 상승 → 매도 수익 실현 전 흐름 | E2E |
| AC-12 | ETF 매도 수수료 = gross × (0.002 + 0.00015), 수령액 = gross − 수수료 정확 계산 | Unit |
| AC-13 | 섹터 종목 가격이 0원으로 내려가도 etf_price ≥ 1원 보장 | Unit |
| AC-14 | sector_flow_delta가 ROTATION_THRESHOLD 초과 시 NewsEventSystem.inject_event 호출 확인 | Unit |
| AC-15 | ROTATION_COOLDOWN 내 연속 임계값 초과 시 이벤트 1회만 발화 (쿨다운 동작) | Unit |
| AC-16 | inflow 이벤트 impact가 outflow impact보다 항상 크거나 같음 | Unit |
| AC-17 | 소외 섹터가 hot_sector와 다른 아키타입에서 선택됨 (1000회 시뮬레이션, 동일 아키타입 0회) | Unit |
| AC-18 | KR → (가상) US 시장 전환 시 EtfManager가 MarketProfile 재로드 → 섹터 목록·rotation_params 갱신 | Integration |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
이 기능은 `GameClock.tick_processed` 신호 → `EtfManager._on_tick_processed()` → 각 ETF 가격 재계산 → `PriceEngine.inject_price(etf_id, price)` 순으로 호출된다.

### 호출 경로
- [x] `EtfManager` autoload 생성 (`src/gameplay/etf_manager.gd`)
- [x] `project.godot`에 EtfManager autoload 등록
- [x] `EtfManager.register_all_etfs()` — 시즌 시작 시 SeasonManager가 호출
- [x] `PriceEngine.inject_price(etf_id: String, price: float)` 메서드 추가
- [x] `StockDatabase.get_sector_stocks(sector: String) -> Array` 메서드 확인 (없으면 추가)
- [x] `OrderEngine._validate_order()` — ETF ID 감지 시 TR3/TR4 거부 로직 추가
- [x] `OrderEngine._validate_order()` — P3 미해금 시 ETF 주문 거부 로직 추가
- [x] `OrderEngine._execute_buy/sell_etf()` — 즉시 체결, 슬리피지 없음 경로
- [x] ETF 포지션 save-load 확인 (portfolio 블록 동일 직렬화)
- [x] `MarketProfile` — ETFs, sector_archetypes, rivalry_weights, rotation_params, rotation_headline_keys 포함 (`assets/data/market_profiles/market_kr.json`)
- [x] `EtfManager._update_sector_flow()` — F3 공식 구현 (FLOW_SENSITIVITY, FLOW_DECAY)
- [x] `EtfManager._check_rotation_trigger()` — F4 공식 구현 (임계값 + 쿨다운)
- [x] `EtfManager._pick_rival_sector()` — 아키타입 기반 가중 랜덤 소외 섹터 선택
- [x] `NewsEventSystem.inject_event(SECTOR_ROTATION, ...)` 호출 — PriceEngine 직접 조작 금지
- [x] 섹터 로테이션 헤드라인 키 → `tr()` 파이프라인 연결 (Godot .po 등록)

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_etf_manager.gd` | `test_etf_order_rejected_without_p3()` |
| AC-02 | `tests/unit/test_etf_manager.gd` | `test_etf_initial_price_50000()` |
| AC-03 | `tests/unit/test_etf_manager.gd` | `test_etf_price_all_stocks_up_10pct()` |
| AC-04 | `tests/unit/test_etf_manager.gd` | `test_etf_weighted_return_mixed()` |
| AC-05 | `tests/unit/test_etf_manager.gd` | `test_etf_slot_consumed()` |
| AC-06 | `tests/unit/test_etf_manager.gd` | `test_etf_short_rejected()` |
| AC-07 | `tests/unit/test_etf_manager.gd` | `test_etf_leverage_rejected()` |
| AC-08 | `tests/integration/test_etf_integration.gd` | `test_etf_stop_loss_triggers()` |
| AC-09 | `tests/integration/test_etf_integration.gd` | `test_etf_season_end_liquidation()` |
| AC-10 | `tests/integration/test_etf_integration.gd` | `test_etf_save_load_roundtrip()` |
| AC-11 | `tests/integration/test_etf_integration.gd` | `test_etf_e2e_buy_sector_rise_sell()` |
| AC-12 | `tests/unit/test_etf_manager.gd` | `test_etf_sell_fee_calculation()` |
| AC-13 | `tests/unit/test_etf_manager.gd` | `test_etf_price_floor_1won()` |
| AC-14 | `tests/unit/test_etf_manager.gd` | `test_rotation_event_injected_on_threshold()` |
| AC-15 | `tests/unit/test_etf_manager.gd` | `test_rotation_cooldown_prevents_spam()` |
| AC-16 | `tests/unit/test_etf_manager.gd` | `test_inflow_impact_greater_than_outflow()` |
| AC-17 | `tests/unit/test_etf_manager.gd` | `test_rival_sector_different_archetype()` |
| AC-18 | `tests/integration/test_etf_integration.gd` | `test_market_profile_reload_on_season_start()` |

### 빌드 검증
- [x] `--export-release` 빌드 성공 (ERROR 없음)
- [x] 바이너리 실행 후 5초 이상 프로세스 생존
- [x] 실행 로그에 SCRIPT ERROR 없음
- [x] QA Lead 서명: (S10-02 구현 완료 2026-04-20)
