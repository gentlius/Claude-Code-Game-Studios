# ADR-005: SeasonManager가 시즌 XP 지급 전권 소유

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Date** | 2026-04-03 |
| **Decision Maker** | user + technical-director |
| **Relates To** | src/gameplay/xp_system.gd, src/gameplay/season_manager.gd |

## Context

시즌 종료 시 플레이어에게 XP 보너스가 지급된다. 지급에 필요한 입력값은
네 가지다: `final_rank`, `is_free_market`, `season_return_pct`, `season_trade_count`.

이 네 값 모두 **SeasonManager**가 시즌 종료 처리(`_on_season_end`)에서
직접 계산하거나 보유하고 있다. 반면 **XpSystem**은 일별 XP 누적을 담당하는
독립 시스템으로, 시즌 문맥(순위, 수익률, 거래 횟수)을 자체적으로 알 수 없다.

여기서 구조적 선택이 필요했다: **누가 시즌 종료 XP 지급을 트리거하는가?**

초기 설계에서는 XpSystem이 `GameClock.on_season_end`를 직접 구독하여
자체적으로 시즌 XP를 처리하는 방안이 고려되었다. 그러나 이 방식은
XpSystem이 알 수 없는 값들을 독자적으로 추정해야 하는 문제를 낳는다.

## Decision

**SeasonManager가 시즌 XP 지급의 단일 진입점**이 된다.
XpSystem의 `on_season_end` 자동 핸들러 패턴을 제거하고,
SeasonManager의 `_on_season_end()` 내에서 XpSystem의 공개 API를
명시적으로 호출한다.

```gdscript
# SeasonManager._on_season_end() 내 step ⑤:
XpSystem.grant_season_bonus(
    final_rank,        # SeasonManager가 계산한 최종 순위
    _is_free_market,   # SeasonManager가 보유한 모드 플래그
    season_return_pct, # SeasonManager.get_season_return_pct()
    season_trade_count # OrderEngine.get_season_trade_count()
)
```

### 공개 API 계약

```gdscript
## XpSystem — 시즌 종료 XP 지급 (SeasonManager 전용 호출).
## final_rank: 시즌 최종 순위 (1-based). 프리마켓이면 0.
## is_free_market: 프리마켓 모드 여부.
## season_return_pct: 시즌 수익률 (%).
## season_trade_count: 시즌 중 체결 횟수.
func grant_season_bonus(
    final_rank: int,
    is_free_market: bool,
    season_return_pct: float,
    season_trade_count: int
) -> void
```

이 함수는 XpSystem의 **public API**로 명시적으로 공개되며,
XpSystem 내부의 `on_season_end` 시그널 구독은 존재하지 않는다.

### 의존 방향

```
SeasonManager ──호출──▶ XpSystem.grant_season_bonus()
                              │
                     XpSystem 내부 처리
                     (_grant_xp, _check_level_ups)
```

XpSystem은 SeasonManager를 참조하지 않는다. 단방향 의존.

## Alternatives Considered

### A. XpSystem이 on_season_end 구독하여 자체 처리

- **설명**: XpSystem이 `GameClock.on_season_end`를 직접 구독하고,
  `OrderEngine.get_season_trade_count()`, `PortfolioManager.get_total_assets()` 등을
  직접 조회하여 시즌 XP를 독자 계산
- **장점**: SeasonManager와 XpSystem의 결합 제거. 각 시스템이 독립적으로 동작.
- **단점**:
  - `final_rank`는 SeasonManager만 알고 있어 XpSystem이 독자 계산 불가.
  - `season_return_pct` 계산에 `_season_start_capital`이 필요한데
    이 값도 SeasonManager 소유. 동일 계산을 두 곳에 구현하면 불일치 위험.
  - 시그널 실행 순서(SeasonManager vs XpSystem 중 누가 먼저 처리하는가)에 따라
    상금 지급 전/후 XP 계산이 달라질 수 있음.
- **기각 이유**: `final_rank` 접근 불가 + 이중 계산 불일치 위험

### B. 공유 DTO(Data Transfer Object)를 통한 시즌 결과 전달

- **설명**: `SeasonResult` 리소스를 정의하고, SeasonManager가 이를 populate하여
  시그널로 방송. XpSystem이 해당 DTO를 수신하여 처리.
