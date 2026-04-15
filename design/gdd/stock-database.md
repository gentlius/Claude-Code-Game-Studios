# 종목 데이터베이스 (Stock Database)

> **Status**: Approved
> **Author**: user + game-designer
> **Last Updated**: 2026-04-03
> **Implements Pillar**: 읽는 재미 (Read the Market)

## Overview

종목 데이터베이스는 시드머니의 모든 가상 종목을 정의하는 Foundation 시스템이다.
각 종목의 이름, 섹터, 기본가치, 변동성, 재무 지표 등 정적 속성을 관리하며,
가격 엔진, 뉴스 시스템, 매매 시스템이 이 데이터를 참조하여 작동한다.

한국 주식시장 구조를 참고한 **11개 섹터에 총 46개 종목**을 배치하고,
각 섹터마다 고유한 변동성 프로필과 뉴스 반응 특성을 부여하여
플레이어가 종목별 차이를 읽고 전략을 세우는 재미를 제공한다.

MVP부터 전체 46종목을 사용한다. 초기 설계 시 10종목(★) MVP 구분이 있었으나,
현재는 46종목 전체가 MVP에 포함된다.

## Player Fantasy

플레이어는 각 종목을 "살아있는 기업"으로 인식한다. 이름만 보고도 어떤 업종인지
알 수 있고, 뉴스를 읽으면 해당 기업에 어떤 영향이 있을지 직관적으로 판단할 수 있다.
"메디진에 임상 성공 뉴스가 떴으니 급등할 거야" — 이런 추론이 자연스럽게 느껴져야
한다. 종목 데이터베이스는 이 직관적 판단의 근거를 제공하는 시스템이다.

섹터당 4~5종목이 있어 같은 업종 안에서도 종목 간 차이를 비교할 수 있다.
"반도체 수출 규제 뉴스 → 스타칩은 팹리스라 영향 적고, 하닉스반도체는 메모리라
직격탄" — 이런 세분화된 판단이 실력 차이를 만든다.

## Detailed Design

### Core Rules

1. **종목 정의**: 각 종목은 고유 ID, 이름, 종목코드, 섹터, 정적 속성을 가진다.
2. **섹터 구조**: 11개 섹터, 섹터당 4~5개 종목, 총 46개.
3. **정적 속성**: 게임 시작 시 로드되며 시즌 중 변경되지 않는 기본 특성.
4. **동적 데이터는 이 시스템에 없다**: 현재 가격, 거래량, 차트 데이터 등은
   가격 엔진이 관리. 종목 DB는 "이 종목이 어떤 종목인가"만 정의.
5. **MVP 범위**: 전체 46종목이 MVP에 포함. ★ 표시는 초기 설계 시 우선 구현 종목이었으나 현재는 구분 없이 전체 사용.

### 종목 데이터 스키마

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `id` | string | 고유 식별자 | "STC" |
| `name` | string | 표시 이름 | "스타칩" |
| `ticker` | string | 종목코드 (3자) | "STC" |
| `sector` | enum | 소속 섹터 | SEMICONDUCTOR |
| `description` | string | 기업 설명 (1-2문장) | "글로벌 반도체 설계 및 제조 기업" |
| `base_price` | int | 시즌 시작 시 기준가 (원) | 120000 |
| `listed_shares` | int | 상장주식수. 시총가중지수 산출 기준 | 1500000 |
| `volatility_profile` | enum | 변동성 프로필 | LOW / MEDIUM / HIGH / EXTREME |
| `sector_sensitivity` | float | 섹터 뉴스 반응 강도 (0.0-2.0) | 1.5 |
| `macro_sensitivity` | float | 거시경제 뉴스 반응 강도 (0.0-2.0) | 1.2 |
| `event_tags` | string[] | 반응하는 이벤트 태그 목록 | ["semiconductor", "export", "tech"] |
| `per` | float \| null | 주가수익비율. 적자 기업은 null (UI에 "N/A" 표시) | 18.3 |
| `dividend_yield` | float | 배당 수익률 (%). MVP에서는 UI 표시 전용 참고 정보 | 1.8 |

> **`market_cap`과 `market_cap_tier` 제거됨**: `listed_shares` 도입으로 시가총액은
> `current_price × listed_shares`로 실시간 계산. 시총 등급은 런타임 분류로 대체.

### 섹터 정의

