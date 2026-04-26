# Cat Jumps Into Box Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two server+box stacks in adjacent racks, one HUM. One cat starts pre-settled inside box-0; the second cat finds box-1 by emergent desire, climbs in, settles, purrs. The HUM bar visibly fills. Cross-rack purr propagation (cat A reaching HUM in rack 1) is gated on contentment.

**Architecture:** Inversion - the entity owns its physical capabilities and emission geometry; infrastructure publishes only its dimensions. Cat declares `body_capabilities` (walks, jumps, drops, settles_in_containers) and `body_geometry`. NavGraphBuilder extends with an ENTER edge type and a `add_box_enterable()` method. Box gains a `contained` join type on its `state_advertisements`, alongside the existing `stack` and `nearby` from the Resting-On spec. ContentmentPurrBridge writes both `purr.intensity` AND `purr.radius_px`. HumSystem.tick_charge inverts: per cat, intersect emission disk with each HUM's body rect (computed from `physical.size_ru x SLOT_HEIGHT_PX` x `RACK_WIDTH_PX`, anchored at the HUM's slot). animal_node.gd stops snapping Y to FLOOR_Y - 1.

**Tech Stack:** GDScript / Godot 4.6, GUT for testing, integer-only game state per TCP's design philosophy. Existing systems extended (not replaced): NavGraphBuilder, ObjectStateManager, ContentmentPurrBridge, HumSystem, WorldInitSystem.

**Reference spec:** `docs/superpowers/specs/2026-04-26-cat-jumps-into-box-design.md`

---

## File Structure

### Created
- `nodes/effects/purr_ring.gd` + `purr_ring.tscn` - pixel-note ring rendered around purring entities
- `tests/unit/test_contentment_purr_bridge_radius.gd` - bridge writes radius_px
- `tests/unit/test_hum_system_emission_intersection.gd` - rect-disk intersection charging
- `tests/unit/test_nav_graph_builder_enter_edges.gd` - ENTER scanner emits/skips edges
- `tests/unit/test_nav_graph_builder_jump_up_edges.gd` - JUMP_UP scanner respects max_height_ru
- `tests/unit/test_settled_in_relationship_lifecycle.gd` - enter/exit/dissolve/capacity
- `tests/integration/test_cat_into_box_charges_hum.gd` - end-to-end loop
- `tests/simulation/test_no_orphaned_settled_relationships.gd` - soak invariants

### Modified (with line references where stable)
- `engine/objects/object_state_manager.gd:7-43` - OBJECT_CONFIG migrates `state_ads: [...]` -> `state_ads: {ads: [...], join: {...}}`. Adds `contained` join type. New methods: `get_join_for_state()`, `transition_state` updates relationships when join changes.
- `engine/core/contentment_purr_bridge.gd:10-19` - writes `radius_px` alongside `intensity` each tick using `purr_config.base_radius_ru * intensity / UNIT`.
- `engine/core/hum_system.gd:66-99` - `tick_charge` inverts to disk-vs-rect intersection; charges every receiver whose body rect intersects the cat's emission disk.
- `engine/navigation/nav_graph_builder.gd` - adds `ENTER` edge type, `add_box_enterable()`, refactors capabilities-array handling to read parametric `body_capabilities` dict.
- `engine/navigation/species_astar.gd` - adds `ENTER` constant alongside `WALK`, `JUMP_UP`, `JUMP_DOWN`.
- `engine/core/world_init_system.gd:71-97` - adds `settled_in_ref` resolution in a fourth pass after refs are known.
- `nodes/animal_node.gd:32-37, 138-141, 190` - render Y from `position.y` directly (drop FLOOR_Y - 1 hardcode); add z-order rule for `settled_in` relationship; add `edge_animations` playback during MOVING_TO.
- `nodes/game_server.gd` - call `nav_graph_builder.add_box_enterable()` on box placement; run position-coupling pass for `contained` joins after main movement loop; dissolve `&"sleeping"` relationships on ai_state SEEKING transition.
- `mods/tcp_cats/species/cat.jsonc` - replace `traversal: [...]` and `max_jump_height_ru: 3` with `body_capabilities: {...}`. Add `body_geometry: {size_ru: 2}`. Move `purr` block into `purr_config: {rate_when_satisfied, base_radius_ru: 6}`. Add `edge_animations` map.
- `mods/tcp_base/objects/hum_device.jsonc:12-14` - `hum_receiver` becomes `{}` (drop `radius_px: 32`).
- `mods/tcp_base/scenarios/starter.jsonc` - new layout: rack 0 server+box (Cat A pre-settled), rack 1 server+box, single HUM in rack 1, Cat B on floor, existing food chain stays.
- `engine/mod/species_schema_validator.gd` - require `body_capabilities`, `body_geometry`; deprecate `traversal` + `max_jump_height_ru`.
- `engine/mod/entity_def_registry.gd` - on cat spawn, materialize `body_capabilities`, `body_geometry`, `purr_config.base_radius_ru` components from recipe.
- `CLAUDE.md` - remove the FLOOR_Y - 1 hardcode AI-DEV note from "Known Issues".
- `docs/art-asset-tracker.md` - mark `cat01_jump_strip4`, `cat01_land_strip2`, `cat01_ledgeclimb_strip11` as wired.

---

## Pre-flight: worktree setup

This plan assumes a fresh worktree off `main`. The current branch (`fix/pet-to-satisfied-chain`) is unrelated; do NOT implement on top of it.

```bash
cd /Users/chucklauervose/github/tuna-control-protocol
git fetch origin
git worktree add ../tcp-cat-into-box -b feat/cat-jumps-into-box origin/main
cd ../tcp-cat-into-box
script/validate   # baseline: confirm green before any changes
```

If `script/validate` is red on a fresh `main`, stop and triage before starting tasks - the plan assumes a green baseline so per-task `script/validate` failures are diagnostic.

---

## Task 1: Add body_capabilities + body_geometry to species recipe schema

**Files:**
- Modify: `mods/tcp_cats/species/cat.jsonc` (replace `traversal` + `max_jump_height_ru` with `body_capabilities`; add `body_geometry`)
- Modify: `engine/mod/species_schema_validator.gd` (require new fields, reject old ones with `push_error`)
- Modify: `engine/mod/entity_def_registry.gd` (on spawn, write `body_capabilities` and `body_geometry` components from recipe)

- [ ] **Step 1: Read the current cat.jsonc and species_schema_validator.gd to understand existing shape**

```bash
cat mods/tcp_cats/species/cat.jsonc | head -40
cat engine/mod/species_schema_validator.gd | head -80
```

Expected: `cat.jsonc` has `traversal: ["WALK","JUMP_UP","JUMP_DOWN"]` and `max_jump_height_ru: 3` at top level. The validator's required-fields list contains `traversal`.

- [ ] **Step 2: Edit cat.jsonc**

Replace the `traversal` and `max_jump_height_ru` fields with `body_capabilities` and `body_geometry`:

```jsonc
// Remove these two lines:
//   "traversal": ["WALK", "JUMP_UP", "JUMP_DOWN"],
//   "max_jump_height_ru": 3,
// Add at the same nesting level:
"body_capabilities": {
    "walks":  {},
    "jumps":  { "max_height_ru": 3 },
    "drops":  { "max_height_ru": 5 },
    "settles_in_containers": { "max_body_size_ru": 2 }
},
"body_geometry": {
    "size_ru": 2
},
```

(Note: `climbs`, `fits_in_tubes`, `settles_on_surfaces` are deferred per spec - declared in spec, not in cat.jsonc this slice.)

- [ ] **Step 3: Update species_schema_validator.gd**

```gdscript
# In the required-fields list (search for "traversal" or "REQUIRED_FIELDS"):
# - Remove `&"traversal"` from the array
# - Remove `&"max_jump_height_ru"` if present
# - Add `&"body_capabilities"` to the array
# - Add `&"body_geometry"` to the array

# In the validator function, add a check that rejects the legacy fields:
if recipe.has("traversal"):
    push_error("species %s: legacy `traversal` field; use `body_capabilities`" % recipe.get("id", "?"))
    return false
if recipe.has("max_jump_height_ru"):
    push_error("species %s: legacy `max_jump_height_ru`; move to body_capabilities.jumps.max_height_ru" % recipe.get("id", "?"))
    return false

# Add a check that body_capabilities is a non-empty dict:
var caps_v = recipe["body_capabilities"]
if not (caps_v is Dictionary) or (caps_v as Dictionary).is_empty():
    push_error("species %s: body_capabilities must be a non-empty dict" % recipe.get("id", "?"))
    return false
```

- [ ] **Step 4: Update entity_def_registry.gd to materialize the components**

In the species spawn code (search for where `purr` or `desires` components are written from the recipe), add:

```gdscript
# After existing recipe-to-component materialization:
if recipe.has("body_capabilities"):
    db.set_component(entity_id, &"body_capabilities", recipe["body_capabilities"])
if recipe.has("body_geometry"):
    db.set_component(entity_id, &"body_geometry", recipe["body_geometry"])
```

- [ ] **Step 5: Run validation**

```bash
script/validate
```

Expected: PASS. If `script/checks/json_snake_case_keys` complains, the `body_capabilities` keys (`walks`, `jumps`, etc.) are already snake_case - this should be clean.

- [ ] **Step 6: Commit**

```bash
git add mods/tcp_cats/species/cat.jsonc engine/mod/species_schema_validator.gd engine/mod/entity_def_registry.gd
git commit -m "$(cat <<'EOF'
refactor(species): replace traversal array with body_capabilities dict

cat.jsonc now declares body_capabilities (walks, jumps, drops,
settles_in_containers) with parametric values per verb, and body_geometry
(size_ru). Spawn materializes both as components. Schema validator rejects
the legacy traversal + max_jump_height_ru fields with a migration hint.

Foundation for the per-species navgraph scanners that follow.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: ContentmentPurrBridge writes radius_px

**Files:**
- Modify: `mods/tcp_cats/species/cat.jsonc` (move `purr.rate_when_satisfied` into `purr_config: {rate_when_satisfied, base_radius_ru: 6}`)
- Modify: `engine/mod/entity_def_registry.gd` (spawn writes `purr_config.base_radius_ru`)
- Modify: `engine/core/contentment_purr_bridge.gd` (write `radius_px = base_radius_ru * SLOT_HEIGHT_PX * intensity / UNIT`)
- Test: `tests/unit/test_contentment_purr_bridge_radius.gd` (new file)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_contentment_purr_bridge_radius.gd`:

```gdscript
extends GutTest

# AI-DEV: AI **MUST NOT** touch this test. If the test is failing, it is
# because you removed or broke code.

const SLOT_HEIGHT_PX: int = 8
const UNIT: int = 1000


func _make_db_with_purrer(is_satisfied: int, base_radius_ru: int, rate: int) -> GameStateDB:
    var db := GameStateDB.new()
    var eid: int = db.create_entity()
    db.set_component(eid, &"contentment", {&"is_satisfied": is_satisfied, &"value": 800})
    db.set_component(eid, &"purr", {&"intensity": 0, &"radius_px": 0})
    db.set_component(eid, &"purr_config", {
        &"rate_when_satisfied": rate,
        &"base_radius_ru": base_radius_ru,
    })
    return db


func test_radius_px_zero_when_not_satisfied() -> void:
    var db := _make_db_with_purrer(0, 6, 10)
    var bridge := ContentmentPurrBridge.new(db)
    bridge.tick()
    var ids: Array[int] = db.get_entities_with(&"purr")
    assert_eq(db.get_field(ids[0], &"purr", &"radius_px"), 0)


func test_radius_px_full_when_satisfied_at_full_intensity() -> void:
    # base_radius_ru=6 -> 48 px. intensity=10/1000? Actually intensity equals
    # the rate when satisfied; the formula reads intensity from the just-written
    # field. With rate=UNIT the formula yields full base_radius_ru * SLOT_HEIGHT_PX.
    var db := _make_db_with_purrer(1, 6, UNIT)
    var bridge := ContentmentPurrBridge.new(db)
    bridge.tick()
    var ids: Array[int] = db.get_entities_with(&"purr")
    assert_eq(db.get_field(ids[0], &"purr", &"radius_px"), 6 * SLOT_HEIGHT_PX)


func test_radius_px_scales_linearly_with_intensity() -> void:
    var db := _make_db_with_purrer(1, 6, 500)  # 50% intensity
    var bridge := ContentmentPurrBridge.new(db)
    bridge.tick()
    var ids: Array[int] = db.get_entities_with(&"purr")
    # Expected: 6 * 8 * 500 / 1000 = 24 px
    assert_eq(db.get_field(ids[0], &"purr", &"radius_px"), 24)


func test_no_purr_config_skipped() -> void:
    var db := GameStateDB.new()
    var eid: int = db.create_entity()
    db.set_component(eid, &"contentment", {&"is_satisfied": 1, &"value": 800})
    db.set_component(eid, &"purr", {&"intensity": 0, &"radius_px": 0})
    # No purr_config - bridge should skip
    var bridge := ContentmentPurrBridge.new(db)
    bridge.tick()
    assert_eq(db.get_field(eid, &"purr", &"intensity"), 0)
    assert_eq(db.get_field(eid, &"purr", &"radius_px"), 0)
```

- [ ] **Step 2: Run test to verify failure**

```bash
script/checks/gut_tests -f tests/unit/test_contentment_purr_bridge_radius.gd
```

Expected: FAIL on `test_radius_px_full_when_satisfied_at_full_intensity` (and `_scales_linearly`) because the bridge does not yet write `radius_px`.

- [ ] **Step 3: Update cat.jsonc**

Replace the existing `purr` block with `purr_config`:

```jsonc
// Replace:
//   "purr": { "rate_when_satisfied": 10 },
// With:
"purr_config": {
    "rate_when_satisfied": 10,
    "base_radius_ru": 6
},
```

- [ ] **Step 4: Update entity_def_registry.gd**

Find the existing handler for the `purr` recipe block (where `purr_config` is materialized). Update to read `base_radius_ru`:

```gdscript
# In the purr/purr_config materialization (search for "rate_when_satisfied"):
if recipe.has("purr_config"):
    var pc: Dictionary = recipe["purr_config"]
    db.set_component(entity_id, &"purr_config", {
        &"rate_when_satisfied": pc.get("rate_when_satisfied", 0),
        &"base_radius_ru": pc.get("base_radius_ru", 0),
    })
    # purr scratch component (if not already created elsewhere):
    if not db.has_component(entity_id, &"purr"):
        db.set_component(entity_id, &"purr", {&"intensity": 0, &"radius_px": 0})
```

If the existing code reads from `recipe["purr"]["rate_when_satisfied"]`, switch to `recipe["purr_config"]["rate_when_satisfied"]`. Search and update all callsites.

- [ ] **Step 5: Implement the bridge**

Replace `engine/core/contentment_purr_bridge.gd` body:

```gdscript
class_name ContentmentPurrBridge extends RefCounted

# AI-DEV: This bridge writes BOTH purr.intensity and purr.radius_px each tick.
# radius_px = base_radius_ru * SLOT_HEIGHT_PX * intensity / UNIT. Future modifiers
# (mood, kitten amplifier, stress) fold into the formula; do not reintroduce a
# fixed-radius shortcut.

var _db: GameStateDB


func _init(db: GameStateDB) -> void:
    _db = db


func tick() -> void:
    for entity_id: int in _db.get_entities_with(&"purr"):
        if not _db.has_component(entity_id, &"contentment"):
            continue
        if not _db.has_component(entity_id, &"purr_config"):
            continue
        var is_satisfied: int = _db.get_field(entity_id, &"contentment", &"is_satisfied")
        var rate: int = _db.get_field(entity_id, &"purr_config", &"rate_when_satisfied")
        var intensity: int = rate if is_satisfied == 1 else 0
        _db.set_field(entity_id, &"purr", &"intensity", intensity)

        var base_radius_ru: int = _db.get_field(entity_id, &"purr_config", &"base_radius_ru")
        var base_radius_px: int = base_radius_ru * Constants.SLOT_HEIGHT_PX
        var radius_px: int = base_radius_px * intensity / Constants.UNIT
        _db.set_field(entity_id, &"purr", &"radius_px", radius_px)
```

- [ ] **Step 6: Run tests to verify pass**

```bash
script/checks/gut_tests -f tests/unit/test_contentment_purr_bridge_radius.gd
```

Expected: 4 passed.

- [ ] **Step 7: Stamp the test**

```bash
script/stamp_tests tests/unit/test_contentment_purr_bridge_radius.gd
```

(Per `verify-test` protocol: stamp once green so future regressions are detected.)

- [ ] **Step 8: Run full validation to catch knock-on breakage**

```bash
script/validate
```

Expected: PASS. If `test_hum_system.gd` or other tests fail because they constructed `purr_config` with the old shape, fix those tests' setup (do NOT change product code).

- [ ] **Step 9: Commit**

```bash
git add tests/unit/test_contentment_purr_bridge_radius.gd tests/unit/test_contentment_purr_bridge_radius.gd.stamp \
  mods/tcp_cats/species/cat.jsonc engine/core/contentment_purr_bridge.gd engine/mod/entity_def_registry.gd
git commit -m "$(cat <<'EOF'
feat(purr): bridge writes radius_px alongside intensity

ContentmentPurrBridge now writes purr.radius_px = base_radius_ru *
SLOT_HEIGHT_PX * intensity / UNIT each tick. cat.jsonc gains
purr_config.base_radius_ru: 6 (48 px at full bliss; cross-rack reach when
contented). Foundation for the HumSystem.tick_charge inversion.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: HumSystem.tick_charge inversion (cat-disk vs HUM-rect)

**Files:**
- Modify: `engine/core/hum_system.gd:66-99` (rewrite `tick_charge`)
- Modify: `mods/tcp_base/objects/hum_device.jsonc:12-14` (drop `radius_px: 32` from `hum_receiver`)
- Modify: `engine/mod/entity_def_registry.gd` (handle `hum_receiver: {}` empty form)
- Test: `tests/unit/test_hum_system_emission_intersection.gd` (new file)
- Possibly modify: `tests/unit/test_hum_system.gd` (existing tests need setup updates - they likely set `hum_receiver.radius_px`; switch to the new shape)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_hum_system_emission_intersection.gd`:

```gdscript
extends GutTest

# AI-DEV: AI **MUST NOT** touch this test. If the test is failing, it is
# because you removed or broke code.

# HUM body rect = (anchor_top, RACK_WIDTH_PX) wide, (size_ru * SLOT_HEIGHT_PX) tall.
# Cat emission disk = circle(cat.pos, purr.radius_px). Charge if rect intersects disk.

const RACK_WIDTH_PX: int = 23
const SLOT_HEIGHT_PX: int = 8


func _make_hum(db: GameStateDB, rack: int, slot: int, size_ru: int) -> int:
    var hum_id: int = db.create_entity()
    var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
    var cx: int = slot_rect.position.x + slot_rect.size.x / 2
    var cy: int = slot_rect.position.y + slot_rect.size.y / 2
    db.set_component(hum_id, &"hum", {&"reserve": 0, &"capacity": 10000})
    db.set_component(hum_id, &"hum_receiver", {})
    db.set_component(hum_id, &"position", {&"x": cx, &"y": cy})
    db.set_component(hum_id, &"physical", {&"mass": 20000, &"size_ru": size_ru})
    return hum_id


func _make_cat(db: GameStateDB, x: int, y: int, intensity: int, radius_px: int) -> int:
    var cat_id: int = db.create_entity()
    db.set_component(cat_id, &"position", {&"x": x, &"y": y})
    db.set_component(cat_id, &"purr", {&"intensity": intensity, &"radius_px": radius_px})
    return cat_id


func test_disk_intersects_body_rect_charges_hum() -> void:
    # HUM at rack 1 slot 9 (top), 6U body. Cat in rack 1 slot 1 (close enough).
    var db := GameStateDB.new()
    var hum := _make_hum(db, 1, 9, 6)
    var slot1 := Constants.slot_rect_world(0, 1, 1)
    _make_cat(db, slot1.position.x + slot1.size.x / 2, slot1.position.y + slot1.size.y / 2, 100, 48)
    var hs := HumSystem.new(db)
    hs.tick_charge()
    assert_eq(db.get_field(hum, &"hum", &"reserve"), 100)


func test_disk_does_not_intersect_no_charge() -> void:
    # Cat far from HUM; small radius.
    var db := GameStateDB.new()
    var hum := _make_hum(db, 1, 9, 6)
    var slot1 := Constants.slot_rect_world(0, 1, 1)
    _make_cat(db, slot1.position.x + slot1.size.x / 2, slot1.position.y + slot1.size.y / 2, 100, 4)
    var hs := HumSystem.new(db)
    hs.tick_charge()
    assert_eq(db.get_field(hum, &"hum", &"reserve"), 0)


func test_disk_intersects_two_hums_charges_both() -> void:
    var db := GameStateDB.new()
    var hum_a := _make_hum(db, 0, 9, 6)
    var hum_b := _make_hum(db, 1, 9, 6)
    # Cat positioned roughly midway, with radius big enough to reach both
    var rack0 := Constants.rack_column_rect_world(0, 0)
    var rack1 := Constants.rack_column_rect_world(0, 1)
    var midx: int = (rack0.position.x + rack1.position.x + rack1.size.x) / 2
    var slot1 := Constants.slot_rect_world(0, 0, 1)
    _make_cat(db, midx, slot1.position.y, 50, 80)
    var hs := HumSystem.new(db)
    hs.tick_charge()
    assert_eq(db.get_field(hum_a, &"hum", &"reserve"), 50)
    assert_eq(db.get_field(hum_b, &"hum", &"reserve"), 50)


func test_zero_intensity_no_charge() -> void:
    var db := GameStateDB.new()
    var hum := _make_hum(db, 1, 9, 6)
    var slot := Constants.slot_rect_world(0, 1, 9)
    _make_cat(db, slot.position.x, slot.position.y, 0, 100)  # large radius but intensity 0
    var hs := HumSystem.new(db)
    hs.tick_charge()
    assert_eq(db.get_field(hum, &"hum", &"reserve"), 0)


func test_cross_rack_reach_gated_on_radius() -> void:
    # Cat in rack 0 slot 1, HUM in rack 1 slot 9. With small radius: no charge.
    # With large radius: charges.
    var db := GameStateDB.new()
    var hum := _make_hum(db, 1, 9, 6)
    var slot01 := Constants.slot_rect_world(0, 0, 1)
    var cx: int = slot01.position.x + slot01.size.x / 2
    var cy: int = slot01.position.y + slot01.size.y / 2
    var cat := _make_cat(db, cx, cy, 75, 16)  # 16 px = strictly intra-rack
    var hs := HumSystem.new(db)
    hs.tick_charge()
    assert_eq(db.get_field(hum, &"hum", &"reserve"), 0, "16-px radius does not cross rack gap")
    db.set_field(cat, &"purr", &"radius_px", 64)  # 64 px = cross-rack
    hs.tick_charge()
    assert_gt(db.get_field(hum, &"hum", &"reserve"), 0, "64-px radius reaches across rack gap")
```

- [ ] **Step 2: Run test, expect failure**

```bash
script/checks/gut_tests -f tests/unit/test_hum_system_emission_intersection.gd
```

Expected: FAIL (current `tick_charge` reads `radius_px` from `hum_receiver` which is now `{}`, panics with assert/error; or finds no `hum_receiver.radius_px` and returns 0 charges).

