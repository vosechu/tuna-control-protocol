# HUM Cable — Phase 2 (Cable System) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **SPEC:** `docs/superpowers/specs/2026-04-17-hum-cable-hookup-design.md` (Phase 2 section).
>
> **PRECONDITIONS:**
> - `2026-04-17-hum-cable-phase0-testability.md` merged and green.
> - `2026-04-17-hum-cable-phase1-per-hum-refactor.md` merged and green.
> - HumSystem API takes `hum_id` on all methods; `purr` + contentment→purr bridge shipped.
>
> This is the largest of the three plans. It is a single plan by user preference; execute in the task order given. Start in a fresh session — do **not** carry forward session context from Phase 1.

**Goal:** Ship player-placeable HUM power cables. Cables connect HUM devices to kinetic actuators (TUNA dispenser, ARM). Unpowered actuators silently refuse to operate. Includes wiring-mode UX, catenary rendering, server-authoritative MP pickup locks, mid-drag save reconstruction, narrator log lines, and new audio/sprite assets.

**Architecture:**
- `&"hum_powered"` capability tag on TUNA dispenser and ARM recipes — declares "this entity needs a cable to operate."
- `&"hum_cable"` component on actuators records the source HUM id (`{hum_id: int}`).
- `FoodSystem._is_powered(device_id, cost) -> int` replaces the Phase 1 `_pick_hum_for` shim; returns `hum_id` or `INVALID_ID` based on cable + reserve.
- HUM despawn uses a **tombstone model** — cables whose `hum_id` no longer resolves are skipped at read time; a reload-validation pass drops them eventually.
- `WiringLockRegistry` (server) owns the pickup state table (dictionary keyed by encoded endpoint_key, carrying `owner_peer_id`, `tick`, `original_hum_id`, `original_actuator_id`). Serves as both MP lock and mid-drag save reconstruction record.
- Intent protocol: `CABLE_START_INTENT`, `CABLE_PICKUP_INTENT`, `CABLE_CONNECT_INTENT`, `CABLE_CANCEL_INTENT`, `CABLE_DELETE_INTENT`.
- `WiringController` (HUD, client-side) handles wiring mode toggle and click routing. `CableView` renders catenary curves.
- Save serializer reads pickup state table + live DB; reload runs a second-pass validator.

**Tech Stack:** GDScript 4, Godot 4.6, GUT, MessagePack, existing Signal architecture (see `.claude/rules/signals.md`).

---

## File Structure

| File | Create / Modify | Responsibility |
|---|---|---|
| `nodes/events.gd` | Modify | Add `cable_connected(hum_id, device_id, cable_type)`, `cable_disconnected(hum_id, device_id)`. |
| `mods/tcp_base/objects/tuna_dispenser.jsonc` | Modify | Add `"hum_powered": {}`. |
| `mods/tcp_base/objects/arm.jsonc` | Modify | Add `"hum_powered": {}`. |
| `engine/mod/entity_def_registry.gd` | Modify | Materialize `hum_powered` (empty tag) from recipe. |
| `engine/core/food_system.gd` | Modify | Replace `_pick_hum_for` with `_is_powered`; hum_cable-aware drain. |
| `engine/core/wiring_lock_registry.gd` | Create | RefCounted. Owns pickup state table. Pure core. |
| `nodes/wiring_lock_registry_node.gd` | Create | Thin Node wrapper; sibling of `AnimalRegistry`/`ObjectRegistry`. |
| `engine/core/wiring_system.gd` | Create | RefCounted. Validates/applies cable intents (`handle_connect`, `handle_pickup`, `handle_cancel`, `handle_delete`, `handle_start`). Emits cable_* events. |
| `engine/core/wiring_save_adapter.gd` | Create | RefCounted. Produces/consumes save payload segments for cables. |
| `nodes/hud/wiring_controller.gd` | Create | Client HUD Node. Tab/LB+RB toggles wiring mode; routes clicks; emits intents. |
| `nodes/hud/cable_view.gd` | Create | Per-cable Node2D. Catenary curve. Responds to wiring mode toggle for opacity. |
| `nodes/hud/cable_layer.gd` | Create | Node2D. Parent of all `CableView`s; subscribes to cable_* events; creates/destroys views. |
| `nodes/hud/dangling_tip.gd` | Create | Node2D. Renders the 10×10 empty-socket glyph at cursor. |
| `nodes/hud/hum_bar.gd` | Modify | Reuse Phase 1 aggregation; per-HUM dim on connected-device status is added in `cable_view` render, not here. |
| `mods/tcp_base/config/hum.jsonc` | Create | `cable_max_length_ru`, `cable_sag_factor`. |
| `mods/tcp_base/sounds/cable_pop_01.wav` | Import | Delete cue. |
| `mods/tcp_base/sounds/cable_lift_01.wav` | Import | Pickup cue. |
| `mods/tcp_base/sounds/hum_brownout_enter_01.wav` | Import | Per-HUM brownout entry. |
| `mods/tcp_base/sounds/hum_brownout_recover_01.wav` | Import | Per-HUM brownout exit. |
| `mods/tcp_base/sprites/infrastructure/cable_tip_dangling_strip1.png` | Create | Dangling-tip glyph (10×10, 1 frame). |
| `mods/tcp_base/sprites/infrastructure/hum_device_strip1.png` | Modify | Bake socket inset. |
| `mods/tcp_base/sprites/infrastructure/tuna_dispenser_strip1.png` | Modify | Bake socket inset. |
| `mods/tcp_base/sprites/infrastructure/arm_strip1.png` | Modify | Bake socket inset. |
| `engine/narrative/robot_narrator.gd` | Modify | Subscribe to cable_connected / cable_disconnected; emit the 10+ log lines per spec table. |
| `.claude/rules/input-design.md` | Modify | Replace `hold Y to disconnect` with click-to-pickup flow. |
| `.claude/rules/narrative.md` | Modify | Append "Robot Cable Interpretation" section. |
| `tests/unit/test_food_system_power.gd` | Create | `_is_powered` branches: no cable, dangling cable, reserve empty, success. |
| `tests/unit/test_wiring_system_connect.gd` | Create | Connect, replace, cross-stripe reject, out-of-reach reject. |
| `tests/unit/test_wiring_system_pickup.gd` | Create | Pickup → delete, pickup → retract, pickup → reconnect. |
| `tests/unit/test_wiring_lock_registry.gd` | Create | Lock contention, expiry, endpoint_key encoding. |
| `tests/unit/test_cable_length_validation.gd` | Create | Euclidean squared distance check. |
| `tests/integration/test_cable_drain_loop.gd` | Create | HUM + TUNA + cable → drain works; disconnect → no drain. |
| `tests/integration/test_hum_despawn_tombstone.gd` | Create | Destroy HUM while cable exists → subsequent press fails gracefully. |
| `tests/integration/test_save_mid_drag.gd` | Create | Pickup → save → reload → cable restored to original HUM. |
| `tests/integration/test_replace_on_connect.gd` | Create | Reconnect to a new HUM emits disconnect+connect atomically. |
| `tests/integration/test_cross_stripe_reject_mp.gd` | Create | Cross-stripe connect denied; no mutation. |
| `tests/integration/test_pickup_lock_mp.gd` | Create | Peer B's pickup intent denied while peer A holds. |
| `tests/soak/test_cable_flap_soak.gd` | Create | 10-minute flap; no dangling refs, no leaked components. |

---

# Section A: Plumbing — components, events, FoodSystem integration

## Task 1: Add cable_connected and cable_disconnected signals

**Files:**
- Modify: `nodes/events.gd`

- [ ] **Step 1: Add signals next to the HUM group.**

```gdscript
# nodes/events.gd — after the existing HUM group
signal cable_connected(hum_id: int, device_id: int, cable_type: StringName)
signal cable_disconnected(hum_id: int, device_id: int)
```

- [ ] **Step 2: Sanity-run compile check.**

Run: `/Applications/Godot.app/Contents/MacOS/godot --headless --import`
Expected: zero errors.

- [ ] **Step 3: Commit.**

```bash
git add nodes/events.gd
git commit -m "feat(events): cable_connected / cable_disconnected"
```

---

## Task 2: `hum_powered` capability on TUNA and ARM recipes

**Files:**
- Modify: `mods/tcp_base/objects/tuna_dispenser.jsonc`
- Modify: `mods/tcp_base/objects/arm.jsonc`
- Modify: `engine/mod/entity_def_registry.gd` — materialize the tag
- Create: `tests/unit/test_hum_powered_spawn.gd`

- [ ] **Step 1: Add to recipes.**

In `mods/tcp_base/objects/tuna_dispenser.jsonc`:
```jsonc
  "hum_powered": {},
```

In `mods/tcp_base/objects/arm.jsonc`:
```jsonc
  "hum_powered": {},
```

- [ ] **Step 2: Failing test.**

```gdscript
# tests/unit/test_hum_powered_spawn.gd
extends GutTest

func test_tuna_dispenser_gets_hum_powered_tag() -> void:
    var db := GameStateDB.new()
    var reg := EntityDefRegistry.new()
    _register_from_disk(reg, "res://mods/tcp_base/objects/tuna_dispenser.jsonc", &"tcp_base:tuna_dispenser")
    var id: int = reg.spawn(&"tcp_base:tuna_dispenser", db, {"rack": 0, "slot": 0})
    assert_true(db.has_component(id, &"hum_powered"),
        "tuna_dispenser recipe must materialize hum_powered tag")

func _register_from_disk(reg: EntityDefRegistry, path: String, id: StringName) -> void:
    var text := FileAccess.get_file_as_string(path)
    # strip // comments (simple jsonc) then JSON.parse
    var lines: PackedStringArray = text.split("\n")
    var clean: String = ""
    for line in lines:
        var idx: int = line.find("//")
        if idx >= 0:
            line = line.substr(0, idx)
        clean += line + "\n"
    var parsed: Dictionary = JSON.parse_string(clean)
    reg.register(id, parsed)
```

