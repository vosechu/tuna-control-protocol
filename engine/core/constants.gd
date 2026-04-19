class_name Constants extends RefCounted

const INVALID_ID: int = -1
const POSITION_SCALE: int = 100

# ── Viewport ──

const VIEWPORT_WIDTH: int = 224   # 14 tiles
const VIEWPORT_HEIGHT: int = 128  # 8 tiles

# ── Grid: rack slot dimensions ──

const SLOT_HEIGHT_PX: int = 8
const SLOT_HEIGHT_PU: int = SLOT_HEIGHT_PX * POSITION_SCALE  # 800

const RACK_WIDTH_PX: int = 23
const RACK_WIDTH_PU: int = RACK_WIDTH_PX * POSITION_SCALE  # 2300

const RACK_STRIDE_PX: int = 31
const RACK_STRIDE_PU: int = RACK_STRIDE_PX * POSITION_SCALE  # 3100

const RACK_GAP_PX: int = 8
const RACK_GAP_PU: int = RACK_GAP_PX * POSITION_SCALE  # 800

const RACK_COUNT: int = 5
const SLOTS_PER_RACK: int = 10
const TOR_SWITCH_SLOTS: int = 0

const FLOOR_HEIGHT_PX: int = 16  # one tile row
const FLOOR_HEIGHT_PU: int = FLOOR_HEIGHT_PX * POSITION_SCALE  # 1600

# ── Layout Y positions (world pixels, top-down) ──

const CEILING_Y: int = 0         # row 0
const RACK_TOP_Y: int = 16       # row 1 — rack sprite top edge
# Sprite has 8px transparent padding above the visible rack + 4px visible frame
# = 12px from sprite top-left to slot 0 interior (measured from sprite pixels)
const RACK_FRAME_PX: int = 12    # sprite top-left to slot 0 interior
const RACK_SLOT0_Y: int = RACK_TOP_Y + RACK_FRAME_PX  # world Y of slot 0 top (28)
const RACK_BOTTOM_Y: int = 112   # row 7 — rack sprite bottom (16 + 96)
const FLOOR_Y: int = 112         # top of row 7 — floor surface
const VIEWPORT_BOTTOM: int = 128 # row 8

# ── Bay layout ──

const LEFTMOST_RACK_OFFSET_PX: int = 25
const LEFTMOST_RACK_OFFSET_PU: int = LEFTMOST_RACK_OFFSET_PX * POSITION_SCALE  # 2500

const BAY_WIDTH_PX: int = 186
const BAY_WIDTH_PU: int = BAY_WIDTH_PX * POSITION_SCALE  # 18600

const BAY_STRIDE_PX: int = 226
const BAY_STRIDE_PU: int = BAY_STRIDE_PX * POSITION_SCALE  # 22600

const BAY_PEEK_PX: int = 20

# ── Heat grid (only bay 0 simulated for now) ──

const HEAT_CELLS_RACK: int = SLOTS_PER_RACK * RACK_COUNT  # 50
const HEAT_CELLS_FLOOR: int = RACK_COUNT  # 5
const HEAT_CELLS_TOTAL: int = HEAT_CELLS_RACK + HEAT_CELLS_FLOOR  # 55

# ── Game rules ──

const UNIT: int = 1000
const SWITCH_THRESHOLD: int = 50
const EVAL_TIME_BUDGET_USEC: int = 1000
const ARM_REACH_RU: int = 3

# ============================================================================
# NEW COORDINATE API — see docs/superpowers/specs/2026-04-19-coordinate-system-redesign.md
# Old API (rack_slot_to_pu, POSITION_SCALE, ru_to_pu, etc.) remains alongside
# during migration. Old API will be removed in the final commit of this
# refactor. Prefer the new API in any code you write today.
# Constants declared here (before static funcs) to satisfy gdlint
# class-definitions-order; public helpers are appended at the bottom of
# the file alongside the other static helpers.
# ============================================================================

const INVALID_BAY: int = -1
const INVALID_SLOT: int = -1

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


# ── Rack unit conversion ──

static func ru_to_pu(ru: int) -> int:
	return ru * SLOT_HEIGHT_PU


static func pu_to_ru(pu: int) -> int:
	return pu / SLOT_HEIGHT_PU


# ── Heat grid cell indexing ──

static func rack_cell(rack: int, slot: int) -> int:
	return rack * SLOTS_PER_RACK + slot


