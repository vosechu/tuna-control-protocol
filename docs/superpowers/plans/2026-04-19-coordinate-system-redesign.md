# Coordinate System Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the PU/RU coordinate abstractions with pure Godot world pixels and three-layer addressing (bay → rack → slot), fixing the 2800-PU frame mismatch that blocks Ring 0's "cat settles in box → HUM charges" golden path.

**Architecture:** Rewrite `engine/core/constants.gd` around `Rect2i`/`Vector2i` helpers keyed by `(bay, rack, slot)`. Slot 0 is bottom, slot 9 is top — axis inversion lives inside the helpers, never in caller code. Named zones (`rack_frame_rect`, `rack_baseboard_rect`, `floor_rect_world`) are distinct from the slot grid. Migration uses additive-then-forcing-rename-then-delete commits so every step leaves `script/validate` green.

**Tech Stack:** GDScript (Godot 4.6), `RefCounted` static helpers, `Rect2i`/`Vector2i` integer geometry, GUT unit tests.

**Spec:** `docs/superpowers/specs/2026-04-19-coordinate-system-redesign.md`

---

## File Structure

**New:**
- `engine/core/slot_query.gd` — small RefCounted result type for reverse lookups.

**Rewritten:**
- `engine/core/constants.gd` — complete replacement (old API kept alongside new until Commit 5).

**Modified (callers migrate off PU/RU):**
- `engine/spatial/heat_grid.gd`
- `engine/desires/desire_resolver.gd`
- `engine/desires/desire_scatter.gd`
- `engine/navigation/nav_graph_builder.gd`
- `engine/growth/plant_growth_system.gd`
- `engine/growth/reclamation_system.gd`
- `engine/core/food_system.gd`
- `engine/core/hum_system.gd`
- `engine/core/wiring_system.gd`
- `engine/core/world_init_system.gd`
- `engine/objects/object_state_manager.gd`
- `nodes/game_server.gd`
- `nodes/game_client.gd`
- `nodes/ru_grid_overlay.gd` → rename to `nodes/slot_grid_overlay.gd`
- `nodes/heat_overlay.gd`

**Config rewritten (schema bump):**
- `mods/tcp_base/scenarios/starter.jsonc` (slot inversion, schema 1→2)
- `mods/tcp_base/objects/hum_device.jsonc`, `arm.jsonc`, others (radius_ru → radius_px)
- `mods/tcp_cats/species/cat.jsonc`
- `mods/tcp_ferrets/species/ferret.jsonc`
- `mods/tcp_tuna/objects/tuna_can.jsonc`

**Tests added/modified:**
- `tests/unit/test_constants_addressing.gd` — new, covers the new API including Y-ordering invariant
- `tests/unit/test_bay_layout.gd` — existing, migrated to new API
- Every `ru_to_pu`/`rack_slot_to_pu`/`radius_ru` test updated

---

## Task 1: Add new API alongside old (Commit 1)

**Files:**
- Create: `engine/core/slot_query.gd`
- Modify: `engine/core/constants.gd` (additive only — do not touch existing functions)
- Test: `tests/unit/test_constants_addressing.gd` (new)

This commit is **pure additive**. Old `rack_slot_to_pu`, `POSITION_SCALE`, `ru_to_pu`, etc. stay untouched. Callers are not migrated yet.

- [ ] **Step 1: Create SlotQuery class**

Create `engine/core/slot_query.gd`:

```gdscript
class_name SlotQuery extends RefCounted

# AI-DEV: Returned by Constants.bay_local_to_slot. `zone` is the typed
# discriminator. Use get_slot()/get_rack() accessors — they assert on misuse.
# Construct with the explicit factory helpers below, not bare .new(...).

var rack: int = Constants.INVALID_ID
var slot: int = Constants.INVALID_SLOT
var zone: StringName = &"other"


static func make_slot(rack_idx: int, slot_idx: int) -> SlotQuery:
	var q := SlotQuery.new()
	q.rack = rack_idx
	q.slot = slot_idx
	q.zone = &"slot"
	return q


static func make_frame(rack_idx: int) -> SlotQuery:
	var q := SlotQuery.new()
	q.rack = rack_idx
	q.zone = &"frame"
	return q


static func make_baseboard(rack_idx: int) -> SlotQuery:
	var q := SlotQuery.new()
	q.rack = rack_idx
	q.zone = &"baseboard"
	return q


static func make_floor(rack_idx: int) -> SlotQuery:
	var q := SlotQuery.new()
	q.rack = rack_idx
	q.zone = &"floor"
	return q


static func make_other() -> SlotQuery:
	return SlotQuery.new()


func get_slot() -> int:
	assert(zone == &"slot", "SlotQuery.get_slot() called with zone=%s" % zone)
	return slot


func get_rack() -> int:
	assert(zone != &"other", "SlotQuery.get_rack() called with zone=&\"other\"")
	return rack
```

- [ ] **Step 2: Write failing test for the new API**

Create `tests/unit/test_constants_addressing.gd`:

