# Perception Channels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decouple perception (receiver senses) from emission falloff (per-ad effect radius), and ship a channel registry that maps each emitter channel to its carrier sense, target desire, and effect direction.

**Architecture:** Two phases in one plan. **Phase 1 (PR1)** is a self-contained bug fix: add a `senses` block per species, widen the spatial query from `8 RU = 64 px` to `BAY_WIDTH_PX = 186 px`, and gate ad scoring on the receiver's sense rather than the per-ad `radius_px`. This alone fixes the Biscuit/Mittens-stuck-on-floor regression and ships behind a wider but still bay-bounded perception model. **Phase 2 (PR2)** lands the channel registry, slot-delivery scatter mode, quadratic falloff, schema bump, ad-field rename (`desire_type`→`channel`, `radius_px`→`effect_radius_px`), and confirms `.claude/rules/animal-ai.md` (already drafted in this branch) ships alongside the code.

**Tech Stack:** GDScript (Godot 4.6.1), GUT (Godot Unit Test), JSONC for mod config, integer game values (0–1000 scale), pure-core RefCounted simulation.

**Spec:** `docs/superpowers/specs/2026-05-02-perception-channels-design.md`

---

## File Structure

### Created
- `tests/unit/test_constants_channels.gd` — pins the `Constants.CHANNELS` registry shape
- `tests/unit/test_sense_gating.gd` — sense-based scoring gate cases from the spec's Worked Examples table
- `tests/scenario/test_cat_finds_box_across_bay.gd` — Biscuit/Mittens regression
- `script/checks/species_requires_senses` — lint that every species recipe declares `senses`
- `script/checks/channels_complete` — lint that every CHANNELS entry has `sense`+`desire`+`effect`

### Modified
- `mods/tcp_cats/species/cat.jsonc` — add `senses` block; (PR2) bump schema_version, migrate desires to all-positive, ad fields rename
- `mods/tcp_ferrets/species/ferret.jsonc` — add `senses` block; (PR2) schema bump, ad fields rename
- `mods/tcp_tuna/objects/tuna_can.jsonc` — (PR2) schema bump, ad fields rename
- `engine/mod/species_schema_validator.gd` — require `senses` field
- `engine/mod/entity_def_registry.gd` — write `senses` component on spawn
- `engine/core/constants.gd` — add `CHANNELS: Dictionary` const (PR1) and `_apply_falloff` if needed (PR2 may put it in scatter)
- `engine/desires/desire_resolver.gd` — gate scoring on `senses[CHANNELS[ad.<key>].sense]`, widen spatial query (PR1); branch on `effect` (PR2)
- `engine/desires/desire_scatter.gd` — widen spatial query (PR1); two-pass slot/radius delivery, entity-first iteration, quadratic falloff (PR2)
- `engine/objects/object_state_manager.gd` — (PR2) ad field rename, add `effect_slot: true` to box ads
- `tests/unit/test_desire_resolver.gd` — update existing assertions for wider behavior
- `script/validate` — invoke new checks
- `.claude/rules/animal-ai.md` — already updated in this branch; verify alignment in Phase 2

---

# Phase 1 (PR1): Senses plumbing + spatial cap widening

This phase fixes the Biscuit/Mittens regression. After Phase 1:
- Every species declares `senses: {sight, hearing, smell, touch}`.
- `Constants.CHANNELS` exists with `{sense, desire, effect}` for the 12 channels.
- `score_ad` gates on the receiver's sense (using CHANNELS lookup), not on `ad.radius_px`.
- Spatial queries in `desire_resolver` and `desire_scatter` use `BAY_WIDTH_PX`.
- A scenario test proves a cat at one rack scores a box several racks away in the same bay.

The legacy ad field name `desire_type` and `radius_px` stay intact — that rename is Phase 2.

---

### Task 1: Add `senses` block to species recipes

**Files:**
- Modify: `mods/tcp_cats/species/cat.jsonc:6-9` (after `"id"`/`"name"`)
- Modify: `mods/tcp_ferrets/species/ferret.jsonc:6-8`

This is data-only. No test — Tasks 2 and 3 verify the data flows into the validator and entity creation.

- [ ] **Step 1: Add `senses` to cat.jsonc**

Insert after the `"name": "Cat",` line:

```jsonc
  "senses": {
    "sight":   186,
    "hearing": 186,
    "smell":   186,
    "touch":    64
  },
```

Touch is intentionally narrow (cat skin senses ambient temperature gradients to ~64 px). All other senses default bay-wide for the prototype — diversity is tuned later per species.

- [ ] **Step 2: Add `senses` to ferret.jsonc**

Insert after the `"name": "Ferret",` line:

```jsonc
  "senses": {
    "sight":   186,
    "hearing": 186,
    "smell":   186,
    "touch":    32
  },
```

Ferrets have shorter touch range (smaller bodies, less ambient temperature sensing) — a content choice, tunable later.

- [ ] **Step 3: Verify JSON parses**

Run: `script/checks/validate_json mods/tcp_cats/species/cat.jsonc mods/tcp_ferrets/species/ferret.jsonc`
Expected: no errors, exit 0.

---

### Task 2: Update `SpeciesSchemaValidator` to require `senses`

**Files:**
- Modify: `engine/mod/species_schema_validator.gd:12`
- Test: `tests/unit/test_species_schema_validator.gd` (create if missing)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_species_schema_validator.gd` if it doesn't exist; otherwise add a test method:

```gdscript
extends GutTest


func test_species_missing_senses_is_rejected() -> void:
    var validator: SpeciesSchemaValidator = SpeciesSchemaValidator.new()
    var def: Dictionary = {
        "id": "test:no_senses_species",
        "desires": {"warmth": 500},
        "body_capabilities": {"walks": {}},
        "body_geometry": {"size_ru": 1},
        # senses intentionally omitted
    }
    var ok: bool = validator.is_valid_species(def)
    assert_false(ok, "Species without `senses` must be rejected")
    assert_push_error("missing required field: senses")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_species_schema_validator.gd`
Expected: FAIL — `is_valid_species` currently returns `true` because `senses` isn't in `_required_fields`.

- [ ] **Step 3: Add `senses` to required fields**

Modify `engine/mod/species_schema_validator.gd:12` from:

```gdscript
var _required_fields: Array[String] = ["desires", "body_capabilities", "body_geometry"]
```

to:

```gdscript
var _required_fields: Array[String] = ["desires", "body_capabilities", "body_geometry", "senses"]
```

Also extend `_SPECIES_MARKER_FIELDS` (line 7) to include `"senses"` so a recipe with `senses` but no other markers still registers as a species:

```gdscript
const _SPECIES_MARKER_FIELDS: Array[String] = ["desires", "body_capabilities", "traversal", "senses"]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_species_schema_validator.gd`
Expected: PASS.

- [ ] **Step 5: Stamp the test**

Run: `script/tdd_verify stamp tests/unit/test_species_schema_validator.gd`
Expected: stamp file written; `tests/unit/test_species_schema_validator.gd.stamp` is now in the working tree.

---

### Task 3: Wire `EntityDefRegistry` to write the `senses` component

**Files:**
- Modify: `engine/mod/entity_def_registry.gd` (add a senses block right after the `desires` block, around line 150)
- Test: `tests/unit/test_entity_def_registry.gd` (likely exists — add a method)

- [ ] **Step 1: Confirm test file exists, find spot**

Run: `ls tests/unit/test_entity_def_registry*.gd 2>/dev/null` — note whether it exists. If not, create it; if yes, append.

- [ ] **Step 2: Write the failing test**

Add method:

```gdscript
func test_spawned_cat_has_senses_component() -> void:
    var db: GameStateDB = GameStateDB.new()
    var registry: EntityDefRegistry = EntityDefRegistry.new()
    registry.register_entity_def("tcp_cats:cat", {
        "id": "tcp_cats:cat",
        "desires": {"warmth": 500},
        "body_capabilities": {"walks": {}},
        "body_geometry": {"size_ru": 2},
        "senses": {"sight": 186, "hearing": 186, "smell": 186, "touch": 64},
    })
    var id: int = registry.spawn(db, "tcp_cats:cat", {"x": 0, "y": 0})
    assert_true(db.has_component(id, &"senses"),
        "Spawned cat must have `senses` component")
    var senses: Dictionary = db.get_component(id, &"senses")
    assert_eq(senses.get(&"touch", -1), 64,
        "Touch range must round-trip from recipe to component")
```

If the existing `EntityDefRegistry` API differs (likely — it doesn't have `register_entity_def` per se), follow the existing test patterns in this file to match shape.

- [ ] **Step 3: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_entity_def_registry.gd`
Expected: FAIL — no `senses` component is written today.

- [ ] **Step 4: Add senses-write block in entity_def_registry.gd**

After the desires/personality block (around line 151, after `db.set_component(id, &"personality", personality)`), insert:

```gdscript
    # Senses component (perception acuity per sense). Required by schema
    # validator; missing senses on a species recipe means it never gets here.
    if def.has("senses"):
        var senses: Dictionary = {}
        for key: String in def["senses"]:
            senses[StringName(key)] = int(def["senses"][key])
        db.set_component(id, &"senses", senses)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_entity_def_registry.gd`
Expected: PASS.

- [ ] **Step 6: Stamp the test**

Run: `script/tdd_verify stamp tests/unit/test_entity_def_registry.gd`

---

### Task 4: Add `script/checks/species_requires_senses` lint

