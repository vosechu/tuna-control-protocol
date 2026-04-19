extends Node

const ANIMAL_SPEED_PU: int = 200  # position units per tick (20 pixels/sec at 10Hz)
const FLOOR_Y_PU: int = Constants.FLOOR_Y * Constants.POSITION_SCALE  # 11200

var db: GameStateDB
var heat_grid: HeatGrid
var desire_resolver: DesireResolver
var desire_scatter: DesireScatter
var object_state_manager: ObjectStateManager
var nav_builder: NavGraphBuilder
var hum_system: HumSystem
var contentment: Contentment
var contentment_purr_bridge: ContentmentPurrBridge
var food_system: FoodSystem
var wiring_locks: WiringLockRegistry
var wiring_system: WiringSystem
var reclamation_system: ReclamationSystem
var plant_growth_system: PlantGrowthSystem
var entity_defs: EntityDefRegistry
var scenarios: ScenarioRegistry
var world_init: WorldInitSystem
var settings: Settings
var _mod_loader := ModLoader.new()
var _verb_resolver := VerbResolver.new()
# AI-DEV: Phase 0 in-memory guard — prevents re-applying the starter
# scenario mid-session. A save-aware flag (save meta) is Phase 1+ scope.
var _starter_applied: bool = false
var _state_timers: Dictionary = {}  # entity_id -> float (seconds in current state)
var _min_durations_override: Dictionary = {}  # entity_id -> float (per-session override)
var _curiosity_trackers: Dictionary = {}  # entity_id -> CuriosityTracker
var _min_durations: Dictionary = {
	&"IDLE": 3.0,
	&"GROOMING": 10.0,
	&"LOAFING": 15.0,
	&"SLEEPING": 30.0,
	&"SNIFFING": 10.0,
	&"SPEED_BUMP": 15.0,
}


func _ready() -> void:
	db = GameStateDB.new()
	settings = Settings.new()
	# Phase 0: enable the debug Shift+F1 override in editor/debug builds.
	# Release builds keep debug_enabled=false; DebugHud asserts on that.
	if OS.has_feature("editor") or OS.has_feature("debug"):
		settings.debug_enabled = true
	var mod_result: Dictionary = _mod_loader.load_all(
		"res://mods/",
	)
	entity_defs = mod_result["entity_defs"]
	scenarios = mod_result["scenarios"]
	world_init = WorldInitSystem.new(db, entity_defs, scenarios)
	heat_grid = HeatGrid.new(db)
	contentment = Contentment.new(db)
	contentment_purr_bridge = ContentmentPurrBridge.new(db)
	hum_system = HumSystem.new(db, Events)
	food_system = FoodSystem.new(db, hum_system, Events)
	wiring_locks = WiringLockRegistry.new()
	# AI-DEV: cable_max_length_ru is the euclidean cap WiringSystem enforces on
	# handle_connect. Lift into a ConfigRegistry lookup when one ships.
	wiring_system = WiringSystem.new(
		db, wiring_locks, Events, {&"cable_max_length_ru": 20},
	)
	desire_resolver = DesireResolver.new(db)
	desire_scatter = DesireScatter.new(db)
	object_state_manager = ObjectStateManager.new(db)
	reclamation_system = ReclamationSystem.new(db)
	plant_growth_system = PlantGrowthSystem.new(db, heat_grid)
	nav_builder = NavGraphBuilder.new()
	_register_species_nav()
	nav_builder.build()
	_spawn_starter_entities()
	_build_nav_for_objects()


func _register_species_nav() -> void:
	for entity_id: StringName in entity_defs.get_all_entities():
		if entity_defs.has_traversal(entity_id):
			nav_builder.register_species(
				entity_id,
				entity_defs.get_traversal(entity_id),
			)


func _build_nav_for_objects() -> void:
	# Register nav nodes for all pre-placed objects in rack slots
	var objects: Array[int] = db.get_entities_with(&"object_type")
	for entity_id: int in objects:
		var pos: Dictionary = db.get_component(entity_id, &"position")
		var layout: Dictionary = Constants.pu_to_bay_rack_slot(pos[&"x"], pos[&"y"])
		if layout[&"slot"] < Constants.SLOTS_PER_RACK:
			nav_builder.add_rack_slot(layout[&"rack"], layout[&"slot"])


