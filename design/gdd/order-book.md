# Order Book (호가창) — Design Document

> **Status**: Approved (2026-04-07)

## 1. Overview

매 틱 갱신되는 종목별 10단 호가창(매도5·매수5)을 시뮬레이션하고, 플레이어 주문이
호가 잔량을 실제로 소진하며 체결된다. 잔량이 0이 되면 해당 레벨은 사라지고 바깥쪽에
새 레벨이 자동 생성된다(상/하한가까지).

**저장 없음**: KRX 미체결 잔량은 장 마감 시 전량 초기화된다. 게임 저장도 장 마감
시점(`on_market_close`)에 발생하므로, 호가창은 저장하지 않고 매 거래일
`confirm_market_open()` 시점에 새로 초기화한다.

**권위 문서**: 이 문서가 호가 잔량 메카닉의 단일 소스다.
관련 문서: `trading-screen.md §주문패널`, `save-load.md §PriceEngine`,
`src/gameplay/order_engine.gd`

---

## 2. Player Fantasy

"내 매수 주문이 시장을 움직인다." 플레이어는 호가창을 보면서 매도 잔량이 얼마나 쌓여
있는지 읽고 전략을 세운다. 대형 주문을 넣으면 잔량이 눈에 띄게 줄어들고, 다음 호가로
가격이 밀린다. 현실 HTS와 같은 긴박감과 정보 밀도.

---

## 3. Detailed Design

### 3-1. 호가 구조

```
[매도5] price_ask5  qty_ask5   ← 가장 비싼 매도호가
[매도4] price_ask4  qty_ask4
[매도3] price_ask3  qty_ask3
[매도2] price_ask2  qty_ask2
[매도1] price_ask1  qty_ask1   ← 최우선 매도호가 (current_price + 1 tick)
────────────────── 현재가 ──────
[매수1] price_bid1  qty_bid1   ← 최우선 매수호가 (current_price)
[매수2] price_bid2  qty_bid2
[매수3] price_bid3  qty_bid3
[매수4] price_bid4  qty_bid4
[매수5] price_bid5  qty_bid5   ← 가장 낮은 매수호가
```

- **호가 간격**: KRX 호가 단위 (ADR-002, `PriceEngine.get_tick_size()`)
- **초기화 시점**: 매 거래일 `GameClock.confirm_market_open()` 호출 시 §4-1 공식으로 생성
- **런타임 상태**: `PriceEngine._stock_states[stock_id]["order_book"]`에 보관.
  장 마감 시 폐기, 저장하지 않음.

### 3-2. 잔량 갱신 (매 틱) — 가격·볼륨 연동

**처리 순서 보장**: `GameClock._process_tick()` 내 실행 순서는
`PriceEngine → OrderEngine`. PriceEngine이 가격 확정 및 호가 재앵커링을
완료한 뒤 OrderEngine이 플레이어 주문을 소진한다. 이중 소진 없음.

매 틱 처리는 **두 단계**로 수행한다. `PriceEngine.process_tick()` 내에서
가격 확정 직후 실행.

#### 1단계: 가격 이동에 따른 레벨 소진 및 재앵커링

```
old_price = 이전 틱 current_price
new_price = 이번 틱 확정된 current_price

if new_price > old_price:   # 가격 상승
    # ① ask: new_price 이하 레벨 소진 (매수 압력이 ask를 뚫음 — new_price 자체도 체결됨)
    removed_count = ask_levels에서 price <= new_price 인 레벨 제거 후 실제 제거 수 카운트
    ask 원거리에 removed_count 개 신규 레벨 추가 (§4-3, 상한가 경계 준수)

    # ② bid: new_price 를 새 bid1으로 삽입 (old bid1은 bid2로 밀림)
    bid_levels 맨 앞에 {price: new_price, qty: §4-3 신규잔량} 삽입
    bid_levels 크기 > 5 이면 가장 원거리(마지막) 레벨 제거

elif new_price < old_price:   # 가격 하락
    # ① bid: new_price 초과 레벨 소진 (매도 압력이 bid를 뚫음)
    #    new_price 자체는 제거하지 않음 — bid1이 될 수 있음
    removed_count = bid_levels에서 price > new_price 인 레벨 제거 후 실제 제거 수 카운트
    bid 원거리에 removed_count 개 신규 레벨 추가 (§4-3, 하한가 경계 준수)

    # ② ask: new_price + tick_size 를 새 ask1으로 삽입 (old ask1은 ask2로 밀림)
    tick_size = PriceEngine.get_tick_size(new_price)
    ask_levels 맨 앞에 {price: new_price + tick_size, qty: §4-3 신규잔량} 삽입
    ask_levels 크기 > 5 이면 가장 원거리(마지막) 레벨 제거

# new_price == old_price: 가격 변동 없음 → 재앵커링 불필요, 2단계만 실행
```

