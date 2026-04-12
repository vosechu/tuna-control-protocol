class_name TilePainter extends RefCounted

const _CELL_SIZE_PX: int = 16
const _SOURCE_ID: int = 0
const _MAIN_LAYER: int = 0

const ATLAS_CEILING: Vector2i = Vector2i(0, 0)
const ATLAS_WALL: Vector2i = Vector2i(1, 0)
const ATLAS_WALL_LOWER: Vector2i = Vector2i(3, 3)
const ATLAS_BASEBOARD_A: Vector2i = Vector2i(0, 3)
const ATLAS_BASEBOARD_B: Vector2i = Vector2i(1, 3)
const ATLAS_BASEBOARD_C: Vector2i = Vector2i(2, 3)
const ATLAS_GROUND: Vector2i = Vector2i(4, 3)
const ATLAS_GROUND_LOWER: Vector2i = Vector2i(4, 5)
const ATLAS_CABLE_A_L: Vector2i = Vector2i(4, 0)
const ATLAS_CABLE_A_R: Vector2i = Vector2i(5, 0)
const ATLAS_CABLE_E_U: Vector2i = Vector2i(11, 0)
const ATLAS_FLOWER_ORANGE: Vector2i = Vector2i(4, 2)
const ATLAS_GRASS: Vector2i = Vector2i(7, 2)
const ATLAS_PLANTS_SMALL: Vector2i = Vector2i(4, 4)
const ATLAS_DARK_EDGE: Vector2i = Vector2i(0, 4)
const ATLAS_ABANDONMENT_LEAVES: Vector2i = Vector2i(6, 2)
const ATLAS_ABANDONMENT_GRASS: Vector2i = Vector2i(10, 2)

var _tilemap: Object


func _init(tilemap: Object) -> void:
	_tilemap = tilemap


func paint_bay(bay_index: int) -> void:
	@warning_ignore("integer_division")
	var bay_start_cell_x: int = (bay_index * Constants.BAY_STRIDE_PX) / _CELL_SIZE_PX
	@warning_ignore("integer_division")
	var bay_end_cell_x: int = ((bay_index + 1) * Constants.BAY_STRIDE_PX) / _CELL_SIZE_PX

	_paint_ceiling_row(bay_start_cell_x, bay_end_cell_x, bay_index)
	_paint_wall_fill(bay_start_cell_x, bay_end_cell_x)
	_paint_floor_strip(bay_start_cell_x, bay_end_cell_x, bay_index)


func clear_bay(bay_index: int) -> void:
	@warning_ignore("integer_division")
	var bay_start_cell_x: int = (bay_index * Constants.BAY_STRIDE_PX) / _CELL_SIZE_PX
	@warning_ignore("integer_division")
	var bay_end_cell_x: int = ((bay_index + 1) * Constants.BAY_STRIDE_PX) / _CELL_SIZE_PX
	@warning_ignore("integer_division")
	var max_y: int = 360 / _CELL_SIZE_PX
	for y: int in range(0, max_y + 1):
		for x: int in range(bay_start_cell_x, bay_end_cell_x + 1):
			_tilemap.set_cell(_MAIN_LAYER, Vector2i(x, y), -1, Vector2i(-1, -1))


func _paint_ceiling_row(start_x: int, end_x: int, bay_index: int) -> void:
	for x: int in range(start_x, end_x + 1):
		var tile: Vector2i = ATLAS_WALL
		if bay_index == 0 and x == start_x:
			tile = ATLAS_CEILING
		_tilemap.set_cell(_MAIN_LAYER, Vector2i(x, 0), _SOURCE_ID, tile)
	if bay_index == 0:
		@warning_ignore("integer_division")
		var mid_x: int = start_x + ((end_x - start_x) / 4)
		_tilemap.set_cell(_MAIN_LAYER, Vector2i(mid_x, 0), _SOURCE_ID, ATLAS_CABLE_A_L)
		_tilemap.set_cell(_MAIN_LAYER, Vector2i(mid_x + 1, 0), _SOURCE_ID, ATLAS_CABLE_A_R)


func _paint_wall_fill(start_x: int, end_x: int) -> void:
	for y: int in range(1, 14):
		for x: int in range(start_x, end_x + 1):
			_tilemap.set_cell(_MAIN_LAYER, Vector2i(x, y), _SOURCE_ID, ATLAS_WALL)


func _paint_floor_strip(start_x: int, end_x: int, bay_index: int) -> void:
	for x: int in range(start_x, end_x + 1):
		_tilemap.set_cell(_MAIN_LAYER, Vector2i(x, 19), _SOURCE_ID, ATLAS_WALL_LOWER)
		var baseboard_tile: Vector2i = ATLAS_BASEBOARD_B
		if x == start_x:
			baseboard_tile = ATLAS_BASEBOARD_A
		elif x == end_x:
			baseboard_tile = ATLAS_BASEBOARD_C
		_tilemap.set_cell(_MAIN_LAYER, Vector2i(x, 20), _SOURCE_ID, baseboard_tile)
		_tilemap.set_cell(_MAIN_LAYER, Vector2i(x, 21), _SOURCE_ID, ATLAS_GROUND)
		_tilemap.set_cell(_MAIN_LAYER, Vector2i(x, 22), _SOURCE_ID, ATLAS_GROUND_LOWER)

	if bay_index != 0:
		@warning_ignore("integer_division")
		var mid_x: int = start_x + ((end_x - start_x) / 2)
		_tilemap.set_cell(_MAIN_LAYER, Vector2i(mid_x, 19), _SOURCE_ID, ATLAS_DARK_EDGE)
		_tilemap.set_cell(_MAIN_LAYER, Vector2i(mid_x + 1, 19), _SOURCE_ID, ATLAS_ABANDONMENT_LEAVES)
		_tilemap.set_cell(_MAIN_LAYER, Vector2i(mid_x - 1, 19), _SOURCE_ID, ATLAS_ABANDONMENT_GRASS)
