extends GutTest

# AI-DEV: Covers the new three-layer addressing API. Every test in this file
# should survive Commit 5 (old API deletion) untouched — the new API is the
# contract.
#
# Y-axis invariant coverage: slot 0 at the bottom (larger Y) and slot 9 at the
# top (smaller Y) is proven by the combination of
# test_rack_frame_rect_sits_above_top_slot (pins slot 9 to frame) and
# test_rack_baseboard_rect_sits_below_bottom_slot (pins slot 0 to baseboard).
# No separate Y-ordering test is needed — the relative-position checks in
# those two tests cover it structurally.


func test_slot_rect_dimensions_match_server_size() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	var rect: Rect2i = Constants.slot_rect_world(0, 0, 0)
	assert_eq(rect.size, Vector2i(23, 8),
		"slot rect must be 23×8 px (server footprint)")


func test_rack_frame_rect_sits_above_top_slot() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	var top_slot: Rect2i = Constants.slot_rect_world(0, 0, 9)
	var frame: Rect2i = Constants.rack_frame_rect(0, 0)
	assert_eq(frame.end.y, top_slot.position.y,
		"frame bottom edge must meet top of slot 9")
	assert_eq(frame.size.y, 12,
		"frame is 12 px tall (rack top frame)")


func test_rack_baseboard_rect_sits_below_bottom_slot() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	var bottom_slot: Rect2i = Constants.slot_rect_world(0, 0, 0)
	var base: Rect2i = Constants.rack_baseboard_rect(0, 0)
	assert_eq(base.position.y, bottom_slot.end.y,
		"baseboard top edge must meet bottom of slot 0")
	assert_eq(base.size.y, 4,
		"baseboard is 4 px tall")


func test_floor_rect_sits_below_baseboard() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	var base: Rect2i = Constants.rack_baseboard_rect(0, 0)
	var floor_r: Rect2i = Constants.floor_rect_world(0)
	assert_eq(floor_r.position.y, base.end.y,
		"floor top edge meets baseboard bottom edge")
	assert_eq(floor_r.size.y, 16, "floor is 16 px tall")


func test_rack_horizontal_stride_is_31px() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	var r0: Rect2i = Constants.slot_rect_world(0, 0, 0)
	var r1: Rect2i = Constants.slot_rect_world(0, 1, 0)
	assert_eq(r1.position.x - r0.position.x, 31,
		"adjacent rack cells are 31 px apart")


func test_bay_index_round_trip_through_world_to_bay() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	for bay: int in [0, 1, 2, 3]:
		var origin: Vector2i = Constants.bay_origin_world(bay)
		assert_eq(Constants.world_to_bay(origin), bay,
			"world_to_bay must return the bay we pulled origin from")


func test_world_to_bay_returns_invalid_for_gap_positions() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	# Between bays there's a gap; points there have no owning bay.
	var bay0_end: Vector2i = Constants.bay_rect_world(0).end
	var far_right: Vector2i = Vector2i(bay0_end.x + 1000, bay0_end.y)
	# World positions past the last known bay are INVALID.
	assert_eq(Constants.world_to_bay(far_right), Constants.INVALID_BAY,
		"points past known bays must return INVALID_BAY")


func test_bay_local_to_slot_finds_slot_when_inside_slot_rect() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	var rect: Rect2i = Constants.slot_rect_world(0, 2, 5)
	var center: Vector2i = rect.position + rect.size / 2
	var q: SlotQuery = Constants.bay_local_to_slot(0, center)
	assert_eq(q.zone, &"slot")
	assert_eq(q.rack, 2)
	assert_eq(q.get_slot(), 5)


func test_bay_local_to_slot_tags_frame_zone() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	var frame: Rect2i = Constants.rack_frame_rect(0, 1)
	var center: Vector2i = frame.position + frame.size / 2
	var q: SlotQuery = Constants.bay_local_to_slot(0, center)
	assert_eq(q.zone, &"frame")
	assert_eq(q.get_rack(), 1)


func test_bay_local_to_slot_tags_floor_zone() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	var floor_r: Rect2i = Constants.floor_rect_world(0)
	var under_rack_1: Vector2i = Vector2i(
		Constants.rack_frame_rect(0, 1).position.x + 5,
		floor_r.position.y + 2,
	)
	var q: SlotQuery = Constants.bay_local_to_slot(0, under_rack_1)
	assert_eq(q.zone, &"floor")
	assert_eq(q.get_rack(), 1)


func test_bay_local_to_slot_tags_other_for_gap_positions() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	# A point in the horizontal gap between rack cells is &"other".
	var r0: Rect2i = Constants.slot_rect_world(0, 0, 0)
	var gap_point: Vector2i = Vector2i(r0.end.x + 2, r0.position.y + 2)
	var q: SlotQuery = Constants.bay_local_to_slot(0, gap_point)
	assert_eq(q.zone, &"other")