> **불변식**: 1단계 완료 후 항상 `bid1.price == new_price`,
> `ask1.price == new_price + get_tick_size(new_price)` 가 성립해야 한다.
>
> **tick_size 경계 안전**: removed_count는 delta_ticks 계산 없이 실제 제거된
> 레벨 수를 직접 카운트한다. 가격이 tick_size 경계(예: 4,900→5,100)를 넘어도
> 정확히 동작한다.

#### 2단계: 볼륨 연동 잔량 변동 (기존 레벨 대상)

```
volume_factor = tick_volume / (DAILY_VOLUME_BY_PROFILE[volatility_profile] / TICKS_PER_DAY)
volume_factor = clampf(volume_factor, 0.1, 5.0)   # 극단값 방지

for each level in ask_levels + bid_levels:
    base_qty = base_qty_per_level * LEVEL_WEIGHT[level.rank]
    inflow   = int(base_qty * INFLOW_RATE  * volume_factor * randf_range(0.5, 1.5))
    outflow  = int(base_qty * OUTFLOW_RATE * volume_factor * randf_range(0.5, 1.5))
    level.qty = max(0, level.qty + inflow - outflow)
    if level.qty == 0:
        소멸 처리 (§3-3)
```

- `tick_volume`: PriceEngine이 해당 틱에 산출한 실제 거래량 (기존 값)
- `volume_factor > 1`: 평균 이상 거래량 → 잔량 변동 폭 확대
- `volume_factor < 1`: 한산한 틱 → 잔량 변동 미미

### 3-3. 레벨 소멸 및 신규 레벨 생성

**매도 레벨 소멸 (ask.qty == 0)**:
1. 해당 레벨 배열에서 제거
2. 기존 최원거리 매도가 + 1 tick 위치에 새 레벨 추가 (§4-3)
3. 새 레벨 가격 ≤ 상한가(§4-4)인 경우에만 생성. 초과 시 생성 없음 → 4단 이하 가능

**매수 레벨 소멸 (bid.qty == 0)**:
동일 로직, 방향 반대. 새 레벨 ≥ 하한가인 경우에만 생성.

### 3-4. 주문 체결과 호가 소진

`PriceEngine.consume_order_book(stock_id, side, order_qty, limit_price)` 호출.
`limit_price == -1` 이면 시장가(제한 없음), 값이 있으면 지정가.

**매수 체결 (side = "buy")**:
```
remaining  = order_qty
total_cost = 0
filled_qty = 0

for ask_level in ask_levels (ask1 → ask5):
    if remaining <= 0: break
    if limit_price != -1 and ask_level.price > limit_price: break  # 지정가 초과 중단

    fill        = min(remaining, ask_level.qty)
    total_cost += fill * ask_level.price
    filled_qty += fill
    remaining  -= fill
    ask_level.qty -= fill
    if ask_level.qty == 0: 소멸 처리 (§3-3)

if filled_qty == 0:
    avg_price = 0   # 체결 없음 — 호출자는 filled_qty == 0 확인 후 avg_price 무시
else:
    avg_price = PriceEngine.round_to_tick(total_cost / filled_qty)
반환: {filled_qty, avg_price, remaining_qty: remaining}
```

**매도는 bid_levels 방향 동일 적용. `limit_price`이면 `bid_level.price < limit_price`에서 중단.**

> **지정가 슬리피지**: 지정가 매수 60,000원이고 ask1=59,500, ask2=60,000인 경우,
> ask1과 ask2 모두 소화 → 가중평균가 체결. 지정가도 시장가와 동일한 레벨 소진 로직이며
> 지정가를 초과하는 레벨에서만 중단한다.

`remaining_qty > 0` 이면 → OrderEngine **pending_orders 큐**에 잔류 처리:

- 미체결분은 동일 주문 조건(방향·가격·잔여수량)으로 pending_orders에 남음
- 다음 틱 `OrderEngine.process_tick()` 시 pending_orders를 재순회하며 `consume_order_book()` 재시도
- **시장가 미체결**: 장중이면 다음 틱 최우선 재시도. 장 마감 시 취소
- **지정가 미체결**: 가격 조건 미충족이면 계속 대기, 장 마감(`on_market_close`) 시 전량 취소
  (KRX 당일주문 규칙 — 기존 OrderEngine 동작 그대로 적용)

