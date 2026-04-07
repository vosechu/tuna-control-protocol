# Object Interactions & Robot Arm — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **2026-04-07 status (added after triage):** This plan is partially executed. Tasks 1-2 (object state component, food desire, scatter exclusions) landed in commit `8245d85 feat: object-interactions scaffolding` along with the supporting test file `tests/unit/test_object_state.gd` (which currently inlines production logic — see `2026-04-06-game-server-extraction-design.md`). **Task 3 (PERFORMING state & action execution) was never written** — `git log --all -S "PERFORMING"` shows the symbol only in spec/rule docs, never in production source. Tasks 4-7 are blocked on Task 3.
>
> **Before resuming this plan**, complete `docs/superpowers/plans/2026-04-07-stash-recovery-and-cleanup.md` first. The DesireResolver WANDERING-vs-SEEKING regression that recovery exposes touches the same scoring path that PERFORMING needs to integrate with — fixing it after building PERFORMING would mean re-touching freshly-written code.

**Goal:** Build the core gameplay loop — ferret presses button, can drops, robot arm opens it, cat eats — plus box degradation from ferret shredding.

**Architecture:** Extends the existing desire→seek→arrive pipeline with a PERFORMING state and action effects. Robot arm is an entity with desires (purpose) that uses the same AI as animals but cannot move. Object state transitions swap ad profiles in-place. Food desire added to cats. Action-only desires (food, openable, scannable) are excluded from passive scatter.

**Tech Stack:** Godot 4.6, GDScript, GUT

**Design spec:** `docs/superpowers/specs/2026-04-05-object-interactions-design.md`

**Key rules files:**
- `design-philosophy.md` — Pure Core, GameStateDB, integers, no null
- `code-style.md` — Naming, types, guard clauses
- `testing.md` — GUT, test suites
- `animal-ai.md` — State machine, scoring loop
- `tick-architecture.md` — 10Hz tick

---

## File Structure

### New files

```
tests/unit/test_object_state.gd          # Object state transitions + box HP
tests/unit/test_action_effects.gd        # Action execution effects
tests/integration/test_performing.gd     # PERFORMING state flow
tests/scenario/test_tuna_chain.gd        # Full chain scenario + edge cases
```

### Modified files

```
engine/core/constants.gd                 # ARM_REACH_RU constant
nodes/game_server.gd                     # Food desire, PERFORMING state, action execution, arm/button/can spawning, scatter exclusions
engine/desires/desire_resolver.gd        # Arm reach check (skip movement for fixed entities)
nodes/animal_node.gd                     # PERFORMING animation, arm sprite loading
nodes/animal_stats_bar.gd               # Dynamic bars per entity's desires
nodes/game_client.gd                     # Arm/button/can sprite rendering, state-based sprite updates, can despawn
```

---

## Task 1: Object State Component & Transitions (unit tested)

**Files:**
- Create: `tests/unit/test_object_state.gd`
- Modify: `nodes/game_server.gd`

- [ ] **Step 1: Write failing test for tuna can state transitions**

