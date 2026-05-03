extends GutTest

var validator: SpeciesSchemaValidator


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	validator = SpeciesSchemaValidator.new()


# Baseline recipe in v4 co-located shape — every desires entry is {weight, decay}.
func _base_recipe() -> Dictionary:
	return {
		"id": "tcp_test:critter",
		"schema_version": 4,
		"desires": {
			"warmth": {"weight": 500, "decay": -2},
			"hunger": {"weight": 600, "decay":  0},
		},
		"body_capabilities": {"walks": {"speed_px_per_tick": 2}},
		"body_geometry": {"size_ru": 1},
		"senses": {"sight": 186, "hearing": 186, "smell": 186, "touch": 32},
	}


func test_accepts_v4_co_located_desires_shape() -> void:
	var recipe: Dictionary = _base_recipe()
	assert_true(validator.is_valid_species(recipe),
		"v4 co-located {weight, decay} entries pass validation")


func test_rejects_bare_int_desires_entry() -> void:
	var recipe: Dictionary = _base_recipe()
	# Legacy v3 shape: bare int. Phase 2 rejects this so future recipes must
	# adopt the co-located form. Phase 1's loader still tolerated bare-ints
	# for the cross-phase boot; phase 2 closes that door.
	recipe["desires"] = {"warmth": 500, "hunger": 600}
	assert_false(validator.is_valid_species(recipe),
		"bare-int desires entries must be rejected at v4")
	assert_push_error("desires.warmth must be an object")


func test_rejects_desires_entry_missing_weight() -> void:
	var recipe: Dictionary = _base_recipe()
	recipe["desires"] = {
		"warmth": {"decay": -2},   # weight missing
		"hunger": {"weight": 600, "decay": 0},
	}
	assert_false(validator.is_valid_species(recipe),
		"every desires entry must declare `weight`")
	assert_push_error("missing required field `weight`")


func test_rejects_desires_entry_missing_decay() -> void:
	var recipe: Dictionary = _base_recipe()
	recipe["desires"] = {
		"warmth": {"weight": 500},   # decay missing
	}
	assert_false(validator.is_valid_species(recipe),
		"every desires entry must declare `decay` (no magic defaults)")
	assert_push_error("missing required field `decay`")


func test_rejects_positive_decay_value() -> void:
	var recipe: Dictionary = _base_recipe()
	recipe["desires"] = {
		"warmth": {"weight": 500, "decay": 5},   # positive — forbidden
	}
	assert_false(validator.is_valid_species(recipe),
		"decay value > 0 is forbidden — decay-only mechanic")
	assert_push_error("decay-only mechanic")


func test_rejects_non_int_weight_or_decay() -> void:
	var recipe: Dictionary = _base_recipe()
	recipe["desires"] = {
		"warmth": {"weight": "high", "decay": -2},
	}
	assert_false(validator.is_valid_species(recipe),
		"weight must be int")
	assert_push_error("desires.warmth.weight must be int")
