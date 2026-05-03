extends GutTest

var registry: EntityDefRegistry
var db: GameStateDB


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	registry = EntityDefRegistry.new()
	db = GameStateDB.new()


# New v4 co-located shape: each desires entry is an object with weight + decay.
func test_spawn_materializes_desire_decay_from_inline_decay_field() -> void:
	registry.register(&"tcp_test:critter", {
		"id": "tcp_test:critter",
		"name": "Critter",
		"desires": {
			"warmth": {"weight": 500, "decay": -2},
			"hunger": {"weight": 600, "decay":  0},
		},
		"body_capabilities": {"walks": {}},
		"body_geometry": {"size_ru": 1},
		"senses": {"sight": 186, "hearing": 186, "smell": 186, "touch": 32},
	})

	var id: int = registry.spawn(&"tcp_test:critter", db)

	assert_true(db.has_component(id, &"desire_decay"),
		"desire_decay component should be set on spawned entity")
	var decay: Dictionary = db.get_component(id, &"desire_decay")
	assert_eq(decay.get(&"warmth"), -2, "warmth decay rate from inline field")
	assert_eq(decay.get(&"hunger"), 0, "hunger decay rate from inline field")

	# Personality weight comes from the same entry's `weight`.
	assert_true(db.has_component(id, &"personality"),
		"personality should still be materialized")
	var personality: Dictionary = db.get_component(id, &"personality")
	assert_eq(personality.get(&"warmth_weight"), 500,
		"weight pulled from inline weight field")


# Phase 1 backwards compat: a v3-shaped recipe (bare-int desires, no inline decay)
# still loads with implicit decay=0. Lets phase 1 land without breaking the
# existing cat.jsonc/ferret.jsonc on disk; phase 2 rewrites those recipes and
# tightens the validator to forbid bare-int entries.
func test_spawn_tolerates_bare_int_desires_with_implicit_zero_decay() -> void:
	registry.register(&"tcp_test:legacy", {
		"id": "tcp_test:legacy",
		"name": "Legacy",
		"desires": {"warmth": 500, "hunger": 600},   # v3 shape
		"body_capabilities": {"walks": {}},
		"body_geometry": {"size_ru": 1},
		"senses": {"sight": 186, "hearing": 186, "smell": 186, "touch": 32},
	})

	var id: int = registry.spawn(&"tcp_test:legacy", db)

	# Legacy entries get a desire_decay component with all zeros — preserves
	# existing behavior (no decay) while making the runtime shape uniform.
	assert_true(db.has_component(id, &"desire_decay"),
		"v3 recipes still materialize desire_decay (all zeros)")
	var decay: Dictionary = db.get_component(id, &"desire_decay")
	assert_eq(decay.get(&"warmth"), 0, "v3 implicit decay")
	assert_eq(decay.get(&"hunger"), 0, "v3 implicit decay")
	# Personality weight from the bare int.
	var personality: Dictionary = db.get_component(id, &"personality")
	assert_eq(personality.get(&"warmth_weight"), 500)


func test_spawn_skips_desire_decay_when_recipe_lacks_desires() -> void:
	registry.register(&"tcp_test:arm", {
		"id": "tcp_test:arm",
		"name": "Arm",
		# No desires block at all (arms don't decay).
		"states": {"idle": {}},
	})

	var id: int = registry.spawn(&"tcp_test:arm", db)

	assert_false(db.has_component(id, &"desire_decay"),
		"arms with no desires must not carry desire_decay")
