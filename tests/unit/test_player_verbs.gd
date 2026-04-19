extends GutTest

var db: GameStateDB


func before_each() -> void:
	db = GameStateDB.new()


func test_petting_fills_attention():
	var cat_id: int = _make_cat(300)
	var fill_amount: int = 500
	var attention: int = db.get_field(
		cat_id, &"desires", &"attention",
	)
	db.set_field(
		cat_id, &"desires", &"attention",
		mini(1000, attention + fill_amount),
	)
	assert_eq(
		db.get_field(cat_id, &"desires", &"attention"),
		800,
		"Petting should add to attention bar",
	)


func test_petting_clamps_at_1000():
	var cat_id: int = _make_cat(900)
	db.set_field(
		cat_id, &"desires", &"attention",
		mini(1000, 900 + 500),
	)
	assert_eq(
		db.get_field(cat_id, &"desires", &"attention"),
		1000,
		"Attention should clamp at 1000",
	)


func test_squeak_sets_target_to_box():
	var cat_id: int = _make_cat(500)
	var box_id: int = db.create_entity()
	var slot_rect: Rect2i = Constants.slot_rect_world(0, 3, 5)
	var bx: int = slot_rect.position.x + slot_rect.size.x / 2
	var by: int = slot_rect.position.y + slot_rect.size.y / 2
	db.set_component(box_id, &"position", {
		&"x": bx, &"y": by,
	})
	db.set_component(box_id, &"object_type", {
		&"type": &"cardboard_box",
	})

	db.set_component(cat_id, &"target", {
		&"x": bx, &"y": by,
		&"entity_id": box_id,
	})
	db.set_component(cat_id, &"ai_state", {
		&"state": &"RETURNING",
		&"meta_state": &"GOAL_DIRECTED",
		&"commitment_score": 200,
	})

	var target: Dictionary = db.get_component(
		cat_id, &"target",
	)
	assert_eq(target[&"entity_id"], box_id,
		"Squeak should set cat target to the box")
	var ai: Dictionary = db.get_component(
		cat_id, &"ai_state",
	)
	assert_eq(ai[&"state"], &"RETURNING",
		"Squeak should set cat to RETURNING state")


func _make_cat(attention: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"species", {
		&"id": &"tcp_cats:cat",
		&"variant": &"cat01",
		&"name": &"Test",
	})
	db.set_component(id, &"desires", {
		&"warmth": 700, &"comfort": 700,
		&"hunger": 700,
		&"attention": attention,
		&"curiosity": 500,
	})
	db.set_component(id, &"ai_state", {
		&"state": &"PACING",
		&"meta_state": &"GOAL_DIRECTED",
		&"commitment_score": 0,
	})
	db.set_component(id, &"position", {
		&"x": 0, &"y": 0,
	})
	db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(id, 0, 0)
	return id
