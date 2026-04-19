extends GutTest

const _SYSTEM_SCRIPT := preload("res://engine/growth/reclamation_system.gd")

var _db: GameStateDB
var _system: RefCounted
var _server_id: int
var _cat_id: int


func before_each() -> void:
	_db = GameStateDB.new()
	_system = _SYSTEM_SCRIPT.new(_db)
	_server_id = _db.create_entity()
	var slot_rect: Rect2i = Constants.slot_rect_world(0, 2, 5)
	var sx: int = slot_rect.position.x + slot_rect.size.x / 2
	var sy: int = slot_rect.position.y + slot_rect.size.y / 2
	_db.set_component(_server_id, &"position", {&"x": sx, &"y": sy})
	_db.set_component(_server_id, &"reclamation", {&"seconds": 0})
	_cat_id = _db.create_entity()
	_db.set_component(_cat_id, &"position", {&"x": sx, &"y": sy})
	_db.set_component(_cat_id, &"species", {&"id": &"tcp_cats:cat"})
	_db.set_component(_cat_id, &"tends_servers", {})


func test_cat_overlapping_server_increments_presence():
	_system.tick()
	var pres: int = _db.get_field(_server_id, &"reclamation", &"seconds")
	assert_gt(pres, 0, "Cat overlapping server should increment reclamation")


func test_cat_far_from_server_does_not_increment():
	_db.set_component(_cat_id, &"position", {&"x": 99999, &"y": 99999})
	_system.tick()
	var pres: int = _db.get_field(_server_id, &"reclamation", &"seconds")
	assert_eq(pres, 0, "Cat far from server should not increment reclamation")


func test_presence_decays_when_cat_leaves():
	_db.set_field(_server_id, &"reclamation", &"seconds", 500)
	_db.set_component(_cat_id, &"position", {&"x": 99999, &"y": 99999})
	for _i: int in 10:
		_system.tick()
	var pres: int = _db.get_field(_server_id, &"reclamation", &"seconds")
	assert_lt(pres, 500, "Presence should decay when cat leaves")


func test_presence_capped_at_max():
	_db.set_field(_server_id, &"reclamation", &"seconds", 0)
	for _i: int in 2000:
		_system.tick()
	var pres: int = _db.get_field(_server_id, &"reclamation", &"seconds")
	assert_lte(pres, 1000,
		"reclamation should cap at 1000 to prevent overflow")


func test_ferret_without_tends_servers_does_not_trigger_presence():
	var server_id: int = _db.create_entity()
	_db.set_component(server_id, &"position", {&"x": 0, &"y": 0})
	_db.set_component(server_id, &"reclamation", {&"seconds": 0})
	var ferret_id: int = _db.create_entity()
	_db.set_component(ferret_id, &"species", {&"id": &"tcp_ferrets:ferret"})
	_db.set_component(ferret_id, &"position", {&"x": 0, &"y": 0})
	# Intentionally no tends_servers component
	var sys := ReclamationSystem.new(_db)
	sys.tick()
	assert_eq(_db.get_field(server_id, &"reclamation", &"seconds"), 0,
		"Ferret should not increment reclamation because it does not tend servers")
