## TASK: 전체 코드 리뷰 (src/ + gdextension/src/)
## STATUS: DONE
## COMPLETED:
- ✅ 파일 목록 파악 (GDScript 49개 + C++ 7개)
- ✅ core/ 파일 읽기 (8개) — 이슈 없음
- ✅ gameplay/ 파일 읽기 (16개) — H:3, M:5, L:5 이슈 발견
- ✅ ui/ 파일 읽기 (25개) — 추가 이슈 포함
- ✅ gdextension/src/ 읽기 — C++ 이슈 포함
- ✅ 코드 리뷰 보고서 작성 (production/session-state/code-review-2026-04-24.md)
- ✅ H-01: price_engine.gd — hardcoded "KR" → MarketConfig.get_active_market()
- ✅ H-02: ai_competitor.gd — assert(TOTAL_PARTICIPANTS == ...) 제거
- ✅ H-03: news_event_system.gd — TICKS_PER_DAY → get_effective_ticks_per_day()
- ✅ H-04: lifestyle_screen.gd — const Array 5개 → lifestyle_items.json 분리
- ✅ M-01: m1_cache_manager.gd — slot_id < 0 가드 추가
- ✅ M-02: short_selling_system.gd — 미지급 borrow fee → margin_deposited 차감
- ✅ M-03: leverage_manager.gd — manual close 초과 손실 → on_loan_shark_ending_triggered
- ✅ M-04: m1_cache_manager.gd — 리터럴 4 → GameClock.TICKS_PER_MINUTE
- ✅ M-05: etf_manager.gd — false positive (시그널 순서 이미 올바름)
- ✅ M-06: settlement_reporter.gd — const BBCode 컬러 → var, _ready()에서 초기화
- ✅ M-07: sector_comparison_view.gd — _set_mini_bar_fill 노드 캐시 (per-tick 할당 제거)
- ✅ M-08: portfolio_view.gd — _refresh_transactions diff-guard 추가
- ✅ M-09: chart_renderer.gd — tf / 4 → tf / GameClock.TICKS_PER_MINUTE
- ✅ L-01: xp_system.gd — _cumulative_xp_table PrepackedInt64Array 사전 계산
- ✅ L-02: ai_competitor.gd — RandomNumberGenerator 클래스 멤버로 이동
- ✅ L-03: news_event_system.gd — _template_index 역인덱스 추가
- ✅ L-04: season_manager.gd — 음수 modulo 방어 (maxi(0, _seasons_played-1))
- ✅ L-05: skill_tree.gd — 튜닝 상수 → skill_tree_config.json 분리
- ✅ L-06: order_panel.gd — 하드코딩 문자열 → tr() 래핑
- ✅ L-07: portfolio_view.gd — 현재가 직접 조회 → PriceEngine.get_current_price()
- ✅ L-08: price_kernel.h — TICKS_PER_MINUTE = 4 상수 추가, cpp 3곳 교체
- ✅ DLL 재빌드 (SCons — 성공)
## NEXT: 커밋
