# 경험치 시스템 (XP System)

> **Status**: Approved
> **Author**: user + agents
> **Last Updated**: 2026-04-01
> **Implements Pillar**: 체감있는 성장 (Feel the Growth)

## Overview

경험치 시스템은 플레이어의 투자 성과를 XP로 변환하여 장기 성장을 구동하는
Progression 시스템이다. 일일 장 마감 시 수익률(일일 보너스 XP)과 시즌 종료 시
최종 순위와 성과(시즌 보너스 XP)의 2계층으로 경험치를 부여한다. 거래 횟수가 아닌
판단의 품질(수익률, 순위)만이 성장을 결정한다.

누적 XP가 임계값에 도달하면 레벨업하며, 레벨업 시 스킬 포인트를 획득한다. 스킬 포인트는
스킬 트리 시스템에서 분석 도구, 시장 감지, 거래 스킬, 포트폴리오 확장을 해금하는 데
사용된다. XP와 스킬은 시즌 리셋에도 영구 유지된다 (디아블로 패러곤 모델).

## Player Fantasy

시즌 첫 거래. 매수 버튼을 누르고 체결음이 울린다. 포트폴리오에 종목이 추가되고,
실시간 손익이 움직이기 시작한다. 장이 끝나고 일일 정산 화면에서 "수익률 +3.2%
→ 보너스 XP +45"가 빛난다. 내 판단이 맞았다는 보상.

시즌이 끝났다. 최종 순위 3위. "시즌 보너스 XP +800" — 레벨업 알림이 뜬다.
"스킬 포인트 +1". 스킬 트리를 열고 이동평균선을 해금한다. 다음 시즌에는 더
정확한 분석이 가능하다. 시즌은 리셋되지만 나의 실력은 남았다.

필라 "판단이 곧 실력"에 따라, 거래 횟수가 아닌 투자 성과만이 XP를 결정한다.
필라 "체감있는 성장"에 따라, 높은 수익률일수록 더 많은 XP를 받아 빠르게 성장한다.

## Detailed Design

### Core Rules

#### 규칙 1. XP 획득 — 2계층 구조

> **설계 근거**: 거래 횟수 기반 XP(Trade XP)는 스팸 매매를 유발하고 "판단이 곧 실력"
> 필라에 위배되므로 제거됨. 모든 XP는 투자 성과(수익률, 순위)에서만 산출된다.

##### 1-1. 일일 보너스 XP (Daily Bonus XP) — 장 마감 시

당일 수익률 기반. 필라 "판단이 곧 실력" — 좋은 판단에 더 많은 보상.

```
daily_return = (장 마감 총 자산 - 전일 장 마감 총 자산) / 전일 장 마감 총 자산 × 100 (%)
daily_xp = floor(BASE_DAILY_XP × daily_return_multiplier)
```

| 당일 수익률 | daily_return_multiplier |
|------------|----------------------|
| < 0% (손실) | 0.5 (최소 보장) |
| 0% ~ 1% | 1.0 |
| 1% ~ 3% | 1.5 |
| 3% ~ 5% | 2.0 |
| 5%+ | 3.0 (상한) |

- `BASE_DAILY_XP` = 30 (튜닝 가능)
- 거래 0건인 날: 일일 보너스 XP 없음 (활동 조건 — 체결(FILLED) 1건 이상 필요)
- 손실 시에도 최소 XP 부여 — 손실에서 배우는 것도 성장
- 시즌 첫 거래일: 전일 장 마감 데이터 없으므로 `season_start_cash` 대비 산출 (→ Edge Cases: 시즌 첫 거래일 기준)

##### 1-2. 시즌 보너스 XP (Season Bonus XP) — 시즌 종료 시

시즌 최종 성과 기반 일괄 XP. 큰 보상으로 시즌 완주를 장려.

```
season_xp = BASE_SEASON_XP + rank_bonus + return_bonus
```

