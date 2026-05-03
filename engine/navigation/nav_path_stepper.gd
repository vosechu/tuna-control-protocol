class_name NavPathStepper extends RefCounted

# Pure integer stepping math for path-following movement. Stateless — callers
# own the waypoint list and advance through it based on the `arrived` field.
# Movement splits the budget proportionally across X and Y (Manhattan
# distribution). If proportional integer math would truncate an axis to zero
# while its delta is nonzero, it is bumped to ±1 so perpendicular-axis motion
# cannot stall a diagonal approach.

static func step(
	pos: Vector2i, waypoint: Vector2i, speed: int,
) -> Dictionary:
	var dx: int = waypoint.x - pos.x
	var dy: int = waypoint.y - pos.y
	var dist: int = absi(dx) + absi(dy)
	if dist <= speed:
		return {&"pos": waypoint, &"arrived": true}
	var mx: int = speed * dx / dist
	var my: int = speed * dy / dist
	if mx == 0 and dx != 0:
		mx = 1 if dx > 0 else -1
	if my == 0 and dy != 0:
		my = 1 if dy > 0 else -1
	return {&"pos": Vector2i(pos.x + mx, pos.y + my), &"arrived": false}