- [ ] **Step 3: Edit hum_device.jsonc**

```jsonc
// Change:
//   "hum_receiver": { "radius_px": 32 },
// To:
"hum_receiver": {},
```

- [ ] **Step 4: Update entity_def_registry.gd to write empty hum_receiver**

Search for the `hum_receiver` materialization (likely already handles arbitrary dict). Verify it accepts `{}` without erroring. If it explicitly requires `radius_px`, remove that requirement.

- [ ] **Step 5: Rewrite hum_system.gd's tick_charge**

Replace the body of `tick_charge` (engine/core/hum_system.gd:66 onwards) with:

```gdscript
func tick_charge() -> void:
    var receivers: Array[int] = _db.get_entities_with(&"hum_receiver")
    if receivers.is_empty():
        return
    var per_hum_charge: Dictionary = {}
    for emitter_id: int in _db.get_entities_with(&"purr"):
        var intensity: int = _db.get_field(emitter_id, &"purr", &"intensity")
        if intensity <= 0:
            continue
        var radius_px: int = _db.get_field(emitter_id, &"purr", &"radius_px")
        if radius_px <= 0:
            continue
        var ex: int = _db.get_field(emitter_id, &"position", &"x")
        var ey: int = _db.get_field(emitter_id, &"position", &"y")
        for r_id: int in receivers:
            var rect: Rect2i = _hum_body_rect(r_id)
            if not _disk_intersects_rect(ex, ey, radius_px, rect):
                continue
            per_hum_charge[r_id] = per_hum_charge.get(r_id, 0) + intensity
    for hum_id: int in per_hum_charge:
        charge(hum_id, per_hum_charge[hum_id])


# Compute the HUM's body rectangle from its anchor position and physical size_ru.
# anchor position is the slot center (stored when the HUM was placed); body
# extends symmetrically from anchor in width but downward in height (slot 0 is
# the bottom; the HUM's bottom edge sits at the bottom of its anchor slot, body
# rises through size_ru-1 slots above).
func _hum_body_rect(hum_id: int) -> Rect2i:
    var px: int = _db.get_field(hum_id, &"position", &"x")
    var py: int = _db.get_field(hum_id, &"position", &"y")
    var size_ru: int = _db.get_field(hum_id, &"physical", &"size_ru")
    var height_px: int = size_ru * Constants.SLOT_HEIGHT_PX
    # px,py is the slot center where the HUM was anchored. Body extends
    # (size_ru/2) slots above and below the anchor in pixels (or, for an even
    # size_ru, mostly above since slot anchors live at the slot's center).
    # Conservative: body rect is centered on (px, py) - actually the existing
    # entity_def_registry positions a 6U HUM with `slot: 9` at slot 9's center;
    # the body extends down through slots 4-9. So body top = anchor's slot top,
    # body height = size_ru * SLOT_HEIGHT_PX.
    var anchor_slot_rect: Rect2i = _slot_rect_for_position(px, py)
    var top_y: int = anchor_slot_rect.position.y
    var left_x: int = anchor_slot_rect.position.x
    return Rect2i(left_x, top_y, Constants.RACK_WIDTH_PX, height_px)


# Resolve world (px, py) back to its containing slot rect. Uses the existing
# bay_local_to_slot helper.
func _slot_rect_for_position(px: int, py: int) -> Rect2i:
    var bay_origin: Vector2i = Constants.bay_origin_world(0)
    var bay_local: Vector2i = Vector2i(px - bay_origin.x, py - bay_origin.y)
    var query: SlotQuery = Constants.bay_local_to_slot(0, bay_local)
    if query.zone != &"slot":
        # Fallback: build rect around the position assuming slot-aligned anchor
        return Rect2i(px - Constants.RACK_WIDTH_PX / 2, py - Constants.SLOT_HEIGHT_PX / 2,
                Constants.RACK_WIDTH_PX, Constants.SLOT_HEIGHT_PX)
    return Constants.slot_rect_world(0, query.get_rack(), query.get_slot())


# Closest-point-on-rect to circle-center; if distance to that point < radius, intersects.
func _disk_intersects_rect(cx: int, cy: int, radius_px: int, rect: Rect2i) -> bool:
    var rx_min: int = rect.position.x
    var rx_max: int = rect.position.x + rect.size.x
    var ry_min: int = rect.position.y
    var ry_max: int = rect.position.y + rect.size.y
    var qx: int = clampi(cx, rx_min, rx_max)
    var qy: int = clampi(cy, ry_min, ry_max)
    var dx: int = cx - qx
    var dy: int = cy - qy
    return dx * dx + dy * dy <= radius_px * radius_px
```

- [ ] **Step 6: Run the new test**

```bash
script/checks/gut_tests -f tests/unit/test_hum_system_emission_intersection.gd
```

Expected: 5 passed.

- [ ] **Step 7: Run existing hum_system tests; fix setup that depends on the old shape**

```bash
script/checks/gut_tests -f tests/unit/test_hum_system.gd
```

Existing tests likely set up `hum_receiver: {radius_px: N}`. They need switching to `hum_receiver: {}` plus a `physical: {size_ru: ...}` and adjusted positions. **This is test setup, not product code.** Update each failing test's `before_each` or per-test setup to use the new shape. Where the old test asserted a specific cat-receiver distance behavior (e.g., "nearest receiver wins"), translate the intent to the new model: every receiver whose body rect intersects the cat's disk gets charged. Some "nearest only" assertions may simply not hold in the new model; rewrite them or delete them with the rationale in the commit message.

- [ ] **Step 8: Stamp both test files**

```bash
script/stamp_tests tests/unit/test_hum_system_emission_intersection.gd
script/stamp_tests tests/unit/test_hum_system.gd
```

- [ ] **Step 9: Validate**

```bash
script/validate
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add tests/unit/test_hum_system_emission_intersection.gd \
  tests/unit/test_hum_system_emission_intersection.gd.stamp \
  tests/unit/test_hum_system.gd tests/unit/test_hum_system.gd.stamp \
  engine/core/hum_system.gd mods/tcp_base/objects/hum_device.jsonc \
  engine/mod/entity_def_registry.gd
git commit -m "$(cat <<'EOF'
feat(hum): tick_charge inverts to disk-vs-rect intersection

Cats own emission geometry (purr.radius_px); HUMs are passive bodies whose
receiving area is their body rect (size_ru * SLOT_HEIGHT_PX tall, RACK_WIDTH_PX
wide, anchored at the HUM's slot). Every receiver whose rect intersects a cat's
emission disk is charged by intensity. Multiple HUMs charge from one cat;
receivers no longer compete for "nearest wins."

hum_device.jsonc drops radius_px from hum_receiver - it's a marker tag now.
Existing test setups updated to the new shape.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Real Y for animals (drop the FLOOR_Y - 1 hardcode)

**Files:**
- Modify: `nodes/animal_node.gd:32-37, 138-141` (read Y from position component)
- Modify: `CLAUDE.md` ("Known Issues" section: remove the AI-DEV note)

- [ ] **Step 1: Edit animal_node.gd**

Replace the two hardcoded `Constants.FLOOR_Y - 1` callsites:

```gdscript
# In initialize() (around line 31-37): CHANGE
# var pos: Dictionary = _db.get_component(entity_id, &"position")
# _target_pos = Vector2(
#     float(pos[&"x"]),
#     float(Constants.FLOOR_Y - 1)
# )
# TO:
var pos: Dictionary = _db.get_component(entity_id, &"position")
_target_pos = Vector2(float(pos[&"x"]), float(pos[&"y"]))

# In _physics_process() (around line 138-141): CHANGE
# _target_pos = Vector2(
#     float(pos[&"x"]),
#     float(Constants.FLOOR_Y - 1)
# )
# TO:
_target_pos = Vector2(float(pos[&"x"]), float(pos[&"y"]))
```

- [ ] **Step 2: Update CLAUDE.md**

In the "Known Issues (Ring 0)" section, remove the line that says **Animals hardcode Y to FLOOR_Y - 1** - it is no longer true.

- [ ] **Step 3: Run validation**

```bash
script/validate
```

Expected: PASS. Existing animals' Y is set on spawn by entity_def_registry/world_init_system; with this change the rendered Y matches the stored Y. If any existing scenario placed an animal off-floor accidentally, that's a separate scenario bug - investigate before "fixing" by re-snapping.

- [ ] **Step 4: Boot the game and visually confirm**

```bash
/Applications/Godot.app/Contents/MacOS/godot --path .
```

Expected: cats walk along the floor as before (their position.y is FLOOR_Y - 1 from existing scenarios). No visual regression.

- [ ] **Step 5: Commit**

```bash
git add nodes/animal_node.gd CLAUDE.md
git commit -m "$(cat <<'EOF'
fix(render): animals render Y from position component, not hardcoded floor

Drops the FLOOR_Y - 1 snap in animal_node.gd. Position component is now the
source of truth. Unblocks cats inside boxes (y=96), cats on shelves, cats
sleeping atop other cats. Known-issue note removed from CLAUDE.md.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: ObjectStateManager supports {ads, join} state shape

**Files:**
- Modify: `engine/objects/object_state_manager.gd:7-43` (OBJECT_CONFIG structure: each state is now `{ads: [...], join: {...}}` instead of bare `[...]`)
- Modify: `engine/objects/object_state_manager.gd:114-123` (`get_ads_for_state` reads from `state[ads]`; add `get_join_for_state`)
- Modify: `engine/objects/object_state_manager.gd:54-69` (`transition_state` looks up the new shape)

This task updates the structure but keeps the cardboard_box's existing comfort/curiosity ads. The `join` block for cardboard_box arrives in Task 6.

- [ ] **Step 1: Read existing tests for OSM**

```bash
ls tests/unit/test_object_state_manager*.gd 2>/dev/null
ls tests/unit/test_obj* 2>/dev/null
```

Note any existing OSM tests; their setup needs updating after the schema migration.

- [ ] **Step 2: Migrate OBJECT_CONFIG in object_state_manager.gd**

Replace the OBJECT_CONFIG dictionary (engine/objects/object_state_manager.gd:7-43) with:

```gdscript
const OBJECT_CONFIG: Dictionary = {
    &"tuna_can": {
        &"state_ads": {
            &"sealed": {
                &"ads": [{
                    &"desire_type": &"openable", &"strength": 800,
                    &"radius_px": 24, &"action": &"open",
                }],
            },
            &"open": {
                &"ads": [{
                    &"desire_type": &"food", &"strength": 800,
                    &"radius_px": 40, &"action": &"eat",
                }],
            },
            &"empty": {&"ads": []},
        },
    },
    &"cardboard_box": {
        &"state_ads": {
            &"new": {
                &"ads": [
                    {&"desire_type": &"comfort", &"strength": 700, &"radius_px": 32},
                    {&"desire_type": &"curiosity", &"strength": 500,
                        &"radius_px": 40, &"action": &"shred"},
                ],
            },
            &"worn": {
                &"ads": [
                    {&"desire_type": &"comfort", &"strength": 400, &"radius_px": 24},
                    {&"desire_type": &"curiosity", &"strength": 300,
                        &"radius_px": 32, &"action": &"shred"},
                ],
            },
            &"scraps": {
                &"ads": [
                    {&"desire_type": &"comfort", &"strength": 600, &"radius_px": 24},
                ],
            },
        },
        &"hp_thresholds": [
            {&"min_hp": 501, &"state": &"new"},
            {&"min_hp": 1, &"state": &"worn"},
            {&"min_hp": 0, &"state": &"scraps"},
        ],
    },
}
```

- [ ] **Step 3: Update get_ads_for_state and add get_join_for_state**

Replace the bottom of the file:

