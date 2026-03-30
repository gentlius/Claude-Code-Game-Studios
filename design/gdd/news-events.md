# 뉴스/이벤트 시스템 (News & Events)

> **Status**: In Design
> **Author**: user + game-designer
> **Last Updated**: 2026-03-25
> **Implements Pillar**: 읽는 재미 (Read the Market), 판단이 곧 실력 (Judgment is King)

## Overview

뉴스/이벤트 시스템은 시드머니의 시장 이벤트를 생성하고 전달하는 Gameplay 시스템이다.
게임 시계의 틱/상태 시그널을 구독하여 사전 정의된 이벤트 풀에서 적절한 타이밍에
이벤트를 선택하고, 가격 엔진에는 Event 오브젝트를, 플레이어에게는 뉴스 텍스트를
전달한다. 이벤트는 MACRO(거시경제), SECTOR(업종), INDIVIDUAL(개별 종목) 세 범위로
나뉘며, 각각 시장 전체, 섹터, 특정 종목의 가격에 영향을 미친다.

플레이어의 스킬 레벨에 따라 뉴스 수신에 딜레이가 적용되어, 정보 속도 자체가
경쟁 우위가 된다. 시즌마다 시장 테마가 설정되어 특정 유형의 이벤트가 더 자주
발생하며, 이를 파악한 플레이어가 전략적 우위를 점한다.

MVP에서 이벤트 풀은 50개 이상의 사전 작성된 이벤트로 구성되며, 절차적 생성은
향후 확장으로 남긴다.

## Player Fantasy

뉴스가 뜬다. "메디진, 3상 임상시험 성공" — 심장이 뛴다. 바이오주니까 급등할 거야.
하지만 잠깐, 이미 가격이 올랐나? 차트를 본다. 아직 안 움직였다. 내가 먼저
알았다! 매수 버튼을 누른다.

이것이 뉴스 시스템이 만드는 경험이다. 뉴스는 단순한 알림이 아니라 **판단의
원료**다. "이 뉴스가 어떤 종목에 영향을 줄까?", "호재인가 악재인가?",
"얼마나 큰 영향일까?" — 이 세 가지 질문에 대한 플레이어의 답이 매매 판단이 된다.

필라 "읽는 재미"에 따라, 뉴스 텍스트는 실제 경제 뉴스처럼 읽히되 게임적으로
명확한 단서를 포함한다. 숙련 플레이어는 "금리 인상 뉴스 → 금융주 호재 + 성장주
악재"를 즉시 읽고, 초보 플레이어도 뉴스에 명시된 섹터를 보고 연결할 수 있다.
필라 "판단이 곧 실력"에 따라, 뉴스를 빨리 읽고 정확히 해석하는 것이 곧 실력 차이다.

## Detailed Design

### Core Rules

#### 규칙 1. 이벤트 풀 구조

##### 1-1. 풀의 물리적 구성

이벤트 풀은 사전 작성된 이벤트 템플릿의 집합이다. 각 템플릿은 JSON 레코드로
저장되며, 런타임에 변경되지 않는 정적 데이터다. 풀 전체는
`assets/data/event_pool.json`에 위치한다.

MVP 풀 규모: **템플릿 50개 이상** (MACRO 10+, SECTOR 30+, INDIVIDUAL 10+).

##### 1-2. 이벤트 카테고리 정의

이벤트는 **Scope × Impact** 두 축으로 분류된다.

**Scope 축 (3종)**

| scope | 대상 | target_stocks 결정 방식 |
|-------|------|------------------------|
| `MACRO` | 시장 전체 | 10개 종목 전부 |
| `SECTOR` | 특정 섹터 전체 | `target_sector`로 섹터 결정 → 해당 섹터 소속 종목 전부. `event_tags` 미사용 |
| `INDIVIDUAL` | 특정 1개 종목 | `event_tags`와 종목 `event_tags` 교집합으로 매칭된 종목 1개 |

**Impact 축 (4등급)**

| 등급 | base_impact 범위 | 설명 | 가격 엔진 BREAKOUT 유발 |
|------|-----------------|------|------------------------|
| `SMALL` | 0.01~0.03 (1~3%) | 소규모 재료. 차트에 흔적만 남김 | 없음 (5% 미만) |
| `MEDIUM` | 0.03~0.07 (3~7%) | 중간 재료. 차트에서 식별 가능 | 없음~경계 |
| `LARGE` | 0.07~0.15 (7~15%) | 큰 재료. BREAKOUT 확실히 유발 | 유발 |
| `MEGA` | 0.15~0.20 (15~20%) | 시장 충격. 다수 종목 동시 영향 | 강하게 유발 |

BREAKOUT 유발 기준: `actual_impact ≥ 5%`. LARGE 등급부터 MEDIUM 이상 민감도의
종목에서 BREAKOUT이 보장된다.

##### 1-3. 이벤트 템플릿 스키마

