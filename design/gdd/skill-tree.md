# 스킬 트리 시스템 (Skill Tree)

> **Status**: In Review
> **Author**: user + agents
> **Last Updated**: 2026-04-03
> **Implements Pillar**: 체감있는 성장 (Feel the Growth)

## Overview

스킬 트리 시스템은 플레이어가 경험치 레벨업으로 획득한 스킬 포인트를 투자하여
분석 도구, 시장 정보, 거래 옵션, 포트폴리오 용량을 해금하는 Progression 시스템이다.
4개 브랜치(분석 도구, 시장 감지, 거래 스킬, 포트폴리오)로 구성되며,
T0 기본 제공 + T1~T4 최대 4단계 순차 해금 구조 (브랜치마다 T3 또는 T4까지)를 가진다. 스킬 해금은 영구적이며 시즌 리셋에 영향받지
않는다. 플레이어는 한정된 스킬 포인트로 어느 브랜치를 우선 성장시킬지 전략적
선택을 내려야 한다.

## Player Fantasy

첫 시즌이 끝났다. 레벨업 — 스킬 포인트 +1. 스킬 트리를 열면 네 갈래 길이
펼쳐진다. 이동평균선? 빠른 뉴스? 지정가 주문? 종목 슬롯 확장?

이동평균선을 찍었다. 다음 시즌, 차트에 새로운 선이 그려진다. 이 선이 보이기
전에는 감으로 매매했는데, 이제는 추세가 보인다. "같은 시장인데 보이는 게
다르다." 이것이 성장이다.

필라 "체감있는 성장"에 따라, 스킬 해금은 단순 숫자 버프가 아니라 게임플레이
자체를 바꾸는 새로운 도구를 제공한다. 더 많은 정보, 더 빠른 뉴스, 더 다양한
주문 — 각각이 판단의 질을 높이는 실질적 도구다.

## Detailed Design

### Core Rules

#### 규칙 1. 스킬 트리 구조

4개 브랜치, 총 14개 해금 가능 스킬. 모든 스킬 비용 = 1 스킬 포인트.

> **명명 규칙**: 스킬은 **ID**(A1, S1, TR1, P1 등)로 참조한다.
> **Tier**(T0-T4)는 브랜치 내 깊이. T0은 기본 제공, T1부터 해금 필요.
> 모든 GDD에서 "Lv" 표기는 제거되었으며, 스킬 ID(A1, S2 등) 또는 Tier(T0-T4)로 참조한다.
> **코드 API**: `is_skill_unlocked("A1")` 같은 ID 기반 조회가 표준.
> 편의 함수: `get_news_delay_ticks()`, `get_max_holdings()`, `has_rumor_channel()`,
> `has_leverage()`, `has_short_selling()`. `get_*_level()` 형태의 API는 존재하지 않는다.

##### 브랜치 1: 분석 도구 (Analysis Tools)

| ID | Tier | 스킬명 | 효과 | 선행 조건 |
|----|------|--------|------|-----------|
| A0 | T0 | 캔들차트 + 거래량 | 기본 차트 표시 | 기본 제공 |
| A1 | T1 | 이동평균선 | 5/20/60일 이동평균선 차트 오버레이 | — |
| A2 | T2 | 보조지표 | RSI(14), MACD(12,26,9) 하단 패널 표시 | A1 |
| A3 | T3 | 재무제표 | PER, PBR, ROE 기업정보 패널 표시 | A2 |
| A4 | T4 | 섹터 비교 분석 | 업종별 상대강도 비교 뷰 | A3 |

##### 브랜치 2: 시장 감지 (Market Sense)

| ID | Tier | 스킬명 | 효과 | 선행 조건 |
|----|------|--------|------|-----------|
| S0 | T0 | 뉴스 (5분 딜레이) | 뉴스 5분(20틱) 후 수신 | 기본 제공 |
| S1 | T1 | 빠른 뉴스 | 뉴스 딜레이 2분(8틱)으로 단축 | — |
| S2 | T2 | 실시간 뉴스 | 뉴스 딜레이 0초 | S1 |
| S3 | T3 | 루머 채널 | 뉴스 발생 전 확률적 힌트 (정확도 70%) | S2 |

