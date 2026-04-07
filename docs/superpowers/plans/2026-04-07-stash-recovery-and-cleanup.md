# Stash Recovery & Cleanup Plan

**Date:** 2026-04-07
**Status:** Open
**Triage source:** Read-only `triage-chaotic-git-state` skill run on 2026-04-07

## Why this plan exists

A previous session got tangled up between the object-interactions feature, the grid redesign (24px/U → 7px/U, 5 racks → 7), and a parallel GameServer extraction attempt. `git stash` was reached for as a panic button and swept up a session's worth of unrelated work into `stash@{0}`.

Most of that stash content (19 of 28 files) was later recovered into proper commits (`8245d85`, `9cc612b`, `61b2e51`). The recovery was *almost* complete. This plan captures the remaining work so we never need to re-run the chaotic-git-state triage on this incident.

**Strategy:** Conservative (Option 1 from triage report). Recover the one file that still matters, fix the production-logic regression that the recovery exposes, then clean up the stashes and stale worktrees once we're satisfied. Do not revert. Do not pop stashes wholesale.

## Ground truth before starting

- **Safe harbor:** `3c1bd18 docs: add hook and compile check info to CLAUDE.md` — last commit before the chaos. Always available via `git checkout 3c1bd18` for inspection.
- **`stash@{0}`:** `WIP on main: 3c1bd18 …`. 28 files. 19 already identical to main. Of the 9 that differ:
  - `tests/unit/test_constants.gd` — **stash version is the correct one** (asserts the new 7px/U scale). Main has the stale 24px/U asserts. **Recoverable.**
  - `PLANNING.md` — stash adds a "Known Issues" section. **Obsolete** — that content lives in `CLAUDE.md` now.
  - `.claude/agents/game-artist.md` — stash adds a 94-line art-style block. **Obsolete** — content moved to `.claude/skills/generate-pixel-sprites/SKILL.md`.
  - `CLAUDE.md`, `nodes/animal_node.gd`, `nodes/camera_controller.gd`, `nodes/game_client.gd`, `nodes/heat_overlay.gd`, `nodes/sound_manager.gd` — bidirectionally diverged. Main has newer work that the stash doesn't. **Leave the stash version alone.**
- **`stash@{1}`:** `WIP on worktree-agent-a2eea031 …`. 233 files, 232 of them binary stubs truncated to ~128 bytes (the LFS/worktree-agent disaster pattern), plus an 8-line `desire_resolver.gd` addition. **The stash IS the corruption** — applying it would replace real assets with stubs. **Drop candidate, not recovery candidate.**
- **Worktrees:** 11 total under `.claude/worktrees/`.
  - 10 pinned to ancient `39d969e` — stale agent leftovers.
  - 1 pinned to `3c1bd18` (`agent-a2eea031`) — referenced by `2026-04-06-game-server-extraction-design.md` as the failed-extraction worktree.
  - 1 was the active feature branch `auto-mode-phase1` — **already merged into `main` and removed on 2026-04-07.** Not present anymore.

## Test failure clusters at the start of this plan

19 failing tests reduce to 3 root causes:

1. **Stale `test_constants.gd` (cluster 1, 4 tests)** — production at 7px/U/7-rack, tests at 24px/U/5-rack. Pure recovery. Fixed by Step 1 of this plan.
2. **DesireResolver WANDERING-vs-SEEKING regression (cluster 2, ~8 tests)** — cats with a warm server in range transition to `WANDERING` instead of `SEEKING`. Warmth scoring also has a non-zero floor (warm cat scores warm server at 360, expected <50). Real production interaction between the WANDERING state (commit `e584381`) and the scatter extraction in `8245d85`. **Not in any stash.** Fixed by Step 2.
3. **Curiosity scoring floor (cluster 3, 1 test)** — `test_satisfied_cat_scores_curiosity_at_zero`: satisfied curiosity (1000) scores 30, expected 0. Same scoring-floor bug as cluster 2. Fixed by Step 2 (or trivially adjacent to it).

The 3 integration + 4 scenario failures are downstream cascades from clusters 2-3.

