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
	# Bay 0 only. Slot 0 is the BOTTOM; heat grid cell indices still run 0..9
	# where 0 is bottom. We paint each slot's cell into its slot_rect.
	for rack: int in Constants.RACK_COUNT:
		for slot: int in Constants.SLOTS_PER_RACK:
			var cell: int = Constants.rack_cell(rack, slot)
			var temp: int = _heat_grid.get_temperature(cell)
			if temp <= 0:
				continue
			var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
			var x: float = float(slot_rect.position.x)
			var y: float = float(slot_rect.position.y)
			var rect := Rect2(x, y, float(slot_rect.size.x), float(slot_rect.size.y))
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
				var hatch_offset: float = (
					float(i + 1) * float(slot_rect.size.y) / float(density + 1)
				)
				draw_line(
					Vector2(x, y + hatch_offset),
					Vector2(x + float(slot_rect.size.x), y + hatch_offset),
					Color(1.0, 1.0, 1.0, 0.15), 1.0
				)
	# Floor cells — one per rack column
	var floor_rect: Rect2i = Constants.floor_rect_world(0)
	for rack: int in Constants.RACK_COUNT:
		var cell: int = Constants.floor_cell(rack)
		var temp: int = _heat_grid.get_temperature(cell)
		if temp <= 0:
			continue
		var rack_col: Rect2i = Constants.rack_column_rect_world(0, rack)
		var x: float = float(rack_col.position.x)
		var rect := Rect2(
			x, float(floor_rect.position.y),
			float(rack_col.size.x), float(floor_rect.size.y),
		)
		var color: Color
		if temp <= 500:
			color = Color(0.2, 0.3, 0.8).lerp(Color(0.9, 0.8, 0.2), float(temp) / 500.0)
		else:
			color = Color(0.9, 0.8, 0.2).lerp(Color(0.9, 0.2, 0.1), float(temp - 500) / 500.0)
		color.a = 0.9
		draw_rect(rect, color)