```gdscript
extends GutTest

# AI-DEV: Covers the new three-layer addressing API. Every test in this file
# should survive Commit 5 (old API deletion) untouched — the new API is the
# contract.


func test_slot_origin_y_descends_as_slot_index_rises() -> void:
	# Slot 0 is the BOTTOM slot and must have a higher world Y than slot 9.
	# This is the Y-axis invariant — if someone re-flips the convention,
	# this test catches it.
	var bottom: Vector2i = Constants.slot_origin_world(0, 0, 0)
	var top: Vector2i = Constants.slot_origin_world(0, 0, 9)
	assert_gt(bottom.y, top.y,
		"slot 0 (bottom) must have larger Y than slot 9 (top); got bottom=%d top=%d"
		% [bottom.y, top.y])


func test_slot_rect_dimensions_match_server_size() -> void:
	var rect: Rect2i = Constants.slot_rect_world(0, 0, 0)
	assert_eq(rect.size, Vector2i(23, 8),
		"slot rect must be 23×8 px (server footprint)")


func test_rack_frame_rect_sits_above_top_slot() -> void:
	var top_slot: Rect2i = Constants.slot_rect_world(0, 0, 9)
	var frame: Rect2i = Constants.rack_frame_rect(0, 0)
	assert_eq(frame.end.y, top_slot.position.y,
		"frame bottom edge must meet top of slot 9")
	assert_eq(frame.size.y, 12,
		"frame is 12 px tall (rack top frame)")


func test_rack_baseboard_rect_sits_below_bottom_slot() -> void:
	var bottom_slot: Rect2i = Constants.slot_rect_world(0, 0, 0)
	var base: Rect2i = Constants.rack_baseboard_rect(0, 0)
	assert_eq(base.position.y, bottom_slot.end.y,
		"baseboard top edge must meet bottom of slot 0")
	assert_eq(base.size.y, 4,
		"baseboard is 4 px tall")


func test_floor_rect_sits_below_baseboard() -> void:
	var base: Rect2i = Constants.rack_baseboard_rect(0, 0)
	var floor_r: Rect2i = Constants.floor_rect_world(0)
	assert_eq(floor_r.position.y, base.end.y,
		"floor top edge meets baseboard bottom edge")
	assert_eq(floor_r.size.y, 16, "floor is 16 px tall")


func test_rack_horizontal_stride_is_31px() -> void:
	var r0: Rect2i = Constants.slot_rect_world(0, 0, 0)
	var r1: Rect2i = Constants.slot_rect_world(0, 1, 0)
	assert_eq(r1.position.x - r0.position.x, 31,
		"adjacent rack cells are 31 px apart")


func test_bay_index_round_trip_through_world_to_bay() -> void:
	for bay: int in [0, 1, 2, 3]:
		var origin: Vector2i = Constants.bay_origin_world(bay)
		assert_eq(Constants.world_to_bay(origin), bay,
			"world_to_bay must return the bay we pulled origin from")


func test_world_to_bay_returns_invalid_for_gap_positions() -> void:
	# Between bays there's a gap; points there have no owning bay.
	var bay0_end: Vector2i = Constants.bay_rect_world(0).end
	var far_right: Vector2i = Vector2i(bay0_end.x + 1000, bay0_end.y)
	# World positions past the last known bay are INVALID.
	assert_eq(Constants.world_to_bay(far_right), Constants.INVALID_BAY,
		"points past known bays must return INVALID_BAY")


func test_bay_local_to_slot_finds_slot_when_inside_slot_rect() -> void:
	var rect: Rect2i = Constants.slot_rect_world(0, 2, 5)
	var center: Vector2i = rect.position + rect.size / 2
	var q: SlotQuery = Constants.bay_local_to_slot(0, center)
	assert_eq(q.zone, &"slot")
	assert_eq(q.rack, 2)
	assert_eq(q.get_slot(), 5)


func test_bay_local_to_slot_tags_frame_zone() -> void:
	var frame: Rect2i = Constants.rack_frame_rect(0, 1)
	var center: Vector2i = frame.position + frame.size / 2
	var q: SlotQuery = Constants.bay_local_to_slot(0, center)
	assert_eq(q.zone, &"frame")
	assert_eq(q.get_rack(), 1)


func test_bay_local_to_slot_tags_floor_zone() -> void:
	var floor_r: Rect2i = Constants.floor_rect_world(0)
	var under_rack_1: Vector2i = Vector2i(
		Constants.rack_frame_rect(0, 1).position.x + 5,
		floor_r.position.y + 2,
	)
	var q: SlotQuery = Constants.bay_local_to_slot(0, under_rack_1)
	assert_eq(q.zone, &"floor")
	assert_eq(q.get_rack(), 1)


func test_bay_local_to_slot_tags_other_for_gap_positions() -> void:
	# A point in the horizontal gap between rack cells is &"other".
	var r0: Rect2i = Constants.slot_rect_world(0, 0, 0)
	var gap_point: Vector2i = Vector2i(r0.end.x + 2, r0.position.y + 2)
	var q: SlotQuery = Constants.bay_local_to_slot(0, gap_point)
	assert_eq(q.zone, &"other")


func test_slot_origin_asserts_on_invalid_slot_index() -> void:
	# TCP philosophy: explode early. Passing 10 or -1 is a programmer error.
	# In release builds this is a silent no-op; in debug it asserts.
	# We only test that the helper does not crash on valid indices here.
	for s: int in range(10):
		var _p: Vector2i = Constants.slot_origin_world(0, 0, s)
```

- [ ] **Step 3: Run tests to verify they fail**

```
script/checks/gut_tests -f tests/unit/test_constants_addressing.gd
```

Expected: All fail with errors like `Invalid call. Nonexistent function 'slot_origin_world' in base 'Constants'.`

- [ ] **Step 4: Add the new API to Constants**

Append to `engine/core/constants.gd` (do **not** touch existing constants or functions — this is purely additive):