```
EventTemplate {
    // --- 식별 ---
    template_id: string         # 고유 ID (예: "BIO_CLINICAL_SUCCESS_01")
    scope: MACRO | SECTOR | INDIVIDUAL
    target_sector: string | null  # SECTOR 이벤트의 섹터 ID. INDIVIDUAL은 null
    event_tags: string[]        # INDIVIDUAL 전용: 종목 매칭에 사용. SECTOR/MACRO에서는 미사용 (메타데이터/검색용으로 보유 가능)

    // --- 가격 엔진 파라미터 ---
    event_type: INSTANT_SHOCK | GRADUAL_SHIFT
    impact_tier: SMALL | MEDIUM | LARGE | MEGA
    impact_min: float           # base_impact 하한
    impact_max: float           # base_impact 상한
    direction: +1 | -1 | VARIABLE  # VARIABLE = 호재/악재 50:50 추첨. 방향별 헤드라인 필드 사용
    decay_ticks: int            # GRADUAL_SHIFT 지속 틱 (0이면 INSTANT)
    decay_curve: LINEAR | EXPONENTIAL

    // --- 뉴스 텍스트 ---
    headline_template: string   # 뉴스 헤드라인 (변수 포함). direction=VARIABLE 시 미사용
    headline_positive: string | null  # direction=VARIABLE 호재 헤드라인
    headline_negative: string | null  # direction=VARIABLE 악재 헤드라인
    body_template: string       # 뉴스 본문 (변수 포함). direction=VARIABLE 시 미사용
    body_positive: string | null      # direction=VARIABLE 호재 본문
    body_negative: string | null      # direction=VARIABLE 악재 본문
    impact_hint: string         # 플레이어에게 보이는 기대 효과 힌트

    // --- 선택 제어 ---
    season_tags: string[]       # 활성화되는 시즌 테마 태그 (빈 배열 = 항상 활성)
    weight_base: float          # 기본 선택 가중치 (1.0 = 표준)
    cooldown_ticks: int         # 동일 템플릿 재선택 금지 틱 수
    exclude_same_scope: bool    # true면 같은 scope의 다른 이벤트와 동일 슬롯 불가

    // --- 텍스트 변수 ---
    variables: {string: string[]}  # 템플릿별 도메인 변수 후보값 목록
}
```

##### 1-4. 템플릿 예시 (3종)

**예시 A — INDIVIDUAL, LARGE, INSTANT_SHOCK (바이오)**
```
template_id: "BIO_CLINICAL_SUCCESS_01"
scope: INDIVIDUAL
event_tags: ["clinical_trial"]
event_type: INSTANT_SHOCK
impact_tier: LARGE
impact_min: 0.10, impact_max: 0.15
direction: +1
decay_ticks: 0
headline_template: "{company}, {phase}상 임상시험 최종 성공 발표"
body_template: "{company}이(가) {drug_name} {phase}상 임상시험의 성공적 완료를
               공식 발표했다. 조건부 허가 신청 예정."
impact_hint: "개별 종목 강한 호재"
season_tags: []
weight_base: 1.0
cooldown_ticks: 390
variables: {"phase": ["2", "3"], "drug_name": ["에코린", "세파졸", "바이오렉스"]}
```

**예시 B — SECTOR, MEDIUM, GRADUAL_SHIFT (반도체)**
```
template_id: "SEMI_EXPORT_QUOTA_01"
scope: SECTOR
target_sector: SEMICONDUCTOR
event_tags: ["semiconductor", "export"]
event_type: GRADUAL_SHIFT
impact_tier: MEDIUM
impact_min: 0.04, impact_max: 0.07
direction: -1
decay_ticks: 60, decay_curve: EXPONENTIAL
headline_template: "정부, {country} 반도체 수출 물량 {percent}% 한시 제한"
body_template: "산업통상자원부는 {country} 대상 반도체 수출 물량을 {duration} 동안
               {percent}% 제한한다고 밝혔다."
impact_hint: "반도체 섹터 지속 악재"
season_tags: ["export_risk"]
weight_base: 0.8
cooldown_ticks: 195
variables: {"country": ["미국", "유럽", "중국"], "percent": ["15", "20", "30"],
            "duration": ["3개월", "6개월"]}
```

**예시 C — MACRO, LARGE, INSTANT_SHOCK (금리)**
```
template_id: "MACRO_RATE_HIKE_01"
scope: MACRO
event_tags: ["interest_rate"]
event_type: INSTANT_SHOCK
impact_tier: LARGE
impact_min: 0.07, impact_max: 0.12
direction: VARIABLE
decay_ticks: 0
headline_positive: "한국은행, 기준금리 {rate_delta}%p 인하 결정"
headline_negative: "한국은행, 기준금리 {rate_delta}%p 인상 결정"
body_positive: "한국은행 금융통화위원회는 기준금리를 {rate_delta}%p 인하하여
               연 {new_rate}%로 결정했다."
body_negative: "한국은행 금융통화위원회는 기준금리를 {rate_delta}%p 인상하여
               연 {new_rate}%로 결정했다."
impact_hint: "시장 전반 큰 충격"
season_tags: ["rate_hike_cycle"]
weight_base: 1.2
cooldown_ticks: 390
variables: {"rate_delta": ["0.25", "0.50"], "new_rate": ["3.25", "3.50", "3.75"]}
```

---

#### 규칙 2. 이벤트 생성 규칙

##### 2-1. 하루 이벤트 슬롯 구조

1거래일(390틱)을 3구간으로 나누어 각 구간에 **슬롯**을 배정한다. 슬롯은 이벤트가
발생할 수 있는 예약된 시간 창이다. 각 슬롯은 확률에 따라 이벤트를 발생시키거나
건너뛴다.

