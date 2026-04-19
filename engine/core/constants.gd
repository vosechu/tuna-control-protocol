class_name Constants extends RefCounted

const INVALID_ID: int = -1
const INVALID_BAY: int = -1
const INVALID_SLOT: int = -1

# ── Viewport ──

const VIEWPORT_WIDTH: int = 224   # 14 tiles
const VIEWPORT_HEIGHT: int = 128  # 8 tiles
const VIEWPORT_BOTTOM: int = 128

# ── Grid: rack slot dimensions (world pixels) ──

const SLOT_HEIGHT_PX: int = 8

const RACK_WIDTH_PX: int = 23
const RACK_STRIDE_PX: int = 31
const RACK_GAP_PX: int = 8

const RACK_COUNT: int = 5
const SLOTS_PER_RACK: int = 10
const TOR_SWITCH_SLOTS: int = 0

const FLOOR_HEIGHT_PX: int = 16  # one tile row

# ── Layout Y positions (world pixels, top-down) ──

const CEILING_Y: int = 0         # row 0
const RACK_TOP_Y: int = 16       # row 1 — rack sprite top edge
const RACK_BOTTOM_Y: int = 112   # row 7 — rack sprite bottom (16 + 96)
const FLOOR_Y: int = 112         # top of row 7 — floor surface

# ── Bay layout (world pixels) ──

const LEFTMOST_RACK_OFFSET_PX: int = 25

const BAY_WIDTH_PX: int = 186
const BAY_STRIDE_PX: int = 226
const BAY_PEEK_PX: int = 20

# ── Heat grid (only bay 0 simulated for now) ──

const HEAT_CELLS_RACK: int = SLOTS_PER_RACK * RACK_COUNT  # 50
const HEAT_CELLS_FLOOR: int = RACK_COUNT  # 5
const HEAT_CELLS_TOTAL: int = HEAT_CELLS_RACK + HEAT_CELLS_FLOOR  # 55

# ── Game rules ──

const UNIT: int = 1000
const SWITCH_THRESHOLD: int = 50
const EVAL_TIME_BUDGET_USEC: int = 1000
const ARM_REACH_PX: int = 24  # 3 slot-heights of vertical reach

# AI-DEV: These numbers match the current 5-set rack sprite exactly. If a mod
# pack ships differently-sized rack art, promote them to art-pack config
# loaded by ModLoader. Do not expose them publicly — the helpers' job is to
# hide art measurements behind the three-layer addressing API.
const _SLOT_HEIGHT_PX: int = 8
const _SERVER_WIDTH_PX: int = 23
const _RACK_CELL_WIDTH_PX: int = 24
const _RACK_STRIDE_PX: int = 31
const _RACK_LEFT_MARGIN_PX: int = 16
const _RACK_TOP_FRAME_HEIGHT_PX: int = 12
const _RACK_BOTTOM_FRAME_HEIGHT_PX: int = 4
const _RACK_INTERIOR_HEIGHT_PX: int = 80
const _FLOOR_HEIGHT_PX: int = 16
const _RACK_TOP_Y_IN_BAY: int = 16


# ── Heat grid cell indexing ──

static func rack_cell(rack: int, slot: int) -> int:
	return rack * SLOTS_PER_RACK + slot


static func floor_cell(rack: int) -> int:
	return HEAT_CELLS_RACK + rack


# ── Bay layer ──────────────────────────────────────────────────────────────


static func bay_origin_world(bay: int) -> Vector2i:
	return Vector2i(bay * BAY_STRIDE_PX, 0)


static func bay_rect_world(bay: int) -> Rect2i:
	return Rect2i(bay_origin_world(bay), Vector2i(BAY_WIDTH_PX, VIEWPORT_HEIGHT))


static func bay_center(bay: int) -> Vector2:
	var bay_x: int = bay * BAY_STRIDE_PX + BAY_WIDTH_PX / 2
	var center_y: int = VIEWPORT_HEIGHT / 2
	return Vector2(float(bay_x), float(center_y))


static func world_to_bay(world_pos: Vector2i) -> int:
	# Bays tile at BAY_STRIDE_PX. A position in the "peek" gap between bays
	# returns INVALID_BAY — bay boundaries are exact, not fuzzy.
	if world_pos.x < 0:
		return INVALID_BAY
	var candidate: int = world_pos.x / BAY_STRIDE_PX
	var origin: Vector2i = bay_origin_world(candidate)
	var rect: Rect2i = Rect2i(origin, Vector2i(BAY_WIDTH_PX, VIEWPORT_HEIGHT))
	if rect.has_point(world_pos):
		return candidate
	return INVALID_BAY


# ── Rack layer ──────────────────────────────────────────────────────────────


