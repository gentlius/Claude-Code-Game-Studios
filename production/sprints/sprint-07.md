# Sprint 7 — 2026-04-15 to 2026-04-28

## Sprint Goal

Beta 개발 첫 스프린트. 이전 스프린트 이월(TR2 GDD)을 완결하고, TR2·F3 화면 구현을 착수한다.
동시에 2026-04-14 팀 리뷰에서 도출된 **보안 블로커** 2건(API 이름 불일치, 가격 정찰 익스플로잇)을
Must Have로 처리하여 이후 스프린트의 기술 부채를 막는다.

> **추가 컨텍스트**: 2026-04-14 팀 전체 기획 리뷰 결과가 이 스프린트에 반영됨.
> 원본: `docs/team-review/2026-04-14-team-assessment.md`

## Capacity

- Total sessions: 10
- Buffer (20%): 2 sessions
- Available: 8 sessions
- Sprint 6 velocity: Must Have 3/3 ✅ Should Have 1/1 ✅ Nice-to-Have 1/1 ✅

## Tasks

### Must Have (Critical Path)

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S7-01 | TR2 손절/익절 GDD 작성 (S6-07 이월) | game-designer | 1 | — | `design/gdd/stop-loss-take-profit.md` 9개 섹션 완성 + Approved. B-01 구현 선행 조건. (P-RULE-03 적용) |
| S7-02 | TR2 손절/익절 구현 (B-01) | gameplay-programmer | 2 | S7-01 완료 | **(1)** 지정가 주문 패널에 손절가/익절가 입력 필드 추가 (TR1 해금 필요). **(2)** `OrderEngine`이 매 틱 손절/익절 조건 평가 → 자동 매도. **(3)** 포트폴리오 뷰에 활성 손절/익절 표시. **(4)** 기존 테스트 전부 통과 + TR2 신규 테스트 추가. **(5)** `--export-release` 빌드 + 5초 생존. |
| S7-03 | **[팀 리뷰] API 이름 일치화** | lead-programmer | 1 | — | 코드 내 `season_start_capital` / `get_season_start_capital()` → `season_start_deposit` / `get_season_start_deposit()` 전수 교체. JSON key `"season_start_capital"` → `"season_start_deposit"`. 세이브 파일 마이그레이션 로직(구 key → 신 key) 추가. 영향 파일: `portfolio_manager.gd`, `season_manager.gd`, `portfolio_view.gd`, `league_screen.gd`, `save_system.gd`. 교체 후 테스트 전부 통과. |
| S7-04 | **[팀 리뷰] 가격 정찰 익스플로잇 차단 (ADR-018)** | lead-programmer | 1 | ADR-018 승인 | `PriceEngine`에 `_rng: RandomNumberGenerator` 도입. `_ready()` 및 `load_save_data()` 에서 `_rng.seed = Time.get_ticks_usec()` 호출. `randf()` → `_rng.randf()` 교체 (PriceEngine 내부). `get_save_data()` 에서 `_rng` 상태 제외. 테스트 환경은 `_rng.seed = TEST_SEED` 고정. 신규 테스트: "동일 세이브 두 번 로드 시 Day N 가격 시퀀스가 다름" 통계 검증. |
| S7-05 | F3 성장 화면 GDD + 구현 (B-03) | game-designer + gameplay-programmer | 1.5 | — | `design/gdd/growth-screen.md` 9개 섹션 완성 + 구현. **(1)** F3 탭 클릭 → 성장 화면 로드. **(2)** 누적 수익률, 시즌 히스토리, 현금 자산·총 자산 표시. **(3)** `account_total_value = CurrencySystem.get_account_total_value()`, `cash_assets = CurrencySystem.get_cash_assets()` 연동. **(4)** 빌드 성공. |
| S7-06 | **[팀 리뷰] Beta DoD 업데이트 + QA 플레이테스트 프로토콜** | qa-lead + producer | 0.5 | — | **(1)** `production/milestones/beta.md` Success Criteria에 "이중 승리 조건 달성 경로 검증 (cash_assets ≥ 1,000억 OR total_assets ≥ 1조)" 추가. **(2)** `docs/testing/playtest-protocol-beta.md` 생성: 대상 인원(3명+), 세션 설계(3시즌 플레이), 판정 방식("4시즌 시작 의향" 0-5점 척도 → 3명 중 2명 이상 4+ 합격). |