| 구간 | 틱 범위 | 슬롯 수 | 슬롯당 발생 확률 | 설명 |
|------|---------|---------|---------------|------|
| 장 초반 (Opening) | 1~100 | 1 | 0.70 | 개장 재료 |
| 장 중반 (Midday) | 101~280 | 2 | 0.55 | 돌발 뉴스 |
| 장 후반 (Closing) | 281~390 | 1 | 0.60 | 마감 전 재료 |

슬롯 발생 시각: 각 구간 내에서 균등분포로 틱을 샘플링.

**기댓값**:
```
E[일일 이벤트 수] = 1×0.70 + 2×0.55 + 1×0.60 = 2.40
```

**하드 캡**: 하루 누적 5개 도달 시 이후 슬롯 건너뜀. 인지 부하 보호.

**최소 보장**: 하루 이벤트 0개 시 장 중반 첫 슬롯에서 SMALL MACRO 1개 강제 발생.

##### 2-2. Scope 배분 비율

| Scope | 기본 가중치 | 기댓값 (일 2.4개 기준) |
|-------|-----------|----------------------|
| `INDIVIDUAL` | 0.55 | 약 1.3개 |
| `SECTOR` | 0.35 | 약 0.8개 |
| `MACRO` | 0.10 | 약 0.2개 |

MACRO는 희소하게 유지. 시즌 테마에 따라 가중치 조정 (규칙 5 참조).

##### 2-3. Impact 등급 배분

| Impact 등급 | 기본 가중치 | 의도 |
|------------|-----------|------|
| `SMALL` | 0.35 | 배경 소음 |
| `MEDIUM` | 0.40 | 전략적 판단 필요 |
| `LARGE` | 0.20 | 즉각 반응 필요 |
| `MEGA` | 0.05 | 시장 충격. 하루 최대 1회 |

MEGA 추가 제약: 하루 MEGA 이미 발생 시 LARGE로 강등.

##### 2-4. 클러스터링 방지 규칙

- **동일 템플릿 쿨다운**: `cooldown_ticks` 동안 같은 `template_id` 재선택 불가
- **동일 Scope 연속 방지**: 직전 슬롯과 동일 Scope면 가중치 50% 감소 후 재추첨 1회
- **동일 종목 보호**: INDIVIDUAL에서 직전 90틱 이내 동일 종목 이벤트 있었으면
  해당 종목 가중치 0. 후보 종목 없으면 SECTOR로 격상

##### 2-5. 이벤트 템플릿 선택 절차

```
1. 풀 필터링:
   - scope == 결정된 Scope
   - impact_tier == 결정된 Impact
   - cooldown 미경과 템플릿 제외
   - 활성 시즌 테마의 season_tags에 포함되거나 season_tags 빈 배열

2. INDIVIDUAL 추가 필터:
   - event_tags와 종목 event_tags 교집합 존재하는 종목이 있어야 함
   - 후보 종목 없으면 SECTOR로 격상, 재필터

3. 가중 추첨:
   - weight_base × 시즌 가중치 배율로 가중치 계산
   - 가중 무작위 선택 1개

4. 후보 0개 시:
   - Impact를 SMALL로 고정 후 재시도
   - 여전히 없으면 슬롯 건너뜀
```

---

#### 규칙 3. 이벤트 콘텐츠 구조

##### 3-1. 템플릿 변수 시스템

뉴스 텍스트의 `{변수명}` 플레이스홀더를 실제값으로 치환한다.

**시스템 제공 변수** (자동 주입):

| 변수명 | 설명 | 예시 |
|-------|------|------|
| `{company}` | 대상 종목 이름 | "메디진" |
| `{ticker}` | 종목코드 | "MDG" |
| `{sector_name}` | 섹터 한글명 | "바이오/제약" |
| `{date}` | 게임 내 현재 날짜 | "3월 15일" |

**템플릿별 정적 변수**: 각 템플릿의 `variables` 필드에 정의된 후보값 목록에서
무작위 선택.

변수 치환 순서: 시스템 변수 먼저 → 템플릿 변수. 미해소 플레이스홀더가 남으면
이벤트 생성 중단 + 경고 로깅.

##### 3-2. INDIVIDUAL 이벤트의 종목 매칭

```
candidate_stocks = [s for s in all_stocks
                    if intersection(template.event_tags, s.event_tags) is not empty
                    and s.id not in recent_90tick_targets]

if candidate_stocks is empty:
    scope 격상 → SECTOR

selected_stock = weighted_random(candidate_stocks,
                 weight = s.sector_sensitivity × volatility_weight(s))
```

`volatility_weight`: EXTREME=1.5, HIGH=1.2, MEDIUM=1.0, LOW=0.7.
변동성 높은 종목이 개별 이벤트를 더 자주 받아 "관심 종목" 드라마 강화.

##### 3-3. 동일 템플릿 재사용

INDIVIDUAL 이벤트의 쿨다운은 `template_id + stock_id` 쌍 기준으로 관리한다.
"바이오 임상 성공" 템플릿이 메디진에 쿨다운 중이어도 다른 종목은 사용 가능.

##### 3-4. 뉴스 텍스트 길이 제약