### 3-5. UI — 주문 패널 통합

```
┌──────────────────────────────────────┐
│ [매도5] 76,500  |  2,340  ████░░░░░ │
│ [매도4] 76,000  |  1,820  ███░░░░░░ │
│ [매도3] 75,500  |  1,200  ██░░░░░░░ │
│ [매도2] 75,000  |    980  █░░░░░░░░ │
│ [매도1] 74,500  |    650  █░░░░░░░░ │  ← 최우선 매도
│ ─────── 현재가 74,000 ────────────── │
│ [매수1] 74,000  |  1,100  ██░░░░░░░ │  ← 최우선 매수
│ [매수2] 73,500  |  1,450  ██░░░░░░░ │
│ [매수3] 73,000  |  1,780  ███░░░░░░ │
│ [매수4] 72,500  |  2,200  ████░░░░░ │
│ [매수5] 72,000  |  2,600  █████░░░░ │
└──────────────────────────────────────┘
[주문 유형 / 가격 / 수량 입력 영역]
```

**클릭 인터랙션**:
- 매도 레벨 클릭 → 지정가 매수 가격 필드에 해당 가격 입력
- 매수 레벨 클릭 → 지정가 매도 가격 필드에 해당 가격 입력
- 주문 유형이 시장가일 때 클릭 → 무시 (UI 피드백 없음)
- 종목 선택 변경 시 → 해당 종목 호가창으로 즉시 전환

**잔량 바**: 현재 화면에 표시된 10단 중 최대 잔량 기준 상대적 폭. 매 틱 갱신.

---

## 4. Formulas

### 4-1. 초기 호가 생성 (매 거래일 장 시작 시)

```
DAILY_VOLUME_BY_PROFILE = {
    LOW:      50_000,
    MEDIUM:  200_000,
    HIGH:    800_000,
    EXTREME: 2_000_000,
}

base_qty_per_level = max(1, DAILY_VOLUME_BY_PROFILE[volatility_profile] / TICKS_PER_DAY / 5)

# 레벨별 가중치: 원거리일수록 잔량 많음 (패시브 주문 집중)
LEVEL_WEIGHT = [1.0, 1.3, 1.6, 2.0, 2.5]   # index 0 = 호가1 (최우선)

qty_initial[level] = max(1, int(
    base_qty_per_level * LEVEL_WEIGHT[level] * randf_range(0.7, 1.3)
))

# ask: current_price + (level+1) * tick_size  (level 0~4)
# bid: current_price - level * tick_size       (level 0~4)
```

### 4-2. 틱별 잔량 변동 (볼륨 연동)

```
base_qty      = base_qty_per_level * LEVEL_WEIGHT[level.rank]
volume_factor = clampf(
    tick_volume / (DAILY_VOLUME_BY_PROFILE[volatility_profile] / TICKS_PER_DAY),
    0.1, 5.0
)

inflow  = int(base_qty * INFLOW_RATE  * volume_factor * randf_range(0.5, 1.5))
outflow = int(base_qty * OUTFLOW_RATE * volume_factor * randf_range(0.5, 1.5))
qty     = max(0, qty + inflow - outflow)
```

| 파라미터 | 기본값 | 의미 |
|---------|--------|------|
| `INFLOW_RATE` | 0.08 | 틱당 유입 기본 비율 (base_qty 대비) |
| `OUTFLOW_RATE` | 0.06 | 틱당 소진 기본 비율 (base_qty 대비) |
| `volume_factor` clamp | [0.1, 5.0] | 거래량 폭주/한산 시 극단 방지 |

### 4-3. 신규 레벨 잔량

```
new_qty = max(1, int(
    base_qty_per_level * LEVEL_WEIGHT[4] * randf_range(0.7, 1.3)
))
```

### 4-4. 상/하한가 경계

```
upper_limit = PriceEngine.round_to_tick(prev_day_close * 1.30)
lower_limit = PriceEngine.round_to_tick(prev_day_close * 0.70)

# 새 매도 레벨 생성 조건: new_price <= upper_limit
# 새 매수 레벨 생성 조건: new_price >= lower_limit
```

---

## 5. Edge Cases

