# AI Competitor System

> **Status**: Approved
> **Sprint**: S2-01
> **Created**: 2026-04-03
> **Last Updated**: 2026-04-14 — 순위/수익률 정합성 재설계 (전일 EOD 기준 통일, 틱 분산 계산, snapshot save/load)

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

2. **세션 내 결정론성**: 동일한 `season_seed`와 `participant_id`에서는 항상 동일한
   수익률 궤적이 생성된다. `season_seed`는 매 시즌 `randi()`로 생성되므로 세션 간
   재현은 지원하지 않는다. 테스트 시에는 반드시 명시적 seed를 `init_season()`에 전달해야 한다.

3. **티어 단조성 (Tier Monotonicity)**: 티어 T+1의 AI 수익률 분포 평균은 항상
   티어 T보다 높다. 고티어 AI가 글로벌 순위 상단을 점하는 것이 보장된다.

4. **플레이어 가시성**: SeasonManager가 요청하는 세 가지 인터페이스만 공개한다.
   내부 생성 방식은 완전히 캡슐화된다.

5. **성능 우선 — 틱 분산 계산**: 전체 19,999명의 수익률을 장 마감 순간에 일괄 계산하지 않는다.
   오늘 장 중 1,560틱에 걸쳐 내일 EOD snapshot을 조금씩 미리 계산한다 (틱당 ~13명).
   장 마감 시점에는 계산이 이미 완료되어 정렬만 수행한다.

6. **순위·수익률 정합성 — 전일 EOD 기준 통일**: 리더보드 표시와 순위 계산 모두
   **전일 장 마감(EOD) 기준**으로 동일하게 고정한다. 장 중 AI 수익률은 변동하지 않는다.
   UI에 "전일 기준" 라벨을 명시. 플레이어는 오늘 열심히 해서 내일 순위를 올리는 구조.
   (실제 KRX 실전투자대회 동일 방식)

### 3-2. 메모리 모델

```
AiCompetitor 내부 상태 (티어 단위로 관리):
  - tier_data[tier]: Dictionary
      - count: int                      # 해당 티어 AI 인원수
      - target_r: Array[float]          # 각 AI의 시즌 최종 목표 수익률 (init_season 시 생성)
      - eod_snapshot: Array[float]      # 전일 EOD 수익률 (장 마감 시 확정·저장 대상)
      - next_snapshot: Array[float]     # 오늘 EOD 예정값 (틱 분산 계산 중)
      - next_computed: int              # next_snapshot에서 계산 완료된 participant_id (0~count-1)
      - sorted_indices: Array[int]      # eod_snapshot 기준 내림차순 정렬 인덱스

  - player_tier: int            # 플레이어 현재 티어 (init_season 시 설정)
  - season_seed: int            # 이 시즌의 글로벌 랜덤 시드
  - _ticks_this_day: int        # 당일 틱 카운터 (틱 분산 계산 진행 추적)
```

**핵심 원칙**:
- `eod_snapshot`: 리더보드 표시·순위 계산에 사용. 장 마감 시 `next_snapshot`으로 교체.
- `next_snapshot`: 오늘 장 중 틱마다 조금씩 계산. 장 마감 전 완료.
- lazy evaluation 제거 — 대신 틱 분산(tick-distributed) 사전 계산.

### 3-3. 수익률 생성 파이프라인

AI 수익률 생성은 두 단계 파이프라인으로 동작한다.

**단계 1 — 시즌 최종 목표 수익률 결정** (`init_season` 시 전 티어 일괄, 1회):

각 AI의 시즌 최종 목표 수익률 `target_r[i]`를 정규분포에서 샘플링한다.

```
rng = RandomNumberGenerator.new()
rng.seed = (season_seed × 1000003) XOR (participant_id × 998244353) XOR (tier × 7919)
target_r[i] = rng.randfn(mu_tier, sigma_tier)
target_r[i] = clamp(target_r[i], r_min_tier, r_max_tier)
```

`mu_tier`, `sigma_tier`, `r_min_tier`, `r_max_tier` 값은 §4-1 티어 파라미터 테이블 참조.