- **헤드라인**: 30자 이내 (변수 치환 후). 3초 이내 독해.
- **본문**: 40~60자 이내. 5초 이내 독해.
- **impact_hint**: 10자 이내. UI 뱃지 형태.

##### 3-5. Event 오브젝트 조립

```
Event {
    event_type  = template.event_type
    impact_tier = template.impact_tier     # SMALL | MEDIUM | LARGE | MEGA (UI 알림 레벨 결정용)
    base_impact = uniform(template.impact_min, template.impact_max)
    direction   = template.direction  (VARIABLE이면 random_choice([+1, -1]))
    # VARIABLE 텍스트 선택: direction=+1이면 headline_positive/body_positive,
    #                       direction=-1이면 headline_negative/body_negative 사용
    scope       = template.scope
    target_stocks = resolve_target_stocks(template, selected_stock)
    decay_ticks = template.decay_ticks
    decay_curve = template.decay_curve
}
```

`resolve_target_stocks`:
- `MACRO`: 전체 10개 종목 ID 배열
- `SECTOR`: 해당 섹터 소속 종목 ID 배열
- `INDIVIDUAL`: `[selected_stock.id]`

---

#### 규칙 4. 뉴스 딜레이 시스템

##### 4-1. 딜레이 큐 구조

이벤트 생성 시 **가격 엔진에 즉시 전달**하되, 뉴스 텍스트는 플레이어 스킬 레벨에
따른 딜레이 후 UI에 표시한다. 가격은 이미 움직이지만 플레이어는 이유를 모른다 —
정보 비대칭 게임플레이의 핵심.

```
NewsQueueEntry {
    event: Event               # 가격 엔진에 이미 전달됨
    headline: string           # 딜레이 후 표시할 헤드라인
    body: string               # 본문
    impact_hint: string
    created_tick: int          # 이벤트가 발생한 틱
    display_tick: int          # = created_tick + player_delay_ticks
}
```

매 틱 `display_tick <= current_tick`인 항목을 꺼내 `on_news_display(entry: NewsQueueEntry)`
시그널을 발행한다. 뉴스 피드 UI가 이 시그널을 구독하여 뉴스 카드를 생성한다.

##### 4-2. 스킬 레벨별 딜레이

| 스킬 레벨 | player_delay_ticks | 실시간 환산 | 설명 |
|----------|-------------------|-----------|------|
| Lv1 (기본) | 30틱 | 약 23초 | 가격 움직임 보고 이유 모르는 구간 |
| Lv2 | 15틱 | 약 11초 | 반응 시간 2배 향상 |
| Lv3 | 0틱 | 즉시 | 이벤트와 동시에 뉴스 표시 |
| Lv4 | -20틱 (선행) | 약 15초 전 | 루머 채널 (4-4 참조). `rumor_advance_ticks`와 동일 값 |

##### 4-3. 장 마감 시 딜레이 큐 처리

`on_market_close` 시 미표시 항목 처리:
- **INDIVIDUAL/SECTOR**: 폐기. 가격 영향은 이미 반영됐으나 플레이어는 이유를 모름
  — 정보 손실이 게임플레이의 일부
- **MACRO**: 마감 후 "오늘의 시장 요약"에 통합 표시. 거시경제 뉴스는 결국 알려짐

Lv1~Lv2에서는 "오늘 왜 이 종목이 이렇게 움직였지?"를 때때로 모른다.
Lv3 해금이 정보 완전성에 큰 가치를 가지는 이유.

##### 4-4. Lv4 루머 채널 — 선행 정보

Lv4 해금 시 일부 이벤트 발생 전에 불확실한 힌트를 표시한다.

**루머 생성 조건**:
- LARGE/MEGA 등급: 발생 20틱 전 루머 100% 발생
- MEDIUM 등급: 30% 확률로 루머 발생
- SMALL 등급: 루머 없음

**루머 텍스트 형식**:
```
headline: "[루머] {company}/{sector_name} 관련 중요 공시 임박 가능성"
body: "복수의 관계자에 따르면 {company} 관련 중요 발표가 임박한 것으로
       알려졌다. 사실 여부 미확인."
```

방향(호재/악재)은 숨기고 대상만 암시.

**페이크 루머**: 하루 2회, 실제 이벤트와 무관한 페이크 루머 발생.
플레이어가 루머를 무조건 신뢰할 수 없도록 불확실성 유지.

---

#### 규칙 5. 시즌 테마

##### 5-1. 시즌 테마 개요

시즌 시작 시 하나의 시즌 테마가 활성화된다. 테마는 특정 Scope/섹터의 이벤트
발생 확률을 조정하고, 시즌 내내 시장의 "분위기"를 형성한다. 플레이어가 테마를
파악하면 선제적 포지션을 잡을 수 있다 — "읽는 재미"의 메타 레이어.

MVP: 3개, V-Slice: 5개, Alpha: 7개+.

##### 5-2. 테마 정의 스키마

```
SeasonTheme {
    theme_id: string
    theme_name: string
    active_season_tags: string[]

    // Scope 가중치 수정자 (기본값에 곱하는 배율)
    macro_weight_scale: float
    sector_weight_scale: float
    individual_weight_scale: float

    // 섹터별 이벤트 가중치 수정자
    sector_bias: {sector_id: float}

    // 힌트 공개
    hint_revealed_at_day: int
    hint_text: string
}
```

