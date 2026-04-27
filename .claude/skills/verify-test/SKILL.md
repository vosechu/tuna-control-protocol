---
name: verify-test
description: "Use when writing, modifying, or verifying a unit test file. Runs the red-green-commit discipline and hash-seals the file via `tdd_verify stamp`. Required before committing any new or changed test in tests/unit/. Pairs with /spec-first (which handles the bug hypothesis and information-hiding parts)."
user-invokable: true
---

> **For agentic workers:** This is a short checklist. Follow each step in order. Do not skip. The stamp at the end is tamper-evident — future edits to the test body will fail `script/checks/verify_tests` until re-stamped.

## What this skill is for

Stamping a test file pins the hash of its setup block and each test
function. `script/checks/verify_tests` reads those hashes in CI and
pre-commit; if the file content drifts without a re-stamp, the build
fails. That's the tamper-evidence guarantee.

**What this skill does NOT do:**
- It does not run a mutation cycle or prove each test depends on
  production code. The mutation cycle was removed — it produced
  gaming pressure (puzzle-mutations, target-painted branches) without
  adding real coverage. See the commit that removed it for details.
- It does not decide which tests should exist. For feature work, that's
  `/spec-first`'s job — bug hypotheses are written up front in the plan
  doc, and implementation runs in an information-hidden subagent. This
  skill is the final stamping step after tests are already written.

## When to use

- Finishing a new unit test file (new tests written, production code
  passes).
- Modifying an existing test's body in a way that changes behavior or
  assertions.
- Adding or removing a test function in an existing file.

## When to use `tdd_verify restamp` instead

Cosmetic-only changes where the test behavior is unchanged:
- Lint-forced whitespace or line-wrapping.
- Comment edits that don't change assertion logic.
- Renames of unused local variables or helpers the tests don't
  reference.

Any change to assertions, expected values, setup data, or branch logic
is not cosmetic — run the full red-green-commit cycle and stamp
normally, don't restamp.

---

## Steps

### 1. Write the failing test

The test name must describe the specific behavior being asserted, not
the method name. A reader who sees only the test name should correctly
predict what the test does.

Include the AI-DEV protection marker as the first line inside the
function body:

```gdscript
func test_drain_action_floors_at_zero() -> void:
    # AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
    var hum_id: int = _make_hum()
    _db.set_field(hum_id, &"hum", &"reserve", 10)
    _hum.drain_action(hum_id, 100)
    assert_eq(_hum.get_reserve(hum_id), 0,
        "Draining 100 from reserve 10 should reach exactly 0 (floor)")
```

### 2. Red — confirm failure

Run:

```bash
script/checks/gut_tests -f tests/unit/<your_file>.gd
```

The new test MUST fail. The failure MUST be an assertion failure, not
a parse error or missing symbol. A parse error means the test wasn't
actually testing the behavior — rewrite so the specific missing
behavior is what fails.

### 3. Write minimum implementation

Just enough production code to make the test pass. No more. Don't add
unrequested features or refactor adjacent code.

### 4. Green — confirm pass

```bash
script/checks/gut_tests -f tests/unit/<your_file>.gd
```

The new test MUST pass. All previously passing tests MUST still pass.

### 5. Repeat for each test

For a new test file with multiple tests, cycle 1–4 one test at a time.
Do not write all the tests up front, then all the production code.

### 6. Stamp the file

```bash
script/tdd_verify stamp tests/unit/<your_file>.gd
```

This runs the tests once more, confirms green, and writes the
`.gd.stamp` sidecar with hashes of the setup block and each test body.

### 7. Commit

Commit the test file, the production changes, and the `.gd.stamp`
sidecar together:

```bash
git add tests/unit/<your_file>.gd tests/unit/<your_file>.gd.stamp engine/...
git commit -m "test(<system>): <what this test pins>"
```

---

## Test quality — the short version

For more, see `.claude/rules/test-philosophy.md`.

- **Black-box the object.** Test the interface, not the implementation.
- **One assertion per unit test** (integration tests may have more).
- **Test name describes the behavior, not the method.**
- **Don't test private methods, outgoing queries, or third-party APIs
  directly** (wrap, mock the wrapper).

### Sandi Metz test matrix

|             | Incoming query        | Incoming command     | Outgoing command     |
|-------------|-----------------------|----------------------|----------------------|
| **Query**   | Assert return value   | —                    | Don't test           |
| **Command** | —                     | Assert side effect   | Mock — verify send   |

Don't test outgoing queries. Don't test private methods.

---

## Common failure modes

| Symptom | Likely cause |
|---|---|
| `verify_tests` fails on my test file | Someone edited the test body without re-stamping. Run `tdd_verify stamp`. |
| Test passes on first run without any production changes | You're not testing new behavior. Re-read the test, confirm it asserts something the production code doesn't already handle. |
| Test fails with parse error instead of assertion failure | The test references a symbol that doesn't exist yet. Stub the symbol so the test can parse, then fail on the assertion. |
| Stub exists in a new file but Godot still says "Identifier X not declared" | `class_name X` registrations need a project import to land. Run `/Applications/Godot.app/Contents/MacOS/godot --headless --import` once after creating the file, then re-run the test. |
| Multiple tests in the file fail after my change | Your production change had a broader effect than intended, or you edited shared setup. Check `before_each` and helpers. |

---

## Related

- `/spec-first` — for feature work, bug hypotheses + information-hiding are authored up front. This skill is the final stamping step within that flow.
- `.claude/rules/test-philosophy.md` — black-box, Sandi Metz matrix, integration-vs-unit.
- `.claude/rules/testing.md` — suite structure, exemplars per suite.
- `script/checks/verify_tests` — CI gate that reads stamps.
