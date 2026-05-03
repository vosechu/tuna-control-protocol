extends GutTest

# AI-DEV: Locks in the contract for add_field_subset — applies a per-entity
# delta in one call so per-species decay loops don't have to call set_field
# 1000× per tick. The test asserts: deltas land on the right entities, missing
# components are skipped (not asserted-out), and dirty notifications fire only
# for entities that actually changed.

var db: GameStateDB


func before_each() -> void:
	db = GameStateDB.new()


func test_applies_per_entity_deltas() -> void:
	var a: int = db.create_entity()
	var b: int = db.create_entity()
	var c: int = db.create_entity()
	db.set_component(a, &"desires", {&"warmth": 500})
	db.set_component(b, &"desires", {&"warmth": 600})
	db.set_component(c, &"desires", {&"warmth": 700})

	db.add_field_subset(&"desires", &"warmth", {a: -2, b: -5, c: 0})

	assert_eq(db.get_field(a, &"desires", &"warmth"), 498)
	assert_eq(db.get_field(b, &"desires", &"warmth"), 595)
	assert_eq(db.get_field(c, &"desires", &"warmth"), 700)


func test_skips_entities_missing_the_component() -> void:
	var a: int = db.create_entity()
	var b: int = db.create_entity()
	db.set_component(a, &"desires", {&"warmth": 500})
	# b has no `desires` component at all.

	db.add_field_subset(&"desires", &"warmth", {a: -10, b: -10})

	assert_eq(db.get_field(a, &"desires", &"warmth"), 490)
	assert_false(db.has_component(b, &"desires"),
		"missing component must remain absent (no implicit creation)")


func test_skips_entities_missing_the_field() -> void:
	var a: int = db.create_entity()
	# desires has hunger but not warmth.
	db.set_component(a, &"desires", {&"hunger": 800})

	db.add_field_subset(&"desires", &"warmth", {a: -10})

	assert_false(db.get_component(a, &"desires").has(&"warmth"),
		"missing field must remain absent (no implicit creation)")


func test_empty_dict_is_noop() -> void:
	var a: int = db.create_entity()
	db.set_component(a, &"desires", {&"warmth": 500})

	db.add_field_subset(&"desires", &"warmth", {})

	assert_eq(db.get_field(a, &"desires", &"warmth"), 500)


func test_dirty_notification_only_for_mutated_entities() -> void:
	var a: int = db.create_entity()
	var b: int = db.create_entity()
	db.set_component(a, &"desires", {&"warmth": 500})
	# b has no desires component — should not be notified.

	var notified: Array[int] = []
	var cb := func(eid: int) -> void: notified.append(eid)
	db.watch(&"desires", cb)
	db.add_field_subset(&"desires", &"warmth", {a: -10, b: -10})
	db.flush_notifications()

	assert_eq(notified, [a],
		"only entities that actually mutated should be notified")


func test_zero_delta_still_marks_dirty() -> void:
	# Mirrors set_field/add_field semantics: a write is a write, even if value
	# is unchanged. Suppressing zero-delta notifications would diverge from
	# the rest of the API and complicate consumer reasoning.
	var a: int = db.create_entity()
	db.set_component(a, &"desires", {&"warmth": 500})

	var notified: Array[int] = []
	var cb := func(eid: int) -> void: notified.append(eid)
	db.watch(&"desires", cb)
	db.add_field_subset(&"desires", &"warmth", {a: 0})
	db.flush_notifications()

	assert_eq(notified, [a])
