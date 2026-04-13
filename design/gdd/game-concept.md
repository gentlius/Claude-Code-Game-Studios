# Game Concept: Seed Money (시드머니)

*Created: 2026-03-25*
*Status: Approved (2026-04-07)*

---

## Elevator Pitch

> 보육원을 퇴소한 청년이 100만원 시드머니 하나 들고 투자 대회에 뛰어드는 실시간 투자 시뮬레이션.
> 기업 정보를 읽고, 차트를 분석하고, 시장 뉴스에 반응하며 매매 판단을 내려
> 쪽방에서 펜트하우스로, 펜트하우스에서 개인 섬으로 -- 1,000억 원 '투자의 거장' 엔딩을 향해 올라간다.
> 단, 바닥을 뚫으면 한강이 기다린다. 올라갈 수도, 모든 것을 잃을 수도 있는 투자 성장 서사.

---

## Core Identity

| Aspect | Detail |
| ---- | ---- |
| **Genre** | 투자 시뮬레이션 / 전략 |
| **Platform** | 웹 브라우저 (컨셉 검증) → Steam (출시) |
| **Target Audience** | 전략/경영 시뮬 팬, 주식 투자에 관심 있는 20-30대 |
| **Player Count** | 싱글플레이어 (AI 경쟁자 기반 시즌 대회) |
| **Session Length** | 30-60분 |
| **Monetization** | Premium (Steam) / 웹 무료 데모 |
| **Estimated Scope** | Small-Medium (MVP 4-6주, 풀 버전 1-3개월) |
| **Comparable Titles** | Offworld Trading Company (실시간 경제 전략), Capitalism Lab (경영 시뮬 깊이), Wall Street Survivor (투자 시뮬 테마) |

---

## Core Fantasy

맨바닥에서 시작해 오직 나의 판단력만으로 투자의 정상에 오르는 성장 서사.

아무 배경도, 인맥도, 정보도 없는 상태에서 시장을 읽는 눈을 스스로 키워가며
2만 명이 경쟁하는 투자 대회를 돌파하는 경험. 100만원으로 시작해 수익을 복리로
불려가며 1,000억 원 -- '투자의 거장' 엔딩을 향해 나아간다.

성장은 숫자만이 아니라 삶으로 체감된다. 쪽방(고시원)에서 변두리 원룸으로,
도심 오피스텔에서 대형 아파트로, 초고층 펜트하우스를 거쳐 교외 대저택으로,
마침내 개인 섬과 자산운용사, 국가 경제 고문의 자리까지 -- 거처와 사회적 지위가
한 단계씩 바뀌는 것을 직접 목격하며 "100만원에서 여기까지 왔다"는 성취감을 느낀다.

그러나 올라가는 길만 있는 것은 아니다. 자산이 100만 원 아래로 떨어지면 공식
리그에서 퇴출되어 프리마켓에서 재기를 도모해야 하고, 프리마켓에서마저 자산이
1만 원 미만으로 추락하면 '한강 엔딩'으로 게임이 종료된다. 바닥은 없다, 그러나
한강은 있다 -- 이 긴장감이 매 판단에 무게를 더하고, "절대 바닥은 보지 말자"는
리스크 관리 동기를 부여한다.

플레이어는 "나는 시장을 읽을 수 있다"는 유능감과 "쪽방에서 개인 섬까지
올라왔다"는 성취감, 그리고 "한순간에 모든 것을 잃을 수 있다"는 긴장감을
동시에 느낀다.

---

## Unique Hook

"실제 투자 판단 과정이 게임 메카닉 그 자체인 투자 시뮬레이션."

교육 앱처럼 딱딱하지 않고, 판타지 경영 시뮬처럼 현실과 동떨어지지 않음.
뉴스를 읽고, 차트를 분석하고, 타이밍을 잡아 매매하는 과정 자체가 게임플레이.
여기에 스킬 트리를 통한 분석 도구 해금이 RPG적 성장감을 더한다.

