# Purr-Power Objects & Food Loop Implementation Plan

> **Partially shipped — chain currently broken (as of 2026-04-17).** Core HUM
> reserve system, TUNA button/dispenser/arm loop, and contentment derivation
> are in-tree and working. The petting → satisfied → purr → HUM charge chain
> is **non-functional**: petting no longer advances through to HUM charge.
> See memory `project_petting_chain_broken.md`. Re-verify against the current
> code before treating any identifier, tick order, or signal name in this
> document as canonical.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the gameplay layer for purr-power Ring 0: placeable objects (HUM device, TUNA dispenser, button, ARM), cat food-seeking behavior states, and player interaction verbs (click button, pet, squeak).

**Architecture:** New object types registered via EntityDefRegistry and placed through the existing placement UI. Cat behavior states extend the existing state machine with goal-directed food-seeking states. Player verbs are click handlers that modify desire bars or emit signals.

**Tech Stack:** GDScript 4.x, GUT test framework, existing EntityDefRegistry/placement patterns

**Spec:** `docs/superpowers/specs/2026-04-12-purr-power-ring0-design.md`

**Prerequisites:** Plan 1 (Foundation) must be complete — 10U constants, hunger/attention desires, contentment derivation, and HUM system core.

**Sibling plans:** This is Plan 2 of 3. Plan 1 (Foundation) is complete. Plan 3 (Feedback & Presentation) is independent.

---

## File Map

### New files

| File | Responsibility |
|---|---|
| `mods/tcp_base/objects/hum_device.jsonc` | HUM device definition: 6U, hum_receiver component with radius |
| `mods/tcp_base/objects/tuna_dispenser.jsonc` | TUNA dispenser definition: 1U, requires HUM to operate |
| `mods/tcp_base/objects/tuna_button.jsonc` | Button definition: 1U, tethered to dispenser in same rack |
| `mods/tcp_base/objects/arm.jsonc` | ARM definition: floor object, opens cans within radius |
| `mods/tcp_base/objects/tuna_can.jsonc` | Tuna can definition: floor item, dropped by dispenser (already exists — may need updating) |
| `engine/core/food_system.gd` | Manages dispenser→can→arm→food pipeline and button press logic |
| `tests/unit/test_food_system.gd` | Unit tests for food system: dispense, arm open, button tethering |
| `tests/unit/test_cat_food_states.gd` | Unit tests for HUNGRY/PACING/EATING/RETURNING/SETTLING transitions |
| `tests/integration/test_food_loop.gd` | Integration test: full button→can→arm→eat→return cycle |

### Modified files

| File | Change |
|---|---|
| `nodes/game_server.gd` | Add FoodSystem init, add food state transitions to `_update_ambient_states()`, handle HUNGRY/PACING/EATING/RETURNING/SETTLING |
| `nodes/game_client.gd` | Add click handlers for button, pet, squeak verbs |
| `nodes/placement_ui.gd` | Add HUM device, TUNA dispenser, button, ARM to placement options |
| `engine/mod/entity_def_registry.gd` | Handle `hum_receiver` and `tuna_dispenser` component spawning |
| `engine/core/hum_system.gd` | Add `try_dispense(cost) -> bool` convenience method |

---

### Task 1: Object definitions (JSONC files)

**Files:**
- Create: `mods/tcp_base/objects/hum_device.jsonc`
- Create: `mods/tcp_base/objects/tuna_dispenser.jsonc`
- Create: `mods/tcp_base/objects/tuna_button.jsonc`
- Create: `mods/tcp_base/objects/arm.jsonc`
- Modify: `mods/tcp_tuna/objects/tuna_can.jsonc` (if needed)

- [ ] **Step 1: Create hum_device.jsonc**

```jsonc
{
  // HUM Device — Harmonic Uptime Matrix receiver + battery
  // 6U tall. Cats purring within radius contribute HUM charge.
  "schema_version": 1,
  "id": "tcp_base:hum_device",
  "name": "HUM Device",
  "size_ru": 6,
  "placement": "rack",
  "hum_receiver": {
    "radius_ru": 4
  },
  "physical": { "mass": 20000, "size_ru": 6 },
  "advertisements": []
}
```

- [ ] **Step 2: Create tuna_dispenser.jsonc**

```jsonc
{
  // TUNA — Tamper-sealed Utility Negotiation Asset dispenser
  // 1U. Drops sealed tuna cans when triggered. Requires HUM.
  "schema_version": 1,
  "id": "tcp_base:tuna_dispenser",
  "name": "TUNA Dispenser",
  "size_ru": 1,
  "placement": "rack",
  "tuna_dispenser": {
    "hum_cost": 50,
    "can_type": "tcp_tuna:tuna_can"
  },
  "physical": { "mass": 8000, "size_ru": 1 },
  "advertisements": [
    {
      "desire_type": "hunger",
      "strength": 300,
      "radius_ru": 6
    }
  ]
}
```

- [ ] **Step 3: Create tuna_button.jsonc**

```jsonc
{
  // Button — triggers the TUNA dispenser in the same rack.
  // 1U. Player clicks or ferret presses.
  "schema_version": 1,
  "id": "tcp_base:tuna_button",
  "name": "TUNA Button",
  "size_ru": 1,
  "placement": "rack",
  "tuna_button": {
    "tethered_to": "tcp_base:tuna_dispenser"
  },
  "physical": { "mass": 2000, "size_ru": 1 },
  "advertisements": []
}
```