| Sector ID | 한글명 | 특성 | 주요 이벤트 태그 |
|-----------|--------|------|----------------|
| SEMICONDUCTOR | 반도체 | 대형. 글로벌 수요 민감 | semiconductor, export, tech, AI |
| BATTERY | 2차전지 | 성장주. 정책 민감 | battery, ev, green_energy, policy |
| BIO | 바이오/제약 | 고변동. 이벤트 드리븐 | clinical_trial, fda, healthcare |
| AUTO | 자동차 | 수출/환율 연동 | export, exchange_rate, auto |
| FINANCE | 금융 | 저변동. 금리 민감 | interest_rate, regulation, finance |
| ENTERTAINMENT | 엔터/미디어 | 이벤트 드리븐 | content_hit, kpop, media |
| RETAIL | 유통/소비 | 방어주. 안정적 | consumption, season, retail |
| CONSTRUCTION | 건설/조선 | 경기/정책 민감 | real_estate, policy, infrastructure, shipbuilding |
| GAMING | 게임 | 고변동. 신작 이벤트 | game_release, esports, tech |
| ENERGY | 에너지/화학 | 원자재 연동 | oil_price, raw_material, chemical |
| TELECOM | 통신 | 안정/배당. 인프라 투자 민감 | telecom, 5g, infrastructure, policy |

### 종목 목록

★ = 초기 설계 시 우선 구현 대상. 현재는 전체 46종목이 MVP에 포함.

#### SEMICONDUCTOR (5종목)

| # | ID | Name | Base Price | Shares | 초기시총(억) | Vol | PER | SecS | MacS | Div% | Event Tags |
|---|-----|------|-----------|--------|------------|-----|-----|------|------|------|------------|
| 1 | SKL★ | 스카이로직 | 210,000 | 2,500,000 | 5,250 | HIGH | 22.0 | 1.3 | 0.9 | 1.2 | semiconductor, memory, export, AI |
| 2 | STC★ | 스타칩 | 120,000 | 1,500,000 | 1,800 | HIGH | 18.3 | 1.5 | 1.2 | 1.5 | semiconductor, export, tech, AI |
| 3 | HNX | 하닉스반도체 | 135,000 | 1,200,000 | 1,620 | HIGH | 15.8 | 1.4 | 1.1 | 1.0 | semiconductor, memory, export |
| 4 | SLW | 실리콘웨이브 | 45,000 | 800,000 | 360 | HIGH | 28.5 | 1.2 | 0.7 | 0.0 | semiconductor, fabless, AI |
| 5 | DSE | 디에스이 | 22,000 | 600,000 | 132 | MEDIUM | 12.0 | 1.0 | 0.8 | 2.0 | semiconductor, equipment, display |

> 반도체 섹터는 시총 비중이 가장 크다. SKL(스카이로직)가 전체 지수에 최대 영향.
> 메모리(SKL, HNX) vs 팹리스(STC, SLW) vs 장비(DSE) 세분화.

#### BATTERY (4종목)

| # | ID | Name | Base Price | Shares | 초기시총(억) | Vol | PER | SecS | MacS | Div% | Event Tags |
|---|-----|------|-----------|--------|------------|-----|-----|------|------|------|------------|
| 6 | SDC | 삼도셀 | 285,000 | 700,000 | 1,995 | MEDIUM | 18.5 | 1.2 | 0.9 | 0.8 | battery, ev, chemical |
| 7 | LEB | 엘에너지 | 380,000 | 500,000 | 1,900 | HIGH | 45.0 | 1.5 | 0.8 | 0.0 | battery, ev, green_energy |
| 8 | ECM | 에코머티리얼 | 62,000 | 400,000 | 248 | EXTREME | N/A | 1.8 | 0.6 | 0.0 | battery, raw_material, green_energy |
| 9 | PBT | 파워배터리텍 | 15,000 | 1,000,000 | 150 | EXTREME | N/A | 1.6 | 0.5 | 0.0 | battery, ev, tech |

> 2차전지는 성장주 섹터. 대형(SDC, LEB)은 MEDIUM~HIGH, 소재/신기술(ECM, PBT)은 EXTREME.
> EV 정책과 원자재 가격에 민감.

#### BIO (5종목)

