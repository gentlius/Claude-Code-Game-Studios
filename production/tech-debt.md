# Technical Debt Register

> 코드 리뷰 (2026-04-03)에서 식별된 아키텍처 이슈. 우선순위별 정리.

## V-Slice 전 (필수)

### TD-01. 틱 처리 순서 보장

- **현황**: `on_tick` 시그널에 News, PriceEngine, OrderEngine이 모두 connect — 실행 순서는 connect 호출 순서에 의존 (fragile)
- **GDD 요구**: News → PriceEngine → OrderEngine 순차 처리
- **해결안**: GameClock이 `on_tick` broadcast 대신 `NewsEventSystem.process_tick()` → `PriceEngine.process_tick()` → `OrderEngine.process_tick()`를 명시적으로 순차 호출
- **작업량**: 소
- **관련 파일**: `src/core/game_clock.gd`, `src/gameplay/price_engine.gd`, `src/gameplay/order_engine.gd`, `src/gameplay/news_event_system.gd`

### TD-02. 테스트 격리용 `reset_for_testing()` 메서드

- **현황**: 모든 테스트가 autoload 싱글톤 내부 변수를 직접 조작 (`PriceEngine._vi_states`, `OrderEngine._next_order_id` 등). 하나의 테스트가 글로벌 상태를 오염시키면 다음 테스트에 영향
- **해결안**: 각 gameplay/core 시스템에 `reset_for_testing()` 메서드 추가. `before_each`에서 호출
- **작업량**: 소
- **관련 파일**: `src/core/game_clock.gd`, `src/core/currency_system.gd`, `src/core/stock_database.gd`, `src/gameplay/*.gd`, `tests/unit/*.gd`

---

## Production 진입 시

### TD-03. UI 직접 상태 변경 완화

- **현황**: `trading_screen.gd`와 `skill_tree_overlay.gd`가 `GameClock.toggle_pause()`, `set_speed()`, `confirm_transition()` 등을 직접 호출. ui-code.md 규칙 위반 ("commands/events로 변경 요청")
- **판단**: `submit_order`는 반환값 필요 → 직접 호출 합리적. `toggle_pause`/`set_speed`는 시그널로 전환 가능
- **해결안**: pause/speed 관련 호출만 시그널 기반 Command 패턴으로 전환
- **작업량**: 중
- **관련 파일**: `src/ui/trading_screen.gd`, `src/ui/skill_tree_overlay.gd`, `src/core/game_clock.gd`

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

### TD-07. 애니메이션 접근성 (reduced_motion)

- **현황**: XP 바, 레벨업 배너, 토스트 등 모든 애니메이션이 모션 감소 설정 미확인 (ui-code.md Rule 4 위반)
- **해결안**: 프로젝트 설정 `accessibility/reduced_motion` 추가. Tween 생성 시 체크하여 즉시 최종값 적용
- **작업량**: 소
- **관련 파일**: `src/ui/xp_bar.gd`, `src/ui/level_up_banner.gd`, `src/ui/trading_screen.gd`

---

## M/L 코드 리뷰 잔여 (33 M + 23 L = 56건)

코드 리뷰 6차에서 식별된 Medium/Low 이슈 56건은 커밋 `1c739ee` 이후 미수정 상태.
주요 항목:
- 차트 RSI/MACD 캐싱 (M, 매 프레임 배열 할당)
- `_format_number` 중복 3개 파일 (M, 유틸리티 추출)
- stock_database 섹터/태그 인덱스 사전 계산 (M, 매 틱 O(n) 스캔)
- 뉴스 날짜 월 하드코딩 (M, 3월 고정)
- SpinBox 에러 Tween 누적 (M)
- 스킬트리 14개 스킬 하드코딩 → 데이터 파일 (M)
