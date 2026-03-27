# 뉴스 피드 UI (News Feed UI)

> **Status**: In Design
> **Author**: user + game-designer
> **Last Updated**: 2026-03-26
> **Implements Pillar**: 읽는 재미 (Read the Market), 짧고 굵게 (Quick & Punchy)

## Overview

뉴스 피드 UI는 뉴스/이벤트 시스템이 생성한 뉴스를 플레이어에게 표시하는
Presentation 시스템이다. 딜레이 큐를 거쳐 도착하는 뉴스를 시간순 리스트로
보여주며, 프리마켓 뉴스 묶음, 루머 채널(Lv4), 읽음/미읽음 추적, 새 뉴스 알림을
제공한다.

필라 "읽는 재미"에 따라 뉴스의 가독성이 최우선이다. 헤드라인 30자 이내를 3초 안에
스캔하고 핵심(어떤 종목, 호재/악재, 영향 크기)을 파악할 수 있어야 한다.
필라 "짧고 굵게"에 따라 뉴스 피드는 정보를 압축하여 전달하되, 세부 내용은 클릭
시 본문으로 확인할 수 있다.

## Player Fantasy

뉴스 피드가 깜빡인다 — 새 뉴스! 빨간 뱃지 "강한 호재"가 달린 헤드라인이 보인다.
"메디진, 3상 임상시험 최종 성공 발표" — 즉시 차트를 확인한다. 아직 가격에 안
반영됐다! 3초 만에 뉴스 → 판단 → 매매로 이어지는 흐름.

Lv4에서는 루머 탭이 빛난다. "[루머] 바이오 관련 중요 공시 임박" — 진짜일까
페이크일까? 루머를 읽고 판단하는 것 자체가 고레벨 플레이다.

## Detailed Design

### Core Rules

#### 규칙 1. 뉴스 카드 구조

각 뉴스는 다음 요소로 구성된 카드 형태로 표시된다:

```
NewsCard {
    // 표시 요소
    scope_badge: MACRO | SECTOR | INDIVIDUAL   # 색상 코딩된 뱃지
    headline: string                            # 30자 이내 헤드라인
    impact_hint: string                         # 10자 이내 영향 뱃지
    timestamp: string                           # "틱 152 (장 중반)" 형태
    is_read: bool                               # 읽음 여부

    // 확장 시 표시
    body: string                                # 40~60자 본문
    affected_stocks: string[]                   # 영향받는 종목 목록
}
```

##### 1-1. Scope 색상 코딩

| Scope | 뱃지 색상 | 뱃지 텍스트 |
|-------|---------|-----------|
| `MACRO` | 빨강 | 시장 전체 |
| `SECTOR` | 주황 | {sector_name} |
| `INDIVIDUAL` | 파랑 | {company} |

##### 1-2. Impact Hint 스타일

| Impact Tier | 뱃지 스타일 | 예시 |
|------------|-----------|------|
| `SMALL` | 회색, 작은 글씨 | "소폭 영향" |
| `MEDIUM` | 기본, 보통 글씨 | "업종 영향" |
| `LARGE` | 강조, 굵은 글씨 | "강한 호재" |
| `MEGA` | 빨간 테두리, 깜빡임 | "시장 충격" |

#### 규칙 2. 피드 레이아웃

```
┌─────────────────────────────┐
│ 뉴스 피드  [전체|루머]  (3)  │  ← 헤더 + 탭 + 미읽은 수
├─────────────────────────────┤
│ ● [시장 전체] 한국은행 금리...│  ← 미읽음 = ● 표시
│   시장 충격  |  틱 152      │
├─────────────────────────────┤
│   [메디진] 3상 임상시험 성...│  ← 읽음 = 연한 배경
│   강한 호재  |  틱 120      │
├─────────────────────────────┤
│   [반도체] 정부, 수출 물량...│
│   업종 악재  |  틱 85       │
├─────────────────────────────┤
│         ··· 더 보기 ···      │
└─────────────────────────────┘
```

- 최신 뉴스가 상단
- 미읽은 뉴스: ● 마커 + 진한 배경
- 읽은 뉴스: 연한 배경
- 카드 클릭 → 본문 확장 + 읽음 처리 (공유 읽음 상태: '전체' 탭에서 루머를 읽으면 '루머' 탭의 미읽은 수도 감소)

#### 규칙 3. 뉴스 탭

