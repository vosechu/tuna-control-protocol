extends GutTest


func test_heat_grid_has_55_cells():
	assert_eq(Constants.HEAT_CELLS_TOTAL, 55,
		"Heat grid should have 55 cells (10x5 + 5)")


func test_heat_grid_propagation_under_budget():
	var db := GameStateDB.new()
	var heat := HeatGrid.new(db)
	for i: int in range(5):
		var eid: int = db.create_entity()
		# Use raw rack*stride positioning (same as test_heat_grid.gd helper)
		# to stay within the 5-rack grid bounds.
		db.set_component(eid, &"position", {
			&"x": i * Constants.RACK_STRIDE_PX,
			&"y": 5 * Constants.SLOT_HEIGHT_PX,
		})
		db.set_component(eid, &"heat_source", {
			&"value": 800, &"radius_px": 3,
		})
	var start: int = Time.get_ticks_usec()
	for _i: int in 100:
		heat.propagate()
	var avg_us: int = (Time.get_ticks_usec() - start) / 100
	assert_lt(avg_us, 200,
		"Propagation avg %dus should be <200us" % avg_us)
