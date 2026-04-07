# GameServer Extraction Design Spec

**Date:** 2026-04-06
**Status:** Partially landed — see "Implementation Status" (rewritten 2026-04-07 after triage)
**Related spec:** `2026-04-06-test-verification-system-design.md`
**Related plan:** `docs/superpowers/plans/2026-04-07-stash-recovery-and-cleanup.md`

> **2026-04-07 update:** Triage of the post-stash-chaos state showed that more of this extraction actually made it onto `main` than the original "Implementation Status" section claimed. The "Lessons Learned" section is still useful as a record of what went wrong and how to avoid it next time. The "Implementation Status" at the bottom has been rewritten to reflect ground truth as of `11dce11`.

## Goal & Motivation

`nodes/game_server.gd` is a Node that holds significant pure logic. This violates the Pure Core Pattern (.claude/rules/design-philosophy.md): "All game logic lives in RefCounted or Resource, never Node. Nodes are thin wrappers that delegate to core objects. Test: if you can't unit-test without a scene tree, it's in the wrong place."

The symptom: 4 test files inline production logic from GameServer because they can't instantiate GameServer in a unit test. They reimplement the functions as local helpers and test the helpers, not the production code. Per the test verification system spec, these tests cannot be honestly stamped — the stamps would prove the helpers work, not that GameServer works.

| Test file | Inlines from GameServer |
|---|---|
| `tests/unit/test_object_state.gd` | All 17 tests use reimplemented `_transition_object`, `_damage_object`, `_update_ads_for_tuna`, `_update_ads_for_box`, `_box_state_for_hp` |
| `tests/integration/test_desire_scatter.gd` | 2 of 4 tests inline `_move_animals`, `_mark_animals_dirty` |
| `tests/integration/test_performing.gd` | 2 of 7 tests inline `_scatter_from_ads`, `_transition_object` |
| `tests/integration/test_tick_loop.gd` | 3 of 4 tests inline `_decay_commitment` |

The fix: extract the inlined functions into pure RefCounted core classes that can be unit-tested directly.

## Design

### Three extracted classes plus one folded method

Each extraction has one job, takes `GameStateDB` in its constructor, and is testable without a scene tree.

#### 1. ObjectStateManager → `engine/objects/object_state_manager.gd`

`class_name ObjectStateManager extends RefCounted`

Manages object state transitions, HP damage, and state→ads mapping. **The API is generic** — no per-type functions. The config is data, not code.

```gdscript
class_name ObjectStateManager extends RefCounted

const OBJECT_CONFIG: Dictionary = {
    &"tuna_can": {
        &"state_ads": {
            &"sealed": [{&"desire_type": &"openable", &"strength": 800, &"radius_ru": 3, &"action": &"open", &"action_duration": 30}],
            &"open": [{&"desire_type": &"food", &"strength": 800, &"radius_ru": 5, &"action": &"eat", &"action_duration": 50}],
            &"empty": [],
        },
    },
    &"cardboard_box": {
        &"state_ads": {
            &"new": [...],
            &"worn": [...],
            &"scraps": [...],
        },
        &"hp_thresholds": [
            {&"min_hp": 501, &"state": &"new"},
            {&"min_hp": 1, &"state": &"worn"},
            {&"min_hp": 0, &"state": &"scraps"},
        ],
    },
}

var _db: GameStateDB

func _init(db: GameStateDB) -> void:
    _db = db

# Set object state, then update its advertisements based on state→ads config
func transition_state(entity_id: int, new_state: StringName) -> void

# Reduce HP by amount, check HP→state thresholds, transition if changed
func damage(entity_id: int, amount: int) -> void

# Generic HP→state lookup. First threshold whose min_hp <= hp wins.
func get_state_for_hp(object_type: StringName, hp: int) -> StringName

# Generic state→ads lookup. Empty array means no ads.
func get_ads_for_state(object_type: StringName, state: StringName) -> Array
```

