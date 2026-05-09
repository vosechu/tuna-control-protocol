extends GutTest

# Modifier composition: known ops, identity behavior, ordering, and the
# integer-truncation rounding contract. Uses synthetic test_dampener
# component so cat is not involved.

var _db: GameStateDB
var _system: SensoryEmissionSystem


func before_each() -> void:
	_db = GameStateDB.new()
	_system = SensoryEmissionSystem.new(_db, {
		&"channels": {&"acoustic": {&"falloff": &"quadratic"}},
		&"outputs": {&"purr": {&"channel": &"acoustic"}},
	})


func _spawn_with_modifier(
		modifier: Dictionary,
		modifier_value: int,
		base_intensity: int = 1000) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"contentment", {&"is_satisfied": 1})
	_db.set_component(id, &"test_dampener", {&"value": modifier_value})
	_db.set_component(id, &"sensory_emissions", {&"purr": {
		&"trigger": {
			&"component": &"contentment",
			&"field": &"is_satisfied",
			&"equals": 1,
		},
		&"base_intensity": {&"kind": &"literal", &"value": base_intensity},
		&"modifiers": [modifier] as Array[Dictionary],
		&"base_radius_ru": {&"kind": &"literal", &"value": 6},
	}})
	_db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
	return id


func test_factor_op() -> void:
	var id: int = _spawn_with_modifier(
		{
			&"id": &"test:m", &"component": &"test_dampener",
			&"field": &"value", &"op": &"factor",
		}, 500)
	_system.tick()
	# 1000 * 500 / 1000 = 500
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 500)


func test_inverse_factor_op() -> void:
	var id: int = _spawn_with_modifier(
		{
			&"id": &"test:m", &"component": &"test_dampener",
			&"field": &"value", &"op": &"inverse_factor",
		}, 250)
	_system.tick()
	# 1000 * (1000 - 250) / 1000 = 750
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 750)


func test_modifier_component_absent_is_identity() -> void:
	var id: int = _db.create_entity()
	_db.set_component(id, &"contentment", {&"is_satisfied": 1})
	# No test_dampener component
	_db.set_component(id, &"sensory_emissions", {&"purr": {
		&"trigger": {
			&"component": &"contentment",
			&"field": &"is_satisfied",
			&"equals": 1,
		},
		&"base_intensity": {&"kind": &"literal", &"value": 1000},
		&"modifiers": [{
			&"id": &"test:m", &"component": &"test_dampener",
			&"field": &"value", &"op": &"factor",
		}] as Array[Dictionary],
		&"base_radius_ru": {&"kind": &"literal", &"value": 6},
	}})
	_db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
	_system.tick()
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 1000)


func test_unknown_op_pushes_error_and_is_identity() -> void:
	var id: int = _spawn_with_modifier(
		{
			&"id": &"test:m", &"component": &"test_dampener",
			&"field": &"value", &"op": &"bogus",
		}, 500)
	_system.tick()
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 1000)
	assert_push_error("unknown modifier op")


func test_modifiers_compose_in_list_order() -> void:
	# Runtime iterates modifiers in the (already priority-sorted) list
	# order. Multiplicative ops happen to be commutative, so this test
	# asserts the chained result against a manually-computed reference
	# rather than swapping orders. When non-commutative ops land, add a
	# follow-up test that flips the order and asserts the diff.
	var id: int = _db.create_entity()
	_db.set_component(id, &"contentment", {&"is_satisfied": 1})
	_db.set_component(id, &"test_dampener", {&"value": 500})
	_db.set_component(id, &"test_other", {&"value": 200})
	_db.set_component(id, &"sensory_emissions", {&"purr": {
		&"trigger": {
			&"component": &"contentment",
			&"field": &"is_satisfied",
			&"equals": 1,
		},
		&"base_intensity": {&"kind": &"literal", &"value": 1000},
		&"modifiers": [
			{
				&"id": &"test:a", &"component": &"test_dampener",
				&"field": &"value", &"op": &"factor",
			},
			{
				&"id": &"test:b", &"component": &"test_other",
				&"field": &"value", &"op": &"inverse_factor",
			},
		] as Array[Dictionary],
		&"base_radius_ru": {&"kind": &"literal", &"value": 6},
	}})
	_db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
	_system.tick()
	# factor 500 first: 1000 * 500 / 1000 = 500
	# inverse_factor 200 next: 500 * (1000 - 200) / 1000 = 400
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 400)


func test_integer_truncation_rounds_toward_zero() -> void:
	# AI-DEV: pin the rounding contract. intensity * value / UNIT
	# truncates toward zero in GDScript int division. A future "fix" to
	# round() would change HUM charge rates measurably across thousands
	# of cats. Don't change unless deliberately altering balance.
	var id: int = _spawn_with_modifier(
		{
			&"id": &"test:m", &"component": &"test_dampener",
			&"field": &"value", &"op": &"factor",
		}, 999, 999)
	_system.tick()
	# 999 * 999 / 1000 = 998 (not 999; truncates)
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 998)
