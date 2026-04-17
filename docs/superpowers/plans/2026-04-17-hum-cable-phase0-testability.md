# HUM Cable — Phase 0 (Testability Prerequisites) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **SPEC:** `docs/superpowers/specs/2026-04-17-hum-cable-hookup-design.md` (Phase 0 section).
>
> **STOP / clear context between phases.** This is one of three plans. After Phase 0 is merged green, START A NEW SESSION before beginning Phase 1. The plans are intentionally bounded so each fits comfortably in a fresh context window, and so each phase ships as a coherent increment. Do not proceed into `2026-04-17-hum-cable-phase1-per-hum-refactor.md` in the same session.

**Goal:** Make the cable loop *testable* by landing (a) a minimal starter scenario and (b) a debug contentment override. The Ring 0 pet→satisfied→purr chain is currently broken; Phase 0 provides the workaround so QA can exercise Phase 1 and Phase 2 without waiting for the real chain to be fixed.

**Architecture:**
- Scenario loader (`engine/core/world_init_system.gd`, RefCounted) scans all mods for `scenarios/*.jsonc`, selects one via `settings.starter_scenario_id`, and populates entities on new-game init only. Idempotent via a top-level save flag.
- Debug override: a `Shift+F1` input action flips a `debug.force_satisfied_entity_id` on the inspected contentment-bearing entity. The contentment system honors the flag when deriving `is_satisfied`.

**Tech Stack:** GDScript 4, Godot 4.6, GUT tests, MessagePack save format (unchanged), JSONC for scenario files.

---

## File Structure

| File | Create / Modify | Responsibility |
|---|---|---|
| `engine/core/world_init_system.gd` | Create | RefCounted. Loads a scenario JSONC by id, spawns entities into `GameStateDB`. |
| `mods/tcp_base/scenarios/starter.jsonc` | Create | The default starter scenario: 1 HUM, 1 TUNA + button, 1 ARM, 2 cats. |
| `engine/mod/scenario_registry.gd` | Create | RefCounted. Discovers `scenarios/*.jsonc` across all mods, indexed by id. |
| `engine/mod/scenario_schema_validator.gd` | Create | RefCounted. Validates one scenario def against the schema. |
| `engine/mod/mod_loader.gd` | Modify | Discover `scenarios/` subdir alongside `species/` and `objects/`. |
| `engine/core/settings.gd` | Create if absent / Modify | Holds `debug.enabled` and `starter_scenario_id`. |
| `nodes/game_server.gd` | Modify | Invoke `WorldInitSystem` on new game; skip on load. Carry `starter_scenario_applied` flag through save root. |
| `engine/core/contentment.gd` | Modify | Honor `debug.force_satisfied_entity_id` override in `evaluate_all`. |
| `nodes/hud/debug_hud.gd` | Create | Registers `Shift+F1` handler; toggles the debug override for the inspected entity. |
| `project.godot` | Modify | Add `debug_force_satisfied` input action (Shift+F1). |
| `tests/unit/test_world_init_system.gd` | Create | Scenario resolution, idempotency, required vs optional. |
| `tests/unit/test_scenario_schema_validator.gd` | Create | Schema checks (required fields, malformed entries). |
| `tests/unit/test_contentment_debug_override.gd` | Create | `is_satisfied` forced via override flag. |
| `tests/integration/test_phase0_smoke.gd` | Create | Fresh game → 6 starter entities exist → Shift+F1 flips satisfaction. |

**Design notes:**
- `WorldInitSystem` is pure Ring-0 core (RefCounted, no scene access). Takes db, events, scenario_registry, entity_defs.
- `ScenarioRegistry` mirrors the existing `EntityDefRegistry` pattern — single `register(id, def)` API, single `get(id) -> Dictionary` lookup.
- `DebugHud` is a small client-side Node. It is deliberately **not** a "debug system" on GameServer — the override lives as a **component on the target entity** (`debug_force_satisfied: {active: int}`), so the server-side contentment system can see it without a sideband.

---

## Task 1: Scenario schema validator

