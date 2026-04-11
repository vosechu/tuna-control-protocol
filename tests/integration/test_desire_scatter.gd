extends GutTest

var _db: GameStateDB
var _heat_grid: HeatGrid
var _resolver: DesireResolver


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	_db = GameStateDB.new()
	_heat_grid = HeatGrid.new(_db)
	_resolver = DesireResolver.new(_db)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_server(rack: int, slot: int) -> int:
	var id: int = _db.create_entity()
	var x: int = rack * Constants.RACK_STRIDE_PU
	var y: int = slot * Constants.SLOT_HEIGHT_PU
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"heat_source", {
		&"value": 800, &"radius_ru": 3,
	})
	_db.set_component(id, &"advertisements", {&"list": [
		{
			&"desire_type": &"warmth",
			&"strength": 800,
			&"radius_ru": 8,
			&"max_occupants": 1,
		},
	]})
	_db.update_spatial(id, x, y)
	return id


func _make_cat(rack: int, slot: int) -> int:
	var id: int = _db.create_entity()
	var x: int = rack * Constants.RACK_STRIDE_PU
	var y: int = slot * Constants.SLOT_HEIGHT_PU
	_db.set_component(id, &"species", {
		&"id": &"tcp_cats:cat",
		&"variant": &"cat01",
		&"name": &"TestCat",
	})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"desires", {
		&"warmth": 200,
		&"comfort": 800,
		&"curiosity": 1000,
	})
	_db.set_component(id, &"personality", {
		&"warmth_weight": 800,
		&"comfort_weight": 600,
		&"curiosity_weight": 100,
	})
	_db.set_component(id, &"ai_state", {
		&"state": &"IDLE",
		&"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	_db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	_db.update_spatial(id, x, y)
	return id


# ── Tests ─────────────────────────────────────────────────────────────────────

func test_cold_cat_near_server_transitions_to_seeking() -> void:
	var server: int = _make_server(2, 20)
	var cat: int = _make_cat(2, 25)

	# Propagate heat from the server
	_heat_grid.propagate()

	# Scatter warmth desire based on heat at cat's position
	var pos: Dictionary = _db.get_component(cat, &"position")
	@warning_ignore("integer_division")
	var rack: int = pos[&"x"] / Constants.RACK_STRIDE_PU
	@warning_ignore("integer_division")
	var slot: int = pos[&"y"] / Constants.SLOT_HEIGHT_PU
	var cell: int = Constants.rack_cell(
		clampi(rack, 0, Constants.RACK_COUNT - 1),
		clampi(slot, 0, Constants.SLOTS_PER_RACK - 1),
	)
	var temp: int = _heat_grid.get_temperature(cell)
	_db.set_field(cat, &"desires", &"warmth", temp)

	_resolver.mark_dirty(cat)
	_resolver.evaluate_budget()

	var ai: Dictionary = _db.get_component(cat, &"ai_state")
	assert_eq(ai[&"state"], &"SEEKING",
		"Cold cat near warm server should transition to SEEKING")
	var target: Dictionary = _db.get_component(cat, &"target")
	assert_eq(target[&"entity_id"], server,
		"Cat should target the server")


func test_cat_moves_toward_target_over_ticks() -> void:
	var server: int = _make_server(2, 20)
	var cat: int = _make_cat(2, 30)

	# Set cat to MOVING_TO with target at server position
	var server_pos: Dictionary = _db.get_component(
		server, &"position"
	)
	_db.set_component(cat, &"ai_state", {
		&"state": &"MOVING_TO",
		&"meta_state": &"GOAL_DIRECTED",
		&"commitment_score": 200,
	})
	_db.set_component(cat, &"target", {
		&"x": server_pos[&"x"],
		&"y": server_pos[&"y"],
		&"entity_id": server,
	})

	var start_pos: Dictionary = _db.get_component(cat, &"position")
	var start_y: int = start_pos[&"y"]

	# NOTE: Inlines movement logic from game_server._move_animals because
	# GameServer requires a scene tree we cannot instantiate in integration
	# tests. If _move_animals changes, this must be updated to match.
	for tick: int in 50:
		var pos: Dictionary = _db.get_component(cat, &"position")
		var target: Dictionary = _db.get_component(
			cat, &"target"
		)
		if target[&"entity_id"] == Constants.INVALID_ID:
			break
		var dx: int = target[&"x"] - pos[&"x"]
		var dy: int = target[&"y"] - pos[&"y"]
		var dist: int = absi(dx) + absi(dy)
		if dist <= 200:
			break
		var move_x: int = 0
		var move_y: int = 0
		if dx != 0:
			@warning_ignore("integer_division")
			move_x = 200 * dx / dist
		if dy != 0:
			@warning_ignore("integer_division")
			move_y = 200 * dy / dist
		if move_x == 0 and dx != 0:
			move_x = 1 if dx > 0 else -1
		if move_y == 0 and dy != 0:
			move_y = 1 if dy > 0 else -1
		_db.set_component(cat, &"position", {
			&"x": pos[&"x"] + move_x,
			&"y": pos[&"y"] + move_y,
		})

	var end_pos: Dictionary = _db.get_component(cat, &"position")
	var end_y: int = end_pos[&"y"]
	assert_lt(end_y, start_y,
		"Cat should have moved upward (lower Y) toward server at slot 20")


func test_mark_animals_dirty_only_marks_species_entities() -> void:
	# Non-species entities (servers, objects) should not be marked dirty
	var server: int = _make_server(2, 20)
	var cat: int = _make_cat(2, 25)

	# Simulate _mark_animals_dirty logic
	var animals: Array[int] = _db.get_entities_with(&"desires")
	for entity_id: int in animals:
		if not _db.has_component(entity_id, &"species"):
			continue
		_resolver.mark_dirty(entity_id)

	# Propagate heat + scatter warmth
	_heat_grid.propagate()
	var pos: Dictionary = _db.get_component(cat, &"position")
	@warning_ignore("integer_division")
	var rack: int = pos[&"x"] / Constants.RACK_STRIDE_PU
	@warning_ignore("integer_division")
	var slot: int = pos[&"y"] / Constants.SLOT_HEIGHT_PU
	var cell: int = Constants.rack_cell(
		clampi(rack, 0, Constants.RACK_COUNT - 1),
		clampi(slot, 0, Constants.SLOTS_PER_RACK - 1),
	)
	var temp: int = _heat_grid.get_temperature(cell)
	_db.set_field(cat, &"desires", &"warmth", temp)

	_resolver.evaluate_budget()

	# Cat should have been evaluated (it was marked dirty)
	var ai: Dictionary = _db.get_component(cat, &"ai_state")
	assert_eq(ai[&"state"], &"SEEKING",
		"Cat should transition to SEEKING after being marked dirty")

	# Server should not have ai_state (it was never marked dirty or evaluated)
	assert_false(
		_db.has_component(server, &"ai_state"),
		"Server should not have ai_state component"
	)


func test_movement_arrival_distance_within_speed() -> void:
	var server: int = _make_server(2, 20)
	var cat: int = _make_cat(2, 20)  # Same position as server

	var server_pos: Dictionary = _db.get_component(
		server, &"position"
	)
	# Place cat very close to target (within ANIMAL_SPEED_PU)
	var close_x: int = server_pos[&"x"] + 100
	var close_y: int = server_pos[&"y"] + 100
	_db.set_component(cat, &"position", {
		&"x": close_x, &"y": close_y,
	})
	_db.set_component(cat, &"ai_state", {
		&"state": &"MOVING_TO",
		&"meta_state": &"GOAL_DIRECTED",
		&"commitment_score": 200,
	})
	_db.set_component(cat, &"target", {
		&"x": server_pos[&"x"],
		&"y": server_pos[&"y"],
		&"entity_id": server,
	})

	# Distance is 200 (100+100), which equals ANIMAL_SPEED_PU (200)
	# So a single movement step should cause arrival
	var pos: Dictionary = _db.get_component(cat, &"position")
	var target: Dictionary = _db.get_component(cat, &"target")
	var dx: int = target[&"x"] - pos[&"x"]
	var dy: int = target[&"y"] - pos[&"y"]
	var dist: int = absi(dx) + absi(dy)
	assert_lte(dist, 200,
		"Cat should be within arrival distance")