**Why generic, not per-type:** The first extraction attempt produced `update_ads_for_tuna` and `update_ads_for_box` as separate functions. Adding a new object type (pillow, shelf) would require new functions. The generic version reads everything from the config dictionary — new object types just add config entries. This is the same data-driven pattern as `state_advertisements` in the resting-on spec.

**Config location:** `OBJECT_CONFIG` lives as a Dictionary constant inside the class for now. It will move to JSON via ConfigRegistry once that exists. The interface stays the same.

**Empty ads array:** Means "remove the advertisements component." Treated as `[]`, not as a missing key.

#### 2. DesireScatter → `engine/desires/desire_scatter.gd`

`class_name DesireScatter extends RefCounted`

Extracts the per-entity ad scatter logic — for each animal with desires, find the best advertisement of each type within radius and apply diminishing-returns satisfaction.

```gdscript
class_name DesireScatter extends RefCounted

var _db: GameStateDB

func _init(db: GameStateDB) -> void:
    _db = db

# For each animal with desires, find the best ad per desire type within
# radius and apply satisfaction (skipping ads tagged with "action").
func scatter_from_ads() -> void
```

This replaces the current `_scatter_warmth_from_objects()` and `_scatter_comfort()` functions in GameServer, which both do essentially the same thing for different desire types. The scatter is generic — any desire type any object advertises gets scattered to nearby animals.

**Action ads are skipped.** An ad tagged with `"action"` (e.g., `"action": "open"` on a sealed tuna can) requires the animal to perform the action to get the satisfaction; it's not satisfied by passive proximity. The scatter loop filters these out. The list of desire types that are "action only" lives in a constant.

#### 3. MovementSystem → `engine/animals/movement_system.gd`

`class_name MovementSystem extends RefCounted`

Extracts the per-entity movement loop — animals in SEEKING/MOVING_TO/WANDERING states move toward their target, with arrival detection and nav graph reachability checks.

```gdscript
class_name MovementSystem extends RefCounted

var _db: GameStateDB
var _nav_builder: NavGraphBuilder

func _init(db: GameStateDB, nav_builder: NavGraphBuilder) -> void:
    _db = db
    _nav_builder = nav_builder

# Per-entity movement tick. Returns the IDs of entities that arrived
# at their target this tick, so the caller can dispatch arrival handling.
func tick() -> Array[int]
```

The arrival handling itself stays in GameServer for now — it dispatches to `_handle_arrival`, `_try_start_performing`, etc., which depend on cross-system coordination (action timers, ambient state pickers, performing state). Those are out of scope for this extraction.

**Why MovementSystem returns arrived entity IDs instead of calling arrival handlers directly:** It would couple movement to behavior dispatch. Returning IDs lets the caller (GameServer) decide what to do with them, keeping movement focused on "compute new positions and detect arrivals."

#### 4. DesireResolver.mark_all_dirty() — folded method

Add a public method to the existing `engine/desires/desire_resolver.gd`:

```gdscript
# Mark every entity that has a desires component as dirty.
# No species filter — robot arms, future smart objects, anything with
# desires gets evaluated.
func mark_all_dirty() -> void:
    var entities: Array[int] = _db.get_entities_with(&"desires")
    for entity_id: int in entities:
        mark_dirty(entity_id)
```

This replaces `_mark_animals_dirty` in GameServer. **Important:** the original function had a species filter (`if not _db.has_component(entity_id, &"species")`) which was a bug — it prevented robot arms and other non-species entities from being properly marked dirty. The new version drops the filter.

#### Out of scope for this extraction

