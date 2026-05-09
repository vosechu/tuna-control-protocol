---
name: edit-rule-files
description: "Use when creating, editing, or auditing a `.claude/rules/*.md` file — tier-aware size budget, frontmatter precision, timeless-content discipline, gotchas-section convention, and when to extract content to a sibling rule or `<important if>` block."
user-invokable: true
---

# Editing rule files in `.claude/rules/`

Rule files are reference specs the agent loads when it edits matching code. Once loaded they're paid for the rest of the conversation, so they trade size for the ability to be omitted entirely when irrelevant.

This skill complements `/edit-claude-md`. Both share principles (timeless content, machine-parsing focus, conditional gating); this one covers the rule-file-specific bits.

## Loading tiers

A rule file lives in one of two tiers. The tier sets the size budget.

| Tier | Routing | Budget | Example |
|---|---|---|---|
| **Always-loaded** | Listed in CLAUDE.md "Always loaded" table; no `paths:` frontmatter | ≤100 lines | `secrets.md`, `naming-conventions.md` |
| **Path-gated** | YAML `paths:` frontmatter | ≤300 lines | `animal-ai.md`, `signals.md` |

If an always-loaded rule grows past 100 lines, either trim it or downgrade to path-gated. If a path-gated rule grows past 300 lines, narrow its `paths:` to a tighter sub-domain or extract a sibling rule with a more specific glob.

## Frontmatter

**Path-gated:**

```yaml
---
paths:
  - "engine/animals/**"
  - "engine/desires/**"
  - "config/balance/desire_thresholds.json"
---
```

Globs must be narrow. `**/*.gd` is almost always wrong — it loads the rule on every GDScript edit, including ones where it's irrelevant. List the directories or files that actually need the rule. If you find yourself wanting `**/*.gd`, the rule is probably a candidate for the always-loaded tier (rewritten to fit ≤100 lines) or for being a skill instead.

**Always-loaded:** no frontmatter, and add an entry to the "Always loaded" table in CLAUDE.md so the routing is visible.

## Content discipline

**Timeless.** Spec what is true. Don't include "Status — 2026-XX-XX:" banners, "we just fixed X" notes, or "currently in progress" comments. Episodic state lives in PLANNING.md or in a transient plan file under `docs/superpowers/plans/`. If the rule genuinely must reference an incomplete state, wrap it in `<important if="restoring the cable subsystem">` so it disappears when irrelevant.

**Every-sentence test.** Ask "would the agent get this wrong without this sentence?" If the model already knows it (basic GDScript syntax, common Godot patterns, generic software hygiene), cut it. Every word is paid by every conversation that loads the rule.

**Negative examples beat positive ones.** Document the wrong path you've seen agents take, then the right one. A "Common slip patterns" or "Gotchas" table is the highest-signal section of a rule. The capability-vs-species slip-patterns table in CLAUDE.md is the canonical example.

**Specific and concrete.** "Use 8px tile size" beats "use small tiles." Cite file paths, function names, exact constants.

## `<important if>` blocks inside rule files

Path gating is one filter; `<important if>` adds a second filter inside the file. Use it when a rule covers several sub-domains and most edits only touch one.

```markdown
<important if="adding a new sound asset">

### Audio import workflow
...

</important>
```

Conditions must be specific and task-shaped. Bad: `you are working on audio`. Good: `you are normalizing or importing a new audio file`.

## Anti-patterns

- **Recapitulating CLAUDE.md or another rule** — if the rule restates something already loaded elsewhere, delete the duplicate.
- **Recapitulating the model's own knowledge** — explaining what `signal` does in GDScript, what a `for` loop is, etc.
- **Doc-style intros** — "This is the definitive reference for…" / "This document covers…" — cut. Lead with the thing the agent needs.
- **Over-broad path globs** — see frontmatter section.
- **Pure agent-generation** — Perplexity's research showed self-generated skills don't help on average; the author has to inject opinion. Treat agent drafts as starting material to be sharpened by hand.

## Append-mostly maintenance

Rule files are append-mostly. Most updates should add a gotcha or slip-pattern row to the existing structure rather than rewrite a section. Rewriting risks invalidating institutional memory captured in the existing wording. When you do rewrite, preserve specific examples and the WHY behind constraints.

## When the rule should be a skill instead

If the trigger is "when this kind of task is happening" rather than "when this file is edited," it's a skill. Examples:

- Wiring a new cross-system signal → `/trace-signal-flow` (task-shaped)
- Editing `engine/core/game_server.gd` → path-gated rule (file-shaped)
- Reviewing a PR → `/pr-review` (task-shaped)

See CLAUDE.md → "Rules vs. skills — pick by trigger" for the full rubric.

## References

- `/edit-claude-md` — sibling skill for CLAUDE.md itself
- Perplexity: [Designing, Refining, and Maintaining Agent Skills at Perplexity](https://research.perplexity.ai/articles/designing-refining-and-maintaining-agent-skills-at-perplexity)
- TCP CLAUDE.md → "Software Rules" section
