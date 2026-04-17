# Sprint 9 — 2026-04-17 to 2026-04-30

## Sprint Goal

TR3 공매도·TR4 레버리지로 고급 거래 브랜치를 완성하고, B-09 설정 화면으로
플레이어 제어권을 확보한다. 거래 수수료·세금 시스템을 MarketConfig 일반식으로
구현해 향후 시장별 DLC 확장 기반을 마련한다. OHLCV 시즌 간 누적은
주봉/월봉 차트 구현 선행 조건으로 이 스프린트에서 해결한다.

## Capacity

- Total sessions: 10
- Buffer (20%): 2 sessions
- Available: 8 sessions
- Sprint 8 velocity: Must Have 6/6 ✅ Should Have 3/3 ✅ Nice-to-Have 0/1

## Tasks

### Must Have (Critical Path)

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S9-01 | TR3 공매도 GDD 작성 (B-07b) | game-designer | 0.5 | — | `design/gdd/short-selling.md` 9개 섹션 완성. 공매도 개시·상환·강제청산 조건, 증거금 공식, 리스크 표시 패널 와이어프레임. S9-02 선행 조건. |
| S9-02 | TR3 공매도 구현 (B-07b) | gameplay-programmer | 1.5 | S9-01 완료 | **(1)** `OrderEngine`에 `SELL_SHORT` 주문 타입 추가. **(2)** 증거금 계산 + 강제청산 트리거 (`margin_ratio < 0.2`). **(3)** 포트폴리오 뷰에 공매도 포지션 표시 (음수 수량, 손익). **(4)** `SkillTree.has_short_selling()` 미해금 시 주문 거부. **(5)** 테스트 추가 + 빌드 성공. |
| S9-03 | TR4 레버리지 GDD 작성 (B-07c) | game-designer | 0.5 | — | `design/gdd/leverage-trading.md` 9개 섹션 완성. 레버리지 배율(2×/3×/5×), 이자 비용 공식, 마진콜 조건, 리스크 경고 UI. S9-04 선행 조건. |
| S9-04 | TR4 레버리지 구현 (B-07c) | gameplay-programmer | 1.5 | S9-03 완료 | **(1)** `OrderEngine`에 레버리지 배율 파라미터 추가. **(2)** 일별 이자 자동 차감 (`LifestyleManager.process_offseason()` 패턴 참조). **(3)** 마진콜 → 자동 포지션 청산. **(4)** `SkillTree.has_leverage()` 미해금 시 배율 선택 UI 잠금. **(5)** 테스트 추가 + 빌드 성공. |
| S9-05 | B-09 설정 화면 GDD + 구현 | game-designer + ui-programmer | 2.5 | — | **(1)** `design/gdd/settings-screen.md` 9개 섹션 완성 (볼륨 슬라이더, 뉴스 자동 감속 On/Off, 색각 모드, 키 리맵 와이어프레임). **(2)** `SettingsScreen` 씬: 볼륨 슬라이더 → `AudioManager` 연결, 뉴스 자동 감속 토글 → `GameClock.AUTO_SLOW_ON_EVENT` 적용. **(3)** 설정값 세이브/로드 직렬화. **(4)** `MainScreen` 탭바 또는 일시정지 메뉴에서 접근 가능. **(5)** 테스트 추가 + 빌드 성공. |
| S9-06 | 거래 수수료·세금 시스템 GDD + 구현 | game-designer + gameplay-programmer | 1.5 | — | **(GDD)** `design/gdd/trading-fees.md` 9개 섹션 완성. 일반화 공식, MarketConfig JSON 스키마, KR 파라미터, 미래 시장 예약 슬롯. **(구현 1)** `assets/data/market_config.json` — KR 데이터 + US/JP/HK/CN 예약 슬롯. **(구현 2)** `MarketConfig` autoload: `get_fee_breakdown(side, gross, holding_days, realized_profit) → {commission, sell_tax, buy_tax, capital_gains_tax, net}`. **(구현 3)** `OrderEngine` 매수/매도 체결 시 `MarketConfig.get_fee_breakdown()` 호출 → net 금액으로 `CurrencySystem` 차감. **(구현 4)** `PortfolioManager` 매도 시 holding_days 추적 + capital_gains_tax 즉시 차감. **(구현 5)** 체결 알림에 "수수료 ₩X / 세금 ₩Y" 항목 표시. **(테스트)** KR 매도: sell_tax 0.20% + commission 0.015% 정확 차감, capital_gains_rate=0 → 추가 차감 없음. US 가상(short_rate=0.22) → 이익의 22% 즉시 차감. 빌드 성공. |

