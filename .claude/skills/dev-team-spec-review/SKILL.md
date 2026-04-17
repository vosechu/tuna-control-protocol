---
description: Dispatch TCP's dev team agents in parallel to review a design spec through their specialized lenses, producing categorized blocking/non-blocking feedback.
---

# Dev Team Spec Review

## When to Use This Skill

When a TCP design spec is drafted and ready for multi-perspective review. Run **before** committing the spec and **before** invoking writing-plans. Expect to run it 1-2 times on a spec — Round 1 surfaces blockers, Round 2 verifies fixes and catches second-order issues in new additions.

## Prerequisites

- Spec file exists at `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
- All TCP dev team agents available: `game-designer`, `game-programmer`, `accessibility-advocate`, `game-qa`, `narrative-designer`, `sound-designer`, `game-artist`, `game-asset-creator`, `community-modder`
- Relevant rule files in `.claude/rules/` (the agents will read them)

## Steps

### 1. Dispatch all 9 agents in parallel

Send a single message with nine `Agent` tool calls (one per agent). Each prompt must include:

- The spec file path
- The agent-specific lens to apply (design, implementation, accessibility, QA edge cases, narrative voice, audio, art, asset pipeline, mod extensibility)
- A length cap (200-350 words, keeps the main context lean)
- A request for categorized output: **Blocking**, **Non-blocking**, **Praise**

For Round 2, also include:
- A status summary of which Round 1 items were addressed
- Instructions to re-hunt for issues specifically in new material added between rounds

### 2. Consolidate findings

Collect all nine responses. Categorize across agents:

- **Blocking fixes the user won't need to decide on** (clear bugs, spec contradictions, rule violations) — fold these in automatically.
- **Design forks needing user input** (legitimate "A or B" choices, scope-expansion questions) — list these and stop for user decision.
- **Non-blocking polish** — include in the fold-in batch if clearly improvements, otherwise defer to playtest.
- **Praise** — keep short, useful for the user to know what landed.

### 3. Apply fixes, present forks

Apply all blocking and clear non-blocking fixes directly to the spec. Present the design forks to the user with a recommended default for each. In auto mode, pick the defaults yourself; the user redirects if wrong.

### 4. Consider Round 2

After Round 1 fixes land, the spec has changed substantially. Re-run the dispatch (Step 1) with the Round 2 framing — "what did Round 1 miss, and what new issues did the fixes introduce?" Usually Round 2 is sufficient; Round 3 only if Round 2 finds another wave of blockers.

## Agent-Specific Lenses

Keep the prompts targeted — vague "review this spec" prompts produce generic feedback.

| Agent | Lens |
|---|---|
| `game-designer` | Abundance vs scarcity feel, emergence, Elegance Principle, coherence with Ring 0/core-loop |
| `game-programmer` | Implementability, existing-code integration, GameStateDB fit, tick-order correctness, test plan gaps |
| `accessibility-advocate` | Controller parity, color-independence, screen-reader, no time pressure, backup channels for every primary feedback |
| `game-qa` | Despawn races, save/load edge cases, multiplayer authority, scale concerns, signal ordering bugs — "what happens when..." |
| `narrative-designer` | Robot voice, terminology coherence, missed narrative beats, log-line rewrites |
| `sound-designer` | Audio mix, masking, new asset needs, deterministic detune for per-entity sources |
| `game-artist` | Readability at 224×128, palette conflicts, opacity limits, sag/curve spec, flicker risk, UI collision with heat/placement overlays |
| `game-asset-creator` | Naming conventions, audio format (.wav 16/48 QOA), config dir structure, asset-tracker updates, credits |
| `community-modder` | Mod override paths, capability-not-species purity, hardcoded refs, missing extensibility hooks |

## Common Issues

- **Agent responses are too long:** set a word cap in the prompt (200-350 words typical).
- **Agents duplicate findings:** expected — cross-agent overlap is a signal (both Bramble and Kibble flagging the same bug = definitely blocking).
- **Design forks that aren't forks:** if an agent raises a "question" that's actually a bug report, fold it in directly. Don't bounce every agent comment back to the user.
- **Round 2 scope creep:** Round 2 should NOT introduce new design changes — only verify Round 1 fixes and catch new bugs in new material. If Round 2 wants to redesign something fundamental, that's a signal the spec needs brainstorming, not review.

## Example Dispatch Pattern

```
Single message with 9 Agent tool calls in parallel.
Each prompt: "Review [spec path] as [agent name] through [specific lens]. Round N feedback. [Status of previous round.] Report under X words. Format: Blocking / Non-blocking / Praise. Cite file:line when pointing at code."
```

Then in the follow-up turn, consolidate and present.