- [ ] **Step 4: Create arm.jsonc**

```jsonc
{
  // ARM — Autonomous Retrieval Manipulator
  // Floor object. Opens sealed tuna cans within radius. Requires HUM.
  "schema_version": 1,
  "id": "tcp_base:arm",
  "name": "ARM",
  "size_ru": 2,
  "placement": "floor",
  "arm": {
    "radius_ru": 3,
    "hum_cost": 30,
    "open_duration_ticks": 20
  },
  "physical": { "mass": 15000, "size_ru": 2 },
  "advertisements": []
}
```

- [ ] **Step 5: Commit**

```bash
git add mods/tcp_base/objects/
git commit -m "feat(objects): add HUM device, TUNA dispenser, button, ARM definitions"
```

---

### Task 2: FoodSystem — dispense and arm logic

**Files:**
- Create: `engine/core/food_system.gd`
- Create: `tests/unit/test_food_system.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_food_system.gd`:

```gdscript
extends GutTest

var db: GameStateDB
var events: Events
var hum: HumSystem
var food: FoodSystem


func before_each() -> void:
	db = GameStateDB.new()
	events = Events.new()
	hum = HumSystem.new(db, events)
	food = FoodSystem.new(db, hum, events)


func test_press_button_dispenses_can_when_hum_available():
	var dispenser_id: int = _make_dispenser(1, 5)
	var button_id: int = _make_button(1, 6, dispenser_id)
	var arm_id: int = _make_arm(1)

	var result: int = food.press_button(button_id)
	assert_ne(result, Constants.INVALID_ID,
		"Pressing button with HUM should create a tuna can entity")
	assert_true(db.has_component(result, &"tuna_can"),
		"Created entity should have tuna_can component")


func test_press_button_fails_without_hum():
	var dispenser_id: int = _make_dispenser(1, 5)
	var button_id: int = _make_button(1, 6, dispenser_id)
	# Drain all HUM
	hum.drain_action(hum.get_reserve())

	var result: int = food.press_button(button_id)
	assert_eq(result, Constants.INVALID_ID,
		"Pressing button without HUM should fail")


func test_press_button_drains_hum():
	var dispenser_id: int = _make_dispenser(1, 5)
	var button_id: int = _make_button(1, 6, dispenser_id)
	var before: int = hum.get_reserve()
	food.press_button(button_id)
	var after: int = hum.get_reserve()
	assert_lt(after, before,
		"Dispensing should drain HUM")


func test_button_must_be_in_same_rack_as_dispenser():
	var dispenser_id: int = _make_dispenser(1, 5)
	# Button in a different rack
	var button_id: int = _make_button(3, 6, dispenser_id)

	var result: int = food.press_button(button_id)
	assert_eq(result, Constants.INVALID_ID,
		"Button in different rack than dispenser should not work")


func test_arm_opens_nearby_sealed_can():
	var arm_id: int = _make_arm(1)
	var can_id: int = _make_sealed_can(1)

	food.tick_arms()
	var can: Dictionary = db.get_component(can_id, &"tuna_can")
	assert_eq(can[&"state"], &"opened",
		"ARM should open sealed can within radius")


func test_arm_ignores_distant_can():
	var arm_id: int = _make_arm(1)
	var can_id: int = _make_sealed_can(5)  # far away

	food.tick_arms()
	var can: Dictionary = db.get_component(can_id, &"tuna_can")
	assert_eq(can[&"state"], &"sealed",
		"ARM should not open can outside radius")


func test_arm_requires_hum_to_open():
	var arm_id: int = _make_arm(1)
	var can_id: int = _make_sealed_can(1)
	hum.drain_action(hum.get_reserve())  # drain all

	food.tick_arms()
	var can: Dictionary = db.get_component(can_id, &"tuna_can")
	assert_eq(can[&"state"], &"sealed",
		"ARM without HUM should not open cans")


func test_opened_can_advertises_food():
	var arm_id: int = _make_arm(1)
	var can_id: int = _make_sealed_can(1)
	food.tick_arms()
	assert_true(db.has_component(can_id, &"advertisements"),
		"Opened can should have food advertisements")
	var ads: Dictionary = db.get_component(can_id, &"advertisements")
	var has_hunger_ad: bool = false
	for ad: Dictionary in ads[&"list"]:
		if ad[&"desire_type"] == &"hunger":
			has_hunger_ad = true
	assert_true(has_hunger_ad,
		"Opened can should advertise hunger satisfaction")


func test_opened_can_despawns_after_delay():
	var arm_id: int = _make_arm(1)
	var can_id: int = _make_sealed_can(1)
	food.tick_arms()
	# Set can to "eaten" state
	db.set_field(can_id, &"tuna_can", &"state", &"eaten")
	# Tick 100 times (10 seconds at 10Hz)
	for i in 100:
		food.tick_cleanup()
	assert_false(db.has_entity(can_id),
		"Eaten can should despawn after delay")


# ── Helpers ──

func _make_dispenser(rack: int, slot: int) -> int:
	var id: int = db.create_entity()
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = slot * Constants.SLOT_HEIGHT_PU
	db.set_component(id, &"position", {&"x": x, &"y": y})
	db.set_component(id, &"tuna_dispenser", {&"hum_cost": 50, &"can_type": &"tcp_tuna:tuna_can"})
	db.set_component(id, &"object_type", {&"type": &"tuna_dispenser"})
	db.update_spatial(id, x, y)
	return id


func _make_button(rack: int, slot: int, dispenser_id: int) -> int:
	var id: int = db.create_entity()
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = slot * Constants.SLOT_HEIGHT_PU
	db.set_component(id, &"position", {&"x": x, &"y": y})
	db.set_component(id, &"tuna_button", {&"dispenser_id": dispenser_id})
	db.set_component(id, &"object_type", {&"type": &"tuna_button"})
	db.update_spatial(id, x, y)
	return id


func _make_arm(rack: int) -> int:
	var id: int = db.create_entity()
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 2
	db.set_component(id, &"position", {&"x": x, &"y": y})
	db.set_component(id, &"arm", {&"radius_ru": 3, &"hum_cost": 30, &"open_duration_ticks": 20})
	db.set_component(id, &"object_type", {&"type": &"arm"})
	db.update_spatial(id, x, y)
	return id


func _make_sealed_can(rack: int) -> int:
	var id: int = db.create_entity()
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 4
	db.set_component(id, &"position", {&"x": x, &"y": y})
	db.set_component(id, &"tuna_can", {&"state": &"sealed", &"despawn_timer": 0})
	db.set_component(id, &"object_type", {&"type": &"tuna_can"})
	db.update_spatial(id, x, y)
	return id
```

