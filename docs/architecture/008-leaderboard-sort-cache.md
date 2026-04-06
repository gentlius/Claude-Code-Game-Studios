# ADR-008: 리더보드 정렬 캐시 — O(N log N) 매 4틱 → O(K) 조회

**날짜:** 2026-04-06  
**상태:** Accepted  
**결정자:** technical-director, lead-programmer

---

## 문제

`SeasonManager.get_leaderboard()`가 GameClock의 on_tick(4틱마다 UI 갱신)에 의해
호출될 때마다 다음 작업을 수행했다:

1. `AiCompetitor.get_all_return_pcts(tier)` — 전체 AI N명의 인트라데이 보간 **O(N)**
2. N개 Dictionary 객체 생성 **O(N)**
3. `Array.sort_custom()` — **O(N log N)**
4. 상위 K개 슬라이스만 반환

Bronze 티어 기준 N ≈ 7,600명 × 4틱/초 × 초당 갱신 = 게임 플레이 중 지속적 CPU 낭비.

---

## 결정

**스냅샷 생성 시 정렬 인덱스를 함께 캐시한다.**

### `AiCompetitor._ensure_daily_snapshot()` 변경

일별 스냅샷(`day_snap: Array[float]`) 계산 완료 후, 해당 스냅샷의 participant_id를
종가 내림차순으로 정렬한 `Array[int]`를 `td["sorted_indices"][day]`에 저장한다.

- 정렬 비용: 하루 1회(lazy) O(N log N) — 기존과 동일하지만 이 비용이 틱 루프에서 분리됨
- 캐시 조회: O(1)

### 새 공개 API

| 메서드 | 복잡도 | 설명 |
|--------|--------|------|
| `get_sorted_indices(tier)` | O(1) | 당일 스냅샷 기준 내림차순 정렬 인덱스 반환 |
| `get_interpolated_return(tier, id)` | O(1) | 단일 참가자 인트라데이 보간 수익률 반환 |

### `SeasonManager.get_leaderboard()` 변경

```
기존: O(N) + O(N) 객체 생성 + O(N log N) 정렬 → 매 4틱
신규: O(1) 인덱스 조회 + O(log N) 플레이어 순위 + O(K) 행 보간 → 매 4틱
```

K = 표시 행 수 (기본 20). Bronze 7,600명 기준 **380배 이상 개선** 예상.

### `SeasonManager._calculate_player_tier_rank()` 변경

`get_all_return_pcts()` O(N) 선형 탐색 → `estimate_player_rank()` O(log N) 버킷 이진 탐색.  
이 함수는 시즌 종료 시 1회만 호출되므로 성능 영향 미미하나 일관성 차원에서 통일.

### `SeasonManager._is_player_weekly_top()` 변경

전체 AI O(N) 순회 → 정렬 인덱스[0] (최고 AI 수익률)과 단순 비교 **O(1)**.

---

## 트레이드오프

### 수용한 근사

- **일중 순위 정확도:** 정렬 인덱스는 종가 기준. 인트라데이에 전일 종가 순서와 당일 종가 순서가
  역전되는 AI 쌍이 있으면 리더보드에서 미세한 순위 오차가 발생할 수 있다.
  - 허용 이유: 리더보드 UI의 목적은 플레이어의 대략적 위치 파악이지 실시간 완벽 순위가 아님.
  - GDD AI-경쟁자 §4-4에 "순위는 추정치" 명시.

- **플레이어 순위 근사:** `estimate_player_rank()`는 RANK_BUCKETS=100개 버킷 기반 추정.
  최대 오차 ±(N/100)명. Bronze 기준 ±76명 수준.
  - 허용 이유: 리더보드 표시용 추정 순위. 시즌 종료 최종 순위는 별도 확정 로직 필요 시 재검토.

### 메모리 증가

- 정렬 인덱스 추가 저장: tier당 day당 N×4 bytes (int32).
- Bronze: 7,600 × 20일 × 4 bytes = 608 KB. 전체 티어 합산 ~2 MB — 허용 범위.

---

## 관련 파일

| 파일 | 변경 내용 |
|------|----------|
| `src/gameplay/ai_competitor.gd` | `_ensure_daily_snapshot()` 정렬 캐시 추가, `get_sorted_indices()`, `get_interpolated_return()` 신규 |
| `src/gameplay/season_manager.gd` | `get_leaderboard()`, `_calculate_player_tier_rank()`, `_is_player_weekly_top()` 리팩터 |

---

## 참고

- ADR-004: AI 경쟁자 통계적 시뮬레이션 (실매매 없음)
- ADR-007: 글로벌 순위 return_pct 단일 정렬 + AI 파라미터 단조성 보장
- GDD: `design/gdd/ai-competitor.md` §4-4 버킷 순위 추정
