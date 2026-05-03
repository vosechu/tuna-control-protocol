extends Node

var db: GameStateDB
var heat_grid: HeatGrid
var desire_resolver: DesireResolver
var desire_scatter: DesireScatter
var desire_decay_system: DesireDecaySystem
var object_state_manager: ObjectStateManager
var nav_builder: NavGraphBuilder
var hum_system: HumSystem
var contentment: Contentment
var contentment_purr_bridge: ContentmentPurrBridge
var food_system: FoodSystem
var movement_system: MovementSystem
var reclamation_system: ReclamationSystem
var plant_growth_system: PlantGrowthSystem
var settled_lifecycle: SettledLifecycle
var entity_defs: EntityDefRegistry
var scenarios: ScenarioRegistry
var world_init: WorldInitSystem
var settings: Settings
var _mod_loader := ModLoader.new()
var _verb_resolver := VerbResolver.new()
var _behavior_timers: BehaviorTimers
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
	desire_resolver = DesireResolver.new(db)
	desire_scatter = DesireScatter.new(db)
	desire_decay_system = DesireDecaySystem.new(db)
	object_state_manager = ObjectStateManager.new(db)
	reclamation_system = ReclamationSystem.new(db)
	plant_growth_system = PlantGrowthSystem.new(db, heat_grid)
	settled_lifecycle = SettledLifecycle.new(db)
	nav_builder = NavGraphBuilder.new()
	_register_species_nav()
	nav_builder.build()
	desire_resolver.set_nav_builder(nav_builder)
	_behavior_timers = BehaviorTimers.new()
	# Alias the shared state-timer dicts onto the same underlying tables
	# the MovementSystem reads via _behavior_timers. Dictionary is a
	# reference type, so writes via either name land in one place. Once
	# AiStateSystem extracts (Task 5.2), these aliases drop and only
	# _behavior_timers remains.
	_state_timers = _behavior_timers.state_timers
	_min_durations_override = _behavior_timers.min_durations_override
	_curiosity_trackers = _behavior_timers.curiosity_trackers
	movement_system = MovementSystem.new(
		db, nav_builder, object_state_manager,
		Events, _behavior_timers, food_system,
	)
	_spawn_starter_entities()
	_build_nav_for_objects()


func _register_species_nav() -> void:
	for entity_id: StringName in entity_defs.get_all_entities():
		if not entity_defs.has_body_capabilities(entity_id):
			continue
		var caps: Dictionary = entity_defs.get_body_capabilities(entity_id)
		var geom: Dictionary = entity_defs.get_body_geometry(entity_id)
		nav_builder.register_species(entity_id, caps, geom)


func _build_nav_for_objects() -> void:
	# Register nav nodes for all pre-placed objects in rack slots
	var objects: Array[int] = db.get_entities_with(&"object_type")
	for entity_id: int in objects:
		var pos: Dictionary = db.get_component(entity_id, &"position")
		var world_pos := Vector2i(pos[&"x"], pos[&"y"])
		var bay: int = Constants.world_to_bay(world_pos)
		if bay == Constants.INVALID_BAY:
			continue
		var q: SlotQuery = Constants.bay_local_to_slot(bay, world_pos)
		if q.zone == &"slot":
			nav_builder.add_rack_slot(q.get_rack(), q.get_slot())


func _physics_process(_delta: float) -> void:
	# AI-DEV: This tick order is load-bearing. If you change it, update
	# the EXPECTED_ORDER array in tests/integration/test_tick_loop.gd.
	# Key constraints:
	#   - heat_grid before _scatter_desires (warmth feeds desire scatter)
	#   - contentment before contentment_purr_bridge (bridge reads is_satisfied)
	#   - contentment_purr_bridge before hum_system (maps purr.intensity before charge)
	#   - hum_system before desire_resolver (HUM reserve affects arm actions)
	#   - movement_system before reclamation (reads fresh positions)
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
	movement_system.tick()                                  # 11
	food_system.tick_arms()                                 # 12
	food_system.tick_cleanup()                              # 13
	reclamation_system.tick()                               # 14
	plant_growth_system.tick()                              # 15
	_update_ambient_states()                                # 16
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
		var world_pos := Vector2i(pos[&"x"], pos[&"y"])
		var bay: int = Constants.world_to_bay(world_pos)
		if bay == Constants.INVALID_BAY:
			continue
		var q: SlotQuery = Constants.bay_local_to_slot(bay, world_pos)
		var cell: int
		match q.zone:
			&"slot":
				cell = Constants.rack_cell(q.get_rack(), q.get_slot())
			&"floor":
				cell = Constants.floor_cell(q.get_rack())
			_:
				# Frame, baseboard, other — no heat cell, skip warmth update
				continue
		var temp: int = heat_grid.get_temperature(cell)
		# Warmth desire is satisfaction: 0 = cold/desperate, 1000 = warm/satisfied.
		# Temperature: 0 = cold, 1000 = hot. They match directly.
		db.set_field(entity_id, &"desires", &"warmth", temp)
	# Per-species satisfaction decay over time. Each entity reads its own
	# decay values from the `desire_decay` component (set from recipe by
	# EntityDefRegistry). Hardcoded global decays were removed in the
	# recipe-driven balance migration.
	desire_decay_system.tick()
	# Satisfaction from nearby object advertisements (warmth, comfort, etc.)
	desire_scatter.scatter_from_ads()
	db.clamp_all(&"desires", &"warmth", 0, 1000)
	db.clamp_all(&"desires", &"comfort", 0, 1000)
	db.clamp_all(&"desires", &"curiosity", 0, 1000)
	db.clamp_all(&"desires", &"hunger", 0, 1000)
	db.clamp_all(&"desires", &"social", 0, 1000)
	db.clamp_all(&"desires", &"safety", 0, 1000)
	db.clamp_all(&"desires", &"quiet", 0, 1000)
	db.clamp_all(&"desires", &"peace", 0, 1000)



