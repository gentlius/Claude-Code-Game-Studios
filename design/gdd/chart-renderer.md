# 차트 렌더러 (Chart Renderer)

> **Status**: In Review
> **Author**: user + game-designer
> **Last Updated**: 2026-04-02
> **Implements Pillar**: 읽는 재미 (Read the Market), 판단이 곧 실력 (Judgment is King)

## Overview

차트 렌더러는 가격 엔진이 생성하는 가격/거래량 데이터를 캔들차트와 보조지표로
시각화하는 Presentation 시스템이다. 트레이딩 스크린의 중앙 영역을 차지하며,
플레이어가 시장을 "읽는" 핵심 인터페이스다.

스킬 트리의 분석 도구 레벨에 따라 표시 가능한 지표가 해금된다: A0(기본 캔들차트
+ 거래량), A1(이동평균선 5/20/60), A2(RSI, MACD). 4가지 타임프레임(1분, 5분,
15분, 1일)을 지원하며, 줌/스크롤/크로스헤어 인터랙션을 제공한다.

A3(재무제표) 및 A4(섹터 비교 분석)의 표시 패널은 향후 확장 예정 (skill-tree.md 참조).

시스템 인덱스에서 High-Risk로 분류된 시스템이다 — 웹 환경에서 실시간 캔들차트를
부드럽게 렌더링하는 것이 핵심 기술 과제다.

## Player Fantasy

차트를 본다. 캔들이 하나씩 쌓인다. "상승추세다. 이동평균선이 골든크로스를 그렸어."
차트에서 패턴이 보이기 시작하는 순간이 실력 성장의 증거다. RSI가 70을 넘었다 —
"과매수 구간이야, 조정 올 수 있어." 차트를 읽을 수 있다는 건 시장을 읽을 수 있다는
뜻이다.

필라 "읽는 재미"에 따라 차트는 정보 전달이 최우선이다. 화려한 이펙트보다 깔끔한
캔들, 명확한 색상, 읽기 쉬운 눈금이 중요하다. 필라 "판단이 곧 실력"에 따라 차트의
패턴은 실제 가격 엔진의 상태를 정직하게 반영해야 한다 — 이동평균선이 크로스하면
실제로 추세 전환 가능성이 높다.

## Detailed Design

### Core Rules

#### 규칙 1. 캔들차트 기본 구조

##### 1-1. OHLCV 데이터

가격 엔진이 틱마다 생성하는 가격 데이터를 타임프레임별로 집계한다.

```
CandleData {
    open: int           # 시가 (구간 첫 틱 가격)
    high: int           # 고가 (구간 내 최고가)
    low: int            # 저가 (구간 내 최저가)
    close: int          # 종가 (구간 마지막 틱 가격)
    volume: int         # 거래량 (구간 내 합산)
    tick_start: int     # 구간 시작 틱
    tick_end: int       # 구간 종료 틱
}
```

##### 1-2. 타임프레임

1틱 = 실시간 0.192초(1x 기준), 게임 내 시간 15초. 타임프레임은 게임시간 기준으로 표기한다.

| 타임프레임 | 틱 수 | 1거래일(1560틱) 내 캔들 수 | 용도 |
|-----------|-------|--------------------------|------|
| 1분 (M1) | 4틱 | 390개 | 단타 분석. 실시간 가격 추적 |
| 5분 (M5) | 20틱 | 78개 | 단기 패턴 분석 |
| 15분 (M15) | 60틱 | 26개 | 중기 추세 분석 |
| 1일 (D1) | 1560틱 | 1개 | 장기 추세. 시즌 전체 조망 |

기본 타임프레임: **1분(M1)**. 플레이어가 탭으로 전환 가능.

##### 1-3. 캔들 집계

```
aggregate_candle(ticks[], timeframe):
    candle = {
        open: ticks[0].price,
        high: max(t.price for t in ticks),
        low: min(t.price for t in ticks),
        close: ticks[-1].price,
        volume: sum(t.volume for t in ticks)
    }
    return candle
```

진행 중인 캔들(현재 구간): 매 틱 high/low/close/volume이 갱신된다.

##### 1-4. 캔들 색상