### Should Have

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S9-07 | TD-HIST-01 OHLCV 시즌 간 영구 누적 (주봉/월봉 선행 조건) | gameplay-programmer | 1.5 | — | **(1)** 슬롯 생성 시 `history_seed`로 100~300시즌 분량 pre-generated history 생성 (`PriceEngine.generate_pre_history(seed, stock_id, length)` — 단순 랜덤워크). **(2)** 실제 플레이 완료 시즌: 1분봉 OHLCV(390바/일 × 20일 × 46종목) gzip 압축 저장 (~1~1.5MB/시즌). **(3)** 파생 집계: `get_candles(timeframe)` 단일 API — 1분봉 원본에서 5분/15분/일/주(5일)/월(20일=1시즌)봉 집계. 진행 중 캔들은 `current_price` 매틱 갱신. **(4)** 세이브/로드 직렬화 (gzip 압축, 슬롯 내 포함, ADR-009 호환). **(5)** 5시즌 플레이 후 전 타임프레임 캔들 수 검증. **(6)** 테스트 추가. |
| S9-08 | TD-CR-03 SaveSystem.active_slot_id private 전환 | lead-programmer | 0.5 | — | `active_slot_id` → `_active_slot_id` (private). `get_active_slot_id()` getter 추가. 외부 직접 쓰기 6개 테스트 파일 `before_each` 패턴 수정. 기존 테스트 전부 통과. |
| S9-09 | TD-CR-11 UIState enum 중복 통합 | lead-programmer | 0.5 | — | `ui_state_types.gd` (autoload 또는 `src/core/`) 공유 enum 파일 생성. `StatusBar.UIState` / `TradingScreen.UIState` 양쪽 참조를 공유 enum으로 교체. 기존 테스트 전부 통과. |

### Nice to Have

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S9-10 | TD-CR-06 portfolio_view.gd 메서드 분리 | lead-programmer | 0.5 | — | `_on_stop_take_btn_pressed()` 138줄 → `_build_stop_take_dialog()` 등으로 분리, 각 함수 40줄 이내. Stop/Take 다이얼로그 문자열에 `tr()` 추가. |
| S9-11 | TD-AUDIT-01 settlement_reporter.gd 레이스 컨디션 조사 | qa-lead | 0.5 | — | 팝업 닫힘 중 타이머 발화 재현 시도. 재현 성공 시 수정 + 테스트. 재현 불가 시 "재현 불가 확인" 주석 + tech-debt 항목 종결. |

## Capacity Check

| Category | Sessions |
|----------|----------|
| Available (buffer 제외) | 8 |
| Must Have 합계 | 8.0 (S9-01×0.5 + S9-02×1.5 + S9-03×0.5 + S9-04×1.5 + S9-05×2.5 + S9-06×1.5) |
| Should Have | 2.5 (S9-07×1.5 + S9-08×0.5 + S9-09×0.5) |
| Nice to Have | 1.0 |
| **Must Have 적합성** | **8.0 / 8 ✅** |
| **전체 합계** | **11.5 (Should Have는 buffer 소진 후 우선순위 순 진행)** |

## Critical Path

```
Day 0:    S9-01 TR3 GDD (game-designer)
          S9-03 TR4 GDD (game-designer, 병행)
          S9-06 거래수수료 GDD (game-designer, 병행)
Day 1-2:  S9-02 TR3 구현 (S9-01 완료 후)
          S9-04 TR4 구현 (S9-03 완료 후, 병행 가능)
          S9-06 MarketConfig 구현 (GDD 완료 후, 병행 가능)
Day 3-4:  S9-05 설정화면 GDD + 구현
Day 5:    S9-05 설정화면 세이브/로드 완성
          S9-07 OHLCV 누적 (Should Have)
Day 6-7:  S9-07 OHLCV 완성 + S9-08/S9-09 (Should Have)
Day 8:    S9-10/S9-11 (Nice-to-Have)
```

## DoD (Definition of Done)

- [x] S9-01: `design/gdd/short-selling.md` 9개 섹션 Approved (2026-04-17)
- [x] S9-02: TR3 해금 → 공매도 주문 E2E + 강제청산 트리거 확인 + 테스트 통과 + 빌드 성공 (2026-04-17)
- [x] S9-03: `design/gdd/leverage-trading.md` 9개 섹션 Approved (2026-04-17)
- [x] S9-04: TR4 해금 → 레버리지 주문 E2E + 마진콜 자동 청산 확인 + 테스트 통과 + 빌드 성공 (2026-04-17)
- [x] S9-05: 설정화면 볼륨·자동감속 E2E + 세이브/로드 확인 + 빌드 성공 (2026-04-17)
- [x] S9-06 GDD: `design/gdd/trading-fees.md` 9개 섹션 Approved (2026-04-17)
- [x] S9-06 구현: MarketConfig autoload + JSON + OrderEngine 수수료 적용 + 테스트 통과 + 빌드 성공 (2026-04-17)
- [x] S9-07 (Should Have): 5시즌 누적 데이터 세이브/로드 + 용량 검증 + 테스트 통과 (2026-04-17)
  - OhlcvHistory autoload: 시드 기반 pre-history(200시즌) + 실플레이 일봉 누적
  - 차트 렌더러 W1(주봉)/MN(월봉) 타임프레임 추가
  - test_ohlcv_history.gd 14개 테스트 — 5시즌 시뮬레이션 검증 포함
- [x] S9-08 (Should Have): `active_slot_id` private 전환 + 기존 테스트 전부 통과 (2026-04-17)
- [x] S9-09 (Should Have): UIState 공유 enum 전환 + 기존 테스트 전부 통과 (2026-04-17)
- [x] S9-10 (Nice-to-Have): `portfolio_view.gd` 메서드 분리 — `_build_ui()` 6개, `_refresh_holdings()` 4개 함수로 분리, `tr()` 누락 수정 (2026-04-17)
- [x] S9-11 (Nice-to-Have): `settlement_reporter.gd` 레이스 컨디션 — 재현 불가 확인, TD-AUDIT-01 종결 (2026-04-17)
- [x] `sprint-09.md` DoD 전 항목 `[x]` — Producer 확인 (2026-04-17, S9-07은 Should Have DoD 기준 충족)
