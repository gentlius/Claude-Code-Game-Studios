# ADR-004: AI 경쟁자 통계적 수익률 시뮬레이션

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-04-03 |
| **Decision Maker** | user + technical-director |
| **Relates To** | design/gdd/ai-competitor.md, src/gameplay/ai_competitor.gd |

## Context

시즌마다 19,999명의 AI 경쟁자가 플레이어와 동일한 리그에 참가한다.
리더보드가 현실감 있으려면 각 AI의 매 틱 수익률이 갱신되어야 한다.

가장 직관적인 구현은 AI마다 실제 PriceEngine/OrderEngine을 통해 매매를
시뮬레이션하는 것이다. 그러나 게임의 1틱 처리 예산(16.6ms 전체)에서
19,999명 × 매 틱 실매매 파이프라인은 CPU 예산을 수십 배 초과한다.
반면 플레이어는 "경쟁자들이 어떤 주식을 언제 샀는지"가 아니라
"내가 몇 위인지"에만 관심이 있다.

이 격차에서 핵심 질문이 도출된다: **AI의 최종 수익률 분포가 올바르면,
실제 매매 경로는 중요한가?**

## Decision

**정규분포 기반 수익률 직접 생성** 방식을 채택한다.
AI 경쟁자는 PriceEngine, OrderEngine, PortfolioManager와 일체 접촉하지 않는다.
수익률은 수식에 따라 직접 생성되며, 세 단계 파이프라인으로 동작한다.

### 파이프라인

```
단계 1 — 시즌 시작 시 (1회):
  target_r[i] = clamp(randfn(mu_tier, sigma_tier), r_min_tier, r_max_tier)
  시드 = (season_seed × 1000003) XOR (participant_id × 998244353) XOR (tier × 7919)

단계 2 — 글로벌 갱신 시 (일 1회, lazy):
  drift_per_day = target_r[i] / SEASON_DAYS
  daily_r[d]    = drift_per_day + randfn(0, sigma_daily)
  cumulative_r[d] = Σ daily_r[0..d]   # 내부: 클램프 없음

단계 3 — 매 틱 (플레이어 티어 한정):
  progress = current_tick / TICKS_PER_DAY
  return_pct[i] = r_prev + (r_next - r_prev) × progress
  → 외부 반환 시에만 clamp(result, r_min, r_max)
```

단계 3은 **플레이어 소속 티어**에만 적용한다. 나머지 티어는 일별 스냅샷(단계 2)만
계산하고 틱 내 보간은 생략한다 (글로벌 리더보드는 일 1회 갱신으로 충분).

### 공개 API 계약

```gdscript
## 시즌 시작 시 호출. 티어별 AI 초기화.
## seed=0 전달 시 비결정론적 자동 시드 (테스트 환경에서 사용 금지).
func init_season(player_tier: int, participant_counts: Dictionary, seed: int = 0) -> void

## 매 틱 호출. 플레이어 소속 티어 내 특정 AI의 현재 return_pct 반환.
func get_tier_return_pct(participant_id: int) -> float

## 일 1회 (글로벌 갱신). 지정 티어 전체 AI의 return_pct 배열 반환.
func get_all_return_pcts(tier: int) -> Array
```

### 결정론적 재현성

동일한 `season_seed` + `participant_id`에서 항상 동일한 궤적을 보장한다.
각 AI의 시드를 tier 오프셋까지 포함하여 독립적으로 생성하므로,
같은 participant_id라도 티어가 다르면 수익률이 다르다.

## Alternatives Considered

### A. PriceEngine/OrderEngine을 이용한 AI 실매매

- **설명**: AI별로 실제 주문을 생성하고 체결 엔진을 통과시킴
- **장점**: 가격에 AI 매매가 영향을 미쳐 시장 리얼리즘 극대화
- **단점**: 19,999명 × 매 틱 실매매는 현재 시스템에서 성능 불가.
  AI의 대량 주문이 가격을 왜곡하여 플레이어에게 불공정한 시장 환경 조성.
  디버깅과 밸런스 조정이 지극히 어려움.
- **기각 이유**: 성능 예산 초과 + 플레이어 경험에 필요하지 않은 리얼리즘

### B. 단순 랜덤 수익률 (상수 범위 내 균등 분포)

- **설명**: 매 시즌 균등 분포(uniform)에서 최종 수익률 샘플링
- **장점**: 구현 최소
- **단점**: 티어 구분이 무의미해짐. 고티어 AI가 저티어보다 일관되게
  높은 수익을 내는 "단조성"이 보장되지 않아 글로벌 순위의 공정성 붕괴.
  플레이어 판타지("저 위에 가려면 얼마나 더 잘해야 하나")를 지원 불가.
- **기각 이유**: 티어 단조성 미보장 → AC-02 테스트 불통과

## Consequences

### 긍정적

- 19,999명의 수익률 갱신이 O(k) (k = 플레이어 티어 인원) 이내로 완료
- 결정론적 시드로 재현성 보장 → 버그 재현·밸런스 검증 용이
- 내부 생성 방식이 완전히 캡슐화 → SeasonManager, LeagueUI는 API만 사용
- 티어 파라미터 테이블(TIER_PARAMS)로 밸런스 조정 가능

### 부정적

- AI가 실제 주식을 매매하지 않으므로, AI 행동이 가격에 영향을 주지 않음
  (싱글플레이어 게임 특성상 허용되는 트레이드오프)
- 수익률 곡선이 수학적으로 생성되므로, 극단적 시드에서 비현실적 궤적 가능
  (r_min/r_max 클램프로 완화)

### 리스크

- **TIER_PARAMS 단조성 위반**: mu/r_min이 티어 간 단조 증가하지 않으면 AC-02 실패.
  완화: `init_season` 시 `_validate_tier_monotonicity()` 런타임 검증.
- **결정론적 패턴 노출**: 플레이어가 같은 시드에서 동일 AI 궤적을 발견할 수 있음.
  완화: `season_seed`를 매 시즌 `randi()`로 생성하여 시즌 간 독립성 확보.

## Performance Implications

- **CPU**: 플레이어 티어 틱 보간 = O(tier_count) / 틱. 전체 예산 영향 미미.
  글로벌 갱신 = O(total_ai × SEASON_DAYS) / 일. 일 1회이므로 허용.
- **Memory**: 19,999명 × 20일 × 4바이트(float) ≈ 1.6MB. 512MB 예산 내 안전.
- **Load Time**: 영향 없음.
- **Network**: 해당 없음.

## Validation Criteria

- **AC-01**: `init_season(0, {0: 10}, 42)` 후 `get_tier_return_pct(0)` 반환값이
  `[r_min_0, r_max_0]` 범위 내. 동일 시드 재실행 시 동일 값.
- **AC-02**: 모든 인접 티어 쌍에서 상위 티어의 `r_min` > 하위 티어의 `r_min`.
  `_validate_tier_monotonicity()` 통과.
- **AC-03**: `get_all_return_pcts(tier)` 반환 배열 길이 = `participant_counts[tier]`.
- **AC-04**: 시즌 20일 경과 후 `get_tier_return_pct(i)` 반환값이
  해당 티어 TIER_PARAMS `r_min~r_max` 범위 내.

## Related Decisions

- [ADR-001](001-system-communication-pattern.md) — GameClock 시그널 구독 패턴
- [ADR-007](007-global-rank-statistical-fairness.md) — 글로벌 순위 단순 정렬 + 단조성
- design/gdd/ai-competitor.md §3-1, §3-3, §4-1