func _physics_process(_delta: float) -> void:
	# AI-DEV: This tick order is load-bearing. If you change it, update
	# the EXPECTED_ORDER array in tests/integration/test_tick_loop.gd.
	# Key constraints:
	#   - heat_grid before _scatter_desires (warmth feeds desire scatter)
	#   - contentment before contentment_purr_bridge (bridge reads is_satisfied)
	#   - contentment_purr_bridge before hum_system (maps purr.intensity before charge)
	#   - hum_system before desire_resolver (HUM reserve affects arm actions)
	#   - _move_animals before reclamation (reads fresh positions)
	#   - food_system before reclamation (food state resolves before presence)
	#   - reclamation before plant_growth (reads fresh presence)
	#   - plant_growth before _update_ambient_states (transitions
	#     influence next tick's ambient state selection)
	db.advance_tick()                                       # 1
	heat_grid.propagate()                                   # 2
	_scatter_desires()                                      # 3
	contentment.evaluate_all()                              # 4
	contentment_purr_bridge.tick()                          # 5
	hum_system.tick_charge()                                # 6
	hum_system.tick_idle_drain()                            # 7
	_decay_commitment()                                     # 8
	desire_resolver.mark_all_dirty()                        # 9
	desire_resolver.evaluate_budget(_curiosity_trackers)    # 10
	_move_animals()                                         # 11
	food_system.tick_arms()                                 # 12
	food_system.tick_cleanup()                              # 13
	reclamation_system.tick()                               # 14
	plant_growth_system.tick()                              # 15
	_update_ambient_states()                                # 16
	# Drop pickup locks whose owners haven't touched them in 20s. Cheap;
	# runs once per tick so abandoned drags can't wedge the registry.
	wiring_locks.tick_expire(db.get_tick(), 200)
	db.flush_notifications()                                # 17


func _decay_commitment() -> void:
	var animals: Array[int] = db.get_entities_with(&"ai_state")
	for entity_id: int in animals:
		var ai: Dictionary = db.get_component(entity_id, &"ai_state")
		var commitment: int = ai[&"commitment_score"]
		if commitment > 0:
			# Decay by 1 per tick (10 per second at 10Hz)
			var new_commitment: int = maxi(0, commitment - 1)
			db.set_component(entity_id, &"ai_state", {
				&"state": ai[&"state"],
				&"meta_state": ai[&"meta_state"],
				&"commitment_score": new_commitment,
			})


func _scatter_desires() -> void:
	var animals: Array[int] = db.get_entities_with(&"desires")
	for entity_id in animals:
		if not db.has_component(entity_id, &"position"):
			continue
		var pos: Dictionary = db.get_component(entity_id, &"position")
		var layout: Dictionary = Constants.pu_to_bay_rack_slot(pos[&"x"], pos[&"y"])
		var rack: int = layout[&"rack"]
		var slot: int = layout[&"slot"]
		var cell: int
		if pos[&"y"] >= Constants.FLOOR_Y * Constants.POSITION_SCALE:
			cell = Constants.floor_cell(rack)
		else:
			cell = Constants.rack_cell(rack, slot)
		var temp: int = heat_grid.get_temperature(cell)
		# Warmth desire is satisfaction: 0 = cold/desperate, 1000 = warm/satisfied.
		# Temperature: 0 = cold, 1000 = hot. They match directly.
		db.set_field(entity_id, &"desires", &"warmth", temp)
	# Satisfaction decay over time (positive values drop toward 0 = desperate).
	db.add_all(&"desires", &"comfort", -5)
	db.add_all(&"desires", &"curiosity", -3)
	db.add_all(&"desires", &"hunger", -3)
	db.add_all(&"desires", &"attention", -8)
	# Satisfaction from nearby object advertisements (warmth, comfort, etc.)
	desire_scatter.scatter_from_ads()
	db.clamp_all(&"desires", &"warmth", 0, 1000)
	db.clamp_all(&"desires", &"comfort", 0, 1000)
	db.clamp_all(&"desires", &"curiosity", 0, 1000)
	db.clamp_all(&"desires", &"hunger", 0, 1000)
	db.clamp_all(&"desires", &"attention", 0, 1000)



