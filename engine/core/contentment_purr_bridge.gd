class_name ContentmentPurrBridge extends RefCounted

var _db: GameStateDB


func _init(db: GameStateDB) -> void:
	_db = db


func tick() -> void:
	for entity_id: int in _db.get_entities_with(&"purr"):
		if not _db.has_component(entity_id, &"contentment"):
			continue
		if not _db.has_component(entity_id, &"purr_config"):
			continue
		var is_satisfied: int = _db.get_field(entity_id, &"contentment", &"is_satisfied")
		var rate: int = _db.get_field(entity_id, &"purr_config", &"rate_when_satisfied")
		var intensity: int = rate if is_satisfied == 1 else 0
		_db.set_field(entity_id, &"purr", &"intensity", intensity)
