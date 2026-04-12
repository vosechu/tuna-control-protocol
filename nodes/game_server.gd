extends Node

const ANIMAL_SPEED_PU: int = 200  # position units per tick (20 pixels/sec at 10Hz)

var db: GameStateDB
var heat_grid: HeatGrid
var desire_resolver: DesireResolver
var desire_scatter: DesireScatter
var object_state_manager: ObjectStateManager
var nav_builder: NavGraphBuilder
var hum_system: HumSystem
var contentment: Contentment
var _mod_loader := ModLoader.new()
var _entity_defs: EntityDefRegistry
var _verb_resolver := VerbResolver.new()
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
	var mod_result: Dictionary = _mod_loader.load_all(
		"res://mods/",
	)
	_entity_defs = mod_result["entity_defs"]
	heat_grid = HeatGrid.new(db)
	contentment = Contentment.new(db)
	hum_system = HumSystem.new(db, Events)
	desire_resolver = DesireResolver.new(db)
	desire_scatter = DesireScatter.new(db)
	object_state_manager = ObjectStateManager.new(db)
	nav_builder = NavGraphBuilder.new()
	_register_species_nav()
	nav_builder.build()
	_spawn_starter_entities()
	_build_nav_for_objects()


func _register_species_nav() -> void:
	for entity_id: StringName in _entity_defs.get_all_entities():
		if _entity_defs.has_traversal(entity_id):
			nav_builder.register_species(
				entity_id,
				_entity_defs.get_traversal(entity_id),
			)


func _build_nav_for_objects() -> void:
	# Register nav nodes for all pre-placed objects in rack slots
	var objects: Array[int] = db.get_entities_with(&"object_type")
	for entity_id: int in objects:
		var pos: Dictionary = db.get_component(entity_id, &"position")
		@warning_ignore("integer_division")
		var rack: int = pos[&"x"] / Constants.RACK_WIDTH_PU
		@warning_ignore("integer_division")
		var slot: int = pos[&"y"] / Constants.SLOT_HEIGHT_PU
		if slot < Constants.SLOTS_PER_RACK:
			nav_builder.add_rack_slot(rack, slot)


func _physics_process(_delta: float) -> void:
	db.advance_tick()
	heat_grid.propagate()
	_scatter_desires()
	contentment.evaluate_all()
	hum_system.tick_charge()
	hum_system.drain_idle()
	_decay_commitment()
	desire_resolver.mark_all_dirty()
	desire_resolver.evaluate_budget(_curiosity_trackers)
	_move_animals()
	_update_ambient_states()
	db.flush_notifications()


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
		@warning_ignore("integer_division")
		var rack: int = pos[&"x"] / Constants.RACK_WIDTH_PU
		@warning_ignore("integer_division")
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
		if state != &"SEEKING" and state != &"MOVING_TO" and state != &"WANDERING":
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

		# Move toward target
		var dx: int = target[&"x"] - pos[&"x"]
		var dy: int = target[&"y"] - pos[&"y"]
		var dist: int = absi(dx) + absi(dy)

		if dist <= ANIMAL_SPEED_PU:
			# Arrived
			db.set_component(entity_id, &"position", {
				&"x": target[&"x"], &"y": target[&"y"],
			})
			db.update_spatial(entity_id, target[&"x"], target[&"y"])

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
		else:
			# Move one step toward target
			var move_x: int = 0
			var move_y: int = 0
			if dx != 0:
				@warning_ignore("integer_division")
				move_x = ANIMAL_SPEED_PU * dx / dist
			if dy != 0:
				@warning_ignore("integer_division")
				move_y = ANIMAL_SPEED_PU * dy / dist
			# Ensure at least 1 unit of movement
			if move_x == 0 and dx != 0:
				move_x = 1 if dx > 0 else -1
			if move_y == 0 and dy != 0:
				move_y = 1 if dy > 0 else -1
			var new_x: int = pos[&"x"] + move_x
			var new_y: int = pos[&"y"] + move_y
			db.set_component(entity_id, &"position", {&"x": new_x, &"y": new_y})
			db.update_spatial(entity_id, new_x, new_y)


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

		if ai[&"meta_state"] != &"AMBIENT":
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

		# Pick new ambient state
		var species: Dictionary = db.get_component(
			entity_id, &"species",
		)
		var desires: Dictionary = db.get_component(
			entity_id, &"desires",
		)
		var species_id: StringName = species[&"id"]
		var is_warm: bool = desires[&"warmth"] < 400
		var has_cat_states: bool = _entity_defs != null \
			and _entity_defs.has_entity(species_id) \
			and _entity_defs.get_states(species_id).has(
				"grooming",
			)
		var new_state: StringName = _pick_ambient_state(
			has_cat_states, is_warm,
		)
		if new_state != current_state:
			db.set_component(entity_id, &"ai_state", {
				&"state": new_state,
				&"meta_state": &"AMBIENT",
				&"commitment_score": ai[&"commitment_score"],
			})
			_state_timers[entity_id] = 0.0
			_min_durations_override.erase(entity_id)


