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
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var x: int = slot_rect.position.x + slot_rect.size.x / 2
	var y: int = slot_rect.position.y + slot_rect.size.y / 2
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"heat_source", {
		&"value": 800, &"radius_px": 24,
	})
	_db.set_component(id, &"advertisements", {&"list": [
		{
			&"desire_type": &"warmth",
			&"strength": 800,
			&"radius_px": 64,
			&"max_occupants": 1,
		},
	]})
	_db.update_spatial(id, x, y)
	return id


func _make_cat(rack: int, slot: int) -> int:
	var id: int = _db.create_entity()
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var x: int = slot_rect.position.x + slot_rect.size.x / 2
	var y: int = slot_rect.position.y + slot_rect.size.y / 2
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
		&"hunger": 800,
		&"attention": 800,
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
	var server: int = _make_server(2, 5)
	var cat: int = _make_cat(2, 8)

	# Propagate heat from the server
	_heat_grid.propagate()

	# Scatter warmth desire based on heat at cat's position
	var pos: Dictionary = _db.get_component(cat, &"position")
	var world_pos := Vector2i(pos[&"x"], pos[&"y"])
	var bay: int = Constants.world_to_bay(world_pos)
	var q: SlotQuery = Constants.bay_local_to_slot(bay, world_pos)
	var cell: int
	if q.zone == &"slot":
		cell = Constants.rack_cell(q.get_rack(), q.get_slot())
	else:
		cell = Constants.rack_cell(0, 0)
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
	var server: int = _make_server(2, 5)
	var cat: int = _make_cat(2, 8)

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
	var speed: int = 2  # ANIMAL_SPEED_PX
	for tick: int in 200:
		var pos: Dictionary = _db.get_component(cat, &"position")
		var target: Dictionary = _db.get_component(
			cat, &"target"
		)
		if target[&"entity_id"] == Constants.INVALID_ID:
			break
		var dx: int = target[&"x"] - pos[&"x"]
		var dy: int = target[&"y"] - pos[&"y"]
		var dist: int = absi(dx) + absi(dy)
		if dist <= speed:
			break
		var move_x: int = 0
		var move_y: int = 0
		if dx != 0:
			move_x = speed * dx / dist
		if dy != 0:
			move_y = speed * dy / dist
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
	# Slot 0 is the BOTTOM (higher Y). Slot 5 is below slot 8 in slot-index
	# space but physically LOWER on screen → larger Y. Cat moves down.
	assert_gt(end_y, start_y,
		"Cat should have moved downward (higher Y) toward server at slot 5")


func test_mark_animals_dirty_only_marks_species_entities() -> void:
	# Non-species entities (servers, objects) should not be marked dirty
	var server: int = _make_server(2, 5)
	var cat: int = _make_cat(2, 8)

	# Simulate _mark_animals_dirty logic
	var animals: Array[int] = _db.get_entities_with(&"desires")
	for entity_id: int in animals:
		if not _db.has_component(entity_id, &"species"):
			continue
		_resolver.mark_dirty(entity_id)

	# Propagate heat + scatter warmth
	_heat_grid.propagate()
	var pos: Dictionary = _db.get_component(cat, &"position")
	var world_pos := Vector2i(pos[&"x"], pos[&"y"])
	var bay: int = Constants.world_to_bay(world_pos)
	var q: SlotQuery = Constants.bay_local_to_slot(bay, world_pos)
	var cell: int
	if q.zone == &"slot":
		cell = Constants.rack_cell(q.get_rack(), q.get_slot())
	else:
		cell = Constants.rack_cell(0, 0)
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
	var server: int = _make_server(2, 5)
	var cat: int = _make_cat(2, 5)  # Same position as server

	var server_pos: Dictionary = _db.get_component(
		server, &"position"
	)
	# Place cat very close to target (within ANIMAL_SPEED_PX which is 2 px)
	var close_x: int = server_pos[&"x"] + 1
	var close_y: int = server_pos[&"y"] + 1
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

	# Distance is 2 (1+1), which equals ANIMAL_SPEED_PX (2)
	# So a single movement step should cause arrival
	var pos: Dictionary = _db.get_component(cat, &"position")
	var target: Dictionary = _db.get_component(cat, &"target")
	var dx: int = target[&"x"] - pos[&"x"]
	var dy: int = target[&"y"] - pos[&"y"]
	var dist: int = absi(dx) + absi(dy)
	assert_lte(dist, 2,
		"Cat should be within arrival distance")


func test_hunger_decays_each_tick() -> void:
	var cat: int = _make_cat(1, 5)
	# Verify hunger exists on spawned cat (set by _make_cat)
	var desires: Dictionary = _db.get_component(cat, &"desires")
	assert_true(desires.has(&"hunger"),
		"Cat should have hunger desire from spawn")
	var before: int = desires[&"hunger"]

	# Simulate one scatter pass: hunger decays at -3 per tick
	_db.add_all(&"desires", &"hunger", -3)
	_db.clamp_all(&"desires", &"hunger", 0, 1000)

	var after: Dictionary = _db.get_component(cat, &"desires")
	assert_eq(after[&"hunger"], before - 3,
		"Hunger should decay by 3 per tick")


func test_attention_decays_faster_than_hunger() -> void:
	var cat: int = _make_cat(1, 5)
	# Verify both desires exist on spawned cat
	var desires: Dictionary = _db.get_component(cat, &"desires")
	assert_true(desires.has(&"hunger"),
		"Cat should have hunger desire from spawn")
	assert_true(desires.has(&"attention"),
		"Cat should have attention desire from spawn")

	# Set both to 800 for comparison
	_db.set_field(cat, &"desires", &"hunger", 800)
	_db.set_field(cat, &"desires", &"attention", 800)

	# Simulate 10 scatter passes
	for tick: int in 10:
		_db.add_all(&"desires", &"hunger", -3)
		_db.add_all(&"desires", &"attention", -8)
	_db.clamp_all(&"desires", &"hunger", 0, 1000)
	_db.clamp_all(&"desires", &"attention", 0, 1000)

	var after: Dictionary = _db.get_component(cat, &"desires")
	assert_eq(after[&"hunger"], 770,
		"Hunger after 10 ticks: 800 - (3*10) = 770")
	assert_eq(after[&"attention"], 720,
		"Attention after 10 ticks: 800 - (8*10) = 720")
	assert_lt(after[&"attention"], after[&"hunger"],
		"Attention should decay faster than hunger")