### Should Have

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S7-07 | Phase 3 스킬 UI (TR2 자동화 피드백, B-04) | gameplay-programmer | 1 | S7-02 완료 | 손절/익절 발동 시 포트폴리오 뷰에 "SL 발동" / "TP 발동" 뱃지 표시. TR2 미해금 시 지정가 패널 손절/익절 입력 필드 비활성. |
| S7-08 | **[팀 리뷰] 아트 바이블 초안 + 거주지 배경 방향** | art-director | 1 | — | **(1)** `design/art-bible.md` 초안 작성: 색상 팔레트(ThemeSetup 기준), 타이포그래피 규칙, UI 컴포넌트 스타일 가이드. **(2)** 거주지 11티어 배경 비주얼 방향 결정 (무드보드 레퍼런스 + 스타일 선택: 픽셀아트 / 미니멀 벡터 / 포토리얼). `design/residence-art-direction.md` 작성. |
| S7-09 | **[팀 리뷰] 앰비언트 음악 계획 + SFX 가이드 완성** | audio-director | 1 | — | **(1)** `design/audio-plan.md` (또는 기존 파일) 업데이트: 시장 상태(PRE_MARKET / MARKET_OPEN / PAUSED / MARKET_CLOSED)별 BGM 테마 방향, 악기 구성, BPM/분위기 레퍼런스. **(2)** DOWNLOAD_GUIDE S-11~S-14 SFX 가이드 최종 완성본 제출. |

### Nice to Have

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S7-10 | 티어업 서사 훅 텍스트 초안 | narrative-director | 0.5 | — | 브론즈→실버, 실버→골드, 골드→플래티넘 티어업 각 1-2줄 대사 초안. `design/narrative/tier-up-lines.md` 작성. |

## Capacity Check

| Category | Sessions |
|----------|----------|
| Available (buffer 제외) | 8 |
| Must Have 합계 | 7.0 (S7-01×1 + S7-02×2 + S7-03×1 + S7-04×1 + S7-05×1.5 + S7-06×0.5) |
| Should Have | 3 |
| Nice to Have | 0.5 |
| **Must Have 적합성** | **7.0 / 8 ✅** |
| **전체 합계** | **10.5 (buffer 흡수 1.5 세션 가능)** |

> **주의**: Should Have(3 세션) 전부 완료 시 총 10 세션. Buffer 2 세션 내로 흡수 가능하나 빡빡함.
> S7-07은 S7-02 완료 후 착수 → 순차 의존성 있으므로 병목 주의.

## Critical Path

```
Day 0-1:  S7-01 TR2 GDD 작성 (game-designer)
          S7-03 API 이름 일치화 (lead-programmer, 병행)
          S7-04 가격 정찰 익스플로잇 차단 (lead-programmer, 병행)
Day 2-4:  S7-02 TR2 구현 (gameplay-programmer) — S7-01 완료 후
          S7-05 F3 성장 화면 (game-designer + gameplay-programmer, 병행)
Day 5:    S7-06 Beta DoD + QA 프로토콜 (qa-lead + producer)
Day 6-7:  S7-07 Phase 3 스킬 UI (S7-02 완료 후)
          S7-08 Art Director (병행)
          S7-09 Audio Director (병행)
Day 8:    S7-10 서사 훅 초안 (선택, 여유 시)
```

## DoD (Definition of Done)