static func floor_cell(rack: int) -> int:
	return HEAT_CELLS_RACK + rack


# ── World-space coordinate helpers (single source of truth) ──

static func bay_origin_pu(bay_index: int) -> Vector2i:
	return Vector2i(bay_index * BAY_STRIDE_PU, 0)


static func rack_interior_pu(bay_index: int, rack_in_bay: int) -> int:
	return bay_index * BAY_STRIDE_PU + LEFTMOST_RACK_OFFSET_PU + (rack_in_bay * RACK_STRIDE_PU)


static func rack_slot_to_pu(bay_index: int, rack_in_bay: int, slot: int) -> Vector2i:
	var x: int = rack_interior_pu(bay_index, rack_in_bay) + (RACK_WIDTH_PU / 2)
	var y: int = slot * SLOT_HEIGHT_PU
	return Vector2i(x, y)


static func _floordiv(a: int, b: int) -> int:
	var q: int = a / b
	if (a ^ b) < 0 and q * b != a:
		q -= 1
	return q


static func pu_to_bay_rack_slot(pu_x: int, pu_y: int) -> Dictionary:
	var bay_index: int = _floordiv(pu_x, BAY_STRIDE_PU)
	var bay_local_x: int = pu_x - (bay_index * BAY_STRIDE_PU)
	var rack_in_bay: int = _floordiv(bay_local_x - LEFTMOST_RACK_OFFSET_PU, RACK_STRIDE_PU)
	rack_in_bay = clampi(rack_in_bay, 0, RACK_COUNT - 1)
	var slot: int = _floordiv(pu_y, SLOT_HEIGHT_PU)
	slot = clampi(slot, 0, SLOTS_PER_RACK - 1)
	return {&"bay": bay_index, &"rack": rack_in_bay, &"slot": slot}


static func bay_center(bay_index: int) -> Vector2:
	var bay_x: int = bay_index * BAY_STRIDE_PX + BAY_WIDTH_PX / 2
	var center_y: int = VIEWPORT_HEIGHT / 2
	return Vector2(float(bay_x), float(center_y))


# ── World pixel ↔ rack/slot conversion ──

## Convert a world-pixel click position to rack/slot indices.
## bay: which bay the camera is viewing.
## Returns {&"rack": int, &"slot": int}.
static func world_to_rack_slot(
	world_x: float, world_y: float, bay: int = 0,
) -> Dictionary:
	var bay_px: int = bay * BAY_STRIDE_PX
	var local_x: float = world_x - float(bay_px) - float(LEFTMOST_RACK_OFFSET_PX)
	var rack: int = int(local_x) / RACK_STRIDE_PX
	rack = clampi(rack, 0, RACK_COUNT - 1)
	var slot_y: float = world_y - float(RACK_SLOT0_Y)
	var slot: int = int(slot_y) / SLOT_HEIGHT_PX
	slot = clampi(slot, 0, SLOTS_PER_RACK - 1)
	return {&"rack": rack, &"slot": slot}


## Convert rack/slot to world-pixel position for rendering.
## Returns top-left corner of the slot in world coordinates.
static func rack_slot_to_world(
	bay: int, rack: int, slot: int,
) -> Vector2:
	var x: float = float(
		bay * BAY_STRIDE_PX
		+ LEFTMOST_RACK_OFFSET_PX
		+ rack * RACK_STRIDE_PX
	)
	var y: float = float(RACK_SLOT0_Y + slot * SLOT_HEIGHT_PX)
	return Vector2(x, y)


# ── Float / int conversion at rendering boundary ──

static func to_world(v: int) -> float:
	return float(v) / float(POSITION_SCALE)


static func from_world(v: float) -> int:
	return roundi(v * float(POSITION_SCALE))


## Convert world-pixel position to PU coordinates.
## Accounts for RACK_SLOT0_Y offset on Y axis.
static func world_to_pu(world_x: float, world_y: float) -> Vector2i:
	return Vector2i(
		from_world(world_x),
		from_world(world_y - float(RACK_SLOT0_Y)),
	)


# ── Bay layer (new coordinate API) ──────────────────────────────────────────


static func bay_origin_world(bay: int) -> Vector2i:
	return Vector2i(bay * BAY_STRIDE_PX, 0)


static func bay_rect_world(bay: int) -> Rect2i:
	return Rect2i(bay_origin_world(bay), Vector2i(BAY_WIDTH_PX, VIEWPORT_HEIGHT))


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
