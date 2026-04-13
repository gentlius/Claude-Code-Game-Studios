# 스킬 구현 로드맵 (Skill Implementation Roadmap)

> **Status**: Active
> **Author**: game-designer
> **Last Updated**: 2026-04-07 (실제 코드 전수 확인 기준 업데이트)
> **Source**: skill-tree.md audit + 코드 검증 (chart_renderer.gd, order_panel.gd, news_feed.gd, skill_tree.gd)

---

## Overview

이 문서는 시드머니의 14개 스킬을 구현 우선순위에 따라 5단계 페이즈로 정리한 로드맵이다.
우선순위 기준은 세 가지다: (1) 플레이어가 스킬의 효과를 즉각 체감할 수 있는가
(Efficacy Signal), (2) 구현 복잡도 대비 플레이어 경험 향상 비율, (3) 다른 스킬의
선행 조건 역할 여부.

현재 상태 요약 (2026-04-07 코드 검증 기준):
A1/A2 Analysis 브랜치 게임플레이+UI 전부 완료. S1/S2/P1/P2는 게임플레이만 있고 UI 피드백 없음.
TR1은 🔒 텍스트 게이트 있으나 버튼 비활성화 미완. S3/TR3/TR4는 스텁. TR2/A3/A4/P3 미구현.

---

## 현재 상태 스냅샷 (2026-04-07 기준 — 코드 실측)

| ID | 스킬명 | 브랜치 | 게임플레이 | UI 피드백 | 전반적 상태 | 대상 페이즈 |
|----|--------|--------|-----------|----------|------------|------------|
| A1 | 이동평균선 | Analysis | ✅ Done | ✅ Done | **Complete** | — |
| A2 | 보조지표 (RSI/MACD) | Analysis | ✅ Done | ✅ Done | **Complete** | ~~Phase 2~~ |
| A3 | 재무제표 (PER/PBR/ROE) | Analysis | ❌ Not Built | ❌ Not Built | Not Started | Phase 4 |
| A4 | 섹터 비교 분석 | Analysis | ❌ Not Built | ❌ Not Built | Not Started | Phase 5 |
| S1 | 빠른 뉴스 | Sense | ✅ Done | ❌ Missing | Gameplay-Only | Phase 1 |
| S2 | 실시간 뉴스 | Sense | ✅ Done | ❌ Missing | Gameplay-Only | Phase 1 |
| S3 | 루머 채널 | Sense | 🔶 Stub Only | ❌ Missing | Not Started | Phase 4 |
| TR1 | 지정가 주문 | Trading | ✅ Done | ⚠️ Partial Gate | Partial | Phase 1 |
| TR2 | 손절/익절 | Trading | ❌ Not Built | ❌ Not Built | Not Started | Phase 3 |
| TR3 | 공매도 | Trading | 🔶 Stub Only | ❌ Missing | Not Started | Phase 4 |
| TR4 | 레버리지 | Trading | 🔶 Stub Only | ❌ Missing | Not Started | Phase 4 |
| P1 | 5종목 보유 | Portfolio | ✅ Done | ❌ Missing | Gameplay-Only | Phase 1 |
| P2 | 10종목 보유 | Portfolio | ✅ Done | ❌ Missing | Gameplay-Only | Phase 1 |
| P3 | 섹터 ETF | Portfolio | ❌ Not Built | ❌ Not Built | Not Started | Phase 5 |

> **A2 완료 확인 (2026-04-07)**: `chart_renderer.gd`에 `_draw_rsi()` / `_draw_macd()` 완전 구현됨. `_rsi_cache` 사전 계산 방식(O(visible) per draw). 레이아웃 4-zone 분할(chart 55%, RSI 15%, MACD 15%, volume 15%). A2 해금 여부에 따라 서브패널 자동 표시/숨김. 이전 "Not Built" 표기는 오류.

> **TR1 Partial Gate 설명 (2026-04-07 업데이트)**: `order_panel.gd`에서 미해금 시 버튼 텍스트 "지정가 🔒" 표시. 버튼은 여전히 클릭 가능하며 주문 제출 시 에러 메시지. 목표: 버튼 자체 비활성(회색) + 툴팁. Sprint 6 S6-02에서 완성.

---

## 페이즈별 로드맵

---

### Phase 1 — Quick Wins (UI Feedback + Skill Gates)

