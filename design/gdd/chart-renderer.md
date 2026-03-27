# 차트 렌더러 (Chart Renderer)

> **Status**: In Design
> **Author**: user + game-designer
> **Last Updated**: 2026-03-26
> **Implements Pillar**: 읽는 재미 (Read the Market), 판단이 곧 실력 (Judgment is King)

## Overview

차트 렌더러는 가격 엔진이 생성하는 가격/거래량 데이터를 캔들차트와 보조지표로
시각화하는 Presentation 시스템이다. 트레이딩 스크린의 중앙 영역을 차지하며,
플레이어가 시장을 "읽는" 핵심 인터페이스다.

스킬 트리의 분석 도구 레벨에 따라 표시 가능한 지표가 해금된다: Lv1(기본 캔들차트
+ 거래량), Lv2(이동평균선 5/20/60), Lv3(RSI, MACD). 4가지 타임프레임(1분, 5분,
15분, 1일)을 지원하며, 줌/스크롤/크로스헤어 인터랙션을 제공한다.

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

| 타임프레임 | 틱 수 | 1거래일(390틱) 내 캔들 수 | 용도 |
|-----------|-------|------------------------|------|
| 1분 (1T) | 1틱 | 390개 | 초단타 분석. 실시간 가격 추적 |
| 5분 (5T) | 5틱 | 78개 | 단기 패턴 분석 |
| 15분 (15T) | 15틱 | 26개 | 중기 추세 분석 |
| 1일 (1D) | 390틱 | 1개 | 장기 추세. 시즌 전체 조망 |

기본 타임프레임: **5분(5T)**. 플레이어가 탭으로 전환 가능.

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
│       보조지표 영역 (RSI/MACD)       │  ← 전체 높이의 20% (Lv3 해금 시)
└─────────────────────────────────────┘
│← 가격 눈금(Y축)                 시간 눈금(X축) →│
```

- Lv1~2: 보조지표 영역 없음. 캔들 70% + 거래량 30%
- Lv3: 보조지표 영역 등장. 캔들 65% + 거래량 15% + 보조지표 20%
- 위 비율은 **헤더 영역(종목명/현재가/타임프레임 탭, 약 48px) 아래**의 차트 본문에 적용

##### 2-2. Y축 자동 스케일 알고리즘

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

# Y좌표 변환
y_position(price) = chart_height × (1 - (price - padded_min) / (padded_max - padded_min))
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `scroll_offset` | int | 0+ | 사용자 입력 | 뷰포트 시작 캔들 인덱스 |
| `visible_count` | int | 20~200 | 줌 레벨 | 화면에 표시되는 캔들 수 |
| `min_y_range_ratio` | float | 0.01~0.05 | config | 최소 Y축 범위 비율 |
| `y_axis_padding` | float | 0.02~0.10 | config | Y축 상하 여백 비율 |

BREAKOUT 등 급변 시 `price_range`가 커지면서 자동으로 Y축이 확장된다.
스크롤 시 뷰포트 내 캔들만으로 재계산하므로 과거 탐색 시에도 적절한 스케일이 유지된다.

#### 규칙 3. 스킬별 오버레이

##### 3-1. 이동평균선 (Lv2 해금)

| MA | 기간 | 색상 | 용도 |
|----|------|------|------|
| MA5 | 5구간 | 노랑 | 초단기 추세 |
| MA20 | 20구간 | 주황 | 단기 추세 |
| MA60 | 60구간 | 보라 | 중기 추세 |

각 MA는 토글로 개별 표시/숨김 가능.

**골든크로스/데드크로스 표시**: MA5가 MA20을 상향 돌파 시 ▲ 마커,
하향 돌파 시 ▼ 마커 표시.

##### 3-2. RSI (Lv3 해금)

보조지표 영역 상단에 표시. 기간 14.

과매수 구간(70 이상): 빨강 배경 강조
과매도 구간(30 이하): 파랑 배경 강조

##### 3-3. MACD (Lv3 해금)

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
    tick_prices: RingBuffer<TickPrice>   # 최근 N틱 가격 (1분봉 원본)
    candles_5t: CandleData[]            # 5분봉 집계 캐시
    candles_15t: CandleData[]           # 15분봉 집계 캐시
    candles_1d: CandleData[]            # 일봉 집계 캐시
    max_tick_history: int = 1950        # 5거래일(1주) 분량
}
```

- 1분봉: `tick_prices` 링 버퍼가 곧 1T 캔들 (1틱 = 1캔들)
- 5분/15분봉: 1분봉에서 실시간 집계
- 일봉: 장 마감 시 확정. 시즌 전체 보존

**초기화**: 종목 선택 시(UNLOADED → LOADING) `get_tick_buffer(stock_id)`로 현재 시즌의
틱 히스토리를 일괄 로드하고, `get_ohlcv_history(stock_id)`로 과거 일봉을 로드한다.
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
| 배속별 렌더 스킵 | 2x 이상 배속 시 2틱마다 1회 렌더 (시각적 차이 무의미) |

### States and Transitions

| State | Description | Transition |
|-------|-------------|------------|
| **UNLOADED** | 종목 미선택. 빈 차트 | → LOADING (종목 선택 시) |
| **LOADING** | 히스토리 로드 중 | → LIVE (데이터 준비 완료) |
| **LIVE** | 실시간 갱신 중. 새 틱마다 캔들 업데이트 | → PAUSED (일시정지 시) / STATIC (장 마감 시) |
| **PAUSED** | 일시정지. 차트 고정. 스크롤/줌 가능 | → LIVE (재개 시) |
| **STATIC** | 장 마감. 차트 고정. 과거 탐색만 가능 | → LIVE (다음 장 시작 시) |

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **가격 엔진** | 차트가 의존 | `get_current_price(stock_id)` — 매 틱 현재가. `get_tick_buffer(stock_id)` — 틱별 `{price, volume}` 시계열. `get_ohlcv_history(stock_id)` — 일봉 OHLCV |
| **트레이딩 스크린** | 트레이딩 스크린이 차트를 호스팅 | 차트 영역 배치. 종목 선택 이벤트 전달 |
| **스킬 트리** | 차트가 참조 | `get_analysis_level()` — 오버레이 해금 여부 (Lv2=MA, Lv3=RSI/MACD) |
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

