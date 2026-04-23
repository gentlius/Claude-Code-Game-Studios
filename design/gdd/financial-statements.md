# 재무제표 (Financial Statements) — A3 스킬

> **Status**: In Review (S8-02/03 PER/PBR/ROE 구현 완료 — total_shares ADR-019 연동 + UI 잔여)
> **Sprint**: Sprint 8 (S8-02/03)
> **Skill ID**: A3
> **Prerequisite**: A2 해금
> **Owner**: game-designer + gameplay-programmer
>
> **연동**: ROE/PER/PBR 갱신 주체는 이 파일이 아님 — [financial-report-system.md](financial-report-system.md) 참조.
> 이 GDD는 A3 패널 **표시 UI** 전용. 데이터 소유는 StockData, 갱신 트리거는 FinancialReportSystem.

---

> **⚠️ 구현 전 필독 — ADR-019 연동**
>
> 이 스킬 구현 시 `StockData`에 `total_shares: int`와 `major_shareholder_pct: float`를
> 추가해야 한다. 이 값이 도입되면 `PriceEngine`의 `DAILY_VOLUME_BY_PROFILE` 고정값을
> `daily_volume = total_shares * turnover_rate_by_profile`로 교체할 수 있다.
>
> - 교체 후 호가잔량·압력 정규화·슬리피지가 시총 비례로 자동 조정됨
> - 현재 `PLAYER_PRESSURE_SCALE`의 선형 충격 모델을 제곱근 충격 법칙으로 고도화 가능
> - 설계 근거 및 교체 조건: [ADR-019](../../docs/architecture/019-player-market-impact.md) §이연된 개선 참조

---

## 1. Overview

A3 스킬 해금 시 거래 화면 종목 패널에 PER·PBR·ROE 세 가지 기업 재무 지표가 표시된다.
플레이어는 현재가와 기업 가치를 비교해 고평가·저평가 여부를 판단할 수 있으며,
뉴스 이벤트로 인한 가격 변화가 재무 지표에 어떻게 반영되는지 관찰하는 새로운 분석 레이어가 생긴다.

지표는 `StockData`에 시즌 시작 시 로드된 기준값에서 틱마다 경미하게 변동한다.
실시간 계산이 아닌 시뮬레이션 변동이므로 성능 비용이 없다.

---

## 2. Player Fantasy

"이 종목, PER이 5밖에 안 되는데 다들 왜 안 사지?"
차트와 뉴스로만 판단하던 플레이어가 처음으로 기업 본질 가치를 들여다보는 순간.
저PER 종목을 발굴하거나 고PBR 종목을 피하는 선택이 생긴다.
숫자 하나가 매수/매도 판단을 바꾸는 경험.

---

## 3. Detailed Design

### 3-1. 표시 위치

거래 화면 종목 선택 후 나타나는 종목 정보 패널 하단에 A3 전용 섹션 추가.

```
┌────────────────────────────────────┐
│  삼성전자(005930)                   │
│  ₩74,200  ▲+2.3%                  │
│  [차트 영역]                        │
│                                    │
│ ── 재무 지표 (A3) ──────────────── │
│  PER   22.0      PBR   1.8        │
│  ROE   8.2%      배당  1.5%        │
└────────────────────────────────────┘
```

- A3 미해금 시 섹션 전체 숨김 (공간 차지 없음)
- 배당수익률(`dividend_yield`)은 `StockData`에 이미 존재 → A3 해금 시 함께 표시

### 3-2. 지표 정의

| 지표 | 명칭 | 의미 | 표시 형식 |
|------|------|------|----------|
| PER | 주가수익비율 | 현재가 / 주당순이익. 낮을수록 저평가 | 소수점 1자리 (예: 22.0) |
| PBR | 주가순자산비율 | 현재가 / 주당순자산. 1 미만 = 장부가 이하 | 소수점 2자리 (예: 1.82) |
| ROE | 자기자본이익률 | 순이익 / 자기자본. 높을수록 수익성 우수 | % 소수점 1자리 (예: 8.2%) |
| 배당수익률 | — | 연간 배당 / 현재가 | % 소수점 1자리 (예: 1.5%) |

### 3-3. 데이터 모델

**기준값**: `StockData`에 시즌 로드 시 JSON에서 읽음.
- `per`: 이미 존재 ✅
- `pbr`: 신규 추가 필요 (`stock_data.gd` + `stocks.json`)
- `roe`: 신규 추가 필요
- `dividend_yield`: 이미 존재 ✅

