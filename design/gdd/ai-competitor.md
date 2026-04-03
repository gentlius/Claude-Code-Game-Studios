# AI Competitor System

*Created: 2026-04-03*
*Status: Approved*
*Sprint: S2-01*

---

## 1. Overview

AI Competitor 시스템은 시즌 내 19,999명의 AI 참가자를 효율적으로 관리하고,
각 참가자의 시즌 수익률(`return_pct`)을 통계적으로 생성·갱신하여 SeasonManager에
제공하는 시스템이다. 실제 주문 체결이나 포트폴리오 시뮬레이션 없이, 각 티어에
설정된 수익률 분포(정규분포 기반)와 결정론적 시드(participant_id × season_seed)를
조합하여 시뮬레이션 부하를 최소화한다. 티어가 높을수록 최종 수익률 분포의 평균과
하한이 높아지도록 설계하여, 글로벌 리더보드에서 고티어 AI가 저티어 AI보다 일관되게
높은 순위를 점하는 공정한 경쟁 환경을 보장한다. 매 틱 갱신되는 티어 내 순위와
일 1회 갱신되는 글로벌 순위 모두 이 시스템이 제공하는 수익률 값에 의존한다.

---

## 2. Player Fantasy

플레이어는 2만 명 중 자신이 어디에 위치하는지 항상 의식한다. 티어 내 순위판에는
자신과 비슷한 수준의 경쟁자들이 좁은 격차로 붙어 있고, 조금만 잘 해도 순위가
올라가고 조금만 방심해도 밀려난다는 긴장감이 지속된다.

글로벌 순위를 보면 다이아·마스터 구간 AI가 이미 높은 수익률을 올리고 있어
"저 위에 가려면 얼마나 더 잘해야 하는가"라는 동경과 압박이 동시에 온다.
반대로 브론즈 하위권에서 살짝 상위 50%에 진입했을 때의 "이제 평균은 넘었다"는
소소한 성취감도 시스템이 만들어내는 감정이다.

AI 경쟁자들은 실제 인간처럼 느껴져야 하지만 플레이어가 불가능한 수익률을 내거나
모든 AI가 동일한 곡선을 그리는 기계적 패턴이 드러나서는 안 된다. 각 AI는 같은
티어 안에서도 저마다 다른 궤적을 그리며, 어떤 AI는 초반에 치고 나갔다가 후반에
무너지고, 어떤 AI는 꾸준히 상위권을 유지한다.

MDA 목표 Aesthetics: **Challenge** (경쟁 압박), **Fantasy** (2만 명 리그 참가라는 스케일감).

---

## 3. Detailed Design

### 3-1. 설계 원칙

1. **통계적 시뮬레이션**: AI는 실제 매매를 실행하지 않는다. 수익률은 수식에 따라
   직접 생성된다. PriceEngine, OrderEngine, PortfolioManager와 무관하다.

2. **결정론적 재현성**: 동일한 `season_seed`와 `participant_id`에서는 항상 동일한
   수익률 궤적이 생성된다. 이를 통해 버그 재현과 밸런스 검증이 가능하다.

3. **티어 단조성 (Tier Monotonicity)**: 티어 T+1의 AI 수익률 분포 평균은 항상
   티어 T보다 높다. 고티어 AI가 글로벌 순위 상단을 점하는 것이 보장된다.

4. **플레이어 가시성**: SeasonManager가 요청하는 세 가지 인터페이스만 공개한다.
   내부 생성 방식은 완전히 캡슐화된다.

5. **성능 우선**: 전체 19,999명의 수익률을 매 틱 재계산하지 않는다. 플레이어 소속
   티어만 매 틱 갱신하고, 나머지 티어는 일 1회 글로벌 갱신 시에만 계산한다.

### 3-2. 메모리 모델