| 조건 | 캔들 몸통 색상 | 설명 |
|------|-------------|------|
| close > open | 빨강 (상승) | 한국 주식시장 관례 |
| close < open | 파랑 (하락) | 한국 주식시장 관례 |
| close == open | 회색 (보합) | 십자선/도지 |

거래량 바: 해당 캔들과 동일 색상. 하단에 별도 영역.

#### 규칙 2. 차트 레이아웃

##### 2-1. 전체 레이아웃 개요

```
┌─────────────────────────────────────┐
│ [종목명] [현재가] [등락률]  [타임프레임 탭] │  ← 헤더
├─────────────────────────────────────┤
│                                     │
│          캔들차트 영역               │  ← 전체 높이의 65%
│       (+ 이동평균선 오버레이)         │
│                                     │
├─────────────────────────────────────┤
│       거래량 바 차트                  │  ← 전체 높이의 15%
├─────────────────────────────────────┤
│       보조지표 영역 (RSI/MACD)       │  ← 전체 높이의 20% (A2 해금 시)
└─────────────────────────────────────┘
│← 가격 눈금(Y축)                 시간 눈금(X축) →│
```

- A0~A1: 보조지표 영역 없음. 캔들 70% + 거래량 30%
- A2: 보조지표 영역 등장. 캔들 65% + 거래량 15% + 보조지표 20%
- 위 비율은 **헤더 영역(종목명/현재가/타임프레임 탭, 약 48px) 아래**의 차트 본문에 적용

##### 2-2. Y축 자동 스케일 알고리즘

**Step 1: 가격 범위 계산**

```
visible_candles = candles[scroll_offset .. scroll_offset + visible_count]
price_min = min(c.low for c in visible_candles)
price_max = max(c.high for c in visible_candles)
price_range = price_max - price_min

# 최소 스케일: 박스권에서 캔들이 납작해지는 것 방지
min_range = price_min × min_y_range_ratio   # min_y_range_ratio = 0.02 (2%)
effective_range = max(price_range, min_range)

# 패딩 적용
padded_min = price_min - effective_range × y_axis_padding
padded_max = price_max + effective_range × y_axis_padding
```

**Step 2: 호가 단위 기반 Y축 그리드 (nice_step)**

그리드 라인을 호가 단위의 배수에 정렬하여, 모든 눈금이 실제 체결 가능한
가격에 위치하도록 한다.

```
tick_size = get_tick_size(price_mid)     # 현재 가격대의 호가 단위
                                         # price_mid = (padded_min + padded_max) / 2
raw_step = (padded_max - padded_min) / target_grid_lines   # target = 5

# 호가 단위의 배수 중 raw_step에 가장 가까운 "보기 좋은" 값 선택
nice_step = find_nice_step(raw_step, tick_size)

# 그리드 라인: nice_step 간격으로, 첫 라인은 padded_min 위의 첫 배수
first_line = ceil(padded_min / nice_step) × nice_step
grid_lines = [first_line, first_line + nice_step, first_line + 2×nice_step, ...]
             while line <= padded_max
```

**nice_step 선택 알고리즘**:

```
find_nice_step(raw_step: float, tick_size: int) -> int:
    # 호가 단위의 배수로 구성된 후보 목록
    NICE_MULTIPLIERS = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000]

    for m in NICE_MULTIPLIERS:
        candidate = tick_size × m
        if candidate >= raw_step:
            return candidate

    return tick_size × NICE_MULTIPLIERS[-1]   # fallback
```

**예시**:

| 종목 | 가격대 | 호가 단위 | 1분봉 범위 | raw_step | nice_step | 그리드 라벨 예시 |
|------|--------|----------|-----------|----------|-----------|----------------|
| GRC (38,000원) | ~50,000 | 50원 | ~300원 | ~60원 | 100원(50×2) | 37,900 / 38,000 / 38,100 |
| KSF (65,000원) | ~100,000 | 100원 | ~500원 | ~100원 | 100원(100×1) | 64,800 / 64,900 / 65,000 / 65,100 |
| STC (120,000원) | ~500,000 | 500원 | ~1,200원 | ~240원 | 500원(500×1) | 119,500 / 120,000 / 120,500 |
| SKL (210,000원) | ~500,000 | 500원 | ~2,000원 | ~400원 | 500원(500×1) | 209,000 / 209,500 / 210,000 / 210,500 |