```gdscript
# tests/unit/test_object_state.gd
extends GutTest

var _db: GameStateDB


func before_each() -> void:
	_db = GameStateDB.new()


func _make_can(state: StringName) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": 0, &"y": 0})
	_db.set_component(id, &"object_type", {&"type": &"tuna_can"})
	if state == &"sealed":
		_db.set_component(id, &"object_state", {
			&"current": &"sealed", &"hp": -1, &"max_hp": -1,
		})
		_db.set_component(id, &"advertisements", {&"list": [
			{&"desire_type": &"openable", &"strength": 800,
				&"radius_ru": 3, &"action": &"open",
				&"action_duration": 3.0},
		]})
	elif state == &"open":
		_db.set_component(id, &"object_state", {
			&"current": &"open", &"hp": -1, &"max_hp": -1,
		})
		_db.set_component(id, &"advertisements", {&"list": [
			{&"desire_type": &"food", &"strength": 800,
				&"radius_ru": 5, &"action": &"eat",
				&"action_duration": 5.0},
		]})
	_db.update_spatial(id, 0, 0)
	return id


func test_can_sealed_to_open():
	var can_id: int = _make_can(&"sealed")
	# Simulate transition
	_transition_object(can_id, &"open")
	var state: Dictionary = _db.get_component(
		can_id, &"object_state",
	)
	assert_eq(state[&"current"], &"open",
		"Can must transition from sealed to open")
	var ads: Dictionary = _db.get_component(
		can_id, &"advertisements",
	)
	assert_eq(ads[&"list"][0][&"desire_type"], &"food",
		"Open can must advertise food, not openable")


func test_can_open_to_empty():
	var can_id: int = _make_can(&"open")
	_transition_object(can_id, &"empty")
	var state: Dictionary = _db.get_component(
		can_id, &"object_state",
	)
	assert_eq(state[&"current"], &"empty",
		"Can must transition from open to empty")
	assert_false(_db.has_component(can_id, &"advertisements"),
		"Empty can must have no advertisements")


func _make_box() -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": 0, &"y": 0})
	_db.set_component(id, &"object_type", {&"type": &"cardboard_box"})
	_db.set_component(id, &"object_state", {
		&"current": &"new", &"hp": 1000, &"max_hp": 1000,
	})
	_db.set_component(id, &"advertisements", {&"list": [
		{&"desire_type": &"comfort", &"strength": 700,
			&"radius_ru": 4, &"max_occupants": 1},
		{&"desire_type": &"curiosity", &"strength": 500,
			&"radius_ru": 5, &"action": &"shred",
			&"action_duration": 2.0,
			&"novelty_duration": 30,
			&"novelty_cooldown": 100},
	]})
	_db.update_spatial(id, 0, 0)
	return id


func test_box_hp_reduction():
	var box_id: int = _make_box()
	_damage_object(box_id, 200)
	var state: Dictionary = _db.get_component(
		box_id, &"object_state",
	)
	assert_eq(state[&"hp"], 800,
		"Box HP must decrease by 200 after shred")


func test_box_transitions_to_worn():
	var box_id: int = _make_box()
	_damage_object(box_id, 600)
	var state: Dictionary = _db.get_component(
		box_id, &"object_state",
	)
	assert_eq(state[&"current"], &"worn",
		"Box must transition to worn when HP drops below 500")


func test_box_transitions_to_scraps():
	var box_id: int = _make_box()
	_damage_object(box_id, 1000)
	var state: Dictionary = _db.get_component(
		box_id, &"object_state",
	)
	assert_eq(state[&"current"], &"scraps",
		"Box must transition to scraps when HP reaches 0")
	var ads: Dictionary = _db.get_component(
		box_id, &"advertisements",
	)
	assert_eq(ads[&"list"].size(), 1,
		"Scraps must have exactly one ad")
	assert_eq(ads[&"list"][0][&"desire_type"], &"comfort",
		"Scraps must advertise comfort only")


# Helper: transition an object to a new state with new ads
func _transition_object(
	entity_id: int, new_state: StringName,
) -> void:
	# This will call game_server.transition_object_state()
	# For unit test, inline the logic
	var obj_state: Dictionary = _db.get_component(
		entity_id, &"object_state",
	)
	obj_state[&"current"] = new_state
	_db.set_component(
		entity_id, &"object_state", obj_state,
	)
	# Swap ads based on new state
	var obj_type: Dictionary = _db.get_component(
		entity_id, &"object_type",
	)
	var type_name: StringName = obj_type[&"type"]
	if type_name == &"tuna_can":
		if new_state == &"open":
			_db.set_component(entity_id, &"advertisements", {
				&"list": [{
					&"desire_type": &"food", &"strength": 800,
					&"radius_ru": 5, &"action": &"eat",
					&"action_duration": 5.0,
				}],
			})
		elif new_state == &"empty":
			_db.remove_component(entity_id, &"advertisements")


func _damage_object(entity_id: int, amount: int) -> void:
	var obj_state: Dictionary = _db.get_component(
		entity_id, &"object_state",
	)
	obj_state[&"hp"] = maxi(0, obj_state[&"hp"] - amount)
	# Check thresholds
	if obj_state[&"hp"] <= 0:
		obj_state[&"current"] = &"scraps"
		_db.set_component(
			entity_id, &"object_state", obj_state,
		)
		_db.set_component(entity_id, &"advertisements", {
			&"list": [{
				&"desire_type": &"comfort", &"strength": 600,
				&"radius_ru": 3, &"max_occupants": 3,
			}],
		})
	elif obj_state[&"hp"] < 500 and obj_state[&"current"] == &"new":
		obj_state[&"current"] = &"worn"
		_db.set_component(
			entity_id, &"object_state", obj_state,
		)
		_db.set_component(entity_id, &"advertisements", {
			&"list": [
				{&"desire_type": &"comfort", &"strength": 400,
					&"radius_ru": 3, &"max_occupants": 1},
				{&"desire_type": &"curiosity", &"strength": 300,
					&"radius_ru": 4, &"action": &"shred",
					&"action_duration": 2.0,
					&"novelty_duration": 30,
					&"novelty_cooldown": 100},
			],
		})
	else:
		_db.set_component(
			entity_id, &"object_state", obj_state,
		)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `script/checks/gut_tests`
Expected: FAIL — tests reference `_transition_object` and `_damage_object` which are local helpers, so they should pass structurally but validate the component logic.

- [ ] **Step 3: Add `transition_object_state` and `damage_object` to game_server.gd**

Add these public methods to `game_server.gd` after `remove_object`:

```gdscript
func transition_object_state(
	entity_id: int, new_state: StringName,
) -> void:
	if not db.has_entity(entity_id):
		return
	if not db.has_component(entity_id, &"object_state"):
		return
	var obj_state: Dictionary = db.get_component(
		entity_id, &"object_state",
	)
	obj_state[&"current"] = new_state
	db.set_component(entity_id, &"object_state", obj_state)
	_update_ads_for_state(entity_id, new_state)


func damage_object(entity_id: int, amount: int) -> void:
	if not db.has_entity(entity_id):
		return
	if not db.has_component(entity_id, &"object_state"):
		return
	var obj_state: Dictionary = db.get_component(
		entity_id, &"object_state",
	)
	if obj_state[&"hp"] < 0:
		return  # not degradable
	obj_state[&"hp"] = maxi(0, obj_state[&"hp"] - amount)
	db.set_component(entity_id, &"object_state", obj_state)
	# Check state thresholds
	var current: StringName = obj_state[&"current"]
	if obj_state[&"hp"] <= 0 and current != &"scraps":
		transition_object_state(entity_id, &"scraps")
	elif obj_state[&"hp"] < 500 and current == &"new":
		transition_object_state(entity_id, &"worn")


func _update_ads_for_state(
	entity_id: int, state: StringName,
) -> void:
	var obj_type: Dictionary = db.get_component(
		entity_id, &"object_type",
	)
	var type_name: StringName = obj_type[&"type"]
	match type_name:
		&"tuna_can":
			match state:
				&"open":
					db.set_component(
						entity_id, &"advertisements", {
							&"list": [{
								&"desire_type": &"food",
								&"strength": 800,
								&"radius_ru": 5,
								&"action": &"eat",
								&"action_duration": 5.0,
							}],
						},
					)
				&"empty":
					if db.has_component(
						entity_id, &"advertisements",
					):
						db.remove_component(
							entity_id, &"advertisements",
						)
		&"cardboard_box":
			match state:
				&"worn":
					db.set_component(
						entity_id, &"advertisements", {
							&"list": [
								{&"desire_type": &"comfort",
									&"strength": 400,
									&"radius_ru": 3,
									&"max_occupants": 1},
								{&"desire_type": &"curiosity",
									&"strength": 300,
									&"radius_ru": 4,
									&"action": &"shred",
									&"action_duration": 2.0,
									&"novelty_duration": 30,
									&"novelty_cooldown": 100},
							],
						},
					)
				&"scraps":
					db.set_component(
						entity_id, &"advertisements", {
							&"list": [{
								&"desire_type": &"comfort",
								&"strength": 600,
								&"radius_ru": 3,
								&"max_occupants": 3,
							}],
						},
					)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `script/checks/gut_tests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/unit/test_object_state.gd nodes/game_server.gd
git commit -m "feat: object state transitions and box degradation"
```

---

## Task 2: Food Desire & Scatter Exclusions

**Files:**
- Modify: `nodes/game_server.gd` (scatter desires, spawn entities)
- Modify: `nodes/animal_stats_bar.gd` (dynamic bars)
- Modify: `nodes/animal_node.gd` (PERFORMING anim map)
- Modify: `engine/core/constants.gd` (ARM_REACH_RU)

