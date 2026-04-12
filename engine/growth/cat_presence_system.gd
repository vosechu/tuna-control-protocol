class_name CatPresenceSystem extends RefCounted

const _MAX_PRESENCE: int = 1000
const _INCREMENT_PER_TICK: int = 10
const _DECAY_PER_TICK: int = 5
const _PROXIMITY_RU: int = 1

var _db: GameStateDB


func _init(db: GameStateDB) -> void:
	_db = db


func tick() -> void:
	var servers: Array[int] = _db.get_entities_with(&"cat_presence")
	for server_id: int in servers:
		_evaluate(server_id)


func _evaluate(server_id: int) -> void:
	var server_pos: Dictionary = _db.get_component(server_id, &"position")
	var proximity_pu: int = _PROXIMITY_RU * Constants.SLOT_HEIGHT_PU * 2
	var nearby: bool = _any_cat_nearby(server_pos, proximity_pu)

	var current: int = _db.get_field(server_id, &"cat_presence", &"seconds")
	var next: int
	if nearby:
		next = mini(current + _INCREMENT_PER_TICK, _MAX_PRESENCE)
	else:
		next = maxi(current - _DECAY_PER_TICK, 0)
	_db.set_field(server_id, &"cat_presence", &"seconds", next)


func _any_cat_nearby(server_pos: Dictionary, max_dist_pu: int) -> bool:
	var cats: Array[int] = _db.get_entities_with(&"species")
	for cat_id: int in cats:
		if not _db.has_component(cat_id, &"position"):
			continue
		var cat_pos: Dictionary = _db.get_component(cat_id, &"position")
		var dx: int = absi(cat_pos[&"x"] - server_pos[&"x"])
		var dy: int = absi(cat_pos[&"y"] - server_pos[&"y"])
		if dx <= max_dist_pu and dy <= max_dist_pu:
			return true
	return false
