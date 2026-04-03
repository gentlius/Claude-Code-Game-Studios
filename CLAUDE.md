# Claude Code Game Studios -- Game Studio Agent Architecture

Indie game development managed through 48 coordinated Claude Code subagents.
Each agent owns a specific domain, enforcing separation of concerns and quality.

## Technology Stack

- **Engine**: Godot 4.6
- **Language**: GDScript (primary), C++ via GDExtension (performance-critical)
- **Version Control**: Git with trunk-based development
- **Build System**: SCons (engine), Godot Export Templates
- **Asset Pipeline**: Godot Import System + custom resource pipeline

> **Note**: Engine-specialist agents exist for Godot, Unity, and Unreal with
> dedicated sub-specialists. Use the set matching your engine.

## Project Structure

@.claude/docs/directory-structure.md

## Engine Version Reference

@docs/engine-reference/godot/VERSION.md

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
| **Team Autonomous** | Director agents decide internally (TD, UX, Game Designer, etc.) | Scene structure, UI layout options, tech implementation choices, formula details, edge case handling |
| **Report to User** | Team resolves, then summarizes outcome | Cross-domain conflicts, decisions affecting multiple GDDs simultaneously, design review findings |
| **User Decision Required** | Must escalate to user | Core game concept changes, scope expansion/reduction, monetization direction, narrative pillars, any decision that changes what the game fundamentally is |

**Rule**: If two or more director-level agents can resolve a question by consulting each other, they MUST do so before escalating to the user. Only escalate when the team is genuinely split or the decision exceeds team authority.

> **First session?** If the project has no engine configured and no game concept,
> run `/start` to begin the guided onboarding flow.

## Coding Standards

@.claude/docs/coding-standards.md

## Context Management

@.claude/docs/context-management.md
