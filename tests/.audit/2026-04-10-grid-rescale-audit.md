# Grid Rescale Audit — 2026-04-10

Files touching the old grid values that need review during the rescale.
This file is deleted after Phase 6 merge.

**Old values:** `SLOT_HEIGHT_PX=7`, `RACK_WIDTH_PX=76`, `RACK_STRIDE_PX=80`, `RACK_COUNT=7`, `SLOTS_PER_RACK=42`, `HEAT_CELLS_TOTAL=301`.

**New values:** `SLOT_HEIGHT_PX=8`, `RACK_WIDTH_PX=23`, `RACK_STRIDE_PX=31`, `RACK_COUNT=5`, `SLOTS_PER_RACK=10`, `HEAT_CELLS_TOTAL=55`.

---

## Literal values to update

### tests/unit/test_constants.gd
- [ ] line 5–7: `ru_to_pu` asserts `1 → 700`. New: `1 → 800` (SLOT_HEIGHT_PU=800).
- [ ] line 11–13: `pu_to_ru` asserts `700 → 1`. New: `800 → 1`.
- [ ] line 18: `rack_cell(1, 0) == 42` → `10` (cell = rack * SLOTS_PER_RACK + slot).
- [ ] line 19: `rack_cell(6, 41)` is out of range for 5 racks × 10 slots. Replace with `rack_cell(4, 9) == 49`.
- [ ] line 23: `floor_cell(0) == 294` → `50` (HEAT_CELLS_RACK = 50).
- [ ] line 24: `floor_cell(6)` out of range. Replace with `floor_cell(4) == 54`.
- [ ] line 28–29: `to_world(700) == 7.0`. Valid (POSITION_SCALE unchanged). Keep or revise if ru→world changes.
- [ ] line 33–34: `from_world(7.0) == 700`. Valid. Keep.
- [ ] line 38: `HEAT_CELLS_TOTAL == 301` → `55`. Update message.
- [ ] line 39: `SLOTS_PER_RACK == 42` → `10`.
- [ ] line 40: `RACK_COUNT == 7` → `5`.
- [ ] line 44: `RACK_STRIDE_PX == 80` → `31`. Update message ("23 + 8 gap = 31px stride").
- [ ] line 45: `RACK_STRIDE_PU == 8000` → `3100`.

### engine/core/constants.gd
- [ ] Lines 7, 10, 14, 22: source-of-truth values. Replaced wholesale in Task 3.

### nodes/game_client.gd
- [ ] line 21: `_FLOOR_REGION := Rect2(64, 48, 80, 16)` — deleted in Phase 5 (Task 20). Leave for now.

---

## Expressions to review

### tests/unit/test_species_astar.gd
These tests use legacy slot indices and hand-rolled rack stride math. The hand-rolled `2 * Constants.RACK_STRIDE_PU + Constants.RACK_STRIDE_PU / 2` pattern does NOT match the new bay model (missing `LEFTMOST_RACK_OFFSET_PU` and bay origin). Must migrate to `Constants.rack_slot_to_pu(bay, rack, slot)`.

- [ ] line 27: `add_rack_slot(2, 38)` — slot 38 ≥ new SLOTS_PER_RACK (10). Choose valid slot, e.g. `(2, 8)`.
- [ ] line 31–37: slot_pos computed from `RACK_STRIDE_PU` midpoint — use `Constants.rack_slot_to_pu(0, 2, 8)`.
- [ ] line 47: `add_rack_slot(2, 38)` same fix.
- [ ] line 51–57: same slot_pos recomputation.
- [ ] line 77: `add_rack_slot(2, 38)` same.
- [ ] line 86–97: `add_rack_slot(1, 20)` + `add_rack_slot(1, 21)` — both out of range. Use `(1, 5)` + `(1, 6)`.
- [ ] line 98–104: slot20_pos, slot21_pos rewrite using `rack_slot_to_pu`.

### engine/navigation/nav_graph_builder.gd
- [ ] line 45: `SLOTS_PER_RACK * SLOT_HEIGHT_PU + FLOOR_HEIGHT_PU / 2` — auto-updates via constants but verify logic still intends "rack bottom + half floor". Floor rendering may shift in Phase 5.
- [ ] line 52: `range(Constants.RACK_COUNT - 1)` — connects adjacent floor pairs, auto-updates.

