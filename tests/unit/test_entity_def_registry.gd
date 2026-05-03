extends GutTest

var _registry: EntityDefRegistry


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
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


func test_has_body_capabilities_true_for_species():
	_registry.register(&"tcp_cats:cat", {
		"id": "cat",
		"body_capabilities": {"walks": {}, "jumps": {"max_height_ru": 3}},
	})
	assert_true(_registry.has_body_capabilities(&"tcp_cats:cat"))


func test_has_body_capabilities_false_for_object():
	_registry.register(
		&"tcp_tuna:tuna_can",
		{"id": "tuna_can", "states": {}},
	)
	assert_false(_registry.has_body_capabilities(&"tcp_tuna:tuna_can"))


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


func test_get_body_capabilities_returns_recipe_dict():
	_registry.register(&"tcp_cats:cat", {
		"id": "cat",
		"body_capabilities": {
			"walks": {},
			"jumps": {"max_height_ru": 3},
			"drops": {"max_height_ru": 5},
		},
	})
	var caps: Dictionary = _registry.get_body_capabilities(&"tcp_cats:cat")
	assert_eq(caps.size(), 3)
	assert_true(caps.has("walks"))
	assert_eq(caps["jumps"]["max_height_ru"], 3)


func test_get_body_geometry_returns_recipe_dict():
	_registry.register(&"tcp_cats:cat", {
		"id": "cat",
		"body_geometry": {"size_ru": 2},
	})
	var geom: Dictionary = _registry.get_body_geometry(&"tcp_cats:cat")
	assert_eq(geom["size_ru"], 2)


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


# --- spawn() tests ---


func test_spawn_creates_entity_with_species_component():
	_registry.register(&"tcp_cats:cat", _make_cat_def())
	var db := GameStateDB.new()
	var id: int = _registry.spawn(
		&"tcp_cats:cat", db,
		{&"name": &"Mochi", &"position": {&"x": 1000, &"y": 2000}},
	)
	assert_ne(id, GameStateDB.INVALID_ID)
	assert_true(db.has_component(id, &"species"))
	var species: Dictionary = db.get_component(id, &"species")
	assert_eq(species[&"id"], &"tcp_cats:cat")
	assert_eq(species[&"name"], &"Mochi")


func test_spawn_sets_desires_from_personality_ranges():
	_registry.register(&"tcp_cats:cat", _make_cat_def())
	var db := GameStateDB.new()
	var id: int = _registry.spawn(&"tcp_cats:cat", db, {})
	var personality: Dictionary = db.get_component(
		id, &"personality",
	)
	assert_gte(personality[&"warmth_weight"], 500)
	assert_lte(personality[&"warmth_weight"], 800)


func test_spawn_sets_ai_state_to_initial():
	_registry.register(&"tcp_cats:cat", _make_cat_def())
	var db := GameStateDB.new()
	var id: int = _registry.spawn(&"tcp_cats:cat", db, {})
	var ai: Dictionary = db.get_component(id, &"ai_state")
	assert_eq(ai[&"state"], &"idle")


func test_spawn_sets_position_from_overrides():
	_registry.register(&"tcp_cats:cat", _make_cat_def())
	var db := GameStateDB.new()
	var id: int = _registry.spawn(
		&"tcp_cats:cat", db,
		{&"position": {&"x": 5000, &"y": 3000}},
	)
	var pos: Dictionary = db.get_component(id, &"position")
	assert_eq(pos[&"x"], 5000)
	assert_eq(pos[&"y"], 3000)


func test_spawn_picks_random_variant():
	_registry.register(&"tcp_cats:cat", _make_cat_def())
	var db := GameStateDB.new()
	var variants_seen: Dictionary = {}
	for i in 20:
		var id: int = _registry.spawn(
			&"tcp_cats:cat", db, {},
		)
		var species: Dictionary = db.get_component(
			id, &"species",
		)
		variants_seen[species[&"variant"]] = true
	assert_gte(
		variants_seen.size(), 2,
		"Expected multiple variants across 20 spawns",
	)


func test_spawn_object_has_no_desires_component():
	_registry.register(
		&"tcp_tuna:tuna_can", _make_tuna_def(),
	)
	var db := GameStateDB.new()
	var id: int = _registry.spawn(
		&"tcp_tuna:tuna_can", db, {},
	)
	assert_false(db.has_component(id, &"desires"))
	assert_false(db.has_component(id, &"personality"))
	assert_true(db.has_component(id, &"object_state"))


func test_spawn_writes_senses_component():
	_registry.register(&"tcp_cats:cat", _make_cat_def())
	var db := GameStateDB.new()
	var id: int = _registry.spawn(&"tcp_cats:cat", db, {})
	assert_true(
		db.has_component(id, &"senses"),
		"Spawned cat must have `senses` component",
	)
	var senses: Dictionary = db.get_component(id, &"senses")
	assert_eq(
		senses.get(&"touch", -1), 64,
		"Touch range must round-trip from recipe to component",
	)
	assert_eq(
		senses.get(&"sight", -1), 186,
		"Sight range must round-trip from recipe to component",
	)


func _make_cat_def() -> Dictionary:
	return {
		"id": "cat", "name": "Cat",
		"desires": {
			"warmth": 700, "comfort": 700, "curiosity": 150,
		},
		"personality_ranges": {
			"warmth": [500, 800],
			"comfort": [600, 900],
			"curiosity": [100, 200],
		},
		"senses": {
			"sight": 186, "hearing": 186, "smell": 186, "touch": 64,
		},
		"physical": {"mass": 4000, "size_ru": 2},
		"strength": 3000,
		"body_capabilities": {
			"walks": {},
			"jumps": {"max_height_ru": 3},
			"drops": {"max_height_ru": 5},
		},
		"body_geometry": {"size_ru": 2},
		"variants": [
			"cat01", "cat02", "cat03", "cat04", "cat05",
		],
		"states": {"idle": {"advertisements": []}},
		"initial_state": "idle",
	}


func _make_tuna_def() -> Dictionary:
	return {
		"id": "tuna_can", "name": "Tuna Can",
		"states": {
			"sealed": {
				"advertisements": [
					{"type": "food", "strength": 800},
				],
			},
			"open": {
				"advertisements": [
					{"type": "food", "strength": 800},
				],
			},
			"empty": {"advertisements": []},
		},
		"initial_state": "sealed",
		"physical": {"mass": 400, "size_ru": 1},
	}
