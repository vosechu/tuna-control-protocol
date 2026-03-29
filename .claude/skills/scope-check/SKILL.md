---
name: scope-check
description: "Quantify scope creep by comparing current state against original design. Flags additions, measures bloat, recommends cuts."
argument-hint: "[feature-name or 'all']"
user-invokable: true
---

When this skill is invoked:

## 1. Gather the Original Scope

Read these documents to establish the baseline:

- `PLANNING.md` — the primary design document. Sections with explicit decisions are "in scope."
- `CLAUDE.md` — core design philosophy and constraints.
- `.claude/rules/` — software architecture rules and reference implementations.

Identify every **concrete deliverable** (not open questions, not brainstorming). A deliverable is something that needs to be built: a system, a mechanic, an entity type, an infrastructure piece, a UI element.

Categorize each deliverable by phase:
- **Prototype (Ring 0):** The interaction test scene — cats, ferrets, warmth, basic desires, placement.
- **Ring 1:** Progression, skill tower, food, multiple species, basic multiplayer.
- **Ring 2+:** Scale, polish, modding ecosystem, full multiplayer, advanced emergence.

## 2. Gather the Current State

- `git log --oneline -30` to see recent work
- Glob `engine/**/*.gd`, `mods/**/*.json`, `nodes/**/*.gd` to see what's been built
- Grep for TODO, FIXME, HACK in the codebase
- Read any new design docs or planning additions since the baseline

Identify:
- What's been **built** (code exists and works)
- What's been **started** (partial implementation)
- What's been **added to scope** (in docs but not in the original plan)
- What's been **dropped** (was in plan, explicitly removed)

## 3. Quantify

Output this table:

```markdown
## Scope Check: TCP — [Date]

### Deliverables by Phase

| Phase | Original | Current | Added | Dropped | Net Change |
|-------|----------|---------|-------|---------|------------|
| Prototype | N | N | +X | -Y | +/-Z (%) |
| Ring 1 | N | N | +X | -Y | +/-Z (%) |
| Ring 2+ | N | N | +X | -Y | +/-Z (%) |

### Scope Additions (not in original plan)
| Addition | Where it appeared | Justified? | Phase | Effort |
|----------|-------------------|------------|-------|--------|
| ... | PLANNING.md §X / conversation / commit abc123 | Yes/No/Unclear | Ring N | S/M/L |

### Scope Reductions
| Removed | Why | Impact |
|---------|-----|--------|
| ... | ... | ... |

### Open Questions (unresolved = hidden scope)
[List every "Outstanding question" and "TBD" from PLANNING.md — each is potential future scope]

### Bloat Score
- Original deliverables: N
- Current deliverables: N
- Unresolved questions (potential scope): N
- **Verdict: ON TRACK / MINOR CREEP / SIGNIFICANT CREEP / OUT OF CONTROL**
  - On Track: within 10%
  - Minor Creep: 10-25% — manageable
  - Significant Creep: 25-50% — cut or extend
  - Out of Control: >50% — stop and re-plan

### Recommendations
1. **Cut:** [Things to remove to stay focused]
2. **Defer:** [Things to move to a later ring]
3. **Decide:** [Open questions that are blocking or creating hidden scope]
4. **Keep:** [Additions that are genuinely necessary]
```

## 4. TCP-Specific Checks

- **Elegance Principle check:** Are new mechanics creating interactions with existing mechanics, or are they isolated? Count interaction edges. More isolated mechanics = scope bloat without depth.
- **Prototype focus check:** Is the prototype scene (cats + ferrets + warmth + placement) still achievable as the NEXT thing to build? Or have Ring 1+ features crept into the prototype?
- **Open question debt:** Count unresolved questions in PLANNING.md. Each is latent scope. Flag if >10 are unresolved.

## Rules

- Scope creep is additions without corresponding cuts or timeline awareness.
- Not all additions are bad — discovered requirements are real. But they must be acknowledged.
- TCP's design philosophy says "cut scope, not quality." When recommending cuts, protect the core loop (cats + desires + placement + emergence) above everything.
- Always quantify. "It feels bigger" is not actionable, "+35% deliverables" is.
- Open questions are scope debt. They WILL become scope when resolved.
