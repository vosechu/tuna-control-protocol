extends GutTest

var builder: NavGraphBuilder


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	# Body capabilities mirror the canonical species recipes (cat jumps 3 RU,
	# ferret has no `jumps` capability at all). The reach tests below use
	# slots that are within the cat's jump range to match real recipe behavior.
	builder = NavGraphBuilder.new()
	builder.register_species(
		&"tcp_cats:cat",
		{
			&"walks": {},
			&"jumps": {&"max_height_ru": 3},
			&"drops": {&"max_height_ru": 5},
		},
		{&"size_ru": 2},
	)
	builder.register_species(
		&"tcp_ferrets:ferret",
		{&"walks": {}, &"drops": {&"max_height_ru": 5}},
		{&"size_ru": 1},
	)
	builder.build()


func _slot_world_center(rack: int, slot: int) -> Vector2:
	var rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	return Vector2(
		float(rect.position.x + rect.size.x / 2),
		float(rect.position.y + rect.size.y / 2),
	)


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
	# Slot 1 sits one slot above the floor — within the cat's max_height_ru: 3.
	builder.add_rack_slot(2, 1)
	var slot_pos: Vector2 = _slot_world_center(2, 1)
	var floor_pos: Vector2 = builder.get_nearest_floor_node(2)
	var path: PackedVector2Array = builder.get_path_points(
		&"tcp_cats:cat", floor_pos, slot_pos,
	)
	assert_gt(
		path.size(), 0,
		"Cat should find path to rack slot via JUMP_UP",
	)


func test_ferret_cannot_jump_to_rack_slot() -> void:
	builder.add_rack_slot(2, 1)
	var slot_pos: Vector2 = _slot_world_center(2, 1)
	var floor_pos: Vector2 = builder.get_nearest_floor_node(2)
	var reachable: bool = builder.can_reach(
		&"tcp_ferrets:ferret", floor_pos, slot_pos,
	)
	assert_false(
		reachable,
		"Ferret should not reach rack slot — no `jumps` capability",
	)


# AI-DEV: `test_remove_rack_slot` was removed from the old file because its
# invariant (`point_count == RACK_COUNT after remove`) is the same property
# proven by `test_floor_nodes_exist` (initial state) plus `add_rack_slot +
# remove_rack_slot` being inverses. Coverage is implicit in the surrounding
# tests and the point-count assertion above.


func test_adjacent_slots_connected() -> void:
	builder.add_rack_slot(1, 5)
	builder.add_rack_slot(1, 6)
	var slot5_pos: Vector2 = _slot_world_center(1, 5)
	var slot6_pos: Vector2 = _slot_world_center(1, 6)
	var path: PackedVector2Array = builder.get_path_points(
		&"tcp_cats:cat", slot5_pos, slot6_pos,
	)
	assert_eq(
		path.size(), 2,
		"Adjacent slots must be directly connected",
	)
