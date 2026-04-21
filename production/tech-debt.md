# Technical Debt Register

> 코드 리뷰 (2026-04-03)에서 식별된 아키텍처 이슈.
> **최종 검토**: 2026-04-09 — season_active 단일 소스 / PriceEngine 초기화 / 시그널 순서 버그픽스 반영.

---

## V-Slice 전 (필수)

### ~~TD-01. 틱 처리 순서 보장~~ — **해결됨 (2026-04-04)**

- `game_clock.gd._process_tick()`에서 NewsEventSystem → PriceEngine → OrderEngine 순차 호출 후 `on_tick.emit()` 브로드캐스트. S2-05 검토 중 기확인.

### ~~TD-02. 테스트 격리용 `reset_for_testing()` 메서드~~ — **해결됨 (2026-04-04)**

- 전체 10개 autoload에 `reset_for_testing()` 추가 완료. `test_api_contracts.gd`에 계약 테스트 추가.

### ~~TD-08. SeasonManager.start_season() 호출 경로 없음~~ — **해결됨 (2026-04-04, S3-01)**

- `SeasonManager.start_season()` → `GameClock.start_season()` 내부 호출. 의존성 역전 방지 패턴 적용.

---

## Production 진입 시

### ~~TD-03. UI 직접 상태 변경 완화~~ — **해결됨 (2026-04-04, S3-13)**

- `SkillTreeOverlay` / `TradingScreen` pause·speed 시그널 추가. `MainScreen`에서 `GameClock` 연결.

### ~~TD-04. trading_screen.gd God Object 분리~~ — **해결됨 (Sprint 4, S4-01)**

- `trading_screen.gd` 현재 **586줄** (기존 1930줄 → 70% 감소).
- 분리 완료: `status_bar.gd` / `toast_manager.gd` / `order_panel.gd` / `stock_list_panel.gd` / `settlement_reporter.gd`
- 문서 업데이트 누락으로 Active 상태로 잘못 기재됐던 것. (코드 확인: 2026-04-07)

---

## Polish 단계

### ~~TD-05. 로컬라이제이션 (tr() 래핑)~~ — **해결됨 (Sprint 5, S5-04)**

- `src/ui/*.gd` 전체 사용자 대면 문자열 `tr()` 래핑 완료. `locale/ko.po` 생성. `project.godot` ko locale 등록.
- (문서 업데이트 누락으로 Active 상태로 잘못 기재됐던 것. 코드 확인: 2026-04-07)

### ~~TD-06. 게임패드 입력 지원~~ — **해결됨 (Sprint 5, S5-05)**

- `trading_screen.gd:165` `InputEventJoypadButton` 처리 확인. `InputMap` 게임패드 액션 등록 완료.
- (문서 업데이트 누락. 코드 확인: 2026-04-07)

### ~~TD-07. 애니메이션 접근성 (reduced_motion)~~ — **해결됨 (S3-12 + TD-04 완료 후)**

- `xp_bar.gd`: `_reduced_motion()` 체크 전체 적용.
- `level_up_banner.gd`: `show_level_up()` / `hide_banner()` reduced_motion 체크 적용.
- `toast_manager.gd`: `_reduced_motion()` 구현 완료 (line 46, 81). TD-04 분리 후 적용 완료.
- (코드 확인: 2026-04-07)

---

## M/L 코드 리뷰 잔여 (S3-09 부분 해결)

### ✅ 해결됨 (S3-09)
- ~~`_format_number` 중복~~ → `FormatUtils.number()` static class 추출.
- ~~SpinBox 에러 Tween 누적~~ → `_error_tween` kill 후 재생성.
- ~~OrderEngine 주문 히스토리 무제한 증가~~ → `ORDER_HISTORY_MAX_SIZE = 500`.
- ~~stock_database O(n) 스캔~~ → `_sector_index` / `_tag_index` Dictionary 사전 계산.

### ✅ 해결됨 (S5-03)
- ~~차트 RSI/MACD 캐싱 (매 프레임 배열 할당)~~ → `_rsi_cache: Array[float]` 사전 계산 방식으로 전환. `_draw_rsi()` / `_draw_macd()` 는 pre-computed cache 읽기만 수행 (O(visible) per draw). (코드 확인: 2026-04-07)

