class_name TilePainter extends RefCounted

const _CELL_SIZE_PX: int = 16
const _SOURCE_ID: int = 0
const _WALL_LAYER: int = 0
const _CABLE_LAYER: int = 1
const _PLANT_LAYER: int = 2

# ── Tile atlas coordinates (col, row) referencing tcp_tileset01.png ──
# See mods/tcp_base/sprites/environment/tcp_tileset01.md for the full cell map.

const ATLAS_CEILING: Vector2i = Vector2i(0, 0)

# Wall: (0,1) is the base wall tile (~80%), others are occasional detail variants.
# Excluding (0,0) which is the ceiling corner.
const ATLAS_WALL_BASE: Vector2i = Vector2i(0, 1)
const ATLAS_WALL_VARIANTS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
	Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
]
const _WALL_BASE_WEIGHT: int = 80  # percent chance of base tile

# Baseboard: 3 variants for random variation
const ATLAS_BASEBOARDS: Array[Vector2i] = [
	Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3),
]

# Ground: 11 surface variants (rows 3 and 5)
const ATLAS_GROUNDS: Array[Vector2i] = [
	Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3),
	Vector2i(8, 3), Vector2i(9, 3), Vector2i(10, 3),
	Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5),
]

# Under-floor and transition (below ground row)
const ATLAS_UNDER_FLOOR: Vector2i = Vector2i(9, 5)

# Cables: each variant is an array of [atlas_coords, offset_x, offset_y] cells.
# Painted on the cable overlay layer so wall tiles show through transparent areas.
const ATLAS_CABLES: Array[Array] = [
	# Cable A: 2 wide, top only
	[[Vector2i(4, 0), 0, 0], [Vector2i(5, 0), 1, 0]],
	# Cable B: 2 wide, top + bottom
	[[Vector2i(6, 0), 0, 0], [Vector2i(7, 0), 1, 0],
		[Vector2i(6, 1), 0, 1], [Vector2i(7, 1), 1, 1]],
	# Cable C+D: 3 wide, top + bottom (always together)
	[[Vector2i(8, 0), 0, 0], [Vector2i(9, 0), 1, 0], [Vector2i(10, 0), 2, 0],
		[Vector2i(8, 1), 0, 1], [Vector2i(9, 1), 1, 1], [Vector2i(10, 1), 2, 1]],
	# Cable E: 1 wide, top only
	[[Vector2i(11, 0), 0, 0]],
]

# Plants for growth system
const ATLAS_PLANTS_SMALL: Vector2i = Vector2i(4, 4)

var _tilemap: Object
var _rng: RandomNumberGenerator


func _init(tilemap: Object, seed_value: int = 42) -> void:
	_tilemap = tilemap
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	while _tilemap.get_layers_count() <= _PLANT_LAYER:
		_tilemap.add_layer(_tilemap.get_layers_count())


# Layout: 8 tile rows total
#   Row 0: ceiling
#   Rows 1-5: wall (rack sprite overlays most of this)
#   Row 6: baseboard (behind rack bottom frame)
#   Row 7: floor
func paint_bay(bay_index: int) -> void:
	var start_x: int = (bay_index * Constants.BAY_STRIDE_PX) / _CELL_SIZE_PX
	var end_x: int = ((bay_index + 1) * Constants.BAY_STRIDE_PX) / _CELL_SIZE_PX

	# Row 0: ceiling
	for x: int in range(start_x, end_x + 1):
		_tilemap.set_cell(_WALL_LAYER, Vector2i(x, 0), _SOURCE_ID, ATLAS_CEILING)

	# Rows 1-5: wall fill (rack sprite sits on top)
	for y: int in range(1, 6):
		for x: int in range(start_x, end_x + 1):
			_tilemap.set_cell(_WALL_LAYER, Vector2i(x, y), _SOURCE_ID, _pick_wall())

	# Row 6: baseboard (mostly hidden behind rack bottom frame)
	for x: int in range(start_x, end_x + 1):
		_tilemap.set_cell(_WALL_LAYER, Vector2i(x, 6), _SOURCE_ID, _pick_random(ATLAS_BASEBOARDS))

	# Row 7: floor
	for x: int in range(start_x, end_x + 1):
		_tilemap.set_cell(_WALL_LAYER, Vector2i(x, 7), _SOURCE_ID, _pick_random(ATLAS_GROUNDS))

	# Scatter cables on the cable layer (rows 0-1)
	var bay_width: int = end_x - start_x
	var cable_count: int = _rng.randi_range(2, 4)
	for _i: int in cable_count:
		var cable: Array = ATLAS_CABLES[_rng.randi_range(0, ATLAS_CABLES.size() - 1)]
		var cable_x: int = start_x + _rng.randi_range(1, bay_width - 3)
		_paint_cable(cable, cable_x)

	# Scatter small plants on the plant layer
	for x: int in range(start_x, end_x + 1):
		if _rng.randi_range(1, 100) <= 15:
			_tilemap.set_cell(_PLANT_LAYER, Vector2i(x, 6), _SOURCE_ID, ATLAS_PLANTS_SMALL)


func clear_bay(bay_index: int) -> void:
	var start_x: int = (bay_index * Constants.BAY_STRIDE_PX) / _CELL_SIZE_PX
	var end_x: int = ((bay_index + 1) * Constants.BAY_STRIDE_PX) / _CELL_SIZE_PX
	for y: int in range(0, 8):
		for x: int in range(start_x, end_x + 1):
			_tilemap.set_cell(_WALL_LAYER, Vector2i(x, y), -1, Vector2i(-1, -1))
			_tilemap.set_cell(_CABLE_LAYER, Vector2i(x, y), -1, Vector2i(-1, -1))
			_tilemap.set_cell(_PLANT_LAYER, Vector2i(x, y), -1, Vector2i(-1, -1))


func _paint_cable(cable: Array, origin_x: int) -> void:
	for cell: Array in cable:
		var atlas: Vector2i = cell[0]
		var ox: int = cell[1]
		var oy: int = cell[2]
		_tilemap.set_cell(_CABLE_LAYER, Vector2i(origin_x + ox, oy), _SOURCE_ID, atlas)


func _pick_wall() -> Vector2i:
	if _rng.randi_range(1, 100) <= _WALL_BASE_WEIGHT:
		return ATLAS_WALL_BASE
	return ATLAS_WALL_VARIANTS[_rng.randi_range(0, ATLAS_WALL_VARIANTS.size() - 1)]


func _pick_random(pool: Array[Vector2i]) -> Vector2i:
	return pool[_rng.randi_range(0, pool.size() - 1)]
