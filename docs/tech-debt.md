# Tech Debt Register

코드 리뷰(2026-04-20) 에서 식별된 항목. WARN 등급 이상만 등록.
해소 시 해당 행 삭제 + 커밋 참조 추가.

| ID | 등급 | 파일 | 설명 | 해소 우선순위 |
|----|------|------|------|--------------|
| TD-CR-07 | WARN | `src/gameplay/price_engine.gd` | `process_tick()` 내 `old_prices` Dictionary 매 틱 재할당 (L659). Pre-allocated Dictionary 재사용으로 hot-path GC 부하 제거 필요. | Medium |
| TD-CR-08 | WARN | `src/gameplay/price_engine.gd` | `_build_transition_matrix()` ~75줄, `_compute_event_delta()` ~60줄, `_end_trading_day()` ~58줄 — 40줄 기준 초과. 분리 필요. | Low |
| TD-CR-09 | WARN | `src/gameplay/news_event_system.gd` | `_fire_event_from_slot()` ~125줄 — 5개 책임 혼재. target 결정, event 생성, queue, stats, rumor emit 분리 필요. | Low |
| TD-CR-10 | WARN | `src/gameplay/ai_competitor.gd` | `TOTAL_PARTICIPANTS = 19999` 가 `SeasonManager.TOTAL_PARTICIPANTS(@export var) - 1` 과 수동 동기화. SeasonManager.TOTAL_PARTICIPANTS를 const로 승격하면 ai_competitor.gd const 파생 가능 — 단 Inspector 조정 불가해짐. 트레이드오프 검토 필요. | Low |
| TD-CR-11 | WARN | `src/gameplay/ai_competitor.gd` | `PARTICIPANTS_PER_TICK = 13` 이 `ceil(TOTAL_PARTICIPANTS / TICKS_PER_DAY)` 수동 산출값. 시즌 길이 또는 참가자 수 변경 시 재계산 필요. 런타임 assert 추가 권장. | Low |
| TD-CR-12 | WARN | `src/gameplay/leverage_manager.gd` | `_forced_liquidation()` 에서 `_positions.erase(pos)` 사용 — `close_position()`의 `surviving` 필터 패턴과 불일치. erase 시 참조 동일성에 의존. `surviving` 패턴으로 통일 필요. | Medium |
| TD-CR-13 | WARN | `src/gameplay/leverage_manager.gd` | `close_position()` ~46줄 초과. 분리 필요. | Low |
| TD-CR-14 | WARN | `src/gameplay/season_manager.gd` | `TIER_THRESHOLD`, `PRIZE_RATE`, `WEEKLY_PRIZE_RATE` 등 핵심 경제 밸런스 상수가 코드 내 `var`로 하드코딩. 외부 config JSON으로 이전 권장 (gameplay-code.md 원칙). | Medium |
| TD-CR-15 | WARN | `src/gameplay/xp_system.gd` | `DAILY_RETURN_MULTIPLIERS`, `RANK_XP_TABLE` 복합 배열이 코드 내 하드코딩. config 파일로 이전 권장. | Medium |
| TD-CR-16 | WARN | `src/gameplay/lifestyle_manager.gd` | `RESIDENCE_COSTS`, `RESIDENCE_NAMES` 등 모든 생활비 상수가 코드 내 하드코딩. `_load_config()` 없음. config 파일 이전 필요. | Medium |
| TD-CR-17 | WARN | `src/gameplay/xp_system.gd` | `_calculate_season_xp()`와 `grant_season_bonus()` 가 동일한 rank_bonus/return_bonus 계산을 중복 수행. `_calculate_season_xp()`가 breakdown dict도 반환하도록 리팩터. | Low |
| TD-CR-18 | WARN | `src/gameplay/order_engine.gd` | `"증거금 부족 (필요: %d원)"` 포맷 문자열이 `_validate_sell_short()`(L232)와 `_validate_leverage_buy()`(L292) 두 곳에 중복. 단일 헬퍼로 추출. | Low |
| TD-CR-19 | WARN | `src/gameplay/order_engine.gd` | `_fill_market_order()` ~53줄 초과. 분리 필요. | Low |
| TD-CR-20 | WARN | `src/gameplay/order_engine.gd` | `cancel_order()` — 3개 큐 O(n)×3 탐색. order_id→queue 매핑 Dictionary 추가 시 O(1) 가능. | Low |
| TD-CR-21 | WARN | `src/core/save_system.gd` | `load_slot()` ~68줄 초과. `_restore_*` 헬퍼 분리 권장. | Low |
| TD-CR-22 | WARN | `src/core/audio_manager.gd` | BGM/SFX가 모두 "Master" 버스에 연결 — 독립 볼륨 제어 불가. Beta 전 별도 버스 추가 필요. | Medium |
| TD-CR-23 | WARN | `src/ui/settlement_reporter.gd` | 시즌 등급 임계값 `(20.0, 10.0, 0.0, -10.0)` 이 UI 파일에 하드코딩된 gameplay 밸런스 값. `SeasonManager` 상수 또는 config로 이전 필요. | Medium |
| TD-CR-24 | WARN | `src/ui/chart_renderer.gd` | `_build_header()` ~80줄, `_rebuild_indicator_caches()` ~75줄, `_draw_macd()` ~80줄 등 다수 함수 40줄 초과. 렌더링 로직 분리 필요. | Low |
| TD-CR-25 | WARN | `src/ui/league_screen.gd` | `_build_left_panel()` ~73줄, `_add_row()` ~65줄 등 다수 함수 40줄 초과. 분리 필요. | Low |
| TD-CR-26 | WARN | `src/ui/start_screen.gd` | `_build_ui()` ~87줄, `_build_slot_card()` ~96줄 초과. 분리 필요. | Low |
| TD-CR-27 | WARN | `src/ui/settings_screen.gd` | `_build_ui()` ~118줄 초과. 분리 필요. | Low |
| TD-CR-28 | INFO | `src/gameplay/ohlcv_history.gd` | `_get_all_daily()` 가 lazy 방식으로 pre-history 4000 bar를 매 호출마다 생성. chart_renderer 호출 빈도가 높으면 CPU 부하. 캐싱 고려. | Low |
| TD-CR-29 | INFO | `src/core/currency_system.gd` | `get_deposit()` deprecated alias. 향후 제거 대상. | Low |
| TD-CR-30 | INFO | `src/gameplay/lifestyle_manager.gd` | `_check_and_grant_titles()` 내 칭호 조건이 하드코딩된 item_id 문자열로 체크. JSON 정의와 drift 위험. | Low |
| TD-CR-31 | INFO | `src/ui/portfolio_view.gd` | S/T 컬럼이 헤더에 선언됐으나 `_add_holding_row()` 에서 S/T 위젯 미생성 — 헤더-행 컬럼 수 불일치. StopTakeSystem 연동 시 동시 수정 필요. | Medium |
