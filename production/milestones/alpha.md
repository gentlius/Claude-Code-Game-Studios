# Milestone: Alpha

> **Status**: Closed
> **Started**: 2026-04-07
> **Closed**: 2026-04-14
> **Previous**: Vertical Slice (Closed 2026-04-06)

## Goal

V-Slice에서 검증된 코어 루프 위에 **플레이어 경험 완성도**를 쌓는다.
처음 실행하는 플레이어가 "게임이 만들어진 느낌"을 받을 수 있는 상태.
세이브/로드로 중단 후 재개가 가능하고, 오디오가 있으며,
도입부 서사가 세계관을 전달하고, AI가 현실적인 자본 구조를 반영한다.

**Alpha 판정 기준**: "처음 해보는 사람이 30분 플레이 후 저장하고 나갔다가 돌아올 수 있는가"

## Success Criteria

- [x] 세이브 → 종료 → 로드 → 재개가 E2E로 동작한다 (XP/레벨/스킬/시즌 상태 복원) — 수동 통과 2026-04-09
- [x] 주문 체결·레벨업·VI 발동·뉴스 알림 4개 SFX 인게임 발동 확인 (2026-04-07)
- [x] 최초 실행 시 인트로 서사 5장 카드가 표시된다 (2026-04-07)
- [x] AI 티어 파라미터가 "티어 = 자본, 실력 ≠ 티어" 모델로 조정된다 ✅ (2026-04-06 완료)
- [ ] 기존 테스트 전부 통과 + 신규 테스트 추가
- [x] `--export-release` 빌드 성공 (2026-04-09, SCRIPT ERROR 없음)

## Alpha Systems

| # | System | Sprint | Status |
|---|--------|--------|--------|
| A-01 | 세이브/로드 시스템 | Sprint 5 | ✅ Done (2026-04-07) |
| A-02 | 오디오 기반 (AudioManager + SFX 4종) | Sprint 5 | ✅ Done (2026-04-07) |
| A-03 | 인트로 서사 (슬라이드 카드 5장) | Sprint 5 | ✅ Done (2026-04-07) |
| A-04 | AI 티어 파라미터 재설계 (자본 모델) | Sprint 5 | ✅ Done (2026-04-06) |
| A-05a | 주거 배경 아트 제작 (브론즈·다이아 2장) | Sprint 5 | 🔲 Not Started |
| A-05b | 주거 시각화 시스템 (배경 전환 UI 통합) | Sprint 6 | 📋 Planned |
| A-06 | Phase 3–4 스킬 (TR2 손절/익절) | Sprint 6 | 📋 Planned |

## Tech Debt (Alpha에서 처리)

| ID | 내용 | Sprint | Status |
|----|------|--------|--------|
| TD-S5-03 | 차트 RSI/MACD 배열 재할당 제거 | Sprint 5 | ✅ Done (2026-04-07) |
| TD-S5-04 | 로컬라이제이션 기반 tr() 래핑 | Sprint 5 | ✅ Done (2026-04-07) |

## Deferred to Beta

- 주거 시각화 시스템 통합 + 전 티어 아트 (A-05b Sprint 6)
- 공매도 (TR3), 레버리지 (TR4)
- 시즌 테마 3종 (현재 단일 테마)
- 온라인 리더보드
- Steam 빌드

## Definition of Done

- [x] A-01~A-03 전부 완료
- [x] 빌드: `--export-release` 성공 + SCRIPT ERROR 없음 (2026-04-09)
- [x] 테스트: 전체 pass 243/243 (2026-04-14, S6-01 완료)
- [x] 최초 실행 → 인트로 → 1시즌 플레이 → 저장 → 재로드 E2E 수동 통과 (2026-04-09)
- [x] QA Lead 서명 — 내부 감사 2026-04-14 (build/windows/SeedMoney.exe, 125MB, SCRIPT ERROR 없음)
- [x] `production/milestones/alpha.md` Status → Closed (2026-04-14)
