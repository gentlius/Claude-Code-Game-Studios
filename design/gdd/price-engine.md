# 가격 엔진 (Price Engine)

> **Status**: Approved
> **Author**: user + game-designer
> **Last Updated**: 2026-03-31
> **Implements Pillar**: 판단이 곧 실력 (Judgment is King), 읽는 재미 (Read the Market)

## Overview

가격 엔진은 시드머니의 10개 가상 종목 가격을 실시간으로 생성하는 Core 시스템이다.
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
각 상태별 고정값이며, 변동성 프로필에 따라 스케일된다(1-3 규칙 참조).

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
    for j in others_indices:
        row[j] = row[j] / others_original_sum × non_self_non_breakout

    # 5. 자기 유지 확률 설정
    row[state_index] = adjusted_self

    # 검증: sum(row) == 1.0
```

EXTREME 프로필에서도 SIDEWAYS 상태는 유지한다. ×0.75 자기 유지 스케일로 인해
EXTREME 종목의 SIDEWAYS는 매우 짧아지며, BREAKOUT ×4.0으로 박스권에서 급등/급락이
빈번하게 발생하여 자연스럽게 "불안정한 박스권" 느낌을 연출한다.

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

##### 2-1. 평균 회귀 개요

패턴 레이어의 누적 결과로 가격이 `base_price`로부터 멀어질수록, 드리프트
레이어가 반대 방향으로 힘을 가한다. 이는 가격이 극단값으로 발산하는 것을
방지하고, 시즌 내 가격 범위를 플레이 가능한 수준으로 유지한다.

##### 2-2. 드리프트 공식

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

##### 2-3. 드리프트 강도 함수 (비선형)

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

##### 2-4. 최대 편차 하드 클램프

드리프트가 회귀 압력을 가하더라도 패턴+이벤트 레이어가 이를 상쇄할 경우를
대비하여, 절대적 상한/하한을 설정한다.

```
max_price = base_price × 3.0    (기준가 대비 최대 +200%)
min_price = max(base_price × 0.15, 1000)   (기준가 대비 최대 -85%, 단 최소 1,000원)
```

이 범위를 벗어나는 가격은 해당 경계값으로 강제 클램핑된다. 클램핑 발생 시
이벤트 레이어에 `PRICE_CLAMPED` 신호를 전송하여 내러티브 이벤트(거래 정지,
서킷 브레이커)로 활용 가능.

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

`max_single_impact` 기본값: **0.25 (25%)**. EXTREME 종목이 메가 이벤트를 받아도
단일 틱에서 최대 ±25% 변동으로 제한하여 플레이어 대응 시간을 보장한다.

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `base_impact` | float | 0.01~0.20 | 이벤트 시스템 | 기준 충격률. 소형 이벤트 1%, 메가 이벤트 20% |
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

##### 4-2. 상태별 거래량 승수

| State | volume_multiplier |
|-------|------------------|
| `STRONG_UP` | 1.5 |
| `UPTREND` | 1.2 |
| `SIDEWAYS` | 0.8 |
| `DOWNTREND` | 1.2 |
| `STRONG_DOWN` | 1.5 |
| `BREAKOUT_UP` | 3.0 ~ 5.0 (균등 샘플링) |
| `BREAKOUT_DOWN` | 3.0 ~ 5.0 (균등 샘플링) |

```
state_vol = base_vol × volume_multiplier
```

##### 4-3. 이벤트 거래량 스파이크

이벤트 발생 틱에 추가 거래량 스파이크를 적용한다.

```
if actual_impact == 0:
    event_spike = 0
else:
    spike_multiplier = clamp(|actual_impact| × 30.0, 1.0, 10.0)
    event_spike = base_vol × spike_multiplier