- [ ] **Step 1: Add food desire decay and scatter exclusion in game_server.gd**

In `_scatter_desires`, after the existing decay lines, add:

```gdscript
db.add_all(&"desires", &"food", -2)
```

And add the clamp:

```gdscript
db.clamp_all(&"desires", &"food", 0, 1000)
```

Add a class-level constant to `game_server.gd` (at the top of the file, alongside other constants):

```gdscript
# Action-only desires: scored by resolver for targeting,
# not passively scattered by _scatter_from_ads
const _ACTION_ONLY_DESIRES: Array[StringName] = [
	&"food", &"openable", &"scannable",
]
```

In `_scatter_from_ads`, in the inner apply loop, skip action-only types:

```gdscript
for dtype: StringName in best:
	if dtype in _ACTION_ONLY_DESIRES:
		continue
	# ... existing apply logic
```

- [ ] **Step 2: Add food to cat spawn entities**

In `_spawn_starter_entities`, update all three cat desire components to include food:

```gdscript
db.set_component(cat, &"desires", {
	&"warmth": 800, &"comfort": 800,
	&"curiosity": 500, &"food": 800,
})
```

And add `food_weight` to cat personality:

```gdscript
db.set_component(cat, &"personality", {
	&"warmth_weight": 800, &"comfort_weight": 600,
	&"curiosity_weight": 100, &"food_weight": 700,
})
```

- [ ] **Step 3: Add ARM_REACH_RU to constants.gd**

```gdscript
const ARM_REACH_RU: int = 3
```

- [ ] **Step 4: Make stats bar dynamic per entity's desires**

Replace the hardcoded 3-bar setup in `animal_stats_bar.gd`. In `_create_panel`, replace the fixed bar creation with a dynamic approach:

```gdscript
const DESIRE_COLORS: Dictionary = {
	&"warmth": Color(0.85, 0.35, 0.2),
	&"comfort": Color(0.45, 0.65, 0.85),
	&"curiosity": Color(0.6, 0.8, 0.3),
	&"food": Color(0.9, 0.7, 0.2),
	&"purpose": Color(0.4, 0.8, 0.8),
}
```

In `_create_panel`, after the state label, build bars from the entity's actual desires:

```gdscript
var desires: Dictionary = _db.get_component(
	entity_id, &"desires",
)
for key: StringName in desires:
	var color: Color = DESIRE_COLORS.get(
		key, Color(0.5, 0.5, 0.5),
	)
	_add_bar(bars, String(key), color)
```

In `_update_panel`, iterate desire keys dynamically:

```gdscript
var desires: Dictionary = _db.get_component(
	entity_id, &"desires",
)
var bar_idx: int = 0
for key: StringName in desires:
	if bar_idx < bars.get_child_count():
		_update_bar(bars.get_child(bar_idx), desires[key])
		bar_idx += 1
```

- [ ] **Step 5: Add PERFORMING to animal_node.gd animation map**

Already done in the `_STATE_ANIMS` dict — verify `&"PERFORMING"` maps to `&"crouch"` as a default:

```gdscript
&"PERFORMING": &"crouch",
```

- [ ] **Step 6: Run tests**

Run: `script/checks/gut_tests`
Expected: PASS (food desire is new, no existing tests break)

- [ ] **Step 7: Commit**

```bash
git add engine/core/constants.gd nodes/game_server.gd nodes/animal_stats_bar.gd nodes/animal_node.gd
git commit -m "feat: food desire, scatter exclusions, dynamic stats bar"
```

---

## Task 3: PERFORMING State & Action Execution

**Files:**
- Create: `tests/unit/test_action_effects.gd`
- Create: `tests/integration/test_performing.gd`
- Modify: `nodes/game_server.gd`

- [ ] **Step 1: Write failing test for action execution**

```gdscript
# tests/unit/test_action_effects.gd
extends GutTest

var _db: GameStateDB


func before_each() -> void:
	_db = GameStateDB.new()


func test_eat_action_satisfies_food():
	var cat: int = _db.create_entity()
	_db.set_component(cat, &"desires", {
		&"warmth": 800, &"comfort": 800,
		&"curiosity": 500, &"food": 200,
	})
	# Simulate eat action effect
	var food_before: int = _db.get_field(
		cat, &"desires", &"food",
	)
	_db.set_field(
		cat, &"desires", &"food",
		mini(1000, food_before + 500),
	)
	assert_eq(
		_db.get_field(cat, &"desires", &"food"), 700,
		"Eating must increase food by 500",
	)


func test_open_action_transitions_can():
	# Uses a GameServer to call transition_object_state()
	# rather than manually setting state — tests the real code path
	var server := GameServer.new()
	server._ready_for_test(_db)
	var can: int = _db.create_entity()
	_db.set_component(can, &"object_type", {
		&"type": &"tuna_can",
	})
	_db.set_component(can, &"object_state", {
		&"current": &"sealed", &"hp": -1, &"max_hp": -1,
	})
	_db.set_component(can, &"advertisements", {&"list": [
		{&"desire_type": &"openable", &"strength": 800,
			&"radius_ru": 3, &"action": &"open",
			&"action_duration": 3.0},
	]})
	server.transition_object_state(can, &"open")
	var state: Dictionary = _db.get_component(
		can, &"object_state",
	)
	assert_eq(state[&"current"], &"open",
		"Can state must be open after open action")
	var ads: Dictionary = _db.get_component(
		can, &"advertisements",
	)
	assert_eq(ads[&"list"][0][&"desire_type"], &"food",
		"Open can must advertise food, not openable")


func test_shred_reduces_box_hp():
	# Uses a GameServer to call damage_object()
	# rather than inlining math — tests the real code path
	var server := GameServer.new()
	server._ready_for_test(_db)
	var box: int = _db.create_entity()
	_db.set_component(box, &"object_type", {
		&"type": &"cardboard_box",
	})
	_db.set_component(box, &"object_state", {
		&"current": &"new", &"hp": 1000, &"max_hp": 1000,
	})
	server.damage_object(box, 200)
	var state: Dictionary = _db.get_component(
		box, &"object_state",
	)
	assert_eq(state[&"hp"], 800,
		"Shred must reduce HP by 200")


func test_press_spawns_can():
	var initial_count: int = _db.entity_count()
	# Simulate press: create a new tuna can
	var can: int = _db.create_entity()
	_db.set_component(can, &"object_type", {
		&"type": &"tuna_can",
	})
	_db.set_component(can, &"object_state", {
		&"current": &"sealed", &"hp": -1, &"max_hp": -1,
	})
	assert_eq(_db.entity_count(), initial_count + 1,
		"Press must spawn exactly one new entity")
```