- **Commitment decay.** GameServer's `_decay_commitment` operates on GameStateDB; AnimalStateMachine.tick() decays its own local commitment. Investigation needed before extracting — they may be redundant or may serve different code paths. Defer to a separate cleanup pass.
- **Arrival handlers.** `_handle_arrival`, `_try_start_performing`, `_arrive_ambient`, `_update_performing`, `_execute_action` — these depend on action timers, state machine transitions, and ambient state selection. Each is its own extraction, not in scope here.
- **Spawn helpers.** `_spawn_starter_entities`, `_spawn_cat`, `_spawn_tuna_can` — these are setup code, not hot-path tick logic. Lower priority.

### Sequential extraction order

The extractions are independent and can be done one at a time. Recommended order based on test impact:

1. **ObjectStateManager** — fixes `test_object_state.gd` (17 tests). Biggest single win.
2. **DesireScatter** — fixes 2 tests in `test_desire_scatter.gd` and 2 tests in `test_performing.gd`.
3. **MovementSystem** — fixes 2 tests in `test_desire_scatter.gd`.
4. **mark_all_dirty()** — fixes the species filter bug. Trivial change.

After each extraction:
1. Update `nodes/game_server.gd` to use the new class
2. Run all test suites, confirm green
3. Update the affected test files to call the extracted class instead of inlining
4. Re-run tests
5. Commit

## Lessons Learned (from failed attempts)

This extraction was attempted twice in the same session and failed both times. The lessons are specific and actionable.

> **2026-04-07 note on SHA references:** This section and the "Where things stand" table below cite specific commit SHAs (`39d969e`, `3c1bd18`, `8245d85`, etc.). These SHAs will be invalidated when Phase 5 of `docs/superpowers/plans/2026-04-07-stash-recovery-and-cleanup.md` runs `git lfs migrate import --everything`. Phase 5 Step 9 of that plan covers updating or annotating these references after the migration. Until then, the SHAs are still resolvable.

### Lesson 1: Worktrees with stale bases corrupt merges

**What happened:** An agent was dispatched in an isolated git worktree (`isolation: "worktree"`) to perform the extraction. The worktree was created from an older commit (`39d969e`), not from current `main` (which had moved to `3c1bd18` plus uncommitted work). The agent extracted code, ran tests against the old codebase, and reported "all 123 tests pass."

> **2026-04-07 note:** The forensic worktree (`agent-a2eea031` at `3c1bd18`) referenced below was removed during Phase 4 cleanup. The lessons in this section are still accurate, but the worktree itself no longer exists on disk. If you need to inspect the failed-extraction state, the underlying commit (`3c1bd18`) is still in the reflog until Phase 5's LFS migration rewrites history.

When I copied files from the worktree into `main`, the worktree's stale `desire_resolver.gd` overwrote the newer version in main. 15 tests immediately failed because the worktree's version had different scoring math than main's.

**Lesson:** Never use `isolation: "worktree"` for extractions or refactors that touch files which have evolved on main. Worktrees are safe for *exploratory* work where the agent's output is throwaway. They are dangerous when the agent's output is meant to be merged back, because the merge has no awareness that the worktree's base is stale.

**Rule for this extraction:** Do all extractions in the main working tree. No worktrees. No parallel agents. Sequential changes, committed between each step.

### Lesson 2: Type-specific APIs become legacy fast

**What happened:** The first extraction attempt produced `update_ads_for_tuna()`, `update_ads_for_box()`, and `box_state_for_hp()` as separate methods. The agent was just literally moving the existing functions. These names bake the current object types into the API — adding a pillow or shelf would require new methods.

**Lesson:** When extracting code, look at the *concept* being modeled, not the *current callers*. "Update ads for tuna" is a specialization of "look up ads for this object type and state." Extract the general concept; let the config carry the type-specific data.

**Rule for this extraction:** The API uses generic names (`transition_state`, `get_ads_for_state`, `get_state_for_hp`). Object types live in `OBJECT_CONFIG`, not in method names. Adding a new object type means adding a config entry, not writing new code.

### Lesson 3: "Mark animals dirty" is too narrow

