extends GutTest

var db: GameStateDB


func before_each() -> void:
	db = GameStateDB.new()


func test_should_become_hungry_covers_both_sides_of_threshold():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# AI-DEV: Covers above-threshold (stay content) and below-threshold (go
	# hungry) in one test — both paths execute the single
	# `hunger < HUNGER_THRESHOLD` comparison inside
	# CatFoodStates.should_become_hungry. Separate tests blocked surgical
	# mutation targeting.
	var below: int = _make_content_cat()
	db.set_field(below, &"desires", &"hunger", 300)
	assert_true(CatFoodStates.should_become_hungry(db, below),
		"hunger 300 < threshold 400 → should become hungry")
	var above: int = _make_content_cat()
	db.set_field(above, &"desires", &"hunger", 500)
	assert_false(CatFoodStates.should_become_hungry(db, above),
		"hunger 500 > threshold 400 → should stay content")


func test_find_nearest_dispenser_picks_closer_and_returns_invalid_when_empty():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# AI-DEV: Covers "picks the closer dispenser" AND "returns INVALID_ID
	# when none exist" in one test — both paths go through the same linear
	# scan in CatFoodStates.find_nearest_dispenser. Separating them blocked
	# surgical mutation targeting (any dispenser-search mutation broke both).
	var cat_id: int = _make_hungry_cat(1, 5)
	# Empty world first: no dispensers exist.
	assert_eq(CatFoodStates.find_nearest_dispenser(db, cat_id), Constants.INVALID_ID,
		"No dispensers → INVALID_ID")
	# Now add two dispensers: one close (rack 1), one far (rack 4).
	var close_id: int = _make_dispenser(1, 3)
	_make_dispenser(4, 3)
	assert_eq(CatFoodStates.find_nearest_dispenser(db, cat_id), close_id,
		"Closer dispenser should win the linear scan")


func test_apply_eat_pulse_raises_hunger_and_clamps_at_1000():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# AI-DEV: Covers under-clamp and at-clamp paths — both exercise the single
	# mini(1000, hunger + EAT_GAIN_PER_PULSE) line. Merging prevents shared-
	# code mutation-target ambiguity.
	var mid: int = _make_content_cat()
	db.set_field(mid, &"desires", &"hunger", 200)
	CatFoodStates.apply_eat_pulse(db, mid)
	assert_eq(db.get_field(mid, &"desires", &"hunger"), 700,
		"200 + 500 = 700, under the clamp")
	var high: int = _make_content_cat()
	db.set_field(high, &"desires", &"hunger", 800)
	CatFoodStates.apply_eat_pulse(db, high)
	assert_eq(db.get_field(high, &"desires", &"hunger"), 1000,
		"800 + 500 should clamp at 1000")


# ── Helpers ──


func _make_content_cat() -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"species", {
		&"id": &"tcp_cats:cat",
		&"variant": &"cat01",
		&"name": &"Test",
	})
	db.set_component(id, &"desires", {
		&"warmth": 700, &"comfort": 700,
		&"hunger": 700, &"attention": 500,
		&"curiosity": 500,
	})
	db.set_component(id, &"ai_state", {
		&"state": &"LOAFING",
		&"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	db.set_component(id, &"position", {&"x": 0, &"y": 0})
	db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(id, 0, 0)
	return id


func _make_hungry_cat(rack: int, slot: int) -> int:
	var id: int = _make_content_cat()
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var x: int = slot_rect.position.x + slot_rect.size.x / 2
	var y: int = slot_rect.position.y + slot_rect.size.y / 2
	db.set_component(id, &"position", {&"x": x, &"y": y})
	db.set_field(id, &"desires", &"hunger", 200)
	db.update_spatial(id, x, y)
	return id


func _make_dispenser(rack: int, slot: int) -> int:
	var id: int = db.create_entity()
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var x: int = slot_rect.position.x + slot_rect.size.x / 2
	var y: int = slot_rect.position.y + slot_rect.size.y / 2
	db.set_component(id, &"position", {&"x": x, &"y": y})
	db.set_component(id, &"tuna_dispenser", {
		&"hum_cost": 50,
		&"can_type": &"tcp_tuna:tuna_can",
	})
	db.set_component(id, &"object_type", {
		&"type": &"tuna_dispenser",
	})
	db.update_spatial(id, x, y)
	return id
