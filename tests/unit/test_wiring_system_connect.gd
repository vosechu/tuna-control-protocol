extends GutTest

# AI-DEV: The happy-path fresh-connect assertions (cable written, hum_id
# correct, exactly one connect event) are covered implicitly by every other
# wiring test that uses `handle_connect(...)` as setup — any mutation to the
# happy path breaks those tests cascading across the whole wiring suite, so
# keeping a dedicated `test_fresh_connect_writes_cable_and_emits` here blocked
# surgical mutation targeting without adding real coverage. Replace-on-connect
# is asserted by tests/integration/test_replace_on_connect.gd. This file now
# focuses on the three deny branches that are not otherwise exercised.

var _db: GameStateDB
var _locks: WiringLockRegistry
var _events: _FakeEvents
var _ws: WiringSystem


func before_each() -> void:
	_db = GameStateDB.new()
	_locks = WiringLockRegistry.new()
	_events = _FakeEvents.new()
	_ws = WiringSystem.new(_db, _locks, _events, {&"cable_max_length_px": 160})


func test_connect_out_of_reach_denies() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum: int = _make_hum(0)
	var tuna: int = _make_tuna(2000)  # 2000 px apart, beyond 160 px budget
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