**틱 변동**: `PriceEngine`이 매 틱 현재가 변화에 비례해 PER·PBR을 재계산.
ROE는 틱 변동 없음 (기업 수익성은 단기 가격에 무관).

```
PER_current = StockData.per * (current_price / base_price)
PBR_current = StockData.pbr * (current_price / base_price)
ROE_current = StockData.roe  ## 고정
```

**결손 기업 표시**: `per == 0.0` 또는 `pbr == 0.0` 이면 "N/A" 표시.

> **FinancialReportSystem 연동 주의**: `FinancialReportSystem`이 정기 실적 이벤트 발생 시 `StockData.per`와 `StockData.pbr`을 업데이트한다 ([financial-report-system.md](financial-report-system.md) 참조). 이 시점에 `base_per`/`base_pbr` 기준이 변경되어 `PER_current`·`PBR_current` 표시값이 단계적으로 변화한다 — **의도된 동작**. 실적 공시 직후 재무 지표가 급변하는 것은 버그가 아니라 공시 효과가 반영된 결과다.

### 3-4. 종목별 기준값 범위 (stocks.json 추가 기준)

KRX 섹터별 일반적 범위를 참고하여 설정:

| 섹터 | PER 범위 | PBR 범위 | ROE 범위 |
|------|---------|---------|---------|
| 반도체 | 15~45 | 1.5~4.0 | 10~25% |
| 배터리/2차전지 | 20~80 | 2.0~6.0 | 5~20% |
| 바이오/제약 | N/A~60 | 2.0~8.0 | -5~15% |
| 자동차 | 5~15 | 0.5~1.5 | 5~15% |
| 금융 | 5~12 | 0.4~1.0 | 8~15% |
| 엔터/콘텐츠 | 15~50 | 1.5~5.0 | 5~20% |
| 철강/소재 | 6~15 | 0.4~1.2 | 5~12% |
| 유통/소비재 | 10~25 | 0.8~2.0 | 5~15% |

---

## 4. Formulas

### F1. PER 틱 변동

```
PER_display = base_per * (current_price / season_start_price)

변수:
  base_per           : StockData.per (JSON 기준값, 시즌 고정)
  current_price      : PriceEngine._stock_states[id].current_price
  season_start_price : PriceEngine._stock_states[id].open_price (시즌 첫 가격)

범위: 0.0 (결손) ~ 약 200.0 (극단적 고평가)
예시: base_per=22.0, current_price=80000, season_start_price=74200 → 23.7
```

### F2. PBR 틱 변동

```
PBR_display = base_pbr * (current_price / season_start_price)

변수:
  base_pbr : StockData.pbr (신규 필드)

범위: 0.0 (결손) ~ 약 15.0
예시: base_pbr=1.8, 가격 +7.8% → 1.94
```

### F3. ROE (고정)

```
ROE_display = StockData.roe  ## 틱 변동 없음

범위: -30.0 ~ 50.0 (%, 결손 기업은 음수 가능)
```

### F4. 배당수익률 틱 변동

```
dividend_display = StockData.dividend_yield / (current_price / season_start_price)

## 가격이 오를수록 배당수익률 하락 (실제 시장 공식 반영)
```

---

## 5. Edge Cases

| 상황 | 처리 |
|------|------|
| `per == 0.0` (결손 기업) | "N/A" 표시. 음수 PER 계산 없음 |
| `pbr == 0.0` | "N/A" 표시 |
| `roe < 0` (적자 기업) | 빨간 색상으로 "▼8.2%" 형식 표시 |
| 가격이 base_price의 400% 초과 | PER/PBR 값이 비정상적으로 커짐. 표시 상한 없음 — 플레이어 판단 영역 |
| `dividend_yield == 0.0` | 배당 행 숨김 (무배당 종목) |
| A3 미해금 상태에서 종목 패널 표시 | 재무 지표 섹션 Node 숨김. 공간 재계산 |

---

## 6. Dependencies

| 시스템 | 방향 | 내용 |
|--------|------|------|
| `StockData` (`src/data/stock_data.gd`) | Hard | `pbr`, `roe`, **`total_shares`**, **`major_shareholder_pct`** 필드 추가 필요 |
| `StockDatabase` (`src/core/stock_database.gd`) | Hard | JSON에서 `pbr`, `roe`, `total_shares`, `major_shareholder_pct` 로드 로직 추가 |
| `assets/data/stocks.json` | Hard | 46개 종목 `pbr`, `roe`, `total_shares`, `major_shareholder_pct` 값 추가 |
| `PriceEngine` | **Hard** | `total_shares` 도입 시 `DAILY_VOLUME_BY_PROFILE` → 파생값으로 교체. [ADR-019](../../docs/architecture/019-player-market-impact.md) §이연된 개선 참조 |
| `SkillTree` | Hard | `is_skill_unlocked("A3")` → 패널 표시 여부 |
| `TradingScreen` / 종목 정보 패널 | Hard | A3 섹션 UI 노드 추가 |
| `chart-renderer.md` | Soft | A2 패널 배치 패턴 참조 |

