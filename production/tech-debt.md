# Technical Debt Register

> 코드 리뷰 (2026-04-03)에서 식별된 아키텍처 이슈. 우선순위별 정리.

## V-Slice 전 (필수)

### ~~TD-01. 틱 처리 순서 보장~~ — **해결됨 (2026-04-04)**

- ~~현황~~: `game_clock.gd._process_tick()`에서 `NewsEventSystem._on_tick()` → `PriceEngine._on_tick()` → `OrderEngine._on_tick()`을 명시적으로 순차 호출 후 `on_tick.emit()`으로 나머지 구독자에 브로드캐스트하는 방식으로 이미 구현되어 있음.
- S2-03 구현 검토 중 기확인. S2-05로 별도 작업 불필요.

### ~~TD-02. 테스트 격리용 `reset_for_testing()` 메서드~~ — **해결됨 (2026-04-04)**

- 전체 10개 autoload 시스템에 `reset_for_testing()` 추가 완료
  - 기존 보유: `CurrencySystem`, `OrderEngine`, `SkillTree`, `PriceEngine`, `NewsEventSystem`
  - 신규 추가: `GameClock`, `PortfolioManager`, `XpSystem`, `AiCompetitor`, `SeasonManager`
- `tests/unit/test_api_contracts.gd`에 `test_all_systems_have_reset_for_testing()` 계약 테스트 추가
- `StockDatabase`는 런타임 변경 불가(JSON 로드 전용)이므로 reset 불필요

### ~~TD-08. SeasonManager.start_season() 호출 경로 없음~~ — **해결됨 (2026-04-04, S3-01)**

- `SeasonManager.start_season()` → 내부에서 `GameClock.start_season()` 호출 (순서 보장)
- `game_main.gd` → init + cache prime + 화면 로드만. season/clock 직접 호출 제거
- `TradingScreen` PRE_MARKET → `is_season_active()` 체크로 "시즌 시작" / "장 시작" 분기
- `GameClock.confirm_transition(SEASON_END)` → `on_new_season_requested` 시그널 emit (Foundation→Gameplay 의존성 역전 방지)
- `SeasonManager._ready()` → `on_new_season_requested.connect` 처리
- `SeasonManager.is_season_active()` 신규 API 추가
- 계약 테스트 갱신 완료

---

## Production 진입 시

### ~~TD-03. UI 직접 상태 변경 완화~~ — **해결됨 (2026-04-04, S3-13)**

- `SkillTreeOverlay.pause_toggle_requested` 시그널 추가. `GameClock.toggle_pause()` 직접 호출 → 시그널 emit으로 전환
- `TradingScreen.pause_toggle_requested` + `speed_change_requested(multiplier)` 시그널 추가
- `TradingScreen._set_speed()` / `_handle_pause_toggle()` → 시그널 emit으로 전환
- `SkillTreeOverlay.pause_toggle_requested` → TradingScreen 내부에서 relay
- `MainScreen._build_ui()` 에서 두 시그널 → `GameClock.toggle_pause()` / `GameClock.set_speed()` 연결
- `confirm_transition`, `confirm_market_open`은 반환값 의존 없으나 UI 흐름 직결 — 직접 호출 유지 (아키텍처 팀 합의)

### TD-04. trading_screen.gd God Object 분리

- **현황**: 1930줄, 8개 책임 혼재 (종목 리스트, 주문 패널, 정산 리포트, 토스트, 알림, 스킬 반응, XP, 속도 제어). 40줄 메서드 제한 다수 위반
- **해결안**: 5~6개 서브컴포넌트로 분리 — StockListPanel, OrderPanel, SettlementReporter, ToastManager, SpeedControls, StatusBar
- **작업량**: 대
- **관련 파일**: `src/ui/trading_screen.gd`

---

## Polish 단계

### TD-05. 로컬라이제이션 (tr() 래핑)

- **현황**: 전 UI 파일에서 한국어 문자열 하드코딩. `tr()` 미사용
- **판단**: 한국어 단일 타겟이므로 기능상 문제 없음. 다국어 지원 시 필수
- **해결안**: 전 UI 파일의 사용자 대면 문자열을 `tr("KEY")` 래핑 + 한국어 locale 파일 생성
- **작업량**: 대
- **관련 파일**: `src/ui/*.gd`

### TD-06. 게임패드 입력 지원

- **현황**: `_unhandled_input`에서 `InputEventKey`만 처리. 게임패드 미지원 (ui-code.md Rule 3 위반)
- **해결안**: `InputMap`에 게임패드 액션 등록 + `InputEventJoypadButton` 처리
- **작업량**: 중
- **관련 파일**: `src/ui/trading_screen.gd`, `src/ui/skill_tree_overlay.gd`, `project.godot`

### ~~TD-07. 애니메이션 접근성 (reduced_motion)~~ — **해결됨 (2026-04-04, S3-12)**

- `project.godot` → `[accessibility] reduced_motion=false` 설정 추가
- `xp_bar.gd` → 모든 Tween 생성 전 `_reduced_motion()` 체크. true이면 즉시 최종값 적용 (fill, SP badge, float text 전부)
- `level_up_banner.gd` → `show_level_up()` / `hide_banner()` 에서 reduced_motion 체크. true이면 즉시 표시/숨김
- 토스트(`trading_screen.gd`) 는 TD-04 God Object 분리(Sprint 4) 이후 적용 예정

---

## M/L 코드 리뷰 잔여 (S3-09 부분 해결)

코드 리뷰 6차에서 식별된 Medium/Low 이슈. S3-09(2026-04-04)에서 5건 해결.

### ✅ 해결됨 (S3-09)
- ~~`_format_number` 중복 3개 파일~~ → `FormatUtils.number()` static class 추출 (`src/core/format_utils.gd`). trading_screen.gd, chart_renderer.gd, portfolio_view.gd, league_screen.gd 모두 위임
- ~~SpinBox 에러 Tween 누적~~ → `_error_tween` 참조 보관, `.kill()` 후 재생성 (`trading_screen.gd._show_order_error()`)
- ~~OrderEngine 주문 히스토리 무제한 증가~~ → `ORDER_HISTORY_MAX_SIZE = 500` 상수 + `_history_append()` 헬퍼 추가
- ~~stock_database 섹터/태그 인덱스 O(n) 스캔~~ → `_sector_index`, `_tag_index` Dictionary 사전 계산 (`_build_indexes()`) — O(1) 조회

### 잔여 항목
- 차트 RSI/MACD 캐싱 (M, 매 프레임 배열 할당) — Sprint 4 S3-10 성능 프로파일링 이후 수치 확인 후 처리
- **뉴스 날짜 월 하드코딩 (M, 3월 고정)** — **설계 결정 필요**: 시즌 시작 월을 설정값으로 만들 것인지, 게임 내 픽션 날짜 체계로 처리할 것인지 결정 후 구현
- 스킬트리 14개 스킬 하드코딩 → 데이터 파일 (M) — TD-04 God Object 분리(Sprint 4) 시 함께 처리