**단계 2 — 오늘 EOD snapshot 틱 분산 계산** (매 틱, 전 티어):

장 중 매 틱, 전 티어를 통틀어 약 13명씩 `next_snapshot` 계산을 진행한다.
각 참가자의 당일 수익률은 random walk with drift 모델로 생성한다.

```
# 틱당 처리할 참가자 수:
participants_per_tick = ceil(TOTAL_PARTICIPANTS / TICKS_PER_DAY)  # ≈ 13명/틱

# 각 참가자의 당일 EOD 수익률:
sigma_daily = sigma_tier / sqrt(SEASON_DAYS)
drift_per_day = target_r[i] / SEASON_DAYS
daily_return[day] = drift_per_day + rng_daily.randfn(0, sigma_daily)
cumulative_r[day] = cumulative_r[day-1] + daily_return[day]
cumulative_r[day] = clamp(cumulative_r[day], -DAILY_LIMIT_PCT×(day+1), +DAILY_LIMIT_PCT×(day+1))
next_snapshot[i] = cumulative_r[day]
```

장 마감(`on_market_close`) 시:
```
# 계산 완료 보장 후:
eod_snapshot = next_snapshot          # 전일 → 오늘로 교체
sorted_indices = sort_descending(eod_snapshot)  # 순위 인덱스 재계산
next_snapshot = []                    # 다음 날 계산용 초기화
next_computed = 0
```

> **인트라데이 보간 제거**: 리더보드와 순위는 `eod_snapshot`(전일 EOD) 기준으로만 표시.
> 장 중 AI 수익률은 변동하지 않는다. UI에 "전일 기준" 라벨 표시.

### 3-4. 공개 인터페이스 (SeasonManager 계약)

```gdscript
## 시즌 시작 시 호출. 전 티어 target_r 생성 + eod_snapshot 초기화 (Day 0: 전부 0.0).
func init_season(player_tier: int, participant_counts: Dictionary, seed: int) -> void

## 전일 EOD 기준 지정 티어 수익률 배열 반환. 리더보드 표시용.
## 반환값: eod_snapshot (Array[float]). 장 중에도 변동 없음 (전일 고정).
func get_eod_snapshot(tier: int) -> Array[float]

## 전일 EOD 기준 정렬 인덱스 반환. 리더보드 O(K) 접근용.
## 반환값: participant_id를 eod_snapshot 내림차순으로 정렬한 Array[int].
func get_sorted_indices(tier: int) -> Array[int]

## 전일 EOD 기준 플레이어 티어 내 추정 순위 반환.
## player_return_pct: 플레이어 현재 수익률 (장 중 실시간 값).
## 반환값: 1-based 추정 순위 (이진탐색 O(log N)).
func estimate_player_rank(player_return_pct: float) -> int

## 거장 뱃지 메타데이터 (LeagueUI 전용 옵션).
func get_participant_meta(tier: int, participant_id: int) -> Dictionary

## 세이브용 직렬화 데이터 반환.
func get_save_data() -> Dictionary

## 로드용 복원. eod_snapshot 직접 복원 (재계산 없음).
func load_save_data(data: Dictionary) -> void
```

### 3-5. 플레이어 순위 계산 전략

`sorted_indices`는 장 마감 시 `eod_snapshot` 기준으로 1회 정렬·캐시된다.
플레이어 수익률 기준 순위 추정은 이진탐색으로 O(log N):

```
# estimate_player_rank(player_return_pct):
lo = 0, hi = sorted_indices.size()
while lo < hi:
    mid = (lo + hi) / 2
    if eod_snapshot[sorted_indices[mid]] > player_return_pct:
        lo = mid + 1
    else:
        hi = mid
estimated_rank = lo + 1
```

**순위 표시 원칙**:
- 리더보드 순위: `sorted_indices` 기준 (전일 EOD, AI 간 순서 고정)
- 플레이어 순위: `estimate_player_rank()` (전일 EOD AI 기준에서 플레이어 현재 수익률 위치 추정)
- UI 라벨: "전일 기준" 명시. 순위는 장 마감 후 갱신됨을 플레이어에게 안내.
- 시즌 종료 시 최종 순위: `sorted_indices` + 플레이어 삽입으로 정확 계산.

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