"주식 시뮬레이터 같지만, AND ALSO 디아블로처럼 스킬을 해금하며 성장하는 게임."

---

## Player Experience Analysis (MDA Framework)

### Target Aesthetics (What the player FEELS)

| Aesthetic | Priority | How We Deliver It |
| ---- | ---- | ---- |
| **Sensation** (sensory pleasure) | 5 | 차트 애니메이션, 체결 효과음, 수익/손실 시각 피드백 |
| **Fantasy** (make-believe, role-playing) | 2 | 100만원 쪽방에서 1,000억 거장까지, 보육원 퇴소 청년의 주거 상승 투자 성장 판타지 |
| **Narrative** (drama, story arc) | 6 | 배경 설정으로만 존재. 서사는 플레이어의 투자 여정 자체 |
| **Challenge** (obstacle course, mastery) | 1 | 시장 분석 → 판단 → 결과의 피드백 루프. 시즌 순위 경쟁 |
| **Fellowship** (social connection) | N/A | 싱글플레이어. AI 라이벌과의 간접 경쟁 |
| **Discovery** (exploration, secrets) | 3 | 새로운 분석 도구 해금, 시장 패턴 발견, 시즌별 다른 시장 테마 |
| **Expression** (self-expression, creativity) | 4 | 나만의 투자 철학/전략 구축. 포트폴리오가 자기 표현 |
| **Submission** (relaxation, comfort zone) | 7 | 시장 관찰 자체의 잔잔한 재미 (서브 요소) |

### Key Dynamics (Emergent player behaviors)

- 플레이어가 뉴스와 차트 패턴의 상관관계를 스스로 발견하고 전략을 세움
- 손실 후 전략을 수정하고 다시 도전하는 "한 시즌만 더" 심리
- 특정 섹터/종목에 대한 개인적 선호와 전문성 발달
- 리스크-리턴 트레이드오프에서 자신만의 스타일 형성 (공격적 vs 보수적)

### Core Mechanics (Systems we build)

1. **실시간 시장 시뮬레이션 엔진** — 가상 종목 가격 변동, 뉴스 이벤트 생성
2. **매매 시스템** — 시장가/지정가 주문, 포트폴리오 관리
3. **정보 분석 시스템** — 차트, 지표, 기업 정보, 뉴스 피드
4. **투자 스킬 트리** — 분석 도구/거래 옵션/정보 속도/포트폴리오 확장 해금
5. **시즌 대회 시스템** — AI 경쟁자, 순위 시스템, 시즌 보상

---

## Player Motivation Profile

### Primary Psychological Needs Served

| Need | How This Game Satisfies It | Strength |
| ---- | ---- | ---- |
| **Autonomy** (freedom, meaningful choice) | 어떤 종목을 사고, 언제 팔지 완전히 플레이어 결정. 투자 철학도 자유 | Core |
| **Competence** (mastery, skill growth) | 시즌마다 순위 상승 + 스킬 해금 + 수익률 향상으로 실력 성장 체감 | Core |
| **Relatedness** (connection, belonging) | AI 라이벌 트레이더들과의 순위 경쟁. 간접적 사회적 자극 | Supporting |

### Player Type Appeal (Bartle Taxonomy)

- [x] **Achievers** (goal completion, collection, progression) — 시즌 1등, 스킬 전체 해금, 수익률 기록 갱신
- [x] **Explorers** (discovery, understanding systems, finding secrets) — 시장 패턴 발견, 새로운 분석 도구 실험, 전략 최적화
- [ ] **Socializers** (relationships, cooperation, community) — 해당 없음 (싱글플레이어)
- [x] **Killers/Competitors** (domination, PvP, leaderboards) — 시즌 리더보드 순위 경쟁, AI 라이벌 압도

### Flow State Design

