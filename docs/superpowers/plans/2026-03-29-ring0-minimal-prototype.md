# Ring 0 Minimal Prototype — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a playable vertical slice where 5 animals react to player-placed infrastructure with desire-driven AI, hysteresis, and purring as the audible success metric.

**Architecture:** Pure Core pattern — all game logic in RefCounted classes under `engine/`, thin Node wrappers under `nodes/`. GameStateDB is the central state store. 10Hz fixed tick. Event bus for cross-system communication. Server-authoritative even in solo.

**Tech Stack:** Godot 4.6, GDScript, GUT (Godot Unit Test), MessagePack (deferred)

**Design spec:** `docs/superpowers/specs/2026-03-29-ring0-minimal-prototype-design.md`

**Key rules files to reference:**
- `design-philosophy.md` — Pure Core, GameStateDB interface, integers, no null
- `code-style.md` — Naming, types, signals, guard clauses
- `testing.md` — GUT framework, test suites, exemplars
- `signals.md` — Three signal patterns, event bus
- `scene-tree.md` — Scene hierarchy, ownership
- `tick-architecture.md` — 10Hz tick, scatter, adaptive budget
- `file-structure.md` — Directory layout

---

## File Structure

### Engine (RefCounted core logic — `engine/`)

```
engine/
  core/
    game_state_db.gd          # Central state store
    constants.gd              # POSITION_SCALE, SLOT_HEIGHT_PU, ru_to_pu(), etc.
    events.gd                 # Event bus autoload (signals only)
  desires/
    desire_resolver.gd        # Utility scoring, time-budgeted evaluation
  spatial/
    heat_grid.gd              # Heat propagation (PackedInt32Array grid)
  animals/
    animal_state_machine.gd   # Ambient/goal-directed states, hysteresis
    curiosity_tracker.gd      # Per-entity cell visit history
  navigation/
    species_astar.gd          # AStar2D subclass with species filtering
    nav_graph_builder.gd      # Builds/updates nav graph from placed objects
```

### Nodes (thin Godot wrappers — `nodes/`)

```
nodes/
  game_server.gd             # Owns tick loop, coordinates systems
  game_client.gd             # Owns rendering, input, sound
  animal_node.gd             # Sprite + sound for one animal
  placed_object_node.gd      # Sprite for one placed object
  sound_manager.gd           # Purr mixing + ambient hum
  placement_ui.gd            # Sidebar buttons, placement ghost
  heat_overlay.gd            # Debug temperature visualization
  camera_controller.gd       # Pan + zoom
```

### Scenes (`.tscn` files — `nodes/`)

```
nodes/
  main.tscn                  # Root scene (GameServer + GameClient + Events)
  animal.tscn                # Animal scene (Sprite + SoundEmitter + Areas)
  placed_object.tscn         # Object scene (Sprite)
```

### Tests (`tests/`)

```
tests/
  unit/
    test_game_state_db.gd
    test_constants.gd
    test_heat_grid.gd
    test_desire_resolver.gd
    test_animal_state_machine.gd
    test_curiosity_tracker.gd
    test_species_astar.gd
  integration/
    test_tick_loop.gd
    test_desire_scatter.gd
```

---

## Task 1: Initialize Godot Project

**Files:**
- Create: `project.godot`
- Create: `engine/core/constants.gd`
- Create: `tests/unit/test_constants.gd`

- [ ] **Step 1: Create project.godot**

Run Godot headless to create the project, or create it manually:

```
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; but it can also be edited as a text file.

[application]

config/name="Tuna Control Protocol"
run/main_scene="res://nodes/main.tscn"
config/features=PackedStringArray("4.6")

[display]

window/size/viewport_width=960
window/size/viewport_height=960

[physics]

common/physics_ticks_per_second=10

[rendering]

textures/canvas_textures/default_texture_filter=0
```

Note: `default_texture_filter=0` is TEXTURE_FILTER_NEAREST for pixel art. `physics_ticks_per_second=10` sets the sim tick rate.

- [ ] **Step 2: Create constants.gd**

```gdscript
# engine/core/constants.gd
class_name Constants extends RefCounted

const INVALID_ID: int = -1

# Position scale: 100 position units = 1 pixel
const POSITION_SCALE: int = 100

# Rack geometry
const SLOT_HEIGHT_PX: int = 24
const SLOT_HEIGHT_PU: int = SLOT_HEIGHT_PX * POSITION_SCALE  # 2400
const RACK_WIDTH_PX: int = 96
const RACK_WIDTH_PU: int = RACK_WIDTH_PX * POSITION_SCALE  # 9600
const RACK_GAP_PX: int = 4
const RACK_COUNT: int = 5
const SLOTS_PER_RACK: int = 42
const FLOOR_HEIGHT_PX: int = 48
const FLOOR_HEIGHT_PU: int = FLOOR_HEIGHT_PX * POSITION_SCALE  # 4800
const TOR_SWITCH_SLOTS: int = 4

# Desire system
const UNIT: int = 1000
const SWITCH_THRESHOLD: int = 150
const EVAL_TIME_BUDGET_USEC: int = 1000

# Heat grid
const HEAT_CELLS_RACK: int = SLOTS_PER_RACK * RACK_COUNT  # 210
const HEAT_CELLS_FLOOR: int = RACK_COUNT  # 5
const HEAT_CELLS_TOTAL: int = HEAT_CELLS_RACK + HEAT_CELLS_FLOOR  # 215

static func ru_to_pu(ru: int) -> int:
	return ru * SLOT_HEIGHT_PU

static func pu_to_ru(pu: int) -> int:
	return pu / SLOT_HEIGHT_PU

static func rack_cell(rack: int, slot: int) -> int:
	return rack * SLOTS_PER_RACK + slot

static func floor_cell(rack: int) -> int:
	return HEAT_CELLS_RACK + rack

static func to_world(v: int) -> float:
	return float(v) / float(POSITION_SCALE)

static func from_world(v: float) -> int:
	return roundi(v * float(POSITION_SCALE))
```

- [ ] **Step 3: Install GUT addon**

Download GUT from https://github.com/bitwes/Gut/releases (latest for Godot 4.x). Extract to `addons/gut/`. Then enable it:

Add to `project.godot`:
```
[editor_plugins]

enabled=PackedStringArray("res://addons/gut/plugin.cfg")
```

- [ ] **Step 4: Write test for constants**

```gdscript
# tests/unit/test_constants.gd
extends GutTest

func test_ru_to_pu_converts_correctly():
	assert_eq(Constants.ru_to_pu(1), 2400, "1 RU = 2400 PU")
	assert_eq(Constants.ru_to_pu(3), 7200, "3 RU = 7200 PU")
	assert_eq(Constants.ru_to_pu(0), 0, "0 RU = 0 PU")

func test_pu_to_ru_converts_correctly():
	assert_eq(Constants.pu_to_ru(2400), 1, "2400 PU = 1 RU")
	assert_eq(Constants.pu_to_ru(7200), 3, "7200 PU = 3 RU")
	assert_eq(Constants.pu_to_ru(0), 0, "0 PU = 0 RU")

func test_rack_cell_addressing():
	assert_eq(Constants.rack_cell(0, 0), 0, "Rack 0 slot 0 = cell 0")
	assert_eq(Constants.rack_cell(1, 0), 42, "Rack 1 slot 0 = cell 42")
	assert_eq(Constants.rack_cell(4, 41), 209, "Rack 4 slot 41 = cell 209")

func test_floor_cell_addressing():
	assert_eq(Constants.floor_cell(0), 210, "Floor rack 0 = cell 210")
	assert_eq(Constants.floor_cell(4), 214, "Floor rack 4 = cell 214")

func test_to_world_converts_int_to_float():
	assert_almost_eq(Constants.to_world(2400), 24.0, 0.01, "2400 PU = 24.0 px")
	assert_almost_eq(Constants.to_world(100), 1.0, 0.01, "100 PU = 1.0 px")

func test_from_world_converts_float_to_int():
	assert_eq(Constants.from_world(24.0), 2400, "24.0 px = 2400 PU")
	assert_eq(Constants.from_world(1.0), 100, "1.0 px = 100 PU")

func test_grid_dimensions():
	assert_eq(Constants.HEAT_CELLS_TOTAL, 215, "210 rack + 5 floor = 215 cells")
	assert_eq(Constants.SLOTS_PER_RACK, 42, "42 U per rack")
	assert_eq(Constants.RACK_COUNT, 5, "5 racks")
```

