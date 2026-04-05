# 가격 엔진 (Price Engine)

> **Status**: In Review
> **Author**: user + game-designer
> **Last Updated**: 2026-04-03
> **Implements Pillar**: 판단이 곧 실력 (Judgment is King), 읽는 재미 (Read the Market)

## Overview

가격 엔진은 시드머니의 46개 가상 종목 가격을 실시간으로 생성하는 Core 시스템이다.
게임 시계의 매 틱마다 `on_tick` 시그널을 수신하여 모든 종목의 현재가를 갱신한다.

가격 생성은 3개 레이어로 구성된다: (1) **패턴 레이어** — 실제 주식 차트에서
관찰되는 패턴(상승추세, 하락추세, 박스권, 급등/급락 등)을 조합하여 기본 가격
곡선을 생성한다. (2) **드리프트 레이어** — 종목의 기본가치(base_price)를 중심으로
장기 회귀 경향을 부여하여 가격이 극단으로 발산하는 것을 방지한다. (3) **이벤트
레이어** — 뉴스/이벤트 시스템에서 전달받은 시장 이벤트가 가격에 방향성 충격을
가한다. 플레이어는 차트 패턴을 읽고 뉴스를 분석하여 가격 방향을 예측할 수 있지만,
정확한 폭과 타이밍은 예측 불가능하다.

MVP에서 플레이어의 매매는 가격에 영향을 주지 않는다(가격 관찰자 모델). 향후
오더북 시뮬레이션 도입 시 가상 트레이더 볼륨과 플레이어 주문이 가격에 반영된다.

## Player Fantasy

시장은 살아있다. 차트를 보면 흐름이 읽힌다 — 상승 추세인지, 박스권인지, 뉴스
충격 후 반등 중인지. 하지만 100% 확신은 불가능하다. "여기서 사야 하나?" 하는
긴장감, "내가 읽은 게 맞았다!" 하는 유능감, "왜 갑자기 떨어지지?" 하는 당혹감 —
이 감정의 롤러코스터가 시장을 살아있게 만든다.

필라 "판단이 곧 실력"에 따라 가격은 읽는 사람에게 패턴을 보여주되, 읽지 않는
사람에게는 랜덤으로 느껴진다. 필라 "읽는 재미"에 따라 차트와 지표가 의미있는
정보를 전달해야 한다 — 이동평균선이 크로스하면 실제로 추세 전환 가능성이 높고,
뉴스 후 거래량 급증은 실제로 큰 변동의 신호다.

## Detailed Design

### Core Rules

#### 규칙 1. 패턴 레이어 — 마르코프 체인 상태 머신

##### 1-1. 시장 상태 정의

총 7개 상태를 정의한다. 각 상태는 틱별 방향 편향(bias), 변동 크기(magnitude),
노이즈 수준(noise)을 가진다. 여기서 수치는 **변동률(%)** 기준이며, 실제 가격
변동량 산출 시 현재 가격에 곱한다.

| State | 한글명 | Bias (% / tick) | Magnitude Range (% / tick) | Noise Std Dev (%) | 설명 |
|-------|--------|-----------------|---------------------------|-------------------|------|
| `STRONG_UP` | 강한 상승추세 | +0.15% | 0.05% ~ 0.30% | 0.08% | 가파른 상승. 이동평균이 우상향. |
| `UPTREND` | 완만한 상승추세 | +0.06% | 0.01% ~ 0.15% | 0.06% | 완만한 상승. 소폭 조정 섞임. |
| `SIDEWAYS` | 박스권 | 0.00% | -0.08% ~ +0.08% | 0.05% | 방향 없음. 지지/저항선 형성. |
| `DOWNTREND` | 완만한 하락추세 | -0.06% | -0.15% ~ -0.01% | 0.06% | 완만한 하락. 소폭 반등 섞임. |
| `STRONG_DOWN` | 강한 하락추세 | -0.15% | -0.30% ~ -0.05% | 0.08% | 가파른 하락. 이동평균이 우하향. |
| `BREAKOUT_UP` | 상방 돌파 | +0.35% | 0.20% ~ 0.60% | 0.12% | 단기 급등. 거래량 급증 동반. |
| `BREAKOUT_DOWN` | 하방 돌파 | -0.35% | -0.60% ~ -0.20% | 0.12% | 단기 급락. 거래량 급증 동반. |

**Bias**: 틱마다 가격 변동량의 기댓값 방향. **Magnitude Range**: 변동량이
균등분포로 샘플링되는 구간. **Noise Std Dev**: 정규분포 노이즈의 표준편차.
실제 틱 변동 = `bias + uniform(mag_min, mag_max) + normal(0, noise_std)`.

##### 1-2. 상태 지속 시간 (Duration)

각 상태는 최소 지속 틱 수(min_duration)를 가진다. 이 기간 동안 전환 체크를
건너뛴다. 이후 매 틱마다 전환 확률을 적용한다.

| State | min_duration (ticks) | self_prob | expected_duration (ticks) | 설명 |
|-------|---------------------|-----------|--------------------------|------|
| `STRONG_UP` | 20 | 0.980 | 20 + 50 = 70 | 차트에서 확인 가능한 추세 형성 |
| `UPTREND` | 30 | 0.985 | 30 + 67 = 97 | 이동평균선이 우상향 패턴 |
| `SIDEWAYS` | 40 | 0.975 | 40 + 40 = 80 | 지지/저항선 형성 |
| `DOWNTREND` | 30 | 0.985 | 30 + 67 = 97 | 이동평균선이 우하향 패턴 |
| `STRONG_DOWN` | 20 | 0.980 | 20 + 50 = 70 | 가파른 하락 추세 |
| `BREAKOUT_UP` | 5 | 0.500 | 5 + 2 = 7 | 단기. 이후 UPTREND 또는 SIDEWAYS로 전환 |
| `BREAKOUT_DOWN` | 5 | 0.500 | 5 + 2 = 7 | 단기. 이후 DOWNTREND 또는 SIDEWAYS로 전환 |

**expected_duration** = `min_duration + 1/(1 - self_prob)`. MEDIUM 기준.
변동성 프로필별 스케일링(1-4)으로 실제 지속 시간이 변한다.

`min_duration` 경과 후, 매 틱마다 **전환 체크**를 수행한다. 전환 체크 확률은
각 상태별 고정값이며, 변동성 프로필에 따라 스케일된다(1-4 규칙 참조).

##### 1-3. 기준 전환 확률 행렬 (MEDIUM 기준)

아래 행렬은 `volatility_profile = MEDIUM`인 종목의 기준 전환 확률이다.
행 = 현재 상태, 열 = 전환 대상 상태. 행의 합 = 1.0.
`min_duration` 경과 후 매 틱 체크 시 사용.

|  | STRONG_UP | UPTREND | SIDEWAYS | DOWNTREND | STRONG_DOWN | BREAKOUT_UP | BREAKOUT_DOWN |
|--|-----------|---------|----------|-----------|-------------|-------------|---------------|
| **STRONG_UP** | 0.980 | 0.010 | 0.003 | 0.001 | 0.000 | 0.005 | 0.001 |
| **UPTREND** | 0.005 | 0.985 | 0.005 | 0.001 | 0.000 | 0.003 | 0.001 |
| **SIDEWAYS** | 0.003 | 0.008 | 0.975 | 0.008 | 0.003 | 0.002 | 0.001 |
| **DOWNTREND** | 0.000 | 0.001 | 0.005 | 0.985 | 0.005 | 0.001 | 0.003 |
| **STRONG_DOWN** | 0.000 | 0.001 | 0.003 | 0.010 | 0.980 | 0.001 | 0.005 |
| **BREAKOUT_UP** | 0.075 | 0.250 | 0.125 | 0.040 | 0.000 | 0.500 | 0.010 |
| **BREAKOUT_DOWN** | 0.000 | 0.040 | 0.125 | 0.250 | 0.075 | 0.010 | 0.500 |

설계 의도: BREAKOUT 상태는 자기 유지 확률 50%(expected_duration ≈ 7틱)로
빠르게 소멸하며, 나머지 50%의 전환 확률 중 돌파 방향의 추세로 진입할 확률이
가장 높다(BREAKOUT_UP 기준: 전환 시 UPTREND 50%, STRONG_UP 15% — 이는 비자기유지
확률 0.500 내의 조건부 확률).
SIDEWAYS는 양방향으로 균형 있게 전환되어 "어디로 터질지 모르는" 박스권
긴장감을 만든다.

##### 1-4. 변동성 프로필별 전환 행렬 수정

기준 행렬(MEDIUM)을 변동성 프로필에 따라 수정한다. 수정 방식: 자기 유지
확률(대각선)을 조정하고, 나머지 확률을 비율 보정하여 행 합계 = 1.0을 유지한다.

| Profile | 자기 유지 확률 스케일 | BREAKOUT 전환 확률 스케일 | 효과 |
|---------|---------------------|--------------------------|------|
| `LOW` | ×1.15 (상태 유지 강화) | ×0.3 | 추세 전환이 느림. BREAKOUT 희귀. 방어주처럼 안정적. |
| `MEDIUM` | ×1.00 (기준) | ×1.0 | 기준값 그대로 사용. |
| `HIGH` | ×0.90 (전환 빠름) | ×2.0 | 추세 전환이 잦음. BREAKOUT 2배. 성장주/테마주처럼 변덕스러움. |
| `EXTREME` | ×0.75 (전환 매우 빠름) | ×4.0 | 극단적 전환. BREAKOUT 자주 발생. 바이오주처럼 예측 불가. |

**수정 알고리즘** (의사코드):

