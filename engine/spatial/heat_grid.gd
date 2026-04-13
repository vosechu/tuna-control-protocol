class_name HeatGrid extends RefCounted

var _db: GameStateDB
# Flat array: indices 0..HEAT_CELLS_RACK-1 are rack cells, then HEAT_CELLS_FLOOR floor cells.
var _grid: PackedInt32Array


func _init(db: GameStateDB) -> void:
	_db = db
	_grid = PackedInt32Array()
	_grid.resize(Constants.HEAT_CELLS_TOTAL)
	_grid.fill(0)


func get_temperature(cell_index: int) -> int:
	assert(cell_index >= 0 and cell_index < Constants.HEAT_CELLS_TOTAL,
		"get_temperature: cell_index %d out of range" % cell_index)
	return _grid[cell_index]


func propagate() -> void:
	# Step 1: zero the entire grid.
	_grid.fill(0)

	# Step 2: apply each heat source.
	var sources: Array[int] = _db.get_entities_with(&"heat_source")
	for entity_id: int in sources:
		_apply_source(entity_id)


# ── Private ───────────────────────────────────────────────────────────────────

func _apply_source(entity_id: int) -> void:
	var pos: Dictionary = _db.get_component(entity_id, &"position")
	var hs: Dictionary = _db.get_component(entity_id, &"heat_source")

	var layout: Dictionary = Constants.pu_to_bay_rack_slot(pos[&"x"], pos[&"y"])
	var rack: int = layout[&"rack"]
	var slot: int = layout[&"slot"]
	var value: int = hs[&"value"]
	var radius: int = hs[&"radius_ru"]

	# "3U up, 1U down" scaled by radius: upward range = radius, downward = radius / 3.
	# range(-radius, radius / 3 + 1) covers up to 3U upward (-3,-2,-1,0) and 1U downward (1).
	for ds: int in range(-radius, radius / 3 + 1):
		var target_slot: int = slot + ds
		if target_slot < 0 or target_slot >= Constants.SLOTS_PER_RACK:
			continue
		var distance: int = absi(ds)
		# Linear falloff: full value at distance 0, zero at distance == radius.
		var heat: int = value * (radius - distance) / radius

		# Same-rack contribution.
		var cell: int = Constants.rack_cell(rack, target_slot)
		_grid[cell] = mini(_grid[cell] + heat, Constants.UNIT)

		# Cross-rack spillover: 1/4 strength to both adjacent racks, same slot only.
		# Only spill the source slot (ds == 0) to keep it simple and spec-compliant.
		if ds == 0:
			var spill: int = value / 4
			if rack > 0:
				var left_cell: int = Constants.rack_cell(rack - 1, target_slot)
				_grid[left_cell] = mini(_grid[left_cell] + spill, Constants.UNIT)
			if rack < Constants.RACK_COUNT - 1:
				var right_cell: int = Constants.rack_cell(rack + 1, target_slot)
				_grid[right_cell] = mini(_grid[right_cell] + spill, Constants.UNIT)

	# Floor only gets heat from servers near the bottom of the rack.
	# Distance from source to floor = (SLOTS_PER_RACK - slot).
	# Downward range = radius / 3 (same as rack propagation).
	var down_range: int = radius / 3
	var floor_dist: int = Constants.SLOTS_PER_RACK - slot
	if floor_dist <= down_range:
		var floor_idx: int = Constants.floor_cell(rack)
		var floor_heat: int = value * (down_range + 1 - floor_dist) / (down_range + 1)
		_grid[floor_idx] = mini(
			_grid[floor_idx] + floor_heat, Constants.UNIT
		)
