# 종목 데이터베이스 (Stock Database)

> **Status**: In Design
> **Author**: user + game-designer
> **Last Updated**: 2026-03-25
> **Implements Pillar**: 읽는 재미 (Read the Market)

## Overview

종목 데이터베이스는 시드머니의 모든 가상 종목을 정의하는 Foundation 시스템이다.
각 종목의 이름, 섹터, 기본가치, 변동성, 재무 지표 등 정적 속성을 관리하며,
가격 엔진, 뉴스 시스템, 매매 시스템이 이 데이터를 참조하여 작동한다.

한국 주식시장 구조를 참고한 10개 섹터에 각 1개 대표 종목을 배치하고,
각 섹터마다 고유한 변동성 프로필과 뉴스 반응 특성을 부여하여
플레이어가 종목별 차이를 읽고 전략을 세우는 재미를 제공한다.

MVP에서 10종목 전체를 포함한다. 10개 섹터의 다양성이 "읽는 재미"의 기반이다.

## Player Fantasy

플레이어는 각 종목을 "살아있는 기업"으로 인식한다. 이름만 보고도 어떤 업종인지
알 수 있고, 뉴스를 읽으면 해당 기업에 어떤 영향이 있을지 직관적으로 판단할 수 있다.
"메디진에 임상 성공 뉴스가 떴으니 급등할 거야" — 이런 추론이 자연스럽게 느껴져야
한다. 종목 데이터베이스는 이 직관적 판단의 근거를 제공하는 시스템이다.

## Detailed Design

### Core Rules

1. **종목 정의**: 각 종목은 고유 ID, 이름, 종목코드, 섹터, 정적 속성을 가진다.
2. **섹터 구조**: 10개 섹터, 각 섹터당 1개 대표 종목 (향후 확장 가능).
3. **정적 속성**: 게임 시작 시 로드되며 시즌 중 변경되지 않는 기본 특성.
4. **동적 데이터는 이 시스템에 없다**: 현재 가격, 거래량, 차트 데이터 등은
   가격 엔진이 관리. 종목 DB는 "이 종목이 어떤 종목인가"만 정의.

### 종목 데이터 스키마

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `id` | string | 고유 식별자 | "STARCHIP" |
| `name` | string | 표시 이름 | "스타칩" |
| `ticker` | string | 종목코드 (3-4자) | "STC" |
| `sector` | enum | 소속 섹터 | SEMICONDUCTOR |
| `description` | string | 기업 설명 (1-2문장) | "글로벌 반도체 설계 및 제조 기업" |
| `base_price` | int | 시즌 시작 시 기준가 (원) | 65000 |
| `market_cap_tier` | enum | 시가총액 등급 | LARGE / MID / SMALL |
| `volatility_profile` | enum | 변동성 프로필 | LOW / MEDIUM / HIGH / EXTREME |
| `sector_sensitivity` | float | 섹터 뉴스 반응 강도 (0.0-2.0) | 1.0 |
| `macro_sensitivity` | float | 거시경제 뉴스 반응 강도 (0.0-2.0) | 0.8 |
| `event_tags` | string[] | 반응하는 이벤트 태그 목록 | ["semiconductor", "export", "tech"] |
| `per` | float \| null | 주가수익비율. 적자 기업은 null (UI에 "N/A" 표시) | 12.5 (메디진: null) |
| `market_cap` | int | 시가총액 (억 원). UI 표시 전용 참고 정보. 게임 메카닉에 영향 없음 | 350000 |
| `dividend_yield` | float | 배당 수익률 (%). MVP에서는 UI 표시 전용 참고 정보. 향후 배당 이벤트 시스템 도입 시 활용 | 1.8 |

### 섹터 정의

| Sector ID | 한글명 | 특성 | 주요 이벤트 태그 |
|-----------|--------|------|----------------|
| SEMICONDUCTOR | 반도체/IT | 대형. 글로벌 수요 민감 | semiconductor, export, tech, AI |
| BATTERY | 2차전지 | 성장주. 정책 민감 | battery, ev, green_energy, policy |
| BIO | 바이오/제약 | 고변동. 이벤트 드리븐 | clinical_trial, fda, healthcare |
| AUTO | 자동차 | 수출/환율 연동 | export, exchange_rate, auto |
| FINANCE | 금융 | 저변동. 금리 민감 | interest_rate, regulation, finance |
| ENTERTAINMENT | 엔터/미디어 | 이벤트 드리븐 | content_hit, kpop, media |
| RETAIL | 유통/식품 | 방어주. 안정적 | consumption, season, retail |
| CONSTRUCTION | 건설 | 경기/정책 민감 | real_estate, policy, infrastructure |
| GAMING | 게임 | 고변동. 신작 이벤트 | game_release, esports, tech |
| ENERGY | 에너지/화학 | 원자재 연동 | oil_price, raw_material, chemical |

### 종목 목록