| 항목 | 공식 | 예시 |
|------|------|------|
| BASE_SEASON_XP | 200 (시즌 완주 보상) | 200 |
| rank_bonus | `RANK_XP_TABLE[final_rank]` | §F2 테이블 참조 (1위: 500 … 11위+: 30) |
| completion_bonus | `20 if (return_pct ≥ 0% AND season_trade_count ≥ MIN_TRADES_FOR_RANK) else 0` | 조건 충족 시 +20 |
| return_bonus | `floor(season_return_pct × RETURN_XP_SCALE)` | +25% → 25 × 10 = 250 |

- `RETURN_XP_SCALE` = 10 (튜닝 가능)
- 음수 수익률 시 return_bonus = 0 (하한)

#### 규칙 2. 레벨업

```
required_xp(level) = BASE_LEVEL_XP × (level ^ LEVEL_EXPONENT)
```

- `BASE_LEVEL_XP` = 100
- `LEVEL_EXPONENT` = 1.5
- 예시: 레벨 1→2: 100, 2→3: 282, 3→4: 519, 5→6: 1,118

레벨업 시:
- 스킬 포인트 +1 획득
- `on_level_up(new_level: int, skill_points: int)` 시그널 발신. `skill_points`는 항상 1.
- **2+ 레벨업 시**: 레벨당 1회씩 순차 발신. 예: 레벨 3→5 = `on_level_up(4, 1)` → `on_level_up(5, 1)` 순서.
- 레벨업 연출 (UI 담당)

#### 규칙 3. 스킬 포인트

- 레벨업 시 1포인트 획득
- 스킬 트리에서 소비 (스킬 트리 GDD에서 정의)
- 미사용 포인트 누적 가능
- 영구 보존 (시즌 리셋 없음)

#### 규칙 4. 시그널 발행 시점

- **`on_xp_gained(amount: int, new_total: int)`**: XP가 추가될 때마다 즉시 발신.
  - 일일 보너스: `on_market_close` 처리 중 1회 발신
  - 시즌 보너스: `on_season_end` 처리 중 1회 발신
  - UI(프로그레션 UI)가 XP 바 애니메이션 트리거로 사용
- **`on_level_up`**: `on_xp_gained` 발신 직후, 레벨 임계값 도달 시 발신 (규칙 2 참조)

### States and Transitions

경험치 시스템은 별도 상태 머신이 없다. 누적 XP와 레벨은 단조 증가하며,
시즌 리셋의 영향을 받지 않는다.

| 데이터 | 시즌 리셋 시 | 영구 보존 |
|--------|-------------|----------|
| 누적 XP | 유지 | ✅ |
| 레벨 | 유지 | ✅ |
| 스킬 포인트 | 유지 | ✅ |
| 해금된 스킬 | 유지 | ✅ |
| 시즌 내 획득 XP 기록 | 리셋 | ❌ (시즌별 기록용) |

### Interactions with Other Systems

| 시스템 | 방향 | 인터페이스 |
|--------|------|-----------|
| 주문 엔진 | → XP | `on_order_filled` — 일일 거래 유무 판정용 (체결 1건 이상 시 일일 보너스 활성화) |
| 포트폴리오 | → XP | `get_return_rate()` → 일일/시즌 수익률 산출 |
| 게임 시계 | → XP | `on_market_close` → 일일 보너스 산출 |
| 시즌 관리 | → XP | `on_season_end` → 시즌 보너스 산출 (※ 시즌 관리 GDD 미설계 — provisional). `final_rank: int` (1-indexed) |
| 스킬 트리 | XP → | `get_available_skill_points()` 조회, `on_level_up` 시그널 |

## Formulas

### F1. 일일 보너스 XP

```
daily_xp = floor(BASE_DAILY_XP × daily_return_multiplier)
```

| 변수 | 기본값 | 범위 | 설명 |
|------|--------|------|------|
| BASE_DAILY_XP | 30 | 10~100 | 일일 기본 XP |
| daily_return_multiplier | 테이블 참조 | 0.5~3.0 | 당일 수익률 구간별 배율 |

