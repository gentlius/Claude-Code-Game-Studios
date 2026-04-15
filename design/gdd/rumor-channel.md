# 루머 채널 (Rumor Channel) — S3 스킬

> **Status**: In Review
> **Sprint**: Sprint 8 (S8-04/05)
> **Skill ID**: S3
> **Prerequisite**: S2 (실시간 뉴스) 해금
> **Owner**: game-designer + gameplay-programmer

---

## 1. Overview

S3 스킬 해금 시 뉴스 이벤트 발생 60틱(게임 15분) 전에 확률적 힌트 메시지가 뉴스 피드에
`[루머]` 태그로 선행 표시된다. 정확도 70% — 30% 확률로 방향이 반전된 잘못된 힌트가 온다.
플레이어는 루머를 맹신할 수 없고, 차트·PER 등 다른 지표와 교차 검증해야 한다.

`NewsEventSystem`이 뉴스 이벤트를 생성하는 시점에 `RUMOR_LEAD_TICKS` 틱 뒤에 해당
이벤트가 실제 발동될 예정임을 알고 있다. 루머는 그 예약 정보를 기반으로 즉시 발화된다.

---

## 2. Player Fantasy

"[루머] 반도체 대형주 악재 예정…?"
다음 틱을 멍하니 기다리던 플레이어가 갑자기 긴장한다. 맞을 수도, 틀릴 수도 있다.
차트를 다시 보고, 포지션을 점검한다. 정보가 확실하지 않아서 오히려 더 재미있는 순간.
정확도 70%를 체득한 플레이어만 루머를 유효하게 활용할 수 있다.

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
                    ├── 정확도 롤 (randf() < 0.70)
                    │       ├── 성공 (70%) → 실제 방향 힌트
                    │       └── 실패 (30%) → 방향 반전 힌트
                    │
                    └── on_rumor_hint 시그널 emit
```

### 3-2. 뉴스 피드 표시

루머는 뉴스 피드 카드로 표시되며 일반 뉴스와 시각적으로 구분된다.

```
┌──────────────────────────────────────────┐
│  [루머]  ████████(005930)                │  ← 회색 배경, 이탤릭
│  "대형 호재 소식이 임박한 것으로 알려져"  │
│  ※ 정확도 70% — 교차 확인 권장          │  ← 고정 문구 (상수 참조)
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

---

## 4. Formulas

### F1. 루머 정확도 롤