func _pick_ambient_state(
		has_cat_states: bool, is_warm: bool,
) -> StringName:
	var pool: Array[Dictionary] = []
	pool.append({&"state": &"IDLE", &"weight": 10})

	if has_cat_states:
		if is_warm:
			pool.append({&"state": &"GROOMING", &"weight": 15})
			pool.append({&"state": &"LOAFING", &"weight": 20})
			pool.append({&"state": &"SLEEPING", &"weight": 25})
		else:
			pool.append({&"state": &"GROOMING", &"weight": 5})
			pool.append({&"state": &"LOAFING", &"weight": 10})
	else:
		# Ferret ambient states
		pool.append({&"state": &"SNIFFING", &"weight": 20})
		pool.append({&"state": &"SPEED_BUMP", &"weight": 10})
		if is_warm:
			pool.append({&"state": &"SLEEPING", &"weight": 15})

	# Weighted random selection
	var total_weight: int = 0
	for entry: Dictionary in pool:
		total_weight += int(entry[&"weight"])
	var roll: int = randi_range(0, total_weight - 1)
	var cumulative: int = 0
	for entry: Dictionary in pool:
		cumulative += int(entry[&"weight"])
		if roll < cumulative:
			return entry[&"state"]
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
		&"server_2u":
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
			db.set_component(entity, &"hum_receiver", {&"radius_ru": 5})
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

	db.set_component(
		entity, &"object_type", {&"type": object_type}
	)
	db.update_spatial(entity, world_x, world_y)
	@warning_ignore("integer_division")
	var rack: int = world_x / Constants.RACK_WIDTH_PU
	@warning_ignore("integer_division")
	var slot: int = world_y / Constants.SLOT_HEIGHT_PU
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
	@warning_ignore("integer_division")
	var rack: int = pos[&"x"] / Constants.RACK_WIDTH_PU
	@warning_ignore("integer_division")
	var slot: int = pos[&"y"] / Constants.SLOT_HEIGHT_PU
	# Remove nav node if object was in a rack slot
	if slot < Constants.SLOTS_PER_RACK:
		nav_builder.remove_rack_slot(rack, slot)
	Events.object_removed.emit(entity_id, rack, slot)
	db.remove_spatial(entity_id)
	db.destroy_entity(entity_id)