---

## Phase 1 — Recover the one file the stash still owns

- [ ] **Step 1: Restore `tests/unit/test_constants.gd` from `stash@{0}`.**
  ```bash
  git show 'stash@{0}:tests/unit/test_constants.gd' > tests/unit/test_constants.gd
  ```
  This is a one-file write. The stash itself is not touched. Reversible via `git checkout HEAD -- tests/unit/test_constants.gd` if needed.

- [ ] **Step 2: Re-stamp the file.**
  ```bash
  script/stamp_tests tests/unit/test_constants.gd
  script/checks/verify_tests
  ```
  Per the test verification system, the file's old hash is now invalid. Re-stamping after recovery is correct because the new content matches the production constants — the test was written and verified before, just for the wrong scale.

- [ ] **Step 3: Confirm cluster 1 is gone.**
  ```bash
  /Applications/Godot.app/Contents/MacOS/godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_constants.gd -gexit
  ```
  Expect 7/7 passing. If `test_rack_stride` (the new test the stash adds) fails because `RACK_STRIDE_PX`/`RACK_STRIDE_PU` don't exist, that's a red flag — they should exist (constants.gd already has them). Investigate before continuing.

- [ ] **Step 4: Commit.** `fix(test): restore test_constants.gd to 7px/U scale (recovered from stash)`

## Phase 2 — Fix the DesireResolver regression cluster 2 reveals

- [ ] **Step 1: Reproduce locally.** Run unit tests, focus on the failing names:
  - `test_warm_cat_scores_server_very_low` — warm cat (warmth=900) scores warm server at **360**, expected **<50**
  - `test_evaluate_budget_transitions_cold_cat_to_seeking` — cold cat near warm server lands in **`WANDERING`**, expected **`SEEKING`**
  - `test_evaluate_budget_sets_target_entity_id` — target entity is **`-1`**, expected the server's id
  - `test_evaluate_budget_does_not_transition_if_score_below_threshold` — satisfied cat reaches **`GOAL_DIRECTED`**, expected **`AMBIENT`**
  - `test_pop_highest_deficit_picks_most_desperate_first` — warm cat (900) ends up `GOAL_DIRECTED`, scored too low
  - `test_mark_dirty_deduplicates`, `test_mark_dirty_same_entity_twice_evaluates_once` — same WANDERING-vs-SEEKING symptom
  - `test_satisfied_cat_scores_curiosity_at_zero` — curiosity=1000 scores 30, expected 0

- [ ] **Step 2: Diagnose root cause(s).** Two interacting changes meet here:
  - WANDERING state was added in `e584381` ("WANDERING state, warmth from objects, STARTLED recovery") so animals with high unmet desires wander to find resources when no advertisement scores well.
  - Object-interactions scaffolding in `8245d85` extracted `DesireScatter` and `ObjectStateManager` — passive warmth is now scattered from object advertisements, action ads are excluded.
  
  The two were never reconciled. Hypotheses to investigate before fixing:
  - WANDERING transition fires *before* the SEEKING evaluation considers scattered ads, so cats wander instead of seeking.
  - The scoring formula now has a non-zero floor for satisfied desires (~30 for curiosity=1000, ~360 for warmth=900). Likely a deficit math change in `desire_resolver.gd` or `desire_scatter.gd` that no longer hits zero when deficit is zero.
  - Target entity id of `-1` suggests the resolver picks WANDERING (which has no target) but the test expects SEEKING toward a specific server.
  
  **Do not skip diagnosis.** These three symptoms might be one bug or three. Use `superpowers:systematic-debugging`.

