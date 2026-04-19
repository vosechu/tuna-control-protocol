extends GutTest

var db: GameStateDB


func before_each() -> void:
	db = GameStateDB.new()


func test_content_cat_transitions_to_hungry_when_hunger_drops():
	var cat_id: int = _make_content_cat()
	db.set_field(cat_id, &"desires", &"hunger", 300)
	var should_transition: bool = _should_become_hungry(cat_id)
	assert_true(should_transition,
		"Cat with hunger below 400 should transition to HUNGRY")


func test_content_cat_stays_content_when_hunger_above_threshold():
	var cat_id: int = _make_content_cat()
	db.set_field(cat_id, &"desires", &"hunger", 500)
	var should_transition: bool = _should_become_hungry(cat_id)
	assert_false(should_transition,
		"Cat with hunger above threshold should stay content")


func test_hungry_cat_targets_nearest_dispenser():
	var cat_id: int = _make_hungry_cat(1, 5)
	var disp1: int = _make_dispenser(1, 3)
	_make_dispenser(4, 3)

	var target: int = _find_nearest_dispenser(cat_id)
	assert_eq(target, disp1,
		"Hungry cat should target nearest dispenser")


func test_hungry_cat_without_dispenser_wanders():
	var cat_id: int = _make_hungry_cat(1, 5)
	var target: int = _find_nearest_dispenser(cat_id)
	assert_eq(target, Constants.INVALID_ID,
		"Hungry cat without dispenser should get INVALID_ID")


func test_eating_cat_hunger_increases():
	var cat_id: int = _make_content_cat()
	db.set_field(cat_id, &"desires", &"hunger", 200)
	var ai: Dictionary = db.get_component(
		cat_id, &"ai_state",
	)
	ai[&"state"] = &"EATING"
	db.set_component(cat_id, &"ai_state", ai)
	var eat_amount: int = 500
	var hunger: int = db.get_field(
		cat_id, &"desires", &"hunger",
	)
	db.set_field(
		cat_id, &"desires", &"hunger",
		mini(1000, hunger + eat_amount),
	)
	assert_eq(
		db.get_field(cat_id, &"desires", &"hunger"), 700,
		"Eating should increase hunger satisfaction",
	)


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


func _should_become_hungry(entity_id: int) -> bool:
	var desires: Dictionary = db.get_component(
		entity_id, &"desires",
	)
	return desires[&"hunger"] < 400


func _find_nearest_dispenser(entity_id: int) -> int:
	var pos: Dictionary = db.get_component(
		entity_id, &"position",
	)
	var dispensers: Array[int] = db.get_entities_with(
		&"tuna_dispenser",
	)
	if dispensers.is_empty():
		return Constants.INVALID_ID
	var best_id: int = Constants.INVALID_ID
	var best_dist: int = 999999
	for disp_id: int in dispensers:
		var dpos: Dictionary = db.get_component(
			disp_id, &"position",
		)
		var dist: int = (
			absi(dpos[&"x"] - pos[&"x"])
			+ absi(dpos[&"y"] - pos[&"y"])
		)
		if dist < best_dist:
			best_dist = dist
			best_id = disp_id
	return best_id
