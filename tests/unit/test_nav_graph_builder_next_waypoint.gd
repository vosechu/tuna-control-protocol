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


func test_same_domain_walks_direct_to_target_nav_node() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Pins the "same-domain final-approach" contract: when from and to both
	# resolve to the SAME nearest nav node (entity is in that node's domain
	# but a few pixels short of it), `get_id_path` returns a single-element
	# path and the previous `path.size() > 1` guard treated this as "no
	# path" — entity stayed put forever at e.g. (67, 110) while its target
	# nav node sat at (67, 104). The contract: walk straight to the target's
	# nav node so arrival can fire on the move loop's next pass.
	var b := NavGraphBuilder.new()
	b.register_species(
		&"jumper",
		{&"walks": {}, &"jumps": {&"max_height_ru": 3}},
		{&"size_ru": 1},
	)
	b.build()
	b.add_rack_slot(0, 0)
	var slot0_px: Vector2i = _slot_world_center(0, 0)
	# Entity is 6 px below the slot 0 nav node — closer to slot 0 than
	# to the floor node, so closest_point returns slot 0 for both from
	# and to. The previous code returned fallback.
	var from_px := Vector2i(slot0_px.x, slot0_px.y + 6)
	var to_px: Vector2i = slot0_px
	var step: Vector2i = b.next_waypoint_or_stay(&"jumper", from_px, to_px)
	assert_eq(
		step, slot0_px,
		"same-domain final-approach must return the target node, not fallback",
	)


func test_off_anchor_position_advances_not_retreats() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Pins the "no 2-px ping-pong" contract: when an entity is in transit
	# between two floor nodes (not exactly at a nav node), the closest
	# nav-node lookup still returns the anchor *behind* the entity. The
	# previous waypoint loop returned that anchor, snapping the animal
	# backward, so the next tick the closest-point flipped and walked it
	# forward again — visible in-game as animals oscillating between two
	# pixels on the floor instead of patrolling. The fix: skip the anchor
	# (path[0]) and step toward path[1], which is always the next nav node
	# along the route.
	var b := NavGraphBuilder.new()
	b.register_species(&"walker", {&"walks": {}}, {&"size_ru": 1})
	b.build()
	var floor0: Vector2 = b.get_nearest_floor_node(0)
	var floor1: Vector2 = b.get_nearest_floor_node(1)
	var floor2: Vector2 = b.get_nearest_floor_node(2)
	# Entity is 2 px past floor0 (one ANIMAL_SPEED_PX step into the route
	# toward floor2). The closest nav node is still floor0 — the anchor.
	var from_px := Vector2i(int(floor0.x) + 2, int(floor0.y))
	var to_px := Vector2i(int(floor2.x), int(floor2.y))
	var step: Vector2i = b.next_waypoint_or_stay(&"walker", from_px, to_px)
	var expected := Vector2i(int(floor1.x), int(floor1.y))
	assert_eq(
		step, expected,
		"off-anchor entity must advance to the next nav node, not snap back to the anchor",
	)


func test_multi_hop_path_returns_next_intermediate_not_target() -> void:
	# Pins the "step toward, don't teleport" contract — a regression that
	# returned path[size-1] would silently let animals snap to a multi-hop
	# target on tick 1.
	#
	# Setup: max_height_ru: 2 (16 px) gates the direct floor->slot 1 edge
	# (slot 1 sits 24 px above floor) while still permitting floor->slot 0
	# (slot 0 sits 16 px above floor). The only path is then
	# floor -> slot 0 -> slot 1, and stepping from floor must return slot 0.
	var b := NavGraphBuilder.new()
	b.register_species(
		&"low_jumper",
		{&"walks": {}, &"jumps": {&"max_height_ru": 2}},
		{&"size_ru": 1},
	)
	b.build()
	b.add_rack_slot(0, 0)
	b.add_rack_slot(0, 1)
	var floor_pos: Vector2 = b.get_nearest_floor_node(0)
	var from_px := Vector2i(int(floor_pos.x), int(floor_pos.y))
	var slot0_px: Vector2i = _slot_world_center(0, 0)
	var slot1_px: Vector2i = _slot_world_center(0, 1)
	var step: Vector2i = b.next_waypoint_or_stay(
		&"low_jumper", from_px, slot1_px,
	)
	assert_eq(
		step, slot0_px,
		"multi-hop path must step to slot 0 first, not jump straight to slot 1",
	)