| # | 상황 | 처리 |
|---|------|------|
| EC-01 | 상한가 도달로 매도 레벨이 5단 미만 | 가능한 레벨만 표시. 상한가 레벨에 "상한" 표시 |
| EC-02 | 하한가 도달로 매수 레벨이 5단 미만 | 동일. 하한가 레벨에 "하한" 표시 |
| EC-03 | 대형 주문이 5단 전량 소진 후에도 수량 남음 | 가능한 전량 즉시 체결 + 나머지 미체결 큐 |
| EC-04 | 지정가 주문 가격이 호가창 범위 밖 (ask1보다 낮은 매수 등) | 즉시 체결 가능 레벨 없음 → 전량 미체결 큐 |
| EC-05 | VI 발동 중 주문 도달 | OrderEngine 기존 VI halt 로직 우선. 호가창 갱신 중단 (halt_remaining 동안) |
| EC-06 | 가격이 한 틱에 5단 이상 급등 | 넘어간 레벨 전량 소진, 신규 레벨 5단 재생성. 상/하한가 경계 준수 |
| EC-07 | 매수1 = 매도1 (스프레드 0) | 발생 불가. bid1 = current_price, ask1 = current_price + tick_size ≥ 1 |
| EC-08 | base_qty_per_level 계산값 0 이하 | max(1, ...) 보장으로 최소 1주 잔량 유지 |
| EC-09 | volume_factor 계산 시 DAILY_VOLUME 분모 0 | max(1, DAILY_VOLUME_BY_PROFILE[...]) 보장 |
| EC-10 | 장 마감 후 로드 시 호가창 없음 | 정상. 다음 날 confirm_market_open() 시 재초기화 |

---

## 6. Dependencies

| 시스템 | 방향 | 인터페이스 |
|--------|------|-----------|
| PriceEngine | 호가 생성·갱신·소진 소유자 | `get_order_book(stock_id)`, `consume_order_book(stock_id, side, qty, limit_price)` |
| OrderEngine | 호가 소비자 (체결 시) | `PriceEngine.consume_order_book()` 호출. **처리 순서: PriceEngine 완료 후 실행** |
| GameClock | 틱 타이밍·장 시작 신호 | `on_tick` → PriceEngine 먼저, OrderEngine 나중. `confirm_market_open()` → 호가 초기화 트리거 |
| OrderPanel (UI) | 호가 표시·클릭 | `PriceEngine.get_order_book()` 조회 + `on_tick` 갱신 |
| ADR-002 | 호가 단위 | `PriceEngine.get_tick_size(price)` |

---

## 7. Tuning Knobs

| 파라미터 | 현재값 | 안전 범위 | 증가 효과 | 감소 효과 |
|---------|--------|----------|----------|----------|
| `DAILY_VOLUME_BY_PROFILE[LOW]` | 50,000 | 10K–200K | 저변동 종목 호가 두꺼워짐 | 얇아져 쉽게 뚫림 |
| `DAILY_VOLUME_BY_PROFILE[MEDIUM]` | 200,000 | 50K–1M | — | — |
| `DAILY_VOLUME_BY_PROFILE[HIGH]` | 800,000 | 200K–5M | — | — |
| `DAILY_VOLUME_BY_PROFILE[EXTREME]` | 2,000,000 | 500K–10M | — | — |
| `LEVEL_WEIGHT[0..4]` | [1.0,1.3,1.6,2.0,2.5] | 0.5–5.0 | 원거리 호가 더 두꺼워짐 | 원거리 얇아짐 |
| `INFLOW_RATE` | 0.08 | 0.01–0.30 | 잔량 빠르게 회복 | 잘 안 채워짐 |
| `OUTFLOW_RATE` | 0.06 | 0.01–0.25 | AI가 호가 빠르게 소진 | 시장 조용함 |

---

## 8. Acceptance Criteria

