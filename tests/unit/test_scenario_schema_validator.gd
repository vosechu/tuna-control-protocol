extends GutTest

var _v: ScenarioSchemaValidator


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	_v = ScenarioSchemaValidator.new()


func test_valid_scenario_passes() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	var def: Dictionary = {
		"schema_version": 1,
		"id": "tcp_base:starter",
		"entities": [
			{"type": "tcp_base:hum_device", "rack": 0, "slot": 0},
		],
	}
	assert_true(_v.is_valid(def))


func test_missing_id_fails() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	var def: Dictionary = {"schema_version": 1, "entities": []}
	assert_false(_v.is_valid(def))


func test_missing_schema_version_fails() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	var def: Dictionary = {"id": "tcp_base:starter", "entities": []}
	assert_false(_v.is_valid(def))


func test_entity_missing_type_fails() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	var def: Dictionary = {
		"schema_version": 1,
		"id": "tcp_base:x",
		"entities": [{"rack": 0, "slot": 0}],
	}
	assert_false(_v.is_valid(def))


func test_entity_without_placement_fields_fails() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	var def: Dictionary = {
		"schema_version": 1,
		"id": "tcp_base:x",
		"entities": [{"type": "tcp_base:arm"}],
	}
	assert_false(_v.is_valid(def))


func test_floor_entity_requires_floor_fields() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	var def: Dictionary = {
		"schema_version": 1,
		"id": "tcp_base:x",
		"entities": [{"type": "tcp_base:arm", "floor_rack": 0, "floor_slot_offset": 0}],
	}
	assert_true(_v.is_valid(def))