| # | ID | Name | Base Price | Shares | 초기시총(억) | Vol | PER | SecS | MacS | Div% | Event Tags |
|---|-----|------|-----------|--------|------------|-----|-----|------|------|------|------------|
| 10 | CGP | 셀진파마 | 165,000 | 1,000,000 | 1,650 | HIGH | 32.0 | 1.3 | 0.7 | 0.5 | healthcare, biosimilar, export |
| 11 | BPH★ | 블루팜 | 320,000 | 150,000 | 480 | EXTREME | N/A | 2.0 | 0.7 | 0.0 | clinical_trial, fda, healthcare |
| 12 | MDG★ | 메디진 | 180,000 | 200,000 | 360 | EXTREME | N/A | 1.8 | 1.0 | 0.0 | clinical_trial, fda, healthcare |
| 13 | HLB | 한라바이오 | 48,000 | 500,000 | 240 | EXTREME | N/A | 1.7 | 0.6 | 0.0 | clinical_trial, fda, healthcare |
| 14 | YBT | 유바이오텍 | 25,000 | 400,000 | 100 | HIGH | 22.0 | 1.2 | 0.8 | 0.0 | healthcare, diagnostic, tech |

> 바이오는 EXTREME 비중이 가장 높은 섹터. 임상 이벤트에 극단적 반응.
> CGP는 바이오시밀러(안정 매출), 나머지는 파이프라인 의존.

#### AUTO (4종목)

| # | ID | Name | Base Price | Shares | 초기시총(억) | Vol | PER | SecS | MacS | Div% | Event Tags |
|---|-----|------|-----------|--------|------------|-----|-----|------|------|------|------------|
| 15 | HMC | 한라모터스 | 195,000 | 1,800,000 | 3,510 | MEDIUM | 6.5 | 1.2 | 1.3 | 3.5 | auto, export, exchange_rate |
| 16 | KAM | 기아모빌리티 | 88,000 | 1,500,000 | 1,320 | MEDIUM | 5.8 | 1.1 | 1.2 | 4.0 | auto, export, exchange_rate |
| 17 | MBP | 모빌파츠 | 215,000 | 800,000 | 1,720 | LOW | 8.2 | 0.9 | 1.0 | 2.5 | auto, parts, export |
| 18 | EVN | 이브이나우 | 35,000 | 300,000 | 105 | EXTREME | N/A | 1.5 | 0.7 | 0.0 | auto, ev, battery |

> 자동차 섹터는 수출/환율 민감. 완성차(HMC, KAM)는 안정적, 부품(MBP)은 방어적,
> EV 스타트업(EVN)은 투기적.

#### FINANCE (4종목)

| # | ID | Name | Base Price | Shares | 초기시총(억) | Vol | PER | SecS | MacS | Div% | Event Tags |
|---|-----|------|-----------|--------|------------|-----|-----|------|------|------|------------|
| 19 | KRB★ | 코리아뱅크 | 52,000 | 2,000,000 | 1,040 | LOW | 6.8 | 0.5 | 1.5 | 4.5 | interest_rate, regulation, finance |
| 20 | SSL | 삼한생명 | 72,000 | 1,200,000 | 864 | LOW | 8.5 | 0.6 | 1.3 | 3.8 | interest_rate, finance, insurance |
| 21 | HNF | 하나파이낸스 | 48,000 | 1,500,000 | 720 | LOW | 5.2 | 0.5 | 1.4 | 5.0 | interest_rate, finance, banking |
| 22 | MSC | 메리츠증권 | 55,000 | 600,000 | 330 | MEDIUM | 7.8 | 0.8 | 1.2 | 3.0 | finance, securities, market |

> 금융은 가장 안정적인 섹터. 금리에 강하게 반응하고 배당 수익률이 높다.
> 증권사(MSC)만 시장 변동성에 연동되어 MEDIUM.

#### ENTERTAINMENT (4종목)

| # | ID | Name | Base Price | Shares | 초기시총(억) | Vol | PER | SecS | MacS | Div% | Event Tags |
|---|-----|------|-----------|--------|------------|-----|-----|------|------|------|------------|
| 23 | HBE | 하이브엔터 | 195,000 | 400,000 | 780 | HIGH | 38.0 | 1.5 | 0.5 | 0.3 | kpop, content_hit, media |
| 24 | SMC | 에스엠컬처 | 82,000 | 500,000 | 410 | MEDIUM | 22.0 | 1.2 | 0.5 | 1.5 | kpop, content_hit, media |
| 25 | NXE★ | 넥스트엔터 | 42,000 | 600,000 | 252 | HIGH | 25.1 | 0.8 | 0.6 | 0.5 | content_hit, kpop, media |
| 26 | JYM | 제이와이뮤직 | 68,000 | 350,000 | 238 | HIGH | 28.5 | 1.3 | 0.4 | 0.8 | kpop, content_hit, media |