```

`actual_impact = 0.05` (5%) → `spike = 0.05 × 30 = 1.5배 추가`.
`actual_impact = 0.15` (15%) → `spike = 4.5배 추가`.

```
tick_volume = (state_vol + event_spike) × time_of_day_multiplier
```

GRADUAL_SHIFT 이벤트는 첫 틱에만 스파이크를 적용하고 이후 틱은
`state_vol`만 사용한다. 이는 "뉴스 직후 거래량 폭발 → 점차 안정" 패턴을
만든다.

##### 4-4. 장 시작/종료 거래량 보정

```
opening_multiplier = 2.5   (틱 0~9, 장 시작 10분)
closing_multiplier = 2.0   (틱 380~389, 장 마감 10분)
normal_multiplier  = 1.0   (틱 10~379)
```

시간대 승수는 규칙 4-3의 `tick_volume` 공식에서 최종 곱셈으로 적용된다:

```
tick_volume = (state_vol + event_spike) × time_of_day_multiplier
```

실제 주식시장의 "동시호가" 구간 거래량 집중을 모사.

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

clamped_price = clamp(raw_new_price, min_price, max_price)
             where min_price = max(base_price × 0.15, 1000)
                   max_price = base_price × 3.0

final_price = round(clamped_price / 100) × 100   # 100원 단위 반올림
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

```
base_vol = uniform(vol_min, vol_max)
state_vol = base_vol × state_multiplier
event_spike = 0 if actual_impact == 0
             else base_vol × clamp(|actual_impact| × 30.0, 1.0, 10.0)
tick_volume = (state_vol + event_spike) × time_of_day_multiplier
```

**Step 9 — 기록**

`{tick, price, volume, state}`를 종목별 시계열 버퍼에 추가한다. 차트 UI 및
지표 계산 시스템이 이 버퍼를 읽는다. 버퍼 크기: 1 거래일 = 390 레코드.
다음 거래일 시작 시 버퍼를 새로 시작하되, 전일 버퍼는 OHLCV(Open/High/Low/
Close/Volume) 요약만 보존한다.

### States and Transitions

#### 시스템 상태

가격 엔진 자체의 수명주기 상태. 마르코프 시장 상태(규칙 1)와는 별개.

| State | Description | Transition |
|-------|-------------|------------|
| **UNINITIALIZED** | 시즌 시작 전. 종목 데이터 미로드 | → READY (시즌 초기화 시) |
| **READY** | 종목별 초기 상태 설정 완료. 첫 틱 대기 | → RUNNING (MARKET_OPEN 진입 시) |
| **RUNNING** | 매 틱마다 10개 종목 가격 갱신 중 | → PAUSED (일시정지 시) / → END_OF_DAY (틱 389 처리 후) |
| **PAUSED** | 플레이어 일시정지. 틱 수신 중단 | → RUNNING (재개 시) |
| **END_OF_DAY** | 거래일 종료. OHLCV 요약 저장, 버퍼 리셋 | → READY (다음 거래일 PRE_MARKET 시) |
| **SEASON_END** | 시즌 종료. 최종 가격 확정 | → UNINITIALIZED (다음 시즌 대기) |

#### 게임 시계 상태 매핑

| 게임 시계 상태 | 가격 엔진 상태 | 전환 트리거 |
|--------------|-------------|------------|
| 시즌 시작 | UNINITIALIZED → READY | `on_season_start` 시그널 |
| PRE_MARKET | READY (대기) | `on_market_state_changed(PRE_MARKET, ...)` |
| MARKET_OPEN | RUNNING | `on_market_open` 시그널 |
| MARKET_OPEN (일시정지) | PAUSED | `on_market_state_changed(PAUSED, MARKET_OPEN)` |
| 일시정지 해제 | PAUSED → RUNNING | `on_market_state_changed(MARKET_OPEN, PAUSED)` |
| MARKET_CLOSE (틱 390) | END_OF_DAY | `on_market_close` 시그널 |
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

- 당일 시계열 버퍼에서 OHLCV 요약 생성 (Open/High/Low/Close/Volume)
- OHLCV 요약을 일봉 히스토리에 추가 (최대 20거래일 = 1시즌)
- 틱 버퍼는 다음 거래일 시작 시 새로 시작
- 마르코프 상태와 `current_state_duration`은 거래일을 넘겨 유지
- 진행 중인 GRADUAL_SHIFT 이벤트의 잔여 틱도 유지

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **게임 시계** | 가격 엔진이 의존 | `on_tick` 시그널 수신. `get_current_tick()` → 장 시작/종료 거래량 보정용 |
| **종목 DB** | 가격 엔진이 의존 | `get_stock(id)` → base_price, volatility_profile, sector_sensitivity, macro_sensitivity |
| **뉴스/이벤트** | 이벤트가 가격 엔진에 입력 | `push_event(Event)` → 이벤트 큐에 추가. 가격 엔진은 이벤트를 소비만 함 |
| **차트 렌더러** | 차트가 가격 엔진에 의존 | `get_tick_buffer(stock_id)` → 틱별 {price, volume} 시계열. `get_ohlcv_history(stock_id)` → 일봉 |
| **주문 처리 엔진** | 주문이 가격 엔진에 의존 | `get_current_price(stock_id)` → 체결가 결정용 |
| **트레이딩 스크린** | UI가 가격 엔진에 의존 | `on_price_updated` 시그널 → 실시간 가격 표시 |

## Formulas

### 공식 요약

Core Rules에서 정의한 공식을 변수 테이블과 함께 정리한다.

#### F1. 틱 변동률

```
total_delta_ratio = pattern_delta + drift_delta + event_delta
new_price = round(clamp(current_price × (1 + total_delta_ratio), min_price, max_price) / 100) × 100
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
base_vol = uniform(vol_min, vol_max)
state_vol = base_vol × state_multiplier
event_spike = 0 if actual_impact == 0
             else base_vol × clamp(|actual_impact| × 30.0, 1.0, 10.0)
