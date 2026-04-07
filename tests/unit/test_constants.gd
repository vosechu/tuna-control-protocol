extends GutTest


func test_ru_to_pu_converts_correctly():
	assert_eq(Constants.ru_to_pu(1), 700, "1 RU = 700 PU")
	assert_eq(Constants.ru_to_pu(3), 2100, "3 RU = 2100 PU")
	assert_eq(Constants.ru_to_pu(0), 0, "0 RU = 0 PU")


func test_pu_to_ru_converts_correctly():
	assert_eq(Constants.pu_to_ru(700), 1, "700 PU = 1 RU")
	assert_eq(Constants.pu_to_ru(2100), 3, "2100 PU = 3 RU")
	assert_eq(Constants.pu_to_ru(0), 0, "0 PU = 0 RU")


func test_rack_cell_addressing():
	assert_eq(Constants.rack_cell(0, 0), 0, "Rack 0 slot 0 = cell 0")
	assert_eq(Constants.rack_cell(1, 0), 42, "Rack 1 slot 0 = cell 42")
	assert_eq(Constants.rack_cell(6, 41), 293, "Rack 6 slot 41 = cell 293")


func test_floor_cell_addressing():
	assert_eq(Constants.floor_cell(0), 294, "Floor rack 0 = cell 294")
	assert_eq(Constants.floor_cell(6), 300, "Floor rack 6 = cell 300")


func test_to_world_converts_int_to_float():
	assert_almost_eq(Constants.to_world(700), 7.0, 0.01, "700 PU = 7.0 px")
	assert_almost_eq(Constants.to_world(100), 1.0, 0.01, "100 PU = 1.0 px")


func test_from_world_converts_float_to_int():
	assert_eq(Constants.from_world(7.0), 700, "7.0 px = 700 PU")
	assert_eq(Constants.from_world(1.0), 100, "1.0 px = 100 PU")


func test_grid_dimensions():
	assert_eq(Constants.HEAT_CELLS_TOTAL, 301, "294 rack + 7 floor = 301 cells")
	assert_eq(Constants.SLOTS_PER_RACK, 42, "42 U per rack")
	assert_eq(Constants.RACK_COUNT, 7, "7 racks")


func test_rack_stride():
	assert_eq(Constants.RACK_STRIDE_PX, 80, "76 + 4 gap = 80px stride")
	assert_eq(Constants.RACK_STRIDE_PU, 8000, "80 * 100 = 8000 PU stride")
