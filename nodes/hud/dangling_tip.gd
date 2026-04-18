class_name DanglingTip extends Node2D

# Cursor follower that renders while a cable endpoint is in the player's
# hand. Empty dotted circle so it reads as "unplugged socket" rather than
# a live signal.

const TIP_COLOR: Color = Color(0.95, 0.95, 0.90, 1.0)
const TIP_RADIUS_PX: float = 5.0
const ARC_SEGMENTS: int = 24

var _wiring_controller: WiringController


func initialize(wc: WiringController) -> void:
	_wiring_controller = wc


func _process(_delta: float) -> void:
	if _wiring_controller == null:
		visible = false
		return
	visible = _wiring_controller.get_state() == WiringController.State.HOLDING_CABLE
	if visible:
		global_position = _wiring_controller.get_cursor_world_pos()
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	draw_arc(
		Vector2.ZERO,
		TIP_RADIUS_PX,
		0.0,
		TAU,
		ARC_SEGMENTS,
		TIP_COLOR,
		1.0,
		true,
	)
