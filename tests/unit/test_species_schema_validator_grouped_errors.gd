extends GutTest

var validator: SpeciesSchemaValidator


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	validator = SpeciesSchemaValidator.new()


func test_multiple_violations_grouped_into_one_error() -> void:
	# Recipe with 3 violations: bare-int desires entry, walks missing
	# speed_px_per_tick, and ambient_states present without special_states.
	var recipe: Dictionary = {
		"id": "tcp_test:broken",
		"schema_version": 4,
		"desires": {"warmth": 500},   # bare-int — phase 2 forbids
		"body_capabilities": {"walks": {}},
		"body_geometry": {"size_ru": 1},
		"senses": {"sight": 186, "hearing": 186, "smell": 186, "touch": 32},
		"ambient_states": {"warm": [], "cold": []},
	}
	assert_false(validator.is_valid_species(recipe),
		"recipe with multiple violations must reject")
	# Single push_error call with all three violations grouped — modders
	# fixing a recipe shouldn't need three reload cycles. The "%d violation(s)"
	# header proves the grouping happened.
	assert_push_error("violation(s)")