- [ ] **Step 5: Run tests**

```bash
/Applications/Godot.app/Contents/MacOS/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gtest=test_constants.gd
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add project.godot engine/core/constants.gd tests/unit/test_constants.gd addons/gut/
git commit -m "feat: initialize Godot project with constants and GUT test framework"
```

---

## Task 2: GameStateDB Core

**Files:**
- Create: `engine/core/game_state_db.gd`
- Create: `tests/unit/test_game_state_db.gd`

- [ ] **Step 1: Write failing tests for entity lifecycle**

```gdscript
# tests/unit/test_game_state_db.gd
extends GutTest

var db: GameStateDB

func before_each():
	db = GameStateDB.new()

func test_create_entity_returns_unique_ids():
	var id1: int = db.create_entity()
	var id2: int = db.create_entity()
	assert_ne(id1, id2, "Entity IDs must be unique")
	assert_ne(id1, Constants.INVALID_ID, "Entity ID must not be INVALID_ID")

func test_has_entity_after_create():
	var id: int = db.create_entity()
	assert_true(db.has_entity(id), "Entity should exist after create")

func test_has_entity_false_for_unknown():
	assert_false(db.has_entity(999), "Unknown entity should not exist")

func test_destroy_entity():
	var id: int = db.create_entity()
	db.destroy_entity(id)
	assert_false(db.has_entity(id), "Entity should not exist after destroy")
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
/Applications/Godot.app/Contents/MacOS/godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gtest=test_game_state_db.gd
```

Expected: FAIL (GameStateDB class not found)

- [ ] **Step 3: Implement entity lifecycle**

```gdscript
# engine/core/game_state_db.gd
class_name GameStateDB extends RefCounted

var _entities: Dictionary = {}  # entity_id -> { component_name -> { field -> value } }
var _next_id: int = 1
var _tick: int = 0

func create_entity() -> int:
	var id: int = _next_id
	_next_id += 1
	_entities[id] = {}
	return id

func destroy_entity(entity_id: int) -> void:
	assert(_entities.has(entity_id), "Cannot destroy unknown entity: %d" % entity_id)
	_entities.erase(entity_id)

func has_entity(entity_id: int) -> bool:
	return _entities.has(entity_id)
```

- [ ] **Step 4: Run tests to verify they pass**

Expected: All 4 tests pass.

- [ ] **Step 5: Write failing tests for component access**

Add to `test_game_state_db.gd`:

```gdscript
func test_set_and_get_component():
	var id: int = db.create_entity()
	db.set_component(id, &"position", {&"x": 100, &"y": 200})
	var pos: Dictionary = db.get_component(id, &"position")
	assert_eq(pos[&"x"], 100, "x should be 100")
	assert_eq(pos[&"y"], 200, "y should be 200")

func test_has_component():
	var id: int = db.create_entity()
	assert_false(db.has_component(id, &"position"), "Should not have position yet")
	db.set_component(id, &"position", {&"x": 0, &"y": 0})
	assert_true(db.has_component(id, &"position"), "Should have position after set")

func test_get_field():
	var id: int = db.create_entity()
	db.set_component(id, &"desires", {&"warmth": 500, &"comfort": 300})
	assert_eq(db.get_field(id, &"desires", &"warmth"), 500)
	assert_eq(db.get_field(id, &"desires", &"comfort"), 300)

func test_set_field():
	var id: int = db.create_entity()
	db.set_component(id, &"desires", {&"warmth": 500, &"comfort": 300})
	db.set_field(id, &"desires", &"warmth", 800)
	assert_eq(db.get_field(id, &"desires", &"warmth"), 800, "warmth should be updated")
	assert_eq(db.get_field(id, &"desires", &"comfort"), 300, "comfort should be unchanged")
```

- [ ] **Step 6: Implement component access**

Add to `game_state_db.gd`:

```gdscript
func set_component(entity_id: int, component: StringName, data: Dictionary) -> void:
	assert(_entities.has(entity_id), "Unknown entity: %d" % entity_id)
	_entities[entity_id][component] = data.duplicate()
	_mark_dirty_component(component, entity_id)

func get_component(entity_id: int, component: StringName) -> Dictionary:
	assert(_entities.has(entity_id), "Unknown entity: %d" % entity_id)
	assert(_entities[entity_id].has(component), "Entity %d missing component: %s" % [entity_id, component])
	return _entities[entity_id][component]

func has_component(entity_id: int, component: StringName) -> bool:
	if not _entities.has(entity_id):
		return false
	return _entities[entity_id].has(component)

func get_field(entity_id: int, component: StringName, field: StringName) -> int:
	var comp: Dictionary = get_component(entity_id, component)
	assert(comp.has(field), "Component %s missing field: %s" % [component, field])
	return comp[field]

func set_field(entity_id: int, component: StringName, field: StringName, value: int) -> void:
	assert(_entities.has(entity_id), "Unknown entity: %d" % entity_id)
	assert(_entities[entity_id].has(component), "Entity %d missing component: %s" % [entity_id, component])
	_entities[entity_id][component][field] = value
	_mark_dirty_component(component, entity_id)

func _mark_dirty_component(component: StringName, entity_id: int) -> void:
	if not _dirty_components.has(component):
		_dirty_components[component] = []
	if entity_id not in _dirty_components[component]:
		_dirty_components[component].append(entity_id)
```

Add `_dirty_components` to the var declarations:

```gdscript
var _dirty_components: Dictionary = {}  # component_name -> Array[int]
```

- [ ] **Step 7: Run tests to verify they pass**

- [ ] **Step 8: Write failing tests for batch operations and watchers**

Add to `test_game_state_db.gd`:

```gdscript
func test_add_all():
	var id1: int = db.create_entity()
	var id2: int = db.create_entity()
	db.set_component(id1, &"desires", {&"warmth": 500})
	db.set_component(id2, &"desires", {&"warmth": 300})
	db.add_all(&"desires", &"warmth", 100)
	assert_eq(db.get_field(id1, &"desires", &"warmth"), 600)
	assert_eq(db.get_field(id2, &"desires", &"warmth"), 400)

func test_clamp_all():
	var id1: int = db.create_entity()
	db.set_component(id1, &"desires", {&"warmth": 1100})
	db.clamp_all(&"desires", &"warmth", 0, 1000)
	assert_eq(db.get_field(id1, &"desires", &"warmth"), 1000, "Should clamp to max")

func test_tick_advances():
	assert_eq(db.get_tick(), 0, "Start at tick 0")
	db.advance_tick()
	assert_eq(db.get_tick(), 1, "After advance, tick = 1")

func test_watcher_fires_on_flush():
	var id: int = db.create_entity()
	db.set_component(id, &"desires", {&"warmth": 500})
	var received_ids: Array[int] = []
	db.watch(&"desires", func(eid: int) -> void: received_ids.append(eid))
	db.set_field(id, &"desires", &"warmth", 800)
	assert_eq(received_ids.size(), 0, "Watcher should not fire before flush")
	db.flush_notifications()
	assert_eq(received_ids.size(), 1, "Watcher should fire once after flush")
	assert_eq(received_ids[0], id, "Watcher should receive the changed entity ID")

func test_watcher_deduplicates():
	var id: int = db.create_entity()
	db.set_component(id, &"desires", {&"warmth": 500})
	var count: int = 0
	db.watch(&"desires", func(_eid: int) -> void: count += 1)
	db.set_field(id, &"desires", &"warmth", 600)
	db.set_field(id, &"desires", &"warmth", 700)
	db.flush_notifications()
	assert_eq(count, 1, "Multiple changes to same entity should fire watcher once")
```

- [ ] **Step 9: Implement batch operations, tick, and watchers**

Add to `game_state_db.gd`:

