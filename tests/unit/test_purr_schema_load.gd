extends GutTest

var _db: GameStateDB
var _reg: EntityDefRegistry


func before_each() -> void:
	_db = GameStateDB.new()
	_reg = EntityDefRegistry.new()


func test_purr_component_materialized_from_recipe() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	_reg.register(&"test:catlike", {
		"id": "test:catlike",
		"schema_version": 1,
		"size_ru": 1,
		"placement": "rack",
		"purr": {"rate_when_satisfied": 12},
	})
	var id: int = _reg.spawn(&"test:catlike", _db, {})
	assert_true(_db.has_component(id, &"purr"), "purr component should exist")
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 0,
		"purr.intensity starts at 0")


func test_species_without_purr_has_no_component() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	_reg.register(&"test:silent", {
		"id": "test:silent",
		"schema_version": 1,
		"size_ru": 1,
		"placement": "rack",
	})
	var id: int = _reg.spawn(&"test:silent", _db, {})
	assert_false(_db.has_component(id, &"purr"),
		"Entity without purr in recipe must not have purr component")


func test_purr_config_rate_matches_recipe() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	_reg.register(&"test:singer", {
		"id": "test:singer",
		"schema_version": 1,
		"size_ru": 1,
		"placement": "rack",
		"purr": {"rate_when_satisfied": 25},
	})
	var id: int = _reg.spawn(&"test:singer", _db, {})
	assert_true(_db.has_component(id, &"purr_config"),
		"purr_config component should exist when recipe declares purr")
	assert_eq(_db.get_field(id, &"purr_config", &"rate_when_satisfied"), 25,
		"purr_config.rate_when_satisfied must reflect the recipe value faithfully")