func _spawn_starter_entities() -> void:
	# Pre-placed server at rack 1, slot 8 (bottom of rack, right above floor, near Mochi)
	var server: int = db.create_entity()
	var server_x: int = 1 * Constants.RACK_WIDTH_PU
	var server_y: int = 8 * Constants.SLOT_HEIGHT_PU
	db.set_component(server, &"position", {&"x": server_x, &"y": server_y})
	db.set_component(server, &"heat_source", {&"value": 1000, &"radius_ru": 5})
	db.set_component(server, &"advertisements", {&"list": [
		{&"desire_type": &"warmth", &"strength": 800, &"radius_ru": 8, &"max_occupants": 1}
	]})
	db.set_component(server, &"hum_receiver", {&"radius_ru": 5})
	db.set_component(
		server, &"object_type", {&"type": &"server_2u"}
	)
	db.update_spatial(server, server_x, server_y)

	# Pre-placed cardboard box on the floor near rack 0
	var box: int = db.create_entity()
	@warning_ignore("integer_division")
	var box_x: int = 0 * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2
	@warning_ignore("integer_division")
	var box_y: int = (
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 4
	)
	db.set_component(box, &"position", {&"x": box_x, &"y": box_y})
	db.set_component(box, &"advertisements", {&"list": [
		{&"desire_type": &"comfort", &"strength": 700, &"radius_ru": 4, &"max_occupants": 1}
	]})
	db.set_component(
		box, &"object_type", {&"type": &"cardboard_box"}
	)
	db.update_spatial(box, box_x, box_y)

	# Clothes pile on the floor near rack 2
	var pile: int = db.create_entity()
	@warning_ignore("integer_division")
	var pile_x: int = 2 * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2
	@warning_ignore("integer_division")
	var pile_y: int = (
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 3
	)
	db.set_component(pile, &"position", {&"x": pile_x, &"y": pile_y})
	db.set_component(pile, &"advertisements", {&"list": [
		{&"desire_type": &"comfort", &"strength": 800, &"radius_ru": 4, &"max_occupants": 3},
		{&"desire_type": &"warmth", &"strength": 500, &"radius_ru": 3},
		{
			&"desire_type": &"curiosity", &"strength": 400, &"radius_ru": 4,
			&"novelty_duration": 300, &"novelty_cooldown": 200,
		},
	]})
	db.set_component(
		pile, &"object_type", {&"type": &"clothes_pile"}
	)
	db.update_spatial(pile, pile_x, pile_y)

	# Spawn cats from mod definitions
	if _entity_defs.has_entity(&"tcp_cats:cat"):
		@warning_ignore("integer_division")
		var floor_y: int = (
			Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU
			+ Constants.FLOOR_HEIGHT_PU / 2
		)
		var cat_spawns: Array[Dictionary] = [
			{
				&"name": &"Mochi",
				&"position": {
					&"x": Constants.RACK_WIDTH_PU / 2,
					&"y": floor_y,
				},
				&"desires": {&"hunger": 900, &"attention": 600},
			},
			{
				&"name": &"Biscuit",
				&"position": {
					&"x": Constants.RACK_WIDTH_PU
						+ Constants.RACK_WIDTH_PU / 4,
					&"y": floor_y,
				},
				&"desires": {&"hunger": 900, &"attention": 600},
			},
			{
				&"name": &"Noodle",
				&"position": {
					&"x": 2 * Constants.RACK_WIDTH_PU
						+ Constants.RACK_WIDTH_PU / 2,
					&"y": floor_y,
				},
				&"desires": {&"hunger": 900, &"attention": 600},
			},
		]
		for overrides: Dictionary in cat_spawns:
			_entity_defs.spawn(
				&"tcp_cats:cat", db, overrides,
			)

	# Spawn ferrets from mod definitions
	if _entity_defs.has_entity(&"tcp_ferrets:ferret"):
		@warning_ignore("integer_division")
		var floor_y: int = (
			Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU
			+ Constants.FLOOR_HEIGHT_PU / 2
		)
		var ferret_spawns: Array[Dictionary] = [
			{
				&"name": &"Slinky",
				&"position": {
					&"x": Constants.RACK_WIDTH_PU
						+ Constants.RACK_WIDTH_PU / 2,
					&"y": floor_y,
				},
			},
			{
				&"name": &"Bandit",
				&"position": {
					&"x": 2 * Constants.RACK_WIDTH_PU
						+ Constants.RACK_WIDTH_PU / 4,
					&"y": floor_y,
				},
			},
		]
		for overrides: Dictionary in ferret_spawns:
			var id: int = _entity_defs.spawn(
				&"tcp_ferrets:ferret", db, overrides,
			)
			var desires: Dictionary = _entity_defs.get_desires(
				&"tcp_ferrets:ferret",
			)
			if desires.has("curiosity"):
				_curiosity_trackers[id] = \
					CuriosityTracker.new()

	_spawn_rack_entities()


func _spawn_rack_entities() -> void:
	for rack_idx: int in Constants.RACK_COUNT:
		var rack_entity: int = db.create_entity()
		@warning_ignore("integer_division")
		var x: int = rack_idx * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2
		var y: int = Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 2
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