```gdscript
var _watchers: Dictionary = {}  # component_name -> Array[Callable]

func add_all(component: StringName, field: StringName, delta: int) -> void:
	for entity_id in _entities:
		if _entities[entity_id].has(component):
			var comp: Dictionary = _entities[entity_id][component]
			if comp.has(field):
				comp[field] += delta
				_mark_dirty_component(component, entity_id)

func clamp_all(component: StringName, field: StringName, min_val: int, max_val: int) -> void:
	for entity_id in _entities:
		if _entities[entity_id].has(component):
			var comp: Dictionary = _entities[entity_id][component]
			if comp.has(field):
				var old: int = comp[field]
				comp[field] = clampi(comp[field], min_val, max_val)
				if comp[field] != old:
					_mark_dirty_component(component, entity_id)

func get_tick() -> int:
	return _tick

func advance_tick() -> void:
	_tick += 1

func watch(component: StringName, callback: Callable) -> void:
	if not _watchers.has(component):
		_watchers[component] = []
	_watchers[component].append(callback)

func flush_notifications() -> void:
	for component in _dirty_components:
		if _watchers.has(component):
			for entity_id in _dirty_components[component]:
				for callback in _watchers[component]:
					callback.call(entity_id)
	_dirty_components.clear()
```

- [ ] **Step 10: Run tests to verify they pass**

- [ ] **Step 11: Write failing tests for spatial queries**

Add to `test_game_state_db.gd`:

```gdscript
func test_spatial_query_finds_nearby():
	var id1: int = db.create_entity()
	var id2: int = db.create_entity()
	var id3: int = db.create_entity()
	db.update_spatial(id1, 1000, 1000)
	db.update_spatial(id2, 1500, 1000)  # 500 PU away
	db.update_spatial(id3, 9000, 9000)  # far away
	var nearby: Array[int] = db.query_radius(1000, 1000, 2000)
	assert_true(id1 in nearby, "id1 should be in radius")
	assert_true(id2 in nearby, "id2 should be in radius")
	assert_false(id3 in nearby, "id3 should not be in radius")

func test_spatial_update_moves_entity():
	var id: int = db.create_entity()
	db.update_spatial(id, 1000, 1000)
	var nearby: Array[int] = db.query_radius(1000, 1000, 500)
	assert_true(id in nearby, "Should find entity at original position")
	db.update_spatial(id, 9000, 9000)
	nearby = db.query_radius(1000, 1000, 500)
	assert_false(id in nearby, "Should not find entity at old position after move")

func test_get_entities_with():
	var id1: int = db.create_entity()
	var id2: int = db.create_entity()
	var id3: int = db.create_entity()
	db.set_component(id1, &"desires", {&"warmth": 500})
	db.set_component(id2, &"desires", {&"warmth": 300})
	# id3 has no desires component
	var with_desires: Array[int] = db.get_entities_with(&"desires")
	assert_eq(with_desires.size(), 2, "Should find 2 entities with desires")
	assert_true(id1 in with_desires)
	assert_true(id2 in with_desires)
```

- [ ] **Step 12: Implement spatial queries**

Add to `game_state_db.gd`:

```gdscript
var _spatial: Dictionary = {}  # entity_id -> { x: int, y: int }

func update_spatial(entity_id: int, x: int, y: int) -> void:
	_spatial[entity_id] = {&"x": x, &"y": y}

func remove_spatial(entity_id: int) -> void:
	_spatial.erase(entity_id)

func query_radius(x: int, y: int, radius: int) -> Array[int]:
	var result: Array[int] = []
	for entity_id in _spatial:
		var pos: Dictionary = _spatial[entity_id]
		var dx: int = absi(pos[&"x"] - x)
		var dy: int = absi(pos[&"y"] - y)
		if dx + dy <= radius:  # Manhattan distance
			result.append(entity_id)
	return result

func get_entities_with(component: StringName) -> Array[int]:
	var result: Array[int] = []
	for entity_id in _entities:
		if _entities[entity_id].has(component):
			result.append(entity_id)
	return result
```

- [ ] **Step 13: Run all tests to verify they pass**

- [ ] **Step 14: Commit**

```bash
git add engine/core/game_state_db.gd tests/unit/test_game_state_db.gd
git commit -m "feat: implement GameStateDB with entity lifecycle, components, batch ops, watchers, and spatial queries"
```

---

## Task 3: Event Bus

**Files:**
- Create: `engine/core/events.gd`

- [ ] **Step 1: Create event bus**

```gdscript
# engine/core/events.gd
extends Node

# Object lifecycle
signal object_placed(object_id: int, rack: int, slot: int, object_type: StringName)
signal object_removed(object_id: int, rack: int, slot: int)

# Heat
signal heat_cell_changed(cell_id: int, old_temp: int, new_temp: int)

# Animal state
signal animal_state_changed(animal_id: int, old_state: StringName, new_state: StringName)
signal animal_relocated(animal_id: int, from_x: int, from_y: int, to_x: int, to_y: int)
```

- [ ] **Step 2: Register as autoload in project.godot**

Add to `project.godot`:
```
[autoload]

Events="*res://engine/core/events.gd"
```

- [ ] **Step 3: Commit**

```bash
git add engine/core/events.gd project.godot
git commit -m "feat: add Events autoload with object, heat, and animal signals"
```

---

## Task 4: Heat Grid

**Files:**
- Create: `engine/spatial/heat_grid.gd`
- Create: `tests/unit/test_heat_grid.gd`

- [ ] **Step 1: Write failing tests**

```gdscript
# tests/unit/test_heat_grid.gd
extends GutTest

var db: GameStateDB
var grid: HeatGrid

func before_each():
	db = GameStateDB.new()
	grid = HeatGrid.new(db)

func test_empty_grid_is_zero():
	grid.propagate()
	for i in Constants.HEAT_CELLS_TOTAL:
		assert_eq(grid.get_temperature(i), 0, "Cell %d should be 0 with no sources" % i)

func test_single_source_heats_same_slot():
	var server: int = db.create_entity()
	db.set_component(server, &"position", {&"x": 0, &"y": 0})
	db.set_component(server, &"heat_source", {&"value": 900, &"radius_ru": 3})
	grid.propagate()
	var cell: int = Constants.rack_cell(0, 0)
	assert_eq(grid.get_temperature(cell), 900, "Source cell should have full heat value")

func test_heat_falls_off_with_distance():
	var server: int = db.create_entity()
	# Place at rack 2, slot 20
	db.set_component(server, &"position", {
		&"x": 2 * Constants.RACK_WIDTH_PU,
		&"y": 20 * Constants.SLOT_HEIGHT_PU
	})
	db.set_component(server, &"heat_source", {&"value": 900, &"radius_ru": 3})
	grid.propagate()
	var at_source: int = grid.get_temperature(Constants.rack_cell(2, 20))
	var one_away: int = grid.get_temperature(Constants.rack_cell(2, 19))
	var two_away: int = grid.get_temperature(Constants.rack_cell(2, 18))
	assert_gt(at_source, one_away, "Heat should decrease with distance")
	assert_gt(one_away, two_away, "Heat should decrease further")

func test_heat_does_not_exceed_radius():
	var server: int = db.create_entity()
	db.set_component(server, &"position", {
		&"x": 2 * Constants.RACK_WIDTH_PU,
		&"y": 20 * Constants.SLOT_HEIGHT_PU
	})
	db.set_component(server, &"heat_source", {&"value": 900, &"radius_ru": 3})
	grid.propagate()
	# 4 slots away should be zero (radius is 3)
	var far: int = grid.get_temperature(Constants.rack_cell(2, 16))
	assert_eq(far, 0, "Beyond radius should have zero heat")

func test_heat_clamps_at_1000():
	var s1: int = db.create_entity()
	var s2: int = db.create_entity()
	db.set_component(s1, &"position", {&"x": 0, &"y": 2400})
	db.set_component(s1, &"heat_source", {&"value": 800, &"radius_ru": 3})
	db.set_component(s2, &"position", {&"x": 0, &"y": 2400})
	db.set_component(s2, &"heat_source", {&"value": 800, &"radius_ru": 3})
	grid.propagate()
	var cell: int = Constants.rack_cell(0, 1)
	assert_lte(grid.get_temperature(cell), 1000, "Heat should clamp at 1000")

func test_cross_rack_spillover_is_weak():
	var server: int = db.create_entity()
	db.set_component(server, &"position", {
		&"x": 2 * Constants.RACK_WIDTH_PU,
		&"y": 20 * Constants.SLOT_HEIGHT_PU
	})
	db.set_component(server, &"heat_source", {&"value": 800, &"radius_ru": 3})
	grid.propagate()
	var same_rack: int = grid.get_temperature(Constants.rack_cell(2, 20))
	var adj_rack: int = grid.get_temperature(Constants.rack_cell(3, 20))
	assert_gt(same_rack, adj_rack * 2, "Adjacent rack should get much less heat than source rack")

func test_floor_gets_weak_heat():
	var server: int = db.create_entity()
	db.set_component(server, &"position", {
		&"x": 2 * Constants.RACK_WIDTH_PU,
		&"y": 20 * Constants.SLOT_HEIGHT_PU
	})
	db.set_component(server, &"heat_source", {&"value": 800, &"radius_ru": 3})
	grid.propagate()
	var floor_temp: int = grid.get_temperature(Constants.floor_cell(2))
	assert_gt(floor_temp, 0, "Floor should get some heat")
	assert_lt(floor_temp, 400, "Floor heat should be weak")
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement HeatGrid**

```gdscript
# engine/spatial/heat_grid.gd
class_name HeatGrid extends RefCounted