- **Onboarding curve**: 첫 시즌 1주차는 튜토리얼 성격. 3종목, 기본 차트, 간단한 뉴스로 시작. 매매의 기본 감각 익힘
- **Difficulty scaling**: 시즌이 진행될수록 시장 변동성 증가, AI 경쟁자 강화, 복합 이벤트 발생. 스킬 해금이 이를 상쇄
- **Feedback clarity**: 실시간 수익률 %, 일일 정산 리포트, 시즌 순위 변동 그래프. 판단의 결과가 즉시 숫자로 보임
- **Recovery from failure**: 시즌 내 손실은 회복 가능 (대회 끝날 때까지 기회 있음). 손실이 나도 스킬은 영구 유지, 다음 시즌 상금으로 자본 회복 가능. 단, 자산 100만 원 미만이면 프리마켓 강등, 프리마켓에서 1만 원 미만이면 한강 엔딩(게임 오버) -- 완전한 세이프티넷은 없다는 긴장감이 리스크 관리를 강제한다

---

## Core Loop

### Moment-to-Moment (30 seconds)
뉴스/공시 팝업 확인 → 차트에서 가격 움직임 관찰 → 매수/매도/홀드 판단 → 주문 체결.
체결 시 시각/사운드 피드백으로 짧은 쾌감. 가격이 실시간으로 움직이며 긴장감 유지.

### Short-Term (5-15 minutes)
하루(거래일) 단위. 장 시작 → 뉴스 체크 → 매매 전략 실행 → 장 마감 → 일일 수익률 정산.
"오늘 얼마 벌었나" 확인 → 시즌 순위 변동 체크. "한 거래일만 더" 심리 유발.

### Session-Level (30-60 minutes)
한 주(5거래일) = 자연스러운 세션 단위.
주간 리포트: 수익률 요약, 순위 변동, 시장 트렌드 분석.
주말에 다음 주 전략 수립 시간. 세션 끝에 "다음 주 실적 시즌 시작" 같은 예고로 복귀 동기 부여.

### Long-Term Progression
시즌 20거래일(4주) 고정 단위 대회 경쟁. 예수금으로 직접 투자하며, 수익은 다음 시즌으로 이월.
시즌 순위에 따라 상금이 추가 지급되어 자본이 복리로 성장한다.
투자 스킬 트리를 시즌 경험치로 해금 -- 새 분석 도구, 거래 옵션, 종목 슬롯 확장.
스킬은 시즌 리셋에도 영구 유지 (디아블로 패러곤 모델).

자산이 올라갈수록 티어와 주거가 함께 변한다 (11단계):
쪽방(브론즈 100만) → 변두리원룸(실버 300만) → 도심오피스텔(골드 1천만)
→ 도심중형아파트(플래티넘 3천만) → 도심대형아파트(에메랄드 1억)
→ 초고층펜트하우스(다이아 3억) → 교외대저택(마스터 10억)
→ 개인섬/별장(그랜드마스터 30억) → 자산운용사설립(챌린저 100억)
→ 국가경제고문(레전드 300억) → **투자의 거장 엔딩(1,000억 이상)**.

반대로 자산이 100만 원 미만이면 공식 리그에서 퇴출, 프리마켓에서 재기를 도모한다.
프리마켓에서마저 자산 1만 원 미만으로 추락하면 '한강 엔딩' -- 게임 오버.
장기 목표: 100만원 쪽방에서 1,000억 거장 엔딩 달성.

### Retention Hooks
- **Curiosity**: 다음 시즌의 시장 테마는? 아직 해금 안 한 스킬은 뭘 해줄까? 다음 티어의 주거는 어떤 모습일까?
- **Investment**: 쌓아온 스킬 트리, 복리로 불어난 예수금, 쪽방에서 올라온 주거 히스토리
- **Social**: 2만 명 리더보드에서 AI 라이벌과의 순위 경쟁
- **Mastery**: 수익률 갱신, 더 어려운 시장 환경 정복, 분석 정확도 향상
- **Stakes**: 한강 엔딩의 존재가 만드는 긴장감 -- "이번 시즌 망하면 프리마켓이다"