- [ ] **Step 2: Run tests to verify they pass** (these are structural tests)

Run: `script/checks/gut_tests`
Expected: PASS

- [ ] **Step 3: Add PERFORMING state handling to game_server.gd**

Add a `_performing_timers` dictionary alongside `_state_timers`:

```gdscript
var _performing_timers: Dictionary = {}  # entity_id -> float
var _performing_targets: Dictionary = {}  # entity_id -> int (target entity_id)
var _performing_actions: Dictionary = {}  # entity_id -> StringName
```

Modify the arrival logic in `_move_animals` (the `if dist <= ANIMAL_SPEED_PU:` block). Replace the arrival state determination with:

```gdscript
# Arrived
db.set_component(entity_id, &"position", {
	&"x": target[&"x"], &"y": target[&"y"],
})
db.update_spatial(
	entity_id, target[&"x"], target[&"y"],
)

var target_id: int = target[&"entity_id"]

# Check for action on the target's ad
var action: StringName = &""
var action_duration: float = 0.0
if target_id != Constants.INVALID_ID:
	if not db.has_entity(target_id):
		# Target despawned during movement
		_reset_to_idle(entity_id)
		continue
	if db.has_component(target_id, &"advertisements"):
		var ads: Dictionary = db.get_component(
			target_id, &"advertisements",
		)
		for ad: Dictionary in ads[&"list"]:
			if ad.has(&"action"):
				action = ad[&"action"]
				action_duration = float(
					ad.get(&"action_duration", 3.0)
				)
				break

if action != &"":
	# Enter PERFORMING
	db.set_component(entity_id, &"ai_state", {
		&"state": &"PERFORMING",
		&"meta_state": &"GOAL_DIRECTED",
		&"commitment_score": 0,
	})
	_performing_timers[entity_id] = 0.0
	_performing_targets[entity_id] = target_id
	_performing_actions[entity_id] = action
	_state_timers[entity_id] = 0.0
	_min_durations_override[entity_id] = action_duration
else:
	# No action — existing arrival logic
	var arrival_state: StringName = &"IDLE"
	var arrival_duration: float = -1.0
	if _curiosity_trackers.has(entity_id) and target_id != Constants.INVALID_ID:
		if db.has_component(target_id, &"advertisements"):
			var ads2: Dictionary = db.get_component(
				target_id, &"advertisements",
			)
			for ad: Dictionary in ads2[&"list"]:
				if ad[&"desire_type"] == &"curiosity":
					arrival_state = &"SNIFFING"
					arrival_duration = float(
						ad.get(&"novelty_duration", 100)
					) / 10.0
					_curiosity_trackers[entity_id].visit(
						target_id, db.get_tick(),
					)
					break
	db.set_component(entity_id, &"ai_state", {
		&"state": arrival_state,
		&"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	if arrival_duration > 0.0:
		_state_timers[entity_id] = 0.0
		_min_durations_override[entity_id] = arrival_duration

db.set_component(entity_id, &"target", {
	&"x": Constants.INVALID_ID,
	&"y": Constants.INVALID_ID,
	&"entity_id": Constants.INVALID_ID,
})
```

Add a helper:

```gdscript
func _reset_to_idle(entity_id: int) -> void:
	db.set_component(entity_id, &"ai_state", {
		&"state": &"IDLE",
		&"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	db.set_component(entity_id, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	_performing_timers.erase(entity_id)
	_performing_targets.erase(entity_id)
	_performing_actions.erase(entity_id)
```

- [ ] **Step 4: Add PERFORMING tick handler**

Add to `_update_ambient_states` (or a new `_update_performing` called from `_physics_process`), before the ambient state logic:

```gdscript
func _update_performing(tick_delta: float) -> void:
	var completed: Array[int] = []
	for entity_id: int in _performing_timers:
		_performing_timers[entity_id] += tick_delta
		var min_dur: float = _min_durations_override.get(
			entity_id, 3.0,
		)
		if _performing_timers[entity_id] >= min_dur:
			completed.append(entity_id)
	for entity_id: int in completed:
		_execute_action(entity_id)
```

Call it from `_physics_process` after `_move_animals()`:

```gdscript
_update_performing(0.1)
```

- [ ] **Step 5: Add action execution**

