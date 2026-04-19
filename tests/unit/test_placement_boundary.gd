extends GutTest


func test_rack_0_center_snaps_to_rack_0():
	var col: Rect2i = Constants.rack_column_rect_world(0, 0)
	var center := Vector2i(col.position.x + col.size.x / 2, 50)
	var q: SlotQuery = Constants.bay_local_to_slot(0, center)
	assert_eq(q.rack, 0, "Center of rack column 0 snaps to rack 0")


func test_rack_4_center_snaps_to_rack_4():
	var col: Rect2i = Constants.rack_column_rect_world(0, 4)
	var center := Vector2i(col.position.x + col.size.x / 2, 50)
	var q: SlotQuery = Constants.bay_local_to_slot(0, center)
	assert_eq(q.rack, 4, "Center of rack column 4 snaps to rack 4")


func test_gap_between_racks_returns_other():
	var col0: Rect2i = Constants.rack_column_rect_world(0, 0)
	var gap_x: int = col0.end.x + 2
	var q: SlotQuery = Constants.bay_local_to_slot(0, Vector2i(gap_x, 50))
	assert_eq(q.zone, &"other", "Horizontal gap between rack columns is 'other'")


func test_slot_boundary_is_per_slot_height():
	# Pick slot 5 via slot_rect_world and confirm its center lands on slot 5.
	var rect: Rect2i = Constants.slot_rect_world(0, 0, 5)
	var center := Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2)
	var q: SlotQuery = Constants.bay_local_to_slot(0, center)
	assert_eq(q.zone, &"slot", "Center of slot rect lands in slot zone")
	assert_eq(q.get_slot(), 5, "Slot index 5 round-trips through bay_local_to_slot")


func test_next_bay_resolves_via_world_to_bay():
	var b1_origin: Vector2i = Constants.bay_origin_world(1)
	assert_eq(
		Constants.world_to_bay(b1_origin), 1,
		"Bay 1 origin resolves to bay 1",
	)