```
function adjust_row(row[], self_scale, breakout_scale):
    # 1. 자기 유지 확률 조정
    state_index = current_state_index
    adjusted_self = min(row[state_index] × self_scale, 0.98)

    # 2. 나머지 확률 총량 계산
    remaining = 1.0 - adjusted_self

    # 3. BREAKOUT 열 조정 (인덱스 5=BREAKOUT_UP, 6=BREAKOUT_DOWN)
    #    주의: state_index가 5 또는 6이면 해당 열은 이미 step 1에서
    #    self로 처리했으므로, 나머지 BREAKOUT 열만 조정한다.
    breakout_indices = [5, 6] - {state_index}  # self 제외
    breakout_original = sum(row[j] for j in breakout_indices)
    breakout_adjusted = min(breakout_original × breakout_scale, remaining × 0.5)
    if len(breakout_indices) == 2:
        breakout_ratio = row[5] / (row[5] + row[6])  # UP:DOWN 원래 비율 유지
        row[5] = breakout_adjusted × breakout_ratio
        row[6] = breakout_adjusted × (1 - breakout_ratio)
    elif len(breakout_indices) == 1:
        row[breakout_indices[0]] = breakout_adjusted  # 단일 BREAKOUT 열만

    # 4. 나머지 열 (non-self, non-breakout) 비율 보정
    non_self_non_breakout = remaining - breakout_adjusted
    others_indices = {j for j in range(7) if j != state_index and j not in [5,6]}
    others_original_sum = sum(row[j] for j in others_indices)
    # Step 5: Guard against zero division
    if others_original_sum == 0:
        # 모든 non-self, non-breakout 확률이 0인 극단 케이스
        # 균등 분배로 fallback
        for j in others_indices:
            row[j] = non_self_non_breakout / len(others_indices)
    else:
        for j in others_indices:
            row[j] = row[j] / others_original_sum × non_self_non_breakout

    # 5. 자기 유지 확률 설정
    row[state_index] = adjusted_self

    # 검증: sum(row) == 1.0
```

EXTREME 프로필에서도 SIDEWAYS 상태는 유지한다. ×0.75 자기 유지 스케일로 인해
EXTREME 종목의 SIDEWAYS는 매우 짧아지며, BREAKOUT ×4.0으로 박스권에서 급등/급락이
빈번하게 발생하여 자연스럽게 "불안정한 박스권" 느낌을 연출한다.

> **의도된 설계**: LOW 종목의 BREAKOUT은 더 오래 지속되고 (self_prob×1.15=0.575), EXTREME 종목의 BREAKOUT은 더 짧게 끝난다 (self_prob×0.75=0.375). 근거: LOW 종목은 평소 움직임이 적으므로 한번 BREAKOUT이 발생하면 관성이 크다. EXTREME 종목은 변동이 잦아 BREAKOUT 상태에서도 빠르게 다른 상태로 전환된다.

##### 1-5. 시즌 내 드리프트 편향 (장기 추세)

시즌 시작 시 각 종목에 `season_bias` 값을 무작위 배정한다. 이 값은 전환 행렬의
UPTREND/DOWNTREND 방향 확률을 미세 조정하여 종목이 시즌 내에서 전반적
상승장/하락장 특성을 가지게 한다.

| season_bias 값 | 효과 | 배정 확률 |
|----------------|------|-----------|
| `BULL` (+0.01 bias 가산) | UPTREND 방향 전환 확률 +1%, DOWNTREND -1% | 40% |
| `NEUTRAL` (0.00) | 기준 행렬 그대로 | 30% |
| `BEAR` (-0.01 bias 가산) | DOWNTREND 방향 전환 확률 +1%, UPTREND -1% | 30% |

BULL 40% / BEAR 30% 비대칭 배정 근거: 실제 주식시장은 장기적으로 우상향
경향이 있으며, 게임에서도 약간의 상승 편향이 초보 플레이어의 성공 경험을
만들어 이탈을 방지한다. 숙련 플레이어는 BEAR 종목을 공매도(향후 확장) 또는
회피하여 추가 알파를 얻는다. 프로토타입 후 밸런스 조정 가능.

이 편향은 매우 약하여 단기 차트에서는 식별 불가능하고, 시즌 전체 추이에서만
통계적으로 드러난다. "마켓 리딩" 숙련 플레이어가 발견할 수 있는 메타 레이어.

##### 1-6. 변동성 프로필별 패턴 크기 스케일링

변동성 프로필은 전환 확률(1-4)뿐 아니라 **틱당 변동 크기**에도 영향을 준다.
패턴 레이어의 최종 delta에 `vol_pattern_scale`을 곱하여, LOW 종목은 같은
상태에서도 더 작은 변동을, EXTREME 종목은 더 큰 변동을 보인다.

| Profile | vol_pattern_scale | 효과 |
|---------|------------------|------|
| `LOW` | 0.6 | 같은 UPTREND에서도 변동폭이 40% 감소. 방어주답게 안정적 |
| `MEDIUM` | 1.0 | 기준값 |
| `HIGH` | 1.3 | 변동폭 30% 증가. 성장주/테마주의 큰 진폭 |
| `EXTREME` | 1.8 | 변동폭 80% 증가. 바이오주의 극단적 변동 |

적용 공식:

```
pattern_delta = (bias + uniform(mag_min, mag_max) + normal(0, noise_std)) × vol_pattern_scale
```

전환 확률 스케일링(1-4)이 "어떤 상태에 머무는지"를 차별화한다면,
패턴 크기 스케일링(1-6)은 "같은 상태 내에서의 진폭"을 차별화한다.
두 메커니즘이 결합되어 LOW와 EXTREME의 차트가 체감적으로 뚜렷이 다르다.

> **프로토타입 검증 결과**: 전환 확률만 조정했을 때 LOW avg range 80.7% vs
> HIGH/EXTREME avg 104.8%로 차이가 1.3배에 불과했다. 패턴 크기 스케일링을
> 추가해야 변동성 프로필 간 2배+ 차이가 발생한다.
> (prototypes/price-engine/REPORT.md 참조)

---

#### 규칙 2. 드리프트 레이어 — 평균 회귀

##### 평균 회귀 개요

패턴 레이어의 누적 결과로 가격이 `base_price`로부터 멀어질수록, 드리프트
레이어가 반대 방향으로 힘을 가한다. 이는 가격이 극단값으로 발산하는 것을
방지하고, 시즌 내 가격 범위를 플레이 가능한 수준으로 유지한다.

##### 드리프트 공식

```
deviation_ratio = (current_price - base_price) / base_price

drift_force = -k_drift × deviation_ratio × drift_intensity(deviation_ratio)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `current_price` | int | 1,000+ | 가격 엔진 | 현재 가격 (원) |
| `base_price` | int | 1,000+ | 종목 DB | 시즌 시작 기준가 (원) |
| `deviation_ratio` | float | 이론상 무제한, 실질 -0.8~+2.0 | calculated | 기준가 대비 편차 비율 |
| `k_drift` | float | 0.0005~0.003 | config | 회귀 강도 계수 (기본 0.001) |
| `drift_force` | float | — | calculated | 이번 틱 드리프트 기여 변동률 |

##### 드리프트 강도 함수 (비선형)

편차가 클수록 드리프트 힘이 급격히 커지는 비선형 함수를 사용한다. 소폭
편차에서는 드리프트가 거의 느껴지지 않고, 극단적 편차에서만 강하게 작동한다.

```
drift_intensity(r) = 1.0                                                             if |r| < threshold_soft
                   = 1.0 + (|r| - threshold_soft) × 4.0                             if threshold_soft ≤ |r| < threshold_hard
                   = 1.0 + (threshold_hard - threshold_soft) × 4.0
                     + (|r| - threshold_hard) × 16.0                                 if |r| ≥ threshold_hard