> 엔터는 이벤트 드리븐. 컨텐츠 히트/실패에 극적 반응. 거시경제에는 둔감.

#### RETAIL (4종목)

| # | ID | Name | Base Price | Shares | 초기시총(억) | Vol | PER | SecS | MacS | Div% | Event Tags |
|---|-----|------|-----------|--------|------------|-----|-----|------|------|------|------------|
| 27 | KSF★ | 코스모푸드 | 65,000 | 800,000 | 520 | MEDIUM | 12.5 | 1.0 | 0.8 | 1.8 | consumption, season, retail |
| 28 | CPG | 쿠플러스 | 32,000 | 1,500,000 | 480 | MEDIUM | 120.0 | 1.1 | 0.7 | 0.0 | consumption, retail, platform |
| 29 | EMT | 이마트레이드 | 85,000 | 500,000 | 425 | LOW | 15.0 | 0.8 | 0.9 | 2.5 | consumption, retail, real_estate |
| 30 | BGF | 배달의국민 | 145,000 | 300,000 | 435 | HIGH | N/A | 1.3 | 0.6 | 0.0 | consumption, retail, platform |

> 유통/소비는 방어적 섹터. 전통 유통(KSF, EMT)은 안정적, 플랫폼(CPG, BGF)은 성장주 성격.
> CPG는 성장주 성격이나 대형 플랫폼 지위로 MEDIUM 변동성 유지. BGF는 신규 플랫폼으로 HIGH 변동성.

#### CONSTRUCTION (4종목)

| # | ID | Name | Base Price | Shares | 초기시총(억) | Vol | PER | SecS | MacS | Div% | Event Tags |
|---|-----|------|-----------|--------|------------|-----|-----|------|------|------|------------|
| 31 | DHI★ | 대한중공업 | 95,000 | 1,000,000 | 950 | LOW | 8.2 | 1.0 | 1.3 | 3.0 | shipbuilding, export, infrastructure |
| 32 | HEC | 한라건설 | 38,000 | 1,200,000 | 456 | MEDIUM | 7.5 | 1.2 | 1.1 | 2.0 | real_estate, policy, infrastructure |
| 33 | PSC | 포스코건설 | 28,000 | 800,000 | 224 | MEDIUM | 6.8 | 1.0 | 1.0 | 2.2 | infrastructure, construction, policy |
| 34 | DWE | 대우이앤씨 | 5,200 | 3,000,000 | 156 | HIGH | 9.2 | 1.3 | 1.2 | 1.0 | real_estate, construction, policy |

> 건설/조선은 경기순환 섹터. 부동산 정책과 수주에 민감. DHI는 조선 특화.
> DWE는 저가주로 변동성 높음.

#### GAMING (4종목)

| # | ID | Name | Base Price | Shares | 초기시총(억) | Vol | PER | SecS | MacS | Div% | Event Tags |
|---|-----|------|-----------|--------|------------|-----|-----|------|------|------|------------|
| 35 | KFT | 크래프톤 | 245,000 | 600,000 | 1,470 | HIGH | 15.0 | 1.3 | 0.5 | 1.0 | game_release, esports, tech |
| 36 | NCW | 엔씨월드 | 185,000 | 500,000 | 925 | MEDIUM | 22.0 | 1.0 | 0.6 | 1.5 | game_release, mmo, media |
| 37 | NXG | 넥슨게임즈 | 22,000 | 800,000 | 176 | HIGH | 18.5 | 1.2 | 0.5 | 0.5 | game_release, tech, media |
| 38 | PRL | 펄어비스 | 38,000 | 400,000 | 152 | EXTREME | 45.0 | 1.5 | 0.4 | 0.0 | game_release, tech, media |

> 게임은 신작 출시에 극적 반응. 대형사(KFT, NCW)는 상대적 안정, 중소(PRL)는 EXTREME.

#### ENERGY (4종목)