**Files:**
- Create: `engine/mod/scenario_schema_validator.gd`
- Create: `tests/unit/test_scenario_schema_validator.gd`

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/unit/test_scenario_schema_validator.gd
extends GutTest

var _v: ScenarioSchemaValidator

func before_each() -> void:
    _v = ScenarioSchemaValidator.new()

func test_valid_scenario_passes() -> void:
    var def := {
        "schema_version": 1,
        "id": "tcp_base:starter",
        "entities": [
            {"type": "tcp_base:hum_device", "rack": 0, "slot": 0},
        ],
    }
    assert_true(_v.is_valid(def))

func test_missing_id_fails() -> void:
    var def := {"schema_version": 1, "entities": []}
    assert_false(_v.is_valid(def))

func test_missing_schema_version_fails() -> void:
    var def := {"id": "tcp_base:starter", "entities": []}
    assert_false(_v.is_valid(def))

func test_entity_missing_type_fails() -> void:
    var def := {
        "schema_version": 1,
        "id": "tcp_base:x",
        "entities": [{"rack": 0, "slot": 0}],
    }
    assert_false(_v.is_valid(def))

func test_entity_without_placement_fields_fails() -> void:
    var def := {
        "schema_version": 1,
        "id": "tcp_base:x",
        "entities": [{"type": "tcp_base:arm"}],
    }
    assert_false(_v.is_valid(def))

func test_floor_entity_requires_floor_fields() -> void:
    var def := {
        "schema_version": 1,
        "id": "tcp_base:x",
        "entities": [{"type": "tcp_base:arm", "floor_rack": 0, "floor_slot_offset": 0}],
    }
    assert_true(_v.is_valid(def))
```

- [ ] **Step 2: Run tests — confirm failure.**

Run: `script/checks/gut_tests -f tests/unit/test_scenario_schema_validator.gd`
Expected: all tests fail with "ScenarioSchemaValidator not found" or equivalent.

- [ ] **Step 3: Implement validator.**

```gdscript
# engine/mod/scenario_schema_validator.gd
class_name ScenarioSchemaValidator extends RefCounted

const REQUIRED_TOP_FIELDS: Array[StringName] = [&"schema_version", &"id", &"entities"]

func is_valid(def: Dictionary) -> bool:
    for field in REQUIRED_TOP_FIELDS:
        if not def.has(String(field)):
            return false
    var entities: Array = def.get("entities", [])
    for entry in entities:
        if not _entry_is_valid(entry):
            return false
    return true

func _entry_is_valid(entry: Dictionary) -> bool:
    if not entry.has("type"):
        return false
    var has_rack_slot: bool = entry.has("rack") and entry.has("slot")
    var has_floor: bool = entry.has("floor_rack") and entry.has("floor_slot_offset")
    return has_rack_slot or has_floor
```

- [ ] **Step 4: Run tests — confirm pass.**

Run: `script/checks/gut_tests -f tests/unit/test_scenario_schema_validator.gd`
Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add engine/mod/scenario_schema_validator.gd tests/unit/test_scenario_schema_validator.gd
git commit -m "feat(mod): scenario schema validator"
```

---

## Task 2: ScenarioRegistry

**Files:**
- Create: `engine/mod/scenario_registry.gd`
- Create: `tests/unit/test_scenario_registry.gd`

- [ ] **Step 1: Write failing tests.**

```gdscript
# tests/unit/test_scenario_registry.gd
extends GutTest

var _r: ScenarioRegistry

func before_each() -> void:
    _r = ScenarioRegistry.new()

func test_register_then_get() -> void:
    var def := {"schema_version": 1, "id": "tcp_base:starter", "entities": []}
    _r.register(&"tcp_base:starter", def)
    assert_eq(_r.get_scenario(&"tcp_base:starter"), def)

func test_has_scenario() -> void:
    assert_false(_r.has_scenario(&"tcp_base:starter"))
    _r.register(&"tcp_base:starter", {"schema_version": 1, "id": "tcp_base:starter", "entities": []})
    assert_true(_r.has_scenario(&"tcp_base:starter"))

func test_get_missing_returns_empty() -> void:
    assert_eq(_r.get_scenario(&"absent:id"), {})

func test_ids_sorted() -> void:
    _r.register(&"b:x", {"schema_version": 1, "id": "b:x", "entities": []})
    _r.register(&"a:x", {"schema_version": 1, "id": "a:x", "entities": []})
    assert_eq(_r.ids(), [&"a:x", &"b:x"])
```

