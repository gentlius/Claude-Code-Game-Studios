# Milestone: Beta

> **Status**: In Progress
> **Started**: 2026-04-15 (Alpha Closed 2026-04-14)
> **Target**: 2026-06-09 (Sprint 10 종료, 조정 가능)
> **Previous**: Alpha (Closed 2026-04-14)

## Goal

Alpha에서 검증된 플레이어 경험 위에 **콘텐츠 완성도**를 쌓는다.
14개 스킬 전부 해금 가능 상태, 주거 시각화, 자동화 거래(손절/익절),
공매도·레버리지 기반을 갖추고, 처음 해보는 플레이어가
튜토리얼 없이도 3시즌 이상 플레이할 수 있는 상태.

**Beta 판정 기준**: "3시즌 플레이 후 4시즌을 시작하고 싶은가"

---

## Success Criteria

- [ ] 14개 스킬 Phase 1~4 전부 해금 가능 (TR2·TR3·TR4·A2·A3·S3·P3 포함)
- [ ] 주거 시각화 — 티어별 배경 이미지 전환 인게임 확인
- [ ] TR2 손절/익절 주문 E2E (설정 → 자동 체결 → 포트폴리오 반영)
- [ ] AudioManager 실 에셋 교체 (programmatic placeholder → 실 SFX 파일)
- [ ] UI 실 에셋 완성 (spinner_ring, start_bg, logo PNG)
- [ ] 기존 테스트 전부 통과 + 신규 테스트 추가
- [ ] `--export-release` 빌드 성공
- [ ] **이중 승리 경로 검증**: `cash_assets ≥ 100,000,000,000원` (루트 A) 또는 `total_assets ≥ 1,000,000,000,000원` (루트 B) 두 경로 모두 "거장" 엔딩 도달 가능함을 수동 시나리오로 확인

---

## Sprint 6 이월

| 항목 | S6 상태 | Beta 처리 |
|------|---------|---------|
| S6-07 TR2 GDD 작성 | Nice-to-Have 미완 | Sprint 7 Must Have 1번 (P-RULE-03 적용) |
| S6-06 스타트 스크린 오디오 | ✅ 완료 (2026-04-14) | — |
| B-05 코어 SFX 가이드 | DOWNLOAD_GUIDE S-11~S-14 작성 완료 | 파일 수령 후 Sprint 7~10 중 진행 |

---

## Beta Systems (스프린트 배정)

| # | System | Sprint | Status |
|---|--------|--------|--------|
| B-01 | TR2 손절/익절 구현 | Sprint 7 | ✅ Done (2026-04-15) |
| B-02 | A-05a/b 주거 아트 + 시각화 시스템 | Sprint 8 (Should Have) | ✅ Done (2026-04-17 — F3 거주지 배경 + 소비화면 거주지 표시) |
| B-03 | F3 성장 화면 GDD + 구현 | Sprint 7 | ✅ Done (2026-04-15) |
| B-04 | Phase 3 스킬 UI (TR2 자동화 피드백) | Sprint 7 | ✅ Done (2026-04-15) |
| B-05 | AudioManager 코어 SFX 교체 (sfx_order_filled/level_up/vi_alert/news_alert) | Sprint 7~10 | ✅ Done (2026-04-15 — assets/audio/sfx/ 전체 수령 확인) |
| B-06 | A3 재무제표 (PER/PBR/ROE) GDD + 구현 | Sprint 8 | ✅ Done (2026-04-17 — S8-02/S8-03) |
| B-07a | S3 루머 채널 GDD + 구현 | Sprint 8 | ✅ Done (2026-04-17 — S8-04/S8-05) |
| B-07b | TR3 공매도 GDD + 구현 | Sprint 9 | 📋 Planned |
| B-07c | TR4 레버리지 GDD + 구현 | Sprint 9 | 📋 Planned |
| B-08 | P3 섹터 ETF GDD + 구현 | Sprint 10 | 📋 Planned |
| B-09 | 설정 화면 (볼륨·접근성·키 리맵·뉴스 자동 감속 On/Off) | Sprint 9 | 📋 Planned (Sprint 8에서 이월 — B-12 우선) |
| B-10 | UI 실 에셋 완성 (spinner_ring, start_bg) | Sprint 8 | ✅ Done (2026-04-15 — SVG 생성 + Godot 임포트 완료) |
| B-11 | 오더북 구현 (`order-book.md` In Review, 코드 없음) — 호가창 + 슬리피지 + 가격 영향 모델 전환 | Sprint 8 | ✅ Done (2026-04-17 — S8-01 + Korean HTS UI) |
| B-12 | 라이프스타일 소비 시스템 (`lifestyle-spending.md` In Review) — LifestyleManager 구현 + 매일 소비 화면 | Sprint 8 | ✅ Done (2026-04-17 — S8-06, 매일 장 마감 후 소비 화면으로 변경) |
| B-13 | 수익 실현 팡파레 (`profit-celebration.md` Draft) — GDD 완성 + 이펙트 4등급 구현 | Sprint 10 | 📋 Planned |

