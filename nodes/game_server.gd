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


func _physics_process(_delta: float) -> void:
	db.advance_tick()
	heat_grid.propagate()
	_scatter_desires()
	_mark_animals_dirty()
	desire_resolver.evaluate_budget()
	_move_animals()
	db.flush_notifications()


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


func _spawn_starter_entities() -> void:
	# Pre-placed server at rack 2, slots 20-21
	var server: int = db.create_entity()
	db.set_component(server, &"position", {
		&"x": 2 * Constants.RACK_WIDTH_PU,
		&"y": 20 * Constants.SLOT_HEIGHT_PU,
	})
	db.set_component(server, &"heat_source", {&"value": 800, &"radius_ru": 3})
	db.set_component(server, &"advertisements", {&"list": [
		{&"desire_type": &"warmth", &"strength": 800, &"radius_ru": 3, &"max_occupants": 1}
	]})
	db.update_spatial(server, 2 * Constants.RACK_WIDTH_PU, 20 * Constants.SLOT_HEIGHT_PU)

	# Pre-placed cardboard box at rack 1, slots 8-10
	var box: int = db.create_entity()
	db.set_component(box, &"position", {
		&"x": 1 * Constants.RACK_WIDTH_PU,
		&"y": 8 * Constants.SLOT_HEIGHT_PU,
	})
	db.set_component(box, &"advertisements", {&"list": [
		{&"desire_type": &"comfort", &"strength": 700, &"radius_ru": 1, &"max_occupants": 1}
	]})
	db.update_spatial(box, 1 * Constants.RACK_WIDTH_PU, 8 * Constants.SLOT_HEIGHT_PU)

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