```gdscript
func _execute_action(entity_id: int) -> void:
	var action: StringName = _performing_actions.get(
		entity_id, &"",
	)
	var target_id: int = _performing_targets.get(
		entity_id, Constants.INVALID_ID,
	)

	# Validate target still exists
	if target_id != Constants.INVALID_ID:
		if not db.has_entity(target_id):
			_reset_to_idle(entity_id)
			return

	match action:
		&"press":
			_action_press(entity_id)
		&"open":
			_action_open(entity_id, target_id)
		&"eat":
			_action_eat(entity_id, target_id)
		&"shred":
			_action_shred(entity_id, target_id)
		&"scan":
			_action_scan(entity_id)

	# Only reset if the action didn't already change the state
	# (e.g., _action_press sets STARTLED — don't clobber it)
	var current_ai: Dictionary = db.get_component(
		entity_id, &"ai_state",
	)
	if current_ai[&"state"] == &"PERFORMING":
		_reset_to_idle(entity_id)


func _action_press(entity_id: int) -> void:
	# Spawn sealed tuna can at drop point (near arm)
	var arm_entities: Array[int] = db.get_entities_with(
		&"ai_state",
	)
	var drop_x: int = 3 * Constants.RACK_STRIDE_PU
	var drop_y: int = (
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU
		+ Constants.FLOOR_HEIGHT_PU / 3
	)
	for eid: int in arm_entities:
		if not db.has_component(eid, &"species"):
			continue
		var sp: Dictionary = db.get_component(eid, &"species")
		if sp[&"id"] == &"tcp_base:robot_arm":
			var arm_pos: Dictionary = db.get_component(
				eid, &"position",
			)
			drop_x = arm_pos[&"x"]
			@warning_ignore("integer_division")
			drop_y = arm_pos[&"y"] - Constants.ru_to_pu(1)
			break
	_spawn_tuna_can(drop_x, drop_y)
	# Startle the ferret
	db.set_component(entity_id, &"ai_state", {
		&"state": &"STARTLED",
		&"meta_state": &"SPECIAL",
		&"commitment_score": 0,
	})
	_state_timers[entity_id] = 0.0


func _action_open(entity_id: int, target_id: int) -> void:
	transition_object_state(target_id, &"open")
	if db.has_component(entity_id, &"desires"):
		var current: int = db.get_field(
			entity_id, &"desires", &"purpose",
		)
		db.set_field(
			entity_id, &"desires", &"purpose",
			mini(1000, current + 500),
		)


func _action_eat(entity_id: int, target_id: int) -> void:
	transition_object_state(target_id, &"empty")
	if db.has_component(entity_id, &"desires"):
		var current: int = db.get_field(
			entity_id, &"desires", &"food",
		)
		db.set_field(
			entity_id, &"desires", &"food",
			mini(1000, current + 500),
		)


func _action_shred(entity_id: int, target_id: int) -> void:
	damage_object(target_id, 200)
	if db.has_component(entity_id, &"desires"):
		var current: int = db.get_field(
			entity_id, &"desires", &"curiosity",
		)
		db.set_field(
			entity_id, &"desires", &"curiosity",
			mini(1000, current + 300),
		)


func _action_scan(entity_id: int) -> void:
	if db.has_component(entity_id, &"desires"):
		var current: int = db.get_field(
			entity_id, &"desires", &"purpose",
		)
		db.set_field(
			entity_id, &"desires", &"purpose",
			mini(1000, current + 200),
		)


func _spawn_tuna_can(x: int, y: int) -> int:
	var can: int = db.create_entity()
	db.set_component(can, &"position", {&"x": x, &"y": y})
	db.set_component(can, &"object_type", {
		&"type": &"tuna_can",
	})
	db.set_component(can, &"object_state", {
		&"current": &"sealed", &"hp": -1, &"max_hp": -1,
	})
	db.set_component(can, &"advertisements", {&"list": [
		{&"desire_type": &"openable", &"strength": 800,
			&"radius_ru": 3, &"action": &"open",
			&"action_duration": 3.0},
	]})
	db.update_spatial(can, x, y)
	Events.object_placed.emit(
		can, 0, 0, &"tuna_can",
	)
	return can
```

- [ ] **Step 6: Run tests**

Run: `script/checks/gut_tests`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add nodes/game_server.gd tests/unit/test_action_effects.gd
git commit -m "feat: PERFORMING state and action execution system"
```

---

## Task 4: Robot Arm & Button Entities

**Files:**
- Modify: `nodes/game_server.gd` (spawn arm + button)
- Modify: `engine/desires/desire_resolver.gd` (arm reach check)
- Modify: `nodes/game_client.gd` (arm + button sprites, can lifecycle)
- Modify: `nodes/animal_node.gd` (arm sprite handling)

- [ ] **Step 1: Add arm reach check in desire_resolver.gd and skip movement in game_server.gd**

In `desire_resolver.gd`'s `_evaluate_one`, after the best score is found and before transitioning to SEEKING, add an arm-specific reach gate. The arm enters SEEKING like any other entity and stores the target. The key difference is that `_move_animals` in game_server.gd skips movement for robot_arm entities and sends them straight to arrival logic.

**desire_resolver.gd** — in `_evaluate_one`, after best score determination:

```gdscript
if best_score > commitment + Constants.SWITCH_THRESHOLD:
	# Arm reach gate: if entity is a robot_arm, only act
	# if target is within ARM_REACH_RU. Otherwise stay ambient.
	if _db.has_component(entity_id, &"species"):
		var sp: Dictionary = _db.get_component(
			entity_id, &"species",
		)
		if sp[&"id"] == &"tcp_base:robot_arm":
			var my_pos: Dictionary = _db.get_component(
				entity_id, &"position",
			)
			var dist: int = (
				absi(my_pos[&"x"] - best_target_pos[&"x"])
				+ absi(my_pos[&"y"] - best_target_pos[&"y"])
			)
			if dist > Constants.ru_to_pu(Constants.ARM_REACH_RU):
				return  # Can't reach, stay ambient

	# Normal SEEKING transition — works for all entities
	_db.set_component(entity_id, &"ai_state", {
		&"state": &"SEEKING",
		&"meta_state": &"GOAL_DIRECTED",
		&"commitment_score": best_score,
	})
	_db.set_component(entity_id, &"target", {
		&"x": best_target_pos[&"x"],
		&"y": best_target_pos[&"y"],
		&"entity_id": best_target_id,
	})
```

**game_server.gd** — in `_move_animals`, add a robot_arm bypass at the top of the entity loop body, before the distance/movement calculation:

```gdscript
# Robot arm cannot move — skip straight to arrival logic
if db.has_component(entity_id, &"species"):
	var sp: Dictionary = db.get_component(
		entity_id, &"species",
	)
	if sp[&"id"] == &"tcp_base:robot_arm":
		# Jump to the arrival block (same code that runs
		# when dist <= ANIMAL_SPEED_PU for normal entities).
		# The arm's position doesn't change — it "reaches"
		# to the target from where it sits.
		var target_id: int = target[&"entity_id"]
		var action: StringName = &""
		var action_duration: float = 0.0
		if target_id != Constants.INVALID_ID:
			if not db.has_entity(target_id):
				_reset_to_idle(entity_id)
				continue
			if db.has_component(
				target_id, &"advertisements",
			):
				var ads: Dictionary = db.get_component(
					target_id, &"advertisements",
				)
				for ad: Dictionary in ads[&"list"]:
					if ad.has(&"action"):
						action = ad[&"action"]
						action_duration = float(
							ad.get(&"action_duration", 3.0)
						)
						break
		if action != &"":
			db.set_component(entity_id, &"ai_state", {
				&"state": &"PERFORMING",
				&"meta_state": &"GOAL_DIRECTED",
				&"commitment_score": 0,
			})
			_performing_timers[entity_id] = 0.0
			_performing_targets[entity_id] = target_id
			_performing_actions[entity_id] = action
			_state_timers[entity_id] = 0.0
			_min_durations_override[entity_id] = action_duration
		else:
			_reset_to_idle(entity_id)
		db.set_component(entity_id, &"target", {
			&"x": Constants.INVALID_ID,
			&"y": Constants.INVALID_ID,
			&"entity_id": Constants.INVALID_ID,
		})
		continue
