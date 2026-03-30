extends Node

var db: GameStateDB
var heat_grid: HeatGrid
var desire_resolver: DesireResolver


func _ready() -> void:
	db = GameStateDB.new()
	heat_grid = HeatGrid.new(db)
	desire_resolver = DesireResolver.new(db)
	_spawn_starter_entities()


const ANIMAL_SPEED_PU: int = 200  # position units per tick (20 pixels/sec at 10Hz)

var _state_timers: Dictionary = {}  # entity_id -> float (seconds in current state)
var _min_durations: Dictionary = {
	&"IDLE": 3.0,
	&"GROOMING": 10.0,
	&"LOAFING": 15.0,
	&"SLEEPING": 30.0,
	&"SNIFFING": 10.0,
	&"SPEED_BUMP": 15.0,
}


func _physics_process(_delta: float) -> void:
	db.advance_tick()
	heat_grid.propagate()
	_scatter_desires()
	_decay_commitment()
	_mark_animals_dirty()
	desire_resolver.evaluate_budget()
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
	db.clamp_all(&"desires", &"warmth", 0, 1000)
	db.clamp_all(&"desires", &"comfort", 0, 1000)
	db.clamp_all(&"desires", &"curiosity", 0, 1000)


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

		# Transition SEEKING -> MOVING_TO on first movement tick
		if state == &"SEEKING":
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
			# Transition to IDLE (simplified for now)
			db.set_component(entity_id, &"ai_state", {
				&"state": &"IDLE",
				&"meta_state": &"AMBIENT",
				&"commitment_score": ai[&"commitment_score"],
			})
			db.set_component(entity_id, &"target", {
				&"x": Constants.INVALID_ID,
				&"y": Constants.INVALID_ID,
				&"entity_id": Constants.INVALID_ID,
			})
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
		var min_dur: float = _min_durations.get(current_state, 3.0)
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
	db.update_spatial(server, server_x, server_y)

	# Pre-placed cardboard box on the floor near rack 0
	var box: int = db.create_entity()
	@warning_ignore("integer_division")
	var box_x: int = 0 * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2
	var box_y: int = Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 4
	db.set_component(box, &"position", {&"x": box_x, &"y": box_y})
	db.set_component(box, &"advertisements", {&"list": [
		{&"desire_type": &"comfort", &"strength": 700, &"radius_ru": 4, &"max_occupants": 1}
	]})
	db.update_spatial(box, box_x, box_y)

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
	db.update_spatial(cat, cat_x, cat_y)
