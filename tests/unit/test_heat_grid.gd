extends GutTest

var _db: GameStateDB
var _grid: HeatGrid


func before_each() -> void:
	_db = GameStateDB.new()
	_grid = HeatGrid.new(_db)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_source(rack: int, slot: int, value: int, radius: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {
		&"x": rack * Constants.RACK_STRIDE_PU,
		&"y": slot * Constants.SLOT_HEIGHT_PU,
	})
	_db.set_component(id, &"heat_source", {
		&"value": value,
		&"radius_ru": radius,
	})
	return id


# ── Tests ─────────────────────────────────────────────────────────────────────

func test_empty_grid_is_all_zeros():
	# No sources: every cell must be 0 after propagation.
	_grid.propagate()
	for i in Constants.HEAT_CELLS_TOTAL:
		assert_eq(_grid.get_temperature(i), 0,
			"Cell %d must be 0 when no sources exist" % i)


func test_single_source_heats_own_cell_to_full_value():
	# A source at slot 20, rack 0 should receive its full heat value at distance 0.
	_make_source(0, 20, 800, 3)
	_grid.propagate()
	var cell: int = Constants.rack_cell(0, 20)
	assert_eq(_grid.get_temperature(cell), 800,
		"Source cell must receive full heat value (distance 0)")


func test_heat_falls_off_with_distance():
	# Cell at distance 1 must be weaker than cell at distance 0.
	_make_source(0, 20, 800, 3)
	_grid.propagate()
	var cell_source: int = Constants.rack_cell(0, 20)
	var cell_adjacent: int = Constants.rack_cell(0, 19)  # 1U up from source
	assert_gt(_grid.get_temperature(cell_source), _grid.get_temperature(cell_adjacent),
		"Heat must decrease with distance from source")
	assert_gt(_grid.get_temperature(cell_adjacent), 0,
		"Adjacent cell must receive non-zero heat")


func test_heat_is_zero_beyond_radius():
	# A source with radius 3 at slot 20 must not heat slot 24+ (beyond 1U down = slot 21).
	# The upward range: slots 17-20 (3U up). Downward: slot 21 (1U down). Slot 22+ = zero.
	_make_source(0, 20, 800, 3)
	_grid.propagate()
	var cell_beyond: int = Constants.rack_cell(0, 22)
	assert_eq(_grid.get_temperature(cell_beyond), 0,
		"Slot 22 (2U below source, beyond 1U downward range) must be 0")
	var cell_far_up: int = Constants.rack_cell(0, 16)
	assert_eq(_grid.get_temperature(cell_far_up), 0,
		"Slot 16 (4U above source, beyond 3U upward range) must be 0")


func test_two_overlapping_sources_stack_and_clamp():
	# Two sources heating the same cell: values add but clamp at 1000.
	_make_source(0, 20, 700, 3)
	_make_source(0, 20, 700, 3)
	_grid.propagate()
	var cell: int = Constants.rack_cell(0, 20)
	# 700 + 700 = 1400 → clamped to 1000
	assert_eq(_grid.get_temperature(cell), 1000,
		"Overlapping sources must stack and clamp at 1000")


func test_cross_rack_spillover_is_much_weaker():
	# Same slot in adjacent rack should receive heat, but less than half of same-rack cell.
	_make_source(1, 20, 800, 3)
	_grid.propagate()
	var cell_same_rack: int = Constants.rack_cell(1, 20)
	var cell_adj_rack: int = Constants.rack_cell(0, 20)
	var same_temp: int = _grid.get_temperature(cell_same_rack)
	var adj_temp: int = _grid.get_temperature(cell_adj_rack)
	assert_gt(adj_temp, 0,
		"Adjacent rack must receive spillover heat")
	assert_lt(adj_temp, same_temp / 2,
		"Adjacent rack heat must be less than half of same-rack source heat")


func test_floor_gets_no_heat_from_distant_server():
	# A server at slot 20 is far from the floor — no floor heat.
	_make_source(0, 20, 800, 3)
	_grid.propagate()
	var floor_idx: int = Constants.floor_cell(0)
	var floor_temp: int = _grid.get_temperature(floor_idx)
	assert_eq(floor_temp, 0,
		"Floor must not receive heat from distant server")


func test_floor_gets_heat_from_bottom_server():
	# A server at slot 41 (directly above floor) spills heat down.
	_make_source(0, 41, 800, 3)
	_grid.propagate()
	var floor_idx: int = Constants.floor_cell(0)
	var floor_temp: int = _grid.get_temperature(floor_idx)
	assert_gt(floor_temp, 0,
		"Floor must receive heat from server directly above")
	assert_lte(floor_temp, 400,
		"Floor heat must be weak spillover")


func test_propagation_resets_each_tick():
	# Add a source, propagate — then remove it, propagate again: grid should be all zeros.
	var id: int = _make_source(0, 20, 800, 3)
	_grid.propagate()
	var cell: int = Constants.rack_cell(0, 20)
	assert_gt(_grid.get_temperature(cell), 0, "Grid must be non-zero after first propagation")

	_db.destroy_entity(id)
	_grid.propagate()
	for i in Constants.HEAT_CELLS_TOTAL:
		assert_eq(_grid.get_temperature(i), 0,
			"Cell %d must be 0 after source is removed and propagation repeats" % i)


func test_heat_applies_downward_one_unit():
	# Source at slot 20 with radius 3 must heat slot 21 (1U down).
	_make_source(0, 20, 800, 3)
	_grid.propagate()
	var cell_down: int = Constants.rack_cell(0, 21)
	assert_gt(_grid.get_temperature(cell_down), 0,
		"Slot 1U below source must receive heat")
