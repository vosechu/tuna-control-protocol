---
name: verify-test
description: "Use when writing, modifying, or verifying a test file — runs the full red-green-refactor + mutation + stamp protocol. Required before committing any new or changed test in tests/. Blocking for verify_tests to pass."
user-invokable: true
---

# LLM Test Verification

> **For agentic workers:** This is a mandatory checklist for every test you write. Follow each step in order. Do not skip steps. Do not mark a step complete until you have actually performed it and confirmed the result. The final step generates tamper-evident hashes — you cannot stamp tests without completing the full process.

**Goal:** Build confidence that LLM-produced tests actually test what they claim, catch regressions, and are protected from future modification.

**Trust chain:** `script/tdd_verify` drives the per-test red/green/mutate/restore cycle → records evidence in `.tdd-state.yaml` → `finish` writes the `.gd.stamp` and `.gd.audit.yaml` atomically → `script/checks/verify_tests` confirms hashes → pre-commit hook enforces.

**Run tests:** `script/checks/gut_tests`
**Verify a test file:** `script/tdd_verify start <file>` → per test: mutate, `mutation <name>`, restore, `restore <name>` → `finish`. tdd_verify is the **only** sanctioned stamping path; refuses duplicate mutations in a session and requires exactly one failing test per mutation step.
**Cosmetic re-stamp (lint/whitespace/comments):** `script/tdd_verify restamp <file> '<reason>'` — does not require a cycle but appends the reason to the audit file.
**Verify all stamps:** `script/checks/verify_tests` (checks every stamp exists, no orphans, all hashes match — used by CI and pre-commit).
**Artifacts:** `*.gd.stamp` (hashes) and `*.gd.audit.yaml` (mutation trail) sidecars alongside each test file.

### Task structure

Create tasks using this pattern. Phase 1 produces the candidate list; each candidate becomes its own task; then two tasks to close out.

1. **Identify test candidates for [module]** — Phase 1. Produces a numbered list of test function names.
2. **Red-green-refactor: [test_function_name]** — Phase 2. One task per test candidate. The full Steps 5-13 cycle for a single test.
3. *(repeat task 2 for each candidate)*
4. **Quality + QA review for [module]** — Phases 3 + 4 combined. Review all tests, dispatch QA agent, address issues.
5. **Stamp tests for [module]** — Phase 5. `script/tdd_verify start → mutation/restore per test → finish`, then `script/checks/verify_tests`.

Do not create all tasks upfront. Create task 1 first. After task 1 completes, create one task per candidate plus the two closing tasks.

---

## Phase 1: Identify Test Candidates

For the code you are writing or modifying, determine what tests are needed.

- [ ] **Step 1: Identify all public methods** in the module/class being implemented or modified.

- [ ] **Step 2: Map branches to test cases.** For each public method:
  - One test for the happy path
  - One test for each side of each branch (if/else, match cases, early returns, error paths, guard clauses)
  - List these as concrete test function names with descriptive behavior names (e.g., `test_occupancy_rejects_when_weight_exceeds_capacity`)

- [ ] **Step 3: Prune duplicates.** Review the list — some branches exercise the same assertion. Remove redundant cases. The goal is full branch coverage with no waste, not maximum test count.

- [ ] **Step 4: Cross-reference existing tests.** Check if any of these cases are already covered by tests with AI-DEV markers (verified tests). Do not re-test what is already verified. Do not modify verified tests.

## Phase 2: Red-Green-Refactor (per test)

For EACH test identified in Phase 1, run this cycle. Do not batch — one test at a time.

- [ ] **Step 5: Write the failing test.** Write a single test function. The test name MUST describe the specific behavior being asserted, not the method name. A reader who sees only the test name should correctly predict what the test does.

- [ ] **Step 6: Red — confirm failure.** Run: `script/checks/gut_tests`. The new test MUST fail. If it passes, the test is not testing new behavior — investigate why before proceeding.

- [ ] **Step 7: Write the minimum implementation.** Write just enough production code to make the test pass. No more.