##### 5-3. MVP 시즌 테마 3종

**테마 A: "AI 붐"**
```
theme_id: "AI_BOOM"
macro_weight_scale: 1.2
sector_weight_scale: 1.0
individual_weight_scale: 0.9
sector_bias: {SEMICONDUCTOR: 2.0, GAMING: 1.3, RETAIL: 0.6, CONSTRUCTION: 0.6}
hint_revealed_at_day: 3
hint_text: "시장에서 AI 관련 소재가 주목받고 있다."
```

**테마 B: "금리 인상기"**
```
theme_id: "RATE_HIKE_CYCLE"
macro_weight_scale: 2.0
sector_weight_scale: 0.9
individual_weight_scale: 0.8
sector_bias: {FINANCE: 2.0, BATTERY: 0.5, GAMING: 0.5, ENTERTAINMENT: 0.5,
              CONSTRUCTION: 1.5, ENERGY: 1.3}
hint_revealed_at_day: 2
hint_text: "금리 정책 변화에 시장이 민감하게 반응하고 있다."
```

**테마 C: "원자재 위기"**
```
theme_id: "RAW_MATERIAL_CRISIS"
macro_weight_scale: 1.5
sector_weight_scale: 1.1
individual_weight_scale: 0.9
sector_bias: {ENERGY: 2.5, BATTERY: 1.8, AUTO: 1.5, SEMICONDUCTOR: 1.3,
              RETAIL: 0.7, ENTERTAINMENT: 0.5}
hint_revealed_at_day: 4
hint_text: "글로벌 공급망 불안이 특정 업종에 집중되고 있다."
```

##### 5-4. 테마 적용 메커니즘

```
// Scope 가중치 수정
adjusted_macro      = 0.10 × theme.macro_weight_scale
adjusted_sector     = 0.35 × theme.sector_weight_scale
adjusted_individual = 0.55 × theme.individual_weight_scale

// 합계 정규화 (합 = 1.0)
total = adjusted_macro + adjusted_sector + adjusted_individual
scope_weights = {MACRO: adjusted_macro/total, ...}

// 섹터별 템플릿 가중치
effective_weight = template.weight_base
                 × theme.sector_bias.get(template.target_sector, 1.0)
```

##### 5-5. 테마 힌트 공개

`hint_revealed_at_day`번째 거래일의 `on_market_open`에서 힌트 텍스트를
"시장 분석" 패널에 표시. 테마 이름 자체는 비공개. 숙련 플레이어는
힌트 전에도 이벤트 패턴으로 테마 추론 가능.

---

#### 규칙 6. 야간/프리마켓 이벤트

##### 6-1. 야간 이벤트 생성

`on_market_close` 직후 야간 이벤트 풀에서 0~2개 생성.

| 야간 이벤트 수 | 확률 |
|-------------|------|
| 0개 | 0.40 |
| 1개 | 0.45 |
| 2개 | 0.15 |

**야간 이벤트 제약**:
- Scope: MACRO 또는 SECTOR만 (INDIVIDUAL은 개별 공시로 별도 처리)
- Impact: SMALL 또는 MEDIUM만 (LARGE 이상은 다음날 장중 이벤트로)
- event_type: GRADUAL_SHIFT 전용 (장 시작 후 서서히 반영)

##### 6-2. 야간 버퍼

```
OvernightBuffer {
    events: OvernightEvent[]          # 내일 아침 공개할 이벤트
    individual_disclosures: Event[]   # 개별 종목 야간 공시
}
```

`on_day_transition` 시 각 종목에 대해 5% 확률로 INDIVIDUAL 야간 공시 생성
(SMALL~MEDIUM). "어닝 서프라이즈", "대규모 계약 체결" 등.

##### 6-3. 프리마켓 공개

다음 거래일 `on_market_open` 직전:

```
1. OvernightBuffer의 모든 이벤트를 가격 엔진에 전달
   (GRADUAL_SHIFT이므로 첫 거래일 틱 1부터 decay 시작)
2. 딜레이 없이 뉴스 텍스트를 즉시 UI에 표시
   ("오늘의 시장 전망" 형태로 묶어서 표시)
3. OvernightBuffer 초기화
```

야간 이벤트는 딜레이 없이 공개. 가격 반영은 MARKET_OPEN 후 첫 틱(틱 1)부터
시작된다. 장 시작 전 뉴스 분석이 "읽는 재미"의 핵심 모멘트.

##### 6-4. 프리마켓 뉴스 UI 형식

