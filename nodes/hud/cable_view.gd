class_name CableView extends Node2D

# One per (hum, actuator) pair. Draws a catenary curve between the two
# endpoints each frame. Opacity brightens in wiring mode so the player
# can see them clearly during placement.

const SAG_FACTOR_PER_1000: int = 150
const MIN_SAG_PX: float = 3.0
const OPACITY_NORMAL: float = 0.60
const OPACITY_WIRING: float = 1.00
const CABLE_COLOR: Color = Color(0.80, 0.55, 0.30, 1.0)
const STEPS: int = 16

var _db: GameStateDB
var _hum_id: int = Constants.INVALID_ID
var _actuator_id: int = Constants.INVALID_ID


func initialize(db: GameStateDB, hum_id: int, actuator_id: int) -> void:
	_db = db
	_hum_id = hum_id
	_actuator_id = actuator_id
	modulate.a = OPACITY_NORMAL


func _process(_delta: float) -> void:
	queue_redraw()


func set_wiring_mode(on: bool) -> void:
	modulate.a = OPACITY_WIRING if on else OPACITY_NORMAL


func _draw() -> void:
	if _db == null:
		return
	if not _db.has_entity(_hum_id) or not _db.has_entity(_actuator_id):
		return
	var a: Vector2 = _world_pos(_hum_id)
	var b: Vector2 = _world_pos(_actuator_id)
	var length_px: float = a.distance_to(b)
	var sag: float = maxf(MIN_SAG_PX, length_px * float(SAG_FACTOR_PER_1000) / 1000.0)
	var mid: Vector2 = (a + b) * 0.5 + Vector2(0, sag)
	var prev: Vector2 = a
	for i: int in range(1, STEPS + 1):
		var t: float = float(i) / float(STEPS)
		var q: Vector2 = _bezier_quad(a, mid, b, t)
		draw_line(prev, q, CABLE_COLOR, 2.0)
		prev = q


func _world_pos(entity_id: int) -> Vector2:
	var x: int = _db.get_field(entity_id, &"position", &"x")
	var y: int = _db.get_field(entity_id, &"position", &"y")
	return Vector2(Constants.to_world(x), Constants.to_world(y))


static func _bezier_quad(a: Vector2, m: Vector2, b: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return u * u * a + 2.0 * u * t * m + t * t * b
