extends Node

const ANIMAL_SPEED_PU: int = 200  # position units per tick (20 pixels/sec at 10Hz)

var db: GameStateDB
var heat_grid: HeatGrid
var desire_resolver: DesireResolver
var nav_builder: NavGraphBuilder
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
	heat_grid = HeatGrid.new(db)
	desire_resolver = DesireResolver.new(db)
	nav_builder = NavGraphBuilder.new()
	_spawn_starter_entities()
	_build_nav_for_objects()


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
	_decay_commitment()
	_mark_animals_dirty()
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
		# Warmth desire: 0 = warm/satisfied, 1000 = cold/desperate
		# Temperature: 0 = cold, 1000 = hot
		# So warmth desire = 1000 - temperature
		db.set_field(entity_id, &"desires", &"warmth", 1000 - temp)
	# Comfort and curiosity decay
	db.add_all(&"desires", &"comfort", 5)
	db.add_all(&"desires", &"curiosity", 3)
	# Comfort satisfaction: animals near comfort-advertising objects get comfort reduced
	_scatter_comfort()
	db.clamp_all(&"desires", &"warmth", 0, 1000)
	db.clamp_all(&"desires", &"comfort", 0, 1000)
	db.clamp_all(&"desires", &"curiosity", 0, 1000)


func _scatter_comfort() -> void:
	var animals: Array[int] = db.get_entities_with(&"desires")
	for entity_id: int in animals:
		if not db.has_component(entity_id, &"position"):
			continue
		if not db.has_component(entity_id, &"species"):
			continue
		var pos: Dictionary = db.get_component(entity_id, &"position")
		# Check nearby objects for comfort advertisements
		var nearby: Array[int] = db.query_radius(pos[&"x"], pos[&"y"], Constants.ru_to_pu(4))
		var best_comfort: int = 0
		for other_id: int in nearby:
			if other_id == entity_id:
				continue
			if not db.has_component(other_id, &"advertisements"):
				continue
			var ads: Dictionary = db.get_component(other_id, &"advertisements")
			for ad: Dictionary in ads[&"list"]:
				if ad[&"desire_type"] == &"comfort":
					var other_pos: Dictionary = db.get_component(other_id, &"position")
					var dist: int = absi(pos[&"x"] - other_pos[&"x"]) + absi(pos[&"y"] - other_pos[&"y"])
					var radius_pu: int = Constants.ru_to_pu(ad[&"radius_ru"])
					if dist <= radius_pu and ad[&"strength"] > best_comfort:
						best_comfort = ad[&"strength"]
		# If near a comfort source, reduce the comfort desire (satisfy it)
		if best_comfort > 0:
			var current: int = db.get_field(entity_id, &"desires", &"comfort")
			@warning_ignore("integer_division")
			var satisfaction: int = best_comfort * (1000 - current) / 1000
			var new_comfort: int = maxi(0, current - satisfaction / 10)
			db.set_field(entity_id, &"desires", &"comfort", new_comfort)


func _mark_animals_dirty() -> void:
	var animals: Array[int] = db.get_entities_with(&"desires")
	for entity_id: int in animals:
		if not db.has_component(entity_id, &"species"):
			continue
		desire_resolver.mark_dirty(entity_id)


func _move_animals() -> void:
	var animals: Array[int] = db.get_entities_with(&"ai_state")
	for entity_id: int in animals:
		var ai: Dictionary = db.get_component(entity_id, &"ai_state")
		var state: StringName = ai[&"state"]
		if state != &"SEEKING" and state != &"MOVING_TO":
			continue

		var pos: Dictionary = db.get_component(entity_id, &"position")
		var target: Dictionary = db.get_component(entity_id, &"target")
		if target[&"entity_id"] == Constants.INVALID_ID:
			continue

		# Transition SEEKING -> MOVING_TO on first movement tick, with nav graph check
		if state == &"SEEKING":
			var species: Dictionary = db.get_component(entity_id, &"species")
			var from_pos: Vector2 = Vector2(float(pos[&"x"]), float(pos[&"y"]))
			var to_pos: Vector2 = Vector2(float(target[&"x"]), float(target[&"y"]))
			# If the species cannot navigate to the target, cancel seeking
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
				&"commitment_score": ai[&"commitment_score"],
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
		if ai[&"meta_state"] != &"AMBIENT":
			continue

		# Update timer
		if not _state_timers.has(entity_id):
			_state_timers[entity_id] = 0.0
		_state_timers[entity_id] += tick_delta

		# Check if min duration elapsed
		var current_state: StringName = ai[&"state"]
		var min_dur: float = _min_durations_override.get(entity_id, _min_durations.get(current_state, 3.0))
		if _state_timers[entity_id] < min_dur:
			continue

		# Pick new ambient state
		var species: Dictionary = db.get_component(entity_id, &"species")
		var desires: Dictionary = db.get_component(entity_id, &"desires")
		var is_cat: bool = String(species[&"id"]).contains("cat")
		# warmth desire: 0 = warm/satisfied, 1000 = cold/desperate
		var is_warm: bool = desires[&"warmth"] < 400



		var new_state: StringName = _pick_ambient_state(is_cat, is_warm)
		if new_state != current_state:
			db.set_component(entity_id, &"ai_state", {
				&"state": new_state,
				&"meta_state": &"AMBIENT",
				&"commitment_score": ai[&"commitment_score"],
			})
			_state_timers[entity_id] = 0.0
			_min_durations_override.erase(entity_id)