---

## Game Pillars

### Pillar 1: 판단이 곧 실력 (Judgment is King)
모든 수익과 손실은 플레이어의 판단에서 나온다. 운이 아닌 분석과 결정이 결과를 좌우한다.

*Design test*: "랜덤 보너스 아이템 vs 분석 보상" → 이 필라는 분석 보상을 선택한다.

### Pillar 2: 읽는 재미 (Read the Market)
정보를 읽고 해석하는 과정 자체가 게임플레이다. UI는 정보 접근성을 최우선으로 설계한다.

*Design test*: "화려한 이펙트 vs 깔끔한 정보 표시" → 이 필라는 정보 가독성을 선택한다.

### Pillar 3: 체감있는 성장 (Feel the Growth)
실력 향상이 수치와 결과로 명확히 느껴져야 한다. 스킬 해금, 순위 상승, 수익률 기록이 성장을 증명한다.

*Design test*: "밸런스 패치로 전체 난이도 하향 vs 스킬 해금으로 개인 능력 상향" → 이 필라는 개인 성장을 선택한다.

### Pillar 4: 짧고 굵게 (Quick & Punchy)
30초 안에 의미있는 판단이 발생해야 한다. 지루한 대기 구간은 허용하지 않는다.

*Design test*: "리얼리스틱 대기 시간 vs 압축된 게임 시간" → 이 필라는 압축된 시간을 선택한다.

### Anti-Pillars (What This Game Is NOT)

- **NOT 현실 완벽 재현**: 재미를 위해 단순화한다. 실제 증권 HTS를 만드는 것이 아니다.
- **NOT 투자 교육 콘텐츠**: 교육이 아니라 게임이다. 학습은 부수 효과일 뿐 목적이 아니다.
- **NOT 운 게임**: 랜덤 보상이나 럭키 펀치 없음. 분석과 판단이 결과를 결정하는 실력 게임이다.

---

## Inspiration and References

| Reference | What We Take From It | What We Do Differently | Why It Matters |
| ---- | ---- | ---- | ---- |
| 삼국지 시리즈 | 서사적 배경 + 전략적 의사결정 구조 | 전쟁이 아닌 시장에서의 전략 | 서사가 전략에 동기를 부여하는 구조 검증 |
| 디아블로 시리즈 | 스킬 해금 + 영구 성장 + 런 반복 구조 | 전투가 아닌 투자 판단이 코어 액션 | 반복 플레이에서 성장감을 유지하는 구조 검증 |
| FIFA 시리즈 | 짧은 세션 내 승리감 + 시즌 구조 | 스포츠가 아닌 투자 대회 | 시즌제 경쟁의 리텐션 효과 검증 |
| 트랜스포트 타이쿤 | 경제 시뮬레이션의 자원 흐름 최적화 재미 | 운송이 아닌 금융 자산 관리 | 숫자 기반 최적화의 중독성 검증 |

**Non-game inspirations**: 실제 주식 투자 대회 (대학생/직장인 투자 대회), 보육원 퇴소 청년의 자립 현실 (사회적 서사)

---

## Target Player Profile

| Attribute | Detail |
| ---- | ---- |
| **Age range** | 20-35세 |
| **Gaming experience** | Mid-core ~ Hardcore. 전략/시뮬레이션 장르 경험 필요 |
| **Time availability** | 30-60분 세션. 점심시간이나 저녁에 플레이 |
| **Platform preference** | PC (웹/Steam) |
| **Current games they play** | 경영 시뮬 (Capitalism Lab, Offworld), 전략 게임 (삼국지, CK3), 투자 관련 앱/게임 |
| **What they're looking for** | "진짜 투자 판단 경험을 게임으로 즐기고 싶다" — 교육도 판타지도 아닌 투자 게임 |
| **What would turn them away** | 과도한 랜덤 요소, 느린 페이스, 복잡한 튜토리얼, Pay-to-Win |