| # | 조건 | 검증 방법 |
|----|------|----------|
| AC-01 | 매 거래일 장 시작 시 종목별 10단 호가 초기화 (상/하한가 근처 제외) | `test_order_book_initialized_on_market_open()` |
| AC-02 | 매수 주문이 매도 잔량을 실제로 차감한다 | `test_buy_order_consumes_ask_qty()` |
| AC-03 | 잔량 0 소멸 시 5단 유지를 위한 신규 레벨이 바깥쪽에 생성된다 | `test_level_consumed_adds_far_level()` |
| AC-04 | 5단 전량 소진 시 가능 수량만 체결되고 나머지는 미체결 큐에 남는다 | `test_partial_fill_queued_on_book_exhaustion()` |
| AC-05 | 슬리피지 발생 시 체결 평균가가 단일 호가와 다르다 | `test_slippage_avg_price_differs_from_single_level()` |
| AC-06 | 상한가 초과 매도 레벨 생성 없음. 하한가 미만 매수 레벨 생성 없음 | `test_no_level_beyond_price_limit()` |
| AC-07 | 가격 N틱 상승 후 bid1 == new_price, ask1 == new_price + tick_size | `test_price_up_reanchors_bid_and_ask()` |
| AC-08 | 가격 N틱 하락 후 bid1 == new_price, ask1 == new_price + tick_size | `test_price_down_reanchors_bid_and_ask()` |
| AC-09 | 고거래량 틱에서 잔량 변동 폭이 저거래량 틱보다 크다 | `test_volume_factor_scales_activity()` |
| AC-10 | 지정가 매수 시 지정가 초과 ask 레벨에서 체결 중단 | `test_limit_buy_stops_at_limit_price()` |
| AC-11 | VI halt 중 호가창 갱신 중단 | `test_order_book_frozen_during_halt()` |
| AC-12 | 호가 클릭 → 지정가 입력 필드 가격 자동 입력 | E2E 시각 검증 |
| AC-13 | 시장가 선택 중 호가 클릭 → 아무 반응 없음 | E2E 시각 검증 |
| AC-14 | 종목 선택 변경 시 호가창 해당 종목으로 즉시 전환 | E2E 시각 검증 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
- 호가 초기화: `GameClock.confirm_market_open()` → `PriceEngine.initialize_order_books()`
- 호가 갱신: `GameClock.on_tick` → `PriceEngine.process_tick()` → `_update_order_books()`
- 호가 소비: `OrderEngine.process_tick()` → `PriceEngine.consume_order_book()`
- UI 갱신: `GameClock.on_tick` → `OrderPanel._on_tick()` → `PriceEngine.get_order_book()`

### 호출 경로
- [ ] `PriceEngine._stock_states[stock_id]["order_book"]` 키 추가 (`ask`, `bid` 배열)
- [ ] `PriceEngine.initialize_order_books()` — `confirm_market_open()` 시 전 종목 초기화
- [ ] `PriceEngine._update_order_books(old_prices)` — `process_tick()` 내 가격 확정 직후 호출
- [ ] `PriceEngine.get_order_book(stock_id) → Dictionary` — UI·OrderEngine 조회용
- [ ] `PriceEngine.consume_order_book(stock_id, side, qty, limit_price) → Dictionary` — 반환: `{filled_qty, avg_price, remaining_qty}`
- [ ] `OrderEngine.process_tick()` — 체결 로직에서 `consume_order_book()` 사용
- [ ] `GameClock.confirm_market_open()` 또는 그 호출 체인에서 `initialize_order_books()` 연결
- [ ] `OrderPanel` — 호가창 UI 섹션 추가 (매 틱 갱신, 클릭 핸들러, 종목 전환)

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_order_book.gd` | `test_order_book_initialized_on_market_open()` |
| AC-02 | `tests/unit/test_order_book.gd` | `test_buy_order_consumes_ask_qty()` |
| AC-03 | `tests/unit/test_order_book.gd` | `test_level_consumed_adds_far_level()` |
| AC-04 | `tests/unit/test_order_book.gd` | `test_partial_fill_queued_on_book_exhaustion()` |
| AC-05 | `tests/unit/test_order_book.gd` | `test_slippage_avg_price_differs_from_single_level()` |
| AC-06 | `tests/unit/test_order_book.gd` | `test_no_level_beyond_price_limit()` |
| AC-07 | `tests/unit/test_order_book.gd` | `test_price_up_reanchors_bid_and_ask()` |
| AC-08 | `tests/unit/test_order_book.gd` | `test_price_down_reanchors_bid_and_ask()` |
| AC-09 | `tests/unit/test_order_book.gd` | `test_volume_factor_scales_activity()` |
| AC-10 | `tests/unit/test_order_book.gd` | `test_limit_buy_stops_at_limit_price()` |
| AC-11 | `tests/unit/test_order_book.gd` | `test_order_book_frozen_during_halt()` |
| AC-12 | E2E 시각 검증 | — |
| AC-13 | E2E 시각 검증 | — |
| AC-14 | E2E 시각 검증 | — |

### 빌드 검증
- [ ] 바이너리 실행 확인: QA Lead 서명 _______