| 탭 | 내용 | 해금 |
|----|------|------|
| **전체** | 모든 뉴스 (시간순) | Lv1 기본 |
| **루머** | 루머 채널 전용 | Lv4 해금 |

Lv4 미해금 시 루머 탭 비활성화 (자물쇠 아이콘 + "시장 감지 Lv4 해금 시 이용 가능").

#### 규칙 4. 프리마켓 뉴스 표시

PRE_MARKET 상태에서 야간/프리마켓 뉴스를 묶음 형태로 표시:

```
┌─────────────────────────────┐
│ [오늘의 시장 전망] 3월 16일  │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━ │
│ • 한국은행, 기준금리 인상 검토│
│   가능성 (시장 전반 영향)    │
│ • 스타칩, 미국 빅테크 대규모 │
│   공급 계약 체결 (개별 호재)  │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━ │
│      [장 시작] 버튼          │
└─────────────────────────────┘
```

프리마켓 뉴스는 별도 스타일로 표시. 장 시작(PRE_MARKET_MODE → ACTIVE 전환) 시
프리마켓 묶음 블록이 해체되어 개별 NewsCard로 변환되며, 일반 피드 상단에 시간순으로
배치된다. 묶음 스타일(테두리, 배경색)은 제거되고 일반 카드 스타일이 적용된다.

#### 규칙 5. 알림 시스템

##### 5-1. 새 뉴스 알림

```
NewsNotification {
    type: BADGE | TOAST | FLASH
    cooldown: int               # 같은 유형 알림 최소 간격 (틱)
}
```

| Impact Tier | 알림 방식 | 쿨다운 |
|------------|---------|--------|
| `SMALL` | BADGE (미읽은 수 카운트만) | — |
| `MEDIUM` | BADGE + 피드 영역 짧은 하이라이트 | 5틱 |
| `LARGE` | TOAST (화면 상단 배너 3초) | 10틱 |
| `MEGA` | FLASH (화면 전체 짧은 플래시 + TOAST) | — |

##### 5-2. 루머 알림 (Lv4)

루머는 전체 탭에도 표시되지만, 루머 탭 뱃지에 별도 카운트.
루머 텍스트는 기울임체 + [루머] 태그로 시각 구분.

#### 규칙 6. 뉴스-종목 연결

뉴스 카드의 종목명을 클릭하면 차트가 해당 종목으로 전환된다.
→ "뉴스 읽기 → 차트 확인 → 매매 판단" 플로우를 UI에서 지원.

SECTOR 뉴스의 경우 영향받는 종목 목록을 본문 확장 시 표시.

#### 규칙 7. 장 마감 시 피드 처리

- 마감 시점의 피드 내용 유지 (정산 중 참고 가능)
- 피드 초기화(FROZEN → EMPTY)는 **PRE_MARKET 진입 시** 발생. 이후 프리마켓 뉴스 묶음이 빈 피드에 표시됨
- 장 시작(MARKET_OPEN) 시에는 초기화 없음 — 프리마켓 뉴스가 일반 피드에 통합되어 유지
- "오늘의 시장 요약"에 통합된 MACRO 뉴스는 요약 형태로 표시

### States and Transitions

| State | Description | Transition |
|-------|-------------|------------|
| **EMPTY** | 뉴스 0건. LOADING 진입 시 또는 시즌/거래일 시작 직후 | → ACTIVE (첫 뉴스 수신 시) / → PRE_MARKET_MODE (Game Clock `PRE_MARKET` 시그널 + 프리마켓 뉴스 존재 시) |
| **ACTIVE** | 뉴스 수신 중. 실시간 갱신 | → FROZEN (Game Clock `MARKET_CLOSED`/`WEEK_END`/`SEASON_END` 시그널 수신 시) |
| **PRE_MARKET_MODE** | 프리마켓 뉴스 묶음 표시 | → ACTIVE (Game Clock `MARKET_OPEN` 시그널 수신 시. 묶음 해체 → 개별 카드 변환) |
| **FROZEN** | 장 마감. 피드 고정. 스크롤만 가능 | → EMPTY (Game Clock `PRE_MARKET` 시그널 수신 시) / → EMPTY (Game Clock `SEASON_END` 후 새 시즌 시작 시) |

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **뉴스/이벤트 시스템** | 뉴스 피드가 의존 | `on_news_display(NewsQueueEntry)` — 딜레이 경과 후 수신. 아래 필드 매핑 참조 |

