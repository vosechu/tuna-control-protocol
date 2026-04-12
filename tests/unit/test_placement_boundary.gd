extends GutTest


func test_snap_at_bay_origin():
	var result: Dictionary = Constants.pu_to_bay_rack_slot(
		Constants.LEFTMOST_RACK_OFFSET_PU, 0
	)
	assert_eq(result[&"bay"], 0)
	assert_eq(result[&"rack"], 0)
	assert_eq(result[&"slot"], 0)


func test_snap_just_before_first_rack():
	var result: Dictionary = Constants.pu_to_bay_rack_slot(
		Constants.LEFTMOST_RACK_OFFSET_PU - 1, 0
	)
	assert_eq(result[&"rack"], -1,
		"Position before LEFTMOST_RACK_OFFSET should be rack -1")


func test_snap_at_last_rack_interior():
	var result: Dictionary = Constants.pu_to_bay_rack_slot(
		Constants.LEFTMOST_RACK_OFFSET_PU + 4 * Constants.RACK_STRIDE_PU,
		0
	)
	assert_eq(result[&"rack"], 4,
		"Position at last rack origin should snap to rack 4")


func test_snap_in_next_bay():
	var result: Dictionary = Constants.pu_to_bay_rack_slot(
		Constants.BAY_STRIDE_PU + Constants.LEFTMOST_RACK_OFFSET_PU,
		0
	)
	assert_eq(result[&"bay"], 1,
		"Position past BAY_STRIDE_PU should be bay 1")
	assert_eq(result[&"rack"], 0)


func test_snap_in_previous_bay():
	var result: Dictionary = Constants.pu_to_bay_rack_slot(
		-Constants.BAY_STRIDE_PU + Constants.LEFTMOST_RACK_OFFSET_PU,
		0
	)
	assert_eq(result[&"bay"], -1,
		"Position before bay 0 should be bay -1")


func test_snap_at_rack_0_last_pixel():
	var boundary: int = Constants.LEFTMOST_RACK_OFFSET_PU + Constants.RACK_STRIDE_PU
	var result: Dictionary = Constants.pu_to_bay_rack_slot(boundary - 1, 0)
	assert_eq(result[&"rack"], 0,
		"One PU before boundary should still snap to rack 0")


func test_snap_at_rack_1_first_pixel():
	var boundary: int = Constants.LEFTMOST_RACK_OFFSET_PU + Constants.RACK_STRIDE_PU
	var result: Dictionary = Constants.pu_to_bay_rack_slot(boundary, 0)
	assert_eq(result[&"rack"], 1,
		"At rack 1 origin should snap to rack 1")


func test_snap_just_past_rack_1_origin():
	var boundary: int = Constants.LEFTMOST_RACK_OFFSET_PU + Constants.RACK_STRIDE_PU
	var result: Dictionary = Constants.pu_to_bay_rack_slot(boundary + 1, 0)
	assert_eq(result[&"rack"], 1,
		"One PU past rack 1 origin should still be rack 1")


func test_snap_slot_boundaries():
	var slot_6_origin: int = 6 * Constants.SLOT_HEIGHT_PU
	var result_before: Dictionary = Constants.pu_to_bay_rack_slot(0, slot_6_origin - 1)
	var result_at: Dictionary = Constants.pu_to_bay_rack_slot(0, slot_6_origin)
	var result_after: Dictionary = Constants.pu_to_bay_rack_slot(0, slot_6_origin + 1)
	assert_eq(result_before[&"slot"], 5, "One PU before slot 6 is slot 5")
	assert_eq(result_at[&"slot"], 6, "At slot 6 origin is slot 6")
	assert_eq(result_after[&"slot"], 6, "One PU past slot 6 origin is slot 6")