**What happened:** The original `_mark_animals_dirty` in GameServer filtered to entities with a `species` component. This was probably written when only animals had desires, but it's a latent bug — robot arms have desires (they want "purpose"), and any future entity type with desires (smart boxes, plants, whatever) would be silently excluded from AI evaluation.

**Lesson:** Filters that look like type guards are often bugs in disguise. The right filter is "has the component you care about," not "is the type you happened to think of when writing this."

**Rule for this extraction:** `mark_all_dirty()` filters on `has_component(&"desires")` only. No species check.

### Lesson 4: Single-source merging beats parallel diff merging

**What happened:** I dispatched two agents in parallel worktrees (one for ObjectStateManager, one for DesireScatter). When the first one finished and reported success, I tried to merge it into main while the second was still running. The second was killed mid-work. Coordinating multiple worktrees touching the same file (`game_server.gd`) is a coordination nightmare.

**Lesson:** When the work is sequential by nature (each extraction modifies the same file), parallel agents create more coordination overhead than they save. One agent doing all extractions in sequence is faster than two agents racing in worktrees and then trying to merge.

**Rule for this extraction:** One agent. Sequential. In main. Commit between steps.

### Lesson 5: `git stash` is dangerous when you have substantial uncommitted work

**What happened:** When the merge failed and tests broke, I ran `git stash` to "test main without my changes." The stash swept up an entire session's worth of uncommitted work — Phase A test fixes, rule rewrites, the resting-on spec, the asset trackers, plus the user's earlier production work. Recovering required `git show stash@{0}:<file>` for each file individually, with no guarantee the recovery was complete.

**Lesson:** `git stash` is safe when you have a small focused change in flight. It is dangerous when you have many unrelated changes in flight, because the stash becomes the only copy of work that wasn't yours, and any failure to fully restore loses it.

**Rule for this extraction:** Commit work as it's verified green. Do not let uncommitted changes accumulate across multiple unrelated tasks. If a merge needs to be tested in isolation, create a branch, not a stash.

### Lesson 6: "All tests pass" from a worktree agent is a false signal

**What happened:** The worktree agent ran `script/checks/gut_tests` against the worktree (which had the stale base) and reported "all 123 tests pass." That report was true *for the worktree*, false for main. I trusted the report without checking the worktree's commit hash.

**Lesson:** Test results from worktrees are only valid for the worktree's base commit. When the base is stale, "tests pass" means "tests pass against a snapshot of main from N commits ago." That's not the same as "tests will pass when merged into current main."

**Rule for this extraction:** Since we're using lesson 1 (no worktrees), this lesson doesn't apply directly. But the general principle holds: trust test results only from the working tree they actually ran in.

## Plan of attack

Each extraction follows the same pattern:

### Step 1: Read the production code
Read the current functions in `nodes/game_server.gd` to understand their inputs, outputs, and dependencies.

### Step 2: Create the new core class
Write `engine/<area>/<class_name>.gd` with the extracted logic. Pure RefCounted, takes GameStateDB in constructor, generic API where applicable.

### Step 3: Update GameServer
Add an instance variable for the new class, create it in `_ready()`, replace the inlined logic with delegation. Delete the now-dead local methods.

### Step 4: Run all four test suites
```
/Applications/Godot.app/Contents/MacOS/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir="res://tests/unit" -gexit
/Applications/Godot.app/Contents/MacOS/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir="res://tests/scene" -gexit
/Applications/Godot.app/Contents/MacOS/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir="res://tests/integration" -gexit
/Applications/Godot.app/Contents/MacOS/godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir="res://tests/scenario" -gexit
```

All must pass before proceeding.

### Step 5: Update the affected test files
Replace inlined helpers in the test files with calls to the new class. Re-run tests.

### Step 6: Re-stamp the test files
Per the test verification system spec, run the full Phase 1-5 verification on the updated tests, then `script/stamp_tests` to seal them.

### Step 7: Commit
Commit message: `refactor: extract <ClassName> from GameServer`. Body explains what was extracted and why.