```

| Parameter | Default Value | Description |
|-----------|--------------|-------------|
| `threshold_soft` | 0.20 (20% 편차) | 이 이내에서는 선형 드리프트만 적용 |
| `threshold_hard` | 0.50 (50% 편차) | 이 이상에서는 매우 강한 회귀력 |

모든 변동성 프로필에 동일한 임계값을 적용한다. EXTREME 종목이 30% 구간을
자주 방문하더라도, 드리프트는 부드럽게 작용하여 패턴 읽기가 가능하다.

**예시**: `k_drift = 0.001`, `deviation_ratio = 0.30` →
`intensity = 1 + (0.30-0.20)×4 = 1.4` → `drift_force = -0.001 × 0.30 × 1.4
= -0.00042` (틱당 -0.042% 회귀 압력). `deviation_ratio = 0.55` →
`intensity = 1 + (0.50-0.20)×4 + (0.55-0.50)×16 = 3.0` →
`drift_force = -0.001 × 0.55 × 3.0 = -0.00165` (틱당 -0.165% 회귀 압력).

> **프로토타입 검증 결과**: k_drift=0.0003 + threshold_soft=0.30에서는 추세력
> 대비 회귀가 5~17배 약하여 LOW 변동성 종목도 -66.7% 하락이 발생했다.
> k_drift=0.001 + threshold_soft=0.20으로 상향하여 회귀가 추세와 균형을 이루게
> 조정. (prototypes/price-engine/REPORT.md 참조)

##### 2-1. 최대 편차 하드 클램프

드리프트가 회귀 압력을 가하더라도 패턴+이벤트 레이어가 이를 상쇄할 경우를
대비하여, 절대적 상한/하한을 설정한다.

```
max_price = base_price × 3.0    (기준가 대비 최대 +200%)
min_price = max(base_price × 0.15, 1000)   (기준가 대비 최대 -85%, 단 최소 1,000원)
```

이 범위를 벗어나는 가격은 해당 경계값으로 강제 클램핑된다. 클램핑 발생 시
`on_price_clamped` 시그널을 발송한다.

##### 2-2. 일일 가격 제한 (상한가/하한가)

한국 주식시장의 일일 가격 제한 제도를 적용한다.

```
DAILY_LIMIT_PCT = 0.30  (±30%)
upper_limit = prev_day_close × (1 + DAILY_LIMIT_PCT)
lower_limit = prev_day_close × (1 - DAILY_LIMIT_PCT)
```

- **전일 종가(`prev_day_close`)**: 시즌 시작 시 `base_price`, 이후 매일 장 마감 시 당일 종가로 갱신
- 하드 클램프(규칙 2-1)보다 **더 촘촘하게** 적용됨
- 상한가/하한가 도달 시 `on_price_limit_hit(stock_id, is_upper, limit_price)` 시그널 발송
- 뉴스/이벤트 시스템이 해당 시그널을 수신하여 속보 뉴스 생성

##### 2-3. 시총가중 종합지수 (Market Index)

KOSPI 방식의 시가총액 가중 종합지수를 산출한다.

```
index = (현재 전 종목 총 시가총액 / 기준 시가총액) × 1000
시가총액 = current_price × listed_shares
```

- **기준값**: 시즌 시작 시 = 1000
- **갱신**: 매 틱, 전 종목 가격 갱신 후 재계산
- **전일 지수 종가**: 매일 장 마감 시 저장 → 서킷브레이커 기준
- SKL(스카이로직)이 최대 시총으로 지수에 가장 큰 영향

Public API:
- `get_current_price(stock_id) → int`: 현재 체결가 (주문 엔진이 호출)
- `get_tick_buffer(stock_id) → Array[{tick, price, volume, state}]`: 현재 시즌 전체 틱 히스토리 (차트 렌더러가 호출). 일봉/분봉은 차트 렌더러가 on-the-fly 계산
- `get_market_index() → float`: 현재 지수값
- `get_prev_day_index() → float`: 전일 지수 종가
- `get_index_change_pct() → float`: 전일 대비 등락률(%)
- `get_market_cap(stock_id) → int`: 개별 종목 시가총액
- `get_daily_limits(stock_id) → {upper, lower, prev_close}`: 상/하한가 조회
- `push_event(event: Event)`: 이벤트 큐에 추가 (뉴스/이벤트 시스템이 호출)

##### 2-4. VI (변동성완화장치, Volatility Interruption)

개별 종목의 가격이 전일 종가 대비 ±15% 이상 변동하면 해당 종목의 거래를 일시 정지한다.

> **현실 참고**: KRX 정적 VI는 ±10%이지만, 게임은 390틱/일로 시간이 극도로 압축되어
> 있고 BREAKOUT 상태 등 변동성이 현실보다 크다. 현실적 빈도(시즌 3~5회)를 달성하기
> 위해 임계값을 15%로 상향 조정한다. 현실 KRX에서도 VI는 개별 종목 기준 연 수회
> 수준의 드문 이벤트이다.

```
vi_threshold = 0.15  (±15%)
vi_halt_ticks = 8    (8틱 = 2분)
vi_max_per_day = 1   (종목당 일 1회 제한)
vi_cooldown_ticks = 20  (해제 후 20틱 재발동 방지)

change_pct = |current_price - prev_day_close| / prev_day_close

if change_pct >= vi_threshold
   and vi_count_today < vi_max_per_day
   and vi_cooldown_remaining == 0:
    trigger VI for this stock
    vi_count_today += 1
```

**VI 발동 중 동작**:
- 해당 종목의 가격 갱신 중단 (8틱 동안 가격 동결)
- 해당 종목의 주문 접수/체결 중단
- 다른 종목은 정상 거래
- `on_vi_triggered(stock_id, is_upper, halt_ticks)` 시그널 발신
- 뉴스/이벤트 시스템이 시그널 수신하여 VI 발동 뉴스 생성
- 8틱 후 자동 해제, `on_vi_released(stock_id)` 시그널 발신

**VI 해제 후**:
- 20틱 쿨다운 시작 (쿨다운 중 동일 종목 VI 재발동 불가)
- 가격 갱신 즉시 재개. 이벤트 큐에 쌓인 이벤트도 재개 시 처리
- 종목당 일 1회 제한이므로, 1회 발동 후 당일 추가 VI 없음
- 상/하한가(±30%)가 최종 안전장치

> **쿨다운 도입 이유**: VI 해제 직후 가격이 여전히 임계값 위에 있을 경우 즉시
> 재발동되는 문제 방지. 20틱(5분) 동안 시장이 자연스럽게 반응할 시간을 부여한다.

| Parameter | Value | Safe Range | Description |
|-----------|-------|------------|-------------|
| `VI_THRESHOLD` | 0.15 | 0.10~0.20 | VI 발동 기준 등락률 |
| `VI_HALT_TICKS` | 8 | 4~20 | 거래 정지 틱 수 |
| `VI_MAX_PER_DAY` | 1 | 1~3 | 종목당 일일 최대 VI 횟수 |
| `VI_COOLDOWN_TICKS` | 20 | 10~40 | VI 해제 후 재발동 방지 틱 수 |

##### 2-5. 서킷브레이커 (Circuit Breaker)

종합지수가 전일 종가 대비 급락하면 **전 종목** 거래를 중단한다. 2단계.

> **현실 참고**: KRX 서킷브레이커는 역사상 손에 꼽힐 정도로 드문 이벤트이다
> (2001, 2006, 2008, 2011, 2020 등). 게임에서도 시즌당 0~1회로, 발동 자체가
> 드라마틱한 시즌 이벤트여야 한다. Stage 1 임계값을 -12%로, Stage 2를 -20%로
> 상향하여 현실적 희소성을 반영한다.

```
index_change_pct = (current_index - prev_day_index) / prev_day_index

# Stage 1: 지수 -12%
if index_change_pct <= -0.12 and cb_stage < 1:
    cb_stage = 1
    halt all stocks for CB_STAGE1_TICKS (20 ticks = 5분)

# Stage 2: 지수 -20%
if index_change_pct <= -0.20 and cb_stage < 2:
    cb_stage = 2
    early close (남은 거래일 중단, 장 마감 처리)
```

**서킷브레이커 발동 중 동작**:
- Stage 1: 전 종목 가격 갱신 + 주문 체결 20틱 정지. 해제 후 정상 재개
- Stage 2: 즉시 장 마감 처리 (`_end_trading_day()` 호출). 금일 거래 종료
- `on_circuit_breaker(stage, halt_ticks)` 시그널 발신
- 뉴스/이벤트 시스템이 시그널 수신하여 서킷브레이커 뉴스 생성
- cb_stage는 일일 리셋 (다음 거래일 시작 시 0으로)

**Stage 1 해제 후**:
- 거래 재개. 지수가 다시 하락하여 -20% 도달 시 Stage 2 발동
- Stage 1 재발동은 없음 (하루 1회)

| Parameter | Value | Safe Range | Description |
|-----------|-------|------------|-------------|
| `CB_STAGE1_PCT` | -0.12 | -0.08~-0.15 | Stage 1 발동 기준 (지수 하락률) |
| `CB_STAGE2_PCT` | -0.20 | -0.15~-0.25 | Stage 2 발동 기준 (조기 마감) |
| `CB_STAGE1_TICKS` | 20 | 10~40 | Stage 1 정지 틱 수 |

> **상향 서킷브레이커**: 실제 KRX에도 상승 서킷브레이커는 없음. 게임에서도 하락만 적용.
> 개별 종목 상승 억제는 상한가(+30%) + VI(+10%)로 충분.

---

#### 규칙 3. 이벤트 레이어 — 뉴스 임팩트

##### 3-1. 이벤트 임팩트 유형

뉴스/이벤트 시스템에서 전달받는 이벤트는 두 가지 임팩트 방식을 가진다.

| Impact Type | 설명 | 적용 방식 |
|-------------|------|-----------|
| `INSTANT_SHOCK` | 즉각적 가격 충격. 발생 틱에 가격이 점프. | 해당 틱의 event_delta에 일괄 가산 |
| `GRADUAL_SHIFT` | 여러 틱에 걸쳐 서서히 영향. | `decay_ticks` 기간 동안 매 틱 분할 적용 |

##### 3-2. 이벤트 데이터 구조

뉴스/이벤트 시스템이 가격 엔진에 전달하는 이벤트 오브젝트:

```
Event {
    event_type: INSTANT_SHOCK | GRADUAL_SHIFT
    base_impact: float          # 기준 충격률 (예: +0.05 = +5%)
    direction: +1 | -1          # 호재(+1) 또는 악재(-1)
    scope: MACRO | SECTOR | INDIVIDUAL
    target_stocks: string[]     # 영향받는 종목 ID 목록
    decay_ticks: int            # GRADUAL_SHIFT에서 지속 틱 수 (0이면 INSTANT)
    decay_curve: LINEAR | EXPONENTIAL
}
```

##### 3-3. 종목별 실제 임팩트 계산

```
sensitivity = macro_sensitivity    if scope == MACRO
            = sector_sensitivity   if scope == SECTOR
            = 1.0                  if scope == INDIVIDUAL

