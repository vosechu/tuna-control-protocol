extends GutTest

# AI-DEV: AI **MUST NOT** touch this test. If the test is failing, it is
# because you removed or broke code.

# SettledLifecycle is the minimum tracking helper for "this entity is
# legitimately resting at this host" — distinguishes intentional settled-in
# state from being stranded by a movement bug. Marker is a one-field
# &"settled_in" component on the joiner; the host_id field points back at
# the entity it's settled into. No relationship table required.


func test_enter_writes_settled_in_component_with_host_id() -> void:
	var db := GameStateDB.new()
	var lifecycle := SettledLifecycle.new(db)
	var host_id: int = db.create_entity()
	var joiner_id: int = db.create_entity()

	lifecycle.enter(joiner_id, host_id)

	assert_true(
		db.has_component(joiner_id, &"settled_in"),
		"enter must write the settled_in component on the joiner",
	)
	assert_eq(
		db.get_field(joiner_id, &"settled_in", &"host_id"), host_id,
		"settled_in.host_id must point at the host that was entered",
	)


func test_exit_removes_settled_in_component() -> void:
	var db := GameStateDB.new()
	var lifecycle := SettledLifecycle.new(db)
	var host_id: int = db.create_entity()
	var joiner_id: int = db.create_entity()
	lifecycle.enter(joiner_id, host_id)

	lifecycle.exit(joiner_id)

	assert_false(
		db.has_component(joiner_id, &"settled_in"),
		"exit must clear the settled_in component on the joiner",
	)


func test_is_settled_reports_membership() -> void:
	var db := GameStateDB.new()
	var lifecycle := SettledLifecycle.new(db)
	var joiner_id: int = db.create_entity()
	var host_id: int = db.create_entity()

	assert_false(
		lifecycle.is_settled(joiner_id),
		"freshly-created joiner is not settled",
	)
	lifecycle.enter(joiner_id, host_id)
	assert_true(
		lifecycle.is_settled(joiner_id),
		"after enter(), is_settled must report true",
	)
	lifecycle.exit(joiner_id)
	assert_false(
		lifecycle.is_settled(joiner_id),
		"after exit(), is_settled must report false again",
	)