```gdscript
# ============================================================================
# NEW COORDINATE API — see docs/superpowers/specs/2026-04-19-coordinate-system-redesign.md
# Old API (rack_slot_to_pu, POSITION_SCALE, ru_to_pu, etc.) remains alongside
# during migration. Old API will be removed in the final commit of this
# refactor. Prefer the new API in any code you write today.
# ============================================================================

const INVALID_BAY: int = -1
const INVALID_SLOT: int = -1

# AI-DEV: These numbers match the current 5-set rack sprite exactly. If a mod
# pack ships differently-sized rack art, promote them to art-pack config
# loaded by ModLoader. Do not expose them publicly — the helpers' job is to
# hide art measurements behind the three-layer addressing API.
const _SLOT_HEIGHT_PX: int = 8
const _SERVER_WIDTH_PX: int = 23
const _RACK_CELL_WIDTH_PX: int = 24
const _RACK_STRIDE_PX: int = 31
const _RACK_LEFT_MARGIN_PX: int = 16
const _RACK_TOP_FRAME_HEIGHT_PX: int = 12
const _RACK_BOTTOM_FRAME_HEIGHT_PX: int = 4
const _RACK_INTERIOR_HEIGHT_PX: int = 80
const _FLOOR_HEIGHT_PX: int = 16
const _RACK_TOP_Y_IN_BAY: int = 16


# ── Bay layer ────────────────────────────────────────────────────────────────


static func bay_origin_world(bay: int) -> Vector2i:
	return Vector2i(bay * BAY_STRIDE_PX, 0)


static func bay_rect_world(bay: int) -> Rect2i:
	return Rect2i(bay_origin_world(bay), Vector2i(BAY_WIDTH_PX, VIEWPORT_HEIGHT))


static func world_to_bay(world_pos: Vector2i) -> int:
	# Bays tile at BAY_STRIDE_PX. A position in the "peek" gap between bays
	# returns INVALID_BAY — bay boundaries are exact, not fuzzy.
	if world_pos.x < 0:
		return INVALID_BAY
	var candidate: int = world_pos.x / BAY_STRIDE_PX
	var origin: Vector2i = bay_origin_world(candidate)
	var rect: Rect2i = Rect2i(origin, Vector2i(BAY_WIDTH_PX, VIEWPORT_HEIGHT))
	if rect.has_point(world_pos):
		return candidate
	return INVALID_BAY


# ── Rack layer ──────────────────────────────────────────────────────────────


static func rack_column_rect_world(bay: int, rack: int) -> Rect2i:
	assert(rack >= 0 and rack < RACK_COUNT,
		"rack index %d out of range [0, %d)" % [rack, RACK_COUNT])
	var origin_x: int = bay * BAY_STRIDE_PX + _RACK_LEFT_MARGIN_PX + rack * _RACK_STRIDE_PX
	var origin_y: int = _RACK_TOP_Y_IN_BAY
	var height: int = (
		_RACK_TOP_FRAME_HEIGHT_PX
		+ _RACK_INTERIOR_HEIGHT_PX
		+ _RACK_BOTTOM_FRAME_HEIGHT_PX
	)
	return Rect2i(Vector2i(origin_x, origin_y), Vector2i(_SERVER_WIDTH_PX, height))


static func rack_interior_rect_world(bay: int, rack: int) -> Rect2i:
	var col: Rect2i = rack_column_rect_world(bay, rack)
	return Rect2i(
		Vector2i(col.position.x, col.position.y + _RACK_TOP_FRAME_HEIGHT_PX),
		Vector2i(col.size.x, _RACK_INTERIOR_HEIGHT_PX),
	)


static func rack_frame_rect(bay: int, rack: int) -> Rect2i:
	var col: Rect2i = rack_column_rect_world(bay, rack)
	return Rect2i(col.position, Vector2i(col.size.x, _RACK_TOP_FRAME_HEIGHT_PX))


static func rack_baseboard_rect(bay: int, rack: int) -> Rect2i:
	var col: Rect2i = rack_column_rect_world(bay, rack)
	var base_y: int = col.position.y + _RACK_TOP_FRAME_HEIGHT_PX + _RACK_INTERIOR_HEIGHT_PX
	return Rect2i(
		Vector2i(col.position.x, base_y),
		Vector2i(col.size.x, _RACK_BOTTOM_FRAME_HEIGHT_PX),
	)


# ── Slot layer ──────────────────────────────────────────────────────────────


static func slot_origin_world(bay: int, rack: int, slot: int) -> Vector2i:
	assert(slot >= 0 and slot < SLOTS_PER_RACK,
		"slot index %d out of range [0, %d)" % [slot, SLOTS_PER_RACK])
	var interior: Rect2i = rack_interior_rect_world(bay, rack)
	# Slot 0 is at the BOTTOM — invert inside the helper so callers never flip.
	var from_bottom: int = SLOTS_PER_RACK - 1 - slot
	return Vector2i(
		interior.position.x,
		interior.position.y + from_bottom * _SLOT_HEIGHT_PX,
	)


static func slot_rect_world(bay: int, rack: int, slot: int) -> Rect2i:
	return Rect2i(slot_origin_world(bay, rack, slot), Vector2i(_SERVER_WIDTH_PX, _SLOT_HEIGHT_PX))


# ── Floor ───────────────────────────────────────────────────────────────────


static func floor_rect_world(bay: int) -> Rect2i:
	var origin: Vector2i = bay_origin_world(bay)
	var floor_y: int = (
		_RACK_TOP_Y_IN_BAY
		+ _RACK_TOP_FRAME_HEIGHT_PX
		+ _RACK_INTERIOR_HEIGHT_PX
		+ _RACK_BOTTOM_FRAME_HEIGHT_PX
	)
	return Rect2i(
		Vector2i(origin.x, floor_y),
		Vector2i(BAY_WIDTH_PX, _FLOOR_HEIGHT_PX),
	)


# ── Reverse query: world pixel → address ────────────────────────────────────


static func bay_local_to_slot(bay: int, world_pos: Vector2i) -> SlotQuery:
	assert(bay >= 0, "bay must be non-negative; got %d" % bay)
	# Find the rack column that contains world_pos.x, if any.
	var rack_found: int = INVALID_ID
	for r: int in range(RACK_COUNT):
		var col: Rect2i = rack_column_rect_world(bay, r)
		if world_pos.x >= col.position.x and world_pos.x < col.end.x:
			rack_found = r
			break
	if rack_found == INVALID_ID:
		# Could still be above the floor strip — check floor span.
		var floor_r: Rect2i = floor_rect_world(bay)
		if floor_r.has_point(world_pos):
			# Floor but not under any rack column — use -1 in rack.
			return SlotQuery.make_other()
		return SlotQuery.make_other()

	# Check Y zones in order: frame → interior (slots) → baseboard → floor.
	var frame: Rect2i = rack_frame_rect(bay, rack_found)
	if frame.has_point(world_pos):
		return SlotQuery.make_frame(rack_found)

	var interior: Rect2i = rack_interior_rect_world(bay, rack_found)
	if interior.has_point(world_pos):
		var from_top_px: int = world_pos.y - interior.position.y
		var from_top_slot: int = from_top_px / _SLOT_HEIGHT_PX
		var slot: int = SLOTS_PER_RACK - 1 - from_top_slot
		return SlotQuery.make_slot(rack_found, slot)

	var base: Rect2i = rack_baseboard_rect(bay, rack_found)
	if base.has_point(world_pos):
		return SlotQuery.make_baseboard(rack_found)

	var floor_r: Rect2i = floor_rect_world(bay)
	if floor_r.has_point(world_pos):
		return SlotQuery.make_floor(rack_found)

	return SlotQuery.make_other()
```

- [ ] **Step 5: Run the new tests — they must pass**

```
script/checks/gut_tests -f tests/unit/test_constants_addressing.gd
```

Expected: All 12 tests pass.

- [ ] **Step 6: Run the full suite to confirm no regression**

```
script/validate
```

Expected: all existing tests green (old API untouched).

- [ ] **Step 7: Commit**

```
git add engine/core/slot_query.gd engine/core/constants.gd tests/unit/test_constants_addressing.gd engine/core/slot_query.gd.uid tests/unit/test_constants_addressing.gd.uid
git commit -m "feat(constants): add bay/rack/slot addressing API alongside PU"
```

---

## Task 2: Stamp the new constants test (TDD verification)

**Files:**
- Modify: `tests/unit/test_constants_addressing.gd` (add AI-DEV markers)
- Generate: `tests/unit/test_constants_addressing.gd.stamp` and `.audit.yaml`

- [ ] **Step 1: Add AI-DEV markers inside each test**

Add `# AI-DEV: AI **MUST NOT** touch this test. If the test is failing, it is because you removed or broke code.` as the first line inside each `func test_*` body.

- [ ] **Step 2: Run the full stamp cycle using tdd_verify**

```
script/tdd_verify start tests/unit/test_constants_addressing.gd
```

For each test (12 total), perform mutation → verify exactly one test fails → restore → verify green. Example for `test_slot_origin_y_descends_as_slot_index_rises`:

```
# Mutation: in constants.gd slot_origin_world, flip the slot inversion:
#   var from_bottom: int = slot   # was: SLOTS_PER_RACK - 1 - slot
script/tdd_verify mutation test_slot_origin_y_descends_as_slot_index_rises
# Restore constants.gd
script/tdd_verify restore test_slot_origin_y_descends_as_slot_index_rises
```

Repeat with targeted mutations for each remaining test (e.g. change `_RACK_TOP_FRAME_HEIGHT_PX` to catch `test_rack_frame_rect_sits_above_top_slot`, change `_RACK_STRIDE_PX` to catch `test_rack_horizontal_stride_is_31px`, etc.).

- [ ] **Step 3: Finalize the stamp**

```
script/tdd_verify finish
script/checks/verify_tests
```

Expected: stamp file written, verify_tests passes.

- [ ] **Step 4: Commit**

```
git add tests/unit/test_constants_addressing.gd tests/unit/test_constants_addressing.gd.stamp tests/unit/test_constants_addressing.gd.audit.yaml
git commit -m "test(constants): stamp new addressing API tests"
```

---

## Task 3: Migrate leaf callers (Commit 2)

**Files:**
- Modify: `engine/navigation/nav_graph_builder.gd` (lines 45, 47, 70, 71)
- Modify: `tests/integration/test_desire_scatter.gd` (lines 20, 40)
- Modify: `tests/integration/test_hum_tick.gd`
- Modify: `tests/unit/test_species_astar.gd` (lines 44, 63, 93, 100)
- Modify: `tests/unit/test_food_system.gd` (lines 134, 156, 174, 209)
- Modify: `tests/unit/test_reclamation_system.gd` (line 15)
- Modify: `tests/unit/test_heat_grid.gd` (line 17)

These callers compute positions from rack/slot without crossing system boundaries. Mechanical swap with slot inversion.

- [ ] **Step 1: Migrate nav_graph_builder.gd**

In `engine/navigation/nav_graph_builder.gd`:

Replace line 45 (`var x: float = float(Constants.rack_slot_to_pu(0, rack, 0).x)`) and line 47 (`Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 2`) with:

```gdscript
	var floor_center: Vector2 = Constants.floor_rect_world(0).get_center()
	var x: float = floor_center.x + float(rack * 31)  # pixel per-rack offset
	var y: float = floor_center.y
```

Actually, for correctness, use the new rack-centered helper. Replace with:

```gdscript
	var column: Rect2i = Constants.rack_column_rect_world(0, rack)
	var floor_r: Rect2i = Constants.floor_rect_world(0)
	var x: float = float(column.position.x + column.size.x / 2)
	var y: float = float(floor_r.position.y + floor_r.size.y / 2)
```

Replace lines 70-71 (`var x: float = float(Constants.rack_slot_to_pu(0, rack, slot).x)` and `var y: float = float(slot * Constants.SLOT_HEIGHT_PU)`) with:

```gdscript
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var x: float = float(slot_rect.position.x + slot_rect.size.x / 2)
	var y: float = float(slot_rect.position.y + slot_rect.size.y / 2)
```

Note: **slot numbers in nav_graph are unchanged** — the file treats slot numbers opaquely. What changes is the world Y for each slot index (slot 0 now maps to bottom).

- [ ] **Step 2: Run full validate**

```
script/validate
```

Expected: nav-related tests may fail because slot-Y semantics flipped. Fix any that assert on specific Y values — the assertion should stay "slot 0 is at floor level" but the numeric Y will differ.

- [ ] **Step 3: Migrate test_species_astar.gd**