**Files:**
- Create: `script/checks/species_requires_senses` (executable shell script)
- Modify: `script/validate` (call the new check)

- [ ] **Step 1: Create the check**

Use `script/checks/no_species_dispatch` as a template (bash). Write `script/checks/species_requires_senses`:

```bash
#!/bin/bash
# Flags species recipes that omit the `senses` block.
# Reference: docs/superpowers/specs/2026-05-02-perception-channels-design.md
#
# Usage: species_requires_senses              (scan all recipes)
#        species_requires_senses file1 file2  (scan specific files)

set -e

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
cd "$REPO_ROOT"

if [ $# -gt 0 ]; then
  FILES=("$@")
else
  FILES=()
  while IFS= read -r line; do
    FILES+=("$line")
  done < <(find mods -path '*/species/*.jsonc' 2>/dev/null)
fi

FAIL=0
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in *.jsonc) ;; *) continue ;; esac
  if ! grep -q '"senses"' "$f"; then
    echo "FAIL: $f is missing required \"senses\" block"
    FAIL=1
  fi
done

if [ $FAIL -eq 0 ]; then
  echo "OK: every species recipe declares \"senses\""
fi
exit $FAIL
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x script/checks/species_requires_senses`

- [ ] **Step 3: Verify it passes on current recipes**

Run: `script/checks/species_requires_senses`
Expected: `OK: every species recipe declares "senses"`, exit 0.

- [ ] **Step 4: Verify it fires when senses is missing (manual smoke)**

Run: `cp mods/tcp_cats/species/cat.jsonc /tmp/test_recipe.jsonc && sed -i '' '/senses/,/},/d' /tmp/test_recipe.jsonc && script/checks/species_requires_senses /tmp/test_recipe.jsonc; rm /tmp/test_recipe.jsonc`
Expected: `FAIL: /tmp/test_recipe.jsonc is missing required "senses" block`, exit 1.

- [ ] **Step 5: Add to script/validate**

Find the section of `script/validate` that runs each check (look for `no_species_dispatch` to find the pattern), and add a sibling line invoking `species_requires_senses`.

- [ ] **Step 6: Run validate**

Run: `script/validate`
Expected: all checks pass.

---

### Task 5: Add `Constants.CHANNELS` registry

**Files:**
- Modify: `engine/core/constants.gd` (add a const after the existing constants block, before the static helpers)
- Create: `tests/unit/test_constants_channels.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_constants_channels.gd`:

```gdscript
extends GutTest


# AI-DEV: This test pins the channel registry shape. Adding a channel
# without sense+desire+effect is a content error — the lint
# `script/checks/channels_complete` enforces this at validate time, but
# this test catches it at GUT-suite time too. If you add a channel,
# extend `_REQUIRED_KEYS` here only if the registry shape itself is
# changing — not for new channels.

const _REQUIRED_KEYS: Array[StringName] = [&"sense", &"desire", &"effect"]
const _VALID_EFFECTS: Array[StringName] = [&"satisfy", &"deplete"]


func test_channels_registry_exists() -> void:
    assert_gt(Constants.CHANNELS.size(), 0,
        "Constants.CHANNELS must be populated")


func test_every_channel_has_required_keys() -> void:
    for channel: StringName in Constants.CHANNELS:
        var entry: Dictionary = Constants.CHANNELS[channel]
        for key: StringName in _REQUIRED_KEYS:
            assert_true(entry.has(key),
                "Channel %s missing required key %s" % [channel, key])


func test_every_channel_effect_is_satisfy_or_deplete() -> void:
    for channel: StringName in Constants.CHANNELS:
        var effect: StringName = Constants.CHANNELS[channel][&"effect"]
        assert_true(effect in _VALID_EFFECTS,
            "Channel %s has invalid effect %s" % [channel, effect])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_constants_channels.gd`
Expected: FAIL — `Constants.CHANNELS` does not exist.

- [ ] **Step 3: Add CHANNELS to constants.gd**

In `engine/core/constants.gd`, after the `const ARM_REACH_PX` line (~line 53), insert:

```gdscript

# Channel → desire registry. Each channel declares its carrier sense (used
# to gate scoring + scatter), the target desire on the receiver, and the
# effect direction (`satisfy` adds to the desire, `deplete` subtracts).
# See docs/superpowers/specs/2026-05-02-perception-channels-design.md.
#
# Six attractors, six aversions. `peace` and `quiet` are dedicated rest
# desires; the other four aversions deplete the matching attractor desire.
const CHANNELS: Dictionary = {
    # Attractors
    &"warmth":    {&"sense": &"touch",   &"desire": &"warmth",    &"effect": &"satisfy"},
    &"comfort":   {&"sense": &"sight",   &"desire": &"comfort",   &"effect": &"satisfy"},
    &"safety":    {&"sense": &"sight",   &"desire": &"safety",    &"effect": &"satisfy"},
    &"food":      {&"sense": &"smell",   &"desire": &"food",      &"effect": &"satisfy"},
    &"social":    {&"sense": &"sight",   &"desire": &"social",    &"effect": &"satisfy"},
    &"curiosity": {&"sense": &"sight",   &"desire": &"curiosity", &"effect": &"satisfy"},
    # Aversions
    &"chill":     {&"sense": &"touch",   &"desire": &"warmth",    &"effect": &"deplete"},
    &"chaos":     {&"sense": &"sight",   &"desire": &"peace",     &"effect": &"deplete"},
    &"startle":   {&"sense": &"sight",   &"desire": &"safety",    &"effect": &"deplete"},
    &"stench":    {&"sense": &"smell",   &"desire": &"food",      &"effect": &"deplete"},
    &"hostility": {&"sense": &"sight",   &"desire": &"social",    &"effect": &"deplete"},
    &"noise":     {&"sense": &"hearing", &"desire": &"quiet",     &"effect": &"deplete"},
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_constants_channels.gd`
Expected: PASS.

- [ ] **Step 5: Stamp the test**

Run: `script/tdd_verify stamp tests/unit/test_constants_channels.gd`

---

### Task 6: Update `desire_resolver.score_ad` to gate on senses

**Files:**
- Modify: `engine/desires/desire_resolver.gd:84-97` (the `score_ad` distance/radius block)
- Test: `tests/unit/test_desire_resolver.gd` (add new test method)

The legacy field name is `desire_type` (an emitter-side string like `&"warmth"` or `&"comfort"`). Those values match `Constants.CHANNELS` keys, so the lookup works without renaming the ad field — that rename is Phase 2.

- [ ] **Step 1: Write the failing test**

Add to `tests/unit/test_desire_resolver.gd`:

```gdscript
func test_score_ad_passes_when_within_sense_range() -> void:
    var cat_id: int = _make_cat(0, 0, 200, 800)
    _db.set_component(cat_id, &"senses", {
        &"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 64,
    })
    # Box at 80px — outside the legacy 24px radius_px gate, but inside
    # senses.sight (186px). With sense-based gating, the ad should score.
    var box_id: int = _db.create_entity()
    _db.set_component(box_id, &"position", {&"x": 80, &"y": 0})
    _db.set_component(box_id, &"advertisements", {&"list": [
        {&"desire_type": &"comfort", &"strength": 600, &"radius_px": 24},
    ]})
    _db.update_spatial(box_id, 80, 0)

    var ad: Dictionary = _db.get_component(box_id, &"advertisements")[&"list"][0]
    var score: int = _resolver.score_ad(cat_id, box_id, ad)
    assert_gt(score, 0,
        "Cat with sight=186 must score the box at 80px (legacy radius=24 is no longer the gate)")


func test_score_ad_zeroes_when_outside_sense_range() -> void:
    var cat_id: int = _make_cat(0, 0, 200, 800)
    _db.set_component(cat_id, &"senses", {
        &"sight": 32, &"hearing": 186, &"smell": 186, &"touch": 64,
    })
    # Box at 80px — outside the cat's sight=32 sense range.
    var box_id: int = _db.create_entity()
    _db.set_component(box_id, &"position", {&"x": 80, &"y": 0})
    _db.set_component(box_id, &"advertisements", {&"list": [
        {&"desire_type": &"comfort", &"strength": 600, &"radius_px": 24},
    ]})
    _db.update_spatial(box_id, 80, 0)

    var ad: Dictionary = _db.get_component(box_id, &"advertisements")[&"list"][0]
    var score: int = _resolver.score_ad(cat_id, box_id, ad)
    assert_eq(score, 0,
        "Near-sighted cat (sight=32) must not score a comfort ad at 80px")
```

