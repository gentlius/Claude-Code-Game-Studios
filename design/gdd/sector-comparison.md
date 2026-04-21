# A4 섹터 비교 분석 (Sector Comparison)

> **Status**: In Review
> **Priority**: Beta (Sprint 10)
> **Skill Gate**: T4 — A4 해금 필요 (A3 선행)
> **Created**: 2026-04-20
> **Last Updated**: 2026-04-20

---

## 1. Overview

A4 섹터 비교 분석은 11개 섹터의 **업종별 상대강도(Relative Strength)**를 한눈에
비교할 수 있는 뷰를 제공한다. A3(재무제표)가 개별 종목 심층 분석이라면,
A4는 섹터 간 순환(Sector Rotation)을 파악하는 매크로 관점의 분석 도구다.

A4는 P3(섹터 ETF) 해금의 전제 조건이다. 섹터 비교 없이 ETF에 투자하는 것은
근거 없는 베팅이기 때문에, 분석 역량 선행을 설계 의도로 강제한다.

---

## 2. Player Fantasy

"어떤 업종이 지금 가장 강세인가?"를 5초 안에 파악할 수 있다.

플레이어는 F2 화면(뉴스/루머)에서 특정 섹터 관련 뉴스를 보고,
A4 뷰에서 해당 섹터의 상대강도를 확인한 뒤,
P3 ETF로 빠르게 베팅한다.

"차트 읽기 → 섹터 파악 → ETF 베팅" 루프가 개별 종목 선택보다
낮은 인지 부하로 판단의 재미를 제공한다.

---

## 3. Detailed Design

### 3-1 A4 뷰 위치

- **접근 경로**: F1(차트/매매 화면) → 분석 패널 탭 → A4 섹터 비교
- **스킬 게이트**: A3 해금 후 T4 스킬 포인트 사용 → A4 해금 시 탭 활성화
- **레이아웃**: F1 우측 정보 패널의 A3 재무제표 탭 옆에 "섹터" 탭 추가

### 3-2 표시 정보

**메인 뷰 — 섹터 강도 순위표**

| 컬럼 | 내용 | 예시 |
|------|------|------|
| 순위 | 현재 수익률 기준 정렬 (1위 = 최강) | 1 |
| 섹터 | 섹터 한글명 | 반도체 |
| 수익률 (오늘) | 당일(현재 틱) 섹터 시가총액 가중 변동 | +3.2% |
| 수익률 (시즌) | 시즌 시작 대비 현재 수익률 | +18.7% |
| ETF 가격 | ETF_[섹터] 현재 가격 (P3 해금 시 표시, 미해금 시 `—`) | 59,350원 |
| 바 차트 | 수익률 크기를 컬러 바로 시각화 (양수=파랑, 음수=빨강) | ████░░ |

**상세 뷰 — 섹터 클릭 시 드릴다운**

- 해당 섹터 구성 종목 목록 (종목명, 오늘 등락, 시즌 등락)
- 구성 종목 중 상승 N개 / 하락 M개 표시
- 섹터 뉴스 태그 연동: 이 섹터에 영향을 주는 이벤트 태그 목록

### 3-3 갱신 주기

- 메인 순위표: 매 틱 갱신 (EtfManager 데이터 재사용)
- 드릴다운 상세: 섹터 클릭 시 즉시 계산

### 3-4 수익률 산출

A4가 표시하는 섹터 수익률은 EtfManager의 `get_etf_return(etf_id)` 값을
그대로 사용한다. 별도 계산 없음 — 단일 소유 원칙.

```
sector_return_display = EtfManager.get_etf_return("ETF_" + sector_name)
```

**당일 수익률 (장 중 변동)**:

```
# 오늘 시작 가격: 전일 종가 or 시즌 첫날은 기준가
today_return = (etf_price_now / etf_price_open_today) - 1.0
```

`etf_price_open_today`는 EtfManager가 매일 장 시작 시 스냅샷 저장.

