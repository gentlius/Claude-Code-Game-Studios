# 게임 시계 (Game Clock)

> **Status**: In Design
> **Author**: user + game-designer
> **Last Updated**: 2026-03-25
> **Implements Pillar**: 짧고 굵게 (Quick & Punchy)

## Overview

게임 시계는 시드머니의 시간 흐름을 제어하는 Foundation 시스템이다. 실제 주식시장의
거래일/주/시즌 구조를 게임에 맞게 압축하여, 6.5시간의 실제 거래일을 약 5분으로,
1주(5거래일)를 약 25-30분으로 제공한다. 가격 엔진과 뉴스 시스템은 이 시계의 틱과
상태 변화 시그널을 구독하여 작동하며, 플레이어는 시계를 직접 조작하지 않고
자연스럽게 흐르는 시장 시간 속에서 매매 판단을 내린다. 향후 멀티플레이어 확장을
위해 GameClock 인터페이스를 추상화하여, LocalClock(싱글)과 ServerClock(멀티)을
교체 가능하도록 설계한다.

## Player Fantasy

플레이어는 시계를 의식하지 않는다. 대신 "시장이 살아서 움직이고 있다"는 긴장감을
느낀다. 장이 열리면 가격이 움직이기 시작하고, 뉴스가 쏟아지고, 시간이 흐르면서
기회가 생겼다 사라진다. 장 마감이 다가오면 "지금 사야 하나, 내일까지 기다려야
하나"의 시간 압박이 판단의 무게를 더한다.

게임 필라 "짧고 굵게"에 따라 지루한 대기 시간은 없으며, 주말/야간 같은 비거래
시간은 즉시 건너뛴다. 시계가 만드는 리듬 — 장 시작의 기대감, 장중의 긴장감,
장 마감의 결산감 — 이 하루하루의 거래에 감정적 굴곡을 부여한다.

## Detailed Design

### Core Rules

1. **시간 계층 구조**: 게임 시간은 4단계 계층으로 구성된다.
   - **틱 (Tick)**: 최소 시간 단위. 1틱 = 게임 내 1분.
     가격 엔진이 틱마다 가격을 갱신한다.
   - **거래일 (Trading Day)**: 390틱 = 6.5시간 (09:00~15:30).
     실제 소요시간 약 5분.
   - **주 (Week)**: 5거래일. 실제 소요시간 약 25분.
   - **시즌 (Season)**: N주 (기본 4주). 실제 소요시간 약 100분.

2. **틱 속도**: 기본 1x에서 1틱 = 실시간 약 0.77초
   (390틱 ÷ 300초 = 1.3 ticks/sec).
   - 1x: 1틱 / 0.77초 (기본)
   - 2x: 1틱 / 0.385초
   - 4x: 1틱 / 0.19초

3. **일시정지**: 플레이어는 장중 언제든 일시정지 가능.
   일시정지 중에도 차트/뉴스 확인 및 주문 입력 가능.
   주문은 재개 후 다음 틱에 처리된다.

4. **비거래 시간 스킵**: 장 마감(15:30) 후, 다음 거래일 장 시작(09:00)
   전까지의 시간은 자동 스킵. 스킵 전에 일일 정산 리포트 표시.

5. **주말 스킵**: 금요일 장 마감 후, 월요일 장 시작까지 자동 스킵.
   스킵 전에 주간 리포트 표시.

6. **틱 처리 순서**: 각 틱은 다음 순서로 처리된다.
   1) 뉴스/이벤트 시스템 — 이번 틱에 발생할 이벤트 평가 및 적용
   2) 가격 엔진 — 이벤트 반영 후 가격 갱신
   3) 주문 처리 엔진 — 갱신된 가격 기준으로 주문 체결
   이 순서가 보장되지 않으면 "뉴스 발생 전 가격에 주문 체결" 같은 비정상 동작 발생.

### States and Transitions

