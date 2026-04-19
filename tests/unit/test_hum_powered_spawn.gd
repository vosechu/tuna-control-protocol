extends GutTest

var _db: GameStateDB
var _reg: EntityDefRegistry


func before_each() -> void:
	_db = GameStateDB.new()
	_reg = EntityDefRegistry.new()
	_reg.register(&"tcp_base:tuna_dispenser", {
		"id": "tcp_base:tuna_dispenser",
		"schema_version": 1,
		"size_ru": 1,
		"placement": "rack",
		"tuna_dispenser": {"hum_cost": 50, "can_type": "tcp_tuna:tuna_can"},
		"hum_powered": {},
	})
	_reg.register(&"tcp_base:arm", {
		"id": "tcp_base:arm",
		"schema_version": 1,
		"size_ru": 2,
		"placement": "floor",
		"arm": {"radius_px": 24, "hum_cost": 30, "open_duration_ticks": 10},
		"hum_powered": {},
	})
	_reg.register(&"tcp_base:plain_dispenser", {
		"id": "tcp_base:plain_dispenser",
		"schema_version": 1,
		"size_ru": 1,
		"placement": "rack",
		"tuna_dispenser": {"hum_cost": 50, "can_type": "tcp_tuna:tuna_can"},
	})


func test_hum_powered_field_materializes_tag_on_any_recipe() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Covers both tuna_dispenser and arm recipes in one test — the
	# production line is entity-agnostic so testing twice was redundant and
	# blocked surgical mutation targeting.
	var disp: int = _reg.spawn(&"tcp_base:tuna_dispenser", _db, {"rack": 0, "slot": 0})
	assert_true(
		_db.has_component(disp, &"hum_powered"),
		"tuna_dispenser recipe must materialize hum_powered tag",
	)
	var arm: int = _reg.spawn(&"tcp_base:arm", _db, {"rack": 0, "slot": 0})
	assert_true(
		_db.has_component(arm, &"hum_powered"),
		"arm recipe must materialize hum_powered tag",
	)


func test_recipe_without_hum_powered_field_gets_no_tag() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var id: int = _reg.spawn(&"tcp_base:plain_dispenser", _db, {"rack": 0, "slot": 0})
	assert_false(
		_db.has_component(id, &"hum_powered"),
		"Recipe without hum_powered field must not get the tag",
	)