- [ ] **Step 8: Green — confirm pass.** Run: `script/checks/gut_tests`. The new test MUST pass. All previously passing tests MUST still pass.

- [ ] **Step 9: Mutate the production code.** Make a targeted change to the specific production code the test exercises. The goal is to prove the test actually catches regressions. Good mutations:
  - Flip an operator (`+` to `-`, `<` to `>`, `>=` to `<`)
  - Change a return value (`true` to `false`, `0` to `1`)
  - Comment out a key line in the function under test

  For **new code** (Steps 5-8 just written): delete or comment out the code you wrote in Step 7.
  For **existing code** (verifying tests that already exist): mutate the specific function the test covers. Do NOT delete the whole function if other tests depend on it — make a surgical change that only the test under verification should catch.

- [ ] **Step 10: Red — confirm the test catches the mutation.** Run via `script/tdd_verify mutation <test_name>` (preferred — records evidence) or `script/checks/gut_tests` (manual). Confirm:
  - The test under verification fails (proves it depends on the production code)
  - **Exactly ONE test fails within a suite.** `tdd_verify mutation` enforces this. If two or more tests in the same suite fail under one mutation, the mutation is too broad — redesign it to target a more specific branch, or rewrite the tests so each covers a distinct behavior. Failures spanning different suites (e.g. a unit test plus a related integration test) are acceptable; multiple failures inside one suite are not.

- [ ] **Step 11: Restore the production code.** Revert the mutation exactly.

- [ ] **Step 12: Green — confirm everything passes again.** Run: `script/checks/gut_tests`. All tests pass. If they don't, the restoration was incomplete.

- [ ] **Step 13: Refactor.** Clean up the production code while keeping all tests green. Run tests after refactoring. (Skip for existing code verification — nothing to refactor.)

**Repeat Steps 5-13 for each test identified in Phase 1.**

## Phase 3: Test Quality Review

After all tests from Phase 2 are green, review the complete test file.

- [ ] **Step 14: Check test names match assertions.** For each test: does the name describe the behavior? Do the assertions verify what the name claims? LLMs refactor tests and forget to update names.

- [ ] **Step 15: Check for trivially passing tests.** Look for:
  - Tests that assert on mock return values
  - Tests that verify `true == true`
  - Tests that only check setup ran (asserting a mock was called without checking the result)
  - Tests where removing all asserts would still "pass"

- [ ] **Step 16: Check for duplicate tests in disguise.** Different names but same assertions exercising the same code path.

- [ ] **Step 17: Check tests test code, not mocks.** A test that mocks everything and asserts the mock was called is testing your test setup, not your code.

The marker MUST be inside each individual test function, not at the file level.

## Phase 4: QA Review

- [ ] **Step 18: QA agent review.** Dispatch the QA agent (game-qa) to review the tests. Provide it with:
  - The production code being tested
  - The complete test file
  - The list of test candidates from Phase 1

  The QA agent checks:
  - Are there missing edge cases?
  - Do the tests cover the failure modes that would ship bugs?
  - Are the tests resilient to implementation changes (testing behavior, not implementation)?

  Address any issues the QA agent raises by returning to Phase 2 for new tests or Phase 3 for fixes.

## Phase 5: Stamp Verification Hashes

Only after ALL previous phases are complete.

- [ ] **Step 19: Drive the cycle through `script/tdd_verify`.**

```bash
script/tdd_verify start tests/unit/test_your_file.gd
# for each test:
#   edit production to introduce a targeted mutation
script/tdd_verify mutation test_name_here
#   revert the mutation
script/tdd_verify restore test_name_here
# after all tests cycled:
script/tdd_verify finish
```

`tdd_verify` owns the test runs and records evidence as it goes. `mutation` fails unless the targeted test — and no other test in the same suite — fails. `finish` refuses to stamp if any expected test has not completed a full mutation + restore, or if two mutation tree-hashes collide (duplicate mutations). On success it writes `.gd.stamp` + `.gd.audit.yaml` and removes `.tdd-state.yaml`.

