extends GutTest

# AI-DEV: One assertion per push_error rejection path. Each rule in
# SensoryEmissionsSchemaValidator must have a test here. If you add a
# rule, add a test. The validator pushes ONE error per violation —
# tests with multiple substring claims rely on `get_errors()` lookup
# (see test_modifier_unknown_op below) since GUT consumes one error per
# `assert_push_error` call.

var _validator: SensoryEmissionsSchemaValidator


func before_each() -> void:
	var output_config: Dictionary = {
		&"channels": {&"acoustic": {&"falloff": &"quadratic"}},
		&"outputs": {&"purr": {&"channel": &"acoustic"}},
	}
	_validator = SensoryEmissionsSchemaValidator.new(output_config)


func _valid_emission() -> Dictionary:
	return {
		"trigger": {
			"component": "contentment",
			"field": "is_satisfied",
			"equals": 1,
		},
		"base_intensity": 1000,
		"modifiers": [],
		"base_radius_ru": 6,
	}


func test_valid_emission_passes() -> void:
	var ok: bool = _validator.validate({"purr": _valid_emission()})
	assert_true(ok)


func test_missing_base_intensity_rejected() -> void:
	var entry: Dictionary = _valid_emission()
	entry.erase("base_intensity")
	var ok: bool = _validator.validate({"purr": entry})
	assert_false(ok)
	assert_push_error("base_intensity")


func test_missing_base_radius_ru_rejected() -> void:
	var entry: Dictionary = _valid_emission()
	entry.erase("base_radius_ru")
	var ok: bool = _validator.validate({"purr": entry})
	assert_false(ok)
	assert_push_error("base_radius_ru")


func test_missing_modifiers_rejected() -> void:
	var entry: Dictionary = _valid_emission()
	entry.erase("modifiers")
	var ok: bool = _validator.validate({"purr": entry})
	assert_false(ok)
	assert_push_error("modifiers")


func test_trigger_missing_field_rejected() -> void:
	var entry: Dictionary = _valid_emission()
	(entry["trigger"] as Dictionary).erase("field")
	var ok: bool = _validator.validate({"purr": entry})
	assert_false(ok)
	assert_push_error("trigger")


func test_trigger_missing_equals_rejected() -> void:
	var entry: Dictionary = _valid_emission()
	(entry["trigger"] as Dictionary).erase("equals")
	var ok: bool = _validator.validate({"purr": entry})
	assert_false(ok)
	assert_push_error("trigger")


func test_trigger_non_int_equals_rejected() -> void:
	var entry: Dictionary = _valid_emission()
	(entry["trigger"] as Dictionary)["equals"] = "yes"
	var ok: bool = _validator.validate({"purr": entry})
	assert_false(ok)
	assert_push_error("equals")


func test_modifier_missing_id_rejected() -> void:
	var entry: Dictionary = _valid_emission()
	entry["modifiers"] = [{
		"component": "stress", "field": "level", "op": "factor",
	}]
	var ok: bool = _validator.validate({"purr": entry})
	assert_false(ok)
	assert_push_error("id")


func test_modifier_missing_component_rejected() -> void:
	var entry: Dictionary = _valid_emission()
	entry["modifiers"] = [{
		"id": "test:m", "field": "level", "op": "factor",
	}]
	var ok: bool = _validator.validate({"purr": entry})
	assert_false(ok)
	assert_push_error("component")


func test_modifier_unknown_op_rejected_with_known_set_listed() -> void:
	# AI-DEV: The error message names both the bad op and the known set so
	# the modder can fix it without diving into engine code. Manual
	# get_errors() inspection because GUT consumes one error per
	# `assert_push_error` call — we want to verify both substrings live in
	# a single error message, not that two errors fired.
	var entry: Dictionary = _valid_emission()
	entry["modifiers"] = [{
		"id": "test:m", "component": "stress",
		"field": "level", "op": "multiply",
	}]
	var ok: bool = _validator.validate({"purr": entry})
	assert_false(ok)
	var errs: Array = get_errors()
	var matched: bool = false
	for err: Variant in errs:
		var code: String = err.code
		if code.contains("multiply") and code.contains("factor"):
			err.handled = true
			matched = true
			break
	assert_true(matched, "expected single error mentioning both 'multiply' and 'factor'")


func test_modifier_non_int_priority_rejected() -> void:
	var entry: Dictionary = _valid_emission()
	entry["modifiers"] = [{
		"id": "test:m", "component": "stress",
		"field": "level", "op": "factor", "priority": "high",
	}]
	var ok: bool = _validator.validate({"purr": entry})
	assert_false(ok)
	assert_push_error("priority")


func test_duplicate_modifier_ids_within_emission_rejected() -> void:
	var entry: Dictionary = _valid_emission()
	entry["modifiers"] = [
		{"id": "test:m", "component": "a", "field": "x", "op": "factor"},
		{"id": "test:m", "component": "b", "field": "y", "op": "factor"},
	]
	var ok: bool = _validator.validate({"purr": entry})
	assert_false(ok)
	assert_push_error("duplicate")


func test_unknown_output_name_rejected() -> void:
	var ok: bool = _validator.validate({"unknown_output": _valid_emission()})
	assert_false(ok)
	assert_push_error("unknown_output")


func test_ref_form_with_non_string_component_rejected() -> void:
	var entry: Dictionary = _valid_emission()
	entry["base_intensity"] = {"component": 123, "field": "rate"}
	var ok: bool = _validator.validate({"purr": entry})
	assert_false(ok)
	assert_push_error("component")


func test_unresolved_component_ref_emits_warning_not_error() -> void:
	# AI-DEV: Typos surface as warnings (not errors) so a forward
	# reference to another mod's component doesn't reject the recipe.
	# GUT has no assert_push_warning helper — verify return value only.
	var entry: Dictionary = _valid_emission()
	entry["modifiers"] = [{
		"id": "test:typo", "component": "strss",
		"field": "level", "op": "factor",
	}]
	var ok: bool = _validator.validate({"purr": entry}, ["contentment"])
	assert_true(ok, "typo'd component is a warning, not a rejection")