### ✅ 해결됨 (S4-05)
- ~~스킬트리 14개 스킬 하드코딩 → 데이터 파일~~ → `assets/data/skill_tree.json` 생성. `SkillTree` autoload JSON 로드. (코드 확인: 2026-04-07)

### ✅ 해결됨 (2026-04-05)
- ~~뉴스 날짜 월 하드코딩 (3월 고정)~~ → `SeasonManager.get_fiction_date()` 도입. Q1~Q4 자동 순환.

---

## 베타 코드 리뷰 잔여 항목 (2026-04-14)

### ~~TD-CR-01. ai_competitor.gd EOD 재계산 O(day)~~ — **해결됨 (2026-04-14)**

- `_compute_eod_for`에 `eod_rng_states: Array[int]` 캐시 도입. 전일 EOD RNG 상태를 저장해
  다음 호출 시 O(1) 한 스텝만 진행. Day 0 또는 캐시 미존재 시만 O(day) 재계산.

### ~~TD-CR-02. 게임패드 홀딩 목록 탐색 불가~~ — **해결됨 (2026-04-20, S10-11)**

- `portfolio_view.gd` `_add_holding_row()`에 `focus_mode = Control.FOCUS_ALL` 적용 완료.

## 잔여 오픈 항목

### ~~TD-AUDIT-01. settlement_reporter.gd 레이스 컨디션~~ (종결 2026-04-17)

- **현황**: 팝업 닫힘 중 타이머가 발화할 경우 다음 시즌 공개 순서 혼란 가능성.
- **우선순위**: Medium
- **목표 스프린트**: Sprint 6 S6-04
- **재현 결과**: 재현 불가 확인 (S9-11, 2026-04-17). GDScript 단일 스레드 모델에서
  `_confirm()` 내 `stop()` → `_season_reveal_step = -1` 순서는 원자적.
  타이머가 같은 프레임에 이미 발화했더라도 sentinel 체크(`step == -1`)가 즉시 차단.
  추가 안전망: `tree_exiting` 연결이 노드 제거 시 타이머 강제 중지.
  코드 위치: `settlement_reporter.gd` lines 46-50, 321-328.

### ~~TD-AUDIT-02. xp_bar.gd C-01 시그니처 불일치~~ — **해결됨 (2026-04-21 감사 확인)**

- `_on_xp_gained(amount, _new_total, _source)` 3-파라미터 핸들러. 시그널 선언과 일치 확인.

### ~~TD-AUDIT-03. chart_renderer.gd Timer dangling~~ — **해결됨 (2026-04-21 감사 확인)**

- `tree_exiting` + `_disconnect_signals()`에서 타이머 cleanup 완료.

### ✅ 해결됨 (2026-04-09)

- ~~`season_active` 다중 소스 (CurrencySystem + SeasonManager + GameClock 각자 관리)~~ → `GameClock._season_active` 단일 소스. `CurrencySystem._season_active` 제거. `SeasonManager.is_season_active()` → `GameClock.is_season_active()` 위임. `GameClock.get_save_data()` / `load_save_data()` 에 `season_active` + `market_state` 포함. `SaveSystem` 로드 순서 GameClock 우선으로 재정렬. 구버전 세이브 하위 호환 처리.
- ~~`PriceEngine` UI 생성 전 가격 미초기화 (₩0 플래시)~~ → `init_first_season()` 신규 메서드: `game_main.gd`에서 MainScreen 생성 전 호출. `_reset_season_mechanics()`: 시즌 전환 시 `current_price` / `prev_day_close` 유지, Markov/bias/히스토리만 리셋.
- ~~`SeasonManager.start_season()` 시그널 순서 버그 (리그 화면 미전환)~~ → `GameClock.start_season()` 먼저 호출 후 `on_season_started.emit()`. Godot 시그널 동기 호출 특성상 emit 시점에 `is_season_active()` == true 보장 필요.

---

## 디자인 리뷰 2026-04-15 식별 항목

### ~~TD-DR-01. trading-screen.md 미완 구현 5개~~ — **해결됨 (2026-04-21 감사 확인)**