> **설계 의도**: 그리드 라벨이 항상 깔끔한 라운드 넘버이면서, 해당 가격대에서
> 실제 존재할 수 있는 가격에만 위치한다. 호가 단위가 100원인 종목에서 64,850원
> 같은 불가능한 가격이 그리드에 찍히지 않는다.

**Y좌표 변환** (기존과 동일):

```
y_position(price) = chart_height × (1 - (price - padded_min) / (padded_max - padded_min))
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `scroll_offset` | int | 0+ | 사용자 입력 | 뷰포트 시작 캔들 인덱스 |
| `visible_count` | int | 20~200 | 줌 레벨 | 화면에 표시되는 캔들 수 |
| `min_y_range_ratio` | float | 0.01~0.05 | config | 최소 Y축 범위 비율 |
| `y_axis_padding` | float | 0.02~0.10 | config | Y축 상하 여백 비율 |
| `target_grid_lines` | int | 3~8 | config | 목표 그리드 라인 수 (기본 5) |

BREAKOUT 등 급변 시 `price_range`가 커지면서 자동으로 Y축이 확장되고,
nice_step도 더 큰 배수로 올라간다.
스크롤 시 뷰포트 내 캔들만으로 재계산하므로 과거 탐색 시에도 적절한 스케일이 유지된다.

#### 규칙 3. 스킬별 오버레이

##### 3-1. 이동평균선 (A1 해금)

| MA | 기간 | 색상 | 용도 |
|----|------|------|------|
| MA5 | 5구간 | 노랑 | 초단기 추세 |
| MA20 | 20구간 | 주황 | 단기 추세 |
| MA60 | 60구간 | 보라 | 중기 추세 |

각 MA는 토글로 개별 표시/숨김 가능.

**골든크로스/데드크로스 표시**: MA5가 MA20을 상향 돌파 시 ▲ 마커,
하향 돌파 시 ▼ 마커 표시.

##### 3-2. RSI (A2 해금)

보조지표 영역 상단에 표시. 기간 14.

과매수 구간(70 이상): 빨강 배경 강조
과매도 구간(30 이하): 파랑 배경 강조

##### 3-3. MACD (A2 해금)

보조지표 영역에 RSI와 탭으로 전환하여 표시.
- MACD 선 (12-26 EMA 차이): 파랑
- Signal 선 (MACD의 9 EMA): 주황
- Histogram (MACD - Signal): 빨강/파랑 바

#### 규칙 4. 인터랙션

| 인터랙션 | 동작 | 입력 |
|---------|------|------|
| 줌 인/아웃 | 표시 캔들 수 조정 (20~200개) | 마우스 휠 / 핀치 |
| 스크롤 | 과거 캔들 탐색 | 드래그 / 방향키 |
| 크로스헤어 | 마우스 위치의 가격/시간 표시 | 마우스 호버 |
| 캔들 상세 | OHLCV 수치 팝업 | 캔들 클릭 |
| 타임프레임 변경 | 캔들 재집계 후 표시 | 탭 클릭 |

##### 4-1. 자동 스크롤

장중(MARKET_OPEN) 실시간 모드: 최신 캔들이 항상 우측 끝에 위치.
플레이어가 과거로 스크롤하면 자동 스크롤 해제 — "현재로 이동" 버튼 표시.

#### 규칙 5. 데이터 관리

##### 5-1. 가격 히스토리 버퍼

```
PriceHistoryBuffer {
    tick_prices: Array[TickPrice]        # 시즌 전체 틱 (single source of truth)
    max_tick_history: int = 31200       # 1시즌 분량 (1560틱/일 × 20거래일). ~500KB/종목
}
```

- **모든 타임프레임(1분봉, 5분봉, 15분봉, 일봉)은 `tick_prices`에서 on-the-fly 계산.**
  캐시/요약 별도 저장 없음 — 틱 데이터가 유일한 소스.
- 1분봉: 4틱 단위 집계 (TICKS_PER_MINUTE = 4)
- 5분봉: 20틱 단위 집계 (TICKS_PER_MINUTE × 5)
- 15분봉: 60틱 단위 집계
- 일봉: 1560틱 단위 집계
- 성능: 31,200틱 전체 스캔 ~0.1ms 이하. 캐시 불필요

**초기화**: 종목 선택 시(UNLOADED → LOADING) `get_tick_buffer(stock_id)`로 현재 시즌의
틱 히스토리를 일괄 로드한다. 일봉/분봉은 틱 데이터에서 on-the-fly 계산.
이후 `on_tick` 시그널 구독으로 실시간 갱신. 시즌 첫 거래일에는 히스토리가 비어있어
즉시 LIVE 전환된다.

##### 5-2. 시즌 시작 시 초기 데이터

시즌 첫 거래일에는 과거 데이터가 없다. 첫 틱부터 캔들이 쌓이기 시작한다.

**지표별 최소 데이터 요건 및 동작**:

| 지표 | 최소 캔들 수 | 데이터 부족 시 동작 |
|------|------------|-------------------|
| MA5 | 3개 이상 | 가용 데이터로 계산 + 점선 표시. 5개 이상이면 실선 |
| MA20 | 10개 이상 | 가용 데이터로 계산 + 점선 표시. 20개 이상이면 실선 |
| MA60 | 60개 | 60개 미만 시 **미표시** ("데이터 부족" 안내) |
| RSI(14) | 14개 | 14개 미만 시 **미표시** |
| MACD(12,26,9) | 26개 | 26개 미만 시 **미표시** |

> **참고**: MA60은 1D(일봉) 타임프레임에서 시즌 내(최대 20~30 거래일) 데이터가
> 영구적으로 부족하여 표시 불가. 1D 차트에서 MA60은 사실상 사용 불가한
> 지표임을 인지. 5T/15T 타임프레임에서는 시즌 초반 이후 사용 가능.

#### 규칙 6. 성능 전략

| 전략 | 상세 |
|------|------|
| 더티 플래그 | 가격 변동 시에만 차트 갱신. idle 틱에는 렌더 스킵 |
| 뷰포트 렌더링 | 화면에 보이는 캔들만 렌더. `visible_range = [scroll_offset, scroll_offset + visible_count]`. 뷰포트 밖 캔들은 렌더 스킵. 뷰포트 경계의 부분 캔들(좌우 끝)은 클리핑하여 표시 |
| 캔들 캐시 | 확정된 캔들은 재계산 없이 캐시에서 로드 |
| 지표 증분 계산 | RSI/MACD는 본질적으로 증분(Wilder/EMA). MA는 running sum + ring buffer 방식: `new_sum = old_sum - oldest_close + newest_close`, `SMA = new_sum / n`. 전체 재계산 없이 O(1)에 갱신 |
| 배속별 렌더 스킵 | 2x 이상 배속 시 2틱마다 1회 렌더 (2x, 4x 동일 스킵 비율 적용. 시각적 차이 무의미) |

### States and Transitions

| State | Description | Transition |
|-------|-------------|------------|
| **UNLOADED** | 종목 미선택. 빈 차트 | → LOADING (종목 선택 시) |
| **LOADING** | 히스토리 로드 중 | → LIVE (데이터 준비 완료) |
| **LIVE** | 실시간 갱신 중. 새 틱마다 캔들 업데이트 | → PAUSED (일시정지 시) / STATIC (`on_market_state_changed`로 MARKET_CLOSED, WEEK_END, SEASON_END 진입 시) |
| **PAUSED** | 일시정지. 차트 고정. 스크롤/줌 가능 | → LIVE (재개 시) |
| **STATIC** | 장 마감. 차트 고정. 과거 탐색만 가능 | → LIVE (다음 장 시작 시) |

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **가격 엔진** | 차트가 의존 | `get_current_price(stock_id)` — 매 틱 현재가. `get_tick_buffer(stock_id)` — 시즌 전체 틱 시계열 (일봉/분봉은 on-the-fly 계산) |
| **트레이딩 스크린** | 트레이딩 스크린이 차트를 호스팅 | 차트 영역 배치. 종목 선택 이벤트 전달 |
| **스킬 트리** | 차트가 참조 | `is_skill_unlocked("A1")` — MA 표시, `is_skill_unlocked("A2")` — RSI/MACD 표시 |
| **게임 시계** | 차트가 의존 | `on_market_state_changed` 시그널로 차트 상태 전환. 배속 정보로 렌더 주기 결정. 상태 매핑: Game Clock `MARKET_OPEN` → Chart `LIVE`, `PAUSED` → `PAUSED`, `MARKET_CLOSED`/`DAY_TRANSITION` → `STATIC`, `PRE_MARKET` → `STATIC` (전일 차트), `WEEK_END` → `STATIC` (주말), `SEASON_END` → `STATIC` (시즌 종료) |

## Formulas

### F1. 이동평균선 (SMA)

```
SMA(n) = Σ(close_i for i in last_n_candles) / n
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `n` | int | 5, 20, 60 | MA 기간 |
| `close_i` | int | 1+ | i번째 캔들 종가 |

