extends GutTest

# Tests for Constants bay/rack/slot coordinate helpers.
# These helpers are the single source of truth for bay math —
# no other file should compute bay offsets by hand.


func test_bay_origin_world_at_zero():
	var origin: Vector2i = Constants.bay_origin_world(0)
	assert_eq(origin, Vector2i(0, 0),
		"Bay 0 origin should be (0, 0) in world pixels")


func test_bay_origin_world_positive():
	var origin: Vector2i = Constants.bay_origin_world(2)
	var expected_x: int = 2 * Constants.BAY_STRIDE_PX
	assert_eq(origin.x, expected_x,
		"Bay 2 origin x should be 2 * BAY_STRIDE_PX")


func test_bay_center_bay0():
	var center: Vector2 = Constants.bay_center(0)
	var expected_x: float = float(Constants.BAY_WIDTH_PX) / 2.0
	assert_almost_eq(center.x, expected_x, 0.01,
		"Bay 0 center x should be BAY_WIDTH_PX / 2")


func test_bay_center_bay1():
	var center: Vector2 = Constants.bay_center(1)
	var expected_x: float = (
		float(Constants.BAY_STRIDE_PX)
		+ float(Constants.BAY_WIDTH_PX) / 2.0
	)
	assert_almost_eq(center.x, expected_x, 0.01,
		"Bay 1 center x should be BAY_STRIDE_PX + half bay width")