시즌 20거래일 기준 최종 누적 수익률의 분포.

> **설계 원칙 (2026-04-06)**: 티어 = 자본량, 실력 ≠ 티어.
> 브론즈가 실력이 낮아서 브론즈인 게 아니라, 시장에 들고 들어온 자본이 적어서 브론즈다.
> mu는 생존편향(2%/티어)만 반영한 거의 균등한 값. sigma는 티어 상승 시 감소
> (대자본 = 분산투자 가능 = 퍼센트 기준 수익률 안정화). r_min/r_max 전 티어 동일.
> 이전 설계(mu 25~250%, 실력 기반)는 현실 반영 실패로 폐기.

| 티어 | 진입기준(원) | 승급목표(원) | mu_tier | sigma_tier | r_min | r_max |
|------|-------------|-------------|---------|-----------|-------|-------|
| 브론즈 | 1,000,000 | 3,000,000 | 8% | 55% | -60% | 600% |
| 실버 | 3,000,000 | 10,000,000 | 10% | 52% | -60% | 600% |
| 골드 | 10,000,000 | 30,000,000 | 12% | 49% | -60% | 600% |
| 플래티넘 | 30,000,000 | 100,000,000 | 14% | 46% | -60% | 600% |
| 에메랄드 | 100,000,000 | 300,000,000 | 16% | 43% | -60% | 600% |
| 다이아 | 300,000,000 | 1,000,000,000 | 18% | 40% | -60% | 600% |
| 마스터 | 1,000,000,000 | 3,000,000,000 | 20% | 37% | -60% | 600% |
| 그랜드마스터 | 3,000,000,000 | 10,000,000,000 | 22% | 34% | -60% | 600% |
| 챌린저 | 10,000,000,000 | 30,000,000,000 | 24% | 31% | -60% | 600% |
| 레전드 | 30,000,000,000 | 100,000,000,000 | 26% | 28% | -60% | 600% |
| 거장 | 100,000,000,000+ | — | 28% | 25% | -60% | 600% |

> **티어 단조성 보장**: 단조성은 `mu_tier` 단독으로 보장한다. `r_min`은 전 티어 동일(-60%)이며,
> 고티어도 손실 가능하다. 분포 겹침(overlap)이 크며 이는 의도된 설계 (티어=자본, 실력≠티어).
> 고티어 순위 상단 점유는 sigma 감소(안정성)와 소폭 mu 우위의 복합 효과로 확률적으로 발생한다.
> 모든 AI의 일별 누적 수익률은 `PriceEngine.DAILY_LIMIT_PCT`(±30%/일) 기반 선형 누적
> 상한으로 클램프된다 (`_generate_cumulative_returns()` 참조).

**예시 계산 — 브론즈 AI participant_id=42, season_seed=12345:**
```
rng.seed = hash(12345 XOR 42) = hash(12303) → 가정값 7891234
target_r[42] = rng.randfn(8.0, 55.0)  → 가정값 21.3%
target_r[42] = clamp(21.3, -60.0, 600.0) = 21.3%
```

### 4-2. 일일 변동성 (sigma_daily)

각 틱마다 느껴지는 수익률 진동의 크기. 티어가 높을수록 변동성이 낮다.
(고티어 참가자는 안정적 운용 능력을 갖춘 것으로 모델링)

```
sigma_daily = sigma_tier / sqrt(SEASON_DAYS)
# 표준 통계: 시즌 변동성을 일별로 분해 (분산 합산 모델)
# SEASON_DAYS = 20

예) 브론즈: sigma_daily = 55 / sqrt(20) ≈ 12.3%
예) 레전드: sigma_daily = 15 / sqrt(20) ≈ 3.4%
```