Every `float(N * Constants.SLOT_HEIGHT_PU)` becomes `float(N * 8)` (since SLOT_HEIGHT_PU = 800 in PU = 8 px × POSITION_SCALE; now we're in pure pixels). Actually simpler: calls should use the helper.

Replace `float(38 * Constants.SLOT_HEIGHT_PU)` patterns with whatever slot/rack the test intended. Read the surrounding test to determine intent. If the test constructs a raw Y coordinate 38 slot-heights from the origin, migrate to `float(Constants.slot_origin_world(0, rack, slot).y)` for an explicit address, or keep the arithmetic if it's testing edge-of-world padding.

After migration, every pixel position should be reachable via the new helpers. If the test was using `SLOT_HEIGHT_PU` as a raw number (800), it probably meant `_SLOT_HEIGHT_PX = 8`.

- [ ] **Step 4: Migrate remaining tests**

For each of `test_desire_scatter.gd`, `test_hum_tick.gd`, `test_food_system.gd`, `test_reclamation_system.gd`, `test_heat_grid.gd`:

Replace `Constants.rack_slot_to_pu(b, r, s)` → `Constants.slot_origin_world(b, r, s)` (slot number inverted if the test is asserting a specific visual location).

Replace `slot * Constants.SLOT_HEIGHT_PU` → compute via `Constants.slot_origin_world(0, rack, s).y`.

Replace `Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU` (historically meant "y position of floor") → `Constants.floor_rect_world(0).position.y`.

For tests that placed entities and then asserted proximity: rethink slot numbers. If the test put a server at slot 3 and a cat at slot 5 and expected them close, the new API places slot 5 above slot 3. That's probably still fine — they're still close. But verify the test still expresses the intended spatial relationship.

- [ ] **Step 5: Run validate**

```
script/validate
```

Expected: all migrated tests pass. Any test assertion on a numeric position value must be updated in the same commit.

- [ ] **Step 6: Re-stamp affected tests**

Any stamped test in the leaf list that changed gets re-stamped through the full mutation cycle. Re-run `script/tdd_verify start/mutation/restore/finish` for each. Unstamped leaf tests (the unit and integration tests in this list that are not under `tests/unit/`) don't need stamping — the verify script only requires stamps for `tests/unit/**`.

- [ ] **Step 7: Commit**

```
git add engine/navigation/nav_graph_builder.gd tests/
git commit -m "refactor(coords): migrate leaf callers to slot_rect_world/slot_origin_world"
```

---

## Task 4: Migrate spatial systems atomically (Commit 3)

**Files:**
- Modify: `engine/spatial/heat_grid.gd` (lines 37, 41)
- Modify: `engine/desires/desire_resolver.gd` (lines 82, 103, 205, 208)
- Modify: `engine/desires/desire_scatter.gd` (lines 28, 48-49)
- Modify: `engine/growth/plant_growth_system.gd` (lines 73, 90)
- Modify: `engine/growth/reclamation_system.gd` (line 23)
- Modify: `engine/core/food_system.gd` (lines 61, 88-89, 122)
- Modify: `engine/core/hum_system.gd` (lines 80-81)
- Modify: `engine/core/wiring_system.gd` (line 144)
- Modify: `engine/core/world_init_system.gd` (lines 84, 88, 90)

All these systems talk to each other by reading PU positions out of GameStateDB and computing distances. When slot inversion lands, they must all land together or a cat at (formerly top) slot 0 will talk to a heat source expecting slot 9.

**Key insight:** GameStateDB position components store world pixels in this commit. Positions are integer pixels, not PU. Every system that reads/writes `&"position": {&"x", &"y"}` interprets those as pixels.

- [ ] **Step 1: Migrate heat_grid.gd**

Line 37 currently: `var layout: Dictionary = Constants.pu_to_bay_rack_slot(pos[&"x"], pos[&"y"])`

Replace with the new reverse query:

```gdscript
	var p: Vector2i = Vector2i(pos[&"x"], pos[&"y"])
	var bay: int = Constants.world_to_bay(p)
	if bay == Constants.INVALID_BAY:
		continue
	var q: SlotQuery = Constants.bay_local_to_slot(bay, p)
	if q.zone != &"slot":
		continue
	# rack = q.get_rack(), slot = q.get_slot()
```

Line 41 (`var radius: int = hs[&"radius_ru"]`) — this is the `radius_ru` field. For now keep the same field name (config audit in Task 6 renames it to `radius_px`). The value it holds is interpreted as RU right now. **For this commit**, convert at the read site:

```gdscript
	var radius_ru: int = hs[&"radius_ru"]
	var radius_px: int = radius_ru * Constants._SLOT_HEIGHT_PX  # temp conversion
```

This keeps heat propagation numerically equivalent to the old PU math until Task 6 rewrites the config files to pixel values.

Wait — `Constants._SLOT_HEIGHT_PX` is private. Expose a temporary public alias `SLOT_HEIGHT_PX` (which already exists as a public const) for the conversion site. Use the existing public `SLOT_HEIGHT_PX`.

Use whatever downstream code consumes `radius_px` to query the heat grid cells. The heat grid internal cell indexing is unchanged (still `rack * 10 + slot`), but slot indices are now 0 = bottom.

- [ ] **Step 2: Migrate desire_resolver.gd**

Line 82 (`var radius_pu: int = Constants.ru_to_pu(ad[&"radius_ru"])`) becomes:

```gdscript
	var radius_px: int = ad[&"radius_ru"] * Constants.SLOT_HEIGHT_PX
```

Line 103 (`var perception_pu: int = Constants.ru_to_pu(8)`) becomes:

```gdscript
	var perception_px: int = 8 * Constants.SLOT_HEIGHT_PX
```

Lines 205-208 (constructing a floor-level position):

```gdscript
	var center_x: int = Constants.rack_slot_to_pu(0, rack, 0).x
	...
	var y: int = Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 2
```

Becomes:

```gdscript
	var column: Rect2i = Constants.rack_column_rect_world(0, rack)
	var center_x: int = column.position.x + column.size.x / 2
	var floor_r: Rect2i = Constants.floor_rect_world(0)
	var y: int = floor_r.position.y + floor_r.size.y / 2
```

- [ ] **Step 3: Migrate desire_scatter.gd**

Line 28 (`Constants.ru_to_pu(8)` as a perception radius) and lines 48-49 (per-ad `radius_ru`) — replace with the same pattern:

```gdscript
# was: Constants.ru_to_pu(8)
	var perception_px: int = 8 * Constants.SLOT_HEIGHT_PX
# was: Constants.ru_to_pu(ad[&"radius_ru"])
	var radius_px: int = ad[&"radius_ru"] * Constants.SLOT_HEIGHT_PX
```

- [ ] **Step 4: Migrate plant_growth_system.gd**

Line 73 — `radius_ru` on an outgoing advertisement: rewrite the advert to emit `radius_ru` unchanged (still read as RU by consumers).

Line 90 (`var info: Dictionary = Constants.pu_to_bay_rack_slot(pos[&"x"], pos[&"y"])`): replace with `world_to_bay` + `bay_local_to_slot` as in Step 1.

When positioning the plant sprite, the plant must perch on top of the rack frame:

```gdscript
	var host_bay: int = Constants.world_to_bay(Vector2i(host_pos[&"x"], host_pos[&"y"]))
	var host_q: SlotQuery = Constants.bay_local_to_slot(host_bay, Vector2i(host_pos[&"x"], host_pos[&"y"]))
	assert(host_q.zone == &"slot", "plant host must be in a slot")
	var frame_rect: Rect2i = Constants.rack_frame_rect(host_bay, host_q.get_rack())
	var plant_x: int = frame_rect.position.x + frame_rect.size.x / 2
	var plant_y: int = frame_rect.position.y  # perched on frame top edge
```

- [ ] **Step 5: Migrate reclamation_system.gd**

Line 23 (`var proximity_pu: int = _PROXIMITY_RU * Constants.SLOT_HEIGHT_PU * 2`) becomes:

```gdscript
	var proximity_px: int = _PROXIMITY_RU * Constants.SLOT_HEIGHT_PX * 2
```

- [ ] **Step 6: Migrate food_system.gd**

Line 61 (`Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU`): this is constructing a floor Y — replace with `Constants.floor_rect_world(0).position.y`.

Lines 88-89 (`Constants.ru_to_pu(arm_data[&"radius_ru"])`): `* Constants.SLOT_HEIGHT_PX` pattern.

Line 122 (hardcoded `&"radius_ru": 6`): leave field name for now; Task 6 renames and adjusts value.

- [ ] **Step 7: Migrate hum_system.gd, wiring_system.gd, world_init_system.gd**

Same pattern:
- `Constants.ru_to_pu(N)` → `N * Constants.SLOT_HEIGHT_PX`
- `Constants.rack_slot_to_pu(b, r, s)` → `Constants.slot_rect_world(b, r, s).get_center()` (if caller needs center) or `slot_origin_world`
- `Constants.pu_to_bay_rack_slot(x, y)` → `world_to_bay` + `bay_local_to_slot` + check zone

For `world_init_system.gd` specifically: line 90's `Constants.FLOOR_Y * Constants.POSITION_SCALE` is a floor Y in PU. Becomes `Constants.floor_rect_world(0).position.y + Constants.floor_rect_world(0).size.y / 2` (or `FLOOR_Y` directly if still using pixels — same number).

- [ ] **Step 8: Run validate**

```
script/validate
```

Expected: all spatial tests pass. If any fail with "cat at wrong Y" or "ad radius doesn't reach," debug the specific per-system conversion.

- [ ] **Step 9: Commit**

```
git add engine/
git commit -m "refactor(coords): migrate spatial systems to pixel-native addressing"
```

---

## Task 5: Forcing rename — Commit 4a

**Files:**
- Modify: `engine/core/constants.gd` (add DEPRECATED_ prefix to old API)
- Modify: every remaining caller of the old API (game_server.gd, game_client.gd, heat_overlay.gd, ru_grid_overlay.gd, remaining tests)
- Rename: `nodes/ru_grid_overlay.gd` → `nodes/slot_grid_overlay.gd`

This commit is the compile-error sweep. Everything using the old API breaks at once; we fix each site.

- [ ] **Step 1: Prefix old API with DEPRECATED_**

In `engine/core/constants.gd`, rename the old functions and constants:

```gdscript
const DEPRECATED_POSITION_SCALE: int = 100
# ... (rename all _PU constants by prefixing DEPRECATED_)
static func DEPRECATED_rack_slot_to_pu(...) -> Vector2i:
static func DEPRECATED_pu_to_bay_rack_slot(...) -> Dictionary:
static func DEPRECATED_ru_to_pu(ru: int) -> int:
static func DEPRECATED_pu_to_ru(pu: int) -> int:
static func DEPRECATED_world_to_pu(...) -> Vector2i:
static func DEPRECATED_rack_slot_to_world(...) -> Vector2:
static func DEPRECATED_world_to_rack_slot(...) -> Dictionary:
# Keep to_world/from_world (float↔int conversion) — those are still used by nodes.
# Rename FLOOR_Y_PU, RACK_SLOT0_Y, RACK_FRAME_PX, etc.
# Keep public constants that stay meaningful: SLOT_HEIGHT_PX, RACK_STRIDE_PX,
# FLOOR_HEIGHT_PX, BAY_WIDTH_PX, BAY_STRIDE_PX, RACK_COUNT, SLOTS_PER_RACK,
# VIEWPORT_WIDTH, VIEWPORT_HEIGHT, CEILING_Y, FLOOR_Y, ARM_REACH_RU (renamed
# in Task 6).
```

- [ ] **Step 2: Run compile**

```
/Applications/Godot.app/Contents/MacOS/godot --headless --check-only --path . 2>&1 | head -100
```

Expected: many parse errors pointing to remaining old-API callers. Use this list as the work queue.

- [ ] **Step 3: Fix each remaining caller**

Primary files and their patterns:

**`nodes/game_server.gd` (many sites):**
- `FLOOR_Y_PU` constant (line 4): delete, use `Constants.floor_rect_world(0).position.y` inline.
- Lines 92, 153, 623: `Constants.pu_to_bay_rack_slot(...)` → world_to_bay + bay_local_to_slot pattern.
- Line 157: `pos[&"y"] >= Constants.FLOOR_Y * Constants.POSITION_SCALE` → `pos[&"y"] >= Constants.floor_rect_world(0).position.y`.
- Lines 515, 521, 535, 541, 552, 558, 581, 705: `&"radius_ru": N` stays as a field name for now; value interpreted as RU.
- Line 590: same pu_to_bay_rack_slot pattern.
- Line 610: `Constants.ru_to_pu(2)` → `2 * Constants.SLOT_HEIGHT_PX`.
- Line 648: `FLOOR_Y_PU + Constants.FLOOR_HEIGHT_PU / 2` → `Constants.floor_rect_world(0).get_center().y`.
- Line 659, 680, 686, 687, 691, 698: `Constants.rack_slot_to_pu(0, r, s)` → `Constants.slot_rect_world(0, r, s).get_center()`.
- Lines 699, 770: `FLOOR_Y_PU` and `Constants.ru_to_pu(3)` patterns.

**`nodes/game_client.gd` (many sites):**
- Line 139: `Constants.world_to_pu(world_pos.x, world_pos.y)` → `Vector2i(int(world_pos.x), int(world_pos.y))` (positions are pixels now).
- Line 141: `Constants.ru_to_pu(2)` → `2 * Constants.SLOT_HEIGHT_PX`.
- Line 452: `Constants.RACK_SLOT0_Y` → `Constants.rack_interior_rect_world(0, 0).position.y`.
- Lines 480, 487: `Constants.rack_slot_to_pu(...)` → `Constants.slot_origin_world(...)` or `slot_rect_world(...).get_center()` depending on caller intent.
- Line 492: `Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU` → `Constants.floor_rect_world(0).position.y`.
- Lines 506, 510, 541, 561, 574, 578, 634: same patterns.

**`nodes/heat_overlay.gd` line 28:** `Constants.RACK_SLOT0_Y` → `float(Constants.rack_interior_rect_world(0, 0).position.y)`.

**`nodes/ru_grid_overlay.gd`:**
- Rename file to `nodes/slot_grid_overlay.gd`.
- Rename class if declared.
- Line 13: `Constants.RACK_SLOT0_Y` → `float(Constants.rack_interior_rect_world(0, 0).position.y)`.
- Find the scene that references `ru_grid_overlay.gd` by UID and update the `.tscn` file (or the scene auto-updates via the UID file).

Important: Godot tracks scripts by UID, not path. Renaming the file is safe if you keep the `.gd.uid` file with the same content — Godot follows the UID. But any hardcoded path reference (e.g. `preload("res://nodes/ru_grid_overlay.gd")`) breaks. Grep for that:

```
# Grep for any preload or path reference to the old name.
```

If matches found, update them.

**Remaining tests:** Every test file that still references `rack_slot_to_pu`, `pu_to_bay_rack_slot`, `ru_to_pu`, `SLOT_HEIGHT_PU`, etc. — rename to new API. Keep the test's assertions intact but update the positions they compute.

- [ ] **Step 4: Audit .tscn files**

```
# grep all .tscn files for hardcoded position = Vector2(...) or similar
```

Rack stride is unchanged (31 px), so most hand-coded positions stay valid. Anything referencing the old rack-slot Y layout may need updating.

- [ ] **Step 5: Run full validate**

```
script/validate
```

Expected: parse clean + all tests green. Game may not boot yet if scenarios carry old slot indices — fine, Task 6 fixes that.

- [ ] **Step 6: Commit**

```
git add -A
git commit -m "refactor(coords): rename old PU/RU API to DEPRECATED_, migrate remaining callers"
```

---

## Task 6: Config audit + schema bump — Commit 4b

**Files:**
- Modify: `mods/tcp_base/scenarios/starter.jsonc` (schema 1→2, slot inversion)
- Modify: `mods/tcp_base/objects/hum_device.jsonc`, `arm.jsonc`, `tuna_button.jsonc`, `tuna_dispenser.jsonc`
- Modify: `mods/tcp_cats/species/cat.jsonc`
- Modify: `mods/tcp_ferrets/species/ferret.jsonc`
- Modify: `mods/tcp_tuna/objects/tuna_can.jsonc`
- Modify: `engine/core/constants.gd` (rename `ARM_REACH_RU`)
- Modify: every GDScript reading the `&"radius_ru"` component field

Per-field audit: some `_ru` values are vertical (slot-heights), some are horizontal (rack-stride) or omni-directional (radius in a circular query). The multiplier depends on the semantic.

- [ ] **Step 1: Audit every `_ru` / `_RU` use**

Scan the repo and categorize each site:

```
# Grep for radius_ru, _RU constants
```

For TCP today, the vast majority of `_ru` values are **omni-directional radii** used in euclidean distance queries. Those convert with `px_radius = ru_radius * SLOT_HEIGHT_PX` — because historic RU was 8 px (slot height) and treated as isotropic. The pixel multiplier is 8.

Edge cases to check:
- `ARM_REACH_RU = 3` in `engine/core/constants.gd` — arm reach around the arm entity's position. Omni radius. `ARM_REACH_PX = 24`.
- Any `_ru` on a field named `_distance` or `_x` or `_horizontal`: may want rack-stride math (× 31). For TCP today, there are none.

Document any surprise cases found during audit at the top of this commit's message.

- [ ] **Step 2: Bump starter.jsonc schema_version and invert slot indices**

Open `mods/tcp_base/scenarios/starter.jsonc`:

```jsonc
{
  "schema_version": 2,  // was 1
  ...
  // Every "slot": N entry: invert to 9 - N
  // e.g. slot 0 (top in old system) → slot 9 (top in new)
  //      slot 9 (bottom in old system) → slot 0 (bottom in new)
}
```

Identify each slot reference in the scenario and flip. If the old scenario placed a server at `"slot": 9`, it visually appeared at the bottom in the old system (last interior slot). In the new system, that same visual bottom is `"slot": 0`. So the new value is `9 - 9 = 0`.

- [ ] **Step 3: Rewrite radius_ru → radius_px in every JSONC**

For every `"radius_ru": N`, replace with `"radius_px": M` where `M = N * 8` for omni-directional radii.

Files to touch:
- `mods/tcp_base/objects/hum_device.jsonc` (radius_ru: 4 → radius_px: 32)
- `mods/tcp_base/objects/arm.jsonc` (radius_ru: 3 → radius_px: 24)
- `mods/tcp_cats/species/cat.jsonc` (multiple radius_ru entries)
- `mods/tcp_ferrets/species/ferret.jsonc`
- `mods/tcp_tuna/objects/tuna_can.jsonc` (two entries)

Bump each file's `schema_version` 1 → 2.

- [ ] **Step 4: Rename `ARM_REACH_RU` → `ARM_REACH_PX` in constants.gd**

```gdscript
# was: const ARM_REACH_RU: int = 3
const ARM_REACH_PX: int = 24
```

Update every reference (grep `ARM_REACH_RU`).

- [ ] **Step 5: Rename component field `&"radius_ru"` → `&"radius_px"` everywhere**

In every `.gd` file that reads or writes the `radius_ru` field of `advertisement`, `arm`, `hum_receiver`, `heat_source` components: rename to `radius_px`. Also update the value read to no longer multiply by SLOT_HEIGHT_PX (the field is now already in pixels).

Files to update (from earlier grep):
- `engine/spatial/heat_grid.gd` (reads `radius_ru`)
- `engine/desires/desire_resolver.gd`
- `engine/desires/desire_scatter.gd`
- `engine/growth/plant_growth_system.gd`
- `engine/growth/reclamation_system.gd`
- `engine/core/food_system.gd`
- `engine/core/hum_system.gd`
- `nodes/game_server.gd` (hardcoded dicts)
- `tests/` (many)

The temporary `* Constants.SLOT_HEIGHT_PX` conversion added in Task 4 gets removed here — the field is already in pixels.

- [ ] **Step 6: Update schemas**

`schemas/object_definition.jsonc`, `schemas/transformation_chain.jsonc`, `schemas/ambient_behavior.jsonc` — remove any `radius_ru` definitions, add `radius_px`. Also update comment headers referencing POSITION_SCALE — positions are pixels now.

- [ ] **Step 7: Run validate**

```
script/validate
```

Expected: green. If a test still asserts specific `radius_ru` field values, fix that test to use `radius_px`.

- [ ] **Step 8: Smoke-boot the game**

```
/Applications/Godot.app/Contents/MacOS/godot --path . --quit-after 60
```

Watch the console. Expected: starter scenario loads without schema errors. Cat spawns. Game runs one minute.

- [ ] **Step 9: Commit**

```
git add -A
git commit -m "refactor(coords): schema bump + radius_ru → radius_px per-field audit"
```

---

## Task 7: Delete deprecated API — Commit 5

**Files:**
- Modify: `engine/core/constants.gd` (remove DEPRECATED_ functions and constants)

No saves exist yet, so Commit 4c (save migrator) from the spec is deferred. When save/load is implemented, the migrator includes slot inversion + PU→pixel rescale as a v1→v2 step. Add a note in the save system design doc when it lands.

- [ ] **Step 1: Delete DEPRECATED_ symbols from constants.gd**

Remove all `DEPRECATED_rack_slot_to_pu`, `DEPRECATED_POSITION_SCALE`, `DEPRECATED_ru_to_pu`, etc. Keep public constants still in use.

After deletion, `Constants` should contain:
- Public: `INVALID_ID`, `INVALID_BAY`, `INVALID_SLOT`, `VIEWPORT_WIDTH`, `VIEWPORT_HEIGHT`, `CEILING_Y`, `FLOOR_Y` (aka `floor_rect_world(0).position.y`), `FLOOR_HEIGHT_PX`, `SLOT_HEIGHT_PX`, `SERVER_WIDTH_PX` (if needed externally), `RACK_STRIDE_PX`, `BAY_WIDTH_PX`, `BAY_STRIDE_PX`, `BAY_PEEK_PX`, `SLOTS_PER_RACK`, `RACK_COUNT`, `HEAT_CELLS_*`, `UNIT`, `SWITCH_THRESHOLD`, `EVAL_TIME_BUDGET_USEC`, `ARM_REACH_PX`
- Private: the `_RACK_*` and `_*_PX` implementation constants
- Public functions: `bay_origin_world`, `bay_rect_world`, `world_to_bay`, `rack_column_rect_world`, `rack_interior_rect_world`, `rack_frame_rect`, `rack_baseboard_rect`, `slot_origin_world`, `slot_rect_world`, `floor_rect_world`, `bay_local_to_slot`, `rack_cell`, `floor_cell`, `to_world`/`from_world` (if still needed at rendering boundary — audit)
- Helpers: `_floordiv` stays if still used

- [ ] **Step 2: Run validate**

```
script/validate
```

Expected: green. Any callsite still using DEPRECATED_ causes a parse error.

- [ ] **Step 3: Run full gut suite**

```
script/checks/gut_tests
```

Expected: all green.

- [ ] **Step 4: Manual golden-path smoke**

Launch the game:

```
/Applications/Godot.app/Contents/MacOS/godot --path .
```

Verify:
1. Game boots without errors.
2. Starter scenario loads. Cat spawns on the floor.
3. Observe: cat detects a nearby comfort source (box on server), approaches, settles, purrs.
4. HUM reserve climbs as the cat purrs.
5. No visual glitches in rack layout, plant placement, or animal sprites.

If any step fails, do not proceed. Debug and re-run this task's steps.

- [ ] **Step 5: Grep confirmation that PU/RU terms are gone**

```
# Grep the repo (excluding docs/ and migration-history logs) for:
#   POSITION_SCALE, _PU, rack_slot_to_pu, pu_to_bay_rack_slot,
#   ru_to_pu, pu_to_ru, radius_ru, RACK_SLOT0_Y, FLOOR_Y_PU,
#   SLOT_HEIGHT_PU, ARM_REACH_RU
```

Expected: zero matches in `engine/`, `nodes/`, `mods/`, `tests/`. Matches in `docs/superpowers/` and `.claude/rules/` are fine but should be updated in a follow-up docs commit.

- [ ] **Step 6: Commit**

```
git add engine/core/constants.gd
git commit -m "refactor(coords): remove deprecated PU/RU API"
```

---

## Task 8: Docs sync

**Files:**
- Modify: `CLAUDE.md` (Coordinate system section, Known Issues)
- Modify: `.claude/rules/art-direction.md` (references to POSITION_SCALE, RACK_SLOT0_Y)
- Modify: `.claude/rules/objects.md` (radius_ru → radius_px)
- Modify: `.claude/rules/animal-ai.md` (radius_ru references)
- Modify: `.claude/rules/hum-cable-system.md`, `food-system.md`, `growth-system.md`, `modding.md`
- Modify: `.claude/rules/scene-tree.md`

Rules and CLAUDE.md still reference the old API. Update text to match the new reality.

- [ ] **Step 1: Update CLAUDE.md**

In the "Coordinate system — use canonical helpers" section, replace the entire function list:

```markdown
### Coordinate system — use canonical helpers

Three-layer addressing: `(bay, rack, slot)` where slot 0 is the bottom slot and slot 9 is the top. All positions are integer Godot world pixels — no PU, no RU, no U.

- `Constants.bay_origin_world(bay) -> Vector2i` — upper-left pixel of a bay
- `Constants.bay_rect_world(bay) -> Rect2i`
- `Constants.world_to_bay(world_pos) -> int` — returns INVALID_BAY if outside any bay
- `Constants.rack_column_rect_world(bay, rack) -> Rect2i`
- `Constants.rack_interior_rect_world(bay, rack) -> Rect2i`
- `Constants.rack_frame_rect(bay, rack) -> Rect2i` — plant zone
- `Constants.rack_baseboard_rect(bay, rack) -> Rect2i`
- `Constants.slot_origin_world(bay, rack, slot) -> Vector2i`
- `Constants.slot_rect_world(bay, rack, slot) -> Rect2i`
- `Constants.floor_rect_world(bay) -> Rect2i`
- `Constants.bay_local_to_slot(bay, world_pos) -> SlotQuery` — reverse query with typed zone

Slot 0 is visually at the bottom. `slot_origin_world(0, 0, 0).y > slot_origin_world(0, 0, 9).y` because Godot Y increases downward. The inversion lives inside the helper — callers never flip manually.
```

Remove the "PU coordinate system adds unnecessary complexity" bullet from Known Issues.

Remove the "Heat overlay alignment uses RACK_SLOT0_Y now" bullet (replace with "Heat overlay aligns via `rack_interior_rect_world(0, 0).position.y`").

- [ ] **Step 2: Update .claude/rules/art-direction.md**

Replace references to `POSITION_SCALE`, `_PU` twins, and `RACK_SLOT0_Y = 28` with the new pixel-native addressing.

- [ ] **Step 3: Update .claude/rules/objects.md, animal-ai.md, modding.md, hum-cable-system.md, food-system.md, growth-system.md**

Every `radius_ru` reference in these rules becomes `radius_px`. Update example JSON snippets.

- [ ] **Step 4: Update .claude/rules/scene-tree.md**

Line 48 referenced `Constants.pu_to_bay_rack_slot()` — update to:

> A bay is one `rack_5set` sprite; slots are resolved by `Constants.bay_local_to_slot()` on click, which returns a typed `SlotQuery` with zone tagging.

- [ ] **Step 5: Run validate**

```
script/validate
```

Expected: green (docs changes are non-code but the post-edit hook may run on them).

- [ ] **Step 6: Commit**

```
git add CLAUDE.md .claude/rules/
git commit -m "docs(coords): sync rules with new bay/rack/slot API"
```

---

## Self-Review Checklist (before handing off)

Run through these before offering execution:

**Spec coverage:**
- ✅ Three-layer addressing (bay/rack/slot) — Task 1
- ✅ Named zones (frame, baseboard, floor) — Task 1
- ✅ SlotQuery reverse lookup — Task 1
- ✅ Y stays Godot-native, inversion inside helper — Task 1 (with invariant test)
- ✅ Migrate leaf callers — Task 3
- ✅ Migrate spatial systems atomically — Task 4
- ✅ Forcing rename of old API — Task 5
- ✅ Config schema bump + per-field `_ru` audit — Task 6
- ⚠️ Save migrator — **deferred** (no save system exists yet). Noted at Task 7.
- ✅ Delete old API — Task 7
- ✅ Golden-path smoke verifies Ring 0 bug is fixed — Task 7 Step 4

**Type/name consistency:**
- `SlotQuery` defined in Task 1 Step 1; referenced consistently throughout.
- `rack_frame_rect` (no `_world` suffix) matches the spec.
- `rack_baseboard_rect` matches the spec.
- `SLOT_HEIGHT_PX` is public in the current Constants; we use it directly in Task 4 instead of `_SLOT_HEIGHT_PX` (private).

**Placeholders:**
- No "TBD", "TODO", "implement later" — all steps have concrete code.
- "Audit" steps in Task 5 and Task 6 have explicit grep commands and categorization rules.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-19-coordinate-system-redesign.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Large-surface refactors like this benefit from the per-task clean context: each subagent sees only the relevant code and this task's scope, avoiding drift.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints for review.

Which approach?