```gdscript
# Generic state -> ads lookup. Returns the ad list for the given state,
# or an empty array if the object type or state is unknown.
func get_ads_for_state(object_type: StringName, state: StringName) -> Array:
    if not OBJECT_CONFIG.has(object_type):
        return []
    var cfg: Dictionary = OBJECT_CONFIG[object_type]
    if not cfg.has(&"state_ads"):
        return []
    var state_ads: Dictionary = cfg[&"state_ads"]
    if not state_ads.has(state):
        return []
    var entry = state_ads[state]
    # Backward-compat: if entry is still a bare Array, treat it as ads.
    if entry is Array:
        return entry
    return (entry as Dictionary).get(&"ads", [])


# Returns the join block for the given state, or empty Dictionary if absent.
func get_join_for_state(object_type: StringName, state: StringName) -> Dictionary:
    if not OBJECT_CONFIG.has(object_type):
        return {}
    var cfg: Dictionary = OBJECT_CONFIG[object_type]
    if not cfg.has(&"state_ads"):
        return {}
    var state_ads: Dictionary = cfg[&"state_ads"]
    if not state_ads.has(state):
        return {}
    var entry = state_ads[state]
    if entry is Array:
        return {}  # legacy shape, no join
    return (entry as Dictionary).get(&"join", {})
```

`transition_state` needs no changes - it calls `get_ads_for_state`, which now returns the same Array shape it used to.

- [ ] **Step 4: Run validation**

```bash
script/validate
```

Expected: PASS. The migration is purely structural; existing ad behavior is unchanged.

- [ ] **Step 5: Commit**

```bash
git add engine/objects/object_state_manager.gd
git commit -m "$(cat <<'EOF'
refactor(osm): state_ads structure is {ads, join} per state

Aligns with the resting-on spec's state_advertisements shape: each state has an
`ads` array and an optional `join` block describing the spatial contract for
animals that arrive there. Behavior unchanged in this task - tuna_can and
cardboard_box now use the new shape with no join blocks yet. New helper
get_join_for_state() returns the join dict (empty when absent).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Add `contained` join to cardboard_box

**Files:**
- Modify: `engine/objects/object_state_manager.gd:21-42` (cardboard_box `new` and `worn` states get `join` blocks; `scraps` gets no join)

- [ ] **Step 1: Add join block to cardboard_box `new` state**

In `OBJECT_CONFIG[&"cardboard_box"][&"state_ads"][&"new"]`, add a `join` key alongside the existing `ads`:

```gdscript
&"new": {
    &"ads": [
        {&"desire_type": &"comfort", &"strength": 700, &"radius_px": 32},
        {&"desire_type": &"curiosity", &"strength": 500,
            &"radius_px": 40, &"action": &"shred"},
    ],
    &"join": {
        &"type": &"contained",
        &"direction": &"any",
        &"capacity": 5,
        &"entry_origin_offset":    Vector2i(0, -16),
        &"interior_origin_offset": Vector2i(0, -8),
        &"entry_threshold_ru": 1,
        &"inner_size_ru": 2,
    },
},
```

- [ ] **Step 2: Add same join block to `worn` state**

Same structure. (Worn boxes still hold a cat - the threshold and capacity stay the same; only the ad strength differs.)

- [ ] **Step 3: Leave `scraps` without a join block**

A box destroyed past `scraps` cannot accept occupants. The absence of `join` (`get_join_for_state` returns `{}`) means the navgraph's ENTER scanner won't emit edges for it; it also triggers the safety-check dissolution for any current occupant when a box transitions into scraps.

- [ ] **Step 4: Validate**

```bash
script/validate
```

Expected: PASS (no new tests yet; structural addition).

- [ ] **Step 5: Commit**

```bash
git add engine/objects/object_state_manager.gd
git commit -m "$(cat <<'EOF'
feat(objects): cardboard_box advertises contained join in new + worn

`new` and `worn` states gain a join block with type=contained, capacity=5
(weight-units, fits 1 cat at join_weight=5 or 5 kittens at join_weight=1),
inner_size_ru=2, entry_threshold_ru=1. The scraps state has no join - a
destroyed box cannot accept occupants.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Add ENTER edge type and parametric body_capabilities to NavGraphBuilder

**Files:**
- Modify: `engine/navigation/species_astar.gd` (add `ENTER` constant)
- Modify: `engine/navigation/nav_graph_builder.gd` (rework `register_species` signature; replace `Array` capabilities with `Dictionary` body_capabilities; add helper for capability lookup)
- Modify: `nodes/game_server.gd` (caller of `register_species` - pass the new dict)

- [ ] **Step 1: Add ENTER edge type**

In `engine/navigation/species_astar.gd`, add `const ENTER: StringName = &"ENTER"` alongside the existing edge type constants (`WALK`, `JUMP_UP`, `JUMP_DOWN`).

- [ ] **Step 2: Update NavGraphBuilder register_species signature**

Change from:

```gdscript
func register_species(species_id: StringName, capabilities: Array) -> void:
    _capabilities[species_id] = capabilities
    if not _astars.has(species_id):
        _astars[species_id] = AStar2D.new()
```

To accept the parametric body_capabilities dict:

```gdscript
# body_capabilities is the dict from species recipe:
# { "walks": {}, "jumps": {"max_height_ru": 3}, ... }
# body_geometry is { "size_ru": 2 } from the species recipe.
func register_species(species_id: StringName, body_capabilities: Dictionary, body_geometry: Dictionary) -> void:
    _body_capabilities[species_id] = body_capabilities
    _body_geometry[species_id] = body_geometry
    if not _astars.has(species_id):
        _astars[species_id] = AStar2D.new()


func has_capability(species_id: StringName, verb: StringName) -> bool:
    var caps: Dictionary = _body_capabilities.get(species_id, {})
    return caps.has(verb)


func get_capability_param(species_id: StringName, verb: StringName, param: StringName, default_value: int = 0) -> int:
    var caps: Dictionary = _body_capabilities.get(species_id, {})
    var verb_data: Dictionary = caps.get(verb, {})
    return verb_data.get(param, default_value)


func get_body_size_ru(species_id: StringName) -> int:
    return _body_geometry.get(species_id, {}).get(&"size_ru", 0)
```

Replace `_capabilities` declarations with `_body_capabilities: Dictionary = {}` and `_body_geometry: Dictionary = {}`.

- [ ] **Step 3: Update `add_rack_slot` to use the new helpers**

In `add_rack_slot` (line 64-87), replace `SpeciesAStar.JUMP_UP in caps` with `has_capability(species_id, &"jumps")` and `SpeciesAStar.WALK in caps` with `has_capability(species_id, &"walks")`. Also gate the JUMP_UP edge on the height check:

```gdscript
# Inside the species loop in add_rack_slot:
if _floor_nodes.has(rack) and has_capability(species_id, &"jumps"):
    var max_height_ru: int = get_capability_param(species_id, &"jumps", &"max_height_ru")
    var max_height_px: int = max_height_ru * Constants.SLOT_HEIGHT_PX
    var floor_pos: Vector2 = _floor_node_positions[rack]
    var slot_y: float = float(slot_rect.position.y + slot_rect.size.y / 2)
    if int(floor_pos.y) - int(slot_y) <= max_height_px:
        astar.connect_points(_floor_nodes[rack], nav_id)

if has_capability(species_id, &"walks"):
    for ds: int in [-1, 1]:
        var adj_key: String = "%d:%d" % [rack, slot + ds]
        if _slot_nodes.has(adj_key):
            astar.connect_points(nav_id, _slot_nodes[adj_key])
```

- [ ] **Step 4: Update game_server.gd's call to register_species**

Search game_server.gd for `register_species(`. Update each call to pass `body_capabilities` and `body_geometry` from the spawned cat's components rather than the old `traversal` array:

```gdscript
# Before:
# nav_graph_builder.register_species(&"tcp_cats:cat", ["WALK", "JUMP_UP", "JUMP_DOWN"])

# After (resolved at species-registration time, reading from the species recipe):
var caps: Dictionary = species_def.recipe.get("body_capabilities", {})
var geom: Dictionary = species_def.recipe.get("body_geometry", {})
nav_graph_builder.register_species(&"tcp_cats:cat", caps, geom)
```

(Path may differ; the registration is wherever species are introduced to the nav builder. Inspect the actual call site.)

- [ ] **Step 5: Write the failing test**

Create `tests/unit/test_nav_graph_builder_jump_up_edges.gd`:

```gdscript
extends GutTest

# AI-DEV: AI **MUST NOT** touch this test. If the test is failing, it is
# because you removed or broke code.


func _builder_with_species(max_jump_ru: int) -> NavGraphBuilder:
    var b := NavGraphBuilder.new()
    b.register_species(&"test:species",
        {&"walks": {}, &"jumps": {&"max_height_ru": max_jump_ru}},
        {&"size_ru": 2}
    )
    b.build()
    return b


func test_jump_up_edge_emitted_when_within_max_height() -> void:
    # Slot 0 is bottom; slot 1 is one above. Distance: 1 RU = 8 px.
    var b := _builder_with_species(3)
    b.add_rack_slot(0, 1)
    var astar: AStar2D = b.get_astar(&"test:species")
    var floor_pos: Vector2 = b.get_nearest_floor_node(0)
    var slot_pos: Vector2 = b.get_path_points(&"test:species", floor_pos, b.get_path_points(&"test:species", floor_pos, floor_pos)[0])
    # Use can_reach for clarity:
    var slot_rect := Constants.slot_rect_world(0, 0, 1)
    var slot_center := Vector2(float(slot_rect.position.x + slot_rect.size.x / 2),
                               float(slot_rect.position.y + slot_rect.size.y / 2))
    assert_true(b.can_reach(&"test:species", floor_pos, slot_center),
        "1-RU jump should succeed when max_height_ru=3")


func test_jump_up_edge_not_emitted_when_too_tall() -> void:
    var b := _builder_with_species(0)  # zero height = no jumps
    b.add_rack_slot(0, 1)
    var floor_pos: Vector2 = b.get_nearest_floor_node(0)
    var slot_rect := Constants.slot_rect_world(0, 0, 1)
    var slot_center := Vector2(float(slot_rect.position.x + slot_rect.size.x / 2),
                               float(slot_rect.position.y + slot_rect.size.y / 2))
    assert_false(b.can_reach(&"test:species", floor_pos, slot_center),
        "0-RU jump capability cannot reach slot 1")


func test_jumps_capability_absent_means_no_edge() -> void:
    var b := NavGraphBuilder.new()
    b.register_species(&"floorbound", {&"walks": {}}, {&"size_ru": 1})
    b.build()
    b.add_rack_slot(0, 1)
    var floor_pos: Vector2 = b.get_nearest_floor_node(0)
    var slot_rect := Constants.slot_rect_world(0, 0, 1)
    var slot_center := Vector2(float(slot_rect.position.x + slot_rect.size.x / 2),
                               float(slot_rect.position.y + slot_rect.size.y / 2))
    assert_false(b.can_reach(&"floorbound", floor_pos, slot_center))
```

- [ ] **Step 6: Run, fix, run**

```bash
script/checks/gut_tests -f tests/unit/test_nav_graph_builder_jump_up_edges.gd
```

Iterate Step 2-3 wiring until tests pass.

- [ ] **Step 7: Existing nav tests need migration**

Run `script/checks/gut_tests -f tests/unit/test_species_astar.gd` (and any other nav-related tests). Update setup to use the new `register_species(species_id, body_capabilities, body_geometry)` signature.

- [ ] **Step 8: Stamp**

```bash
script/stamp_tests tests/unit/test_nav_graph_builder_jump_up_edges.gd
script/stamp_tests tests/unit/test_species_astar.gd
```

- [ ] **Step 9: Validate**

```bash
script/validate
```

- [ ] **Step 10: Commit**