- MainScreen [나가기] 버튼: `main_screen.gd:198-220` `_build_f4_exit_button()` 확인
- MainScreen F4 감지: `_unhandled_input()` lines 80-81 확인
- StockListPanel._row_nodes 1회 빌드: `_build_rows()` 확인
- StockListPanel._last_prices dirty flag: `_on_price_updated()` lines 102-103 확인
- _sel_style/_desel_style: `_sel_style` 캐시 확인. `_desel_style`는 `remove_theme_stylebox_override` 방식(테마 상속)으로 처리 — 주석 일치화 완료

### ~~TD-DR-02. price-engine.md AC 35개 미검증~~ — **폴리시 스프린트로 이월**

- PriceEngine 구현 완료. AC 검증은 Polish QA 단계에서 일괄 처리.

### ~~TD-DR-03. skill_tree_overlay.gd orphan 파일~~ — **해결됨 (2026-04-15)**

**결과**: `src/deprecated/skill_tree_overlay.gd`로 이동. 코드/씬에서 미참조 확인됨.

---

## 디자인 리뷰 2026-04-21 식별 항목 (전체 GDD 전수 감사)

### TD-DR-04. S3 루머 채널 — PriceEngine 가격 선반영 미구현

**출처**: 2026-04-21 전체 GDD 전수 감사  
**우선순위**: Medium (루머가 뉴스 피드에는 표시되지만 가격에 영향 없음)  
**목표 스프린트**: Sprint 11 (Polish)  
**관련 GDD**: rumor-channel.md §9 가격 선반영 구현, price-engine.md §9

- `PriceEngine._rumor_pressure: Dictionary` 상태 미추가
- `PriceEngine._on_rumor_hint(rumor: Dictionary)` 핸들러 미구현
- `process_tick()` Step 4-c rumor_delta 계산 누락
- Step 5 공식 갱신 (`total_delta = pattern + drift + event + player + rumor`) 누락
- F5 거래량 공식 `tick_energy`에 `|rumor_delta|` 미포함
- 장 마감 시 `_rumor_pressure` 정리 누락
- `price_engine_config.json` 미생성 (`RUMOR_PRESSURE_STRENGTH: 0.0005`)
- `PriceEngine.reset()` 시 `_rumor_pressure.clear()` 미포함

### TD-DR-05. DLC 시장 필터링 인프라 — NewsEventSystem 미구현

**출처**: 2026-04-21 전체 GDD 전수 감사  
**우선순위**: Low (한국 시장 단일 서비스 시 무관, DLC 시 필수)  
**목표 스프린트**: DLC 그린라이트 후  
**관련 GDD**: news-events.md §9 DLC 확장성 섹션

- `event_pool.json`에 `"market_id"` 필드 미추가
- `NewsEventSystem` 이벤트 선택 시 `active_market_id` 필터링 로직 미구현
- `event_pool_us.json`, `event_pool_jp.json` 스텁 파일 미생성
- 테스트 `test_event_pool_filtered_by_market_id()` 미추가

### TD-DR-06. ShortSelling 대차 풀(Borrow Pool) 시스템 미구현

**출처**: 2026-04-21 전체 GDD 전수 감사  
**우선순위**: Medium (현재 무제한 차입 가능 — 밸런스 영향)  
**목표 스프린트**: Sprint 11 (Polish)  
**관련 GDD**: short-selling.md §9 진입점/호출 경로

- `short_selling_config.json`에 `borrowableRatioByVolatility` 미추가
- `ShortSellingSystem._borrow_pool: Dictionary` 상태 변수 미추가
- `ShortSellingSystem._init_pools()` 메서드 미구현
- `ShortSellingSystem.get_borrow_pool(stock_id) -> Dictionary` 공개 API 미구현
- `OrderEngine` SELL_SHORT 검증 4-S5 단계 (pool 잔량 체크) 미추가
- `GameClock.on_season_start` → `_init_pools()` 연결 누락

### TD-DR-07. StockDatabase DLC 동적 로드 미구현

**출처**: 2026-04-21 전체 GDD 전수 감사  
**우선순위**: Low (한국 시장 단일 서비스 시 무관, DLC 시 필수)  
**목표 스프린트**: DLC 그린라이트 후  
**관련 GDD**: stock-database.md §9 DLC 확장성 섹션

- `stock_database.gd`가 `stocks.json` 하드코딩 경로 사용 (`stocks_kr.json` 미전환)
- `StockData._ready()` 동적 경로 로드 (`"stocks_%s.json" % active_market_id`) 미구현
- `stocks_us.json`, `stocks_jp.json` 스텁 파일 미생성
- 기존 `stocks.json` 참조 교체 미완료