var _db: GameStateDB
var _grid: PackedInt32Array

func _init(db: GameStateDB) -> void:
	_db = db
	_grid = PackedInt32Array()
	_grid.resize(Constants.HEAT_CELLS_TOTAL)

func get_temperature(cell_index: int) -> int:
	assert(cell_index >= 0 and cell_index < Constants.HEAT_CELLS_TOTAL,
		"Cell index out of range: %d" % cell_index)
	return _grid[cell_index]

func propagate() -> void:
	_grid.fill(0)
	var sources: Array[int] = _db.get_entities_with(&"heat_source")
	for entity_id in sources:
		var pos: Dictionary = _db.get_component(entity_id, &"position")
		var heat: Dictionary = _db.get_component(entity_id, &"heat_source")
		_apply_diamond(pos, heat)

func _apply_diamond(pos: Dictionary, heat: Dictionary) -> void:
	var src_rack: int = pos[&"x"] / Constants.RACK_WIDTH_PU
	var src_slot: int = pos[&"y"] / Constants.SLOT_HEIGHT_PU
	var value: int = heat[&"value"]
	var radius: int = heat[&"radius_ru"]

	# Vertical spread within source rack: 3U up, 1U down
	for ds in range(-radius, radius / 3 + 1):
		var s: int = src_slot + ds
		if s < 0 or s >= Constants.SLOTS_PER_RACK:
			continue
		var dist: int = absi(ds)
		if dist > radius:
			continue
		var falloff: int = value * (radius - dist) / radius
		var idx: int = Constants.rack_cell(src_rack, s)
		_grid[idx] = mini(_grid[idx] + falloff, 1000)

	# Weak cross-rack spillover (1/4 strength, same slot only)
	for dr in [-1, 1]:
		var r: int = src_rack + dr
		if r < 0 or r >= Constants.RACK_COUNT:
			continue
		var spillover: int = value / 4
		var idx: int = Constants.rack_cell(r, src_slot)
		_grid[idx] = mini(_grid[idx] + spillover, 1000)

	# Weak floor radiation
	var floor_idx: int = Constants.floor_cell(src_rack)
	var floor_heat: int = value / (radius + 1)
	_grid[floor_idx] = mini(_grid[floor_idx] + floor_heat, 1000)
```

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add engine/spatial/heat_grid.gd tests/unit/test_heat_grid.gd
git commit -m "feat: implement HeatGrid with diamond propagation and cross-rack spillover"
```

---

## Task 5: Animal State Machine

**Files:**
- Create: `engine/animals/animal_state_machine.gd`
- Create: `tests/unit/test_animal_state_machine.gd`

- [ ] **Step 1: Write failing tests**

```gdscript
# tests/unit/test_animal_state_machine.gd
extends GutTest

var sm: AnimalStateMachine

func before_each():
	sm = AnimalStateMachine.new()

func test_starts_in_idle():
	assert_eq(sm.state, &"IDLE")
	assert_eq(sm.meta_state, &"AMBIENT")

func test_cannot_transition_before_min_duration():
	sm.min_duration = 3.0
	sm.state_timer = 1.0
	var result: bool = sm.try_transition(&"SEEKING", 500)
	assert_false(result, "Should not transition before min_duration")
	assert_eq(sm.state, &"IDLE")

func test_transitions_when_score_exceeds_threshold():
	sm.state_timer = 10.0  # past min_duration
	sm.commitment_score = 0
	var result: bool = sm.try_transition(&"SEEKING", 200)
	assert_true(result, "200 > 0 + 150, should transition")
	assert_eq(sm.state, &"SEEKING")
	assert_eq(sm.meta_state, &"GOAL_DIRECTED")

func test_hysteresis_blocks_weak_transition():
	sm.state_timer = 10.0
	sm.commitment_score = 300
	var result: bool = sm.try_transition(&"SEEKING", 400)
	assert_false(result, "400 < 300 + 150, should not transition")
	assert_eq(sm.state, &"IDLE")

func test_commitment_decays():
	sm.commitment_score = 100
	sm.tick(0.1)  # one 10Hz tick
	assert_eq(sm.commitment_score, 99, "Should decay by 1 per tick (10/sec * 0.1s)")

func test_commitment_floors_at_zero():
	sm.commitment_score = 0
	sm.tick(0.1)
	assert_eq(sm.commitment_score, 0, "Should not go below 0")

func test_startled_overrides_min_duration():
	sm.min_duration = 30.0
	sm.state_timer = 0.1
	sm.enter_startled()
	assert_eq(sm.state, &"STARTLED")

func test_goal_directed_states():
	for s in [&"SEEKING", &"MOVING_TO", &"SETTLING"]:
		sm.state_timer = 10.0
		sm.commitment_score = 0
		sm.try_transition(s, 200)
		assert_eq(sm.meta_state, &"GOAL_DIRECTED",
			"State %s should be GOAL_DIRECTED" % s)
		sm._enter_state(&"IDLE", 0)  # reset

func test_ambient_states():
	for s in [&"IDLE", &"GROOMING", &"LOAFING", &"SLEEPING", &"SNIFFING", &"SPEED_BUMP"]:
		sm._enter_state(s, 0)
		assert_eq(sm.meta_state, &"AMBIENT",
			"State %s should be AMBIENT" % s)
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement AnimalStateMachine**

```gdscript
# engine/animals/animal_state_machine.gd
class_name AnimalStateMachine extends RefCounted

const GOAL_DIRECTED_STATES: Array[StringName] = [
	&"SEEKING", &"MOVING_TO", &"SETTLING",
]

const AMBIENT_STATES: Array[StringName] = [
	&"IDLE", &"GROOMING", &"LOAFING", &"SLEEPING",
	&"SNIFFING", &"SPEED_BUMP",
]

var state: StringName = &"IDLE"
var meta_state: StringName = &"AMBIENT"
var commitment_score: int = 0
var state_timer: float = 0.0
var min_duration: float = 3.0

func try_transition(new_state: StringName, score: int) -> bool:
	if state_timer < min_duration:
		return false
	if meta_state == &"GOAL_DIRECTED":
		if score < commitment_score + Constants.SWITCH_THRESHOLD:
			return false
	if meta_state == &"AMBIENT":
		if score < commitment_score + Constants.SWITCH_THRESHOLD:
			return false
	_enter_state(new_state, score)
	return true

func enter_startled() -> void:
	_enter_state(&"STARTLED", 0)

func _enter_state(new_state: StringName, score: int) -> void:
	state = new_state
	commitment_score = score
	state_timer = 0.0
	if new_state in GOAL_DIRECTED_STATES:
		meta_state = &"GOAL_DIRECTED"
	elif new_state == &"STARTLED":
		meta_state = &"SPECIAL"
		min_duration = randf_range(0.5, 1.5)
	else:
		meta_state = &"AMBIENT"
		_set_min_duration_for_ambient(new_state)