**예시 계산 — 브론즈 AI, target_r=38.6%, SEASON_DAYS=20:**
```
drift_per_day = 38.6 / 20 = 1.93%
sigma_daily   = 55 / sqrt(20) ≈ 12.3%

day 0: daily_return[0] = 1.93 + rng2.randfn(0, 12.3) → 1.93 + 5.2 = 7.13%
day 1: daily_return[1] = 1.93 + (-8.1) = -6.17%
...
cumulative_r[0] = 7.13%
cumulative_r[1] = 7.13 + (-6.17) = 0.96%
```

### 4-3. EOD 기준 순위 정합성

리더보드 표시값과 순위는 동일한 `eod_snapshot`을 공유하므로 항상 정합성이 보장된다.

```
# 리더보드 표시: eod_snapshot[sorted_indices[k]] (k = 0, 1, 2, ...)
# 순위 추정: estimate_player_rank()가 동일 eod_snapshot 이진탐색

→ "1위 AI 수익률 X%, 나는 X%보다 높은데 2위" 모순 발생 불가
```

> **인트라데이 보간 제거 근거**: 이전 설계에서 리더보드는 보간값, 순위는 EOD 목표값을
> 섞어 사용하여 장 중 순위 역전 모순이 발생했다. 실제 KRX 실전투자대회도 전일 기준
> 순위 방식을 사용한다.

### 4-4. 순위 추정 (이진탐색)

```
# sorted_indices: eod_snapshot 내림차순 정렬 인덱스 (장 마감 시 생성)
# player_return_pct: 플레이어 현재 수익률 (장 중 실시간)

lo = 0
hi = sorted_indices.size()
while lo < hi:
    mid = (lo + hi) / 2
    if eod_snapshot[sorted_indices[mid]] > player_return_pct:
        lo = mid + 1
    else:
        hi = mid
estimated_rank = lo + 1   # 1-based

예) 브론즈 7,600명, player_pct = 35.0%
    eod_snapshot에서 35.0%보다 높은 AI = 1,800명
    estimated_rank = 1,801위
```

> 버킷 추정(구 방식) 대비 이진탐색이 더 정확하며 O(log N) 동일 성능.

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
| EC-01 | `init_season` 호출 없이 `get_eod_snapshot` / `get_sorted_indices` / `estimate_player_rank` 호출 | `push_error("AiCompetitor: init_season not called")` 후 빈 배열 / 0 반환. 시즌 시작 전 UI 보호 목적 |
| EC-02 | `participant_id`가 해당 티어 인원수를 초과 | `push_error` + `0.0` 반환. SeasonManager 버그 방지용 가드 |
| EC-03 | `seed = 0` (기본값) 전달 시 | `Time.get_ticks_msec()`으로 시드 자동 생성. 비결정론적 — 테스트 환경에서는 금지. 테스트 시 반드시 명시적 시드 전달 |
| EC-04 | Day 0 (시즌 첫날): 전일 EOD 데이터 없음 | `eod_snapshot` 전부 `0.0`으로 초기화. 첫날 리더보드에는 "전일 기준" 데이터가 없으므로 UI가 "아직 집계 전" 표시. |
| EC-05 | `cumulative_r[d]`가 일별 PriceEngine 제한을 초과하는 경우 | `next_snapshot` 계산 시 `PriceEngine.DAILY_LIMIT_PCT × (d+1)`을 상하한으로 클램프. 예: 1일차 ±30%, 2일차 ±60%, 20일차 ±600%. `target_r`은 이미 `r_max`로 상한 제어되므로 클램프는 하한(폭락 경로) 보정이 주 목적 |
| EC-06 | 거장 AI(200명)의 `get_eod_snapshot` 요청 | 정상 반환. 거장 AI는 `mu_tier=28%`으로 전 티어 중 가장 높은 mu와 가장 낮은 sigma(25%)를 가지며, `r_min=-60%`. 글로벌 상위권을 점유하는 경향이 있으나 확률적이며, 손실 가능성도 동등하게 존재한다 |
| EC-07 | 플레이어 티어 내 AI가 0명인 경우 (잠재적 설정 오류) | `get_eod_snapshot` / `get_sorted_indices` 호출 시 빈 배열 반환 (push_error 없음). `estimate_player_rank` 호출 시 `1` 반환 |
| EC-08 | 시즌 도중 플레이어 티어 변경 요청 | AiCompetitor는 티어를 시즌 시작 시 고정하며, 시즌 중 티어 변경을 지원하지 않는다. SeasonManager가 시즌 종료 후 `init_season`을 재호출하여 갱신한다 |
| EC-09 | `sigma_tier = 0` (모든 AI가 동일 목표 수익률) | 모든 AI가 동일한 수익률을 가져 동점 처리가 과부하를 유발할 수 있다. `sigma_tier >= 5.0` 하한을 Tuning Knob 유효성 검증에서 강제 |
| EC-10 | `TICKS_PER_DAY = 0` (이론상 불가, GameClock 오류 연동) | `participants_per_tick = ceil(TOTAL / max(TICKS_PER_DAY, 1))` 으로 분모 0 방지. `push_error` 발생 |
| EC-11 | 두 AI가 동일한 `eod_snapshot` 수익률 기록 (동점) | SeasonManager §4-3 동점 처리 규칙에 위임 (season_join_timestamp 기준). AiCompetitor는 수익률 값만 제공하며 순위 결정 로직을 소유하지 않는다 |
| EC-12 | 장 마감 전 틱 분산 계산 미완료 (`next_computed < TOTAL_PARTICIPANTS`) | `on_market_close` 시 미완료 참가자를 동기적으로 일괄 계산 후 swap. 프레임 드랍 경고 로그 출력. 정상 운영 시 발생하지 않아야 함 (`PARTICIPANTS_PER_TICK × TICKS_PER_DAY >= TOTAL_PARTICIPANTS`) |
| EC-13 | `load_save_data`에 특정 티어 키 누락 (세이브 파일 구버전 호환) | 해당 티어 `eod_snapshot`을 `0.0` 배열로 초기화. `target_r`은 `season_seed` 기반으로 재생성. `sorted_indices`는 초기화 후 재정렬 |