- [ ] **Step 2: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_food_system.gd`
Expected: FAIL — `FoodSystem` class not found.

- [ ] **Step 3: Implement FoodSystem**

Create `engine/core/food_system.gd`:

```gdscript
class_name FoodSystem extends RefCounted

const CAN_DESPAWN_TICKS: int = 100  # ~10 seconds at 10Hz

var _db: GameStateDB
var _hum: HumSystem
var _events: Events


func _init(db: GameStateDB, hum: HumSystem, events: Events) -> void:
	_db = db
	_hum = hum
	_events = events


func press_button(button_id: int) -> int:
	if not _db.has_component(button_id, &"tuna_button"):
		return Constants.INVALID_ID

	var button_data: Dictionary = _db.get_component(button_id, &"tuna_button")
	var dispenser_id: int = button_data[&"dispenser_id"]

	if not _db.has_entity(dispenser_id):
		return Constants.INVALID_ID
	if not _db.has_component(dispenser_id, &"tuna_dispenser"):
		return Constants.INVALID_ID

	# Same-rack check
	var button_pos: Dictionary = _db.get_component(button_id, &"position")
	var disp_pos: Dictionary = _db.get_component(dispenser_id, &"position")
	@warning_ignore("integer_division")
	var button_rack: int = button_pos[&"x"] / Constants.RACK_WIDTH_PU
	@warning_ignore("integer_division")
	var disp_rack: int = disp_pos[&"x"] / Constants.RACK_WIDTH_PU
	if button_rack != disp_rack:
		return Constants.INVALID_ID

	# HUM cost check
	var disp_data: Dictionary = _db.get_component(dispenser_id, &"tuna_dispenser")
	var cost: int = disp_data[&"hum_cost"]
	if not _hum.has_reserve(cost):
		return Constants.INVALID_ID

	# Dispense
	_hum.drain_action(cost)
	var can_id: int = _db.create_entity()
	# Can drops to floor below the dispenser
	var can_x: int = disp_pos[&"x"]
	@warning_ignore("integer_division")
	var can_y: int = Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 4
	_db.set_component(can_id, &"position", {&"x": can_x, &"y": can_y})
	_db.set_component(can_id, &"tuna_can", {&"state": &"sealed", &"despawn_timer": 0})
	_db.set_component(can_id, &"object_type", {&"type": &"tuna_can"})
	_db.update_spatial(can_id, can_x, can_y)
	return can_id


func tick_arms() -> void:
	var arms: Array[int] = _db.get_entities_with(&"arm")
	for arm_id: int in arms:
		if not _db.has_component(arm_id, &"position"):
			continue
		var arm_data: Dictionary = _db.get_component(arm_id, &"arm")
		var arm_pos: Dictionary = _db.get_component(arm_id, &"position")
		var radius_pu: int = Constants.ru_to_pu(arm_data[&"radius_ru"])
		var cost: int = arm_data[&"hum_cost"]

		if not _hum.has_reserve(cost):
			continue

		var nearby: Array[int] = _db.query_radius(arm_pos[&"x"], arm_pos[&"y"], radius_pu)
		for entity_id: int in nearby:
			if not _db.has_component(entity_id, &"tuna_can"):
				continue
			var can: Dictionary = _db.get_component(entity_id, &"tuna_can")
			if can[&"state"] != &"sealed":
				continue
			if not _hum.has_reserve(cost):
				break
			_hum.drain_action(cost)
			_db.set_field(entity_id, &"tuna_can", &"state", &"opened")
			_db.set_component(entity_id, &"advertisements", {&"list": [
				{&"desire_type": &"hunger", &"strength": 900, &"radius_ru": 6, &"max_occupants": 1},
			]})