##### 브랜치 3: 거래 스킬 (Trading Skills)

| ID | Tier | 스킬명 | 효과 | 선행 조건 |
|----|------|--------|------|-----------|
| TR0 | T0 | 시장가 매매 | 현재가 즉시 체결 | 기본 제공 |
| TR1 | T1 | 지정가 주문 | 목표가 설정, 조건 충족 시 자동 체결 | — |
| TR2 | T2 | 손절/익절 | 보유 종목에 자동 매도 조건 설정 | TR1 |
| TR3 | T3 | 공매도 | 주가 하락 시 수익. 보유 없이 매도 후 매수로 청산 | TR2 + **A2** (보조지표) |
| TR4 | T4 | 레버리지 | 2x 배율 거래. 수익/손실 2배 | TR3 |

##### 브랜치 4: 포트폴리오 (Portfolio)

| ID | Tier | 스킬명 | 효과 | 선행 조건 |
|----|------|--------|------|-----------|
| P0 | T0 | 3종목 보유 | 동시 보유 3종목 | 기본 제공 |
| P1 | T1 | 5종목 보유 | MAX_HOLDINGS = 5 | — |
| P2 | T2 | 10종목 보유 | MAX_HOLDINGS = 10 | P1 |
| P3 | T3 | 섹터 ETF | 섹터 단위 투자 가능 | P2 + **A4** (섹터 비교) |

##### 크로스 브랜치 선행 조건 요약

- 공매도(TR3) ← 보조지표(A2): 하락 타이밍 판단에 RSI/MACD 필요
- 섹터 ETF(P3) ← 섹터 비교(A4): 섹터 분석 도구 없이 ETF 투자 불가

#### 규칙 2. 스킬 해금

```
해금 조건:
1. available_skill_points >= 1
2. 선행 조건 스킬이 모두 해금됨
→ 스킬 포인트 -1, 스킬 영구 활성화
```

- 해금은 비가역적 (리스펙 없음)
- 해금 즉시 효과 적용 (다음 시즌이 아닌 현재 진행 중인 시즌에도)
- 한 번에 여러 스킬 해금 가능 (포인트가 충분하면)

#### 규칙 3. MVP 범위

MVP(레벨 2 = 스킬 포인트 1개)에서 접근 가능한 T1 스킬:
- A1 이동평균선, S1 빠른 뉴스, TR1 지정가 주문, P1 5종목 보유

이 중 하나를 선택 — 플레이어의 첫 번째 전략적 선택.

### States and Transitions

스킬 트리 시스템에 상태 머신은 없다. 각 스킬은 `LOCKED` 또는 `UNLOCKED` 이진 상태.

| 상태 | 설명 | 전환 |
|------|------|------|
| LOCKED | 미해금. 선행 조건 미충족 또는 포인트 부족 | → UNLOCKED (해금 시) |
| UNLOCKED | 해금됨. 효과 영구 적용 | — (비가역) |

추가 표시 상태 (UI용, 저장 불필요):
- `AVAILABLE`: LOCKED이지만 선행 조건 충족 + 포인트 보유 → 해금 가능
- `PREREQ_MISSING`: LOCKED이고 선행 조건 미충족 → 해금 불가 (어떤 선행 조건이 필요한지 표시)

### Interactions with Other Systems