```
AiCompetitor 내부 상태 (티어 단위로 관리):
  - tier_data[tier]: Dictionary
      - seed_base: int          # tier × season_seed
      - count: int              # 해당 티어 AI 인원수
      - daily_snapshots[day]: Array[float]   # 일별 수익률 스냅샷 (일 1회 갱신)
      - intra_day_progress: float  # 0.0~1.0, 현재 거래일 진행률

  - player_tier: int            # 플레이어 현재 티어 (init_season 시 설정)
  - current_day: int            # 현재 시즌 일수 (0~19)
  - current_tick: int           # 당일 틱 번호 (0~1559)
  - season_seed: int            # 이 시즌의 글로벌 랜덤 시드
```

`daily_snapshots`는 지연 계산(lazy evaluation)으로, 해당 일의 글로벌 갱신 시점에만
생성된다. 시즌 시작 시에는 빈 배열로 초기화된다.

### 3-3. 수익률 생성 파이프라인

AI 수익률 생성은 세 단계 파이프라인으로 동작한다.

**단계 1 — 시즌 최종 목표 수익률 결정** (`init_season` 시 각 AI에 대해 1회):

각 AI의 시즌 최종 목표 수익률 `target_r[i]`를 정규분포에서 샘플링한다.

```
rng = RandomNumberGenerator.new()
rng.seed = hash(season_seed XOR participant_id)
target_r[i] = rng.randfn(mu_tier, sigma_tier)
target_r[i] = clamp(target_r[i], r_min_tier, r_max_tier)
```

`mu_tier`, `sigma_tier`, `r_min_tier`, `r_max_tier` 값은 §4-1 티어 파라미터 테이블 참조.

**단계 2 — 일별 수익률 궤적 생성** (글로벌 갱신 시 해당 일 계산):

시즌 최종 목표를 향해 각 일의 수익률을 오류 확산(random walk with drift) 모델로
생성한다.

```
daily_return[d] = drift_per_day + volatility_noise[d]
drift_per_day  = target_r[i] / SEASON_DAYS    # 선형 드리프트
volatility_noise[d] = rng2.randfn(0, sigma_daily)
```

`d`번째 날의 누적 수익률:
```
cumulative_r[d] = Σ(daily_return[0..d])
# d = 0~19 (SEASON_DAYS = 20)
```

`sigma_daily`는 §4-2의 일일 변동성 테이블 참조.

**단계 3 — 틱 내 보간 (플레이어 티어 한정, 매 틱)**:

플레이어 소속 티어의 AI에 대해서만, 현재 거래일의 수익률을 틱 단위로 보간한다.

```
intra_day_progress = current_tick / TICKS_PER_DAY  # 0.0~1.0
r_prev = cumulative_r[current_day - 1]  # 전일 누적 (day 0이면 0.0)
r_next = cumulative_r[current_day]      # 당일 목표 누적
return_pct[i] = r_prev + (r_next - r_prev) × intra_day_progress
```

### 3-4. 공개 인터페이스 (SeasonManager 계약)

```gdscript
## 시즌 시작 시 호출. 티어별 AI 참가자 초기화.
## tier: 플레이어 배정 티어 (int, TIER_BRONZE=0 ~ TIER_MASTER_OF_INVESTMENT=10)
## participant_count: Dictionary[int, int] — 티어 → 인원수
func init_season(player_tier: int, participant_counts: Dictionary, seed: int) -> void

## 매 틱 호출. 플레이어 소속 티어 내 특정 AI의 현재 return_pct 반환.
## participant_id: 0-based index (해당 티어 내 순번)
## 반환값: float (%), 예) 12.4
func get_tier_return_pct(participant_id: int) -> float

## 일 1회 (글로벌 갱신 시) 호출. 지정 티어 전체 AI의 return_pct 배열 반환.
## tier: 대상 티어 번호
## 반환값: Array[float], 인덱스 = participant_id
func get_all_return_pcts(tier: int) -> Array
```

> `init_season` 호환성 주의: season-manager.md §3-3에 명시된 원래 계약
> `init_season(tier, participant_count)` (2인수)에서, 내부 설계상
> `seed`를 추가 인수로 받는 형태로 확장한다.
> SeasonManager는 `GameClock.get_season_seed()` 또는 자체 생성 시드를 전달한다.
> 하위 호환성이 필요하면 `seed`에 기본값(`0`)을 허용하고, `0`일 경우
> `Time.get_ticks_msec()`로 시드를 자동 생성한다 (비결정론적 — 테스트 환경에서는 금지).

