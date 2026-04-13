# Execution Plan — Alpha Close → Beta

**작성일**: 2026-04-07  
**기준**: Alpha 진행 중. Sprint 5 종료 기준 미완 항목 전수 조사 후 작성.

---

## 현재 상태 (2026-04-07 기준)

| 마일스톤 | 상태 |
|---------|------|
| MVP | ✅ Closed |
| V-Slice | ✅ Closed |
| **Alpha** | 🔄 In Progress (Sprint 6에서 종료 목표) |
| Beta | 📋 Planned (Sprint 7~8) |

---

## Sprint 6 (2026-04-21 ~ 05-04) — Alpha 종료

> 상세: `production/sprints/sprint-06.md`

| ID | 항목 | 분류 | 완료 기준 |
|----|------|------|---------|
| S6-01 | **Alpha E2E 재검증** — 신규 진입 흐름(SplashScreen→StartScreen→NewGame→Intro) + 멀티슬롯 세이브/로드 + SFX 4종 | Must | alpha.md Closed |
| S6-02 | **Phase 1 스킬 UI** — S1/S2 뉴스 배지, TR1 탭 비활성화, P1/P2 슬롯 카운터 | Must | 5개 항목 인게임 확인 |
| ~~S6-03~~ | ~~A2 RSI/MACD 차트 서브패널~~ | ✅ **이미 완료** | `chart_renderer.gd` `_draw_rsi()` / `_draw_macd()` 구현됨. Timer dangling만 S6-03에서 수정. |
| S6-04 | **코드 TODO + audit 버그** — 로고 TextureRect, settlement_reporter 레이스컨디션, xp_bar C-01 | Must | TODO 주석 제거 |
| S6-05 | **문서 스테일** — alpha.md·systems-index·tech-debt(TD-04 ✅)·sprint-05 일괄 업데이트 | Must | 5건 완료 |
| S6-07 | **스타트 스크린 오디오** S-01~06 연동 | Should | 파일 수령 조건부 |
| S6-08 | **TR2 손절/익절 GDD** 작성 | Nice | Sprint 7 구현 선행 조건 |

---

## Sprint 7 (2026-05-05 ~ 05-18) — Beta 1차

> 상세: `production/milestones/beta.md` → sprint-07.md 생성 예정

| ID | 항목 | 분류 | 비고 |
|----|------|------|------|
| S7-01 | **TR2 손절/익절 구현** | Must | S6-07 GDD 선행 조건 |
| S7-02 | **A-05a 주거 배경 아트** (브론즈·다이아 2장) | Must | AI 생성 or 스톡 |
| S7-03 | **A-05b 주거 시각화 시스템** — 티어별 배경 전환 UI | Must | S7-02 선행 조건 |
| S7-04 | **F3 성장 화면 GDD + 구현** | Must | GDD 작성 후 구현 |
| S7-05 | **AudioManager 실 에셋 교체** — programmatic → 실 SFX | Should | 파일 수령 조건부 |
| S7-06 | **UI 에셋 TODO** — spinner_ring TextureRect 연동, start_bg 교체 | Should | 사용자 Figma/AI 생성 조건부 |
| S7-07 | **Phase 3 스킬 UI** — TR2 자동화 체결 피드백 | Should | S7-01 선행 조건 |

---

## Sprint 8 (2026-05-19 ~ 06-01) — Beta 2차

| ID | 항목 | 분류 | 비고 |
|----|------|------|------|
| S8-01 | **A3 재무제표 스킬** — PER/PBR/ROE 종목 카드 표시 | Must | `stock-database.md` 확장 필요 |
| S8-02 | **TR3 공매도 GDD + 구현** | Must | Phase 4 |
| S8-03 | **TR4 레버리지 GDD + 구현** | Must | Phase 4, TR3 선행 조건 |
| S8-04 | **S3 루머 채널 스킬** — Stub → 구현 | Should | Phase 4 |
| S8-05 | **설정 화면** — 볼륨·접근성(reduced_motion)·키 리맵 기본 | Should | System 21 |
| S8-06 | **Beta E2E + QA 종료** — 3시즌 플레이 + 전 스킬 해금 경로 확인 | Must | beta.md Closed |

---

## Beta 이후 (Full Release)

| 항목 | 비고 |
|------|------|
| P3 섹터 ETF 스킬 | Phase 5 |
| A4 섹터 비교 분석 스킬 | Phase 5 |
| 튜토리얼 시스템 | System 20 |
| 온라인 리더보드 | 멀티플레이 인프라 필요 |
| Steam 빌드 + 플랫폼 인증 | 릴리즈 매니저 |
| 시즌 테마 3종 | 현재 단일 테마 |

---

## 에셋 수령 필요 항목 (사용자 작업)

| 에셋 | 용도 | 가이드 | 목표 스프린트 |
|------|------|--------|-------------|
| `bgm_start_screen.ogg` | StartScreen BGM | `assets/audio/DOWNLOAD_GUIDE.md` ID:155139 | S6 (S6-07 조건) |
| `sfx_logo_sting.ogg` | SplashScreen | DOWNLOAD_GUIDE ID:335860 (CC BY 4.0) | S6 (S6-07 조건) |
| `sfx_save_complete.ogg` | SavingOverlay | DOWNLOAD_GUIDE ID:452998 | S6 (S6-07 조건) |
| `sfx_slot_select.ogg` | StartScreen | DOWNLOAD_GUIDE ID:677860 | S6 (S6-07 조건) |
| `sfx_slot_hover.ogg` | StartScreen | DOWNLOAD_GUIDE ID:448086 | S6 (S6-07 조건) |
| `sfx_delete_confirm.ogg` | StartScreen | DOWNLOAD_GUIDE ID:445976 | S6 (S6-07 조건) |
| `spinner_ring.png` (48×48) | SavingOverlay | Figma 원형 stroke #ebebeb | Sprint 7 |
| `start_bg.png` (1920×1080) | StartScreen 배경 | `asset-plan.md` A-02 AI 생성 프롬프트 | Sprint 7 |
