extends Node2D

# Debug overlay: draws the rack-unit grid over the scene so we can see
# how sprites line up with the game's coordinate system.

const LINE_COLOR := Color(1.0, 1.0, 1.0, 0.15)
const RACK_LINE_COLOR := Color(1.0, 0.5, 0.2, 0.35)
const FLOOR_LINE_COLOR := Color(0.2, 1.0, 0.5, 0.5)


func _draw() -> void:
	var total_width: float = float(
		Constants.RACK_COUNT * Constants.RACK_STRIDE_PX
	)
	var rack_area_height: float = float(
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PX
	)
	var total_height: float = rack_area_height + float(Constants.FLOOR_HEIGHT_PX)

	# Horizontal lines every 1U
	for slot: int in range(Constants.SLOTS_PER_RACK + 1):
		var y: float = float(slot * Constants.SLOT_HEIGHT_PX)
		draw_line(
			Vector2(0.0, y),
			Vector2(total_width, y),
			LINE_COLOR,
			1.0,
		)

	# Vertical lines at rack boundaries
	for rack: int in range(Constants.RACK_COUNT + 1):
		var x: float = float(rack * Constants.RACK_STRIDE_PX)
		draw_line(
			Vector2(x, 0.0),
			Vector2(x, total_height),
			RACK_LINE_COLOR,
			1.0,
		)

	# Floor line (top edge of floor strip)
	draw_line(
		Vector2(0.0, rack_area_height),
		Vector2(total_width, rack_area_height),
		FLOOR_LINE_COLOR,
		1.0,
	)
