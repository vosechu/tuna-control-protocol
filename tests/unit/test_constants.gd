extends GutTest


func test_rack_cell_addressing():
	assert_eq(Constants.rack_cell(0, 0), 0, "Rack 0 slot 0 = cell 0")
	assert_eq(
		Constants.rack_cell(1, 0), 10,
		"Rack 1 slot 0 = cell 10 (SLOTS_PER_RACK)",
	)
	assert_eq(
		Constants.rack_cell(4, 9), 49,
		"Rack 4 slot 9 = cell 49 (last rack cell)",
	)


func test_floor_cell_addressing():
	assert_eq(Constants.floor_cell(0), 50, "Floor rack 0 = cell 50")
	assert_eq(Constants.floor_cell(4), 54, "Floor rack 4 = cell 54")


func test_grid_dimensions():
	assert_eq(
		Constants.HEAT_CELLS_TOTAL, 55,
		"50 rack + 5 floor = 55 cells",
	)
	assert_eq(Constants.SLOTS_PER_RACK, 10, "10 slots per rack")
	assert_eq(Constants.RACK_COUNT, 5, "5 racks")


func test_rack_stride():
	assert_eq(
		Constants.RACK_STRIDE_PX, 31,
		"23 width + 8 gap = 31px stride",
	)