**목표**: 이미 작동하는 게임플레이에 플레이어가 느낄 수 있는 피드백을 추가한다.
코드 변경 최소화, 체감 향상 최대화.

**이론적 근거**: MDA Framework에서 Aesthetics(체감)는 Mechanics(규칙)가 아닌
Dynamics(행동 패턴)에서 발생한다. 현재 S1/S2/P1/P2는 Mechanic은 있으나 Dynamic이
없다 — 플레이어가 스킬 효과를 인지하지 못하면 스킬 트리의 "체감있는 성장" 필라가
완전히 무너진다.

| ID | 스킬명 | 해야 할 것 | 복잡도 | Efficacy Signal |
|----|--------|-----------|--------|----------------|
| S1 | 빠른 뉴스 | 뉴스 피드 UI에 뉴스 수신 시 "FAST" 배지 표시. 현재 딜레이 값(틱)을 스킬 트리 UI에 표기 | S | "딜레이가 줄었다는 걸 배지로 확인, 다른 플레이어보다 먼저 보인다는 느낌" |
| S2 | 실시간 뉴스 | 뉴스 피드 UI에 "LIVE" 배지 + 붉은 점(실시간 인디케이터). 스킬 트리에 "0틱 딜레이" 명시 | S | "뉴스가 뜨는 순간 내 화면에 바로 등장. 배지가 우월감을 시각화" |
| P1 | 5종목 보유 | 포트폴리오 UI 상단에 "보유 슬롯: 3/5" 형태의 카운터 표시. 슬롯 아이콘 5개 중 잠금/열림 상태 | S | "빈 슬롯이 보인다. 채울 수 있다. 더 많이 담을 수 있다는 여유" |
| P2 | 10종목 보유 | 동일 — 카운터를 "5/10"으로 갱신. 슬롯 아이콘 확장 | S | "포트폴리오가 넓어졌다. 분산투자가 가능해졌다는 시각적 확인" |
| TR1 | 지정가 주문 | 주문 엔진에 `is_skill_unlocked("TR1")` 체크 추가 — 미해금 플레이어는 지정가 탭 비활성(회색) + "TR1 해금 필요" 툴팁 | S | "잠겨 있던 탭이 열린다. 처음으로 지정가 주문 버튼이 활성화되는 순간" |

**Phase 1 Dependencies**: 뉴스 피드 UI (`news-feed-ui.md`), 포트폴리오 UI (`portfolio-ui.md`), 주문 엔진 (`order-engine.md`), 스킬 트리 시스템 (`skill-tree.md`)

**Phase 1 완료 기준**:
- S1/S2 배지가 스킬 해금 여부에 따라 정확히 표시/비표시된다
- P1/P2 슬롯 카운터가 현재 보유 종목 수와 최대 종목 수를 정확히 반영한다
- TR1 미해금 상태에서 지정가 탭이 비활성화되어 클릭되지 않는다
- TR1 해금 즉시 지정가 탭이 활성화된다

---

### Phase 2 — Chart Enhancements (A2 보조지표)

**목표**: 차트 하단에 RSI(14)와 MACD(12,26,9) 서브패널을 구현한다.
A2는 TR3(공매도)의 크로스 브랜치 선행 조건이므로, Phase 4 전에 반드시 완료되어야 한다.

**이론적 근거**: 분석 브랜치의 핵심 성장 경로. A1(MA선)이 "추세를 보는 눈"을 주었다면
A2는 "타이밍을 재는 도구"를 준다. Flow State 관점에서 새로운 정보 레이어 추가 = 새로운
숙련 목표 제공 = 플레이어를 flow channel에 재진입시키는 매커니즘.

| ID | 스킬명 | 해야 할 것 | 복잡도 | Efficacy Signal |
|----|--------|-----------|--------|----------------|
| A2 | 보조지표 (RSI/MACD) | **게임플레이**: RSI(14) 계산 로직, MACD(12,26,9) 계산 로직을 가격 히스토리 데이터 기반으로 구현. **UI**: 차트 렌더러 하단에 스위처블 서브패널 (RSI 뷰 / MACD 뷰). RSI 70/30 과매수/과매도 선, MACD 히스토그램 + 시그널선 표시 | M | "RSI가 30 아래로 내려갔다. 여기서 샀더니 반등했다. 차트가 나한테 말을 거는 것 같다" |

**A2 세부 구현 항목**:

| 항목 | 설명 |
|------|------|
| RSI 계산 | `RSI = 100 - (100 / (1 + RS))`, RS = 14기간 평균상승폭 / 14기간 평균하락폭. 가격 히스토리 최소 14개 캔들 필요 |
| MACD 계산 | `MACD line = EMA(12) - EMA(26)`, `Signal line = EMA(9) of MACD line`, `Histogram = MACD - Signal` |
| 서브패널 레이아웃 | 차트 영역 하단 25% 분할. RSI/MACD 탭 스위처. A2 미해금 시 패널 숨김 |
| 과매수/과매도 표시 | RSI 70 (빨간 점선), RSI 30 (파란 점선), 구간 배경 반투명 채색 |
| 데이터 부족 처리 | 히스토리 14캔들 미만 시 "데이터 수집 중" 메시지. 0으로 채우지 않음 |

**Phase 2 Dependencies**: 차트 렌더러 (`chart-renderer.md`), 가격 엔진 (`price-engine.md`), 스킬 트리 (`skill-tree.md`)

**Phase 2 완료 기준**:
- A2 해금 시 차트 하단에 서브패널이 나타난다
- A2 미해금 시 서브패널이 보이지 않는다
- RSI 계산값이 14기간 이동평균 기반으로 수학적으로 정확하다
- MACD 히스토그램이 골든크로스/데드크로스 시점에서 부호 전환을 보인다
- 유닛 테스트: 알려진 가격 시퀀스에 대해 RSI/MACD 기대값 검증

---

### Phase 3 — Trading Features (TR2 손절/익절)

**목표**: 보유 종목에 자동 매도 조건을 설정하는 손절/익절 시스템을 구현한다.

**이론적 근거**: Self-Determination Theory의 Autonomy 욕구에 직접 응답하는 스킬.
플레이어가 "내가 없어도 내 전략이 실행된다"는 감각은 고급 트레이더로서의 정체성을 강화한다.
TR2는 TR1(지정가)의 개념을 "보유 포지션"으로 확장하는 자연스러운 성장 경로다.

| ID | 스킬명 | 해야 할 것 | 복잡도 | Efficacy Signal |
|----|--------|-----------|--------|----------------|
| TR2 | 손절/익절 | **게임플레이**: 각 보유 종목에 `stop_loss_price`와 `take_profit_price` 필드 추가. 주문 엔진의 틱 처리 루프에서 가격이 조건 충족 시 자동 시장가 매도 실행. **UI**: 포트폴리오 UI의 각 보유 종목 행에 손절/익절가 입력 필드 + 활성/비활성 토글. 조건 충족 시 체결 알림 | M | "잠들어 있었는데 알림이 왔다. 손절가에 자동 매도됐다. 내가 설정한 전략이 나 대신 일했다" |

**TR2 세부 구현 항목**:

| 항목 | 설명 |
|------|------|
| 데이터 구조 | `HoldingConditions { stop_loss: int\|null, take_profit: int\|null }`. 종목 ID를 키로 딕셔너리 저장 |
| 틱 체크 순서 | 가격 갱신 후, 주문 처리 전 단계에서 조건 체크. 체결 순서: 손절 먼저, 익절 나중 |
| 동시 조건 처리 | 같은 틱에 손절/익절 동시 충족 불가 (가격은 하나). 논리적으로 배타적 |
| TR2 미해금 처리 | 포트폴리오 UI에서 해당 입력 필드 비활성 + "TR2 해금 필요" 툴팁 |
| 조건 취소 | null로 설정 시 조건 비활성화. 매도 후 자동으로 해당 종목 조건 삭제 |
| 가격 유효성 | 손절가 > 현재가 또는 익절가 < 현재가 설정 시 경고 (하지만 허용 — 미래 가격 대비 설정 가능) |

**Phase 3 Dependencies**: 주문 엔진 (`order-engine.md`), 포트폴리오 관리 (`portfolio-manager.md`), 포트폴리오 UI (`portfolio-ui.md`), TR1 해금 (선행 조건)

**Phase 3 완료 기준**:
- 손절가 설정 후 가격이 해당 가격 이하로 하락 시 자동 매도 체결된다
- 익절가 설정 후 가격이 해당 가격 이상으로 상승 시 자동 매도 체결된다
- 자동 체결 후 플레이어에게 알림이 표시된다
- TR2 미해금 상태에서 UI 입력 필드가 비활성화된다
- 유닛 테스트: 조건 설정 → 가격 시뮬레이션 → 자동 체결 확인

---

