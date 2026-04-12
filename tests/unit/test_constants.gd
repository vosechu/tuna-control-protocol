extends GutTest


func test_ru_to_pu_converts_correctly():
	assert_eq(Constants.ru_to_pu(1), 800, "1 RU = 800 PU (SLOT_HEIGHT_PU)")
	assert_eq(Constants.ru_to_pu(3), 2400, "3 RU = 2400 PU")
	assert_eq(Constants.ru_to_pu(0), 0, "0 RU = 0 PU")


func test_pu_to_ru_converts_correctly():
	assert_eq(Constants.pu_to_ru(800), 1, "800 PU = 1 RU")
	assert_eq(Constants.pu_to_ru(2400), 3, "2400 PU = 3 RU")
	assert_eq(Constants.pu_to_ru(0), 0, "0 PU = 0 RU")


func test_rack_cell_addressing():
	assert_eq(Constants.rack_cell(0, 0), 0, "Rack 0 slot 0 = cell 0")
	assert_eq(Constants.rack_cell(1, 0), 10, "Rack 1 slot 0 = cell 10 (SLOTS_PER_RACK)")
	assert_eq(Constants.rack_cell(4, 9), 49, "Rack 4 slot 9 = cell 49 (last rack cell)")


func test_floor_cell_addressing():
	assert_eq(Constants.floor_cell(0), 50, "Floor rack 0 = cell 50 (HEAT_CELLS_RACK)")
	assert_eq(Constants.floor_cell(4), 54, "Floor rack 4 = cell 54 (last floor cell)")


func test_to_world_converts_int_to_float():
	assert_almost_eq(Constants.to_world(800), 8.0, 0.01, "800 PU = 8.0 px (1 RU)")
	assert_almost_eq(Constants.to_world(100), 1.0, 0.01, "100 PU = 1.0 px")


func test_from_world_converts_float_to_int():
	assert_eq(Constants.from_world(8.0), 800, "8.0 px = 800 PU (1 RU)")
	assert_eq(Constants.from_world(1.0), 100, "1.0 px = 100 PU")


func test_grid_dimensions():
	assert_eq(Constants.HEAT_CELLS_TOTAL, 55, "50 rack + 5 floor = 55 cells")
	assert_eq(Constants.SLOTS_PER_RACK, 10, "10 U per rack")
	assert_eq(Constants.RACK_COUNT, 5, "5 racks")


func test_rack_stride():
	assert_eq(Constants.RACK_STRIDE_PX, 31, "23 width + 8 gap = 31px stride")
	assert_eq(Constants.RACK_STRIDE_PU, 3100, "31 * 100 = 3100 PU stride")
