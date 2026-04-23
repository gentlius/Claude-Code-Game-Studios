# 루머 채널 (Rumor Channel) — S3 스킬

> **Status**: Approved
> **Sprint**: Sprint 8 (S8-04/05)
> **Skill ID**: S3
> **Prerequisite**: S2 (실시간 뉴스) 해금
> **Owner**: game-designer + gameplay-programmer

---

## 1. Overview

S3 스킬 해금 시 뉴스 이벤트 발생 60틱(게임 15분) 전에 확률적 힌트 메시지가 뉴스 피드에
`[루머]` 태그로 선행 표시된다. 정확도 55% — 45% 확률로 방향이 반전된 잘못된 힌트가 온다.
플레이어는 루머를 맹신할 수 없고, 차트·PER 등 다른 지표와 교차 검증해야 한다.

루머 발화와 동시에 PriceEngine에 **가격 선반영 압력(rumor_delta)**이 주입된다.
루머 방향(stated direction)으로 60틱 동안 미세하게 가격이 선행 이동하여
"소문에 사서 뉴스에 팔아라(Buy the rumor, sell the news)" 전략이 실제로 작동한다.
30% 가짜 루머의 경우 선반영이 잘못된 방향으로 일어나고 뉴스 발동 시 급반전한다 — 설거지 효과.

`NewsEventSystem`이 뉴스 이벤트를 생성하는 시점에 `RUMOR_LEAD_TICKS` 틱 뒤에 해당
이벤트가 실제 발동될 예정임을 알고 있다. 루머는 그 예약 정보를 기반으로 즉시 발화된다.

---

## 2. Player Fantasy

"[루머] 반도체 대형주 악재 예정…?"
다음 틱을 멍하니 기다리던 플레이어가 갑자기 긴장한다.

루머가 뜨자마자 가격이 서서히 오르기 시작한다. 시장도 루머를 믿고 있다.
맞을 수도, 틀릴 수도 있다. 선취매를 할 것인가, 기다릴 것인가.

**55% 정확 루머**: 선취매 → 60틱 동안 가격이 올라준다 → 뉴스 발동 순간 매도 → 이중 수익.
**45% 가짜 루머**: 선취매 → 가격이 올라간다 → 뉴스 발동 순간 악재 → 급락. 설거지당한다.

> **핵심 긴장 (W-24)**: 루머는 인사이더 정보처럼 느껴지지만 55%는 동전 던지기와 거의 같다.
> 진짜 우위는 차트 패턴, PER, 뉴스 이력을 **교차 검증**해야 생긴다.
> "인사이더처럼 맹신하면 실패하고, 분석가처럼 판단하면 살아남는다." — 루머 채널의 핵심 메시지.
> 루머 단독 EV는 거의 0에 수렴하고, 다른 지표와 결합할 때만 양수 EV가 된다.

루머는 더 이상 알림이 아니라 **교차 분석의 출발점**이자 고위험 선행 트레이딩의 트리거다.

---

## 3. Detailed Design

### 3-1. 루머 발화 흐름

```
[뉴스 이벤트 생성]
    │
    ├── NewsEventSystem._schedule_event(event, fire_at_tick)
    │       event.fire_at_tick = current_tick + RUMOR_LEAD_TICKS (60)
    │
    └── S3 해금 여부 확인 (SkillTree.has_rumor_channel())
            │
            ├── 미해금 → 루머 없음 (기존 동작 유지)
            │
            └── 해금 → 즉시 루머 생성
                    │
                    ├── 정확도 롤 (randf() < 0.55)
                    │       ├── 성공 (55%) → 실제 방향 힌트
                    │       └── 실패 (45%) → 방향 반전 힌트
                    │
                    └── on_rumor_hint 시그널 emit
```

### 3-2. 뉴스 피드 표시

루머는 뉴스 피드 카드로 표시되며 일반 뉴스와 시각적으로 구분된다.

```
┌──────────────────────────────────────────┐
│  [루머]  ████████(005930)                │  ← 회색 배경, 이탤릭
│  "대형 호재 소식이 임박한 것으로 알려져"  │
│  ※ 정확도 55% — 교차 확인 권장          │  ← 고정 문구 (상수 참조)
└──────────────────────────────────────────┘
```

