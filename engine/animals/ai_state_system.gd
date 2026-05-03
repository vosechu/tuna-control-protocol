class_name AiStateSystem extends RefCounted

# Pure-core ai-state advancer. Extracted from GameServer._update_ambient_states.
# Reads ambient-state min_duration_ticks per-entity from the recipe-derived
# `ambient_states` component instead of an engine-side _min_durations dict.
# Reads STARTLED recovery duration from `special_states`.
#
# Timers are integer ticks (incremented by 1 per tick), not float seconds.
# Shared with MovementSystem via the injected BehaviorTimers struct.

const _DEFAULT_MIN_DURATION_TICKS: int = 30  # safety net only — validator enforces presence

var _db: GameStateDB
var _food: FoodSystem
var _events: Object  # duck-typed Events autoload
var _settled: SettledLifecycle
var _nav: NavGraphBuilder
var _timers: BehaviorTimers


func _init(
		db: GameStateDB,
		food: FoodSystem,
		events: Object,
		settled: SettledLifecycle,
		nav: NavGraphBuilder,
		timers: BehaviorTimers,
) -> void:
	_db = db
	_food = food
	_events = events
	_settled = settled
	_nav = nav
	_timers = timers


func tick() -> void:
	var animals: Array[int] = _db.get_entities_with(&"ai_state")
	for entity_id: int in animals:
		if not _db.has_component(entity_id, &"species"):
			continue
		# Settled entities are deliberately resting at a host. Mirror the
		# desire_resolver guard from commit 33be244 — without this skip the
		# hunger-block at the bottom of this loop converts a SLEEPING
		# settled cat into PACING the moment its hunger crosses 400, even
		# though `settled_in` should mean "stay put."
		if _db.has_component(entity_id, &"settled_in"):
			continue
		var ai: Dictionary = _db.get_component(entity_id, &"ai_state")

		# Recover from STARTLED after recipe-declared min_duration_ticks.
		if ai[&"state"] == &"STARTLED":
			# AI-DEV: STARTLED-without-special_states is a load-time
			# validator violation; SpeciesSchemaValidator rejects recipes
			# that declare ambient_states without special_states. This
			# assertion is defense-in-depth — if it fires, the recipe
			# slipped through validation. Godot's assert() halts the
			# debug runner and cannot be trapped by GUT, so coverage of
			# this guard is only in the validator's unit tests.
			assert(_db.has_component(entity_id, &"special_states"),
				"Entity in STARTLED but recipe declared no special_states")
			var specials: Dictionary = _db.get_component(entity_id, &"special_states")
			var startled_entry: Dictionary = specials.get(&"STARTLED", {})
			var startled_min: int = int(startled_entry.get(
				&"min_duration_ticks", _DEFAULT_MIN_DURATION_TICKS,
			))
			_timers.state_timers[entity_id] = int(_timers.state_timers.get(entity_id, 0)) + 1
			if int(_timers.state_timers[entity_id]) >= startled_min:
				_db.set_component(entity_id, &"ai_state", {
					&"state": &"IDLE",
					&"meta_state": &"AMBIENT",
					&"commitment_score": 0,
				})
				_timers.state_timers[entity_id] = 0
			continue

		# Food state machine (GOAL_DIRECTED states)
		if ai[&"state"] == &"PACING":
			_timers.state_timers[entity_id] = int(_timers.state_timers.get(entity_id, 0)) + 1
			var food_id: int = _food.find_nearby_food(entity_id)
			if food_id != Constants.INVALID_ID:
				_db.set_component(entity_id, &"ai_state", {
					&"state": &"EATING",
					&"meta_state": &"GOAL_DIRECTED",
					&"commitment_score": 300,
				})
				_timers.state_timers[entity_id] = 0
			continue

		if ai[&"state"] == &"EATING":
			_timers.state_timers[entity_id] = int(_timers.state_timers.get(entity_id, 0)) + 1
			_db.add_field(entity_id, &"desires", &"hunger", 30)
			_db.clamp_field(entity_id, &"desires", &"hunger", 0, 1000)
			# 3 simulated seconds = 30 ticks at 10 Hz.
			if int(_timers.state_timers[entity_id]) >= 30:
				_food.mark_nearest_can_eaten(entity_id)
				var box_id: int = _food.find_nearest_box(entity_id)
				if box_id != Constants.INVALID_ID:
					var bpos: Dictionary = _db.get_component(box_id, &"position")
					_db.set_component(entity_id, &"ai_state", {
						&"state": &"RETURNING",
						&"meta_state": &"GOAL_DIRECTED",
						&"commitment_score": 150,
					})
					_db.set_component(entity_id, &"target", {
						&"x": bpos[&"x"],
						&"y": bpos[&"y"],
						&"entity_id": box_id,
					})
				else:
					_db.set_component(entity_id, &"ai_state", {
						&"state": &"IDLE",
						&"meta_state": &"AMBIENT",
						&"commitment_score": 0,
					})
				_timers.state_timers[entity_id] = 0
			continue

		if ai[&"state"] == &"SETTLING":
			_timers.state_timers[entity_id] = int(_timers.state_timers.get(entity_id, 0)) + 1
			# 2 simulated seconds = 20 ticks at 10 Hz.
			if int(_timers.state_timers[entity_id]) >= 20:
				# Tuck into the host (box) the cat walked to. The target
				# entity_id was preserved through arrival so SETTLING
				# knows its host. Without settled_in the cat would fall
				# through to AMBIENT and immediately re-target the same
				# box on the resolver's next pass.
				var t: Dictionary = _db.get_component(entity_id, &"target")
				var host_id: int = t[&"entity_id"]
				if host_id != Constants.INVALID_ID and _db.has_entity(host_id):
					_settled.enter(entity_id, host_id)
				_db.set_component(entity_id, &"ai_state", {
					&"state": &"SLEEPING",
					&"meta_state": &"AMBIENT",
					&"commitment_score": 0,
				})
				_db.set_component(entity_id, &"target", {
					&"x": Constants.INVALID_ID,
					&"y": Constants.INVALID_ID,
					&"entity_id": Constants.INVALID_ID,
				})
				_timers.state_timers[entity_id] = 0
			continue

		if ai[&"meta_state"] != &"AMBIENT":
			continue

		# Check hunger for AMBIENT cats
		if _db.has_component(entity_id, &"desires"):
			var desires: Dictionary = _db.get_component(entity_id, &"desires")
			if desires.has(&"hunger") \
					and CatFoodStates.should_become_hungry(_db, entity_id):
				var target_id: int = _food.find_nearest_dispenser(entity_id, _nav)
				if target_id != Constants.INVALID_ID:
					var tpos: Dictionary = _db.get_component(target_id, &"position")
					# Reachability is enforced at movement time by
					# nav_builder.next_waypoint_or_stay; an unreachable
					# dispenser target just means the cat won't move
					# toward it. PACING below remains the fallback when
					# no dispenser exists at all.
					_db.set_component(entity_id, &"ai_state", {
						&"state": &"HUNGRY",
						&"meta_state": &"GOAL_DIRECTED",
						&"commitment_score": 200,
					})
					_db.set_component(entity_id, &"target", {
						&"x": tpos[&"x"],
						&"y": tpos[&"y"],
						&"entity_id": target_id,
					})
					_timers.state_timers[entity_id] = 0
					continue
				else:
					_db.set_component(entity_id, &"ai_state", {
						&"state": &"PACING",
						&"meta_state": &"GOAL_DIRECTED",
						&"commitment_score": 200,
					})
					_events.creature_started_pacing.emit(entity_id)
					_timers.state_timers[entity_id] = 0
					continue

		# Update timer
		_timers.state_timers[entity_id] = int(_timers.state_timers.get(entity_id, 0)) + 1

		# Check if min duration elapsed — recipe-driven.
		var current_state: StringName = ai[&"state"]
		var override: Variant = _timers.min_durations_override.get(entity_id, null)
		var min_dur: int
		if override != null:
			min_dur = int(override)
		else:
			min_dur = _recipe_min_duration_ticks(entity_id, current_state)
		if int(_timers.state_timers[entity_id]) < min_dur:
			continue

		# Pick new ambient state — species recipe supplies the pool.
		var desires: Dictionary = _db.get_component(entity_id, &"desires")
		var is_warm: bool = desires[&"warmth"] < 400
		if not _db.has_component(entity_id, &"ambient_states"):
			continue
		var pools: Dictionary = _db.get_component(entity_id, &"ambient_states")
		var pool: Array = pools.get("warm" if is_warm else "cold", [])
		var new_state: StringName = _pick_ambient_state(pool)
		if new_state != current_state:
			_db.set_component(entity_id, &"ai_state", {
				&"state": new_state,
				&"meta_state": &"AMBIENT",
				&"commitment_score": ai[&"commitment_score"],
			})
			_timers.state_timers[entity_id] = 0
			_timers.min_durations_override.erase(entity_id)