### 3-5. 플레이어 티어 내 실시간 순위 계산 전략

브론즈 7,600명 포함 모든 티어에서 매 틱 전원 재정렬하는 것은 성능 부담이다.
아래 전략으로 O(n) 정렬을 피한다.

**버킷 기반 증분 순위 추정:**

```
# 초기화 (init_season 또는 일별 스냅샷 갱신 시):
# 해당 티어 AI의 return_pct 배열을 정렬하여 백분위 버킷 생성
# RANK_BUCKETS = 100  (1%단위, 튜닝 가능)
bucket_edges[b] = sorted_returns[b * count / RANK_BUCKETS]  # b = 0~99

# 매 틱 플레이어 순위 추정:
player_pct = current_return_pct  # 플레이어 수익률
bucket_idx = bucket_edges.bsearch(player_pct)  # 이진 탐색 O(log 100) = O(1)
estimated_rank = count * (1.0 - bucket_idx / RANK_BUCKETS) + 1
```

버킷은 일별 스냅샷 갱신(하루 1회) 시에만 재계산한다.
플레이어 순위는 버킷 기반 추정값이며, "≈ 37위" 형태로 UI에 표시해도 충분하다.
정확한 순위가 필요한 경우(순위 보상 최종 결정)는 시즌 종료 시 전체 정렬로 확정한다.

**거장 티어 AI 리더보드 처리:**

season-manager.md §3-3 기본 방침에 따라 거장 AI(200명)는 글로벌 순위에 포함된다.
`get_all_return_pcts(TIER_MASTER_OF_INVESTMENT)` 호출 시 정상 반환한다.
단, 이들 AI의 `participant_id`에는 `IS_GRANDMASTER_FLAG = true`를 메타데이터로
함께 제공하여 UI가 `[거장]` 뱃지를 렌더링할 수 있도록 한다.

```gdscript
## 거장 뱃지 메타데이터 (옵션 인터페이스)
func get_participant_meta(tier: int, participant_id: int) -> Dictionary:
    # { "is_master_of_investment": bool, "display_name": String }
```

---

## 4. Formulas

### 4-1. 티어별 수익률 분포 파라미터

시즌 20거래일 기준 최종 누적 수익률의 분포. `mu_tier`는 해당 티어 승급 목표를
달성하는 수익률을 중심으로 설정한다.

> 원래 GDD 초안은 `daily_r = (승급목표/진입기준)^(1/20) - 1` 복리 공식에서 도출된 mu 값을 사용했으나,
> 3x와 3.33x 티어 배율이 교대하면서 mu가 200%↔233% 패턴으로 진동하여 AC-02(인접 티어 단조성) 위반이 발생함.
> 따라서 mu를 선형 보간으로 재산정하여 단조 증가를 보장한다. 튜닝 시 반드시 mu[T] < mu[T+1] 조건 유지 필요.

| 티어 | 진입기준(원) | 승급목표(원) | mu_tier | sigma_tier | r_min | r_max |
|------|-------------|-------------|---------|-----------|-------|-------|
| 브론즈 | 1,000,000 | 3,000,000 | 100.0% | 60% | -30% | 600% |
| 실버 | 3,000,000 | 10,000,000 | 130.0% | 55% | -25% | 650% |
| 골드 | 10,000,000 | 30,000,000 | 160.0% | 45% | -20% | 550% |
| 플래티넘 | 30,000,000 | 100,000,000 | 190.0% | 40% | -15% | 500% |
| 에메랄드 | 100,000,000 | 300,000,000 | 215.0% | 35% | -10% | 450% |
| 다이아 | 300,000,000 | 1,000,000,000 | 235.0% | 30% | -5% | 420% |
| 마스터 | 1,000,000,000 | 3,000,000,000 | 250.0% | 25% | 0% | 380% |
| 그랜드마스터 | 3,000,000,000 | 10,000,000,000 | 265.0% | 22% | 5% | 360% |
| 챌린저 | 10,000,000,000 | 30,000,000,000 | 278.0% | 18% | 10% | 320% |
| 레전드 | 30,000,000,000 | 100,000,000,000 | 290.0% | 15% | 15% | 300% |
| 거장 | 100,000,000,000+ | — | 310.0% | 20% | 50% | 500% |

