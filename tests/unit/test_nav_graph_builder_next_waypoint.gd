extends GutTest

# AI-DEV: AI **MUST NOT** touch this test. If the test is failing, it is
# because you removed or broke code.

# Movement responsibility lives on the navgraph: when a species' from->to
# pair has no traversable path, next_waypoint_or_stay must return `from`
# unchanged. The mover then takes a zero-step (stays put) until the AI
# layer reassigns the target. Without this, the previous fallback returned
# `target` directly and the mover walked the entity straight at an
# unreachable rack-mounted object — the cause of the "ferret hovering
# above the rack" regression after real-Y rendering shipped.


func _slot_world_center(rack: int, slot: int) -> Vector2i:
	var rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	return Vector2i(
		rect.position.x + rect.size.x / 2,
		rect.position.y + rect.size.y / 2,
	)


func test_no_path_returns_from_unchanged() -> void:
	# Ferret has no `jumps` and no rack-slot nodes have been added; the
	# path floor->slot 5 cannot exist.
	var b := NavGraphBuilder.new()
	b.register_species(
		&"floorbound", {&"walks": {}}, {&"size_ru": 1},
	)
	b.build()
	var floor_pos: Vector2 = b.get_nearest_floor_node(2)
	var from_px := Vector2i(int(floor_pos.x), int(floor_pos.y))
	var to_px: Vector2i = _slot_world_center(2, 5)
	var step: Vector2i = b.next_waypoint_or_stay(&"floorbound", from_px, to_px)
	assert_eq(
		step, from_px,
		"unreachable target -> waypoint must be `from` (the entity stays put)",
	)


func test_reachable_target_returns_next_nav_node() -> void:
	# Cat with 3 RU jumps reaches rack 0 slot 1 (one slot above floor)
	# directly. Path length 2: floor_node -> slot1_node. Walking from
	# floor toward slot 1 should yield slot 1 (the next non-current node).
	var b := NavGraphBuilder.new()
	b.register_species(
		&"jumper",
		{&"walks": {}, &"jumps": {&"max_height_ru": 3}},
		{&"size_ru": 2},
	)
	b.build()
	b.add_rack_slot(0, 1)
	var floor_pos: Vector2 = b.get_nearest_floor_node(0)
	var from_px := Vector2i(int(floor_pos.x), int(floor_pos.y))
	var to_px: Vector2i = _slot_world_center(0, 1)
	var step: Vector2i = b.next_waypoint_or_stay(&"jumper", from_px, to_px)
	assert_eq(
		step, to_px,
		"reachable single-edge path returns the target as the next waypoint",
	)


func test_already_at_target_returns_target() -> void:
	# from == to is a no-op: the entity is already there.
	var b := NavGraphBuilder.new()
	b.register_species(&"any", {&"walks": {}}, {&"size_ru": 1})
	b.build()
	var floor_pos: Vector2 = b.get_nearest_floor_node(0)
	var same := Vector2i(int(floor_pos.x), int(floor_pos.y))
	var step: Vector2i = b.next_waypoint_or_stay(&"any", same, same)
	assert_eq(step, same, "from == to -> same point, no movement")
