# Sprint 10 — 2026-05-01 to 2026-05-21

## Sprint Goal

Beta 최종 스프린트. 이 스프린트가 끝나면 Beta가 닫히고 Sprint 11부터 Polish가 시작된다.
이월 없음 — 모든 태스크를 이 스프린트 안에서 완결한다.

P3 섹터 ETF·A4 섹터 비교로 분석→ETF 매매 루프를 완성하고, TR4 레버리지 UI와
B-13 팡파레로 감성 연출을 완료한다. 이번 세션에서 업데이트된 GDD 전체
(save-load AC-18/19, news-events 가중치, season-manager E2E, currency-system E2E,
short-selling 마진율, leverage F2b, trading-fees MVP 계약, FinancialReport,
MarketProfile DLC)를 전부 구현하고, 유닛 테스트·fixture·GDD 상태 정리까지
완결 후 Beta 3시즌 E2E QA로 마일스톤을 닫는다.

## Capacity

- Total sessions: 15 (3주)
- Buffer (20%): 3 sessions
- Available: 12 sessions
- Sprint 9 velocity: Must Have 6/6 ✅ Should Have 3/3 ✅ Nice-to-Have 2/2 ✅

## Tasks

### Must Have (이월 없음 — 전 항목 이 스프린트 안에서 완결)

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S10-01 | A4 섹터 비교 분석 GDD 완성 + 구현 | game-designer + ui-programmer | 1.0 | EtfManager (S10-02 병행) | **(GDD)** `design/gdd/sector-comparison.md` 9개 섹션 완성 (Draft → In Review). **(구현)** `SectorComparisonView` 씬: 11개 섹터 수익률 순위표 + 오늘/시즌 수익률 토글 + 드릴다운. EtfManager.get_etf_return/get_etf_open_price API 연동. F1 화면 "섹터" 탭 추가. SkillTree A4 해금 시 탭 활성화. AC-01~AC-10 테스트 통과. 빌드 성공. |
| S10-02 | P3 섹터 ETF GDD 완성 + 구현 (B-08) | game-designer + gameplay-programmer | 2.0 | S10-01 (A4 선행) | **(GDD)** `design/gdd/sector-etf.md` 9개 섹션 완성 (Draft → In Review). **(구현 1)** `EtfManager` autoload: 11개 ETF 시즌 시작 시 50,000원 초기화, 매 틱 시가총액 가중 수익률 계산, PriceEngine.inject_price() 주입, 당일 시가 스냅샷. **(구현 2)** `PriceEngine.inject_price(etf_id, price)` 메서드 추가. **(구현 3)** `OrderEngine` — ETF 즉시 체결(슬리피지 없음) + TR3/TR4 거부 + P3 미해금 시 거부. **(구현 4)** `assets/data/etf_config.json` 생성. **(구현 5)** ETF 포지션 save-load (portfolio 블록 동일). AC-01~AC-13 테스트 통과. 빌드 성공. |
| S10-03 | TR4 레버리지 UI 완성 + 엔딩 화면 | ui-programmer | 1.5 | TR4 구현 (S9-04 완료), S10-07 (get_ending_param API) | **(1)** 레버리지 포지션 패널: 보유 레버리지 종목, 배율, 현재 손익, 마진비율 실시간 표시. **(2)** 마진콜 팝업: 마진비율 < 20% 진입 시 "긴급 추가 증거금 납부" 경고 팝업 + 자동 청산 카운트다운. **(3)** 엔딩 화면 3종 (`endings-achievements.md §9` 미구현 항목 전체): `EndingScreen.tscn` 단일 씬, `ending_id` 파라미터 → `MarketProfile.get_ending_param(ending_id, field)` 경유 데이터 바인딩 (ADR-021). (a) 한강 엔딩 (bankruptcy: cash_assets < 10,000원), (b) 론샤크 엔딩 (leverage_crash: 마진콜 강제청산 후 cash < 100만원), (c) 거장 엔딩 (win: cash_assets ≥ 1,000억 OR total_assets ≥ 1조). `GameMain`에서 3개 시그널 연결. 세이브 초기화 플로우 포함. **(4)** 빌드 성공 + QA 서명. |
| S10-04 | B-13 수익 실현 팡파레 GDD + 구현 | game-designer + ui-programmer | 1.0 | 주문 엔진 | **(GDD)** `design/gdd/profit-celebration.md` 9개 섹션 완성 (Draft → In Review). 이펙트 4등급(소/중/대/메가) 트리거 조건. **(구현)** OrderEngine 매도 체결 후 `realized_profit` 기준 등급 판정 → 파티클/사운드/텍스트 연출. AudioManager SFX 연동. 테스트 추가. 빌드 성공. |
| S10-05 | 재무보고 시스템 Phase 1 구현 | gameplay-programmer | 1.5 | financial-report-system.md | `design/gdd/financial-report-system.md` Phase 1 구현 체크리스트 전 항목: **(1)** `FinancialReportSystem` autoload — 분기 스케줄러, consensus_roe 계산, 4단계 정보 공개(analyst→잠정→루머→공식). **(2)** 분기 보고 이벤트 → 뉴스/이벤트 시스템 연동. **(3)** 세이브/로드 직렬화. **(4)** E-09 섹터 파급: LARGE 어닝쇼크 시 `NewsEventSystem.inject_event(scope:"SECTOR_RIPPLE", ...)` 호출 (ADR-022). **(5)** 테스트 추가. 빌드 성공. |
| S10-06 | GDD 업데이트 구현 — 이번 세션 수정 사항 전체 | gameplay-programmer + lead-programmer | 1.5 | — | **(a) save-load.md AC-18/19**: 레버리지·공매도 포지션 직렬화 유닛 테스트 (`borrowed`, `accrued_interest`, `entry_price`, `margin_deposited` 포함). **(b) news-events.md AC**: `test_news_events.gd._calculate_weight()` — boost=1.5 → ×1.5, boost=0.5 → ×0.5 정량 검증 (허용 오차 ±0.001). **(c) season-manager.md AC-21/22**: 프리마켓 → 브론즈 재진입 + auto_deposit E2E, 손실 → 한강 엔딩 E2E. **(d) currency-system.md E2E AC**: 브론즈 입금→매매→시즌종료→실버 배정→예수금 300만 자동입금 전 흐름. **(e) short-selling.md**: `short_selling_config.json`의 `margin_rate` 하한을 1.10→1.20으로 수정 + 하한 위반 시 거부 로직 확인. **(f) leverage-trading.md F2b**: 이자 원금화(부족분 borrowed 누적) 로직 구현 확인 또는 추가. **(g) trading-fees.md MVP 계약 검증**: OrderEngine이 `get_fee_breakdown()` 호출 시 `holding_days=0`을 실제로 전달하는지 grep 확인 → KR 시장 `capital_gains = 0` 항상 성립 단위 테스트 추가. |
| S10-07 | MarketProfile JSON DLC 인프라 (ADR-021 개정) | gameplay-programmer + lead-programmer | 1.5 | ADR-021, ADR-022 | **(Phase 1)** `assets/data/market_profiles/market_kr.json` 생성 (섹터/ETF/sector_archetypes/rivalry_weights/rotation_params/rotation_headline_keys/calendar 전체 포함) + `MarketProfile` autoload + `rivalry_weights` 합산 1.0 검증 로직. **(Phase 2)** GameClock, PriceEngine, ShortSelling, SeasonManager, AiCompetitor, EndingsAchievements, NewsEvents, StockDatabase, EtfManager — `MarketProfile.get_*()` 통한 설정값 읽도록 전환 (하드코딩 제거). **(Phase 3)** DLC 확장 테스트: `market_us.json` 최소 파일 + `MarketProfile.load("us")` 반환값 검증. **(Phase 4)** Godot `.po` 파일에 `ROTATION_KR_INFLOW_*` / `ROTATION_KR_OUTFLOW_*` 키 등록 + `tr()` 파이프라인 연결. 빌드 성공. |
| S10-08 | TD-CR-05 핵심 시스템 유닛 테스트 추가 | qa-lead + lead-programmer | 1.0 | — | StockDatabase, FormatUtils, CurrencySystem, PortfolioManager, NewsEventSystem의 public API에 대한 유닛 테스트 추가. `test_api_contracts.gd`에 해당 메서드 API 계약 등록. 기존 테스트 전부 통과. |
| S10-09 | TD-QA-01 superaccount.json fixture | qa-lead | 0.5 | — | `tests/fixtures/superaccount.json` 생성: cash_assets 충분 + 전 스킬 해금 상태. QA 10일 시나리오 테스트가 이 픽스처로 초기화 가능. |
| S10-10 | portfolio-manager.md Approved 전환 | game-designer + lead-programmer | 0.5 | xp-system Approved 확인 | portfolio-manager.md Status: In Review → Approved. 역방향 Hard 의존(xp-system)이 Approved 상태이므로 승격 조건 충족. 코드-GDD 일치 최종 확인. systems-index.md 갱신. |
| S10-11 | TD-CR-02 gamepad 홀딩스 네비게이션 | ui-programmer | 0.5 | — | `portfolio_view.gd` 컨트롤에 `focus_mode = Control.FOCUS_ALL` 설정. 게임패드 D-pad로 보유 종목 리스트 탐색 가능. 기존 테스트 전부 통과. |
| S10-12 | Beta 3시즌 E2E QA + beta.md Closed | qa-lead + producer | 0.5 | S10-01~S10-11 전체 완료 | **(1)** 3시즌 플레이 → 저장 → 재로드 수동 통과. **(2)** 이중 승리 조건(cash_assets ≥ 1,000억 OR total_assets ≥ 1조) 각 경로 수동 검증. **(3)** 가격 정찰 익스플로잇 차단(동일 세이브 5회 로드 → 가격 시퀀스 다름). **(4)** 14개 스킬 Phase 1~4 전부 해금 가능 확인. **(5)** `--export-release` 빌드 성공. **(6)** beta.md DoD 전 항목 `[x]` → Status: Closed. |

