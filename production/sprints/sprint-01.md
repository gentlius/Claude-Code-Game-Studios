# Sprint 1 — 2026-04-01 to 2026-04-14

## Sprint Goal

MVP 보강(VI/서킷브레이커, 지수 HUD, 테스트 환경)을 완료하고,
V-Slice의 첫 두 시스템(AI 경쟁자, 경험치)을 설계+구현하여
"경쟁 상대가 있는 투자 게임" 형태를 만든다.

## Capacity

- Total sessions: 10
- Buffer (20%): 2 sessions (버그 수정, 예기치 않은 작업)
- Available: 8 sessions

## Tasks

### Must Have (Critical Path)

| ID | Task | Category | Est. | Dependencies | Acceptance Criteria |
|----|------|----------|------|-------------|-------------------|
| S1-01 | VI(변동성완화장치) 구현 | Gameplay | 1 sess | GDD 완료 | 종목 ±10% 도달 시 8틱 거래정지, 일 2회 제한, 뉴스 생성 |
| S1-02 | 서킷브레이커 구현 | Gameplay | 0.5 sess | S1-01 | 지수 -8% → 20틱 전종목 정지, -15% → 조기 마감, 뉴스 생성 |
| S1-03 | 시장 지수 HUD 표시 | UI | 0.5 sess | — | 상단 상태바에 종합지수 + 등락률 표시 |
| S1-04 | AI 경쟁자 시스템 GDD 작성 | Design | 1 sess | — | 8섹션 완료, /design-review APPROVED |
| S1-05 | AI 경쟁자 시스템 구현 | Gameplay | 2 sess | S1-04 | 3~5 AI 트레이더가 독립적으로 매매, 포트폴리오 추적 가능 |
| S1-06 | 경험치 시스템 GDD 작성 | Design | 0.5 sess | — | 8섹션 완료, /design-review APPROVED |
| S1-07 | 경험치 시스템 구현 | Gameplay | 1 sess | S1-06 | 거래/수익률 기반 XP 산출, 레벨업 시그널 |

### Should Have

| ID | Task | Category | Est. | Dependencies | Acceptance Criteria |
|----|------|----------|------|-------------|-------------------|
| S1-08 | GUT 테스트 프레임워크 설치 | Infra | 0.5 sess | — | `gut_cmdln.gd` 실행으로 기존 유닛 테스트 통과 |
| S1-09 | VI/CB 유닛 테스트 | Test | 0.5 sess | S1-01, S1-02, S1-08 | VI 발동/해제, CB 단계별 발동 테스트 통과 |
| S1-10 | 호가 단위 유닛 테스트 | Test | 0.5 sess | S1-08 | 7가격대별 tick_size, round_to_tick 검증 |

### Nice to Have

| ID | Task | Category | Est. | Dependencies | Acceptance Criteria |
|----|------|----------|------|-------------|-------------------|
| S1-11 | ADR 추가 (호가 단위, 에너지-거래량) | Docs | 0.5 sess | — | docs/architecture/에 ADR 2개 추가 |
| S1-12 | 프로토타입 README 작성 | Docs | 0.25 sess | — | prototypes/price-engine/README.md 존재 |

## Carryover from Previous Sprint

없음 (첫 스프린트)

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| AI 경쟁자 설계가 복잡해져 2세션 초과 | Medium | High | MVP 수준 AI(랜덤+규칙 기반)로 범위 제한. 학습형 AI는 후속 스프린트 |
| VI/CB가 기존 가격 엔진과 충돌 | Low | Medium | 가격 엔진 GDD에 이미 설계 포함. 시그널 기반 분리 |
| GUT 설치 시 Godot 4.6 호환 문제 | Low | Low | GUT 최신 버전 확인. 실패 시 커스텀 테스트 러너 유지 |

## Dependencies on External Factors

- GUT 프레임워크의 Godot 4.6 호환성 (외부 addon)

## Definition of Done for this Sprint

- [ ] Must Have 7개 태스크 전부 완료
- [ ] VI/CB 발동 시 뉴스 생성 확인
- [ ] AI 경쟁자가 시즌 동안 매매하고 포트폴리오 변동 확인
- [ ] 경험치가 거래 시 증가하는 것 확인
- [ ] 헤드리스 테스트 통과 (기존 + 신규)
- [ ] GDD 업데이트 완료 (변경사항 반영)
- [ ] 코드 커밋 완료