> **티어 단조성 보장**: mu_tier와 r_min_tier 모두 단계적으로 상승한다.
> 고티어 AI는 저티어 AI보다 항상 높은 평균·하한 수익률을 가져 글로벌 순위 상단을 점한다 (AC-02).

**예시 계산 — 브론즈 AI participant_id=42, season_seed=12345:**
```
rng.seed = hash(12345 XOR 42) = hash(12303) → 가정값 7891234
target_r[42] = rng.randfn(200.0, 60.0)  → 가정값 173.4%
target_r[42] = clamp(173.4, -30.0, 600.0) = 173.4%
```

### 4-2. 일일 변동성 (sigma_daily)

각 틱마다 느껴지는 수익률 진동의 크기. 티어가 높을수록 변동성이 낮다.
(고티어 참가자는 안정적 운용 능력을 갖춘 것으로 모델링)

```
sigma_daily = sigma_tier / sqrt(SEASON_DAYS)
# 표준 통계: 시즌 변동성을 일별로 분해 (분산 합산 모델)
# SEASON_DAYS = 20

예) 브론즈: sigma_daily = 60 / sqrt(20) ≈ 13.4%
예) 레전드: sigma_daily = 15 / sqrt(20) ≈ 3.4%
```

**예시 계산 — 브론즈 AI, target_r=173.4%, SEASON_DAYS=20:**
```
drift_per_day = 173.4 / 20 = 8.67%
sigma_daily   = 60 / sqrt(20) ≈ 13.4%

day 0: daily_return[0] = 8.67 + rng2.randfn(0, 13.4) → 8.67 + 5.2 = 13.87%
day 1: daily_return[1] = 8.67 + (-8.1) = 0.57%
...
cumulative_r[0] = 13.87%
cumulative_r[1] = 13.87 + 0.57 = 14.44%
```

### 4-3. 틱 내 보간 공식

```
return_pct(tick) = r_prev + (r_next - r_prev) × (tick / TICKS_PER_DAY)

변수 정의:
  r_prev        = cumulative_r[current_day - 1]  (전일 종가 누적, day 0이면 0.0)
  r_next        = cumulative_r[current_day]       (당일 예정 누적)
  tick          = 0 ~ TICKS_PER_DAY-1 (= 0~1559)
  TICKS_PER_DAY = 1560  (game-clock.md §Core Rules 참조)

예) 브론즈 AI, r_prev=13.87%, r_next=14.44%, tick=780 (장중 50%):
  return_pct = 13.87 + (14.44 - 13.87) × (780/1560)
             = 13.87 + 0.57 × 0.5
             = 14.155%
```

### 4-4. 버킷 기반 순위 추정

```
estimated_rank(player_pct, bucket_edges, count) =
  count × (1.0 - bsearch_rank(player_pct, bucket_edges) / RANK_BUCKETS) + 1

변수 정의:
  player_pct      = 플레이어 현재 return_pct
  bucket_edges[b] = b번째 백분위 경계값 (0~RANK_BUCKETS-1)
  bsearch_rank    = player_pct 이상인 최소 bucket 인덱스 (이진 탐색)
  count           = 해당 티어 총 인원수 (AI + 플레이어)
  RANK_BUCKETS    = 100

예) 브론즈 7,600명, player_pct=35.0%, bucket_edges[70]=30.0%, bucket_edges[71]=38.0%
  bsearch_rank = 71
  estimated_rank = 7600 × (1.0 - 71/100) + 1 = 7600 × 0.29 + 1 ≈ 2205위
```

### 4-5. 시드 생성 공식

```
participant_rng_seed = (season_seed × 1000003) XOR (participant_id × 998244353)
# 1000003, 998244353은 소수 상수 (충돌 최소화)
# XOR 연산으로 시드 분산 확보

예) season_seed=12345, participant_id=42:
  seed = (12345 × 1000003) XOR (42 × 998244353)
       = 12345036735 XOR 41926262826
       = (정수 XOR 연산) → 재현 가능한 고유 시드
```