---

## 6. Dependencies

### 이 시스템이 제공하는 것 (Outbound)

| 수신 시스템 | 인터페이스 | 내용 |
|------------|-----------|------|
| `SeasonManager` | `get_eod_snapshot(tier)` | 전일 EOD 기준 수익률 배열. 리더보드 표시용 |
| `SeasonManager` | `get_sorted_indices(tier)` | 전일 EOD 기준 내림차순 정렬 인덱스. 리더보드 O(K) 접근용 |
| `SeasonManager` | `estimate_player_rank(player_return_pct)` | 전일 EOD AI 기준 플레이어 추정 순위 (이진탐색) |
| `LeagueUI` | `get_participant_meta(tier, id)` | 거장 뱃지 메타데이터 (옵션) |

### 이 시스템이 요구하는 것 (Inbound)

| 제공 시스템 | 인터페이스 | 내용 |
|------------|-----------|------|
| `SeasonManager` | `init_season(player_tier, participant_counts, seed)` | 시즌 초기화 트리거. 티어별 인원수와 시드 제공 |
| `GameClock` | `TICKS_PER_DAY` 상수 | 틱 분산 계산 총 틱 수 (1560). `game-clock.md` §Core Rules 참조 |
| `GameClock` | `on_tick` 시그널 | 매 틱 `next_snapshot` 분산 계산 진행 (틱당 ~13명) |
| `GameClock` | `on_market_close` 시그널 | 장 마감 시 `eod_snapshot ← next_snapshot` swap + 정렬 |

### 역참조 문서

| 문서 | 관계 |
|------|------|
| `season-manager.md` | 이 시스템의 주 소비자. 티어 구조, 인원 분포, 계약 인터페이스 원본 정의 |
| `game-clock.md` | `TICKS_PER_DAY = 1560` 상수, `on_tick` / `on_market_close` 시그널 소스 |
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
| `SEASON_DAYS` | 20 | 10 ~ 40 | 수익률 궤적 길이. game-clock.md `SEASON_WEEKS × 5`와 반드시 동기화 | Gate |
| `PARTICIPANTS_PER_TICK` | `ceil(19999 / 1560) = 13` | 10 ~ 30 | 틱당 `next_snapshot` 계산 인원수. `PARTICIPANTS_PER_TICK × TICKS_PER_DAY >= TOTAL_PARTICIPANTS` 조건 필수. 증가 시 프레임 부담 증가 | Perf |