raw_impact = base_impact × direction × sensitivity × volatility_amplifier
actual_impact = clamp(raw_impact, -max_single_impact, +max_single_impact)
```

`max_single_impact` 기본값: **0.15 (15%)**. EXTREME 종목이 메가 이벤트를 받아도
단일 틱에서 최대 ±15% 변동으로 제한한다. MEGA+EXTREME 조합에서만 VI 임계값(15%)에
도달 가능하며, LARGE 이하 등급은 단독으로 VI를 유발하지 않는다.

> **참고**: `max_single_impact`(0.15)는 event_delta만 클램프한다. `pattern_delta`는 별도이므로 `total_delta = event_delta + pattern_delta`가 15%를 초과할 수 있다. 이 경우 VI가 정상 발동하여 가격 안정화를 수행한다.

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `base_impact` | float | 0.005~0.10 | 이벤트 시스템 | 기준 충격률 (증폭 전). SMALL 0.5~1.5%, MEGA 6~10% |
| `sensitivity` | float | 0.0~2.0 | 종목 DB | 종목의 이벤트 유형별 감도 |
| `volatility_amplifier` | float | 아래 참조 | 종목 DB | 변동성 프로필별 이벤트 반응 배율 |
| `actual_impact` | float | — | calculated | 이 종목의 실제 임팩트 변동률 |

| volatility_profile | volatility_amplifier |
|--------------------|---------------------|
| `LOW` | 0.6 |
| `MEDIUM` | 1.0 |
| `HIGH` | 1.4 |
| `EXTREME` | 2.0 |

**예시**: 반도체 수출 규제 이벤트(MACRO, base_impact=0.06, direction=-1) →
스타칩(macro_sensitivity=1.2, MEDIUM) → `actual_impact = 0.06 × (-1) × 1.2 × 1.0
= -0.072` (즉시 -7.2%). 코리아뱅크(macro_sensitivity=1.5, LOW) → `0.06 × (-1) × 1.5
× 0.6 = -0.054` (-5.4%).

##### 3-4. INSTANT_SHOCK 적용

발생 틱의 `event_delta`에 `actual_impact`를 직접 가산한다. 한 틱에 복수 이벤트가
겹칠 수 있으므로 `event_delta`는 리스트로 누적 후 합산한다.

##### 3-5. GRADUAL_SHIFT 적용

`decay_ticks` 기간 동안 매 틱 `per_tick_impact`를 분배한다.

```
LINEAR     : per_tick_impact = actual_impact / decay_ticks
EXPONENTIAL: per_tick_impact_t = actual_impact × (1 - decay_rate)^t × decay_rate
             (where decay_rate = 1 - exp(ln(0.01) / decay_ticks))
```

EXPONENTIAL 방식은 초기에 강하고 후반으로 갈수록 약해진다. 뉴스 직후 급변
후 안정화되는 실제 시장 패턴을 모사한다. `decay_ticks` 내 합산은 `actual_impact`의
약 99%에 수렴한다. 잔여 ~1%는 의도적으로 생략하며, 충격의 자연적 감쇠를
표현한다(마지막 틱 보정 없음).

이벤트 종료(decay_ticks 소진) 후에도 패턴 레이어 상태는 이벤트로 이미
전환되었을 수 있으므로, 영향이 자연스럽게 이어진다.

##### 3-6. 이벤트에 의한 마르코프 상태 강제 전환

`INSTANT_SHOCK`의 `|actual_impact| ≥ 0.05` (5% 이상)이면 패턴 레이어의 현재
상태를 강제 전환한다.

```
actual_impact ≥ +0.05  →  BREAKOUT_UP 강제 전환 (min_duration 리셋)
actual_impact ≤ -0.05  →  BREAKOUT_DOWN 강제 전환 (min_duration 리셋)
```

이를 통해 큰 뉴스 이후 차트에서 BREAKOUT 패턴이 실제로 관찰된다.
플레이어가 "뉴스 → 차트 변화"를 인과로 읽을 수 있다.

---

#### 규칙 4. 거래량 생성

##### 4-1. 기준 거래량 (Base Volume)

| volatility_profile | base_volume_range (arbitrary units) | 설명 |
|--------------------|-------------------------------------|------|
| `LOW` | 100 ~ 300 | 안정적. 일정한 매매 |
| `MEDIUM` | 200 ~ 600 | 평균적인 활동량 |
| `HIGH` | 400 ~ 1200 | 활발한 매매 |
| `EXTREME` | 800 ~ 3000 | 매우 높은 변동성, 높은 기본 거래량 |

틱마다 `base_volume = uniform(vol_min, vol_max)` 로 샘플링.

##### 4-2. 틱 에너지 (Tick Energy) — 가격-거래량 상관관계

가격 변동의 입력 레이어들이 계산된 후, 각 레이어의 **절대값 합**을 "틱 에너지"로 정의한다.
이 값이 거래량의 핵심 승수가 된다.

```
tick_energy = |pattern_delta| + |event_delta|
```

> **설계 의도**: `total_delta = pattern + drift + event`는 방향이 상쇄될 수 있지만,
> `tick_energy`는 작용한 힘의 총량을 측정한다. 매수·매도 세력이 팽팽하게 충돌하면
> 가격은 안 움직여도 거래량은 폭발하는 실제 시장 패턴을 재현한다.
>
> - `pattern = +0.03`, `event = -0.025` → `total_delta = 0.005` (가격 거의 불변)
>   → `tick_energy = 0.055` (거래량 급증) — 세력 충돌
> - `pattern = +0.03`, `event = +0.02` → `total_delta = 0.05` (가격 급등)
>   → `tick_energy = 0.05` (거래량 급증) — 추세 확인
> - `pattern = +0.002`, `event = 0` → `total_delta = 0.002` (가격 미미)
>   → `tick_energy = 0.002` (거래량 적음) — 횡보

에너지를 거래량 승수로 변환:

```
energy_multiplier = 1.0 + clamp(tick_energy / ENERGY_THRESHOLD, 0.0, ENERGY_MAX_BOOST)
```

| Parameter | Value | 설명 |
|-----------|-------|------|
| `ENERGY_THRESHOLD` | 0.01 | 에너지가 이 값일 때 승수 +1.0 (2배). 정규화 기준 |
| `ENERGY_MAX_BOOST` | 4.0 | 최대 추가 승수. 최종 승수 상한 5.0× |

예시:
- `tick_energy = 0.005` → `0.005 / 0.01 = 0.5` → 승수 1.5×
- `tick_energy = 0.02` → `0.02 / 0.01 = 2.0` → 승수 3.0×
- `tick_energy = 0.06` → `0.06 / 0.01 = 6.0` → clamp → 승수 5.0× (상한)

##### 4-3. 상태별 거래량 기본 승수

마르코프 상태는 에너지와 별도로 기본 거래 활성도를 조절한다.

| State | state_multiplier | 설명 |
|-------|-----------------|------|
| `STRONG_UP` | 1.3 | 강한 추세 = 참여자 증가 |
| `UPTREND` | 1.1 | 완만한 추세 |
| `SIDEWAYS` | 0.7 | 관심 저하, 거래 감소 |
| `DOWNTREND` | 1.1 | 완만한 추세 |
| `STRONG_DOWN` | 1.3 | 강한 추세 = 참여자 증가 |
| `BREAKOUT_UP` | 2.0 | 돌파 = 활발한 매매 |
| `BREAKOUT_DOWN` | 2.0 | 돌파 = 활발한 매매 |

> **이전 대비 변경**: 상태 승수를 낮추고 에너지 승수가 주도하도록 함.
> BREAKOUT 상태는 에너지도 높으므로 `2.0 × 에너지승수`로 기존 3~5배와 유사한 결과.

##### 4-4. 상/하한가 근접 감쇠 (Limit Proximity Dampening)

가격이 상한가/하한가에 접근할수록 거래량이 감소한다. 실제 시장에서
가격제한폭 근처에 호가가 고갈되어 거래가 얇아지는 현상을 모사한다.

```
proximity_ratio = |current_price - prev_day_close| / (prev_day_close × DAILY_LIMIT_PCT)
```

- `proximity_ratio = 0.0` → 전일 종가 수준 (감쇠 없음)
- `proximity_ratio = 1.0` → 상한가 또는 하한가 도달

```
if proximity_ratio < LIMIT_DAMPEN_START:
    limit_dampen = 1.0                          # 감쇠 없음
else:
    t = (proximity_ratio - LIMIT_DAMPEN_START) / (1.0 - LIMIT_DAMPEN_START)
    limit_dampen = lerp(1.0, LIMIT_DAMPEN_MIN, t)
