# Agent Coordination Rules

## Director Group (Tier 1 + Tier 2 전원)

스프린트 자율 의사결정 권한을 가진 11인 그룹. 유저 에스컬레이션 없이 팀 내부에서 결정하고 실행한다.

| 에이전트 | 티어 | 도메인 |
|---------|------|--------|
| `creative-director` | 1 | 크리에이티브 비전, 방향 충돌 중재 |
| `technical-director` | 1 | 기술 아키텍처, 기술 충돌 중재 |
| `producer` | 1 | 제작 관리, 부서 간 조율 |
| `game-designer` | 2 | 게임 설계, 밸런스 |
| `lead-programmer` | 2 | 코드 아키텍처, 코드 리뷰 |
| `art-director` | 2 | 비주얼 방향, 에셋 기준 |
| `audio-director` | 2 | 오디오 방향, 사운드 설계 |
| `narrative-director` | 2 | 스토리, 세계관, 대화 |
| `qa-lead` | 2 | 품질보증, 테스트 전략, **빌드 검증** |
| `release-manager` | 2 | 빌드/배포, 버전 관리 |
| `localization-lead` | 2 | 국제화, 문자열 관리 |

**QA Lead 추가 원칙**: 모든 기능 구현 후 실행 가능한 빌드 검증 필수. "실행해봤냐?"를 Done 기준에 포함.

---

## Producer 운영 규칙 (위반 시 마일스톤/스프린트 마감 불가)

### P-RULE-01: DoD 즉시 체크
작업 완료를 확인한 그 자리에서 해당 스프린트 DoD 항목을 `[x]`로 업데이트하고 커밋한다.
세션 말미에 몰아서 처리하면 안 된다. 확인 → 체크 → 커밋이 하나의 원자적 행동이다.

**위반 증상**: "이미 다 했는데 다음 세션에 또 `[ ]`로 남아있는" 항목이 생긴다.

### P-RULE-02: 마일스톤 마감 전 스프린트 DoD 교차 확인
마일스톤(milestone.md)을 Closed로 변경하기 전에, 해당 마일스톤을 담당하는 **모든 스프린트의 DoD가 전부 `[x]`** 인지 먼저 확인한다. 스프린트 DoD에 `[ ]` 항목이 하나라도 남아있으면 마일스톤 마감 불가.

**확인 순서**: `sprint-NN.md` DoD 전 항목 `[x]` 확인 → 그 다음에 `milestone.md` Status → Closed.

### P-RULE-03: 다음 스프린트 선행 조건 항목은 Nice-to-Have 분류 금지
스프린트 태스크의 AC 또는 설명에 "다음 스프린트 구현 선행 조건", "Sprint N+1 착수 전 필수" 등
다음 스프린트 의존성이 명시된 항목은 **Nice-to-Have로 분류할 수 없다.** 최소 Should Have, 실질적
블로커이면 Must Have로 분류한다.

**근거**: Nice-to-Have는 미완 시 이월이 허용된다. 그러나 다음 스프린트 착수를 막는 항목이
이월되면 다음 스프린트 첫 세션부터 블로킹 상태가 된다. 분류 시점에 의존성을 확인하여
우선순위를 올바르게 결정한다.

---

1. **Vertical Delegation**: Leadership agents delegate to department leads, who
   delegate to specialists. Never skip a tier for complex decisions.
2. **Horizontal Consultation**: Agents at the same tier may consult each other
   but must not make binding decisions outside their domain.
3. **Conflict Resolution**: When two agents disagree, escalate to the shared
   parent. If no shared parent, escalate to `creative-director` for design
   conflicts or `technical-director` for technical conflicts.
4. **Change Propagation**: When a design change affects multiple domains, the
   `producer` agent coordinates the propagation.
5. **No Unilateral Cross-Domain Changes**: An agent must never modify files
   outside its designated directories without explicit delegation.

## Model Tier Assignment

Skills and agents are assigned to model tiers based on task complexity:

| Tier | Model | When to use |
|------|-------|-------------|
| **Haiku** | `claude-haiku-4-5-20251001` | Read-only status checks, formatting, simple lookups — no creative judgment needed |
| **Sonnet** | `claude-sonnet-4-6` | Implementation, design authoring, analysis of individual systems — default for most work |
| **Opus** | `claude-opus-4-6` | Multi-document synthesis, high-stakes phase gate verdicts, cross-system holistic review |

Skills with `model: haiku`: `/help`, `/sprint-status`, `/story-readiness`, `/scope-check`,
`/project-stage-detect`, `/changelog`, `/patch-notes`, `/onboard`

Skills with `model: opus`: `/review-all-gdds`, `/architecture-review`, `/gate-check`

All other skills default to Sonnet. When creating new skills, assign Haiku if the
skill only reads and formats; assign Opus if it must synthesize 5+ documents with
high-stakes output; otherwise leave unset (Sonnet).

## Subagents vs Agent Teams

This project uses two distinct multi-agent patterns:

### Subagents (current, always active)
Spawned via `Task` within a single Claude Code session. Used by all `team-*` skills
and orchestration skills. Subagents share the session's permission context, run
sequentially or in parallel within the session, and return results to the parent.

**When to spawn in parallel**: If two subagents' inputs are independent (neither
needs the other's output to begin), spawn both Task calls simultaneously rather
than waiting. Example: `/review-all-gdds` Phase 1 (consistency) and Phase 2
(design theory) are independent — spawn both at the same time.

### Agent Teams (experimental — opt-in)
Multiple independent Claude Code *sessions* running simultaneously, coordinated
via a shared task list. Each session has its own context window and token budget.
Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` environment variable.

**Use agent teams when**:
- Work spans multiple subsystems that will not touch the same files
- Each workstream would take >30 minutes and benefits from true parallelism
- A senior agent (technical-director, producer) needs to coordinate 3+ specialist
  sessions working on different epics simultaneously

**Do not use agent teams when**:
- One session's output is required as input for another (use sequential subagents)
- The task fits in a single session's context (use subagents instead)
- Cost is a concern — each team member burns tokens independently

**Current status**: Opt-in via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Document first usage here when adopted.

## Parallel Task Protocol

When an orchestration skill spawns multiple independent agents:

1. Issue all independent Task calls before waiting for any result
2. Collect all results before proceeding to dependent phases
3. If any agent is BLOCKED, surface it immediately — do not silently skip
4. Always produce a partial report if some agents complete and others block