```
is_accurate = (rng.randf() < RUMOR_BASE_ACCURACY)

RUMOR_BASE_ACCURACY = SkillTree.RUMOR_BASE_ACCURACY  # 0.70 (70%)

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

---

## 5. Edge Cases

| 상황 | 처리 |
|------|------|
| S3 미해금 | 루머 시그널 미발화. 뉴스는 기존대로 동작 |
| 동일 틱에 루머 2건 발생 | 각각 독립 카드로 표시. 순서는 생성 순 |
| RUMOR_LEAD_TICKS 내에 장 마감 | 루머 발화 후 뉴스 발동 전 장 마감 → 루머만 표시되고 뉴스 미발동. 다음 거래일로 이월 없음 — 해당 이벤트 취소 처리 |
| 루머 후 즉시 뉴스 발동 (LEAD_TICKS = 0) | 루머 없이 뉴스만 발동. 튜닝 최솟값 30틱 이하 비권장 |
| 동일 종목 루머 중복 (60틱 내 두 번째 이벤트) | 두 번째 루머도 정상 발화. 플레이어가 혼란을 감수하는 리스크 |
| 익스플로잇 — 루머 패턴 학습 후 100% 예측 | 30% 반전은 독립 확률 → 패턴 없음. 장기 통계로만 70% 수렴 |

---

## 6. Dependencies

| 시스템 | 방향 | 내용 |
|--------|------|------|
| `NewsEventSystem` | Hard | 이벤트 스케줄 시점에 루머 발화. `on_rumor_hint` 시그널 추가 |
| `SkillTree` | Hard | `has_rumor_channel()` 확인 (이미 구현 ✅), `RUMOR_BASE_ACCURACY`, `RUMOR_LEAD_MINUTES` 상수 |
| `GameClock` | Soft | `TICKS_PER_GAME_MINUTE` 참조 (LEAD_TICKS 계산) |
| 뉴스 피드 UI | Hard | `on_rumor_hint` 시그널 수신 → 루머 카드 생성 |
| `news-events.md` | Soft | 이벤트 스케줄 구조 기준 |
| `news-feed-ui.md` | Soft | 카드 스타일 패턴 기준 |

---

## 7. Tuning Knobs

| 변수 | 위치 | 기본값 | 범위 | 영향 | 위험 |
|------|------|--------|------|------|------|
| `RUMOR_BASE_ACCURACY` | `skill_tree.gd` `@export` | 0.70 | 0.50~0.90 | 루머 신뢰도 | 0.90+: 확실한 선행 정보 = 밸런스 파괴 |
| `RUMOR_LEAD_MINUTES` | `skill_tree.gd` `@export` | 15 | 7~30 | 선행 시간 | 30+: 과도한 이점 |

---

## 8. Acceptance Criteria

| # | 조건 | 판정 방법 |
|---|------|---------|
| AC-01 | S3 미해금 시 루머 카드 미표시 | S2까지만 해금 → 10분 플레이 → 루머 카드 없음 확인 |
| AC-02 | S3 해금 후 뉴스 발동 60틱 전 루머 카드 표시 | S3 해금 → 뉴스 발동 틱 기록 → (발동 틱 - 60)에 루머 카드 확인 |
| AC-03 | 루머 카드가 일반 뉴스 카드와 시각적으로 구분됨 | 루머 카드 회색 배경 + `[루머]` 태그 확인 |
| AC-04 | 장기 실행 시 루머 정확도 약 70% 수렴 | 테스트: 100회 루머 발화 → 정확 건수 65~75건 |
| AC-05 | 장 마감 전 발화된 루머에 대응하는 뉴스가 미발동 시 이벤트 취소 | 장 마감 직전 루머 발화 확인 → 다음 거래일에 해당 뉴스 미발동 |
| AC-06 | `--export-release` 빌드 성공, SCRIPT ERROR 없음 | QA Lead 빌드 검증 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
- 이 기능은 어디서 호출되는가: `NewsEventSystem._schedule_event()` 내부 → `SkillTree.has_rumor_channel()` 체크 → `on_rumor_hint` 시그널 emit

### 호출 경로

**시그널 추가**
- [ ] `news_event_system.gd`: `signal on_rumor_hint(rumor: Dictionary)` 선언
  - `rumor` 구조: `{ "stock_id": String, "direction": String, "is_accurate": bool, "text": String }`
  - `is_accurate`는 발화 시점에 결정. **UI에 노출하지 않음**

**루머 발화 로직**
- [ ] `news_event_system.gd`: `_schedule_event()` 또는 이벤트 생성 직후 시점에 루머 분기 추가
- [ ] `SkillTree.has_rumor_channel()` 체크
- [ ] `rng.randf() < RUMOR_BASE_ACCURACY` 정확도 롤
- [ ] 방향 반전 처리: `is_accurate == false` 시 방향 텍스트 반전
- [ ] 장 마감 이전 `RUMOR_LEAD_TICKS` 이내인지 확인 → 장 마감 후 이벤트면 루머 생략

**뉴스 피드 UI**
- [ ] `news_feed.gd` 또는 `trading_screen.gd`: `on_rumor_hint` 시그널 연결
- [ ] 루머 카드 생성: 회색 배경, `[루머]` 태그, 모호한 방향 텍스트
- [ ] 고정 문구 상수화: `"※ 정확도 %d%% — 교차 확인 권장" % int(RUMOR_BASE_ACCURACY * 100)`

### AC → 테스트 매핑
| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_rumor_channel.gd` | `test_no_rumor_without_s3()` |
| AC-04 | `tests/unit/test_rumor_channel.gd` | `test_accuracy_converges_to_70pct()` |

### 빌드 검증
- [ ] 바이너리 실행 확인: QA Lead 서명 _______