| 시스템 | 방향 | 인터페이스 |
|--------|------|-----------|
| 경험치 시스템 | → 스킬 트리 | `on_level_up(new_level, skill_points)` → 스킬 포인트 갱신, `get_available_skill_points()` |
| 차트 렌더러 | 스킬 트리 → | `is_skill_unlocked("A1")` → 이동평균선 표시 여부, `is_skill_unlocked("A2")` → RSI/MACD 패널 |
| 뉴스/이벤트 | 스킬 트리 → | `get_news_delay_ticks()` → 30/15/0초 반환 |
| 주문 엔진 | 스킬 트리 → | `is_skill_unlocked("TR1")` → 지정가 허용, `is_skill_unlocked("TR3")` → 공매도 허용, `is_skill_unlocked("TR4")` → 레버리지 허용 |
| 호가창 UI | 스킬 트리 → | `is_skill_unlocked("TR1")` → 호가창 섹션 표시 (`OrderPanel._order_book_section.visible`) |
| 포트폴리오 | 스킬 트리 → | `get_max_holdings()` → 3/5/10 반환 |
| 스킬 트리 UI | 스킬 트리 → | `get_all_skills()`, `unlock_skill(id)`, `get_skill_state(id)` |
| 세이브/로드 | ↔ 스킬 트리 | 해금 상태 직렬화/역직렬화 |

## Formulas

### F1. 뉴스 딜레이

```
news_delay = NEWS_DELAY_TABLE[highest_sense_tier]
```

| 해금 상태 | 딜레이 (틱) | 실시간 환산 |
|-----------|-----------|------------|
| S0 (기본) | 20틱 (게임시간 5분) | 약 3.8초 (20×0.192) at 1x |
| S1 | 8틱 (게임시간 2분) | 약 1.5초 (8×0.192) at 1x |
| S2 | 0틱 | 즉시 |

### F2. 최대 보유 종목

```
max_holdings = HOLDINGS_TABLE[highest_portfolio_tier]
```

| 해금 상태 | 최대 종목 수 |
|-----------|-------------|
| P0 (기본) | 3 |
| P1 | 5 |
| P2 | 10 |

### F3. 루머 정확도

```
rumor_accuracy = RUMOR_BASE_ACCURACY  # 70%
rumor_lead_time = RUMOR_LEAD_TICKS    # 뉴스 발생 60틱 (게임시간 15분, 실시간 약 11.5초 at 1x) 전
```

루머 메시지는 실제 뉴스의 종목명과 방향(호재/악재)을 포함하되,
정확도 미달 시 방향이 반전됨 (30% 확률로 잘못된 힌트).

### F4. 레버리지 배율

```
leverage_multiplier = LEVERAGE_RATIO  # 2.0x
leveraged_pnl = base_pnl × LEVERAGE_RATIO
margin_call_threshold = -(initial_investment / LEVERAGE_RATIO)
```

예시: 100만원 2x 레버리지 매수 → 실효 노출 200만원.
+5% 상승 시 수익 = 10만원 (10% 수익률). -50% 하락 시 마진콜 → 강제 청산.

스킬 트리 자체에 복잡한 연산은 없다. 핵심 공식은 각 하위 시스템
(차트 렌더러, 뉴스 시스템, 주문 엔진, 포트폴리오)에서 스킬 상태를
조회하여 적용한다.

## Edge Cases

| 상황 | 처리 |
|------|------|
| 스킬 포인트 0에서 해금 시도 | 거부. UI에서 비활성 표시 |
| 선행 조건 미충족 상태에서 해금 시도 | 거부. 필요한 선행 스킬 표시 |
| 레벨업으로 다수 포인트 동시 획득 | 각 포인트 개별 사용 가능. 한 번에 여러 스킬 해금 가능 |
| 시즌 도중 스킬 해금 | 즉시 적용. 예: 이동평균선 해금 → 차트에 바로 표시 |
| P2(10종목) 해금 전 이미 3종목 보유 | 기존 보유 유지. 추가 매수 가능해짐 |
| 포트폴리오 축소 불가 | 다운그레이드 없음 (비가역). 한번 확장된 슬롯은 줄어들지 않음 |
| 공매도 포지션에서 시즌 종료 | 시즌 종료 강제 청산 순서에서 공매도 포지션도 청산 |
| 레버리지 포지션에서 자산 0 이하 | 자산 0으로 클램프. 강제 청산 (마진콜). 음수 자산 불가 |
| 모든 스킬 해금 후 추가 스킬 포인트 | 잉여 포인트 누적. 향후 확장 콘텐츠용 |
| 저장 데이터에 존재하지 않는 스킬 ID | 무시. 해금 상태에서 제거 |
| 루머 채널에서 잘못된 힌트 수신 | 30% 확률. 방향 반전된 힌트. 플레이어가 정확도를 학습해야 함 |
| P3(섹터 ETF) 해금 없이 섹터 ETF 매수 시도 | 거부. "섹터 ETF 스킬을 해금하세요" 안내 표시. 크로스 브랜치 조건(A4)도 동일 적용 |

