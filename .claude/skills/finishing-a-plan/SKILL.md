---
name: finishing-a-plan
description: "Close out a completed plan/spec by extracting its durable mechanics into permanent docs and deleting the transient planning artifacts. Run when implementation is done and only cosmetic checkboxes remain."
argument-hint: "[path-to-plan-or-spec]"
user-invokable: true
---

When this skill is invoked:

## Purpose

A plan or spec is a **transient artifact** — it exists to coordinate a piece of work. Once that work ships, the plan's job is done. The **mechanics it described** are the permanent value.

This skill converts the plan/spec into permanent reference docs and deletes the transient files. The acceptance test:

> "If we had to reproduce this game in a different language, could we one-shot the mechanic from the permanent docs alone?"

If the answer is no, the extraction isn't finished yet.

## When to use

- The plan's implementation tasks are done (code shipped, tests green).
- Remaining checkboxes in the plan are cosmetic or grep-based verifications.
- The spec/plan duplicates knowledge that now lives in code and should live in durable docs.

## When NOT to use

- Implementation is incomplete or in-progress. Finish the work first.
- The plan was abandoned mid-flight — use `triage-chaotic-git-state` to sort out what shipped, then come back.
- The spec is a **design-in-progress** with open questions — it's still earning its keep as a living document.

---

## Step 1: Verify the plan actually shipped

Before deleting anything, confirm the plan's claims match reality.

- Read the plan's success criteria (usually a "Completion checklist" at the end).
- Run each grep/verification the plan prescribes. Record what passes.
- `script/validate` must exit 0.
- Any stamped tests referenced by the plan must still be stamped and passing.
- For each Task that prescribed a code change: grep for the symbol/file and confirm the change is present.

If any step fails, the plan is not done. Stop and address the gaps before extraction.

## Step 2: Audit testing discipline

Before extracting permanent knowledge, audit what happened to the test surface
during the plan. Test deletion and stamp shortcuts are the most common silent
regressions, and they compound plan-over-plan. This step catches the
LLM-shaped shortcuts that `script/validate` cannot.

Walk every commit in this plan that touched `tests/**`. For each change, answer
the question in plain prose. Vague or absent answers mean the shortcut wasn't
caught — go back and fix it before completing the audit.

| Change | Question to answer |
|---|---|
| **Deleted test function** | Name a specific integration/scenario/scene test (path + test_name) whose assertion pins the same invariant, and quote the matching assertion. `.claude/rules/test-philosophy.md` explicitly rejects "integration covers this" as a catch-all — integrations are spot-checks, not a safety net for unit coverage. If you cannot produce a specific citation that names the same invariant, the deletion was wrong; restoration is required. |
| **Merged test pair** | Does the merged body contain every assertion from both originals? List any dropped assertion. A dropped assertion is a silent coverage loss — add it back, or file a TODO comment + follow-up task. |
| **Stamped tests (any new or modified test file)** | Cross-check against the bug hypotheses in the plan doc (see `/spec-first` Phase 1). For each new test, does its body actually pin the bug class the hypothesis names? A hypothesis that says "forgot the SLOTS_PER_RACK - 1 - inversion" should be paired with a test that fails if that exact mutation is applied. If the hypothesis is vague or the test doesn't match, the pair isn't earning its keep. |
| **Restamped via `tdd_verify restamp`** | Confirm from the commit body (or `git log -p`) that the reason describes a cosmetic-class change: whitespace, lint-forced wrapping, comment edits, renames of unused locals. An assertion-logic change slipped in via restamp is an abuse — re-run `tdd_verify stamp` after a proper red-green cycle instead. |
| **`# TODO` comments added to test files** | List them. Each is documented coverage debt. Confirm each has an owner or follow-up task. |

Emit the audit findings as a block in the closeout commit body:

```
## Testing audit
Deleted tests: N — coverage verified in: <paths> (or restored in <commits>).
Merged pairs: M — dropped assertions: <list or "none">.
Bug hypotheses cross-checked: <N tests> — mismatches: <list or "none">.
Restamped cosmetically: <list with reasons, or "none">.
Open TODOs: <list or "none">.
```

If any row produces a gap — missing citation, dropped assertion, test
body that doesn't match its bug hypothesis — resolve the gap before
proceeding to Step 3. The gap is the point of the audit; don't paper
over it.

> **Note on legacy `.audit.yaml` files.** Older plans generated
> `.audit.yaml` sidecars recording per-test mutation hashes. Those are
> historical now — the mutation cycle was removed (see the tdd_verify
> refactor commit). New stamps don't produce audit files. Existing ones
> can stay in tree as historical record or be cleaned up; they don't
> affect verification.

## Step 3: Enumerate the plan's permanent knowledge

Walk through the spec + plan and classify every meaningful paragraph into one of:

| Category | Example | Destination |
|---|---|---|
| **Anchor principle** — a rule that constrains future code | "Systems check capabilities, not species" | `CLAUDE.md` top-level section or a rule file |
| **Mechanic definition** — how a system works | "Animals charge HUM reserve when satisfied; reserve drains idle" | `.claude/rules/<system>.md` |
| **Schema** — required fields, types, naming | "Species recipe must declare desires, sprite_config, ambient_states" | `.claude/rules/modding.md` or dedicated schema file |
| **Invariant** — something that must always be true | "Tick must complete in constant wall-clock time" | `.claude/rules/tick-architecture.md` |
| **Historical motivation** — why we chose X over Y | "We picked MessagePack because 40-60% smaller than JSON" | `.claude/rules/<system>.md` as context |
| **Task-level instructions** — "edit file X line Y" | — | **DROP** (transient, not permanent) |
| **Before/after code snippets** showing the refactor | — | **DROP** (the after-state is in code) |
| **Timeline/staging rationale** — "Task 1 before Task 2 because..." | — | **DROP** (implementation detail) |
| **Success criteria checklists** | — | **DROP** (already passed) |

Be ruthless. If a reader of the permanent doc wouldn't need it to rebuild the system, drop it.

## Step 4: Choose destinations

For each item in the "keep" pile:

1. **Is a suitable rule file already present?** Grep `.claude/rules/` for adjacent content. Prefer extending an existing rule over creating a new one.
2. **Does it belong in `CLAUDE.md`?** Only if it's a cross-cutting anchor that belongs on every code-writing session's first read. Otherwise use a path-gated rule file.
3. **Does it need a new rule file?** Create one only if the mechanic is a coherent subsystem not covered by any existing rule.

Map each kept paragraph to its destination file + section. Write the map down before editing — if the map feels forced, re-classify.

## Step 5: Write the permanent docs

For each destination:

- **Distill, don't transcribe.** The plan said the same thing three times; the rule file says it once, clearly.
- **Present tense, declarative voice.** "Systems check capabilities" — not "we decided to change systems to check capabilities."
- **Concrete examples.** Include a minimal working snippet (schema, function signature, call flow) so a reader can reproduce the shape.
- **Link, don't duplicate.** If the HUM charge rate is in `.claude/rules/tick-architecture.md`, the core-loop doc points there.
- **No dates, no commit hashes, no "during the refactor".** Permanent docs are timeless.

After writing, run `script/validate` to catch any broken references (if the project lints markdown links).

## Step 6: The one-shot reproducibility test

Pretend you're a developer reimplementing this system in a different language with only the permanent docs. For each mechanic the plan covered:

- [ ] Can I derive the correct data structures from the schema?
- [ ] Can I implement the hot loop from the tick-order section?
- [ ] Can I wire the signals/events without guessing?
- [ ] Do I know what to test and what the invariants are?
- [ ] Is the "why" obvious enough that I won't re-derive a worse design?

If any answer is "no," loop back to Step 5 and fill the gap. Do not proceed to deletion with holes.

## Step 7: Delete the plan and spec

Only after Step 5 passes:

- `git rm docs/superpowers/plans/<date>-<plan-name>.md`
- `git rm docs/superpowers/specs/<date>-<spec-name>-design.md`
- Grep for cross-references to those paths and update them to point at the new permanent docs.
- If other specs reference this one via "See spec X", either inline the specific fact into the referring doc or point at the new rule.

## Step 8: Commit

One commit: `docs: fold <plan-name> into permanent rules; remove transient plan/spec`

Commit body should:
- List which permanent docs were written or updated.
- List the deleted paths.
- Call out anything that was deliberately dropped (e.g., "Dropped staged-ordering rationale — historical detail not useful to future sessions").

---

## Rules

- **Permanent docs outlive everything else.** If a plan's knowledge only lives in the plan, deleting the plan loses the knowledge. Extraction must precede deletion, always.
- **Plans are not changelogs.** Don't preserve a plan "for history" — that's what `git log` is for.
- **Specs with superseded banners can be deleted too** once their mechanics live in the permanent docs. The banner is an intermediate state, not a permanent resting place.
- **Test stamps protect tests.** This skill touches docs only. If the plan prescribes new tests, they should already be stamped by the implementation commits.
- **Cross-reference carefully.** A rule file pointing at a deleted spec is a dead link. Grep before deleting.

## TCP-specific destinations

For TCP plans, common destinations:

| Topic | File |
|---|---|
| Core game loop, abundance, purr-as-metric | `.claude/rules/core-loop.md` |
| Sim tick, scatter, evaluation budget | `.claude/rules/tick-architecture.md` |
| AI states, advertisements, aversions | `.claude/rules/animal-ai.md` |
| Species recipes, mod layering, IDs | `.claude/rules/modding.md` |
| Signal patterns, event bus ownership | `.claude/rules/signals.md` |
| GameStateDB behavior, invariants | `.claude/rules/design-philosophy.md` |
| Save format, versioning | `.claude/rules/save-system.md` |
| Networking protocol | `.claude/rules/networking.md` |
| Cross-cutting principles that apply every session | `CLAUDE.md` |

If a mechanic doesn't fit any of these, propose a new rule file and name it by subsystem, not by plan name.