---

## 5. Edge Cases

| # | 상황 | 처리 |
|---|------|------|
| EC-01 | `init_season` 호출 없이 `get_tier_return_pct` 호출 | `push_error("AiCompetitor: init_season not called")` 후 `0.0` 반환. 시즌 시작 전 UI 보호 목적 |
| EC-02 | `participant_id`가 해당 티어 인원수를 초과 | `push_error` + `0.0` 반환. SeasonManager 버그 방지용 가드 |
| EC-03 | `seed = 0` (기본값) 전달 시 | `Time.get_ticks_msec()`으로 시드 자동 생성. 비결정론적 — 테스트 환경에서는 금지. 테스트 시 반드시 명시적 시드 전달 |
| EC-04 | `current_day = 0` (시즌 첫날 장중)의 `r_prev` | `r_prev = 0.0` 고정. 첫날은 0%에서 출발 |
| EC-05 | `cumulative_r[d]`가 `r_min_tier`보다 낮아지는 경우 (일별 진동 누적) | 일별 `cumulative_r[d]`를 `r_min_tier`로 하한 클램프. 단, 최종 `target_r`은 이미 클램프되어 있으므로, 중간 경로에서만 발생하는 일시적 이탈이다 |
| EC-06 | 거장 AI(200명)의 `get_all_return_pcts` 요청 | 정상 반환. 거장 AI는 `mu_tier=250%, r_min=50%`으로 항상 높은 수익률 분포를 가짐. 글로벌 상위권을 점유하는 것은 의도된 설계 |
| EC-07 | 플레이어 티어 내 AI가 0명인 경우 (잠재적 설정 오류) | `get_tier_return_pct` 호출 시 `push_error` + `0.0`. `get_all_return_pcts` 호출 시 빈 배열 반환 |
| EC-08 | 시즌 도중 플레이어 티어 변경 요청 | AiCompetitor는 티어를 시즌 시작 시 고정하며, 시즌 중 티어 변경을 지원하지 않는다. SeasonManager가 시즌 종료 후 `init_season`을 재호출하여 갱신한다 |
| EC-09 | `sigma_tier = 0` (모든 AI가 동일 목표 수익률) | 모든 AI가 동일한 수익률을 가져 동점 처리가 과부하를 유발할 수 있다. `sigma_tier >= 5.0` 하한을 Tuning Knob 유효성 검증에서 강제 |
| EC-10 | `TICKS_PER_DAY = 0` (이론상 불가, GameClock 오류 연동) | 보간 분모 0 방지: `tick / max(TICKS_PER_DAY, 1)`. `push_error` 발생 |
| EC-11 | 두 AI가 동일한 시즌 최종 `return_pct`를 기록 (동점) | SeasonManager §4-3 동점 처리 규칙에 위임 (season_join_timestamp 기준). AiCompetitor는 수익률 값만 제공하며 순위 결정 로직을 소유하지 않는다 |
| EC-12 | `get_all_return_pcts` 호출 시 해당 일 `daily_snapshots`가 아직 생성되지 않은 경우 | 해당 일 스냅샷을 즉시 지연 계산 후 반환 (lazy evaluation). 캐시 이중 생성 방지를 위해 이미 계산된 경우 캐시값 반환 |

---

## 6. Dependencies

### 이 시스템이 제공하는 것 (Outbound)

| 수신 시스템 | 인터페이스 | 내용 |
|------------|-----------|------|
| `SeasonManager` | `get_tier_return_pct(id)` | 매 틱, 플레이어 티어 AI의 return_pct |
| `SeasonManager` | `get_all_return_pcts(tier)` | 일 1회, 글로벌 순위 갱신용 전 티어 return_pct 배열 |
| `LeagueUI` | `get_participant_meta(tier, id)` | 거장 뱃지 메타데이터 (옵션) |

### 이 시스템이 요구하는 것 (Inbound)

