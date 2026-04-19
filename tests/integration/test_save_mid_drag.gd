extends GutTest

# Round-trip a mid-drag state through the save adapter: a cable that was
# in the player's hand when the snapshot ran must resurface on the original
# HUM after reload. Phase 2 ships the adapter as a standalone class; wiring
# it into an on-disk save writer is a later-phase concern.


func test_mid_drag_save_reload_restores_cable() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var db := GameStateDB.new()
	var locks := WiringLockRegistry.new()
	var ws := WiringSystem.new(db, locks, null, {&"cable_max_length_px": 160})
	var adapter := WiringSaveAdapter.new(db, locks)
	var hum: int = _make_hum(db, 0)
	var tuna: int = _make_tuna(db, 20)
	ws.handle_connect(1, hum, tuna)
	ws.handle_pickup_actuator_end(1, 100, tuna)
	# Snapshot mid-drag: live DB lacks the cable but the adapter still
	# produces a synthetic row from the lock registry.
	assert_false(db.has_component(tuna, &"hum_cable"))
	var payload: Dictionary = adapter.write_snapshot()
	var rows: Array = payload[&"hum_cables"]
	assert_eq(rows.size(), 1)
	assert_eq(rows[0][&"actuator_id"], tuna)
	assert_eq(rows[0][&"hum_id"], hum)
	# Reload into a fresh DB with the same entity ids.
	var db2 := GameStateDB.new()
	_make_hum_with_id(db2, hum, 0)
	_make_tuna_with_id(db2, tuna, 20)
	var adapter2 := WiringSaveAdapter.new(db2, WiringLockRegistry.new())
	adapter2.read_snapshot(payload)
	assert_true(db2.has_component(tuna, &"hum_cable"))
	assert_eq(db2.get_field(tuna, &"hum_cable", &"hum_id"), hum)


func test_reload_drops_cables_to_missing_hum() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var db := GameStateDB.new()
	_make_tuna_with_id(db, 99, 0)  # actuator exists
	var adapter := WiringSaveAdapter.new(db, WiringLockRegistry.new())
	adapter.read_snapshot({&"hum_cables": [
		{&"actuator_id": 99, &"hum_id": 42},  # hum 42 does not exist
	]})
	assert_false(
		db.has_component(99, &"hum_cable"),
		"Cable to missing HUM must be dropped on reload",
	)


func _make_hum(db: GameStateDB, x: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"hum", {
		&"reserve": HumSystem.DEFAULT_CAPACITY,
		&"capacity": HumSystem.DEFAULT_CAPACITY,
	})
	db.set_component(id, &"position", {&"x": x, &"y": 0})
	db.update_spatial(id, x, 0)
	return id


func _make_hum_with_id(db: GameStateDB, id: int, x: int) -> void:
	db.create_entity_with_id(id)
	db.set_component(id, &"hum", {
		&"reserve": HumSystem.DEFAULT_CAPACITY,
		&"capacity": HumSystem.DEFAULT_CAPACITY,
	})
	db.set_component(id, &"position", {&"x": x, &"y": 0})
	db.update_spatial(id, x, 0)


func _make_tuna(db: GameStateDB, x: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"tuna_dispenser", {&"hum_cost": 50})
	db.set_component(id, &"hum_powered", {})
	db.set_component(id, &"position", {&"x": x, &"y": 0})
	db.update_spatial(id, x, 0)
	return id


func _make_tuna_with_id(db: GameStateDB, id: int, x: int) -> void:
	db.create_entity_with_id(id)
	db.set_component(id, &"tuna_dispenser", {&"hum_cost": 50})
	db.set_component(id, &"hum_powered", {})
	db.set_component(id, &"position", {&"x": x, &"y": 0})
	db.update_spatial(id, x, 0)
