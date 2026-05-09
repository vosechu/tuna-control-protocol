class_name PurrRing extends Node2D

# Renders pixel-note glyphs orbiting at purr.radius_px around the parent's
# global position. Density and alpha scale with intensity. Pure visual; reads
# the entity's purr component each display frame, never writes.

const NOTE_COUNT_MAX: int = 12

# Shared toggle so one keypress (N in game_client) flips notes for every
# entity at once. Default off — opt in when you want to see HUM-receiver
# coverage. The purr notes are debug-flavored; the player-facing purr
# feedback lives in the cat's own animation/audio.
static var notes_visible: bool = false

var entity_id: int = Constants.INVALID_ID
var _db: GameStateDB
var _phase: float = 0.0


func bind(db: GameStateDB, eid: int) -> void:
	_db = db
	entity_id = eid


func _process(delta: float) -> void:
	_phase += delta * 2.0  # ~2 rad/sec orbit
	queue_redraw()


func _draw() -> void:
	if not notes_visible:
		return
	if _db == null or not _db.has_entity(entity_id):
		return
	if not _db.has_component(entity_id, &"purr"):
		return
	var intensity: int = _db.get_field(entity_id, &"purr", &"intensity")
	var radius_px: int = _db.get_field(entity_id, &"purr", &"radius_px")
	if intensity <= 0 or radius_px <= 0:
		return

	var note_count: int = clampi(
		intensity * NOTE_COUNT_MAX / Constants.UNIT, 1, NOTE_COUNT_MAX,
	)
	var alpha: float = clampf(float(intensity) / float(Constants.UNIT), 0.0, 1.0)
	var color := Color(1.0, 1.0, 0.6, alpha)
	for i: int in note_count:
		var angle: float = _phase + (TAU * float(i) / float(note_count))
		var px: float = cos(angle) * float(radius_px)
		var py: float = sin(angle) * float(radius_px)
		# Tiny pixel "note": 1x2 vertical stem + 2x1 head.
		draw_rect(Rect2(px, py, 1, 2), color)
		draw_rect(Rect2(px + 1, py, 2, 1), color)
