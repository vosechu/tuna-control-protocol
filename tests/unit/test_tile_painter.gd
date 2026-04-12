extends GutTest

const _PAINTER_SCRIPT := preload("res://engine/environment/tile_painter.gd")


class _MockTileMap:
	var cells: Array = []

	func set_cell(layer: int, coords: Vector2i, source_id: int = -1,
			atlas_coords: Vector2i = Vector2i(-1, -1)) -> void:
		cells.append({
			&"layer": layer,
			&"coords": coords,
			&"source_id": source_id,
			&"atlas_coords": atlas_coords,
		})

	func clear() -> void:
		cells.clear()


func test_paint_bay_0_paints_ceiling_row():
	var mock := _MockTileMap.new()
	var painter = _PAINTER_SCRIPT.new(mock)
	painter.paint_bay(0)
	var ceiling_cells: Array = mock.cells.filter(
		func(c): return c[&"coords"].y == 0
	)
	assert_gt(ceiling_cells.size(), 0,
		"Painting bay 0 should paint at least one ceiling cell")


func test_paint_bay_0_paints_wall_fill():
	var mock := _MockTileMap.new()
	var painter = _PAINTER_SCRIPT.new(mock)
	painter.paint_bay(0)
	var wall_cells: Array = mock.cells.filter(
		func(c): return c[&"coords"].y >= 2 and c[&"coords"].y <= 13
	)
	assert_gt(wall_cells.size(), 0, "Wall fill rows should be painted")


func test_paint_bay_0_paints_ground_row():
	var mock := _MockTileMap.new()
	var painter = _PAINTER_SCRIPT.new(mock)
	painter.paint_bay(0)
	var ground_cells: Array = mock.cells.filter(
		func(c): return c[&"coords"].y >= 20 and c[&"coords"].y <= 22
	)
	assert_gt(ground_cells.size(), 0, "Ground strip should be painted")


func test_paint_bay_negative_one_offsets_left():
	var mock := _MockTileMap.new()
	var painter = _PAINTER_SCRIPT.new(mock)
	painter.paint_bay(-1)
	var min_x: int = 99999
	for cell in mock.cells:
		min_x = mini(min_x, cell[&"coords"].x)
	assert_lt(min_x, 0, "Bay -1 cells should be at negative x")


func test_paint_bay_one_offsets_right():
	var mock := _MockTileMap.new()
	var painter = _PAINTER_SCRIPT.new(mock)
	painter.paint_bay(1)
	var max_x: int = -99999
	for cell in mock.cells:
		max_x = maxi(max_x, cell[&"coords"].x)
	@warning_ignore("integer_division")
	var expected_min: int = Constants.BAY_STRIDE_PX / 16
	assert_gt(max_x, expected_min, "Bay 1 cells should be at positive x beyond BAY_STRIDE_PX")


func test_clear_bay_removes_cells():
	var mock := _MockTileMap.new()
	var painter = _PAINTER_SCRIPT.new(mock)
	painter.paint_bay(0)
	var count_before: int = mock.cells.size()
	assert_gt(count_before, 0, "Bay should have cells before clear")
	painter.clear_bay(0)
	var cleared: Array = mock.cells.filter(func(c): return c[&"source_id"] == -1)
	assert_gt(cleared.size(), 0, "clear_bay should emit clear-cell calls")
