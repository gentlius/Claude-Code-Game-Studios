# Sprint 6 -- 2026-04-21 to 2026-05-04

## Sprint Goal

Alpha 마일스톤을 완전히 종료한다.
Sprint 5에서 남긴 E2E 미검증 4건을 신규 흐름 기준으로 재작성하여 통과시키고,
Phase 1/2 스킬 UI를 완성하고, 문서 스테일을 일괄 정리한다.
이 스프린트가 끝나면 `alpha.md` Status → **Closed**이고 Beta 개발로 진입한다.

## Capacity

- Total sessions: 10
- Buffer (20%): 2 sessions
- Available: 8 sessions
- Sprint 5 velocity: Must Have 3/3 ✅ Should Have 4/4 ✅ Nice-to-Have 2/2 ✅

## Tasks

### Must Have (Critical Path)

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S6-01 | Alpha E2E 재검증 + QA 종료 | qa-lead | 2 | S5 구현 전체 완료 | **(1) 신규 게임 진입 E2E**: SplashScreen 2초 → StartScreen 슬롯 목록 → 새 슬롯 생성 → IntroSequence 5장 → MainScreen F1 정상 로드. **(2) 멀티슬롯 세이브/로드 E2E**: 슬롯 생성 → 플레이 → 자동저장 → SavingOverlay 표시/해제 → 앱 재시작 → StartScreen에서 슬롯 선택 → 상태(XP·레벨·스킬·시즌·포트폴리오) 전부 복원. **(3) 레거시 마이그레이션**: `save_data.json` v1 → `save_slot_0.json` + `save_index.json` 자동 변환 확인. **(4) SFX 4종 발동**: 주문 체결·레벨업·VI 발동·뉴스 알림 인게임 확인. **(5) 기존 테스트 전부 통과 + intro_sequence 신규 테스트 통과**. **(6)** `--export-release` 빌드 성공 + SCRIPT ERROR 없음. **(7)** `alpha.md` Status → **Closed**. QA Lead 서명. |
| S6-02 | Phase 1 스킬 UI 피드백 (S1/S2/TR1/P1/P2) | gameplay-programmer | 2 | `skill-roadmap.md` Phase 1 | **(S1)** 해금 시 뉴스 피드 헤더에 "FAST" 배지 표시, 미해금 시 미표시. **(S2)** 해금 시 "LIVE" 배지 + 붉은 점 인디케이터. **(TR1)** 미해금 시 지정가 탭 비활성(회색) + "TR1 해금 필요" 툴팁 → 기존 에러 메시지 방식 제거. 해금 즉시 탭 활성. **(P1)** 포트폴리오 슬롯 카운터 "X/5" 표시. **(P2)** 해금 시 "X/10"으로 갱신. 스킬 해금 이벤트 → 즉시 UI 반영. 기존 테스트 전부 통과. |
| S6-03 | chart_renderer.gd Timer dangling 수정 | gameplay-programmer | 0.5 | — | 80ms 디바운스 타이머 씬 제거 시 dangling 수정 (audit TD-AUDIT-03). A2 RSI/MACD 구현 자체는 이미 완료 상태 — 수정 불필요. |
| S6-04 | 코드 TODO + audit 버그 처리 | gameplay-programmer | 0.5 | — | **(logo)** `splash_screen.gd:31` Label → TextureRect, `assets/ui/logo.svg` 연결. TODO 주석 제거. **(audit-1)** `settlement_reporter.gd` 팝업 닫힘 중 타이머 레이스 컨디션 수정. **(audit-2)** `xp_bar.gd` C-01 시그니처 재검증 후 수정. |
| S6-05 | 문서 스테일 일괄 정리 | producer | 0.5 | S6-01 완료 후 | **(1)** `alpha.md` Systems 테이블 업데이트 (A-01/A-02/A-03/TD-S5-03/TD-S5-04 → ✅ Done). **(2)** `systems-index.md` System 18/19 → Done. **(3)** `sprint-05.md` DoD 4개 미체크 → ✅ 완료 (신규 흐름 기준). **(4)** `season-manager.md` Checklist M-04 완성. |

