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
