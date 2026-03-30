extends Node

var db: GameStateDB
var heat_grid: HeatGrid
var desire_resolver: DesireResolver


func _ready() -> void:
	db = GameStateDB.new()
	heat_grid = HeatGrid.new(db)
	desire_resolver = DesireResolver.new(db)
	_spawn_starter_entities()


func _physics_process(_delta: float) -> void:
	db.advance_tick()
	heat_grid.propagate()
	_scatter_desires()
	desire_resolver.evaluate_budget()
	db.flush_notifications()


func _scatter_desires() -> void:
	var animals: Array[int] = db.get_entities_with(&"desires")
	for entity_id in animals:
		if not db.has_component(entity_id, &"position"):
			continue
		var pos: Dictionary = db.get_component(entity_id, &"position")
		var rack: int = pos[&"x"] / Constants.RACK_WIDTH_PU
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
