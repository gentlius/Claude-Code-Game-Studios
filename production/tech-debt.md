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

### ✅ TD-CR-01. ai_competitor.gd EOD 재계산 O(day) — **해결됨 (2026-04-14)**

- `_compute_eod_for`에 `eod_rng_states: Array[int]` 캐시 도입. 전일 EOD RNG 상태를 저장해
  다음 호출 시 O(1) 한 스텝만 진행. Day 0 또는 캐시 미존재 시만 O(day) 재계산.

### TD-CR-02. 게임패드 홀딩 목록 탐색 불가

- **현황**: `portfolio_view.gd` 홀딩 목록 행(`HBoxContainer`)이 `MOUSE_FILTER_STOP`만 설정.
  `focus_mode` 미설정으로 키보드/게임패드 탐색 불가. ADR ui-code.md 규칙("키보드/마우스 AND 게임패드") 위반.
- **영향**: 포트폴리오 뷰에서 종목 클릭 → 차트 전환 기능을 게임패드로 사용 불가.
- **우선순위**: Low (현재 마우스 중심 UI이지만 접근성 규칙 위반)
- **목표 스프린트**: Sprint 9 (Polish 단계)
- **제안 수정**: 각 홀딩 행에 `focus_mode = Control.FOCUS_ALL` + `focus_neighbor_*` 설정.
  방향키로 행 이동, Enter로 `stock_clicked` 발행.

## 잔여 오픈 항목

### TD-AUDIT-01. settlement_reporter.gd 레이스 컨디션

- **현황**: 팝업 닫힘 중 타이머가 발화할 경우 다음 시즌 공개 순서 혼란 가능성.
- **우선순위**: Medium
- **목표 스프린트**: Sprint 6 S6-04

### TD-AUDIT-02. xp_bar.gd C-01 시그니처 불일치

- **현황**: `_on_xp_gained` 핸들러가 2파라미터이나 시그널이 3파라미터 emit 가능성.
- **우선순위**: Critical → Sprint 6 S6-04에서 검증 및 수정.
- **목표 스프린트**: Sprint 6 S6-04

### TD-AUDIT-03. chart_renderer.gd Timer dangling

- **현황**: 80ms 디바운스 타이머가 씬 제거 시 dangling 가능성.
- **우선순위**: Low
- **목표 스프린트**: Sprint 6 S6-03 (RSI/MACD 작업과 병행)

> **참고**: chart_renderer.gd의 RSI/MACD 구현 자체는 완료 상태 (`_draw_rsi()`, `_draw_macd()`, `_rsi_cache` 전부 존재). S6-03은 Timer dangling 수정만 진행.

### ✅ 해결됨 (2026-04-09)

- ~~`season_active` 다중 소스 (CurrencySystem + SeasonManager + GameClock 각자 관리)~~ → `GameClock._season_active` 단일 소스. `CurrencySystem._season_active` 제거. `SeasonManager.is_season_active()` → `GameClock.is_season_active()` 위임. `GameClock.get_save_data()` / `load_save_data()` 에 `season_active` + `market_state` 포함. `SaveSystem` 로드 순서 GameClock 우선으로 재정렬. 구버전 세이브 하위 호환 처리.
- ~~`PriceEngine` UI 생성 전 가격 미초기화 (₩0 플래시)~~ → `init_first_season()` 신규 메서드: `game_main.gd`에서 MainScreen 생성 전 호출. `_reset_season_mechanics()`: 시즌 전환 시 `current_price` / `prev_day_close` 유지, Markov/bias/히스토리만 리셋.
- ~~`SeasonManager.start_season()` 시그널 순서 버그 (리그 화면 미전환)~~ → `GameClock.start_season()` 먼저 호출 후 `on_season_started.emit()`. Godot 시그널 동기 호출 특성상 emit 시점에 `is_season_active()` == true 보장 필요.

---

## 디자인 리뷰 2026-04-15 식별 항목

### TD-DR-01. trading-screen.md 미완 구현 5개 (Sprint 8 예정)

**출처**: 2026-04-15 전체 GDD 디자인 리뷰  
**우선순위**: Medium  
**목표 스프린트**: Sprint 8