---

## Sprint 계획 개요

| Sprint | 기간 | 포커스 | Must Have |
|--------|------|--------|-----------|
| 7 | 2026-04-15 ~ 2026-04-28 | TR2 + F3 성장화면 | S6-07이월(TR2 GDD) + B-01(TR2 구현) + B-03(F3 GDD+구현) + B-04(Phase3 스킬 UI) |
| 8 | 2026-04-29 ~ 2026-05-12 | A3 + S3 루머 + 오더북 + 라이프스타일 | B-06(A3 재무제표) + B-07a(S3 루머) + B-11(오더북) + B-12(라이프스타일) + B-02(주거시각화, Should Have) |
| 9 | 2026-05-13 ~ 2026-05-26 | TR3 + TR4 + 설정화면 | B-07b(TR3 공매도) + B-07c(TR4 레버리지) + B-09(설정화면, Sprint 8 이월) |
| 10 | 2026-05-27 ~ 2026-06-09 | P3 + 팡파레 + Beta 마감 | B-08(P3 섹터ETF) + B-13(팡파레) + 3시즌 E2E QA + Beta DoD 정리 |

> **조건부 항목**: B-05(코어 SFX), B-10(UI 에셋)은 파일 수령 즉시 해당 스프린트에 편입.
>
> **스프린트 조정 이력**:
> - 2026-04-15: 주거 아트 에셋 전체(11개) 수령 완료 → B-02 Sprint 9→8 (Should Have), B-12 Sprint 9→8 (Must Have), B-09 설정화면 Sprint 8→9 이월.
>
> **미구현 GDD 편입 현황** (2026-04-15 감사):
> - B-11 `order-book.md` (In Review, 코드 없음) → Sprint 8 Must Have ✅
> - B-12 `lifestyle-spending.md` (In Review, GDD 완성) → Sprint 8 Must Have (아트 수령으로 조건 충족)
> - B-13 `profit-celebration.md` (Draft) → Sprint 10 Must Have
> - `growth-screen.md` → B-03 (Sprint 7, 기존 포함) ✅
> - `stop-loss-take-profit.md` → B-01 (Sprint 7, 기존 포함) ✅

---

## Tech Debt (Beta에서 처리)

| ID | 내용 | Sprint | Status |
|----|------|--------|--------|
| ~~TD-04~~ | ~~God Object 분리~~ — Sprint 4 완결 | — | ✅ Done |
| B-05 코어 SFX | programmatic SFX → 실 에셋 파일 교체 | 파일 수령 후 | 📋 가이드 완성 (DOWNLOAD_GUIDE S-11~S-14) |
| UI 에셋 TODO | `saving_overlay.gd` spinner_ring TextureRect | Sprint 7 | 📋 Planned (사용자 작업 조건) |

---

## Deferred to Full Release

- 튜토리얼 시스템
- 설정 화면 완성 (기본 볼륨/접근성만 Beta에서)
- 온라인 리더보드
- Steam 빌드 + 플랫폼 인증
- 시즌 테마 3종

---

## Definition of Done

- [ ] B-01~B-04 전부 완료
- [ ] 14개 스킬 Phase 1~4 전부 해금 가능
- [ ] 빌드: `--export-release` 성공 + SCRIPT ERROR 없음
- [ ] 3시즌 플레이 → 저장 → 재로드 E2E 수동 통과
- [ ] 이중 승리 조건(cash_assets ≥ 1,000억 OR total_assets ≥ 1조) 각 경로 수동 검증 — QA Lead 서명
- [ ] 가격 정찰 익스플로잇 차단 확인: 동일 세이브 5회 로드 → 가격 시퀀스 다름 확인 — QA Lead 서명
- [ ] 기존 테스트 전부 통과 + 신규 테스트 추가
- [ ] QA Lead 서명
- [ ] `production/milestones/beta.md` Status → Closed
