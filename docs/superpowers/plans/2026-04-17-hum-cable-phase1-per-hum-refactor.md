# HUM Cable — Phase 1 (Per-HUM Refactor) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **SPEC:** `docs/superpowers/specs/2026-04-17-hum-cable-hookup-design.md` (Phase 1 section).
>
> **PRECONDITION:** `2026-04-17-hum-cable-phase0-testability.md` is merged to `main` and green. Phase 0 provides the starter scenario and debug override that Phase 1 smoke tests rely on.
>
> **STOP / clear context between phases.** This is one of three plans. After Phase 1 is merged green, START A NEW SESSION before beginning Phase 2. Do not proceed into `2026-04-17-hum-cable-phase2-cable-system.md` in the same session.

**Goal:** Refactor HUM from a singleton (`FACILITY_ID` owns `hum` component, tick_charge counts satisfied animals directly) to per-HUM-device batteries charged by entities emitting on a new `&"purr"` channel. Establish the emit/listen architecture so future cable drain sites can target specific HUMs. Preserve existing gameplay: one HUM, one cat purring, lights stay on.

**Architecture:**
- `hum` component migrates from `FACILITY_ID` to each HUM device entity, capacity sourced from the recipe.
- New `&"purr"` component (`intensity: int`) on cats. Emitter is hardcoded to cats in Ring 1 — non-cat species get their own emission capabilities if/when they ship.
- Contentment→purr bridge runs each tick right after contentment, writing `purr.intensity = cat_recipe.purr.rate_when_satisfied` when `is_satisfied == 1`, else `0`. The bridge knows `contentment` and `purr`; it does not know HUM exists.
- `HumSystem.tick_charge()` iterates entities with `hum_receiver`, queries the radius, sums `purr.intensity` of in-range emitters (nearest-receiver assignment on overlap), credits the matching HUM's reserve. Does not read `contentment` or species labels.
- `HumSystem` public API (`charge`, `drain_action`, `drain_idle`, `has_reserve`, `get_reserve`, `get_capacity`, `get_reserve_ratio`) takes a `hum_id` parameter.
- `FoodSystem` calls get a temporary shim `_pick_hum_for(device_id) -> int` that returns the first HUM with reserve. Phase 2 replaces this shim with a `hum_cable` lookup.

**Tech Stack:** GDScript 4, Godot 4.6, GUT tests, existing GameStateDB column/row model (no new DB primitives).

---

## File Structure

| File | Create / Modify | Responsibility |
|---|---|---|
| `engine/core/hum_system.gd` | Modify | Stateless RefCounted. All public methods take `hum_id`. `tick_charge` reads `purr.intensity`. |
| `engine/core/contentment_purr_bridge.gd` | Create | RefCounted. `tick()` writes `purr.intensity` on contentment+purr entities. |
| `engine/core/food_system.gd` | Modify | `press_button` and `tick_arms` use `_pick_hum_for(device_id)` shim (replaced in Phase 2). |
| `mods/tcp_base/objects/hum_device.jsonc` | Modify | Add `"hum": {"capacity": 10000}` component to the recipe. |
| `engine/mod/entity_def_registry.gd` | Modify | Auto-materialize `hum` and `purr` components from recipe, matching existing `tends_servers` / `hum_receiver` pattern. |
| `mods/tcp_cats/species/cat.jsonc` | Modify | Add top-level `"purr": {"rate_when_satisfied": 10}` (sibling of existing `sounds.purr`). |
| `nodes/events.gd` | Modify | Add `hum_id: int` parameter to `hum_reserve_changed`, `hum_brownout_entered`, `hum_brownout_recovered`. |
| `nodes/game_server.gd` | Modify | Wire `ContentmentPurrBridge` into tick between contentment (step 4) and tick_charge (step 5). |
| `nodes/hud/hum_bar.gd` | Modify | Aggregate reserve/capacity across all HUMs on signal. |
| `engine/narrative/robot_narrator.gd` | Modify | Update any brownout/reserve subscribers to accept the new `hum_id` parameter and filter/aggregate as needed. |
| `tests/unit/test_hum_system.gd` | Modify | Update existing tests to the new API; add new Phase 1 tests. |
| `tests/unit/test_contentment_purr_bridge.gd` | Create | Bridge writes/clears intensity correctly. |
| `tests/unit/test_purr_schema_load.gd` | Create | Recipe-based materialization of `purr` component. |
| `tests/integration/test_hum_tick.gd` | Modify | Existing tests continue to pass against the new per-entity model. |
| `tests/integration/test_two_hums.gd` | Create | Independent batteries, nearest-receiver assignment. |