### 3-5 정렬 옵션

- 기본: 시즌 수익률 내림차순 (가장 강한 섹터가 1위)
- 토글: 오늘 수익률 / 시즌 수익률 전환 정렬
- 섹터명 가나다순 정렬 (고정 참조용)

---

## 4. Formulas

### F1 섹터 시즌 수익률

sector-etf.md F1 공식과 동일. EtfManager에서 계산된 값 재사용.

```
sector_return_season = EtfManager.get_etf_return("ETF_" + sector_name)
```

### F2 섹터 당일 수익률

```
# open_price: EtfManager가 장 시작 시 저장한 당일 시가
today_return = (EtfManager.get_etf_price("ETF_" + sector_name) / EtfManager.get_etf_open_price("ETF_" + sector_name)) - 1.0
```

| 변수 | 타입 | 출처 |
|------|------|------|
| sector_name | String | "반도체", "2차전지" 등 |
| get_etf_price | float | EtfManager (현재 틱) |
| get_etf_open_price | float | EtfManager (당일 장 시작 스냅샷) |

---

## 5. Edge Cases

| 케이스 | 처리 방식 |
|--------|---------|
| 섹터 구성 종목 전부 거래 정지 | EtfManager.get_etf_return 동결값 그대로 표시 |
| 시즌 첫 틱 (open_price 스냅샷 미수집) | today_return = 0.0 표시 (N/A 표기 대신) |
| P3 미해금 시 ETF 가격 컬럼 | "—" 표시 (잠금 아이콘과 함께) |
| 11개 섹터가 모두 동일 수익률 | 섹터명 가나다순으로 순위 결정 |
| A4 미해금 상태 | 탭 자체가 비활성 (잠금 처리), 접근 불가 |
| 드릴다운 중 틱 갱신 | 드릴다운 뷰는 틱과 무관하게 클릭 시점 스냅샷 유지 (UX 안정성) |

---

## 6. Dependencies

| 시스템 | 방향 | 내용 |
|--------|------|------|
| EtfManager | Hard | 섹터 수익률·ETF 가격 조회 (단일 소유) |
| SkillTree | Hard | A4 해금 확인 (`is_unlocked("A4")`) |
| A3 재무제표 | Design-time | A4 해금 선행 조건 — financial-statements.md |
| StockDatabase | Hard | 섹터 구성 종목 목록 조회 |
| 뉴스/이벤트 시스템 | Soft | 드릴다운에서 섹터 관련 이벤트 태그 표시 |
| TradingScreen / F1 화면 | Hard | A4 탭 UI 수용 — 패널 레이아웃 변경 필요 |
| GameClock | Soft | `day_started` 신호 — 당일 시가 스냅샷 저장 트리거 |
| **역방향**: P3 섹터 ETF | Design-time | A4가 P3 해금 선행 조건 — sector-etf.md에 명시됨 |
| **역방향**: EtfManager | Hard | EtfManager는 A4가 소비할 `get_etf_return()` / `get_etf_open_price()` API를 제공해야 함 |

---

## 7. Tuning Knobs

| 파라미터 | 현재값 | 안전 범위 | 영향 |
|---------|--------|---------|------|
| 표시 섹터 수 | 11 (전체) | 변경 불가 (전 섹터 동등) | 정보 밀도 |
| 순위표 행 높이 | UI 조정 | 20px ~ 48px | 가독성 |
| 바 차트 최대 표시 범위 | ±20% | ±5% ~ ±50% | 시각 비교 정확도 |
| 당일 수익률 / 시즌 수익률 기본 정렬 | 시즌 수익률 | — | 플레이어 디폴트 관점 |

---

## 8. Acceptance Criteria