### Phase 4 — Advanced Features (S3, A3, TR3, TR4)

**목표**: 게임의 고급 플레이 레이어를 구성하는 4개 스킬을 구현한다.
각 스킬이 독립적인 시스템을 요구하므로 순차적으로 구현한다.

**권장 구현 순서**: S3 → A3 → TR3 → TR4 (의존성 및 복잡도 기준)

#### S3 — 루머 채널

| 항목 | 내용 |
|------|------|
| 복잡도 | M |
| 해야 할 것 (게임플레이) | 뉴스/이벤트 시스템에 루머 생성 로직 추가. 이벤트 스케줄 시점에서 `rumor_lead_ticks`(기본값 60틱) 전에 루머 이벤트 생성. 70% 확률로 올바른 방향, 30% 확률로 반전된 방향 |
| 해야 할 것 (UI) | 뉴스 피드에 `[루머]` 태그가 붙은 별도 스타일 메시지. 루머와 실제 뉴스가 도달했을 때 시각적 연결 (같은 종목의 루머-뉴스 쌍을 하이라이트) |
| Efficacy Signal | "루머가 떴다. 방향을 믿어야 하나 말아야 하나. 70%다 — 질러보자. 맞았다! 아니면 틀렸다! 확률과 싸우는 쾌감" |
| Dependencies | 뉴스/이벤트 시스템, 뉴스 피드 UI, S2 해금 (선행 조건) |

#### A3 — 재무제표

| 항목 | 내용 |
|------|------|
| 복잡도 | L |
| 해야 할 것 (게임플레이) | 종목 데이터베이스에 각 종목별 PER, PBR, ROE 기초 수치 추가. 분기별 실적 발표 이벤트와 연동하여 수치 변동. 적정가치 계산: `fair_value = EPS × target_PER` |
| 해야 할 것 (UI) | 차트 우측 또는 별도 탭에 기업정보 패널. PER/PBR/ROE 수치 + 섹터 평균과 비교 막대. A3 미해금 시 패널 잠금 상태(흐릿하게 표시 + 해금 유도) |
| Efficacy Signal | "PER 5배짜리 저평가 종목을 발견했다. 섹터 평균은 15배다. 이건 사야해. 숫자가 나한테 신호를 준다" |
| Dependencies | 종목 데이터베이스 (`stock-database.md`), 뉴스/이벤트 시스템 (실적 이벤트), A2 해금 (선행 조건) |

#### TR3 — 공매도

| 항목 | 내용 |
|------|------|
| 복잡도 | L |
| 해야 할 것 (게임플레이) | 포트폴리오에 숏 포지션 타입 추가. 매도 주문 시 보유 없이 제출 가능(TR3 해금 시). 청산은 반대 매수 주문. 손익 계산: `pnl = (short_price - current_price) × quantity`. 마진 요건: 공매도 금액의 100%를 증거금으로 차감 |
| 해야 할 것 (UI) | 주문 패널에 "공매도" 탭. 포트폴리오 UI에 숏 포지션 별도 구분 표시(빨간 배경). 숏 포지션 손익은 반전 표시(가격 하락 = 수익) |
| Efficacy Signal | "다들 살 때 나는 팔았다. 가격이 내려갈수록 내 계좌가 올라간다. 시장이 무너질 때 웃는 쾌감" |
| Dependencies | 주문 엔진, 포트폴리오 관리, TR2 해금 + A2 해금 (크로스 브랜치 선행 조건) |

#### TR4 — 레버리지

| 항목 | 내용 |
|------|------|
| 복잡도 | L |
| 해야 할 것 (게임플레이) | 매수 주문 시 `leverage_ratio`(기본 2.0) 옵션 추가. 실효 포지션 = `quantity × price × leverage_ratio`. 마진콜 조건: 손실이 `initial_investment / leverage_ratio` 초과 시 강제 청산. 음수 자산 방지: 0으로 클램프 후 강제 청산 |
| 해야 할 것 (UI) | 주문 패널에 레버리지 배율 슬라이더 또는 토글(1x / 2x). 레버리지 포지션은 포트폴리오에 "×2" 배지 표시. 마진콜 경고 알림 (손실이 마진콜 임계치의 80% 도달 시 사전 경고) |
| Efficacy Signal | "2배 레버리지. 5% 올랐는데 내 수익은 10%다. 심장이 두 배로 뛴다. 틀리면 두 배로 아프다는 것도 안다" |
| Dependencies | 주문 엔진, 포트폴리오 관리, 재화 시스템 (마진 계산), TR3 해금 (선행 조건) |