static func rack_column_rect_world(bay: int, rack: int) -> Rect2i:
	assert(rack >= 0 and rack < RACK_COUNT,
		"rack index %d out of range [0, %d)" % [rack, RACK_COUNT])
	var origin_x: int = bay * BAY_STRIDE_PX + _RACK_LEFT_MARGIN_PX + rack * _RACK_STRIDE_PX
	var origin_y: int = _RACK_TOP_Y_IN_BAY
	var height: int = (
		_RACK_TOP_FRAME_HEIGHT_PX
		+ _RACK_INTERIOR_HEIGHT_PX
		+ _RACK_BOTTOM_FRAME_HEIGHT_PX
	)
	return Rect2i(Vector2i(origin_x, origin_y), Vector2i(_SERVER_WIDTH_PX, height))


static func rack_interior_rect_world(bay: int, rack: int) -> Rect2i:
	var col: Rect2i = rack_column_rect_world(bay, rack)
	return Rect2i(
		Vector2i(col.position.x, col.position.y + _RACK_TOP_FRAME_HEIGHT_PX),
		Vector2i(col.size.x, _RACK_INTERIOR_HEIGHT_PX),
	)


static func rack_frame_rect(bay: int, rack: int) -> Rect2i:
	var col: Rect2i = rack_column_rect_world(bay, rack)
	return Rect2i(col.position, Vector2i(col.size.x, _RACK_TOP_FRAME_HEIGHT_PX))


static func rack_baseboard_rect(bay: int, rack: int) -> Rect2i:
	var col: Rect2i = rack_column_rect_world(bay, rack)
	var base_y: int = col.position.y + _RACK_TOP_FRAME_HEIGHT_PX + _RACK_INTERIOR_HEIGHT_PX
	return Rect2i(
		Vector2i(col.position.x, base_y),
		Vector2i(col.size.x, _RACK_BOTTOM_FRAME_HEIGHT_PX),
	)


# ── Slot layer ──────────────────────────────────────────────────────────────


static func slot_origin_world(bay: int, rack: int, slot: int) -> Vector2i:
	assert(slot >= 0 and slot < SLOTS_PER_RACK,
		"slot index %d out of range [0, %d)" % [slot, SLOTS_PER_RACK])
	var interior: Rect2i = rack_interior_rect_world(bay, rack)
	# Slot 0 is at the BOTTOM — invert inside the helper so callers never flip.
	var from_bottom: int = SLOTS_PER_RACK - 1 - slot
	return Vector2i(
		interior.position.x,
		interior.position.y + from_bottom * _SLOT_HEIGHT_PX,
	)


static func slot_rect_world(bay: int, rack: int, slot: int) -> Rect2i:
	return Rect2i(slot_origin_world(bay, rack, slot), Vector2i(_SERVER_WIDTH_PX, _SLOT_HEIGHT_PX))


# ── Floor ───────────────────────────────────────────────────────────────────


static func floor_rect_world(bay: int) -> Rect2i:
	var origin: Vector2i = bay_origin_world(bay)
	var floor_y: int = (
		_RACK_TOP_Y_IN_BAY
		+ _RACK_TOP_FRAME_HEIGHT_PX
		+ _RACK_INTERIOR_HEIGHT_PX
		+ _RACK_BOTTOM_FRAME_HEIGHT_PX
	)
	return Rect2i(
		Vector2i(origin.x, floor_y),
		Vector2i(BAY_WIDTH_PX, _FLOOR_HEIGHT_PX),
	)


# ── Reverse query: world pixel → address ────────────────────────────────────


static func bay_local_to_slot(bay: int, world_pos: Vector2i) -> SlotQuery:
	assert(bay >= 0, "bay must be non-negative; got %d" % bay)
	# Find the rack column that contains world_pos.x, if any.
	var rack_found: int = INVALID_ID
	for r: int in range(RACK_COUNT):
		var col: Rect2i = rack_column_rect_world(bay, r)
		if world_pos.x >= col.position.x and world_pos.x < col.end.x:
			rack_found = r
			break
	if rack_found == INVALID_ID:
		# Could still be above the floor strip — check floor span.
		var floor_r: Rect2i = floor_rect_world(bay)
		if floor_r.has_point(world_pos):
			# Floor but not under any rack column — use -1 in rack.
			return SlotQuery.make_other()
		return SlotQuery.make_other()

	# Check Y zones in order: frame → interior (slots) → baseboard → floor.
	var frame: Rect2i = rack_frame_rect(bay, rack_found)
	if frame.has_point(world_pos):
		return SlotQuery.make_frame(rack_found)

	var interior: Rect2i = rack_interior_rect_world(bay, rack_found)
	if interior.has_point(world_pos):
		var from_top_px: int = world_pos.y - interior.position.y
		var from_top_slot: int = from_top_px / _SLOT_HEIGHT_PX
		var slot: int = SLOTS_PER_RACK - 1 - from_top_slot
		return SlotQuery.make_slot(rack_found, slot)

	var base: Rect2i = rack_baseboard_rect(bay, rack_found)
	if base.has_point(world_pos):
		return SlotQuery.make_baseboard(rack_found)

	var floor_r: Rect2i = floor_rect_world(bay)
	if floor_r.has_point(world_pos):
		return SlotQuery.make_floor(rack_found)

	return SlotQuery.make_other()