# Recipe-driven min duration. Walks the entity's current ambient pool for an
# entry whose `state` matches the current state and reads its
# `min_duration_ticks`. Falls back to a default — validator enforces the
# field's presence so the fallback is debug-only safety.
func _recipe_min_duration_ticks(entity_id: int, current_state: StringName) -> int:
	if not _db.has_component(entity_id, &"ambient_states"):
		return _DEFAULT_MIN_DURATION_TICKS
	var pools: Dictionary = _db.get_component(entity_id, &"ambient_states")
	# Search both pools — the entity may be in a state that's only in the
	# off-pool (e.g. cold-LOAFING but warmth recovered to "warm"). Picking
	# either pool's value is fine; first match wins.
	for pool_key: String in ["warm", "cold"]:
		var pool: Array = pools.get(pool_key, [])
		for entry: Dictionary in pool:
			if StringName(entry.get("state", "")) == current_state:
				return int(entry.get("min_duration_ticks", _DEFAULT_MIN_DURATION_TICKS))
	return _DEFAULT_MIN_DURATION_TICKS


func _pick_ambient_state(pool: Array) -> StringName:
	if pool.is_empty():
		return &"IDLE"
	var total_weight: int = 0
	for entry: Dictionary in pool:
		total_weight += int(entry.get("weight", 0))
	if total_weight <= 0:
		return &"IDLE"
	var roll: int = randi_range(0, total_weight - 1)
	var cumulative: int = 0
	for entry: Dictionary in pool:
		cumulative += int(entry.get("weight", 0))
		if roll < cumulative:
			return StringName(entry.get("state", "IDLE"))
	return &"IDLE"