| 제공 시스템 | 인터페이스 | 내용 |
|------------|-----------|------|
| `SeasonManager` | `init_season(player_tier, participant_counts, seed)` | 시즌 초기화 트리거. 티어별 인원수와 시드 제공 |
| `GameClock` | `TICKS_PER_DAY` 상수 | 틱 내 보간 분모 (1560). `game-clock.md` §Core Rules 참조 |
| `GameClock` | `on_day_end` 시그널 | 일별 스냅샷 갱신 타이밍 (일 1회 lazy evaluation 트리거) |

### 역참조 문서

| 문서 | 관계 |
|------|------|
| `season-manager.md` | 이 시스템의 주 소비자. 티어 구조, 인원 분포, 계약 인터페이스 원본 정의 |
| `game-clock.md` | `TICKS_PER_DAY = 1560` 상수, `on_day_end` 시그널 소스 |
| `league-ui.md` | 거장 뱃지 UI 렌더링 — `get_participant_meta` 옵션 인터페이스 사용 |

### 이 시스템이 사용하지 않는 것

`PriceEngine`, `OrderEngine`, `PortfolioManager`, `CurrencySystem` — AI는 실제
매매를 하지 않으므로 이 시스템들과 완전히 독립적이다.

---

## 7. Tuning Knobs

모든 값은 `assets/data/ai_competitor_config.tres` (또는 동등한 외부 데이터 파일)에
저장한다. 코드에 하드코딩 금지.

### 7-1. 전역 파라미터

| 파라미터 | 기본값 | 안전 범위 | 영향 | 종류 |
|---------|-------|---------|------|------|
| `RANK_BUCKETS` | 100 | 20 ~ 500 | 순위 추정 정밀도와 버킷 재계산 비용 트레이드오프. 값이 클수록 정밀하나 메모리·계산 증가 | Feel |
| `SEASON_DAYS` | 20 | 10 ~ 40 | 수익률 궤적 길이. game-clock.md `SEASON_WEEKS × 5`와 반드시 동기화 | Gate |

### 7-2. 티어별 분포 파라미터

| 파라미터 | 기본값 예시 (브론즈) | 안전 범위 | 영향 | 종류 |
|---------|------------------|---------|------|------|
| `mu_tier[T]` | 200.0% | `mu_tier[T] > mu_tier[T-1]` 조건 필수 | 해당 티어 AI의 평균 시즌 수익률. 값 증가 시 글로벌 순위에서 해당 티어가 상위 이동 | Curve |
| `sigma_tier[T]` | 60% (브론즈) ~ 15% (레전드) | 5.0% ~ 120% | 티어 내 수익률 분포 폭. 클수록 플레이어가 AI를 이기기도 쉽고 밀리기도 쉬워짐 | Curve |
| `r_min_tier[T]` | -30% (브론즈) ~ 15% (레전드) | `r_min[T] >= r_min[T-1]` 조건 필수 | 티어 AI의 최저 수익률 하한. 티어 단조성(Monotonicity) 보장의 핵심 제약 | Curve |
| `r_max_tier[T]` | 600% (브론즈) ~ 300% (레전드) | `r_max[T] >= mu_tier[T] + 2×sigma_tier[T]` 권장 | AI가 지나치게 높은 수익률로 플레이어를 압도하지 않도록 상한 제어 | Curve |

> **단조성 검증 규칙**: 빌드 시 또는 `init_season` 호출 시, 아래 두 조건을 assert로 검증한다.
> 1. `mu_tier[T+1] > mu_tier[T]` (모든 T에 대해)
> 2. `r_min_tier[T+1] >= r_min_tier[T]` (모든 T에 대해)
> 위반 시 `push_error`로 설계 오류임을 알린다.

### 7-3. 성능 관련 파라미터

| 파라미터 | 기본값 | 안전 범위 | 영향 | 종류 |
|---------|-------|---------|------|------|
| `PLAYER_TIER_TICK_UPDATE` | true | bool | false 시 플레이어 티어도 일별 스냅샷만 갱신. 성능 긴급 상황 시 임시 전환 | Feel |
| `LAZY_EVAL_ON_DEMAND` | true | bool | false 시 시즌 시작 시 전 일수 사전 계산 (메모리 ↑, 글로벌 갱신 지연 ↓) | Feel |

