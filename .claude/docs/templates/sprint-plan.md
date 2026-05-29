# Sprint [N] — [Start Date] to [End Date]

## Sprint Goal

[One sentence: what does this sprint achieve toward the current milestone?]

## Milestone Context

- **Current Milestone**: [Name]
- **Milestone Deadline**: [Date]
- **Sprints Remaining**: [N]

## Capacity

- **Total days**: [X]
- **Buffer (20%)**: [Y days reserved for unplanned work]
- **Available**: [Z days]

## Tasks

### Must Have (Critical Path)

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria | Status |
|----|------|-------------|-----------|-------------|-------------------|--------|
| S[N]-001 | | | | None | | Not Started |
| S[N]-002 | | | | S[N]-001 | | Not Started |

### Should Have

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria | Status |
|----|------|-------------|-----------|-------------|-------------------|--------|
| S[N]-010 | | | | | | Not Started |

### Nice to Have (Cut First)

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria | Status |
|----|------|-------------|-----------|-------------|-------------------|--------|
| S[N]-020 | | | | | | Not Started |

## Carryover from Sprint [N-1]

| Original ID | Task | Reason for Carryover | New Estimate | Priority Change |
|------------|------|---------------------|-------------|----------------|

## Risks to This Sprint

| Risk | Probability | Impact | Mitigation | Owner |
|------|------------|--------|-----------|-------|

## External Dependencies

| Dependency | Status | Impact if Delayed | Contingency |
|-----------|--------|------------------|-------------|

## Definition of Done

- [ ] All Must Have tasks completed
- [ ] All tasks pass acceptance criteria
- [ ] QA plan exists (`production/qa/qa-plan-sprint-[N].md`)
- [ ] All Logic/Integration stories have passing unit/integration tests
- [ ] Smoke check passed (`/smoke-check sprint`)
- [ ] QA sign-off report: APPROVED or APPROVED WITH CONDITIONS (`/team-qa sprint`)
- [ ] No S1 or S2 bugs in delivered features
- [ ] Code reviewed and merged to develop (Code Review Checklist "GDD 동기화" 4항목 + "ADR 동기화" 4항목 통과)
- [ ] **이 스프린트에서 구현된 모든 시스템의 GDD Status = Approved** (미완이면 In Review + 미완 항목 명시)
- [ ] **이 스프린트에서 내린 아키텍처 결정이 모두 ADR로 작성됨** (Technical Director 서명)
- [ ] Test cases written and executed for all new features
- [ ] Asset naming and format standards met
- [ ] `--export-release` 빌드 성공 + SCRIPT ERROR 없음. QA Lead 서명.

