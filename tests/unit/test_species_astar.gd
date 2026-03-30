extends GutTest

var builder: NavGraphBuilder


func before_each() -> void:
	builder = NavGraphBuilder.new()


func test_floor_nodes_exist() -> void:
	var astar: AStar2D = builder.get_astar()
	assert_eq(astar.get_point_count(), Constants.RACK_COUNT,
		"Should have one floor node per rack in cat astar")


func test_floor_nodes_connected() -> void:
	# Path from rack 0 to rack 4 should exist for a cat
	var path: PackedVector2Array = builder.get_path_points(
		&"tcp_base:cat",
		builder.get_nearest_floor_node(0),
		builder.get_nearest_floor_node(4)
	)
	assert_gt(path.size(), 0, "Should find path across floor")


func test_cat_can_jump_to_rack_slot() -> void:
	builder.add_rack_slot(2, 38)
	@warning_ignore("integer_division")
	var slot_pos: Vector2 = Vector2(
		float(2 * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2),
		float(38 * Constants.SLOT_HEIGHT_PU)
	)
	var floor_pos: Vector2 = builder.get_nearest_floor_node(2)
	var path: PackedVector2Array = builder.get_path_points(&"tcp_base:cat", floor_pos, slot_pos)
	assert_gt(path.size(), 0, "Cat should find path to rack slot via JUMP_UP")


func test_ferret_cannot_jump_to_rack_slot() -> void:
	builder.add_rack_slot(2, 38)
	@warning_ignore("integer_division")
	var slot_pos: Vector2 = Vector2(
		float(2 * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2),
		float(38 * Constants.SLOT_HEIGHT_PU)
	)
	var floor_pos: Vector2 = builder.get_nearest_floor_node(2)
	# Ferret has no JUMP_UP capability, so slot node is disconnected in ferret's AStar instance
	var reachable: bool = builder.can_reach(&"tcp_base:ferret", floor_pos, slot_pos)
	assert_false(reachable, "Ferret should not reach rack slot — no JUMP_UP capability")


func test_remove_rack_slot() -> void:
	builder.add_rack_slot(2, 38)
	builder.remove_rack_slot(2, 38)
	var astar: AStar2D = builder.get_astar()
	assert_eq(astar.get_point_count(), Constants.RACK_COUNT,
		"After removal, only floor nodes should remain")


func test_adjacent_slots_connected() -> void:
	builder.add_rack_slot(1, 20)
	builder.add_rack_slot(1, 21)
	@warning_ignore("integer_division")
	var slot20_pos: Vector2 = Vector2(
		float(1 * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2),
		float(20 * Constants.SLOT_HEIGHT_PU)
	)
	@warning_ignore("integer_division")
	var slot21_pos: Vector2 = Vector2(
		float(1 * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2),
		float(21 * Constants.SLOT_HEIGHT_PU)
	)
	var path: PackedVector2Array = builder.get_path_points(&"tcp_base:cat", slot20_pos, slot21_pos)
	assert_gt(path.size(), 0, "Adjacent rack slots should be connected by WALK edges")


func test_can_reach_returns_true_for_cat_to_slot() -> void:
	builder.add_rack_slot(0, 40)
	@warning_ignore("integer_division")
	var slot_pos: Vector2 = Vector2(
		float(0 * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2),
		float(40 * Constants.SLOT_HEIGHT_PU)
	)
	var floor_pos: Vector2 = builder.get_nearest_floor_node(0)
	var reachable: bool = builder.can_reach(&"tcp_base:cat", floor_pos, slot_pos)
	assert_true(reachable, "Cat should be able to reach rack slot")


func test_can_reach_returns_false_for_ferret_to_slot() -> void:
	builder.add_rack_slot(0, 40)
	@warning_ignore("integer_division")
	var slot_pos: Vector2 = Vector2(
		float(0 * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2),
		float(40 * Constants.SLOT_HEIGHT_PU)
	)
	var floor_pos: Vector2 = builder.get_nearest_floor_node(0)
	var reachable: bool = builder.can_reach(&"tcp_base:ferret", floor_pos, slot_pos)
	assert_false(reachable, "Ferret should not be able to reach rack slot")