---

## 8. Acceptance Criteria

모든 AC는 GUT 테스트로 검증 가능하며, `tests/unit/test_ai_competitor.gd`에 구현한다.

### AC-01 결정론적 재현성

```
테스트: 동일한 season_seed와 participant_id로 두 번 init_season 호출 후
        get_tier_return_pct(id) 값 비교
기대: 두 호출의 반환값이 부동소수점 오차 범위(epsilon=0.001%) 내에서 동일
```

### AC-02 티어 단조성 (글로벌 순위 공정성)

```
테스트: 전 11개 티어에 대해 get_all_return_pcts 호출 후
        각 티어의 중앙값(median) 비교
기대: median(tier T+1) > median(tier T) — 모든 인접 티어 쌍에서 성립
      (샘플 크기 N=1000, season_seed=42 기준)
```

### AC-03 계약 인터페이스 정상 동작

```
테스트: init_season 후 각 인터페이스 호출
기대:
  - get_tier_return_pct(id) → float 반환, 범위 [r_min_tier, r_max_tier]
  - get_all_return_pcts(tier) → Array, 길이 = 해당 티어 participant_count
  - 모든 반환값이 NaN / INF가 아님
```

### AC-04 성능 — 매 틱 예산

```
테스트: 브론즈 7,600명 대상으로 get_all_return_pcts(TIER_BRONZE) 호출
        실행 시간 측정 (GUT의 time_ms 활용)
기대: 단일 호출 ≤ 2ms (게임 프레임 예산 16.6ms의 12% 이내)
환경: Editor 디버그 빌드 기준 (릴리스 빌드는 3~5배 빠름)
```

### AC-05 성능 — 틱 내 보간

```
테스트: 플레이어 티어(브론즈 기준) 7,600명에 대해 매 틱 보간 갱신
        1,560틱(1 거래일) 시뮬레이션 총 실행 시간
기대: 총 1,560 × 7,600회 보간 ≤ 500ms (1거래일 실제 소요 약 300초이므로 충분)
```

### AC-06 클램프 동작

```
테스트: sigma_tier를 비정상적으로 크게 설정(예: 10000%)하여
        일부 AI의 raw target_r이 r_min / r_max를 벗어나도록 유도
기대: 반환되는 return_pct가 항상 [r_min_tier, r_max_tier] 범위 내
```

### AC-07 버킷 순위 추정 오차

```
테스트: 브론즈 7,600명 AI를 생성 후 전체 정렬 순위(정확값)와
        버킷 기반 추정 순위 비교
기대: |정확순위 - 추정순위| ≤ count × (2 / RANK_BUCKETS)
      (예: 7600명, RANK_BUCKETS=100 → 오차 ≤ 152위)
```

### AC-08 거장 AI 메타데이터

```
테스트: 거장 티어 AI에 대해 get_participant_meta 호출
기대: 반환 Dictionary에 "is_master_of_investment": true 포함
      일반 티어 AI에 대해서는 "is_master_of_investment": false
```

### AC-09 에러 가드 동작

```
테스트: init_season 호출 없이 get_tier_return_pct(0) 호출
기대: 반환값 0.0, 콘솔에 push_error 메시지 출력 (GUT assert_has_error 활용)
```

### AC-10 단조성 검증 assert

```
테스트: mu_tier 배열을 단조성 조건 위반으로 설정(예: mu[5] < mu[4])하여
        init_season 호출
기대: push_error 발생, 시즌 초기화 중단
```

### AC-11 경험적 순위 분포 건전성 (플레이어 경험)

```
테스트 (플레이테스트 검증): 플레이어가 해당 티어 평균 수익률(mu_tier)을 달성했을 때
기대: 티어 내 순위가 대략 40~60% 구간에 위치 (즉, "평균 달성 = 중간 순위")
      이 조건이 깨지면 mu_tier 또는 sigma_tier 재조정 필요
```

---

*이 문서는 season-manager.md와 교차 검증되었으며 양방향 의존 관계가 확인됨.*
*마지막 교차 검증: 2026-04-03*