데이터 부족 시: 규칙 5-2의 지표별 최소 데이터 요건 참조.

### F2. RSI (Relative Strength Index)

```
avg_gain = SMA(gains, 14)
avg_loss = SMA(losses, 14)
RS = avg_gain / avg_loss
RSI = 100 - (100 / (1 + RS))
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `gains` | float[] | 0+ | 상승 캔들의 상승폭 |
| `losses` | float[] | 0+ | 하락 캔들의 하락폭 (절대값) |
| `RSI` | float | 0~100 | 과매수(70+) / 과매도(30-) |

**2단계 초기화**:
```
# Phase 1: 시드 값 (첫 14개 캔들)
avg_gain_14 = SMA(gains[0..13], 14)
avg_loss_14 = SMA(losses[0..13], 14)

# Phase 2: Wilder's smoothing (15번째 캔들부터)
for t in 14..N:
    gain_t = max(close_t - close_{t-1}, 0)
    loss_t = max(close_{t-1} - close_t, 0)
    avg_gain_t = (avg_gain_{t-1} × 13 + gain_t) / 14
    avg_loss_t = (avg_loss_{t-1} × 13 + loss_t) / 14

# 보합(close == prev_close) 처리: gain=0, loss=0 (양쪽 모두 0 기여)
```

### F3. MACD

```
EMA(n, price) = price × (2/(n+1)) + EMA_prev × (1 - 2/(n+1))