func _move_animals() -> void:
	var animals: Array[int] = db.get_entities_with(&"ai_state")
	for entity_id: int in animals:
		var ai: Dictionary = db.get_component(entity_id, &"ai_state")
		var state: StringName = ai[&"state"]
		if state != &"SEEKING" and state != &"MOVING_TO" \
				and state != &"WANDERING" \
				and state != &"HUNGRY" \
				and state != &"RETURNING":
			continue

		var pos: Dictionary = db.get_component(entity_id, &"position")
		var target: Dictionary = db.get_component(entity_id, &"target")
		# SEEKING/MOVING_TO require an entity target; WANDERING just needs a position
		if state != &"WANDERING" and target[&"entity_id"] == Constants.INVALID_ID:
			continue

		# Transition SEEKING -> MOVING_TO on first movement tick, with nav graph check
		if state == &"SEEKING":
			var species: Dictionary = db.get_component(entity_id, &"species")
			var from_pos: Vector2 = Vector2(float(pos[&"x"]), float(pos[&"y"]))
			var to_pos: Vector2 = Vector2(float(target[&"x"]), float(target[&"y"]))
			if not nav_builder.can_reach(species[&"id"], from_pos, to_pos):
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
				continue
			db.set_component(entity_id, &"ai_state", {
				&"state": &"MOVING_TO",
				&"meta_state": &"GOAL_DIRECTED",
				&"commitment_score": ai[&"commitment_score"],
			})
		# WANDERING skips nav check — random floor positions are always reachable

		# Pick next waypoint. Nav-guided states step through nav-graph nodes
		# so floor→slot edges are traversed where the path requires them.
		# WANDERING moves directly on the floor plane (random floor targets
		# are always reachable without a graph query).
		var from_pu: Vector2i = Vector2i(pos[&"x"], pos[&"y"])
		var target_pu: Vector2i = Vector2i(target[&"x"], target[&"y"])
		var waypoint: Vector2i = target_pu
		if state != &"WANDERING" and db.has_component(entity_id, &"species"):
			var species_comp: Dictionary = db.get_component(entity_id, &"species")
			waypoint = _next_path_waypoint(species_comp[&"id"], from_pu, target_pu)

		var step_result: Dictionary = NavPathStepper.step(
			from_pu, waypoint, ANIMAL_SPEED_PU,
		)
		var new_pos: Vector2i = step_result[&"pos"]
		db.set_component(entity_id, &"position", {&"x": new_pos.x, &"y": new_pos.y})
		db.update_spatial(entity_id, new_pos.x, new_pos.y)

		# Arrival is determined by reaching the FINAL target, not intermediate
		# waypoints. A step snapping onto an intermediate nav point just ticks
		# the path forward on the next tick.
		if new_pos != target_pu:
			continue

		# Food state arrivals
		if state == &"HUNGRY":
			var food_id: int = _find_nearby_food(
				entity_id,
			)
			if food_id != Constants.INVALID_ID:
				db.set_component(entity_id, &"ai_state", {
					&"state": &"EATING",
					&"meta_state": &"GOAL_DIRECTED",
					&"commitment_score": 300,
				})
			else:
				db.set_component(entity_id, &"ai_state", {
					&"state": &"PACING",
					&"meta_state": &"GOAL_DIRECTED",
					&"commitment_score": 100,
				})
				Events.creature_started_pacing.emit(
					entity_id,
				)
			_state_timers[entity_id] = 0.0
			continue
		if state == &"RETURNING":
			db.set_component(entity_id, &"ai_state", {
				&"state": &"SETTLING",
				&"meta_state": &"GOAL_DIRECTED",
				&"commitment_score": 50,
			})
			_state_timers[entity_id] = 0.0
			continue

		# Determine arrival state based on what drew the animal here
		var arrival_state: StringName = &"IDLE"
		var arrival_duration: float = -1.0
		if _curiosity_trackers.has(entity_id) and target[&"entity_id"] != Constants.INVALID_ID:
			var target_id: int = target[&"entity_id"]
			if db.has_component(target_id, &"advertisements"):
				var ads: Dictionary = db.get_component(target_id, &"advertisements")
				for ad: Dictionary in ads[&"list"]:
					if ad[&"desire_type"] == &"curiosity":
						arrival_state = &"SNIFFING"
						arrival_duration = float(ad.get(&"novelty_duration", 100)) / 10.0
						_curiosity_trackers[entity_id].visit(
							target_id, db.get_tick()
						)
						break

		db.set_component(entity_id, &"ai_state", {
			&"state": arrival_state,
			&"meta_state": &"AMBIENT",
			&"commitment_score": 0,
		})
		db.set_component(entity_id, &"target", {
			&"x": Constants.INVALID_ID,
			&"y": Constants.INVALID_ID,
			&"entity_id": Constants.INVALID_ID,
		})
		# Override min duration for this SNIFFING session if set
		if arrival_duration > 0.0:
			_state_timers[entity_id] = 0.0
			_min_durations_override[entity_id] = arrival_duration