`script/tdd_verify` is the ONLY sanctioned way to produce or update a `.gd.stamp` file. There is no separate stamper — the audit trail lives in tdd_verify.

- [ ] **Step 20: Run the verify script to confirm the stamp is valid.**

```bash
script/checks/verify_tests
```

This checks three things:
1. Every test file has a `.gd.stamp` sidecar
2. No orphan `.gd.stamp` files without a corresponding test
3. All setup hashes and per-test hashes in stamps match the current file contents

This step should pass immediately after `tdd_verify finish` — it's a sanity check that the stamp wrote correctly.

---

## Rules for Verified Tests

### Verified tests MUST NOT be modified

If a verified test is failing, fix the production code, not the test. The test is the source of truth.

If a test's **behavior** genuinely needs to change (API change, expected-value change, new assertion, modified setup, restructured test logic), the old hash must be invalidated and the full Phase 2-5 cycle must be re-run for the modified test. There is no shortcut.

### Cosmetic-only changes: re-stamp without re-verification

A narrow exception exists for changes that demonstrably do not affect what the test verifies. **Re-stamping without the full Phase 2-5 cycle is permitted ONLY when ALL of the following are true:**

1. **The diff is purely non-semantic.** Allowed: whitespace, line wrapping, indentation, comment edits, renaming an unused variable, removing a discarded return-value assignment, reordering imports. Forbidden: anything that touches assertion arguments, expected values, conditionals, loop bounds, mock configuration, setup data, or the order of side-effecting calls.
2. **The change was forced by an external constraint.** Examples: a linter rule applied to the file, an unrelated refactor renamed a helper, a code-style sweep. Never re-stamp because you "improved" or "cleaned up" a verified test on your own initiative.
3. **The full test suite still passes** with the modified test included. Run `script/checks/gut_tests` and confirm zero failures before re-stamping.
4. **You can articulate the diff in one sentence** without referring to test logic. If you find yourself explaining what the test does, the change isn't cosmetic — go through the full cycle.

If all four conditions hold, run `script/tdd_verify restamp <file> '<one-sentence reason>'` to refresh the seal. The reason is appended to the audit file alongside a timestamp. The commit message must state the same reason (e.g. "lint fix: wrap long lines in test_desire_resolver.gd; behavior unchanged").

**Transparency requirement:** When re-stamping under this exception, explicitly state in your response to the user: (a) that you are re-stamping without full re-verification, (b) which condition applies, and (c) what the specific change was. Do not silently re-stamp and move on — the user should be able to challenge the judgment call. A silent re-stamp that turns out to be wrong is worse than a verbose one that gets caught.

**When in doubt, run the full Phase 2-5 cycle.** The cost of an unnecessary re-verification is small. The cost of re-stamping a behavior change without re-verification is silently shipping a broken test.

**This exception does not apply to:**
- Tests that have never been verified (no stamp exists). New stamps require the full Phase 1-5 process.
- Tests where a previous re-stamp was already done as a cosmetic exception. Re-stamping a re-stamp without verification compounds the trust gap. The next change to that test must go through full verification.

### Pre-commit and CI enforcement

`script/checks/verify_tests` runs in both the pre-commit hook and CI (`script/validate`). It performs the three checks (stamps exist, no orphans, hashes match). If any check fails, the commit is blocked. The error output describes only the *state* of each failing file (modified, unstamped, orphaned) — it does not prescribe a fix, because the correct response depends on whether the change was behavioral or cosmetic. Refer back to this rule to choose the right path.

### Stamp file format

Each test file gets a sidecar stamp file alongside it:

```
tests/unit/test_desire_resolver.gd
tests/unit/test_desire_resolver.gd.stamp
```

Contents of the `.gd.stamp` file:

```yaml
# AI-DEV: AI **MUST NOT** edit this file. It is generated by the verification
# process defined by the /verify-test skill. If a stamp is
# invalid, re-run the full verification process — do not manually update hashes.
setup_hash: a1b2c3d4
verified_at: 2026-04-05T14:30:00Z
tests:
  test_food_outscores_warmth_when_hungry: e5f6a7b8
  test_distance_sensitivity_affects_scoring: c9d0e1f2
```

`setup_hash` covers all non-test functions: `before_each`, `after_each`, `before_all`, `after_all`, private helpers (`_make_*`), and top-level `var` declarations. A change to any of these invalidates ALL test stamps in the file, since any test could depend on any helper. Per-test hashes cover only individual `test_*` function bodies.

This means: changing a test function body invalidates only that test's stamp. Changing setup code invalidates all stamps in the file. Adding a comment outside any function invalidates nothing.

### What `script/checks/verify_tests` checks

Three things, in order:

1. **Every test file has a stamp.** Globs for `tests/**/test_*.gd`, checks each has a corresponding `.gd.stamp`. Missing stamps are listed by name.
2. **No orphan stamps.** Globs for `tests/**/*.gd.stamp`, checks each has a corresponding `.gd` file. Orphan stamps are listed by name.
3. **All stamps match.** For each stamp file: recomputes the setup hash and per-test-function hashes against the current `.gd` file. Stale hashes are listed by test name.

Exits non-zero if any check fails. Output names every failing file/test so the developer knows exactly what to re-stamp.

### Handling stale stamps

- **Test body changed, stamp not updated:** `verify_tests` fails check 3. Run the full `tdd_verify` cycle for that file.
- **Test function renamed:** Old entry in stamp has no matching function (check 3 fails), new function has no hash (check 3 fails). Run the full cycle.
- **Test file deleted:** Orphan stamp/audit detected (check 2). Delete the `.gd.stamp` **and** `.gd.audit.yaml` sidecars.
- **New test file added:** Missing stamp detected (check 1). Run the full `tdd_verify` cycle for the new file.
- **Helper/fixture changed:** `setup_hash` mismatch (check 3). All tests in the file need re-verification since any test could depend on the changed helper.

### Hitchhike unrelated cleanup onto setup-hash rehashes

When `setup_hash` is going to be invalidated anyway — because you're adding a test, modifying `before_each`, or renaming a helper — that is the moment to land other hygiene changes in the same file at zero extra rehash cost: freeing leaked Nodes in `before_each`, converting bare `preload(...).new()` to `add_child_autofree(...)`, deleting dead helpers, fixing type annotations. Every test in the file is already going through a full mutation + restore cycle; bundling a hygiene fix adds no cycles.

Do **not** cause the rehash for hygiene alone — the mutation-cycle cost isn't worth it. Wait for a real trigger and piggy-back.

---

## System Architecture

Five artifacts cooperate. Each has one job; the separation is deliberate.

```
Skill (this file)         — the Phase 1–4 checklist the agent works through
     ↓
script/tdd_verify         — owns the test runs; enforces red/green/mutate/restore
     ↓
.tdd-state.yaml (transient) — session state, deleted on finish, git-ignored
     ↓
.gd.stamp + .gd.audit.yaml — both committed to git; stamp = hashes, audit = trail
     ↓
script/checks/verify_tests — pre-commit + CI check the hashes match current code
     ↓
Commit proceeds (or is blocked)
```

1. **The skill** — this file. Task-gated (invoked when writing or verifying tests). The agent works through Phases 1–4 in their head; Phase 5 is driven by the script.
2. **`script/tdd_verify`** — Ruby CLI that runs the test suite itself for each step. It refuses to stamp without a full cycle, rejects duplicate mutations, and writes both the stamp and the audit atomically on `finish`. Earlier versions had a separate `stamp_tests` writer; it is deleted. Trust now lives in the tool's enforcement, not only in human review.
3. **`script/lib/test_stamp.rb`** — shared hashing logic used by both tdd_verify (writer) and verify_tests (reader). One implementation so writer and reader cannot disagree.
4. **`script/checks/verify_tests`** — Ruby reader. Pure: three checks (stamps exist, no orphans, hashes match). No arguments, checks everything. Runs in CI and the pre-commit hook.
5. **The sidecars** — `*.gd.stamp` (flat YAML of hashes) and `*.gd.audit.yaml` (mutation_at, mutation_tree_hash, restored_at per test, plus restamp reasons). Both committed to git and reviewed alongside the test.