### Should Have

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S6-06 | 스타트 스크린 오디오 연동 (S-01~S-06) | audio-director + gameplay-programmer | 1 | AudioManager(S5-02) 완료 + **오디오 파일 수령 조건** | `start_screen.gd` `_ready()` → `AudioManager.play_bgm("bgm_start_screen")`. 슬롯 선택·호버·삭제 SFX 각 연결. `splash_screen.gd` → `sfx_logo_sting` 페이드인 후 재생. `saving_overlay.gd` → save_completed 시 `sfx_save_complete`. 각 SFX 인게임 발동 확인. |

### Nice to Have

| ID | Task | Agent/Owner | Est. Sessions | Dependencies | Acceptance Criteria |
|----|------|-------------|---------------|-------------|---------------------|
| S6-07 | TR2 손절/익절 GDD 작성 | game-designer | 1 | — | `design/gdd/stop-loss-take-profit.md` 9개 섹션 완성 + Approved. Sprint 7 구현 선행 조건 완료. |

## Capacity Check

| Category | Sessions |
|----------|----------|
| Available (buffer 제외) | 8 |
| Must Have 합계 | 5.5 (S6-01×2 + S6-02×2 + S6-03×0.5 + S6-04×0.5 + S6-05×0.5) |
| Should Have | 1 |
| **실행 합계** | **6.5** |
| **여유** | **buffer 2 + 잉여 1.5 = S6-06/S6-07 전부 흡수 가능** |

> **A2 RSI/MACD**: 이미 완전 구현됨 (`chart_renderer.gd` `_draw_rsi()` / `_draw_macd()` / `_rsi_cache`). S6-03은 Timer dangling 버그 수정만 진행.
> **TD-04**: Sprint 4 S4-01에서 완결됨 (586줄). 이번 스프린트는 S6-05 문서 정리만.

## Critical Path

```
Day 0-1:  S6-01 Alpha E2E 재검증 착수 (신규 진입 흐름 + 멀티슬롯)
          S6-04 코드 TODO + audit 버그 처리 (병행, 짧음)
Day 2:    S6-01 SFX 발동 + 테스트 통과 + alpha.md Closed
Day 3-4:  S6-02 Phase 1 스킬 UI 피드백
Day 5-7:  S6-03 A2 RSI/MACD 차트 서브패널
Day 8:    S6-05 문서 스테일 일괄 정리
          S6-06 스타트 스크린 오디오 (파일 수령 완료 조건)
Day 9+:   S6-07 TR2 GDD (여유 시)
```

## Carryover from Sprint 5

| 항목 | S5 상태 | S6 처리 |
|------|---------|---------|
| E2E 세이브/로드 | 미검증 — 멀티슬롯으로 **재설계됨** | S6-01에서 신규 스펙으로 재작성 + 통과 |
| E2E 최초 실행→인트로 | 미검증 — SplashScreen→StartScreen으로 **재설계됨** | S6-01에서 신규 흐름 기준으로 재작성 + 통과 |
| SFX 4종 발동 확인 | 미검증 | S6-01 QA 검증 포함 |
| 테스트 전체 통과 | 미실행 | S6-01 완료 기준에 포함 |
| 오디오 에셋 S-01~06 | 바이너리 수령 대기 | S6-06 (파일 수령 후 진행) |

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| E2E 중 신규 버그 발견 (멀티슬롯·진입 흐름) | High | High | S6-01에 2 sessions 배정. buffer 1.5 sessions 추가 확보 |
| A2 RSI/MACD 차트 레이아웃 충돌 | Medium | Medium | 서브패널 영역 예약 설계(1 session) → 렌더링 구현(1.5 session) 순서로 진행 |
| 오디오 파일 미수령 | High | Low | S6-06 Should Have, 조건부 실행 |

## Dependencies on External Factors

- **오디오 파일 (사용자 수동 작업)**: `assets/audio/DOWNLOAD_GUIDE.md` 참조.
- **spinner_ring.png (사용자 Figma 작업)**: 48×48. Sprint 7 이전 배치 권장.

## Progress Snapshot (2026-04-07) — Sprint 시작 전 사전 작업

### 완료 (Sprint 6 시작 전)
- [x] ADR-009~015 작성 완료 (멀티슬롯, 게임 진입 흐름, SavingOverlay, pause 참조 카운팅, 탭 생명주기, 저장 트리거, TradingScreen 컴포넌트)
- [x] `test_save_system.gd` 전면 재작성 — 단일슬롯 API(save_game/load_game) → 멀티슬롯 API(save_slot/load_slot/create_slot)

