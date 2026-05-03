extends GutTest

var db: GameStateDB


func before_each() -> void:
	db = GameStateDB.new()


func test_pet_animal_fills_attention_clamping_at_1000():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# AI-DEV: Covers both partial-fill and clamp-at-max in one test — both
	# paths execute the same `mini(1000, attention + PET_FILL_AMOUNT)` line in
	# PlayerVerbs.pet_animal. Testing them separately was redundant and
	# blocked surgical mutation targeting.
	var cat_partial: int = _make_cat(300)
	PlayerVerbs.pet_animal(db, cat_partial)
	assert_eq(
		db.get_field(cat_partial, &"desires", &"attention"),
		800,
		"Petting 300-attention cat with +500 should land at 800",
	)
	var cat_near_max: int = _make_cat(900)
	PlayerVerbs.pet_animal(db, cat_near_max)
	assert_eq(
		db.get_field(cat_near_max, &"desires", &"attention"),
		1000,
		"Petting 900-attention cat with +500 should clamp at 1000",
	)


func test_squeak_box_retargets_nearby_pacing_cat():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var cat_id: int = _make_cat(500)
	var box_id: int = db.create_entity()
	var slot_rect: Rect2i = Constants.slot_rect_world(0, 3, 5)
	var bx: int = slot_rect.position.x + slot_rect.size.x / 2
	var by: int = slot_rect.position.y + slot_rect.size.y / 2
	db.set_component(box_id, &"position", {&"x": bx, &"y": by})
	db.set_component(box_id, &"object_type", {&"type": &"cardboard_box"})
	# Move the cat into range of the box so squeak's radius query hits it.
	db.set_component(cat_id, &"position", {&"x": bx, &"y": by})
	db.update_spatial(cat_id, bx, by)

	PlayerVerbs.squeak_box(db, box_id)

	var target: Dictionary = db.get_component(cat_id, &"target")
	assert_eq(target[&"entity_id"], box_id,
		"Squeak should set cat target entity_id to the box")
	var ai: Dictionary = db.get_component(cat_id, &"ai_state")
	assert_eq(ai[&"state"], &"RETURNING",
		"Squeak should transition a PACING cat into RETURNING state")


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