- [x] S7-01: `design/gdd/stop-loss-take-profit.md` Approved — Draft 완료 2026-04-15 (Approved 조건: Implementation Checklist 전 항목 체크 + QA 서명)
- [x] S7-02: TR2 E2E 동작 확인 + 테스트 통과 + 빌드 성공 — 완료 2026-04-15 (StopTakeSystem autoload, OrderEngine 3-d 통합, PortfolioView S/T 버튼, save_version 3)
- [x] S7-03: `season_start_capital` 코드베이스 전수 제거 확인 (`grep` 결과 0건) — 완료 2026-04-14
- [x] S7-04: 동일 세이브 두 번 로드 시 가격 다름 확인 — 완료 2026-04-14 (ADR-018 구현)
- [x] S7-05: F3 탭 E2E 동작 확인 + 빌드 성공 — 완료 2026-04-15 (GrowthScreen 코드 빌드, XpBar 제거, SkillTreeOverlay 제거, growth_tab_requested 시그널 체인)
- [x] S7-06: `beta.md` 이중 승리 조건 추가 + `playtest-protocol-beta.md` 존재 — `beta.md` 완료 2026-04-14, `playtest-protocol-beta.md` 완료 2026-04-15
- [x] S7-07: SL/TP 발동 배지 표시 + TR2 해금 즉시 S/T 버튼 활성 — 완료 2026-04-15
- [x] S7-08: `design/art-bible.md` + `design/residence-art-direction.md` Draft — 완료 2026-04-15
- [x] S7-09: `design/audio-plan.md` Draft (BGM 테마 방향 + SFX 전 항목 완료) — 완료 2026-04-15
- [x] S7-10: `design/narrative/tier-up-lines.md` 브론즈→실버→골드→플래티넘 대사 초안 — 완료 2026-04-15
- [x] `sprint-07.md` DoD 전 항목 `[x]` — Producer 확인 2026-04-15

## 스프린트 전 완료 항목 (2026-04-14 베타 코드 리뷰)

S7 공식 착수 전 2026-04-14 세션에서 베타 기준 코드 리뷰(P0~P3)를 완료.
원본 리뷰: `docs/team-review/2026-04-14-team-assessment.md`

| 항목 | 심각도 | 완료 내용 |
|------|--------|-----------|
| `season_start_capital` → `season_start_deposit` 전수 교체 | P0 | `season_manager.gd`, `portfolio_manager.gd`, `portfolio_view.gd`, `league_screen.gd`, `tests/` 4개 파일. JSON 마이그레이션(구키 폴백) 포함. |
| `settle_season()` → `settle_to_cash(_prize)` 리네임 | P0 | `currency_system.gd` — GDD 명세 불일치 데드코드 교정. |
| ADR-018 PriceEngine 세션 RNG 엔트로피 | P0 | `price_engine.gd` 에 `_rng` 전용 인스턴스 + `_reseed_session()`. `randf()` → `_rng.randf()` 전수 교체. |
| `SaveSystem.is_save_pending()` 캡슐화 | P1 | `save_system.gd` public 메서드 추가. `main_screen.gd` 직접 접근 제거. |
| `portfolio_view.gd` 표시 포맷 단일화 | P1 | 거래내역 `tx_stock.name_ko` → `tx_stock.get_display_name()`. |
| `main_screen.gd` Color 리터럴 → ThemeSetup 상수 | P1 | `ThemeSetup`에 `LAYOUT_*` 상수 8개 추가. `main_screen.gd` 리터럴 전수 교체. |
| `status_bar.gd` 그림자 상수 제거 | P2 | `class_name TradingScreen` 추가. `TradingScreen.UIState` 직접 참조. `set_ui_state` 타입 `int` → `TradingScreen.UIState`. |
| `portfolio_view.gd` 홀딩 목록 diff 기반 갱신 | P3 | `_holding_rows` 캐시 + 구조 변경 감지 → 매 틱 Node 재생성 제거. |
| `ai_competitor.gd` EOD 재계산 O(day) → O(1) | P3 | `eod_rng_states` 캐시 도입. `_compute_eod_for` 전일 RNG 상태 복원 후 1스텝만 진행. |
| 게임패드 홀딩 목록 탐색 불가 | P3 | Tech Debt 등록 완료 (`production/tech-debt.md`). |