- [ ] **Step 2: Run — confirm fail.**

Run: `script/checks/gut_tests -f tests/unit/test_scenario_registry.gd`
Expected: FAIL (ScenarioRegistry not found).

- [ ] **Step 3: Implement.**

```gdscript
# engine/mod/scenario_registry.gd
class_name ScenarioRegistry extends RefCounted

var _scenarios: Dictionary = {}  # StringName -> Dictionary

func register(id: StringName, def: Dictionary) -> void:
    _scenarios[id] = def

func has_scenario(id: StringName) -> bool:
    return _scenarios.has(id)

func get_scenario(id: StringName) -> Dictionary:
    if not _scenarios.has(id):
        return {}
    return _scenarios[id]

func ids() -> Array[StringName]:
    var result: Array[StringName] = []
    var keys: Array = _scenarios.keys()
    keys.sort()
    for k in keys:
        result.append(k)
    return result
```

- [ ] **Step 4: Run — pass.**

- [ ] **Step 5: Commit.**

```bash
git add engine/mod/scenario_registry.gd tests/unit/test_scenario_registry.gd
git commit -m "feat(mod): scenario registry"
```

---

## Task 3: ModLoader discovers scenarios

**Files:**
- Modify: `engine/mod/mod_loader.gd` (lines 84–120 region — next to species/objects loaders)
- Modify: `tests/unit/test_mod_loader.gd` (if exists) or create `tests/unit/test_mod_loader_scenarios.gd`

- [ ] **Step 1: Read existing ModLoader structure.**

