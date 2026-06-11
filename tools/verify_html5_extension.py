#!/usr/bin/env python3
"""
Structural + technical verification of the HTML5/PixiJS engine family extension.
Runs checks 1+2 from the verification plan. Designed to be re-runnable.
"""

import re
import sys
from pathlib import Path

CCGS = Path("d:/developer/github.com/Claude-Code-Game-Studios")
BAGEL = Path("d:/developer/github.com/BagelMVP")

NEW_AGENTS = [
    "html5-specialist",
    "pixijs-specialist",
    "webgl-shader-specialist",
    "web-build-specialist",
    "playwright-e2e-specialist",
]

HTML5_REF_ROOT = CCGS / "docs" / "engine-reference" / "html5"

issues = []  # (severity, file, message)
checks_passed = 0
checks_total = 0


def check(name, ok, detail=""):
    global checks_passed, checks_total
    checks_total += 1
    if ok:
        checks_passed += 1
        print(f"  PASS  {name}")
    else:
        issues.append(("FAIL", name, detail))
        print(f"  FAIL  {name}: {detail}")


def warn(name, detail):
    issues.append(("WARN", name, detail))
    print(f"  WARN  {name}: {detail}")


# ---------------------------------------------------------------------------
# 1A. YAML frontmatter validation on 5 new agent files
# ---------------------------------------------------------------------------
print("\n=== 1A. Agent YAML frontmatter ===")

REQUIRED_FIELDS = ["name", "description", "tools", "model"]
ALLOWED_MODELS = {"sonnet", "opus", "haiku"}

for agent in NEW_AGENTS:
    p = CCGS / ".claude" / "agents" / f"{agent}.md"
    if not p.exists():
        check(f"{agent}.md exists", False, str(p))
        continue
    text = p.read_text(encoding="utf-8")
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    if not m:
        check(f"{agent} frontmatter delimited", False, "no `---` block")
        continue
    fm = m.group(1)
    fields = {}
    for line in fm.split("\n"):
        if not line.strip() or line.strip().startswith("#"):
            continue
        if ":" not in line:
            continue
        k, _, v = line.partition(":")
        fields[k.strip()] = v.strip().strip('"')
    missing = [f for f in REQUIRED_FIELDS if f not in fields]
    check(f"{agent} required fields present", not missing, f"missing: {missing}")
    if "name" in fields:
        check(f"{agent} frontmatter name matches filename", fields["name"] == agent,
              f"frontmatter name={fields.get('name')} vs filename={agent}")
    if "model" in fields:
        check(f"{agent} model is valid", fields["model"] in ALLOWED_MODELS,
              f"model={fields['model']} not in {ALLOWED_MODELS}")

# ---------------------------------------------------------------------------
# 1B. BagelMVP agent files match (copied)
# ---------------------------------------------------------------------------
print("\n=== 1B. BagelMVP agent copies ===")
for agent in NEW_AGENTS:
    bp = BAGEL / ".claude" / "agents" / f"{agent}.md"
    check(f"BagelMVP/{agent}.md exists", bp.exists(), str(bp))

# ---------------------------------------------------------------------------
# 1C. engine-reference/html5 files exist (5 root + 9 modules = 14)
# ---------------------------------------------------------------------------
print("\n=== 1C. engine-reference/html5 file inventory ===")
expected_roots = ["VERSION.md", "breaking-changes.md", "deprecated-apis.md",
                  "current-best-practices.md", "PLUGINS.md"]
expected_modules = ["rendering.md", "input.md", "audio.md", "physics.md",
                    "ui.md", "networking.md", "animation.md", "navigation.md",
                    "build.md"]
for f in expected_roots:
    check(f"html5/{f}", (HTML5_REF_ROOT / f).exists())
for f in expected_modules:
    check(f"html5/modules/{f}", (HTML5_REF_ROOT / "modules" / f).exists())

# ---------------------------------------------------------------------------
# 1D. Internal markdown link integrity (within engine-reference/html5)
# ---------------------------------------------------------------------------
print("\n=== 1D. Markdown link integrity within engine-reference/html5 ===")
link_re = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")
http_re = re.compile(r"^https?://")
broken = 0
checked = 0
for md in HTML5_REF_ROOT.rglob("*.md"):
    text = md.read_text(encoding="utf-8")
    for label, link in link_re.findall(text):
        # strip anchor fragments
        bare = link.split("#")[0]
        if not bare or http_re.match(bare):
            continue
        checked += 1
        target = (md.parent / bare).resolve()
        if not target.exists():
            warn(f"broken link in {md.name}", f"[{label}]({link}) -> {target}")
            broken += 1
check(f"engine-reference internal links ({checked} checked)", broken == 0,
      f"{broken} broken")