## Implementation Status

**As of `11dce11` (2026-04-07 verified by triage):**

| Item | Status | Where |
|---|---|---|
| `ObjectStateManager` (generic, config-driven) | ✅ Landed | `engine/objects/object_state_manager.gd` (committed in `8245d85`) |
| `DesireScatter` | ✅ Landed | `engine/desires/desire_scatter.gd` (committed in `8245d85`) |
| `DesireResolver.mark_all_dirty()` | ✅ Landed | `engine/desires/desire_resolver.gd:21`, called from `nodes/game_server.gd:53` |
| `MovementSystem` extraction | ❌ Never written | `git log --all -S "MovementSystem"` shows only this spec doc |
| 4 affected test files updated to call new classes | ❌ Still inline production logic | `test_object_state.gd`, `test_desire_scatter.gd`, `test_performing.gd`, `test_tick_loop.gd` |
| Re-stamp updated test files | ❌ Blocked on the row above | |

**Why the original status was wrong:** the previous session ended with the author believing the extractions had been lost in worktree merge failures. Triage on 2026-04-07 found that the production code for the first three items had actually made it into `8245d85 feat: object-interactions scaffolding` (probably as part of the same recovery push that pulled most of `stash@{0}` back into commits). The lost-artifact narrative carried over into this spec uncorrected. The spec is otherwise still accurate as a design reference.

**Caveat for whoever picks this up:** the production code on `main` was written under time pressure in the chaotic session and has not been re-verified against this spec's "generic API, no per-type functions" rule. Before resuming, diff the current `engine/objects/object_state_manager.gd` and `engine/desires/desire_scatter.gd` against the design in this spec. If they drifted toward type-specific APIs, fix that *before* extracting MovementSystem — it's much cheaper to fix two extractions than three.

**Remaining work:**

1. **Verify ObjectStateManager + DesireScatter match the spec design.** Read the current files. Confirm generic API. If the API drifted to per-type methods, refactor. Re-stamp affected tests.
2. **Extract `MovementSystem` from `nodes/game_server.gd`.** Sequential, in `main`, no worktrees, follow the "Plan of attack" section above.
3. **Update the 4 inlining test files** to call the extracted classes (`ObjectStateManager`, `DesireScatter`, `MovementSystem`) instead of reimplementing them. Phase 1-5 of the test verification checklist (mutation testing against the *real* production code is the safety net — tests that survive mutation against real code were giving false confidence before).
4. **Stamp the updated test files** via `script/stamp_tests`.
5. **Run `script/checks/verify_tests`** and confirm green.

**Blocker:** the DesireResolver WANDERING-vs-SEEKING regression (see `docs/superpowers/plans/2026-04-07-stash-recovery-and-cleanup.md` Phase 2) needs to be fixed first. The 4 inlining tests are downstream of `desire_resolver.gd` behavior, and re-stamping them against broken production code would seal the wrong behavior into the verification system.

## Known Limitations

### The four affected test files may need restructuring

The current tests reimplement helpers because GameServer wasn't testable. After extraction, some tests will be straightforward port-overs (call `ObjectStateManager.transition_state()` instead of the inlined helper). Others may be revealed as testing the wrong thing entirely — the local helper might have drifted from production over time, and the test was passing because the helper, not because the production code worked.

When re-stamping the updated tests, the Phase 2 mutation step is the safety net: mutate the *real* production code (the new core class) and confirm the test catches it. Tests that survive mutation against the real code were giving false confidence before.

### Arrival handlers and spawn helpers are still in GameServer

This extraction handles the hot-path tick logic that has test-coverage problems. Arrival handlers (`_handle_arrival`, `_try_start_performing`, etc.) and spawn helpers (`_spawn_starter_entities`, etc.) remain in GameServer. They're not currently inlined into tests, so they're not blocking the test verification system. They can be extracted later if/when they grow test coverage requirements.
