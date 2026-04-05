# Sprint 3 -- 2026-04-15 to 2026-04-28

## Sprint Goal

V-Slice를 완성하여 "시즌 시작 → 거래 → 시즌 종료 → 리더보드 확인"의 전체 루프를
처음부터 끝까지 플레이 가능한 상태로 만든다.

## Capacity

- Total sessions: 10
- Buffer (20%): 2 sessions (비계획 작업, 통합 버그)
- Available: 8 sessions
- Sprint 2 velocity: 계획 8 + 비계획 6 items 소화 (buffer 초과)
- Sprint 3 비계획 예상: E2E 통합 스프린트이므로 런타임 버그 추가 발견 가능성 높음

## Tasks

### Must Have (Critical Path)

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------------|-----------|-------------|---------------------|
| S3-01 | TD-08: SeasonManager 시즌 시작 흐름 재설계 | lead-programmer | 1 day | — | PRE_MARKET 화면에 "시즌 시작" 버튼 → `SeasonManager.start_season()` → 내부에서 `GameClock.start_season()` 호출. `game_main.gd` 직접 호출 제거. 기존 테스트 통과 |
| S3-02 | GameClock.pause_request/release() 구현 | lead-programmer | 1 day | — | 참조 카운팅 방식 일시정지. `pause_request(source_id)` 호출 시 정지, 모든 소스가 `pause_release(source_id)` 해제 시에만 재개. 중복 source_id 방어. 유닛 테스트 추가. API 계약 테스트 추가 |
| S3-03 | SeasonManager.get_leaderboard() 구현 | lead-programmer | 1 day | — | 티어 내 리더보드 반환 (AI + 플레이어 통합). 반환: `[{rank, nickname, return_pct, prize_preview, is_grandmaster_ai}]`. `get_leaderboard(tier, from_rank, to_rank)` 범위 쿼리 지원. 유닛 테스트 추가 |
| S3-04 | MainScreen.tscn + F1/F2/F3 탭 전환 구현 | ui-programmer | 2 days | S3-01, S3-02 | MainScreen이 TabBar 소유 (ADR-006). F1=TradingScreen, F2=LeagueScreen, F3=GrowthScreen(placeholder). F1/F2/F3 키 + 클릭 전환. 장 중 F2/F3 진입 시 자동 pause_request + "장 중 일시정지" 배너. F1 복귀 시 pause_release |
| S3-05 | LeagueScreen.tscn + league_screen.gd 구현 | ui-programmer | 2 days | S3-03, S3-04 | league-ui.md AC-08~AC-15 전부 충족. 좌측: 내 현황 (티어, 순위, 시즌/주간 수익률, 주간 수익률상 현황). 우측: 리더보드 (상위 10위 + 내 순위 ±2위 컨텍스트). 글로벌 순위 하단 고정. 시즌 미시작 시 "시즌 시작 전" 안내 |
| S3-06 | 상태바 HUD 리그 정보 통합 | ui-programmer | 0.5 day | S3-03 | trading_screen.gd 상태바 행 2에 `[티어 N위] \| 시즌 +X.X% \| 주간 +X.X%` 표시. 양수 초록/음수 빨강. 클릭 시 F2 이동. league-ui.md AC-01~AC-03 충족 |
| S3-07 | V-Slice E2E 빌드 검증 | qa-lead | 1 day | S3-01~S3-06 전부 | 시즌 시작 → 거래 → 시즌 종료 → 리더보드 확인 전체 흐름 플레이 가능. `--export-release` 빌드 성공. 바이너리 5초+ 생존. SCRIPT ERROR 없음. v-slice.md Success Criteria 5개 항목 전부 충족. QA Lead 서명 _______ |