---

## Technical Considerations

| Consideration | Assessment |
| ---- | ---- |
| **Recommended Engine** | Godot 4.6 — 웹 export 기본 지원 (HTML5), Steam 빌드 지원, UI 중심 게임에 적합, 솔로 개발에 가벼움 |
| **Key Technical Challenges** | 리얼리스틱한 시장 시뮬레이션 엔진 (패턴 있되 예측불가한 균형), 복잡한 UI 레이아웃 (차트+호가창+뉴스+포트폴리오) |
| **Art Style** | 클린 UI 중심. 금융 대시보드 느낌. 미니멀 2D. 3D 에셋 불필요 |
| **Art Pipeline Complexity** | Low — UI 컴포넌트, 차트 렌더링, 아이콘 중심 |
| **Audio Needs** | Moderate — 매매 체결 효과음, 시장 분위기 BGM, 알림음 |
| **Networking** | None (MVP). 향후 온라인 리더보드 추가 가능 |
| **Content Volume** | 가상 종목 46개/11섹터 (MVP), 뉴스 이벤트 50+개, 시즌 테마 3-5개 |
| **Procedural Systems** | 시장 가격 변동 절차적 생성, 뉴스 이벤트 풀에서 랜덤 선택 |

---

## Risks and Open Questions

### Design Risks
- 시장 시뮬레이션이 너무 랜덤하면 "판단 게임"이 아니라 "도박"이 됨. 패턴이 읽히되 예측불가능한 균형점 필요
- 직관적 판단 수준의 1차 버전이 충분한 깊이를 가질 수 있을지 검증 필요

### Technical Risks
- 실시간 차트 렌더링 + 다수 종목 동시 시뮬레이션의 웹 성능
- Godot 웹 export의 UI 렌더링 퍼포먼스 (복잡한 금융 UI)

### Market Risks
- "진짜 투자 게임" 포지션이 비어있는 이유가 수요 부족일 가능성
- 투자 시뮬이라는 테마가 일반 게이머에게 진입장벽으로 느껴질 수 있음

### Scope Risks
- 시장 시뮬레이션 엔진의 품질이 게임 전체 품질을 좌우 — 이 하나가 무너지면 게임 전체가 무너짐
- UI 복잡도가 예상보다 높을 수 있음 (차트/호가창/뉴스/포트폴리오 동시 배치)

### Open Questions
- 시장 시뮬레이션 엔진의 알고리즘 설계 — 프로토타입으로 검증 필요
- ~~적정 시즌 길이~~ → 20거래일(4주) 확정 (season-manager.md)
- 웹 빌드에서 Godot UI 성능 — 기술 프로토타입으로 확인

---

## MVP Definition

**Core hypothesis**: "뉴스/차트를 읽고 매매 타이밍을 판단하는 과정이 30분 이상의 세션을 지속시킬 만큼 재미있다"

**Required for MVP**:
1. 가상 종목 46개 (11섹터)의 실시간 가격 변동 엔진
2. 기본 캔들차트 + 거래량 표시
3. 뉴스/공시 이벤트 시스템 (시장에 영향)
4. 시장가/지정가 주문 매매
5. 1 시즌 대회 (플레이어 1 + AI 19,999 = 20,000명 대회, 순위 시스템)
6. 기본 스킬 트리 (T0 기본 + T1 해금)
7. 웹 브라우저 빌드

**Explicitly NOT in MVP** (defer to later):
- 공매도 / 레버리지 / 옵션 거래
- ETF / 섹터 분석
- Steam 빌드
- 리얼리스틱 분석 도구 (RSI, MACD 등)
- 온라인 리더보드

### Scope Tiers (if budget/time shrinks)