```
[오늘의 시장 전망] — 3월 16일 (화)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• 한국은행, 기준금리 인상 검토 가능성 (시장 전반 영향)
• 스타칩, 미국 빅테크 대규모 공급 계약 체결 (개별 호재)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

각 항목에 `impact_hint` 뱃지 표시.

### States and Transitions

#### 시스템 상태

| State | Description | Transition |
|-------|-------------|------------|
| **UNINITIALIZED** | 시즌 시작 전. 이벤트 풀 미로드 | → READY (시즌 초기화 시) |
| **READY** | 이벤트 풀 로드 완료. 시즌 테마 배정. 슬롯 스케줄 미생성 | → ACTIVE (첫 거래일 시작 시) |
| **ACTIVE** | 매 틱마다 슬롯 체크 및 이벤트 생성 | → DAY_END (장 마감 시) |
| **DAY_END** | 야간 이벤트 생성. 딜레이 큐 정리. 다음날 슬롯 생성 | → ACTIVE (다음 거래일 시작 시) |
| **SEASON_END** | 시즌 종료. 이벤트 통계 기록 | → UNINITIALIZED |

#### 게임 시계 상태 매핑

| 게임 시계 상태 | 뉴스/이벤트 상태 | 전환 트리거 |
|--------------|---------------|------------|
| 시즌 시작 | UNINITIALIZED → READY | `on_season_start` — 풀 로드, 테마 배정 |
| PRE_MARKET | READY (대기) | `on_market_state_changed(PRE_MARKET, ...)` |
| MARKET_OPEN | ACTIVE | `on_market_open` — 일일 슬롯 스케줄 생성 |
| MARKET_CLOSE | DAY_END | `on_market_close` — 야간 이벤트 생성, 큐 정리 |
| DAY_TRANSITION | DAY_END (유지) | `on_day_transition` — 개별 공시 생성, 프리마켓 큐 준비 |
| DAY_TRANSITION → PRE_MARKET | DAY_END → READY | `on_market_state_changed(PRE_MARKET, DAY_TRANSITION)` — 프리마켓 공개 |
| 시즌 종료 | SEASON_END → UNINITIALIZED | `on_season_end` |

#### 일일 슬롯 사전 생성

각 거래일 `on_market_open` 시 그날의 이벤트 스케줄을 **사전 결정**한다:

1. 4개 슬롯 각각의 발생 여부를 확률로 결정
2. 발생하는 슬롯의 발생 틱을 구간 내에서 균등분포 샘플링
3. 각 슬롯의 Scope와 Impact 등급을 사전 결정
4. 스케줄을 내부 리스트에 저장

**템플릿 선택은 해당 틱에 수행**: 쿨다운 상태는 이전 슬롯 처리 후에야
판별 가능하므로, 구체적인 템플릿은 슬롯 발생 틱에 동적으로 선택한다.
Lv4 루머는 슬롯 발생 시각과 Scope/Impact가 확정된 시점에서
`rumor_advance_ticks` 전에 "대상 섹터/종목 관련 공시 임박" 형태로
생성한다 (템플릿 미확정이므로 구체적 내용은 숨김).

**사전 결정의 이점**:
- 매 틱 확률 체크 불필요. `current_tick == schedule[i].tick` 단순 비교만 수행
- Lv4 루머: 발생 시각과 Scope를 미리 알므로 루머 타이밍 결정 가능
- 디버깅 시 "오늘 152틱에 MACRO LARGE 발생 예정" 즉시 확인 가능

단, 최소 보장 이벤트(하루 0건 시 강제 발생)는 장 중반에 동적으로 추가될 수 있다.

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **게임 시계** | 뉴스/이벤트가 의존 | `on_tick` — 슬롯 체크. `on_market_state_changed(new_state, prev_state)` — PRE_MARKET 감지(프리마켓 공개), MARKET_OPEN/CLOSED 전환, DAY_TRANSITION(야간 이벤트 생성), SEASON_END(이벤트 통계 기록 + 시스템 리셋) 트리거. `on_season_start` — 시즌 초기화(이벤트 풀 로드, 테마 배정) |
| **종목 DB** | 뉴스/이벤트가 의존 | `get_stocks_by_event_tag(tag)` — INDIVIDUAL 이벤트 대상 종목 매칭. `get_stocks_by_sector(sector_id)` — SECTOR 이벤트 대상 종목 조회. `get_stock(id)` — 종목명/섹터 변수 주입 |
| **가격 엔진** | 가격 엔진이 이벤트를 소비 | `push_event(Event)` — 생성된 Event 오브젝트 전달. 가격 엔진의 이벤트 큐에 추가 |
| **뉴스 피드 UI** | UI가 뉴스 텍스트를 소비 | `on_news_display(NewsQueueEntry)` — 딜레이 경과 후 뉴스 텍스트 전달. 프리마켓 뉴스 묶음 전달 |
| **스킬 트리** | 뉴스/이벤트가 참조 | `get_market_sense_level()` — 플레이어 딜레이 틱 수 결정. Lv4 시 루머 채널 활성화 |
| **시즌/대회 관리** | 뉴스/이벤트가 참조 | `get_season_theme()` — 활성 시즌 테마 조회. 테마별 이벤트 가중치 적용 |

## Formulas

### 공식 요약

#### F1. 일일 기대 이벤트 수

```
E[daily_events] = Σ(slot_probability_i) for all slots
                = 0.70 + 0.55 + 0.55 + 0.60 = 2.40
```

#### F2. Scope 가중치 (시즌 테마 적용)

```
adjusted_w = base_w × theme_scale
normalized_w = adjusted_w / Σ(adjusted_w_all)
```

#### F3. 템플릿 유효 가중치

```
effective_weight = template.weight_base
                 × theme.sector_bias.get(target_sector, 1.0)