# ---------------------------------------------------------------------------
# 1E. Cross-agent references resolve to real agent files
# ---------------------------------------------------------------------------
print("\n=== 1E. Cross-agent references resolve ===")
all_agents = {p.stem for p in (CCGS / ".claude" / "agents").glob("*.md")}
agent_ref_re = re.compile(r"`([a-z][a-z0-9-]*-(?:specialist|programmer|director|designer|lead|tester|engineer|analyst|artist|writer|manager))`")
missing_refs = set()
for agent in NEW_AGENTS:
    p = CCGS / ".claude" / "agents" / f"{agent}.md"
    text = p.read_text(encoding="utf-8")
    for ref in agent_ref_re.findall(text):
        if ref not in all_agents:
            missing_refs.add((agent, ref))
check(f"cross-agent backtick references exist ({len(all_agents)} known agents)",
      not missing_refs, f"unknown refs: {sorted(missing_refs)}")

# ---------------------------------------------------------------------------
# 1F. BagelMVP @import resolution
# ---------------------------------------------------------------------------
print("\n=== 1F. BagelMVP @import paths resolve ===")
bagel_claude = (BAGEL / "CLAUDE.md").read_text(encoding="utf-8")
imports = re.findall(r"^@(\S+)", bagel_claude, re.MULTILINE)
for imp in imports:
    target = BAGEL / imp
    check(f"@{imp} resolves", target.exists(), str(target))

# ---------------------------------------------------------------------------
# 2A. PixiJS v8 self-contradiction check on pixijs-specialist.md
# ---------------------------------------------------------------------------
print("\n=== 2A. pixijs-specialist self-contradiction (v7 anti-pattern leak) ===")
pixijs_text = (CCGS / ".claude" / "agents" / "pixijs-specialist.md").read_text(encoding="utf-8")

# v7 patterns the agent explicitly bans — check none appear OUTSIDE the
# "Red Flags" table context (which legitimately mentions them as wrong).
# Heuristic: count occurrences. The Red Flags table mentions each ~once.
# More than 2 occurrences of any v7 pattern outside the table = suspicious.
V7_PATTERNS = {
    "app.view": 1,                       # mentioned in Red Flag table only
    ".beginFill(": 1,                    # Red Flag table only
    "interactive: true": 1,              # Red Flag table only
    "SCALE_MODES.LINEAR": 1,             # Red Flag table only
    "new BlurFilter(8": 1,               # Red Flag table only
}
for pattern, expected_max in V7_PATTERNS.items():
    count = pixijs_text.count(pattern)
    check(f"pixijs-specialist mentions '{pattern}' <= {expected_max} times",
          count <= expected_max,
          f"found {count} occurrences (expected <= {expected_max})")

# Confirm the agent DOES enforce v8 patterns
V8_REQUIRED = [
    "await app.init",
    "app.canvas",
    "eventMode",
    "Assets.load",
    "ticker.deltaMS",
]
for needed in V8_REQUIRED:
    check(f"pixijs-specialist enforces '{needed}'",
          needed in pixijs_text,
          "v8 pattern not mentioned")

# ---------------------------------------------------------------------------
# 2B. breaking-changes.md / deprecated-apis.md must reference v8 patterns
# ---------------------------------------------------------------------------
print("\n=== 2B. Reference docs contain v8 migration content ===")
bc_text = (HTML5_REF_ROOT / "breaking-changes.md").read_text(encoding="utf-8")
da_text = (HTML5_REF_ROOT / "deprecated-apis.md").read_text(encoding="utf-8")

for key, label in [
    ("await app.init", "v8 async init"),
    ("app.canvas", "v8 canvas accessor"),
    (".rect(", "v8 Graphics builder"),
    ("Assets.load", "v8 Assets system"),
    ("addParticle", "v8 ParticleContainer API"),
]:
    check(f"breaking-changes.md mentions '{key}' ({label})",
          key in bc_text)
    check(f"deprecated-apis.md mentions '{key}' ({label})",
          key in da_text)

# ---------------------------------------------------------------------------
# 2C. Routing tables in agents are mutually consistent
# ---------------------------------------------------------------------------
print("\n=== 2C. Routing tables consistency ===")
# Each new agent should mention all 4 sibling specialists somewhere
for self_agent in NEW_AGENTS:
    p = CCGS / ".claude" / "agents" / f"{self_agent}.md"
    text = p.read_text(encoding="utf-8")
    for sibling in NEW_AGENTS:
        if sibling == self_agent:
            continue
        # Check sibling is mentioned in the file (in some routing context)
        if sibling not in text:
            warn(f"{self_agent} does not mention {sibling}",
                 "sibling specialist not referenced — routing may be incomplete")

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print("\n" + "=" * 60)
print(f"RESULT: {checks_passed}/{checks_total} checks passed")
fails = [i for i in issues if i[0] == "FAIL"]
warns = [i for i in issues if i[0] == "WARN"]
print(f"        {len(fails)} failures, {len(warns)} warnings")
if fails:
    print("\nFAILURES:")
    for sev, name, detail in fails:
        print(f"  - {name}: {detail}")
if warns:
    print("\nWARNINGS (review but not blocking):")
    for sev, name, detail in warns:
        print(f"  - {name}: {detail}")

sys.exit(1 if fails else 0)
