# ADR-015: SaveSystem 저장 트리거 타이밍

| Field | Value |
|-------|-------|
| **Status** | Revised (2026-04-09) |
| **Original Date** | 2026-04-07 |
| **Revised Date** | 2026-04-09 |
| **Decision Maker** | user + lead-programmer |
| **Sprint** | Sprint 6 (S6 버그수정) |
| **Relates To** | src/core/save_system.gd, src/core/game_clock.gd, src/gameplay/ai_competitor.gd, src/gameplay/news_event_system.gd, ADR-009, ADR-010 |

## Context

초기 설계(2026-04-07)는 `MARKET_CLOSED` 시점에 저장했다.
이후 세이브/로드 버그 5건이 모두 같은 근본 원인에서 파생됐다:

> **"MARKET_CLOSED에 저장하지만, 로드 시엔 PRE_MARKET 상태로 복원해야 한다"는 임피던스 불일치**

### 파생 버그 목록

| 버그 | 임시 패치 | 근본 원인 |
|------|----------|----------|
| 로드 후 `market_index` 1000으로 리셋 | `initialize_for_load()` 역산 보정 | MARKET_CLOSED day N 저장 → PRE_MARKET day N+1 로드 |
| 리그 순위 불일치 (PRE_MARKET) | `_interpolate_return()` PRE_MARKET 분기 | `AiCompetitor.current_day + 1` 보정과 표시값 불일치 |
| AI `get_save_data()` day+1 보정 | `MARKET_CLOSED` 상태 체크 분기 | GameClock과 동기화 위해 동일한 +1 필요 |
| GameClock `get_save_data()` day+1 보정 | 동일 | — |
| 뉴스 "오늘의 시장 전망" 복구 안 됨 | `_deliver_pre_market_news()` 버퍼 clear 제거 | `_generate_overnight_disclosures()`가 저장 **이후** 실행됨 |

5건 중 4건이 +1 보정 또는 그 부작용, 1건은 overnight buffer가 저장 이후에 채워지는 순서 문제.

## Decision (개정)

**저장 시점을 `MARKET_CLOSED` → `PRE_MARKET (prev_state == DAY_TRANSITION)`으로 이동.**

### 새 트리거 순서

```
DAY_TRANSITION 진입
  └─ on_day_transition 발생
       └─ NewsEventSystem._on_day_transition()
              └─ _generate_overnight_disclosures()   ← 공시 버퍼 추가

PRE_MARKET 진입 (_advance_to_next_day()에서 _current_day 이미 +1)
  └─ on_market_state_changed(PRE_MARKET, DAY_TRANSITION) 발생
       ├─ [1] NewsEventSystem — _deliver_pre_market_news()
       │         overnight 버퍼 전달 + PriceEngine push
       │         (버퍼는 clear하지 않음 — 저장 직전까지 보존)
       └─ [2] SaveSystem — _on_auto_save_trigger()    ← ★ 저장
                overnight 버퍼 포함된 상태로 저장
```

신호 핸들러 실행 순서는 project.godot autoload 등록 순서에 의해 보장된다:
- NewsEventSystem (line 21) → 먼저 등록 → PRE_MARKET 핸들러 먼저 실행
- SaveSystem (line 28) → 나중에 등록 → 항상 deliver 완료 후 저장

### 저장 트리거 목록 (개정)

| 트리거 | 시점 | 조건 |
|--------|------|------|
| **일별 자동 저장** | `on_market_state_changed(PRE_MARKET, DAY_TRANSITION)` | 항상 |
| **시즌 종료 저장** | `SeasonManager.on_season_ended` 완료 후 | 항상 |
| **신규 게임 초기 저장** | `MainScreen._ready()` 완료 후 | `_pending_initial_save` 플래그 |

### 제거된 코드

| 파일 | 제거 내용 |
|------|----------|
| `game_clock.gd` `get_save_data()` | `MARKET_CLOSED` 분기 (`current_day + 1` 보정) |
| `ai_competitor.gd` `get_save_data()` | `MARKET_CLOSED` 분기 (`saved_day + 1` 보정) |
| `save_system.gd` | `GameClock.on_market_close.connect(...)` |
| `news_event_system.gd` | `_deliver_pre_market_news()` 마지막 `_overnight_buffer.clear()` |

### 중복 저장 방지 (변경 없음)

```gdscript
var _save_pending: bool = false

func save_slot(id: int) -> bool:
    if _save_pending:
        return false
    _save_pending = true
    # ...
    _save_pending = false
    return true
```

`SeasonManager.on_season_ended`와 `PRE_MARKET` 트리거가 동시에 올 수 없다
(SEASON_END → `on_new_season_requested` → `start_season()` → PRE_MARKET은
`prev_state == SEASON_END`이므로 일별 저장 조건 불충족).

## Alternatives Considered

### A (기각): MARKET_CLOSED 저장 + 보정 코드 유지

임시 패치를 계속 쌓는 방식. 버그 5건을 각각 수정했으나 근본 원인은 미해결.
보정 코드가 늘어날수록 상태 간 동기화 오류 위험이 증가한다.

### B (채택): PRE_MARKET 저장

보정 코드 전량 제거. 저장 시점과 복원 시점이 같은 상태(PRE_MARKET).
overnight 버퍼가 이미 완성된 상태를 저장하므로 별도 처리 불필요.

## Consequences

### 긍정적

- `game_clock.gd`, `ai_competitor.gd` 보정 코드 제거 → 단순화
- 뉴스 overnight buffer가 저장 시점에 항상 완전한 상태
- 순위 불일치 버그 구조적 해소 (PRE_MARKET 분기 로직은 정상 게임플레이를 위해 유지)
- 저장 파일 상태 = 로드 후 상태 (PRE_MARKET) — 임피던스 제로

### 부정적

- SavingOverlay가 PRE_MARKET 화면에서 표시됨 (정산 화면 대신)
  → 플레이어가 "장 시작" 버튼을 보는 시점에 짧게 나타남. 허용 가능한 UX.
- MARKET_CLOSED ~ PRE_MARKET 사이 앱 강제 종료 시 당일 저장 없음
  → 이전과 동일 (MARKET_CLOSED 저장도 정산 확인 후이므로 동일한 리스크)

## Validation Criteria

- **AC-01**: 로드 후 뉴스 "오늘의 시장 전망"이 복원된다
- **AC-02**: 로드 후 `market_index`가 보정 코드 없이 정상 복원된다
- **AC-03**: 로드 후 PRE_MARKET 리그 순위-수익률 정합성 유지
- **AC-04**: 시즌 종료 저장과 일별 저장이 중복 실행되지 않는다

## Related Decisions

- [ADR-009](009-multi-slot-save-architecture.md) — 저장 파일 구조
- [ADR-010](010-game-entry-flow-ownership.md) — 신규 게임 `_pending_initial_save` 플래그
- [ADR-011](011-saving-overlay-canvas-layer.md) — `_save_pending`이 SavingOverlay 트리거