---

## 7. Tuning Knobs

| 변수 | 위치 | 기본값 | 범위 | 영향 |
|------|------|--------|------|------|
| `pbr` per stock | `stocks.json` | 섹터별 상이 | 0.0~15.0 | 종목 상대 저평가 느낌 |
| `roe` per stock | `stocks.json` | 섹터별 상이 | -30~50% | 종목 수익성 정체성 |
| PER/PBR 상한 표시 | UI 상수 | 없음 | — | 극단값 표시 여부 |

---

## 8. Acceptance Criteria

| # | 조건 | 판정 방법 |
|---|------|---------|
| AC-01 | A3 미해금 시 재무 지표 섹션이 표시되지 않는다 | A3 미해금 상태에서 종목 패널 확인 → 섹션 없음 |
| AC-02 | A3 해금 후 종목 패널에 PER·PBR·ROE·배당 표시 | A3 해금 → 임의 종목 선택 → 4개 값 표시 확인 |
| AC-03 | 결손 기업(per=0) 종목의 PER이 "N/A"로 표시 | 결손 종목(예: 바이오 적자사) 선택 → PER "N/A" |
| AC-04 | 가격 상승 시 PER·PBR이 비례 증가 | 틱 관찰: 가격+10% → PER+10% 확인 |
| AC-05 | ROE는 틱 변동 없이 고정 | 틱 10회 관찰 → ROE 값 불변 확인 |
| AC-06 | 무배당 종목(dividend_yield=0)은 배당 행 숨김 | 무배당 종목 선택 → 배당 행 미표시 확인 |
| AC-07 | `--export-release` 빌드 성공, SCRIPT ERROR 없음 | QA Lead 빌드 검증 |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
- 이 기능은 어디서 호출되는가: `TradingScreen._on_stock_selected(stock_id)` → 종목 정보 패널 갱신 → A3 섹션 표시

### 호출 경로

**데이터 레이어**
- [x] `src/data/stock_data.gd`: `pbr: float = 0.0`, `roe: float = 0.0` 필드 추가 (S8-02)
- [ ] `src/data/stock_data.gd`: `total_shares: int = 0`, `major_shareholder_pct: float = 0.0` 필드 추가 (**ADR-019 연동 필수, 미구현 블로커**)
- [ ] `src/core/stock_database.gd`: `_load_stock()` 에서 `total_shares`, `major_shareholder_pct` JSON 파싱 추가
- [ ] `assets/data/stocks.json`: 46개 종목 `total_shares`, `major_shareholder_pct` 값 추가 (§3-4 섹터 범위 기준)
- [ ] `src/gameplay/price_engine.gd`: `DAILY_VOLUME_BY_PROFILE` → `total_shares * turnover_rate_by_profile` 파생값으로 교체 ([ADR-019](../../docs/architecture/019-player-market-impact.md) §이연된 개선)

**표시 로직**
- [x] `PriceEngine.get_per_display(stock_id) -> String` 구현 완료 (`price_engine.gd:474`, S8-02)
- [x] `PriceEngine.get_pbr_display(stock_id) -> String` 구현 완료 (`price_engine.gd:489`, S8-02)
- [ ] 종목 정보 패널 UI: A3 섹션 노드 추가 (PER·PBR·ROE·배당 레이블 4개)
- [ ] `SkillTree.is_skill_unlocked("A3")` 체크 → 섹션 visible 제어

**엣지 케이스**
- [ ] `per == 0.0` / `pbr == 0.0` → "N/A" 표시 분기
- [ ] `roe < 0` → 빨간 색상 표시
- [ ] `dividend_yield == 0.0` → 배당 행 숨김

### AC → 테스트 매핑
| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_financial_statements.gd` | `test_a3_panel_hidden_when_not_unlocked()` |
| AC-03 | `tests/unit/test_financial_statements.gd` | `test_per_null_display()` |
| AC-04 | `tests/unit/test_financial_statements.gd` | `test_per_scales_with_price()` |
| AC-05 | `tests/unit/test_financial_statements.gd` | `test_roe_is_fixed()` |

### 빌드 검증
- [ ] 바이너리 실행 확인: QA Lead 서명 _______
