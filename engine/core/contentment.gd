class_name Contentment extends RefCounted

const THRESHOLD: int = 400
const BARS: Array[StringName] = [&"warmth", &"comfort", &"hunger", &"attention"]
const BARS_NEEDED: int = 3

var _db: GameStateDB
var _purring_count: int = 0


func _init(db: GameStateDB) -> void:
	_db = db


func evaluate_all() -> void:
	_purring_count = 0
	var animals: Array[int] = _db.get_entities_with(&"species")
	for entity_id: int in animals:
		if not _db.has_component(entity_id, &"desires"):
			continue
		var desires: Dictionary = _db.get_component(entity_id, &"desires")
		var bars_met: int = 0
		for bar: StringName in BARS:
			if desires.has(bar) and desires[bar] >= THRESHOLD:
				bars_met += 1
		var is_purring: int = 1 if bars_met >= BARS_NEEDED else 0
		_db.set_component(entity_id, &"contentment", {&"is_purring": is_purring})
		if is_purring == 1:
			_purring_count += 1


func get_purring_count() -> int:
	return _purring_count
