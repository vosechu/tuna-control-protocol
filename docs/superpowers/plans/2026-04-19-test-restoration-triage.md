# Test Restoration Triage — post coordinate-refactor shrink

**Goal:** Recover lost unit-level coverage from the 10 test-shrink commits
that trailed the coordinate-system refactor, without weakening stamp
integrity or re-introducing genuine duplicates.

**Inputs audited:** 10 commits touching `tests/unit/`, 48 removed test
functions, 10 replacement merges, current post-refactor test content,
`tdd_verify` constraints.

## Buckets

- **A — Restore + Stamp** — distinct surgical mutation is findable
  (unique failing-test set of exactly `[test_name]` across the whole
  suite). Full `tdd_verify start → mutation → restore → finish` cycle.
- **B — Restore + UNSTAMPED** — genuine unit invariant that shares
  mutation surface with already-stamped tests. Restore with inline
  `# UNSTAMPED: <reason>` marker; content-hashing still protects against
  edits, per-test mutation evidence is waived. Requires extending
  `script/tdd_verify` and `script/checks/verify_tests` to skip mutation
  requirement for marked tests (setup_hash and file-content hash still
  enforced).
- **C — Keep deleted** — either a true duplicate of a test that now
  lives elsewhere, or a merge into a genuinely-equivalent test where
  every split path shares one line.

**Totals: 13A + 1B + 34C = 48.** Plus one adjacent fix (restore a
dropped `action_duration` assertion into an existing merged test).

---

## `de228eb` — test_hum_system (9 removed → 3 restored)