| # | ID | Name | Base Price | Shares | 초기시총(억) | Vol | PER | SecS | MacS | Div% | Event Tags |
|---|-----|------|-----------|--------|------------|-----|-----|------|------|------|------------|
| 39 | SKI | 에스케이에너지 | 125,000 | 800,000 | 1,000 | MEDIUM | 12.5 | 1.2 | 1.3 | 2.5 | oil_price, raw_material, chemical |
| 40 | KEP | 한국전력 | 22,000 | 3,000,000 | 660 | LOW | N/A | 0.8 | 1.5 | 0.0 | energy, policy, infrastructure |
| 41 | GRC★ | 그린케미 | 38,000 | 1,200,000 | 456 | MEDIUM | 9.7 | 1.2 | 1.0 | 2.0 | chemical, raw_material, oil_price |
| 42 | HPC | 한화파워 | 32,000 | 600,000 | 192 | HIGH | N/A | 1.4 | 0.8 | 0.0 | green_energy, solar, policy |

> 에너지는 원자재/유가에 연동. KEP(전력)은 정책 민감 저PER, HPC(태양광)는 성장주.
> **참고**: KEP/HPC는 PER=N/A, Div=0.0으로 설정. 실제 한국전력은 배당주이나,
> 게임에서는 MVP 단순화를 위해 배당 메카닉 미구현. 향후 배당 시스템 도입 시 조정.

#### TELECOM (4종목)

| # | ID | Name | Base Price | Shares | 초기시총(억) | Vol | PER | SecS | MacS | Div% | Event Tags |
|---|-----|------|-----------|--------|------------|-----|-----|------|------|------|------------|
| 43 | PLT★ | 피플텔레콤 | 78,000 | 900,000 | 702 | MEDIUM | 11.0 | 1.0 | 1.0 | 4.0 | telecom, 5g, infrastructure |
| 44 | KTN | 코리아넷 | 42,000 | 1,500,000 | 630 | LOW | 9.5 | 0.9 | 1.1 | 4.5 | telecom, 5g, infrastructure |
| 45 | LPM | 엘피모바일 | 28,000 | 1,000,000 | 280 | MEDIUM | 14.2 | 1.0 | 0.9 | 3.5 | telecom, 5g, mobile |
| 46 | DGT | 디지텔 | 8,500 | 500,000 | 42 | HIGH | 35.0 | 1.3 | 0.6 | 0.0 | telecom, digital, platform |

> 통신은 고배당 방어 섹터. 대형 통신사(PLT, KTN)는 안정적이고 배당 높음.
> DGT는 알뜰폰/디지털전환 플랫폼으로 성장주 성격.

### 종목 분포 요약

**변동성 분포** (46종목):

| Profile | 종목 수 | 비율 | 역할 |
|---------|--------|------|------|
| LOW | 8 | 17% | 방어적 투자처. 배당 수익 중심 |
| MEDIUM | 15 | 33% | 중간 위험/보상. 분석 기반 매매 |
| HIGH | 16 | 35% | 적극적 매매 대상. 뉴스 반응 큼 |
| EXTREME | 7 | 15% | 투기적. 고위험 고수익 |

**시총 분포** (초기 기준, 상위 10):

| 순위 | ID | 초기시총(억) | 지수 영향 |
|------|-----|-----------|----------|
| 1 | SKL | 5,250 | 최대 |
| 2 | HMC | 3,510 | 매우 큼 |
| 3 | SDC | 1,995 | 큼 |
| 4 | LEB | 1,900 | 큼 |
| 5 | STC | 1,800 | 큼 |
| 6 | MBP | 1,720 | 큼 |
| 7 | CGP | 1,650 | 큼 |
| 8 | HNX | 1,620 | 큼 |
| 9 | KFT | 1,470 | 중간 |
| 10 | KAM | 1,320 | 중간 |

상위 5종목 시총 합계 ≈ 14,455억 (전체 ~38%). KOSPI와 유사한 대형주 편중 구조.

**시가총액 = current_price × listed_shares** (실시간 계산). 시총가중지수(KOSPI 방식) 산출에 사용.

### States and Transitions

종목 데이터베이스는 상태 머신이 아닌 정적 데이터 저장소이다.
상태 전환 없음. 데이터는 시즌 시작 시 로드되고 시즌 종료까지 불변.