| State | Entry Condition | Exit Condition | Behavior |
|-------|----------------|----------------|----------|
| **PRE_MARKET** | 거래일 시작 (틱 0) | 플레이어 확인 버튼 클릭 | 전일 뉴스 요약 표시. 예약 주문 입력 가능 (장 시작 첫 틱에 체결). 플레이어가 확인하면 MARKET_OPEN 전환 |
| **MARKET_OPEN** | PRE_MARKET 종료 | 장 마감 시각 도달 (틱 390) | 가격 실시간 변동. 주문 즉시 체결. 뉴스 이벤트 발생. 일시정지/배속 가능 |
| **MARKET_CLOSED** | 장 마감 시각 도달 | 일일 정산 리포트 확인 후 | 신규 주문 불가. 일일 수익률 정산. 순위 갱신 |
| **DAY_TRANSITION** | 리포트 확인 | 다음 거래일의 PRE_MARKET | 비거래 시간 스킵. 야간 뉴스 이벤트 생성 (다음 날 공개) |
| **WEEK_END** | 금요일 MARKET_CLOSED | 주간 리포트 확인 후 | 주간 리포트 표시. 다음 주 시장 테마 힌트 |
| **SEASON_END** | 마지막 주의 WEEK_END | 시즌 결과 확인 후 → PRE_MARKET (새 시즌 첫 거래일) | 최종 순위 확정. 보상 지급. 스킬 트리 경험치 정산. 시즌 결과 확인 시 `on_season_start` 발행 후 새 시즌의 PRE_MARKET 진입 |

**PAUSED (서브상태)**: MARKET_OPEN 중에만 진입 가능한 오버레이 상태.
시간 정지. UI 조작/주문 입력 가능. 재개 시 MARKET_OPEN으로 복귀하며
다음 틱부터 처리 재개. MARKET_OPEN 외의 상태에서는 일시정지 불가.

### Signal Catalog

```
on_tick(tick_number: int, day: int, week: int)
    # 매 틱 발행. 모든 구독 시스템이 틱 처리 수행

on_market_state_changed(new_state: MarketState, prev_state: MarketState)
    # 시장 상태 전환 시 발행. MarketState = PRE_MARKET | MARKET_OPEN | PAUSED
    #   | MARKET_CLOSED | DAY_TRANSITION | WEEK_END | SEASON_END
    # 구독자는 new_state로 자체 상태 매핑 수행
    # PRE_MARKET 진입도 이 시그널로 전달됨 (별도 on_pre_market 없음)

on_season_start()       # 시즌 최초 시작 시 (시즌 초기화용). SEASON_END 후 새 시즌 진입 시점
on_market_open()        # MARKET_OPEN 진입 시
on_market_close()       # MARKET_CLOSED 진입 시
on_day_transition()     # DAY_TRANSITION 진입 시
on_week_end()           # WEEK_END 진입 시
on_season_end()         # SEASON_END 진입 시
```

**`on_market_state_changed`로 커버되는 전환** (별도 편의 시그널 없음):
- PAUSED 진입/퇴출: `on_market_state_changed(PAUSED, MARKET_OPEN)` / `on_market_state_changed(MARKET_OPEN, PAUSED)`
- PRE_MARKET 진입: `on_market_state_changed(PRE_MARKET, DAY_TRANSITION)` 또는 `on_market_state_changed(PRE_MARKET, SEASON_START)`

배속 정보는 시그널이 아닌 `get_speed_multiplier(): float` 조회로 제공.

### Public API

```
get_market_state(): MarketState      # 현재 시장 상태
get_current_time(): GameTime         # 현재 게임 시각 (틱/일/주)
get_current_tick(): int              # 현재 틱 번호 (0~390). 가격 엔진 히스토리 인덱싱용
get_day_progress(): float            # 거래일 진행률 (0.0~1.0)
get_speed_multiplier(): float        # 현재 배속 (1/2/4)
set_speed(multiplier: float)         # 배속 변경 요청
```

