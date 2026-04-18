extends GutTest

var _db: GameStateDB
var _reg: EntityDefRegistry


func before_each() -> void:
	_db = GameStateDB.new()
	_reg = EntityDefRegistry.new()
	_reg.register(&"tcp_base:hum_device", {
		"id": "tcp_base:hum_device",
		"schema_version": 1,
		"size_ru": 6,
		"placement": "rack",
		"hum": {"capacity": 10000},
		"hum_receiver": {"radius_ru": 4},
	})


func test_hum_device_spawns_with_full_reserve() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var id: int = _reg.spawn(&"tcp_base:hum_device", _db, {"rack": 0, "slot": 0})
	assert_true(_db.has_component(id, &"hum"))
	assert_eq(_db.get_field(id, &"hum", &"capacity"), 10000)
	assert_eq(
		_db.get_field(id, &"hum", &"reserve"),
		10000,
		"Fresh HUM device starts at full reserve",
	)


func test_hum_device_has_receiver() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var id: int = _reg.spawn(&"tcp_base:hum_device", _db, {"rack": 0, "slot": 0})
	assert_true(_db.has_component(id, &"hum_receiver"))
	assert_eq(_db.get_field(id, &"hum_receiver", &"radius_ru"), 4)