func _update_ambient_states() -> void:
	var tick_delta: float = 0.1  # 1/10Hz
	var animals: Array[int] = db.get_entities_with(&"ai_state")
	for entity_id: int in animals:
		if not db.has_component(entity_id, &"species"):
			continue
		# Settled entities are deliberately resting at a host. Mirror the
		# desire_resolver guard from commit 33be244 — without this skip the
		# hunger-block at the bottom of this loop converts a SLEEPING
		# settled cat into PACING the moment its hunger crosses 400, even
		# though `settled_in` should mean "stay put."
		if db.has_component(entity_id, &"settled_in"):
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
			var food_id: int = food_system.find_nearby_food(entity_id)
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
				food_system.mark_nearest_can_eaten(entity_id)
				var box_id: int = food_system.find_nearest_box(entity_id)
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
				# Tuck into the host (box) the cat walked to. The target
				# entity_id was preserved through arrival so SETTLING knows
				# its host. Without settled_in the cat would fall through to
				# AMBIENT and immediately re-target the same box on the
				# resolver's next pass.
				var t: Dictionary = db.get_component(entity_id, &"target")
				var host_id: int = t[&"entity_id"]
				if host_id != Constants.INVALID_ID and db.has_entity(host_id):
					settled_lifecycle.enter(entity_id, host_id)
				db.set_component(entity_id, &"ai_state", {
					&"state": &"SLEEPING",
					&"meta_state": &"AMBIENT",
					&"commitment_score": 0,
				})
				db.set_component(entity_id, &"target", {
					&"x": Constants.INVALID_ID,
					&"y": Constants.INVALID_ID,
					&"entity_id": Constants.INVALID_ID,
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
			if desires.has(&"hunger") \
					and CatFoodStates.should_become_hungry(db, entity_id):
				var target_id: int = food_system.find_nearest_dispenser(
					entity_id, nav_builder,
				)
				if target_id != Constants.INVALID_ID:
					var tpos: Dictionary = db.get_component(
						target_id, &"position",
					)
					# Reachability is enforced at movement time by
					# nav_builder.next_waypoint_or_stay; an unreachable
					# dispenser target just means the cat won't move toward
					# it. PACING below remains the fallback when no dispenser
					# exists at all.
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
				&"value": 1000, &"radius_px": 40,
			})
			db.set_component(entity, &"advertisements", {
				&"list": [{
					&"desire_type": &"warmth",
					&"strength": 800,
					&"radius_px": 64,
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
						&"radius_px": 32,
						&"max_occupants": 1,
						# AI-DEV: action-tagged so passive proximity doesn't
						# satisfy comfort. A cat must actually settle in (see
						# SettledLifecycle) to consume this ad. Without the
						# tag, cats sit on adjacent servers, scatter fills
						# their comfort to ~920, and the box ad's score drops
						# below SWITCH_THRESHOLD — they're "comforted" without
						# ever climbing in. DesireScatter bypasses the action
						# gate when other_id == entity's settled_in.host_id.
						&"action": &"settle",
					},
					{
						&"desire_type": &"curiosity",
						&"strength": 500,
						&"radius_px": 40,
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
					&"radius_px": 32,
					&"max_occupants": 3,
				}],
			})
		&"hum_device":
			db.set_component(entity, &"hum_receiver", {
				&"radius_px": 32,
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
				&"radius_px": Constants.ARM_REACH_PX,
				&"hum_cost": 30,
				&"open_duration_ticks": 20,
			})

	db.set_component(
		entity, &"object_type", {&"type": object_type}
	)
	db.update_spatial(entity, world_x, world_y)
	var world_pos := Vector2i(world_x, world_y)
	var bay: int = Constants.world_to_bay(world_pos)
	var rack: int = Constants.INVALID_ID
	var slot: int = Constants.INVALID_SLOT
	if bay != Constants.INVALID_BAY:
		var q: SlotQuery = Constants.bay_local_to_slot(bay, world_pos)
		if q.zone == &"slot":
			rack = q.get_rack()
			slot = q.get_slot()
			nav_builder.add_rack_slot(rack, slot)
			# Enterable hosts (currently cardboard_box) publish a `join` block
			# in their per-state ad config. Wire entry/interior anchors and
			# species-gated ENTER edges into the navgraph at placement time.
			var initial_state: StringName = &"new"
			if db.has_component(entity, &"object_state"):
				var st: Dictionary = db.get_component(entity, &"object_state")
				initial_state = st.get(&"state", &"new")
			var join: Dictionary = object_state_manager.get_join_for_state(
				object_type, initial_state,
			)
			if not join.is_empty():
				nav_builder.add_box_enterable(rack, slot, join)
		elif q.zone != &"other":
			rack = q.rack
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
	# Startle nearby animals (2 slot-heights radius)
	var nearby: Array[int] = db.query_radius(
		pos[&"x"], pos[&"y"], 2 * Constants.SLOT_HEIGHT_PX
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
	var world_pos := Vector2i(pos[&"x"], pos[&"y"])
	var bay: int = Constants.world_to_bay(world_pos)
	var rack: int = Constants.INVALID_ID
	var slot: int = Constants.INVALID_SLOT
	if bay != Constants.INVALID_BAY:
		var q: SlotQuery = Constants.bay_local_to_slot(bay, world_pos)
		if q.zone == &"slot":
			rack = q.get_rack()
			slot = q.get_slot()
			nav_builder.remove_rack_slot(rack, slot)
		elif q.zone != &"other":
			rack = q.rack
	Events.object_removed.emit(entity_id, rack, slot)
	db.remove_spatial(entity_id)
	db.destroy_entity(entity_id)


func _spawn_starter_entities() -> void:
	# Scenario-driven world init — populates the Phase 0 starter bay
	# (HUM device, TUNA dispenser + button, ARM) from the tcp_base:starter
	# scenario JSONC. Guarded against re-entry by _starter_applied so a
	# second _ready (e.g. test re-use) won't double-spawn.
	if not _starter_applied:
		world_init.apply(settings.starter_scenario_id)
		# Deferred so GameClient has wired its Events.object_placed listener
		# before our seed objects fire the signal. Without the defer, sprites
		# for the seed stacks never spawn (signal fires too early).
		call_deferred(&"_seed_starter_box_stacks")
		_starter_applied = true
		# TODO Phase 2: emit a robot_log signal once Events grows one.

	# Starter-entity spawn — driven by each loaded species recipe's `starters` array.
	var floor_rect: Rect2i = Constants.floor_rect_world(0)
	var floor_y: int = floor_rect.position.y + floor_rect.size.y / 2
	for species_id: StringName in entity_defs.get_all_entities():
		var def: Dictionary = entity_defs.get_definition(species_id)
		if not def.has("starters"):
			continue
		var starters: Array = def["starters"]
		for entry: Dictionary in starters:
			var rack: int = int(entry.get("rack", 0))
			var rack_col: Rect2i = Constants.rack_column_rect_world(0, rack)
			var starter_x: int = rack_col.position.x + rack_col.size.x / 2
			var overrides: Dictionary = {
				&"name": StringName(entry.get("name", "")),
				&"position": {
					&"x": starter_x,
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
	var floor_rect: Rect2i = Constants.floor_rect_world(0)
	var floor_y: int = floor_rect.position.y + floor_rect.size.y / 2
	for rack_idx: int in Constants.RACK_COUNT:
		var rack_entity: int = db.create_entity()
		var rack_col: Rect2i = Constants.rack_column_rect_world(0, rack_idx)
		var x: int = rack_col.position.x + rack_col.size.x / 2
		var y: int = floor_y
		db.set_component(rack_entity, &"position", {&"x": x, &"y": y})
		db.set_component(rack_entity, &"advertisements", {&"list": [
			{
				&"desire_type": &"curiosity",
				&"strength": 500,
				&"radius_px": 64,
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


# Engine-side completion of the starter scenario. The JSONC scenario format
# can only spawn entries that resolve to a registered EntityDefRegistry
# recipe; servers and cardboard_boxes are placed via game_server.place_object
# (no recipe yet). Until that gap closes, this function:
#   1. places one server + cardboard_box stack in racks 1 and 3 — the
#      "two server+box stacks" baseline the cat-jumps-into-box spec needs
#   2. drains every HUM to ~5% so the purr->charge climb is observable on
#      first boot rather than masked by 100% steady state
#   3. force-satisfies one purr-capable entity so the bridge produces
#      non-zero purr.intensity from tick 0 (without it, scatter has to warm
#      the cell from desires=200 default, which takes a couple of seconds
#      and obscures the demo)
func _seed_starter_box_stacks() -> void:
	# Server at slot 0 (1U), box at slot 2 (2U-tall sprite extends down through
	# slot 1, bottom edge meeting the server's top edge cleanly). Box at slot 1
	# would overlap the server vertically because the rack-mounted box texture
	# is anchored at slot.top and renders downward.
	var rack1_box_id: int = Constants.INVALID_ID
	for rack: int in [1, 3]:
		var server_slot_rect: Rect2i = Constants.slot_rect_world(0, rack, 0)
		var server_x: int = (
			server_slot_rect.position.x + server_slot_rect.size.x / 2
		)
		var server_y: int = (
			server_slot_rect.position.y + server_slot_rect.size.y / 2
		)
		place_object(&"server_1u", server_x, server_y)
		var box_slot_rect: Rect2i = Constants.slot_rect_world(0, rack, 2)
		var box_x: int = box_slot_rect.position.x + box_slot_rect.size.x / 2
		var box_y: int = box_slot_rect.position.y + box_slot_rect.size.y / 2
		var box_id: int = place_object(&"cardboard_box", box_x, box_y)
		if rack == 1:
			rack1_box_id = box_id
	for hum_id: int in db.get_entities_with(&"hum"):
		var capacity: int = db.get_field(hum_id, &"hum", &"capacity")
		db.set_field(hum_id, &"hum", &"reserve", capacity / 20)
	# Pick the first purr-capable entity, force-content it, and tuck it into
	# the rack-1 box. Two effects: bridge writes non-zero intensity from
	# tick 0 (HUM has something to charge against) and the demo literally
	# shows "a cat in a box."
	var purrers: Array[int] = db.get_entities_with(&"purr_config")
	if not purrers.is_empty() and rack1_box_id != Constants.INVALID_ID:
		var demo_cat: int = purrers[0]
		db.set_component(
			demo_cat, &"debug_force_satisfied", {&"active": 1},
		)
		# Position cat at the box's anchor slot (slot 2). The cat sprite is
		# 40 px tall with offset_y = -12, so its feet land ~8 px below the
		# anchor. With the cat anchored at slot 2, the feet sit inside the
		# box's bottom edge (slot_2_top + 16) and the head/ears poke up out
		# of the box opening. Anchoring at slot 1 (the seed's previous spot)
		# pushed the feet 4 px below the box bottom — visually "one slot
		# under the box," which is the bug the screenshot caught on
		# 2026-04-29.
		var box_slot_rect: Rect2i = Constants.slot_rect_world(0, 1, 2)
		var cat_x: int = box_slot_rect.position.x + box_slot_rect.size.x / 2
		var cat_y: int = box_slot_rect.position.y + box_slot_rect.size.y / 2
		db.set_component(demo_cat, &"position", {&"x": cat_x, &"y": cat_y})
		db.update_spatial(demo_cat, cat_x, cat_y)
		settled_lifecycle.enter(demo_cat, rack1_box_id)
		# Park the cat in IDLE so the move loop doesn't try to walk it
		# anywhere — settled_in is a "stay put" marker for now.
		db.set_component(demo_cat, &"ai_state", {
			&"state": &"SLEEPING",
			&"meta_state": &"AMBIENT",
			&"commitment_score": 0,
		})
		db.set_component(demo_cat, &"target", {
			&"x": Constants.INVALID_ID,
			&"y": Constants.INVALID_ID,
			&"entity_id": Constants.INVALID_ID,
		})


func _find_dispenser_in_rack(
		world_x: int, world_y: int,
) -> int:
	var btn_pos := Vector2i(world_x, world_y)
	var btn_bay: int = Constants.world_to_bay(btn_pos)
	if btn_bay == Constants.INVALID_BAY:
		return Constants.INVALID_ID
	var btn_q: SlotQuery = Constants.bay_local_to_slot(btn_bay, btn_pos)
	if btn_q.zone == &"other":
		return Constants.INVALID_ID
	var rack: int = btn_q.rack
	var dispensers: Array[int] = db.get_entities_with(
		&"tuna_dispenser",
	)
	for disp_id: int in dispensers:
		var dpos: Dictionary = db.get_component(
			disp_id, &"position",
		)
		var dp := Vector2i(dpos[&"x"], dpos[&"y"])
		var d_bay: int = Constants.world_to_bay(dp)
		if d_bay == Constants.INVALID_BAY:
			continue
		var dq: SlotQuery = Constants.bay_local_to_slot(d_bay, dp)
		if dq.zone == &"other":
			continue
		if dq.rack == rack:
			return disp_id
	return Constants.INVALID_ID