func _next_path_waypoint(
	species_id: StringName, from_pu: Vector2i, target_pu: Vector2i,
) -> Vector2i:
	# Returns the next intermediate nav-graph point to step toward, or the
	# final target if the path is empty/trivial. Per-tick recomputation is
	# cheap at current nav-graph size (~5-15 nodes) and avoids state.
	var path: PackedVector2Array = nav_builder.get_path_points(
		species_id,
		Vector2(float(from_pu.x), float(from_pu.y)),
		Vector2(float(target_pu.x), float(target_pu.y)),
	)
	if path.size() <= 1:
		return target_pu
	for i: int in range(path.size()):
		var pt: Vector2 = path[i]
		var wp: Vector2i = Vector2i(roundi(pt.x), roundi(pt.y))
		if wp != from_pu:
			return wp
	return target_pu


func _update_ambient_states() -> void:
	var tick_delta: float = 0.1  # 1/10Hz
	var animals: Array[int] = db.get_entities_with(&"ai_state")
	for entity_id: int in animals:
		if not db.has_component(entity_id, &"species"):
			continue
		var ai: Dictionary = db.get_component(entity_id, &"ai_state")

		# Recover from STARTLED after min duration expires
		if ai[&"state"] == &"STARTLED":
			if not _state_timers.has(entity_id):
				_state_timers[entity_id] = 0.0
			_state_timers[entity_id] += tick_delta
			var startled_dur: float = _min_durations.get(&"STARTLED", 1.0)
			if _state_timers[entity_id] >= startled_dur:
				db.set_component(entity_id, &"ai_state", {
					&"state": &"IDLE",
					&"meta_state": &"AMBIENT",
					&"commitment_score": 0,
				})
				_state_timers[entity_id] = 0.0
			continue

		# Food state machine (GOAL_DIRECTED states)
		if ai[&"state"] == &"PACING":
			_state_timers[entity_id] = (
				_state_timers.get(entity_id, 0.0) + tick_delta
			)
			var food_id: int = _find_nearby_food(entity_id)
			if food_id != Constants.INVALID_ID:
				db.set_component(entity_id, &"ai_state", {
					&"state": &"EATING",
					&"meta_state": &"GOAL_DIRECTED",
					&"commitment_score": 300,
				})
				_state_timers[entity_id] = 0.0
			continue

		if ai[&"state"] == &"EATING":
			_state_timers[entity_id] = (
				_state_timers.get(entity_id, 0.0) + tick_delta
			)
			db.add_field(entity_id, &"desires", &"hunger", 30)
			db.clamp_field(
				entity_id, &"desires", &"hunger", 0, 1000,
			)
			if _state_timers[entity_id] >= 3.0:
				_mark_nearest_can_eaten(entity_id)
				var box_id: int = _find_nearest_box(entity_id)
				if box_id != Constants.INVALID_ID:
					var bpos: Dictionary = db.get_component(
						box_id, &"position",
					)
					db.set_component(entity_id, &"ai_state", {
						&"state": &"RETURNING",
						&"meta_state": &"GOAL_DIRECTED",
						&"commitment_score": 150,
					})
					db.set_component(entity_id, &"target", {
						&"x": bpos[&"x"],
						&"y": bpos[&"y"],
						&"entity_id": box_id,
					})
				else:
					db.set_component(entity_id, &"ai_state", {
						&"state": &"IDLE",
						&"meta_state": &"AMBIENT",
						&"commitment_score": 0,
					})
				_state_timers[entity_id] = 0.0
			continue

		if ai[&"state"] == &"SETTLING":
			_state_timers[entity_id] = (
				_state_timers.get(entity_id, 0.0) + tick_delta
			)
			if _state_timers[entity_id] >= 2.0:
				db.set_component(entity_id, &"ai_state", {
					&"state": &"LOAFING",
					&"meta_state": &"AMBIENT",
					&"commitment_score": 0,
				})
				_state_timers[entity_id] = 0.0
			continue

		if ai[&"meta_state"] != &"AMBIENT":
			continue

		# Check hunger for AMBIENT cats
		if db.has_component(entity_id, &"desires"):
			var desires: Dictionary = db.get_component(
				entity_id, &"desires",
			)
			if desires.has(&"hunger") and desires[&"hunger"] < 400:
				var target_id: int = _find_nearest_dispenser(
					entity_id,
				)
				if target_id != Constants.INVALID_ID:
					var tpos: Dictionary = db.get_component(
						target_id, &"position",
					)
					db.set_component(entity_id, &"ai_state", {
						&"state": &"HUNGRY",
						&"meta_state": &"GOAL_DIRECTED",
						&"commitment_score": 200,
					})
					db.set_component(entity_id, &"target", {
						&"x": tpos[&"x"],
						&"y": tpos[&"y"],
						&"entity_id": target_id,
					})
					_state_timers[entity_id] = 0.0
					continue
				else:
					db.set_component(entity_id, &"ai_state", {
						&"state": &"PACING",
						&"meta_state": &"GOAL_DIRECTED",
						&"commitment_score": 200,
					})
					Events.creature_started_pacing.emit(
						entity_id,
					)
					_state_timers[entity_id] = 0.0
					continue

		# Update timer
		if not _state_timers.has(entity_id):
			_state_timers[entity_id] = 0.0
		_state_timers[entity_id] += tick_delta

		# Check if min duration elapsed
		var current_state: StringName = ai[&"state"]
		var min_dur: float = _min_durations_override.get(
			entity_id, _min_durations.get(current_state, 3.0)
		)
		if _state_timers[entity_id] < min_dur:
			continue

		# Pick new ambient state — species recipe supplies the pool.
		var desires: Dictionary = db.get_component(entity_id, &"desires")
		var is_warm: bool = desires[&"warmth"] < 400
		if not db.has_component(entity_id, &"ambient_states"):
			continue
		var pools: Dictionary = db.get_component(entity_id, &"ambient_states")
		var pool: Array = pools.get("warm" if is_warm else "cold", [])
		var new_state: StringName = _pick_ambient_state(pool)
		if new_state != current_state:
			db.set_component(entity_id, &"ai_state", {
				&"state": new_state,
				&"meta_state": &"AMBIENT",
				&"commitment_score": ai[&"commitment_score"],
			})
			_state_timers[entity_id] = 0.0
			_min_durations_override.erase(entity_id)


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


