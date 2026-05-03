class_name MovementSystem extends RefCounted

# Pure-core movement system. Extracted from GameServer._move_animals.
# Reads walking speed per-entity from body_capabilities.walks.speed_px_per_tick
# instead of an engine constant — different recipes step at different speeds
# without code changes.
#
# Owns _waypoints (per-entity stored next-step) privately; the AI state
# machine does not read these. Shared per-entity state-timer dicts live on
# the injected BehaviorTimers, not here.

var _db: GameStateDB
var _nav: NavGraphBuilder
var _osm: ObjectStateManager
var _events: Object  # duck-typed Events autoload
var _timers: BehaviorTimers
var _food: FoodSystem
var _waypoints: Dictionary = {}  # entity_id -> {waypoint, target_eid, target_pos}


func _init(
		db: GameStateDB,
		nav: NavGraphBuilder,
		osm: ObjectStateManager,
		events: Object,
		timers: BehaviorTimers,
		food: FoodSystem,
) -> void:
	_db = db
	_nav = nav
	_osm = osm
	_events = events
	_timers = timers
	_food = food


func tick() -> void:
	var animals: Array[int] = _db.get_entities_with(&"ai_state")
	for entity_id: int in animals:
		var ai: Dictionary = _db.get_component(entity_id, &"ai_state")
		var state: StringName = ai[&"state"]
		if state != &"SEEKING" and state != &"MOVING_TO" \
				and state != &"WANDERING" \
				and state != &"HUNGRY" \
				and state != &"RETURNING":
			continue

		var pos: Dictionary = _db.get_component(entity_id, &"position")
		var target: Dictionary = _db.get_component(entity_id, &"target")
		# SEEKING/MOVING_TO require an entity target; WANDERING just needs a position
		if state != &"WANDERING" and target[&"entity_id"] == Constants.INVALID_ID:
			continue

		# Transition SEEKING -> MOVING_TO unconditionally. The nav layer
		# (next_waypoint_or_stay) decides whether movement happens; an
		# unreachable target produces zero forward progress this tick and
		# the AI layer notices via the desire resolver's next pass.
		if state == &"SEEKING":
			_db.set_component(entity_id, &"ai_state", {
				&"state": &"MOVING_TO",
				&"meta_state": &"GOAL_DIRECTED",
				&"commitment_score": ai[&"commitment_score"],
			})

		# Pick next waypoint. The navgraph owns reachability: if from->target
		# has no path, next_waypoint_or_stay returns from_px and the entity
		# stays put. WANDERING uses target_px directly because random floor
		# positions are always reachable without a graph query.
		# Sticky waypoints: once a waypoint is chosen we walk straight to
		# it before recomputing. This kills the 2-px ping-pong that
		# happens when from_px is exactly between two nav nodes (e.g.
		# floor and slot_0) — astar.get_closest_point flips and each
		# anchor produces a different next-step.
		var from_px: Vector2i = Vector2i(pos[&"x"], pos[&"y"])
		var target_px: Vector2i = Vector2i(target[&"x"], target[&"y"])
		var current_target_eid: int = target[&"entity_id"]
		var waypoint: Vector2i = target_px
		if state == &"WANDERING":
			# Wander targets aren't navgraph nodes; walk straight, no
			# stickiness needed.
			_waypoints.erase(entity_id)
		elif _db.has_component(entity_id, &"species"):
			var species_comp: Dictionary = _db.get_component(entity_id, &"species")
			var stored: Variant = _waypoints.get(entity_id)
			var keep_stored: bool = false
			if stored != null:
				var stored_dict: Dictionary = stored
				keep_stored = (
					stored_dict[&"target_eid"] == current_target_eid
					and stored_dict[&"target_pos"] == target_px
					and stored_dict[&"waypoint"] != from_px
				)
			if keep_stored:
				waypoint = (stored as Dictionary)[&"waypoint"]
			else:
				waypoint = _nav.next_waypoint_or_stay(
					species_comp[&"id"], from_px, target_px,
				)
				_waypoints[entity_id] = {
					&"waypoint": waypoint,
					&"target_eid": current_target_eid,
					&"target_pos": target_px,
				}

		# Speed comes from the entity's recipe — replaces the old
		# ANIMAL_SPEED_PX engine constant. Validator guarantees the field
		# exists for any entity with a `walks` capability; the .get
		# fallback is debug-only safety.
		var caps: Dictionary = _db.get_component(entity_id, &"body_capabilities")
		var walks: Dictionary = caps.get(&"walks", {})
		var speed_px: int = int(walks.get(&"speed_px_per_tick", 0))

		var step_result: Dictionary = NavPathStepper.step(
			from_px, waypoint, speed_px,
		)
		var new_pos: Vector2i = step_result[&"pos"]
		_db.set_component(entity_id, &"position", {&"x": new_pos.x, &"y": new_pos.y})
		_db.update_spatial(entity_id, new_pos.x, new_pos.y)

		# Arrival is determined by reaching the FINAL target, not intermediate
		# waypoints. A step snapping onto an intermediate nav point just ticks
		# the path forward on the next tick — clearing the sticky waypoint
		# so the next pass requests a fresh one from the navgraph.
		if new_pos == waypoint and waypoint != target_px:
			_waypoints.erase(entity_id)
		if new_pos != target_px:
			continue
		# Final-target arrival; clear the sticky waypoint.
		_waypoints.erase(entity_id)

		# Food state arrivals
		if state == &"HUNGRY":
			var food_id: int = _food.find_nearby_food(entity_id)
			if food_id != Constants.INVALID_ID:
				_db.set_component(entity_id, &"ai_state", {
					&"state": &"EATING",
					&"meta_state": &"GOAL_DIRECTED",
					&"commitment_score": 300,
				})
			else:
				_db.set_component(entity_id, &"ai_state", {
					&"state": &"PACING",
					&"meta_state": &"GOAL_DIRECTED",
					&"commitment_score": 100,
				})
				_events.creature_started_pacing.emit(entity_id)
			_timers.state_timers[entity_id] = 0.0
			continue
		if state == &"RETURNING":
			_db.set_component(entity_id, &"ai_state", {
				&"state": &"SETTLING",
				&"meta_state": &"GOAL_DIRECTED",
				&"commitment_score": 50,
			})
			_timers.state_timers[entity_id] = 0.0
			continue

		# Determine arrival state based on what drew the animal here.
		# If the target is an enterable host (box) the cat fits in, route
		# through SETTLING — the settle handler in _update_ambient_states
		# writes settled_in so the cat tucks visually. Otherwise fall back
		# to SNIFFING (curiosity ad) or IDLE.
		if target[&"entity_id"] != Constants.INVALID_ID \
				and _can_settle_in(entity_id, target[&"entity_id"]):
			_db.set_component(entity_id, &"ai_state", {
				&"state": &"SETTLING",
				&"meta_state": &"GOAL_DIRECTED",
				&"commitment_score": 50,
			})
			_timers.state_timers[entity_id] = 0.0
			continue

		var arrival_state: StringName = &"IDLE"
		var arrival_duration: float = -1.0
		if _timers.curiosity_trackers.has(entity_id) and target[&"entity_id"] != Constants.INVALID_ID:
			var target_id: int = target[&"entity_id"]
			if _db.has_component(target_id, &"advertisements"):
				var ads: Dictionary = _db.get_component(target_id, &"advertisements")
				for ad: Dictionary in ads[&"list"]:
					var ad_channel: StringName = ad.get(
						&"channel", ad.get(&"desire_type", &""),
					)
					if ad_channel == &"curiosity":
						arrival_state = &"SNIFFING"
						arrival_duration = float(ad.get(&"novelty_duration", 100)) / 10.0
						_timers.curiosity_trackers[entity_id].visit(
							target_id, _db.get_tick()
						)
						break

		_db.set_component(entity_id, &"ai_state", {
			&"state": arrival_state,
			&"meta_state": &"AMBIENT",
			&"commitment_score": 0,
		})
		_db.set_component(entity_id, &"target", {
			&"x": Constants.INVALID_ID,
			&"y": Constants.INVALID_ID,
			&"entity_id": Constants.INVALID_ID,
		})
		# Override min duration for this SNIFFING session if set
		if arrival_duration > 0.0:
			_timers.state_timers[entity_id] = 0.0
			_timers.min_durations_override[entity_id] = arrival_duration


func _can_settle_in(entity_id: int, host_id: int) -> bool:
	# A cat can settle in a host if the host's current state publishes a
	# `contained` join, the cat's species carries the `settles_in_containers`
	# capability, and the cat's body fits the join's inner_size_ru.
	if not _db.has_entity(host_id):
		return false
	if not _db.has_component(host_id, &"object_type"):
		return false
	if not _db.has_component(entity_id, &"species"):
		return false
	var otype: Dictionary = _db.get_component(host_id, &"object_type")
	var state: StringName = &"new"
	if _db.has_component(host_id, &"object_state"):
		var st: Dictionary = _db.get_component(host_id, &"object_state")
		state = st.get(&"state", &"new")
	var join: Dictionary = _osm.get_join_for_state(otype[&"type"], state)
	if join.get(&"type", &"") != &"contained":
		return false
	var species_id: StringName = _db.get_component(entity_id, &"species")[&"id"]
	if not _nav.has_capability(species_id, &"settles_in_containers"):
		return false
	var inner: int = join.get(&"inner_size_ru", 0)
	var body: int = _nav.get_body_size_ru(species_id)
	return body <= inner
