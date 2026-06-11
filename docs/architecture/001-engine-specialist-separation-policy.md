# ADR-0001: Engine Specialist Separation Policy

## Status

Accepted

## Date

2026-06-11

## Last Verified

2026-06-11

## Decision Makers

- technical-director (recommended)
- user (gentlius) — approved during HTML5/PixiJS engine family addition session

## Summary

Defines when an engine family adds a separate language-quality specialist agent vs absorbs language quality into the framework primary. Policy: separate specialist only when **multiple distinct languages co-exist within the same project**; absorb when **a single language is the de-facto framework requirement**. This codifies the choice made when adding the HTML5 engine family (TypeScript absorbed into `pixijs-specialist`) and retroactively explains the Godot vs Unity/Unreal asymmetry.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | All (cross-engine framework policy) |
| **Domain** | Core (agent architecture) |
| **Knowledge Risk** | LOW — this is a framework policy, not engine API |
| **References Consulted** | Existing agent files under `.claude/agents/` (godot-*, unity-*, ue-*, html5-*) |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None — policy adherence verified by agent file inventory |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | Future engine family additions can apply this policy mechanically |
| **Blocks** | None |
| **Ordering Note** | First ADR in CCGS framework; sets precedent for agent architecture decisions |

## Context

### Problem Statement

When adding a new engine family to the CCGS framework, framework maintainers face a recurring decision: should language code quality (e.g., TypeScript review, GDScript style enforcement, C# idiom checks) get its own specialist agent, or be absorbed into the framework primary's responsibilities? Without a written policy, the choice has been made ad hoc — Godot has separate `godot-gdscript-specialist` and `godot-csharp-specialist`, while Unity has no `unity-csharp-specialist` and Unreal has no `unreal-cpp-specialist`. The asymmetry looks arbitrary to outside observers and provides no guidance for the next engine family.

### Current State

Existing CCGS agent composition (as of 2026-06-11):

| Engine | Primary | Language Specialist(s) | Reasoning (implicit) |
|--------|---------|------------------------|----------------------|
| Godot | `godot-specialist` | `godot-gdscript-specialist` + `godot-csharp-specialist` (separate) | Two distinct languages can co-exist in one Godot project |
| Unity | `unity-specialist` | None (C# absorbed into primary) | C# is the only Unity language; no alternative |
| Unreal | `unreal-specialist` | `ue-blueprint-specialist` (Blueprint only) | Blueprint is a distinct authoring surface (visual graphs) vs C++ text |
| HTML5 (proposed) | `html5-specialist` | `pixijs-specialist` (absorbs TS quality) | **Decision needed** — proposed below |

The HTML5 family addition forced an explicit decision: separate `typescript-game-specialist` (6 agents) vs absorb TS into `pixijs-specialist` (5 agents).

### Constraints

- Adding agents has marginal cost: ~150 lines per agent file, routing table maintenance, user mental load remembering which specialist owns which file extension
- Agent overlap creates ownership ambiguity (two specialists fighting over the same `.ts` file)
- Framework precedent should be self-consistent — outside contributors expect future engine additions to follow a predictable rule

### Requirements

- A single, technically-grounded rule that determines specialist separation for any future engine family
- Rule must retroactively explain existing Godot/Unity/Unreal asymmetry
- Rule must mechanically resolve the HTML5 TS specialist question
- Rule must not produce absurd outcomes for hypothetical future engines (e.g., a hypothetical Bevy/Rust addition)

## Decision

**Engine Specialist Separation Rule**:

> A language-quality specialist agent is created **only when** an engine family routinely supports **two or more distinct, structurally different languages within the same project**. Otherwise, language quality is absorbed into the framework primary specialist.

### Mechanical Application

| Engine | Languages | Co-existence in one project? | Verdict |
|--------|-----------|------------------------------|---------|
| Godot | GDScript + C# | Yes (`.gd` + `.cs` in same project, ~normal) | **Separate** specialists per language |
| Unity | C# | No (single language) | **Absorbed** into `unity-specialist` |
| Unreal | C++ + Blueprint | Yes (text + visual graphs are structurally different) | **Separate** `ue-blueprint-specialist` for Blueprint; C++ absorbed into `unreal-specialist` |
| HTML5 | TypeScript (or JS) | No (one language identity per project) | **Absorbed** into `pixijs-specialist` |

### Definition of "Structurally Different"

Two languages are structurally different if:
1. They have **different file extensions** AND
2. They have **different authoring surfaces** (text vs visual graph vs DSL) OR **different runtime targets** (managed vs native vs DOM)

C++ and C# both being "text-based imperative typed" languages does NOT, by itself, force separation. What matters is whether a *single project* uses both for non-overlapping reasons.

### Boundary Cases Resolved

- **HTML5 with TypeScript vs Vanilla JS**: These are NOT considered co-existing — a project picks one language identity (per Appendix B1 guardrail in setup-engine SKILL.md). Therefore single language → absorbed.
- **Future Bevy/Rust engine**: Single language (Rust) → absorbed. Primary `bevy-specialist` covers Rust idiom.
- **Future engine with native + scripting (e.g., Lua + C++ in Solar2D)**: Two structurally different languages → separate specialists.

## Consequences

### Positive

- New engine family additions become mechanical decisions, not committee debates
- Asymmetry between existing engines is now justified by a written rule rather than apparent arbitrariness
- Agent count grows linearly with genuine complexity, not with engine count
- Outside contributors can predict the agent composition before reading individual agent files

### Negative

- A future case may emerge where the rule produces a result that "feels wrong" — the rule is heuristic, not algorithmic. In that case: write a new ADR superseding this one, don't quietly violate.
- The rule does not cover non-language specialist separation (shader specialist, build specialist, etc.) — those decisions remain per-engine.

### Neutral

- This ADR is meta: it governs the framework's own architecture, not any game's runtime architecture. It will be referenced by future engine-addition PRs.

## Alternatives Considered

### Alternative 1: Always Separate (Strict Decomposition)

Every engine family gets a separate language specialist regardless of co-existence.

- **Pro**: Maximum consistency.
- **Con**: Inflates agent count for no benefit; unity-csharp-specialist would be functionally identical to unity-specialist; user confusion about which to invoke.
- **Verdict**: Rejected — adds cost without benefit.

### Alternative 2: Always Absorb (Minimum Decomposition)

Every engine family has only a primary specialist; language quality always absorbed.

- **Pro**: Smallest framework.
- **Con**: Cannot route `.gd` vs `.cs` files in a Godot project that uses both — primary can't be specialized for both at once.
- **Verdict**: Rejected — breaks the Godot dual-language case which is a legitimate real-world configuration.

### Alternative 3: Case-by-Case (No Rule)

Continue making the decision per engine family with no written policy.

- **Pro**: Maximum flexibility.
- **Con**: This is the current state and is what created the asymmetry concern in the first place.
- **Verdict**: Rejected — rule must exist to prevent ad hoc accumulation.

## Implementation

This ADR is implemented by the existing agent inventory at the time of writing. No code changes required. Future engine family additions must:

1. Apply the rule mechanically in their setup-engine extension
2. Document the language co-existence assessment in the engine's `VERSION.md` or `current-best-practices.md`
3. Reference this ADR in the new engine's setup-engine appendix

## References

- HTML5 engine family addition session (2026-06-11) — origin of this ADR
- Existing agent files under `.claude/agents/` — empirical inputs
- `.claude/skills/setup-engine/SKILL.md` Appendix A (Godot variants) and Appendix B (HTML5 variants) — applied examples