### 7-2. 티어별 분포 파라미터

| 파라미터 | 기본값 예시 (브론즈) | 안전 범위 | 영향 | 종류 |
|---------|------------------|---------|------|------|
| `mu_tier[T]` | 8% (브론즈) ~ 28% (거장) | `mu_tier[T] > mu_tier[T-1]` 조건 필수 | 해당 티어 AI의 평균 시즌 수익률. 거의 균등 (생존편향 2%/티어). 값 증가 시 해당 티어 AI가 상위 이동 | Curve |
| `sigma_tier[T]` | 55% (브론즈) ~ 25% (거장) | 5.0% ~ 120% | 티어 내 수익률 분포 폭. 클수록 플레이어가 AI를 이기기도 쉽고 밀리기도 쉬워짐 | Curve |
| `r_min_tier[T]` | -60% (전 티어 동일) | 고정값. 단조성 조건 없음 | 티어 AI의 최저 수익률 하한. 단조성은 `mu_tier`로만 보장하며, `r_min`은 전 티어 동일한 -60%를 사용한다. 고티어도 손실 가능 | Curve |
| `r_max_tier[T]` | 600% (전 티어 동일) | `r_max[T] >= mu_tier[T] + 2×sigma_tier[T]` 권장 | AI가 지나치게 높은 수익률로 플레이어를 압도하지 않도록 상한 제어 | Curve |

> **단조성 검증 규칙**: `init_season` 호출 시 `_validate_tier_monotonicity()`가 자동으로 실행된다.
> 검증 조건: `mu_tier[T+1] > mu_tier[T]` (모든 T에 대해, 총 10쌍)
> `r_min`은 전 티어 동일(-60%)이므로 검증 대상에서 제외.
> 위반 시 `assert` 실패로 즉시 중단 — 튜닝 중 실수 방지 목적.

### 7-3. 성능 관련 파라미터

| 파라미터 | 기본값 | 안전 범위 | 영향 | 종류 |
|---------|-------|---------|------|------|
| `SYNC_FALLBACK_WARN_THRESHOLD` | 100 | 0 ~ 500 | 장 마감 시 동기 fallback 처리 인원 수가 이 값을 초과하면 `push_warning` 출력. 틱 분산 계산 파라미터 검토 신호 | Perf |

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
테스트: 전 11개 티어에 대해 get_eod_snapshot 호출 후
        각 티어의 중앙값(median) 비교
(주의: API는 get_all_return_pcts → get_eod_snapshot으로 변경됨. ADR 기준 현행 API 사용)
기대: median(tier T+1) > median(tier T) — 모든 인접 티어 쌍에서 성립
      (샘플 크기 N=1000, season_seed=42 기준)
```

### AC-03 계약 인터페이스 정상 동작

```
테스트: init_season 후 각 인터페이스 호출
기대:
  - get_eod_snapshot(tier) → Array[float], 길이 = 해당 티어 participant_count
  - get_sorted_indices(tier) → Array[int], 길이 = 해당 티어 participant_count, 내림차순 정렬
  - estimate_player_rank(35.0) → int, 범위 [1, participant_count+1]
  - 모든 반환값이 NaN / INF가 아님
```

### AC-04 성능 — 틱당 분산 계산 예산

```
테스트: 시즌 시작 후 단일 틱 처리(_on_tick) 실행 시간 측정 (GUT의 time_ms 활용)
        브론즈 7,600명 포함 전 티어 19,999명 기준, PARTICIPANTS_PER_TICK=13
기대: 단일 틱 처리 ≤ 0.5ms (프레임 예산 16.6ms의 3% 이내)
환경: Editor 디버그 빌드 기준
```

### AC-05 성능 — 장 마감 swap

```
테스트: on_market_close 수신 시 eod_snapshot swap + sorted_indices 정렬 실행 시간
        브론즈 7,600명 기준 (최대 티어)
