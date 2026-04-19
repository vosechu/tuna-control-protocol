extends GutTest

# AI-DEV: The gap/slot-boundary/world_to_bay tests that used to live in
# this file were redundant with tests/unit/test_constants_addressing.gd
# (test_bay_local_to_slot_tags_other_for_gap_positions,
# test_bay_local_to_slot_finds_slot_when_inside_slot_rect,
# test_bay_index_round_trip_through_world_to_bay). The placement-boundary
# unique coverage is the rack iteration upper-bound — rack 4, the last
# rack, is only hit here; mid-range racks (0–2) are exercised elsewhere.


func test_first_and_last_rack_columns_snap_to_their_own_rack():
	# AI-DEV: Covers rack 0 and rack 4 in one test — both paths run the
	# single `for r in range(RACK_COUNT)` line in bay_local_to_slot, so a
	# surgical mutation can only target one test. Splitting them blocks
	# the cycle. Rack 4 pins the upper bound (mid-range racks are
	# exercised in test_constants_addressing.gd); rack 0 pins the lower.
	var col_0: Rect2i = Constants.rack_column_rect_world(0, 0)
	var center_0 := Vector2i(col_0.position.x + col_0.size.x / 2, 50)
	var q_0: SlotQuery = Constants.bay_local_to_slot(0, center_0)
	assert_eq(q_0.rack, 0, "Center of rack column 0 snaps to rack 0")

	var col_4: Rect2i = Constants.rack_column_rect_world(0, 4)
	var center_4 := Vector2i(col_4.position.x + col_4.size.x / 2, 50)
	var q_4: SlotQuery = Constants.bay_local_to_slot(0, center_4)
	assert_eq(q_4.rack, 4, "Center of rack column 4 snaps to rack 4")
