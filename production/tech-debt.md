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

### ~~TD-DR-04. S3 루머 채널 — PriceEngine 가격 선반영 미구현~~ — **해결됨 (2026-04-21)**

`PriceEngine._rumor_pressure` dict, `_on_rumor_hint()` 핸들러, Step 4-c rumor_delta, F5 tick_energy 포함, 장 마감 정리, `price_engine_config.json` 생성, `reset()` clear 전부 구현.
`NewsEventSystem.on_rumor_hint` → `PriceEngine._on_rumor_hint` ADR-022 파이프라인 준수.

### ~~TD-DR-05. DLC 시장 필터링 인프라 — NewsEventSystem 미구현~~ — **해결됨 (2026-04-21)**

`event_pool.json` 전 템플릿에 `"market_id": "KR"` 추가 (v2.1). `NewsEventSystem._active_market_id`, `set_active_market()`, `_load_event_pool()` 필터링 구현. `stocks_us.json`, `stocks_jp.json` 스텁 생성.

### ~~TD-DR-06. ShortSelling 대차 풀(Borrow Pool) 시스템 미구현~~ — **해결됨 (2026-04-21)**

`short_selling_config.json` `borrowableRatioByVolatility`, `_borrow_pool` dict, `_init_pools()`, `get_borrow_pool()`, `_restore_borrow_pool()`, `open_position()`/`close_position()` 풀 차감/복원, `OrderEngine` 4-S5 검증, SaveSystem 직렬화 전부 구현.

### ~~TD-DR-07. StockDatabase DLC 동적 로드 미구현~~ — **해결됨 (2026-04-21)**

`stocks.json` → `stocks_kr.json` 이전. `STOCK_DATA_PATH_TEMPLATE`, `_active_market_id`, `set_active_market()`, `_load_stocks_from_json()` 동적 경로 로드. `stocks_us.json`, `stocks_jp.json` 스텁 생성.

### ~~TD-DR-08. GameClock 거래 시간 MarketProfile 동적 로드 미구현~~ — **해결됨 (2026-04-21)**

`_effective_minutes_per_day`, `_effective_ticks_per_day` 런타임 변수 추가. `configure_trading_hours()` 및 `get_effective_ticks_per_day()` API. `get_day_progress()`, `_process_tick()` 에서 `_effective_ticks_per_day` 참조. KR 상수 기본값 유지.

### ~~TD-DR-09. AiCompetitor 수익률 분포 MarketProfile 미전환~~ — **해결됨 (2026-04-21)**

`_mu_multiplier`, `_sigma_multiplier` 상태 변수. `configure_market_distribution(mu_mult, sigma_mult)` API. `_generate_target_returns()`에서 mu×배율, `_compute_eod_for()`에서 sigma_daily×배율 적용. KR 기본값 1.0 유지.

### ~~TD-DR-10. 52주 신고가/저가 오더북 행 미구현~~ — **해결됨 (2026-04-21)**

`order_panel.gd` `_lbl_week52_high`/`_lbl_week52_low` Labels + `_build_ob_week52_block()` UI 구현. `OhlcvHistory.get_week52_high_low()` 호출. `StockData.week52_high/low` 런타임 계산 방식 채택.

---

## 코드 리뷰 2026-04-15 식별 항목 (전체 37개 파일)

### ~~TD-CR-03. SaveSystem.active_slot_id public 직접 쓰기 가능~~ — **해결됨 (2026-04-21 감사 확인)**

- `_active_slot_id` private var + `get_active_slot_id()` 게터 완료.

### ~~TD-CR-04. SettlementReporter._weekly_xp_gained 세이브/로드 간 소실~~ — **해결됨 (2026-04-15)**

XpSystem._weekly_xp 필드 추가 + get_weekly_xp()/reset_weekly_xp() API. SettlementReporter는 자체 카운터 제거 후 XpSystem.get_weekly_xp() 읽기. 세이브/로드 직렬화는 XpSystem.get_save_data()에서 처리.

### ~~TD-CR-05. 단위 테스트 미작성 시스템 (P1)~~ — **해결됨 (2026-04-20, S10-08)**

- `tests/unit/test_core_systems.gd` 신규 작성: StockDatabase, FormatUtils, CurrencySystem, PortfolioManager, NewsEventSystem 전부 커버.

### ~~TD-CR-06. portfolio_view.gd _on_stop_take_btn_pressed() 138줄~~ — **해결됨 (감사 확인 2026-04-21)**

`_on_stop_take_btn_pressed()` 메서드가 현재 코드베이스에 없음. 이미 `_build_stop_take_dialog()` 등으로 분리 완료 확인.

### ~~TD-CR-07. level_up_banner.gd _ready() 146줄~~ — **해결됨 (감사 확인 2026-04-21)**