```

| Parameter | Value | 설명 |
|-----------|-------|------|
| `LIMIT_DAMPEN_START` | 0.7 | 감쇠 시작 지점 (상/하한가 70% 도달 시) |
| `LIMIT_DAMPEN_MIN` | 0.15 | 상/하한가 도달 시 최소 거래량 비율 (15%) |

예시 (하한가 -30% 기준):
- 등락률 -10% → `proximity = 0.33` → 감쇠 없음 (1.0×)
- 등락률 -21% → `proximity = 0.70` → 감쇠 시작 (1.0×)
- 등락률 -25% → `proximity = 0.83` → 감쇠 중 (~0.72×)
- 등락률 -30% → `proximity = 1.00` → 최소 거래량 (0.15×)

##### 4-5. 장 시작/종료 거래량 보정

```
opening_multiplier = 2.5   (틱 0~39, 장 시작 10분 = 40틱)
closing_multiplier = 2.0   (틱 1520~1559, 장 마감 10분 = 40틱)
normal_multiplier  = 1.0   (틱 40~1519)
```

> **주의**: 1거래일 = 1560틱 (4틱/분 × 390분). 틱 인덱스는 분 단위가 아닌
> 틱 단위로 지정한다.
> 슬롯 구조(규칙 2-1)의 390 구간 번호는 게임 분 단위이며, 여기서의 1,560틱은 절대 틱 인덱스다 (4틱/분 × 390분).

실제 주식시장의 "동시호가" 구간 거래량 집중을 모사.

##### 4-6. 최종 거래량 공식

모든 요소를 곱셈으로 결합:

```
tick_volume = base_vol × state_multiplier × energy_multiplier × limit_dampen × tod_multiplier
```

| 요소 | 역할 | 범위 |
|------|------|------|
| `base_vol` | 종목 고유 기본 거래량 | vol_profile별 랜덤 |
| `state_multiplier` | 마르코프 상태에 따른 기본 활성도 | 0.7 ~ 2.0 |
| `energy_multiplier` | 가격 변동 에너지에 비례하는 핵심 승수 | 1.0 ~ 5.0 |
| `limit_dampen` | 상/하한가 근접 시 호가 고갈 감쇠 | 0.15 ~ 1.0 |
| `tod_multiplier` | 장 시작/종료 시간대 보정 | 1.0 ~ 2.5 |

GRADUAL_SHIFT 이벤트는 첫 틱에만 event_delta가 크게 잡히므로
자연스럽게 "뉴스 직후 거래량 폭발 → 점차 안정" 패턴이 만들어진다.

---

#### 규칙 5. 틱별 가격 갱신 순서 (Per-Tick Update Sequence)

##### 5-1. 전체 처리 순서

게임 시계의 `on_tick` 시그널 수신 후, 각 종목에 대해 다음 순서로 처리한다.

```
Step 1. 이벤트 임팩트 수집
Step 2. 패턴 레이어 — 틱 변동량 계산
Step 3. 드리프트 레이어 — 회귀력 계산
Step 4. 이벤트 레이어 — 이벤트 임팩트 계산
Step 5. 레이어 합산 (가법 결합)
Step 6. 가격 갱신
Step 7. 마르코프 상태 전환 체크
Step 8. 거래량 계산
Step 9. 시장 데이터 스트림에 기록
```

##### 5-2. 각 단계 상세

**Step 1 — 이벤트 임팩트 수집**

이번 틱에 적용되어야 하는 모든 이벤트 임팩트를 이벤트 큐에서 수집한다.
- INSTANT_SHOCK: 이번 틱 발생 이벤트 전체
- GRADUAL_SHIFT: 현재 진행 중인 이벤트들의 이번 틱 분배분

**Step 2 — 패턴 레이어 계산**

```
raw_pattern = bias(current_state)
            + uniform(mag_min(current_state), mag_max(current_state))
            + normal(0, noise_std(current_state))
pattern_delta = raw_pattern × vol_pattern_scale(volatility_profile)
```

**Step 3 — 드리프트 레이어 계산**

```
deviation_ratio = (current_price - base_price) / base_price
drift_delta = -k_drift × deviation_ratio × drift_intensity(deviation_ratio)
```

**Step 4 — 이벤트 레이어 계산**

```
event_delta = sum(actual_impact_i for all events i in this tick)
```

이벤트에 의한 강제 전환(규칙 3-6)은 이 단계에서 수행된다. `|actual_impact| ≥ 0.05`
이면 BREAKOUT 상태로 강제 전환하고 `current_state_duration = 0`으로 리셋하며,
`forced_transition_this_tick = true` 플래그를 설정한다.

**Step 5 — 레이어 합산 (가법 결합)**

```
total_delta_ratio = pattern_delta + drift_delta + event_delta
```

세 레이어는 **가법(additive)**으로 결합한다. 이벤트가 없을 때 drift와 pattern만으로
가격이 결정되어야 하며, 이벤트 임팩트가 "추가적 충격"의 직관에 부합한다.

**Step 6 — 가격 갱신**

```
raw_new_price = current_price × (1 + total_delta_ratio)

# 1) 일일 가격 제한 클램프 (규칙 2-2, 상한가/하한가 ±30%)
upper_limit = prev_day_close × (1 + DAILY_LIMIT_PCT)   # DAILY_LIMIT_PCT = 0.30
lower_limit = prev_day_close × (1 - DAILY_LIMIT_PCT)
daily_clamped = clamp(raw_new_price, lower_limit, upper_limit)

# 2) 하드 클램프 (규칙 2-1, 기준가 대비 절대 범위)
clamped_price = clamp(daily_clamped, min_price, max_price)
             where min_price = max(base_price × 0.15, 1000)
                   max_price = base_price × 3.0

# 3) 호가 단위(tick size) 반올림 — KRX 규정 기반 (규칙 5-3 참조)
tick_size = get_tick_size(clamped_price)
final_price = round(clamped_price / tick_size) × tick_size
```

**Step 7 — 마르코프 상태 전환 체크**

```
if forced_transition_this_tick:
    forced_transition_this_tick = false
    # 강제 전환 완료. min_duration 이미 0으로 리셋됨. 전환 체크 건너뜀.
elif current_state_duration < min_duration(current_state):
    current_state_duration += 1
    # 전환 없음
else:
    roll = uniform(0.0, 1.0)
    next_state = sample_from_transition_matrix(current_state, volatility_profile, season_bias)
    if next_state != current_state:
        current_state = next_state
        current_state_duration = 0
    else:
        current_state_duration += 1
```

**Step 8 — 거래량 계산**

가격 계산에 사용된 중간 레이어 값을 재활용하여 거래량을 산출한다 (규칙 4-2~4-6).

```
# 1) 에너지: 가격 레이어 절대값 합 (상쇄 전 힘의 총량)
tick_energy = |pattern_delta| + |event_delta|
energy_multiplier = 1.0 + clamp(tick_energy / ENERGY_THRESHOLD, 0.0, ENERGY_MAX_BOOST)

# 2) 상한가 근접 감쇠
proximity_ratio = |current_price - prev_day_close| / (prev_day_close × DAILY_LIMIT_PCT)
if proximity_ratio < LIMIT_DAMPEN_START:
    limit_dampen = 1.0
else:
    t = (proximity_ratio - LIMIT_DAMPEN_START) / (1.0 - LIMIT_DAMPEN_START)
    limit_dampen = lerp(1.0, LIMIT_DAMPEN_MIN, t)

# 3) 최종 거래량
base_vol = uniform(vol_min, vol_max)
tick_volume = base_vol × state_multiplier × energy_multiplier × limit_dampen × tod_multiplier
```

##### 5-3. 호가 단위 (Tick Size) — KRX 기반

가격대별로 최소 가격 변동 단위가 달라진다. KRX 실제 규정을 게임용으로 단순화한 6단계.

| 가격 범위 | 호가 단위 (tick_size) | 예시 가격 → 반올림 결과 |
|-----------|---------------------|----------------------|
| ~ 1,000원 | 1원 | 987원 → 987원 |
| 1,000원 ~ 5,000원 | 5원 | 3,412원 → 3,410원 |
| 5,000원 ~ 10,000원 | 10원 | 7,865원 → 7,870원 |
| 10,000원 ~ 50,000원 | 50원 | 38,123원 → 38,100원 |
| 50,000원 ~ 100,000원 | 100원 | 65,432원 → 65,400원 |
| 100,000원 ~ 500,000원 | 500원 | 210,300원 → 210,500원 |
| 500,000원 ~ | 1,000원 | 523,400원 → 523,000원 |

```
get_tick_size(price: int) -> int:
    if price < 1000:    return 1
    if price < 5000:    return 5
    if price < 10000:   return 10
    if price < 50000:   return 50
    if price < 100000:  return 100
    if price < 500000:  return 500
    return 1000