func place_object(
	object_type: StringName,
	world_x: int,
	world_y: int,
) -> int:
	var entity: int = db.create_entity()
	db.set_component(
		entity, &"position", {&"x": world_x, &"y": world_y}
	)

	match object_type:
		&"server_1u":
			db.set_component(entity, &"heat_source", {
				&"value": 1000, &"radius_ru": 5,
			})
			db.set_component(entity, &"advertisements", {
				&"list": [{
					&"desire_type": &"warmth",
					&"strength": 800,
					&"radius_ru": 8,
					&"max_occupants": 1,
				}],
			})
			# No hum_receiver — servers are wireless per hum-cable-system.md.
			# Only dedicated HUM devices listen on the purr channel; servers
			# emit heat. A stray hum_receiver here would compete for nearest-
			# receiver matches in tick_charge and route purr into a non-HUM.
		&"cardboard_box":
			db.set_component(entity, &"advertisements", {
				&"list": [
					{
						&"desire_type": &"comfort",
						&"strength": 700,
						&"radius_ru": 4,
						&"max_occupants": 1,
					},
					{
						&"desire_type": &"curiosity",
						&"strength": 500,
						&"radius_ru": 5,
						&"novelty_duration": 400,
						&"novelty_cooldown": 300,
					},
				],
			})
		&"clothes_pile":
			db.set_component(entity, &"advertisements", {
				&"list": [{
					&"desire_type": &"comfort",
					&"strength": 800,
					&"radius_ru": 4,
					&"max_occupants": 3,
				}],
			})
		&"hum_device":
			db.set_component(entity, &"hum_receiver", {
				&"radius_ru": 4,
			})
		&"tuna_dispenser":
			db.set_component(entity, &"tuna_dispenser", {
				&"hum_cost": 50,
				&"can_type": &"tcp_tuna:tuna_can",
			})
			# No advertisements — food comes from open tuna cans only.
			# Future work: an excitement/noise channel when those ship.
		&"tuna_button":
			var disp_id: int = _find_dispenser_in_rack(
				world_x, world_y,
			)
			if disp_id != Constants.INVALID_ID:
				db.set_component(entity, &"tuna_button", {
					&"dispenser_id": disp_id,
				})
			else:
				push_error(
					"No TUNA dispenser in this rack"
				)
		&"arm":
			db.set_component(entity, &"arm", {
				&"radius_ru": 3,
				&"hum_cost": 30,
				&"open_duration_ticks": 20,
			})

	db.set_component(
		entity, &"object_type", {&"type": object_type}
	)
	db.update_spatial(entity, world_x, world_y)
	var layout: Dictionary = Constants.pu_to_bay_rack_slot(world_x, world_y)
	var rack: int = int(layout[&"rack"])
	var slot: int = int(layout[&"slot"])
	# Add nav node if object is in a rack slot (not on the floor)
	if slot < Constants.SLOTS_PER_RACK:
		nav_builder.add_rack_slot(rack, slot)
	Events.object_placed.emit(
		entity, rack, slot, object_type
	)
	return entity