**이벤트 감속 소유권**: 뉴스/이벤트 시스템이 `game_clock.set_speed(1)` 메서드를
호출하여 감속을 요청한다. 게임 시계는 `set_speed(multiplier)` API를 제공하며,
`auto_slow_on_event = false`일 때 뉴스 시스템은 호출하지 않는다.

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **가격 엔진** | 하위 → 구독 | `on_tick(tick_number, day, week)` 시그널 구독. 틱마다 가격 갱신. `get_market_state()` 호출로 장중 여부 확인 |
| **뉴스/이벤트 시스템** | 하위 → 구독 | `on_tick` 구독. `on_market_open`, `on_market_close`, `on_day_transition` 시그널로 이벤트 타이밍 결정 |
| **주문 처리 엔진** | 하위 → 구독+조회 | `on_market_open`, `on_market_close` 시그널 구독 (상태 전환). `on_tick` 구독 (지정가 체결 체크). `get_market_state()` 호출 (주문 접수 시 상태 확인) |
| **시즌/대회 관리** | 하위 → 구독 | `on_week_end`, `on_season_end` 시그널 구독. 시즌 진행 상태 추적 |
| **트레이딩 스크린 (UI)** | 하위 → 조회 | `get_current_time()`, `get_market_state()`, `get_day_progress()` 호출. 시계/타임바 표시 |
| **차트 렌더러** | 하위 → 구독 | `on_market_state_changed` 시그널로 차트 상태(LIVE/PAUSED/STATIC) 전환. 배속 정보로 렌더 주기 결정 |
| **뉴스 피드 UI** | 하위 → 구독 | `on_market_state_changed` 시그널로 피드 상태(ACTIVE/FROZEN/PRE_MARKET_MODE) 전환. 피드 초기화 타이밍 결정 |
| **포트폴리오 UI** | 하위 → 구독 | `on_tick` 구독 (보유 종목 실시간 평가 갱신). `on_market_state_changed` 시그널로 SETTLEMENT 상태 전환 |

## Formulas

### 틱 간격 계산 (Tick Interval)

```
tick_interval_sec = base_tick_interval / speed_multiplier
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| base_tick_interval | float | 0.5-2.0 | config | 1x 속도에서 1틱의 실시간 초 (기본 0.77) |
| speed_multiplier | float | {1, 2, 4} | player input | 배속 설정 |
| tick_interval_sec | float | 0.19-2.0 | calculated | 실제 틱 간격 (초) |

**Expected output range**: 0.19초 (4x) ~ 0.77초 (1x)

### 거래일 진행률 (Day Progress)

```
day_progress = current_tick / ticks_per_day
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| current_tick | int | 0-390 | game clock | 현재 틱 번호 |
| ticks_per_day | int | 390 | config | 거래일 총 틱 수 |
| day_progress | float | 0.0-1.0 | calculated | 거래일 진행률 (UI 타임바용) |

### 시즌 진행률 (Season Progress)

