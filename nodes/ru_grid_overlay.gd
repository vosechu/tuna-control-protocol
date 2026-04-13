extends Node2D

# Debug overlay: draws the rack-unit grid. Toggle with G key.

const LINE_COLOR := Color(1.0, 1.0, 1.0, 0.15)
const RACK_LINE_COLOR := Color(1.0, 0.5, 0.2, 0.35)
const FLOOR_LINE_COLOR := Color(0.2, 1.0, 0.5, 0.5)


func _draw() -> void:
	# Rack slot area starts after 4px frame at top of rack sprite
	var x_offset: float = float(Constants.LEFTMOST_RACK_OFFSET_PX)
	var y_offset: float = float(Constants.RACK_SLOT0_Y)
	var rack_area_width: float = float(
		Constants.RACK_COUNT * Constants.RACK_STRIDE_PX
	)
	var rack_area_height: float = float(
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PX
	)

	# Horizontal lines every 1U
	for slot: int in range(Constants.SLOTS_PER_RACK + 1):
		var y: float = float(slot * Constants.SLOT_HEIGHT_PX) + y_offset
		draw_line(
			Vector2(x_offset, y),
			Vector2(x_offset + rack_area_width, y),
			LINE_COLOR,
			1.0,
		)

	# Vertical lines at rack boundaries
	for rack: int in range(Constants.RACK_COUNT + 1):
		var x: float = float(rack * Constants.RACK_STRIDE_PX) + x_offset
		draw_line(
			Vector2(x, y_offset),
			Vector2(x, y_offset + rack_area_height),
			RACK_LINE_COLOR,
			1.0,
		)

	# Floor line
	draw_line(
		Vector2(0.0, float(Constants.FLOOR_Y)),
		Vector2(float(Constants.VIEWPORT_WIDTH), float(Constants.FLOOR_Y)),
		FLOOR_LINE_COLOR,
		1.0,
	)
