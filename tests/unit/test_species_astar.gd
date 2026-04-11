extends GutTest

var builder: NavGraphBuilder


func before_each() -> void:
	builder = NavGraphBuilder.new()
	builder.register_species(
		&"tcp_cats:cat", ["WALK", "JUMP_UP", "JUMP_DOWN"],
	)
	builder.register_species(
		&"tcp_ferrets:ferret", ["WALK", "JUMP_DOWN"],
	)
	builder.build()


func test_floor_nodes_exist() -> void:
	var astar: AStar2D = builder.get_astar(&"tcp_cats:cat")
	assert_eq(
		astar.get_point_count(), Constants.RACK_COUNT,
		"Should have one floor node per rack in cat astar",
	)


func test_floor_nodes_connected() -> void:
	var path: PackedVector2Array = builder.get_path_points(
		&"tcp_cats:cat",
		builder.get_nearest_floor_node(0),
		builder.get_nearest_floor_node(4),
	)
	assert_gt(
		path.size(), 0, "Should find path across floor",
	)


func test_cat_can_jump_to_rack_slot() -> void:
	builder.add_rack_slot(2, 38)
	@warning_ignore("integer_division")
	var slot_pos: Vector2 = Vector2(
		float(
			2 * Constants.RACK_STRIDE_PU
			+ Constants.RACK_STRIDE_PU / 2
		),
		float(38 * Constants.SLOT_HEIGHT_PU),
	)
	var floor_pos: Vector2 = builder.get_nearest_floor_node(2)
	var path: PackedVector2Array = builder.get_path_points(
		&"tcp_cats:cat", floor_pos, slot_pos,
	)
	assert_gt(
		path.size(), 0,
		"Cat should find path to rack slot via JUMP_UP",
	)


func test_ferret_cannot_jump_to_rack_slot() -> void:
	builder.add_rack_slot(2, 38)
	@warning_ignore("integer_division")
	var slot_pos: Vector2 = Vector2(
		float(
			2 * Constants.RACK_STRIDE_PU
			+ Constants.RACK_STRIDE_PU / 2
		),
		float(38 * Constants.SLOT_HEIGHT_PU),
	)
	var floor_pos: Vector2 = builder.get_nearest_floor_node(2)
	var reachable: bool = builder.can_reach(
		&"tcp_ferrets:ferret", floor_pos, slot_pos,
	)
	assert_false(
		reachable,
		"Ferret should not reach rack slot — no JUMP_UP",
	)


func test_remove_rack_slot() -> void:
	builder.add_rack_slot(2, 38)
	builder.remove_rack_slot(2, 38)
	var astar: AStar2D = builder.get_astar(&"tcp_cats:cat")
	assert_eq(
		astar.get_point_count(), Constants.RACK_COUNT,
		"After removal, only floor nodes should remain",
	)


func test_adjacent_slots_connected() -> void:
	builder.add_rack_slot(1, 20)
	builder.add_rack_slot(1, 21)
	@warning_ignore("integer_division")
	var slot20_pos: Vector2 = Vector2(
		float(
			1 * Constants.RACK_STRIDE_PU
			+ Constants.RACK_STRIDE_PU / 2
		),
		float(20 * Constants.SLOT_HEIGHT_PU),
	)
	@warning_ignore("integer_division")
	var slot21_pos: Vector2 = Vector2(
		float(
			1 * Constants.RACK_STRIDE_PU
			+ Constants.RACK_STRIDE_PU / 2
		),
		float(21 * Constants.SLOT_HEIGHT_PU),
	)
	var path: PackedVector2Array = builder.get_path_points(
		&"tcp_cats:cat", slot20_pos, slot21_pos,
	)
	assert_eq(
		path.size(), 2,
		"Adjacent slots must be directly connected",
	)