func remove_object(entity_id: int) -> void:
	if not db.has_entity(entity_id):
		return
	var pos: Dictionary = db.get_component(
		entity_id, &"position"
	)
	# Startle nearby animals
	var nearby: Array[int] = db.query_radius(
		pos[&"x"], pos[&"y"], Constants.ru_to_pu(2)
	)
	for other_id: int in nearby:
		if not db.has_component(other_id, &"species"):
			continue
		if not db.has_component(other_id, &"ai_state"):
			continue
		db.set_component(other_id, &"ai_state", {
			&"state": &"STARTLED",
			&"meta_state": &"SPECIAL",
			&"commitment_score": 0,
		})
		_state_timers[other_id] = 0.0
	var layout: Dictionary = Constants.pu_to_bay_rack_slot(pos[&"x"], pos[&"y"])
	# Remove nav node if object was in a rack slot
	if layout[&"slot"] < Constants.SLOTS_PER_RACK:
		nav_builder.remove_rack_slot(layout[&"rack"], layout[&"slot"])
	Events.object_removed.emit(entity_id, layout[&"rack"], layout[&"slot"])
	db.remove_spatial(entity_id)
	db.destroy_entity(entity_id)


func _spawn_starter_entities() -> void:
	# Scenario-driven world init — populates the Phase 0 starter bay
	# (HUM device, TUNA dispenser + button, ARM) from the tcp_base:starter
	# scenario JSONC. Guarded against re-entry by _starter_applied so a
	# second _ready (e.g. test re-use) won't double-spawn.
	if not _starter_applied:
		world_init.apply(settings.starter_scenario_id)
		_starter_applied = true
		# TODO Phase 2: emit a robot_log signal once Events grows one.

	# Starter-entity spawn — driven by each loaded species recipe's `starters` array.
	var floor_y: int = FLOOR_Y_PU + Constants.FLOOR_HEIGHT_PU / 2
	for species_id: StringName in entity_defs.get_all_entities():
		var def: Dictionary = entity_defs.get_definition(species_id)
		if not def.has("starters"):
			continue
		var starters: Array = def["starters"]
		for entry: Dictionary in starters:
			var rack: int = int(entry.get("rack", 0))
			var overrides: Dictionary = {
				&"name": StringName(entry.get("name", "")),
				&"position": {
					&"x": Constants.rack_slot_to_pu(0, rack, 0).x,
					&"y": floor_y,
				},
			}
			if entry.has("desires"):
				var d: Dictionary = entry["desires"]
				var typed: Dictionary = {}
				for k: String in d:
					typed[StringName(k)] = int(d[k])
				overrides[&"desires"] = typed
			entity_defs.spawn(species_id, db, overrides)

	_spawn_rack_entities()
	_create_curiosity_trackers()