### TD-DR-08. GameClock 거래 시간 MarketProfile 동적 로드 미구현

**출처**: 2026-04-21 전체 GDD 전수 감사  
**우선순위**: Low (한국 시장 단일 서비스 시 무관, DLC 시 필수)  
**목표 스프린트**: DLC 그린라이트 후  
**관련 GDD**: game-clock.md §9 DLC 확장성 섹션

- `MINUTES_PER_DAY = 390` 상수 → `MarketProfile.get_calendar_param("trading_minutes")` 동적 로드로 교체 필요
- `TICKS_PER_DAY` 등 파생 상수 연쇄 갱신 구조 필요
- `market_kr.json`에 `"trading_minutes": 390` 미등록
- `GameClock._ready()` → `MarketProfile` 로드 연결 필요
- 테스트 `test_trading_minutes_loaded_from_market_profile()` 미추가

### TD-DR-09. AiCompetitor 수익률 분포 MarketProfile 미전환

**출처**: 2026-04-21 전체 GDD 전수 감사  
**우선순위**: Low (한국 시장 단일 서비스 시 무관, DLC 시 필수)  
**목표 스프린트**: DLC 그린라이트 후  
**관련 GDD**: ai-competitor.md §9 DLC 확장성 섹션

- 티어별 수익률 정규분포 파라미터 (`mean`, `std_dev`)가 코드 내 하드코딩
- `market_kr.json`에 `"ai_return_distribution": {...}` 미등록
- `AiCompetitor.init_season()` MarketProfile 파라미터 수신 경로 미설계

### TD-DR-10. 52주 신고가/저가 오더북 행 미구현

**출처**: 2026-04-21 전체 GDD 전수 감사  
**우선순위**: Low  
**목표 스프린트**: Polish (Sprint 11 이후)  
**관련 GDD**: order-book.md §9 블록 6 (52주 행)

- `StockData.week52_high/low` 필드 미추가 (`stocks.json` 미등록)
- `OrderPanel` 블록 6 52주 행 UI 미구현
- `order_panel.gd:258` 주석: `"생략: StockData.week52_high/low 미구현"`

---

## 코드 리뷰 2026-04-15 식별 항목 (전체 37개 파일)

### ~~TD-CR-03. SaveSystem.active_slot_id public 직접 쓰기 가능~~ — **해결됨 (2026-04-21 감사 확인)**

- `_active_slot_id` private var + `get_active_slot_id()` 게터 완료.

### ~~TD-CR-04. SettlementReporter._weekly_xp_gained 세이브/로드 간 소실~~ — **해결됨 (2026-04-15)**

XpSystem._weekly_xp 필드 추가 + get_weekly_xp()/reset_weekly_xp() API. SettlementReporter는 자체 카운터 제거 후 XpSystem.get_weekly_xp() 읽기. 세이브/로드 직렬화는 XpSystem.get_save_data()에서 처리.

### ~~TD-CR-05. 단위 테스트 미작성 시스템 (P1)~~ — **해결됨 (2026-04-20, S10-08)**

- `tests/unit/test_core_systems.gd` 신규 작성: StockDatabase, FormatUtils, CurrencySystem, PortfolioManager, NewsEventSystem 전부 커버.

### TD-CR-06. portfolio_view.gd _on_stop_take_btn_pressed() 138줄

**출처**: 2026-04-15 전체 코드 리뷰  
**우선순위**: Medium  
**목표 스프린트**: Sprint 9  
`_on_stop_take_btn_pressed()`가 138줄(40줄 한도 초과). `_build_stop_take_dialog()` 분리 및 Stop/Take 다이얼로그 내 플레이어 노출 문자열에 `tr()` 추가.

### TD-CR-07. level_up_banner.gd _ready() 146줄

**출처**: 2026-04-15 전체 코드 리뷰  
**우선순위**: Low  
**목표 스프린트**: Sprint 9  
`_ready()` 146줄. `_build_flash_overlay()`, `_build_banner_panel()`, `_build_buttons()` 등으로 분리 필요.

### TD-CR-08. tr() 미포장 문자열 잔여 (portfolio_view 다이얼로그, splash/start 브랜드명)