- **색상**: 일반 뉴스 흰색 카드 vs 루머 회색(dim) 카드
- **아이콘**: 물음표(?) 아이콘 또는 루머 전용 색상 배지
- **종목명**: 정확도 관계없이 실제 종목 표시 (종목은 항상 맞음)
- **방향 텍스트**: 호재/악재 중 하나. 30% 확률로 반전

### 3-3. 힌트 텍스트 생성

```gdscript
## 호재 루머 (accurate)
"[루머] {종목명} — 긍정적 소식이 임박한 것으로 알려져"

## 악재 루머 (accurate)
"[루머] {종목명} — 부정적 소식이 임박한 것으로 알려져"

## 호재 루머 (반전 — 실제로는 악재)
"[루머] {종목명} — 긍정적 소식이 임박한 것으로 알려져"  ← 동일 텍스트, 플레이어는 모름

## 악재 루머 (반전 — 실제로는 호재)
"[루머] {종목명} — 부정적 소식이 임박한 것으로 알려져"
```

텍스트는 의도적으로 모호하게 작성. "호재 예정" 또는 "악재 예정"이 아닌
"긍정적/부정적 소식이 임박" 표현 사용.

### 3-4. 루머 → 실제 뉴스 연결

60틱 후 실제 뉴스 발동 시:
- 뉴스 카드가 정상 표시 (기존 동작)
- 루머 카드는 피드에서 별도 제거 없음 — 플레이어가 결과 비교 가능
- `_rumor_pressure` 항목이 남아 있으면 PriceEngine에서 즉시 제거 (이벤트 delta로 교체)

---

### 3-5. 가격 선반영 (Price Pre-Reflection)

루머 발화 시 `PriceEngine.apply_rumor_pressure()` 호출 (시그널 경유):

```
루머 발화 (on_rumor_hint emit)
    │
    └── PriceEngine._on_rumor_hint(rumor)
            │
            ├── direction = rumor["stated_direction"]  # +1 (호재), -1 (악재)
            │   ※ stated direction 기준 — 실제 방향이 아닌 루머가 말하는 방향
            │   (가짜 루머 30%는 이 방향이 틀려 있음)
            │
            └── _rumor_pressure[stock_id] = {
                    "delta_per_tick": RUMOR_PRESSURE_STRENGTH × direction,
                    "ticks_remaining": RUMOR_LEAD_TICKS   # 60
                }
```

**틱마다 적용**:
```
# PriceEngine.process_tick() — Step 4-c
if _rumor_pressure.has(stock_id):
    rumor_delta = _rumor_pressure[stock_id]["delta_per_tick"]
    _rumor_pressure[stock_id]["ticks_remaining"] -= 1
    if _rumor_pressure[stock_id]["ticks_remaining"] <= 0:
        _rumor_pressure.erase(stock_id)
else:
    rumor_delta = 0.0

total_delta = pattern_delta + drift_delta + event_delta + player_delta + rumor_delta
```

**중복 루머 처리**: 동일 종목에 60틱 내 두 번째 루머 발화 시 **덮어쓰기** (최신 루머 기준). 누적 금지.

**장 마감 취소**: 장 마감 이벤트 수신 시 해당 종목의 `_rumor_pressure` 항목 삭제.

**설거지 효과 (45% 가짜 루머)**:
```
1~60틱: 루머 방향(호재 표시)으로 가격 +N% 선반영
60틱 시점: 실제 뉴스(악재) event_delta 발동 — 반대 방향 충격
결과: 60틱간의 상승분이 순간적으로 반전 → 급락
```

---

## 4. Formulas

### F1. 루머 정확도 롤

```
is_accurate = (rng.randf() < RUMOR_BASE_ACCURACY)

RUMOR_BASE_ACCURACY = SkillTree.RUMOR_BASE_ACCURACY  # 0.55 (55%) — B-09: 70%에서 하향. 루머 단독 EV 제거.
# 설계 근거: 70% 정확도 + S3(TR2 손절) 조합 시 루머당 EV +1.27% (지배 전략). 55%는 교차 검증 없이 장기 수익 불가.

결과:
  is_accurate = true  → 실제 뉴스 방향 = 루머 방향
  is_accurate = false → 루머 방향 = !실제_방향 (반전)
```

