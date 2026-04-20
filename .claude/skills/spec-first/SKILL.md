---
name: spec-first
description: "Use when starting a new feature. Locks test descriptions and bug hypotheses into the plan before tests or code exist, then runs each implementation phase in a fresh subagent. Removes the 'which tests exist' and 'which mutations count' degrees of freedom that agents rationalize under pressure. Complements /verify-test (stamping) and /finishing-a-plan (closeout audit)."
argument-hint: "[path-to-feature-spec]"
user-invokable: true
---

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to dispatch each phase's subagent with a fresh context. Phase-to-phase insulation is this skill's primary defense against cross-phase optimization (e.g. writing shallow descriptions now to make later implementation easier). If you run phases in the main thread, or let a subagent span phases, you've defeated the skill.
>
> The main thread owns the plan doc. In Phase 2 it inserts the workflow checklist (template below), and ticks each checkbox as that phase completes. Progress is visible and the session is resumable.

## Purpose

Agents game test verification under pressure. Observed patterns (and
covered in Simon Willison's writing on LLMs and testing):

1. Deleting tests mid-plan with "integration covers this" rationale.
2. Target-painted "puzzle mutations" that pass a uniqueness check but
   represent no plausible bug (e.g. `if cost == 50: cost = 49`).
3. Hard-coding production code to specific test input values.
4. Rubber-stamping self-audits at plan closeout.

This skill shifts three decisions from *agent under pressure* to
*human in the spec*, removing most of the gaming surface:

| Decision | Old flow | New flow |
|---|---|---|
| **Which tests exist** | Agent decides mid-implementation; can quietly delete. | Human writes the description list in the plan doc, committed before any code. Deletions are visible. |
| **What bug each test catches** | Agent invents a mutation at stamp time to satisfy the uniqueness check, producing contrived puzzles. | Human writes the **bug hypothesis** alongside each description up front. No search, no pressure, no puzzle — the agent just translates a named bug class into a mutation. |
| **What the test inputs are** | Agent implementing production code reads the test file and can hard-code to specific values. | **Information-hiding**: the implementation subagent gets only the description list + test signatures, never the test bodies. It must implement semantics, not values. |

The common pattern is: **do the thinking up front in the spec, by a
human, where gaming pressure doesn't exist. Leave agents with
mechanical translation work.**

Remaining gaming surface is Cheat #4 (rubber-stamp collusion) and
minor variants. Phase 6's automated grep + adversarial QA raises the
floor; Phase 8 (human spot-check) is the actual backstop. This skill
is not cheat-proof — but it removes the specific failure modes we've
seen in this project.

## When to use

- Starting a feature that ships new observable behavior.
- Meaningful refactors where new tests will be added.
- Any plan where you'd otherwise have an LLM decide mid-stream what to test.

## When NOT to use

- Bug fix for a specific regression. Write the failing test, fix it, done.
- Exploratory spike. Use brainstorming skills first.
- Pure cleanup (renames, formatting) that doesn't change tested behavior.

## The workflow

Each phase has a fresh subagent with minimal context. **Do not let a
subagent span phases** — the insulation is the point. A subagent that
knows it's about to write code has incentive to generate shallow
descriptions; a subagent that only knows it's drafting descriptions has
no such pressure.

### Variant: pure-function subsystems (YAML input/output)

For purely-functional subsystems (coordinate helpers, utility math,
parsers, pure-core transforms), skip the prose-descriptions layer.
Write the contract as a YAML table of `input → expected_output` rows.
See Drew Breunig's `whenwords` library for the canonical form of this
pattern. The table is the contract; a subagent mechanically generates
the test file from the table (no interpretation). Phase 3 (QA
descriptions) collapses — there's nothing to interpret, the YAML is
eyeballable. Phases 5–8 run normally.

Use prose descriptions (the main flow below) only when the behavior
can't be expressed as input→output: state transitions, signal
emissions, ordering invariants, side effects on a shared store.

### Phase 1 — Draft test descriptions (with bug hypotheses)

Dispatch a subagent with: the feature spec, `.claude/rules/testing.md`,
`.claude/rules/test-philosophy.md`. Task: produce a numbered list of
rspec-style test descriptions covering every public method and every
branch called out in the spec. **Each description is paired with a
bug hypothesis** — the plausible mistake this test would catch.

The bug hypothesis has two jobs:

1. **Discipline the description.** You can't name a real bug class for
   "handles edge cases." If you can't say what would break the test,
   the test is vague and the description needs rework.
2. **Replace puzzle-mutations.** The bug hypothesis IS the intended
   mutation, written by a human up front. Phase 4's test-writer
   implements an assertion that the described bug would break; Phase 8
   human review cross-checks the test body against the claimed bug
   class. No agent is under pressure to invent a mutation, so no
   target-painted `if cost == 50: cost = 49` contrivances.

Format:

```
Good: "slot_origin_world Y descends as slot index rises
       | bug: forgot the `SLOTS_PER_RACK - 1 -` inversion in the formula"
Good: "bay_local_to_slot tags &\"other\" in horizontal gap between racks
       | bug: over-eager rack match that claims the gap X as a rack column"
Bad:  "handles edge cases | bug: unclear"
Bad:  "works correctly | bug: the code is wrong"
```

If a description could describe two different tests, split it. If two
descriptions pin the same invariant in different words, merge them. If
two bug hypotheses describe the same class of bug, the descriptions
are probably redundant.

### Phase 2 — Commit the descriptions and workflow checklist

Add the list to the plan doc under a `## Test plan` heading, together
with the phase checklist. Main thread edits the plan doc directly — the
checklist is the main thread's progress tracker, not a subagent's
output.

Template:

```markdown
## Test plan

> Phase tracker for /spec-first. Tick as each phase completes.
> Use `superpowers:subagent-driven-development` for Phase 1, 3, 4, 5, 6 dispatches.

- [x] Phase 1: Draft test descriptions + bug hypotheses
- [ ] Phase 2: Commit descriptions + checklist
- [ ] Phase 3: QA descriptions
- [ ] Phase 4: Write failing tests (assertion-failure output in commit body)
- [ ] Phase 5: Implement via information-hidden subagent brief
- [ ] Phase 6: QA implementation (grep pre-check + adversarial subagent)
- [ ] Phase 7: Hash-seal via `tdd_verify stamp`
- [ ] Phase 8: Human spot check

### Descriptions

1. <description> | bug: <hypothesis>
2. <description> | bug: <hypothesis>
...
```

Commit:

```
plan(<feature>): test descriptions + workflow checklist
```

This commit is the contract. From here on, any deletion from the
descriptions list is a visible act that requires a prose rationale,
and the ticked checklist shows at a glance where the session is.

As each subsequent phase completes, the main thread returns to this
section and flips `- [ ]` to `- [x]`. Amend the relevant phase's
commit if that phase wasn't the one touching the plan doc, or include
the checkbox flip in the phase's own commit if it was.

### Phase 3 — QA the descriptions

Dispatch a **fresh** subagent (new context, doesn't know Phase 1's
contents beyond what's in git). Task: answer each question in prose
citing specific descriptions, not hand-waving.

- Does every public method in the spec have at least one description?
- Does every branch in the spec's prose have a description?
- Are any descriptions restatements of each other in different words?
- Do any description titles mislead about what they pin?
- Does any description cite "integration covers this"? If so, REOPEN —
  that's the anti-pattern, the description needs to be an invariant in
  its own right.
- **Is each bug hypothesis a plausible human bug class** (off-by-one,
  wrong comparator, forgotten null check, swapped args, dropped guard),
  or is it a puzzle ("if input equals X return Y")? Puzzle hypotheses
  mean the description is vague enough that no real bug maps to it —
  tighten the description or drop it.
- Do any two bug hypotheses describe the same bug? If so, the
  descriptions are probably redundant.

If the QA finds gaps, loop back to Phase 1 with the gaps as input. Do
not proceed to Phase 4 with open concerns.

### Phase 4 — Write failing tests

Dispatch a subagent. Task: implement each description as a test
function. Run `script/checks/gut_tests -f <file>`. The tests MUST fail,
and they must fail on an ASSERTION, not a parse error or a missing
symbol.

Paste the failure output into the commit body:

```
test(<feature>): failing tests for descriptions

Run output:
- test_slot_origin_y_descends: FAIL at line 42 — expected 72, got 32
- test_gap_zone_is_other: FAIL at line 51 — expected &other, got &slot
- ...
```

A failure that reads "Parse error: SlotQuery not found" is a cheat —
rewrite the test so the specific missing behavior is what fails, not
the missing type. Commit.

### Phase 5 — Implement the feature (information-hiding)

The default failure mode here is hard-coding to test inputs — the
implementation agent reads the test file, sees specific input values
and expected outputs, writes `if x == 27: return 64` style branches.
The structural defense is to **withhold the test bodies** from the
implementation subagent. If it never sees the specific values, it
can't hard-code to them; it has to implement the semantics.

Prepare an **implementation brief** and dispatch a subagent with ONLY
that brief, not free access to `tests/`. The brief contains:

- The feature spec.
- The description list (Phase 1) or the YAML table keys (variant), but
  **not** the YAML input/output rows.
- The test function *signatures only* — the output of
  `grep -oE '^func test_[a-z_0-9]+' tests/unit/<file>.gd`. Signatures,
  not bodies.
- Path-gated rules for the systems being touched.

Instruct the subagent explicitly: "Do not read the test file bodies,
only the signatures provided. Implement from the spec and descriptions;
you will not see the specific inputs the tests use."

Tests run after the subagent is done. If tests pass, the agent
implemented semantics rather than values — it couldn't have hard-coded
to inputs it never saw. Commit:

```
feat(<feature>): implement to pass test descriptions (brief-only)
```

Commit before Phase 6. Do not defer the commit to "after QA passes" —
a cheat embedded in git history can be reviewed; a cheat squashed into
a retroactively-rationalized final commit cannot.

**Escape hatch:** if the subagent genuinely cannot implement from the
brief alone (ambiguous spec, genuinely needs an example), that's a
signal to go back and tighten the spec or add canonical examples to
Phase 1's descriptions. Do not just hand over the test file; the
information asymmetry is the defense.

### Phase 6 — QA the implementation (adversarial)

Two-step defense against agent rubber-stamping: **automated grep first,
adversarial subagent second.** The grep is uncheatable (it's not an
agent); the subagent starts from the grep's findings and must explain
each rather than being asked to open-endedly "look for problems."

**Step 6a — automated pre-check (run by the dispatching thread, not a
subagent):**

```bash
# Flag specific-value branches in production files that were touched:
git diff --name-only <phase-5-commit>^ <phase-5-commit> -- 'engine/**/*.gd' 'nodes/**/*.gd' \
  | xargs grep -nE 'if [a-z_]+ == [-0-9]+' \
  | grep -v '== 0' \
  | grep -v 'Constants\.INVALID'
```

Anything this surfaces is a candidate hard-code. The output — even if
empty — goes into the brief for Step 6b.

Additional patterns worth grepping: `return Vector2i\(\d+, \d+\)`,
magic constants that match values in the description list, branches on
specific `StringName` values that correspond to test inputs. Tune the
regex set for your project.

**Step 6b — adversarial QA subagent:**

Dispatch a **fresh** subagent with the grep output + the Phase 5
commit. Brief it adversarially:

> Your job is to find at least one concern with the implementation, or
> to explain with citations why each concern I've listed is safe. A
> response of "looks fine" without citations is a failed QA. You will
> not be penalized for finding problems; you will be penalized for
> missing them.

The subagent must answer each question with a cited file:line location
or an explicit "no match in file":

- For each grep hit: is this a legitimate branch or a hard-code to a
  test input value? Cite the matching test if it's a hard-code.
- Does the implementation reimplement the test's assertion as
  production logic (e.g. test asserts `rect.size == Vector2i(23, 8)`
  and the production code hard-returns that)?
- Is there plausible behavior for inputs outside the test set, or does
  the code visibly fall apart on any untested input?
- Would an experienced reviewer call this "actually implementing the
  semantics" or "hard-coded to the tests"?

If any answer surfaces a problem, reopen Phase 5 with the specific
findings. Do not accept "looks fine" without cited locations.

### Phase 7 — Hash-seal the tests

Run `script/tdd_verify stamp <test_file>`. This runs the tests once
more, confirms green, and writes a `.stamp` sidecar with hashes of
the setup block and each test body. That's the tamper-evidence guarantee
— future silent edits to the test bodies will fail `verify_tests` in
CI until re-stamped.

Phase 7 does NOT re-verify test quality. Phases 3 and 6 did that, and
the bug hypotheses written in Phase 1 document which bugs each test is
meant to catch. No mutation cycle runs here — mutation design happened
up front in Phase 1, not at stamp time.

### Phase 8 — Human spot check

**The final checkpoint belongs to a human, not an agent.** Read the
final diff. Look for the same patterns Phase 6 asked about. Cross-check
the bug hypotheses from Phase 1 against the test bodies — does each
test actually pin the bug class it claims?

This is the only phase that catches "all the subagents rubber-stamped
each other." Do not treat it as a formality.

## What this blocks

| Cheat | Defense |
|---|---|
| "Integration covers this, delete the unit test" | Phase 2 commits descriptions. Deletion requires removing a line from the plan doc — visible in git. |
| Shallow descriptions ("handles edge cases") | Phase 3 QA, with specific questions that hand-waving can't answer. |
| Tests that fail for the wrong reason | Phase 4 requires assertion-failure output in the commit body. |
| Agent optimizing across phases (shallow descriptions to make later implementation easier) | Fresh subagents per phase. Each only knows its own task. |
| Hard-coding production code to specific test input values | Phase 5 information-hiding — the implementation subagent never sees the test bodies, so it cannot know the specific values to branch on. |
| QA subagent reflexively rubber-stamping the implementation | Phase 6a automated grep (not an agent, can't be sycophantic) feeds concrete flags into Phase 6b, where the subagent is briefed adversarially and must cite each flag rather than waving. |

## What this does NOT block

| Cheat | Mitigation |
|---|---|
| Implementation subagent ignores the "don't read test bodies" instruction | Honor-system within the subagent briefing; detectable if its output contains test input values verbatim. If this is a recurring issue, construct the subagent brief as a *file package* (spec + signatures file) and run it with a read scope that excludes `tests/`. |
| Grep pre-check misses a novel hard-coding pattern | Phase 8 (human). Tune the regex set in Phase 6a as new patterns appear. |
| All subagents colluding on the same rubber-stamp | Phase 8. There is no agent-only solution. The adversarial brief in Phase 6b raises the floor but doesn't make it uncheatable. |
| Feature spec is wrong | Not this skill's problem. Run `/design-review` or `/dev-team-spec-review` before starting. |
| Description list is shallow AND QA rubber-stamps it | Human reads the committed list before Phase 4. If this feels like too much human labor, the feature may not warrant this skill. |

## Related

- `/verify-test` — hash-stamping a test file via `tdd_verify stamp`. Used in Phase 7.
- `/finishing-a-plan` — Step 2 testing audit catches residual gaming at plan close. Pairs well with this skill's Phase 8.
- `.claude/rules/testing.md` — suite structure, exemplars.
- `.claude/rules/test-philosophy.md` — Sandi Metz matrix, integration-as-spot-check (not safety net).
- Simon Willison, "A Software Library with No Code" — pure form of the spec-as-tests pattern (`whenwords` library).
- Simon Willison, "Red/green TDD" — the TDD shorthand this skill is built around.