## Capacity Check

| Category | Sessions |
|----------|----------|
| Available (buffer 제외) | 12 |
| 전체 태스크 합계 | 12.0 (S10-01×1.0 + S10-02×2.0 + S10-03×1.5 + S10-04×1.0 + S10-05×1.5 + S10-06×1.5 + S10-07×1.5 + S10-08×1.0 + S10-09×0.5 + S10-10×0.5 + S10-11×0.5 + S10-12×0.5) |
| **적합성** | **12.0 / 12 ✅ 버퍼 정확히 소진** |

> 스프린트 기간 3주(2026-05-01~05-21)로 확장. 이월 없음. 전 태스크 Must Have.

## Critical Path

```
Day 0-1:  S10-01 A4 구현 (SectorComparisonView)
          S10-02 EtfManager + PriceEngine.inject_price 시작 (병행)
Day 2-3:  S10-02 OrderEngine ETF 통합 + 테스트
          S10-03 TR4 레버리지 UI (병행)
Day 3-4:  S10-04 팡파레 GDD + 구현
          S10-06 GDD 업데이트 구현 a~g (병행)
Day 4-5:  S10-05 FinancialReportSystem Phase 1
          S10-07 MarketProfile DLC Phase 1~3 (병행)
Day 5-6:  S10-05/S10-07 완성 + 테스트
Day 7:    S10-08 유닛 테스트 추가 (TD-CR-05)
Day 8:    S10-09 fixture + S10-10 GDD Approved + S10-11 gamepad
Day 9-10: 전체 빌드 검증 + 회귀 테스트
Day 10:   S10-12 Beta E2E QA + beta.md Closed
```

