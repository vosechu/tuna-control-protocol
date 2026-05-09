# Dev-Team Progressive-Disclosure Design

> **Status:** open question / design exploration. Not yet committed to implementation. Captured during the 2026-05-09 rule-file audit so the idea doesn't get lost.

## Problem

TCP has two surfaces today for dev-team domain knowledge:

1. **Path-gated rule files** (`art-direction.md`, `sound-design.md`, `narrative.md`, etc.) — auto-load when editing matching paths. One-way: file edit triggers the load. The main thread can't "ask for" this content; it just appears when a relevant file is touched.
2. **Dev-team agents** (`game-artist`, `sound-designer`, `narrative-designer`, etc.) — spawnable via the Agent tool. Heavy: spawns a fresh context, runs to completion, returns a summary. Useful for structured review, but every call is a context boundary.

What's missing: a middle ground. Sometimes the main thread is making a design decision — not editing a file in the gated paths — and would benefit from the dev-team's perspective without needing a full agent run.

Concrete cases:

- Choosing colors for a new HUD overlay outside `nodes/hud/` (so `art-direction.md`'s path glob doesn't fire).
- Naming new advertisement channels (touches `Constants.CHANNELS` but not narrative files; Parcel's voice rules aren't loaded).
- The user explicitly mentioned this during the rule-file audit: "We might also need to make some of the dev team skills that do progressive disclosure *and* have the option to run as an agent. Some way to allow the main thread to pull in that info."

## Goal

Each dev-team domain has two surfaces:

1. **Agent invocation** (current) — full review pass, returns structured feedback, runs in isolated context.
2. **Context-load** (proposed) — main thread pulls in the agent's principles, vocabulary, and decision rubric on demand, without spawning.

Both surfaces should share one source of truth.

## Possible shapes

### Shape A — Skill per dev-team agent

Add a paired user-invokable skill to each dev-team agent: `game-artist` (agent) + `/load-art-context` (skill). The skill loads the same principles the agent would use, into the main thread's context. The agent reads from the skill's content for its own system prompt.

- **Pro:** Single source of truth. Skill discoverable via the Skill tool.
- **Con:** Doubles the surface count (8 dev-team agents → 16 surfaces). Skill names get verbose.

### Shape B — Agent supports "context-only" mode

The Agent tool gains a `context_only: true` parameter. Returns the agent's system prompt as content to the main thread, doesn't spawn the agent loop.

- **Pro:** No new surface. Single invocation pattern.
- **Con:** Requires harness support — TCP can't ship this without Claude Code changes.

### Shape C — Agent's principles ARE the path-gated rule

Each dev-team agent's system prompt is a thin wrapper around the existing rule file (e.g. `game-artist` reads `art-direction.md`). The rule already loads on relevant file edits; the agent is "the rule plus an instruction to act on it."

- **Pro:** Uses existing infrastructure. No new files. The path-gated rule IS the context-load surface — agents just dispatch into it.
- **Con:** Loading is still mechanical (file path), not on-demand. Doesn't directly solve the "make a design decision without editing a file" case — though the user can manually invoke the skill that loads the rule.

### Shape D — Dev-team agent definitions live in `.claude/skills/`

The agent definition file IS the skill. Both `Agent({subagent_type: "game-artist"})` and `Skill({skill: "game-artist"})` resolve to the same file, with the harness picking spawn-vs-load based on which tool was called.

- **Pro:** Truly one source of truth, one file per agent.
- **Con:** Requires harness support. New convention.

## Key open question

Are the existing dev-team rule files (`art-direction.md`, `sound-design.md`, etc.) already the "context-load" surface — just gated by file path?

If yes, then the missing piece is a way for the main thread to request the rule on-demand when it's not editing a matching path. That's a small addition: a user-invokable skill per dev-team domain that does nothing but load the rule.

If no — if the agents have important principles NOT captured in their rule files — then the source-of-truth question is real and Shape A or D matters.

The agent cross-references added during the 2026-05-09 audit ("Maintained alongside the `game-artist` (Smudge) agent") imply the answer is "mostly yes, with the agent adding persona on top." Worth verifying by reading each dev-team agent's actual prompt and diffing against the corresponding rule.

## Recommendation (for future implementation)

Likely **Shape C with a small skill-per-domain layer on top.**

1. Audit each dev-team agent's prompt against its corresponding rule file. Where the agent has principles not in the rule, move them into the rule.
2. The agent's system prompt becomes: "You are <persona>. Read `.claude/rules/<rule>.md`. Apply those principles to the user's request."
3. Add a thin user-invokable skill per dev-team domain (e.g. `/art-context`, `/sound-context`) that loads the rule into the main thread without spawning the agent.

This avoids harness changes (no Shape B/D dependency), keeps one source of truth (the rule), and serves the main-thread case (the skill).

## Defer triggers

Implement when:

- The user hits the "main-thread design decision needs dev-team perspective" case more than ~3 times in a session and notices the friction.
- A dev-team agent's principles diverge meaningfully from its rule file (drift detected during a review).
- A new dev-team domain is added (good time to standardize the pattern).

Until then: manually invoke a skill that loads a rule, or just spawn the agent.

## Related

- `.claude/skills/edit-rule-files/SKILL.md` — rule-file standards.
- `CLAUDE.md` → "Rules vs. skills — pick by trigger" — the decision rubric this would extend.
- `.claude/agents/` — current dev-team agent definitions.
- `.claude/rules/{art-direction,sound-design,narrative,input-design,asset-pipeline}.md` — existing per-domain rule files (each now cross-references its agent).
