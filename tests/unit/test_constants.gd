extends GutTest


func test_ru_to_pu_converts_correctly():
	assert_eq(Constants.ru_to_pu(1), 2400, "1 RU = 2400 PU")
	assert_eq(Constants.ru_to_pu(3), 7200, "3 RU = 7200 PU")
	assert_eq(Constants.ru_to_pu(0), 0, "0 RU = 0 PU")


func test_pu_to_ru_converts_correctly():
	assert_eq(Constants.pu_to_ru(2400), 1, "2400 PU = 1 RU")
	assert_eq(Constants.pu_to_ru(7200), 3, "7200 PU = 3 RU")
	assert_eq(Constants.pu_to_ru(0), 0, "0 PU = 0 RU")


func test_rack_cell_addressing():
	assert_eq(Constants.rack_cell(0, 0), 0, "Rack 0 slot 0 = cell 0")
	assert_eq(Constants.rack_cell(1, 0), 42, "Rack 1 slot 0 = cell 42")
	assert_eq(Constants.rack_cell(4, 41), 209, "Rack 4 slot 41 = cell 209")


func test_floor_cell_addressing():
	assert_eq(Constants.floor_cell(0), 210, "Floor rack 0 = cell 210")
	assert_eq(Constants.floor_cell(4), 214, "Floor rack 4 = cell 214")


func test_to_world_converts_int_to_float():
	assert_almost_eq(Constants.to_world(2400), 24.0, 0.01, "2400 PU = 24.0 px")
	assert_almost_eq(Constants.to_world(100), 1.0, 0.01, "100 PU = 1.0 px")


func test_from_world_converts_float_to_int():
	assert_eq(Constants.from_world(24.0), 2400, "24.0 px = 2400 PU")
	assert_eq(Constants.from_world(1.0), 100, "1.0 px = 100 PU")


func test_grid_dimensions():
	assert_eq(Constants.HEAT_CELLS_TOTAL, 215, "210 rack + 5 floor = 215 cells")
	assert_eq(Constants.SLOTS_PER_RACK, 42, "42 U per rack")
	assert_eq(Constants.RACK_COUNT, 5, "5 racks")