func _set_min_duration_for_ambient(s: StringName) -> void:
	match s:
		&"IDLE": min_duration = 3.0
		&"GROOMING": min_duration = 10.0
		&"LOAFING": min_duration = 15.0
		&"SLEEPING": min_duration = 30.0
		&"SNIFFING": min_duration = 10.0
		&"SPEED_BUMP": min_duration = 15.0
		_: min_duration = 3.0

func tick(delta: float) -> void:
	state_timer += delta
	commitment_score = maxi(0, commitment_score - maxi(1, roundi(10.0 * delta)))
```

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add engine/animals/animal_state_machine.gd tests/unit/test_animal_state_machine.gd
git commit -m "feat: implement AnimalStateMachine with hysteresis, ambient/goal states"
```

---

## Task 6: Curiosity Tracker

**Files:**
- Create: `engine/animals/curiosity_tracker.gd`
- Create: `tests/unit/test_curiosity_tracker.gd`

- [ ] **Step 1: Write failing tests**

```gdscript
# tests/unit/test_curiosity_tracker.gd
extends GutTest

var tracker: CuriosityTracker

func before_each():
	tracker = CuriosityTracker.new()

func test_new_cell_satisfies_curiosity():
	var satisfaction: int = tracker.visit_cell(42, 100)
	assert_eq(satisfaction, 0, "Visiting a new cell should fully satisfy curiosity (0 = satisfied)")

func test_recently_visited_cell_does_not_satisfy():
	tracker.visit_cell(42, 100)
	var satisfaction: int = tracker.visit_cell(42, 110)
	assert_eq(satisfaction, -1, "Revisiting within cooldown should return -1 (no change)")

func test_cell_becomes_novel_after_cooldown():
	tracker.visit_cell(42, 100)
	var satisfaction: int = tracker.visit_cell(42, 201)
	assert_eq(satisfaction, 0, "Cell should be novel again after 100 ticks")

func test_tracks_multiple_cells():
	tracker.visit_cell(10, 100)
	tracker.visit_cell(20, 100)
	assert_eq(tracker.visit_cell(10, 105), -1, "Cell 10 still on cooldown")
	assert_eq(tracker.visit_cell(30, 105), 0, "Cell 30 is new")
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement CuriosityTracker**

```gdscript
# engine/animals/curiosity_tracker.gd
class_name CuriosityTracker extends RefCounted

const NOVELTY_COOLDOWN_TICKS: int = 100  # ~10 seconds at 10Hz

var _visit_times: Dictionary = {}  # cell_index -> last_visit_tick

func visit_cell(cell_index: int, current_tick: int) -> int:
	if _visit_times.has(cell_index):
		var elapsed: int = current_tick - _visit_times[cell_index]
		if elapsed < NOVELTY_COOLDOWN_TICKS:
			return -1  # still on cooldown, no satisfaction change
	_visit_times[cell_index] = current_tick
	return 0  # fully satisfied
```

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add engine/animals/curiosity_tracker.gd tests/unit/test_curiosity_tracker.gd
git commit -m "feat: implement CuriosityTracker with cell visit cooldown"
```

---

## Task 7: Desire Resolver

**Files:**
- Create: `engine/desires/desire_resolver.gd`
- Create: `tests/unit/test_desire_resolver.gd`

- [ ] **Step 1: Write failing tests**

```gdscript
# tests/unit/test_desire_resolver.gd
extends GutTest

var db: GameStateDB
var resolver: DesireResolver

func before_each():
	db = GameStateDB.new()
	resolver = DesireResolver.new(db)

func _make_cat(x: int, y: int, warmth: int, comfort: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"species", {&"id": &"tcp_base:cat"})
	db.set_component(id, &"position", {&"x": x, &"y": y})
	db.set_component(id, &"desires", {&"warmth": warmth, &"comfort": comfort, &"curiosity": 0})
	db.set_component(id, &"personality", {
		&"warmth_weight": 800, &"comfort_weight": 600, &"curiosity_weight": 100
	})
	db.set_component(id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0
	})
	db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID
	})
	db.update_spatial(id, x, y)
	return id

func _make_server(x: int, y: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"position", {&"x": x, &"y": y})
	db.set_component(id, &"advertisements", {&"list": [
		{&"desire_type": &"warmth", &"strength": 800, &"radius_ru": 3, &"max_occupants": 1}
	]})
	db.update_spatial(id, x, y)
	return id

func test_cold_cat_scores_warm_server():
	var cat: int = _make_cat(0, 0, 800, 200)  # warmth 800 = very cold
	var server: int = _make_server(2400, 0)  # 1 RU away
	var score: int = resolver.score_ad(cat, server, {
		&"desire_type": &"warmth", &"strength": 800, &"radius_ru": 3, &"max_occupants": 1
	})
	assert_gt(score, 0, "Cold cat should score warm server positively")

func test_warm_cat_scores_server_low():
	var cat: int = _make_cat(0, 0, 100, 200)  # warmth 100 = quite warm
	var server: int = _make_server(2400, 0)
	var score: int = resolver.score_ad(cat, server, {
		&"desire_type": &"warmth", &"strength": 800, &"radius_ru": 3, &"max_occupants": 1
	})
	assert_lt(score, 50, "Warm cat should score server very low")

func test_out_of_radius_scores_zero():
	var cat: int = _make_cat(0, 0, 800, 200)
	var server: int = _make_server(Constants.ru_to_pu(10), 0)  # 10 RU away, radius is 3
	var score: int = resolver.score_ad(cat, server, {
		&"desire_type": &"warmth", &"strength": 800, &"radius_ru": 3, &"max_occupants": 1
	})
	assert_eq(score, 0, "Beyond radius should score zero")

func test_higher_weight_produces_higher_score():
	var cat_high: int = _make_cat(0, 0, 800, 200)
	db.set_component(cat_high, &"personality", {
		&"warmth_weight": 900, &"comfort_weight": 600, &"curiosity_weight": 100
	})
	var cat_low: int = _make_cat(5000, 0, 800, 200)
	db.set_component(cat_low, &"personality", {
		&"warmth_weight": 300, &"comfort_weight": 600, &"curiosity_weight": 100
	})
	var server: int = _make_server(2400, 0)
	var score_high: int = resolver.score_ad(cat_high, server, {
		&"desire_type": &"warmth", &"strength": 800, &"radius_ru": 3, &"max_occupants": 1
	})
	var score_low: int = resolver.score_ad(cat_low, server, {
		&"desire_type": &"warmth", &"strength": 800, &"radius_ru": 3, &"max_occupants": 1
	})
	assert_gt(score_high, score_low, "Higher weight should produce higher score")

func test_evaluate_marks_transition():
	var cat: int = _make_cat(0, 0, 800, 200)
	var server: int = _make_server(2400, 0)
	resolver.mark_dirty(cat)
	resolver.evaluate_budget()
	var ai: Dictionary = db.get_component(cat, &"ai_state")
	assert_eq(ai[&"state"], &"SEEKING", "Cat should transition to SEEKING")
	var target: Dictionary = db.get_component(cat, &"target")
	assert_eq(target[&"entity_id"], server, "Cat should target the server")
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement DesireResolver**

```gdscript
# engine/desires/desire_resolver.gd
class_name DesireResolver extends RefCounted

var _db: GameStateDB
var _dirty: Array[int] = []

func _init(db: GameStateDB) -> void:
	_db = db

func mark_dirty(entity_id: int) -> void:
	if entity_id not in _dirty:
		_dirty.append(entity_id)

func evaluate_budget() -> void:
	var start: int = Time.get_ticks_usec()
	while _dirty.size() > 0:
		if Time.get_ticks_usec() - start >= Constants.EVAL_TIME_BUDGET_USEC:
			break
		var id: int = _pop_highest_deficit()
		_evaluate_one(id)