시즌 간 변경 가능 항목:
- `base_price`: 시즌 테마에 따라 조정 가능
- 종목 추가/제거: 시즌 테마에 따라 신규 상장/상장 폐지 이벤트 (향후 확장)

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **가격 엔진** | 가격 엔진이 참조 | `get_stock(id)` → 종목의 변동성, 감도 값을 읽어 가격 변동 계산에 사용 |
| **뉴스/이벤트 시스템** | 뉴스가 참조 | `get_stocks_by_event_tag(tag)` → 이벤트 태그로 반응 종목 조회. `get_stocks_by_sector(sector_id)` → SECTOR 이벤트 대상 종목 조회 |
| **주문 처리 엔진** | 주문이 참조 | `stock_exists(id): bool` → 종목 존재 검증. `get_stock(id)` → 종목 기본 정보 |
| **포트폴리오 관리** | 포트폴리오가 참조 | `get_stock(id)` → 종목 이름, 섹터 등 표시 정보 |
| **스킬 트리** | 스킬이 참조 | `get_all_sectors(): SectorInfo[]` → 섹터 ETF 해금 시 섹터 목록 조회. `SectorInfo = {id: SectorEnum, name: string, stock_count: int}` |

## Formulas

이 시스템은 정적 데이터 저장소이며, 동적 가격/손익 계산은 소비 시스템에서 수행된다:
- 가격 변동 공식 → 가격 엔진 GDD
- 뉴스 영향 공식 → 뉴스/이벤트 시스템 GDD
- 손익 계산 공식 → 포트폴리오 관리 GDD

다만 시즌 시작 시 기준가 조정 공식은 이 시스템이 소유한다:

### F1. 시즌별 기준가 조정 (향후 확장)

