extends GutTest

var _db: GameStateDB
var _c: Contentment


func before_each() -> void:
	_db = GameStateDB.new()
	_c = Contentment.new(_db)


func test_override_sets_satisfied_true_despite_low_desires() -> void:
	# AI-DEV: Proves the debug_force_satisfied component short-circuits the
	# normal threshold rule. Without this, a Shift+F1 debug toggle couldn't
	# force contentment on a sad cat for HUM chain testing.
	var id: int = _db.create_entity()
	_db.set_component(id, &"desires", {
		&"warmth": 100, &"comfort": 100, &"hunger": 100, &"attention": 100
	})
	_db.set_component(id, &"debug_force_satisfied", {&"active": 1})
	_c.evaluate_all()
	assert_eq(_db.get_field(id, &"contentment", &"is_satisfied"), 1,
		"Debug override must force is_satisfied = 1")


func test_no_override_follows_normal_rule() -> void:
	# AI-DEV: Negative control — without the override component, low desires
	# must still produce is_satisfied = 0. Guards against the override branch
	# being incorrectly entered when the component is absent.
	var id: int = _db.create_entity()
	_db.set_component(id, &"desires", {
		&"warmth": 100, &"comfort": 100, &"hunger": 100, &"attention": 100
	})
	_c.evaluate_all()
	assert_eq(_db.get_field(id, &"contentment", &"is_satisfied"), 0,
		"No override + all desires low => unsatisfied")


func test_override_removed_reverts_on_next_tick() -> void:
	# AI-DEV: The override must not be sticky. Removing the component and
	# re-evaluating must fall back to the normal threshold rule — otherwise
	# a one-time debug toggle would latch a cat into permanent contentment.
	var id: int = _db.create_entity()
	_db.set_component(id, &"desires", {
		&"warmth": 100, &"comfort": 100, &"hunger": 100, &"attention": 100
	})
	_db.set_component(id, &"debug_force_satisfied", {&"active": 1})
	_c.evaluate_all()
	_db.remove_component(id, &"debug_force_satisfied")
	_c.evaluate_all()
	assert_eq(_db.get_field(id, &"contentment", &"is_satisfied"), 0)
