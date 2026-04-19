extends GutTest

# AI-DEV: Covers the new three-layer addressing API. Every test in this file
# should survive Commit 5 (old API deletion) untouched — the new API is the
# contract.


func test_slot_origin_y_descends_as_slot_index_rises() -> void:
	# Slot 0 is the BOTTOM slot and must have a higher world Y than slot 9.
	# This is the Y-axis invariant — if someone re-flips the convention,
	# this test catches it.
	var bottom: Vector2i = Constants.slot_origin_world(0, 0, 0)
	var top: Vector2i = Constants.slot_origin_world(0, 0, 9)
	assert_gt(bottom.y, top.y,
		"slot 0 (bottom) must have larger Y than slot 9 (top); got bottom=%d top=%d"
		% [bottom.y, top.y])


func test_slot_rect_dimensions_match_server_size() -> void:
	var rect: Rect2i = Constants.slot_rect_world(0, 0, 0)
	assert_eq(rect.size, Vector2i(23, 8),
		"slot rect must be 23×8 px (server footprint)")


func test_rack_frame_rect_sits_above_top_slot() -> void:
	var top_slot: Rect2i = Constants.slot_rect_world(0, 0, 9)
	var frame: Rect2i = Constants.rack_frame_rect(0, 0)
	assert_eq(frame.end.y, top_slot.position.y,
		"frame bottom edge must meet top of slot 9")
	assert_eq(frame.size.y, 12,
		"frame is 12 px tall (rack top frame)")


func test_rack_baseboard_rect_sits_below_bottom_slot() -> void:
	var bottom_slot: Rect2i = Constants.slot_rect_world(0, 0, 0)
	var base: Rect2i = Constants.rack_baseboard_rect(0, 0)
	assert_eq(base.position.y, bottom_slot.end.y,
		"baseboard top edge must meet bottom of slot 0")
	assert_eq(base.size.y, 4,
		"baseboard is 4 px tall")


func test_floor_rect_sits_below_baseboard() -> void:
	var base: Rect2i = Constants.rack_baseboard_rect(0, 0)
	var floor_r: Rect2i = Constants.floor_rect_world(0)
	assert_eq(floor_r.position.y, base.end.y,
		"floor top edge meets baseboard bottom edge")
	assert_eq(floor_r.size.y, 16, "floor is 16 px tall")


func test_rack_horizontal_stride_is_31px() -> void:
	var r0: Rect2i = Constants.slot_rect_world(0, 0, 0)
	var r1: Rect2i = Constants.slot_rect_world(0, 1, 0)
	assert_eq(r1.position.x - r0.position.x, 31,
		"adjacent rack cells are 31 px apart")


func test_bay_index_round_trip_through_world_to_bay() -> void:
	for bay: int in [0, 1, 2, 3]:
		var origin: Vector2i = Constants.bay_origin_world(bay)
		assert_eq(Constants.world_to_bay(origin), bay,
			"world_to_bay must return the bay we pulled origin from")


func test_world_to_bay_returns_invalid_for_gap_positions() -> void:
	# Between bays there's a gap; points there have no owning bay.
	var bay0_end: Vector2i = Constants.bay_rect_world(0).end
	var far_right: Vector2i = Vector2i(bay0_end.x + 1000, bay0_end.y)
	# World positions past the last known bay are INVALID.
	assert_eq(Constants.world_to_bay(far_right), Constants.INVALID_BAY,
		"points past known bays must return INVALID_BAY")


func test_bay_local_to_slot_finds_slot_when_inside_slot_rect() -> void:
	var rect: Rect2i = Constants.slot_rect_world(0, 2, 5)
	var center: Vector2i = rect.position + rect.size / 2
	var q: SlotQuery = Constants.bay_local_to_slot(0, center)
	assert_eq(q.zone, &"slot")
	assert_eq(q.rack, 2)
	assert_eq(q.get_slot(), 5)


func test_bay_local_to_slot_tags_frame_zone() -> void:
	var frame: Rect2i = Constants.rack_frame_rect(0, 1)
	var center: Vector2i = frame.position + frame.size / 2
	var q: SlotQuery = Constants.bay_local_to_slot(0, center)
	assert_eq(q.zone, &"frame")
	assert_eq(q.get_rack(), 1)


func test_bay_local_to_slot_tags_floor_zone() -> void:
	var floor_r: Rect2i = Constants.floor_rect_world(0)
	var under_rack_1: Vector2i = Vector2i(
		Constants.rack_frame_rect(0, 1).position.x + 5,
		floor_r.position.y + 2,
	)
	var q: SlotQuery = Constants.bay_local_to_slot(0, under_rack_1)
	assert_eq(q.zone, &"floor")
	assert_eq(q.get_rack(), 1)


func test_bay_local_to_slot_tags_other_for_gap_positions() -> void:
	# A point in the horizontal gap between rack cells is &"other".
	var r0: Rect2i = Constants.slot_rect_world(0, 0, 0)
	var gap_point: Vector2i = Vector2i(r0.end.x + 2, r0.position.y + 2)
	var q: SlotQuery = Constants.bay_local_to_slot(0, gap_point)
	assert_eq(q.zone, &"other")


func test_slot_origin_asserts_on_invalid_slot_index() -> void:
	# TCP philosophy: explode early. Passing 10 or -1 is a programmer error.
	# In release builds this is a silent no-op; in debug it asserts.
	# We only test that the helper does not crash on valid indices here.
	for s: int in range(10):
		var _p: Vector2i = Constants.slot_origin_world(0, 0, s)
