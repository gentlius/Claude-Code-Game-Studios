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
| B-01 | TR2 손절/익절 구현 | Sprint 7 | 📋 Planned |
| B-02 | A-05a/b 주거 아트 + 시각화 시스템 | Sprint 9 | 📋 Planned (아트 에셋 사용자 작업 조건) |
| B-03 | F3 성장 화면 GDD + 구현 | Sprint 7 | 📋 Planned |
| B-04 | Phase 3 스킬 UI (TR2 자동화 피드백) | Sprint 7 | 📋 Planned |
| B-05 | AudioManager 코어 SFX 교체 (sfx_order_filled/level_up/vi_alert/news_alert) | Sprint 7~10 | 📋 Planned (파일 수령 조건, DOWNLOAD_GUIDE S-11~S-14 참조) |
| B-06 | A3 재무제표 (PER/PBR/ROE) GDD + 구현 | Sprint 8 | 📋 Planned |
| B-07a | S3 루머 채널 GDD + 구현 | Sprint 8 | 📋 Planned |
| B-07b | TR3 공매도 GDD + 구현 | Sprint 9 | 📋 Planned |
| B-07c | TR4 레버리지 GDD + 구현 | Sprint 9 | 📋 Planned |
| B-08 | P3 섹터 ETF GDD + 구현 | Sprint 10 | 📋 Planned |
| B-09 | 설정 화면 (볼륨·접근성·키 리맵·뉴스 자동 감속 On/Off) | Sprint 8 | 📋 Planned |
| B-10 | UI 실 에셋 완성 (spinner_ring, start_bg) | Sprint 7 | 📋 Planned (사용자 Figma 작업 조건) |

---

## Sprint 계획 개요

| Sprint | 기간 | 포커스 | Must Have |
|--------|------|--------|-----------|
| 7 | 2026-04-15 ~ 2026-04-28 | TR2 + F3 성장화면 | S6-07이월(TR2 GDD) + B-01(TR2 구현) + B-03(F3 GDD+구현) + B-04(Phase3 스킬 UI) |
| 8 | 2026-04-29 ~ 2026-05-12 | A3 + S3 루머 | B-06(A3 재무제표) + B-07a(S3 루머) + B-09(설정화면) |
| 9 | 2026-05-13 ~ 2026-05-26 | TR3 + TR4 + 주거시각화 | B-07b(TR3 공매도) + B-07c(TR4 레버리지) + B-02(주거시각화, Should Have, 아트 조건부) |
| 10 | 2026-05-27 ~ 2026-06-09 | P3 + Beta 마감 | B-08(P3 섹터ETF) + 3시즌 E2E QA + Beta DoD 정리 |

> **조건부 항목**: B-02(주거시각화 Sprint 9 Should Have), B-05(코어 SFX), B-10(UI 에셋)은 사용자 자산 수령 즉시 해당 스프린트에 편입. B-02는 3시즌 리텐션 핵심 — 아트 에셋 최대한 빨리 수령 권장.

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
- [ ] 기존 테스트 전부 통과 + 신규 테스트 추가
- [ ] QA Lead 서명
- [ ] `production/milestones/beta.md` Status → Closed