```

> **현재 종목 가격대와 적용되는 호가 단위**:
> - 넥스트엔터(NXE) 42,000원 → 50원 단위
> - 코리아뱅크(KRB) 52,000원 → 100원 단위
> - 코스모푸드(KSF) 65,000원 → 100원 단위
> - 대한중공업(DHI) 95,000원 → 100원 단위
> - 스타칩(STC) 120,000원 → 500원 단위
> - 메디진(MDG) 180,000원 → 500원 단위
> - 스카이로직(SKL) 210,000원 → 500원 단위
> - 그린케미(GRC) 38,000원 → 50원 단위
> - 피플텔레콤(PLT) 78,000원 → 100원 단위
> - 블루팜(BPH) 320,000원 → 500원 단위
>
> **참고**: 가격 변동에 따라 호가 단위가 동적으로 변한다. 예를 들어 NXE(넥스트엔터)가 50,000원을
> 넘기면 호가 단위가 50원 → 100원으로 바뀐다.

**Step 9 — 기록**

`{tick, price, volume, state}`를 종목별 시계열 버퍼에 추가한다. 차트 UI 및
지표 계산 시스템이 이 버퍼를 읽는다. 버퍼는 **시즌 전체 틱을 누적 보존**한다
(1시즌 = 1,560틱/일 × 20거래일 = 31,200틱, ~500KB/종목, 46종목 합계 ~23MB).
OHLCV 별도 저장 없음 — 일봉/분봉은 차트 렌더러가 틱에서 on-the-fly 계산.
플레이어가 과거 거래일 차트를 1분봉/5분봉 단위로 스크롤할 수 있다.

### States and Transitions

#### 시스템 상태

가격 엔진 자체의 수명주기 상태. 마르코프 시장 상태(규칙 1)와는 별개.

| State | Description | Transition |
|-------|-------------|------------|
| **UNINITIALIZED** | 시즌 시작 전. 종목 데이터 미로드 | → READY (시즌 초기화 시) |
| **READY** | 종목별 초기 상태 설정 완료. 첫 틱 대기 | → RUNNING (MARKET_OPEN 진입 시) |
| **RUNNING** | 매 틱마다 46개 종목 가격 갱신 중 | → PAUSED (일시정지 시) / → END_OF_DAY (틱 1559 처리 후) |
| **PAUSED** | 플레이어 일시정지. 틱 수신 중단 | → RUNNING (재개 시) |
| **END_OF_DAY** | 거래일 종료. 틱 버퍼 유지 (누적) | → READY (다음 거래일 PRE_MARKET 시) |
| **SEASON_END** | 시즌 종료. 최종 가격 확정 | → UNINITIALIZED (다음 시즌 대기) |

#### 게임 시계 상태 매핑

| 게임 시계 상태 | 가격 엔진 상태 | 전환 트리거 |
|--------------|-------------|------------|
| 시즌 시작 | UNINITIALIZED → READY | `on_season_start` 시그널 |
| PRE_MARKET | READY (대기) | `on_market_state_changed(PRE_MARKET, ...)` |
| MARKET_OPEN | RUNNING | `on_market_open` 시그널 |
| MARKET_OPEN (일시정지) | PAUSED | `on_market_state_changed(PAUSED, MARKET_OPEN)` |
| 일시정지 해제 | PAUSED → RUNNING | `on_market_state_changed(MARKET_OPEN, PAUSED)` |
| MARKET_CLOSE (틱 1559 처리 후) | END_OF_DAY | `on_market_close` 시그널 |
| DAY_TRANSITION → PRE_MARKET | END_OF_DAY → READY | `on_market_state_changed(PRE_MARKET, DAY_TRANSITION)` |
| 시즌 종료 | SEASON_END → UNINITIALIZED | `on_season_end` 시그널 |

#### 시즌 초기화 (UNINITIALIZED → READY)

각 종목에 대해 다음을 수행한다:
- `current_price = base_price` (종목 DB의 시즌 시작 기준가)
- `current_state = SIDEWAYS` (시즌 시작은 중립)
- `current_state_duration = 0`
- `season_bias` 무작위 배정 (BULL 40% / NEUTRAL 30% / BEAR 30%)
- 시계열 버퍼 초기화
- 진행 중인 이벤트 큐 초기화

#### 거래일 종료 (RUNNING → END_OF_DAY)

- 틱 버퍼는 시즌 전체 누적 (폐기하지 않음). 다음 거래일 틱이 기존 버퍼에 이어서 추가됨
- OHLCV 별도 저장 없음 — 일봉은 차트 렌더러가 틱 데이터에서 on-the-fly 계산
- 마르코프 상태와 `current_state_duration`은 거래일을 넘겨 유지
- 진행 중인 GRADUAL_SHIFT 이벤트의 잔여 틱도 유지

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **게임 시계** | 가격 엔진이 의존 | `on_tick` 시그널 수신. `get_current_tick()` → 장 시작/종료 거래량 보정용 |
| **종목 DB** | 가격 엔진이 의존 | `get_stock(id)` → base_price, volatility_profile, sector_sensitivity, macro_sensitivity |
| **뉴스/이벤트** | 이벤트가 가격 엔진에 입력 | `push_event(Event)` → 이벤트 큐에 추가. 가격 엔진은 이벤트를 소비만 함 |
| **차트 렌더러** | 차트가 가격 엔진에 의존 | `get_tick_buffer(stock_id)` → 시즌 전체 틱 시계열. 일봉은 차트 렌더러가 틱에서 on-the-fly 계산 |
| **주문 처리 엔진** | 주문이 가격 엔진에 의존 | `get_current_price(stock_id)` → 체결가 결정용 |
| **트레이딩 스크린** | UI가 가격 엔진에 의존 | `on_price_updated` 시그널 → 실시간 가격 표시 |

## Formulas

### 공식 요약

Core Rules에서 정의한 공식을 변수 테이블과 함께 정리한다.

#### F1. 틱 변동률

```
total_delta_ratio = pattern_delta + drift_delta + event_delta
clamped = clamp(current_price × (1 + total_delta_ratio), min_price, max_price)
tick_size = get_tick_size(clamped)
new_price = round(clamped / tick_size) × tick_size
# 주의: 일일 가격 제한(±30%) 클램프가 하드 클램프보다 먼저 적용됨. 상세 순서는 규칙 5-2 Step 6 참조.
```

#### F2. 패턴 레이어

```
pattern_delta = (bias + uniform(mag_min, mag_max) + normal(0, noise_std)) × vol_pattern_scale
```

각 값은 현재 마르코프 상태에서 참조 (규칙 1-1 테이블).
`vol_pattern_scale`은 변동성 프로필별 크기 배율 (규칙 1-6 테이블).

#### F3. 드리프트 레이어

```
deviation_ratio = (current_price - base_price) / base_price
drift_delta = -k_drift × deviation_ratio × drift_intensity(deviation_ratio)

drift_intensity(r) = 1.0                                                                          if |r| < threshold_soft
                   = 1.0 + (|r| - threshold_soft) × 4.0                                              if threshold_soft ≤ |r| < threshold_hard
                   = 1.0 + (threshold_hard - threshold_soft) × 4.0 + (|r| - threshold_hard) × 16.0    if |r| ≥ threshold_hard
