# ADR-026: 매크로 추세 레이어 (Macro Trend Layer)

**Status**: Active (v2 updated 2026-04-23)  
**Deciders**: technical-director, game-designer  
**Date**: 2026-04-23

---

## 문제

§1-7 아키타입 행렬은 분 단위(M1) 미시 Markov를 제어한다. 그러나 미시 Markov는
중심극한정리(central limit theorem)에 의해 자기평균화된다: 390분/일 × 20일/시즌의
수천 번 전환이 누적되면 주봉·월봉에서는 방향성 없이 박스 패턴만 형성된다.

관찰된 문제:
- 일봉/주봉: 아키타입 행렬 + seasonDrift 개선으로 어느 정도 방향성 생김
- 월봉: 여전히 박스 상하단만 치는 전략으로 수익 가능 (플레이어 착취 가능)

## 결정

**일봉 수준에서 작동하는 상위 Markov(3-state macro Markov)**를 도입한다.

### MacroState 정의

| 상태 | 값 | 역할 |
|------|----|------|
| `TREND_UP` | 0 | 미시 행렬의 상승 컬럼(STRONG_UP, UPTREND) 확률 증폭 |
| `FLAT` | 1 | 미시 행렬 무변경 (보합) |
| `TREND_DOWN` | 2 | 미시 행렬의 하락 컬럼(DOWNTREND, STRONG_DOWN) 확률 증폭 |

### 메커니즘

매 거래일 종료 시 (`_end_trading_day()` → `_roll_macro_states()`):

1. **SeasonBias 매크로 넛지** (v2 신규): 현재 시즌의 season_bias에 따라 macro_tm의 FLAT 행 조정
   - BULL: FLAT→TREND_UP +0.06, FLAT→TREND_DOWN -0.02 (재정규화)
   - BEAR: 역방향
   - 역할: "BULL 시즌에는 상승 추세 달이 더 자주 발생"
2. **MacroState 전환 롤**: 조정된 macro_tm으로 다음 날 MacroState 결정
3. **컬럼 바이어스 적용**: `_apply_macro_bias(matrix, macro_state)` — biasFactor=3.0으로 해당 컬럼 증폭 후 행 재정규화
4. **driftScale 적용** (v2 신규): TREND_UP/DOWN 기간 중 k_drift × 0.2 → 가격이 base_price로부터 최대 ~11% 이탈 가능 (기존 0.875%)
5. **거래량 배수**: `macro_vol_mult` 일별 1회 추출, 해당 일의 모든 M1 bar 거래량에 적용

## v1 대비 v2 변경 사항 (2026-04-23)

| 항목 | v1 | v2 | 근거 |
|------|----|----|------|
| self-prob (기본) | 0.92~0.93 (avg 12.5~14.3일) | 0.96 (avg 25일) | 월봉 지배 확률 ~80% 확보 |
| GROWTH UP self-prob | 0.94 (avg 16.7일) | 0.97 (avg 33일) | 구조적 상승 강화 |
| VALUE_DIVIDEND FLAT self-prob | 0.95 (avg 20일) | 0.97 (avg 33일) | 좁은 박스 강화 |
| DECLINING_TRAP DOWN self-prob | 0.95 (avg 20일) | 0.97 (avg 33일) | 하락 함정 강화 |
| driftScale | 없음 (k_drift=1.0 고정) | [0.2, 1.0, 0.2] | 추세 기간 가격 이탈 허용 |
| SeasonBias | 7×7 미시 행렬 additive 넛지 | 3×3 macro_tm FLAT 행 넛지 | 7×7 적용 시 수학적 상한 0.375% — 무효 |
| CACHE_VERSION | 5 | 6 | 알고리즘 변경으로 캐시 무효화 |

## driftScale 근거 (수식)

평균회귀 평형점 = `net_bias_per_tick / k_drift_effective`

- v1: `k_drift=0.001`, `net_bias ≈ 0.000875/tick` → 평형 ≈ **0.875%** (월봉 무시 수준)
- v2: TREND_UP 시 `k_drift_eff = 0.001 × 0.2 = 0.0002` → 평형 ≈ **4.375%**
  소프트 임계(20%) 이상에서 비선형 강화 감안하면 실효 가격 이동 ≈ **11%**

## SeasonBias 메커니즘 변경 근거

7×7 미시 행렬에 additive nudge(+0.002) 적용 시:
- 평형점 변화량 = `nudge / k_drift = 0.002 / 0.001 = 2배` (이론)
- 실제 제약: 행렬 행의 나머지 확률 재분배 한계 → 최대 ~0.375% 평형 이동
- 월봉(20일 × 390분 = 7800분 집계)에서 무의미

3×3 macro_tm FLAT 행 넛지:
- FLAT→TREND_UP 확률 0.02→0.08 (4배)
- BULL 시즌에 "어떤 달이 상승 달인가" 직접 제어
- 역할 분리: SeasonBias=추세 달 빈도, MacroState=추세 강도

## 구현 위치

| 컴포넌트 | 파일 | 역할 |
|----------|------|------|
| C++ 생성 | `gdextension/src/markov_generator.cpp` | `_macro_drift_scale[]`, `_apply_macro_bias()`, drift 공식 |
| C++ 헤더 | `gdextension/src/markov_generator.h` | `DEFAULT_MACRO_DS[3]`, `_macro_drift_scale[3]` |
| GDScript 런타임 | `src/gameplay/price_engine.gd` | `_roll_macro_states()`, `_compute_drift_delta(macro_state)` |
| 설정 | `assets/data/price_engine_config.json` v5 | `macroTrend.driftScale`, `seasonBiasMacroNudge`, self-probs |
| 캐시 | `src/gameplay/m1_cache_manager.gd` | `CACHE_VERSION=6`, `append_season_d1()` |

## 결과 (예상)

- 월봉: 단일 MacroState가 한 달을 지배 → 상승/하락/보합 중 하나가 명확히 나타남
- 종목 간 차별화: GROWTH 종목은 월봉에서 주로 상승, DECLINING_TRAP은 주로 하락
- BULL/BEAR 시즌: SeasonBias 넛지로 상승/하락 달 빈도가 실제로 달라짐
- 박스 전략 착취 어려워짐: 상승 추세 월에는 박스 하단 매수 → 상단 매도가 통하지 않음
