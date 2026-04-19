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
	var ws := WiringSystem.new(db, locks, events, {&"cable_max_length_px": 160})
	# Dispenser and button share rack 0; HUM sits within cable reach. Positions
	# use slot 5 of rack 0 so the rack_of() check resolves all three entities
	# in rack 0.
	var slot_rect: Rect2i = Constants.slot_rect_world(0, 0, 5)
	var cx: int = slot_rect.position.x + slot_rect.size.x / 2
	var cy: int = slot_rect.position.y + slot_rect.size.y / 2
	var hum: int = _make_hum_at(db, cx, cy)
	var tuna: int = _make_tuna_at(db, cx, cy)
	var button: int = _make_button_at(db, tuna, cx, cy)
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
	var ws := WiringSystem.new(db, locks, events, {&"cable_max_length_px": 160})
	var slot_rect: Rect2i = Constants.slot_rect_world(0, 0, 5)
	var cx: int = slot_rect.position.x + slot_rect.size.x / 2
	var cy: int = slot_rect.position.y + slot_rect.size.y / 2
	var hum: int = _make_hum_at(db, cx, cy)
	var tuna: int = _make_tuna_at(db, cx, cy)
	var button: int = _make_button_at(db, tuna, cx, cy)
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


func _make_hum_at(db: GameStateDB, x: int, y: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"hum", {
		&"reserve": HumSystem.DEFAULT_CAPACITY,
		&"capacity": HumSystem.DEFAULT_CAPACITY,
	})
	db.set_component(id, &"position", {&"x": x, &"y": y})
	db.update_spatial(id, x, y)
	return id


func _make_tuna_at(db: GameStateDB, x: int, y: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"tuna_dispenser", {
		&"hum_cost": 50, &"can_type": &"tcp_tuna:tuna_can",
	})
	db.set_component(id, &"hum_powered", {})
	db.set_component(id, &"position", {&"x": x, &"y": y})
	db.update_spatial(id, x, y)
	return id


func _make_button_at(db: GameStateDB, dispenser_id: int, x: int, y: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"tuna_button", {&"dispenser_id": dispenser_id})
	db.set_component(id, &"position", {&"x": x, &"y": y})
	db.update_spatial(id, x, y)
	return id