**NewsQueueEntry → NewsCard 필드 매핑**:

| NewsQueueEntry 필드 | 접근 경로 | NewsCard 필드 | 변환 |
|---------------------|----------|--------------|------|
| `event.scope` | `entry.event.scope` | `scope_badge` | 그대로 사용 (MACRO/SECTOR/INDIVIDUAL) |
| `headline` | `entry.headline` | `headline` | 그대로 사용 |
| `body` | `entry.body` | `body` | 그대로 사용 |
| `impact_hint` | `entry.impact_hint` | `impact_hint` | 그대로 사용 (뉴스/이벤트 시스템이 생성한 문자열) |
| `display_tick` | `entry.display_tick` | `timestamp` | 틱→"틱 N (장 초반/중반/후반)" 형식 변환 |
| `event.target_stocks` | `entry.event.target_stocks[]` | `affected_stocks` | stock_id 목록 → 종목명 변환 (종목 DB 조회) |
| `event.impact_tier` | `entry.event.impact_tier` | (알림 레벨) | SMALL/MEDIUM/LARGE/MEGA → 규칙 5 알림 방식 결정 |
| — | — | `is_read` | UI 로컬 필드 (기본 false) |
| — | — | `display_timestamp` | UI 로컬 필드 (틱→표시 형식 변환) |

> **참고**: `impact_hint`는 `EventTemplate`에 정의된 프리포맷 문자열(예: "개별 종목 강한 호재")을
> 뉴스/이벤트 시스템이 `NewsQueueEntry`에 복사하여 전달한다. UI는 이 문자열을 그대로 표시하며,
> `impact_tier`는 알림 레벨(BADGE/TOAST/FLASH) 결정에만 사용한다.
| **트레이딩 스크린** | 트레이딩 스크린이 뉴스 피드를 호스팅 | 피드 영역 배치. 종목 클릭 이벤트를 차트에 전달 |
| **스킬 트리** | 뉴스 피드가 참조 | `get_market_sense_level()` — Lv4 시 루머 탭 활성화 |
| **게임 시계** | 뉴스 피드가 의존 | `on_market_state_changed` 시그널로 모드 전환. 상태 매핑: Game Clock `PRE_MARKET` → Feed `PRE_MARKET_MODE`, `MARKET_OPEN`/`PAUSED` → Feed `ACTIVE`, `MARKET_CLOSED`/`DAY_TRANSITION`/`WEEK_END`/`SEASON_END` → Feed `FROZEN`. 초기 EMPTY 상태는 Trading Screen LOADING 시 호스트가 직접 설정 (Game Clock 시그널 아님) |

## Formulas

### F1. 뉴스 정렬 우선순위

```
sort_key = (display_tick DESC, impact_priority DESC)
impact_priority: MEGA=4, LARGE=3, MEDIUM=2, SMALL=1
```

동일 틱 뉴스는 Impact가 높은 것이 상단.

### F2. 미읽은 뉴스 카운트

```
unread_count(tab) = count(news where is_read == false and visible_in(tab))
```

- `visible_in("전체")`: 모든 뉴스
- `visible_in("루머")`: 루머 뉴스만
- `is_read`는 카드 단위로 **공유** — '전체' 탭에서 루머를 읽으면 해당 카드의 `is_read = true`가 되어 '루머' 탭의 미읽은 수도 감소

탭별로 별도 카운트. 헤더에 숫자 뱃지로 표시.

### F3. 알림 쿨다운

```
can_show_toast = (current_tick - last_toast_tick) >= toast_cooldown
toast_cooldown = 10틱
```