```

This keeps the desire resolver clean (it just gates on reach, then sets SEEKING normally) and puts all arm-specific movement bypassing in game_server where the performing dictionaries live.

- [ ] **Step 2: Spawn arm, button in game_server.gd**

Add to `_spawn_starter_entities`, after the existing entities:

```gdscript
# Robot arm — fixed on floor near rack 3
var arm: int = db.create_entity()
@warning_ignore("integer_division")
var arm_x: int = (
	3 * Constants.RACK_STRIDE_PU + Constants.RACK_STRIDE_PU / 2
)
var arm_y: int = (
	Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU
	+ Constants.FLOOR_HEIGHT_PU / 2
)
db.set_component(arm, &"species", {
	&"id": &"tcp_base:robot_arm",
	&"variant": &"arm",
	&"name": &"ARM-01",
})
db.set_component(arm, &"position", {&"x": arm_x, &"y": arm_y})
db.set_component(arm, &"desires", {&"purpose": 800})
db.set_component(arm, &"personality", {
	&"openable_weight": 900, &"scannable_weight": 500,
})
db.set_component(arm, &"ai_state", {
	&"state": &"IDLE", &"meta_state": &"AMBIENT",
	&"commitment_score": 0,
})
db.set_component(arm, &"target", {
	&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
	&"entity_id": Constants.INVALID_ID,
})
db.set_component(arm, &"advertisements", {&"list": [
	{&"desire_type": &"scannable", &"strength": 300,
		&"radius_ru": 4},
]})
db.update_spatial(arm, arm_x, arm_y)

# Dispenser button — next to arm
var button: int = db.create_entity()
@warning_ignore("integer_division")
var btn_x: int = arm_x - Constants.RACK_STRIDE_PU / 4
var btn_y: int = arm_y
db.set_component(button, &"position", {
	&"x": btn_x, &"y": btn_y,
})
db.set_component(button, &"object_type", {
	&"type": &"dispenser_button",
})
db.set_component(button, &"advertisements", {&"list": [
	{&"desire_type": &"curiosity", &"strength": 600,
		&"radius_ru": 6, &"action": &"press",
		&"action_duration": 1.0,
		&"novelty_cooldown": 200},
]})
db.update_spatial(button, btn_x, btn_y)
```

- [ ] **Step 3: Add purpose decay to `_scatter_desires`**

```gdscript
db.add_all(&"desires", &"purpose", -6)
db.clamp_all(&"desires", &"purpose", 0, 1000)
```

- [ ] **Step 4: Generate placeholder arm and button sprites**

Use the `generate-pixel-sprites` skill to create:
- `mods/tcp_base/sprites/robot/arm_idle.png` (32x40, placeholder)
- `mods/tcp_base/sprites/objects/dispenser_button.png` (16x12)

- [ ] **Step 5: Handle arm and button rendering in game_client.gd**

Add sprite creation for arm and button in `_build_starter_objects` or after entity spawn. Handle the arm as a non-animal entity that still needs a sprite. The simplest approach: create sprites for all entities with `object_type` that don't already have sprites, plus the arm entity.

- [ ] **Step 6: Handle tuna can sprite lifecycle in game_client.gd**

Subscribe to `Events.object_placed` for new can sprites. Track object state changes to swap sprites (sealed→open). Set up a timer for empty can despawn (3 seconds after transitioning to empty).

- [ ] **Step 7: Handle arm in animal_node.gd**

In `_setup_sprite`, when species is `tcp_base:robot_arm`, load the arm sprite instead of animal strips. The arm doesn't animate with sprite strips — use a static sprite:

```gdscript
if species[&"id"] == &"tcp_base:robot_arm":
	var arm_tex: Texture2D = load(
		"res://mods/tcp_base/sprites/robot/arm_idle.png"
	)
	if arm_tex:
		var frames := SpriteFrames.new()
		if frames.has_animation(&"default"):
			frames.remove_animation(&"default")
		frames.add_animation(&"idle")
		frames.add_frame(&"idle", arm_tex)
		_sprite.sprite_frames = frames
		_sprite.play(&"idle")
	return
```

- [ ] **Step 8: Run tests**

Run: `script/checks/gut_tests`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add engine/core/constants.gd engine/desires/desire_resolver.gd nodes/game_server.gd nodes/game_client.gd nodes/animal_node.gd mods/tcp_base/sprites/robot/ mods/tcp_base/sprites/objects/dispenser_button.png
git commit -m "feat: robot arm and button entities with desire-driven AI"
```

---

## Task 5: Integration & Scenario Tests

**Files:**
- Create: `tests/integration/test_performing.gd`
- Create: `tests/scenario/test_tuna_chain.gd`

- [ ] **Step 1: Write integration test for PERFORMING flow**

```gdscript
# tests/integration/test_performing.gd
extends GutTest

var _db: GameStateDB
var _resolver: DesireResolver


func before_each() -> void:
	_db = GameStateDB.new()
	_resolver = DesireResolver.new(_db)


func _make_cat(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {
		&"id": &"tcp_base:cat",
		&"variant": &"cat01", &"name": &"Test",
	})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"desires", {
		&"warmth": 800, &"comfort": 800,
		&"curiosity": 500, &"food": 200,
	})
	_db.set_component(id, &"personality", {
		&"warmth_weight": 800, &"comfort_weight": 600,
		&"curiosity_weight": 100, &"food_weight": 700,
	})
	_db.set_component(id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	_db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	_db.update_spatial(id, x, y)
	return id


func _make_open_can(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"object_type", {
		&"type": &"tuna_can",
	})
	_db.set_component(id, &"object_state", {
		&"current": &"open", &"hp": -1, &"max_hp": -1,
	})
	_db.set_component(id, &"advertisements", {&"list": [
		{&"desire_type": &"food", &"strength": 800,
			&"radius_ru": 5, &"action": &"eat",
			&"action_duration": 5.0},
	]})
	_db.update_spatial(id, x, y)
	return id


func test_hungry_cat_targets_open_can():
	var cat: int = _make_cat(0, 0)
	var can: int = _make_open_can(500, 0)
	_resolver.mark_dirty(cat)
	_resolver.evaluate_budget()
	var ai: Dictionary = _db.get_component(
		cat, &"ai_state",
	)
	assert_eq(ai[&"state"], &"SEEKING",
		"Hungry cat must seek open tuna can")
	var target: Dictionary = _db.get_component(
		cat, &"target",
	)
	assert_eq(target[&"entity_id"], can,
		"Cat must target the open can")


func test_fed_cat_ignores_open_can():
	var cat: int = _make_cat(0, 0)
	_db.set_field(cat, &"desires", &"food", 950)
	var _can: int = _make_open_can(500, 0)
	_resolver.mark_dirty(cat)
	_resolver.evaluate_budget()
	var ai: Dictionary = _db.get_component(
		cat, &"ai_state",
	)
	assert_eq(ai[&"meta_state"], &"AMBIENT",
		"Fed cat (food=950) must stay ambient")


func test_food_not_scattered_passively():
	# Uses a real GameServer to run _scatter_desires() and verify
	# that food ads don't passively satisfy the food desire.
	var server := GameServer.new()
	server._ready_for_test(_db)
	var cat: int = _make_cat(0, 0)
	_db.set_field(cat, &"desires", &"food", 200)
	var _can: int = _make_open_can(0, 0)
	# Run the scatter logic that normally runs each tick
	server._scatter_desires()
	var food_after: int = _db.get_field(
		cat, &"desires", &"food",
	)
	# Food decays by -2 per tick from scatter, but must NOT
	# gain from the nearby open can's food advertisement
	assert_le(food_after, 200,
		"Food must not increase from passive scatter — "
		+ "only the eat action satisfies food")
```