- [ ] **Step 3: Write the smallest failing test that pins the bug** (if the existing tests aren't surgical enough).

- [ ] **Step 4: Fix.** Touch only `engine/desires/desire_resolver.gd` and/or `engine/desires/desire_scatter.gd`. Don't refactor.

- [ ] **Step 5: Re-stamp any test files whose body content changed.** `test_desire_resolver.gd` and `test_curiosity_tracker.gd` are stamped — if the fix requires touching them, re-stamp.

- [ ] **Step 6: Confirm cluster 2 + cluster 3 are gone.** All unit tests green. Then run integration + scenario suites — most of the 3+4 cascade failures should clear too. Diagnose any leftovers individually.

- [ ] **Step 7: Commit.** `fix(desires): reconcile WANDERING state with object scatter scoring`

## Phase 3 — Pause and decide

Stop here. Run `script/validate`. Confirm all tests green. If green:

- The recovery is complete.
- `stash@{0}` and `stash@{1}` still exist, untouched.
- Worktrees still exist, untouched.
- Decide: continue forward into Phase 4 (finish object-interactions / GameServer extraction), or break here and circle back.

If anything is still red, return to the relevant Phase 2 step and diagnose. **Do not** start Phase 4 cleanup until you're satisfied.

## Phase 4 — Cleanup (only after satisfaction)

- [ ] **Step 1: Drop `stash@{1}`.** Unambiguous corruption.
  ```bash
  git stash drop stash@{1}
  ```

- [ ] **Step 2: Verify `stash@{0}` no longer holds anything you need.** Re-run the per-file diff from the triage:
  ```bash
  for f in $(git stash show stash@{0} --stat | awk '{print $1}' | grep -v Bin); do
    [ -f "$f" ] || continue
    diff -q <(git show "stash@{0}:$f") "$f" >/dev/null 2>&1 && echo "IDENTICAL $f" || echo "DIFFERS  $f"
  done
  ```
  Expect: only the diverged-bidirectionally files (CLAUDE.md, nodes/*, animal_node, etc.) plus PLANNING.md and game-artist.md. **If `tests/unit/test_constants.gd` shows IDENTICAL, recovery is confirmed complete.**

- [ ] **Step 3: Drop `stash@{0}`.**
  ```bash
  git stash drop stash@{0}
  ```

- [ ] **Step 4: Prune the 10 stale agent worktrees.**
  ```bash
  for wt in .claude/worktrees/agent-*; do
    git worktree remove "$wt"
  done
  ```
  If any of them have local changes git refuses to remove, inspect first — do not `--force`.

- [ ] **Step 5: Delete the `worktree-agent-*` branch refs.**
  ```bash
  for br in $(git branch | grep '^[* +]*worktree-agent-' | sed 's/^[* +]*//'); do
    git branch -D "$br"
  done
  ```
  These exist in `git branch -a` even after `git worktree remove`. Phase 5 (LFS migration) uses `--everything`, which would otherwise rewrite all of them and produce useless garbage refs.

- [ ] **Step 6: Decide about `agent-a2eea031` (the failed-extraction worktree).** It is referenced by `2026-04-06-game-server-extraction-design.md` line 178 as the failed `isolation: "worktree"` artifact. Two paths:
  - **Keep it as a forensic snapshot** until MovementSystem extraction is resumed. Skip Phase 5 below until then, or accept that LFS migration with `--everything` will rewrite the commit it's pinned to.
  - **Drop it now.** Remove the worktree and its branch, update the line in `2026-04-06-game-server-extraction-design.md` to say "removed on 2026-04-07; the lessons in this section are still accurate, but the worktree itself no longer exists."
  - This decision must be made before Phase 5 so the migration doesn't orphan the worktree.

- [ ] **Step 7: Commit a marker if helpful.** Optional. A commit like `chore: drop recovered stashes and stale agent worktrees` makes the cleanup discoverable.

## Phase 5 — Migrate binary assets into git-lfs (and shrink the repo)

Discovered on 2026-04-07 while merging `auto-mode-phase1`: a fresh `git worktree add` against `main` printed `Encountered 221 files that should have been pointers, but weren't` for every PNG under `mods/tcp_base/sprites/cat/` and `mods/tcp_base/sprites/ferret/`, plus `mods/tcp_base/sprites/robot/arm_station.png`.

**Root cause:** `.gitattributes` declares `*.png *.jpg *.jpeg *.ogg *.wav` as `filter=lfs diff=lfs merge=lfs`, but only 30 PNGs (all under `addons/gut/`) plus a handful of fonts (52 LFS objects total) were ever committed through the LFS filter. The 221 sprite PNGs and any matching audio assets were committed as raw binary blobs at some point in the past — probably `git add` ran before LFS was set up to track that path, or someone force-added them. Every git working-tree operation now triggers the LFS smudge filter, sees raw bytes where it expects a pointer, and reports the file as "modified."

This is the same root pattern as `stash@{1}`'s 232 truncated binary stubs. Fixing the LFS state at HEAD makes both symptoms go away forever.

**Why this phase is gated on Phases 1-4 finishing first:**

- `git lfs migrate import --everything` rewrites every ref in the repo. Stashes get rewritten or orphaned. The recovery plan's "Ground truth" SHA references (`8245d85`, `9cc612b`, `61b2e51`, `3c1bd18`, `39d969e`, `e584381`) all become stale. Worktrees pinned to old commits become detached at dead commits.
- Phases 1-3 must run first so `stash@{0}` is genuinely empty of needed work. Phase 4 must run first so the stashes are dropped and the agent worktrees are gone before history is rewritten.
- Phase 5 must run with a clean working tree (no dirty files, no untracked items in scope).

- [ ] **Step 1: Verify prerequisites.**
  ```bash
  git status                       # MUST be clean
  git stash list                   # MUST be empty
  git worktree list                # MUST show only the main checkout (and possibly agent-a2eea031 if Phase 4 Step 6 chose "keep")
  git branch -a | grep worktree-agent-   # MUST be empty
  ```
  If any of these fail, do NOT proceed. Return to Phase 4.

- [ ] **Step 2: Inventory what's currently outside LFS that should be in it.**
  ```bash
  # Files matching .gitattributes lfs patterns
  git ls-files | grep -iE '\.(png|jpe?g|ogg|wav)$' | sort > /tmp/all-binary.txt
  # Files actually tracked by LFS
  git lfs ls-files | awk '{print $3}' | sort > /tmp/lfs-tracked.txt
  # Difference = the migration target
  comm -23 /tmp/all-binary.txt /tmp/lfs-tracked.txt > /tmp/needs-migration.txt
  wc -l /tmp/needs-migration.txt   # should be ~221+ files
  head /tmp/needs-migration.txt
  ```

- [ ] **Step 3: Capture pre-migration repo size for comparison.**
  ```bash
  du -sh .git
  git lfs ls-files | wc -l
  git rev-parse HEAD               # record current main SHA for the post-migration comparison
  ```

- [ ] **Step 4: Run the migration.**
  ```bash
  git lfs migrate import --everything \
    --include="*.png,*.jpg,*.jpeg,*.ogg,*.wav"
  ```
  `--everything` rewrites every local ref. Every commit SHA changes. Content is preserved byte-for-byte; only the storage backend changes. This may take several minutes.

- [ ] **Step 5: Garbage-collect the unreachable raw blobs.**
  ```bash
  git reflog expire --expire=now --all
  git gc --prune=now --aggressive
  ```
  The old raw-blob PNGs are now unreachable. Aggressive GC removes them and shrinks `.git/objects/pack/`.

- [ ] **Step 6: Verify the migration.**
  ```bash
  du -sh .git                                      # should be substantially smaller
  git lfs ls-files | wc -l                         # should jump from 52 to ~270+
  git lfs ls-files | grep -c 'mods/tcp_base/sprites'   # should be ~221
  git status                                       # should still be clean
  ```

- [ ] **Step 7: Smoke-test by creating a fresh worktree.**
  ```bash
  git worktree add /tmp/lfs-verify -b lfs-verify-test
  # Expect: NO "Encountered N files that should have been pointers" output
  cd /tmp/lfs-verify && git status  # should be clean
  cd -
  git worktree remove /tmp/lfs-verify
  git branch -D lfs-verify-test
  ```

- [ ] **Step 8: Force-push `main` to origin.**
  ```bash
  git push --force-with-lease origin main
  ```
  This rewrites the remote. **Solo repo confirmed on 2026-04-07** — no other clones to coordinate with. If that ever changes, stop and re-plan.

- [ ] **Step 9: Update the SHA references in this plan and in `2026-04-06-game-server-extraction-design.md`.** Every SHA mentioned in those documents (`8245d85`, `9cc612b`, `61b2e51`, `3c1bd18`, `39d969e`, `e584381`) now points at nothing. Two options:
  - **Replace** with the new SHAs from the rewritten history (use `git log --all` to find equivalent commits by message).
  - **Annotate** each line with `(pre-LFS-migration SHA, no longer resolvable)` and leave them for historical context.
  Either is fine. Do not leave the docs lying about whether the SHAs are live.

- [ ] **Step 10: Commit the doc updates.**
  ```bash
  git add docs/superpowers/plans/2026-04-07-stash-recovery-and-cleanup.md \
          docs/superpowers/specs/2026-04-06-game-server-extraction-design.md
  git commit -m "docs: invalidate pre-LFS-migration SHA references"
  git push origin main
  ```

## What this plan deliberately does NOT cover

- **Resuming MovementSystem extraction.** Captured in `2026-04-06-game-server-extraction-design.md`'s updated status section.
- **Implementing PERFORMING state and action execution.** Captured in `2026-04-05-object-interactions.md` Task 3 (which has a status banner pointing here for context).
- **Test verification system pre-commit + CI integration.** Captured in `2026-04-06-test-verification-system-design.md`'s remaining work section.
- **Updating the 4 inlining test files** (`test_object_state.gd`, `test_desire_scatter.gd`, `test_performing.gd`, `test_tick_loop.gd`) to call extracted classes instead of inlining production logic. Captured in `2026-04-06-game-server-extraction-design.md`.
- **`Constants.to_world` / `Constants.from_world` use float math.** `to_world` does `float(v) / float(POSITION_SCALE)`; `from_world` does `roundi(v * float(POSITION_SCALE))`. These are the integer↔rendering boundary and a float is unavoidable on the render side, but the internal division in `to_world` can drift if the caller immediately feeds it back into math that expects integer semantics. Per `.claude/rules/design-philosophy.md` ("Integer-Float Boundary"), this is the correct *location* for the conversion — but it's worth auditing whether every caller actually needs a float, or if some should be using integer PU math throughout. Noted 2026-04-07 during Phase 1 mutation verification. Not a recovery-scope fix.

These are real follow-ups but they are *forward* work, not recovery work. They should be picked up after this plan is closed.

## Reversibility table

| Action | Reversible by |
|---|---|
| Phase 1 Step 1 (write test_constants.gd) | `git checkout HEAD -- tests/unit/test_constants.gd` |
| Phase 1 Step 2 (re-stamp) | Stamp file is generated; re-running stamp restores prior hash if file is reverted |
| Phase 2 Steps 2-4 (DesireResolver fix) | Standard `git revert` of the fix commit |
| Phase 4 Step 1 (drop stash@{1}) | Theoretically recoverable from reflog within 30 days, but you don't want to recover this stash |
| Phase 4 Step 3 (drop stash@{0}) | Same — reflog within 30 days. Verify Step 2 first. |
| Phase 4 Step 4 (worktree removal) | Worktrees removed cleanly leave no trace; the underlying branches are still in `git branch -a` |
| Phase 4 Step 5 (delete worktree-agent-* branches) | Branch SHAs are in the reflog for 30 days. `git reflog --all` finds them. |
| Phase 5 Step 4 (LFS migration with --everything) | **Effectively irreversible once force-pushed.** Before Step 8, every rewritten ref is in the reflog and can be reset with `git reset --hard ORIG_HEAD@{N}`. After Step 8, the rewrite is published and a rollback would require force-pushing the *old* refs back, which depends on still having them in the local reflog. Treat this as a one-way door. |
| Phase 5 Step 5 (gc --prune=now --aggressive) | Pruned objects are gone immediately. This is what makes the migration actually shrink the repo. Run this only after Step 4 looks correct. |