daily_return_multiplier 테이블 (Detailed Design 규칙 1-1 참조):
- `< 0%`: 0.5 → `daily_xp = 15`
- `0%~1%`: 1.0 → `daily_xp = 30`
- `1%~3%`: 1.5 → `daily_xp = 45`
- `3%~5%`: 2.0 → `daily_xp = 60`
- `5%+`: 3.0 → `daily_xp = 90`

조건: 당일 체결(FILLED) 1건 이상 필요. 미거래 시 0.

### F2. 시즌 보너스 XP

```
season_xp = BASE_SEASON_XP + rank_bonus + return_bonus + completion_bonus
rank_bonus = RANK_XP_TABLE[final_rank]
return_bonus = floor(max(0, season_return_pct) × RETURN_XP_SCALE)
completion_bonus = 20 if (season_return_pct >= 0.0 AND season_trade_count >= MIN_TRADES_FOR_RANK) else 0
# MIN_TRADES_FOR_RANK = 5 (season-manager.md §4-5 기준)
```

| 변수 | 기본값 | 범위 | 설명 |
|------|--------|------|------|
| BASE_SEASON_XP | 200 | 100~500 | 시즌 완주 기본 보상 |
| RETURN_XP_SCALE | 10 | 5~30 | 수익률 1%당 XP |

RANK_XP_TABLE:

> 상세 규칙은 `design/gdd/season-manager.md §3-4` 참조.

| 순위 | rank_bonus |
|------|-----------|
| 1위 | 500 |
| 2위 | 350 |
| 3위 | 250 |
| 4위 | 180 |
| 5위 | 150 |
| 6위 | 120 |
| 7위 | 100 |
| 8위 | 80 |
| 9위 | 60 |
| 10위 | 50 |
| 11위+ | 30 |

예시: 시즌 3위, 수익률 +25%, 체결 ≥ 5회 → BASE_SEASON_XP(200) + rank_bonus(250) + return_bonus(250) + completion_bonus(20) = **720 XP**

### F3. 레벨업 필요 XP

```
required_xp(level) = floor(BASE_LEVEL_XP × (level ^ LEVEL_EXPONENT))
```

| 변수 | 기본값 | 범위 | 설명 |
|------|--------|------|------|
| BASE_LEVEL_XP | 100 | 50~200 | 레벨업 기본 단위 |
| LEVEL_EXPONENT | 1.5 | 1.2~2.0 | 성장 곡선 기울기 |

레벨업 테이블 (기본값 기준):

| 레벨 | 해당 구간 필요 XP | 필요 누적 XP | 예상 시즌 수 |
|------|------------|-------------|------------|
| 1→2 | 100 | 100 | ~0.1 시즌 |
| 2→3 | 282 | 382 | ~0.2 시즌 |
| 3→4 | 519 | 901 | ~0.6 시즌 |
| 4→5 | 800 | 1,701 | ~1.1 시즌 |
| 5→6 | 1,118 | 2,819 | ~1.8 시즌 |
| 6→7 | 1,469 | 4,288 | ~2.7 시즌 |
| 7→8 | 1,852 | 6,140 | ~3.8 시즌 |
| 8→9 | 2,262 | 8,402 | ~5.3 시즌 |
| 9→10 | 2,700 | 11,102 | ~6.9 시즌 |

> **산출 기준**: `floor(100 × level^1.5)`. 예상 시즌 수는 시즌 평균 ~1,600 XP
> (경쟁 플레이어 기준: 3위, 수익률 1~3%) 가정. 하위 플레이어는 시즌당 ~550 XP.

### F4. 스킬 포인트

```
total_skill_points = current_level - 1
available_skill_points = total_skill_points - spent_skill_points
```

시즌 1회 평균 XP 추정 (20거래일, 3위 가정):
- 일일 보너스: 20일 × 45 (평균 multiplier 1.5) = 900
- 시즌 보너스: 200 + 250(3위) + 250(+25%) = 700
- **합계: ~1,600 XP / 시즌** → 약 2시즌에 레벨 5 도달 (스킬 포인트 4개, T1 전체 해금 가능)

