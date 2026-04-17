extends GutTest

var _r: ScenarioRegistry


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	_r = ScenarioRegistry.new()


func test_register_then_get() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	var def: Dictionary = {
		"schema_version": 1,
		"id": "tcp_base:starter",
		"entities": [],
	}
	_r.register(&"tcp_base:starter", def)
	assert_eq(_r.get_scenario(&"tcp_base:starter"), def)


func test_has_scenario() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	assert_false(_r.has_scenario(&"tcp_base:starter"))
	_r.register(&"tcp_base:starter", {
		"schema_version": 1,
		"id": "tcp_base:starter",
		"entities": [],
	})
	assert_true(_r.has_scenario(&"tcp_base:starter"))


func test_get_missing_returns_empty() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	assert_eq(_r.get_scenario(&"absent:id"), {})


func test_ids_sorted() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	_r.register(&"b:x", {"schema_version": 1, "id": "b:x", "entities": []})
	_r.register(&"a:x", {"schema_version": 1, "id": "a:x", "entities": []})
	assert_eq(_r.ids(), [&"a:x", &"b:x"])
