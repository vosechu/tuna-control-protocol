extends GutTest


# AI-DEV: AI **MUST NOT** edit these tests to keep them green by changing the
# assertions. They test the validator's contract: legacy fields rejected, new
# required fields enforced.


func test_valid_species_def_passes():
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {
		"id": "test:cat",
		"desires": {"warmth": 500},
		"body_capabilities": {"walks": {}},
		"body_geometry": {"size_ru": 2},
		"senses": {"sight": 186, "hearing": 186, "smell": 186, "touch": 64},
	}
	assert_true(validator.is_valid_species(def))


func test_missing_desires_rejected():
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {
		"id": "test:cat",
		"body_capabilities": {"walks": {}},
		"body_geometry": {"size_ru": 2},
	}
	assert_false(validator.is_valid_species(def))
	assert_push_error("missing required field: desires")


func test_missing_body_capabilities_rejected():
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {
		"id": "test:cat",
		"desires": {"warmth": 500},
		"body_geometry": {"size_ru": 2},
	}
	assert_false(validator.is_valid_species(def))
	assert_push_error("missing required field: body_capabilities")


func test_missing_body_geometry_rejected():
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {
		"id": "test:cat",
		"desires": {"warmth": 500},
		"body_capabilities": {"walks": {}},
	}
	assert_false(validator.is_valid_species(def))
	assert_push_error("missing required field: body_geometry")


func test_legacy_traversal_field_rejected():
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {
		"id": "test:legacy_cat",
		"desires": {"warmth": 500},
		"traversal": ["WALK"],
	}
	assert_false(validator.is_valid_species(def))
	assert_push_error("uses legacy `traversal`")


func test_legacy_max_jump_height_ru_rejected():
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {
		"id": "test:legacy_cat",
		"desires": {"warmth": 500},
		"body_capabilities": {"walks": {}},
		"body_geometry": {"size_ru": 2},
		"max_jump_height_ru": 3,
	}
	assert_false(validator.is_valid_species(def))
	assert_push_error("uses legacy `max_jump_height_ru`")


func test_non_species_def_passes_through():
	# Objects are loaded via the same jsonc pipeline; validator should
	# ignore defs that don't claim to be species.
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {"id": "test:box", "object_type_id": "box"}
	assert_true(validator.is_valid_species(def))


func test_missing_senses_rejected():
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {
		"id": "test:no_senses_species",
		"desires": {"warmth": 500},
		"body_capabilities": {"walks": {}},
		"body_geometry": {"size_ru": 2},
	}
	assert_false(validator.is_valid_species(def))
	assert_push_error("missing required field: senses")
