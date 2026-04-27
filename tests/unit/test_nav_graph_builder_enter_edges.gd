extends GutTest

# AI-DEV: AI **MUST NOT** touch this test. If the test is failing, it is
# because you removed or broke code.

# add_box_enterable adds entry + interior nodes and emits JUMP_UP + ENTER
# edges per species, gated on body_capabilities.


func _box_join() -> Dictionary:
	return {
		&"type": &"contained",
		&"capacity": 5,
		&"entry_origin_offset": Vector2i(0, -16),
		&"interior_origin_offset": Vector2i(0, -8),
		&"entry_threshold_ru": 1,
		&"inner_size_ru": 2,
	}


func _builder() -> NavGraphBuilder:
	var b := NavGraphBuilder.new()
	b.register_species(
		&"big_cat",
		{
			&"walks": {},
			&"jumps": {&"max_height_ru": 99},
			&"settles_in_containers": {&"max_body_size_ru": 4},
		},
		{&"size_ru": 2},
	)
	b.register_species(
		&"small_kitten",
		{
			&"walks": {},
			&"jumps": {&"max_height_ru": 99},
			&"settles_in_containers": {&"max_body_size_ru": 1},
		},
		{&"size_ru": 1},
	)
	b.register_species(
		&"big_dog",
		{
			&"walks": {},
			&"jumps": {&"max_height_ru": 99},
			&"settles_in_containers": {&"max_body_size_ru": 8},
		},
		{&"size_ru": 4},  # too big to fit inner_size_ru=2
	)
	b.register_species(
		&"floorbound", {&"walks": {}}, {&"size_ru": 2},
	)  # cannot jump
	b.build()
	return b


func _interior_pos(rack: int, slot: int) -> Vector2:
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var cx: float = float(slot_rect.position.x + slot_rect.size.x / 2)
	var cy: float = float(slot_rect.position.y + slot_rect.size.y / 2)
	# interior_origin_offset = (0, -8)
	return Vector2(cx, cy - 8.0)


func test_enter_edge_emitted_when_body_fits_and_can_jump() -> void:
	var b: NavGraphBuilder = _builder()
	b.add_box_enterable(0, 1, _box_join())
	var floor_pos: Vector2 = b.get_nearest_floor_node(0)
	var interior: Vector2 = _interior_pos(0, 1)
	assert_true(b.can_reach(&"big_cat", floor_pos, interior))


func test_enter_edge_not_emitted_when_body_too_big() -> void:
	var b: NavGraphBuilder = _builder()
	b.add_box_enterable(0, 1, _box_join())
	var floor_pos: Vector2 = b.get_nearest_floor_node(0)
	var interior: Vector2 = _interior_pos(0, 1)
	assert_false(
		b.can_reach(&"big_dog", floor_pos, interior),
		"dog body_size_ru=4 exceeds inner_size_ru=2; no ENTER edge",
	)


func test_enter_edge_emitted_for_kitten() -> void:
	var b: NavGraphBuilder = _builder()
	b.add_box_enterable(0, 1, _box_join())
	var floor_pos: Vector2 = b.get_nearest_floor_node(0)
	var interior: Vector2 = _interior_pos(0, 1)
	assert_true(b.can_reach(&"small_kitten", floor_pos, interior))


func test_enter_edge_not_emitted_when_cannot_jump_to_entry() -> void:
	var b: NavGraphBuilder = _builder()
	b.add_box_enterable(0, 1, _box_join())
	var floor_pos: Vector2 = b.get_nearest_floor_node(0)
	var interior: Vector2 = _interior_pos(0, 1)
	assert_false(
		b.can_reach(&"floorbound", floor_pos, interior),
		"floorbound has no jumps capability; cannot reach the box's entry",
	)
