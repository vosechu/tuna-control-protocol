extends GutTest


func test_synthetic_species_loads_and_spawns_animated_animal():
	# Load the fixture mod in isolation — no engine changes needed
	var loader := ModLoader.new()
	var fixture_result: Dictionary = loader.load_all(
		"res://tests/fixtures/"
	)
	var entity_defs: EntityDefRegistry = fixture_result["entity_defs"]

	assert_true(
		entity_defs.has_entity(&"tcp_test_species:test_creature"),
		"Fixture recipe must load without engine changes"
	)

	var db := GameStateDB.new()
	var entity_id: int = entity_defs.spawn(
		&"tcp_test_species:test_creature", db,
		{ &"position": { &"x": 0, &"y": 0 } }
	)

	# Assert core components projected from recipe
	assert_true(db.has_component(entity_id, &"species"))
	assert_true(db.has_component(entity_id, &"desires"))
	assert_true(db.has_component(entity_id, &"sprite_config"))
	assert_true(db.has_component(entity_id, &"ambient_states"))
	assert_true(db.has_component(entity_id, &"hud_color"))
	assert_true(db.has_component(entity_id, &"ai_state"))

	# Sprite config round-trips
	var config: Dictionary = db.get_component(entity_id, &"sprite_config")
	assert_true(config.has("animations"))
	assert_true(config["animations"].has("IDLE"))


func test_synthetic_species_is_rejected_when_missing_desires():
	# Compose a recipe missing `desires` and feed it directly to validator
	var validator := SpeciesSchemaValidator.new()
	validator.add_required_field("sprite_config")
	validator.add_required_field("ambient_states")
	validator.add_required_field("hud_color")
	var bad_def: Dictionary = {
		"id": "bad:creature",
		"body_capabilities": {"walks": {}},
		"body_geometry": {"size_ru": 1},
		"hud_color": [0.5, 0.5, 0.5],
		"sprite_config": {},
		"ambient_states": {},
	}
	assert_false(validator.is_valid_species(bad_def))
	assert_push_error("missing required field: desires")