The existing `_make_cat` helper does not write `senses`; the test sets it explicitly. (Phase 2 may extend `_make_cat` to take a senses arg — for now, set inline.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `script/checks/gut_tests -f tests/unit/test_desire_resolver.gd`
Expected: BOTH new tests FAIL — `score_ad` currently gates on `radius_px`, so the at-80 case returns 0 even with bay-wide sight, and the near-sighted case may also return 0 for the wrong reason (still radius-gated).

- [ ] **Step 3: Replace the radius gate in `score_ad`**

In `engine/desires/desire_resolver.gd`, replace lines 84-97 (the block from `var animal_pos` through `return desire_weight * deficit / 1000 * strength / 1000 * dist_factor / 1000`) with:

```gdscript
    var animal_pos: Dictionary = _db.get_component(animal_id, &"position")
    var object_pos: Dictionary = _db.get_component(object_id, &"position")
    var dist_px: int = (
        absi(animal_pos[&"x"] - object_pos[&"x"])
        + absi(animal_pos[&"y"] - object_pos[&"y"])
    )

    # Sense gate: look up the channel's carrier sense in Constants.CHANNELS,
    # then read the receiver's acuity for that sense. Default for an
    # undeclared sense is BAY_WIDTH_PX — bootstrap fallback only;
    # SpeciesSchemaValidator enforces the senses block at mod load.
    # `desire_type` is the legacy ad field name; PR2 renames it to `channel`.
    var channel_meta: Dictionary = Constants.CHANNELS.get(desire_type, {})
    var sense_key: StringName = channel_meta.get(&"sense", &"sight")
    var senses: Dictionary = _db.get_component(animal_id, &"senses") if _db.has_component(animal_id, &"senses") else {}
    var sense_range: int = senses.get(sense_key, Constants.BAY_WIDTH_PX)

    if dist_px > sense_range:
        return 0

    # Distance falloff scales over sense range (travel-cost preference) —
    # NOT over the ad's radius. Scoring answers "how far must I walk?",
    # not "is the effect reaching me right now?" (that's scatter's job).
    var dist_factor: int = 1000 - (dist_px * 1000 / sense_range) if sense_range > 0 else 1000

    return desire_weight * deficit / 1000 * strength / 1000 * dist_factor / 1000
```

Notes for the implementer:
- The legacy `var radius_px: int = ad[&"radius_px"]` line is now unused inside score_ad. Leave it for Phase 2 to remove (it's still read by scatter). Don't delete the field — Phase 2 renames it and audits all consumers.
- The `_db.has_component(animal_id, &"senses")` guard lets pre-Task-3 test fixtures work without a senses block, by falling back to `BAY_WIDTH_PX`. Real entities always carry senses after Task 3.

- [ ] **Step 4: Run tests to verify they pass**

Run: `script/checks/gut_tests -f tests/unit/test_desire_resolver.gd`
Expected: both new tests PASS. Existing tests in this file may need updates if they assumed `radius_px` was the gate — see Task 9.

- [ ] **Step 5: Stamp**

Run: `script/tdd_verify stamp tests/unit/test_desire_resolver.gd`

---

### Task 7: Widen spatial cap in `desire_resolver._evaluate_one` and `desire_scatter`

**Files:**
- Modify: `engine/desires/desire_resolver.gd:127-129`
- Modify: `engine/desires/desire_scatter.gd:28-31`

The spatial query currently uses `8 * Constants.SLOT_HEIGHT_PX = 64 px`. The spec replaces this with `BAY_WIDTH_PX = 186 px`, scoping ambient queries to one bay rather than 8 RU.

- [ ] **Step 1: Write the failing scenario test**

Create `tests/scenario/test_cat_finds_box_across_bay.gd`:

```gdscript
extends GutTest

# AI-DEV: Biscuit/Mittens regression guard. With the legacy 8-RU spatial
# query (64 px), a cat on rack-2 floor cannot see boxes placed at rack-4
# in the same bay. The widened BAY_WIDTH_PX (186 px) cap restores
# bay-scope perception. If this test starts failing because the cat's
# best score is 0, suspect: spatial query bound regressed, senses default
# regressed, or score_ad gate logic regressed.

var _db: GameStateDB
var _resolver: DesireResolver


func before_each() -> void:
    _db = GameStateDB.new()
    _resolver = DesireResolver.new(_db)


func test_cat_at_rack_2_scores_box_at_rack_4_same_bay() -> void:
    # Rack-2 floor cat
    var cat_id: int = _db.create_entity()
    var rack2_pos: Vector2i = Constants.rack_column_rect_world(0, 2).position
    var cat_x: int = rack2_pos.x + 12
    var cat_y: int = Constants.FLOOR_Y - 4
    _db.set_component(cat_id, &"species", {&"id": &"tcp_cats:cat"})
    _db.set_component(cat_id, &"position", {&"x": cat_x, &"y": cat_y})
    _db.set_component(cat_id, &"senses", {
        &"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 64,
    })
    _db.set_component(cat_id, &"desires", {
        &"warmth": 200, &"comfort": 200, &"curiosity": 800,
    })
    _db.set_component(cat_id, &"personality", {
        &"warmth_weight": 700, &"comfort_weight": 800, &"curiosity_weight": 100,
    })
    _db.set_component(cat_id, &"ai_state", {
        &"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
    })
    _db.set_component(cat_id, &"target", {
        &"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
        &"entity_id": Constants.INVALID_ID,
    })
    _db.update_spatial(cat_id, cat_x, cat_y)

    # Rack-4 box (~80 px away, well past the legacy 64 px cap)
    var box_id: int = _db.create_entity()
    var rack4_pos: Vector2i = Constants.rack_column_rect_world(0, 4).position
    var box_x: int = rack4_pos.x + 12
    var box_y: int = Constants.FLOOR_Y - 4
    _db.set_component(box_id, &"position", {&"x": box_x, &"y": box_y})
    _db.set_component(box_id, &"advertisements", {&"list": [
        {&"desire_type": &"comfort", &"strength": 700, &"radius_px": 24},
    ]})
    _db.update_spatial(box_id, box_x, box_y)

    var dist_px: int = absi(cat_x - box_x) + absi(cat_y - box_y)
    assert_gt(dist_px, 64,
        "Test setup: box must be past the legacy 8-RU cap")
    assert_lt(dist_px, Constants.BAY_WIDTH_PX,
        "Test setup: box must be within bay-width cap")

    _resolver.mark_dirty(cat_id)
    _resolver.evaluate_budget()

    var ai_state: Dictionary = _db.get_component(cat_id, &"ai_state")
    assert_eq(ai_state[&"state"], &"SEEKING",
        "Cat must SEEK after spotting the box across the bay")
    var target: Dictionary = _db.get_component(cat_id, &"target")
    assert_eq(target[&"entity_id"], box_id,
        "Cat must target the box specifically")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/scenario/test_cat_finds_box_across_bay.gd`
Expected: FAIL — `_evaluate_one` queries at 64px, the box at 80px isn't returned.

- [ ] **Step 3: Update `desire_resolver._evaluate_one` query**

In `engine/desires/desire_resolver.gd:127-129`, replace:

```gdscript
    # Perception radius: 8 slot-heights = 64 pixels
    var perception_px: int = 8 * Constants.SLOT_HEIGHT_PX
    var nearby: Array[int] = _db.query_radius(pos[&"x"], pos[&"y"], perception_px)
```

with:

```gdscript
    # Spatial bound: one bay. Per-sense clipping happens inside score_ad,
    # so per-channel acuity (touch=64 etc.) still narrows the actual
    # candidate set after this query returns.
    var nearby: Array[int] = _db.query_radius(
        pos[&"x"], pos[&"y"], Constants.BAY_WIDTH_PX,
    )
```

- [ ] **Step 4: Update `desire_scatter.scatter_from_ads` query**

In `engine/desires/desire_scatter.gd:27-31`, replace:

```gdscript
        # Perception radius: 8 slot-heights = 64 pixels
        var perception_px: int = 8 * Constants.SLOT_HEIGHT_PX
        var nearby: Array[int] = _db.query_radius(
            pos[&"x"], pos[&"y"], perception_px,
        )
```

with:

```gdscript
        # Spatial bound: one bay. Per-ad `radius_px` (Phase 1) or
        # `effect_radius_px` (Phase 2) does the narrow-phase clipping.
        var nearby: Array[int] = _db.query_radius(
            pos[&"x"], pos[&"y"], Constants.BAY_WIDTH_PX,
        )
```

- [ ] **Step 5: Run scenario test to verify it passes**

Run: `script/checks/gut_tests -f tests/scenario/test_cat_finds_box_across_bay.gd`
Expected: PASS — cat now SEEKS the box.

- [ ] **Step 6: Run full unit suite to catch regressions**

Run: `script/checks/gut_tests`
Expected: all tests pass. If something breaks, see Task 9.

---

### Task 8: Audit existing desire_resolver tests for the wider behavior

**Files:**
- Modify: `tests/unit/test_desire_resolver.gd`
- Modify: `tests/unit/test_desire_resolver_reachability.gd`

Some existing assertions may have been written to the legacy "ads beyond 64px don't score" or "ads beyond radius_px score 0" behavior. Those need to be updated to match the new gate semantics OR the test fixtures need to set `senses` to narrow the gate explicitly.

- [ ] **Step 1: Find candidate tests**

Run: `grep -n "radius_px\|radius_slots\|perception" tests/unit/test_desire_resolver*.gd`
Expected: a handful of references. Each fixture that creates a server/box at distance > 64 px or uses a small `radius_slots` to gate scoring needs review.

- [ ] **Step 2: For each affected test**

Two fix shapes:

**Shape A — test was checking sense-gating intent (sight/touch):**
Add a `senses` component set to the cat fixture. Set narrow sense values to reproduce the legacy gate (e.g. `sight: 32`).

**Shape B — test was checking emitter physics (warmth scatter at distance):**
Leave the `radius_px` on the ad. The Phase 1 scatter still uses `radius_px`. Fixture works as-is.

The line-by-line edits depend on what each test actually checks. Run the full suite after Task 7 — only address tests that fail, leave passing tests untouched.

- [ ] **Step 3: Run full unit suite**

Run: `script/checks/gut_tests`
Expected: all tests pass.

- [ ] **Step 4: Re-stamp any modified tests**

Run: `script/tdd_verify stamp tests/unit/test_desire_resolver.gd` (and any others that were edited).

---

### Task 9: PR1 final validation + commit

- [ ] **Step 1: Run full validate**

Run: `script/validate`
Expected: all checks pass — gdlint, gdscript_compile, gut_tests, json_snake_case_keys, no_node_in_core, no_parent_paths, no_secrets, no_species_dispatch, species_requires_senses, validate_json, verify_tests.

- [ ] **Step 2: Boot the game manually**

Run: `/Applications/Godot.app/Contents/MacOS/godot --path .` and let it run for ~10 seconds. Confirm cats spawn, no parse errors in the console, and that Biscuit/Mittens visibly path toward boxes (not stuck mid-floor).

- [ ] **Step 3: Stage and commit PR1**

```bash
git add \
    mods/tcp_cats/species/cat.jsonc \
    mods/tcp_ferrets/species/ferret.jsonc \
    engine/mod/species_schema_validator.gd \
    engine/mod/entity_def_registry.gd \
    engine/core/constants.gd \
    engine/desires/desire_resolver.gd \
    engine/desires/desire_scatter.gd \
    script/checks/species_requires_senses \
    script/validate \
    tests/unit/test_constants_channels.gd \
    tests/unit/test_constants_channels.gd.stamp \
    tests/unit/test_constants_channels.gd.uid \
    tests/unit/test_species_schema_validator.gd \
    tests/unit/test_species_schema_validator.gd.stamp \
    tests/unit/test_species_schema_validator.gd.uid \
    tests/unit/test_entity_def_registry.gd \
    tests/unit/test_entity_def_registry.gd.stamp \
    tests/unit/test_entity_def_registry.gd.uid \
    tests/unit/test_desire_resolver.gd \
    tests/unit/test_desire_resolver.gd.stamp \
    tests/scenario/test_cat_finds_box_across_bay.gd \
    tests/scenario/test_cat_finds_box_across_bay.gd.uid

git commit -m "$(cat <<'EOF'
feat(perception): senses + bay-wide cap, fix Biscuit/Mittens

PR1 of the perception-channels migration. Adds a `senses` block to
species recipes, wires it into entity creation, and replaces the
hardcoded 8-RU spatial query with BAY_WIDTH_PX (186). Scoring now
gates on the receiver's per-sense acuity via Constants.CHANNELS,
not on per-ad radius_px.

Floor cats can now see boxes anywhere in the bay (regression fix).
Per-ad radius_px still gates scatter — that rename + slot delivery
ships in PR2.

Spec: docs/superpowers/specs/2026-05-02-perception-channels-design.md
EOF
)"
```

Adjust the file list if any test files weren't created in this session (e.g. if `test_entity_def_registry.gd` already existed, drop the `.uid` line). `git status` will show what's actually staged vs. modified.

- [ ] **Step 4: Verify the commit is green**

Run: `script/validate`
Expected: all checks pass.

---

# Phase 2 (PR2): Channel registry consumers, slot delivery, schema bump

After Phase 1, the senses gate works in scoring. Phase 2 finishes the migration:
- Rename ad fields (`desire_type`→`channel`, `radius_px`→`effect_radius_px`).
- Add `effect_slot: true` for box ads (slot-delivered comfort/safety).
- Two-pass scatter: slot delivery + entity-first radius delivery with quadratic falloff.
- `score_ad` branches on `effect: satisfy|deplete` (not yet wired in PR1).
- Schema versions bump; one-shot migrator handles old saves.
- `script/checks/channels_complete` lints the registry.
- `.claude/rules/animal-ai.md` (already drafted in this branch) ships alongside.

---

### Task 10: Add `script/checks/channels_complete` lint

**Files:**
- Create: `script/checks/channels_complete`
- Modify: `script/validate`

This duplicates `tests/unit/test_constants_channels.gd` at the lint level so a CHANNELS-shape regression fails fast without booting GUT. The two are belt-and-suspenders by design.

- [ ] **Step 1: Create the check**

Write `script/checks/channels_complete`:

```bash
#!/bin/bash
# Verifies every entry in Constants.CHANNELS has sense+desire+effect.
# Reference: docs/superpowers/specs/2026-05-02-perception-channels-design.md

set -e
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
cd "$REPO_ROOT"

CONST="engine/core/constants.gd"
[ -f "$CONST" ] || { echo "FAIL: $CONST not found"; exit 1; }

# Find the CHANNELS block, then for each top-level &"<name>" entry
# verify it has &"sense", &"desire", &"effect" keys nearby (within 3 lines).
awk '
/^const CHANNELS: Dictionary = \{/ { in_block=1; next }
in_block && /^\}/                  { in_block=0; next }
in_block                           { print }
' "$CONST" > /tmp/channels.txt

FAIL=0
while IFS= read -r entry; do
  # Match lines that start a channel entry: e.g.   &"warmth": {&"sense": ...
  case "$entry" in
    *"&\""*"\":"*"{"*)
      for key in "&\"sense\":" "&\"desire\":" "&\"effect\":"; do
        echo "$entry" | grep -q "$key" || {
          echo "FAIL: channel entry missing $key — $entry"
          FAIL=1
        }
      done
      ;;
  esac
done < /tmp/channels.txt
rm -f /tmp/channels.txt

[ $FAIL -eq 0 ] && echo "OK: all CHANNELS entries have sense+desire+effect"
exit $FAIL
```

- [ ] **Step 2: Make it executable and run**

```bash
chmod +x script/checks/channels_complete
script/checks/channels_complete
```

Expected: `OK: all CHANNELS entries have sense+desire+effect`, exit 0.

- [ ] **Step 3: Add to script/validate**

Insert a call to `script/checks/channels_complete` next to the other check calls.

- [ ] **Step 4: Run validate**

Run: `script/validate`
Expected: all checks pass.

---

### Task 11: Bump schema versions + write the ad-shape migrator

**Files:**
- Modify: `mods/tcp_cats/species/cat.jsonc:6` (schema_version 2→3)
- Modify: `mods/tcp_ferrets/species/ferret.jsonc:5` (schema_version 2→3)
- Modify: `mods/tcp_tuna/objects/tuna_can.jsonc` (find schema_version line, bump)
- Modify: `engine/mod/entity_def_registry.gd` or wherever ad-shape normalization happens — add a one-shot migrator

The migration is structural: `desire_type` → `channel`, `radius_px` → `effect_radius_px`. We'll write the new shape to disk in the next tasks; the migrator handles any *out-of-tree* mods that ship with the old shape.

- [ ] **Step 1: Find the existing ad-loading entry point**

Run: `grep -rn "ad\[&\"desire_type\"\]\|ads\[&\"list\"\]\|state_ads\|advertisements" engine/mod/ engine/objects/ | head -20`

Identify the function (likely in `entity_def_registry.gd`) that reads the `advertisements` block out of a recipe.

- [ ] **Step 2: Write the failing migrator test**

Add to `tests/unit/test_entity_def_registry.gd` (or a new `test_ad_migration.gd`):

```gdscript
func test_legacy_desire_type_field_is_migrated_to_channel() -> void:
    var ad: Dictionary = {&"desire_type": &"warmth", &"strength": 500, &"radius_px": 16}
    var migrated: Dictionary = EntityDefRegistry.migrate_ad(ad)
    assert_true(migrated.has(&"channel"),
        "Legacy desire_type must migrate to channel")
    assert_eq(migrated[&"channel"], &"warmth")
    assert_true(migrated.has(&"effect_radius_px"),
        "Legacy radius_px must migrate to effect_radius_px")
    assert_eq(migrated[&"effect_radius_px"], 16)
    assert_false(migrated.has(&"desire_type"),
        "desire_type must be removed after migration")
    assert_false(migrated.has(&"radius_px"),
        "radius_px must be removed after migration")


func test_already_new_shape_passes_through() -> void:
    var ad: Dictionary = {&"channel": &"warmth", &"strength": 500, &"effect_radius_px": 16}
    var migrated: Dictionary = EntityDefRegistry.migrate_ad(ad)
    assert_eq(migrated[&"channel"], &"warmth")
    assert_eq(migrated[&"effect_radius_px"], 16)
```

- [ ] **Step 3: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_entity_def_registry.gd`
Expected: FAIL — `migrate_ad` doesn't exist.

- [ ] **Step 4: Implement the migrator**

In `engine/mod/entity_def_registry.gd`, add a static function:

```gdscript
# AI-DEV: One-shot migrator for the desire_type→channel and
# radius_px→effect_radius_px rename shipped in PR2 of the
# perception-channels design. Called wherever an ad dict is read from
# recipe config so out-of-tree mods on the old shape still load. Once
# all in-tree mods are on the new shape, this migrator stays for
# backwards compatibility — rename is a breaking change (see CHANNELS
# namespace policy in docs/superpowers/specs/2026-05-02-perception-channels-design.md).
static func migrate_ad(ad: Dictionary) -> Dictionary:
    var out: Dictionary = ad.duplicate()
    if out.has(&"desire_type") and not out.has(&"channel"):
        out[&"channel"] = out[&"desire_type"]
        out.erase(&"desire_type")
    if out.has(&"radius_px") and not out.has(&"effect_radius_px"):
        out[&"effect_radius_px"] = out[&"radius_px"]
        out.erase(&"radius_px")
    return out
```

Then find the function that materializes ads onto a spawned entity and pipe each ad through `migrate_ad` before storing.

- [ ] **Step 5: Run test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_entity_def_registry.gd`
Expected: PASS.

- [ ] **Step 6: Bump schema_version in each recipe**

Edit each file:
- `mods/tcp_cats/species/cat.jsonc:6` — `"schema_version": 2,` → `"schema_version": 3,`
- `mods/tcp_ferrets/species/ferret.jsonc:5` — `"schema_version": 2,` → `"schema_version": 3,`
- `mods/tcp_tuna/objects/tuna_can.jsonc` — bump whatever the current value is by 1

- [ ] **Step 7: Stamp the migrator test**

Run: `script/tdd_verify stamp tests/unit/test_entity_def_registry.gd`

---

### Task 12: Migrate ad fields in `object_state_manager.gd`

**Files:**
- Modify: `engine/objects/object_state_manager.gd:7-73` (the `OBJECT_CONFIG` dict)

Per the spec: rename, drop `effect_radius_px` where intent was visibility (comfort), keep + tune where physics matters. Cardboard box `comfort` ads become slot-delivered.

- [ ] **Step 1: Update tuna_can config**

In `OBJECT_CONFIG[&"tuna_can"][&"state_ads"]`, replace `&"desire_type"` with `&"channel"` and `&"radius_px"` with `&"effect_radius_px"` for both states:

```gdscript
&"sealed": {
    &"ads": [{
        &"channel": &"openable", &"strength": 800,
        &"effect_radius_px": 24, &"action": &"open",
    }],
},
&"open": {
    &"ads": [{
        &"channel": &"food", &"strength": 800,
        &"effect_radius_px": 40, &"action": &"eat",
    }],
},
&"empty": {&"ads": []},
```

(`openable` is not in `Constants.CHANNELS` because it's an action ad consumed by the food system, not the regular AI. It stays out of the registry; scoring code that hits a missing channel must handle this gracefully — see Task 14.)

- [ ] **Step 2: Update cardboard_box config — comfort becomes slot-delivered**

For each state (`&"new"`, `&"worn"`, `&"scraps"`):
- The `&"comfort"` ad: replace `&"radius_px": <n>` with `&"effect_slot": true`. Drop the radius entirely; slot delivery doesn't use a radius.
- The `&"curiosity"` action ad: rename fields but keep `&"effect_radius_px"` (curiosity is a draw-toward signal, radius makes sense for the `shred` action ad).

Example for `&"new"`:

```gdscript
&"new": {
    &"ads": [
        {&"channel": &"comfort", &"strength": 700,
            &"effect_slot": true, &"action": &"settle"},
        {&"channel": &"curiosity", &"strength": 500,
            &"effect_radius_px": 40, &"action": &"shred"},
    ],
    &"join": { ... unchanged ... },
},
```

Apply the same pattern to `&"worn"` and `&"scraps"`. The `&"scraps"` state's `&"comfort"` ad becomes `&"effect_slot": true` with the strength preserved.

- [ ] **Step 3: Run validate**

Run: `script/validate`
Expected: still green. Behavior may have changed (boxes now slot-delivered), but Phase 1 scatter still reads `effect_radius_px` if present and ignores `effect_slot` — see Task 16. Until then, slot-delivered box ads scatter nothing — that's expected; tests in Task 16 will assert correct behavior.

---

### Task 13: Migrate ad fields in mod jsonc files

**Files:**
- Modify: `mods/tcp_cats/species/cat.jsonc:96-110` (states.idle, states.sleeping, states.startled)
- Modify: `mods/tcp_ferrets/species/ferret.jsonc:74` (states.sleeping)
- Modify: `mods/tcp_tuna/objects/tuna_can.jsonc:9,18` (sealed/openable, open/food)

- [ ] **Step 1: Cat ads**

In `mods/tcp_cats/species/cat.jsonc:93-113`, rewrite the `"states"` block:

```jsonc
  "states": {
    "idle": {
      "advertisements": [
        { "channel": "warmth", "strength": 300, "effect_radius_px": 16 },
        { "channel": "curiosity", "strength": 400, "effect_radius_px": 24, "novelty_duration": 150, "novelty_cooldown": 50 }
      ]
    },
    "sleeping": {
      "advertisements": [
        { "channel": "warmth", "strength": 400, "effect_radius_px": 8 },
        { "channel": "comfort", "strength": 300, "effect_slot": true }
      ]
    },
    "grooming": { "advertisements": [] },
    "seeking": { "advertisements": [] },
    "startled": {
      "advertisements": [
        { "channel": "noise", "strength": 200, "effect_radius_px": 24 }
      ]
    }
  },
```

- Sleeping cat's `comfort` becomes slot-delivered (it's *in* its sleeping spot).
- `noise` stays radius — it's a sound emission with real spatial extent.

- [ ] **Step 2: Ferret ads**

In `mods/tcp_ferrets/species/ferret.jsonc:70-79`:

```jsonc
  "states": {
    "idle": { "advertisements": [] },
    "sleeping": {
      "advertisements": [
        { "channel": "warmth", "strength": 200, "effect_radius_px": 8 }
      ]
    },
    "seeking": { "advertisements": [] },
    "startled": { "advertisements": [] }
  },
```

- [ ] **Step 3: Tuna can ads**

In `mods/tcp_tuna/objects/tuna_can.jsonc`, rename the two `desire_type` fields to `channel` and `radius_px` to `effect_radius_px`. Don't change the values.

- [ ] **Step 4: Run validate**

Run: `script/validate`
Expected: green. Migrator (Task 11) handles any out-of-tree old-shape ads on load; in-tree ads are now on new shape directly.

---

### Task 14: Update `score_ad` to read `channel` field and branch on `effect`

**Files:**
- Modify: `engine/desires/desire_resolver.gd:62-97` (the `score_ad` function)

Phase 1 left `desire_type` as the field name and treated `effect` as implicit-satisfy. Now the field is `channel`, and `effect` from the registry decides sign.

- [ ] **Step 1: Write the failing test**

Add to `tests/unit/test_desire_resolver.gd`:

```gdscript
func test_score_ad_returns_negative_for_deplete_channel() -> void:
    var cat_id: int = _make_cat(0, 0, 800, 500)  # high warmth, low priority
    _db.set_component(cat_id, &"senses", {
        &"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 64,
    })
    # Add `quiet` desire and weight (not in default _make_cat)
    var desires: Dictionary = _db.get_component(cat_id, &"desires")
    desires[&"quiet"] = 600
    _db.set_component(cat_id, &"desires", desires)
    var personality: Dictionary = _db.get_component(cat_id, &"personality")
    personality[&"quiet_weight"] = 700
    _db.set_component(cat_id, &"personality", personality)

    # Buzzer at 60 px emitting noise (deplete on quiet)
    var buzzer_id: int = _db.create_entity()
    _db.set_component(buzzer_id, &"position", {&"x": 60, &"y": 0})
    _db.set_component(buzzer_id, &"advertisements", {&"list": [
        {&"channel": &"noise", &"strength": 700, &"effect_radius_px": 186},
    ]})
    _db.update_spatial(buzzer_id, 60, 0)

    var ad: Dictionary = _db.get_component(buzzer_id, &"advertisements")[&"list"][0]
    var score: int = _resolver.score_ad(cat_id, buzzer_id, ad)
    assert_lt(score, 0,
        "Deplete-channel ad must contribute negative score (cat avoids the buzzer)")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_desire_resolver.gd`
Expected: FAIL — current code reads `desire_type`, doesn't branch on effect.

- [ ] **Step 3: Update `score_ad`**

Rewrite `score_ad` body in `engine/desires/desire_resolver.gd`:

```gdscript
func score_ad(
    animal_id: int,
    object_id: int,
    ad: Dictionary,
    tracker: CuriosityTracker = null,
    current_tick: int = 0,
) -> int:
    # `channel` is the new (PR2) field name; `desire_type` is legacy and
    # routed through the migrator on entity load. score_ad accepts either
    # so test fixtures and any in-flight ads on the old shape still work.
    var channel: StringName = ad.get(&"channel", ad.get(&"desire_type", &""))

    # Curiosity novelty check (preserved from PR1)
    if tracker != null and channel == &"curiosity":
        var cooldown: int = ad.get(&"novelty_cooldown", 100)
        if not tracker.is_novel(object_id, current_tick, cooldown):
            return 0

    # Action ads outside the channel registry (e.g. `openable` consumed by
    # the food system) score 0 here — they're not part of the regular AI
    # scoring loop. The arm/food path consumes them through its own ticker.
    if not Constants.CHANNELS.has(channel):
        return 0

    var meta: Dictionary = Constants.CHANNELS[channel]
    var target_desire: StringName = meta[&"desire"]
    var effect: StringName = meta[&"effect"]
    var sense_key: StringName = meta[&"sense"]

    var personality: Dictionary = _db.get_component(animal_id, &"personality")
    var weight_key: StringName = StringName(String(target_desire) + "_weight")
    var desire_weight: int = personality.get(weight_key, 500)

    var animal_pos: Dictionary = _db.get_component(animal_id, &"position")
    var object_pos: Dictionary = _db.get_component(object_id, &"position")
    var dist_px: int = (
        absi(animal_pos[&"x"] - object_pos[&"x"])
        + absi(animal_pos[&"y"] - object_pos[&"y"])
    )

    var senses: Dictionary = _db.get_component(animal_id, &"senses") if _db.has_component(animal_id, &"senses") else {}
    var sense_range: int = senses.get(sense_key, Constants.BAY_WIDTH_PX)
    if dist_px > sense_range:
        return 0

    var dist_factor: int = 1000 - (dist_px * 1000 / sense_range) if sense_range > 0 else 1000
    var strength: int = ad[&"strength"]

    if effect == &"satisfy":
        var desires: Dictionary = _db.get_component(animal_id, &"desires")
        var deficit: int = 1000 - desires.get(target_desire, 500)
        return desire_weight * deficit / 1000 * strength / 1000 * dist_factor / 1000
    # deplete: no deficit term — a cat is not "deficit-hungry for quiet"
    return -1 * desire_weight * strength / 1000 * dist_factor / 1000
```

- [ ] **Step 4: Run test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_desire_resolver.gd`
Expected: PASS. Earlier tests using `desire_type` still pass via the `ad.get(&"channel", ad.get(&"desire_type", ...))` fallback.

- [ ] **Step 5: Stamp**

Run: `script/tdd_verify stamp tests/unit/test_desire_resolver.gd`

---

### Task 15: Slot-delivery scatter pass

**Files:**
- Modify: `engine/desires/desire_scatter.gd`

Add a first pass that scatters slot-delivered ads at full strength to slot occupants.

- [ ] **Step 1: Write the failing test**

Add to `tests/unit/test_desire_scatter.gd` (create if missing):

```gdscript
extends GutTest

var _db: GameStateDB
var _scatter: DesireScatter


func before_each() -> void:
    _db = GameStateDB.new()
    _scatter = DesireScatter.new(_db)


func test_slot_delivery_lands_full_strength_on_slot_occupant() -> void:
    # Place a box at bay 0, rack 1, slot 5 (interior)
    var slot_origin: Vector2i = Constants.slot_origin_world(0, 1, 5)
    var box_x: int = slot_origin.x + 4
    var box_y: int = slot_origin.y + 4
    var box_id: int = _db.create_entity()
    _db.set_component(box_id, &"position", {&"x": box_x, &"y": box_y})
    _db.set_component(box_id, &"advertisements", {&"list": [
        {&"channel": &"comfort", &"strength": 700, &"effect_slot": true},
    ]})
    _db.update_spatial(box_id, box_x, box_y)

    # Cat at the same slot, anchor offset
    var cat_id: int = _db.create_entity()
    _db.set_component(cat_id, &"position", {&"x": box_x + 2, &"y": box_y + 2})
    _db.set_component(cat_id, &"desires", {&"comfort": 100})
    _db.set_component(cat_id, &"senses", {
        &"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 64,
    })
    _db.update_spatial(cat_id, box_x + 2, box_y + 2)

    _scatter.scatter_from_ads()

    var desires: Dictionary = _db.get_component(cat_id, &"desires")
    assert_gt(desires[&"comfort"], 100,
        "Slot-delivered comfort must raise the cat's comfort desire")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_desire_scatter.gd`
Expected: FAIL — `scatter_from_ads` doesn't yet handle `effect_slot`.

- [ ] **Step 3: Add slot-delivery pass**

In `engine/desires/desire_scatter.gd`, prepend the existing scatter loop with a new slot-delivery pass:

```gdscript
func scatter_from_ads() -> void:
    _scatter_slot_delivery()
    _scatter_radius_delivery()


# Slot delivery: full strength to every entity sharing the ad-owner's slot.
# Boxes, beds, tubes, cat towers — anything where the effect logically
# belongs to a slot occupant rather than to a radius around a position.
func _scatter_slot_delivery() -> void:
    var ad_owners: Array[int] = _db.get_entities_with(&"advertisements")
    for owner_id: int in ad_owners:
        if not _db.has_component(owner_id, &"position"):
            continue
        var ads: Array = _db.get_component(owner_id, &"advertisements")[&"list"]
        var owner_pos: Dictionary = _db.get_component(owner_id, &"position")
        for ad: Dictionary in ads:
            if not ad.get(&"effect_slot", false):
                continue
            var channel: StringName = ad.get(&"channel", ad.get(&"desire_type", &""))
            if not Constants.CHANNELS.has(channel):
                continue
            # bay_local_to_slot needs a bay number. Today we only simulate bay 0.
            var query: Constants.SlotQuery = Constants.bay_local_to_slot(
                0, Vector2i(owner_pos[&"x"], owner_pos[&"y"]),
            )
            if query.zone != &"slot":
                push_error(
                    "DesireScatter: effect_slot ad on entity %d at %s is not slot-anchored (zone=%s)"
                    % [owner_id, owner_pos, query.zone],
                )
                continue
            _apply_to_slot_occupants(query.rack, query.slot, owner_id, ad, channel)


func _apply_to_slot_occupants(
    rack: int, slot: int, owner_id: int, ad: Dictionary, channel: StringName,
) -> void:
    var meta: Dictionary = Constants.CHANNELS[channel]
    var target_desire: StringName = meta[&"desire"]
    var effect: StringName = meta[&"effect"]
    var strength: int = ad[&"strength"]

    var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
    var nearby: Array[int] = _db.query_rect(
        slot_rect.position.x, slot_rect.position.y,
        slot_rect.end.x, slot_rect.end.y,
    )
    for entity_id: int in nearby:
        if entity_id == owner_id:
            continue
        if not _db.has_component(entity_id, &"desires"):
            continue
        var desires: Dictionary = _db.get_component(entity_id, &"desires")
        if not desires.has(target_desire):
            continue
        var current: int = desires[target_desire]
        var new_val: int
        if effect == &"satisfy":
            new_val = mini(1000, current + strength / 10)
        else:
            new_val = maxi(0, current - strength / 10)
        _db.set_field(entity_id, &"desires", target_desire, new_val)


# Existing radius delivery — kept; rewritten in Task 16.
func _scatter_radius_delivery() -> void:
    # ... move the existing scatter_from_ads body here ...
```

(The strength-per-tick math `/ 10` matches the legacy diminishing-returns behavior to avoid one-shot saturation. Phase 2 quadratic falloff is for radius delivery; slot delivery is binary in/out and uses a fixed per-tick rate.)

- [ ] **Step 4: Run test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_desire_scatter.gd`
Expected: PASS.

- [ ] **Step 5: Stamp**

Run: `script/tdd_verify stamp tests/unit/test_desire_scatter.gd`

---

### Task 16: Entity-first radius scatter with quadratic falloff

**Files:**
- Modify: `engine/desires/desire_scatter.gd:_scatter_radius_delivery`

Replace the legacy gap-based gain math with quadratic falloff. Invert the loop (entity-first) so each entity reads `senses` once per tick.

- [ ] **Step 1: Write the failing test**

Add to `tests/unit/test_desire_scatter.gd`:

```gdscript
func test_radius_delivery_applies_quadratic_falloff_at_half_radius() -> void:
    # Buzzer at origin, noise channel, 200 px effect_radius_px (large for the test)
    var buzzer_id: int = _db.create_entity()
    _db.set_component(buzzer_id, &"position", {&"x": 0, &"y": 0})
    _db.set_component(buzzer_id, &"advertisements", {&"list": [
        {&"channel": &"noise", &"strength": 1000, &"effect_radius_px": 200, &"falloff": &"quadratic"},
    ]})
    _db.update_spatial(buzzer_id, 0, 0)

    # Cat at 100 px (half radius). Quadratic: (1 - 100/200)² = 0.25
    var cat_id: int = _db.create_entity()
    _db.set_component(cat_id, &"position", {&"x": 100, &"y": 0})
    _db.set_component(cat_id, &"desires", {&"quiet": 1000})
    _db.set_component(cat_id, &"senses", {
        &"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 64,
    })
    _db.update_spatial(cat_id, 100, 0)

    _scatter.scatter_from_ads()

    var desires: Dictionary = _db.get_component(cat_id, &"desires")
    # quiet was 1000; deplete by strength * 0.25 / 10 = 25.
    # Allow ±5 for integer rounding.
    var quiet: int = desires[&"quiet"]
    assert_between(quiet, 970, 980,
        "Quadratic falloff at half-radius must deplete ~25/tick from quiet (got %d)" % quiet)
```

`assert_between` is `assert_true(quiet >= 970 and quiet <= 980, ...)` if GUT doesn't ship `assert_between`.

- [ ] **Step 2: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_desire_scatter.gd`
Expected: FAIL — current scatter applies a different math shape (gap-based gain).

- [ ] **Step 3: Replace `_scatter_radius_delivery` body**

```gdscript
func _scatter_radius_delivery() -> void:
    var entities: Array[int] = _db.get_entities_with(&"desires")
    for entity_id: int in entities:
        if not _db.has_component(entity_id, &"position"):
            continue
        var entity_pos: Dictionary = _db.get_component(entity_id, &"position")
        var senses: Dictionary = _db.get_component(entity_id, &"senses") if _db.has_component(entity_id, &"senses") else {}
        var broad_phase: int = _max_sense_range(senses)

        var nearby: Array[int] = _db.query_radius_with(
            entity_pos[&"x"], entity_pos[&"y"], broad_phase, &"advertisements",
        )
        var desires: Dictionary = _db.get_component(entity_id, &"desires")

        for ad_owner_id: int in nearby:
            if ad_owner_id == entity_id:
                continue
            if not _db.has_component(ad_owner_id, &"position"):
                continue
            var ads: Array = _db.get_component(ad_owner_id, &"advertisements")[&"list"]
            var owner_pos: Dictionary = _db.get_component(ad_owner_id, &"position")
            var dist: int = absi(entity_pos[&"x"] - owner_pos[&"x"]) + absi(entity_pos[&"y"] - owner_pos[&"y"])

            for ad: Dictionary in ads:
                if not ad.has(&"effect_radius_px"):
                    continue  # slot-delivered or actionable; not our pass
                if ad.has(&"action"):
                    continue  # action ads consumed by a state loop, not scatter
                var radius: int = ad[&"effect_radius_px"]
                if dist > radius:
                    continue
                var channel: StringName = ad.get(&"channel", ad.get(&"desire_type", &""))
                if not Constants.CHANNELS.has(channel):
                    continue
                var meta: Dictionary = Constants.CHANNELS[channel]
                var sense_key: StringName = meta[&"sense"]
                var sense_range: int = senses.get(sense_key, Constants.BAY_WIDTH_PX)
                if dist > sense_range:
                    continue
                var target: StringName = meta[&"desire"]
                if not desires.has(target):
                    continue
                var falloff_kind: StringName = ad.get(&"falloff", &"quadratic")
                var falloff_factor: int = _apply_falloff(dist, radius, falloff_kind)
                var delta: int = ad[&"strength"] * falloff_factor / 1000 / 10
                var current: int = desires[target]
                if meta[&"effect"] == &"satisfy":
                    _db.set_field(entity_id, &"desires", target, mini(1000, current + delta))
                else:
                    _db.set_field(entity_id, &"desires", target, maxi(0, current - delta))


# Returns the broadest declared sense range, defaulting to BAY_WIDTH_PX if
# senses is empty or missing — matches score_ad's bootstrap fallback.
func _max_sense_range(senses: Dictionary) -> int:
    var max_range: int = 0
    for key: StringName in senses:
        if senses[key] > max_range:
            max_range = senses[key]
    return max_range if max_range > 0 else Constants.BAY_WIDTH_PX


# Returns falloff factor in 0–1000 (thousandths). Distance >= radius → 0.
func _apply_falloff(dist: int, radius: int, kind: StringName) -> int:
    if dist >= radius:
        return 0
    if radius <= 0:
        return 1000
    var t: int = (radius - dist) * 1000 / radius   # 0..1000
    match kind:
        &"step":
            return 1000
        &"linear":
            return t
        &"quadratic":
            return t * t / 1000
        &"inverse_square":
            # 1 / (1 + (dist/radius * scale)²) — kept simple
            var d_norm: int = dist * 1000 / radius
            var denom: int = 1000 + d_norm * d_norm / 1000
            return 1_000_000 / denom
        _:
            return t * t / 1000   # default to quadratic
```

- [ ] **Step 4: Run test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_desire_scatter.gd`
Expected: PASS.

- [ ] **Step 5: Run full unit suite — catch regressions**

Run: `script/checks/gut_tests`
Expected: any test that depended on the legacy gap-based gain math will fail. Update those tests to assert the new quadratic-falloff math (see Task 19).

- [ ] **Step 6: Stamp**

Run: `script/tdd_verify stamp tests/unit/test_desire_scatter.gd`

---

### Task 17: Update species recipes — drop negative weights, add `quiet`/`peace`

**Files:**
- Modify: `mods/tcp_cats/species/cat.jsonc:14-31`
- Modify: `mods/tcp_ferrets/species/ferret.jsonc:8-20`

The `effect: deplete` math reads positive weights. Today's `cat.jsonc` declares `noise: -600` and `chased: -900`. Convert each negative entry to its receiver-side desire (`noise` is a channel, depleting `quiet`; `chased` has no shipped channel — drop until one ships).

- [ ] **Step 1: Cat recipe**

In `mods/tcp_cats/species/cat.jsonc:14-31`, replace the `desires` and `personality_ranges` blocks:

```jsonc
  "desires": {
    "warmth":    700,
    "comfort":   700,
    "curiosity": 150,
    "hunger":    700,
    "social":    500,
    "quiet":     600,
    "peace":     500,
    "safety":    800
  },
  "personality_ranges": {
    "warmth":    [500, 800],
    "comfort":   [600, 900],
    "curiosity": [100, 200],
    "hunger":    [600, 800],
    "social":    [400, 600],
    "quiet":     [400, 800],
    "peace":     [350, 650],
    "safety":    [700, 900]
  },
```

(`attention` was a stand-in for `social`; `chased` had no channel and is dropped.)

- [ ] **Step 2: Ferret recipe**

Similar shape in `mods/tcp_ferrets/species/ferret.jsonc:8-20`:

```jsonc
  "desires": {
    "warmth":    350,
    "comfort":   700,
    "curiosity": 850,
    "hunger":    700,
    "social":    400,
    "quiet":     400,
    "peace":     400,
    "safety":    600
  },
  "personality_ranges": {
    "warmth":    [300, 400],
    "comfort":   [600, 800],
    "curiosity": [800, 900],
    "hunger":    [600, 800],
    "social":    [300, 500],
    "quiet":     [300, 500],
    "peace":     [300, 500],
    "safety":    [500, 700]
  },
```

- [ ] **Step 3: Run validate**

Run: `script/validate`
Expected: all checks pass — JSON valid, weights all positive.

- [ ] **Step 4: Boot the game manually**

Run: `/Applications/Godot.app/Contents/MacOS/godot --path .`. Confirm cats spawn with the new desire shape; no parse errors.

---

### Task 18: Add the spec's worked-example sense-gating tests

**Files:**
- Create: `tests/unit/test_sense_gating.gd`

Per spec § "Tests that need attention" — pin the worked-example cases:

- [ ] **Step 1: Write the test file**

```gdscript
extends GutTest

# AI-DEV: Worked Examples regression guard. Each test pins a row from
# docs/superpowers/specs/2026-05-02-perception-channels-design.md
# § "Worked examples." If a regression makes one of these pass for the
# wrong reason (e.g. the sense gate stops firing), the others usually
# fail too. Read the spec row before relaxing any assertion.

var _db: GameStateDB
var _scatter: DesireScatter


func before_each() -> void:
    _db = GameStateDB.new()
    _scatter = DesireScatter.new(_db)


func _make_receiver(x: int, y: int, senses: Dictionary, desires: Dictionary) -> int:
    var id: int = _db.create_entity()
    _db.set_component(id, &"position", {&"x": x, &"y": y})
    _db.set_component(id, &"senses", senses)
    _db.set_component(id, &"desires", desires)
    _db.update_spatial(id, x, y)
    return id


func _make_emitter(x: int, y: int, ad: Dictionary) -> int:
    var id: int = _db.create_entity()
    _db.set_component(id, &"position", {&"x": x, &"y": y})
    _db.set_component(id, &"advertisements", {&"list": [ad]})
    _db.update_spatial(id, x, y)
    return id


func test_deaf_cat_does_not_receive_noise() -> void:
    var cat_id: int = _make_receiver(0, 0,
        {&"sight": 186, &"hearing": 0, &"smell": 186, &"touch": 64},
        {&"quiet": 800})
    _make_emitter(8, 0,
        {&"channel": &"noise", &"strength": 800, &"effect_radius_px": 186, &"falloff": &"quadratic"})

    _scatter.scatter_from_ads()

    var quiet: int = _db.get_component(cat_id, &"desires")[&"quiet"]
    assert_eq(quiet, 800,
        "Deaf cat (hearing=0) must not have quiet depleted by adjacent noise")


func test_cat_far_from_warm_server_does_not_receive_warmth() -> void:
    var cat_id: int = _make_receiver(0, 0,
        {&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 16},
        {&"warmth": 200})
    _make_emitter(100, 0,
        {&"channel": &"warmth", &"strength": 800, &"effect_radius_px": 16, &"falloff": &"quadratic"})

    _scatter.scatter_from_ads()

    var warmth: int = _db.get_component(cat_id, &"desires")[&"warmth"]
    assert_eq(warmth, 200,
        "Cat far from warm server must not gain warmth (effect_radius and touch both block)")


func test_hearing_cat_across_bay_receives_noise() -> void:
    var cat_id: int = _make_receiver(150, 0,
        {&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 64},
        {&"quiet": 1000})
    _make_emitter(0, 0,
        {&"channel": &"noise", &"strength": 800, &"effect_radius_px": 186, &"falloff": &"quadratic"})

    _scatter.scatter_from_ads()

    var quiet: int = _db.get_component(cat_id, &"desires")[&"quiet"]
    assert_lt(quiet, 1000,
        "Hearing cat across bay must have quiet depleted by noise")


func test_blind_cat_gets_only_noise_from_bawling_kitten() -> void:
    var cat_id: int = _make_receiver(0, 0,
        {&"sight": 0, &"hearing": 186, &"smell": 186, &"touch": 64},
        {&"peace": 1000, &"quiet": 1000})
    var kitten_id: int = _db.create_entity()
    _db.set_component(kitten_id, &"position", {&"x": 8, &"y": 0})
    _db.set_component(kitten_id, &"advertisements", {&"list": [
        {&"channel": &"noise", &"strength": 800, &"effect_radius_px": 186, &"falloff": &"quadratic"},
        {&"channel": &"chaos", &"strength": 800, &"effect_radius_px": 96,  &"falloff": &"quadratic"},
    ]})
    _db.update_spatial(kitten_id, 8, 0)

    _scatter.scatter_from_ads()

    var desires: Dictionary = _db.get_component(cat_id, &"desires")
    assert_lt(desires[&"quiet"], 1000, "Blind cat must hear noise → quiet drops")
    assert_eq(desires[&"peace"], 1000, "Blind cat must not see chaos → peace unchanged")


func test_deaf_cat_gets_only_chaos_from_bawling_kitten() -> void:
    var cat_id: int = _make_receiver(0, 0,
        {&"sight": 186, &"hearing": 0, &"smell": 186, &"touch": 64},
        {&"peace": 1000, &"quiet": 1000})
    var kitten_id: int = _db.create_entity()
    _db.set_component(kitten_id, &"position", {&"x": 8, &"y": 0})
    _db.set_component(kitten_id, &"advertisements", {&"list": [
        {&"channel": &"noise", &"strength": 800, &"effect_radius_px": 186, &"falloff": &"quadratic"},
        {&"channel": &"chaos", &"strength": 800, &"effect_radius_px": 96,  &"falloff": &"quadratic"},
    ]})
    _db.update_spatial(kitten_id, 8, 0)

    _scatter.scatter_from_ads()

    var desires: Dictionary = _db.get_component(cat_id, &"desires")
    assert_lt(desires[&"peace"], 1000, "Deaf cat must see chaos → peace drops")
    assert_eq(desires[&"quiet"], 1000, "Deaf cat must not hear noise → quiet unchanged")
```

- [ ] **Step 2: Run test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_sense_gating.gd`
Expected: all five tests PASS — they exercise the senses gate + slot/radius delivery already implemented.

- [ ] **Step 3: Stamp**

Run: `script/tdd_verify stamp tests/unit/test_sense_gating.gd`

---

### Task 19: Update existing tests for new scatter math

**Files:**
- Modify: `tests/unit/test_desire_resolver.gd`
- Modify: `tests/unit/test_desire_resolver_reachability.gd`
- Possibly: `tests/scenario/test_*.gd` that check warmth scatter values

The new scatter math (quadratic falloff at distance) produces different absolute values than the legacy gap-based gain. Tests asserting specific desire values after one scatter tick need to update.

- [ ] **Step 1: Run full GUT suite, list failures**

Run: `script/checks/gut_tests`
Expected: a few tests fail. Note them.

- [ ] **Step 2: For each failure, update the assertion**

Two cases:
- **Test was structurally checking that scatter happens**: change `assert_eq(warmth, <legacy_value>)` to `assert_gt(warmth, <previous_value>)` — preserves intent without pinning the exact math.
- **Test was checking the math shape**: re-derive the expected value under quadratic falloff. The new math: `delta_per_tick = strength * ((1 - dist/radius)²) / 10`.

- [ ] **Step 3: Re-stamp updated tests**

Run: `script/tdd_verify stamp <each_changed_unit_test>` (don't re-stamp scenario/integration tests — they're not stamped).

- [ ] **Step 4: Run validate**

Run: `script/validate`
Expected: green.

---

### Task 20: Verify `.claude/rules/animal-ai.md` matches the implementation

**Files:**
- Read: `.claude/rules/animal-ai.md`

The animal-ai.md aversions section was rewritten in this branch during the spec-design phase. The implementation in Tasks 14, 16, 17 should match. Confirm.

- [ ] **Step 1: Read animal-ai.md aversions section**

Run: `grep -n -A 5 "Aversions (Channel Effect Direction)" .claude/rules/animal-ai.md`

- [ ] **Step 2: Cross-check claims**

For each claim in the doc, confirm the code matches:

| Doc claim | Code check |
|---|---|
| "Animals have a single `desires` dict of positive weights" | grep `personality.get(.*_weight` and `desires.get(` — no negative checks anywhere |
| "Effect is a registry property, not a per-ad sign" | `Constants.CHANNELS[*][&"effect"]` is the only source of effect direction |
| "satisfy → deficit-weighted; deplete → no deficit term" | score_ad branches on effect, only satisfy reads deficit |
| "score_for branches on `meta[&"effect"]`" | resolver.score_ad ditto |
| "`is_available()` is not checked in scoring" | grep score_ad for `is_available` — should not appear |
| "`senses` block is the gate" | resolver.score_ad uses senses, not radius_px, in the gate |
| "Spatial query at `BAY_WIDTH_PX`" | `_evaluate_one` and `_scatter_radius_delivery` use `Constants.BAY_WIDTH_PX` |
| "Slot-delivery + radius-delivery passes" | `_scatter_slot_delivery` and `_scatter_radius_delivery` exist |

- [ ] **Step 3: Patch any drift**

If the doc says X and the code does Y, decide which is right. Usually the spec is authoritative — if the code drifted, fix the code; if the rule drifted during the rewrite, fix the rule. Confirm with the user before any rule edits if uncertain.

- [ ] **Step 4: No commit yet — Task 21 commits the whole PR2**

---

### Task 21: PR2 final validation + commit

- [ ] **Step 1: Run full validate**

Run: `script/validate`
Expected: all checks pass.

- [ ] **Step 2: Boot the game manually**

Run: `/Applications/Godot.app/Contents/MacOS/godot --path .`. Confirm:
- Cats spawn with new desire shape (no negative weights in inspect).
- Cat in box visibly receives slot-delivered comfort (the `tucked` z-flip and slot-occupant comfort math both fire).
- A noise-emitting buzzer (if one is placed in test scenarios) deplets `quiet` on nearby cats.
- No parse errors in the console.

- [ ] **Step 3: Stage and commit PR2**

```bash
git add \
    engine/core/constants.gd \
    engine/desires/desire_resolver.gd \
    engine/desires/desire_scatter.gd \
    engine/objects/object_state_manager.gd \
    engine/mod/entity_def_registry.gd \
    mods/tcp_cats/species/cat.jsonc \
    mods/tcp_ferrets/species/ferret.jsonc \
    mods/tcp_tuna/objects/tuna_can.jsonc \
    script/checks/channels_complete \
    script/validate \
    .claude/rules/animal-ai.md \
    tests/unit/test_constants_channels.gd \
    tests/unit/test_constants_channels.gd.stamp \
    tests/unit/test_desire_resolver.gd \
    tests/unit/test_desire_resolver.gd.stamp \
    tests/unit/test_desire_scatter.gd \
    tests/unit/test_desire_scatter.gd.stamp \
    tests/unit/test_desire_scatter.gd.uid \
    tests/unit/test_sense_gating.gd \
    tests/unit/test_sense_gating.gd.stamp \
    tests/unit/test_sense_gating.gd.uid \
    tests/unit/test_entity_def_registry.gd \
    tests/unit/test_entity_def_registry.gd.stamp

git commit -m "$(cat <<'EOF'
feat(perception): channel registry, slot delivery, aversion rewrite

PR2 of the perception-channels migration. Adds Constants.CHANNELS
(12 channels: 6 attractor + 6 aversion) with {sense, desire, effect}
metadata. Renames ad fields (desire_type→channel, radius_px→
effect_radius_px) with a one-shot migrator for out-of-tree mods.
Splits scatter into two passes: slot delivery (full strength to slot
occupants) and radius delivery (entity-first, quadratic falloff).
Species recipes drop negative weights — aversion is encoded by the
channel registry's `effect: deplete`, not by signed weights.

Animal-ai.md aversions section ships alongside the code.

Spec: docs/superpowers/specs/2026-05-02-perception-channels-design.md
EOF
)"
```

- [ ] **Step 4: Verify commit is green**

Run: `script/validate`
Expected: green.

---

## Self-Review

(Author checklist — run after writing the plan, before handing off.)

**1. Spec coverage:**

| Spec section | Covered by |
|---|---|
| § The conflation | Tasks 6, 11, 12, 14 (separates senses gate from emitter physics) |
| § Worked examples | Task 18 (`test_sense_gating.gd` pins each row) |
| § Anti-cases | Task 14 (`score_ad` doesn't compose senses+radius with `min`) |
| § 1. Per-species senses | Tasks 1–4 (block + validator + lint + entity creation) |
| § 2. Per-ad delivery (radius / slot) | Tasks 11, 12, 13, 15, 16 (config rename + slot pass + radius pass) |
| § Bonds (and why not in scatter) | Implicit — scatter never reads bonds in Task 16 |
| § 3. Channel → desire mapping | Task 5 (registry) + Task 14 (consumer) |
| § What changes in the resolver | Tasks 6, 7, 14 (resolver) + Tasks 15, 16 (scatter) |
| § Tick discipline | Documented; existing `tick_scheduler` already orders scatter→scoring |
| § Migration | Tasks 11, 12, 13 (schema bump + migrator + ad rename) |
| § Tests that need attention | Tasks 18 (new) + 19 (existing) |
| § Boundaries | Documented; not implementation work |
| § Open questions | All resolved in spec; no plan tasks needed |

**2. Placeholder scan:** No "TBD," "implement later," or "similar to Task N" — every code step has explicit code. Tasks 8 and 19 acknowledge that the precise scope of test fixes depends on what fails — that's not a placeholder; it's an honest statement that the engineer needs to react to which specific tests break. Each provides the two fix shapes.

**3. Type consistency:**
- `Constants.CHANNELS` is `Dictionary` everywhere; entries always have `sense`+`desire`+`effect`.
- `score_ad` reads `ad.get(&"channel", ad.get(&"desire_type", &""))` — handles both shapes during the migration window.
- `senses` is a `Dictionary` keyed by `StringName` sense names; values are `int` pixel ranges.
- `effect_slot: bool` and `effect_radius_px: int` are mutually exclusive on a single ad — Tasks 12, 13 enforce this in config; Task 16's radius pass simply skips ads without `effect_radius_px`.
- `_apply_falloff` returns thousandths (0–1000), matching TCP's integer scale convention.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-02-perception-channels.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
