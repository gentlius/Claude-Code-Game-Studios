## Prototype Report: Price Engine

### Hypothesis
3-layer 가격 생성 알고리즘(Markov pattern + mean reversion drift + event impact)이
"읽을 수 있지만 예측 불가능한" 차트 패턴을 생성하여, 플레이어가 패턴을 읽고 투자
판단을 내릴 수 있는가?

### Approach
Python으로 GDD의 모든 공식을 그대로 구현. 10개 종목 × 20거래일 × 390틱 = 78,000
데이터포인트 시뮬레이션. 5개 이벤트(INSTANT_SHOCK 3개, GRADUAL_SHIFT 2개) 포함.
5개 시드로 반복 테스트. matplotlib로 차트 시각화.

구현 파일:
- `price_engine_prototype.py` — 전체 시뮬레이션 엔진 (~400 LOC)
- `visualize.py` — 차트 생성 (~180 LOC)

### Result

**차트 가독성: PASS** — 마르코프 상태 기반 패턴 생성이 실제 주식 차트와 유사한
추세/횡보/급등락 패턴을 만든다. 10개 종목 모두 뚜렷한 "읽을 수 있는" 차트를 생성.
이벤트 충격이 차트에서 명확히 관찰됨(메디진 Day 10 급등 등).

**발견된 문제 3가지:**

#### 문제 1: 드리프트 레이어가 너무 약함 (CRITICAL)

`k_drift = 0.0003`은 패턴 레이어의 추세력 대비 지나치게 약하다.

- DOWNTREND bias = -0.0005/tick, magnitude = -0.0001~-0.0010
- deviation_ratio = 0.30 (soft threshold)에서 drift_force = 0.0003 × 0.30 × 1.0 = **0.00009/tick**
- 추세력(~0.0005~0.0015/tick) 대비 drift(0.00009/tick)는 약 5~17배 약함

결과: 대한중공업(LOW/BEAR) -66.7%, 코스모푸드(MEDIUM/NEUTRAL) maxDD 53.1%.
LOW 변동성 종목이 시즌 중 -66.7% 하락은 게임 밸런스상 과도함.

**제안**: `k_drift`를 0.001~0.003으로 약 3~10배 증가. 또는 threshold_soft를 0.15~0.20으로
하향하여 회귀가 더 빨리 시작되게 조정.

#### 문제 2: 변동성 프로필 차별화 부족 (MAJOR)

LOW 변동성(KB, DH) 평균 range = 80.7% vs HIGH/EXTREME 평균 range = 104.8%.
차이가 1.3배에 불과. GDD 예시에서 LOW는 ~50%, HIGH는 ~100%+ 범위를 예상했으나
실제로는 거의 비슷.

원인: 변동성 프로필 스케일링이 **전환 확률만** 조정하고, **틱당 변동 크기**는 동일.
LOW와 MEDIUM 모두 SIDEWAYS에서 ±0.0005 magnitude + 0.0004 noise 사용.

**제안 A**: STATE_PARAMS의 magnitude와 noise_std에 변동성 배율 적용.
`scaled_mag = base_mag × vol_magnitude_scale` (LOW=0.6, MED=1.0, HIGH=1.3, EXTREME=1.8)

**제안 B**: 또는 pattern_delta 전체에 변동성 배율 적용.
`pattern_delta = (bias + uniform + noise) × vol_scale`

#### 문제 3: Season Bias 효과가 불균형 (MINOR)

BEAR bias 종목(DH: -66.7%, MG: -9.0%)과 BULL bias 종목(KB: +59.6%, NE: +80.5%)의
격차가 크다. BEAR + LOW 조합이 특히 극단적. Season bias의 +0.05/-0.03 전환 확률
보정이 누적되면 20일간 강한 방향성을 만든다.

**제안**: Season bias 델타를 절반으로 줄이거나(up_bonus: +0.025, down_penalty: -0.015),
BEAR/BULL 배정 확률을 균등(33/34/33)으로 조정.

### Metrics

| Metric | Value | Assessment |
|--------|-------|------------|
| 10종목 독립 가격 갱신 | PASS | 10개 모두 독립 시계열 |
| 마르코프 전환 작동 | PASS | 2,868회 전환 (평균 27틱/전환) |
| 변동성별 차이 | **MARGINAL** | LOW avg 80.7% vs HIGH/EXT avg 104.8% (1.3x, 목표 2x+) |
| 하드클램프 | PASS | 모든 가격 범위 내 |
| 100원 반올림 | PASS | 100% 적용 |
| 이벤트 없이 작동 | PASS | Day 0-2 정상 가격 생성 |
| 이벤트 즉시 반영 | PASS | INSTANT_SHOCK 발생 틱에 반영 |
| BREAKOUT 거래량 | PASS | 3~5배 증가 관찰 |
| Multi-seed 일관성 | PASS | Range spread 93.5~103.0% (안정적) |
| 차트 가독성 (주관) | PASS | 추세/횡보/급변 패턴 명확히 관찰 |

