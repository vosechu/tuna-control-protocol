extends GutTest

# Outer iteration, trigger gating, value-source canonicalization,
# intensity clamping, and _read_value runtime guard. Modifier behavior
# lives in test_sensory_emission_modifiers; radius_px contract in
# test_sensory_emission_radius.

var _db: GameStateDB
var _system: SensoryEmissionSystem


func before_each() -> void:
	_db = GameStateDB.new()
	_system = SensoryEmissionSystem.new(_db, _output_config())


func _output_config() -> Dictionary:
	return {
		&"channels": {&"acoustic": {&"falloff": &"quadratic"}},
		&"outputs": {&"purr": {&"channel": &"acoustic"}},
	}


# Materialized form: value sources are {kind: literal|ref, ...} dicts.
# Tests construct this directly because we're testing the runtime, not
# the materializer (test_entity_def_registry_sensory_emissions covers it).
func _emission_def_literal(base_intensity: int, base_radius_ru: int) -> Dictionary:
	return {
		&"trigger": {
			&"component": &"contentment",
			&"field": &"is_satisfied",
			&"equals": 1,
		},
		&"base_intensity": {&"kind": &"literal", &"value": base_intensity},
		&"modifiers": [] as Array[Dictionary],
		&"base_radius_ru": {&"kind": &"literal", &"value": base_radius_ru},
	}


func _spawn_purrer(satisfied: int, base_intensity: int, base_radius_ru: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"contentment", {&"is_satisfied": satisfied})
	_db.set_component(id, &"sensory_emissions",
		{&"purr": _emission_def_literal(base_intensity, base_radius_ru)})
	_db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
	return id


func test_tick_no_op_when_no_entities() -> void:
	_system.tick()  # must not crash
	assert_true(true)


func test_satisfied_writes_full_intensity() -> void:
	var id: int = _spawn_purrer(1, 1000, 6)
	_system.tick()
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 1000)


func test_unsatisfied_writes_both_intensity_and_radius_zero() -> void:
	# AI-DEV: regression guard. The bridge's original test asserted both
	# fields go to 0; if the runner returns early before writing
	# radius_px on trigger fail, a stale radius from a previous tick
	# charges the wrong HUM. Both assertions required.
	var id: int = _spawn_purrer(0, 1000, 6)
	_db.set_field(id, &"purr", &"intensity", 999)   # prior value
	_db.set_field(id, &"purr", &"radius_px", 48)    # prior value
	_system.tick()
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 0)
	assert_eq(_db.get_field(id, &"purr", &"radius_px"), 0)


func test_trigger_component_absent_writes_zero() -> void:
	var id: int = _db.create_entity()
	_db.set_component(id, &"sensory_emissions",
		{&"purr": _emission_def_literal(1000, 6)})
	_db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
	# No contentment component
	_system.tick()
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 0)


func test_one_entity_two_outputs_writes_both_without_clobber() -> void:
	# Synthetic second output to verify inner-loop iteration.
	var id: int = _db.create_entity()
	_db.set_component(id, &"contentment", {&"is_satisfied": 1})
	_db.set_component(id, &"sensory_emissions", {
		&"purr": _emission_def_literal(800, 6),
		&"test_pulse": _emission_def_literal(400, 4),
	})
	_db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
	_db.set_component(id, &"test_pulse", {&"intensity": 0, &"radius_px": 0})

	var cfg: Dictionary = _output_config()
	(cfg[&"outputs"] as Dictionary)[&"test_pulse"] = {&"channel": &"acoustic"}
	var system := SensoryEmissionSystem.new(_db, cfg)
	system.tick()

	assert_eq(_db.get_field(id, &"purr", &"intensity"), 800)
	assert_eq(_db.get_field(id, &"test_pulse", &"intensity"), 400)


func test_multiple_entities_one_output_each() -> void:
	var id_a: int = _spawn_purrer(1, 100, 6)
	var id_b: int = _spawn_purrer(1, 200, 6)
	_system.tick()
	assert_eq(_db.get_field(id_a, &"purr", &"intensity"), 100)
	assert_eq(_db.get_field(id_b, &"purr", &"intensity"), 200)


func test_ref_form_base_intensity() -> void:
	var id: int = _db.create_entity()
	_db.set_component(id, &"contentment", {&"is_satisfied": 1})
	_db.set_component(id, &"purr_quality", {&"rate": 1500})
	var def: Dictionary = _emission_def_literal(0, 6)
	def[&"base_intensity"] = {
		&"kind": &"ref", &"component": &"purr_quality", &"field": &"rate",
	}
	_db.set_component(id, &"sensory_emissions", {&"purr": def})
	_db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
	_system.tick()
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 1500)


func test_unknown_value_kind_pushes_error() -> void:
	var id: int = _db.create_entity()
	_db.set_component(id, &"contentment", {&"is_satisfied": 1})
	var def: Dictionary = _emission_def_literal(0, 6)
	def[&"base_intensity"] = {&"kind": &"bogus", &"value": 0}
	_db.set_component(id, &"sensory_emissions", {&"purr": def})
	_db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
	_system.tick()
	assert_push_error("unknown value source kind")


func test_system_does_not_read_species() -> void:
	# AI-DEV: regression guard, ported from
	# test_contentment_purr_bridge.test_bridge_does_not_read_species.
	# Recipe-driven spawn would catch this implicitly, but the explicit
	# test is cheap.
	var id: int = _spawn_purrer(1, 7, 0)
	_system.tick()
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 7)
