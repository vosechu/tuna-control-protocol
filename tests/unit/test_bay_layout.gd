extends GutTest

# Tests for Constants bay/rack/slot coordinate helpers.
# These helpers are the single source of truth for bay math —
# no other file should compute bay offsets by hand.

func test_bay_origin_pu_at_zero():
	var origin: Vector2i = Constants.bay_origin_pu(0)
	assert_eq(origin, Vector2i(0, 0),
		"Bay 0 origin should be (0, 0) in PU")

func test_bay_origin_pu_positive():
	var origin: Vector2i = Constants.bay_origin_pu(2)
	var expected_x: int = 2 * Constants.BAY_STRIDE_PU
	assert_eq(origin.x, expected_x,
		"Bay 2 origin x should be 2 * BAY_STRIDE_PU")

func test_bay_origin_pu_negative():
	var origin: Vector2i = Constants.bay_origin_pu(-1)
	var expected_x: int = -Constants.BAY_STRIDE_PU
	assert_eq(origin.x, expected_x,
		"Bay -1 origin x should be negative BAY_STRIDE_PU")

func test_rack_interior_pu_first_rack_in_bay():
	var x: int = Constants.rack_interior_pu(0, 0)
	var expected: int = Constants.LEFTMOST_RACK_OFFSET_PU
	assert_eq(x, expected,
		"Rack 0 in bay 0 should start at LEFTMOST_RACK_OFFSET_PU")

func test_rack_interior_pu_last_rack_in_bay():
	var x: int = Constants.rack_interior_pu(0, 4)
	var expected: int = Constants.LEFTMOST_RACK_OFFSET_PU + (4 * Constants.RACK_STRIDE_PU)
	assert_eq(x, expected,
		"Rack 4 in bay 0 should be offset by 4 strides")

func test_rack_interior_pu_across_bays():
	var bay0_rack4: int = Constants.rack_interior_pu(0, 4)
	var bay1_rack0: int = Constants.rack_interior_pu(1, 0)
	assert_lt(bay0_rack4, bay1_rack0,
		"Last rack of bay 0 should come before first rack of bay 1")

func test_rack_slot_to_pu_roundtrip():
	var original_bay: int = 0
	var original_rack: int = 2
	var original_slot: int = 5
	var pu: Vector2i = Constants.rack_slot_to_pu(
		original_bay, original_rack, original_slot
	)
	var back: Dictionary = Constants.pu_to_bay_rack_slot(pu.x, pu.y)
	assert_eq(back[&"bay"], original_bay, "bay roundtrip")
	assert_eq(back[&"rack"], original_rack, "rack roundtrip")
	assert_eq(back[&"slot"], original_slot, "slot roundtrip")

func test_rack_slot_to_pu_negative_bay():
	var pu: Vector2i = Constants.rack_slot_to_pu(-1, 0, 0)
	var back: Dictionary = Constants.pu_to_bay_rack_slot(pu.x, pu.y)
	assert_eq(back[&"bay"], -1, "negative bay roundtrip")

func test_bay_center_bay0():
	var center: Vector2 = Constants.bay_center(0)
	var expected_x: float = float(Constants.BAY_WIDTH_PX) / 2.0
	assert_almost_eq(center.x, expected_x, 0.01,
		"Bay 0 center x should be BAY_WIDTH_PX / 2")

func test_bay_center_bay1():
	var center: Vector2 = Constants.bay_center(1)
	var expected_x: float = float(Constants.BAY_STRIDE_PX) + float(Constants.BAY_WIDTH_PX) / 2.0
	assert_almost_eq(center.x, expected_x, 0.01,
		"Bay 1 center x should be BAY_STRIDE_PX + half bay width")
