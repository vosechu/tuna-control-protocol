class_name ContentmentPurrBridge extends RefCounted

var _db: GameStateDB


func _init(db: GameStateDB) -> void:
	_db = db


func tick() -> void:
	# AI-DEV: This bridge writes BOTH purr.intensity AND purr.radius_px each
	# tick. radius_px = base_radius_ru * SLOT_HEIGHT_PX * intensity / UNIT.
	# Future inputs (mood, kitten amplifier, stress) compose into the formula;
	# do not reintroduce a fixed-radius shortcut.
	for entity_id: int in _db.get_entities_with(&"purr"):
		if not _db.has_component(entity_id, &"contentment"):
			continue
		if not _db.has_component(entity_id, &"purr_config"):
			continue
		var is_satisfied: int = _db.get_field(entity_id, &"contentment", &"is_satisfied")
		var rate: int = _db.get_field(entity_id, &"purr_config", &"rate_when_satisfied")
		var intensity: int = rate if is_satisfied == 1 else 0
		_db.set_field(entity_id, &"purr", &"intensity", intensity)

		var base_radius_ru: int = _db.get_field(
			entity_id, &"purr_config", &"base_radius_ru"
		)
		var base_radius_px: int = base_radius_ru * Constants.SLOT_HEIGHT_PX
		var radius_px: int = base_radius_px * intensity / Constants.UNIT
		_db.set_field(entity_id, &"purr", &"radius_px", radius_px)
