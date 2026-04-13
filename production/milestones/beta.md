# Milestone: Beta

> **Status**: Planned
> **Starts**: 2026-05-05 (Sprint 7 시작, Alpha Closed 후)
> **Target**: 2026-06-01 (Sprint 8 종료, 조정 가능)
> **Previous**: Alpha (종료 예정 2026-05-04)

## Goal

Alpha에서 검증된 플레이어 경험 위에 **콘텐츠 완성도**를 쌓는다.
14개 스킬 전부 해금 가능 상태, 주거 시각화, 자동화 거래(손절/익절),
공매도·레버리지 기반을 갖추고, 처음 해보는 플레이어가
튜토리얼 없이도 3시즌 이상 플레이할 수 있는 상태.

**Beta 판정 기준**: "리그 1위를 목표로 3시즌을 플레이했을 때 막히는 지점이 없는가"

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

## Beta Systems (스프린트 배정)

| # | System | Sprint | Status |
|---|--------|--------|--------|
| B-01 | TR2 손절/익절 구현 | Sprint 7 | 📋 Planned |
| B-02 | A-05a/b 주거 아트 + 시각화 시스템 | Sprint 7 | 📋 Planned |
| B-03 | F3 성장 화면 GDD + 구현 | Sprint 7 | 📋 Planned |
| B-04 | Phase 3 스킬 UI (TR2 자동화 피드백) | Sprint 7 | 📋 Planned |
| B-05 | AudioManager 실 에셋 교체 (programmatic → 파일) | Sprint 7 | 📋 Planned (파일 수령 조건) |
| B-06 | A2 스킬 — 재무제표 (PER/PBR/ROE) A3 | Sprint 8 | 📋 Planned |
| B-07 | Phase 4 스킬 — S3 루머, TR3 공매도, TR4 레버리지 GDD + 구현 | Sprint 8 | 📋 Planned |
| B-08 | P3 섹터 ETF | Sprint 9 | 📋 Planned |
| B-09 | 설정 화면 (볼륨·접근성·키 리맵·**뉴스 자동 감속 On/Off**) | Sprint 8 | 📋 Planned |
| B-10 | UI 실 에셋 완성 (spinner_ring, start_bg) | Sprint 7 | 📋 Planned (사용자 작업 조건) |

---

## Tech Debt (Beta에서 처리)

| ID | 내용 | Sprint |
|----|------|--------|
| ~~TD-04~~ | ~~God Object 분리~~ — **Sprint 4에서 완결됨** (trading_screen.gd 586줄, 전 컴포넌트 분리 완료) | ✅ Done |
| AudioManager placeholder | 프로그래매틱 SFX → 실 에셋 파일 교체 | Sprint 7 |
| UI 에셋 TODO | `saving_overlay.gd` spinner_ring TextureRect | Sprint 7 |

---

## Deferred to Full Release

- 튜토리얼 시스템 (System 20)
- 설정 화면 완성 (System 21) — 기본 볼륨/접근성만 Beta에서
- 온라인 리더보드 (멀티플레이 인프라)
- Steam 빌드 + 플랫폼 인증
- 시즌 테마 3종 (현재 단일 테마)

---

## Definition of Done

- [ ] B-01~B-05 전부 완료
- [ ] 14개 스킬 Phase 1~4 전부 해금 가능
- [ ] 빌드: `--export-release` 성공 + SCRIPT ERROR 없음
- [ ] 3시즌 플레이 → 저장 → 재로드 E2E 수동 통과
- [ ] QA Lead 서명
- [ ] `production/milestones/beta.md` Status → Closed