func tick_cleanup() -> void:
	var cans: Array[int] = _db.get_entities_with(&"tuna_can")
	var to_remove: Array[int] = []
	for can_id: int in cans:
		var can: Dictionary = _db.get_component(can_id, &"tuna_can")
		if can[&"state"] == &"eaten":
			var timer: int = can[&"despawn_timer"] + 1
			if timer >= CAN_DESPAWN_TICKS:
				to_remove.append(can_id)
			else:
				_db.set_field(can_id, &"tuna_can", &"despawn_timer", timer)
	for can_id: int in to_remove:
		_db.remove_spatial(can_id)
		_db.destroy_entity(can_id)
```

- [ ] **Step 4: Run tests and verify pass**

Run: `script/checks/gut_tests -f tests/unit/test_food_system.gd`
Expected: All 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add engine/core/food_system.gd tests/unit/test_food_system.gd
git commit -m "feat(food): FoodSystem — dispense, arm open, cleanup pipeline"
```

---

### Task 3: Cat food-seeking behavior states

Add HUNGRY, PACING, EATING, RETURNING, SETTLING states to the cat state machine.

**Files:**
- Create: `tests/unit/test_cat_food_states.gd`
- Modify: `nodes/game_server.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_cat_food_states.gd`:

```gdscript
extends GutTest

var db: GameStateDB


func before_each() -> void:
	db = GameStateDB.new()


func test_content_cat_transitions_to_hungry_when_hunger_drops():
	var cat_id: int = _make_content_cat()
	# Hunger drops below threshold
	db.set_field(cat_id, &"desires", &"hunger", 300)
	var should_transition: bool = _should_become_hungry(cat_id)
	assert_true(should_transition,
		"Cat with hunger below 400 threshold should transition to HUNGRY")


func test_content_cat_stays_content_when_hunger_above_threshold():
	var cat_id: int = _make_content_cat()
	db.set_field(cat_id, &"desires", &"hunger", 500)
	var should_transition: bool = _should_become_hungry(cat_id)
	assert_false(should_transition,
		"Cat with hunger above threshold should stay content")


func test_hungry_cat_targets_nearest_dispenser():
	var cat_id: int = _make_hungry_cat(1, 5)
	var disp1: int = _make_dispenser(1, 3)  # close
	var disp2: int = _make_dispenser(5, 3)  # far

	var target: int = _find_nearest_dispenser(cat_id)
	assert_eq(target, disp1,
		"Hungry cat should target nearest dispenser")


func test_hungry_cat_without_dispenser_wanders():
	var cat_id: int = _make_hungry_cat(1, 5)
	var target: int = _find_nearest_dispenser(cat_id)
	assert_eq(target, Constants.INVALID_ID,
		"Hungry cat without dispenser should get INVALID_ID (wander)")


func test_eating_cat_hunger_increases():
	var cat_id: int = _make_content_cat()
	db.set_field(cat_id, &"desires", &"hunger", 200)
	db.set_field(cat_id, &"ai_state", &"state", &"EATING")
	# Simulate eating: hunger refills
	var eat_amount: int = 500
	var hunger: int = db.get_field(cat_id, &"desires", &"hunger")
	db.set_field(cat_id, &"desires", &"hunger", mini(1000, hunger + eat_amount))
	assert_eq(db.get_field(cat_id, &"desires", &"hunger"), 700,
		"Eating should increase hunger satisfaction")


# ── Helpers ──

func _make_content_cat() -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"species", {&"id": &"tcp_cats:cat", &"variant": &"cat01", &"name": &"Test"})
	db.set_component(id, &"desires", {
		&"warmth": 700, &"comfort": 700, &"hunger": 700, &"attention": 500, &"curiosity": 500,
	})
	db.set_component(id, &"ai_state", {
		&"state": &"LOAFING", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	db.set_component(id, &"position", {&"x": 0, &"y": 0})
	db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID, &"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(id, 0, 0)
	return id


func _make_hungry_cat(rack: int, slot: int) -> int:
	var id: int = _make_content_cat()
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = slot * Constants.SLOT_HEIGHT_PU
	db.set_component(id, &"position", {&"x": x, &"y": y})
	db.set_field(id, &"desires", &"hunger", 200)
	db.set_field(id, &"ai_state", &"state", &"HUNGRY")
	db.update_spatial(id, x, y)
	return id


func _make_dispenser(rack: int, slot: int) -> int:
	var id: int = db.create_entity()
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = slot * Constants.SLOT_HEIGHT_PU
	db.set_component(id, &"position", {&"x": x, &"y": y})
	db.set_component(id, &"tuna_dispenser", {&"hum_cost": 50, &"can_type": &"tcp_tuna:tuna_can"})
	db.set_component(id, &"object_type", {&"type": &"tuna_dispenser"})
	db.update_spatial(id, x, y)
	return id


func _should_become_hungry(entity_id: int) -> bool:
	var desires: Dictionary = db.get_component(entity_id, &"desires")
	return desires[&"hunger"] < 400


func _find_nearest_dispenser(entity_id: int) -> int:
	var pos: Dictionary = db.get_component(entity_id, &"position")
	var dispensers: Array[int] = db.get_entities_with(&"tuna_dispenser")
	if dispensers.is_empty():
		return Constants.INVALID_ID
	var best_id: int = Constants.INVALID_ID
	var best_dist: int = 999999
	for disp_id: int in dispensers:
		var dpos: Dictionary = db.get_component(disp_id, &"position")
		var dist: int = absi(dpos[&"x"] - pos[&"x"]) + absi(dpos[&"y"] - pos[&"y"])
		if dist < best_dist:
			best_dist = dist
			best_id = disp_id
	return best_id
```