### F2. 루머 선행 시간

```
rumor_fire_tick = event_scheduled_tick - RUMOR_LEAD_TICKS

RUMOR_LEAD_TICKS = SkillTree.RUMOR_LEAD_MINUTES * GameClock.TICKS_PER_GAME_MINUTE
                 = 15 * 4 = 60틱

게임 시간: 15분 선행
실시간:   60틱 × 0.192초/틱 ≈ 11.5초 (1× 속도 기준)
```

### F3. 루머 압력 (Rumor Pressure)

```
delta_per_tick = RUMOR_PRESSURE_STRENGTH × stated_direction

stated_direction = +1  (루머가 호재라고 표시)
                 = -1  (루머가 악재라고 표시)
                 ※ 실제 방향(is_accurate)과 무관 — 시장은 루머 표면을 따른다

total_rumor_price_effect ≈ RUMOR_PRESSURE_STRENGTH × 60  (틱 누적, 복리 근사는 무시)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `RUMOR_PRESSURE_STRENGTH` | float | 0.0002~0.001 | price_engine_config.json | 틱당 루머 압력 크기. 기본값 0.0005 (60틱 ≈ 3% 누적) |
| `stated_direction` | int | ±1 | NewsEventSystem | 루머 카드에 표시된 방향 (실제와 다를 수 있음) |
| `ticks_remaining` | int | 0~60 | PriceEngine | 남은 루머 압력 적용 틱 수 |

**예시 (RUMOR_PRESSURE_STRENGTH = 0.0005, 호재 루머)**:
- 틱당 +0.05% 압력
- 60틱 누적 ≈ +3.0% 가격 상승
- 뉴스 발동(event_delta): MEDIUM 이벤트 +5~8% 추가 (정확 루머) / -5~8% 반전 (가짜 루머)

---

## 5. Edge Cases

| 상황 | 처리 |
|------|------|
| S3 미해금 | 루머 시그널 미발화. 뉴스는 기존대로 동작 |
| 동일 틱에 루머 2건 발생 | 각각 독립 카드로 표시. 순서는 생성 순 |
| RUMOR_LEAD_TICKS 내에 장 마감 | 루머 발화 후 뉴스 발동 전 장 마감 → 루머 카드만 표시되고 뉴스 미발동, 해당 이벤트 취소. `_rumor_pressure` 항목도 즉시 삭제하여 다음 거래일로 가격 압력이 이월되지 않도록 한다. |
| 루머 후 즉시 뉴스 발동 (LEAD_TICKS = 0) | 루머 없이 뉴스만 발동. 가격 선반영도 없음. 튜닝 최솟값 30틱 이하 비권장 |
| 동일 종목 루머 중복 (60틱 내 두 번째 이벤트) | 두 번째 루머로 `_rumor_pressure` **덮어쓰기** (누적 금지). 첫 번째 루머 방향은 버려진다. 누적하면 압력이 2배가 되어 밸런스 파괴. |
| 익스플로잇 — 루머 패턴 학습 후 100% 예측 | 30% 반전은 독립 확률 → 패턴 없음. 장기 통계로만 70% 수렴 |
| 가짜 루머로 인한 설거지 후 상/하한가 클램프 | 선반영(+3%) + 악재 event_delta(-8%)가 겹치면 일일 하한가(-30%)에 걸릴 수 있음. 이는 의도된 동작 — 레버리지 또는 대량 보유 플레이어의 극단 손실 가능. |
| `RUMOR_PRESSURE_STRENGTH` 과도하게 클 때 | 60틱 누적 압력이 ±30% 일일 가격제한폭에 걸릴 수 있음. 상한: `60 × RUMOR_PRESSURE_STRENGTH < DAILY_LIMIT_PCT` → 0.005 미만 유지. 안전 최대값 권장: 0.001 (60틱 6%). |

---

## 6. Dependencies

| 시스템 | 방향 | 내용 |
|--------|------|------|
| `NewsEventSystem` | Hard | 이벤트 스케줄 시점에 루머 발화. `on_rumor_hint` 시그널 추가. 장 마감 시 `_rumor_pressure` 취소 알림 책임. |
| `PriceEngine` | Hard (신규) | `on_rumor_hint` 시그널 구독 → `_on_rumor_hint()` 처리 → `_rumor_pressure` 주입. 장 마감 시 해당 종목 압력 삭제. |
| `SkillTree` | Hard | `has_rumor_channel()` 확인 (이미 구현 ✅), `RUMOR_BASE_ACCURACY`, `RUMOR_LEAD_MINUTES` 상수 |
| `GameClock` | Soft | `TICKS_PER_GAME_MINUTE` 참조 (LEAD_TICKS 계산) |
| 뉴스 피드 UI | Hard | `on_rumor_hint` 시그널 수신 → 루머 카드 생성 |
| `news-events.md` | Soft | 이벤트 스케줄 구조 기준 |
| `news-feed-ui.md` | Soft | 카드 스타일 패턴 기준 |

---

## 7. Tuning Knobs

| 변수 | 위치 | 기본값 | 범위 | 영향 | 위험 |
|------|------|--------|------|------|------|
| `RUMOR_BASE_ACCURACY` | `skill_tree.gd` `@export` | 0.55 | 0.50~0.80 | 루머 신뢰도 (B-09: 0.70→0.55). 0.65+: 교차 검증 없이 양수 EV 재발생 위험. 0.50 = 완전 랜덤. | 0.80+: 지배 전략 재등장 — 밸런스 파괴 |
| `RUMOR_LEAD_MINUTES` | `skill_tree.gd` `@export` | 15 | 7~30 | 선행 시간 | 30+: 과도한 이점 |
| `RUMOR_PRESSURE_STRENGTH` | `price_engine_config.json` | 0.0005 | 0.0002~0.001 | 틱당 루머 가격 압력. 60틱 누적 ≈ 3%. 상한: 0.001 (누적 6%, 일일 제한폭 내). | 0.001+: 루머만으로 상한가 근접 가능 — 밸런스 파괴 |

---

## 8. Acceptance Criteria

| # | 조건 | 판정 방법 |
|---|------|---------|
| AC-01 | S3 미해금 시 루머 카드 미표시 | S2까지만 해금 → 10분 플레이 → 루머 카드 없음 확인 |
| AC-02 | S3 해금 후 뉴스 발동 60틱 전 루머 카드 표시 | S3 해금 → 뉴스 발동 틱 기록 → (발동 틱 - 60)에 루머 카드 확인 |
| AC-03 | 루머 카드가 일반 뉴스 카드와 시각적으로 구분됨 | 루머 카드 회색 배경 + `[루머]` 태그 확인 |
| AC-04 | 장기 실행 시 루머 정확도 약 55% 수렴 | 테스트: 100회 루머 발화 → 정확 건수 45~65건 (B-09: 65~75건에서 변경) |
| AC-05 | 장 마감 전 발화된 루머에 대응하는 뉴스가 미발동 시 이벤트 취소, `_rumor_pressure`도 삭제됨 | 단위 테스트: 장 마감 시뮬레이션 후 pressure 항목 부재 확인 |
| AC-06 | `--export-release` 빌드 성공, SCRIPT ERROR 없음 | QA Lead 빌드 검증 |
| AC-07 | S3 해금 + 루머 발화 후 해당 종목 가격이 루머 방향으로 완만하게 이동함 (60틱 누적 ~3%) | 단위 테스트: 루머 발화 후 60틱 시뮬레이션 → 가격 변화 측정 |
| AC-08 | 가짜 루머(30%) 시나리오에서 선반영(+N%) 후 반대 방향 뉴스 발동 → 순가격 하락 | 단위 테스트: is_accurate=false 루머 + 반전 뉴스 → 뉴스 발동 후 가격이 루머 발화 전보다 낮음 |
| AC-09 | 동일 종목에 중복 루머 발화 시 두 번째 루머로 덮어쓰기 (압력 누적 없음) | 단위 테스트: 두 루머 발화 후 _rumor_pressure 항목이 1개만 존재 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
- 이 기능은 어디서 호출되는가: `NewsEventSystem._schedule_event()` 내부 → `SkillTree.has_rumor_channel()` 체크 → `on_rumor_hint` 시그널 emit

### 호출 경로

**시그널 추가**
- [x] `news_event_system.gd`: `signal on_rumor_hint(rumor: Dictionary)` 선언
  - `rumor` 구조: `{ "stock_id": String, "direction": String, "is_accurate": bool, "text": String }`
  - `is_accurate`는 발화 시점에 결정. **UI에 노출하지 않음**

**루머 발화 로직**
- [x] `news_event_system.gd`: `_emit_rumor_if_eligible()` 메서드로 루머 분기 구현 (이벤트 스케줄 직후 호출)
- [x] `SkillTree.has_rumor_channel()` 체크
- [x] `rng.randf() < RUMOR_BASE_ACCURACY` 정확도 롤
- [x] 방향 반전 처리: `is_accurate == false` 시 방향 텍스트 반전
- [x] 장 마감 이전 `RUMOR_LEAD_TICKS` 이내인지 확인 → 장 마감 후 이벤트면 루머 생략

**뉴스 피드 UI**
- [x] `news_feed.gd` 또는 `trading_screen.gd`: `on_rumor_hint` 시그널 연결
- [x] 루머 카드 생성: 회색 배경, `[루머]` 태그, 모호한 방향 텍스트
- [x] 고정 문구 상수화: `"※ 정확도 %d%% — 교차 확인 권장" % int(RUMOR_BASE_ACCURACY * 100)`  # B-09: RUMOR_BASE_ACCURACY=0.55 → "55%" 자동 반영

**가격 선반영 구현 (신규)**
- [x] `PriceEngine`: `_rumor_pressure: Dictionary` 상태 추가 (`stock_id → {delta_per_tick, ticks_remaining}`)
- [x] `PriceEngine._on_rumor_hint(rumor: Dictionary)`: `on_rumor_hint` 시그널 연결 핸들러. `_rumor_pressure` 주입 (덮어쓰기 방식)
- [x] `PriceEngine.process_tick()` Step 4-c: `rumor_delta` 계산 + `ticks_remaining` 감소 + 0 도달 시 삭제
- [x] `PriceEngine` Step 5 공식 갱신: `total_delta = pattern + drift + event + player + rumor`
- [x] `PriceEngine` F5 거래량 공식 갱신: `tick_energy`에 `|rumor_delta|` 포함
- [x] 장 마감 이벤트 수신 시 `_rumor_pressure` 해당 종목 항목 삭제 (또는 전체 clear)
- [x] `price_engine_config.json`: `RUMOR_PRESSURE_STRENGTH` 추가 (초기값 0.0005)
- [x] `PriceEngine.reset()` 시 `_rumor_pressure.clear()` 포함 확인

### AC → 테스트 매핑
| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_rumor_channel.gd` | `test_no_rumor_without_s3()` |
| AC-02 | E2E 시각 검증 | 루머 카드 표시 시점 (scheduled_tick - RUMOR_LEAD_TICKS) |
| AC-03 | E2E 시각 검증 | 루머 카드 점선 테두리 + 기울임체 구분 |
| AC-04 | `tests/unit/test_rumor_channel.gd` | `test_accuracy_converges_to_70pct()` |
| AC-05 | `tests/unit/test_rumor_channel.gd` | `test_no_rumor_when_event_after_market_close()` |
| AC-07 | `tests/unit/test_rumor_channel.gd` | `test_rumor_pressure_shifts_price_in_stated_direction()` |
| AC-08 | `tests/unit/test_rumor_channel.gd` | `test_fake_rumor_reverses_after_news()` |
| AC-09 | `tests/unit/test_rumor_channel.gd` | `test_duplicate_rumor_overwrites_pressure()` |

### 빌드 검증
- [x] 바이너리 실행 확인: QA Lead 서명 — S8 완료 빌드 (2026-04-17, SCRIPT ERROR 없음)