| AC # | 설명 | 유형 |
|------|------|------|
| AC-01 | A3 미해금 상태에서 A4 탭이 잠금 표시 | Unit |
| AC-02 | A4 해금 후 섹터 순위표 탭 활성화, 11개 섹터 전부 표시 | Unit |
| AC-03 | 순위표가 시즌 수익률 내림차순으로 정렬됨 | Unit |
| AC-04 | 정렬 토글 → 오늘 수익률 기준으로 순서 재정렬 | Unit |
| AC-05 | 섹터 클릭 → 드릴다운: 해당 섹터 구성 종목 목록 표시 | Unit |
| AC-06 | P3 미해금 시 ETF 가격 컬럼 "—" 표시 | Unit |
| AC-07 | P3 해금 후 ETF 가격 컬럼에 현재 ETF 가격 표시 | Unit |
| AC-08 | 섹터 수익률이 EtfManager.get_etf_return 값과 일치 | Unit |
| AC-09 | 당일 수익률이 장 시작 스냅샷 대비 현재 변동률과 일치 | Unit |
| AC-10 | (E2E) A3 해금 → A4 해금 → 섹터 비교 → 강세 섹터 확인 → P3 ETF 매수 전 흐름 | E2E |

---

## 9. Implementation Checklist

Approved 조건: 아래 전 항목 체크 완료 + QA Lead 서명.

### 진입점
`SkillTree.skill_unlocked("A4")` 신호 수신 → F1 화면 `SectorComparisonTab` 활성화.
플레이어가 탭 클릭 → `SectorComparisonView._refresh()` → EtfManager에서 전 섹터 수익률 조회.

### 호출 경로
- [x] `src/ui/sector_comparison_view.gd` 생성 (SectorComparisonView)
- [x] `SectorComparisonView._refresh()` — 11개 섹터 수익률 조회 + 정렬 + 표시
- [x] `EtfManager.get_etf_return(etf_id) -> float` — 시즌 수익률 반환 (sector-etf.md 구현 의존)
- [x] `EtfManager.get_etf_open_price(etf_id) -> float` — 당일 시가 반환 메서드 (S10-02에서 구현 완료)
- [x] `EtfManager._on_market_open()` — `on_market_open` 신호 수신 시 전 ETF 시가 스냅샷 저장
- [x] F1 화면 OrderPanel에 "섹터" 탭 추가 (order_panel.gd `_build_analysis_section()`)
- [x] 드릴다운 패널 — 구성 종목 표시 (SectorComparisonView 내장)
- [x] A4 해금 상태에 따른 탭 잠금/활성화 로직

### AC → 테스트 매핑

| AC | 테스트 파일 | 테스트 함수 |
|----|------------|------------|
| AC-01 | `tests/unit/test_sector_comparison.gd` | `test_tab_locked_without_a3()` |
| AC-02 | `tests/unit/test_sector_comparison.gd` | `test_all_11_sectors_displayed()` |
| AC-03 | `tests/unit/test_sector_comparison.gd` | `test_sorted_by_season_return()` |
| AC-04 | `tests/unit/test_sector_comparison.gd` | `test_toggle_sort_today_return()` |
| AC-05 | `tests/unit/test_sector_comparison.gd` | `test_drilldown_shows_sector_stocks()` |
| AC-06 | `tests/unit/test_sector_comparison.gd` | `test_etf_price_hidden_without_p3()` |
| AC-07 | `tests/unit/test_sector_comparison.gd` | `test_etf_price_shown_with_p3()` |
| AC-08 | `tests/unit/test_sector_comparison.gd` | `test_sector_return_matches_etf_manager()` |
| AC-09 | `tests/unit/test_sector_comparison.gd` | `test_today_return_from_open_snapshot()` |
| AC-10 | `tests/integration/test_sector_comparison_integration.gd` | `test_e2e_a3_a4_p3_flow()` |

### 빌드 검증
- [ ] `--export-release` 빌드 성공 (ERROR 없음)
- [ ] 바이너리 실행 후 5초 이상 프로세스 생존
- [ ] 실행 로그에 SCRIPT ERROR 없음
- [ ] QA Lead 서명: _______ (S10-12 E2E QA 세션에서 서명 예정)
