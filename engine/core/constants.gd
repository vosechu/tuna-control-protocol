class_name Constants extends RefCounted

const INVALID_ID: int = -1
const POSITION_SCALE: int = 100
const SLOT_HEIGHT_PX: int = 7
const SLOT_HEIGHT_PU: int = SLOT_HEIGHT_PX * POSITION_SCALE  # 700
const RACK_WIDTH_PX: int = 76
const RACK_WIDTH_PU: int = RACK_WIDTH_PX * POSITION_SCALE  # 7600
const RACK_GAP_PX: int = 4
const RACK_STRIDE_PX: int = RACK_WIDTH_PX + RACK_GAP_PX  # 80
const RACK_STRIDE_PU: int = RACK_STRIDE_PX * POSITION_SCALE  # 8000
const RACK_COUNT: int = 7
const HALF_RACK_PX: int = 40
const SLOTS_PER_RACK: int = 10
const FLOOR_HEIGHT_PX: int = 40
const FLOOR_HEIGHT_PU: int = FLOOR_HEIGHT_PX * POSITION_SCALE  # 4000
const TOR_SWITCH_SLOTS: int = 4
const UNIT: int = 1000
const SWITCH_THRESHOLD: int = 50
const EVAL_TIME_BUDGET_USEC: int = 1000
const ARM_REACH_RU: int = 3
const HEAT_CELLS_RACK: int = SLOTS_PER_RACK * RACK_COUNT  # 294
const HEAT_CELLS_FLOOR: int = RACK_COUNT  # 7
const HEAT_CELLS_TOTAL: int = HEAT_CELLS_RACK + HEAT_CELLS_FLOOR  # 301


static func ru_to_pu(ru: int) -> int:
	return ru * SLOT_HEIGHT_PU


static func pu_to_ru(pu: int) -> int:
	@warning_ignore("integer_division")
	return pu / SLOT_HEIGHT_PU


static func rack_cell(rack: int, slot: int) -> int:
	return rack * SLOTS_PER_RACK + slot


static func floor_cell(rack: int) -> int:
	return HEAT_CELLS_RACK + rack


static func to_world(v: int) -> float:
	return float(v) / float(POSITION_SCALE)


static func from_world(v: float) -> int:
	return roundi(v * float(POSITION_SCALE))