Run: `cat engine/mod/mod_loader.gd | head -160`
Note the pattern: `_load_species_dir`, `_load_objects_dir` (exact names may differ — adapt to what's actually there).

- [ ] **Step 2: Write failing test.**

```gdscript
# tests/unit/test_mod_loader_scenarios.gd
extends GutTest

func test_scenarios_dir_discovered() -> void:
    var loader := ModLoader.new()
    var result := loader.load_all("res://mods/")
    var scenarios: ScenarioRegistry = result[&"scenarios"]
    assert_true(scenarios.has_scenario(&"tcp_base:starter"),
        "Expected tcp_base:starter scenario to be discovered")
```

- [ ] **Step 3: Run — FAIL** (starter.jsonc doesn't exist yet + loader doesn't scan scenarios/).

- [ ] **Step 4: Extend loader.**

In `engine/mod/mod_loader.gd`, after the existing species/objects discovery (around lines 84–120), add a scenarios block. Keep the exact format matching the existing dir loaders:

```gdscript
# engine/mod/mod_loader.gd — adapt to existing style
# Add to the result Dictionary returned by load_all:

func _load_scenarios_dir(mod_id: StringName, mod_path: String, registry: ScenarioRegistry, validator: ScenarioSchemaValidator) -> void:
    var scenarios_dir := mod_path.path_join("scenarios")
    if not DirAccess.dir_exists_absolute(scenarios_dir):
        return
    var dir := DirAccess.open(scenarios_dir)
    if dir == null:
        return
    dir.list_dir_begin()
    var filename := dir.get_next()
    while filename != "":
        if not dir.current_is_dir() and filename.ends_with(".jsonc"):
            var path := scenarios_dir.path_join(filename)
            var parsed := _parse_jsonc(path)
            if parsed.is_empty():
                push_error("scenario parse failed: %s" % path)
            elif not validator.is_valid(parsed):
                push_error("scenario invalid: %s" % path)
            else:
                var id: StringName = StringName(parsed["id"])
                registry.register(id, parsed)
        filename = dir.get_next()
    dir.list_dir_end()
```

Wire it into `load_all` by creating a `ScenarioRegistry` and `ScenarioSchemaValidator`, calling `_load_scenarios_dir(id, mod_path, registry, validator)` once per mod, and returning the registry under `&"scenarios"`.

- [ ] **Step 5: Create the starter scenario file so the test passes.**

(This is slightly out of order but necessary — the scenario registry discovery test needs a real file to find.)

```jsonc
// mods/tcp_base/scenarios/starter.jsonc
{
  "schema_version": 1,
  "id": "tcp_base:starter",
  "entities": [
    { "type": "tcp_base:hum_device",     "rack": 0, "slot": 0 },
    { "type": "tcp_base:tuna_dispenser", "rack": 2, "slot": 1 },
    {
      "type": "tcp_base:tuna_button",
      "rack": 2, "slot": 2,
      "dispenser_ref": { "rack": 2, "slot": 1 }
    },
    { "type": "tcp_base:arm", "floor_rack": 0, "floor_slot_offset": 0 },
    { "type": "tcp_cats:cat", "rack": 0, "slot": 7, "required": false },
    { "type": "tcp_cats:cat", "rack": 0, "slot": 8, "required": false }
  ]
}
```

- [ ] **Step 6: Run — PASS.**

- [ ] **Step 7: Commit.**

```bash
git add engine/mod/mod_loader.gd mods/tcp_base/scenarios/starter.jsonc tests/unit/test_mod_loader_scenarios.gd
git commit -m "feat(mod): discover scenarios/ dir; add tcp_base:starter"
```

---

## Task 4: WorldInitSystem — scenario population

**Files:**
- Create: `engine/core/world_init_system.gd`
- Create: `tests/unit/test_world_init_system.gd`

- [ ] **Step 1: Write the failing tests.**

```gdscript
# tests/unit/test_world_init_system.gd
extends GutTest

var _db: GameStateDB
var _entity_defs: EntityDefRegistry
var _scenarios: ScenarioRegistry
var _wis: WorldInitSystem

func before_each() -> void:
    _db = GameStateDB.new()
    _entity_defs = EntityDefRegistry.new()
    _scenarios = ScenarioRegistry.new()
    _register_fake_entity(&"mod:item", {"size_ru": 1, "placement": "rack"})
    _wis = WorldInitSystem.new(_db, _entity_defs, _scenarios)

func test_required_entity_spawns() -> void:
    _scenarios.register(&"mod:one", {
        "schema_version": 1,
        "id": "mod:one",
        "entities": [{"type": "mod:item", "rack": 0, "slot": 0}],
    })
    _wis.apply(&"mod:one")
    assert_eq(_db.entity_count(), 1, "Expected one entity spawned")

func test_missing_required_entity_aborts() -> void:
    _scenarios.register(&"mod:one", {
        "schema_version": 1,
        "id": "mod:one",
        "entities": [{"type": "absent:type", "rack": 0, "slot": 0}],
    })
    _wis.apply(&"mod:one")
    assert_eq(_db.entity_count(), 0, "Required entity failure must abort population")
    assert_push_error("world_init aborted")

func test_missing_optional_entity_skipped() -> void:
    _scenarios.register(&"mod:one", {
        "schema_version": 1,
        "id": "mod:one",
        "entities": [
            {"type": "mod:item", "rack": 0, "slot": 0},
            {"type": "absent:type", "rack": 0, "slot": 1, "required": false},
        ],
    })
    _wis.apply(&"mod:one")
    assert_eq(_db.entity_count(), 1, "Optional entity skipped, required still spawns")

func test_missing_scenario_aborts() -> void:
    _wis.apply(&"never:registered")
    assert_eq(_db.entity_count(), 0)
    assert_push_error("scenario not found")

func _register_fake_entity(id: StringName, def: Dictionary) -> void:
    var full: Dictionary = {"id": String(id), "schema_version": 1}
    full.merge(def)
    _entity_defs.register(id, full)
```

- [ ] **Step 2: Run — FAIL.**

- [ ] **Step 3: Implement.**

```gdscript
# engine/core/world_init_system.gd
class_name WorldInitSystem extends RefCounted

var _db: GameStateDB
var _entity_defs: EntityDefRegistry
var _scenarios: ScenarioRegistry

func _init(db: GameStateDB, entity_defs: EntityDefRegistry, scenarios: ScenarioRegistry) -> void:
    _db = db
    _entity_defs = entity_defs
    _scenarios = scenarios

func apply(scenario_id: StringName) -> void:
    if not _scenarios.has_scenario(scenario_id):
        push_error("world_init: scenario not found: %s" % scenario_id)
        return
    var def: Dictionary = _scenarios.get_scenario(scenario_id)
    var entities: Array = def.get("entities", [])
    # Two-pass: verify required entities resolve, then spawn.
    for entry in entities:
        var required: bool = entry.get("required", true)
        var type_id: StringName = StringName(entry["type"])
        if required and not _entity_defs.has(type_id):
            push_error("world_init aborted: required type missing: %s" % type_id)
            return
    for entry in entities:
        var type_id: StringName = StringName(entry["type"])
        if not _entity_defs.has(type_id):
            continue  # optional entity, silently skipped
        var overrides: Dictionary = _overrides_for(entry)
        _entity_defs.spawn(type_id, _db, overrides)

func _overrides_for(entry: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    if entry.has("rack"):
        out["rack"] = entry["rack"]
    if entry.has("slot"):
        out["slot"] = entry["slot"]
    if entry.has("floor_rack"):
        out["floor_rack"] = entry["floor_rack"]
    if entry.has("floor_slot_offset"):
        out["floor_slot_offset"] = entry["floor_slot_offset"]
    if entry.has("dispenser_ref"):
        out["dispenser_ref"] = entry["dispenser_ref"]
    return out
```

You will likely also need to add `has(id: StringName) -> bool` to `EntityDefRegistry` if it is not already there. Check `engine/mod/entity_def_registry.gd`; if absent, add:

```gdscript
func has(entity_id: StringName) -> bool:
    return _definitions.has(entity_id)
```

- [ ] **Step 4: Run — PASS.**

- [ ] **Step 5: Commit.**

```bash
git add engine/core/world_init_system.gd engine/mod/entity_def_registry.gd tests/unit/test_world_init_system.gd
git commit -m "feat(core): WorldInitSystem applies scenario definitions"
```

---

## Task 5: GameServer invokes WorldInitSystem on new game

**Files:**
- Modify: `nodes/game_server.gd` — replace `_spawn_starter_entities` (lines 583–638) with a scenario-driven path; keep the recipe-starters path intact as a fallback. Read `settings.starter_scenario_id` (defaults to `&"tcp_base:starter"`).
- Modify: `nodes/game_server.gd` — save payload: write `starter_scenario_applied: true` under `meta`; on load, read it back.

- [ ] **Step 1: Write the failing integration test.**

```gdscript
# tests/integration/test_phase0_smoke.gd (partial — first assertion)
extends GutTest

func test_new_game_populates_starter_scenario() -> void:
    var server := GameServer.new()
    add_child_autofree(server)
    await get_tree().process_frame
    # After init, expect: 1 HUM device, 1 TUNA dispenser, 1 TUNA button, 1 ARM, (+cats if tcp_cats loaded)
    var hums := server.db.get_entities_with(&"hum_receiver")
    var tunas := server.db.get_entities_with(&"tuna_dispenser")
    var arms := server.db.get_entities_with(&"arm")
    assert_eq(hums.size(), 1)
    assert_eq(tunas.size(), 1)
    assert_eq(arms.size(), 1)
```

- [ ] **Step 2: Run — FAIL.**

- [ ] **Step 3: Refactor GameServer._spawn_starter_entities.**

Replace the hardcoded pre-placed-object block with a call into `WorldInitSystem`. Sketch (adapt to actual code at lines 33–52 of `nodes/game_server.gd` for instantiation, 583–638 for starter body):

```gdscript
# in _ready(), near line ~40, after mod_loader registry creation:
var scenario_registry: ScenarioRegistry = _mod_load_result[&"scenarios"]
var world_init := WorldInitSystem.new(db, entity_defs, scenario_registry)
self._world_init = world_init

# in _spawn_starter_entities (or replace it entirely):
func _spawn_starter_entities() -> void:
    if _has_starter_been_applied():
        return
    var scenario_id: StringName = _settings.get("starter_scenario_id", &"tcp_base:starter")
    _world_init.apply(scenario_id)
    _mark_starter_applied()
    _events.robot_log.emit("Boot complete. Inventory shows pre-arranged devices. Continuing.")

func _has_starter_been_applied() -> bool:
    # For fresh starts without save data, return false. Persisted flag lives in save meta.
    return _db.has_component(Constants.FACILITY_ID, &"world_init_state") \
        and _db.get_field(Constants.FACILITY_ID, &"world_init_state", &"starter_applied") == 1

func _mark_starter_applied() -> void:
    _db.set_component(Constants.FACILITY_ID, &"world_init_state", {&"starter_applied": 1})
```

The recipe `starters` iteration (current lines 614–636) remains for pre-existing species starter entries — they still spawn, so today's Mochi/Biscuit/Noodle continue to appear. The scenario adds *additional* infrastructure. If the scenario should *replace* recipe starters, that's a separate design decision; for Phase 0 we add, not replace.

- [ ] **Step 4: Run — PASS.**

- [ ] **Step 5: Commit.**

```bash
git add nodes/game_server.gd tests/integration/test_phase0_smoke.gd
git commit -m "feat(game_server): scenario-driven starter population"
```

---

## Task 6: Settings + `debug.enabled` / `starter_scenario_id`

**Files:**
- Create or modify: `engine/core/settings.gd`
- Modify: `project.godot` (autoload section if Settings is autoloaded)

- [ ] **Step 1: Check whether a settings object already exists.**

Run: `find engine -name settings*.gd -o -name config*.gd | head -10`
If present, extend it. If absent, create a minimal one.

- [ ] **Step 2: Minimal settings.**

```gdscript
# engine/core/settings.gd
class_name Settings extends RefCounted

var debug_enabled: bool = false
var starter_scenario_id: StringName = &"tcp_base:starter"

func from_dict(src: Dictionary) -> void:
    if src.has("debug_enabled"):
        debug_enabled = bool(src["debug_enabled"])
    if src.has("starter_scenario_id"):
        starter_scenario_id = StringName(src["starter_scenario_id"])
```

Instantiate once on GameServer init; pass to WorldInitSystem for its scenario id read; pass to DebugHud gating.

- [ ] **Step 3: Commit.**

```bash
git add engine/core/settings.gd nodes/game_server.gd
git commit -m "feat(core): Settings with debug_enabled and starter_scenario_id"
```

---

## Task 7: Contentment honors debug override

**Files:**
- Modify: `engine/core/contentment.gd` (lines 15–27 — `evaluate_all`)
- Create: `tests/unit/test_contentment_debug_override.gd`

- [ ] **Step 1: Failing test.**

```gdscript
# tests/unit/test_contentment_debug_override.gd
extends GutTest

var _db: GameStateDB
var _c: Contentment

func before_each() -> void:
    _db = GameStateDB.new()
    _c = Contentment.new(_db)

func test_override_sets_satisfied_true_despite_low_desires() -> void:
    var id: int = _db.create_entity()
    _db.set_component(id, &"desires", {
        &"warmth": 100, &"comfort": 100, &"hunger": 100, &"attention": 100
    })
    _db.set_component(id, &"debug_force_satisfied", {&"active": 1})
    _c.evaluate_all()
    assert_eq(_db.get_field(id, &"contentment", &"is_satisfied"), 1,
        "Debug override must force is_satisfied = 1")

func test_no_override_follows_normal_rule() -> void:
    var id: int = _db.create_entity()
    _db.set_component(id, &"desires", {
        &"warmth": 100, &"comfort": 100, &"hunger": 100, &"attention": 100
    })
    _c.evaluate_all()
    assert_eq(_db.get_field(id, &"contentment", &"is_satisfied"), 0,
        "No override + all desires low => unsatisfied")

func test_override_removed_reverts_on_next_tick() -> void:
    var id: int = _db.create_entity()
    _db.set_component(id, &"desires", {
        &"warmth": 100, &"comfort": 100, &"hunger": 100, &"attention": 100
    })
    _db.set_component(id, &"debug_force_satisfied", {&"active": 1})
    _c.evaluate_all()
    _db.remove_component(id, &"debug_force_satisfied")
    _c.evaluate_all()
    assert_eq(_db.get_field(id, &"contentment", &"is_satisfied"), 0)
```

- [ ] **Step 2: Run — FAIL.**

- [ ] **Step 3: Modify `evaluate_all`.**

In `engine/core/contentment.gd`, inside the existing per-entity loop (around lines 18–25), check for the override before computing normally:

```gdscript
# engine/core/contentment.gd (inside evaluate_all's loop)
for entity_id in _db.get_entities_with(&"desires"):
    var is_satisfied: int = 0
    if _db.has_component(entity_id, &"debug_force_satisfied") and \
       _db.get_field(entity_id, &"debug_force_satisfied", &"active") == 1:
        is_satisfied = 1
    else:
        var count: int = 0
        for bar in BARS:
            if _db.get_field(entity_id, &"desires", bar) >= THRESHOLD:
                count += 1
        if count >= BARS_NEEDED:
            is_satisfied = 1
    _db.set_component(entity_id, &"contentment", {&"is_satisfied": is_satisfied})
    if is_satisfied == 1:
        _satisfied_count += 1
```

- [ ] **Step 4: Run — PASS.**

- [ ] **Step 5: Commit.**

```bash
git add engine/core/contentment.gd tests/unit/test_contentment_debug_override.gd
git commit -m "feat(contentment): honor debug_force_satisfied override"
```

---

## Task 8: Shift+F1 input action + DebugHud

**Files:**
- Modify: `project.godot` — add `debug_force_satisfied` action mapping Shift+F1.
- Create: `nodes/hud/debug_hud.gd`
- Modify: HUD scene tree to include `DebugHud` under the main HUD (e.g., `nodes/hud/hud.tscn` or equivalent).

- [ ] **Step 1: Add input action.**

In `project.godot`, under the `[input]` section (create the section if absent), add:

```
debug_force_satisfied={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":true,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":4194344,"physical_keycode":0,"key_label":0,"unicode":0,"echo":false,"script":null)
]
}
```

(Keycode `4194344` is F1; `shift_pressed: true` combines it. Godot may reserialize after first run — the above is a template.)

- [ ] **Step 2: Implement DebugHud.**

```gdscript
# nodes/hud/debug_hud.gd
class_name DebugHud extends Node

var _db: GameStateDB
var _settings: Settings
var _inspect_provider: Object  # something with get_inspected_id() -> int, or Constants.INVALID_ID

func initialize(db: GameStateDB, settings: Settings, inspect_provider: Object) -> void:
    _db = db
    _settings = settings
    _inspect_provider = inspect_provider

func _unhandled_input(event: InputEvent) -> void:
    if not _settings.debug_enabled:
        return
    if event.is_action_pressed("debug_force_satisfied"):
        _toggle_force_satisfied_on_inspected()

func _toggle_force_satisfied_on_inspected() -> void:
    var target_id: int = _get_target_id()
    if target_id == Constants.INVALID_ID:
        _toggle_all_contentment_bearers()
        return
    _toggle_one(target_id)

func _get_target_id() -> int:
    if _inspect_provider and _inspect_provider.has_method(&"get_inspected_id"):
        return _inspect_provider.get_inspected_id()
    return Constants.INVALID_ID

func _toggle_one(entity_id: int) -> void:
    if _db.has_component(entity_id, &"debug_force_satisfied") and \
       _db.get_field(entity_id, &"debug_force_satisfied", &"active") == 1:
        _db.remove_component(entity_id, &"debug_force_satisfied")
    else:
        _db.set_component(entity_id, &"debug_force_satisfied", {&"active": 1})

func _toggle_all_contentment_bearers() -> void:
    for id in _db.get_entities_with(&"desires"):
        _toggle_one(id)
```

- [ ] **Step 3: Wire into HUD scene tree.**

Add a `DebugHud` Node under the HUD (same level as other HUD children). In the HUD root's `_ready`:

```gdscript
# wherever the HUD assembles its children
var debug_hud := DebugHud.new()
debug_hud.name = "DebugHud"
add_child(debug_hud)
debug_hud.initialize(_game_server.db, _settings, _inspect_panel)
```

The `_inspect_panel` should expose a `get_inspected_id()` method; if it does not, add one returning `Constants.INVALID_ID` when nothing is inspected.

- [ ] **Step 4: Release-build assertion.**

In `DebugHud._ready()`:

```gdscript
func _ready() -> void:
    if OS.has_feature("editor") or OS.has_feature("debug"):
        return
    assert(not _settings.debug_enabled, "debug_enabled must be off in release builds")
```

- [ ] **Step 5: Commit.**

```bash
git add project.godot nodes/hud/debug_hud.gd nodes/hud/<hud_scene_file>.tscn
git commit -m "feat(hud): Shift+F1 debug_force_satisfied override"
```

---

## Task 9: End-to-end smoke integration test

**Files:**
- Modify: `tests/integration/test_phase0_smoke.gd` — extend with the debug override path.

- [ ] **Step 1: Extend test.**

```gdscript
# tests/integration/test_phase0_smoke.gd
extends GutTest

func test_debug_override_flips_is_satisfied() -> void:
    var db := GameStateDB.new()
    var c := Contentment.new(db)
    var id: int = db.create_entity()
    db.set_component(id, &"desires", {
        &"warmth": 100, &"comfort": 100, &"hunger": 100, &"attention": 100
    })
    c.evaluate_all()
    assert_eq(db.get_field(id, &"contentment", &"is_satisfied"), 0,
        "Pre-override: unsatisfied")
    # Simulate Shift+F1 handler body:
    db.set_component(id, &"debug_force_satisfied", {&"active": 1})
    c.evaluate_all()
    assert_eq(db.get_field(id, &"contentment", &"is_satisfied"), 1,
        "Post-override: satisfied")
```

- [ ] **Step 2: Run all tests.**

Run: `script/checks/gut_tests`
Expected: all green, no regressions.

- [ ] **Step 3: Run full validation.**

Run: `script/validate`
Expected: green.

- [ ] **Step 4: Manual smoke check.**

Run: `/Applications/Godot.app/Contents/MacOS/godot --path .`
Confirm: fresh game boots, HUM + TUNA + ARM + button present, cats visible, pressing Shift+F1 (with debug_enabled=true in settings) on an inspected cat flips the cat's `is_satisfied` visibly.

- [ ] **Step 5: Commit.**

```bash
git add tests/integration/test_phase0_smoke.gd
git commit -m "test: phase0 end-to-end smoke"
```

---

## Phase 0 Exit Criteria

- [ ] `script/validate` is green.
- [ ] New game boots into a world containing 1 HUM, 1 TUNA dispenser, 1 TUNA button, 1 ARM, and the existing cat starters.
- [ ] With `debug_enabled = true`, `Shift+F1` on an inspected contentment-bearing entity flips its `is_satisfied` (visible via inspect panel).
- [ ] Releasing the same key again removes the override (toggle).
- [ ] No regressions: existing unit / integration / scenario tests pass.
- [ ] `script/checks/verify_tests` passes (stamp tests per `.claude/rules/llm-test-verification.md`).

## STOP — clear context before Phase 1

Do NOT continue into `2026-04-17-hum-cable-phase1-per-hum-refactor.md` in the same session. Close the session, open a fresh one, and read that plan from scratch. The intentional boundary keeps each phase in a clean context window and shipping as its own green commit series.