func score_ad(animal_id: int, object_id: int, ad: Dictionary) -> int:
	var desire_type: StringName = ad[&"desire_type"]
	var personality: Dictionary = _db.get_component(animal_id, &"personality")
	var desires: Dictionary = _db.get_component(animal_id, &"desires")

	var weight_key: StringName = StringName(String(desire_type) + "_weight")
	var desire_weight: int = personality.get(weight_key, 500)
	var current: int = desires.get(desire_type, 500)
	var deficit: int = current  # 0 = satisfied, 1000 = desperate; deficit IS the value
	var strength: int = ad[&"strength"]

	var animal_pos: Dictionary = _db.get_component(animal_id, &"position")
	var object_pos: Dictionary = _db.get_component(object_id, &"position")
	var dist_pu: int = absi(animal_pos[&"x"] - object_pos[&"x"]) + absi(animal_pos[&"y"] - object_pos[&"y"])
	var radius_pu: int = Constants.ru_to_pu(ad[&"radius_ru"])
	if dist_pu > radius_pu:
		return 0
	var dist_factor: int = 1000 - (dist_pu * 1000 / radius_pu) if radius_pu > 0 else 1000

	return desire_weight * deficit / 1000 * strength / 1000 * dist_factor / 1000

func _evaluate_one(entity_id: int) -> void:
	var pos: Dictionary = _db.get_component(entity_id, &"position")
	var perception_radius: int = Constants.ru_to_pu(8)
	var nearby: Array[int] = _db.query_radius(pos[&"x"], pos[&"y"], perception_radius)
	var best_score: int = 0
	var best_target: int = Constants.INVALID_ID

	for other_id in nearby:
		if other_id == entity_id:
			continue
		if not _db.has_component(other_id, &"advertisements"):
			continue
		var ads: Dictionary = _db.get_component(other_id, &"advertisements")
		for ad in ads[&"list"]:
			var score: int = score_ad(entity_id, other_id, ad)
			if score > best_score:
				best_score = score
				best_target = other_id

	var ai: Dictionary = _db.get_component(entity_id, &"ai_state")
	if best_score > ai[&"commitment_score"] + Constants.SWITCH_THRESHOLD:
		var target_pos: Dictionary = _db.get_component(best_target, &"position")
		_db.set_component(entity_id, &"ai_state", {
			&"state": &"SEEKING",
			&"meta_state": &"GOAL_DIRECTED",
			&"commitment_score": best_score,
		})
		_db.set_component(entity_id, &"target", {
			&"x": target_pos[&"x"],
			&"y": target_pos[&"y"],
			&"entity_id": best_target,
		})

func _pop_highest_deficit() -> int:
	var best_id: int = _dirty[0]
	var best_deficit: int = 0
	for id in _dirty:
		if not _db.has_entity(id):
			continue
		if not _db.has_component(id, &"desires"):
			continue
		var desires: Dictionary = _db.get_component(id, &"desires")
		for field in desires:
			if desires[field] > best_deficit:
				best_deficit = desires[field]
				best_id = id
	_dirty.erase(best_id)
	return best_id
```

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add engine/desires/desire_resolver.gd tests/unit/test_desire_resolver.gd
git commit -m "feat: implement DesireResolver with utility scoring and time-budgeted evaluation"
```

---

## Task 8: Scene Skeleton + Camera

**Files:**
- Create: `nodes/main.tscn` (described as code — build in editor or as `.tscn` text)
- Create: `nodes/game_server.gd`
- Create: `nodes/game_client.gd`
- Create: `nodes/camera_controller.gd`

- [ ] **Step 1: Create game_server.gd**

```gdscript
# nodes/game_server.gd
extends Node

var db: GameStateDB
var heat_grid: HeatGrid
var desire_resolver: DesireResolver

func _ready() -> void:
	db = GameStateDB.new()
	heat_grid = HeatGrid.new(db)
	desire_resolver = DesireResolver.new(db)

func _physics_process(_delta: float) -> void:
	db.advance_tick()
	heat_grid.propagate()
	_scatter_desires()
	desire_resolver.evaluate_budget()
	db.flush_notifications()

func _scatter_desires() -> void:
	# Scatter heat to warmth for all animals
	var animals: Array[int] = db.get_entities_with(&"desires")
	for entity_id in animals:
		if not db.has_component(entity_id, &"position"):
			continue
		var pos: Dictionary = db.get_component(entity_id, &"position")
		var rack: int = pos[&"x"] / Constants.RACK_WIDTH_PU
		var slot: int = pos[&"y"] / Constants.SLOT_HEIGHT_PU
		var cell: int
		if slot >= Constants.SLOTS_PER_RACK:
			cell = Constants.floor_cell(clampi(rack, 0, Constants.RACK_COUNT - 1))
		else:
			cell = Constants.rack_cell(
				clampi(rack, 0, Constants.RACK_COUNT - 1),
				clampi(slot, 0, Constants.SLOTS_PER_RACK - 1)
			)
		var temp: int = heat_grid.get_temperature(cell)
		db.set_field(entity_id, &"desires", &"warmth", 1000 - temp)
	# Comfort and curiosity decay
	db.add_all(&"desires", &"comfort", 5)
	db.add_all(&"desires", &"curiosity", 3)
	db.clamp_all(&"desires", &"warmth", 0, 1000)
	db.clamp_all(&"desires", &"comfort", 0, 1000)
	db.clamp_all(&"desires", &"curiosity", 0, 1000)
```

- [ ] **Step 2: Create camera_controller.gd**

```gdscript
# nodes/camera_controller.gd
extends Camera2D

const PAN_SPEED: float = 300.0
const ZOOM_LEVELS: Array[Vector2] = [Vector2(1.0, 1.0), Vector2(0.5, 0.5)]

var _zoom_index: int = 0

func _ready() -> void:
	# Center on the rack row
	var total_width: float = Constants.RACK_COUNT * (Constants.RACK_WIDTH_PX + Constants.RACK_GAP_PX)
	position = Vector2(total_width / 2.0, Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PX / 2.0)

func _process(delta: float) -> void:
	var input_dir: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("ui_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("ui_right"):
		input_dir.x += 1
	if Input.is_action_pressed("ui_up"):
		input_dir.y -= 1
	if Input.is_action_pressed("ui_down"):
		input_dir.y += 1
	position += input_dir * PAN_SPEED * delta

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_index = clampi(_zoom_index - 1, 0, ZOOM_LEVELS.size() - 1)
			zoom = ZOOM_LEVELS[_zoom_index]
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_index = clampi(_zoom_index + 1, 0, ZOOM_LEVELS.size() - 1)
			zoom = ZOOM_LEVELS[_zoom_index]
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_EQUAL or event.keycode == KEY_PAGEUP:
			_zoom_index = clampi(_zoom_index - 1, 0, ZOOM_LEVELS.size() - 1)
			zoom = ZOOM_LEVELS[_zoom_index]
		elif event.keycode == KEY_MINUS or event.keycode == KEY_PAGEDOWN:
			_zoom_index = clampi(_zoom_index + 1, 0, ZOOM_LEVELS.size() - 1)
			zoom = ZOOM_LEVELS[_zoom_index]
```

- [ ] **Step 3: Create game_client.gd**

```gdscript
# nodes/game_client.gd
extends Node

@onready var game_server: Node = get_node("../GameServer")
```

- [ ] **Step 4: Create main.tscn**

Build the scene tree in the Godot editor matching this hierarchy:

```
Root (Node)
  GameServer (Node) -> game_server.gd
  GameClient (Node) -> game_client.gd
    Camera (Camera2D) -> camera_controller.gd
    World (Node2D)
      RackRow (Node2D)
      Floor (Node2D)
      PlacedObjects (Node2D)
      Animals (Node2D)
      HeatOverlay (Node2D)
    PlacementUI (Control)
    SoundManager (Node)
```

Or write it as a `.tscn` text file. Set Camera as current. Verify in editor: scene runs, shows empty window, camera pans with arrow keys.

- [ ] **Step 5: Add static rack sprites to RackRow**

In `game_client.gd`, add `_ready()` to spawn rack backgrounds:

```gdscript
func _ready() -> void:
	_build_racks()
	_build_floor()

func _build_racks() -> void:
	var rack_texture: Texture2D = preload("res://mods/tcp_base/sprites/infrastructure/rack/rack_frame.png")
	var rack_row: Node2D = $World/RackRow
	for i in Constants.RACK_COUNT:
		var sprite := Sprite2D.new()
		sprite.texture = rack_texture
		sprite.centered = false
		sprite.position = Vector2(
			i * (Constants.RACK_WIDTH_PX + Constants.RACK_GAP_PX), 0
		)
		rack_row.add_child(sprite)

func _build_floor() -> void:
	var floor_texture: Texture2D = preload("res://mods/tcp_base/sprites/environment/floor_tile.png")
	var floor_node: Node2D = $World/Floor
	var floor_y: float = Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PX
	for i in Constants.RACK_COUNT:
		var sprite := Sprite2D.new()
		sprite.texture = floor_texture
		sprite.centered = false
		sprite.position = Vector2(
			i * (Constants.RACK_WIDTH_PX + Constants.RACK_GAP_PX), floor_y
		)
		floor_node.add_child(sprite)
```

