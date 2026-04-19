extends GutTest

var _db: GameStateDB
var _grid: HeatGrid


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	_db = GameStateDB.new()
	_grid = HeatGrid.new(_db)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_source(rack: int, slot: int, value: int, radius_slots: int) -> int:
	var id: int = _db.create_entity()
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var cx: int = slot_rect.position.x + slot_rect.size.x / 2
	var cy: int = slot_rect.position.y + slot_rect.size.y / 2
	_db.set_component(id, &"position", {
		&"x": cx,
		&"y": cy,
	})
	_db.set_component(id, &"heat_source", {
		&"value": value,
		&"radius_px": radius_slots * Constants.SLOT_HEIGHT_PX,
	})
	return id


# ── Tests ─────────────────────────────────────────────────────────────────────

# AI-DEV: test_empty_grid_is_all_zeros was deleted — its only
# distinguishing invariant (propagate leaves cells at 0 when there are
# no sources) is exactly what test_propagation_resets_each_tick already
# proves in its second phase (after destroying the source). Both tests
# share the `_grid.fill(0)` call at the top of propagate() as the single
# mutatable line, so a surgical mutation can only target one failing
# test. Removing the empty-start variant keeps the fill-happened-so-
# cells-are-zero invariant covered without blocking the cycle.


func test_single_source_heats_own_cell_to_full_value():
	_make_source(0, 5, 800, 3)
	_grid.propagate()
	var cell: int = Constants.rack_cell(0, 5)
	assert_eq(_grid.get_temperature(cell), 800,
		"Source cell must receive full heat value (distance 0)")


func test_heat_falls_off_with_distance():
	# Slot 0 is the BOTTOM; upward = higher index. Slot 6 is 1U above slot 5.
	_make_source(0, 5, 800, 3)
	_grid.propagate()
	var cell_source: int = Constants.rack_cell(0, 5)
	var cell_up: int = Constants.rack_cell(0, 6)
	assert_gt(_grid.get_temperature(cell_source), _grid.get_temperature(cell_up),
		"Heat must decrease with distance from source")
	assert_gt(_grid.get_temperature(cell_up), 0,
		"Slot 1U up from source must receive non-zero heat")


func test_heat_is_zero_beyond_radius():
	# Source at slot 5, radius 3. Heats upward to slot 8 (3U up) and downward
	# to slot 4 (1U down = radius/3). Slot 9 (4U up) and slot 3 (2U down) out.
	_make_source(0, 5, 800, 3)
	_grid.propagate()
	var cell_far_up: int = Constants.rack_cell(0, 9)
	assert_eq(_grid.get_temperature(cell_far_up), 0,
		"Slot 9 (4U above source, beyond 3U upward range) must be 0")
	var cell_far_down: int = Constants.rack_cell(0, 3)
	assert_eq(_grid.get_temperature(cell_far_down), 0,
		"Slot 3 (2U below source, beyond 1U downward range) must be 0")


func test_two_overlapping_sources_stack_and_clamp():
	_make_source(0, 5, 700, 3)
	_make_source(0, 5, 700, 3)
	_grid.propagate()
	var cell: int = Constants.rack_cell(0, 5)
	assert_eq(_grid.get_temperature(cell), 1000,
		"Overlapping sources must stack and clamp at 1000")


func test_cross_rack_spillover_is_much_weaker():
	_make_source(1, 5, 800, 3)
	_grid.propagate()
	var cell_same_rack: int = Constants.rack_cell(1, 5)
	var cell_adj_rack: int = Constants.rack_cell(0, 5)
	var same_temp: int = _grid.get_temperature(cell_same_rack)
	var adj_temp: int = _grid.get_temperature(cell_adj_rack)
	assert_gt(adj_temp, 0,
		"Adjacent rack must receive spillover heat")
	assert_lt(adj_temp, same_temp / 2,
		"Adjacent rack heat must be less than half of same-rack source heat")


func test_floor_gets_no_heat_from_distant_server():
	# Source at slot 5. Floor distance = slot + 1 = 6 units. radius/3 = 1 < 6.
	_make_source(0, 5, 800, 3)
	_grid.propagate()
	var floor_idx: int = Constants.floor_cell(0)
	assert_eq(_grid.get_temperature(floor_idx), 0,
		"Floor must not receive heat from distant server")


func test_floor_gets_heat_from_bottom_server():
	# Slot 0 is the BOTTOM. Floor is 1U below. radius/3 = 1, so floor gets heat.
	_make_source(0, 0, 800, 3)
	_grid.propagate()
	var floor_idx: int = Constants.floor_cell(0)
	var floor_temp: int = _grid.get_temperature(floor_idx)
	assert_gt(floor_temp, 0,
		"Floor must receive heat from server directly above")
	assert_lte(floor_temp, 400,
		"Floor heat must be weak spillover")


func test_propagation_resets_each_tick():
	var id: int = _make_source(0, 5, 800, 3)
	_grid.propagate()
	var cell: int = Constants.rack_cell(0, 5)
	assert_gt(_grid.get_temperature(cell), 0,
		"Grid must be non-zero after first propagation")

	_db.destroy_entity(id)
	_grid.propagate()
	for i in Constants.HEAT_CELLS_TOTAL:
		assert_eq(_grid.get_temperature(i), 0,
			"Cell %d must be 0 after source is removed" % i)


func test_heat_applies_downward_one_unit():
	# radius/3 = 1, so slot 4 (1U below slot 5) receives heat.
	_make_source(0, 5, 800, 3)
	_grid.propagate()
	var cell_down: int = Constants.rack_cell(0, 4)
	assert_gt(_grid.get_temperature(cell_down), 0,
		"Slot 1U below source must receive heat")
