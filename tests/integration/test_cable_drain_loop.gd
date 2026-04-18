extends GutTest

# End-to-end: HUM + cable + TUNA press → reserve drains.
# Disconnect → next press silently fails; reserve unchanged.

const EventsScript: GDScript = preload("res://nodes/events.gd")


func test_connected_cable_lets_press_drain_hum() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var db := GameStateDB.new()
	var events: Object = EventsScript.new()
	var hum_sys := HumSystem.new(db, events)
	var food := FoodSystem.new(db, hum_sys, events)
	var locks := WiringLockRegistry.new()
	var ws := WiringSystem.new(db, locks, events, {&"cable_max_length_ru": 20})
	# Dispenser and button share rack 0; HUM sits just out of the same rack
	# so reach (20 RU) still covers it but the rack check for the button
	# passes.
	var hum: int = _make_hum(db, 0)
	var tuna: int = _make_tuna(db, 400)
	var button: int = _make_button(db, tuna, 800)
	var before: int = hum_sys.get_reserve(hum)
	# Without a cable, press fails.
	assert_eq(
		food.press_button(button),
		Constants.INVALID_ID,
		"No cable → press refused",
	)
	assert_eq(hum_sys.get_reserve(hum), before, "Reserve untouched")
	# Connect, then press: reserve drops.
	ws.handle_connect(1, hum, tuna)
	var can: int = food.press_button(button)
	assert_ne(can, Constants.INVALID_ID, "Cable + reserve → press dispenses")
	assert_lt(hum_sys.get_reserve(hum), before, "Reserve drained")


func test_disconnect_restores_unpowered_state() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var db := GameStateDB.new()
	var events: Object = EventsScript.new()
	var hum_sys := HumSystem.new(db, events)
	var food := FoodSystem.new(db, hum_sys, events)
	var locks := WiringLockRegistry.new()
	var ws := WiringSystem.new(db, locks, events, {&"cable_max_length_ru": 20})
	var hum: int = _make_hum(db, 0)
	var tuna: int = _make_tuna(db, 400)
	var button: int = _make_button(db, tuna, 800)
	ws.handle_connect(1, hum, tuna)
	ws.handle_pickup_actuator_end(1, 100, tuna)
	ws.handle_delete(1, tuna)
	var before: int = hum_sys.get_reserve(hum)
	assert_eq(
		food.press_button(button),
		Constants.INVALID_ID,
		"After delete → press refused again",
	)
	assert_eq(hum_sys.get_reserve(hum), before)


func _make_hum(db: GameStateDB, x: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"hum", {
		&"reserve": HumSystem.DEFAULT_CAPACITY,
		&"capacity": HumSystem.DEFAULT_CAPACITY,
	})
	db.set_component(id, &"position", {&"x": x, &"y": 0})
	db.update_spatial(id, x, 0)
	return id


func _make_tuna(db: GameStateDB, x: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"tuna_dispenser", {
		&"hum_cost": 50, &"can_type": &"tcp_tuna:tuna_can",
	})
	db.set_component(id, &"hum_powered", {})
	db.set_component(id, &"position", {&"x": x, &"y": 0})
	db.update_spatial(id, x, 0)
	return id


func _make_button(db: GameStateDB, dispenser_id: int, x: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"tuna_button", {&"dispenser_id": dispenser_id})
	db.set_component(id, &"position", {&"x": x, &"y": 0})
	db.update_spatial(id, x, 0)
	return id