미완 항목:
- `MainScreen` 탭바에 `[나가기]` 버튼 추가 (F1/F2/F3 우측)
- `MainScreen._input(event)`: F4 감지 → `SavingOverlay.visible` 체크 → StartScreen 전환
- `StockListPanel._row_nodes` — `_ready()`에서 1회 빌드, `get_children()` 런타임 호출 없음
- `StockListPanel._last_prices` — dirty flag skip 동작
- `StockListPanel._sel_style` / `_desel_style` — `_ready()` 1회 캐시, 런타임 `StyleBoxFlat.new()` 없음

### TD-DR-02. price-engine.md AC 35개 미검증

**출처**: 2026-04-15 전체 GDD 디자인 리뷰  
**우선순위**: Low  
**목표 스프린트**: Sprint 8 (오더북 구현과 병행)

price-engine.md Acceptance Criteria 35개가 모두 `[ ]` 상태.  
PriceEngine은 구현 완료됐으나 AC 항목별 검증이 공식 기록에 없음.  
Sprint 8에서 QA Lead가 AC 체크리스트 기반 검증 실행 후 갱신.

### TD-DR-03. skill_tree_overlay.gd orphan 파일

**출처**: 2026-04-15 전체 GDD 디자인 리뷰  
**우선순위**: Low → 처리 완료 2026-04-15  
**결과**: `src/deprecated/skill_tree_overlay.gd`로 이동. 코드/씬에서 미참조 확인됨.

---

## 코드 리뷰 2026-04-15 식별 항목 (전체 37개 파일)

### TD-CR-03. SaveSystem.active_slot_id public 직접 쓰기 가능

**출처**: 2026-04-15 전체 코드 리뷰  
**우선순위**: Medium  
**목표 스프린트**: Sprint 9  
`active_slot_id`가 public var로 외부에서 직접 쓰기 가능. `get_active_slot_id()` 게터 추가 후 private으로 전환. 테스트 파일(6개) `before_each` 패턴도 함께 수정.

### TD-CR-04. SettlementReporter._weekly_xp_gained 세이브/로드 간 소실

**출처**: 2026-04-15 전체 코드 리뷰  
**우선순위**: Low  
**목표 스프린트**: Sprint 9 → **✅ 2026-04-15 해결**  
XpSystem._weekly_xp 필드 추가 + get_weekly_xp()/reset_weekly_xp() API. SettlementReporter는 자체 카운터 제거 후 XpSystem.get_weekly_xp() 읽기. 세이브/로드 직렬화는 XpSystem.get_save_data()에서 처리.

### TD-CR-05. 단위 테스트 미작성 시스템 (P1)

**출처**: 2026-04-15 전체 코드 리뷰  
**우선순위**: High  
**목표 스프린트**: Sprint 8  
다음 시스템에 전용 단위 테스트 파일 없음:
- `StockDatabase`: `get_stock()`, `get_stocks_by_sector()`, `stock_exists()` 등 미검증
- `FormatUtils`: 경계값(0, <1000, 음수, 매우 큰 수) 및 `pct()` 부호 로직 미검증
- `CurrencySystem`: `sim_deduct()` 언더플로우, `award_prize()` 음수 가드 미검증
- `PortfolioManager`: FIFO 평균 단가, 실현 손익, `update_valuation()` 공식 미검증
- `NewsEventSystem`: 일별 스케줄 생성, 야간 이벤트, 지연 큐, 가중치 랜덤 픽 미검증

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

### TD-HIST-01. OHLCV 시즌 간 영구 히스토리 저장 구조

**출처**: 팀 전체 토론 2026-04-15  
**우선순위**: Medium  
**목표 스프린트**: 주봉/월봉 차트 구현 스프린트(Sprint 9~10) 선행 조건  

**배경**: 현재 `ohlcv_daily`는 시즌 시작 시 초기화됨. 다회차 플레이 시 주봉/월봉 차트를 의미있게 만들려면 시즌 간 일봉 데이터 누적이 필요.

**팀 컨센서스**:
- 세이브 파일 내 포함 (별도 파일은 ADR-009 멀티슬롯과 충돌)
- 용량: 46종목 × 20일 × 5값 ≈ 200KB/시즌. 10시즌 ~2MB — 무시 가능
- `season_id` 필드로 시즌 경계 구분 필요

**선행 확인 사항** (구현 전 필수):
1. PriceEngine 20시즌 시뮬레이션 → 주봉/월봉이 "읽힐 만한" 패턴인지 눈으로 검증
2. 장기 가격 드리프트 방지 정규화 설계

**구현 방법은 별도 논의 예정.**

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
