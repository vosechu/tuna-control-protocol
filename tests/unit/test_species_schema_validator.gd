extends GutTest


func test_valid_species_def_passes():
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {
		"id": "test:cat",
		"desires": {"warmth": 500},
		"traversal": ["WALK"],
	}
	assert_true(validator.is_valid_species(def))


func test_missing_desires_rejected():
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {
		"id": "test:cat",
		"traversal": ["WALK"],
	}
	assert_false(validator.is_valid_species(def))
	assert_push_error("missing required field: desires")


func test_missing_traversal_rejected():
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {
		"id": "test:cat",
		"desires": {"warmth": 500},
	}
	assert_false(validator.is_valid_species(def))
	assert_push_error("missing required field: traversal")


func test_non_species_def_passes_through():
	# Objects are loaded via the same jsonc pipeline; validator should
	# ignore defs that don't claim to be species.
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {"id": "test:box", "object_type_id": "box"}
	assert_true(validator.is_valid_species(def))