func _spawn_rack_entities() -> void:
	for rack_idx: int in Constants.RACK_COUNT:
		var rack_entity: int = db.create_entity()
		var x: int = Constants.rack_slot_to_pu(0, rack_idx, 0).x
		var y: int = FLOOR_Y_PU
		db.set_component(rack_entity, &"position", {&"x": x, &"y": y})
		db.set_component(rack_entity, &"advertisements", {&"list": [
			{
				&"desire_type": &"curiosity",
				&"strength": 500,
				&"radius_ru": 8,
				&"novelty_duration": 30,
				&"novelty_cooldown": 100,
			},
		]})
		db.update_spatial(rack_entity, x, y)


func _create_curiosity_trackers() -> void:
	var entities: Array[int] = db.get_entities_with(&"desires")
	for entity_id: int in entities:
		if _curiosity_trackers.has(entity_id):
			continue
		var desires: Dictionary = db.get_component(entity_id, &"desires")
		if desires.has(&"curiosity"):
			_curiosity_trackers[entity_id] = CuriosityTracker.new()


func _find_dispenser_in_rack(
		world_x: int, world_y: int,
) -> int:
	var btn_layout: Dictionary = Constants.pu_to_bay_rack_slot(world_x, world_y)
	var rack: int = int(btn_layout[&"rack"])
	var dispensers: Array[int] = db.get_entities_with(
		&"tuna_dispenser",
	)
	for disp_id: int in dispensers:
		var dpos: Dictionary = db.get_component(
			disp_id, &"position",
		)
		var disp_layout: Dictionary = Constants.pu_to_bay_rack_slot(dpos[&"x"], dpos[&"y"])
		var disp_rack: int = int(disp_layout[&"rack"])
		if disp_rack == rack:
			return disp_id
	return Constants.INVALID_ID


func _find_nearest_dispenser(entity_id: int) -> int:
	var pos: Dictionary = db.get_component(
		entity_id, &"position",
	)
	var dispensers: Array[int] = db.get_entities_with(
		&"tuna_dispenser",
	)
	var best_id: int = Constants.INVALID_ID
	var best_dist: int = 999999
	for disp_id: int in dispensers:
		var dpos: Dictionary = db.get_component(
			disp_id, &"position",
		)
		var dist: int = (
			absi(dpos[&"x"] - pos[&"x"])
			+ absi(dpos[&"y"] - pos[&"y"])
		)
		if dist < best_dist:
			best_dist = dist
			best_id = disp_id
	return best_id


func _find_nearby_food(entity_id: int) -> int:
	var pos: Dictionary = db.get_component(
		entity_id, &"position",
	)
	var nearby: Array[int] = db.query_radius(
		pos[&"x"], pos[&"y"], Constants.ru_to_pu(3),
	)
	for other_id: int in nearby:
		if db.has_component(other_id, &"tuna_can"):
			var can: Dictionary = db.get_component(
				other_id, &"tuna_can",
			)
			if can[&"state"] == &"opened":
				return other_id
	return Constants.INVALID_ID


func _find_nearest_box(entity_id: int) -> int:
	var pos: Dictionary = db.get_component(
		entity_id, &"position",
	)
	var objects: Array[int] = db.get_entities_with(
		&"object_type",
	)
	var best_id: int = Constants.INVALID_ID
	var best_dist: int = 999999
	for obj_id: int in objects:
		var otype: Dictionary = db.get_component(
			obj_id, &"object_type",
		)
		if otype[&"type"] != &"cardboard_box":
			continue
		var opos: Dictionary = db.get_component(
			obj_id, &"position",
		)
		var dist: int = (
			absi(opos[&"x"] - pos[&"x"])
			+ absi(opos[&"y"] - pos[&"y"])
		)
		if dist < best_dist:
			best_dist = dist
			best_id = obj_id
	return best_id


func _mark_nearest_can_eaten(entity_id: int) -> void:
	var food_id: int = _find_nearby_food(entity_id)
	if food_id != Constants.INVALID_ID:
		var can: Dictionary = db.get_component(
			food_id, &"tuna_can",
		)
		can[&"state"] = &"eaten"
		db.set_component(food_id, &"tuna_can", can)
		db.remove_component(food_id, &"advertisements")