## DoD (Definition of Done)

- [x] S10-01: A4 섹터 비교 뷰 E2E (해금 → 순위표 → 드릴다운 → 정렬 토글) + 테스트 통과 + 빌드 성공
- [x] S10-02: P3 ETF E2E (P3 해금 → ETF 매수 → 섹터 상승 → 수익 매도) + AC-01~13 테스트 통과 + 빌드 성공
- [x] S10-03: TR4 레버리지 UI — 포지션 패널, 마진콜 팝업 + 엔딩 화면 3종 (한강/론샤크/거장 각 트리거 → EndingScreen 표시) 확인 + 빌드 성공 + QA 서명
- [x] S10-04: 팡파레 4등급 E2E (소/중/대/메가 각 트리거 조건 수동 확인) + 빌드 성공
- [x] S10-05: FinancialReportSystem Phase 1 — 분기 스케줄 발화, consensus_roe 계산, 뉴스 연동, E-09 LARGE 어닝쇼크 섹터 파급 확인 + 테스트 통과
- [x] S10-06: (a) save-load AC-18/19 테스트 통과 (b) news-events 가중치 정량 테스트 통과 (c) season-manager AC-21/22 통과 (d) currency-system E2E AC 통과 (e) margin_rate 하한 1.20 config 적용 확인 (f) F2b 이자 원금화 구현 확인 (g) trading-fees holding_days=0 계약 단위 테스트 통과
- [x] S10-07: MarketProfile market_kr.json 로드 + 전 의존 시스템 전환 + DLC market_us.json 테스트 통과
- [x] S10-08: 핵심 5개 시스템 유닛 테스트 추가 + API contracts 등록 + 전 테스트 통과
- [x] S10-09: superaccount.json fixture 생성 + QA 시나리오 연동 확인
- [x] S10-10: portfolio-manager.md Approved + systems-index.md 갱신
- [x] S10-11: gamepad 홀딩스 네비게이션 + 기존 테스트 통과
- [ ] S10-12: beta.md DoD 전 항목 `[x]` + beta.md Status: Closed + QA Lead 서명
- [ ] `sprint-10.md` DoD 전 항목 `[x]` — Producer 확인
