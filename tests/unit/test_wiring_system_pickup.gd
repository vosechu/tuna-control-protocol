extends GutTest

var _db: GameStateDB
var _locks: WiringLockRegistry
var _events: _FakeEvents
var _ws: WiringSystem


func before_each() -> void:
	_db = GameStateDB.new()
	_locks = WiringLockRegistry.new()
	_events = _FakeEvents.new()
	_ws = WiringSystem.new(_db, _locks, _events, {&"cable_max_length_ru": 20})


func test_pickup_actuator_end_removes_cable_and_locks() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum: int = _make_hum(0)
	var tuna: int = _make_tuna(5)
	_ws.handle_connect(1, hum, tuna)
	_events.clear()
	var ok: bool = _ws.handle_pickup_actuator_end(1, 100, tuna)
	assert_true(ok)
	assert_false(_db.has_component(tuna, &"hum_cable"))
	assert_true(_locks.is_locked_actuator(tuna))
	assert_eq(_events.disconnects.size(), 1)


func test_pickup_denies_when_already_locked() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum: int = _make_hum(0)
	var tuna: int = _make_tuna(5)
	_ws.handle_connect(1, hum, tuna)
	_ws.handle_pickup_actuator_end(1, 100, tuna)
	var ok: bool = _ws.handle_pickup_actuator_end(2, 101, tuna)
	assert_false(ok, "Second peer denied while first holds pickup lock")


func test_cancel_retracts_cable_back_to_original() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum: int = _make_hum(0)
	var tuna: int = _make_tuna(5)
	_ws.handle_connect(1, hum, tuna)
	_ws.handle_pickup_actuator_end(1, 100, tuna)
	_events.clear()
	var ok: bool = _ws.handle_cancel(1, tuna)
	assert_true(ok)
	assert_false(_locks.is_locked_actuator(tuna))
	assert_eq(_db.get_field(tuna, &"hum_cable", &"hum_id"), hum)
	assert_eq(_events.connects.size(), 1, "Retract emits connect")


func test_cancel_drops_when_original_hum_gone() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum: int = _make_hum(0)
	var tuna: int = _make_tuna(5)
	_ws.handle_connect(1, hum, tuna)
	_ws.handle_pickup_actuator_end(1, 100, tuna)
	_db.destroy_entity(hum)
	var ok: bool = _ws.handle_cancel(1, tuna)
	assert_false(ok, "Original HUM gone → retract fails, treat as delete")
	assert_false(_locks.is_locked_actuator(tuna))
	assert_false(_db.has_component(tuna, &"hum_cable"))


func test_delete_releases_lock_without_reattaching() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum: int = _make_hum(0)
	var tuna: int = _make_tuna(5)
	_ws.handle_connect(1, hum, tuna)
	_ws.handle_pickup_actuator_end(1, 100, tuna)
	var ok: bool = _ws.handle_delete(1, tuna)
	assert_true(ok)
	assert_false(_locks.is_locked_actuator(tuna))
	assert_false(_db.has_component(tuna, &"hum_cable"))


func test_start_validates_hum_source() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum: int = _make_hum(0)
	assert_true(_ws.handle_start(1, hum))
	var junk: int = _db.create_entity()
	assert_false(_ws.handle_start(1, junk))


func _make_hum(x: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"hum", {
		&"reserve": HumSystem.DEFAULT_CAPACITY,
		&"capacity": HumSystem.DEFAULT_CAPACITY,
	})
	_db.set_component(id, &"position", {&"x": x, &"y": 0})
	_db.update_spatial(id, x, 0)
	return id


func _make_tuna(x: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"tuna_dispenser", {&"hum_cost": 50})
	_db.set_component(id, &"hum_powered", {})
	_db.set_component(id, &"position", {&"x": x, &"y": 0})
	_db.update_spatial(id, x, 0)
	return id


class _FakeEvents extends RefCounted:
	var connects: Array = []
	var disconnects: Array = []
	var denies: Array = []
	func emit_cable_connected(hum: int, dev: int, cable_type: StringName) -> void:
		connects.append([hum, dev, cable_type])
	func emit_cable_disconnected(hum: int, dev: int) -> void:
		disconnects.append([hum, dev])
	func emit_cable_deny(reason: StringName) -> void:
		denies.append(reason)
	func clear() -> void:
		connects.clear()
		disconnects.clear()
		denies.clear()