MEGA는 쿨다운 무시 (항상 표시).

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 같은 틱에 3개 이상 뉴스 동시 수신 | 모두 표시. Impact 높은 순으로 정렬. TOAST는 가장 높은 Impact 1건만 | 정보 과부하 방지 |
| 루머 + 실제 뉴스 동시 수신 | 둘 다 표시. 전체 탭에서 시간순 혼합. 루머는 기울임체로 구분 | Lv4 판단 요소 |
| 장 마감 직전 LARGE 뉴스 | 정상 표시. 마감까지 남은 시간이 짧아도 TOAST 알림 | 마감 전 기회 제공 |
| 프리마켓 뉴스 0건 | "오늘은 특별한 시장 전망이 없습니다" 표시 | 빈 화면 방지 |
| 피드에 뉴스 50건 이상 누적 | 최근 30건만 표시. "더 보기" 클릭 시 **오래된 방향으로** `news_page_size`(기본 10)건 추가 로드 (피드 하단에 추가) | 성능/가독성 보호 |
| 뉴스 카드 클릭으로 종목 전환 중 새 뉴스 수신 | 종목 전환 완료 후 새 뉴스 표시. 전환 중단 없음 | UX 안정성 |
| MACRO 뉴스 (전체 시장 영향) 클릭 | 종목 전환 없음. 본문 확장만 | MACRO는 특정 종목이 아님 |
| Lv4 미해금 상태에서 루머 발생 | 루머 자체가 생성되지 않음. **소유권: 뉴스/이벤트 시스템** — 규칙 4-4에서 `market_sense_level < 4`이면 루머 NewsQueueEntry를 생성하지 않음. 뉴스 피드 UI는 수신한 항목만 표시하며, 루머 필터링 책임 없음 | 시스템 레벨 게이팅 |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| 뉴스/이벤트 시스템 | 뉴스 피드가 의존 | 뉴스 텍스트/메타데이터 수신. **Hard** |
| 트레이딩 스크린 | 트레이딩 스크린이 호스팅 | 영역 배치. **Hard** |
| 스킬 트리 | 뉴스 피드가 참조 | 루머 탭 해금. **Soft** (미구현 시 루머 탭 비활성화) |
| 게임 시계 | 뉴스 피드가 의존 | 시장 상태로 모드 전환. **Hard** |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `max_visible_news` | 30 | 15~50 | 과거 뉴스 더 많이 조회 | 성능/가독성 개선 |
| `toast_duration` | 3초 | 2~5초 | 더 오래 보임 | 빠르게 사라짐 |
| `toast_cooldown` | 10틱 | 5~20틱 | 알림 빈도 감소 | 더 잦은 알림. 근거: 10틱 ≈ 약 10초(1x 기준). LARGE 이벤트가 10초 내 연속 발생은 드물며, 발생 시 첫 알림이 충분 |
| `mega_flash_duration` | 0.3초 | 0.1~0.5초 | 강렬한 경고 | 미묘한 경고 |
| `card_headline_font_size` | 14px | 12~18px | 큰 글씨. 빠른 스캔 | 더 많은 뉴스 표시 |
| `card_body_max_lines` | 3 | 2~5 | 더 자세한 본문 | 간결한 피드 |
| `news_page_size` | 10 | 5~20 | "더 보기" 클릭 시 추가 로드 건수 | 적은 추가 로드 |

## Acceptance Criteria

- [ ] 뉴스 카드에 scope 뱃지, 헤드라인, impact_hint, 타임스탬프가 정확히 표시됨
- [ ] Scope별 색상 코딩이 정확함 (MACRO=빨강, SECTOR=주황, INDIVIDUAL=파랑)
- [ ] Impact 등급별 알림 방식이 정확히 적용됨
- [ ] 미읽은 뉴스에 ● 마커 + 진한 배경이 표시됨
- [ ] 카드 클릭 시 본문 확장 + 읽음 처리
- [ ] 종목명 클릭 시 차트가 해당 종목으로 전환됨
- [ ] 프리마켓 뉴스가 "오늘의 시장 전망" 형태로 묶어 표시됨
- [ ] Lv4 해금 시 루머 탭이 활성화되고 루머가 기울임체로 구분됨
- [ ] 최신 뉴스가 상단에 정렬됨
- [ ] 30건 이상 뉴스 시 "더 보기" 페이지네이션 정상 작동
- [ ] MEGA 뉴스 시 FLASH + TOAST 알림이 표시됨
- [ ] 장 마감 시 피드 고정, 다음 거래일 PRE_MARKET 진입 시 초기화
- [ ] MEGA 플래시 발생 시 진행 중인 주문 입력 폼의 포커스/값이 유지됨 (입력 중단 없음)

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|------------|
| 뉴스 피드 위치 — 트레이딩 스크린 우측 vs 하단 | ux-designer | 트레이딩 스크린 GDD 시 | 트레이딩 스크린에서 결정 |
| 뉴스 필터 기능 (Scope별, 종목별) 필요 여부 | game-designer | V-Slice | MVP는 전체+루머 탭만 |
| 뉴스 히스토리 (이전 거래일 뉴스 조회) | game-designer | 세이브/로드 GDD 시 | 미정 |