```
season_base_price = original_base_price * season_theme_modifier
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| original_base_price | int | 1,000-1,000,000 | stock data | 종목의 원래 기준가 |
| season_theme_modifier | float | 0.7-1.3 | season config | 시즌 테마에 따른 조정 계수 |

---

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| 존재하지 않는 종목 ID 조회 | null 반환 + 에러 로그. 호출자가 null 체크 필수 | 방어적 프로그래밍 |
| 동일 섹터 내 다중 종목 섹터 뉴스 반응 | 섹터 뉴스에 모두 반응하되, sector_sensitivity로 개별 강도 차등 | 같은 업종이어도 기업마다 반응 다름 |
| 적자 기업의 PER 표시 | PER null → UI에 "N/A" 표시 | 바이오주, 성장주 등 흑자 전환 전 |
| 시즌 시작 시 기준가 0 이하 | 최소 기준가 1,000원으로 클램핑 | 비정상 데이터 방지 |
| event_tags가 비어있는 종목 | 섹터 뉴스에만 반응, 개별 이벤트 반응 없음 | 기본 동작으로 충분 |
| 배당 수익률 높은 종목 장기 보유 | MVP에서는 배당 이벤트 없음. dividend_yield는 참고 정보로만 표시 | 향후 확장으로 배당 메카닉 도입 예정 |
| 동일 섹터 종목 간 시총 격차 큼 | 정상 동작. 시총 격차는 지수 영향도 차이로 반영됨 | 현실 시장 반영 |

---

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| 가격 엔진 | 가격 엔진이 이 시스템에 의존 | 종목 속성 (변동성, 감도)을 읽어 가격 계산. **Hard** |
| 뉴스/이벤트 시스템 | 뉴스가 이 시스템에 의존 | event_tags로 뉴스 대상 종목 결정. **Hard** |
| 주문 처리 엔진 | 주문이 이 시스템에 의존 | 종목 존재 확인. **Hard** |
| 포트폴리오 관리 | 포트폴리오가 이 시스템에 의존 | 종목 표시 정보. **Soft** |
| 스킬 트리 | 스킬이 이 시스템에 의존 | 섹터 ETF 해금. **Soft** |

이 시스템은 다른 시스템에 의존하지 않는 Foundation 시스템이다.

---

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `base_price` (per stock) | 종목별 상이 | 1,000-1,000,000 | 주당 가격 높아짐 → 적은 주수 매매 | 주당 가격 낮아짐 → 많은 주수 매매 |
| `volatility_profile` | 종목별 상이 | LOW-EXTREME | 더 큰 가격 변동 → 하이리스크 하이리턴 | 안정적 → 안전한 투자처 |
| `sector_sensitivity` | 0.4-2.0 | 0.0-2.0 | 섹터 뉴스에 더 크게 반응 | 섹터 뉴스에 둔감 |
| `macro_sensitivity` | 0.4-1.5 | 0.0-2.0 | 거시경제 이벤트에 더 크게 반응 | 거시경제에 둔감 |
| `dividend_yield` | 종목별 상이 | 0.0-8.0% | 장기 보유 인센티브 증가 | 단기 트레이딩 위주 |
| `total_stock_count` | 46 | 20-80 | 더 다양한 선택지 | 집중된 경험 |
| `sector_count` | 11 | 5-15 | 섹터 다양성 증가 | 섹터 간 차이 선명 |

---

## Acceptance Criteria

- [x] 모든 종목이 고유 ID, 이름을 가지며 중복 없음
- [x] `get_stock(id)` 호출 시 1ms 이내 응답
- [x] 11개 섹터에 각 4~5개 종목이 정확히 매핑됨
- [x] 각 종목의 변동성 프로필이 LOW/MEDIUM/HIGH/EXTREME 중 하나
- [x] `get_stocks_by_event_tag(tag)` 호출 시 해당 태그를 가진 종목만 반환
- [x] 적자 기업(PER null)의 PER이 UI에 "N/A"로 표시됨
- [x] 모든 종목 데이터가 외부 config 파일에서 로드됨 (하드코딩 금지)
- [x] MVP 빌드에서 46종목 전체 로드됨
- [x] 존재하지 않는 종목 ID 조회 시 크래시 없이 null 반환
- [x] `stock_exists(id)` 호출 시 정확한 bool 반환 (1ms 이내)
- [x] `get_stocks_by_sector(sector_id)` 호출 시 해당 섹터 종목만 반환 (1ms 이내)
- [x] 모든 46종목의 listed_shares 값이 정확히 로드되어 가격 엔진의 시총가중지수 계산에 제공됨

---

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| 시즌별 종목 추가/폐지 이벤트 도입 여부 | game-designer | 시즌 관리 GDD 시 | 향후 확장 |
| 종목 데이터를 JSON vs Resource(Godot) 중 어느 형식으로 저장 | engine-programmer | 엔진 설정 후 | /setup-engine 후 결정 |
| MVP→V-Slice 전환 시 기존 세이브 데이터 호환성 | engine-programmer | V-Slice 시점 | 미정 |
| 배당 메카닉 도입 시점과 dividend_yield 활용 방안 | game-designer | 향후 | dividend_yield 필드는 이미 준비됨 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점

| 기능 | 진입점 |
|------|--------|
| 종목 데이터 로드 | `stock_database.gd._ready()` → `_load_stocks_from_json()` (자동, 게임 시작 시) |
| 섹터별 종목 조회 | 각 시스템 → `StockDatabase.get_stocks_by_sector(sector)` — O(1) 인덱스 (S3-09) |
| 이벤트 태그 조회 | `news_event_system.gd` → `StockDatabase.get_stocks_by_event_tag(tag)` — O(1) 인덱스 (S3-09) |

### 호출 경로

- [x] `StockDatabase.get_stock(stock_id) -> StockData` 존재
- [x] `StockDatabase.get_all_stock_ids() -> Array[String]` 존재
- [x] `StockDatabase.get_stocks_by_sector(sector) -> Array[StockData]` 존재 (O(1) 인덱스)
- [x] `StockDatabase.get_stock_ids_by_sector(sector) -> Array[String]` 존재
- [x] `StockDatabase.get_stocks_by_event_tag(tag) -> Array[StockData]` 존재 (O(1) 인덱스)
- [x] `StockDatabase.stock_exists(stock_id) -> bool` 존재
- [x] `assets/data/stocks.json` — 46종목 11섹터 데이터 파일 존재

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 | 상태 |
|----|------------|------------|------|
| JSON 로드 정상 | `tests/unit/test_api_contracts.gd` | `test_stock_database_api()` | ✅ |
| 종목 수 검증 (46개) | 런타임 검증 (StockDatabase.get_stock_count() == 46) | — | ⬜ 단독 테스트 없음 |
| 섹터 인덱스 정확성 | 런타임 검증 필요 | — | ⬜ |

### 빌드 검증

- [x] 바이너리 실행 확인: QA Lead 서명 — 내부 감사 2026-04-15 (Alpha 완료 빌드, SCRIPT ERROR 없음)