- [ ] **Step 6: Run the game in the Godot editor**

Expected: 5 racks visible with floor strip below. Camera pans with arrow keys. Zoom with scroll wheel, +/-, PgUp/PgDn.

- [ ] **Step 7: Commit**

```bash
git add nodes/game_server.gd nodes/game_client.gd nodes/camera_controller.gd nodes/main.tscn
git commit -m "feat: add scene skeleton with 5 racks, floor, and camera controls"
```

---

## Task 9: Animal Node + First Cat on Screen

**Files:**
- Create: `nodes/animal_node.gd`
- Create: `nodes/animal.tscn`

- [ ] **Step 1: Create animal_node.gd**

```gdscript
# nodes/animal_node.gd
extends Node2D

var entity_id: int = Constants.INVALID_ID
var _db: GameStateDB
var _prev_pos: Vector2
var _target_pos: Vector2
var _sprite: AnimatedSprite2D
var _name_label: Label

func initialize(db: GameStateDB, eid: int) -> void:
	_db = db
	entity_id = eid
	var pos: Dictionary = _db.get_component(entity_id, &"position")
	_target_pos = Vector2(Constants.to_world(pos[&"x"]), Constants.to_world(pos[&"y"]))
	_prev_pos = _target_pos
	global_position = _target_pos

	var species: Dictionary = _db.get_component(entity_id, &"species")
	_setup_sprite(species)
	_setup_name_label(species)

func _setup_sprite(species: Dictionary) -> void:
	_sprite = $Sprite
	var variant: String = species.get(&"variant", "cat01")
	var idle_path: String = "res://mods/tcp_base/sprites/"
	if String(species[&"id"]).contains("cat"):
		idle_path += "cat/%s_idle_strip8.png" % variant
		_sprite.scale = Vector2(2.0, 2.0)
	else:
		idle_path += "ferret/%s_idle_strip8.png" % variant
		_sprite.scale = Vector2(2.0, 2.0)
	var texture: Texture2D = load(idle_path)
	if texture:
		_sprite.sprite_frames = _make_idle_frames(texture, 8)
		_sprite.play(&"idle")

func _setup_name_label(species: Dictionary) -> void:
	_name_label = $NameLabel
	_name_label.text = species.get(&"name", "???")

func _make_idle_frames(sheet: Texture2D, frame_count: int) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation(&"idle")
	frames.set_animation_speed(&"idle", 6)
	frames.set_animation_loop(&"idle", true)
	var frame_width: int = sheet.get_width() / frame_count
	var frame_height: int = sheet.get_height()
	for i in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * frame_width, 0, frame_width, frame_height)
		frames.add_frame(&"idle", atlas)
	return frames

func _physics_process(_delta: float) -> void:
	if _db == null or not _db.has_entity(entity_id):
		return
	_prev_pos = _target_pos
	var pos: Dictionary = _db.get_component(entity_id, &"position")
	_target_pos = Vector2(Constants.to_world(pos[&"x"]), Constants.to_world(pos[&"y"]))

func _process(_delta: float) -> void:
	var t: float = Engine.get_physics_interpolation_fraction()
	global_position = _prev_pos.lerp(_target_pos, t)
	z_index = 200 + int(global_position.y / 2.0)
```

- [ ] **Step 2: Create animal.tscn**

Build in editor:
```
AnimalRoot (Node2D) -> animal_node.gd
  Sprite (AnimatedSprite2D)
    texture_filter = NEAREST
  NameLabel (Label)
    position = Vector2(-20, -50)
    horizontal_alignment = CENTER
    custom_font_size = 8
```

- [ ] **Step 3: Spawn first cat in game_server.gd**

Add to `game_server.gd` `_ready()`:

```gdscript
func _ready() -> void:
	db = GameStateDB.new()
	heat_grid = HeatGrid.new(db)
	desire_resolver = DesireResolver.new(db)
	_spawn_starter_entities()

func _spawn_starter_entities() -> void:
	# Pre-placed server at rack 2, slot 20
	var server: int = db.create_entity()
	db.set_component(server, &"position", {
		&"x": 2 * Constants.RACK_WIDTH_PU,
		&"y": 20 * Constants.SLOT_HEIGHT_PU,
	})
	db.set_component(server, &"heat_source", {&"value": 800, &"radius_ru": 3})
	db.set_component(server, &"advertisements", {&"list": [
		{&"desire_type": &"warmth", &"strength": 800, &"radius_ru": 3, &"max_occupants": 1}
	]})

	# First cat: Mochi
	var cat: int = db.create_entity()
	db.set_component(cat, &"species", {
		&"id": &"tcp_base:cat", &"variant": &"cat01", &"name": &"Mochi"
	})
	db.set_component(cat, &"position", {
		&"x": 0 * Constants.RACK_WIDTH_PU,
		&"y": Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU,  # floor level
	})
	db.set_component(cat, &"desires", {&"warmth": 200, &"comfort": 200, &"curiosity": 0})
	db.set_component(cat, &"personality", {
		&"warmth_weight": 800, &"comfort_weight": 600, &"curiosity_weight": 100
	})
	db.set_component(cat, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0
	})
	db.set_component(cat, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID
	})
	db.update_spatial(cat, 0, Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU)
```

- [ ] **Step 4: Spawn AnimalNode in game_client.gd**

Add to `game_client.gd` `_ready()`:

```gdscript
var _animal_scene: PackedScene = preload("res://nodes/animal.tscn")

func _ready() -> void:
	_build_racks()
	_build_floor()
	# Wait one frame for GameServer to create entities
	await get_tree().process_frame
	_spawn_animal_nodes()

func _spawn_animal_nodes() -> void:
	var db: GameStateDB = game_server.db
	var animals: Array[int] = db.get_entities_with(&"species")
	for entity_id in animals:
		var node: Node2D = _animal_scene.instantiate()
		$World/Animals.add_child(node)
		node.initialize(db, entity_id)
```

- [ ] **Step 5: Run the game**

Expected: Mochi (cat01) is visible on screen at floor level, playing idle animation, with "Mochi" name label. 5 racks visible behind.

- [ ] **Step 6: Commit**

```bash
git add nodes/animal_node.gd nodes/animal.tscn nodes/game_server.gd nodes/game_client.gd
git commit -m "feat: spawn first cat (Mochi) on screen with idle animation and name label"
```

---

## Task 10: Heat Overlay

**Files:**
- Create: `nodes/heat_overlay.gd`

- [ ] **Step 1: Implement heat_overlay.gd**

```gdscript
# nodes/heat_overlay.gd
extends Node2D

var _db: GameStateDB
var _heat_grid: HeatGrid
var _visible: bool = false

func initialize(db: GameStateDB, heat_grid: HeatGrid) -> void:
	_db = db
	_heat_grid = heat_grid

func _process(_delta: float) -> void:
	if _visible:
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		_visible = not _visible
		queue_redraw()

func _draw() -> void:
	if not _visible or _heat_grid == null:
		return
	# Draw rack cells
	for rack in Constants.RACK_COUNT:
		for slot in Constants.SLOTS_PER_RACK:
			var cell: int = Constants.rack_cell(rack, slot)
			var temp: int = _heat_grid.get_temperature(cell)
			if temp <= 0:
				continue
			var x: float = rack * (Constants.RACK_WIDTH_PX + Constants.RACK_GAP_PX)
			var y: float = slot * Constants.SLOT_HEIGHT_PX
			var rect := Rect2(x, y, Constants.RACK_WIDTH_PX, Constants.SLOT_HEIGHT_PX)
			# Color: blue -> yellow -> red
			var color: Color
			if temp <= 500:
				color = Color(0.2, 0.3, 0.8).lerp(Color(0.9, 0.8, 0.2), float(temp) / 500.0)
			else:
				color = Color(0.9, 0.8, 0.2).lerp(Color(0.9, 0.2, 0.1), float(temp - 500) / 500.0)
			color.a = 0.25
			draw_rect(rect, color)
			# Pattern: hatching for color-blind accessibility
			var density: int = temp / 200  # 0-5 lines
			for i in density:
				var offset: float = float(i) * Constants.SLOT_HEIGHT_PX / float(density + 1)
				draw_line(
					Vector2(x, y + offset),
					Vector2(x + Constants.RACK_WIDTH_PX, y + offset),
					Color(1, 1, 1, 0.15), 1.0
				)
```