```bash
git add engine/navigation/species_astar.gd engine/navigation/nav_graph_builder.gd \
  nodes/game_server.gd tests/unit/test_nav_graph_builder_jump_up_edges.gd \
  tests/unit/test_nav_graph_builder_jump_up_edges.gd.stamp \
  tests/unit/test_species_astar.gd tests/unit/test_species_astar.gd.stamp
git commit -m "$(cat <<'EOF'
feat(nav): parametric body_capabilities; ENTER edge type added

NavGraphBuilder.register_species takes a body_capabilities dict (verb -> params)
and body_geometry instead of an Array of capability tags. JUMP_UP edges now
respect the species' max_height_ru; species without `jumps` get no jump edges.
Adds ENTER edge type constant for the box-entry scanner that follows.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: NavGraphBuilder.add_box_enterable() + ENTER scanner

**Files:**
- Modify: `engine/navigation/nav_graph_builder.gd` (add `add_box_enterable(rack, slot, join)`)
- Modify: `nodes/game_server.gd` (call `add_box_enterable` on cardboard_box placement)
- Test: `tests/unit/test_nav_graph_builder_enter_edges.gd` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_nav_graph_builder_enter_edges.gd`:

```gdscript
extends GutTest

# AI-DEV: AI **MUST NOT** touch this test. If the test is failing, it is
# because you removed or broke code.


func _box_join() -> Dictionary:
    return {
        &"type": &"contained",
        &"capacity": 5,
        &"entry_origin_offset": Vector2i(0, -16),
        &"interior_origin_offset": Vector2i(0, -8),
        &"entry_threshold_ru": 1,
        &"inner_size_ru": 2,
    }


func _builder() -> NavGraphBuilder:
    var b := NavGraphBuilder.new()
    b.register_species(&"big_cat",
        {&"walks": {}, &"jumps": {&"max_height_ru": 3},
         &"settles_in_containers": {&"max_body_size_ru": 4}},
        {&"size_ru": 2})
    b.register_species(&"small_kitten",
        {&"walks": {}, &"jumps": {&"max_height_ru": 1},
         &"settles_in_containers": {&"max_body_size_ru": 1}},
        {&"size_ru": 1})
    b.register_species(&"big_dog",
        {&"walks": {}, &"jumps": {&"max_height_ru": 4},
         &"settles_in_containers": {&"max_body_size_ru": 8}},
        {&"size_ru": 4})  # too big to fit inner_size_ru=2
    b.register_species(&"floorbound",
        {&"walks": {}}, {&"size_ru": 2})  # cannot jump
    b.build()
    return b


func _box_interior(rack: int, slot: int) -> Vector2:
    var slot_rect := Constants.slot_rect_world(0, rack, slot)
    var cx: float = float(slot_rect.position.x + slot_rect.size.x / 2)
    var cy: float = float(slot_rect.position.y + slot_rect.size.y / 2)
    return Vector2(cx + 0, cy - 8)  # interior_origin_offset


func test_enter_edge_emitted_when_body_fits_and_can_jump() -> void:
    var b := _builder()
    b.add_rack_slot(0, 0)  # server below
    b.add_box_enterable(0, 1, _box_join())
    var floor_pos: Vector2 = b.get_nearest_floor_node(0)
    var interior: Vector2 = _box_interior(0, 1)
    assert_true(b.can_reach(&"big_cat", floor_pos, interior))


func test_enter_edge_not_emitted_when_body_too_big() -> void:
    var b := _builder()
    b.add_rack_slot(0, 0)
    b.add_box_enterable(0, 1, _box_join())
    var floor_pos: Vector2 = b.get_nearest_floor_node(0)
    var interior: Vector2 = _box_interior(0, 1)
    assert_false(b.can_reach(&"big_dog", floor_pos, interior),
        "dog body_size_ru=4 exceeds inner_size_ru=2; no ENTER edge")


func test_enter_edge_emitted_for_kitten() -> void:
    var b := _builder()
    b.add_rack_slot(0, 0)
    b.add_box_enterable(0, 1, _box_join())
    var floor_pos: Vector2 = b.get_nearest_floor_node(0)
    var interior: Vector2 = _box_interior(0, 1)
    assert_true(b.can_reach(&"small_kitten", floor_pos, interior))


func test_enter_edge_not_emitted_when_cannot_jump_to_entry() -> void:
    var b := _builder()
    b.add_rack_slot(0, 0)
    b.add_box_enterable(0, 1, _box_join())
    var floor_pos: Vector2 = b.get_nearest_floor_node(0)
    var interior: Vector2 = _box_interior(0, 1)
    assert_false(b.can_reach(&"floorbound", floor_pos, interior),
        "floorbound has no jumps capability; cannot reach the box's entry")
```

- [ ] **Step 2: Run test, expect failure**

```bash
script/checks/gut_tests -f tests/unit/test_nav_graph_builder_enter_edges.gd
```

Expected: FAIL ("add_box_enterable not defined" or similar).

- [ ] **Step 3: Implement add_box_enterable in nav_graph_builder.gd**

```gdscript
# Box-side entry. `join` is the contained-type join dict from
# OBJECT_CONFIG[type].state_ads[state].join. Adds two nav nodes:
#   - entry_origin (top-stand, the spot above the box where the cat lands)
#   - interior_origin (where the cat sits inside)
# Connects: floor -> entry via JUMP_UP (if species can jump that height),
#           entry -> interior via ENTER (if body fits and threshold <= max jump).
func add_box_enterable(rack: int, slot: int, join: Dictionary) -> void:
    if join.get(&"type", &"") != &"contained":
        return
    var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
    var box_x: int = slot_rect.position.x + slot_rect.size.x / 2
    var box_y: int = slot_rect.position.y + slot_rect.size.y / 2
    var entry_off: Vector2i = join.get(&"entry_origin_offset", Vector2i.ZERO)
    var inter_off: Vector2i = join.get(&"interior_origin_offset", Vector2i.ZERO)
    var entry_pos := Vector2(float(box_x + entry_off.x), float(box_y + entry_off.y))
    var inter_pos := Vector2(float(box_x + inter_off.x), float(box_y + inter_off.y))

    var entry_id: int = _next_nav_id
    _next_nav_id += 1
    var inter_id: int = _next_nav_id
    _next_nav_id += 1
    var entry_key: String = "box_entry:%d:%d" % [rack, slot]
    var inter_key: String = "box_interior:%d:%d" % [rack, slot]
    _enterable_nodes[entry_key] = entry_id
    _enterable_nodes[inter_key] = inter_id

    var inner_size_ru: int = join.get(&"inner_size_ru", 0)
    var entry_threshold_ru: int = join.get(&"entry_threshold_ru", 0)

    for species_id: StringName in _astars:
        var astar: AStar2D = _astars[species_id]
        astar.add_point(entry_id, entry_pos)
        astar.add_point(inter_id, inter_pos)

        # JUMP_UP from floor to entry, if species can clear the entry threshold.
        if not has_capability(species_id, &"jumps"): continue
        var max_jump_ru: int = get_capability_param(species_id, &"jumps", &"max_height_ru")
        if entry_threshold_ru > max_jump_ru: continue
        # The actual delta from floor to entry node (in pixels):
        if not _floor_nodes.has(rack): continue
        var floor_pos: Vector2 = _floor_node_positions[rack]
        var delta_y: int = int(floor_pos.y) - int(entry_pos.y)
        if delta_y <= max_jump_ru * Constants.SLOT_HEIGHT_PX:
            astar.connect_points(_floor_nodes[rack], entry_id)

        # ENTER from entry to interior, if body fits the inner volume.
        if not has_capability(species_id, &"settles_in_containers"): continue
        var body_size: int = get_body_size_ru(species_id)
        if body_size > inner_size_ru: continue
        astar.connect_points(entry_id, inter_id)


func remove_box_enterable(rack: int, slot: int) -> void:
    var entry_key: String = "box_entry:%d:%d" % [rack, slot]
    var inter_key: String = "box_interior:%d:%d" % [rack, slot]
    for k: String in [entry_key, inter_key]:
        if not _enterable_nodes.has(k):
            continue
        var nav_id: int = _enterable_nodes[k]
        for species_id: StringName in _astars:
            (_astars[species_id] as AStar2D).remove_point(nav_id)
        _enterable_nodes.erase(k)
```

Add `var _enterable_nodes: Dictionary = {}` to the field declarations near the top of the class.

- [ ] **Step 4: Hook game_server.gd to call add_box_enterable**

Find the place where boxes are placed (search for `cardboard_box` or `place_object`). After the box entity is created and added to nav, call:

```gdscript
# Inside the box-placement code path:
var join: Dictionary = object_state_manager.get_join_for_state(&"cardboard_box", state)
if not join.is_empty() and join.get(&"type") == &"contained":
    nav_graph_builder.add_box_enterable(rack, slot, join)
```

For state transitions (e.g., new -> worn -> scraps), wire `transition_state` to refresh the navgraph: when leaving a state with a join and entering one without (or vice versa), call `add_box_enterable`/`remove_box_enterable` as appropriate.

```gdscript
# In ObjectStateManager.transition_state, after the existing ad-update logic:
# Notify nav about join changes. (Inject nav_graph_builder via _init or signal.)
var old_join: Dictionary = get_join_for_state(type_name, old_state)
var new_join: Dictionary = get_join_for_state(type_name, new_state)
if old_join.is_empty() and not new_join.is_empty():
    Events.enterable_join_added.emit(entity_id, new_join)
elif not old_join.is_empty() and new_join.is_empty():
    Events.enterable_join_removed.emit(entity_id)
elif old_join != new_join:
    Events.enterable_join_added.emit(entity_id, new_join)  # rebuild
```

(Add `enterable_join_added` and `enterable_join_removed` signals to `nodes/events.gd`.)

In `game_server.gd`, listen and call the navgraph methods.

- [ ] **Step 5: Run the new test**

```bash
script/checks/gut_tests -f tests/unit/test_nav_graph_builder_enter_edges.gd
```

Iterate until pass.

- [ ] **Step 6: Stamp**

```bash
script/stamp_tests tests/unit/test_nav_graph_builder_enter_edges.gd
```

- [ ] **Step 7: Validate**

```bash
script/validate
```

- [ ] **Step 8: Commit**

```bash
git add engine/navigation/nav_graph_builder.gd nodes/game_server.gd \
  engine/objects/object_state_manager.gd nodes/events.gd \
  tests/unit/test_nav_graph_builder_enter_edges.gd \
  tests/unit/test_nav_graph_builder_enter_edges.gd.stamp
git commit -m "$(cat <<'EOF'
feat(nav): add_box_enterable emits entry+interior nodes and ENTER edges

NavGraphBuilder.add_box_enterable(rack, slot, join) reads the contained-type
join block, creates two nodes (entry_origin and interior_origin), and emits
JUMP_UP + ENTER edges per species based on body_capabilities. Body size > inner
size = no ENTER edge; threshold > max_jump_ru = no JUMP_UP either. Box state
transitions emit enterable_join_added/removed for navgraph refresh.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Position-coupling for `contained` join + relationship lifecycle

**Files:**
- Modify: `nodes/game_server.gd` (add a `_tick_contained_joins()` after `_move_animals()`; add `_dissolve_settled_on_seek()` listening on ai_state changes)
- Test: `tests/unit/test_settled_in_relationship_lifecycle.gd` (new)

This task wires the lifecycle: when an animal traverses the ENTER edge, add the relationship and snap position; when it transitions to SEEKING, dissolve the relationship and snap to entry_origin; when the host's join goes away (state change to scraps), STARTLED + drop.

- [ ] **Step 1: Write the test**

Create `tests/unit/test_settled_in_relationship_lifecycle.gd`:

```gdscript
extends GutTest

# AI-DEV: AI **MUST NOT** touch this test. If the test is failing, it is
# because you removed or broke code.