```

#### F4. 이벤트 레이어

```
raw_impact = base_impact × direction × sensitivity × volatility_amplifier
actual_impact = clamp(raw_impact, -max_single_impact, +max_single_impact)
event_delta = sum(actual_impact_i)  for all active events this tick
```

#### F5. 거래량

```
# 에너지 기반 거래량 (Rules 4-2 ~ 4-6 곱셈 모델)
base_vol = uniform(vol_min, vol_max)
tick_energy = |pattern_delta| + |event_delta|
energy_multiplier = 1.0 + clamp(tick_energy / ENERGY_THRESHOLD, 0.0, ENERGY_MAX_BOOST)
proximity_ratio = |current_price - prev_day_close| / (prev_day_close × DAILY_LIMIT_PCT)
limit_dampen = lerp(1.0, LIMIT_DAMPEN_MIN, t)  if proximity ≥ LIMIT_DAMPEN_START, else 1.0
tick_volume = base_vol × state_multiplier × energy_multiplier × limit_dampen × tod_multiplier
```

| 요소 | 역할 | 범위 |
|------|------|------|
| `ENERGY_THRESHOLD` | 에너지→승수 변환 기준 | config |
| `ENERGY_MAX_BOOST` | 에너지 승수 상한 | 4.0 |
| `LIMIT_DAMPEN_START` | 감쇠 시작 지점 | 0.7 |
| `LIMIT_DAMPEN_MIN` | 상/하한가 도달 시 최소 비율 | 0.15 |

#### F6. 가격 클램프

```
min_price = max(base_price × 0.15, 1000)
max_price = base_price × 3.0
```

### 변수 마스터 테이블

| Variable | Default | Range | Owner | Description |
|----------|---------|-------|-------|-------------|
| `k_drift` | 0.001 | 0.0005~0.003 | config | 평균 회귀 강도 계수 |
| `threshold_soft` | 0.20 | 0.10~0.40 | config | 드리프트 비선형 구간 시작 |
| `threshold_hard` | 0.50 | 0.30~0.70 | config | 드리프트 강한 회귀 구간 시작 |
| `vol_pattern_scale` | 0.6/1.0/1.3/1.8 | 0.3~2.5 | config | LOW/MED/HIGH/EXTREME 패턴 크기 배율 |
| `max_single_impact` | 0.15 | 0.10~0.25 | config | 단일 이벤트 최대 임팩트 클램프 |
| `base_impact` | — | 0.005~0.10 | 이벤트 시스템 | 이벤트 기준 충격률 (증폭 전) |
| `volatility_amplifier` | 0.6/1.0/1.4/2.0 | — | 종목 DB | LOW/MED/HIGH/EXTREME |
| `opening_multiplier` | 2.5 | 1.5~4.0 | config | 장 시작 거래량 보정 |
| `closing_multiplier` | 2.0 | 1.5~3.0 | config | 장 마감 거래량 보정 |

### 예시 시나리오 — 시즌 중 기대 가격 범위

MEDIUM 변동성(코스모푸드, base_price=65,000원) 기준, vol_pattern_scale=1.0,
이벤트 없는 순수 패턴+드리프트만 고려:

| 시점 | 예상 가격 범위 | 근거 |
|------|---------------|------|
| 1일차 (390틱) | 62,000 ~ 68,000 | SIDEWAYS 시작. ±0.08%/틱 × 390 ≈ 최대 ±5% |
| 5일차 (1,950틱) | 55,000 ~ 78,000 | 추세 전환 1~2회. UPTREND/DOWNTREND 진입 가능 |
| 10일차 (3,900틱) | 50,000 ~ 85,000 | STRONG 추세 경험 가능. 드리프트 20% 구간 도달 시 회귀 시작 |
| 20일차 (7,800틱) | 45,000 ~ 95,000 | 시즌 전체. 강화된 드리프트로 ±50% 이내 억제 |

LOW 변동성(코리아뱅크, base_price=52,000원) 기준, vol_pattern_scale=0.6:

| 시점 | 예상 가격 범위 | 근거 |
|------|---------------|------|
| 1일차 | 51,000 ~ 53,000 | SIDEWAYS × 0.6. 변동폭 미미 |
| 10일차 | 45,000 ~ 60,000 | 추세 변동폭도 0.6배. 안정적 |
| 20일차 | 40,000 ~ 65,000 | 시즌 전체 ±25% 이내. 방어주다운 안정성 |

HIGH 변동성(넥스트엔터, base_price=42,000원) 기준, vol_pattern_scale=1.3:

| 시점 | 예상 가격 범위 | 근거 |
|------|---------------|------|
| 1일차 | 39,000 ~ 45,000 | 전환 빈도 높아 혼합 상태. 1.3배 진폭 |
| 10일차 | 28,000 ~ 60,000 | BREAKOUT 2~3회. 큰 변동폭 |
| 20일차 | 22,000 ~ 75,000 | 드리프트 soft/hard 구간 반복 진입 |

EXTREME 변동성(메디진, base_price=180,000원) + 대형 이벤트 1회, vol_pattern_scale=1.8:

| 시점 | 예상 가격 범위 | 근거 |
|------|---------------|------|
| 이벤트 전 5일차 | 130,000 ~ 240,000 | BREAKOUT 빈번(×4.0). 1.8배 진폭 |
| 이벤트 직후 (+10% INSTANT_SHOCK) | +18,000~+36,000 점프 | raw = 0.10 × 2.0 = 0.20 → clamp(±0.15) = **15%**. BREAKOUT_UP 강제 |
| 이벤트 후 3일 | 안정화 시작 | 강화된 드리프트 회귀 + BREAKOUT→UPTREND→SIDEWAYS 자연 전환 |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 가격이 하드클램프(min/max)에 도달 | 경계값으로 고정. `on_price_clamped` 시그널 발송 | 내러티브 이벤트 트리거 |
| 가격이 상한가(+30%)에 도달 | upper_limit으로 고정. `on_price_limit_hit` 시그널 발송. 뉴스 생성 | 추가 상승 불가. 투자자에게 정보 제공 |
| 가격이 하한가(-30%)에 도달 | lower_limit으로 고정. `on_price_limit_hit` 시그널 발송. 뉴스 생성 | 추가 하락 불가. 투자자에게 정보 제공 |
| 한 틱에 복수 이벤트 동시 발생 | event_delta 합산. 각각 독립 계산 후 가법 | 이벤트 순서 무관하게 결정론적 |
| INSTANT_SHOCK + GRADUAL_SHIFT 동시 | 둘 다 적용. INSTANT가 BREAKOUT 강제 전환 트리거 가능 | 실제 시장도 복합 이벤트 존재 |
| 호가 단위 반올림으로 가격 변동 없음 (변동량 < tick_size/2) | 가격 동결. 거래량은 에너지 기반으로 정상 생성 (가격 불변이어도 힘이 작용했으면 거래량 발생) | 저가주(tick_size 작음)보다 고가주(tick_size 큼)에서 빈번. 누적되면 다음 틱에서 반영 |
| 가격 변동으로 호가 단위 경계 통과 (예: 49,950 → 50,100) | 호가 단위가 50원 → 100원으로 변경. 새 호가 단위로 반올림 적용 | 동적 호가 단위 전환. 자연스럽게 처리됨 |
| 매수·매도 세력 상쇄 (pattern +3%, event -2.5%) | 가격 변동 미미(+0.5%). 거래량은 에너지 기준(5.5%)으로 급증 | 세력 충돌 = 거래량 폭발 패턴 재현 |
| 상한가 도달 상태에서 추가 상승 압력 | 가격 고정. 에너지는 높지만 limit_dampen(0.15×)으로 거래량 급감 | 호가 고갈. 매도 물량 없음 |
| 가격이 전일 종가 근처 (proximity_ratio ≈ 0) | limit_dampen = 1.0. 거래량에 감쇠 없음 | 정상 거래 구간 |
| tick_energy가 0에 가까운 경우 (pattern·event 모두 미미) | energy_multiplier ≈ 1.0. base_vol × state_mult 수준의 최소 거래량 | 시장 조용할 때 자연스러운 저거래량 |
| VI 발동 중 이벤트 도착 | 이벤트 큐에 쌓임. VI 해제 틱에 일괄 처리 | 정지 중에도 뉴스는 쌓인다 |
| VI 1회 소진 후 ±15% 재도달 | VI 미발동. 가격 정상 변동 (상/하한가가 안전장치) | 종목당 일 1회 제한 |
| VI 해제 직후 가격이 여전히 ±15% 이상 | 쿨다운 20틱 동안 재발동 불가. 시장이 자연 반응할 시간 확보 | 즉시 재트리거 방지 |
| VI 중 GRADUAL_SHIFT remaining_ticks | remaining_ticks 카운트 계속 감소 (시간은 흐름). 가격 반영은 VI 해제 후 | decay는 시간 기반이므로 정지와 무관하게 진행 |
| 서킷브레이커 Stage 1 정지 중 개별 종목 VI | CB가 우선. CB 해제 후 VI 조건 재평가 | 중복 정지 방지 |
| 서킷브레이커 Stage 2 (조기 마감) 발동 | 즉시 _end_trading_day() 호출. 잔여 틱 무시. prev_day_close 갱신 | 다음 거래일 정상 시작 |
| 서킷브레이커 Stage 1 해제 후 지수 회복 | Stage 1 재발동 안 함. Stage 2만 추가 가능 | 하루 1회 Stage 1 |
| 시즌 첫 틱 (모든 종목 SIDEWAYS) | 정상 작동. 전환 체크는 min_duration(40) 이후. VI/CB 카운터 = 0 | 시즌 시작은 평온하게 |
| base_price 극단값 (38,000 vs 320,000) | 동일 변동률(%) 적용. 절대 금액은 다르나 % 기준 동일 메카닉 | 가격 공정성 |
| deviation_ratio가 음수 (가격 < base_price) | drift_force 양수 → 상승 회귀 압력 | 대칭 회귀 설계 |
| BREAKOUT 상태에서 또 다른 대형 이벤트 | min_duration 리셋. BREAKOUT 연장 | 연쇄 급등/급락 허용 |
| 이벤트 없이 시즌 전체 진행 | 패턴+드리프트만으로 정상 가격 생성. 지표도 의미 유지 | 이벤트 시스템 미완성 시에도 독립 작동 |
| MEGA+EXTREME+BREAKOUT 삼중 조합 시 단일 틱 VI 발동 | event_delta(15% clamped) + pattern_delta(BREAKOUT bias)로 total_delta > 15% 가능. 이 경우 해당 틱에서 VI 발동. 의도된 동작 — MEGA 이벤트와 BREAKOUT 상태의 극단적 조합에서만 발생 | 극히 드문 시나리오이지만 VI가 정상 작동하여 가격 안정화 |
| GRADUAL_SHIFT 진행 중 거래일 종료 | 잔여 틱 보존. 다음 거래일에 이어서 적용 | 이벤트 효과가 거래일 경계에서 소실되지 않음 |
| 46개 종목 모두 같은 MACRO 이벤트 수신 | 종목별 macro_sensitivity × volatility_amplifier로 차등 반영 | 동일 뉴스, 다른 반응 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| 게임 시계 | 가격 엔진이 의존 | `on_tick` 시그널로 구동. 틱 번호로 장 시작/종료 판별. **Hard** |
| 종목 DB | 가격 엔진이 의존 | base_price, volatility_profile, sector/macro_sensitivity 조회. **Hard** |
| 뉴스/이벤트 시스템 | 이벤트가 가격 엔진에 입력 | Event 오브젝트 수신. 없어도 패턴+드리프트로 작동. **Soft** |
| 차트 렌더러 | 차트가 가격 엔진에 의존 | `get_tick_buffer()` — 시즌 전체 틱 시계열 읽기. **Hard** |
| 주문 처리 엔진 | 주문이 가격 엔진에 의존 | `get_current_price()` 체결가 조회. **Hard** |
| 트레이딩 스크린 | UI가 가격 엔진에 의존 | `on_price_updated` 시그널 구독. **Soft** |
| AI 경쟁자 시스템 | 양방향 | MVP: AI가 가격 데이터 읽기만 함 (단방향, **Soft**). 향후: AI 매매 주문량 + 주문 잔량(매수/매도 대기) 비율이 가격에 영향 → 오더북 레이어 추가 시 **Hard** 양방향 의존. 가격 엔진이 AI 주문 풀을 입력으로 받아 수급 기반 가격 보정 |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `k_drift` | 0.001 | 0.0005~0.003 | 평균 회귀 강화. 가격이 base_price 근처에 머무름 | 회귀 약화. 극단 가격 빈번 |
| `threshold_soft` | 0.20 | 0.10~0.40 | 드리프트 비선형 구간 늦게 시작. 자유로운 변동 | 빠르게 비선형 회귀 진입 |
| `threshold_hard` | 0.50 | 0.30~0.70 | 강한 회귀 구간 늦게 시작 | 하드클램프에 가까운 빠른 회귀 |
| `vol_pattern_scale` | 0.6/1.0/1.3/1.8 | 0.3~2.5 | 상태 내 변동폭 증가. 차트 진폭 확대 | 상태 내 변동폭 감소. 차트 평탄화 |
| `MEDIUM 전환 행렬` | 규칙 1-3 참조 | — | 전환 빈도/패턴 직접 결정 | — |
| `volatility_amplifier` | 0.6/1.0/1.4/2.0 | 0.3~3.0 | 이벤트 반응 증폭 | 이벤트 반응 둔화 |
| `opening_multiplier` | 2.5 | 1.5~4.0 | 장 시작 거래량 집중 | 장 시작 평탄화 |
| `closing_multiplier` | 2.0 | 1.5~3.0 | 장 마감 거래량 집중 | 장 마감 평탄화 |
| `season_bias 배정 확률` | BULL 40/NEU 30/BEAR 30 | 각 10~60% | 상승장 종목 비율 변동 | — |
| `max_single_impact` | 0.15 (15%) | 0.10~0.25 | 단일 이벤트 변동 상한 완화 | 단일 이벤트 변동 제한 강화 |
| `BREAKOUT 강제 전환 임계값` | 0.05 (5%) | 0.03~0.10 | 큰 이벤트만 BREAKOUT 유발 | 작은 이벤트도 BREAKOUT |
| `DAILY_LIMIT_PCT` | 0.30 (±30%) | 0.15~0.50 | 일일 변동 허용폭 확대. 극단 이벤트 시 가격 반영 완전 | 변동 제한 강화. 상/하한가 빈번 발생 |
| `INDEX_BASE` | 1000.0 | 100~10000 | 지수 기준값 변경 (표시 단위만 영향). 서킷브레이커 임계값은 비율 기준이므로 영향 없음 | 동일 |
| `ENERGY_THRESHOLD` | 0.01 | 0.005~0.03 | 에너지→거래량 변환 둔감. 큰 변동만 거래량 증가 | 작은 변동에도 거래량 민감 반응 |
| `ENERGY_MAX_BOOST` | 4.0 | 2.0~8.0 | 에너지 기반 최대 거래량 배수 증가. 극단 거래량 허용 | 거래량 상한 제한. 균일한 거래량 |
| `LIMIT_DAMPEN_START` | 0.7 | 0.5~0.9 | 감쇠 시작 늦춤. 상/하한가 직전까지 거래 활발 | 일찍 감쇠 시작. 점진적 호가 고갈 |
| `LIMIT_DAMPEN_MIN` | 0.15 | 0.05~0.30 | 상/하한가에서도 거래 약간 유지 | 상/하한가 거래량 거의 0. 극단적 호가 고갈 |
| `VI_THRESHOLD` | 0.15 (±15%) | 0.10~0.20 | VI 발동 기준 완화. 덜 빈번한 정지 | VI 빈번. 잦은 거래 중단 |
| `VI_HALT_TICKS` | 8 | 4~20 | 긴 정지. 냉각 효과 강화 | 짧은 정지. 빠른 재개 |
| `VI_MAX_PER_DAY` | 1 | 1~3 | 더 많은 VI 허용 | — |
| `VI_COOLDOWN_TICKS` | 20 | 10~40 | 긴 쿨다운. 재발동 여유 확보 | 짧은 쿨다운. 빠른 재발동 가능 |
| `CB_STAGE1_PCT` | -0.12 | -0.08~-0.15 | 덜 민감한 CB. 큰 폭락만 반응 | 민감한 CB. 작은 하락에도 발동 |
| `CB_STAGE2_PCT` | -0.20 | -0.15~-0.25 | 조기 마감 기준 완화 | 조기 마감 빈번 |
| `CB_STAGE1_TICKS` | 20 | 10~40 | 긴 정지. 시장 안정화 | 짧은 정지 |

## Acceptance Criteria

- [ ] 46개 종목이 매 틱마다 독립적으로 가격 갱신됨
- [ ] 마르코프 상태 전환이 전환 확률 행렬에 따라 정확히 작동함
- [ ] 변동성 프로필(LOW/MEDIUM/HIGH/EXTREME)별로 가격 변동폭이 유의미하게 차이남
- [ ] 드리프트 레이어가 soft/hard 임계값에서 비선형 회귀력을 정확히 적용함
- [ ] 가격이 하드클램프(base_price×0.15 ~ base_price×3.0)를 절대 벗어나지 않음
- [ ] 가격대별 호가 단위(KRX 기반 7단계)에 맞는 반올림이 모든 가격에 적용됨
- [ ] 가격 변동으로 호가 단위 경계를 통과할 때 새 단위가 즉시 적용됨
- [ ] INSTANT_SHOCK 이벤트가 발생 틱에 즉시 가격에 반영됨
- [ ] GRADUAL_SHIFT 이벤트가 decay_ticks 동안 분배 적용됨
- [ ] |actual_impact| ≥ 5% 이벤트가 BREAKOUT 상태를 강제 전환함
- [ ] 거래량이 틱 에너지(|pattern_delta| + |event_delta|)와 양의 상관관계를 보임
- [ ] 가격 변동 없이 세력 상쇄된 틱에서도 에너지가 높으면 거래량이 증가함
- [ ] BREAKOUT 상태에서 state_mult(2.0) × energy_mult로 거래량이 유의미하게 증가함
- [ ] 상/하한가 근접(proximity ≥ 0.7) 시 거래량이 감쇠됨
- [ ] 상/하한가 도달(proximity = 1.0) 시 거래량이 기본의 15%로 감소함
- [ ] 시즌 초기화 시 모든 종목이 SIDEWAYS, base_price로 리셋됨
- [ ] 이벤트 없이도 패턴+드리프트만으로 의미있는 차트가 생성됨
- [ ] 성능: 46개 종목 1틱 처리가 4ms 이내
- [ ] 전일 종가 대비 ±30% 초과 가격이 절대 발생하지 않음
- [ ] 상한가/하한가 도달 시 `on_price_limit_hit` 시그널이 정확히 발생함
- [ ] 시가총액가중지수가 `(현재 총시총 / 기준 총시총) × 1000`으로 계산됨
- [ ] 지수가 매 틱마다 모든 종목 가격 갱신 후 업데이트됨
- [ ] `get_market_index()`, `get_index_change_pct()`, `get_market_cap()` API가 정확한 값을 반환함
- [ ] 시즌 초기화 시 기준 시가총액이 재계산되고 지수가 1000.0으로 리셋됨
- [ ] 장 마감 시 `prev_day_close`가 갱신되어 다음 날 상/하한가 기준이 됨
- [ ] 종목 가격이 전일 종가 ±15% 도달 시 VI 발동, 8틱 동안 해당 종목 가격 동결
- [ ] VI는 종목당 일 1회까지만 발동
- [ ] VI 해제 후 20틱 쿨다운 동안 동일 종목 재발동 불가
- [ ] VI 발동/해제 시 `on_vi_triggered` / `on_vi_released` 시그널 정상 발신
- [ ] 시즌(20일) 동안 총 VI 발생 횟수가 3~5회 수준 (현실적 희소성)
- [ ] 종합지수가 전일 대비 -12% 도달 시 서킷브레이커 Stage 1 발동, 20틱 전종목 정지
- [ ] 종합지수가 -20% 도달 시 Stage 2 발동, 즉시 장 마감 처리
- [ ] 서킷브레이커는 시즌당 0~1회 수준 (발동 자체가 드라마틱 이벤트)
- [ ] 서킷브레이커 발동 시 `on_circuit_breaker` 시그널 정상 발신

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|------------|
| 오더북 레이어 설계 — AI/플레이어 주문량·주문 잔량이 가격에 반영되는 메커니즘 | game-designer | V-Slice | 향후. MVP는 가격 관찰자 모델 |
| 슬리피지 모델 — 종목별 유동성 등급, 슬리피지 곡선 설계. 가격 관찰자 모델에서 피드백 모델로 전환 시 Price Engine + Order Engine 양쪽 수정 필요. 스킬 해금(TR3+) 연동 권고 | game-designer + systems-designer | Post-MVP | MVP=없음. 외부 감사 권고 (2026-04-03) |
| 수수료가 체결가에 포함되는지, 별도 차감인지 | systems-designer | 주문 엔진 GDD 시 | 미정 |
| 이동평균선/볼린저밴드 등 지표 계산의 소유 시스템 (가격 엔진 vs 차트 렌더러) | lead-programmer | 차트 렌더러 GDD 시 | 미정 |
| ~~PRICE_CLAMPED 발생 시 서킷 브레이커 연출~~ | — | **해결됨** | 상/하한가(±30%) + VI + 서킷브레이커로 구체화. 규칙 2-2 참조 |
| ~~VI(변동성완화장치) 발동 조건 및 거래 정지 시간~~ | — | **해결됨** | 규칙 2-4 참조. ±15% → 8틱 정지, 종목당 일 1회 |
| ~~서킷브레이커(시장 전체 거래 중단) 발동 조건~~ | — | **해결됨** | 규칙 2-5 참조. 지수 -12% → Stage 1 (20틱 정지), -20% → Stage 2 (조기 마감) |
| ~~전일 종가 대비 등락률 제한(가격제한폭) 도입 여부~~ | — | **해결됨** | ±30% 일일 가격제한폭 구현 완료. 규칙 2-2 참조 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 기능 | 진입점 |
|------|--------|
| 매 틱 가격 갱신 | `game_clock.gd._process_tick()` → `PriceEngine._on_tick(tick, day, week)` (직접 호출, 틱 순서 2번째) |
| 현재가 조회 | 각 시스템 → `PriceEngine.get_current_price(stock_id)` |
| VI/서킷브레이커 | 자동 — `_on_tick()` 내부에서 가격 변동 감지 후 발동 |

### 호출 경로

- [x] `PriceEngine.get_current_price(stock_id) -> int` 존재
- [x] `PriceEngine.get_tick_size(price) -> int` 존재 (KRX 호가 단위, ADR-002)
- [x] `PriceEngine.get_daily_limits(stock_id) -> Dictionary` 존재
- [x] `PriceEngine.get_market_index() -> float` 존재
- [x] `PriceEngine.on_vi_triggered(stock_id, is_upper, halt_ticks)` 시그널 존재
- [x] `PriceEngine.on_circuit_breaker(stage, halt_ticks)` 시그널 존재
- [x] `PriceEngine.reset_for_testing()` 존재

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 | 상태 |
|----|------------|------------|------|
| KRX 호가 단위 (ADR-002) | `tests/unit/test_price_engine.gd` | `test_tick_size_*` | ✅ |
| VI 발동 조건 | `tests/unit/test_vi_cb.gd` | `test_vi_triggers_at_15pct()` | ✅ |
| 서킷브레이커 Stage1 | `tests/unit/test_vi_cb.gd` | `test_circuit_breaker_stage1()` | ✅ |
| 일일 가격제한폭 ±30% | `tests/unit/test_price_engine.gd` | `test_daily_price_limit_clamped()` | ✅ |
| API 계약 | `tests/unit/test_api_contracts.gd` | `test_price_engine_api()` | ✅ |

### 빌드 검증

- [ ] 바이너리 실행 확인: QA Lead 서명 _______
