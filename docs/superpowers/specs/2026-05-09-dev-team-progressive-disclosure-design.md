# Dev-Team Progressive-Disclosure Design

> **Status:** design firmed up 2026-05-09. Not yet implemented. Captured during the rule-file audit so the idea doesn't get lost.

## Problem

TCP has two surfaces today for dev-team domain knowledge:

1. **Path-gated rule files** (`art-direction.md`, `sound-design.md`, `narrative.md`, etc.) — auto-load when editing matching paths. One-way: file edit triggers the load. The main thread can't "ask for" this content; it just appears when a relevant file is touched.
2. **Dev-team agents** (`game-artist`, `sound-designer`, `narrative-designer`, etc.) — spawnable via the Agent tool. Heavy: spawns a fresh context, runs to completion, returns a summary. Useful for structured review, but every call is a context boundary.

What's missing: a middle ground. Sometimes the main thread is making a design decision — not editing a file in the gated paths — and would benefit from the dev-team's perspective without needing a full agent run.

Concrete cases:

- Choosing colors for a new HUD overlay outside `nodes/hud/` (so `art-direction.md`'s path glob doesn't fire).
- Naming new advertisement channels (touches `Constants.CHANNELS` but not narrative files; Parcel's voice rules aren't loaded).
- The user explicitly mentioned this during the rule-file audit: "We might also need to make some of the dev team skills that do progressive disclosure *and* have the option to run as an agent. Some way to allow the main thread to pull in that info."

## Recommended design — three triggers, one source

The path-gated rule file stays the canonical source of truth for each domain. Two new surfaces read from it:

```
              .claude/rules/art-direction.md  ← single source
                /          |          \
               /           |           \
       path edit       /load-       Agent spawn
       triggers        game-        (game-artist
       on .png /       artist       reads same
       .tscn           invokes      rule for its
       (mechanical)    explicitly   system prompt)
                       (on-demand)  (full review)
```

Three triggers, one source. No content duplication, no drift.

### Why rules stay canonical (not moved into skills)

- **Path-gated auto-load is a safety net we shouldn't break.** Editing a sprite mechanically pulls in palette guidance today. Moving content into skills means relying on description routing — the model has to recognize "I'm doing art work" instead of the path doing the work. Worse outcomes.
- **Persona is performance, not principles.** "Smudge is bold, suggests you double the saturation" lives in the agent definition. The principles ("8px tile size, native 1× rendering, palette discipline") live in the rule. Both surfaces read the principles; the agent adds the persona on top.
- **Today's audit already set this up** — every dev-team rule now has a one-line cross-reference to its agent. Adding the skill is the third leg.

## Skill naming convention

`/load-<agent-role-name>` — matches the agent's `subagent_type` 1:1.

Full set:

| Skill | Agent | Loads rule |
|---|---|---|
| `/load-game-designer` | `game-designer` | `design-philosophy.md` (Game Design Principles section) + modding, animal-ai, narrative |
| `/load-game-asset-creator` | `game-asset-creator` | `asset-pipeline.md` + design-philosophy, modding, art-direction |
| `/load-game-artist` | `game-artist` | `art-direction.md` + design-philosophy, asset-pipeline |
| `/load-sound-designer` | `sound-designer` | `sound-design.md` + design-philosophy |
| `/load-narrative-designer` | `narrative-designer` | `narrative.md` + design-philosophy |
| `/load-game-qa` | `game-qa` | `testing.md` + design-philosophy, code-style, signals |
| `/load-game-programmer` | `game-programmer` | `design-philosophy.md` (Technical Principles section) + 12 path-gated rules |
| `/load-accessibility-advocate` | `accessibility-advocate` | `input-design.md` |
| `/load-community-modder` | `community-modder` | `modding.md` |

Same vocabulary across both surfaces. Tab-completion surfaces them together. Slightly verbose, unambiguous.

## Decision criteria embedded in each agent and skill

Without a rubric, the user (or main thread) has to memorize the routing every time. With one, both surfaces self-explain. Pattern: a callout at the top of the rule file (read by both surfaces).

Template:

```markdown
> **Use `/load-game-programmer` when** you're about to make a programming-shape decision and want Bramble's principles in the main thread's context (architecture choice, refactor scope, what-belongs-in-pure-core question).
> **Spawn the `game-programmer` agent when** you want a structured review of existing code, a second opinion on a finished design, or to parallelize independent investigation.
```

Rough rubric:
- **Skill load** → "I'm about to act, want the principles in front of me first"
- **Agent spawn** → "I have an artifact, want a structured review against the principles"

The criteria live in the rule file (one source). Both the skill and the agent read them.

## Implementation steps

1. **Audit each dev-team agent's prompt against its corresponding rule file.** Where the agent has principles not in the rule, move them into the rule. Where the rule has content the agent doesn't apply, that's fine — the rule is the superset.
2. **Add a "Use this domain" callout** at the top of each dev-team rule file, with the skill-vs-agent rubric tailored to the domain.
3. **Rewrite each dev-team agent's system prompt** to: "You are <persona>. Read `.claude/rules/<rule>.md`. Apply those principles to the user's request, with <persona-specific guidance>."
4. **Add `/load-<agent-role-name>` skills** — one per dev-team agent. Each skill is ~5 lines: a `Skill` invocation that loads the corresponding rule into the main thread.
5. **Update CLAUDE.md** "Software Rules" section so the rules-vs-skills decision rubric mentions this third surface.

Some rule files don't map 1:1 to a dev-team agent today (e.g. `code-style.md` covers programming but isn't owned by `game-programmer` exclusively). For those, either:

- Pick the closest agent and have that agent's `/load-` skill load multiple rules.
- Or split the rule along agent boundaries.

**Resolution (2026-05-09):** All TBDs in the naming-convention table above are now resolved. The implementation chose option (a) for design/programmer/QA — pick the closest agent's primary rule and have its `/load-` skill load multiple rules. game-designer and game-programmer both load `design-philosophy.md` because both moved their TCP-specific principles into named subsections of that file (Game Design Principles, Technical Principles). game-qa loads `testing.md` as primary plus three supporting rules.

## Alternatives considered

- **Move rules into skills (drop path-gated loading).** Rejected — see "Why rules stay canonical."
- **Agent supports `context_only: true` mode.** Would let `Agent({subagent_type: "game-artist", context_only: true})` return the prompt to the main thread without spawning. Cleaner in theory, but requires Claude Code harness changes TCP can't ship unilaterally.
- **Agent definition file IS the skill (one file per agent).** Same harness-dependency problem; also conflates persona with principles.

## Defer triggers

Implement when:

- The user hits the "main-thread design decision needs dev-team perspective" case more than ~3 times in a session and notices the friction.
- A dev-team agent's principles diverge meaningfully from its rule file (drift detected during a review).
- A new dev-team domain is added (good time to standardize the pattern).

Until then: manually invoke a skill that loads a rule (or just add the rule file to the conversation by mentioning it), or spawn the agent.

## Related

- `.claude/skills/edit-rule-files/SKILL.md` — rule-file standards.
- `CLAUDE.md` → "Rules vs. skills — pick by trigger" — the decision rubric this would extend (would gain a third row for the skill-loads-rule pattern).
- `.claude/agents/` — current dev-team agent definitions.
- `.claude/rules/{art-direction,sound-design,narrative,input-design,asset-pipeline}.md` — existing per-domain rule files (each now cross-references its agent after the 2026-05-09 audit).