func _setup_box_and_cat() -> Dictionary:
    var db := GameStateDB.new()
    var box_id: int = db.create_entity()
    db.set_component(box_id, &"object_type", {&"type": &"cardboard_box"})
    db.set_component(box_id, &"object_state", {&"state": &"new"})
    db.set_component(box_id, &"object_hp", {&"hp": 1000})
    db.set_component(box_id, &"position", {&"x": 100, &"y": 100})
    var cat_id: int = db.create_entity()
    db.set_component(cat_id, &"position", {&"x": 200, &"y": 111})
    db.set_component(cat_id, &"species", {&"id": &"tcp_cats:cat"})
    db.set_component(cat_id, &"ai_state", {&"state": &"IDLE", &"commitment_score": 0})
    return {&"db": db, &"box_id": box_id, &"cat_id": cat_id}


func test_enter_adds_sleeping_relationship_and_snaps_position() -> void:
    var s := _setup_box_and_cat()
    var db: GameStateDB = s[&"db"]
    var box_id: int = s[&"box_id"]
    var cat_id: int = s[&"cat_id"]
    # Simulate ENTER edge traversal:
    var lifecycle := SettledLifecycle.new(db)  # see implementation
    lifecycle.enter_container(cat_id, box_id, &"sleeping")
    var hosts: Array[int] = db.get_targets(&"sleeping", cat_id)
    assert_eq(hosts.size(), 1)
    assert_eq(hosts[0], box_id)
    # Position snapped to box.position + interior_origin_offset (Vector2i(0, -8))
    assert_eq(db.get_field(cat_id, &"position", &"x"), 100)
    assert_eq(db.get_field(cat_id, &"position", &"y"), 92)


func test_capacity_gate_blocks_extra_occupants() -> void:
    var s := _setup_box_and_cat()
    var db: GameStateDB = s[&"db"]
    var box_id: int = s[&"box_id"]
    var lifecycle := SettledLifecycle.new(db)
    # Fill capacity (cardboard_box capacity=5; cat join_weight=5 -> 1 cat fills it)
    lifecycle.enter_container(s[&"cat_id"], box_id, &"sleeping")
    var second_cat: int = db.create_entity()
    db.set_component(second_cat, &"position", {&"x": 0, &"y": 0})
    db.set_component(second_cat, &"species", {&"id": &"tcp_cats:cat"})
    db.set_component(second_cat, &"ai_state", {&"state": &"IDLE"})
    var ok: bool = lifecycle.try_enter_container(second_cat, box_id, &"sleeping")
    assert_false(ok, "second cat exceeds capacity")


func test_state_transition_to_seeking_dissolves_relationship() -> void:
    var s := _setup_box_and_cat()
    var db: GameStateDB = s[&"db"]
    var box_id: int = s[&"box_id"]
    var cat_id: int = s[&"cat_id"]
    var lifecycle := SettledLifecycle.new(db)
    lifecycle.enter_container(cat_id, box_id, &"sleeping")
    # AI transitions to SEEKING:
    db.set_field(cat_id, &"ai_state", &"state", &"SEEKING")
    lifecycle.dissolve_on_seek(cat_id)
    assert_eq(db.get_targets(&"sleeping", cat_id).size(), 0)
    # Position snapped to entry_origin_offset (0, -16) above box at (100, 100):
    assert_eq(db.get_field(cat_id, &"position", &"y"), 84)


func test_box_to_scraps_dissolves_occupant_and_startles() -> void:
    var s := _setup_box_and_cat()
    var db: GameStateDB = s[&"db"]
    var box_id: int = s[&"box_id"]
    var cat_id: int = s[&"cat_id"]
    var lifecycle := SettledLifecycle.new(db)
    lifecycle.enter_container(cat_id, box_id, &"sleeping")
    # Box transitions to scraps (no join):
    db.set_field(box_id, &"object_state", &"state", &"scraps")
    lifecycle.host_state_changed(box_id)
    assert_eq(db.get_targets(&"sleeping", cat_id).size(), 0)
    assert_eq(db.get_field(cat_id, &"ai_state", &"state"), &"STARTLED")
```

- [ ] **Step 2: Run, expect failure**

Expected: FAIL ("SettledLifecycle not defined").

- [ ] **Step 3: Create SettledLifecycle helper**

Create `engine/animals/settled_lifecycle.gd`:

```gdscript
class_name SettledLifecycle extends RefCounted

# Adds/removes &"sleeping" (or other state-derived) relationships when animals
# enter/exit `contained` joins. Tracks weight-capacity through a sum over
# all current occupants' join_weight values.

const _CAT_JOIN_WEIGHT: int = 5  # TODO: read from species recipe (Task TBD)
const _CAPACITY_KEY: StringName = &"capacity"

var _db: GameStateDB
var _osm: ObjectStateManager


func _init(db: GameStateDB, osm: ObjectStateManager = null) -> void:
    _db = db
    _osm = osm


func try_enter_container(joiner_id: int, host_id: int, rel_name: StringName) -> bool:
    var join: Dictionary = _join_for(host_id)
    if join.is_empty(): return false
    var capacity: int = join.get(_CAPACITY_KEY, 0)
    var current_weight: int = _occupied_weight(host_id, rel_name)
    var joiner_weight: int = _join_weight_for(joiner_id)
    if current_weight + joiner_weight > capacity: return false
    enter_container(joiner_id, host_id, rel_name)
    return true


func enter_container(joiner_id: int, host_id: int, rel_name: StringName) -> void:
    _db.add_relationship(rel_name, joiner_id, host_id)
    var join: Dictionary = _join_for(host_id)
    var inter_off: Vector2i = join.get(&"interior_origin_offset", Vector2i.ZERO)
    var hx: int = _db.get_field(host_id, &"position", &"x")
    var hy: int = _db.get_field(host_id, &"position", &"y")
    _db.set_field(joiner_id, &"position", &"x", hx + inter_off.x)
    _db.set_field(joiner_id, &"position", &"y", hy + inter_off.y)


func dissolve_on_seek(joiner_id: int) -> void:
    # When an animal transitions to SEEKING, drop any incoming "settled in" rel.
    for rel_name: StringName in [&"sleeping", &"loafing", &"grooming", &"idle"]:
        var hosts: Array[int] = _db.get_targets(rel_name, joiner_id)
        for host_id: int in hosts:
            _db.remove_relationship(rel_name, joiner_id, host_id)
            _snap_to_entry(joiner_id, host_id)


func host_state_changed(host_id: int) -> void:
    # If host's new state has no join, dissolve any incoming relationships and
    # STARTLED the joiners.
    var join: Dictionary = _join_for(host_id)
    if not join.is_empty(): return
    for rel_name: StringName in [&"sleeping", &"loafing", &"grooming", &"idle"]:
        var joiners: Array[int] = _db.get_sources(rel_name, host_id)
        for joiner_id: int in joiners:
            _db.remove_relationship(rel_name, joiner_id, host_id)
            _db.set_field(joiner_id, &"ai_state", &"state", &"STARTLED")


func _join_for(host_id: int) -> Dictionary:
    if not _db.has_component(host_id, &"object_type"):
        return {}
    var type_name: StringName = _db.get_field(host_id, &"object_type", &"type")
    var state: StringName = _db.get_field(host_id, &"object_state", &"state")
    if _osm == null:
        return ObjectStateManager.OBJECT_CONFIG.get(type_name, {}).get(&"state_ads", {}).get(state, {}).get(&"join", {})
    return _osm.get_join_for_state(type_name, state)


func _join_weight_for(joiner_id: int) -> int:
    # Until species recipes carry join_weight explicitly, assume cat = 5.
    # TODO: pipe through species_def.recipe[join_weight].
    return _CAT_JOIN_WEIGHT


func _occupied_weight(host_id: int, rel_name: StringName) -> int:
    var sources: Array[int] = _db.get_sources(rel_name, host_id)
    var w: int = 0
    for joiner_id: int in sources:
        w += _join_weight_for(joiner_id)
    return w


func _snap_to_entry(joiner_id: int, host_id: int) -> void:
    var join: Dictionary = _join_for(host_id)
    if join.is_empty(): return  # host gone or no longer enterable; STARTLED path handles it
    var entry_off: Vector2i = join.get(&"entry_origin_offset", Vector2i.ZERO)
    var hx: int = _db.get_field(host_id, &"position", &"x")
    var hy: int = _db.get_field(host_id, &"position", &"y")
    _db.set_field(joiner_id, &"position", &"x", hx + entry_off.x)
    _db.set_field(joiner_id, &"position", &"y", hy + entry_off.y)
```

- [ ] **Step 4: Hook into game_server tick + state transition events**

In `nodes/game_server.gd`:

```gdscript
# In _ready() or similar setup:
_settled_lifecycle = SettledLifecycle.new(_db, _object_state_manager)
Events.enterable_join_removed.connect(_settled_lifecycle.host_state_changed)

# In _physics_process, after the main movement loop:
_tick_settled_dissolution()  # checks SEEKING transitions

# Helper:
func _tick_settled_dissolution() -> void:
    # Naive: walk all entities with ai_state and dissolve any settled relationship
    # if their new state is SEEKING. Could be optimized via the dirty-changed query.
    var changed: Array[int] = _db.get_changed_entities(&"ai_state", _last_dissolution_tick)
    _last_dissolution_tick = _db.get_tick()
    for eid: int in changed:
        var state: StringName = _db.get_field(eid, &"ai_state", &"state")
        if state == &"SEEKING":
            _settled_lifecycle.dissolve_on_seek(eid)
```

Add the `_tick_contained_joins()` pass for position coupling - keep occupants snapped to host position each tick if the host moves (it doesn't move for boxes, but the pattern matches Resting-On's `stack` join):

```gdscript
func _tick_contained_joins() -> void:
    for rel_name: StringName in [&"sleeping", &"loafing", &"grooming", &"idle"]:
        # Iterate every host of this relationship; for each, sync occupants' position.
        # (At prototype scale, a flat scan is fine.)
        # Implementation: GameStateDB doesn't expose "all hosts of rel" directly,
        # so iterate joiners and look up their host.
        for joiner_id: int in _db.get_entities_with(&"position"):
            var hosts: Array[int] = _db.get_targets(rel_name, joiner_id)
            if hosts.is_empty(): continue
            var host_id: int = hosts[0]
            if not _db.has_entity(host_id):
                _settled_lifecycle.host_state_changed(host_id)  # cleanup
                continue
            var join: Dictionary = _settled_lifecycle._join_for(host_id)
            if join.is_empty():
                _settled_lifecycle.host_state_changed(host_id)
                continue
            var inter_off: Vector2i = join.get(&"interior_origin_offset", Vector2i.ZERO)
            var hx: int = _db.get_field(host_id, &"position", &"x")
            var hy: int = _db.get_field(host_id, &"position", &"y")
            _db.set_field(joiner_id, &"position", &"x", hx + inter_off.x)
            _db.set_field(joiner_id, &"position", &"y", hy + inter_off.y)
```

Call `_tick_contained_joins()` after `_move_animals()` in `_physics_process`.

- [ ] **Step 5: Run, fix, run**

```bash
script/checks/gut_tests -f tests/unit/test_settled_in_relationship_lifecycle.gd
```

- [ ] **Step 6: Stamp**

```bash
script/stamp_tests tests/unit/test_settled_in_relationship_lifecycle.gd
```

- [ ] **Step 7: Validate**

```bash
script/validate
```

- [ ] **Step 8: Commit**

```bash
git add engine/animals/settled_lifecycle.gd nodes/game_server.gd \
  tests/unit/test_settled_in_relationship_lifecycle.gd \
  tests/unit/test_settled_in_relationship_lifecycle.gd.stamp
git commit -m "$(cat <<'EOF'
feat(animals): contained-join lifecycle (enter/dissolve/scraps cascade)