- [ ] **Step 2: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_cat_food_states.gd`
Expected: Tests pass (these are logic tests using existing DB, no new classes needed yet). If they pass, good — these validate the helpers we'll use in integration.

- [ ] **Step 3: Add food state transitions to game_server.gd**

In `_update_ambient_states()`, add a hunger check before the ambient state picker. After the STARTLED recovery block and before the ambient min-duration check:

```gdscript
# Check if cat should transition to HUNGRY
if ai[&"meta_state"] == &"AMBIENT" and db.has_component(entity_id, &"desires"):
	var desires: Dictionary = db.get_component(entity_id, &"desires")
	if desires.has(&"hunger") and desires[&"hunger"] < 400:
		# Find nearest dispenser
		var target_id: int = _find_nearest_dispenser(entity_id)
		if target_id != Constants.INVALID_ID:
			var tpos: Dictionary = db.get_component(target_id, &"position")
			db.set_component(entity_id, &"ai_state", {
				&"state": &"HUNGRY",
				&"meta_state": &"GOAL_DIRECTED",
				&"commitment_score": 200,
			})
			db.set_component(entity_id, &"target", {
				&"x": tpos[&"x"], &"y": tpos[&"y"],
				&"entity_id": target_id,
			})
			_state_timers[entity_id] = 0.0
			continue
		else:
			# No dispenser — wander and meow
			db.set_component(entity_id, &"ai_state", {
				&"state": &"PACING",
				&"meta_state": &"GOAL_DIRECTED",
				&"commitment_score": 200,
			})
			_state_timers[entity_id] = 0.0
			continue
```

- [ ] **Step 4: Handle HUNGRY arrival → PACING/EATING**

In `_move_animals()`, when a HUNGRY cat arrives at its target (the dispenser), check if food is available:

```gdscript
# After arrival, check state
if state == &"HUNGRY":
	# Look for opened tuna cans nearby
	var food_id: int = _find_nearby_food(entity_id)
	if food_id != Constants.INVALID_ID:
		db.set_component(entity_id, &"ai_state", {
			&"state": &"EATING",
			&"meta_state": &"GOAL_DIRECTED",
			&"commitment_score": 300,
		})
		_state_timers[entity_id] = 0.0
	else:
		db.set_component(entity_id, &"ai_state", {
			&"state": &"PACING",
			&"meta_state": &"GOAL_DIRECTED",
			&"commitment_score": 100,
		})
		_state_timers[entity_id] = 0.0
```

- [ ] **Step 5: Add EATING → RETURNING → SETTLING → CONTENT transitions**

In `_update_ambient_states()`, handle the food loop states:

```gdscript
# PACING: check if food appeared
if ai[&"state"] == &"PACING":
	var food_id: int = _find_nearby_food(entity_id)
	if food_id != Constants.INVALID_ID:
		db.set_component(entity_id, &"ai_state", {
			&"state": &"EATING",
			&"meta_state": &"GOAL_DIRECTED",
			&"commitment_score": 300,
		})
		_state_timers[entity_id] = 0.0
	continue

# EATING: refill hunger, then transition to RETURNING
if ai[&"state"] == &"EATING":
	_state_timers[entity_id] = _state_timers.get(entity_id, 0.0) + tick_delta
	# Eat for 3 seconds, refilling hunger over time
	db.add_field(entity_id, &"desires", &"hunger", 30)
	db.clamp_field(entity_id, &"desires", &"hunger", 0, 1000)
	if _state_timers[entity_id] >= 3.0:
		# Mark can as eaten
		_mark_nearest_can_eaten(entity_id)
		# Find home box to return to
		var box_id: int = _find_nearest_box(entity_id)
		if box_id != Constants.INVALID_ID:
			var bpos: Dictionary = db.get_component(box_id, &"position")
			db.set_component(entity_id, &"ai_state", {
				&"state": &"RETURNING",
				&"meta_state": &"GOAL_DIRECTED",
				&"commitment_score": 150,
			})
			db.set_component(entity_id, &"target", {
				&"x": bpos[&"x"], &"y": bpos[&"y"],
				&"entity_id": box_id,
			})
		else:
			db.set_component(entity_id, &"ai_state", {
				&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
			})
		_state_timers[entity_id] = 0.0
	continue

# SETTLING: wait, then become CONTENT
if ai[&"state"] == &"SETTLING":
	_state_timers[entity_id] = _state_timers.get(entity_id, 0.0) + tick_delta
	if _state_timers[entity_id] >= 2.0:
		db.set_component(entity_id, &"ai_state", {
			&"state": &"LOAFING", &"meta_state": &"AMBIENT", &"commitment_score": 0,
		})
		_state_timers[entity_id] = 0.0
	continue
```

And in `_move_animals()`, handle RETURNING arrival → SETTLING:

```gdscript
if state == &"RETURNING":
	db.set_component(entity_id, &"ai_state", {
		&"state": &"SETTLING",
		&"meta_state": &"GOAL_DIRECTED",
		&"commitment_score": 50,
	})
	_state_timers[entity_id] = 0.0