MACD_line = EMA(12, close) - EMA(26, close)
Signal_line = EMA(9, MACD_line)
Histogram = MACD_line - Signal_line
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `MACD_line` | float | 음수 가능 | 단기-장기 EMA 차이 |
| `Signal_line` | float | 음수 가능 | MACD의 9일 EMA |
| `Histogram` | float | 음수 가능 | 추세 강도 시각화 |

데이터 부족: EMA(26)에 최소 26개 캔들 필요. 그 전에는 MACD 미표시.
MACD Line은 26캔들부터 표시 가능. Signal Line(9-period EMA of MACD)은 34캔들(26+9-1)부터 표시 가능. 26~33캔들 구간에서는 MACD Line만 단독 표시하고, Signal Line과 Histogram은 빈 상태로 둔다.

### F4. 캔들 집계

```
candle_index = floor((current_tick - 1) / timeframe_ticks)
candle_start_tick = candle_index × timeframe_ticks + 1
candle_end_tick = candle_start_tick + timeframe_ticks - 1
```

**인덱싱 컨벤션**: 틱 번호는 1-indexed (첫 틱 = 1, Game Clock `current_tick` 기준).
캔들 배열은 0-indexed (첫 캔들 = index 0).

**예시**: 5분봉 (timeframe_ticks = 20), 현재 틱 47
- `candle_index = floor(46/20) = 2` (3번째 캔들, 0-indexed)
- `candle_start_tick = 2 × 20 + 1 = 41, candle_end_tick = 41 + 20 - 1 = 60`

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 시즌 첫 거래일 데이터 부족 | MA5/20은 최소 캔들 수 이상이면 점선으로 부분 표시, 정상 기간 이상이면 실선. MA60/RSI/MACD는 최소 요건 충족 전 미표시. 캔들은 첫 틱부터 표시. (상세: 규칙 5-2 참조) | 잘못된 지표보다 미표시가 낫다 |
| BREAKOUT으로 가격 급변 | Y축 스케일 자동 조정. 급변 캔들이 차트 밖으로 벗어나지 않음 | 정보 가시성 보장 |
| 타임프레임 변경 시 | 즉시 재집계. 과거 캔들은 캐시에서 로드 | 빠른 전환 |
| 거래량 0인 틱 | 거래량 바 높이 0. 캔들은 정상 표시 (OHLC 동일값 = 점) | MVP에서 거래량은 가격 엔진이 시뮬레이션 |
| 매우 좁은 가격 범위 (박스권) | Y축 최소 스케일 적용하여 캔들 형태 유지. 너무 납작해지지 않음 | 가독성 보호 |
| 매우 넓은 가격 범위 (급등+급락) | Y축 자동 스케일로 전체 범위 포함. 줌 인하면 상세 관찰 가능 | 전체 컨텍스트 제공 |
| 200개 이상 캔들 표시 시도 | max 200개로 제한. 스크롤로 과거 탐색 | 성능 보호 |
| 2x 이상 배속에서 차트 업데이트 | 2틱마다 1회 렌더 (2x, 4x 동일 스킵 비율 적용). 시각적 차이 없으나 성능 2배 | 고배속 최적화 |
| MA60 + 1D 타임프레임 | 시즌 전체(최대 20~30 거래일)에서 60개 일봉 불가능 → MA60 **영구 미표시**. MA60 토글 비활성화 + "시즌 내 데이터 부족" 안내. 1T/5T/15T에서는 시즌 초반 이후 정상 표시 | MA60은 1D에서 구조적으로 불가능한 지표 |
| PAUSED 상태에서 차트 인터랙션 | 차트 데이터 갱신 정지. 줌/스크롤/크로스헤어 **정상 작동**. 타임프레임 전환 가능. 재개 시 최신 틱부터 LIVE 렌더 재개 | PAUSED는 분석 시간이므로 차트 탐색 허용 |
| PRE_MARKET 상태에서 차트 인터랙션 | STATIC 모드 (전일 차트). 줌/스크롤/크로스헤어 **정상 작동**. 타임프레임 전환 가능. 장 시작 시 LIVE로 전환 | 프리마켓은 전일 데이터 분석 시간 |
| D1 타임프레임에서 캔들 수 ≤ 20 | zoom 조절 비활성화. 전체 캔들을 가용 너비에 맞춰 표시 (캔들당 최소 폭 제한 없음). default_visible_candles/max_visible_candles 무시 | 시즌 내 일봉은 최대 20개이므로 줌이 무의미. 가용 영역에 맞춰 자동 배치 |
| RSI 계산 시 avg_loss = 0 | RSI = 100으로 처리 (과매수 극단) | avg_loss가 0이면 분모가 0. 전통적 RSI 정의에서 RS = infinity → RSI = 100 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| 가격 엔진 | 차트가 의존 | 틱별 가격/거래량 데이터. **Hard** |
| 트레이딩 스크린 | 트레이딩 스크린이 차트를 호스팅 | 영역 배치, 종목 선택 전달. **Hard** |
| 스킬 트리 | 차트가 참조 | `is_skill_unlocked("A1"/"A2")` 해금 여부. **Soft** (미구현 시 기본 차트) |
| 게임 시계 | 차트가 의존 | 시장 상태, 배속 정보. **Hard** |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `default_visible_candles` | 60 | 20~120 | 넓은 시야. 추세 한눈에 | 상세한 캔들 관찰 |
| `max_visible_candles` | 200 | 100~300 | 더 긴 과거 조망 | 성능 보호 강화 |
| `max_tick_history` | 31200 | 15600~62400 | 1시즌(20거래일) 전체 조회 | 메모리 절약 |
| `candle_up_color` | 빨강 (#E74C3C) | — | — | — |
| `candle_down_color` | 파랑 (#3498DB) | — | — | — |
| `render_skip_at_speed` | 2 | 1~4 | 더 높은 배속부터 스킵 시작 (int. 2x에서도 매 틱 렌더 = 시각 품질 향상, 성능 부하 증가) | 더 낮은 배속부터 스킵 시작 (1x부터 스킵 = 성능 개선, 시각 품질 저하) |
| `y_axis_padding` | 5% | 2~10% | 여유 있는 차트 | 꽉 찬 차트 |
| `target_grid_lines` | 5 | 3~8 | 촘촘한 그리드 (정밀 가격 읽기) | 여유 있는 그리드 (깔끔한 화면) |
| `ma_periods` | [5, 20, 60] | 각 1~200 | 장기 추세 추적 | 단기 추세 추적 |
| `rsi_period` | 14 | 7~21 | 느린 반응 | 빠른 반응, 노이즈 증가 |

## Acceptance Criteria

| # | 기준 | 검증 방법 |
|---|------|----------|
| 1 | 1분/5분/15분/1일 타임프레임이 정확히 집계되어 표시됨 | 유닛 테스트: 집계 결과 OHLCV 검증 |
| 2 | 캔들 색상이 한국식 (상승=빨강, 하락=파랑)으로 정확히 표시됨 | 시각 검증 |
| 3 | 거래량 바 차트가 캔들과 동기화되어 표시됨 | 시각 검증 |
| 4 | A1 해금 시 MA5/20/60이 정확히 계산되어 오버레이됨 | 유닛 테스트: SMA 계산값 검증 |
| 5 | A2 해금 시 RSI/MACD가 정확히 계산되어 보조지표 영역에 표시됨 | 유닛 테스트: RSI/MACD 공식 검증 |
| 6 | 줌 인/아웃으로 표시 캔들 수를 20~200 범위에서 조정 가능 | 통합 테스트: 휠 입력 후 visible_count 확인 |
| 7 | 과거 스크롤 + "현재로 이동" 버튼이 정상 작동 | 통합 테스트 |
| 8 | 크로스헤어로 가격/시간을 정확히 표시 | 통합 테스트: 마우스 위치 대비 표시값 검증 |
| 9 | BREAKOUT 시 Y축 스케일이 자동 조정됨 | 통합 테스트: 급변 가격 입력 후 Y축 범위 확인 |
| 10 | Y축 그리드 라벨이 호가 단위의 배수에 정렬됨 (불가능한 가격이 표시되지 않음) | 유닛 테스트: nice_step 결과가 tick_size 배수인지 검증 |
| 11 | 가격대가 바뀌어 호가 단위가 변경되면 그리드 간격이 동적으로 조정됨 | 유닛 테스트: 가격대별 nice_step 변화 확인 |
| 12 | 데이터 부족 시 지표 미표시 + "데이터 부족" 안내 | 통합 테스트: 시즌 초반 캔들 수 미달 상황 |
| 13 | 성능: 60fps 유지 (1분봉 200캔들 + MA3개 + RSI 동시 표시 기준) | 성능 테스트: 프로파일러 프레임 타임 확인 |
| 14 | 성능: 타임프레임 전환 100ms 이내 | 성능 테스트: 전환 소요 시간 측정 |

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|------------|
| Godot 웹 export에서 캔들차트 렌더링 성능 검증 | engine-programmer | 프로토타입 | /prototype chart-renderer로 검증 |
| Canvas 2D vs Control 노드 기반 렌더링 결정 | technical-artist | 엔진 설정 후 | 성능 프로토타입 결과로 결정 |
| 다크 모드/라이트 모드 색상 테마 | art-director | Alpha | 미정 |
| 기업 재무제표(PER/PBR) A3 표시 위치 — 차트 내 vs 별도 패널 | ux-designer | V-Slice | 미정 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 기능 | 진입점 |
|------|--------|
| 캔들 데이터 갱신 | `GameClock.on_tick` 시그널 → `chart_renderer.gd._on_tick()` |
| 종목 선택 시 차트 교체 | `trading_screen.gd.stock_selected` 시그널 → `ChartRenderer.set_stock(stock_id)` |

### 호출 경로

- [x] `PriceEngine.get_price_history(stock_id) -> Array[int]` 존재
- [x] `SkillTree.is_skill_unlocked("A1")` — MA 표시 여부 확인
- [x] `SkillTree.is_skill_unlocked("A2")` — RSI 표시 여부 확인

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 | 상태 |
|----|------------|------------|------|
| 전체 AC (시각 검증) | 시각적 검증 필요 (E2E, S3-07) | — | ⬜ 단위 테스트 없음 |

### 빌드 검증

- [x] 바이너리 실행 확인: QA Lead 서명 — 내부 감사 2026-04-15 (Alpha 완료 빌드, SCRIPT ERROR 없음)