SettledLifecycle adds/removes the &\"sleeping\" relationship when animals
enter/exit a contained-type join. Capacity gated on weight; SEEKING state
transition dissolves; host transitioning to scraps STARTLES occupants.
game_server runs a position-coupling pass each tick after _move_animals.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: WorldInitSystem supports settled_in_ref

**Files:**
- Modify: `engine/core/world_init_system.gd:24-68` (add a fourth pass: resolve `settled_in_ref` after refs are known; call `SettledLifecycle.enter_container`)
- Modify: `engine/mod/scenario_schema_validator.gd` (allow `settled_in_ref` and `ai_state` fields on entries)

- [ ] **Step 1: Read scenario_schema_validator.gd to find the field allowlist**

```bash
grep -n "settled_in_ref\|ai_state\|cable_to\|ref_name" engine/mod/scenario_schema_validator.gd
```

- [ ] **Step 2: Update validator**

Whitelist the new optional fields in the schema. Search for the existing per-entry field check; add `settled_in_ref` and `ai_state` to the allowed set.

- [ ] **Step 3: Add fourth pass to apply()**

In `engine/core/world_init_system.gd:24-68`, alongside the existing `pending_cables` pass, add a parallel `pending_settled_in` pass:

```gdscript
# In the spawn loop (the second pass), capture settled_in_ref:
if entry.has("settled_in_ref"):
    pending_settled_in.append({
        &"joiner_id": entity_id,
        &"ref_name": StringName(entry["settled_in_ref"]),
    })
# Optional ai_state seed:
if entry.has("ai_state"):
    _db.set_component(entity_id, &"ai_state",
        {&"state": StringName(entry["ai_state"]), &"commitment_score": 0})

# After cable_to resolution, add a fourth pass for settled_in_ref:
var lifecycle := SettledLifecycle.new(_db)  # or pull from a shared instance
for s: Dictionary in pending_settled_in:
    var joiner_id: int = s[&"joiner_id"]
    var ref_name: StringName = s[&"ref_name"]
    if not refs.has(ref_name):
        push_error("world_init: settled_in_ref.ref_name not found: %s" % ref_name)
        continue
    var host_id: int = refs[ref_name]
    var ok: bool = lifecycle.try_enter_container(joiner_id, host_id, &"sleeping")
    if not ok:
        push_error("world_init: settled_in failed for joiner=%d host=%d" % [joiner_id, host_id])
```

(Inject `SettledLifecycle` via `_init` if test ergonomics require.)

- [ ] **Step 4: Validate**

```bash
script/validate
```

(No new test for this task; the integration test in Task 14 exercises it.)

- [ ] **Step 5: Commit**

```bash
git add engine/core/world_init_system.gd engine/mod/scenario_schema_validator.gd
git commit -m "$(cat <<'EOF'
feat(scenarios): settled_in_ref + ai_state seed for pre-occupied scenarios

Scenario entries can now declare `settled_in_ref: \"box_0\"` to start the entity
inside a previously-spawned host's contained join, and `ai_state: \"SLEEPING\"`
to seed the initial state. WorldInitSystem resolves refs in a fourth pass,
calling SettledLifecycle.try_enter_container.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Update starter scenario to demo layout

**Files:**
- Modify: `mods/tcp_base/scenarios/starter.jsonc` (rewrite for the demo)

- [ ] **Step 1: Replace starter.jsonc**

```jsonc
{
    "schema_version": 2,
    "id": "tcp_base:starter",
    "entities": [
        // Rack 0: server + box (Cat A pre-settled inside)
        { "type": "tcp_base:server_1u",  "rack": 0, "slot": 0, "ref_name": "server_0" },
        { "type": "tcp_base:cardboard_box", "rack": 0, "slot": 1, "ref_name": "box_0" },

        // Rack 1: server + box + HUM, Cat B starts on the floor near rack 1
        { "type": "tcp_base:server_1u",  "rack": 1, "slot": 0, "ref_name": "server_1" },
        { "type": "tcp_base:cardboard_box", "rack": 1, "slot": 1, "ref_name": "box_1" },
        { "type": "tcp_base:hum_device",   "rack": 1, "slot": 9, "ref_name": "hum_a" },

        // Existing food chain (kept; cabled to the single HUM)
        {
            "type": "tcp_base:tuna_dispenser",
            "rack": 2, "slot": 8,
            "ref_name": "tuna_a",
            "cable_to": { "ref_name": "hum_a" }
        },
        {
            "type": "tcp_base:tuna_button",
            "rack": 2, "slot": 7,
            "dispenser_ref": { "rack": 2, "slot": 8 }
        },
        {
            "type": "tcp_base:arm",
            "floor_rack": 0, "floor_slot_offset": 0,
            "cable_to": { "ref_name": "hum_a" }
        },

        // Cat A: pre-settled inside box_0 (loop demo, immediate purr)
        {
            "type": "tcp_cats:cat",
            "rack": 0, "slot": 1,
            "ref_name": "cat_a",
            "settled_in_ref": "box_0",
            "ai_state": "SLEEPING",
            "required": false
        },

        // Cat B: floor-spawned near rack 1 (emergent demo - finds box_1 by desire)
        {
            "type": "tcp_cats:cat",
            "floor_rack": 1, "floor_slot_offset": 0,
            "ref_name": "cat_b",
            "ai_state": "IDLE",
            "required": false
        }
    ]
}
```

- [ ] **Step 2: Boot and observe**

```bash
/Applications/Godot.app/Contents/MacOS/godot --path .
```

Expected: Cat A is rendered inside box_0 (slot 1, rack 0) with the "tucked in" z-order making the box's lip occlude the cat's lower body. Cat B starts on the floor near rack 1, soon scores box_1's comfort ad, walks over, jumps up, and enters. Both cats purr; HUM bar fills (Cat B charges directly; Cat A charges if its happy-cat radius reaches across the rack gap).

