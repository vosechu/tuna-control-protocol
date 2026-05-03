extends GutTest

# AI-DEV: AI **MUST NOT** touch this test. If the test is failing, it is
# because you removed or broke code.

# JUMP_UP edges are gated on the species' max_height_ru. Slots above the
# floor are wired iff (slot.y - floor.y) <= max_height_ru * SLOT_HEIGHT_PX.


func _slot_world_center(rack: int, slot: int) -> Vector2:
	var rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	return Vector2(
		float(rect.position.x + rect.size.x / 2),
		float(rect.position.y + rect.size.y / 2),
	)


func _builder_with_jumper(max_height_ru: int) -> NavGraphBuilder:
	var b := NavGraphBuilder.new()
	b.register_species(
		&"test:species",
		{&"walks": {}, &"jumps": {&"max_height_ru": max_height_ru}},
		{&"size_ru": 2},
	)
	b.build()
	return b


func test_jump_up_edge_emitted_when_within_max_height() -> void:
	# Slot 1 is one slot above the rack's bottom — close to the floor. With
	# max_height_ru: 3 the cat clears it.
	var b := _builder_with_jumper(3)
	b.add_rack_slot(0, 1)
	var floor_pos: Vector2 = b.get_nearest_floor_node(0)
	var slot_pos: Vector2 = _slot_world_center(0, 1)
	assert_true(
		b.can_reach(&"test:species", floor_pos, slot_pos),
		"1-slot jump should succeed when max_height_ru=3",
	)


func test_jump_up_edge_not_emitted_when_too_short() -> void:
	# max_height_ru: 0 means the species has the `jumps` verb but with zero
	# reach — no edge should be wired.
	var b := _builder_with_jumper(0)
	b.add_rack_slot(0, 1)
	var floor_pos: Vector2 = b.get_nearest_floor_node(0)
	var slot_pos: Vector2 = _slot_world_center(0, 1)
	assert_false(
		b.can_reach(&"test:species", floor_pos, slot_pos),
		"0-RU jump capability cannot reach any slot",
	)


func test_jumps_capability_absent_means_no_edge() -> void:
	var b := NavGraphBuilder.new()
	b.register_species(
		&"floorbound", {&"walks": {}}, {&"size_ru": 1},
	)
	b.build()
	b.add_rack_slot(0, 1)
	var floor_pos: Vector2 = b.get_nearest_floor_node(0)
	var slot_pos: Vector2 = _slot_world_center(0, 1)
	assert_false(
		b.can_reach(&"floorbound", floor_pos, slot_pos),
		"Without `jumps` capability, no JUMP_UP edge is emitted",
	)