```

#### F4. 종목 선택 가중치 (INDIVIDUAL)

```
stock_weight = sector_sensitivity × volatility_weight
volatility_weight: EXTREME=1.5, HIGH=1.2, MEDIUM=1.0, LOW=0.7
```

#### F5. 뉴스 딜레이

```
display_tick = created_tick + player_delay_ticks
player_delay_ticks: Lv1=30, Lv2=15, Lv3=0
```

#### F6. 루머 발생 (Lv4)

```
rumor_tick = event_scheduled_tick - advance_ticks
advance_ticks = 20
rumor_probability: LARGE/MEGA=1.0, MEDIUM=0.3, SMALL=0.0
```

### 변수 마스터 테이블

| Variable | Default | Range | Owner | Description |
|----------|---------|-------|-------|-------------|
| `slot_probability_opening` | 0.70 | 0.3~0.9 | config | 장 초반 슬롯 발생 확률 |
| `slot_probability_midday` | 0.55 | 0.3~0.8 | config | 장 중반 슬롯 발생 확률 |
| `slot_probability_closing` | 0.60 | 0.3~0.8 | config | 장 후반 슬롯 발생 확률 |
| `scope_weight_individual` | 0.55 | 0.3~0.7 | config | INDIVIDUAL 기본 가중치 |
| `scope_weight_sector` | 0.35 | 0.2~0.5 | config | SECTOR 기본 가중치 |
| `scope_weight_macro` | 0.10 | 0.05~0.3 | config | MACRO 기본 가중치 |
| `daily_hard_cap` | 5 | 3~8 | config | 하루 최대 이벤트 수 |
| `player_delay_lv1` | 30 | 15~60 | config | Lv1 뉴스 딜레이 (틱) |
| `player_delay_lv2` | 15 | 5~30 | config | Lv2 뉴스 딜레이 (틱) |
| `rumor_advance_ticks` | 20 | 10~40 | config | 루머 선행 틱 수 (= Lv4 player_delay의 절대값) |
| `fake_rumor_per_day` | 2 | 0~4 | config | 하루 페이크 루머 수 |
| `overnight_individual_prob` | 0.05 | 0.02~0.10 | config | 야간 개별 공시 확률 |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 모든 슬롯 미발생 (확률적 빈 날) | 장 중반에 SMALL MACRO 1개 강제 발생 | 빈 거래일 방지 |
| 한 틱에 복수 슬롯 겹침 | 순서대로 모두 처리. 각각 독립 Event 생성 | 극히 희박하나 가능 |
| INDIVIDUAL 대상 후보 종목 0개 | SECTOR로 Scope 격상 후 재시도 | 풀 고갈 방지 |
| 쿨다운으로 모든 템플릿 소진 | Impact를 SMALL로 강등 후 재시도. 여전히 없으면 슬롯 건너뜀 | 무한 루프 방지 |
| Lv1 딜레이 뉴스가 장 마감 전 미표시 | INDIVIDUAL/SECTOR: 폐기. MACRO: "오늘의 시장 요약"에 통합 | 정보 비대칭 게임플레이 |
| 페이크 루머와 진짜 루머 동시 발생 | 둘 다 표시. 플레이어가 구분해야 함 | Lv4 스킬의 판단 요소 |
| MEGA 이벤트 2개가 같은 날 추첨 | 두 번째 MEGA를 LARGE로 강등 | 하루 MEGA 최대 1회 |
| 시즌 첫 거래일 (테마 미파악) | 정상 이벤트 발생. 힌트는 hint_revealed_at_day까지 미공개 | 테마 추론이 스킬 |
| 야간 이벤트 + 프리마켓 공시 동시 | 모두 "오늘의 시장 전망"에 묶어 표시. 가격 엔진에 순서대로 전달 | 정보 과부하 방지 |
| GRADUAL_SHIFT 야간 이벤트 진행 중 다음 장 마감 | 잔여 틱 보존. 거래일 경계에서 소실 없음 | 가격 엔진 규칙과 일관 |
| direction=VARIABLE 이벤트 | 50:50 무작위 결정. 뉴스 텍스트도 방향에 맞게 조정 | 예측 불가 이벤트 허용 |
| 강제 발생 vs 하드캡 충돌 | 하드캡(5) 판정이 우선. 슬롯에서 이미 5개 발생 시 강제 발생 없음. 반대로 4슬롯 모두 미발생 시 장 중반에 SMALL MACRO 1개 강제 — 이 강제 이벤트도 하드캡 카운트에 포함 | 하드캡은 절대 상한, 강제는 빈 날 방지용 안전망 |
| Lv4 루머 타이밍 — 이벤트 발생 틱 < rumor_advance_ticks (20) | 루머 display_tick = 0 (PRE_MARKET). 다음 거래일이 아닌 **현재 거래일 PRE_MARKET** 뉴스 묶음에 루머 포함 — 이미 MARKET_OPEN이면 즉시 표시. 루머가 이벤트보다 20틱 전에 표시될 수 없으므로 가능한 만큼만 선행 | 틱 0 이전은 존재하지 않음. 장 초반 이벤트의 루머는 축소된 선행 시간으로 표시 |
| 페이크 루머 생성 기본 사양 | 하루 2회, 장 시작 30~360틱 사이에서 균등분포 배치. 페이크 루머는 실제 이벤트 풀에서 랜덤 template 선택 후 방향/대상만 표시 (실제 이벤트 미발생). `is_fake: true` 플래그로 내부 추적 (UI 비구분). 시즌 종료 시 "루머 적중률" 통계에서 페이크 제외 가능 | 루머 신뢰도 조절. 무조건 루머 추종 전략 방지 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| 게임 시계 | 뉴스/이벤트가 의존 | 틱/상태 시그널로 이벤트 타이밍 결정. **Hard** |
| 종목 DB | 뉴스/이벤트가 의존 | event_tags로 대상 종목 매칭, 종목 속성 참조. **Hard** |
| 가격 엔진 | 가격 엔진이 이벤트를 소비 | Event 오브젝트 전달. **Hard** (가격 엔진 입장) |
| 뉴스 피드 UI | UI가 뉴스 텍스트를 소비 | NewsQueueEntry 전달. **Soft** (UI 없이도 이벤트 생성 가능) |
| 스킬 트리 | 뉴스/이벤트가 참조 | 딜레이 레벨 조회. **Soft** (미구현 시 Lv1 기본값) |
| 시즌/대회 관리 | 뉴스/이벤트가 참조 | 시즌 테마 조회. **Soft** (미구현 시 기본 가중치) |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `slot_probability_*` | 0.55~0.70 | 0.3~0.9 | 이벤트 빈도 증가 | 조용한 시장 |
| `daily_hard_cap` | 5 | 3~8 | 더 바쁜 시장 | 인지 부하 감소 |
| `scope_weight_macro` | 0.10 | 0.05~0.3 | 시장 전체 충격 빈번 | MACRO 희소화 |
| `player_delay_lv1` | 30틱 | 15~60 | 정보 격차 심화. 너무 높으면 이탈 위험 | Lv1도 빠른 반응. 스킬 업그레이드 가치 감소 |
| `rumor_advance_ticks` | 20틱 | 10~40 | 루머 가치 증가. 너무 높으면 Lv4 OP | 선행 시간 감소. 루머 실질 가치 하락 |
| `fake_rumor_per_day` | 2 | 0~4 | 루머 신뢰도 하락 | 루머 과신 가능 |
| `overnight_individual_prob` | 0.05 | 0.02~0.10 | 프리마켓 뉴스 풍부 | 조용한 아침 |
| `theme.sector_bias` | 테마별 상이 | 0.3~3.0 | 테마 편향 강화 | 균등 분포 |
| `impact_tier_weights` | SMALL 35%, MEDIUM 40%, LARGE 20%, MEGA 5% | SMALL 20~50%, MEDIUM 25~50%, LARGE 10~30%, MEGA 2~10%. 합계 100% | LARGE/MEGA 비율↑: 자극적 시장, 빈번한 BREAKOUT | SMALL/MEDIUM 비율↑: 안정적 시장, 분석 중심 |
| `headline 길이 제한` | 30자 | 15~40자 | 더 상세한 헤드라인 | 더 짧은 스캔 |

## Acceptance Criteria

- [ ] 거래일당 평균 2~4개 이벤트가 발생함
- [ ] 하루 최대 5개(하드캡) 초과하지 않음
- [ ] 빈 거래일이 발생하지 않음 (최소 1개 보장)
- [ ] MACRO/SECTOR/INDIVIDUAL 이벤트가 설계 비율대로 분포함
- [ ] 템플릿 변수 치환 후 뉴스 텍스트가 자연스럽게 읽힘
- [ ] Lv1에서 30틱 딜레이 후 뉴스가 표시됨
- [ ] Lv3에서 이벤트와 동시에 뉴스가 표시됨
- [ ] 가격 엔진에 유효한 Event 오브젝트가 정확히 전달됨
- [ ] LARGE+ 이벤트 시 가격 엔진에서 BREAKOUT이 유발됨
- [ ] 시즌 테마에 따라 이벤트 분포가 유의미하게 변화함
- [ ] 야간 이벤트가 다음날 프리마켓에 정확히 공개됨
- [ ] 동일 종목에 90틱 이내 연속 INDIVIDUAL 이벤트 없음
- [ ] MEGA 이벤트가 하루 1회를 초과하지 않음
- [ ] 성능: 일일 슬롯 생성 1ms 이내, 틱당 슬롯 체크 0.1ms 이내

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|------------|
| 이벤트 풀 50개 콘텐츠 실제 작성 — 템플릿별 변수 후보값 포함 | writer + game-designer | V-Slice | MVP는 최소 30개로 시작 |
| direction=VARIABLE 이벤트의 뉴스 텍스트 분기 — 호재/악재 양방향 템플릿 필요 여부 | game-designer | 구현 시 | **결정됨**: `headline_positive`/`headline_negative` + `body_positive`/`body_negative` 듀얼 필드 방식 채택 (규칙 1-3 스키마 참조) |
| Lv4 페이크 루머의 최적 빈도 — 하루 2회가 너무 많거나 적을 수 있음 | game-designer | 프로토타입 후 | 플레이테스트로 조정 |
| 시즌 테마 추가 (5개+) 시 테마 간 밸런스 검증 방법 | systems-designer | V-Slice | 미정 |
| 이벤트 풀 저장 형식 — JSON vs Godot Resource | engine-programmer | 엔진 설정 후 | /setup-engine 후 결정 |