(If purr_ring effects are missing, that's Task 13. If z-order is wrong, that's Task 12. Note any visible regression but don't try to fix it here.)

- [ ] **Step 3: Validate**

```bash
script/validate
```

- [ ] **Step 4: Commit**

```bash
git add mods/tcp_base/scenarios/starter.jsonc
git commit -m "$(cat <<'EOF'
feat(scenarios): starter.jsonc shows two server+box stacks + one HUM

Rack 0: server + box (Cat A pre-settled inside, sleeping). Rack 1: server +
box + HUM (Cat B starts on the floor, walks to box_1 by desire). Demo of the
inversion: cat in box charges HUM via cat-owned emission radius. Cross-rack
reach (Cat A -> rack-1 HUM) gated on contentment-driven radius.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: edge_animations + z-order for settled_in

**Files:**
- Modify: `mods/tcp_cats/species/cat.jsonc` (add `edge_animations` map + animation_frames entries for jump, fall, ledgeclimb)
- Modify: `nodes/animal_node.gd` (read `edge_animations`; play matching strip during MOVING_TO; z-order rule for settled_in relationship)

- [ ] **Step 1: Update cat.jsonc**

Add the `edge_animations` block alongside the existing `animations` block in `sprite_config`. Also add the new strips to `animation_frames`:

```jsonc
"sprite_config": {
    "base_path": "res://mods/tcp_cats/sprites/{variant}",
    "offset_y": -12,
    "animations": {
        // existing entries unchanged
    },
    "edge_animations": {
        "WALK":      { "animation": "walk" },
        "JUMP_UP":   { "animation": "jump" },
        "JUMP_DOWN": { "animation": "fall" },
        "ENTER":     { "animation": "ledgeclimb" }
    },
    "animation_frames": {
        // existing entries...
        "jump":       { "sprite": "_jump_strip4.png",       "frames": 4,  "fps": 8.0 },
        "fall":       { "sprite": "_fall_strip3.png",       "frames": 3,  "fps": 6.0 },
        "ledgeclimb": { "sprite": "_ledgeclimb_strip11.png","frames": 11, "fps": 8.0 },
        "land":       { "sprite": "_land_strip2.png",       "frames": 2,  "fps": 6.0 }
    }
}
```

- [ ] **Step 2: Update animal_node.gd**

Add edge-animation playback. Around line 44 (`_cache_state_animations`), expand to also cache edge animations:

```gdscript
var _state_animations: Dictionary = {}
var _edge_animations: Dictionary = {}


func _cache_state_animations() -> void:
    var config: Dictionary = _db.get_component(entity_id, &"sprite_config")
    _state_animations = config.get("animations", {})
    _edge_animations = config.get("edge_animations", {})
```

In `_physics_process`, before the existing state-based animation block, add:

```gdscript
# Edge animation has priority during MOVING_TO if the entity is currently
# traversing a typed edge. The agent writes the edge type into ai_state.current_edge.
if _db.has_component(entity_id, &"ai_state"):
    var ai: Dictionary = _db.get_component(entity_id, &"ai_state")
    var state: StringName = ai[&"state"]
    if state == &"MOVING_TO":
        var edge: StringName = ai.get(&"current_edge", &"WALK")
        var edge_anim: StringName = _edge_to_animation(edge)
        if _sprite.sprite_frames and _sprite.sprite_frames.has_animation(edge_anim):
            if _sprite.animation != edge_anim:
                _sprite.play(edge_anim)
        return  # skip state-based animation when an edge animation is active

# (Existing state-based animation block follows.)
```

Add helper:

```gdscript
func _edge_to_animation(edge: StringName) -> StringName:
    var entry: Dictionary = _edge_animations.get(String(edge), {})
    return StringName(entry.get("animation", "walk"))
```

For `current_edge` to be populated, the movement system needs to write it. Find where `_move_animals` advances animals along the path; add:

```gdscript
# game_server.gd or movement_system.gd, when moving along a path:
# Determine the edge type for the segment from current_pos to next_waypoint.
# Simplest hook: store the edge type alongside the path. NavGraphBuilder doesn't
# return edge types per segment today; add a helper that classifies:
#   delta_y < 0 with magnitude > SLOT_HEIGHT_PX -> JUMP_UP
#   delta_y > 0 with magnitude > SLOT_HEIGHT_PX -> JUMP_DOWN
#   delta_y == 0 -> WALK
#   Special: previous waypoint was an enterable-entry, next is enterable-interior -> ENTER
```

Implement that classifier in `nav_graph_builder.gd` or a new helper, and write the result to `ai_state.current_edge` each tick.

- [ ] **Step 3: Add z-order rule for settled_in**

In `animal_node.gd`, around line 190 (the existing `z_index = 200 + int(global_position.y / 2.0)`):

```gdscript
func _process(_delta: float) -> void:
    var t: float = Engine.get_physics_interpolation_fraction()
    global_position = _prev_pos.lerp(_target_pos, t)
    var base_z: int = 200 + int(global_position.y / 2.0)
    z_index = base_z + _settled_z_offset()


func _settled_z_offset() -> int:
    if _db == null or not _db.has_entity(entity_id): return 0
    # If we're settled_in (any relationship to an enterable host), sit BEHIND
    # the host (z-1). settled_on (future) would be z+1.
    for rel_name: StringName in [&"sleeping", &"loafing", &"grooming", &"idle"]:
        var hosts: Array[int] = _db.get_targets(rel_name, entity_id)
        if hosts.is_empty(): continue
        # We're inside something. The host's z is base_z based on its y; we offset -1.
        return -1
    return 0
```

(The z_index drives draw order; nudging by -1 sets the cat one layer below the box visually.)

- [ ] **Step 4: Validate**

```bash
script/validate
```

- [ ] **Step 5: Boot and visually confirm**

```bash
/Applications/Godot.app/Contents/MacOS/godot --path .
```

Expected: Cat A renders behind the box in slot 1 (lip occludes lower body, ears poke out). Cat B walks over, jumps up (jump animation plays), drops in (ledgeclimb animation plays), settles, and renders behind box_1.

- [ ] **Step 6: Commit**

```bash
git add mods/tcp_cats/species/cat.jsonc nodes/animal_node.gd \
  engine/navigation/nav_graph_builder.gd nodes/game_server.gd
git commit -m "$(cat <<'EOF'
feat(animation): edge_animations + settled_in z-order tuck-in

cat.jsonc declares edge_animations (WALK/JUMP_UP/JUMP_DOWN/ENTER -> strip).
animal_node plays the edge clip during MOVING_TO; falls back to state-based
otherwise. z-order rule: settled_in -> z = base - 1, so the box's lip occludes
the cat's lower body and only ears poke out.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: purr_ring.gd VFX

**Files:**
- Create: `nodes/effects/purr_ring.gd`
- Create: `nodes/effects/purr_ring.tscn`
- Modify: `nodes/animal_node.gd` (instantiate the ring as a child; bind to entity's purr component)

- [ ] **Step 1: Create purr_ring.tscn (a Node2D scene with a single Sprite2D for now)**

Open Godot editor, create `nodes/effects/purr_ring.tscn`:
- Root: Node2D
- Child: nothing - the script does the drawing via `_draw()`.

- [ ] **Step 2: Create purr_ring.gd**

```gdscript
extends Node2D

# Renders pixel-note glyphs orbiting at purr.radius_px around the parent's
# global position. Density scales with intensity. Pure visual; reads the cat's
# purr component each frame (display rate; not _physics_process).

const NOTE_COUNT_MAX: int = 12

var entity_id: int = Constants.INVALID_ID
var _db: GameStateDB
var _phase: float = 0.0


func bind(db: GameStateDB, eid: int) -> void:
    _db = db
    entity_id = eid


func _process(delta: float) -> void:
    _phase += delta * 2.0  # rotate at ~2 rad/sec
    queue_redraw()


func _draw() -> void:
    if _db == null or not _db.has_entity(entity_id): return
    if not _db.has_component(entity_id, &"purr"): return
    var intensity: int = _db.get_field(entity_id, &"purr", &"intensity")
    var radius_px: int = _db.get_field(entity_id, &"purr", &"radius_px")
    if intensity <= 0 or radius_px <= 0: return

    var note_count: int = clampi(intensity * NOTE_COUNT_MAX / Constants.UNIT, 1, NOTE_COUNT_MAX)
    var color := Color(1.0, 1.0, 0.6, float(intensity) / float(Constants.UNIT))
    for i: int in note_count:
        var angle: float = _phase + (TAU * i / float(note_count))
        var px: float = cos(angle) * float(radius_px)
        var py: float = sin(angle) * float(radius_px)
        # Tiny pixel "note" - 1x2 vertical stem + 2x1 head
        draw_rect(Rect2(px, py, 1, 2), color)
        draw_rect(Rect2(px + 1, py, 2, 1), color)
```

- [ ] **Step 3: Instantiate inside animal_node.gd**

In `_ready()` or `initialize()`:

```gdscript
@onready var _purr_ring: Node2D = preload("res://nodes/effects/purr_ring.tscn").instantiate()


func initialize(db: GameStateDB, eid: int) -> void:
    # ... existing code ...
    add_child(_purr_ring)
    _purr_ring.bind(db, eid)
```

- [ ] **Step 4: Validate**

```bash
script/validate
```

- [ ] **Step 5: Boot, observe**

```bash
/Applications/Godot.app/Contents/MacOS/godot --path .
```

Expected: when a cat is purring, you see a faint ring of pixel notes around it; ring expands as the cat reaches full intensity. Ring vanishes when intensity = 0.

- [ ] **Step 6: Commit**

```bash
git add nodes/effects/purr_ring.gd nodes/effects/purr_ring.tscn nodes/animal_node.gd
git commit -m "$(cat <<'EOF'
feat(vfx): purr_ring renders pixel-note halo at purr.radius_px

A Node2D child of each animal renders a ring of pixel-note glyphs orbiting at
the cat's purr.radius_px, density and alpha scaling with intensity. Pure
visual; reads GameStateDB at display rate. Ring vanishes when intensity=0.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: Integration test - full loop

**Files:**
- Test: `tests/integration/test_cat_into_box_charges_hum.gd` (new)

- [ ] **Step 1: Write the test**

```gdscript
extends GutTest

# AI-DEV: AI **MUST NOT** touch this test. If the test is failing, it is
# because you removed or broke code.

# Apply the starter scenario, run the simulation for N ticks, and assert that:
#  (a) Cat B has a `sleeping` relationship to box_1 by the end.
#  (b) HUM-1's reserve has increased by at least K above its starting value.
# This spans desire scoring, A*, traversal, settle, purr, and charge.


func test_cat_b_finds_box_and_charges_hum() -> void:
    var server := GameServer.new()
    server.bootstrap_test_world(&"tcp_base:starter")
    var db: GameStateDB = server.db
    # Resolve cat_b and hum_a by ref (assumes WorldInitSystem stores ref_name -> id):
    var cat_b: int = server.get_ref(&"cat_b")
    var box_1: int = server.get_ref(&"box_1")
    var hum_id: int = server.get_ref(&"hum_a")
    var initial_reserve: int = db.get_field(hum_id, &"hum", &"reserve")

    # Run for 200 ticks (~20 seconds at 10 Hz)
    for i: int in 200:
        server.tick()

    var hosts: Array[int] = db.get_targets(&"sleeping", cat_b)
    assert_true(hosts.size() > 0, "Cat B should have settled into a host within 200 ticks")
    assert_true(box_1 in hosts, "Cat B's host should be box_1")
    var final_reserve: int = db.get_field(hum_id, &"hum", &"reserve")
    assert_gt(final_reserve, initial_reserve + 100,
        "HUM-1 reserve should have grown from purring contribution")
```

(`bootstrap_test_world` and `get_ref` may need adding to GameServer as test affordances. If they don't exist yet, add them - they're test-only and harmless.)

- [ ] **Step 2: Run, fix flaky issues**

```bash
script/checks/gut_tests -f tests/integration/test_cat_into_box_charges_hum.gd
```

If it fails, diagnose: did Cat B reach the box? (check `_db.get_field(cat_b, &"position", &"x")` over time). Did the HUM see Cat B's purr radius? (check intensity + radius_px values). Tune `200` ticks if needed but flag in commit if more time is needed than expected.

- [ ] **Step 3: Stamp**

```bash
script/stamp_tests tests/integration/test_cat_into_box_charges_hum.gd
```

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_cat_into_box_charges_hum.gd \
  tests/integration/test_cat_into_box_charges_hum.gd.stamp
git commit -m "$(cat <<'EOF'
test(integration): cat finds box, settles, purrs, charges HUM

End-to-end scenario test. Spans desire scoring, A*, traversal, settle, purr,
charge. Asserts Cat B has a sleeping relationship to box_1 within 200 ticks
and HUM-1's reserve has grown.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: Soak invariant

**Files:**
- Test: `tests/simulation/test_no_orphaned_settled_relationships.gd` (new)

- [ ] **Step 1: Write the soak test**

```gdscript
extends GutTest

# AI-DEV: AI **MUST NOT** touch this test. If the test is failing, it is
# because you removed or broke code.

# Run 10,000 ticks of the starter scenario; assert two invariants are never
# violated:
#  (1) Every &"sleeping" relationship's host entity exists.
#  (2) Each host's occupancy weight never exceeds its capacity.


func test_no_orphans_or_overcap() -> void:
    var server := GameServer.new()
    server.bootstrap_test_world(&"tcp_base:starter")
    var db: GameStateDB = server.db
    var box_1: int = server.get_ref(&"box_1")
    var capacity: int = 5  # cardboard_box capacity in OBJECT_CONFIG

    for tick: int in 10000:
        server.tick()
        # Invariant 1: no orphan hosts
        for joiner_id: int in db.get_entities_with(&"position"):
            var hosts: Array[int] = db.get_targets(&"sleeping", joiner_id)
            for host_id: int in hosts:
                assert_true(db.has_entity(host_id),
                    "Tick %d: orphan settled_in relationship: joiner=%d -> dead host=%d" % [tick, joiner_id, host_id])
        # Invariant 2: capacity not exceeded (5 weight max; cat=5)
        var sources: Array[int] = db.get_sources(&"sleeping", box_1)
        var weight: int = sources.size() * 5
        assert_lte(weight, capacity,
            "Tick %d: box_1 over capacity: %d weight" % [tick, weight])
```

- [ ] **Step 2: Run**

```bash
script/checks/gut_tests -f tests/simulation/test_no_orphaned_settled_relationships.gd
```

This will be slow - it's a soak test. Expected: PASS in <30 seconds.

- [ ] **Step 3: Stamp**

```bash
script/stamp_tests tests/simulation/test_no_orphaned_settled_relationships.gd
```

- [ ] **Step 4: Final validation**

```bash
script/validate
```

- [ ] **Step 5: Commit**

```bash
git add tests/simulation/test_no_orphaned_settled_relationships.gd \
  tests/simulation/test_no_orphaned_settled_relationships.gd.stamp
git commit -m "$(cat <<'EOF'
test(soak): settled_in relationships never orphan or exceed capacity

10,000-tick run of the starter scenario asserts two invariants: (1) every
sleeping relationship points to a live host, (2) box_1 occupancy weight
never exceeds capacity.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 16: Asset tracker note + final clean-up

**Files:**
- Modify: `docs/art-asset-tracker.md` (mark jump/land/ledgeclimb as wired)

- [ ] **Step 1: Update tracker**

```bash
grep -n "jump_strip4\|land_strip2\|ledgeclimb_strip11" docs/art-asset-tracker.md
```

For each entry, change the status from "orphaned" / "unwired" to "wired (cat-into-box plan, 2026-04-26)".

- [ ] **Step 2: Validate full project once more**

```bash
script/validate
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add docs/art-asset-tracker.md
git commit -m "$(cat <<'EOF'
docs(art): mark jump/land/ledgeclimb cat strips as wired

Wired through cat.jsonc edge_animations as part of the cat-jumps-into-box plan.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**1. Spec coverage:** Each numbered section in the spec maps to tasks:
- Spec 1 (body_capabilities/geometry) -> Task 1
- Spec 2 (per-species navgraph) -> Tasks 7, 8
- Spec 3 (real Y) -> Task 4
- Spec 4 (contained join) -> Tasks 5, 6
- Spec 5 (cat-owned purr emission) -> Tasks 2, 3
- Spec 6 (animation + render) -> Tasks 12, 13
- Spec end-to-end loop -> Task 11 (scenario), Task 14 (integration test)
- Spec leaving the box -> Task 9 (lifecycle)
- Spec pre-existing relationships -> Task 10
- Spec tests (unit/integration/soak) -> Tasks 2, 3, 7, 8, 9, 14, 15

**2. Placeholder scan:** None found. The "TBD" in `_join_weight_for` (Task 9 SettledLifecycle) is a deliberate hardcode-with-comment until species recipes carry `join_weight` - flagged in code, will be lifted when ferrets/kittens land.

**3. Type consistency:** `body_capabilities` is a Dictionary in the recipe and a Component dict on the entity. `body_geometry: {size_ru: int}` consistent throughout. Relationship name `&"sleeping"` used consistently as the lowercase joiner-state. Node IDs (entry/interior) use `_enterable_nodes` keyed by `"box_entry:rack:slot"` and `"box_interior:rack:slot"`.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-26-cat-jumps-into-box.md`.

**Worktree note:** This plan is for a fresh feature branch off `main`. Do not implement on top of `fix/pet-to-satisfied-chain`. The pre-flight section at the top has the worktree commands.

**Two execution options:**

1. **Subagent-Driven (recommended)** - dispatch a fresh subagent per task, review between tasks, fast iteration. Each subagent gets one task with full context; the main thread reviews diffs and stamps before moving on.

2. **Inline Execution** - execute tasks in this session using executing-plans, batch execution with checkpoints for review.

Which approach?