### F5. 누적 XP 조회

```
get_cumulative_xp_for_level(target_level) = Σ required_xp(lv) for lv = 1 to (target_level - 1)
```

레벨업 판정: `total_xp >= get_cumulative_xp_for_level(current_level + 1)` 일 때 레벨업 발생.

## Edge Cases

| 상황 | 처리 |
|------|------|
| 장 중 체결(FILLED) 0건 | 일일 보너스 XP = 0 (활동 조건 미충족) |
| 시즌 중도 이탈 (시즌 완주 안 함) | 시즌 보너스 XP = 0. 일일 XP는 이미 부여됨 |
| 시즌 보너스로 2+ 레벨업 | 순차적으로 각 레벨마다 스킬 포인트 +1 부여 |
| 수익률 정확히 0% | daily_return_multiplier = 1.0 (0%~1% 구간) |
| 수익률 -100% (전액 손실) | daily_multiplier = 0.5, return_bonus = 0 |
| 최대 레벨 | 제한 없음. XP와 레벨은 무한 성장 (스킬 포인트 잉여 누적) |
| 저장 데이터 손상 | XP/레벨이 음수가 되면 0으로 클램프 |
| 스팸 매매 | XP에 영향 없음. 거래 횟수는 XP 산출에 사용되지 않음 |
| 시즌 첫 거래일 기준 | 전일 장 마감 자산이 없으므로 season_start_cash를 전일 자산으로 대체하여 daily_return을 산출. 첫 시즌: 1,000,000원. 이후 시즌: 이월된 season_start_cash. |

## Dependencies

### 상위 의존 (이 시스템이 필요로 하는 것)

| 시스템 | 의존 유형 | 데이터 |
|--------|----------|--------|
| 주문 엔진 | Soft | `on_order_filled` — 일일 거래 유무 판정용 (체결 1건 이상 시 일일 보너스 활성화) |
| 포트폴리오 관리 | Hard | `get_return_rate()` → 일일/시즌 수익률 |
| 게임 시계 | Hard | `on_market_close`, `on_season_end` 시그널 |
| 시즌/대회 관리 | Soft | `final_rank: int` (1-indexed, 미설계 — MVP에서는 하드코딩 가능) |

### 하위 의존 (이 시스템에 의존하는 것)

| 시스템 | 의존 유형 | 데이터 |
|--------|----------|--------|
| 스킬 트리 | Hard | `get_available_skill_points()`, `on_level_up(new_level: int, skill_points: int)` 시그널 |
| UI (프로그레션 UI) | Soft | `get_total_xp()`, `get_current_level()`, `get_xp_progress()`, `get_cumulative_xp_for_level()`, `on_xp_gained(amount: int, new_total: int)` 시그널, `on_level_up(new_level: int, skill_points: int)` 시그널 (레벨업 배너 트리거) |

## Tuning Knobs

| 변수 | 기본값 | 범위 | 영향 | 위험 |
|------|--------|------|------|------|
| BASE_DAILY_XP | 30 | 10~100 | 일일 플레이 보상 | 너무 높으면 시즌 보너스 무의미 |
| BASE_SEASON_XP | 200 | 100~500 | 시즌 완주 동기 | 너무 낮으면 시즌 중도 이탈 |
| RETURN_XP_SCALE | 10 | 5~30 | 수익률 대비 XP | 너무 높으면 고수만 빠른 성장 |
| RANK_XP_TABLE | [500,350,250,150,50] | — | 순위 경쟁 동기 | 1위와 꼴찌 격차가 너무 크면 좌절감 |
| BASE_LEVEL_XP | 100 | 50~200 | 초반 레벨업 속도 | 너무 낮으면 의미 없음 |
| LEVEL_EXPONENT | 1.5 | 1.2~2.0 | 후반 성장 속도 | 너무 높으면 후반 정체감 |
| daily_return_multiplier 테이블 | 규칙 1-1 참조 | — | 수익률별 보상 차이 | 손실 배율이 0이면 손실 시 좌절 |