#### Per-Stock Summary

| ID | Name | Vol | Bias | Base | Final | Return% | Range% | MaxDD% |
|----|------|-----|------|------|-------|---------|--------|--------|
| BF | 블루팜 | EXTREME | BULL | 320,000 | 511,000 | +59.7 | 126.0 | 38.5 |
| DH | 대한중공업 | LOW | BEAR | 95,000 | 31,600 | -66.7 | 69.4 | 69.4 |
| GC | 그린케미 | MEDIUM | NEUTRAL | 38,000 | 48,000 | +26.3 | 122.1 | 39.8 |
| KB | 코리아뱅크 | LOW | BULL | 52,000 | 83,000 | +59.6 | 92.1 | 38.2 |
| KF | 코스모푸드 | MEDIUM | NEUTRAL | 65,000 | 73,700 | +13.4 | 100.6 | 53.1 |
| MG | 메디진 | EXTREME | BEAR | 180,000 | 163,800 | -9.0 | 80.6 | 68.9 |
| NE | 넥스트엔터 | HIGH | BULL | 42,000 | 75,800 | +80.5 | 115.0 | 47.0 |
| PT | 피플텔레콤 | MEDIUM | BULL | 78,000 | 94,200 | +20.8 | 108.0 | 47.5 |
| SC | 스타칩 | HIGH | BULL | 120,000 | 176,700 | +47.2 | 112.0 | 52.9 |
| SK | 스카이로직 | HIGH | NEUTRAL | 210,000 | 201,800 | -3.9 | 90.5 | 48.4 |

### Recommendation: PROCEED

3-layer 아키텍처는 유효하다. 마르코프 상태 기반 패턴 생성이 "읽을 수 있지만
예측 불가능한" 차트의 핵심 요구사항을 충족. 이벤트 레이어도 정상 작동.
**다만 2가지 밸런스 이슈를 반드시 수정해야 한다.**

### If Proceeding

프로덕션 구현 전 GDD에서 수정해야 할 사항:

1. **k_drift 기본값 상향** — 0.0003 → 0.001 (3.3배 증가)
   - 또는 threshold_soft를 0.30 → 0.15로 하향
   - 프로토타입에서 재검증 필요 (수정 후 재시뮬레이션)

2. **변동성 프로필별 패턴 크기 스케일링 추가** — GDD에 새 규칙 필요
   ```
   vol_pattern_scale:
     LOW: 0.6
     MEDIUM: 1.0
     HIGH: 1.3
     EXTREME: 1.8
   pattern_delta = (bias + uniform + noise) × vol_pattern_scale
   ```

3. **Season bias 델타 축소** (선택적)
   - up_bonus: +0.05 → +0.03
   - down_penalty: -0.03 → -0.02

4. **Architecture requirements**:
   - GDScript Resource 기반 StockState (per-stock mutable data)
   - 전환 행렬은 precomputed Dictionary (10개 × 변동성 × 시즌 조합)
   - 이벤트 큐는 Array[GradualEvent] per stock
   - 틱 버퍼는 PackedFloat32Array (390 × 2 = price + volume)

5. **Performance target**: 10종목 × 1틱 < 1ms (GDD AC)
   - Python 프로토타입에서 78,000 데이터포인트를 <1초 처리 → GDScript에서 충분

### Lessons Learned

1. **드리프트 vs 패턴 밸런스가 핵심**: k_drift가 패턴 bias의 최소 1/3 이상이어야
   의미있는 회귀가 발생. 현재 0.0003 vs bias 0.0005~0.0030은 불균형.

2. **변동성 차별화는 전환 확률만으로는 부족**: 전환 확률 스케일링은 "어떤 상태에
   머무는지"를 바꾸지만, 각 상태 내의 변동 크기가 동일하면 체감 차이가 약함.
   magnitude 스케일링이 필수.

3. **Season bias는 20일간 누적 효과가 큼**: 5%p 전환 확률 보정이 7,800틱에 걸쳐
   누적되면 강한 방향성이 됨. 2~3%p로도 충분할 수 있음.

4. **100원 반올림은 저가주(38,000원)에서도 문제 없음**: 38,000원 기준 0.26%
   granularity. 틱당 변동이 이보다 크므로 정보 손실 미미.

5. **이벤트 없이도 차트가 의미있음**: 패턴+드리프트만으로 Day 0-2에서 정상 차트
   생성. 이벤트 시스템 개발 전에도 가격 엔진 단독 테스트 가능.