### Hashing rules

- **Hashes are first 8 hex chars of SHA-256.**
- **File hash** (or `setup_hash`) covers the whole file (or all non-test functions — see the Stamp File Format section above for the current scope).
- **Per-test hash** covers the function body from `func test_*` through the next top-level statement, with `# AI-DEV:` lines excluded and trailing whitespace stripped.
- Both scripts share helper functions for `get_test_functions`, `get_function_body`, and the SHA-256 truncation. If these drift, every stamp becomes invalid. Keep them in sync.

### Why per-test hashes exclude AI-DEV lines

So an agent can add or update an `# AI-DEV` marker on a stamped test without invalidating the per-test hash. The file hash still catches the change (forcing a re-stamp), but the per-test logic is consistent with or without the marker.

### Why a sidecar instead of inline markers

- **Tamper resistance.** An agent editing a test file can't accidentally update test and hash in lockstep — the stamp is in a different file, updated by a different script.
- **Diff visibility.** Stamps show up next to test changes in PRs, making it obvious which tests were re-verified vs. modified without verification.

### Why per-file stamps instead of a central registry

A central `tests/.test_registry.yaml` would conflict every time two branches added or modified tests. Per-file stamps only conflict when two branches modify the *same* test file — which is a real conflict that needs human attention anyway.

---

## Known Limitations

### Stamps do not protect the test/production relationship

A stamp verifies the test file's *content* hasn't changed. It does **not** verify that the production values the test asserts against haven't changed. A stamped test can go silently stale when production constants shift — the stamp stays valid, the assertions still run, they just compare against the wrong numbers.

The correct signal here is a *failing* stamped test after a production change — the agent investigates, fixes one side or the other, then re-stamps. The bad outcome is someone re-stamping a stale test without fixing it, sealing the wrong assertions. Phase 2's mutate-and-reverify step is the defence: when re-stamping a previously-stamped file, confirm mutation testing was actually re-run, not skipped because the file already had a stamp.

### Helper file changes don't invalidate stamps

If a test imports a helper or fixture file and the helper changes, the test's hash doesn't break. The test could now behave completely differently and the stamp would still be valid.

Mitigations: minimize helper dependencies; when a helper changes, manually re-stamp all dependent tests (agent responsibility, not mechanically enforced).

### Mutation testing is manual

Phase 2's mutation step relies on the agent picking a good mutation. No GDScript mutation framework exists, so this is the most judgment-heavy step in the process. The post-stamp code review catches cases where the mutation was too narrow.

### When a mutation survives the targeted test

If the targeted test doesn't fail under your mutation, the first thing to check is whether the production code uses defense-in-depth — two independent guards that would both have to break for behavior to change. In that case, pick a smaller mutation that only disables *one* guard. Do not weaken the production code to make a test fail.

Do **not** use "surviving mutations are fine" as an escape hatch. The bar is still: each test must fail alone under at least one surgical mutation of the code it's claiming to test. If you cannot construct such a mutation, the test is not verifying what its name claims — rewrite the test or delete it.

### Multiple tests failing under one mutation is not acceptable

If two or more tests **in the same suite** fail under a single mutation, those tests are not testing distinct behaviors — they are redundant descriptions of the same code path. Fix one of the following, do not paper over it:

- Narrow the mutation until only one test fails.
- Rewrite the tests so each pins down a different behavior (different inputs, different assertions, different branches).
- Delete the duplicate(s).

Failures spanning **different suites** (a unit test plus a related integration test) are acceptable — they're verifying the same behavior at different layers, which is valuable. Failures inside one suite are not.

`script/tdd_verify mutation` enforces this automatically by requiring exactly one failing test within the suite being verified.