**출처**: 2026-04-15 전체 코드 리뷰  
**우선순위**: Low (로컬라이제이션 단계 전 충분)  
**목표 스프린트**: Sprint 9 (Polish)  
- `portfolio_view.gd` Stop/Take 다이얼로그 내 16개 문자열
- `splash_screen.gd:83,90` `"SEED"`, `"M O N E Y"` (브랜드명 — 번역 제외 가능하나 주석 명시 필요)
- `start_screen.gd:56` `"SEED MONEY"` (동일)

### TD-CR-09. ThemeSetup 색상 상수 미사용 (inline Color 리터럴)

**출처**: 2026-04-15 전체 코드 리뷰  
**우선순위**: Low  
**목표 스프린트**: Sprint 9  
`start_screen.gd` 7개, `main_screen.gd` 일부 Color 리터럴이 ThemeSetup 상수 대신 직접 값으로 정의됨. 테마 일괄 변경 시 누락 위험.

### TD-CR-10. game_clock.gd AUTO_SLOW_ON_EVENT 미사용 상수

**출처**: 2026-04-15 전체 코드 리뷰  
**우선순위**: Low  
**목표 스프린트**: Beta 설정 UI 구현 시  
`AUTO_SLOW_ON_EVENT` 상수가 선언되어 있으나 어디서도 읽히지 않음. 설정 UI 미구현 상태. 구현 또는 제거 결정 필요.

### TD-CR-11. UIState enum 중복 (StatusBar vs TradingScreen)

**출처**: 2026-04-15 전체 코드 리뷰  
**우선순위**: Medium  
**목표 스프린트**: Sprint 9  
`StatusBar.UIState`와 `TradingScreen.UIState`가 동일 값을 별도 정의. 동기화 위험 내재. 공유 `ui_state_types.gd` 파일로 enum 분리하거나 StatusBar가 int 파라미터로 수신하는 방식으로 통일.

### TD-CR-12. private 메서드 doc comment 전체 미작성

**출처**: 2026-04-15 전체 코드 리뷰  
**우선순위**: Low (public API 규칙은 준수 중)  
**목표 스프린트**: Sprint 9 (일괄 처리)  
`src/ui/*.gd` 전 파일의 복잡한 private 빌드 메서드(`_build_ui`, `_refresh_*`, `_show_*` 등)에 ## 주석 없음. 팀 가독성 개선을 위해 일괄 추가 권고.

---

## 전체 코드 리뷰 2026-04-21 식별 항목 (52개 파일 전수)

> 즉시 수정 완료: trading_screen.gd(SKILL_TR1 상수화, TAB_ALERTS 상수 사용), order_engine.gd(ERR_BALANCE/ERR_QUANTITY 상수화), profit_celebration/sector_comparison_view(\_fmt\_int\_comma → FormatUtils.number), league_screen.gd(\_fmt\_pct/\_fmt\_comma → FormatUtils)

### TD-CR-13. financial_report_system.gd 뉴스 헤드라인 문자열 중복

**출처**: 2026-04-21 전체 코드 리뷰 — financial_report_system.gd:427, 430, 444, 447, 462, 465, 516, 519, 522, 525  
**우선순위**: Low  
**목표 스프린트**: Polish  
이벤트 타입별 뉴스 헤드라인 문자열이 함수 내 11곳에 인라인 하드코딩. `event_pool.json` 로드 또는 상단 Dictionary 상수로 단일화 권장.

### TD-CR-14. news_event_system.gd impact_hint 형식 혼용

**출처**: 2026-04-21 전체 코드 리뷰 — news_event_system.gd:443, 420, 1115, 1260, 1279, 1306  
**우선순위**: Low  
**목표 스프린트**: Polish  
`impact_hint` 필드값이 `"positive"/"negative"` 문자열과 `"ℹ️"/"⚠️"/"🚨"` 이모지 혼용. 단일 형식(문자열 상수)으로 통일하고 UI 렌더러에서 이모지 매핑.

### TD-CR-15. intro_sequence.gd 게임 수치 리터럴 하드코딩

**출처**: 2026-04-21 전체 코드 리뷰 — intro_sequence.gd:19-22  
**우선순위**: Low  
**목표 스프린트**: Polish  
도입 카드 텍스트의 `"10,000원"`, `"1,000,000원에서 1,000억까지"` 등이 GDD 상수 미참조 리터럴. 상수 변경 시 텍스트가 자동으로 틀려짐. CurrencySystem 또는 GameBalance 상수에서 참조로 교체.