- **장점**: 결합도를 DTO 인터페이스로 한정. 양쪽 모두 시그널 기반 유지.
- **단점**: 단순 함수 호출로 해결 가능한 문제에 DTO 클래스 신설이 과도한 추상화.
  GDScript 4에서 타입화된 시그널 페이로드로 충분히 대체 가능.
  이 프로젝트 규모(21 시스템)에서 YAGNI 원칙에 어긋남.
- **기각 이유**: 복잡성 대비 이득 없음. 직접 호출이 더 명료.

## Consequences

### 긍정적

- `final_rank`, `is_free_market`, `season_return_pct`, `season_trade_count`가
  단일 호출 지점에서 SeasonManager의 권위 있는 값으로 전달됨 → 이중 계산 불가
- SeasonManager의 `_on_season_end()` 단계 목록(`step ①~⑦`)이 XP 지급 순서를
  명시적으로 문서화함 → 추적과 디버깅 용이
- XpSystem이 외부 시스템(SeasonManager, PortfolioManager)을 스스로 조회하지 않으므로
  유닛 테스트 시 SeasonManager mock으로 `grant_season_bonus()` 직접 호출 가능

### 부정적

- SeasonManager가 XpSystem에 의존하는 결합이 생김 (의존성 주입으로 완화 가능)
- `grant_season_bonus`가 SeasonManager 전용이라는 약속이 코드 레벨에서 강제되지 않음
  (주석과 ADR 문서로 보완)

### 리스크

- **SeasonManager 누락 호출**: `_on_season_end`에서 step 순서 오류로 XP 지급이 빠질 수 있음.
  완화: SeasonManager 유닛 테스트에서 `_on_season_end` 후 XP 증가 확인.
- **is_free_market 불일치**: SeasonManager의 `_is_free_market`이 정확해야 함.
  완화: `start_season()` → `_assign_tier()` 경로에서 단일 소스로 결정.

## Performance Implications

- **CPU**: 영향 없음. 시즌 종료는 이벤트성(1회).
- **Memory**: 영향 없음.
- **Load Time**: 영향 없음.
- **Network**: 해당 없음.

## Validation Criteria

- **AC-01**: `_on_season_end()` 실행 후 `XpSystem.get_total_xp()`가 증가했음을 확인.
- **AC-02**: `is_free_market=true`일 때 rank_bonus XP(BASE_SEASON_XP + RANK_XP)가
  지급되지 않고, completion_bonus(20 XP)만 조건 충족 시 지급.
- **AC-03**: `season_trade_count < 5`이면 completion_bonus 미지급.
- **AC-04**: XpSystem이 `on_season_end` 시그널 핸들러를 직접 구독하지 않음
  (코드 리뷰 항목).

## Implementation Notes (구현 중 결정 사항, 2026-04-04)

### Q3: 한강 엔딩 체크 타이밍 — 매 틱 → PRE_MARKET 전환 시 1회

초기 설계에서 한강 엔딩 조건(현금 < 10,000원 AND 보유 주식 없음)을 매 틱 on_tick에서 체크하는 방안을 고려했다. 그러나:
- 매 틱 체크는 장중 순간적인 0 상태(주문 대기 중)에서 오발동 가능
- 장중에는 예약 현금(reserved_cash)이 별도 관리되어 실제 잔고와 분리됨
- 플레이어 관점에서 "장 시작 전" 자산 상태가 가장 의미 있는 기준점

**결정**: `on_market_state_changed` → PRE_MARKET 전환 시 1회만 체크. 장 시작 직전 상태를 기준으로 한강 엔딩 판정.

### Q4: 주간 스냅샷 갱신 타이밍 — 주간 어워드 지급 후

`_on_week_end()`에서 주간 수익률 계산 → 어워드 지급 → 스냅샷 갱신 순서로 처리. 어워드 지급 이후에 `_weekly_start_capital`을 갱신해야 다음 주 수익률 기산점이 어워드를 포함한 올바른 자산으로 설정됨.

### 알려진 구조적 gap: SeasonManager.start_season() 호출 경로 없음

`SeasonManager.start_season()`이 현재 어떤 UI 코드에서도 호출되지 않음. `tech-debt.md TD-08` 참조. 해결 전까지 티어 배정/AI 초기화는 비활성 상태.

## Related Decisions

- [ADR-001](001-system-communication-pattern.md) — 직접 호출 vs 시그널 판단 기준
- design/gdd/xp-system.md §3-1, §4-7
- design/gdd/season-manager.md §3-1 step ⑤, §3-4