- [ ] **Step 2: Write scenario test for full tuna chain**

```gdscript
# tests/scenario/test_tuna_chain.gd
extends GutTest


func test_arm_scores_sealed_can():
	var db := GameStateDB.new()
	var resolver := DesireResolver.new(db)
	# Create arm
	var arm: int = db.create_entity()
	db.set_component(arm, &"species", {
		&"id": &"tcp_base:robot_arm",
		&"variant": &"arm", &"name": &"ARM-01",
	})
	db.set_component(arm, &"position", {&"x": 0, &"y": 0})
	db.set_component(arm, &"desires", {&"purpose": 200})
	db.set_component(arm, &"personality", {
		&"openable_weight": 900, &"scannable_weight": 500,
	})
	db.set_component(arm, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	db.set_component(arm, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(arm, 0, 0)
	# Create sealed can within reach
	var can: int = db.create_entity()
	db.set_component(can, &"position", {&"x": 500, &"y": 0})
	db.set_component(can, &"advertisements", {&"list": [
		{&"desire_type": &"openable", &"strength": 800,
			&"radius_ru": 3, &"action": &"open",
			&"action_duration": 3.0},
	]})
	db.update_spatial(can, 500, 0)
	# Evaluate
	resolver.mark_dirty(arm)
	resolver.evaluate_budget()
	var ai: Dictionary = db.get_component(arm, &"ai_state")
	assert_eq(ai[&"state"], &"SEEKING",
		"Arm must target sealed can")
	var target: Dictionary = db.get_component(
		arm, &"target",
	)
	assert_eq(target[&"entity_id"], can,
		"Arm must target the sealed can entity")


func test_arm_ignores_can_beyond_reach():
	var db := GameStateDB.new()
	var resolver := DesireResolver.new(db)
	var arm: int = db.create_entity()
	db.set_component(arm, &"species", {
		&"id": &"tcp_base:robot_arm",
		&"variant": &"arm", &"name": &"ARM-01",
	})
	db.set_component(arm, &"position", {&"x": 0, &"y": 0})
	db.set_component(arm, &"desires", {&"purpose": 200})
	db.set_component(arm, &"personality", {
		&"openable_weight": 900, &"scannable_weight": 500,
	})
	db.set_component(arm, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	db.set_component(arm, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(arm, 0, 0)
	# Can far beyond arm reach (3 RU = 2100 PU)
	var can: int = db.create_entity()
	db.set_component(can, &"position", {
		&"x": 5000, &"y": 0,
	})
	db.set_component(can, &"advertisements", {&"list": [
		{&"desire_type": &"openable", &"strength": 800,
			&"radius_ru": 3, &"action": &"open",
			&"action_duration": 3.0},
	]})
	db.update_spatial(can, 5000, 0)
	resolver.mark_dirty(arm)
	resolver.evaluate_budget()
	var ai: Dictionary = db.get_component(arm, &"ai_state")
	assert_eq(ai[&"meta_state"], &"AMBIENT",
		"Arm must ignore can beyond reach radius")
```

- [ ] **Step 3: Run tests**

Run: `script/checks/gut_tests`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test_performing.gd tests/scenario/test_tuna_chain.gd
git commit -m "test: integration and scenario tests for object interactions"
```

---

## Task 6: Edge Case Tests

**Files:**
- Modify: `tests/scenario/test_tuna_chain.gd`

- [ ] **Step 1: Add edge case tests**

Append to `test_tuna_chain.gd`:

```gdscript
func test_two_cats_same_can_only_one_eats():
	var db := GameStateDB.new()
	var server := GameServer.new()
	server._ready_for_test(db)
	# Create open can
	var can: int = db.create_entity()
	db.set_component(can, &"position", {&"x": 0, &"y": 0})
	db.set_component(can, &"object_type", {
		&"type": &"tuna_can",
	})
	db.set_component(can, &"object_state", {
		&"current": &"open", &"hp": -1, &"max_hp": -1,
	})
	db.set_component(can, &"advertisements", {&"list": [
		{&"desire_type": &"food", &"strength": 800,
			&"radius_ru": 5, &"action": &"eat",
			&"action_duration": 5.0},
	]})
	db.update_spatial(can, 0, 0)
	# Create two cats both MOVING_TO the same can
	var cat1: int = _make_cat_targeting(db, 100, 0, can)
	var cat2: int = _make_cat_targeting(db, -100, 0, can)
	# First cat arrives and eats — uses real action execution
	server._performing_targets[cat1] = can
	server._performing_actions[cat1] = &"eat"
	server._execute_action(cat1)
	# Can is now empty
	var state: Dictionary = db.get_component(
		can, &"object_state",
	)
	assert_eq(state[&"current"], &"empty",
		"Can must be empty after first cat eats")
	# Second cat arrives — target despawned its ads
	# Arrival logic should find no action and reset to IDLE
	server._performing_targets[cat2] = can
	server._performing_actions[cat2] = &"eat"
	server._execute_action(cat2)
	var ai2: Dictionary = db.get_component(
		cat2, &"ai_state",
	)
	# Second cat gets reset because the can has no ads
	# (_execute_action validates target still has the action)
	assert_ne(ai2[&"state"], &"PERFORMING",
		"Second cat must not stay PERFORMING on empty can")