---

## Task 1: Add `purr` to the cat recipe (design-only edit)

**Files:**
- Modify: `mods/tcp_cats/species/cat.jsonc`

- [ ] **Step 1: Add top-level `purr` block.**

Open `mods/tcp_cats/species/cat.jsonc`. Find the top-level object. Insert (near the other top-level fields, not under `sounds`):

```jsonc
  "purr": {
    "rate_when_satisfied": 10
  },
```

The existing `sounds.purr: [...]` array is unrelated (it's the audio file list). The new top-level `purr` block is the emitter component config.

- [ ] **Step 2: Commit.**

```bash
git add mods/tcp_cats/species/cat.jsonc
git commit -m "feat(cats): declare purr emitter with rate_when_satisfied"
```

---

## Task 2: Auto-materialize `purr` component on cats at spawn

**Files:**
- Modify: `engine/mod/entity_def_registry.gd`
- Create: `tests/unit/test_purr_schema_load.gd`

- [ ] **Step 1: Failing test.**

```gdscript
# tests/unit/test_purr_schema_load.gd
extends GutTest

var _db: GameStateDB
var _reg: EntityDefRegistry

func before_each() -> void:
    _db = GameStateDB.new()
    _reg = EntityDefRegistry.new()

func test_purr_component_materialized_from_recipe() -> void:
    _reg.register(&"test:catlike", {
        "id": "test:catlike",
        "schema_version": 1,
        "size_ru": 1,
        "placement": "rack",
        "purr": {"rate_when_satisfied": 12},
    })
    var id: int = _reg.spawn(&"test:catlike", _db, {})
    assert_true(_db.has_component(id, &"purr"), "purr component should exist")
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 0,
        "purr.intensity starts at 0")

func test_species_without_purr_has_no_component() -> void:
    _reg.register(&"test:silent", {
        "id": "test:silent",
        "schema_version": 1,
        "size_ru": 1,
        "placement": "rack",
    })
    var id: int = _reg.spawn(&"test:silent", _db, {})
    assert_false(_db.has_component(id, &"purr"))
```

- [ ] **Step 2: Run — FAIL.**

- [ ] **Step 3: Extend `EntityDefRegistry.spawn` to materialize `purr`.**

Find the existing materialization block in `engine/mod/entity_def_registry.gd` (around line 162 for `tends_servers`). Add a parallel block for `purr`:

```gdscript
# In spawn(), alongside other component materializations:
if def.has("purr"):
    var purr_cfg: Dictionary = def["purr"]
    var rate: int = int(purr_cfg.get("rate_when_satisfied", 0))
    # Component fields are set via set_component to establish shape; intensity starts 0.
    # rate_when_satisfied is recipe metadata, not a runtime-tick field; store on a separate sibling component.
    db.set_component(id, &"purr", {&"intensity": 0})
    db.set_component(id, &"purr_config", {&"rate_when_satisfied": rate})
```

Why two components: `purr` is the per-tick broadcast value (hot path, read by HumSystem); `purr_config` is the per-species recipe snapshot (cold, read by the bridge once per tick to decide what intensity to write). Keeping them separate means the HumSystem never has to touch recipe-derived fields.

- [ ] **Step 4: Run — PASS.**

- [ ] **Step 5: Commit.**

```bash
git add engine/mod/entity_def_registry.gd tests/unit/test_purr_schema_load.gd
git commit -m "feat(mod): materialize purr + purr_config components from species recipe"
```

---

## Task 3: Add `hum` component to HUM device recipe

**Files:**
- Modify: `mods/tcp_base/objects/hum_device.jsonc`
- Modify: `engine/mod/entity_def_registry.gd` — materialize `hum` when present
- Create: `tests/unit/test_hum_device_spawn.gd`

- [ ] **Step 1: Update recipe.**

Add the `hum` component next to `hum_receiver`:

```jsonc
{
  "schema_version": 1,
  "id": "tcp_base:hum_device",
  "name": "HUM Device",
  "size_ru": 6,
  "placement": "rack",
  "hum": {
    "capacity": 10000
  },
  "hum_receiver": {
    "radius_ru": 4
  },
  "physical": { "mass": 20000, "size_ru": 6 },
  "advertisements": []
}
```

- [ ] **Step 2: Failing test.**

```gdscript
# tests/unit/test_hum_device_spawn.gd
extends GutTest

var _db: GameStateDB
var _reg: EntityDefRegistry

func before_each() -> void:
    _db = GameStateDB.new()
    _reg = EntityDefRegistry.new()
    _reg.register(&"tcp_base:hum_device", {
        "id": "tcp_base:hum_device",
        "schema_version": 1,
        "size_ru": 6,
        "placement": "rack",
        "hum": {"capacity": 10000},
        "hum_receiver": {"radius_ru": 4},
    })

func test_hum_device_spawns_with_full_reserve() -> void:
    var id: int = _reg.spawn(&"tcp_base:hum_device", _db, {"rack": 0, "slot": 0})
    assert_true(_db.has_component(id, &"hum"))
    assert_eq(_db.get_field(id, &"hum", &"capacity"), 10000)
    assert_eq(_db.get_field(id, &"hum", &"reserve"), 10000,
        "Fresh HUM device starts at full reserve")

func test_hum_device_has_receiver() -> void:
    var id: int = _reg.spawn(&"tcp_base:hum_device", _db, {"rack": 0, "slot": 0})
    assert_true(_db.has_component(id, &"hum_receiver"))
    assert_eq(_db.get_field(id, &"hum_receiver", &"radius_ru"), 4)
```

- [ ] **Step 3: Run — FAIL.**

- [ ] **Step 4: Extend spawn logic.**

In `engine/mod/entity_def_registry.gd`:

```gdscript
# In spawn(), add alongside other component materializations:
if def.has("hum"):
    var hum_cfg: Dictionary = def["hum"]
    var capacity: int = int(hum_cfg.get("capacity", HumSystem.DEFAULT_CAPACITY))
    db.set_component(id, &"hum", {&"reserve": capacity, &"capacity": capacity})
```

- [ ] **Step 5: Run — PASS.**

- [ ] **Step 6: Commit.**

```bash
git add mods/tcp_base/objects/hum_device.jsonc engine/mod/entity_def_registry.gd tests/unit/test_hum_device_spawn.gd
git commit -m "feat(hum): per-device hum component from recipe"
```

---

## Task 4: Contentment→purr bridge

**Files:**
- Create: `engine/core/contentment_purr_bridge.gd`
- Create: `tests/unit/test_contentment_purr_bridge.gd`

- [ ] **Step 1: Failing tests.**

```gdscript
# tests/unit/test_contentment_purr_bridge.gd
extends GutTest

var _db: GameStateDB
var _b: ContentmentPurrBridge

func before_each() -> void:
    _db = GameStateDB.new()
    _b = ContentmentPurrBridge.new(_db)

func test_satisfied_entity_writes_recipe_rate() -> void:
    var id: int = _db.create_entity()
    _db.set_component(id, &"contentment", {&"is_satisfied": 1})
    _db.set_component(id, &"purr", {&"intensity": 0})
    _db.set_component(id, &"purr_config", {&"rate_when_satisfied": 10})
    _b.tick()
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 10)

func test_unsatisfied_entity_writes_zero() -> void:
    var id: int = _db.create_entity()
    _db.set_component(id, &"contentment", {&"is_satisfied": 0})
    _db.set_component(id, &"purr", {&"intensity": 50})  # prior value
    _db.set_component(id, &"purr_config", {&"rate_when_satisfied": 10})
    _b.tick()
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 0,
        "Unsatisfied entity has intensity reset to 0")

func test_entity_without_contentment_is_untouched() -> void:
    var id: int = _db.create_entity()
    _db.set_component(id, &"purr", {&"intensity": 99})
    _db.set_component(id, &"purr_config", {&"rate_when_satisfied": 10})
    _b.tick()
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 99,
        "Non-contentment-bearing purr emitter keeps its intensity (bridge is guarded)")

func test_entity_without_purr_is_untouched() -> void:
    var id: int = _db.create_entity()
    _db.set_component(id, &"contentment", {&"is_satisfied": 1})
    _b.tick()
    assert_false(_db.has_component(id, &"purr"))

func test_bridge_does_not_read_species() -> void:
    # Black-box: contentment+purr+purr_config is sufficient; no species label required.
    var id: int = _db.create_entity()
    _db.set_component(id, &"contentment", {&"is_satisfied": 1})
    _db.set_component(id, &"purr", {&"intensity": 0})
    _db.set_component(id, &"purr_config", {&"rate_when_satisfied": 7})
    _b.tick()
    assert_eq(_db.get_field(id, &"purr", &"intensity"), 7)
```

- [ ] **Step 2: Run — FAIL.**

- [ ] **Step 3: Implement.**

```gdscript
# engine/core/contentment_purr_bridge.gd
class_name ContentmentPurrBridge extends RefCounted

var _db: GameStateDB

func _init(db: GameStateDB) -> void:
    _db = db

func tick() -> void:
    for entity_id in _db.get_entities_with(&"purr"):
        if not _db.has_component(entity_id, &"contentment"):
            continue
        if not _db.has_component(entity_id, &"purr_config"):
            continue
        var is_satisfied: int = _db.get_field(entity_id, &"contentment", &"is_satisfied")
        var rate: int = _db.get_field(entity_id, &"purr_config", &"rate_when_satisfied")
        var intensity: int = rate if is_satisfied == 1 else 0
        _db.set_field(entity_id, &"purr", &"intensity", intensity)
```

- [ ] **Step 4: Run — PASS.**

- [ ] **Step 5: Mutate to verify tests catch regressions.**

Change `if is_satisfied == 1 else 0` to `if is_satisfied == 0 else 0`. Run — expect `test_satisfied_entity_writes_recipe_rate` to fail. Revert.

- [ ] **Step 6: Commit.**

```bash
git add engine/core/contentment_purr_bridge.gd tests/unit/test_contentment_purr_bridge.gd
git commit -m "feat(core): contentment→purr bridge (satisfied emits recipe rate)"
```

---

## Task 5: HumSystem — refactor API to take `hum_id`

**Files:**
- Modify: `engine/core/hum_system.gd`
- Modify: `nodes/events.gd` — update signal signatures
- Modify: `tests/unit/test_hum_system.gd` — rewrite existing tests to the new API

**AI-DEV:** This task rewrites the core. Existing tests are scaffolding — they will fail and be rewritten. **If you are unsure whether a failing test is covered or abandoned, read the test name before editing, and verify the new version asserts the same behavior for the new API.**

- [ ] **Step 1: Update `Events` signal signatures.**

In `nodes/events.gd`, replace the existing HUM signals with:

```gdscript
# HUM — per-HUM signals carry hum_id
signal hum_reserve_changed(hum_id: int, old_reserve: int, new_reserve: int)
signal hum_brownout_entered(hum_id: int)
signal hum_brownout_recovered(hum_id: int)
```

- [ ] **Step 2: Rewrite HumSystem.**

Replace the file body with the per-entity implementation. Key points:
- `_init(db, events)` no longer creates FACILITY_ID's hum component. It just stores refs.
- All public methods take `hum_id`.
- `tick_charge` iterates `hum_receiver` entities and sums `purr.intensity` for entities within the receiver's radius. Assigns each emitter to its nearest receiver (entity id tiebreak).
- `tick_idle_drain` iterates all `hum` entities.

```gdscript
# engine/core/hum_system.gd
class_name HumSystem extends RefCounted

const DEFAULT_CAPACITY: int = 10000
const IDLE_DRAIN_BASE: int = 5
const BROWNOUT_THRESHOLD: int = 250  # ratio per 1000

var _db: GameStateDB
var _events: Object
var _brownout_active: Dictionary = {}  # hum_id: int -> bool

func _init(db: GameStateDB, events: Object = null) -> void:
    _db = db
    _events = events

func has_reserve(hum_id: int, cost: int) -> bool:
    if not _db.has_component(hum_id, &"hum"):
        return false
    return _db.get_field(hum_id, &"hum", &"reserve") >= cost

func get_reserve(hum_id: int) -> int:
    if not _db.has_component(hum_id, &"hum"):
        return 0
    return _db.get_field(hum_id, &"hum", &"reserve")

func get_capacity(hum_id: int) -> int:
    if not _db.has_component(hum_id, &"hum"):
        return 0
    return _db.get_field(hum_id, &"hum", &"capacity")

func get_reserve_ratio(hum_id: int) -> int:
    var cap: int = get_capacity(hum_id)
    if cap <= 0:
        return 0
    return get_reserve(hum_id) * 1000 / cap

func charge(hum_id: int, amount: int) -> void:
    assert(_db.has_component(hum_id, &"hum"), "charge() on non-HUM entity %d" % hum_id)
    if amount <= 0:
        return
    var old: int = get_reserve(hum_id)
    var cap: int = get_capacity(hum_id)
    var new_val: int = mini(cap, old + amount)
    _set_reserve(hum_id, old, new_val)

func drain_action(hum_id: int, cost: int) -> void:
    assert(_db.has_component(hum_id, &"hum"), "drain_action() on non-HUM entity %d" % hum_id)
    if cost <= 0:
        return
    var old: int = get_reserve(hum_id)
    var new_val: int = maxi(0, old - cost)
    _set_reserve(hum_id, old, new_val)

func drain_idle(hum_id: int) -> void:
    if not _db.has_component(hum_id, &"hum"):
        return
    var old: int = get_reserve(hum_id)
    var ratio: int = get_reserve_ratio(hum_id)
    var drain: int = maxi(1, IDLE_DRAIN_BASE * ratio / 1000)
    var new_val: int = maxi(0, old - drain)
    _set_reserve(hum_id, old, new_val)

func tick_idle_drain() -> void:
    for hum_id in _db.get_entities_with(&"hum"):
        drain_idle(hum_id)

func tick_charge() -> void:
    var receivers: Array[int] = _db.get_entities_with(&"hum_receiver")
    if receivers.is_empty():
        return
    var per_hum_charge: Dictionary = {}  # hum_id: int -> int
    # Assign each purr emitter to its nearest receiver (nearest by PU-squared distance).
    for emitter_id in _db.get_entities_with(&"purr"):
        var intensity: int = _db.get_field(emitter_id, &"purr", &"intensity")
        if intensity <= 0:
            continue
        var ex: int = _db.get_field(emitter_id, &"position", &"x")
        var ey: int = _db.get_field(emitter_id, &"position", &"y")
        var best_id: int = Constants.INVALID_ID
        var best_dist_sq: int = -1
        for r_id in receivers:
            var radius_ru: int = _db.get_field(r_id, &"hum_receiver", &"radius_ru")
            var radius_pu: int = radius_ru * Constants.RACK_WIDTH_PU  # verify correct conversion in project
            var rx: int = _db.get_field(r_id, &"position", &"x")
            var ry: int = _db.get_field(r_id, &"position", &"y")
            var dx: int = ex - rx
            var dy: int = ey - ry
            var dist_sq: int = dx * dx + dy * dy
            if dist_sq > radius_pu * radius_pu:
                continue
            if best_id == Constants.INVALID_ID or dist_sq < best_dist_sq or \
               (dist_sq == best_dist_sq and r_id < best_id):
                best_id = r_id
                best_dist_sq = dist_sq
        if best_id == Constants.INVALID_ID:
            continue
        per_hum_charge[best_id] = per_hum_charge.get(best_id, 0) + intensity
    for hum_id in per_hum_charge.keys():
        charge(hum_id, per_hum_charge[hum_id])

func _set_reserve(hum_id: int, old: int, new_val: int) -> void:
    if new_val == old:
        return
    _db.set_field(hum_id, &"hum", &"reserve", new_val)
    if _events:
        _events.hum_reserve_changed.emit(hum_id, old, new_val)
    _check_brownout(hum_id, old, new_val)

func _check_brownout(hum_id: int, old: int, new_val: int) -> void:
    var cap: int = get_capacity(hum_id)
    if cap <= 0:
        return
    var old_ratio: int = old * 1000 / cap
    var new_ratio: int = new_val * 1000 / cap
    var was_brown: bool = _brownout_active.get(hum_id, false)
    if not was_brown and new_ratio < BROWNOUT_THRESHOLD:
        _brownout_active[hum_id] = true
        if _events:
            _events.hum_brownout_entered.emit(hum_id)
    elif was_brown and new_ratio >= BROWNOUT_THRESHOLD:
        _brownout_active[hum_id] = false
        if _events:
            _events.hum_brownout_recovered.emit(hum_id)
```

- [ ] **Step 3: Rewrite the existing HumSystem tests against the new API.**

Open `tests/unit/test_hum_system.gd`. For every test:
- Replace `FACILITY_ID` references with a locally-created HUM entity.
- Pass `hum_id` to every API call.
- Update signal-capture helpers to the new three-arg / one-arg signatures.

Example of one migrated test:

```gdscript
# tests/unit/test_hum_system.gd (migration pattern)
func test_charge_adds_up_to_capacity() -> void:
    var db := GameStateDB.new()
    var sys := HumSystem.new(db)
    var hum_id: int = _make_hum(db)
    sys.drain_action(hum_id, 5000)  # reserve = 5000
    sys.charge(hum_id, 3000)
    assert_eq(sys.get_reserve(hum_id), 8000)

func _make_hum(db: GameStateDB, capacity: int = 10000) -> int:
    var id: int = db.create_entity()
    db.set_component(id, &"hum", {&"reserve": capacity, &"capacity": capacity})
    db.set_component(id, &"position", {&"x": 0, &"y": 0})
    db.set_component(id, &"hum_receiver", {&"radius_ru": 4})
    return id
```

Work through each existing test. Preserve the behavior assertions; only update the API surface. If a test refers to `FACILITY_ID` directly, replace it with a local HUM id.

- [ ] **Step 4: Run the unit tests.**

Run: `script/checks/gut_tests -f tests/unit/test_hum_system.gd`
Expected: all green against the new API.

- [ ] **Step 5: Commit.**

```bash
git add engine/core/hum_system.gd nodes/events.gd tests/unit/test_hum_system.gd
git commit -m "refactor(hum): per-entity API (hum_id on all methods)"
```

---

## Task 6: Phase 1 integration — two HUMs, independent charge

**Files:**
- Create: `tests/integration/test_two_hums.gd`

- [ ] **Step 1: Failing test.**

```gdscript
# tests/integration/test_two_hums.gd
extends GutTest

var _db: GameStateDB
var _sys: HumSystem

func before_each() -> void:
    _db = GameStateDB.new()
    _sys = HumSystem.new(_db)

func test_purr_near_hum_a_does_not_charge_hum_b() -> void:
    var a: int = _make_hum(0, 0)
    var b: int = _make_hum(50 * Constants.RACK_WIDTH_PU, 0)  # far away
    _drain(a, 5000)
    _drain(b, 5000)
    var cat: int = _make_purr_emitter(0, 0, 10)  # near A
    _sys.tick_charge()
    assert_eq(_sys.get_reserve(a), 5010, "HUM A charged by 10")
    assert_eq(_sys.get_reserve(b), 5000, "HUM B unchanged")

func test_nearest_receiver_tie_break_by_lower_id() -> void:
    var a: int = _make_hum(0, 0)
    var b: int = _make_hum(0, 0)  # same position
    _drain(a, 5000)
    _drain(b, 5000)
    _make_purr_emitter(0, 0, 7)
    _sys.tick_charge()
    assert_eq(_sys.get_reserve(a), 5007, "Lower id wins tie")
    assert_eq(_sys.get_reserve(b), 5000)

func _make_hum(x: int, y: int) -> int:
    var id: int = _db.create_entity()
    _db.set_component(id, &"hum", {&"reserve": 10000, &"capacity": 10000})
    _db.set_component(id, &"position", {&"x": x, &"y": y})
    _db.set_component(id, &"hum_receiver", {&"radius_ru": 10})
    return id

func _make_purr_emitter(x: int, y: int, intensity: int) -> int:
    var id: int = _db.create_entity()
    _db.set_component(id, &"position", {&"x": x, &"y": y})
    _db.set_component(id, &"purr", {&"intensity": intensity})
    return id

func _drain(id: int, amt: int) -> void:
    _sys.drain_action(id, amt)
```

- [ ] **Step 2: Run — expect PASS** (the refactor should already support this). If fail, debug the tick_charge assignment logic.

- [ ] **Step 3: Commit.**

```bash
git add tests/integration/test_two_hums.gd
git commit -m "test(hum): independent per-entity charge with nearest-receiver tiebreak"
```

---

## Task 7: Wire the bridge into GameServer tick order

**Files:**
- Modify: `nodes/game_server.gd`
- Modify: `tests/integration/test_tick_loop.gd` — update expected order

- [ ] **Step 1: Update the expected tick order in `test_tick_loop.gd`.**

Insert a new step between existing step 4 (contentment) and step 5 (hum_system.tick_charge):

```gdscript
# tests/integration/test_tick_loop.gd (excerpt)
const EXPECTED_ORDER: Array[StringName] = [
    &"advance_tick",
    &"heat_propagate",
    &"scatter_desires",
    &"contentment_evaluate",
    &"purr_bridge_tick",      # NEW
    &"hum_tick_charge",
    &"hum_drain_idle",
    # ... rest unchanged
]
```

- [ ] **Step 2: Run — FAIL** (the new step is in the contract but not wired).

- [ ] **Step 3: Wire in GameServer.**

In `nodes/game_server.gd`, inside `_physics_process`, after contentment (~line 89) and before tick_charge (~line 92):

```gdscript
# In game_server._physics_process, after contentment.evaluate_all():
_purr_bridge.tick()
```

In `_ready()` (or the constructor equivalent):

```gdscript
_purr_bridge = ContentmentPurrBridge.new(db)
```

- [ ] **Step 4: Run — PASS.**

- [ ] **Step 5: Commit.**

```bash
git add nodes/game_server.gd tests/integration/test_tick_loop.gd
git commit -m "feat(tick): purr bridge runs between contentment and tick_charge"
```

---

## Task 8: FoodSystem `_pick_hum_for` shim

**Files:**
- Modify: `engine/core/food_system.gd`
- Modify: `tests/unit/test_food_system.gd` (or wherever existing food tests live)

**Intent:** Phase 1's FoodSystem doesn't know about cables yet. Until Phase 2, drain the first available HUM. Phase 2 replaces this shim with a `hum_cable` lookup.

- [ ] **Step 1: Add the shim.**

```gdscript
# engine/core/food_system.gd — add near the top of the class

# AI-DEV: TEMPORARY SHIM. Phase 2 replaces this with a hum_cable-driven lookup.
# Do not make this the long-term API.
func _pick_hum_for(_device_id: int) -> int:
    for hum_id in _db.get_entities_with(&"hum"):
        if _hum.has_reserve(hum_id, 1):
            return hum_id
    return Constants.INVALID_ID
```

- [ ] **Step 2: Update `press_button` drain site.**

Find the existing `if not _hum.has_reserve(cost): return INVALID_ID` guard (around line 49–54) and the drain call (around line 57). Replace with:

```gdscript
var hum_id: int = _pick_hum_for(button_id)
if hum_id == Constants.INVALID_ID:
    return Constants.INVALID_ID
if not _hum.has_reserve(hum_id, cost):
    return Constants.INVALID_ID
_hum.drain_action(hum_id, cost)
```

- [ ] **Step 3: Update `tick_arms`.**

Similar pattern at the existing drain site (lines 93–109):

```gdscript
var hum_id: int = _pick_hum_for(arm_id)
if hum_id == Constants.INVALID_ID:
    continue
if not _hum.has_reserve(hum_id, cost):
    continue
_hum.drain_action(hum_id, cost)
```

- [ ] **Step 4: Run existing food tests.**

Run: `script/checks/gut_tests -f tests/unit/test_food_system.gd tests/integration/test_food_loop.gd`
Expected: all green (behavior unchanged in single-HUM scenario).

- [ ] **Step 5: Commit.**

```bash
git add engine/core/food_system.gd
git commit -m "feat(food): _pick_hum_for shim pending Phase 2 cable lookup"
```

---

## Task 9: HUM bar aggregates across HUMs

**Files:**
- Modify: `nodes/hud/hum_bar.gd`

**Current behavior (line 12–17 of `hum_bar.gd`):** subscribes to `hum_reserve_changed(old, new)` and renders a single bar.

**New behavior:** maintain a per-HUM dictionary `{hum_id -> {reserve, capacity}}`; on every `hum_reserve_changed(hum_id, old, new)` update the entry; render aggregate `sum(reserve) / sum(capacity)`.

- [ ] **Step 1: Rewrite.**

```gdscript
# nodes/hud/hum_bar.gd (core of the update)

var _per_hum: Dictionary = {}  # hum_id -> {reserve: int, capacity: int}

func initialize(events: Object, db: GameStateDB) -> void:
    # Populate initial snapshot from db (covers any HUMs already in play on load)
    for hum_id in db.get_entities_with(&"hum"):
        _per_hum[hum_id] = {
            &"reserve": db.get_field(hum_id, &"hum", &"reserve"),
            &"capacity": db.get_field(hum_id, &"hum", &"capacity"),
        }
    events.hum_reserve_changed.connect(_on_hum_reserve_changed)
    _refresh()

func _on_hum_reserve_changed(hum_id: int, _old: int, new_val: int) -> void:
    if _per_hum.has(hum_id):
        _per_hum[hum_id][&"reserve"] = new_val
    # If we've never seen this hum_id, ignore — capacity unknown without a db snapshot.
    _refresh()

func _refresh() -> void:
    var total_reserve: int = 0
    var total_capacity: int = 0
    for entry in _per_hum.values():
        total_reserve += int(entry[&"reserve"])
        total_capacity += int(entry[&"capacity"])
    var ratio: int = 0
    if total_capacity > 0:
        ratio = total_reserve * 1000 / total_capacity
    _render(ratio)

func _render(ratio: int) -> void:
    var fill_pct: float = float(ratio) / 1000.0
    _bar_fill.size.x = BAR_WIDTH * fill_pct
    if ratio >= 500:
        _bar_fill.color = Color(0.3, 0.8, 0.4)
    elif ratio >= 250:
        _bar_fill.color = Color(0.9, 0.7, 0.2)
    else:
        _bar_fill.color = Color(0.9, 0.2, 0.1)
    var pct: int = ratio / 10
    _reserve_label.text = "HUM: %d%%" % pct
    if ratio >= 500:
        _glyph_label.text = "O"
    elif ratio >= 250:
        _glyph_label.text = "^"
    else:
        _glyph_label.text = "!"
```

(This preserves the existing visual. The behavioral change is solely that `ratio` is now computed from aggregated reserve / capacity instead of a single entity's values.)

- [ ] **Step 2: Manual smoke check.**

Run: `/Applications/Godot.app/Contents/MacOS/godot --path .`
Expected: HUM bar renders correctly. Drain the HUM (trigger the TUNA button) and confirm the bar drops.

- [ ] **Step 3: Commit.**

```bash
git add nodes/hud/hum_bar.gd
git commit -m "feat(hud): HUM bar aggregates across all HUM entities"
```

---

## Task 10: Narrator subscriber updates

**Files:**
- Modify: `engine/narrative/robot_narrator.gd` (or wherever brownout/reserve subscriptions live)

- [ ] **Step 1: Find subscribers.**

Run: `rg -n "hum_brownout_entered|hum_brownout_recovered|hum_reserve_changed" --type gd`

For each subscriber, update the signal handler signature to the new form: `_on_hum_brownout_entered(hum_id: int)` etc. Current handlers likely have no parameters.

- [ ] **Step 2: Update log text minimally — aggregate-neutral.**

Phase 1's HUD shows aggregate reserve, but the narrator can still log per-HUM. Spec: `"carrier weakening at sector-A source. sector-B nominal. i am moving slowly only on devices bridged to A. apologies are localized."`

For Phase 1's single-HUM scenario, a simplified log suffices (same string today). Phase 2 expands this when cables create per-HUM-domain isolation.

Minimum change: handler signatures only. Log content stays as-is until Phase 2.

- [ ] **Step 3: Run — PASS.**

- [ ] **Step 4: Commit.**

```bash
git add engine/narrative/robot_narrator.gd
git commit -m "refactor(narrator): adopt hum_id-parameterized signal signatures"
```

---

## Task 11: Full Phase 1 regression + stamping

- [ ] **Step 1: Run full validation.**

Run: `script/validate`
Expected: green across `gdscript_compile`, `gdlint`, `gut_tests`, `no_secrets`, `no_species_dispatch`, `verify_tests`.

- [ ] **Step 2: Manual smoke test.**

Run: `/Applications/Godot.app/Contents/MacOS/godot --path .`
Confirm:
- Fresh game has one HUM device (from Phase 0 starter scenario).
- With `Shift+F1` forcing a cat satisfied, HUM bar visibly climbs (charge flowing through purr → receiver).
- Without the override and with the real pet chain still broken, bar slowly drains (idle) — this is expected; use the override to keep it topped up.

- [ ] **Step 3: Stamp all tests per `.claude/rules/llm-test-verification.md`.**

For every new or modified test file:

```bash
script/stamp_tests tests/unit/test_contentment_purr_bridge.gd
script/stamp_tests tests/unit/test_purr_schema_load.gd
script/stamp_tests tests/unit/test_hum_device_spawn.gd
script/stamp_tests tests/unit/test_hum_system.gd
script/stamp_tests tests/integration/test_two_hums.gd
script/stamp_tests tests/integration/test_tick_loop.gd
script/checks/verify_tests
```

Expected: all stamps valid, no orphans.

- [ ] **Step 4: Final commit (stamp sidecars only if not yet committed).**

```bash
git add tests/**/*.gd.stamp
git commit -m "test: stamp Phase 1 test verification hashes"
```

---

## Phase 1 Exit Criteria

- [ ] `script/validate` green.
- [ ] All Phase 1 unit / integration tests pass: `test_purr_schema_load`, `test_contentment_purr_bridge`, `test_hum_device_spawn`, `test_two_hums`, updated `test_hum_system`, updated `test_tick_loop`.
- [ ] `HumSystem` has **zero** references to `contentment`, `is_satisfied`, species labels, or `FACILITY_ID`.
- [ ] `ContentmentPurrBridge` has zero references to HUM.
- [ ] Existing TUNA/ARM food loop works unchanged in the starter scenario (only one HUM).
- [ ] HUM bar renders the aggregate reserve correctly.
- [ ] `script/checks/verify_tests` passes.

## STOP — clear context before Phase 2

Phase 2 introduces the cable system, MP pickup locks, rendering, narrator log lines, and the audio/sprite asset work. It is the largest of the three plans. Start it in a fresh session with `2026-04-17-hum-cable-phase2-cable-system.md`.