tick_volume = (state_vol + event_spike) × time_of_day_multiplier
```

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
| `max_single_impact` | 0.25 | 0.10~0.50 | config | 단일 이벤트 최대 임팩트 클램프 |
| `base_impact` | — | 0.01~0.20 | 이벤트 시스템 | 이벤트 기준 충격률 |
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
| 이벤트 직후 (+10% INSTANT_SHOCK) | +18,000~+36,000 점프 | actual_impact = 0.10 × 2.0 = 20%. BREAKOUT_UP 강제 |
| 이벤트 후 3일 | 안정화 시작 | 강화된 드리프트 회귀 + BREAKOUT→UPTREND→SIDEWAYS 자연 전환 |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 가격이 하드클램프(min/max)에 도달 | 경계값으로 고정. `PRICE_CLAMPED` 신호 발송 | 서킷 브레이커 내러티브 활용 |
| 한 틱에 복수 이벤트 동시 발생 | event_delta 합산. 각각 독립 계산 후 가법 | 이벤트 순서 무관하게 결정론적 |
| INSTANT_SHOCK + GRADUAL_SHIFT 동시 | 둘 다 적용. INSTANT가 BREAKOUT 강제 전환 트리거 가능 | 실제 시장도 복합 이벤트 존재 |
| 100원 반올림으로 가격 변동 없음 (변동량 < 50원) | 가격 동결. 거래량은 정상 생성 | 저가주에서 발생 가능. 누적되면 다음 틱에서 반영 |
| 시즌 첫 틱 (모든 종목 SIDEWAYS) | 정상 작동. 전환 체크는 min_duration(40) 이후 | 시즌 시작은 평온하게 |
| base_price 극단값 (38,000 vs 320,000) | 동일 변동률(%) 적용. 절대 금액은 다르나 % 기준 동일 메카닉 | 가격 공정성 |
| deviation_ratio가 음수 (가격 < base_price) | drift_force 양수 → 상승 회귀 압력 | 대칭 회귀 설계 |
| BREAKOUT 상태에서 또 다른 대형 이벤트 | min_duration 리셋. BREAKOUT 연장 | 연쇄 급등/급락 허용 |
| 이벤트 없이 시즌 전체 진행 | 패턴+드리프트만으로 정상 가격 생성. 지표도 의미 유지 | 이벤트 시스템 미완성 시에도 독립 작동 |
| GRADUAL_SHIFT 진행 중 거래일 종료 | 잔여 틱 보존. 다음 거래일에 이어서 적용 | 이벤트 효과가 거래일 경계에서 소실되지 않음 |
| 10개 종목 모두 같은 MACRO 이벤트 수신 | 종목별 macro_sensitivity × volatility_amplifier로 차등 반영 | 동일 뉴스, 다른 반응 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| 게임 시계 | 가격 엔진이 의존 | `on_tick` 시그널로 구동. 틱 번호로 장 시작/종료 판별. **Hard** |
| 종목 DB | 가격 엔진이 의존 | base_price, volatility_profile, sector/macro_sensitivity 조회. **Hard** |
| 뉴스/이벤트 시스템 | 이벤트가 가격 엔진에 입력 | Event 오브젝트 수신. 없어도 패턴+드리프트로 작동. **Soft** |
| 차트 렌더러 | 차트가 가격 엔진에 의존 | 틱 버퍼, OHLCV 히스토리 읽기. **Hard** |
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
| `max_single_impact` | 0.25 (25%) | 0.10~0.50 | 단일 이벤트 변동 상한 완화 | 단일 이벤트 변동 제한 강화 |
| `BREAKOUT 강제 전환 임계값` | 0.05 (5%) | 0.03~0.10 | 큰 이벤트만 BREAKOUT 유발 | 작은 이벤트도 BREAKOUT |

## Acceptance Criteria

- [ ] 10개 종목이 매 틱마다 독립적으로 가격 갱신됨
- [ ] 마르코프 상태 전환이 전환 확률 행렬에 따라 정확히 작동함
- [ ] 변동성 프로필(LOW/MEDIUM/HIGH/EXTREME)별로 가격 변동폭이 유의미하게 차이남
- [ ] 드리프트 레이어가 soft/hard 임계값에서 비선형 회귀력을 정확히 적용함
- [ ] 가격이 하드클램프(base_price×0.15 ~ base_price×3.0)를 절대 벗어나지 않음
- [ ] 100원 단위 반올림이 모든 가격에 적용됨
- [ ] INSTANT_SHOCK 이벤트가 발생 틱에 즉시 가격에 반영됨
- [ ] GRADUAL_SHIFT 이벤트가 decay_ticks 동안 분배 적용됨
- [ ] |actual_impact| ≥ 5% 이벤트가 BREAKOUT 상태를 강제 전환함
- [ ] 거래량이 상태/이벤트/시간대별로 차등 생성됨
- [ ] BREAKOUT 상태에서 거래량이 3~5배 증가함
- [ ] 시즌 초기화 시 모든 종목이 SIDEWAYS, base_price로 리셋됨
- [ ] 이벤트 없이도 패턴+드리프트만으로 의미있는 차트가 생성됨
- [ ] 성능: 10개 종목 1틱 처리가 1ms 이내

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|------------|
| 오더북 레이어 설계 — AI/플레이어 주문량·주문 잔량이 가격에 반영되는 메커니즘 | game-designer | V-Slice | 향후. MVP는 가격 관찰자 모델 |
| 수수료가 체결가에 포함되는지, 별도 차감인지 | systems-designer | 주문 엔진 GDD 시 | 미정 |
| 이동평균선/볼린저밴드 등 지표 계산의 소유 시스템 (가격 엔진 vs 차트 렌더러) | lead-programmer | 차트 렌더러 GDD 시 | 미정 |
| PRICE_CLAMPED 발생 시 서킷 브레이커 연출 (거래 정지 N틱?) | game-designer | 뉴스/이벤트 GDD 시 | 미정 |
| 전일 종가 대비 등락률 제한(가격제한폭) 도입 여부 | game-designer | 프로토타입 후 | 미정 |