func _pick_ambient_state(is_cat: bool, is_warm: bool) -> StringName:
	# Weighted pool based on species and warmth context
	var pool: Array[Dictionary] = []
	# IDLE is always available
	pool.append({&"state": &"IDLE", &"weight": 10})

	if is_cat:
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
		&"cardboard_box":
			db.set_component(entity, &"advertisements", {
				&"list": [{
					&"desire_type": &"comfort",
					&"strength": 700,
					&"radius_ru": 4,
					&"max_occupants": 1,
				}],
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
	# Pre-placed server at rack 1, slot 40 (bottom of rack, right above floor, near Mochi)
	var server: int = db.create_entity()
	var server_x: int = 1 * Constants.RACK_WIDTH_PU
	var server_y: int = 40 * Constants.SLOT_HEIGHT_PU
	db.set_component(server, &"position", {&"x": server_x, &"y": server_y})
	db.set_component(server, &"heat_source", {&"value": 1000, &"radius_ru": 5})
	db.set_component(server, &"advertisements", {&"list": [
		{&"desire_type": &"warmth", &"strength": 800, &"radius_ru": 8, &"max_occupants": 1}
	]})
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
		{&"desire_type": &"comfort", &"strength": 800, &"radius_ru": 4, &"max_occupants": 3}
	]})
	db.set_component(
		pile, &"object_type", {&"type": &"clothes_pile"}
	)
	db.update_spatial(pile, pile_x, pile_y)

	# First cat: Mochi — on the floor near rack 0
	var cat: int = db.create_entity()
	db.set_component(cat, &"species", {
		&"id": &"tcp_base:cat",
		&"variant": &"cat01",
		&"name": &"Mochi",
	})
	@warning_ignore("integer_division")
	var cat_x: int = (
		0 * Constants.RACK_WIDTH_PU
		+ Constants.RACK_WIDTH_PU / 2
	)
	@warning_ignore("integer_division")
	var cat_y: int = (
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU
		+ Constants.FLOOR_HEIGHT_PU / 2
	)
	db.set_component(cat, &"position", {
		&"x": cat_x, &"y": cat_y,
	})
	db.set_component(cat, &"desires", {
		&"warmth": 200,
		&"comfort": 200,
		&"curiosity": 0,
	})
	db.set_component(cat, &"personality", {
		&"warmth_weight": 800,
		&"comfort_weight": 600,
		&"curiosity_weight": 100,
	})
	db.set_component(cat, &"ai_state", {
		&"state": &"IDLE",
		&"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	db.set_component(cat, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.set_component(cat, &"advertisements", {&"list": [
		{
			&"desire_type": &"warmth",
			&"strength": 300,
			&"radius_ru": 2,
		},
		{
			&"desire_type": &"curiosity",
			&"strength": 400,
			&"radius_ru": 3,
			&"novelty_duration": 150,
			&"novelty_cooldown": 50,
		},
	]})
	db.update_spatial(cat, cat_x, cat_y)

	# Second cat: Biscuit — comfort-focused, on the floor near rack 1
	var cat2: int = db.create_entity()
	db.set_component(cat2, &"species", {
		&"id": &"tcp_base:cat", &"variant": &"cat02", &"name": &"Biscuit",
	})
	@warning_ignore("integer_division")
	var cat2_x: int = 1 * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 4
	@warning_ignore("integer_division")
	var cat2_y: int = (
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 2
	)
	db.set_component(cat2, &"position", {&"x": cat2_x, &"y": cat2_y})
	db.set_component(cat2, &"desires", {&"warmth": 200, &"comfort": 200, &"curiosity": 0})
	db.set_component(cat2, &"personality", {
		&"warmth_weight": 500, &"comfort_weight": 900, &"curiosity_weight": 100,
	})
	db.set_component(cat2, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	db.set_component(cat2, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.set_component(cat2, &"advertisements", {&"list": [
		{
			&"desire_type": &"warmth",
			&"strength": 300,
			&"radius_ru": 2,
		},
		{
			&"desire_type": &"curiosity",
			&"strength": 400,
			&"radius_ru": 3,
			&"novelty_duration": 150,
			&"novelty_cooldown": 50,
		},
	]})
	db.update_spatial(cat2, cat2_x, cat2_y)

	# Third cat: Noodle — balanced, on the floor near rack 2
	var cat3: int = db.create_entity()
	db.set_component(cat3, &"species", {
		&"id": &"tcp_base:cat", &"variant": &"cat03", &"name": &"Noodle",
	})
	@warning_ignore("integer_division")
	var cat3_x: int = 2 * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2
	@warning_ignore("integer_division")
	var cat3_y: int = (
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 2
	)
	db.set_component(cat3, &"position", {&"x": cat3_x, &"y": cat3_y})
	db.set_component(cat3, &"desires", {&"warmth": 200, &"comfort": 200, &"curiosity": 0})
	db.set_component(cat3, &"personality", {
		&"warmth_weight": 700, &"comfort_weight": 700, &"curiosity_weight": 200,
	})
	db.set_component(cat3, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	db.set_component(cat3, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.set_component(cat3, &"advertisements", {&"list": [
		{
			&"desire_type": &"warmth",
			&"strength": 300,
			&"radius_ru": 2,
		},
		{
			&"desire_type": &"curiosity",
			&"strength": 400,
			&"radius_ru": 3,
			&"novelty_duration": 150,
			&"novelty_cooldown": 50,
		},
	]})
	db.update_spatial(cat3, cat3_x, cat3_y)

	# First ferret: Slinky — explorer, on the floor near rack 1
	var ferret1: int = db.create_entity()
	db.set_component(ferret1, &"species", {
		&"id": &"tcp_base:ferret", &"variant": &"lilotter", &"name": &"Slinky",
	})
	@warning_ignore("integer_division")
	var f1_x: int = 1 * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2
	@warning_ignore("integer_division")
	var f1_y: int = (
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 2
	)
	db.set_component(ferret1, &"position", {&"x": f1_x, &"y": f1_y})
	db.set_component(ferret1, &"desires", {&"warmth": 200, &"comfort": 200, &"curiosity": 0})
	db.set_component(ferret1, &"personality", {
		&"warmth_weight": 300, &"comfort_weight": 600, &"curiosity_weight": 900,
	})
	db.set_component(ferret1, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	db.set_component(ferret1, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(ferret1, f1_x, f1_y)
	_curiosity_trackers[ferret1] = CuriosityTracker.new()

	# Second ferret: Bandit — comfort hoarder, on the floor near rack 2
	var ferret2: int = db.create_entity()
	db.set_component(ferret2, &"species", {
		&"id": &"tcp_base:ferret", &"variant": &"lilotter", &"name": &"Bandit",
	})
	@warning_ignore("integer_division")
	var f2_x: int = 2 * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 4
	@warning_ignore("integer_division")
	var f2_y: int = (
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 2
	)
	db.set_component(ferret2, &"position", {&"x": f2_x, &"y": f2_y})
	db.set_component(ferret2, &"desires", {&"warmth": 200, &"comfort": 200, &"curiosity": 0})
	db.set_component(ferret2, &"personality", {
		&"warmth_weight": 400, &"comfort_weight": 800, &"curiosity_weight": 800,
	})
	db.set_component(ferret2, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	db.set_component(ferret2, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(ferret2, f2_x, f2_y)
	_curiosity_trackers[ferret2] = CuriosityTracker.new()

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
				&"strength": 300,
				&"radius_ru": 8,
				&"novelty_duration": 30,
				&"novelty_cooldown": 100,
			},
		]})
		db.update_spatial(rack_entity, x, y)