```
season_progress = (completed_days + day_progress) / total_season_days
total_season_days = weeks_per_season * 5
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| completed_days | int | 0-N | game clock | 이번 시즌에서 완료된 거래일 수 |
| day_progress | float | 0.0-1.0 | calculated | 현재 거래일 진행률 |
| weeks_per_season | int | 2-12 | config | 시즌 당 주 수 (기본 4) |
| total_season_days | int | 10-60 | calculated | 시즌 총 거래일 수 |
| season_progress | float | 0.0-1.0 | calculated | 시즌 진행률 |

---

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 4x 배속 중 뉴스 이벤트 발생 | 자동으로 1x로 감속 + 알림 표시 | 중요 판단 기회를 놓치지 않도록. 필라 "판단이 곧 실력" |
| 일시정지 중 주문 입력 후 재개 | 재개 후 첫 번째 틱에서 주문 처리 | 일시정지는 분석 시간이지 치트가 아님 |
| 시즌 마지막 금요일 장 마감 | MARKET_CLOSED → WEEK_END + SEASON_END 동시 발생. 주간+시즌 합산 리포트 표시 | 시즌은 항상 주 단위로 정렬. 금요일에 종료 |
| 플레이어가 리포트 확인 안 하고 방치 | 무한 대기. 리포트 확인 버튼 클릭 시에만 진행 | 자동 진행하면 정보를 놓칠 수 있음 |
| PRE_MARKET에서 일시정지 시도 | PRE_MARKET은 시간이 흐르지 않으므로 일시정지 불필요. 플레이어는 확인 버튼 클릭 전까지 자유롭게 뉴스 확인 가능 | 일시정지는 MARKET_OPEN 서브상태 |
| 시즌 중간에 게임 종료 | 현재 틱/일/주 상태를 세이브. 재개 시 정확히 같은 지점에서 계속 | 진행 상태 보존 |
| 배속 전환 중 틱 누락 | 배속 전환은 다음 틱 시작 시점에 적용. 현재 틱은 기존 속도로 완료 | 틱 무결성 보장 |

---

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| 가격 엔진 | 가격 엔진이 이 시스템에 의존 | 틱 시그널로 가격 갱신 트리거. **Hard** — 틱 없으면 가격 변동 없음 |
| 뉴스/이벤트 시스템 | 뉴스가 이 시스템에 의존 | 틱/상태 시그널로 이벤트 타이밍 결정. **Hard** |
| 주문 처리 엔진 | 주문이 이 시스템에 의존 | 시장 상태 조회로 체결 가능 여부 판단. **Hard** |
| 시즌/대회 관리 | 시즌이 이 시스템에 의존 | 주/시즌 종료 시그널 구독. **Hard** |
| 트레이딩 스크린 (UI) | UI가 이 시스템에 의존 | 시간/진행률 조회로 타임바 표시. **Soft** |
| 차트 렌더러 | 차트가 이 시스템에 의존 | `on_market_state_changed` 시그널로 차트 상태 전환. **Soft** |
| 뉴스 피드 UI | 피드가 이 시스템에 의존 | `on_market_state_changed` 시그널로 피드 상태 전환. **Soft** |
| 포트폴리오 UI | UI가 이 시스템에 의존 | `on_tick` 구독 (실시간 평가 갱신). `on_market_state_changed` 시그널로 SETTLEMENT 전환. **Soft** |

모든 의존 방향이 단방향(하위 → 게임 시계)이다. 게임 시계는 어떤 시스템에도
의존하지 않는 Foundation 시스템이다. 단, 뉴스/이벤트 시스템은 이벤트 감속 시
`set_speed(1)` 메서드를 호출하므로 이 한 가지에 한해 역방향 호출이 존재한다.

---

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `base_tick_interval` | 0.77초 | 0.3-2.0초 | 거래일 길어짐 → 여유로운 분석 | 거래일 짧아짐 → 긴박한 판단 |
| `ticks_per_day` | 390 | 60-780 | 하루에 더 많은 가격 변동 포인트 | 하루가 거칠게 움직임 (틱당 변동 커짐) |
| `weeks_per_season` | 4 | 2-12 | 시즌 길어짐 → 장기 전략 가능 | 시즌 짧아짐 → 빠른 순환 |
| `speed_options` | [1, 2, 4] | [1, 2, 4, 8] | 더 빠른 스킵 가능 | — |
| `auto_slow_on_event` | true | bool | 이벤트 시 자동 감속 (판단 보호) | 이벤트 놓칠 수 있음 (고수용) |
| `days_per_week` | 5 | 5 (고정) | — | — (현실 시장 구조 반영, 변경 불가) |

---

## Acceptance Criteria

- [ ] 거래일 1일이 1x 속도에서 4.5~5.5분 내에 완료된다
- [ ] 1x → 2x → 4x 배속 전환이 즉시 적용되며 시각적으로 구분된다
- [ ] 일시정지 중 차트/뉴스 확인 및 주문 입력이 가능하다
- [ ] 장 마감 후 일일 정산 리포트가 표시되고, 확인 전까지 다음 날로 진행하지 않는다
- [ ] 주말 스킵 시 주간 리포트가 표시된다
- [ ] 시즌 종료 시 WEEK_END + SEASON_END 합산 리포트가 표시된다
- [ ] 4x 배속 중 뉴스 이벤트 발생 시 자동으로 1x로 감속된다
- [ ] `get_market_state()`가 정확한 현재 상태를 반환한다
- [ ] 틱 시그널이 모든 구독 시스템(가격 엔진, 뉴스)에 정확히 전달된다
- [ ] 배속 전환 시 틱 누락이 발생하지 않는다
- [ ] 성능: 틱 처리가 16ms (60fps) 이내에 완료된다
- [ ] `on_season_start` 시그널이 새 시즌 진입 시 정확히 1회 발행된다
- [ ] `get_current_tick()`이 MARKET_OPEN 상태에서 0~390 범위의 정확한 값을 반환한다
- [ ] SEASON_END 확인 후 새 시즌의 PRE_MARKET으로 정상 전환된다
- [ ] 모든 시간 관련 값은 config 파일에서 로드된다 (하드코딩 금지)

---

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| 8x 배속 옵션이 필요한가? (스킬 해금 후 고수용) | game-designer | 스킬 트리 GDD 작성 시 | 미정 |
| 멀티플레이어 전환 시 ServerClock 인터페이스 상세 | network-programmer | 멀티 확장 시점 | 향후 |
| PRE_MARKET 상태의 지속 시간 | game-designer | — | 해결: 플레이어 확인 버튼 클릭까지 대기 방식으로 결정 |
