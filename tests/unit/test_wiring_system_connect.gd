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


func test_fresh_connect_writes_cable_and_emits() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum: int = _make_hum(0)
	var tuna: int = _make_tuna(5)
	var ok: bool = _ws.handle_connect(1, hum, tuna)
	assert_true(ok)
	assert_true(_db.has_component(tuna, &"hum_cable"))
	assert_eq(_db.get_field(tuna, &"hum_cable", &"hum_id"), hum)
	assert_eq(_events.connects.size(), 1)


func test_connect_out_of_reach_denies() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum: int = _make_hum(0)
	var tuna: int = _make_tuna(200_000)  # ~250 RU apart, beyond 20 RU budget
	var ok: bool = _ws.handle_connect(1, hum, tuna)
	assert_false(ok)
	assert_false(_db.has_component(tuna, &"hum_cable"))
	assert_eq(_events.denies, [&"out_of_reach"])


func test_connect_to_non_hum_powered_denies() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum: int = _make_hum(0)
	var target: int = _db.create_entity()
	_db.set_component(target, &"position", {&"x": 0, &"y": 0})
	var ok: bool = _ws.handle_connect(1, hum, target)
	assert_false(ok, "Non-hum_powered target must be rejected")


func test_connect_from_non_hum_denies() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var source: int = _db.create_entity()
	_db.set_component(source, &"position", {&"x": 0, &"y": 0})
	var tuna: int = _make_tuna(5)
	var ok: bool = _ws.handle_connect(1, source, tuna)
	assert_false(ok, "Source must carry a hum component")


func test_replace_on_connect_emits_disconnect_then_connect() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_a: int = _make_hum(0)
	var hum_b: int = _make_hum(2000)
	var tuna: int = _make_tuna(1000)
	_ws.handle_connect(1, hum_a, tuna)
	_events.clear()
	_ws.handle_connect(1, hum_b, tuna)
	assert_eq(_events.disconnects.size(), 1)
	assert_eq(_events.disconnects[0][0], hum_a)
	assert_eq(_events.connects.size(), 1)
	assert_eq(_db.get_field(tuna, &"hum_cable", &"hum_id"), hum_b)


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
