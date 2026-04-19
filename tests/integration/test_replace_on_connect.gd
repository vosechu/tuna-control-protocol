extends GutTest

# Reconnecting a cable to a different HUM must emit exactly one
# disconnect (for the old carrier) and one connect (for the new one)
# in that order, with no intermediate state the narrator could log.


func test_replace_emits_disconnect_then_connect() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var db := GameStateDB.new()
	var locks := WiringLockRegistry.new()
	var events := _SequencedEvents.new()
	var ws := WiringSystem.new(db, locks, events, {&"cable_max_length_px": 160})
	var hum_a: int = _make_hum(db, 0)
	var hum_b: int = _make_hum(db, 20)
	var tuna: int = _make_tuna(db, 10)
	ws.handle_connect(1, hum_a, tuna)
	events.clear()
	ws.handle_connect(1, hum_b, tuna)
	var seq: Array = events.sequence
	assert_eq(seq.size(), 2, "Replace must emit exactly disconnect + connect")
	assert_eq(seq[0][0], &"disconnect")
	assert_eq(seq[0][1], hum_a)
	assert_eq(seq[0][2], tuna)
	assert_eq(seq[1][0], &"connect")
	assert_eq(seq[1][1], hum_b)
	assert_eq(seq[1][2], tuna)
	assert_eq(db.get_field(tuna, &"hum_cable", &"hum_id"), hum_b)


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
	db.set_component(id, &"tuna_dispenser", {&"hum_cost": 50})
	db.set_component(id, &"hum_powered", {})
	db.set_component(id, &"position", {&"x": x, &"y": 0})
	db.update_spatial(id, x, 0)
	return id


class _SequencedEvents extends RefCounted:
	var sequence: Array = []
	func emit_cable_connected(hum: int, dev: int, _cable_type: StringName) -> void:
		sequence.append([&"connect", hum, dev])
	func emit_cable_disconnected(hum: int, dev: int) -> void:
		sequence.append([&"disconnect", hum, dev])
	func emit_cable_deny(_reason: StringName) -> void:
		pass
	func clear() -> void:
		sequence.clear()
