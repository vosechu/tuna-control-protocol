class_name ReclamationSystem extends RefCounted

const _MAX_PRESENCE: int = 1000
const _INCREMENT_PER_TICK: int = 10
const _DECAY_PER_TICK: int = 5
# Proximity in pixels: 1 slot-height, doubled by the ×2 bounding-box formula.
const _PROXIMITY_PX: int = 8

var _db: GameStateDB


func _init(db: GameStateDB) -> void:
	_db = db


func tick() -> void:
	var servers: Array[int] = _db.get_entities_with(&"reclamation")
	for server_id: int in servers:
		_evaluate(server_id)


func _evaluate(server_id: int) -> void:
	var server_pos: Dictionary = _db.get_component(server_id, &"position")
	var proximity_px: int = _PROXIMITY_PX * 2
	var nearby: bool = _any_tender_nearby(server_pos, proximity_px)

	var current: int = _db.get_field(server_id, &"reclamation", &"seconds")
	var next: int
	if nearby:
		next = mini(current + _INCREMENT_PER_TICK, _MAX_PRESENCE)
	else:
		next = maxi(current - _DECAY_PER_TICK, 0)
	_db.set_field(server_id, &"reclamation", &"seconds", next)


func _any_tender_nearby(server_pos: Dictionary, max_dist_px: int) -> bool:
	var tenders: Array[int] = _db.get_entities_with(&"tends_servers")
	for tender_id: int in tenders:
		if not _db.has_component(tender_id, &"position"):
			continue
		var tpos: Dictionary = _db.get_component(tender_id, &"position")
		var dx: int = absi(tpos[&"x"] - server_pos[&"x"])
		var dy: int = absi(tpos[&"y"] - server_pos[&"y"])
		if dx <= max_dist_px and dy <= max_dist_px:
			return true
	return false
