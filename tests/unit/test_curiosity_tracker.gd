extends GutTest

var _tracker: CuriosityTracker


func before_each() -> void:
	_tracker = CuriosityTracker.new()


# ── Tests ─────────────────────────────────────────────────────────────────────

func test_visiting_new_cell_is_novel():
	assert_true(_tracker.is_novel(42, 0, 100),
		"A never-visited entity must be novel")


func test_revisiting_within_cooldown_is_not_novel():
	_tracker.visit(42, 0)
	assert_false(_tracker.is_novel(42, 99, 100),
		"Entity visited at tick 0 must not be novel at tick 99 with cooldown 100")


func test_entity_becomes_novel_again_after_cooldown_expires():
	_tracker.visit(42, 0)
	assert_true(_tracker.is_novel(42, 101, 100),
		"Entity must become novel again after cooldown expires")


func test_multiple_entities_tracked_independently():
	_tracker.visit(1, 0)
	_tracker.visit(2, 0)
	assert_false(_tracker.is_novel(1, 50, 100),
		"Entity 1 must still be known within cooldown")
	assert_true(_tracker.is_novel(2, 50, 30),
		"Entity 2 must be novel with shorter cooldown (30) at tick 50")


func test_visit_at_exact_cooldown_boundary():
	_tracker.visit(99, 100)
	assert_true(_tracker.is_novel(99, 200, 100),
		"Visiting at exactly the cooldown boundary must be novel")



func test_short_cooldown_expires_before_long_cooldown():
	_tracker.visit(10, 0)
	var short_novel: bool = _tracker.is_novel(10, 31, 30)
	var long_novel: bool = _tracker.is_novel(10, 31, 200)
	assert_true(short_novel,
		"Short cooldown (30) must expire by tick 31")
	assert_false(long_novel,
		"Long cooldown (200) must not expire by tick 31")


func test_visit_records_without_returning_novelty():
	_tracker.visit(10, 50)
	assert_false(_tracker.is_novel(10, 60, 100),
		"visit() must record the tick so is_novel() can check it")