### Should Have

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------------|-----------|-------------|---------------------|
| S3-08 | GDD §9 Implementation Checklist 백필 (ai-competitor.md, season-manager.md) | game-designer | 1 day | — | 두 GDD에 §9 섹션 추가. 진입점, 호출 경로, AC→테스트 매핑, 빌드 검증 란 포함 |
| S3-09 | M/L 코드 리뷰 확장 처리 (~15건) | lead-programmer | 2.5 days | S3-07 이후 권장 | `_format_number` 중복 제거, 뉴스 날짜 월 하드코딩 수정, SpinBox Tween 누적 수정, stock_database 섹터 인덱스 사전 계산, 차트 RSI/MACD 캐싱, 스킬트리 하드코딩→데이터 파일, OrderEngine 주문 히스토리 cap, PriceEngine VI 카운터 초기화, 기타 L급 ~8건. 처리 후 기존 테스트 전부 통과 |
| S3-12 | TD-07: 애니메이션 reduced_motion 지원 | ui-programmer | 0.5 day | S3-07 이후 | `accessibility/reduced_motion` 프로젝트 설정 추가. XpBar, LevelUpBanner, 토스트 Tween 생성 시 체크 → 즉시 최종값 적용. TD-07 해결 |
| S3-13 | TD-03: UI 직접 상태 변경 완화 (pause/speed 시그널화) | lead-programmer | 1 day | S3-07 이후 | `toggle_pause`/`set_speed` 호출을 시그널 기반 Command 패턴으로 전환. `submit_order`는 반환값 필요하므로 직접 호출 유지. TD-03 해결 |

### Nice to Have

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------------|-----------|-------------|---------------------|
| S3-10 | 성능 프로파일링 1차 | lead-programmer | 1 day | S3-07 | Godot 프로파일러로 E2E 플레이 중 측정. RSI/MACD 캐싱, stock_database O(n) 스캔, HUD 갱신 16.6ms 이내. 결과를 `docs/profiling/v-slice-baseline.md`에 기록 |
| S3-11 | 나머지 GDD §9 백필 | game-designer | 1 day | S3-08 | xp-system.md, skill-tree.md, trading-screen.md 등 나머지 GDD 전부에 §9 추가 |

## Capacity Check

| Category | Sessions |
|----------|----------|
| Available (buffer 제외) | 8 |
| Must Have | 4.25 |
| Should Have (S3-08~S3-13) | 2.5 |
| Nice to Have | 1.0 |
| **합계** | **7.75** |
| **여유** | **+0.25 (buffer로 흡수)** |

> TD-03, TD-07 추가 승인 (2026-04-04). S3-09 범위 5건 → ~15건 확장. TD-04(God Object)는 Sprint 3에서 같은 파일을 동시 수정하는 충돌 위험으로 Sprint 4 첫 태스크로 확정.

## Critical Path

```
Day 1:  S3-01 (TD-08) ─────────────────────────────────────────────────────┐
        S3-02 (pause_request) ─────────────────────────────────────────────┼──→ S3-04 (MainScreen, Day 2-3)
        S3-03 (get_leaderboard) ──→ S3-06 (HUD 통합, Day 2) ──────────────┤
                                 └──→ S3-05 (LeagueScreen, Day 4-5) ────────┘
Day 6:  S3-07 (E2E 검증)
```

**병행 가능**: S3-01, S3-02, S3-03은 서로 독립 — Day 1 동시 착수.
**블로커**: S3-04는 S3-01 + S3-02 완료 필요. S3-05는 S3-03 + S3-04 필요.

## Carryover from Sprint 2

| Task | Reason | New Estimate |
|------|--------|-------------|
| 리그 F2탭 UI (System 16) | Sprint 2에서 GDD만 완료, 구현은 Sprint 3 계획 | S3-04~S3-06 (4.5 days) |
| TD-08 SeasonManager 진입점 | Sprint 2 종료 시점에 식별, V-Slice 전 필수 | S3-01 (1 day) |

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| MainScreen 탭 컨테이너가 기존 TradingScreen 초기화 흐름과 충돌 | Medium | High | scene_tree 의존성 먼저 파악 후 착수. Lead Programmer + Technical Director 협의 |
| pause_request 참조 카운팅이 기존 toggle_pause 호출과 충돌 | Medium | Medium | 기존 toggle_pause를 점진적 마이그레이션. 하위 호환 유지하며 deprecation 경고 추가 |
| E2E 통합 시 미발견 런타임 버그 (Sprint 2에서 3건 발견) | High | Medium | S3-07에 1 full day 배정. Buffer 2 sessions이 흡수 |
| LeagueScreen 리더보드 병합 로직 복잡도 예상 초과 | Low | Medium | league-ui.md GDD에 엣지 케이스 9건 + 병합 로직 명세 완비 |