### F4. 캔들 집계

```
candle_index = floor((current_tick - 1) / timeframe_ticks)
candle_start_tick = candle_index × timeframe_ticks + 1
candle_end_tick = candle_start_tick + timeframe_ticks - 1
```

**인덱싱 컨벤션**: 틱 번호는 1-indexed (첫 틱 = 1, Game Clock `current_tick` 기준).
캔들 배열은 0-indexed (첫 캔들 = index 0).

**예시**: 5분봉, 현재 틱 47
- `candle_index = floor(46/5) = 9` (10번째 캔들, 0-indexed)
- `candle_start_tick = 46, candle_end_tick = 50`

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
| 배속 4x에서 차트 업데이트 | 2틱마다 1회 렌더. 시각적 차이 없으나 성능 2배 | 고배속 최적화 |
| MA60 + 1D 타임프레임 | 시즌 전체(최대 20~30 거래일)에서 60개 일봉 불가능 → MA60 **영구 미표시**. MA60 토글 비활성화 + "시즌 내 데이터 부족" 안내. 1T/5T/15T에서는 시즌 초반 이후 정상 표시 | MA60은 1D에서 구조적으로 불가능한 지표 |
| PAUSED 상태에서 차트 인터랙션 | 차트 데이터 갱신 정지. 줌/스크롤/크로스헤어 **정상 작동**. 타임프레임 전환 가능. 재개 시 최신 틱부터 LIVE 렌더 재개 | PAUSED는 분석 시간이므로 차트 탐색 허용 |
| PRE_MARKET 상태에서 차트 인터랙션 | STATIC 모드 (전일 차트). 줌/스크롤/크로스헤어 **정상 작동**. 타임프레임 전환 가능. 장 시작 시 LIVE로 전환 | 프리마켓은 전일 데이터 분석 시간 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| 가격 엔진 | 차트가 의존 | 틱별 가격/거래량 데이터. **Hard** |
| 트레이딩 스크린 | 트레이딩 스크린이 차트를 호스팅 | 영역 배치, 종목 선택 전달. **Hard** |
| 스킬 트리 | 차트가 참조 | 분석 도구 해금 레벨. **Soft** (미구현 시 Lv1 기본) |
| 게임 시계 | 차트가 의존 | 시장 상태, 배속 정보. **Hard** |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `default_visible_candles` | 60 | 20~120 | 넓은 시야. 추세 한눈에 | 상세한 캔들 관찰 |
| `max_visible_candles` | 200 | 100~300 | 더 긴 과거 조망 | 성능 보호 강화 |
| `max_tick_history` | 1950 | 780~3900 | 2주 과거까지 조회 | 메모리 절약 |
| `candle_up_color` | 빨강 (#E74C3C) | — | — | — |
| `candle_down_color` | 파랑 (#3498DB) | — | — | — |
| `render_skip_at_speed` | int, 2 | 1~4 | 더 높은 배속부터 스킵 시작 (2x에서도 매 틱 렌더 = 시각 품질 향상, 성능 부하 증가) | 더 낮은 배속부터 스킵 시작 (1x부터 스킵 = 성능 개선, 시각 품질 저하) |
| `y_axis_padding` | 5% | 2~10% | 여유 있는 차트 | 꽉 찬 차트 |
| `ma_periods` | [5, 20, 60] | 각 1~200 | 장기 추세 추적 | 단기 추세 추적 |
| `rsi_period` | 14 | 7~21 | 느린 반응 | 빠른 반응, 노이즈 증가 |

## Acceptance Criteria

- [ ] 1분/5분/15분/1일 타임프레임이 정확히 집계되어 표시됨
- [ ] 캔들 색상이 한국식 (상승=빨강, 하락=파랑)으로 정확히 표시됨
- [ ] 거래량 바 차트가 캔들과 동기화되어 표시됨
- [ ] Lv2 해금 시 MA5/20/60이 정확히 계산되어 오버레이됨
- [ ] Lv3 해금 시 RSI/MACD가 정확히 계산되어 보조지표 영역에 표시됨
- [ ] 줌 인/아웃으로 표시 캔들 수를 20~200 범위에서 조정 가능
- [ ] 과거 스크롤 + "현재로 이동" 버튼이 정상 작동
- [ ] 크로스헤어로 가격/시간을 정확히 표시
- [ ] BREAKOUT 시 Y축 스케일이 자동 조정됨
- [ ] 데이터 부족 시 지표 미표시 + "데이터 부족" 안내
- [ ] 성능: 60fps 유지 (1분봉 200캔들 + MA3개 + RSI 동시 표시 기준)
- [ ] 성능: 타임프레임 전환 100ms 이내

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|------------|
| Godot 웹 export에서 캔들차트 렌더링 성능 검증 | engine-programmer | 프로토타입 | /prototype chart-renderer로 검증 |
| Canvas 2D vs Control 노드 기반 렌더링 결정 | technical-artist | 엔진 설정 후 | 성능 프로토타입 결과로 결정 |
| 다크 모드/라이트 모드 색상 테마 | art-director | Alpha | 미정 |
| 기업 재무제표(PER/PBR) Lv4 표시 위치 — 차트 내 vs 별도 패널 | ux-designer | V-Slice | 미정 |