**Phase 4 완료 기준**:
- S3: 루머 메시지가 해당 뉴스보다 `rumor_lead_ticks` 앞서 도달한다. 30% 확률로 방향 반전 루머가 생성된다
- A3: PER/PBR/ROE 수치가 종목 데이터베이스에서 읽혀 패널에 표시된다
- TR3: 공매도 포지션이 가격 하락 시 양의 PnL을 기록한다. 마진 증거금이 정확히 차감된다
- TR4: 2x 레버리지 포지션에서 1% 가격 변동이 2%의 PnL 변화를 만든다. 마진콜이 정확히 발동한다

---

### Phase 5 — Endgame Systems (A4, P3)

**목표**: 완전 분산 투자 전략가를 위한 최고 난이도 도구를 구현한다.
A4와 P3는 서로 크로스 브랜치 의존성으로 묶여 있으므로 함께 설계해야 한다.

**이론적 근거**: Bartle의 Achiever 타입을 위한 최종 마일스톤. "모든 스킬을 해금했다"는 완성감과
함께, 섹터 단위의 포트폴리오 관리라는 새로운 전략 공간이 열린다. 이 두 스킬은 게임의
최장기 플레이어를 위한 Meta-game layer다.

#### A4 — 섹터 비교 분석

| 항목 | 내용 |
|------|------|
| 복잡도 | XL |
| 해야 할 것 (게임플레이) | 각 틱마다 섹터별 평균 수익률 계산 및 집계. 상대강도 지수 = `(섹터 수익률 - 전체 시장 평균) / 전체 시장 변동성`. 섹터 로테이션 패턴을 가격 엔진의 시즌 테마와 연동 |
| 해야 할 것 (UI) | 트레이딩 스크린에 섹터 히트맵 오버레이 또는 별도 섹터 비교 뷰. 섹터별 등락률 막대 차트 (당일 / 주간 / 시즌 기간 선택 가능). 섹터 내 개별 종목 드릴다운 |
| Efficacy Signal | "IT 섹터가 오늘 전체에서 가장 강하다. 나머지는 다 빨간데 IT만 초록이다. 여기에 집중해야겠다" |
| Dependencies | 종목 데이터베이스 (섹터 분류), 가격 엔진 (실시간 섹터 수익률), A3 해금 (선행 조건) |

#### P3 — 섹터 ETF

| 항목 | 내용 |
|------|------|
| 복잡도 | XL |
| 해야 할 것 (게임플레이) | 섹터 ETF를 특수 종목 타입으로 구현. ETF 가격 = 해당 섹터 내 종목들의 시가총액 가중 평균가. 매수 시 실제 개별 종목 대신 ETF 슬롯 1개 차지. 배당/비용 없음 (단순 인덱스 추종) |
| 해야 할 것 (UI) | 종목 선택 목록에 "ETF" 카테고리 추가. 각 섹터별 ETF 1개. ETF 상세 뷰에서 구성 종목 가중치 표시. P2 + A4 동시 미해금 시 ETF 탭 잠금 |
| Efficacy Signal | "섹터가 오를 것 같은데 어떤 종목을 골라야 할지 모르겠다. ETF를 하나 사자. 섹터 전체에 베팅한다" |
| Dependencies | 종목 데이터베이스 (섹터 구성), 가격 엔진 (실시간 ETF 가격 계산), 포트폴리오 관리 (ETF 보유 처리), P2 해금 + A4 해금 (크로스 브랜치 선행 조건) |

**Phase 5 완료 기준**:
- A4: 섹터별 상대강도가 매 틱 갱신되며 히트맵에 반영된다
- A4: 시즌 테마에서 강세 섹터로 지정된 섹터가 히트맵에서 일관되게 상위권을 기록한다
- P3: ETF 가격이 구성 종목들의 가중 평균을 정확히 추종한다
- P3: ETF 매수 시 포트폴리오 슬롯 1개를 차지한다 (종목 수 제한 적용)
- P2 또는 A4 미해금 시 ETF 탭이 접근 불가하다

---

## 전체 일정 요약

