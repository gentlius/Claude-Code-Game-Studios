# Claude Code Game Studios -- Game Studio Agent Architecture

Indie game development managed through 49 coordinated Claude Code subagents.
Each agent owns a specific domain, enforcing separation of concerns and quality.

## Technology Stack

- **Engine**: [CHOOSE: Godot 4 / Unity / Unreal Engine 5]
- **Language**: [CHOOSE: GDScript / C# / C++ / Blueprint]
- **Version Control**: Git with trunk-based development
- **Build System**: [SPECIFY after choosing engine]
- **Asset Pipeline**: [SPECIFY after choosing engine]

> **Note**: Engine-specialist agents exist for Godot, Unity, and Unreal with
> dedicated sub-specialists. Run `/setup-engine` to pin the engine and unblock
> the matching specialist set.

## Project Structure

@.claude/docs/directory-structure.md

## Engine Version Reference

<!-- `/setup-engine` activates this @include with the chosen engine's VERSION.md.
     Available: docs/engine-reference/{godot,unity,unreal}/VERSION.md -->
<!-- @docs/engine-reference/godot/VERSION.md -->

## Technical Preferences

@.claude/docs/technical-preferences.md

## Coordination Rules

@.claude/docs/coordination-rules.md

## Collaboration Protocol

**User-driven collaboration, not autonomous execution.**
Every task follows: **Question -> Options -> Decision -> Draft -> Approval**

- Agents MUST ask "May I write this to [filepath]?" before using Write/Edit tools
- Agents MUST show drafts or summaries before requesting approval
- Multi-file changes require explicit approval for the full changeset
- No commits without user instruction

See `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md` for full protocol and examples.

## Escalation Policy

Not every decision requires user input. Use this table to determine who decides:

| Level | Decision Owner | Examples |
|-------|---------------|---------|
| **Team Autonomous** | Director Group 11인이 내부 결정 (Tier 1: creative-director · technical-director · producer / Tier 2: game-designer · lead-programmer · art-director · audio-director · narrative-director · qa-lead · release-manager · localization-lead) | Scene structure, UI layout options, tech implementation choices, formula details, edge case handling |
| **Report to User** | Team resolves, then summarizes outcome | Cross-domain conflicts, decisions affecting multiple GDDs simultaneously, design review findings |
| **User Decision Required** | Must escalate to user | Core game concept changes, scope expansion/reduction, monetization direction, narrative pillars, any decision that changes what the game fundamentally is |

**Rule**: If two or more director-level agents can resolve a question by consulting each other, they MUST do so before escalating to the user. Only escalate when the team is genuinely split or the decision exceeds team authority.

> **First session?** If the project has no engine configured and no game concept,
> run `/start` to begin the guided onboarding flow.

## Auto-Resume Protocol

세션 시작 또는 컴팩션 후 `active.md` 에 `STATUS: IN PROGRESS` 항목이 있으면:

### 사용자가 새 작업(Task B)을 지시한 경우

1. **Task B 먼저 실행** (사용자의 현재 지시가 우선)
2. Task B 완료 후 → "Task A(이전 미완 작업)를 이어서 진행합니다" 고지
3. Task A 재개 → 완결까지 반복

단, Task B가 Task A를 무효화하거나 대체하는 경우 Task A를 폐기하고 사용자에게 알린다.

### 사용자가 새 작업 없이 세션만 재개한 경우 (예: "안녕", "계속해")

1. 즉시 Task A NEXT 항목부터 재개 — 사용자 재지시 불필요
2. 완결까지 반복

### active.md 없이 pre-compact 경고만 있는 경우

1. 수정 파일 목록으로 미완 작업 파악
2. `active.md` 작성
3. Task B가 있으면 Task B 먼저 → Task A 재개. 없으면 즉시 Task A 재개.

**리뷰 작업 (코드 리뷰 / GDD 리뷰 / 디자인 리뷰)은 반드시 active.md 작성 후 시작한다.**
컨텍스트 한계로 중단되더라도 active.md → AUTO-RESUME 메커니즘으로 완결까지 반복 진행한다.

## Coding Standards

@.claude/docs/coding-standards.md

## Studio Template Promotion

각 프로젝트에서 얻은 skill·규칙·메모리·agent 수정 중 스튜디오 템플릿으로
역전파할 가치가 있는 자산은 `/studio-promote`로 평가하고 승격한다.
판단 기준(G1~G6 게이트, anti-promotion signal, 프로세스)은 아래 문서가 단일 권위다.

@.claude/docs/studio-promotion-criteria.md

## Context Management

@.claude/docs/context-management.md