기대: ≤ 5ms (장 마감은 프레임 단위 이벤트이므로 한 프레임 내 허용)
환경: Editor 디버그 빌드 기준
```

### AC-06 클램프 동작

```
테스트: sigma_tier를 비정상적으로 크게 설정(예: 10000%)하여
        일부 AI의 raw target_r이 r_min / r_max를 벗어나도록 유도
기대: 반환되는 return_pct가 항상 [r_min_tier, r_max_tier] 범위 내
```

### AC-07 이진탐색 순위 추정 정확도

```
테스트: 브론즈 7,600명 eod_snapshot 생성 후 임의 player_return_pct 100개에 대해
        estimate_player_rank() 결과와 선형 스캔 정확 순위 비교
기대: 두 값이 항상 동일 (이진탐색은 버킷 추정과 달리 정확값)
```

### AC-12 EOD 정합성 (리더보드 ↔ 순위)

```
테스트: init_season 후 _on_market_close() 호출 → 리더보드 1위 AI의 eod_snapshot 값을
        estimate_player_rank()에 입력하여 반환 순위 확인
기대: estimate_player_rank(eod_snapshot[sorted_indices[0]]) = 1
      (동점은 플레이어 우선 — 1위 AI와 동일 수익률이면 플레이어가 1위)
      → 리더보드 표시값과 순위 계산이 동일 eod_snapshot을 참조함을 검증
```

### AC-13 snapshot save/load 복원

```
테스트: init_season → 수 틱 진행 → on_market_close 호출 → get_save_data()
        → 새 AiCompetitor 인스턴스 → load_save_data() → get_eod_snapshot(tier) 비교
기대: 로드 후 get_eod_snapshot() 반환값이 저장 전과 float epsilon 오차 내 동일
     target_r는 season_seed 기반 재생성 (저장 불필요)
     sorted_indices는 eod_snapshot에서 재정렬 (저장 불필요)
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

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 기능 | 진입점 |
|------|--------|
| AI 시즌 초기화 | `season_manager.gd.start_season()` → `AiCompetitor.init_season(tier, counts, seed)` |
| 틱 분산 계산 | `game_clock.gd._process_tick()` 내 `on_tick` emit → `ai_competitor.gd._on_tick()` — 매 틱 ~13명 `next_snapshot` 계산 |
| 장 마감 snapshot swap | `GameClock.on_market_close` emit → `ai_competitor.gd._on_market_close()` — `eod_snapshot ← next_snapshot` + `sorted_indices` 재정렬 |
| 리더보드 데이터 제공 | `season_manager.gd.get_leaderboard()` → `AiCompetitor.get_eod_snapshot(tier)` + `get_sorted_indices(tier)` + `get_participant_meta(tier, id)` |
| 플레이어 순위 추정 | `season_manager.gd._calculate_player_tier_rank()` → `AiCompetitor.estimate_player_rank(player_return_pct)` |

### 호출 경로