| 페이즈 | 대상 스킬 | 총 복잡도 | 핵심 가치 |
|--------|-----------|----------|----------|
| Phase 1 | S1, S2, P1, P2, TR1 (gate 교체) | 5 × S | 이미 작동하는 기능을 플레이어가 느끼게 만든다 |
| Phase 2 | A2 | M | TR3의 크로스 브랜치 선행 조건 해소. 차트 분석 심화 |
| Phase 3 | TR2 | M | 자동화 전략의 첫 경험. 고급 트레이더 정체성 형성 |
| Phase 4 | S3, A3, TR3, TR4 | M + L + L + L | 게임의 고위험/고보상 플레이 레이어 완성 |
| Phase 5 | A4, P3 | XL + XL | 섹터 단위 메타게임. 최고 숙련 플레이어를 위한 엔드게임 |

---

## 스킬 제작 스케줄

> **기준**: Sprint 3 종료(2026-04-28) 후 Alpha 마일스톤 진입 가정.
> Phase 1은 V-Slice 이후 첫 Alpha 스프린트에서 즉시 착수 — V-Slice 체험 시 스킬 피드백이 없으면 "성장 체감" 기준 미충족으로 이어질 수 있음.

### 페이즈 → 스프린트 매핑

| 페이즈 | 스프린트 | 기간 (추정) | 마일스톤 | 스킬 수 | 총 복잡도 |
|--------|---------|-----------|---------|---------|---------|
| Phase 1 | Sprint 4 | 2026-04-29 ~ 2026-05-12 | Alpha | 5개 (UI 피드백 + gate 교체) | 5 × S = ~1.5 sessions |
| Phase 2 | Sprint 4 후반 ~ Sprint 5 | 2026-04-29 ~ 2026-05-26 | Alpha | 1개 (RSI/MACD) | M = ~2 sessions |
| Phase 3 | Sprint 5 ~ Sprint 6 | 2026-05-13 ~ 2026-06-09 | Alpha | 1개 (손절/익절) | M = ~2 sessions |
| Phase 4 | Sprint 6 ~ Sprint 8 | 2026-05-27 ~ 2026-07-07 | Alpha | 4개 (S3, A3, TR3, TR4) | M+L+L+L = ~6 sessions |
| Phase 5 | Sprint 9 ~ Sprint 10 | 2026-07-08 ~ 2026-08-04 | Full | 2개 (A4, P3) | XL+XL = ~5 sessions |

> **Sprint 4 전략**: Phase 1은 S이므로 Sprint 4 전반부(~1.5 sessions)에 끝낼 수 있다. 남은 session을 Phase 2(A2) 착수에 사용. Sprint 4에서 Phase 1 + Phase 2 착수를 목표로 한다.

---

### Phase 1 상세 태스크 (Sprint 4 — Must Have)

> **전제**: Phase 1은 모두 Small 복잡도이므로 Sprint 4에서 한 번에 처리.
> Lead Programmer + UI Programmer 병행 가능 (S1/S2/P1/P2 UI vs TR1 gate 교체).

| ID | 스킬 | 담당 | 파일 | 작업 내용 | Est. |
|----|------|------|------|----------|------|
| SK1-01 | S1 "FAST" 배지 | ui-programmer | `src/ui/news_feed_ui.gd` | 뉴스 수신 시 S1 해금 여부 확인 → `[FAST]` 배지 라벨 추가. 미해금 시 숨김 | 0.25 day |
| SK1-02 | S2 "LIVE" 배지 | ui-programmer | `src/ui/news_feed_ui.gd` | S2 해금 시 `[LIVE]` 붉은 점 인디케이터 + 별도 스타일 메시지 | 0.25 day |
| SK1-03 | P1 슬롯 카운터 | ui-programmer | `src/ui/portfolio_ui.gd` | 상단에 "보유 슬롯: N/5" 카운터 + 슬롯 아이콘 5개 (잠금/열림 상태). P1 미해금 시 "N/3" | 0.5 day |
| SK1-04 | P2 슬롯 확장 | ui-programmer | `src/ui/portfolio_ui.gd` | P2 해금 시 카운터 최대값 10으로 갱신. 아이콘 10개로 확장 | 0.25 day |
| SK1-05 | TR1 gate 교체 | lead-programmer | `src/ui/trading_screen.gd` | 현재 에러 방식 → 지정가 라디오 버튼 `disabled = true` + 툴팁 "TR1 스킬 해금 필요". 해금 시 즉시 활성화 (XpSystem.on_skill_unlocked 시그널 연결) | 0.5 day |

**Phase 1 AC → 테스트 매핑**