- [ ] **Step 2: Wire it up in game_client.gd**

In `_ready()` after spawning animals:

```gdscript
func _ready() -> void:
	_build_racks()
	_build_floor()
	await get_tree().process_frame
	_spawn_animal_nodes()
	_setup_heat_overlay()

func _setup_heat_overlay() -> void:
	var overlay: Node2D = $World/HeatOverlay
	overlay.set_script(preload("res://nodes/heat_overlay.gd"))
	overlay.initialize(game_server.db, game_server.heat_grid)
```

- [ ] **Step 3: Run the game, press H**

Expected: Heat overlay appears showing warm cells around the pre-placed server. Toggle with H key.

- [ ] **Step 4: Commit**

```bash
git add nodes/heat_overlay.gd nodes/game_client.gd
git commit -m "feat: add heat overlay toggle (press H) with color + hatch pattern"
```

---

## Tasks 11-15: Remaining Steps

These tasks follow the same pattern. Due to plan length constraints, I'll describe them at task level rather than step level. Each follows the TDD pattern: write failing test, implement, verify, commit.

---

## Task 11: Cat Walks Toward Server (Desire Integration)

**Files:**
- Modify: `nodes/game_server.gd` — wire desire resolver dirty marking from desire scatter
- Modify: `nodes/animal_node.gd` — read ai_state and move toward target
- Create: `tests/integration/test_desire_scatter.gd`

Connect the pieces: when heat scatter updates a cat's warmth desire past a threshold band, mark it dirty in the resolver. The resolver evaluates, finds the server advertisement, transitions the cat to SEEKING. The animal node reads the target position and lerps toward it each physics tick.

**Test:** Create a GameStateDB with one cold cat and one warm server. Run 100 ticks. Assert the cat's position has moved closer to the server and ai_state is SEEKING or SETTLING.

**Visible result:** Mochi walks toward the pre-placed server.

---

## Task 12: Hysteresis + Commitment

**Files:**
- Modify: `nodes/game_server.gd` — tick animal state machines, decay commitment
- Modify: `engine/desires/desire_resolver.gd` — check commitment before transitioning
- Create: `tests/integration/test_tick_loop.gd`

Each tick, decay commitment scores for all animals. When the server is removed, the cat's warmth drops but the commitment score keeps it in place for several seconds before it gives up and transitions.

**Test:** Setup cat at server. Remove server. Assert cat stays in LOAFING for at least 30 ticks (~3 seconds) before transitioning.

**Visible result:** Remove server, cat stays put for a few seconds, then reluctantly gets up and moves.

---

## Task 13: Ambient State Machine

**Files:**
- Modify: `nodes/animal_node.gd` — map AI states to sprite animations
- Modify: `nodes/game_server.gd` — run ambient state selection for non-goal-directed animals

When an animal is in AMBIENT meta-state and its current state's min_duration has elapsed, roll a weighted random ambient state based on context (warm → grooming/loafing/sleeping eligible).

**Test:** Run 1000 ticks with a warm cat. Count state distribution. Assert LOAFING + SLEEPING > 50% (warm cat should be content and settled).

**Visible result:** Mochi cycles through idle, grooming, loafing, sleeping animations near the warm server.

---

## Task 14: Purr Sound + Visual Indicator + Ambient Hum

**Files:**
- Create: `nodes/sound_manager.gd`
- Modify: `nodes/main.tscn` — attach sound_manager.gd to SoundManager node

Implement SoundManager with watcher-based purr counting, asymmetric volume fade (-20dB to -6dB), two pitch-offset purr loops, and a base ambient hum at -30dB.

Add visual purr indicator: when a cat is purring, show a small animated "~" or sound wave icon near the sprite.

**Test:** Create 3 cats, set 2 to LOAFING with warmth > 500. Assert purring_count is 2. Assert target volume is between -20dB and -6dB.

**Visible result:** Hear purring when Mochi is content. See visual indicator. Ambient hum always present.

---

## Task 15: Comfort Desire + Box + Clothes Pile

**Files:**
- Create: `nodes/placed_object_node.gd`
- Modify: `nodes/game_server.gd` — spawn pre-placed box, add comfort scatter
- Modify: `nodes/game_client.gd` — spawn placed object nodes

Add the second desire type. Objects advertise comfort. When comfort decays high enough and a comfort source is nearby, the cat evaluates it against its current warmth commitment.

**Visible result:** Cat chooses between warm server and comfy box based on personality weights.

---

## Task 16: Add Remaining Cats + Ferrets

**Files:**
- Modify: `nodes/game_server.gd` — spawn Biscuit (cat02), Noodle (cat03), Slinky (ferret), Bandit (ferret)
- Modify: `nodes/animal_node.gd` — add walk animation, ferret-specific ambient states

Spawn all 5 animals with different personality weights. Cats have high warmth_weight, low curiosity_weight. Ferrets have high curiosity_weight, low warmth_weight.

Add curiosity integration: when a ferret moves to a new cell, CuriosityTracker satisfies curiosity. Curiosity decays constantly, driving ferrets to keep exploring.

**Visible result:** Three cats make different choices about where to settle. Two ferrets patrol the floor, visibly different behavior.

---

## Task 17: Placement UI + Object Removal

**Files:**
- Create: `nodes/placement_ui.gd`
- Modify: `nodes/game_server.gd` — handle placement/removal intents
- Modify: `nodes/game_client.gd` — wire placement UI

Sidebar with 3 buttons (Server, Box, Pile) + Remove toggle. Placement ghost snaps to grid. Click to place. In remove mode, click to start 2-second CLEARING. Objects pulse during CLEARING. Animals get STARTLED when their object is removed.

Block placement if animal is in target slot.

**Visible result:** Player can place servers, boxes, and piles. Animals react to changes. Removing objects causes cats to startle and relocate.

---

## Task 18: Navigation Graph

**Files:**
- Create: `engine/navigation/species_astar.gd`
- Create: `engine/navigation/nav_graph_builder.gd`
- Create: `tests/unit/test_species_astar.gd`
- Modify: `nodes/game_server.gd` — build nav graph, use for pathfinding

Floor nodes + rack slot nodes. Cats can JUMP_UP to rack slots (max 3U). Ferrets stay on floor. When objects are placed/removed, nav graph updates dynamically.

**Test:** Build graph with floor nodes and one rack slot. Assert cat can find path to rack slot. Assert ferret cannot. Assert path updates when node is removed.

**Visible result:** Cats jump up to rack slots where servers are placed. Ferrets stay on the floor.

---

## Summary

| Task | What | Milestone |
|---|---|---|
| 1 | project.godot + constants + GUT | Godot opens |
| 2 | GameStateDB | Core data store tested |
| 3 | Event bus | Cross-system communication |
| 4 | Heat grid | Temperature propagation tested |
| 5 | Animal state machine | AI states tested |
| 6 | Curiosity tracker | Ferret exploration tested |
| 7 | Desire resolver | Utility scoring tested |
| 8 | Scene skeleton + camera | 5 racks on screen |
| 9 | Animal node + first cat | **Mochi on screen** |
| 10 | Heat overlay | See temperature (press H) |
| 11 | Desire integration | **Mochi walks to server** |
| 12 | Hysteresis | Mochi cares about her spot |
| 13 | Ambient states | Mochi grooms, loafs, sleeps |
| 14 | Purr + sound | **Hear purring** |
| 15 | Comfort + objects | Choose between warmth and comfort |
| 16 | All 5 animals | Different personalities, ferrets explore |
| 17 | Placement UI | Player arranges, animals react |
| 18 | Nav graph | Cats climb, ferrets stay low |
