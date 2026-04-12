extends GutTest

var _db: GameStateDB
var _contentment: Contentment


func before_each() -> void:
	_db = GameStateDB.new()
	_contentment = Contentment.new(_db)


func _make_cat(desires: Dictionary) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {&"id": &"tcp_base:cat"})
	_db.set_component(id, &"desires", desires)
	return id


# ── Purring derivation ───────────────────────────────────────────────────────

func test_cat_with_all_four_bars_above_threshold_is_purring():
	var id: int = _make_cat({
		&"warmth": 600, &"comfort": 600, &"hunger": 600, &"attention": 600,
	})
	_contentment.evaluate_all()
	var comp: Dictionary = _db.get_component(id, &"contentment")
	assert_eq(comp[&"is_purring"], 1,
		"Cat with all 4 bars at 600 (above 400 threshold) should be purring")


func test_cat_with_three_bars_above_threshold_is_purring():
	var id: int = _make_cat({
		&"warmth": 600, &"comfort": 600, &"hunger": 600, &"attention": 100,
	})
	_contentment.evaluate_all()
	var comp: Dictionary = _db.get_component(id, &"contentment")
	assert_eq(comp[&"is_purring"], 1,
		"Cat with 3 bars at 600 and 1 at 100 should be purring (3-of-4 rule)")


func test_cat_with_two_bars_above_threshold_not_purring():
	var id: int = _make_cat({
		&"warmth": 600, &"comfort": 600, &"hunger": 100, &"attention": 100,
	})
	_contentment.evaluate_all()
	var comp: Dictionary = _db.get_component(id, &"contentment")
	assert_eq(comp[&"is_purring"], 0,
		"Cat with only 2 bars above threshold should not be purring")


func test_threshold_boundary_exactly_at_threshold_counts():
	var id: int = _make_cat({
		&"warmth": 400, &"comfort": 400, &"hunger": 400, &"attention": 100,
	})
	_contentment.evaluate_all()
	var comp: Dictionary = _db.get_component(id, &"contentment")
	assert_eq(comp[&"is_purring"], 1,
		"Bars exactly at threshold (400) should count as met")


func test_threshold_boundary_one_below_threshold_fails():
	var id: int = _make_cat({
		&"warmth": 399, &"comfort": 399, &"hunger": 600, &"attention": 100,
	})
	_contentment.evaluate_all()
	var comp: Dictionary = _db.get_component(id, &"contentment")
	assert_eq(comp[&"is_purring"], 0,
		"Two bars at 399 + one at 600 = only 1 met, should not be purring")


func test_non_cat_entities_ignored():
	var id: int = _db.create_entity()
	_db.set_component(id, &"object_type", {&"id": &"tcp_base:server_2u"})
	_contentment.evaluate_all()
	assert_false(_db.has_component(id, &"contentment"),
		"Entity without species+desires should not get a contentment component")


func test_evaluate_sets_purr_count():
	# Two purring cats
	_make_cat({&"warmth": 600, &"comfort": 600, &"hunger": 600, &"attention": 600})
	_make_cat({&"warmth": 600, &"comfort": 600, &"hunger": 600, &"attention": 100})
	# One non-purring cat
	_make_cat({&"warmth": 100, &"comfort": 100, &"hunger": 100, &"attention": 100})
	_contentment.evaluate_all()
	assert_eq(_contentment.get_purring_count(), 2,
		"2 purring + 1 not purring should yield purring_count of 2")
