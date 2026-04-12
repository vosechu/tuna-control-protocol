extends GutTest

const _SYSTEM_SCRIPT := preload("res://engine/growth/plant_growth_system.gd")
const _STATE := preload("res://engine/growth/plant_growth_state.gd")


class _FakeHeatGrid:
	var _temp: int = 0

	func get_temperature(_slot_key: int) -> int:
		return _temp

	func set_temp(t: int) -> void:
		_temp = t


var _db: GameStateDB
var _heat: _FakeHeatGrid
var _system: RefCounted
var _server_id: int


func before_each() -> void:
	_db = GameStateDB.new()
	_heat = _FakeHeatGrid.new()
	_system = _SYSTEM_SCRIPT.new(_db, _heat)
	_server_id = _db.create_entity()
	_db.set_component(_server_id, &"position", {&"x": 2500, &"y": 800})
	_db.set_component(_server_id, &"cat_presence", {&"seconds": 0})
	_db.set_component(_server_id, &"plant_growth", {
		&"state": _STATE.DORMANT,
		&"cat_seconds": 0,
		&"variant": _STATE.VARIANT_MOSS,
		&"attached_to": _server_id,
	})


func _set_growth(field: StringName, value: Variant) -> void:
	var g: Dictionary = _db.get_component(_server_id, &"plant_growth")
	g[field] = value
	_db.set_component(_server_id, &"plant_growth", g)


func test_dormant_with_cold_slot_stays_dormant():
	_heat.set_temp(300)
	_db.set_field(_server_id, &"cat_presence", &"seconds", 500)
	_system.tick()
	var growth: Dictionary = _db.get_component(_server_id, &"plant_growth")
	assert_eq(growth[&"state"], _STATE.DORMANT,
		"Cold slot should stay DORMANT even with cat presence")


func test_dormant_with_warm_slot_and_cats_arms():
	_heat.set_temp(700)
	_db.set_field(_server_id, &"cat_presence", &"seconds", 10)
	_system.tick()
	var growth: Dictionary = _db.get_component(_server_id, &"plant_growth")
	assert_eq(growth[&"state"], _STATE.ARMED,
		"Warm slot with cats should transition to ARMED")


func test_armed_accumulates_cat_seconds():
	_heat.set_temp(700)
	_db.set_field(_server_id, &"cat_presence", &"seconds", 50)
	_set_growth(&"state", _STATE.ARMED)
	_set_growth(&"cat_seconds", 100)
	_system.tick()
	var growth: Dictionary = _db.get_component(_server_id, &"plant_growth")
	assert_gt(growth[&"cat_seconds"], 100,
		"ARMED state should accumulate cat_seconds while cats present")


func test_armed_reaches_threshold_grows():
	_heat.set_temp(700)
	_db.set_field(_server_id, &"cat_presence", &"seconds", 400)
	_set_growth(&"state", _STATE.ARMED)
	_set_growth(&"cat_seconds", 299)
	_system.tick()
	var growth: Dictionary = _db.get_component(_server_id, &"plant_growth")
	assert_eq(growth[&"state"], _STATE.PRESENT,
		"Reaching 300 cat-seconds should transition to PRESENT")


func test_hysteresis_dip_preserves_counter():
	_db.set_field(_server_id, &"cat_presence", &"seconds", 400)
	_set_growth(&"state", _STATE.ARMED)
	_set_growth(&"cat_seconds", 100)

	_heat.set_temp(700)
	_system.tick()
	var after_warm_1: Dictionary = _db.get_component(_server_id, &"plant_growth")
	assert_gt(after_warm_1[&"cat_seconds"], 100, "First warm tick should increment counter")

	_heat.set_temp(500)
	for _i: int in 5:
		_system.tick()
	var dip_growth: Dictionary = _db.get_component(_server_id, &"plant_growth")
	var dip_cat_seconds: int = dip_growth[&"cat_seconds"]
	assert_gte(dip_cat_seconds, after_warm_1[&"cat_seconds"],
		"Dip ticks must preserve counter")
	assert_eq(dip_growth[&"state"], _STATE.ARMED,
		"State should stay ARMED during dip")

	_heat.set_temp(700)
	_system.tick()
	var resume_cat_seconds: int = _db.get_component(_server_id, &"plant_growth")[&"cat_seconds"]
	assert_gt(resume_cat_seconds, dip_cat_seconds,
		"Return to warm should resume incrementing counter")


func test_present_survives_hum_brownout():
	_heat.set_temp(0)
	_db.set_field(_server_id, &"cat_presence", &"seconds", 400)
	_set_growth(&"state", _STATE.PRESENT)
	_set_growth(&"cat_seconds", 500)
	_system.tick()
	var growth: Dictionary = _db.get_component(_server_id, &"plant_growth")
	assert_eq(growth[&"state"], _STATE.PRESENT,
		"PRESENT state should survive HUM brownout")


func test_present_despawns_when_cats_leave():
	_heat.set_temp(700)
	_db.set_field(_server_id, &"cat_presence", &"seconds", 50)
	_set_growth(&"state", _STATE.PRESENT)
	_set_growth(&"cat_seconds", 99)
	_system.tick()
	var growth: Dictionary = _db.get_component(_server_id, &"plant_growth")
	assert_eq(growth[&"state"], _STATE.DORMANT,
		"PRESENT should despawn when cat_seconds < DECAY_THRESHOLD")
