extends GutTest

# Tests for Constants bay/rack/slot coordinate helpers.
# These helpers are the single source of truth for bay math —
# no other file should compute bay offsets by hand.


func test_bay_origin_world_uses_stride_with_zero_anchor():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# AI-DEV: Covers both "bay 0 starts at origin" and "bay N offsets by N*stride"
	# in one test — the production code is a single `bay * BAY_STRIDE_PX` line,
	# so testing them separately was redundant and blocked surgical mutation
	# targeting.
	var origin0: Vector2i = Constants.bay_origin_world(0)
	assert_eq(origin0, Vector2i(0, 0),
		"Bay 0 origin should be (0, 0) in world pixels")
	var origin2: Vector2i = Constants.bay_origin_world(2)
	assert_eq(origin2.x, 2 * Constants.BAY_STRIDE_PX,
		"Bay 2 origin x should be 2 * BAY_STRIDE_PX")


func test_bay_center_offsets_by_stride_and_half_width():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# AI-DEV: Covers bay 0 (pure half-width) and bay 1 (stride + half-width) in
	# one test — both paths execute the same
	# `bay * BAY_STRIDE_PX + BAY_WIDTH_PX / 2` line. Separate tests blocked
	# surgical mutation targeting.
	var center0: Vector2 = Constants.bay_center(0)
	var expected0: float = float(Constants.BAY_WIDTH_PX) / 2.0
	assert_almost_eq(center0.x, expected0, 0.01,
		"Bay 0 center x should be BAY_WIDTH_PX / 2")
	var center1: Vector2 = Constants.bay_center(1)
	var expected1: float = (
		float(Constants.BAY_STRIDE_PX)
		+ float(Constants.BAY_WIDTH_PX) / 2.0
	)
	assert_almost_eq(center1.x, expected1, 0.01,
		"Bay 1 center x should be BAY_STRIDE_PX + half BAY_WIDTH_PX")
