extends GutTest

# Materialization invariants for `sensory_emissions` in species recipes.
# Validates: recursive StringName key conversion, value-source
# canonicalization to {kind: literal|ref, ...}, modifier priority sort,
# per-output component initialization.

var _db: GameStateDB
var _registry: EntityDefRegistry


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	_db = GameStateDB.new()
	_registry = EntityDefRegistry.new()


func _register_minimal_species(emissions: Dictionary) -> StringName:
	var def: Dictionary = {
		"id": "test:species",
		"name": "Test",
		"schema_version": 4,
		"senses": {"sight": 100, "hearing": 100, "smell": 100, "touch": 100},
		"desires": {"warmth": {"weight": 500, "decay": 0}},
		"ambient_states": {"warm": [], "cold": []},
		"special_states": {},
		"body_capabilities": {"walks": {"speed_px_per_tick": 2}},
		"body_geometry": {"size_ru": 2},
		"sprite_config": {},
		"hud_color": [1.0, 1.0, 1.0],
		"sensory_emissions": emissions,
	}
	_registry.register(&"test:species", def)
	return &"test:species"


func test_string_keys_become_stringname_recursively() -> void:
	var emissions: Dictionary = {
		"purr": {
			"trigger": {
				"component": "contentment", "field": "is_satisfied", "equals": 1,
			},
			"base_intensity": 1000,
			"modifiers": [],
			"base_radius_ru": 6,
		},
	}
	_register_minimal_species(emissions)
	var id: int = _registry.spawn(&"test:species", _db)
	var component: Dictionary = _db.get_component(id, &"sensory_emissions")
	assert_true(component.has(&"purr"), "output_name key is StringName")
	var purr: Dictionary = component[&"purr"]
	assert_true(purr.has(&"trigger"), "trigger key is StringName")
	var trigger: Dictionary = purr[&"trigger"]
	assert_true(trigger.has(&"component"),
		"nested trigger.component key is StringName")
	assert_eq(trigger[&"component"], &"contentment",
		"trigger.component value is StringName")


func test_int_literal_base_intensity_canonicalized() -> void:
	var emissions: Dictionary = {
		"purr": {
			"trigger": {
				"component": "contentment", "field": "is_satisfied", "equals": 1,
			},
			"base_intensity": 1000,
			"modifiers": [],
			"base_radius_ru": 6,
		},
	}
	_register_minimal_species(emissions)
	var id: int = _registry.spawn(&"test:species", _db)
	var component: Dictionary = _db.get_component(id, &"sensory_emissions")
	var bi: Dictionary = component[&"purr"][&"base_intensity"]
	assert_eq(bi[&"kind"], &"literal")
	assert_eq(bi[&"value"], 1000)


func test_ref_form_base_intensity_canonicalized() -> void:
	var emissions: Dictionary = {
		"purr": {
			"trigger": {
				"component": "contentment", "field": "is_satisfied", "equals": 1,
			},
			"base_intensity": {"component": "purr_quality", "field": "rate"},
			"modifiers": [],
			"base_radius_ru": 6,
		},
	}
	_register_minimal_species(emissions)
	var id: int = _registry.spawn(&"test:species", _db)
	var component: Dictionary = _db.get_component(id, &"sensory_emissions")
	var bi: Dictionary = component[&"purr"][&"base_intensity"]
	assert_eq(bi[&"kind"], &"ref")
	assert_eq(bi[&"component"], &"purr_quality")
	assert_eq(bi[&"field"], &"rate")


func test_modifiers_sorted_by_priority_ascending() -> void:
	var emissions: Dictionary = {
		"purr": {
			"trigger": {
				"component": "contentment", "field": "is_satisfied", "equals": 1,
			},
			"base_intensity": 1000,
			"modifiers": [
				{
					"id": "test:hi", "component": "a", "field": "x",
					"op": "factor", "priority": 10,
				},
				{
					"id": "test:lo", "component": "b", "field": "y",
					"op": "factor", "priority": 0,
				},
			],
			"base_radius_ru": 6,
		},
	}
	_register_minimal_species(emissions)
	var id: int = _registry.spawn(&"test:species", _db)
	var component: Dictionary = _db.get_component(id, &"sensory_emissions")
	var modifiers: Array = component[&"purr"][&"modifiers"]
	assert_eq(modifiers.size(), 2)
	assert_eq((modifiers[0] as Dictionary)[&"id"], &"test:lo",
		"priority 0 sorts before priority 10")
	assert_eq((modifiers[1] as Dictionary)[&"id"], &"test:hi")


func test_modifiers_with_tied_priority_preserve_list_order() -> void:
	var emissions: Dictionary = {
		"purr": {
			"trigger": {
				"component": "contentment", "field": "is_satisfied", "equals": 1,
			},
			"base_intensity": 1000,
			"modifiers": [
				{
					"id": "test:first", "component": "a", "field": "x", "op": "factor",
				},
				{
					"id": "test:second", "component": "b", "field": "y", "op": "factor",
				},
			],
			"base_radius_ru": 6,
		},
	}
	_register_minimal_species(emissions)
	var id: int = _registry.spawn(&"test:species", _db)
	var component: Dictionary = _db.get_component(id, &"sensory_emissions")
	var modifiers: Array = component[&"purr"][&"modifiers"]
	assert_eq((modifiers[0] as Dictionary)[&"id"], &"test:first")
	assert_eq((modifiers[1] as Dictionary)[&"id"], &"test:second")


func test_per_output_component_initialized_to_zero() -> void:
	var emissions: Dictionary = {
		"purr": {
			"trigger": {
				"component": "contentment", "field": "is_satisfied", "equals": 1,
			},
			"base_intensity": 1000,
			"modifiers": [],
			"base_radius_ru": 6,
		},
	}
	_register_minimal_species(emissions)
	var id: int = _registry.spawn(&"test:species", _db)
	assert_true(_db.has_component(id, &"purr"))
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 0)
	assert_eq(_db.get_field(id, &"purr", &"radius_px"), 0)
