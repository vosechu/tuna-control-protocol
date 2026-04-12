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


# ── Rack unit conversion ──

static func ru_to_pu(ru: int) -> int:
	return ru * SLOT_HEIGHT_PU


static func pu_to_ru(pu: int) -> int:
	@warning_ignore("integer_division")
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
	@warning_ignore("integer_division")
	var x: int = rack_interior_pu(bay_index, rack_in_bay) + (RACK_WIDTH_PU / 2)
	var y: int = slot * SLOT_HEIGHT_PU
	return Vector2i(x, y)


static func _floordiv(a: int, b: int) -> int:
	@warning_ignore("integer_division")
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
	@warning_ignore("integer_division")
	var bay_x: int = bay_index * BAY_STRIDE_PX + BAY_WIDTH_PX / 2
	@warning_ignore("integer_division")
	var center_y: int = VIEWPORT_HEIGHT / 2
	return Vector2(float(bay_x), float(center_y))


# ── Float / int conversion at rendering boundary ──

static func to_world(v: int) -> float:
	return float(v) / float(POSITION_SCALE)


static func from_world(v: float) -> int:
	return roundi(v * float(POSITION_SCALE))