```

- [ ] **Step 6: Add helper methods to game_server.gd**

```gdscript
func _find_nearest_dispenser(entity_id: int) -> int:
	var pos: Dictionary = db.get_component(entity_id, &"position")
	var dispensers: Array[int] = db.get_entities_with(&"tuna_dispenser")
	var best_id: int = Constants.INVALID_ID
	var best_dist: int = 999999
	for disp_id: int in dispensers:
		var dpos: Dictionary = db.get_component(disp_id, &"position")
		var dist: int = absi(dpos[&"x"] - pos[&"x"]) + absi(dpos[&"y"] - pos[&"y"])
		if dist < best_dist:
			best_dist = dist
			best_id = disp_id
	return best_id


func _find_nearby_food(entity_id: int) -> int:
	var pos: Dictionary = db.get_component(entity_id, &"position")
	var nearby: Array[int] = db.query_radius(pos[&"x"], pos[&"y"], Constants.ru_to_pu(3))
	for other_id: int in nearby:
		if db.has_component(other_id, &"tuna_can"):
			var can: Dictionary = db.get_component(other_id, &"tuna_can")
			if can[&"state"] == &"opened":
				return other_id
	return Constants.INVALID_ID


func _find_nearest_box(entity_id: int) -> int:
	var pos: Dictionary = db.get_component(entity_id, &"position")
	var objects: Array[int] = db.get_entities_with(&"object_type")
	var best_id: int = Constants.INVALID_ID
	var best_dist: int = 999999
	for obj_id: int in objects:
		var otype: Dictionary = db.get_component(obj_id, &"object_type")
		if otype[&"type"] != &"cardboard_box":
			continue
		var opos: Dictionary = db.get_component(obj_id, &"position")
		var dist: int = absi(opos[&"x"] - pos[&"x"]) + absi(opos[&"y"] - pos[&"y"])
		if dist < best_dist:
			best_dist = dist
			best_id = obj_id
	return best_id


func _mark_nearest_can_eaten(entity_id: int) -> void:
	var food_id: int = _find_nearby_food(entity_id)
	if food_id != Constants.INVALID_ID:
		db.set_field(food_id, &"tuna_can", &"state", &"eaten")
		db.remove_component(food_id, &"advertisements")
```

Note: `add_field` and `clamp_field` may need to be added to GameStateDB if they don't exist. Check and add:

```gdscript
# In game_state_db.gd
func add_field(entity_id: int, component: StringName, field: StringName, delta: int) -> void:
	var value: int = get_field(entity_id, component, field)
	set_field(entity_id, component, field, value + delta)

func clamp_field(entity_id: int, component: StringName, field: StringName, min_val: int, max_val: int) -> void:
	var value: int = get_field(entity_id, component, field)
	set_field(entity_id, component, field, clampi(value, min_val, max_val))
```

- [ ] **Step 7: Wire FoodSystem into game_server.gd tick loop**

Add to variable declarations:

```gdscript
var food_system: FoodSystem
```

In `_ready()`:

```gdscript
food_system = FoodSystem.new(db, hum_system, events)
```

In `_physics_process()`, after movement and before `_update_ambient_states()`:

```gdscript
food_system.tick_arms()
food_system.tick_cleanup()
```

- [ ] **Step 8: Run full test suite**

Run: `script/checks/gut_tests`
Expected: All pass.

- [ ] **Step 9: Commit**

```bash
git add engine/core/food_system.gd engine/core/game_state_db.gd nodes/game_server.gd tests/
git commit -m "feat(food): cat HUNGRY/PACING/EATING/RETURNING/SETTLING state loop"
```

---

### Task 4: Player verbs — click button, pet, squeak

**Files:**
- Modify: `nodes/game_client.gd`
- Create: `tests/unit/test_player_verbs.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_player_verbs.gd`:

```gdscript
extends GutTest

var db: GameStateDB


func before_each() -> void:
	db = GameStateDB.new()


func test_petting_fills_attention():
	var cat_id: int = _make_cat(300)  # attention at 300
	var fill_amount: int = 500
	var attention: int = db.get_field(cat_id, &"desires", &"attention")
	db.set_field(cat_id, &"desires", &"attention", mini(1000, attention + fill_amount))
	assert_eq(db.get_field(cat_id, &"desires", &"attention"), 800,
		"Petting should add to attention bar")


func test_petting_clamps_at_1000():
	var cat_id: int = _make_cat(900)
	db.set_field(cat_id, &"desires", &"attention", mini(1000, 900 + 500))
	assert_eq(db.get_field(cat_id, &"desires", &"attention"), 1000,
		"Attention should clamp at 1000")


func test_squeak_sets_target_to_box():
	var cat_id: int = _make_cat(500)
	var box_id: int = db.create_entity()
	var bx: int = 3 * Constants.RACK_WIDTH_PU
	var by: int = 5 * Constants.SLOT_HEIGHT_PU
	db.set_component(box_id, &"position", {&"x": bx, &"y": by})
	db.set_component(box_id, &"object_type", {&"type": &"cardboard_box"})

	# Simulate squeak: set cat target to box and state to RETURNING
	db.set_component(cat_id, &"target", {&"x": bx, &"y": by, &"entity_id": box_id})
	db.set_component(cat_id, &"ai_state", {
		&"state": &"RETURNING", &"meta_state": &"GOAL_DIRECTED", &"commitment_score": 200,
	})

	var target: Dictionary = db.get_component(cat_id, &"target")
	assert_eq(target[&"entity_id"], box_id,
		"Squeak should set cat target to the squeaked box")
	var ai: Dictionary = db.get_component(cat_id, &"ai_state")
	assert_eq(ai[&"state"], &"RETURNING",
		"Squeak should set cat to RETURNING state")


