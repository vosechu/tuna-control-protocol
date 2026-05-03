extends GutTest

var validator: SpeciesSchemaValidator


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	validator = SpeciesSchemaValidator.new()


func _base_recipe() -> Dictionary:
	return {
		"id": "tcp_test:critter",
		"schema_version": 4,
		"desires": {"warmth": {"weight": 500, "decay": -2}},
		"body_capabilities": {"walks": {"speed_px_per_tick": 2}},
		"body_geometry": {"size_ru": 1},
		"senses": {"sight": 186, "hearing": 186, "smell": 186, "touch": 32},
	}


func test_accepts_walks_with_speed() -> void:
	assert_true(validator.is_valid_species(_base_recipe()),
		"body_capabilities.walks with speed_px_per_tick passes")


func test_rejects_walks_without_speed() -> void:
	var recipe: Dictionary = _base_recipe()
	recipe["body_capabilities"]["walks"] = {}
	assert_false(validator.is_valid_species(recipe),
		"body_capabilities.walks without speed_px_per_tick must be rejected")
	assert_push_error("speed_px_per_tick")


func test_no_walks_no_speed_required() -> void:
	var recipe: Dictionary = _base_recipe()
	# A capability without `walks` (e.g. a stationary entity) doesn't need speed
	recipe["body_capabilities"] = {"jumps": {"max_height_ru": 3}}
	assert_true(validator.is_valid_species(recipe),
		"no walks block means no speed_px_per_tick required")
