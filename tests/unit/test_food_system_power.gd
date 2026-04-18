extends GutTest

const EventsScript: GDScript = preload("res://nodes/events.gd")

var _db: GameStateDB
var _events: Object
var _hum: HumSystem
var _food: FoodSystem


func before_each() -> void:
	_db = GameStateDB.new()
	_events = EventsScript.new()
	_hum = HumSystem.new(_db, _events)
	_food = FoodSystem.new(_db, _hum, _events)


func test_device_without_cable_is_not_powered() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	_make_hum(0)
	var device_id: int = _make_tuna(0)
	assert_eq(
		_food.is_powered(device_id, 50),
		Constants.INVALID_ID,
		"Device without hum_cable must report not powered",
	)


func test_cable_to_live_hum_with_reserve_is_powered() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum(0)
	var device_id: int = _make_tuna(0)
	_db.set_component(device_id, &"hum_cable", {&"hum_id": hum_id})
	assert_eq(
		_food.is_powered(device_id, 50),
		hum_id,
		"Cable + reserve should return the source hum_id",
	)


func test_cable_to_missing_hum_is_not_powered() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var device_id: int = _make_tuna(0)
	_db.set_component(device_id, &"hum_cable", {&"hum_id": 99999})
	assert_eq(
		_food.is_powered(device_id, 50),
		Constants.INVALID_ID,
		"Tombstone cable (HUM despawned) must report not powered",
	)


func test_cable_to_drained_hum_is_not_powered() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum(0)
	_hum.drain_action(hum_id, _hum.get_reserve(hum_id))
	var device_id: int = _make_tuna(0)
	_db.set_component(device_id, &"hum_cable", {&"hum_id": hum_id})
	assert_eq(
		_food.is_powered(device_id, 50),
		Constants.INVALID_ID,
		"Drained HUM cannot power a device",
	)


func test_device_without_hum_powered_tag_is_not_powered() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum(0)
	var id: int = _db.create_entity()
	_db.set_component(id, &"tuna_dispenser", {&"hum_cost": 50})
	_db.set_component(id, &"hum_cable", {&"hum_id": hum_id})
	_db.set_component(id, &"position", {&"x": 0, &"y": 0})
	# No hum_powered tag — not something that needs a cable to operate
	assert_eq(
		_food.is_powered(id, 50),
		Constants.INVALID_ID,
		"Device without hum_powered tag must report not powered",
	)


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
