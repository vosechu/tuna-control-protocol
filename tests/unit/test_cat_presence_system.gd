extends GutTest

const _SYSTEM_SCRIPT := preload("res://engine/growth/cat_presence_system.gd")

var _db: GameStateDB
var _system: RefCounted
var _server_id: int
var _cat_id: int


func before_each() -> void:
	_db = GameStateDB.new()
	_system = _SYSTEM_SCRIPT.new(_db)
	_server_id = _db.create_entity()
	var slot_pu: Vector2i = Constants.rack_slot_to_pu(0, 2, 5)
	_db.set_component(_server_id, &"position", {&"x": slot_pu.x, &"y": slot_pu.y})
	_db.set_component(_server_id, &"cat_presence", {&"seconds": 0})
	_cat_id = _db.create_entity()
	_db.set_component(_cat_id, &"position", {&"x": slot_pu.x, &"y": slot_pu.y})
	_db.set_component(_cat_id, &"species", {&"id": &"tcp_cats:cat"})


func test_cat_overlapping_server_increments_presence():
	_system.tick()
	var pres: int = _db.get_field(_server_id, &"cat_presence", &"seconds")
	assert_gt(pres, 0, "Cat overlapping server should increment cat_presence")


func test_cat_far_from_server_does_not_increment():
	_db.set_component(_cat_id, &"position", {&"x": 99999, &"y": 99999})
	_system.tick()
	var pres: int = _db.get_field(_server_id, &"cat_presence", &"seconds")
	assert_eq(pres, 0, "Cat far from server should not increment cat_presence")


func test_presence_decays_when_cat_leaves():
	_db.set_field(_server_id, &"cat_presence", &"seconds", 500)
	_db.set_component(_cat_id, &"position", {&"x": 99999, &"y": 99999})
	for _i: int in 10:
		_system.tick()
	var pres: int = _db.get_field(_server_id, &"cat_presence", &"seconds")
	assert_lt(pres, 500, "Presence should decay when cat leaves")


func test_presence_capped_at_max():
	_db.set_field(_server_id, &"cat_presence", &"seconds", 0)
	for _i: int in 2000:
		_system.tick()
	var pres: int = _db.get_field(_server_id, &"cat_presence", &"seconds")
	assert_lte(pres, 1000,
		"cat_presence should cap at 1000 to prevent overflow")
