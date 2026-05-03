extends GutTest

# AI-DEV: Biscuit/Mittens regression guard. With the legacy 8-RU spatial
# query (64 px), a cat on rack-2 floor cannot see boxes placed at rack-4
# in the same bay. The widened BAY_WIDTH_PX (186 px) cap restores
# bay-scope perception. If this test starts failing because the cat's
# best score is 0, suspect: spatial query bound regressed, senses default
# regressed, or score_ad gate logic regressed.

var _db: GameStateDB
var _resolver: DesireResolver


func before_each() -> void:
	_db = GameStateDB.new()
	_resolver = DesireResolver.new(_db)


func test_cat_at_rack_0_scores_box_at_rack_4_same_bay():
	# Rack-0 floor cat
	var cat_id: int = _db.create_entity()
	var rack0_pos: Vector2i = Constants.rack_column_rect_world(0, 0).position
	var cat_x: int = rack0_pos.x + 12
	var cat_y: int = Constants.FLOOR_Y - 4
	_db.set_component(cat_id, &"species", {&"id": &"tcp_cats:cat"})
	_db.set_component(cat_id, &"position", {&"x": cat_x, &"y": cat_y})
	_db.set_component(cat_id, &"senses", {
		&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 64,
	})
	_db.set_component(cat_id, &"desires", {
		&"warmth": 200, &"comfort": 200, &"curiosity": 800,
	})
	_db.set_component(cat_id, &"personality", {
		&"warmth_weight": 700,
		&"comfort_weight": 800,
		&"curiosity_weight": 100,
	})
	_db.set_component(cat_id, &"ai_state", {
		&"state": &"IDLE",
		&"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	_db.set_component(cat_id, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	_db.update_spatial(cat_id, cat_x, cat_y)

	# Rack-4 box (well past the legacy 64 px cap)
	var box_id: int = _db.create_entity()
	var rack4_pos: Vector2i = Constants.rack_column_rect_world(0, 4).position
	var box_x: int = rack4_pos.x + 12
	var box_y: int = Constants.FLOOR_Y - 4
	_db.set_component(box_id, &"position", {&"x": box_x, &"y": box_y})
	_db.set_component(box_id, &"advertisements", {&"list": [
		{&"desire_type": &"comfort", &"strength": 700, &"radius_px": 24},
	]})
	_db.update_spatial(box_id, box_x, box_y)

	var dist_px: int = absi(cat_x - box_x) + absi(cat_y - box_y)
	assert_gt(
		dist_px, 64,
		"Test setup: box must be past the legacy 8-RU cap, got %d" % dist_px,
	)
	assert_lt(
		dist_px, Constants.BAY_WIDTH_PX,
		"Test setup: box must be within bay-width cap, got %d" % dist_px,
	)

	_resolver.mark_dirty(cat_id)
	_resolver.evaluate_budget()

	var ai_state: Dictionary = _db.get_component(cat_id, &"ai_state")
	assert_eq(
		ai_state[&"state"], &"SEEKING",
		"Cat must SEEK after spotting the box across the bay, got %s"
			% ai_state[&"state"],
	)
	var target: Dictionary = _db.get_component(cat_id, &"target")
	assert_eq(
		target[&"entity_id"], box_id,
		"Cat must target the box specifically (got %d, expected %d)"
			% [target[&"entity_id"], box_id],
	)