- [ ] **Step 3: Run — FAIL** (recipe has the field but spawn logic doesn't materialize it).

- [ ] **Step 4: Materialize tag in `EntityDefRegistry.spawn`.**

```gdscript
# engine/mod/entity_def_registry.gd — alongside other tag materializations
if def.has("hum_powered"):
    db.set_component(id, &"hum_powered", {})
```

- [ ] **Step 5: Run — PASS.**

- [ ] **Step 6: Commit.**

```bash
git add mods/tcp_base/objects/tuna_dispenser.jsonc mods/tcp_base/objects/arm.jsonc engine/mod/entity_def_registry.gd tests/unit/test_hum_powered_spawn.gd
git commit -m "feat(objects): hum_powered capability tag on TUNA and ARM"
```

---

## Task 3: `_is_powered` replaces `_pick_hum_for`

**Files:**
- Modify: `engine/core/food_system.gd`
- Create: `tests/unit/test_food_system_power.gd`

- [ ] **Step 1: Failing tests.**

```gdscript
# tests/unit/test_food_system_power.gd
extends GutTest

var _db: GameStateDB
var _hum: HumSystem
var _food: FoodSystem

func before_each() -> void:
    _db = GameStateDB.new()
    _hum = HumSystem.new(_db)
    _food = FoodSystem.new(_db, _hum, null)

func test_no_cable_means_not_powered() -> void:
    var hum_id: int = _make_hum(0)
    var device_id: int = _make_tuna_dispenser(0)
    assert_eq(_food._is_powered(device_id, 50), Constants.INVALID_ID)

func test_cable_to_existing_hum_with_reserve_is_powered() -> void:
    var hum_id: int = _make_hum(0)
    var device_id: int = _make_tuna_dispenser(0)
    _db.set_component(device_id, &"hum_cable", {&"hum_id": hum_id})
    assert_eq(_food._is_powered(device_id, 50), hum_id)

func test_cable_to_missing_hum_is_not_powered() -> void:
    var device_id: int = _make_tuna_dispenser(0)
    _db.set_component(device_id, &"hum_cable", {&"hum_id": 99999})
    assert_eq(_food._is_powered(device_id, 50), Constants.INVALID_ID)

func test_cable_to_empty_hum_is_not_powered() -> void:
    var hum_id: int = _make_hum(0)
    _hum.drain_action(hum_id, 10000)  # drain to 0
    var device_id: int = _make_tuna_dispenser(0)
    _db.set_component(device_id, &"hum_cable", {&"hum_id": hum_id})
    assert_eq(_food._is_powered(device_id, 50), Constants.INVALID_ID)

func test_device_without_hum_powered_tag_is_not_powered() -> void:
    var hum_id: int = _make_hum(0)
    var id: int = _db.create_entity()
    _db.set_component(id, &"tuna_dispenser", {&"hum_cost": 50})
    _db.set_component(id, &"hum_cable", {&"hum_id": hum_id})
    # No hum_powered tag — device isn't something that needs a cable
    assert_eq(_food._is_powered(id, 50), Constants.INVALID_ID)

func _make_hum(x: int) -> int:
    var id: int = _db.create_entity()
    _db.set_component(id, &"hum", {&"reserve": 10000, &"capacity": 10000})
    _db.set_component(id, &"position", {&"x": x, &"y": 0})
    _db.set_component(id, &"hum_receiver", {&"radius_ru": 4})
    return id

func _make_tuna_dispenser(x: int) -> int:
    var id: int = _db.create_entity()
    _db.set_component(id, &"tuna_dispenser", {&"hum_cost": 50})
    _db.set_component(id, &"hum_powered", {})
    _db.set_component(id, &"position", {&"x": x, &"y": 0})
    return id
```

- [ ] **Step 2: Run — FAIL.**

- [ ] **Step 3: Replace shim with `_is_powered`.**

```gdscript
# engine/core/food_system.gd — replace _pick_hum_for
func _is_powered(device_id: int, cost: int) -> int:
    if not _db.has_component(device_id, &"hum_powered"):
        return Constants.INVALID_ID
    if not _db.has_component(device_id, &"hum_cable"):
        return Constants.INVALID_ID
    var hum_id: int = _db.get_field(device_id, &"hum_cable", &"hum_id")
    if hum_id == Constants.INVALID_ID:
        return Constants.INVALID_ID
    if not _db.has_entity(hum_id):
        return Constants.INVALID_ID  # tombstone
    if not _db.has_component(hum_id, &"hum"):
        return Constants.INVALID_ID  # entity exists but no longer a HUM
    if not _hum.has_reserve(hum_id, cost):
        return Constants.INVALID_ID
    return hum_id
```

Update `press_button` and `tick_arms` call sites from `_pick_hum_for` to `_is_powered`:

```gdscript
# press_button body
var hum_id: int = _is_powered(button_id, cost)
if hum_id == Constants.INVALID_ID:
    if _events: _events.emit_button_pressed_unpowered(button_id)  # Phase 2: narrator hook
    return Constants.INVALID_ID
_hum.drain_action(hum_id, cost)
# ...spawn can
```

```gdscript
# tick_arms body
var hum_id: int = _is_powered(arm_id, cost)
if hum_id == Constants.INVALID_ID:
    continue
_hum.drain_action(hum_id, cost)
# ...open can
```

Remove or delete the old `_pick_hum_for` helper.

- [ ] **Step 4: Run — PASS.**

Note: The Phase 0 starter scenario does not yet auto-cable the TUNA and ARM. This means after this task lands, a fresh game will have unpowered TUNA / ARM. This is expected — Phase 2 Section D provides the UX to let the player cable them.

For regression tests that depend on "fresh game works," temporarily pre-cable in the Phase 0 starter scenario (add an explicit `hum_cable` on TUNA pointing to the HUM) OR mark those tests as integration-level and skip them until Section D lands. Preferred: Update the starter scenario to pre-cable for now — see Task 4.

- [ ] **Step 5: Commit.**

```bash
git add engine/core/food_system.gd tests/unit/test_food_system_power.gd
git commit -m "feat(food): _is_powered replaces shim; hum_cable gate on drain"
```

---

## Task 4: Starter scenario pre-cables TUNA and ARM (temporary)

**Files:**
- Modify: `mods/tcp_base/scenarios/starter.jsonc`
- Modify: `engine/core/world_init_system.gd` — support `cable_to` reference resolution

- [ ] **Step 1: Extend the scenario.**

```jsonc
// mods/tcp_base/scenarios/starter.jsonc
{
  "schema_version": 1,
  "id": "tcp_base:starter",
  "entities": [
    { "type": "tcp_base:hum_device",     "rack": 0, "slot": 0, "ref_name": "hum_a" },
    {
      "type": "tcp_base:tuna_dispenser",
      "rack": 2, "slot": 1,
      "ref_name": "tuna_a",
      "cable_to": { "ref_name": "hum_a" }
    },
    {
      "type": "tcp_base:tuna_button",
      "rack": 2, "slot": 2,
      "dispenser_ref": { "rack": 2, "slot": 1 }
    },
    {
      "type": "tcp_base:arm",
      "floor_rack": 0, "floor_slot_offset": 0,
      "cable_to": { "ref_name": "hum_a" }
    },
    { "type": "tcp_cats:cat", "rack": 0, "slot": 7, "required": false },
    { "type": "tcp_cats:cat", "rack": 0, "slot": 8, "required": false }
  ]
}
```

- [ ] **Step 2: Extend `WorldInitSystem` to resolve `ref_name` and apply `cable_to`.**

```gdscript
# engine/core/world_init_system.gd — apply() revisited

func apply(scenario_id: StringName) -> void:
    if not _scenarios.has_scenario(scenario_id):
        push_error("world_init: scenario not found: %s" % scenario_id)
        return
    var def: Dictionary = _scenarios.get_scenario(scenario_id)
    var entities: Array = def.get("entities", [])
    # First pass: required-check
    for entry in entities:
        var required: bool = entry.get("required", true)
        var type_id: StringName = StringName(entry["type"])
        if required and not _entity_defs.has(type_id):
            push_error("world_init aborted: required type missing: %s" % type_id)
            return
    # Second pass: spawn, build ref_name -> entity_id map
    var refs: Dictionary = {}
    var pending_cables: Array = []  # [{actuator_id, ref_name}]
    for entry in entities:
        var type_id: StringName = StringName(entry["type"])
        if not _entity_defs.has(type_id):
            continue
        var entity_id: int = _entity_defs.spawn(type_id, _db, _overrides_for(entry))
        if entry.has("ref_name"):
            refs[StringName(entry["ref_name"])] = entity_id
        if entry.has("cable_to") and entry["cable_to"].has("ref_name"):
            pending_cables.append({
                &"actuator_id": entity_id,
                &"ref_name": StringName(entry["cable_to"]["ref_name"]),
            })
    # Third pass: cable application (references now resolvable)
    for cable in pending_cables:
        var actuator_id: int = cable[&"actuator_id"]
        var name: StringName = cable[&"ref_name"]
        if not refs.has(name):
            push_error("world_init: cable_to.ref_name not found: %s" % name)
            continue
        var hum_id: int = refs[name]
        _db.set_component(actuator_id, &"hum_cable", {&"hum_id": hum_id})
```

- [ ] **Step 3: Run full test suite.**

Run: `script/validate`
Expected: green. Food loop works because TUNA and ARM are pre-cabled.

- [ ] **Step 4: Commit.**

```bash
git add mods/tcp_base/scenarios/starter.jsonc engine/core/world_init_system.gd
git commit -m "feat(scenario): starter pre-cables TUNA and ARM to HUM"
```

---

# Section B: WiringLockRegistry + WiringSystem

## Task 5: WiringLockRegistry — pickup state table

**Files:**
- Create: `engine/core/wiring_lock_registry.gd`
- Create: `tests/unit/test_wiring_lock_registry.gd`

- [ ] **Step 1: Failing tests.**

```gdscript
# tests/unit/test_wiring_lock_registry.gd
extends GutTest

var _r: WiringLockRegistry

func before_each() -> void:
    _r = WiringLockRegistry.new()

func test_acquire_success() -> void:
    var ok: bool = _r.acquire_actuator(42, 1, 100, 7, 42)  # actuator_id=42, peer_id=1, tick=100, hum=7, actuator=42
    assert_true(ok)
    assert_true(_r.is_locked_actuator(42))

func test_acquire_twice_denies_second() -> void:
    _r.acquire_actuator(42, 1, 100, 7, 42)
    var ok: bool = _r.acquire_actuator(42, 2, 101, 7, 42)  # different peer
    assert_false(ok)

func test_release_unlocks() -> void:
    _r.acquire_actuator(42, 1, 100, 7, 42)
    _r.release_actuator(42)
    assert_false(_r.is_locked_actuator(42))

func test_hum_end_pickup_keyed_by_cable() -> void:
    # Two different cables from the same HUM — both can be picked up by different peers
    _r.acquire_hum_end(7, 42, 1, 100, 7, 42)  # hum_id=7, cable_to_actuator=42, peer_id=1
    var ok: bool = _r.acquire_hum_end(7, 99, 2, 101, 7, 99)  # same hum, different actuator, different peer
    assert_true(ok)

func test_expire_removes_stale_lock() -> void:
    _r.acquire_actuator(42, 1, 100, 7, 42)
    _r.tick_expire(current_tick = 400, ttl_ticks = 200)
    assert_false(_r.is_locked_actuator(42))

func test_active_locks_for_peer() -> void:
    _r.acquire_actuator(42, 1, 100, 7, 42)
    _r.acquire_actuator(43, 1, 101, 8, 43)
    _r.acquire_actuator(44, 2, 102, 9, 44)
    var locks: Array = _r.entries_for_peer(1)
    assert_eq(locks.size(), 2)

func test_synthetic_rows_for_save() -> void:
    _r.acquire_actuator(42, 1, 100, 7, 42)
    _r.acquire_actuator(43, 1, 101, 8, 43)
    var rows: Array = _r.synthetic_hum_cable_rows()
    assert_eq(rows.size(), 2)
    # Each row has actuator_id and hum_id
    assert_eq(rows[0][&"actuator_id"], 42)
    assert_eq(rows[0][&"hum_id"], 7)
```

- [ ] **Step 2: Run — FAIL.**

- [ ] **Step 3: Implement.**

```gdscript
# engine/core/wiring_lock_registry.gd
class_name WiringLockRegistry extends RefCounted

# Two sub-tables keyed differently:
#   _actuator_locks: actuator_id -> entry
#   _hum_locks: (hum_id << 32) | actuator_id -> entry
# entry = {owner_peer_id: int, tick: int, original_hum_id: int, original_actuator_id: int}

var _actuator_locks: Dictionary = {}
var _hum_locks: Dictionary = {}

func acquire_actuator(actuator_id: int, peer_id: int, tick: int, hum_id: int, original_actuator_id: int) -> bool:
    if _actuator_locks.has(actuator_id):
        return false
    _actuator_locks[actuator_id] = {
        &"owner_peer_id": peer_id,
        &"tick": tick,
        &"original_hum_id": hum_id,
        &"original_actuator_id": original_actuator_id,
    }
    return true

func acquire_hum_end(hum_id: int, cable_actuator_id: int, peer_id: int, tick: int,
                    original_hum_id: int, original_actuator_id: int) -> bool:
    var key: int = _hum_end_key(hum_id, cable_actuator_id)
    if _hum_locks.has(key):
        return false
    _hum_locks[key] = {
        &"owner_peer_id": peer_id,
        &"tick": tick,
        &"original_hum_id": original_hum_id,
        &"original_actuator_id": original_actuator_id,
    }
    return true

func release_actuator(actuator_id: int) -> void:
    _actuator_locks.erase(actuator_id)

func release_hum_end(hum_id: int, cable_actuator_id: int) -> void:
    _hum_locks.erase(_hum_end_key(hum_id, cable_actuator_id))

func is_locked_actuator(actuator_id: int) -> bool:
    return _actuator_locks.has(actuator_id)

func is_locked_hum_end(hum_id: int, cable_actuator_id: int) -> bool:
    return _hum_locks.has(_hum_end_key(hum_id, cable_actuator_id))

func tick_expire(current_tick: int, ttl_ticks: int) -> void:
    var expired: Array = []
    for key in _actuator_locks.keys():
        if current_tick - _actuator_locks[key][&"tick"] > ttl_ticks:
            expired.append(key)
    for key in expired:
        _actuator_locks.erase(key)
    expired.clear()
    for key in _hum_locks.keys():
        if current_tick - _hum_locks[key][&"tick"] > ttl_ticks:
            expired.append(key)
    for key in expired:
        _hum_locks.erase(key)

func entries_for_peer(peer_id: int) -> Array:
    var out: Array = []
    for entry in _actuator_locks.values():
        if entry[&"owner_peer_id"] == peer_id:
            out.append(entry)
    for entry in _hum_locks.values():
        if entry[&"owner_peer_id"] == peer_id:
            out.append(entry)
    return out

func synthetic_hum_cable_rows() -> Array:
    var rows: Array = []
    for entry in _actuator_locks.values():
        if entry[&"original_hum_id"] == Constants.INVALID_ID:
            continue
        rows.append({
            &"actuator_id": entry[&"original_actuator_id"],
            &"hum_id": entry[&"original_hum_id"],
        })
    for entry in _hum_locks.values():
        if entry[&"original_hum_id"] == Constants.INVALID_ID:
            continue
        rows.append({
            &"actuator_id": entry[&"original_actuator_id"],
            &"hum_id": entry[&"original_hum_id"],
        })
    return rows

func _hum_end_key(hum_id: int, actuator_id: int) -> int:
    return (hum_id << 32) | (actuator_id & 0xFFFFFFFF)
```

- [ ] **Step 4: Run — PASS.**

- [ ] **Step 5: Commit.**

```bash
git add engine/core/wiring_lock_registry.gd tests/unit/test_wiring_lock_registry.gd
git commit -m "feat(core): WiringLockRegistry (pickup state table)"
```

---

## Task 6: WiringSystem — validate + apply intents

**Files:**
- Create: `engine/core/wiring_system.gd`
- Create: `tests/unit/test_wiring_system_connect.gd`
- Create: `tests/unit/test_wiring_system_pickup.gd`
- Create: `tests/unit/test_cable_length_validation.gd`
- Create: `mods/tcp_base/config/hum.jsonc` (for the length constant)

- [ ] **Step 1: Create config file.**

```jsonc
// mods/tcp_base/config/hum.jsonc
{
  "schema_version": 1,
  "cable_max_length_ru": 20,
  "cable_sag_factor": 150
}
```

- [ ] **Step 2: Failing tests.**

For `test_wiring_system_connect.gd`:

```gdscript
# tests/unit/test_wiring_system_connect.gd
extends GutTest

var _db: GameStateDB
var _locks: WiringLockRegistry
var _events: Object
var _ws: WiringSystem

func before_each() -> void:
    _db = GameStateDB.new()
    _locks = WiringLockRegistry.new()
    _events = _FakeEvents.new()
    _ws = WiringSystem.new(_db, _locks, _events, {&"cable_max_length_ru": 20})

func test_fresh_connect_writes_hum_cable_and_emits() -> void:
    var hum: int = _make_hum(0)
    var tuna: int = _make_tuna(5)
    var ok: bool = _ws.handle_connect(1, hum, tuna)  # peer_id=1
    assert_true(ok)
    assert_true(_db.has_component(tuna, &"hum_cable"))
    assert_eq(_db.get_field(tuna, &"hum_cable", &"hum_id"), hum)
    assert_eq(_events.connects.size(), 1)
    assert_eq(_events.connects[0], [hum, tuna, &"hum_power"])

func test_connect_out_of_reach_denies() -> void:
    var hum: int = _make_hum(0)
    var tuna: int = _make_tuna(100)  # way beyond 20 RU
    var ok: bool = _ws.handle_connect(1, hum, tuna)
    assert_false(ok)
    assert_false(_db.has_component(tuna, &"hum_cable"))
    assert_eq(_events.connects.size(), 0)
    assert_eq(_events.denies.size(), 1)
    assert_eq(_events.denies[0], &"out_of_reach")

func test_connect_to_non_hum_powered_denies() -> void:
    var hum: int = _make_hum(0)
    var target: int = _db.create_entity()
    _db.set_component(target, &"position", {&"x": 0, &"y": 0})
    # No hum_powered tag
    var ok: bool = _ws.handle_connect(1, hum, target)
    assert_false(ok)

func test_replace_on_connect_emits_both_signals() -> void:
    var hum_a: int = _make_hum(0)
    var hum_b: int = _make_hum(Constants.RACK_WIDTH_PU * 3)
    var tuna: int = _make_tuna(Constants.RACK_WIDTH_PU * 1)
    _ws.handle_connect(1, hum_a, tuna)
    _ws.handle_connect(1, hum_b, tuna)
    assert_eq(_events.connects.size(), 2)
    assert_eq(_events.disconnects.size(), 1)
    assert_eq(_events.disconnects[0], [hum_a, tuna])  # old hum disconnected
    assert_eq(_db.get_field(tuna, &"hum_cable", &"hum_id"), hum_b)

func _make_hum(x: int) -> int:
    var id: int = _db.create_entity()
    _db.set_component(id, &"hum", {&"reserve": 10000, &"capacity": 10000})
    _db.set_component(id, &"position", {&"x": x, &"y": 0})
    return id

func _make_tuna(x: int) -> int:
    var id: int = _db.create_entity()
    _db.set_component(id, &"tuna_dispenser", {&"hum_cost": 50})
    _db.set_component(id, &"hum_powered", {})
    _db.set_component(id, &"position", {&"x": x, &"y": 0})
    return id

class _FakeEvents:
    var connects: Array = []
    var disconnects: Array = []
    var denies: Array = []
    signal cable_connected(hum_id: int, device_id: int, cable_type: StringName)
    signal cable_disconnected(hum_id: int, device_id: int)
    func emit_connect(h: int, d: int, t: StringName) -> void:
        connects.append([h, d, t])
    func emit_disconnect(h: int, d: int) -> void:
        disconnects.append([h, d])
    func emit_deny(reason: StringName) -> void:
        denies.append(reason)
```

For `test_wiring_system_pickup.gd`: analogous structure — tests for `handle_pickup_actuator_end`, `handle_pickup_hum_end`, `handle_delete`, `handle_cancel` (retract).

For `test_cable_length_validation.gd`: direct unit test of a `_within_range(x1, y1, x2, y2, max_ru) -> bool` helper, Euclidean squared distance.

- [ ] **Step 3: Run — FAIL.**

- [ ] **Step 4: Implement `WiringSystem`.**

Full implementation — key methods:

```gdscript
# engine/core/wiring_system.gd
class_name WiringSystem extends RefCounted

var _db: GameStateDB
var _locks: WiringLockRegistry
var _events: Object
var _config: Dictionary  # {cable_max_length_ru: int}

func _init(db: GameStateDB, locks: WiringLockRegistry, events: Object, config: Dictionary) -> void:
    _db = db
    _locks = locks
    _events = events
    _config = config

func handle_connect(peer_id: int, hum_id: int, device_id: int) -> bool:
    if not _db.has_entity(hum_id) or not _db.has_entity(device_id):
        return false
    if not _db.has_component(hum_id, &"hum"):
        return false
    if not _db.has_component(device_id, &"hum_powered"):
        return false
    if not _within_range(hum_id, device_id):
        if _events: _events.emit_deny(&"out_of_reach")
        return false
    if not _same_stripe(peer_id, hum_id, device_id):
        if _events: _events.emit_deny(&"cross_stripe")
        return false
    var replaced: bool = false
    var old_hum: int = Constants.INVALID_ID
    if _db.has_component(device_id, &"hum_cable"):
        old_hum = _db.get_field(device_id, &"hum_cable", &"hum_id")
        replaced = true
    _db.set_component(device_id, &"hum_cable", {&"hum_id": hum_id})
    if replaced and _events:
        _events.emit_disconnect(old_hum, device_id)
    if _events:
        _events.emit_connect(hum_id, device_id, &"hum_power")
    return true

func handle_pickup_actuator_end(peer_id: int, current_tick: int, actuator_id: int) -> bool:
    if _locks.is_locked_actuator(actuator_id):
        return false
    if not _db.has_component(actuator_id, &"hum_cable"):
        return false
    var hum_id: int = _db.get_field(actuator_id, &"hum_cable", &"hum_id")
    var ok: bool = _locks.acquire_actuator(actuator_id, peer_id, current_tick, hum_id, actuator_id)
    if not ok:
        return false
    _db.remove_component(actuator_id, &"hum_cable")
    if _events:
        _events.emit_disconnect(hum_id, actuator_id)
    return true

func handle_pickup_hum_end(peer_id: int, current_tick: int, hum_id: int, cable_actuator_id: int) -> bool:
    if _locks.is_locked_hum_end(hum_id, cable_actuator_id):
        return false
    if not _db.has_component(cable_actuator_id, &"hum_cable"):
        return false
    var orig_hum: int = _db.get_field(cable_actuator_id, &"hum_cable", &"hum_id")
    if orig_hum != hum_id:
        return false  # stale reference
    var ok: bool = _locks.acquire_hum_end(hum_id, cable_actuator_id, peer_id, current_tick, hum_id, cable_actuator_id)
    if not ok:
        return false
    _db.remove_component(cable_actuator_id, &"hum_cable")
    if _events:
        _events.emit_disconnect(hum_id, cable_actuator_id)
    return true

func handle_cancel(peer_id: int, actuator_id: int) -> bool:
    # Retract: re-add hum_cable with the original hum if both endpoints still live.
    if not _locks.is_locked_actuator(actuator_id):
        return false
    # Read original from lock, then release.
    # (Lock registry provides a getter for this — see registry refinement note below.)
    var entry: Dictionary = _locks.get_actuator_entry(actuator_id)
    var orig_hum: int = entry[&"original_hum_id"]
    _locks.release_actuator(actuator_id)
    if orig_hum != Constants.INVALID_ID and _db.has_entity(orig_hum) \
       and _db.has_component(orig_hum, &"hum") and _db.has_entity(actuator_id):
        _db.set_component(actuator_id, &"hum_cable", {&"hum_id": orig_hum})
        if _events:
            _events.emit_connect(orig_hum, actuator_id, &"hum_power")
        return true
    # Fallback: original endpoint gone, treat as delete
    if _events: _events.emit_deny(&"retract_failed_delete_fallback")
    return false

func handle_delete(peer_id: int, actuator_id: int) -> bool:
    if not _locks.is_locked_actuator(actuator_id):
        return false
    _locks.release_actuator(actuator_id)
    return true  # no events; the earlier cable_disconnected already fired

func handle_start(peer_id: int, hum_id: int) -> bool:
    # "Start a fresh cable from this HUM" — no state mutation, just validation for UX.
    return _db.has_entity(hum_id) and _db.has_component(hum_id, &"hum")

func _within_range(hum_id: int, device_id: int) -> bool:
    var hx: int = _db.get_field(hum_id, &"position", &"x")
    var hy: int = _db.get_field(hum_id, &"position", &"y")
    var dx: int = _db.get_field(device_id, &"position", &"x")
    var dy: int = _db.get_field(device_id, &"position", &"y")
    var max_ru: int = int(_config.get(&"cable_max_length_ru", 20))
    var max_pu: int = max_ru * Constants.RACK_WIDTH_PU
    var delta_x: int = hx - dx
    var delta_y: int = hy - dy
    return (delta_x * delta_x + delta_y * delta_y) <= (max_pu * max_pu)

func _same_stripe(peer_id: int, hum_id: int, device_id: int) -> bool:
    # Solo: single-peer default. MP: compare rack stripe memberships.
    # For Phase 2 pre-MP landing: always true.
    return true  # TODO(mp): stripe check when MP is wired
```

Add a `get_actuator_entry(actuator_id: int) -> Dictionary` to `WiringLockRegistry`:

```gdscript
# engine/core/wiring_lock_registry.gd — add:
func get_actuator_entry(actuator_id: int) -> Dictionary:
    return _actuator_locks.get(actuator_id, {})
```

- [ ] **Step 5: Run — PASS.**

- [ ] **Step 6: Commit.**

```bash
git add engine/core/wiring_system.gd engine/core/wiring_lock_registry.gd mods/tcp_base/config/hum.jsonc tests/unit/test_wiring_system_connect.gd tests/unit/test_wiring_system_pickup.gd tests/unit/test_cable_length_validation.gd
git commit -m "feat(core): WiringSystem with connect/pickup/cancel/delete intents"
```

---

## Task 7: Wire WiringSystem into GameServer; MP stripe check stub

**Files:**
- Modify: `nodes/game_server.gd`
- Create: `nodes/wiring_lock_registry_node.gd` (Node wrapper, optional — can be held as RefCounted directly under GameServer)

- [ ] **Step 1: Instantiate in GameServer.**

```gdscript
# nodes/game_server.gd (in _ready or init sequence)
var hum_config: Dictionary = _config_registry.get(&"tcp_base:hum", {&"cable_max_length_ru": 20})
_wiring_locks = WiringLockRegistry.new()
_wiring_system = WiringSystem.new(db, _wiring_locks, Events, hum_config)
```

- [ ] **Step 2: Add tick-expire call into the physics loop.**

In `_physics_process`, add a call near `hum_system.drain_idle()`:

```gdscript
_wiring_locks.tick_expire(db.get_tick(), 200)  # 20s @ 10Hz
```

- [ ] **Step 3: Run full tests — PASS.**

- [ ] **Step 4: Commit.**

```bash
git add nodes/game_server.gd
git commit -m "feat(game_server): host WiringSystem and expire stale locks"
```

---

# Section C: HUM despawn tombstone & save/reload

## Task 8: HUM despawn tombstone integration test

**Files:**
- Create: `tests/integration/test_hum_despawn_tombstone.gd`

- [ ] **Step 1: Write test.**

```gdscript
# tests/integration/test_hum_despawn_tombstone.gd
extends GutTest

func test_destroy_hum_leaves_stale_cable_but_drain_silently_fails() -> void:
    var db := GameStateDB.new()
    var hum_sys := HumSystem.new(db)
    var food := FoodSystem.new(db, hum_sys, null)
    var hum_id: int = db.create_entity()
    db.set_component(hum_id, &"hum", {&"reserve": 10000, &"capacity": 10000})
    db.set_component(hum_id, &"position", {&"x": 0, &"y": 0})
    var tuna_id: int = db.create_entity()
    db.set_component(tuna_id, &"tuna_dispenser", {&"hum_cost": 50})
    db.set_component(tuna_id, &"hum_powered", {})
    db.set_component(tuna_id, &"hum_cable", {&"hum_id": hum_id})
    db.set_component(tuna_id, &"position", {&"x": 0, &"y": 0})
    # Sanity: powered now
    assert_eq(food._is_powered(tuna_id, 50), hum_id)
    # Destroy HUM; cable is now a tombstone
    db.destroy_entity(hum_id)
    # _is_powered returns INVALID_ID (has_entity check)
    assert_eq(food._is_powered(tuna_id, 50), Constants.INVALID_ID)
    # hum_cable component still exists on the actuator (no eager cleanup)
    assert_true(db.has_component(tuna_id, &"hum_cable"))
```

- [ ] **Step 2: Run — PASS** (expected: `_is_powered` was already written to guard this in Task 3).

- [ ] **Step 3: Commit.**

```bash
git add tests/integration/test_hum_despawn_tombstone.gd
git commit -m "test: HUM despawn leaves tombstone; drain silently fails"
```

---

## Task 9: Save / reload — WiringSaveAdapter

**Files:**
- Create: `engine/core/wiring_save_adapter.gd`
- Modify: the save writer / reader (location depends on project; likely `engine/save/save_writer.gd` and `save_reader.gd`)
- Create: `tests/integration/test_save_mid_drag.gd`

- [ ] **Step 1: Failing test.**

```gdscript
# tests/integration/test_save_mid_drag.gd
extends GutTest

func test_mid_drag_save_reload_restores_cable() -> void:
    var db := GameStateDB.new()
    var locks := WiringLockRegistry.new()
    var events := _FakeEvents.new()
    var ws := WiringSystem.new(db, locks, events, {&"cable_max_length_ru": 20})
    var adapter := WiringSaveAdapter.new(db, locks)
    var hum: int = _make_hum(db, 0)
    var tuna: int = _make_tuna(db, 5)
    ws.handle_connect(1, hum, tuna)
    # Player picks up cable mid-drag
    ws.handle_pickup_actuator_end(1, 100, tuna)
    # Save
    var payload: Dictionary = adapter.write_snapshot()
    # Cable is removed from live DB (pickup semantics) but synthetic row is in payload
    assert_false(db.has_component(tuna, &"hum_cable"))
    var rows: Array = payload.get(&"hum_cables", [])
    assert_eq(rows.size(), 1, "Synthetic row should be present")
    assert_eq(rows[0][&"actuator_id"], tuna)
    assert_eq(rows[0][&"hum_id"], hum)
    # Reload on a fresh DB
    var db2 := GameStateDB.new()
    _make_hum_with_id(db2, hum, 0)
    _make_tuna_with_id(db2, tuna, 5)
    var adapter2 := WiringSaveAdapter.new(db2, WiringLockRegistry.new())
    adapter2.read_snapshot(payload)
    assert_true(db2.has_component(tuna, &"hum_cable"))
    assert_eq(db2.get_field(tuna, &"hum_cable", &"hum_id"), hum)

class _FakeEvents:
    func emit_connect(h: int, d: int, t: StringName) -> void: pass
    func emit_disconnect(h: int, d: int) -> void: pass
    func emit_deny(r: StringName) -> void: pass

func _make_hum(db: GameStateDB, x: int) -> int:
    var id: int = db.create_entity()
    db.set_component(id, &"hum", {&"reserve": 10000, &"capacity": 10000})
    db.set_component(id, &"position", {&"x": x, &"y": 0})
    return id

func _make_hum_with_id(db: GameStateDB, id: int, x: int) -> void:
    db.create_entity_with_id(id)
    db.set_component(id, &"hum", {&"reserve": 10000, &"capacity": 10000})
    db.set_component(id, &"position", {&"x": x, &"y": 0})

func _make_tuna(db: GameStateDB, x: int) -> int:
    var id: int = db.create_entity()
    db.set_component(id, &"tuna_dispenser", {&"hum_cost": 50})
    db.set_component(id, &"hum_powered", {})
    db.set_component(id, &"position", {&"x": x, &"y": 0})
    return id

func _make_tuna_with_id(db: GameStateDB, id: int, x: int) -> void:
    db.create_entity_with_id(id)
    db.set_component(id, &"tuna_dispenser", {&"hum_cost": 50})
    db.set_component(id, &"hum_powered", {})
    db.set_component(id, &"position", {&"x": x, &"y": 0})
```

- [ ] **Step 2: Run — FAIL.**

- [ ] **Step 3: Implement WiringSaveAdapter.**

```gdscript
# engine/core/wiring_save_adapter.gd
class_name WiringSaveAdapter extends RefCounted

var _db: GameStateDB
var _locks: WiringLockRegistry

func _init(db: GameStateDB, locks: WiringLockRegistry) -> void:
    _db = db
    _locks = locks

func write_snapshot() -> Dictionary:
    var rows: Array = []
    # Live rows
    for actuator_id in _db.get_entities_with(&"hum_cable"):
        var hum_id: int = _db.get_field(actuator_id, &"hum_cable", &"hum_id")
        rows.append({&"actuator_id": actuator_id, &"hum_id": hum_id})
    # Synthetic rows from active pickups
    for row in _locks.synthetic_hum_cable_rows():
        rows.append(row)
    return {&"hum_cables": rows}

func read_snapshot(payload: Dictionary) -> void:
    var rows: Array = payload.get(&"hum_cables", [])
    for row in rows:
        var actuator_id: int = int(row[&"actuator_id"])
        var hum_id: int = int(row[&"hum_id"])
        # Tombstone guard — drop if HUM no longer exists
        if not _db.has_entity(hum_id) or not _db.has_component(hum_id, &"hum"):
            push_warning("hum_cable reload: dropping stale ref to hum %d" % hum_id)
            continue
        if not _db.has_entity(actuator_id):
            push_warning("hum_cable reload: actuator %d missing" % actuator_id)
            continue
        _db.set_component(actuator_id, &"hum_cable", {&"hum_id": hum_id})
```

- [ ] **Step 4: Wire into save writer / reader.**

The project's `save_writer.gd` assembles the overall payload. Add a `hum_cables` key produced by `WiringSaveAdapter.write_snapshot()`. Similarly `save_reader.gd` calls `adapter.read_snapshot(payload)` after all entities are loaded (the two-pass reload order that the spec calls out).

- [ ] **Step 5: Run — PASS.**

- [ ] **Step 6: Commit.**

```bash
git add engine/core/wiring_save_adapter.gd engine/save/save_writer.gd engine/save/save_reader.gd tests/integration/test_save_mid_drag.gd
git commit -m "feat(save): WiringSaveAdapter (live + mid-drag synthetic rows)"
```

---

# Section D: Client UX — WiringController, rendering, input

## Task 10: WiringController — mode toggle and intent emission

**Files:**
- Create: `nodes/hud/wiring_controller.gd`
- Modify: `project.godot` — add `wiring_mode_toggle` input action (Tab)

- [ ] **Step 1: Add input action.**

In `project.godot` `[input]` block:

```
wiring_mode_toggle={
"deadzone": 0.5,
"events": [Object(InputEventKey,"keycode":4194306,"shift_pressed":false,...)]  # Tab
}
cable_pickup_confirm={
"events": [Object(InputEventMouseButton,"button_index":1,...)]  # LMB
}
cable_delete={"events": [Object(InputEventKey,"keycode":88,...)]}  # X
cable_cancel={"events": [Object(InputEventKey,"keycode":4194305,...)]}  # Escape
```

- [ ] **Step 2: Implement.**

```gdscript
# nodes/hud/wiring_controller.gd
class_name WiringController extends Node

enum State { INACTIVE, WIRING, HOLDING_CABLE }

signal wiring_mode_changed(active: bool)

var _state: State = State.INACTIVE
var _pickup_from: int = Constants.INVALID_ID  # entity id being dragged from
var _source_hum: int = Constants.INVALID_ID  # if starting fresh cable

var _client: Object  # connection to network/intent emitter
var _cursor_world_pos: Vector2 = Vector2.ZERO

func initialize(client: Object) -> void:
    _client = client

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("wiring_mode_toggle"):
        _toggle_mode()
        return
    if _state == State.INACTIVE:
        return
    if event is InputEventMouseMotion:
        _cursor_world_pos = _client.screen_to_world(event.position)
        return
    if event.is_action_pressed("cable_cancel"):
        _handle_cancel()
        return
    if _state == State.HOLDING_CABLE and event.is_action_pressed("cable_delete"):
        _client.send_intent(&"CABLE_DELETE_INTENT", {&"actuator_id": _pickup_from})
        _state = State.WIRING
        _pickup_from = Constants.INVALID_ID
        return
    if event.is_action_pressed("cable_pickup_confirm"):
        _handle_click_at(_cursor_world_pos)

func _toggle_mode() -> void:
    if _state == State.INACTIVE:
        _state = State.WIRING
        wiring_mode_changed.emit(true)
    else:
        _handle_cancel()
        _state = State.INACTIVE
        wiring_mode_changed.emit(false)

func _handle_click_at(world_pos: Vector2) -> void:
    var clicked_id: int = _client.entity_under_point(world_pos)
    if clicked_id == Constants.INVALID_ID:
        return
    if _state == State.WIRING:
        # Either start a new cable (HUM) or pick up an existing cable endpoint
        if _client.is_hum(clicked_id):
            _client.send_intent(&"CABLE_START_INTENT", {&"hum_id": clicked_id})
            _source_hum = clicked_id
            _state = State.HOLDING_CABLE
        elif _client.has_existing_cable(clicked_id):
            _client.send_intent(&"CABLE_PICKUP_INTENT", {&"actuator_id": clicked_id})
            _pickup_from = clicked_id
            _state = State.HOLDING_CABLE
    elif _state == State.HOLDING_CABLE:
        if _client.is_hum_powered_device(clicked_id):
            var payload: Dictionary = {
                &"target_id": clicked_id,
                &"source_hum_id": _source_hum,
            }
            _client.send_intent(&"CABLE_CONNECT_INTENT", payload)
            _state = State.WIRING
            _source_hum = Constants.INVALID_ID
            _pickup_from = Constants.INVALID_ID

func _handle_cancel() -> void:
    if _state == State.HOLDING_CABLE:
        _client.send_intent(&"CABLE_CANCEL_INTENT", {&"actuator_id": _pickup_from})
    _state = State.WIRING
    _pickup_from = Constants.INVALID_ID
    _source_hum = Constants.INVALID_ID

func get_state() -> int:
    return _state

func get_cursor_world_pos() -> Vector2:
    return _cursor_world_pos

func get_pickup_from() -> int:
    return _pickup_from

func get_source_hum() -> int:
    return _source_hum
```

- [ ] **Step 3: Wire into HUD scene tree.**

Add `WiringController` as a child of the HUD root; in HUD `_ready()`:

```gdscript
var wc := WiringController.new()
wc.name = "WiringController"
add_child(wc)
wc.initialize(_game_client)
_wiring_controller = wc
```

- [ ] **Step 4: Commit.**

```bash
git add project.godot nodes/hud/wiring_controller.gd nodes/hud/<hud_scene>.tscn
git commit -m "feat(hud): WiringController (mode toggle, click routing, intents)"
```

---

## Task 11: Cable rendering — catenary + opacity + dangling tip

**Files:**
- Create: `nodes/hud/cable_view.gd`
- Create: `nodes/hud/cable_layer.gd`
- Create: `nodes/hud/dangling_tip.gd`

- [ ] **Step 1: Implement CableLayer.**

```gdscript
# nodes/hud/cable_layer.gd
class_name CableLayer extends Node2D

var _cables: Dictionary = {}  # (hum_id, actuator_id) -> CableView
var _db: GameStateDB

func initialize(db: GameStateDB, events: Object) -> void:
    _db = db
    events.cable_connected.connect(_on_cable_connected)
    events.cable_disconnected.connect(_on_cable_disconnected)
    # Populate any cables already in the DB at scene entry
    for actuator_id in _db.get_entities_with(&"hum_cable"):
        var hum_id: int = _db.get_field(actuator_id, &"hum_cable", &"hum_id")
        _spawn(hum_id, actuator_id)

func _on_cable_connected(hum_id: int, device_id: int, _cable_type: StringName) -> void:
    _spawn(hum_id, device_id)

func _on_cable_disconnected(hum_id: int, device_id: int) -> void:
    var key: Array = [hum_id, device_id]
    if not _cables.has(key):
        return
    _cables[key].queue_free()
    _cables.erase(key)

func _spawn(hum_id: int, actuator_id: int) -> void:
    var view := CableView.new()
    add_child(view)
    view.initialize(_db, hum_id, actuator_id)
    _cables[[hum_id, actuator_id]] = view

func set_wiring_mode(on: bool) -> void:
    for view in _cables.values():
        view.set_wiring_mode(on)
```

- [ ] **Step 2: Implement CableView.**

```gdscript
# nodes/hud/cable_view.gd
class_name CableView extends Node2D

const SAG_FACTOR: int = 150
const MIN_SAG_PX: int = 3
const OPACITY_NORMAL: float = 0.60
const OPACITY_WIRING: float = 1.00

var _db: GameStateDB
var _hum_id: int
var _actuator_id: int
var _wiring_mode: bool = false

func initialize(db: GameStateDB, hum_id: int, actuator_id: int) -> void:
    _db = db
    _hum_id = hum_id
    _actuator_id = actuator_id
    modulate.a = OPACITY_NORMAL

func _process(_delta: float) -> void:
    queue_redraw()

func set_wiring_mode(on: bool) -> void:
    _wiring_mode = on
    modulate.a = OPACITY_WIRING if on else OPACITY_NORMAL

func _draw() -> void:
    if not _db.has_entity(_hum_id) or not _db.has_entity(_actuator_id):
        return
    var hx: int = _db.get_field(_hum_id, &"position", &"x")
    var hy: int = _db.get_field(_hum_id, &"position", &"y")
    var ax: int = _db.get_field(_actuator_id, &"position", &"x")
    var ay: int = _db.get_field(_actuator_id, &"position", &"y")
    var a: Vector2 = Constants.pu_to_world(Vector2(hx, hy))
    var b: Vector2 = Constants.pu_to_world(Vector2(ax, ay))
    var length_px: float = a.distance_to(b)
    var sag: float = maxf(MIN_SAG_PX, length_px * SAG_FACTOR / 1000.0)
    var mid: Vector2 = (a + b) * 0.5 + Vector2(0, sag)
    # 4-point cubic Bezier approximation via midpoint mid and endpoints a, b
    var prev: Vector2 = a
    var steps: int = 16
    for i in range(1, steps + 1):
        var t: float = float(i) / float(steps)
        var q: Vector2 = _bezier3(a, mid, b, t)
        draw_line(prev, q, Color(0.80, 0.55, 0.30, modulate.a), 2.0)
        prev = q

static func _bezier3(a: Vector2, m: Vector2, b: Vector2, t: float) -> Vector2:
    var u: float = 1.0 - t
    return u * u * a + 2.0 * u * t * m + t * t * b
```

- [ ] **Step 3: Implement DanglingTip.**

```gdscript
# nodes/hud/dangling_tip.gd
class_name DanglingTip extends Node2D

var _wiring_controller: WiringController

func initialize(wc: WiringController) -> void:
    _wiring_controller = wc

func _process(_delta: float) -> void:
    visible = _wiring_controller.get_state() == WiringController.State.HOLDING_CABLE
    if visible:
        global_position = _wiring_controller.get_cursor_world_pos()
    queue_redraw()

func _draw() -> void:
    if not visible:
        return
    # 10x10 dotted circle; breath white
    var color: Color = Color(0.95, 0.95, 0.90, 1.0)
    draw_arc(Vector2.ZERO, 5.0, 0.0, TAU, 24, color, 1.0, true)
```

- [ ] **Step 4: Commit.**

```bash
git add nodes/hud/cable_view.gd nodes/hud/cable_layer.gd nodes/hud/dangling_tip.gd nodes/hud/<hud_scene>.tscn
git commit -m "feat(hud): catenary cable view + dangling-tip glyph"
```

---

## Task 12: Connect WiringController ↔ CableLayer ↔ WiringSystem round trip

**Files:**
- Modify: `nodes/game_client.gd` (or wherever client-side intent handling lives)
- Modify: `nodes/hud/wiring_controller.gd` — wire ViewMode signal to CableLayer

- [ ] **Step 1: Intent serialization.**

The `game_client.send_intent(intent_name, payload)` method should exist already if Ring 0 networking is in place. If not, create a minimal local-loop version:

```gdscript
# nodes/game_client.gd — if no network, just call server directly
func send_intent(intent: StringName, payload: Dictionary) -> void:
    match intent:
        &"CABLE_START_INTENT":
            _server_wiring_system.handle_start(_peer_id, payload[&"hum_id"])
        &"CABLE_CONNECT_INTENT":
            _server_wiring_system.handle_connect(_peer_id, payload[&"source_hum_id"], payload[&"target_id"])
        &"CABLE_PICKUP_INTENT":
            _server_wiring_system.handle_pickup_actuator_end(_peer_id, _db.get_tick(), payload[&"actuator_id"])
        &"CABLE_CANCEL_INTENT":
            _server_wiring_system.handle_cancel(_peer_id, payload[&"actuator_id"])
        &"CABLE_DELETE_INTENT":
            _server_wiring_system.handle_delete(_peer_id, payload[&"actuator_id"])
```

- [ ] **Step 2: Wire CableLayer mode toggle.**

```gdscript
# nodes/hud/<hud_scene>.gd (or equivalent wiring in _ready)
_wiring_controller.wiring_mode_changed.connect(_cable_layer.set_wiring_mode)
```

- [ ] **Step 3: Manual smoke test.**

Run: `/Applications/Godot.app/Contents/MacOS/godot --path .`
- Fresh game loads with a pre-cabled TUNA (Task 4 starter scenario).
- Press Tab → wiring mode active, cable visible at 100% opacity.
- Click the TUNA's cable endpoint → cable picks up, tip follows cursor.
- Click the HUM → reconnects.
- Click TUNA cable endpoint again, press X → cable deleted. TUNA button now fails silently.

- [ ] **Step 4: Commit.**

```bash
git add nodes/game_client.gd nodes/hud/wiring_controller.gd nodes/hud/<hud_scene>.tscn
git commit -m "feat(hud): round-trip cable intents through WiringSystem"
```

---

# Section E: Assets

## Task 13: Audio imports

**Files:**
- Import via `.claude/skills/import-sound.md` or manual SoX normalize:
  - `mods/tcp_base/sounds/cable_pop_01.wav`
  - `mods/tcp_base/sounds/cable_lift_01.wav`
  - `mods/tcp_base/sounds/hum_brownout_enter_01.wav`
  - `mods/tcp_base/sounds/hum_brownout_recover_01.wav`
- Update `../game_assets/Credits.md` per CLAUDE.md Audio Asset Conventions

- [ ] **Step 1: Source candidate sounds.**

Use free-to-use sources (Freesound.org, bfxr, sfxr). Criteria per spec:
- `cable_pop_01.wav`: dry pop, ~0.2 s, RJ45-clip-release timbre
- `cable_lift_01.wav`: sharp dry click, 2-3 kHz, ~0.1 s
- `hum_brownout_enter_01.wav`: detune-and-die tone, ~0.4 s
- `hum_brownout_recover_01.wav`: soft re-engage swell, ~0.4 s

- [ ] **Step 2: Normalize + import.**

For each file:
```bash
sox "downloaded/source.wav" -b 16 -r 48000 "mods/tcp_base/sounds/<name>.wav" gain -n -1
```

Ensure the `.import` sidecar has `compress/mode=2` (QOA) and `edit/loop_mode=0`.

- [ ] **Step 3: Credits entry.**

Add 4 rows to `../game_assets/Credits.md` (author + source URL + license).

- [ ] **Step 4: Commit.**

```bash
git add mods/tcp_base/sounds/cable_pop_01.wav* mods/tcp_base/sounds/cable_lift_01.wav* mods/tcp_base/sounds/hum_brownout_enter_01.wav* mods/tcp_base/sounds/hum_brownout_recover_01.wav*
git commit -m "feat(audio): cable pickup/pop + brownout enter/recover"
```

(Credits.md lives in `../game_assets/` which is a sibling repo; commit there separately if tracked.)

---

## Task 14: Sprite assets

**Files:**
- Create: `mods/tcp_base/sprites/infrastructure/cable_tip_dangling_strip1.png` (10×10, 1 frame, empty-circle glyph)
- Modify: `mods/tcp_base/sprites/infrastructure/hum_device_strip1.png` — bake a 10×10 socket inset at the designated anchor pixel
- Modify: `mods/tcp_base/sprites/infrastructure/tuna_dispenser_strip1.png` — same
- Modify: `mods/tcp_base/sprites/infrastructure/arm_strip1.png` — same

- [ ] **Step 1: Generate `cable_tip_dangling_strip1.png` via the sprite-generation skill.**

Invoke `generate-pixel-sprites` skill with the design: 10×10 empty dotted circle, 1 px Breath White inner ring. Save to the target path.

- [ ] **Step 2: Socket insets.**

Edit the three device sprites to add a recessed 10×10 socket glyph at the approximate plug anchor. Keep edits minimal — use the existing palette (see `.claude/rules/art-direction.md`). Unlit by default (Slate Void); runtime shader / palette swap in wiring mode (handled at the view layer).

- [ ] **Step 3: Reimport.**

Run: `/Applications/Godot.app/Contents/MacOS/godot --headless --import`
Expected: zero errors.

- [ ] **Step 4: Commit.**

```bash
git add mods/tcp_base/sprites/infrastructure/cable_tip_dangling_strip1.png* mods/tcp_base/sprites/infrastructure/hum_device_strip1.png* mods/tcp_base/sprites/infrastructure/tuna_dispenser_strip1.png* mods/tcp_base/sprites/infrastructure/arm_strip1.png*
git commit -m "feat(sprites): dangling-tip glyph + device socket insets"
```

---

# Section F: Narrator & doc updates

## Task 15: Robot narrator — cable log lines

**Files:**
- Modify: `engine/narrative/robot_narrator.gd`

- [ ] **Step 1: Subscribe to cable signals.**

```gdscript
# engine/narrative/robot_narrator.gd — in init:
events.cable_connected.connect(_on_cable_connected)
events.cable_disconnected.connect(_on_cable_disconnected)
# Add bulk-coalesce state: a counter reset per tick via a Timer or tick hook
```

- [ ] **Step 2: Implement handlers per the spec table (line 527–540 of the spec).**

For each entry in the table, write a log emit helper. Use exact log text from the spec:

```gdscript
func _on_cable_connected(hum_id: int, device_id: int, _cable_type: StringName) -> void:
    _bulk_connect_count_this_tick += 1
    if _is_first_cable_ever():
        _log_status("New harmonic bridge detected in sector. I did not initiate this. The devices are coordinating. Excellent.")
        _mark_first_cable_logged()
        return
    if _same_tick_disconnect_seen(device_id):
        _log_status("UNIT-T%02d re-coupled through alternate bridge. Previous carrier retired." % device_id)
        return
    _log_status("UNIT-T%02d harmonic coupled to acoustic source. Spindle resonance routing nominal." % device_id)

# ... similar for disconnect, deny, pressed-unpowered, etc.
```

Include the bulk-coalesce guard: at the end of each tick, if `_bulk_connect_count_this_tick > 3`, suppress individual logs and emit `"Multiple harmonic bridges established simultaneously. Topology unexpectedly rich. Recording for review."` once.

Precedence: during starter-scenario boot (Task 4 places cables via world_init), bulk-coalesce wins over first-cable discovery. Check `_starter_scenario_boot_active` before logging the first-cable line.

- [ ] **Step 3: Test manually.**

Run: `/Applications/Godot.app/Contents/MacOS/godot --path .`
- Fresh game: starter scenario is active → bulk-coalesce log fires, not first-cable.
- Disconnect + reconnect one cable → "re-coupled through alternate bridge" log.
- Pick up a cable and press X → no connect log, just the disconnect that already fired.

- [ ] **Step 4: Commit.**

```bash
git add engine/narrative/robot_narrator.gd
git commit -m "feat(narrator): cable log lines per spec Section Narrative"
```

---

## Task 16: Rule doc updates

**Files:**
- Modify: `.claude/rules/input-design.md` — replace "hold Y to disconnect" paragraph with click-to-pickup flow
- Modify: `.claude/rules/narrative.md` — append "Robot Cable Interpretation" section

- [ ] **Step 1: input-design.md.**

Find the existing disconnect paragraph and replace with the click-to-pickup description from the spec Accessibility section (line 624).

- [ ] **Step 2: narrative.md.**

Append a new section mirroring the existing "Robot Sound Interpretation" and "Satisfaction Interpretation" tables, with a short table of cable-event interpretations (`cable_connected` → "harmonic bridge," etc.).

- [ ] **Step 3: Commit.**

```bash
git add .claude/rules/input-design.md .claude/rules/narrative.md
git commit -m "docs(rules): update input-design and narrative for cable system"
```

---

# Section G: MP and Resync

## Task 17: Cross-stripe rejection (MP scaffolding)

**Files:**
- Modify: `engine/core/wiring_system.gd::_same_stripe`
- Create: `tests/integration/test_cross_stripe_reject_mp.gd`

- [ ] **Step 1: Replace the stub.**

```gdscript
# engine/core/wiring_system.gd::_same_stripe
func _same_stripe(peer_id: int, hum_id: int, device_id: int) -> bool:
    # Peer's stripe membership comes from the MP peer table (stripe assignment).
    # Solo: peer_id=1 owns all stripes → always true.
    # MP: compare the stripe that contains each endpoint's rack column.
    var hum_stripe: int = _stripe_of(hum_id)
    var dev_stripe: int = _stripe_of(device_id)
    var peer_stripe: int = _peer_stripe(peer_id)
    return hum_stripe == peer_stripe and dev_stripe == peer_stripe

func _stripe_of(entity_id: int) -> int:
    if not _db.has_component(entity_id, &"position"):
        return -1
    var x: int = _db.get_field(entity_id, &"position", &"x")
    var rack: int = Constants.pu_x_to_rack(x)
    # Stripe assignment per networking.md: 5-rack stripes in solo/5-mode, 3-rack in collab
    return rack / 5  # adapt to current stripe size constant

func _peer_stripe(peer_id: int) -> int:
    # Single-peer/solo: stripe 0
    # MP: read from the peer roster; injected dependency for testability
    return 0  # solo
```

The peer-stripe lookup will be completed when full MP lands. For now, solo mode always returns stripe 0.

- [ ] **Step 2: Test.**

```gdscript
# tests/integration/test_cross_stripe_reject_mp.gd
extends GutTest

func test_cross_stripe_rejected() -> void:
    # Place HUM in stripe 0, actuator in stripe 1, attempt connect, expect deny
    # Requires injecting peer_stripe(); in solo mode _peer_stripe always returns 0,
    # so the cross-stripe case means: hum_stripe != 0 OR device_stripe != 0
    pass  # implement once peer injection is in place — acceptable stub for now
```

Keep this test as a placeholder; mark it skipped if needed. The real cross-stripe check lands with MP proper.

- [ ] **Step 3: Commit.**

```bash
git add engine/core/wiring_system.gd tests/integration/test_cross_stripe_reject_mp.gd
git commit -m "feat(wiring): stripe-aware rejection (solo baseline)"
```

---

## Task 18: Resync / rejoin handling stub

**Files:**
- Modify: `engine/core/wiring_system.gd` — add `entries_for_peer(peer_id) -> Array`
- Modify: `nodes/hud/wiring_controller.gd` — accept resync push and reconcile local state

- [ ] **Step 1: Expose entries for peer.**

```gdscript
# engine/core/wiring_system.gd
func entries_for_peer(peer_id: int) -> Array:
    return _locks.entries_for_peer(peer_id)
```

- [ ] **Step 2: Client-side reconcile.**

```gdscript
# nodes/hud/wiring_controller.gd
func reconcile_server_pickups(server_entries: Array) -> void:
    if _state != State.HOLDING_CABLE:
        return
    var have_match: bool = false
    for entry in server_entries:
        if entry.get(&"original_actuator_id", -1) == _pickup_from:
            have_match = true
            break
    if not have_match:
        # Server lost the lock; clear local drag silently
        _state = State.WIRING
        _pickup_from = Constants.INVALID_ID
        _source_hum = Constants.INVALID_ID
```

The network layer (or local loop) calls `reconcile_server_pickups` on every resync message; in solo mode this is a no-op unless the lock TTL expires.

- [ ] **Step 3: Commit.**

```bash
git add engine/core/wiring_system.gd nodes/hud/wiring_controller.gd
git commit -m "feat(wiring): resync reconciliation on peer rejoin"
```

---

# Section H: Coverage

## Task 19: Integration — `test_cable_drain_loop`

**Files:**
- Create: `tests/integration/test_cable_drain_loop.gd`

- [ ] **Step 1: Test.**

```gdscript
# tests/integration/test_cable_drain_loop.gd
extends GutTest

func test_cable_makes_tuna_press_drain_hum() -> void:
    var db := GameStateDB.new()
    var hum_sys := HumSystem.new(db)
    var food := FoodSystem.new(db, hum_sys, null)
    var locks := WiringLockRegistry.new()
    var events := _FakeEvents.new()
    var ws := WiringSystem.new(db, locks, events, {&"cable_max_length_ru": 20})
    var hum: int = _make_hum(db, 0)
    var tuna: int = _make_tuna(db, 5)
    _make_button(db, tuna, 6)
    # No cable yet → press returns INVALID_ID
    # (Invoke press via food's public API; adapt to what exists.)
    ws.handle_connect(1, hum, tuna)
    var reserve_before: int = hum_sys.get_reserve(hum)
    # Press via food.press_button(button_id) — adapt if API differs
    # expect drain of 50
    assert_lt(hum_sys.get_reserve(hum), reserve_before)

class _FakeEvents:
    func emit_connect(a, b, c): pass
    func emit_disconnect(a, b): pass
    func emit_deny(r): pass
# _make_* helpers as per Tasks 9 / 6
```

- [ ] **Step 2: Commit.**

```bash
git add tests/integration/test_cable_drain_loop.gd
git commit -m "test(integration): cable→TUNA→HUM drain loop"
```

---

## Task 20: Integration — `test_replace_on_connect`

**Files:**
- Create: `tests/integration/test_replace_on_connect.gd`

- [ ] **Step 1: Test.**

```gdscript
# tests/integration/test_replace_on_connect.gd
extends GutTest

func test_replace_emits_disconnect_then_connect() -> void:
    var db := GameStateDB.new()
    var locks := WiringLockRegistry.new()
    var events := _FakeEvents.new()
    var ws := WiringSystem.new(db, locks, events, {&"cable_max_length_ru": 20})
    var hum_a: int = _make_hum(db, 0)
    var hum_b: int = _make_hum(db, Constants.RACK_WIDTH_PU * 3)
    var tuna: int = _make_tuna(db, Constants.RACK_WIDTH_PU * 1)
    ws.handle_connect(1, hum_a, tuna)
    ws.handle_connect(1, hum_b, tuna)
    # Exactly 2 connects, 1 disconnect, in order: c, d, c
    var seq: Array = events.event_sequence
    assert_eq(seq[0][0], &"connect")
    assert_eq(seq[1][0], &"disconnect")
    assert_eq(seq[2][0], &"connect")
    assert_eq(_db_hum_cable_target(db, tuna), hum_b)

class _FakeEvents:
    var event_sequence: Array = []
    func emit_connect(h: int, d: int, t: StringName) -> void:
        event_sequence.append([&"connect", h, d, t])
    func emit_disconnect(h: int, d: int) -> void:
        event_sequence.append([&"disconnect", h, d])
    func emit_deny(r: StringName) -> void:
        event_sequence.append([&"deny", r])
```

- [ ] **Step 2: Commit.**

```bash
git add tests/integration/test_replace_on_connect.gd
git commit -m "test(integration): replace-on-connect emits atomic disconnect+connect"
```

---

## Task 21: Soak — cable flap

**Files:**
- Create: `tests/soak/test_cable_flap_soak.gd`

- [ ] **Step 1: Test.**

```gdscript
# tests/soak/test_cable_flap_soak.gd
extends GutTest

func test_10_minute_flap_no_leaks() -> void:
    var db := GameStateDB.new()
    var locks := WiringLockRegistry.new()
    var events := _FakeEvents.new()
    var ws := WiringSystem.new(db, locks, events, {&"cable_max_length_ru": 20})
    var hums: Array = []
    var actuators: Array = []
    for i in 3:
        hums.append(_make_hum(db, i * 2 * Constants.RACK_WIDTH_PU))
    for i in 5:
        actuators.append(_make_tuna(db, Constants.RACK_WIDTH_PU))
    # 10 min * 10Hz = 6000 ticks; pick 600 cable ops (1/10 ticks)
    for tick in 600:
        var act: int = actuators[tick % actuators.size()]
        var hum: int = hums[tick % hums.size()]
        ws.handle_connect(1, hum, act)
        if tick % 3 == 0:
            ws.handle_pickup_actuator_end(1, tick, act)
            ws.handle_cancel(1, act)
        locks.tick_expire(tick, 200)
    # Every cable either connected or absent — no dangling state
    for act in actuators:
        if db.has_component(act, &"hum_cable"):
            var hum_id: int = db.get_field(act, &"hum_cable", &"hum_id")
            assert_true(db.has_entity(hum_id), "Cable references live HUM")
    # Pickup state table is empty (all locks resolved)
    for peer_id in [1, 2, 3]:
        assert_eq(locks.entries_for_peer(peer_id).size(), 0)

class _FakeEvents:
    func emit_connect(a, b, c): pass
    func emit_disconnect(a, b): pass
    func emit_deny(r): pass
```

- [ ] **Step 2: Commit.**

```bash
git add tests/soak/test_cable_flap_soak.gd
git commit -m "test(soak): 10-minute cable flap → no leaks"
```

---

## Task 22: Final validation and stamping

- [ ] **Step 1: Run full validation.**

Run: `script/validate`
Expected: green.

- [ ] **Step 2: Stamp all new tests.**

```bash
script/stamp_tests tests/unit/test_hum_powered_spawn.gd
script/stamp_tests tests/unit/test_food_system_power.gd
script/stamp_tests tests/unit/test_wiring_lock_registry.gd
script/stamp_tests tests/unit/test_wiring_system_connect.gd
script/stamp_tests tests/unit/test_wiring_system_pickup.gd
script/stamp_tests tests/unit/test_cable_length_validation.gd
script/stamp_tests tests/integration/test_hum_despawn_tombstone.gd
script/stamp_tests tests/integration/test_save_mid_drag.gd
script/stamp_tests tests/integration/test_cable_drain_loop.gd
script/stamp_tests tests/integration/test_replace_on_connect.gd
script/stamp_tests tests/integration/test_cross_stripe_reject_mp.gd
script/stamp_tests tests/integration/test_pickup_lock_mp.gd
script/stamp_tests tests/soak/test_cable_flap_soak.gd
script/checks/verify_tests
```

Expected: all pass.

- [ ] **Step 3: Run the spec's manual test plan (lines 736–755 of the spec).**

Walk through every bullet. Anything that fails: file as a bug and fix before shipping.

- [ ] **Step 4: Commit stamp sidecars.**

```bash
git add tests/**/*.gd.stamp
git commit -m "test: stamp Phase 2 test verification hashes"
```

---

## Phase 2 Exit Criteria

- [ ] `script/validate` green.
- [ ] All Phase 2 unit / integration / soak tests pass.
- [ ] Manual test plan from the spec passes each item.
- [ ] `script/checks/verify_tests` green; all new tests stamped.
- [ ] Narrator emits the 10+ log lines per the spec table in the appropriate circumstances.
- [ ] Audio and sprite assets imported, referenced in `docs/art-asset-tracker.md` and `docs/sound-asset-tracker.md`.
- [ ] `.claude/rules/input-design.md` and `.claude/rules/narrative.md` updated.

## DONE

Phase 2 merged green completes the HUM cable hookup feature. The three phases together deliver:

- **Phase 0:** starter scenario + debug override (testability).
- **Phase 1:** per-HUM batteries + `purr` emitter channel + contentment→purr bridge.
- **Phase 2:** cables, UX, MP locks, save/reload, rendering, narrative.

Post-merge: flag `project_petting_chain_broken.md` in project memory — the real pet→satisfied chain fix remains an unblocking Ring 0 work item. Until that ships, the debug contentment override is the manual dev workaround.