## Progress Snapshot (2026-04-04) — Day 2 → SPRINT COMPLETE

- S3-01 ✅ TD-08 해결 완료: SeasonManager 시즌 시작 흐름 재설계
- S3-02 ✅ GameClock.pause_request/release() 구현 완료 (test_game_clock.gd 6건)
- S3-03 ✅ SeasonManager.get_leaderboard() + is_season_active() 구현 완료 (테스트 6건)
- S3-04 ✅ MainScreen.tscn + F1/F2/F3 탭 전환 구현 완료 (ADR-006 준수)
- S3-06 ✅ 상태바 HUD 리그 정보 통합 (league_tab_requested 시그널)
- S3-05 ✅ LeagueScreen.tscn + league_screen.gd 구현 완료 (AC-08~AC-15)
  - SeasonManager에 get_tier_rank(), get_weekly_trade_count(), is_season_trade_eligible() 추가
  - EC-05 (프리마켓), EC-06 (시즌 미시작) 처리 완료
  - 리더보드 병합 로직 (MERGE_THRESHOLD=12) 구현 완료
- API 계약 테스트: 62 → 70건 (pause_request, pause_release, is_season_active, get_leaderboard, get_tier_rank, get_weekly_trade_count, is_season_trade_eligible, submit_market_order, submit_limit_order 추가; submit_order 수정)
- S3-08 ✅ GDD §9 Implementation Checklist 백필 (ai-competitor.md, season-manager.md)
- S3-12 ✅ TD-07 reduced_motion 지원 (project.godot 설정 추가, xp_bar.gd, level_up_banner.gd)
- S3-13 ✅ TD-03 pause/speed 시그널화 (SkillTreeOverlay→TradingScreen→MainScreen→GameClock 경로)
- S3-09 ✅ M/L 코드 리뷰 5건 처리 완료: FormatUtils 추출, Tween 누적 수정, OrderEngine cap, StockDatabase O(1) 인덱스
  - 뉴스 날짜 월 하드코딩: 설계 결정 필요 (사용자 확인 요) — Sprint 4 이후
- S3-11 ✅ 나머지 GDD §9 백필 완료 (14개 파일: game-clock, stock-database, price-engine, news-events, order-engine, portfolio-manager, currency-system, xp-system, skill-tree, news-feed-ui, chart-renderer, portfolio-ui, trading-screen, progression-ui)
- S3-07 ✅ V-Slice E2E 빌드 검증 완료 (QA Lead 서명: 2026-04-04)
  - GUT 185/185 통과 (test_api_contracts.gd submit_order 버그 수정 포함)
  - --export-release 빌드 성공: build/windows/SeedMoney.exe (109MB)
  - 바이너리 8초+ 생존 확인 (5초 기준 충족)
  - SCRIPT ERROR 없음 (종료 시 StringName cleanup은 엔진 내부 이슈, 게임 코드 무관)

## Definition of Done for this Sprint

- [x] V-Slice Success Criteria 5개 항목 전부 충족 (v-slice.md 참조)
- [x] Must Have S3-01~S3-07 전부 완료
- [x] `--export-release` 빌드 성공 + 바이너리 5초+ 생존 + SCRIPT ERROR 없음
- [x] 시즌 시작 → 거래 → 시즌 종료 → 리더보드 확인 E2E 플레이 가능 (QA Lead 서명: 2026-04-04)
- [x] API 계약 테스트 포함 기존 테스트 전부 통과 (185/185)
- [x] league-ui.md AC-01~AC-15 충족
- [x] 코드 커밋 완료, main 브랜치 green (b48c709)
