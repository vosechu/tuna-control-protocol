extends Node2D

var _db: GameStateDB
var _heat_grid: HeatGrid
var _visible: bool = false


func initialize(db: GameStateDB, heat_grid: HeatGrid) -> void:
	_db = db
	_heat_grid = heat_grid


func _process(_delta: float) -> void:
	if _visible:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		_visible = not _visible
		queue_redraw()


func _draw() -> void:
	if not _visible or _heat_grid == null:
		return
	var x_offset: float = float(Constants.LEFTMOST_RACK_OFFSET_PX)
	var y_offset: float = float(Constants.RACK_TOP_Y) + 4.0
	for rack: int in Constants.RACK_COUNT:
		for slot: int in Constants.SLOTS_PER_RACK:
			var cell: int = Constants.rack_cell(rack, slot)
			var temp: int = _heat_grid.get_temperature(cell)
			if temp <= 0:
				continue
			var x: float = float(rack * Constants.RACK_STRIDE_PX) + x_offset
			var y: float = float(slot * Constants.SLOT_HEIGHT_PX) + y_offset
			var rect := Rect2(x, y, Constants.RACK_WIDTH_PX, Constants.SLOT_HEIGHT_PX)
			var color: Color
			if temp <= 500:
				color = Color(0.2, 0.3, 0.8).lerp(Color(0.9, 0.8, 0.2), float(temp) / 500.0)
			else:
				color = Color(0.9, 0.8, 0.2).lerp(Color(0.9, 0.2, 0.1), float(temp - 500) / 500.0)
			color.a = 0.9
			draw_rect(rect, color)
			# Hatch pattern for color-blind accessibility
			var density: int = temp / 200
			for i: int in density:
				var hatch_offset: float = float(i + 1) * float(Constants.SLOT_HEIGHT_PX) / float(density + 1)
				draw_line(
					Vector2(x, y + hatch_offset),
					Vector2(x + float(Constants.RACK_WIDTH_PX), y + hatch_offset),
					Color(1.0, 1.0, 1.0, 0.15), 1.0
				)
	# Floor cells
	var floor_y: float = float(Constants.FLOOR_Y)
	for rack: int in Constants.RACK_COUNT:
		var cell: int = Constants.floor_cell(rack)
		var temp: int = _heat_grid.get_temperature(cell)
		if temp <= 0:
			continue
		var x: float = float(rack * Constants.RACK_STRIDE_PX) + x_offset
		var rect := Rect2(x, floor_y, Constants.RACK_WIDTH_PX, Constants.FLOOR_HEIGHT_PX)
		var color: Color
		if temp <= 500:
			color = Color(0.2, 0.3, 0.8).lerp(Color(0.9, 0.8, 0.2), float(temp) / 500.0)
		else:
			color = Color(0.9, 0.8, 0.2).lerp(Color(0.9, 0.2, 0.1), float(temp - 500) / 500.0)
		color.a = 0.9
		draw_rect(rect, color)
