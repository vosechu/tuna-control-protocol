extends GutTest

# AI-DEV: Pins the disk-vs-rect geometry contract. The HUM is a
# rectangular body (RACK_WIDTH_PX wide × size_ru × SLOT_HEIGHT_PX tall);
# the cat's emission is a circle of radius purr.radius_px. Charge
# happens iff disk intersects rect — NOT center-distance, NOT rect-vs-
# rect. A tempting "simplification" to center-distance silently breaks
# tall HUMs (size_ru > 1) because the disk edge can touch the rect's
# face without reaching its center. Keep the assertions as-is.

# HUM body rect = (anchor_top, RACK_WIDTH_PX) wide, (size_ru * SLOT_HEIGHT_PX) tall.
# Cat emission disk = circle(cat.pos, purr.radius_px). Charge if rect intersects disk.


func _make_hum(db: GameStateDB, rack: int, slot: int, size_ru: int) -> int:
	var hum_id: int = db.create_entity()
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var cx: int = slot_rect.position.x + slot_rect.size.x / 2
	var cy: int = slot_rect.position.y + slot_rect.size.y / 2
	db.set_component(hum_id, &"hum", {&"reserve": 0, &"capacity": 10000})
	db.set_component(hum_id, &"hum_receiver", {})
	db.set_component(hum_id, &"position", {&"x": cx, &"y": cy})
	db.set_component(hum_id, &"physical", {&"mass": 20000, &"size_ru": size_ru})
	return hum_id


func _make_cat(db: GameStateDB, x: int, y: int, intensity: int, radius_px: int) -> int:
	var cat_id: int = db.create_entity()
	db.set_component(cat_id, &"position", {&"x": x, &"y": y})
	db.set_component(cat_id, &"purr", {&"intensity": intensity, &"radius_px": radius_px})
	return cat_id


func test_disk_intersects_body_rect_charges_hum() -> void:
	# HUM at rack 1 slot 9 (top), 6U body. Cat in rack 1 slot 1 (close enough).
	var db := GameStateDB.new()
	var hum := _make_hum(db, 1, 9, 6)
	var slot1: Rect2i = Constants.slot_rect_world(0, 1, 1)
	_make_cat(
		db,
		slot1.position.x + slot1.size.x / 2,
		slot1.position.y + slot1.size.y / 2,
		100,
		48,
	)
	var hs := HumSystem.new(db)
	hs.tick_charge()
	assert_eq(db.get_field(hum, &"hum", &"reserve"), 100)


func test_disk_does_not_intersect_no_charge() -> void:
	# Cat far from HUM; small radius.
	var db := GameStateDB.new()
	var hum := _make_hum(db, 1, 9, 6)
	var slot1: Rect2i = Constants.slot_rect_world(0, 1, 1)
	_make_cat(
		db,
		slot1.position.x + slot1.size.x / 2,
		slot1.position.y + slot1.size.y / 2,
		100,
		4,
	)
	var hs := HumSystem.new(db)
	hs.tick_charge()
	assert_eq(db.get_field(hum, &"hum", &"reserve"), 0)


func test_disk_intersects_two_hums_charges_both() -> void:
	var db := GameStateDB.new()
	var hum_a := _make_hum(db, 0, 9, 6)
	var hum_b := _make_hum(db, 1, 9, 6)
	# Cat positioned roughly midway, with radius big enough to reach both
	var rack0: Rect2i = Constants.rack_column_rect_world(0, 0)
	var rack1: Rect2i = Constants.rack_column_rect_world(0, 1)
	var midx: int = (rack0.position.x + rack1.position.x + rack1.size.x) / 2
	var slot1: Rect2i = Constants.slot_rect_world(0, 0, 1)
	_make_cat(db, midx, slot1.position.y, 50, 80)
	var hs := HumSystem.new(db)
	hs.tick_charge()
	assert_eq(db.get_field(hum_a, &"hum", &"reserve"), 50)
	assert_eq(db.get_field(hum_b, &"hum", &"reserve"), 50)


func test_zero_intensity_no_charge() -> void:
	var db := GameStateDB.new()
	var hum := _make_hum(db, 1, 9, 6)
	var slot: Rect2i = Constants.slot_rect_world(0, 1, 9)
	# large radius but intensity 0
	_make_cat(db, slot.position.x, slot.position.y, 0, 100)
	var hs := HumSystem.new(db)
	hs.tick_charge()
	assert_eq(db.get_field(hum, &"hum", &"reserve"), 0)


func test_cross_rack_reach_gated_on_radius() -> void:
	# Cat in rack 0 slot 1, HUM in rack 1 slot 9. With small radius: no charge.
	# With large radius: charges.
	var db := GameStateDB.new()
	var hum := _make_hum(db, 1, 9, 6)
	var slot01: Rect2i = Constants.slot_rect_world(0, 0, 1)
	var cx: int = slot01.position.x + slot01.size.x / 2
	var cy: int = slot01.position.y + slot01.size.y / 2
	# 16 px = strictly intra-rack
	var cat: int = _make_cat(db, cx, cy, 75, 16)
	var hs := HumSystem.new(db)
	hs.tick_charge()
	assert_eq(
		db.get_field(hum, &"hum", &"reserve"), 0,
		"16-px radius does not cross rack gap",
	)
	# 64 px = cross-rack
	db.set_field(cat, &"purr", &"radius_px", 64)
	hs.tick_charge()
	assert_gt(
		db.get_field(hum, &"hum", &"reserve"), 0,
		"64-px radius reaches across rack gap",
	)