| AC | 설명 | 테스트 파일 | 테스트 함수 |
|----|------|-----------|-----------|
| Ph1-AC-01 | S1 해금 시 뉴스에 FAST 배지 표시, 미해금 시 숨김 | `tests/unit/test_skill_ui_contracts.gd` | `test_s1_badge_visible_when_unlocked()` |
| Ph1-AC-02 | S2 해금 시 LIVE 인디케이터 표시 | `tests/unit/test_skill_ui_contracts.gd` | `test_s2_live_indicator_visible_when_unlocked()` |
| Ph1-AC-03 | P1 해금 시 슬롯 카운터 최대 5로 표시 | `tests/unit/test_skill_ui_contracts.gd` | `test_p1_slot_counter_shows_five()` |
| Ph1-AC-04 | P2 해금 시 슬롯 카운터 최대 10으로 갱신 | `tests/unit/test_skill_ui_contracts.gd` | `test_p2_slot_counter_shows_ten()` |
| Ph1-AC-05 | TR1 미해금 시 지정가 라디오 버튼 disabled | `tests/unit/test_skill_ui_contracts.gd` | `test_tr1_limit_button_disabled_when_locked()` |
| Ph1-AC-06 | TR1 해금 즉시 지정가 라디오 버튼 활성화 | `tests/unit/test_skill_ui_contracts.gd` | `test_tr1_limit_button_enabled_on_unlock()` |

---

### Phase 2 상세 태스크 (Sprint 4 후반 ~ Sprint 5)

| ID | 스킬 | 담당 | 파일 | 작업 내용 | Est. |
|----|------|------|------|----------|------|
| SK2-01 | A2 게임플레이 (RSI) | gameplay-programmer | `src/gameplay/price_engine.gd` | RSI(14) 계산 함수 추가. 가격 히스토리 14캔들 기반. `get_rsi(stock_id) -> float` | 0.5 day |
| SK2-02 | A2 게임플레이 (MACD) | gameplay-programmer | `src/gameplay/price_engine.gd` | MACD(12,26,9) 계산 함수 추가. `get_macd(stock_id) -> Dictionary` (line, signal, histogram) | 0.5 day |
| SK2-03 | A2 UI (서브패널) | ui-programmer | `src/ui/chart_renderer.gd` | 차트 하단 25% 서브패널. RSI/MACD 탭 스위처. A2 미해금 시 패널 숨김. RSI 70/30 기준선 | 2 days |
| SK2-04 | A2 유닛 테스트 | lead-programmer | `tests/unit/test_price_engine.gd` | 알려진 가격 시퀀스 → RSI/MACD 기대값 검증. 데이터 부족(< 14캔들) 엣지 케이스 | 0.5 day |

---

### Phase 3 상세 태스크 (Sprint 5 ~ 6)

| ID | 스킬 | 담당 | 파일 | 작업 내용 | Est. |
|----|------|------|------|----------|------|
| SK3-01 | TR2 게임플레이 | gameplay-programmer | `src/gameplay/order_engine.gd`, `src/gameplay/portfolio_manager.gd` | 보유 종목별 `stop_loss_price`, `take_profit_price` 저장. 틱 체크: 조건 충족 시 자동 시장가 매도 | 1 day |
| SK3-02 | TR2 UI | ui-programmer | `src/ui/portfolio_ui.gd` (또는 `trading_screen.gd`) | 보유 종목 행에 손절/익절가 입력 필드 + 활성/비활성 토글. TR2 미해금 시 비활성화 + 툴팁 | 1 day |
| SK3-03 | TR2 알림 | ui-programmer | `src/ui/trading_screen.gd` | 조건 충족 자동 체결 시 토스트 알림 ("삼성전자 손절 자동 체결 −5.2%") | 0.5 day |
| SK3-04 | TR2 유닛 테스트 | lead-programmer | `tests/unit/test_order_engine.gd` | 조건 설정 → 가격 시뮬레이션 → 자동 체결 확인. 동시 조건 불가 케이스 | 0.5 day |

---

### Phase 4 상세 태스크 (Sprint 6 ~ 8)

> 4개 스킬이 각각 독립적인 신규 시스템이므로 Sprint 당 1~2개 처리.

