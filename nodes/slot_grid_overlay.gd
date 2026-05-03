extends Node2D

# Debug overlay: draws the slot grid (per bay 0). Toggle with G key.

const LINE_COLOR := Color(1.0, 1.0, 1.0, 0.15)
const RACK_LINE_COLOR := Color(1.0, 0.5, 0.2, 0.35)
const FLOOR_LINE_COLOR := Color(0.2, 1.0, 0.5, 0.5)


func _draw() -> void:
	var interior_rects: Array[Rect2i] = []
	for rack: int in Constants.RACK_COUNT:
		interior_rects.append(Constants.rack_interior_rect_world(0, rack))

	# Horizontal lines every 1 slot within each rack's interior area.
	for rack: int in Constants.RACK_COUNT:
		var interior: Rect2i = interior_rects[rack]
		for i: int in range(Constants.SLOTS_PER_RACK + 1):
			var y: float = float(interior.position.y + i * Constants.SLOT_HEIGHT_PX)
			draw_line(
				Vector2(float(interior.position.x), y),
				Vector2(float(interior.position.x + interior.size.x), y),
				LINE_COLOR,
				1.0,
			)

	# Vertical lines at rack boundaries (left and right edges of each rack column).
	for rack: int in Constants.RACK_COUNT:
		var interior: Rect2i = interior_rects[rack]
		for x: int in [interior.position.x, interior.position.x + interior.size.x]:
			draw_line(
				Vector2(float(x), float(interior.position.y)),
				Vector2(float(x), float(interior.position.y + interior.size.y)),
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
