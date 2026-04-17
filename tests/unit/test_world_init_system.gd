extends GutTest

var _db: GameStateDB
var _entity_defs: EntityDefRegistry
var _scenarios: ScenarioRegistry
var _wis: WorldInitSystem


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	_db = GameStateDB.new()
	_entity_defs = EntityDefRegistry.new()
	_scenarios = ScenarioRegistry.new()
	_register_fake_entity(&"mod:item", {"size_ru": 1, "placement": "rack"})
	_wis = WorldInitSystem.new(_db, _entity_defs, _scenarios)


func test_required_entity_spawns() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	_scenarios.register(&"mod:one", {
		"schema_version": 1,
		"id": "mod:one",
		"entities": [{"type": "mod:item", "rack": 0, "slot": 0}],
	})
	_wis.apply(&"mod:one")
	assert_eq(_db.entity_count(), 1, "Expected one entity spawned")


func test_missing_required_entity_aborts() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	_scenarios.register(&"mod:one", {
		"schema_version": 1,
		"id": "mod:one",
		"entities": [{"type": "absent:type", "rack": 0, "slot": 0}],
	})
	_wis.apply(&"mod:one")
	assert_eq(_db.entity_count(), 0, "Required entity failure must abort population")
	assert_push_error("world_init aborted")


func test_missing_optional_entity_skipped() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	_scenarios.register(&"mod:one", {
		"schema_version": 1,
		"id": "mod:one",
		"entities": [
			{"type": "mod:item", "rack": 0, "slot": 0},
			{"type": "absent:type", "rack": 0, "slot": 1, "required": false},
		],
	})
	_wis.apply(&"mod:one")
	assert_eq(_db.entity_count(), 1, "Optional entity skipped, required still spawns")


func test_missing_scenario_aborts() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	_wis.apply(&"never:registered")
	assert_eq(_db.entity_count(), 0)
	assert_push_error("scenario not found")


func _register_fake_entity(id: StringName, def: Dictionary) -> void:
	var full: Dictionary = {"id": String(id), "schema_version": 1}
	full.merge(def)
	_entity_defs.register(id, full)
