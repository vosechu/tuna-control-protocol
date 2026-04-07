# LLM Test Verification

> **For agentic workers:** This is a mandatory checklist for every test you write. Follow each step in order. Do not skip steps. Do not mark a step complete until you have actually performed it and confirmed the result. The final step generates tamper-evident hashes — you cannot stamp tests without completing the full process.

**Goal:** Build confidence that LLM-produced tests actually test what they claim, catch regressions, and are protected from future modification.

**Trust chain:** Checklist runs → each step produces checkable artifacts → stamp script seals the result → verify script checks hashes → pre-commit hook enforces.

**Run tests:** `script/checks/gut_tests`
**Stamp tests:** `script/stamp_tests <test_file>` (computes hashes, writes `.gd.stamp` sidecar)
**Verify tests:** `script/checks/verify_tests` (checks all stamps exist, no orphans, all hashes match — used by CI and pre-commit)
**Stamp files:** `*.gd.stamp` sidecar files alongside each test file

### Task structure

Create tasks using this pattern. Phase 1 produces the candidate list; each candidate becomes its own task; then two tasks to close out.

1. **Identify test candidates for [module]** — Phase 1. Produces a numbered list of test function names.
2. **Red-green-refactor: [test_function_name]** — Phase 2. One task per test candidate. The full Steps 5-13 cycle for a single test.
3. *(repeat task 2 for each candidate)*
4. **Quality + QA review for [module]** — Phases 3 + 4 combined. Review all tests, dispatch QA agent, address issues.
5. **Stamp tests for [module]** — Phase 5. Run `script/stamp_tests`, then `script/checks/verify_tests`.

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

- [ ] **Step 10: Red — confirm the test catches the mutation.** Run: `script/checks/gut_tests`. Confirm:
  - The test under verification fails (proves it depends on the production code)
  - Ideally exactly ONE test fails (proves the mutation was targeted). If multiple tests fail, that's okay — it means multiple tests cover this code path. But if ALL tests fail, the mutation was too broad — make it more surgical.

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

- [ ] **Step 19: Run the stamp script.**

```bash
script/stamp_tests tests/unit/test_your_file.gd
```

`script/stamp_tests` is a simple write operation:
1. Reads the test file
2. Computes a hash of the full file
3. Computes a hash of each test function body
4. Writes both to the sidecar `.gd.stamp` file alongside the test (e.g., `test_desire_resolver.gd.stamp`)

The stamp script does NOT run tests or verify anything. The verification already happened through Phases 1-4 of this checklist. The stamp seals the result.

- [ ] **Step 20: Run the verify script to confirm the stamp is valid.**

```bash
script/checks/verify_tests
```

This checks three things:
1. Every test file has a `.gd.stamp` sidecar
2. No orphan `.gd.stamp` files without a corresponding test
3. All file hashes and per-test hashes in stamps match the current file contents

This step should pass immediately after `script/stamp_tests` — it's a sanity check that the stamp wrote correctly.

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

If all four conditions hold, run `script/stamp_tests <file>` to refresh the seal. The commit message must state which condition forced the change (e.g. "lint fix: wrap long lines in test_desire_resolver.gd; behavior unchanged").

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
# process defined in .claude/rules/llm-test-verification.md. If a stamp is
# invalid, re-run the full verification process — do not manually update hashes.
file_hash: a1b2c3d4
verified_at: 2026-04-05T14:30:00Z
tests:
  test_food_outscores_warmth_when_hungry: e5f6a7b8
  test_distance_sensitivity_affects_scoring: c9d0e1f2
```

### What `script/checks/verify_tests` checks

Three things, in order:

1. **Every test file has a stamp.** Globs for `tests/**/test_*.gd`, checks each has a corresponding `.gd.stamp`. Missing stamps are listed by name.
2. **No orphan stamps.** Globs for `tests/**/*.gd.stamp`, checks each has a corresponding `.gd` file. Orphan stamps are listed by name.
3. **All stamps match.** For each stamp file: recomputes the file hash and per-test-function hashes against the current `.gd` file. Stale hashes are listed by test name.

Exits non-zero if any check fails. Output names every failing file/test so the developer knows exactly what to re-stamp.

### Handling stale stamps

- **Test body changed, stamp not updated:** `verify_tests` fails check 3. Re-run `script/stamp_tests` for that file.
- **Test function renamed:** Old entry in stamp has no matching function (check 3 fails), new function has no hash (check 3 fails). Re-stamp the file.
- **Test file deleted:** Orphan stamp detected (check 2). Delete the `.gd.stamp` file.
- **New test file added:** Missing stamp detected (check 1). Run `script/stamp_tests` for the new file.
- **Helper/fixture changed:** Not tracked in v1. Known gap — test dependencies are a v2 concern.