| # | ID | Name | Ticker | Sector | Base Price | Vol Profile | Cap Tier | PER | Div Yield | Sector Sens | Macro Sens |
|---|-----|------|--------|--------|-----------|-------------|----------|-----|-----------|-------------|------------|
| 1 | STARCHIP | 스타칩 | STC | SEMICONDUCTOR | 65,000 | MEDIUM | LARGE | 12.5 | 1.8% | 1.0 | 1.2 |
| 2 | GREENCELL | 그린셀 | GRC | BATTERY | 320,000 | HIGH | LARGE | 45.0 | 0.0% | 1.2 | 0.8 |
| 3 | MEDIGIN | 메디진 | MDG | BIO | 180,000 | EXTREME | MID | -* | 0.0% | 0.8 | 0.5 |
| 4 | AUTOMOBILE | 오토모빌 | ATM | AUTO | 185,000 | MEDIUM | LARGE | 8.0 | 3.5% | 1.0 | 1.3 |
| 5 | KOREABANK | 코리아뱅크 | KBK | FINANCE | 52,000 | LOW | LARGE | 6.5 | 5.0% | 1.0 | 1.5 |
| 6 | STARENT | 스타엔터 | STE | ENTERTAINMENT | 95,000 | HIGH | MID | 28.0 | 0.5% | 0.8 | 0.4 |
| 7 | LIFEMART | 라이프마트 | LFM | RETAIL | 120,000 | LOW | LARGE | 15.0 | 2.5% | 0.8 | 0.6 |
| 8 | BUILDONE | 빌드원 | BDO | CONSTRUCTION | 38,000 | MEDIUM | MID | 7.0 | 4.0% | 1.2 | 1.2 |
| 9 | PIXELGAMES | 픽셀게임즈 | PXG | GAMING | 210,000 | HIGH | MID | 22.0 | 1.0% | 0.8 | 0.4 |
| 10 | CHEMITEK | 케미텍 | CMT | ENERGY | 150,000 | MEDIUM | LARGE | 10.0 | 3.0% | 1.0 | 1.0 |

\* 메디진: 바이오 기업으로 아직 흑자 전환 전. PER 미적용 (적자 기업).

**MVP 종목** (10개): 전체 포함. 10개 섹터의 다양성이 코어 루프의 "읽는 재미" 기반.

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

### 종목 데이터베이스 자체에는 계산 공식이 없다

이 시스템은 정적 데이터 제공자이다. 공식은 이 데이터를 소비하는 시스템에 존재:
- 가격 변동 공식 → 가격 엔진 GDD
- 뉴스 영향 공식 → 뉴스/이벤트 시스템 GDD
- 손익 계산 공식 → 포트폴리오 관리 GDD

### 시즌별 기준가 조정 (향후 확장)

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
| 존재하지 않는 종목 ID 조회 | null 반환 + 에러 로그. 크래시하지 않음 | 방어적 프로그래밍 |
| 동일 섹터 내 다중 종목 (향후 확장) | 섹터 뉴스에 모두 반응하되, sector_sensitivity로 개별 강도 차등 | 같은 업종이어도 기업마다 반응 다름 |
| 적자 기업의 PER 표시 | PER < 0 또는 미적용 → UI에 "N/A" 표시 | 메디진 같은 바이오주는 흑자 전환 전 |
| 시즌 시작 시 기준가 0 이하 | 최소 기준가 1,000원으로 클램핑 | 비정상 데이터 방지 |
| event_tags가 비어있는 종목 | 섹터 뉴스에만 반응, 개별 이벤트 반응 없음 | 기본 동작으로 충분 |
| 배당 수익률 높은 종목 장기 보유 | MVP에서는 배당 이벤트 없음. dividend_yield는 참고 정보로만 표시 | 향후 확장으로 배당 메카닉 도입 예정 |

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
| `sector_sensitivity` | 1.0 | 0.0-2.0 | 섹터 뉴스에 더 크게 반응 | 섹터 뉴스에 둔감 |
| `macro_sensitivity` | 0.8 | 0.0-2.0 | 거시경제 이벤트에 더 크게 반응 | 거시경제에 둔감 |
| `dividend_yield` | 종목별 상이 | 0.0-8.0% | 장기 보유 인센티브 증가 | 단기 트레이딩 위주 |
| `mvp_stock_count` | 10 | 5-20 | 더 다양한 선택지 | 집중된 경험 |

---

## Acceptance Criteria

- [ ] 모든 종목이 고유 ID, 이름, ticker를 가지며 중복 없음
- [ ] `get_stock(id)` 호출 시 1ms 이내 응답
- [ ] 10개 섹터에 각 1개 종목이 정확히 매핑됨
- [ ] 각 종목의 변동성 프로필이 LOW/MEDIUM/HIGH/EXTREME 중 하나
- [ ] `get_stocks_by_event_tag(tag)` 호출 시 해당 태그를 가진 종목만 반환
- [ ] 적자 기업(PER < 0)의 PER이 UI에 "N/A"로 표시됨
- [ ] 모든 종목 데이터가 외부 config 파일에서 로드됨 (하드코딩 금지)
- [ ] MVP 빌드에서 10종목 전체가 로드됨
- [ ] 존재하지 않는 종목 ID 조회 시 크래시 없이 null 반환
- [ ] `stock_exists(id)` 호출 시 정확한 bool 반환 (1ms 이내)
- [ ] `get_stocks_by_sector(sector_id)` 호출 시 해당 섹터 종목만 반환 (1ms 이내)

---

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| 시즌별 종목 추가/폐지 이벤트 도입 여부 | game-designer | 시즌 관리 GDD 시 | 향후 확장 |
| 종목 데이터를 JSON vs Resource(Godot) 중 어느 형식으로 저장 | engine-programmer | 엔진 설정 후 | /setup-engine 후 결정 |
| 동일 섹터에 2-3개 종목 추가 시 밸런스 조정 방법 | systems-designer | 확장 시점 | 향후 |