### engine/desires/desire_resolver.gd
- [ ] line 206: `randi_range(0, Constants.RACK_COUNT - 1)` — auto-updates.
- [ ] line 209: floor Y compute — verify against Phase 5 floor shift.

### engine/spatial/heat_grid.gd
- [ ] line 68: `if rack < Constants.RACK_COUNT - 1` — auto-updates.
- [ ] line 73, 77: `Constants.SLOTS_PER_RACK - slot` — auto-updates, logic preserved.

### tests/integration/test_desire_scatter.gd
- [ ] line 87: `clampi(rack, 0, Constants.RACK_COUNT - 1)` — auto-updates.
- [ ] line 88: `clampi(slot, 0, Constants.SLOTS_PER_RACK - 1)` — auto-updates.
- [ ] line 184–185: same pair, auto-updates.
- [ ] Verify tests still exercise multiple racks after RACK_COUNT drops from 7 to 5.

### nodes/game_client.gd
- [ ] line 54, 81, 110: `SLOTS_PER_RACK * SLOT_HEIGHT_PX` — auto-updates (new = 80). Reference frame changes in Phase 5.
- [ ] line 239: `clampi(rack, 0, Constants.RACK_COUNT - 1)` — auto-updates.
- [ ] line 246, 310: `&"server_2u"` — keep per rename strategy.
- [ ] line 251: `Constants.SLOTS_PER_RACK - 2` — legacy "top-2" slot choice. Reevaluate in Phase 5 (Task 21).
- [ ] line 263: `SLOTS_PER_RACK * SLOT_HEIGHT_PU` — auto-updates.

### nodes/heat_overlay.gd
- [ ] line 54: `SLOTS_PER_RACK * SLOT_HEIGHT_PX` — auto-updates.

### nodes/game_server.gd
- [ ] line 105, 108, 109: `clampi(rack|slot, ...)` — auto-updates.
- [ ] line 338, 439: `&"server_2u"` type string — keep.
- [ ] line 449: `SLOTS_PER_RACK * SLOT_HEIGHT_PU + FLOOR_HEIGHT_PU / 4` — Y calc, auto-updates but verify intent against new floor geometry.
- [ ] line 466: `.../ 3` — same.
- [ ] line 486, 523, 563: `SLOTS_PER_RACK * SLOT_HEIGHT_PU` — auto-updates.

### nodes/placement_ui.gd
- [ ] line 27, 81: `&"server_2u"` — keep.

### nodes/ru_grid_overlay.gd
- [ ] line 13: `RACK_COUNT * RACK_STRIDE_PX` — auto-updates; plan says "no code change".
- [ ] line 16: `SLOTS_PER_RACK * SLOT_HEIGHT_PX` — auto-updates.
- [ ] line 21: `range(SLOTS_PER_RACK + 1)` — auto-updates.
- [ ] line 31: `range(RACK_COUNT + 1)` — auto-updates.

### nodes/camera_controller.gd
- [ ] line 14: `RACK_COUNT * (RACK_WIDTH_PX + RACK_GAP_PX)` — auto-updates but may conflict with bay-based camera (Task 23: `bay_center` helper).
- [ ] line 17: `SLOTS_PER_RACK * SLOT_HEIGHT_PX + FLOOR_HEIGHT_PX / 2` — auto-updates.

---

## Position literals in tests

None found in `tests/scenario/`, `tests/integration/`, `tests/scene/` via Vector2 grep. Only hits were in `tests/unit/test_species_astar.gd` (covered above).

---

## Scene/resource files

- [ ] `nodes/main.tscn` and other `.tscn` files: no literal hits of `42|294|80|76|96` as whole words (grep negative).
- [ ] `mods/tcp_base/sprites/**/*.tres`: not yet audited in full; new TileSet resources created in Phase 3 (Task 9).

---

## False positives (no action)

- `tests/unit/test_curiosity_tracker.gd` lines 14, 19, 20, 25, 26: `42` is an entity ID / seed, not a grid value.
- `tests/unit/test_desire_resolver.gd:121`: comment `3 * 700 = 2100 pu` is radius math, not rack stride.

---

## `"server_2u"` type string audit

All hits kept per rename strategy (spec §TODO):
- `nodes/game_client.gd:246, 310`
- `nodes/game_server.gd:338, 439`
- `nodes/placement_ui.gd:27, 81`

No action needed.
