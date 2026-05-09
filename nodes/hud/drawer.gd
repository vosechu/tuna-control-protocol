class_name Drawer extends PanelContainer

# Base for HUD drawers. Subclasses (InspectDrawer, future
# PlacementDrawer, NarratorDrawer) inherit edge anchoring + slide
# tween. Per docs/superpowers/specs/2026-05-09-inspect-drawer-design.md
# §"The drawer primitive".

enum AnchorEdge { LEFT, RIGHT, BOTTOM }

const _SLIDE_SECONDS: float = 0.15

@export var anchor_edge: AnchorEdge = AnchorEdge.LEFT
@export var open_position: Vector2 = Vector2.ZERO

var _is_open: bool = false
var _closed_position: Vector2 = Vector2.ZERO
var _tween: Tween


func _ready() -> void:
	_closed_position = _compute_closed_position()
	position = _closed_position
	visible = false


func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "position", open_position, _SLIDE_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "position", _closed_position, _SLIDE_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void: visible = false)


func is_open() -> bool:
	return _is_open


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _compute_closed_position() -> Vector2:
	var w: float = float(size.x if size.x > 0.0 else custom_minimum_size.x)
	var h: float = float(size.y if size.y > 0.0 else custom_minimum_size.y)
	match anchor_edge:
		AnchorEdge.LEFT:
			return Vector2(open_position.x - w, open_position.y)
		AnchorEdge.RIGHT:
			return Vector2(open_position.x + w, open_position.y)
		AnchorEdge.BOTTOM:
			return Vector2(open_position.x, open_position.y + h)
	return open_position
