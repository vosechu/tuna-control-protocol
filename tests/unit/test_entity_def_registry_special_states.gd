extends GutTest

var registry: EntityDefRegistry
var db: GameStateDB


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	registry = EntityDefRegistry.new()
	db = GameStateDB.new()


func test_spawn_materializes_special_states_component() -> void:
	registry.register(&"tcp_test:critter", {
		"id": "tcp_test:critter",
		"name": "Critter",
		"desires": {"warmth": {"weight": 500, "decay": -2}},
		"body_capabilities": {"walks": {}},
		"body_geometry": {"size_ru": 1},
		"senses": {"sight": 186, "hearing": 186, "smell": 186, "touch": 32},
		"ambient_states": {"warm": [], "cold": []},
		"special_states": {"STARTLED": {"min_duration_ticks": 10}},
	})

	var id: int = registry.spawn(&"tcp_test:critter", db)

	assert_true(db.has_component(id, &"special_states"),
		"special_states component should be set on spawned entity")
	var specials: Dictionary = db.get_component(id, &"special_states")
	var startled: Dictionary = specials.get(&"STARTLED")
	assert_eq(startled.get(&"min_duration_ticks"), 10,
		"STARTLED min_duration_ticks materialized correctly")


func test_spawn_skips_special_states_when_recipe_lacks_it() -> void:
	registry.register(&"tcp_test:plain", {
		"id": "tcp_test:plain",
		"name": "Plain",
		"desires": {"warmth": {"weight": 500, "decay": -2}},
		"body_capabilities": {"walks": {}},
		"body_geometry": {"size_ru": 1},
		"senses": {"sight": 186, "hearing": 186, "smell": 186, "touch": 32},
		# No special_states block
	})

	var id: int = registry.spawn(&"tcp_test:plain", db)

	assert_false(db.has_component(id, &"special_states"),
		"recipes without special_states must not carry the component")