func test_bay_origin_world_x_scales_by_bay_stride() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	# Bug this catches: stride math is broken on its own (e.g. off-by-one
	# multiplication). The round-trip test can pass if bay_origin_world
	# and world_to_bay have compensating bugs; this pins the stride
	# independently. input: bay = 2 — non-degenerate (bay = 0 zeroes out
	# the multiplication and masks the bug).
	assert_eq(Constants.bay_origin_world(2).x, 2 * Constants.BAY_STRIDE_PX,
		"bay_origin_world(2).x must equal 2 * BAY_STRIDE_PX")


func test_rack_interior_spans_exactly_the_slot_column() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	# Bug this catches: rack_interior_rect_world height or Y drifts away
	# from the frame/baseboard boundaries (missing/duplicated frame offset,
	# wrong slot-height arithmetic). Pinning the top and bottom to the
	# frame and baseboard rects makes the three zones structurally adjacent.
	var interior: Rect2i = Constants.rack_interior_rect_world(0, 0)
	var frame: Rect2i = Constants.rack_frame_rect(0, 0)
	var base: Rect2i = Constants.rack_baseboard_rect(0, 0)
	assert_eq(interior.position.y, frame.end.y,
		"rack interior top must meet frame bottom edge")
	assert_eq(interior.end.y, base.position.y,
		"rack interior bottom must meet baseboard top edge")


func test_slot_origin_world_returns_top_left_of_slot_rect() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	# Bug this catches: slot_origin_world returns the rect's center (or
	# any non-top-left corner). The spec commits to top-left; without
	# this assertion a refactor could silently return center and break
	# every placement caller.
	var rect: Rect2i = Constants.slot_rect_world(0, 0, 5)
	var origin: Vector2i = Constants.slot_origin_world(0, 0, 5)
	assert_eq(origin, rect.position,
		"slot_origin_world must return slot_rect_world's position (top-left)")


func test_bay_local_to_slot_tags_baseboard_zone() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	# Bug this catches: the baseboard Y strip is misclassified as &"slot"
	# or &"other" — any off-by-one around the rack-interior/baseboard
	# boundary lets the bottom slot bleed into baseboard or vice versa.
	# The existing zone tests cover slot/frame/floor/other but not
	# baseboard; this is the fifth-zone gap.
	var base: Rect2i = Constants.rack_baseboard_rect(0, 2)
	var center: Vector2i = base.position + base.size / 2
	var q: SlotQuery = Constants.bay_local_to_slot(0, center)
	assert_eq(q.zone, &"baseboard",
		"position inside baseboard rect must tag zone=&'baseboard'")
	assert_eq(q.get_rack(), 2,
		"baseboard zone must carry the rack index above it")


func test_bay_local_to_slot_other_zone_has_invalid_rack_and_slot() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	# Bug this catches: &"other" zone leaves rack or slot populated with
	# a non-sentinel value, so a caller that reads q.rack without first
	# matching on zone gets a plausible-looking but wrong index. The
	# existing other-zone test only pins the zone name.
	var r0: Rect2i = Constants.slot_rect_world(0, 0, 0)
	var gap_point: Vector2i = Vector2i(r0.end.x + 2, r0.position.y + 2)
	var q: SlotQuery = Constants.bay_local_to_slot(0, gap_point)
	assert_eq(q.rack, Constants.INVALID_ID,
		"rack must be INVALID_ID in &'other' zone")
	assert_eq(q.slot, Constants.INVALID_SLOT,
		"slot must be INVALID_SLOT in &'other' zone")


func test_bay_local_to_slot_tags_other_in_left_margin_over_floor() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	# Bug this catches: the rack-lookup loop's left X-bound is missing,
	# so a margin-over-floor point is misattributed to rack 0's floor
	# column (zone=&"floor", rack=0) instead of unowned &"other". Y is
	# deliberately inside the floor strip — at slot or frame Y, the
	# per-zone rects filter the bug out through their own X-bounds and
	# the test cannot distinguish correct from buggy behavior.
	# input: X = 10 within bay 0 (< 25 where rack 0 begins), Y on the
	# floor strip so a bad rack match reaches floor.has_point and
	# produces an observably different zone.
	var floor_r: Rect2i = Constants.floor_rect_world(0)
	var left_margin_floor: Vector2i = Vector2i(10, floor_r.position.y + 2)
	var q: SlotQuery = Constants.bay_local_to_slot(0, left_margin_floor)
	assert_eq(q.zone, &"other",
		"margin-over-floor point must tag zone=&'other', not claim rack 0")


func test_slots_per_rack_constant_is_ten() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	# Bug this catches: the slot-count contract silently drifts (9 or 11).
	# Every consumer of slot indices depends on this being 10; an
	# accidental change breaks save migration, placement, and the Y
	# inversion formula all at once. Explicit contract pin.
	assert_eq(Constants.SLOTS_PER_RACK, 10,
		"SLOTS_PER_RACK is the public contract for rack capacity")


func test_rack_count_constant_is_five() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it is failing, it
	# is because you removed or broke code.
	# Bug this catches: RACK_COUNT drifts (4 or 6), breaking every caller
	# that iterates racks. Public contract pin.
	assert_eq(Constants.RACK_COUNT, 5,
		"RACK_COUNT is the public contract for racks per bay")