| Tier | Content | Features | Timeline |
| ---- | ---- | ---- | ---- |
| **MVP** | 종목 46개 (11섹터), 뉴스 30개 | 기본 매매 + 차트 + 1시즌 | 4-6주 |
| **Vertical Slice** | 종목 46개, 뉴스 50개 | + 스킬 트리 전체 + 시즌 보상 | 6-8주 |
| **Alpha** | 종목 46개, 시즌 테마 3개 | + 수수료/배당 + 고급 거래 | 8-12주 |
| **Full Vision** | 종목 46+, 실물 연동 시뮬 | 전체 기능 + Steam 빌드 | 3-6개월 |

---

## Skill Tree Detail

### 1. 분석 도구 (Analysis Tools)
분석에 사용할 수 있는 차트 지표와 정보를 해금한다.

| ID | Unlock | Description |
| ---- | ---- | ---- |
| A0 (T0) | 기본 캔들차트 + 거래량 | 시작 시 제공 |
| A1 (T1) | 이동평균선 (5/20/60일) | 추세 파악 도구 |
| A2 (T2) | RSI, MACD | 과매수/과매도 판단 보조지표 |
| *향후* | 재무제표, 섹터 비교 등 | 확장 예정 |

### 2. 시장 감지 (Market Sense)
정보의 속도와 품질을 향상시킨다.

| ID | Unlock | Description |
| ---- | ---- | ---- |
| S0 (T0) | 뉴스 ~7.7초 딜레이 (40틱) | 시작 시 기본 |
| S1 (T1) | 뉴스 ~4초 딜레이 (20틱) | 더 빠른 반응 가능 |
| S2 (T2) | 실시간 뉴스 (0틱) | 이벤트 즉시 확인 |
| S3 (T3) | 루머/내부 힌트 채널 | 확률적 선행 정보 |

### 3. 거래 스킬 (Trading Skills)
사용 가능한 주문 유형과 거래 옵션을 확장한다.

| ID | Unlock | Description |
| ---- | ---- | ---- |
| TR0 (T0) | 시장가 매매 | 시작 시 기본 |
| TR1 (T1) | 지정가 주문 | 목표 가격에 자동 체결 |
| TR2 (T2) | 손절/익절 자동 주문 | 리스크 관리 도구 |
| TR3 (T3) | 공매도 | 하락장에서도 수익 가능 (향후) |
| TR4 (T4) | 레버리지/옵션 | 고위험 고수익 거래 (향후) |

### 4. 포트폴리오 (Portfolio)
동시 보유 가능한 종목 수와 투자 옵션을 확장한다.

| ID | Unlock | Description |
| ---- | ---- | ---- |
| P0 (T0) | 동시 보유 3종목 | 시작 시 기본 |
| P1 (T1) | 동시 보유 5종목 | 분산 투자 시작 |
| P2 (T2) | 동시 보유 10종목 | 본격적 포트폴리오 |

---

## Currency System

### 단일 계좌 구조

| Account | Purpose | Lifecycle |
| ---- | ---- | ---- |
| **예수금 (Deposit)** | 플레이어의 전 재산이자 투자 자금. 시작 100만원(정착지원금) | 영구 유지, 수익/손실 직접 반영 |

- 예수금으로 직접 투자 대회에 참가. 수익/손실이 예수금에 바로 반영된다.
- 시즌 종료 시 순위 상금이 예수금에 추가 입금 → 복리 성장 구조.
- 시즌 시작 시 보유 주식은 청산되지만, 예수금 잔액은 이월된다.

---

## Next Steps

- [ ] 엔진 설정 — `/setup-engine godot 4.6`
- [ ] 컨셉 리뷰 — `/design-review design/gdd/game-concept.md`
- [ ] 시스템 분해 — `/map-systems` (시장 엔진, 매매 시스템, UI, 스킬 트리 등 의존성 매핑)
- [ ] 핵심 시스템 GDD 작성 — `/design-system` (시장 시뮬레이션 엔진부터)
- [ ] 코어 루프 프로토타입 — `/prototype market-simulation`
- [ ] 플레이테스트 — `/playtest-report`
- [ ] 첫 스프린트 계획 — `/sprint-plan new`