func _make_cat(attention: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"species", {&"id": &"tcp_cats:cat", &"variant": &"cat01", &"name": &"Test"})
	db.set_component(id, &"desires", {
		&"warmth": 700, &"comfort": 700, &"hunger": 700,
		&"attention": attention, &"curiosity": 500,
	})
	db.set_component(id, &"ai_state", {
		&"state": &"PACING", &"meta_state": &"GOAL_DIRECTED", &"commitment_score": 0,
	})
	db.set_component(id, &"position", {&"x": 0, &"y": 0})
	db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID, &"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(id, 0, 0)
	return id
```

- [ ] **Step 2: Implement click handlers in game_client.gd**

Add methods for the three player verbs. These will be called from `_unhandled_input()` based on what entity is under the cursor:

```gdscript
func _handle_click_on_entity(entity_id: int) -> void:
	if not game_server.db.has_entity(entity_id):
		return

	# Click on button → press it
	if game_server.db.has_component(entity_id, &"tuna_button"):
		game_server.food_system.press_button(entity_id)
		return

	# Click on cat → pet it
	if game_server.db.has_component(entity_id, &"species"):
		_pet_animal(entity_id)
		return

	# Click on box → squeak it
	if game_server.db.has_component(entity_id, &"object_type"):
		var otype: Dictionary = game_server.db.get_component(entity_id, &"object_type")
		if otype[&"type"] == &"cardboard_box":
			_squeak_box(entity_id)
			return


func _pet_animal(entity_id: int) -> void:
	if not game_server.db.has_component(entity_id, &"desires"):
		return
	var attention: int = game_server.db.get_field(entity_id, &"desires", &"attention")
	game_server.db.set_field(entity_id, &"desires", &"attention", mini(1000, attention + 500))


func _squeak_box(box_id: int) -> void:
	var box_pos: Dictionary = game_server.db.get_component(box_id, &"position")
	# Find all cats within earshot (6 RU)
	var nearby: Array[int] = game_server.db.query_radius(
		box_pos[&"x"], box_pos[&"y"], Constants.ru_to_pu(6)
	)
	for entity_id: int in nearby:
		if not game_server.db.has_component(entity_id, &"species"):
			continue
		# Only redirect cats that are PACING, HUNGRY, or RETURNING
		var ai: Dictionary = game_server.db.get_component(entity_id, &"ai_state")
		if ai[&"state"] in [&"PACING", &"HUNGRY", &"RETURNING", &"EATING"]:
			game_server.db.set_component(entity_id, &"ai_state", {
				&"state": &"RETURNING",
				&"meta_state": &"GOAL_DIRECTED",
				&"commitment_score": 200,
			})
			game_server.db.set_component(entity_id, &"target", {
				&"x": box_pos[&"x"],
				&"y": box_pos[&"y"],
				&"entity_id": box_id,
			})
```

- [ ] **Step 3: Wire click handlers to input**

In `_unhandled_input()`, add entity detection under cursor. The specifics depend on how the current hit-detection works (Area2D queries or position math). The implementing agent should check the current input handling pattern and extend it.

- [ ] **Step 4: Run tests**

Run: `script/checks/gut_tests`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add nodes/game_client.gd tests/unit/test_player_verbs.gd
git commit -m "feat(verbs): player click handlers — button press, pet, squeak"
```

---

### Task 5: Placement UI — add new objects

**Files:**
- Modify: `nodes/placement_ui.gd`

- [ ] **Step 1: Add new object types to placement options**

The current placement UI uses keyboard shortcuts 1/2/3 for server/box/pile. Add:

```gdscript
# New placement options
# Key 4: HUM device (6U)
# Key 5: TUNA dispenser (1U)
# Key 6: Button (1U)
# Key 7: ARM (floor object)
```

Add to the match block in the placement handler:

```gdscript
&"hum_device":
	db.set_component(entity, &"hum_receiver", {&"radius_ru": 4})
&"tuna_dispenser":
	db.set_component(entity, &"tuna_dispenser", {&"hum_cost": 50, &"can_type": &"tcp_tuna:tuna_can"})
	db.set_component(entity, &"advertisements", {&"list": [
		{&"desire_type": &"hunger", &"strength": 300, &"radius_ru": 6},
	]})
&"tuna_button":
	# Find the dispenser in the same rack and link to it
	var disp_id: int = _find_dispenser_in_rack(rack)
	if disp_id == Constants.INVALID_ID:
		push_error("No TUNA dispenser in this rack to tether button to")
		return Constants.INVALID_ID
	db.set_component(entity, &"tuna_button", {&"dispenser_id": disp_id})
&"arm":
	db.set_component(entity, &"arm", {&"radius_ru": 3, &"hum_cost": 30, &"open_duration_ticks": 20})
```

Note: HUM device placement should be restricted to rack slots and validate that 6 consecutive slots are available. The implementing agent should check how the current slot validation works and extend it for multi-slot objects.

