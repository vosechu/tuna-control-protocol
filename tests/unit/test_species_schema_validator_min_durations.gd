extends GutTest

var validator: SpeciesSchemaValidator


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	validator = SpeciesSchemaValidator.new()


func _base_recipe_with_ambient() -> Dictionary:
	return {
		"id": "tcp_test:critter",
		"schema_version": 4,
		"desires": {"warmth": {"weight": 500, "decay": -2}},
		"body_capabilities": {"walks": {"speed_px_per_tick": 2}},
		"body_geometry": {"size_ru": 1},
		"senses": {"sight": 186, "hearing": 186, "smell": 186, "touch": 32},
		"ambient_states": {
			"warm": [
				{"state": "IDLE", "weight": 10, "min_duration_ticks": 30},
			],
			"cold": [
				{"state": "IDLE", "weight": 10, "min_duration_ticks": 30},
			],
		},
		"special_states": {"STARTLED": {"min_duration_ticks": 10}},
	}


func test_accepts_complete_ambient_states() -> void:
	assert_true(validator.is_valid_species(_base_recipe_with_ambient()),
		"all min_duration_ticks declared, special_states present, passes")


func test_rejects_ambient_entry_missing_min_duration_ticks() -> void:
	var recipe: Dictionary = _base_recipe_with_ambient()
	recipe["ambient_states"]["warm"].append(
		{"state": "GROOMING", "weight": 5}
	)
	assert_false(validator.is_valid_species(recipe),
		"ambient_states entry without min_duration_ticks must be rejected")
	assert_push_error("missing `min_duration_ticks`")


func test_rejects_ambient_states_without_special_states() -> void:
	var recipe: Dictionary = _base_recipe_with_ambient()
	recipe.erase("special_states")
	assert_false(validator.is_valid_species(recipe),
		"ambient_states present without special_states must be rejected")
	assert_push_error("missing `special_states`")


func test_rejects_special_state_missing_min_duration_ticks() -> void:
	var recipe: Dictionary = _base_recipe_with_ambient()
	recipe["special_states"]["STARTLED"] = {}
	assert_false(validator.is_valid_species(recipe),
		"special_states entry without min_duration_ticks must be rejected")
	assert_push_error("special_states.STARTLED missing")