- [x] `SeasonManager.start_season()` → `AiCompetitor.init_season(player_tier, participant_counts, seed)` 존재 확인
- [x] `GameClock.on_tick` 시그널 → `AiCompetitor._on_tick(tick, day, week)` 구독 — 틱 분산 계산
- [x] `GameClock.on_market_close` 시그널 → `AiCompetitor._on_market_close()` 구독 — snapshot swap + 정렬
- [x] `AiCompetitor.get_eod_snapshot(tier) -> Array[float]` 공개 API 존재
- [x] `AiCompetitor.get_sorted_indices(tier) -> Array[int]` 공개 API 존재
- [x] `AiCompetitor.estimate_player_rank(player_return_pct: float) -> int` 공개 API 존재
- [x] `AiCompetitor.get_participant_meta(tier, id) -> Dictionary` → `{display_name, is_master_of_investment}` 반환
- [x] `AiCompetitor.get_save_data()` → `{season_seed, participant_counts, eod_snapshots}` 직렬화
- [x] `AiCompetitor.load_save_data(data)` → `eod_snapshot` 직접 복원, `target_r` 재생성, `sorted_indices` 재정렬
- [x] `AiCompetitor.reset()` 존재 (테스트 격리)
- [x] `SeasonManager.get_leaderboard()` — `get_eod_snapshot()` / `get_sorted_indices()` / `estimate_player_rank()` 호출 전환 완료 (ADR-008)

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 | 상태 |
|----|------------|------------|------|
| AC-01 결정론적 재현성 | `tests/unit/test_ai_competitor.gd` | `test_init_is_deterministic_for_same_seed()` | ⬜ 재검증 필요 |
| AC-02 티어 단조성 | `tests/unit/test_ai_competitor.gd` | `test_tier_monotonicity()` | ⬜ 재검증 필요 |
| AC-03 계약 인터페이스 | `tests/unit/test_api_contracts.gd` | `test_ai_competitor_api()` | ⬜ 신규 API로 재작성 필요 |
| AC-04 틱당 분산 계산 예산 | `tests/unit/test_ai_competitor.gd` | `test_tick_calculation_performance()` | ⬜ 신규 |
| AC-05 장 마감 swap 성능 | `tests/unit/test_ai_competitor.gd` | `test_market_close_swap_performance()` | ⬜ 신규 |
| AC-06 클램프 동작 | `tests/unit/test_ai_competitor.gd` | `test_return_pct_clamped_to_range()` | ⬜ 재검증 필요 |
| AC-07 이진탐색 순위 정확도 | `tests/unit/test_ai_competitor.gd` | `test_binary_search_rank_accuracy()` | ⬜ 신규 |
| AC-08 거장 AI 메타데이터 | `tests/unit/test_ai_competitor.gd` | `test_grandmaster_ai_metadata()` | ⬜ 재검증 필요 |
| AC-09 에러 가드 | `tests/unit/test_ai_competitor.gd` | `test_get_eod_snapshot_before_init_returns_empty()` | ⬜ 신규 |
| AC-10 단조성 assert | `tests/unit/test_ai_competitor.gd` | `test_monotonicity_validation_assert()` | ⬜ 재검증 필요 |
| AC-11 경험적 순위 분포 | 플레이테스트 (S6-01 E2E 검증) | — | ⬜ 미확인 |
| AC-12 EOD 정합성 | `tests/unit/test_ai_competitor.gd` | `test_eod_consistency_leaderboard_rank()` | ⬜ 신규 |
| AC-13 snapshot save/load | `tests/unit/test_ai_competitor.gd` | `test_snapshot_save_load_roundtrip()` | ⬜ 신규 |

### 빌드 검증

- [x] 바이너리 실행 확인: QA Lead 서명 — 내부 감사 2026-04-15 (Alpha 완료 빌드, SCRIPT ERROR 없음)

### DLC 확장성 — MarketProfile 추상화 (Sprint 10)

> AI 경쟁자 수익률 분포가 한국 시장 변동성 기준으로 고정된 부분을 MarketProfile로 분리한다.  
> 근거: [ADR-021](../../docs/architecture/021-market-profile-data-driven.md) / 감사 항목: **M-02**

- [ ] 티어별 수익률 정규분포 파라미터 (`mean`, `std_dev`) → `_profile.ai_return_distribution` 딕셔너리 로드로 교체
- [ ] `assets/data/market_profiles/market_kr.json` — `"ai_return_distribution": {"BRONZE": {"mean": 0.03, "std": 0.08}, ...}` 등록
- [ ] 시즌 길이(`season-manager.md` M-01)가 변경될 때 수익률 분포도 재조정되어야 함 — 연동 확인
- [ ] `AiCompetitor.init_season()` 에서 MarketProfile 파라미터 수신 경로 설계: `SeasonManager` 경유 또는 직접 로드
- [ ] 테스트: `test_ai_competitor.gd` — `test_return_distribution_loaded_from_market_profile()` 추가

---

*이 문서는 season-manager.md와 교차 검증 필요 (인터페이스 재설계로 인해 season-manager.gd get_leaderboard() 업데이트 선행 필요).*
*마지막 교차 검증: 2026-04-03 (구 설계 기준) — 재설계 후 재검증 예정*