| ID | 스킬 | Sprint | 담당 | Est. |
|----|------|--------|------|------|
| SK4-01 | S3 루머 채널 (게임플레이 + UI) | Sprint 6 | gameplay-programmer + ui-programmer | 2 days |
| SK4-02 | A3 재무제표 (게임플레이 + UI) | Sprint 6 ~ 7 | gameplay-programmer + ui-programmer | 3 days |
| SK4-03 | TR3 공매도 (게임플레이 + UI) | Sprint 7 ~ 8 | gameplay-programmer + ui-programmer | 3 days |
| SK4-04 | TR4 레버리지 (게임플레이 + UI) | Sprint 8 | gameplay-programmer + ui-programmer | 3 days |

> **주의**: TR3는 포트폴리오 PnL 계산 전체 재검토 필요 (위험 요소 참조). Sprint 7 전에 PnL 계산 회귀 테스트를 먼저 완비해야 한다.

---

### Phase 5 상세 태스크 (Sprint 9 ~ 10)

| ID | 스킬 | Sprint | 담당 | Est. |
|----|------|--------|------|------|
| SK5-01 | A4 섹터 비교 분석 (게임플레이 + UI) | Sprint 9 | gameplay-programmer + ui-programmer | 4 days |
| SK5-02 | P3 섹터 ETF (게임플레이 + UI) | Sprint 9 ~ 10 | gameplay-programmer + ui-programmer | 4 days |

> A4와 P3는 크로스 브랜치 의존성. A4 섹터 집계 캐시를 P3 ETF 가격 계산에 재사용할 것.

---

### 스킬 완성도 예측 타임라인

```
Sprint 3 (현재): V-Slice 완성. 스킬 1/14 완료 (A1만)
Sprint 4:        Phase 1 + Phase 2 착수. 스킬 6/14 완료 (A1 + S1/S2/P1/P2/TR1 UI + A2 착수)
Sprint 5:        Phase 2 완료 + Phase 3 착수. 스킬 7/14 완료 (+ A2)
Sprint 6:        Phase 3 완료 + Phase 4 착수. 스킬 9/14 완료 (+ TR2 + S3)
Sprint 7~8:      Phase 4 완료. 스킬 12/14 완료 (+ A3 + TR3 + TR4)
Sprint 9~10:     Phase 5 완료. 스킬 14/14 완료 (+ A4 + P3) — Full Vision 마일스톤
```

---

## 의존성 체인 요약

```
A1(Done) → A2(Ph2) → A3(Ph4) → A4(Ph5)
                  ↘
                   TR3(Ph4) → TR4(Ph4)
                  ↗
S1(Ph1) → S2(Ph1) → S3(Ph4)

TR1(Ph1 gate) → TR2(Ph3) → TR3(Ph4) → TR4(Ph4)

P1(Ph1) → P2(Ph1) → P3(Ph5)
                       ↑
                      A4(Ph5)
```

Phase 3의 TR2가 Phase 4의 TR3 선행 조건이고, A2도 TR3의 크로스 선행 조건이다.
따라서 Phase 2(A2)는 Phase 4 전에 반드시 완료되어야 한다.

---

## 위험 요소

| 위험 | 대상 | 설명 | 완화 방안 |
|------|------|------|----------|
| 고위험 | TR3 공매도 | 숏 포지션 PnL 계산은 롱과 부호가 반대 — 포트폴리오 손익 합산 로직 전체 재검토 필요 | TR3 구현 전 포트폴리오 PnL 계산 유닛 테스트를 먼저 작성하여 회귀 방지 |
| 고위험 | TR4 레버리지 | 마진콜 강제 청산이 동시에 여러 포지션에서 발생할 경우 처리 순서 정의 필요 | 청산 우선순위: 손실률 높은 순. 세부 규칙을 order-engine.md에 추가 |
| 중간 | A4 섹터 히트맵 | 실시간으로 섹터 수익률 집계 시 틱마다 전체 종목 순회 필요 — 성능 프로파일링 선행 | 섹터 수익률을 캐시로 관리, 틱 끝에 한 번만 갱신 |
| 중간 | P3 ETF 가격 | ETF 가격이 구성 종목 전체의 가중 평균이므로 틱마다 재계산 — A4와 동일 성능 이슈 | A4의 섹터 집계 캐시를 P3 ETF 가격 계산에 재사용 |
| 낮음 | S3 루머 정확도 | 30% 오보 확률이 플레이어에게 unfair하게 느껴질 수 있음 | 루머 발생 시 UI에 "정확도 70%" 명시. 플레이어가 불확실성을 인지하고 선택하도록 |