## Dependencies

### 상위 의존 (이 시스템이 필요로 하는 것)

| 시스템 | 의존 유형 | 데이터 |
|--------|----------|--------|
| 경험치 시스템 | Hard | `get_available_skill_points()`, `on_level_up(new_level, skill_points)` 시그널 |

### 하위 의존 (이 시스템에 의존하는 것)

| 시스템 | 의존 유형 | 데이터 |
|--------|----------|--------|
| 차트 렌더러 | Soft | `is_skill_unlocked("A1"/"A2"/"A3"/"A4")` → 표시할 지표 결정 |
| 뉴스/이벤트 | Soft | `get_news_delay_ticks()` → 뉴스 딜레이 |
| 주문 엔진 | Soft | `is_skill_unlocked("TR1"/"TR2"/"TR3"/"TR4")` → 허용 주문 유형 |
| StopTakeSystem | Soft | `is_skill_unlocked("TR1")`, `is_skill_unlocked("TR2")` → 손절/익절 감시 활성화 여부 판단. TR2 해금 시 `check_and_trigger()` 실행 경로 활성화 |
| 포트폴리오 관리 | Soft | `get_max_holdings()` → 최대 보유 종목 수 |
| 스킬 트리 UI | Hard | `get_all_skills()`, `unlock_skill(id)`, `get_skill_state(id)` |
| 세이브/로드 | Hard | 해금 상태 직렬화/역직렬화 |

## Tuning Knobs

| 변수 | 기본값 | 범위 | 영향 | 위험 |
|------|--------|------|------|------|
| SKILL_COST | 1 (전체 동일) | 1~3 | 스킬 해금 속도 | 2+로 올리면 초반 성장감 급감 |
| NEWS_DELAY_T0 | 20틱 (게임 5분, 실시간 ~3.8초) | 10~40 | 초기 정보 불이익 크기 | 너무 크면 뉴스 시스템 무용 |
| NEWS_DELAY_T1 | 8틱 (게임 2분, 실시간 ~1.5초) | 4~15 | S1 해금 가치 | T0과 차이 적으면 해금 동기 부족 |
| RUMOR_BASE_ACCURACY | 70% | 50~90% | 루머 채널 가치 | 90%+면 확실한 선행 정보 = 밸런스 파괴 |
| RUMOR_LEAD_TICKS | 60틱 (게임 15분, 실시간 ~11.5초) | 30~120 | 루머 선행 시간 | 120+면 과도한 이점 |
| LEVERAGE_RATIO | 2.0 | 1.5~3.0 | 레버리지 위험/보상 | 3.0+은 즉사급 손실 가능 |
| MAX_HOLDINGS_T0 | 3 | 2~5 | 초기 분산 제한 | 2이면 집중 투자 강제 |
| MAX_HOLDINGS_T1 | 5 | 4~7 | 중간 분산 | — |
| MAX_HOLDINGS_T2 | 10 | 8~15 | 완전 분산 | 종목 수 초과 시 UI 복잡도 증가 |

## Acceptance Criteria