### TD-CR-16. stop_take_system.gd Variant 반환 타입 명시화

**출처**: 2026-04-21 전체 코드 리뷰 — stop_take_system.gd:74-75, 106  
**우선순위**: Low  
**목표 스프린트**: Polish  
`get_setting() -> Variant` 반환 타입이 실제로 `Dictionary | null`임. Variant 사용으로 호출자가 타입 추론 불가. `-> Variant` → `-> Dictionary` + null 반환 조건 명시, 매개변수도 `Variant` 주석 대신 타입별 분리 오버로드 검토.

### TD-CR-17. lifestyle_manager.gd 기본값 누락 + season_final 판별 하드코딩

**출처**: 2026-04-21 전체 코드 리뷰 — lifestyle_manager.gd:166, 305-306, 342-344  
**우선순위**: Low  
**목표 스프린트**: Polish  
(1) `_load_config()`에서 `donationMin/Max` 로드 실패 시 기본값 세팅 없음 — config 파일 누락 시 `DONATION_MIN = 0` 위험.  
(2) `is_season_final_day` 판별 로직이 `GameClock` 상수 직접 계산 — `GameClock.is_season_final_day()` 헬퍼로 캡슐화 권장.

### TD-HIST-01. OHLCV 시즌 간 영구 히스토리 저장 구조

**출처**: 팀 전체 토론 2026-04-15  
**우선순위**: Medium  
**목표 스프린트**: Sprint 9 (Should Have, S9-07)

**확정 설계** (2026-04-17):

**Pre-generated history** (슬롯 생성 시 1회):
- 슬롯 생성 시 `history_seed` 저장
- `PriceEngine.generate_pre_history(seed, stock_id, length)` — 단순 랜덤워크, 100~300시즌 랜덤 길이 (seed에서 결정)
- 저장 없음 — 조회 시마다 seed로 재생성 (항상 동일 결과)

**실제 플레이 시즌** (시즌 완료 시 적립):
- 1분봉 OHLCV 저장 (TICKS_PER_MINUTE=4 → 390바/일 × 20일 × 46종목)
- gzip 압축 후 세이브 파일 내 포함 (ADR-009 호환)
- 압축 후 ~1~1.5MB/시즌. 10시즌 ~10~15MB — Steam 기준 허용 범위
- 웹 데모는 1시즌 제한이므로 누적 없음

**파생 타임프레임** (집계 API):
- `get_candles(stock_id, timeframe)` 단일 진입점
- 1분봉 원본 → 5분(×5) / 15분(×15) / 일봉(×390) / 주봉(5거래일) / 월봉(20거래일=1시즌) 집계
- 진행 중 캔들: 완성된 바 + 현재 진행 중 1개 (매틱 갱신, `current_price` 반영)

**선행 확인 사항** (구현 전 필수):
1. pre-generated history 단순 랜덤워크 → 실제 플레이 가격과 시각적으로 이어지는지 확인
2. 장기 가격 드리프트 방지 정규화 설계

### TD-QA-01. 스킬 검증용 슈퍼 계정 세이브 파일

**출처**: QA 플레이테스트 계획 2026-04-15  
**우선순위**: Medium  
**목표 스프린트**: Beta QA 단계 (Sprint 9 이후)  
스킬 효과 검증을 위한 미리 구성된 세이브 픽스처 파일 필요.

**구현 방법**: 디버그 세이브 슬롯 (Option A)  
- `tests/fixtures/superaccount.json` 생성  
  - 모든 스킬 해금 (A1~A4, S1~S4, TR1~TR4, P1~P3)  
  - Lv.MAX, XP 충분  
  - 현금 ₩100억  
  - 시즌 3+ 진행 기록  
- 로드 방법: `SaveSystem.load_raw("tests/fixtures/superaccount.json")` 또는 슬롯 0에 복사 후 게임 실행  
- 프로덕션 코드 변경 없음 — 세이브 파일만 추가  
- 검증 대상: TR2(손절/익절), TR3(공매도), TR4(레버리지), P1/P2/P3(종목 슬롯), A1~A4(분석 도구), S1~S4(시장 감지)