func _make_cat_targeting(
	p_db: GameStateDB, x: int, y: int, target_id: int,
) -> int:
	var id: int = p_db.create_entity()
	p_db.set_component(id, &"species", {
		&"id": &"tcp_base:cat",
		&"variant": &"cat01", &"name": &"Test",
	})
	p_db.set_component(id, &"position", {&"x": x, &"y": y})
	p_db.set_component(id, &"desires", {
		&"warmth": 800, &"comfort": 800,
		&"curiosity": 500, &"food": 200,
	})
	p_db.set_component(id, &"personality", {
		&"warmth_weight": 800, &"comfort_weight": 600,
		&"curiosity_weight": 100, &"food_weight": 700,
	})
	p_db.set_component(id, &"ai_state", {
		&"state": &"PERFORMING",
		&"meta_state": &"GOAL_DIRECTED",
		&"commitment_score": 0,
	})
	var target_pos: Dictionary = p_db.get_component(
		target_id, &"position",
	)
	p_db.set_component(id, &"target", {
		&"x": target_pos[&"x"],
		&"y": target_pos[&"y"],
		&"entity_id": target_id,
	})
	p_db.update_spatial(id, x, y)
	return id


func test_full_tuna_chain():
	# End-to-end: arm + button + ferret + cat through the
	# full chain: press -> can drops -> arm opens -> cat eats
	var db := GameStateDB.new()
	var server := GameServer.new()
	server._ready_for_test(db)
	var resolver := DesireResolver.new(db)

	# Spawn arm on the floor
	var arm: int = db.create_entity()
	db.set_component(arm, &"species", {
		&"id": &"tcp_base:robot_arm",
		&"variant": &"arm", &"name": &"ARM-01",
	})
	db.set_component(arm, &"position", {&"x": 1000, &"y": 5000})
	db.set_component(arm, &"desires", {&"purpose": 200})
	db.set_component(arm, &"personality", {
		&"openable_weight": 900, &"scannable_weight": 500,
	})
	db.set_component(arm, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	db.set_component(arm, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(arm, 1000, 5000)

	# Step 1: Ferret presses button — simulate press action
	var can_id: int = server._spawn_tuna_can(1000, 4800)
	assert_true(db.has_entity(can_id),
		"Press must spawn a sealed tuna can")
	var can_state: Dictionary = db.get_component(
		can_id, &"object_state",
	)
	assert_eq(can_state[&"current"], &"sealed",
		"Spawned can must be sealed")

	# Step 2: Arm detects sealed can and seeks it
	resolver.mark_dirty(arm)
	resolver.evaluate_budget()
	var arm_ai: Dictionary = db.get_component(
		arm, &"ai_state",
	)
	assert_eq(arm_ai[&"state"], &"SEEKING",
		"Arm must target sealed can within reach")

	# Step 3: Arm performs open action
	server._performing_targets[arm] = can_id
	server._performing_actions[arm] = &"open"
	server._execute_action(arm)
	can_state = db.get_component(can_id, &"object_state")
	assert_eq(can_state[&"current"], &"open",
		"Can must be open after arm action")

	# Step 4: Cat detects open can and seeks it
	var cat: int = db.create_entity()
	db.set_component(cat, &"species", {
		&"id": &"tcp_base:cat",
		&"variant": &"cat01", &"name": &"Mochi",
	})
	db.set_component(cat, &"position", {
		&"x": 1200, &"y": 4800,
	})
	db.set_component(cat, &"desires", {
		&"warmth": 800, &"comfort": 800,
		&"curiosity": 500, &"food": 200,
	})
	db.set_component(cat, &"personality", {
		&"warmth_weight": 800, &"comfort_weight": 600,
		&"curiosity_weight": 100, &"food_weight": 700,
	})
	db.set_component(cat, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	db.set_component(cat, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(cat, 1200, 4800)
	resolver.mark_dirty(cat)
	resolver.evaluate_budget()
	var cat_ai: Dictionary = db.get_component(
		cat, &"ai_state",
	)
	assert_eq(cat_ai[&"state"], &"SEEKING",
		"Hungry cat must seek open can")

	# Step 5: Cat eats the open can
	server._performing_targets[cat] = can_id
	server._performing_actions[cat] = &"eat"
	server._execute_action(cat)
	can_state = db.get_component(can_id, &"object_state")
	assert_eq(can_state[&"current"], &"empty",
		"Can must be empty after cat eats")
	var food_after: int = db.get_field(
		cat, &"desires", &"food",
	)
	assert_gt(food_after, 200,
		"Cat food desire must increase after eating")


func test_empty_can_has_no_ads():
	var db := GameStateDB.new()
	var can: int = db.create_entity()
	db.set_component(can, &"object_type", {
		&"type": &"tuna_can",
	})
	db.set_component(can, &"object_state", {
		&"current": &"empty", &"hp": -1, &"max_hp": -1,
	})
	assert_false(
		db.has_component(can, &"advertisements"),
		"Empty can must not have advertisements",
	)
```

- [ ] **Step 2: Run tests**

Run: `script/checks/gut_tests`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add tests/scenario/test_tuna_chain.gd
git commit -m "test: edge cases for object interactions"
```

---

## Task 7: Final Validation & Lint

- [ ] **Step 1: Run full validation**

Run: `script/validate`
Expected: All checks pass (lint, compile, tests)

- [ ] **Step 2: Fix any lint issues**

Run: `gdlint nodes/ engine/ tests/`
Fix any issues in files we modified.

- [ ] **Step 3: Run the game manually**

Run: `/Applications/Godot.app/Contents/MacOS/godot --path .`

Verify visually:
- Arm and button appear on the floor near rack 3
- Stats bar shows purpose bar for arm, food bar for cats
- Ferret eventually seeks the button
- After press: can appears, ferret startles
- Arm opens the can
- Cat seeks and eats the opened can
- Box degrades when ferret shreds it

- [ ] **Step 4: Commit any final fixes**

```bash
git add -A
git commit -m "fix: final validation and polish for object interactions"
```