| # | 기준 | 검증 방법 |
|---|------|----------|
| AC-1 | 스킬 포인트 보유 시 선행 조건 충족된 스킬 해금 가능 | 유닛 테스트: unlock_skill() 성공 후 is_skill_unlocked() == true |
| AC-2 | 선행 조건 미충족 시 해금 거부 | 유닛 테스트: A2 해금 시도 (A1 미해금) → 실패 |
| AC-3 | 크로스 브랜치 조건 검증 | 유닛 테스트: TR3 해금 시도 (A2 미해금) → 실패 |
| AC-4 | 해금 시 스킬 포인트 -1 | 유닛 테스트: 해금 전후 포인트 차이 == 1 |
| AC-5 | 이동평균선(A1) 해금 후 차트에 MA 표시 | 통합 테스트: A1 해금 → 차트 렌더러에 MA 데이터 전달 확인 |
| AC-6 | 뉴스 딜레이가 스킬에 따라 변경됨 | 유닛 테스트: S0→20틱, S1→8틱, S2→0틱 |
| AC-7 | MAX_HOLDINGS가 스킬에 따라 변경됨 | 유닛 테스트: P0→3, P1→5, P2→10 |
| AC-8 | 시즌 리셋 후 해금 상태 유지 | 시즌 리셋 전후 해금 상태 비교 |
| AC-9 | 포인트 0에서 해금 시도 시 거부 | 유닛 테스트 |
| AC-10 | P3(섹터 ETF) 해금 시 섹터 단위 투자 가능 | 유닛 테스트: P3 해금 → 섹터 ETF 매매 허용, P3 미해금 → 섹터 ETF 매매 거부 |
| AC-11 | `has_rumor_channel()` = S3 해금 시 true 반환, 미해금 시 false | 유닛 테스트 |

## Open Questions

- ~~공매도(TR3)/레버리지(TR4)는 MVP 범위 밖. V-Slice에서 스킬 트리에 표시하되 해금 불가로 처리할지, 아예 숨길지 결정 필요~~ **결정(2026-04-14)**: V-Slice에서 TR3/TR4 노드는 스킬 트리에 **표시하되 잠금 상태(LOCKED)** 유지. 해금은 Beta Sprint 9(B-07b/B-07c)에서 구현. 이유: 노드 표시로 진행감 제공(로드맵 가시화), 숨기면 "성장 서사" 필라에 반함.
- 리스펙(스킬 초기화) 기능 추가 여부 — 현재는 비가역. 향후 프리미엄 리셋 아이템 가능성
- 루머 채널(S3)의 구체적 UX: 별도 패널? 뉴스 피드에 "[루머]" 태그?

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 기능 | 진입점 |
|------|--------|
| 스킬 해금 | `growth_screen.gd` (F3 탭) → `SkillTree.unlock_skill(skill_id)` (SkillTreeOverlay 제거됨, F3 임베드로 전환) |
| 스킬 활성 여부 확인 | `chart_renderer.gd` 등 → `SkillTree.is_skill_unlocked(skill_id)` |
| SP 소비 연동 | `SkillTree.unlock_skill()` 내부 → `XpSystem.spend_skill_point()` |

### 호출 경로

- [x] `SkillTree.unlock_skill(skill_id: String) -> bool` 존재
- [x] `SkillTree.is_skill_unlocked(skill_id: String) -> bool` 존재
- [x] `SkillTree.can_unlock(skill_id: String) -> bool` 존재
- [x] `SkillTree.on_skill_unlocked(skill_id)` 시그널 존재
- [x] `SkillTree.reset()` 존재

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 | 상태 |
|----|------------|------------|------|
| 사전 요건 검증 | `tests/unit/test_skill_tree.gd` | `test_cannot_unlock_without_prereq()` | ✅ |
| SP 소비 | `tests/unit/test_skill_tree.gd` | `test_unlock_consumes_skill_point()` | ✅ |
| 이미 해금된 스킬 재해금 방지 | `tests/unit/test_skill_tree.gd` | `test_cannot_unlock_already_unlocked()` | ✅ |
| API 계약 | `tests/unit/test_api_contracts.gd` | `test_skill_tree_api()` | ✅ |

### 빌드 검증

- [x] 바이너리 실행 확인: QA Lead 서명 — 내부 감사 2026-04-15 (Alpha 완료 빌드, SCRIPT ERROR 없음)