`_ready()`가 이미 `_build_flash_overlay()`, `_build_dim_overlay()`, `_build_banner_panel()`, `_build_banner_top_row()`, `_build_banner_bottom_row()` 등으로 분리 완료.

### ~~TD-CR-08. tr() 미포장 문자열 잔여 (splash/start 브랜드명)~~ — **해결됨 (2026-04-21)**

`splash_screen.gd` "SEED", "M O N E Y", `start_screen.gd` "SEED MONEY"에 `## intentionally NOT wrapped in tr() — brand name` 주석 추가.

### ~~TD-CR-09. ThemeSetup 색상 상수 미사용 (inline Color 리터럴)~~ — **해결됨 (2026-04-21)**

`ThemeSetup`에 `START_BG`~`START_PORTFOLIO_VALUE` 8개 상수 추가. `start_screen.gd` inline Color 7개 전부 ThemeSetup 참조로 교체.

### ~~TD-CR-10. game_clock.gd AUTO_SLOW_ON_EVENT 미사용 상수~~ — **해결됨 (감사 확인 2026-04-21)**

`_auto_slow_on_event: bool` 변수 + `get/set_auto_slow_on_event()` API로 전환 완료. `SettingsScreen`에서 읽고 씀.

### ~~TD-CR-11. UIState enum 중복 (StatusBar vs TradingScreen)~~ — **해결됨 (감사 확인 2026-04-21)**

`status_bar.gd`, `trading_screen.gd` 모두 `const UIState = UIStateTypes.UIState` 앨리어스 사용 중. `ui_state_types.gd` 단일 소스 확인.

### TD-CR-12. private 메서드 doc comment 전체 미작성

**출처**: 2026-04-15 전체 코드 리뷰  
**우선순위**: Low (public API 규칙은 준수 중)  
**목표 스프린트**: Sprint 9 (일괄 처리)  
`src/ui/*.gd` 전 파일의 복잡한 private 빌드 메서드(`_build_ui`, `_refresh_*`, `_show_*` 등)에 ## 주석 없음. 팀 가독성 개선을 위해 일괄 추가 권고.

---

## 전체 코드 리뷰 2026-04-21 식별 항목 (52개 파일 전수)

> 즉시 수정 완료: trading_screen.gd(SKILL_TR1 상수화, TAB_ALERTS 상수 사용), order_engine.gd(ERR_BALANCE/ERR_QUANTITY 상수화), profit_celebration/sector_comparison_view(\_fmt\_int\_comma → FormatUtils.number), league_screen.gd(\_fmt\_pct/\_fmt\_comma → FormatUtils)

### ~~TD-CR-13. financial_report_system.gd 뉴스 헤드라인 문자열 중복~~ — **해결됨 (2026-04-21)**

10개 헤드라인 템플릿 상수(`_HL_*`) 추가. `_fire_analyst_report()`, `_fire_preliminary_news()`, `_fire_rumor()`, `_publish_earnings_news()` 내 인라인 리터럴 전부 상수 참조로 교체.

### ~~TD-CR-14. news_event_system.gd impact_hint 형식 혼용~~ — **해결됨 (2026-04-21)**

`IMPACT_HINT_WARNING`, `IMPACT_HINT_INFO`, `IMPACT_HINT_EMERGENCY`, `IMPACT_HINT_POSITIVE`, `IMPACT_HINT_NEGATIVE` 등 상수 추가. VI trigger/release/CB 핸들러 이모지 리터럴 전부 상수로 교체.

### ~~TD-CR-15. intro_sequence.gd 게임 수치 리터럴 하드코딩~~ — **해결됨 (2026-04-21)**

`CARD_TEXTS const` → `static func _build_card_texts()` 전환. `FormatUtils.currency(CurrencySystem.INITIAL_CASH_ASSETS)`, `SeasonManager.HANGANG_THRESHOLD`, `SeasonManager.ENDING_THRESHOLD` 직접 참조.

### ~~TD-CR-16. stop_take_system.gd Variant 반환 타입 명시화~~ — **해결됨 (2026-04-21)**

`get_setting() -> Dictionary`로 변경. null 대신 `{}` 반환. `order_panel.gd` 호출자 `if cur != null` → `if not cur.is_empty()` 수정.

### ~~TD-CR-17. lifestyle_manager.gd 기본값 누락 + season_final 판별 하드코딩~~ — **해결됨 (2026-04-21)**

`DONATION_MIN/MAX` 중복 선언 제거. `GameClock.is_season_final_day()` 헬퍼 추가 및 `process_market_close()` 위임.

### ~~TD-HIST-01. OHLCV 시즌 간 영구 히스토리 저장 구조~~ — **해결됨 (감사 확인 2026-04-21)**

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

### ~~TD-QA-01. 스킬 검증용 슈퍼 계정 세이브 파일~~ — **해결됨 (2026-04-21)**

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