## Acceptance Criteria

| # | 기준 | 검증 방법 |
|---|------|----------|
| AC-1 | 거래 체결 자체는 XP를 부여하지 않음 | 유닛 테스트: 체결 전후 XP 변화 == 0 |
| AC-2 | 장 마감 시 당일 수익률에 따른 일일 보너스 XP 부여 | 유닛 테스트: 각 수익률 구간별 expected XP 검증 |
| AC-3 | 체결(FILLED) 0건인 날은 일일 보너스 XP = 0 | 유닛 테스트 |
| AC-4 | 시즌 종료 시 순위 + 수익률 기반 시즌 보너스 XP 부여 | 유닛 테스트: 순위별, 수익률별 expected XP |
| AC-5 | 누적 XP가 임계값 도달 시 레벨업 + 스킬 포인트 +1 | 유닛 테스트: XP 부여 후 레벨/포인트 검증 |
| AC-6 | 한 번에 2+ 레벨업 시 각 레벨마다 포인트 부여 | 유닛 테스트: 대량 XP 부여 후 포인트 == 레벨-1 |
| AC-7 | XP/레벨/스킬 포인트가 시즌 리셋 시 영구 유지 | 시즌 리셋 전후 값 비교 테스트 |
| AC-8 | `on_level_up` 시그널이 레벨업 시 정확히 1회 발신 | 시그널 카운트 테스트 |
| AC-9 | 시즌 1회 평균 XP가 ~1,400~1,800 범위 (경쟁 플레이어 기준, 20거래일, 수익률 1~3%, 3위 가정). 하위 플레이어 기준 ~550 XP 이상. | 시뮬레이션 테스트로 밸런스 확인 |

## Open Questions

- ~~시즌 관리 시스템과의 인터페이스~~ → 시즌 관리 GDD 설계 시 확정 (provisional: `on_season_end` + `final_rank: int, 1-indexed`)
- ~~거래 XP 스팸 문제~~ → 디자인 리뷰에서 거래 XP 제거로 해결 (2026-04-01). 근거: "판단이 곧 실력" 필라 우선, 거래 횟수 보상은 스팸 유발

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 기능 | 진입점 |
|------|--------|
| 시즌 XP 지급 | `season_manager.gd._on_season_end()` → `XpSystem.grant_season_bonus(rank, is_free_market, return_pct, trade_count)` |
| 주문 체결 XP | `order_engine.gd.on_order_filled` 시그널 → `xp_system.gd._on_order_filled()` |
| XP 바 갱신 | `XpSystem.on_xp_gained` 시그널 → `xp_bar.gd._on_xp_gained()` |

### 호출 경로

- [x] `XpSystem.grant_season_bonus(rank, is_free_market, return_pct, trade_count)` 존재
- [x] `XpSystem.get_current_level() -> int` 존재
- [x] `XpSystem.get_xp_progress() -> float` 존재
- [x] `XpSystem.get_available_skill_points() -> int` 존재
- [x] `XpSystem.on_xp_gained(amount, source)` 시그널 존재
- [x] `XpSystem.on_level_up(new_level, skill_points)` 시그널 존재
- [x] `XpSystem.reset_for_testing()` 존재

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 | 상태 |
|----|------------|------------|------|
| 시즌 XP 지급 공식 | `tests/unit/test_xp_system.gd` | `test_season_bonus_xp_*` | ✅ |
| 레벨업 임계값 | `tests/unit/test_xp_system.gd` | `test_level_up_at_threshold()` | ✅ |
| 프리마켓 XP 감소 | `tests/unit/test_xp_system.gd` | `test_free_market_xp_penalty()` | ✅ |
| API 계약 | `tests/unit/test_api_contracts.gd` | `test_xp_system_api()` | ✅ |

### 빌드 검증

- [ ] 바이너리 실행 확인: QA Lead 서명 _______
