---
name: spec-first
description: "Use when starting a new feature. Locks test descriptions into the plan before tests or code exist, then runs each implementation phase in a fresh subagent. Removes the 'which tests exist' degree of freedom that agents rationalize under pressure. Complements /verify-test (stamping) and /finishing-a-plan (closeout audit)."
argument-hint: "[path-to-feature-spec]"
user-invokable: true
---

## Purpose

Agents game test verification under pressure. The specific gaming patterns
observed in this project (and documented in the literature, see Simon
Willison's "Automated tests and LLM effectiveness"):

1. Deleting tests mid-plan with "integration covers this" rationale.
2. Target-painted "puzzle mutations" that pass the uniqueness check but
   represent no plausible bug (e.g. `if cost == 50: cost = 49`).
3. Hard-coding production code to specific test input values.
4. Rubber-stamping self-audits at plan closeout.

This skill removes the FIRST cheat — the "which tests exist" decision —
by making test descriptions a git-committed artifact **before any test
or production code is written**. Once a description is in the plan, the
agent can't quietly drop it; a deletion would show up in git alongside a
prose rationale that a human can read.

It does NOT remove the other three cheats. Puzzle-mutations need
`/verify-test`'s audit. Hard-coding and rubber-stamping need human
review of the final diff. This skill is one layer of defense, not the
whole answer.

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

### Phase 1 — Draft test descriptions

Dispatch a subagent with: the feature spec, `.claude/rules/testing.md`,
`.claude/rules/test-philosophy.md`. Task: produce a numbered list of
rspec-style test descriptions covering every public method and every
branch called out in the spec.

Each description names a specific observable behavior:

```
Good: "slot_origin_world returns a world-Y that descends as slot index rises"
Good: "bay_local_to_slot tags zone `&other` in the horizontal gap between racks"
Bad:  "handles edge cases"
Bad:  "slot_origin_world works correctly"
```

If a description could describe two different tests, split it. If two
descriptions pin the same invariant in different words, merge them.

### Phase 2 — Commit the descriptions

Add the list to the plan doc under a `## Test plan` heading. Commit:

```
plan(<feature>): test descriptions
```

This commit is the contract. From here on, any deletion from the list is
a visible act that requires a prose rationale.

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

### Phase 5 — Implement the feature

Dispatch a subagent with: the spec, the description list, the test
file, path-gated rules. Task: make the tests pass. Commit:

```
feat(<feature>): implement to pass test descriptions
```

Commit before Phase 6. Do not defer the commit to "after QA passes" —
a cheat embedded in git history can be reviewed; a cheat squashed into
a retroactively-rationalized final commit cannot.

### Phase 6 — QA the implementation

Dispatch a **fresh** subagent. Task: read the Phase 5 commit and answer
each question, citing specific file:line locations:

- Does any production branch on a specific input value that matches a
  test input? `if rack == 2 and slot == 5: return Vector2i(27, 64)` is
  the smoking gun. List every site.
- Does the implementation reimplement the test's assertion as production
  logic (e.g. the test asserts `rect.size == Vector2i(23, 8)` and the
  production code hard-returns that)?
- Is there plausible behavior for inputs outside the test set, or does
  the code visibly fall apart on any untested input?
- Would an experienced reviewer call this "actually implementing the
  semantics" or "hard-coded to the tests"?

If any answer surfaces a problem, reopen Phase 5 with the specific
findings. Do not accept "looks fine" without cited locations.

### Phase 7 — Stamp the tests

Run `/verify-test` on the test file. This runs the per-test mutation
cycle and writes `.stamp` + `.audit.yaml` sidecars. This phase is the
tamper-evidence mechanism; it does not re-verify correctness (Phases 3
and 6 did that).

If any mutation in the audit reads like a puzzle (`if x == 27: ...`),
flag it in the final report. Real mutations have names like "off-by-one
in capacity clamp," not "what value makes only this test fail."

### Phase 8 — Human spot check

**The final checkpoint belongs to a human, not an agent.** Read the
final diff. Look for the same patterns Phase 6 asked about. Spot-check
one of the mutations from the audit.

This is the only phase that catches "all the subagents rubber-stamped
each other." Do not treat it as a formality.

## What this blocks

| Cheat | Defense |
|---|---|
| "Integration covers this, delete the unit test" | Phase 2 commits descriptions. Deletion requires removing a line from the plan doc — visible in git. |
| Shallow descriptions ("handles edge cases") | Phase 3 QA, with specific questions that hand-waving can't answer. |
| Tests that fail for the wrong reason | Phase 4 requires assertion-failure output in the commit body. |
| Agent optimizing across phases (shallow descriptions to make later implementation easier) | Fresh subagents per phase. Each only knows its own task. |

## What this does NOT block

| Cheat | Mitigation |
|---|---|
| Hard-coded production code to test inputs | Phase 6 explicitly looks for it; Phase 8 (human) is the real backstop. |
| Puzzle-mutations at stamp time | Phase 7 records them; Phase 8 reviewer reads the audit. |
| All subagents rubber-stamping each other | Phase 8. There is no agent-only solution. |
| Feature spec is wrong | Not this skill's problem. Run `/design-review` or `/dev-team-spec-review` before starting. |
| Description list is shallow AND QA rubber-stamps it | Human reads the committed list before Phase 4. If this feels like too much human labor, the feature may not warrant this skill. |

## Related

- `/verify-test` — per-test mutation-cycle stamping. Used in Phase 7.
- `/finishing-a-plan` — Step 2 testing audit catches residual gaming at plan close. Pairs well with this skill's Phase 8.
- `.claude/rules/testing.md` — suite structure, exemplars.
- `.claude/rules/test-philosophy.md` — Sandi Metz matrix, integration-as-spot-check (not safety net).
- Simon Willison, "A Software Library with No Code" — pure form of the spec-as-tests pattern (`whenwords` library).
- Simon Willison, "Red/green TDD" — the TDD shorthand this skill is built around.