- [ ] **Step 2: Add size validation for multi-slot objects**

The HUM device is 6U. When placing it, validate that 6 contiguous slots starting from the target slot are empty. Add a helper:

```gdscript
func _validate_multi_slot(rack: int, start_slot: int, size_ru: int) -> bool:
	for i in size_ru:
		var slot: int = start_slot + i
		if slot >= Constants.SLOTS_PER_RACK:
			return false
		# Check if slot is occupied (query for entities at that position)
		var x: int = rack * Constants.RACK_WIDTH_PU
		var y: int = slot * Constants.SLOT_HEIGHT_PU
		var occupants: Array[int] = db.query_radius(x, y, Constants.SLOT_HEIGHT_PU / 2)
		for occ_id: int in occupants:
			if db.has_component(occ_id, &"object_type"):
				return false
	return true
```

- [ ] **Step 3: Test placement manually**

Run the game and verify you can place all new object types.

- [ ] **Step 4: Commit**

```bash
git add nodes/placement_ui.gd nodes/game_server.gd
git commit -m "feat(placement): add HUM device, TUNA dispenser, button, ARM to placement UI"
```

---

### Task 6: Integration test — full food loop

**Files:**
- Create: `tests/integration/test_food_loop.gd`

- [ ] **Step 1: Write the integration test**

```gdscript
extends GutTest

var game_server: Node


func before_each() -> void:
	game_server = preload("res://nodes/game_server.gd").new()
	add_child_autofree(game_server)


func test_full_food_loop_button_to_eat_to_return():
	# Place infrastructure: dispenser + button + arm + box
	var disp_id: int = game_server.place_object(&"tuna_dispenser", 1 * Constants.RACK_WIDTH_PU, 5 * Constants.SLOT_HEIGHT_PU)
	var button_id: int = game_server.place_object(&"tuna_button", 1 * Constants.RACK_WIDTH_PU, 6 * Constants.SLOT_HEIGHT_PU)
	# Link button to dispenser
	game_server.db.set_component(button_id, &"tuna_button", {&"dispenser_id": disp_id})

	var arm_id: int = game_server.place_object(&"arm", 1 * Constants.RACK_WIDTH_PU, Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + 100)
	var box_id: int = game_server.place_object(&"cardboard_box", 2 * Constants.RACK_WIDTH_PU, 3 * Constants.SLOT_HEIGHT_PU)

	# Make a hungry cat
	var cats: Array[int] = game_server.db.get_entities_with(&"species")
	assert_gt(cats.size(), 0, "Need at least one cat")
	var cat_id: int = cats[0]
	game_server.db.set_field(cat_id, &"desires", &"hunger", 100)

	# Press the button
	var can_id: int = game_server.food_system.press_button(button_id)
	assert_ne(can_id, Constants.INVALID_ID, "Button press should create a can")

	# Run ticks until arm opens the can
	for i in 30:
		game_server._physics_process(0.1)

	# Verify can is opened
	if game_server.db.has_entity(can_id):
		var can: Dictionary = game_server.db.get_component(can_id, &"tuna_can")
		assert_eq(can[&"state"], &"opened",
			"ARM should open the can within 30 ticks")
```

- [ ] **Step 2: Run test**

Run: `script/checks/gut_tests -f tests/integration/test_food_loop.gd`
Expected: Pass.

- [ ] **Step 3: Commit**

```bash
git add tests/integration/test_food_loop.gd
git commit -m "test(food): integration test for full button→can→arm→eat loop"
```

---

### Task 7: Stamp all tests

- [ ] **Step 1: Stamp new test files**

```bash
script/stamp_tests tests/unit/test_food_system.gd
script/stamp_tests tests/unit/test_cat_food_states.gd
script/stamp_tests tests/unit/test_player_verbs.gd
script/stamp_tests tests/integration/test_food_loop.gd
```

- [ ] **Step 2: Re-stamp modified files**

```bash
script/stamp_tests tests/integration/test_desire_scatter.gd
```

And any other files modified during this plan.

- [ ] **Step 3: Verify stamps**

Run: `script/checks/verify_tests`
Expected: All stamps valid.

- [ ] **Step 4: Run full validation**

Run: `script/validate`
Expected: All checks pass.

- [ ] **Step 5: Commit**

```bash
git add tests/
git commit -m "chore(tests): stamp all new and modified test files for food loop"
```

---

## Verification Checklist

After all tasks complete, verify:

- [ ] HUM device (6U) placeable in rack slots
- [ ] TUNA dispenser (1U) placeable in rack slots
- [ ] Button (1U) placeable, auto-tethers to dispenser in same rack
- [ ] ARM placeable on floor
- [ ] Button press → can drops → ARM opens → food available
- [ ] Button press fails without HUM reserve
- [ ] ARM fails without HUM reserve
- [ ] Hungry cat transitions CONTENT → HUNGRY → walks to dispenser
- [ ] Cat at dispenser without food → PACING (meows)
- [ ] Food appears → PACING → EATING (hunger refills)
- [ ] EATING complete → RETURNING → walks to box
- [ ] RETURNING arrival → SETTLING → CONTENT (purring resumes)
- [ ] Petting fills attention bar by 500
- [ ] Squeak redirects nearby pacing/hungry cats to target box
- [ ] Empty cans despawn after ~10 seconds
- [ ] `script/validate` passes