### 발견된 블로커 (S6-01 착수 전 해결 필요)
- ✅ **"새게임" 버튼 무반응 버그**: `save_system.gd:271` Array[Dictionary]↔Dictionary 타입 불일치 → GDScript 파스 실패 → SaveSystem null → 수정 완료 (2026-04-08)
- ❌ **Sprint 5 테스트 미실행**: test_save_system.gd가 완전 파손 상태였음 (구 API 참조). 재작성 완료, 실행은 버그 수정 후.

## Progress Snapshot (2026-04-08) — S6-01 E2E 진행 중

### 인게임 확인 (2026-04-09)
- [x] 슬롯 삭제 — PASS
- [x] 새게임(슬롯 생성 → IntroSequence → MainScreen) — PASS
- [x] 세이브 → 종료 → 로드 → 재개 E2E (날짜·가격·뉴스·포트폴리오 복원) — PASS (2026-04-09)
- [x] 리그 AI 경쟁자 순위·수익률 복원 — 설계 재작성 완료 + 테스트 243/243 통과 (2026-04-14)

### 수정 완료된 세이브/로드 버그 (2026-04-08)
- [x] **날짜 오류**: `GameClock.get_save_data()` MARKET_CLOSED 시 day+1 저장
- [x] **등락률 0**: `StockListPanel._init_prev_close()` → PriceEngine.get_daily_limits() 사용
- [x] **뉴스 사라짐**: `NewsEventSystem.get_save_data()` overnight_buffer 저장 + `NewsFeed._ready()` 재수령
- [x] **포트폴리오 비어있음**: `PortfolioView._ready()` 말미에 `_refresh()` 추가
- [x] **리그 순위 불일치**: `AiCompetitor.get_save_data()` day+1 저장 + `load_save_data()` 후 bucket 재계산

### AI 경쟁자 리그 설계 재검토 (2026-04-09)

세이브/로드 반복 과정에서 AI 경쟁자 순위·수익률이 지속적으로 오작동.
증상 수정을 반복해도 근본 해결 불가 → **설계 자체 재검토 결정**.
`ai-competitor.md` GDD + `ai_competitor.gd` 구현을 새 설계 기준으로 재작성 예정.
S6-01 리그 복원 항목은 재설계 완료 후 재검증.

## Definition of Done for this Sprint

- [x] S6-01: Alpha E2E 7개 항목 전부 통과. `alpha.md` Status → **Closed**. QA Lead 서명 (2026-04-14)
- [x] S6-02: Phase 1 스킬 UI 5개 항목 인게임 확인 완료 (2026-04-14)
- [x] S6-03: Timer dangling 수정 완료 (TD-AUDIT-03) — chart_renderer.gd:352 _disconnect_signals()에서 stop+disconnect 처리, tree_exiting 연결
- [x] S6-04: 코드 TODO 1건 + audit 버그 2건 처리 완료
  - (logo) splash_screen.gd:31 — native node 로고 구현 완료 (SVG nanosvg 미지원으로 대체)
  - (audit-1) settlement_reporter.gd — tree_exiting 가드 + step==0 가드 (commit d00d3c2)
  - (audit-2) xp_bar.gd — _on_xp_gained 3-param 시그니처 일치 확인 ✅
- [x] S6-05: 문서 스테일 5건 정리 완료 (2026-04-14)
- [x] 기존 테스트 전부 통과 + 신규 테스트 추가 (243/243, 2026-04-14)
- [x] Code Review Checklist "ADR 동기화" 통과. Technical Director 서명 (2026-04-14) — ADR-017 신규 (뉴스 순회), ADR-007 동점 처리 추가
- [x] `--export-release` 빌드 성공 + SCRIPT ERROR 없음 (2026-04-14, 125MB)
- [x] S6-06: 스타트 스크린 오디오 S-01~S-06 전부 연결 완료 (2026-04-14) — 파일 수령 확인, start_screen/splash_screen/saving_overlay 연동
- [x] 코드 커밋 완료, main 브랜치 green (e6f0197, 2026-04-14)