| Test | Bucket | Surgical mutation / rationale |
|---|---|---|
| `test_charge_adds_to_reserve` | C | `test_charge_emits_hum_reserve_changed` asserts old=500,new=600 as part of signal check — arithmetic covered |
| `test_drain_idle_reduces_reserve` | C | `test_drain_idle_slows_at_low_reserve` asserts `drain_at_quarter < drain_at_full`; both being zero fails that inequality, so reduction is implied |
| `test_drain_action_can_reach_zero` | C | merged into `test_drain_action_floors_at_zero` (legitimate — both on `maxi(0, …)`) |
| `test_reserve_never_goes_negative` | C | merged into same as above |
| `test_tick_charges_from_purring_emitter_near_receiver` | **A** | Mutation: skip the charge call in `tick_charge`. Positive test fails; outside-radius and zero-intensity tests still pass (reserve unchanged, matches their assertion) |
| `test_tick_does_not_charge_from_emitter_outside_radius` | **A** | Mutation: remove the distance guard in `tick_charge`. Only outside-radius test fails (charges when it shouldn't); positive + zero-intensity tests unaffected |
| `test_zero_intensity_emitter_does_not_charge` | **A** | Mutation: remove the `intensity == 0` short-circuit. Only zero-intensity test fails |
| `test_brownout_entered_emitted_at_threshold` | C | legitimate merge into `test_brownout_entered_and_recovered_signals` (recovery depends on the entered transition) |
| `test_brownout_recovered_emitted_on_recovery` | C | merged into same |

## `de24bd6` — test_desire_resolver (9 removed → 5 restored)

| Test | Bucket | Surgical mutation / rationale |
|---|---|---|
| `test_cold_cat_scores_warm_server_positively` | C | merged into `test_deficit_factor_scales_score` |
| `test_warm_cat_scores_server_very_low` | C | merged into same |
| `test_evaluate_budget_transitions_cold_cat_to_seeking_toward_server` | **A** | Mutation: skip the `state = SEEKING` assignment in the transition branch. Only this test fails (asserts state==SEEKING); threshold and commitment tests assert stays-AMBIENT which still holds; trackers test asserts NOT SEEKING which still holds |
| `test_evaluate_budget_does_not_transition_if_score_below_threshold` | **A** | Mutation: remove the `SWITCH_THRESHOLD` gate (always transition). Only this test fails (expects AMBIENT, gets SEEKING); transitions test still passes (it scores above threshold anyway) |
| `test_evaluate_budget_does_not_transition_if_score_below_commitment_plus_threshold` | **A** | Mutation: drop the commitment offset, use bare threshold. Only this test fails |
| `test_curious_ferret_scores_curiosity_ad_positively` | C | `test_curiosity_ad_scores_normally_after_cooldown` already asserts curiosity > 0 for a ferret; ferret label here is cosmetic (no species branch in `score_ad`) |
| `test_curiosity_ad_scores_zero_when_recently_visited` | **A** | Mutation: ignore the `tracker.recently_visited` check. Only this test fails; after-cooldown test passes (tick > cooldown either way) |
| `test_satisfied_cat_scores_curiosity_at_zero` | C | the merged `test_deficit_factor_scales_score` now asserts `curiosity=1000 → score=0` for a satisfied cat — covered |
| `test_evaluate_budget_honors_trackers_dict` | **A** | Mutation: drop the `trackers` argument from the `score_ad` call inside `evaluate_budget`. Only this test fails (ferret transitions to SEEKING when it shouldn't) |

## `38fbf96` — test_object_state (8 removed → 0 restored, 1 minor fix)

| Test | Bucket | Rationale |
|---|---|---|
| `test_sealed_to_open_changes_ads_to_food` | C | legitimate merge into `test_sealed_to_open_transitions_to_food_ad_with_eat_action` |
| `test_sealed_to_open_to_empty_full_lifecycle` | C | full chain of transitions covered one-by-one |
| `test_tuna_open_ad_has_eat_action` | C (+fix) | merged, **but** merged test dropped the `action_duration == 50` assertion. Fix: add that one line to the merged test (no stamp cycle needed — it's part of the same test_ body, test-name-level hash changes but the assertion is the same invariant). Actually: any addition to a stamped test body changes that test's hash, so it needs a `restamp` with reason. This is a legitimate cosmetic-class change (adding a dropped assertion back). |
| `test_new_box_advertises_comfort_and_curiosity` | C | merged into `test_new_box_state_and_ads` |
| `test_box_full_degradation_lifecycle` | C | chain covered one-by-one |
| `test_box_state_boundary_at_501` | C | merged (tests `hp=501 → new`) |
| `test_box_state_boundary_at_500` | C | covered by the damage-to-worn test |
| `test_box_state_boundary_at_1` | C | covered by the damage-to-worn test |

**Adjacent fix:** add `assert_eq(ads[&"list"][0][&"action_duration"], 50)` to
`test_sealed_to_open_transitions_to_food_ad_with_eat_action`, then
`tdd_verify restamp` with reason "restore action_duration assertion
dropped during merge (dev-team-level test-philosophy fix, not a
mutation change)". *Open question: does dropping-then-readding an
assertion count as restamp-eligible, or is it a full-cycle change?
I think the strict reading is full-cycle, since assertion logic
changed. Flag for user decision.*

## `0b88bb5` — test_food_system (5 removed → 5 restored)

| Test | Bucket | Surgical mutation |
|---|---|---|
| `test_press_button_dispenses_can_when_hum_available` | **A** | Mutation: `press_button` always returns `INVALID_ID`. Only this test fails; fails-without-hum and rack-mismatch tests already expect `INVALID_ID` and still pass |
| `test_press_button_drains_hum` | **A** | Mutation: set drain amount to 0 in `press_button`. Only this test fails; dispense test still passes (result id is returned regardless) |
| `test_arm_opens_nearby_sealed_can` | **A** | Mutation: `tick_arms` skips the `transition_state(&"open")` call. Only this test fails; ignores-distant and requires-hum tests already expect the can to stay sealed and still pass |
| `test_opened_can_advertises_food` | **A** | Mutation: skip the `set_component(&"advertisements", …)` call in the open-can path. Only this test fails |
| `test_eaten_can_despawns_after_delay` | **A** | Mutation: `tick_cleanup` skips the `despawn_entity` call. Only this test fails (no other unit test asserts post-cleanup despawn; integration tests exist but should be migrated to the scenario suite if we want to keep them out of the tdd_verify surgical check — see open question below) |

## `5a8cc83` — test_heat_grid (1 removed → 0 restored)

| Test | Bucket | Rationale |
|---|---|---|
| `test_empty_grid_is_all_zeros` | C | `propagate()` on fresh grid is trivially zero because `HEAT_CELLS_TOTAL` Arrays default to 0. The `_grid.fill(0)` line is actually exercised by `test_propagation_resets_each_tick` after the source is destroyed. Deletion is correct |

## `327a49d` — test_reclamation_system (2 removed → 0 restored)

| Test | Bucket | Rationale |
|---|---|---|
| `test_cat_far_from_server_does_not_increment` | C | legitimate merge — same `maxi(current - _DECAY_PER_TICK, 0)` line; merged test pins the 0-floor + nonzero-decay paths |
| `test_presence_decays_when_cat_leaves` | C | merged into same |

## `e9c993b` — test_placement_boundary (5 removed → 0 restored)

| Test | Bucket | Rationale |
|---|---|---|
| `test_rack_0_center_snaps_to_rack_0` | C | legitimate merge into `test_first_and_last_rack_columns_snap_to_their_own_rack` |
| `test_rack_4_center_snaps_to_rack_4` | C | merged into same |
| `test_gap_between_racks_returns_other` | C | exact duplicate of `test_bay_local_to_slot_tags_other_for_gap_positions` in `test_constants_addressing.gd` |
| `test_slot_boundary_is_per_slot_height` | C | duplicate of `test_bay_local_to_slot_finds_slot_when_inside_slot_rect` |
| `test_next_bay_resolves_via_world_to_bay` | C | duplicate of `test_bay_index_round_trip_through_world_to_bay` |

## `2ed390b` — test_bay_layout (4 removed → 0 restored)

All four merged pairs share a single line of production code
(`bay * BAY_STRIDE_PX` or `bay * BAY_STRIDE_PX + BAY_WIDTH_PX / 2`).
Splitting them cannot produce distinct failing-test sets for any
mutation. Keep merged. **All C.**

## `81fd7b4` — test_wiring_system_connect (2 removed → 1 restored)

| Test | Bucket | Rationale |
|---|---|---|
| `test_fresh_connect_writes_cable_and_emits` | **B (UNSTAMPED)** | The happy-path connect runs as setup for pickup/drain/replace/save-mid-drag/cross-stripe tests across the whole suite, so "return false from handle_connect" cascades into many integrations. A more surgical mutation (e.g. skip the event emit) may be possible but is fragile across future tests. Restoring with UNSTAMPED preserves file-content-hash integrity while acknowledging the shared mutation surface. |
| `test_replace_on_connect_emits_disconnect_then_connect` | C | `tests/integration/test_replace_on_connect.gd` covers it and the unit-level replace assertion duplicates the integration assertion |

**Try harder first:** before committing to UNSTAMPED, attempt the "skip
connect event emit" mutation. If only one test fails across the full
suite, promote to A.

## `4034962` — test_cable_length_validation (3 removed → 0 restored)

All three exercise the single `(dx*dx + dy*dy) <= (max_px * max_px)`
line. The merged test now asserts under/over/euclidean-diagonal/
not-manhattan in one body. Legitimate merge. **All C.**

---

## Execution plan

1. **Extend `tdd_verify` + `verify_tests`** for UNSTAMPED support
   (single shared path for both scripts — the stamp still includes
   the test's content hash, the mutation cycle is skipped for names
   that carry the inline marker). Scope-limit the feature: only if the
   one B test above genuinely resists a surgical mutation. If we find
   the mutation, we can skip this step entirely.
2. **Restore Bucket A (13 tests)** one file at a time, using full
   `tdd_verify` cycles. Order by file to minimize stamp churn:
   - `test_hum_system.gd` — add 3 tests, re-cycle 13 total
   - `test_desire_resolver.gd` — add 5 tests, re-cycle 12 total
   - `test_food_system.gd` — add 5 tests, re-cycle 9 total (all 5 were
     stamp-loss; file goes from 4→9)
3. **Object-state adjunct** — add the dropped `action_duration=50`
   assertion back to `test_sealed_to_open_transitions_to_food_ad_with_eat_action`.
   **Open question:** treat as restamp (cosmetic-class) or full
   mutation cycle (assertion logic change). My read: assertion *added
   back from the pre-deletion file* with no new invariant is
   restamp-eligible; but the strict tdd_verify reading says full cycle.
   Ask user.
4. **Try-harder pass on the B test**, then either stamp it or
   land the UNSTAMPED path (requires step 1).
5. **Commit sequence:** one commit per file, same cadence as the
   original shrink commits. Every commit leaves `script/validate`
   green and the game bootable.

## Open questions for user

1. **Object-state `action_duration` fix — restamp or full cycle?**
   The assertion was in the pre-deletion test body and was dropped
   during the merge. Adding it back is "restore pre-existing invariant"
   more than "new invariant", but strict tdd_verify policy says
   anything that changes assertion logic requires the full cycle.
2. **Tolerance for UNSTAMPED size?** Currently exactly 1 test would
   need it. If the try-harder pass finds a surgical mutation, we
   avoid the tooling change entirely. Worth delaying the tdd_verify
   extension until we've confirmed the need.
3. **Scope gate before execution:** do you want this whole plan
   executed in one session, or a checkpoint after each file's
   restoration?
