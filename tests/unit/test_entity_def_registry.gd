extends GutTest

var _registry: EntityDefRegistry


func before_each() -> void:
	_registry = EntityDefRegistry.new()


func test_register_and_lookup():
	var def: Dictionary = {
		"id": "cat", "desires": {"warmth": 800},
	}
	_registry.register(&"tcp_cats:cat", def)
	assert_true(_registry.has_entity(&"tcp_cats:cat"))
	assert_eq(_registry.get_definition(&"tcp_cats:cat"), def)


func test_has_entity_returns_false_for_unknown():
	assert_false(_registry.has_entity(&"nonexistent:thing"))


func test_get_all_entities():
	_registry.register(
		&"tcp_cats:cat",
		{"id": "cat", "desires": {"warmth": 800}},
	)
	_registry.register(
		&"tcp_tuna:tuna_can",
		{"id": "tuna_can", "states": {}},
	)
	var all: Array[StringName] = _registry.get_all_entities()
	assert_eq(all.size(), 2)
	assert_has(all, &"tcp_cats:cat")
	assert_has(all, &"tcp_tuna:tuna_can")


func test_has_traversal_true_for_species():
	_registry.register(&"tcp_cats:cat", {
		"id": "cat", "traversal": ["WALK", "JUMP_UP"],
	})
	assert_true(_registry.has_traversal(&"tcp_cats:cat"))


func test_has_traversal_false_for_object():
	_registry.register(
		&"tcp_tuna:tuna_can",
		{"id": "tuna_can", "states": {}},
	)
	assert_false(_registry.has_traversal(&"tcp_tuna:tuna_can"))


func test_has_desires_true_for_species():
	_registry.register(&"tcp_cats:cat", {
		"id": "cat", "desires": {"warmth": 800},
	})
	assert_true(_registry.has_desires(&"tcp_cats:cat"))


func test_has_desires_false_for_object():
	_registry.register(
		&"tcp_tuna:tuna_can",
		{"id": "tuna_can", "states": {}},
	)
	assert_false(_registry.has_desires(&"tcp_tuna:tuna_can"))


func test_get_traversal():
	_registry.register(&"tcp_cats:cat", {
		"id": "cat",
		"traversal": ["WALK", "JUMP_UP", "JUMP_DOWN"],
	})
	var traversal: Array = _registry.get_traversal(
		&"tcp_cats:cat",
	)
	assert_eq(traversal.size(), 3)
	assert_has(traversal, "WALK")


func test_get_desires():
	_registry.register(&"tcp_cats:cat", {
		"id": "cat",
		"desires": {"warmth": 800, "noise": -600},
	})
	var desires: Dictionary = _registry.get_desires(
		&"tcp_cats:cat",
	)
	assert_eq(desires["warmth"], 800)
	assert_eq(desires["noise"], -600)


func test_get_initial_state():
	_registry.register(
		&"tcp_cats:cat",
		{"id": "cat", "initial_state": "idle"},
	)
	assert_eq(
		_registry.get_initial_state(&"tcp_cats:cat"),
		&"idle",
	)


func test_get_states():
	var states: Dictionary = {
		"idle": {"advertisements": []},
		"sleeping": {
			"advertisements": [
				{"type": "warmth", "strength": 400},
			],
		},
	}
	_registry.register(
		&"tcp_cats:cat", {"id": "cat", "states": states},
	)
	assert_eq(_registry.get_states(&"tcp_cats:cat"), states)
