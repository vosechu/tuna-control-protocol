class_name InspectDrawerState extends RefCounted

# State machine + content builders for the inspect drawer.
# Pure RefCounted — no scene tree, no signals.
# Per docs/superpowers/specs/2026-05-09-inspect-drawer-design.md.

enum ContentType { CLOSED, ANIMAL, SERVER }

var inspected_id: int = Constants.INVALID_ID
var content_type: int = ContentType.CLOSED


func open(entity_id: int) -> void:
	if entity_id == Constants.INVALID_ID:
		return
	inspected_id = entity_id


func close() -> void:
	inspected_id = Constants.INVALID_ID
	content_type = ContentType.CLOSED


func is_open() -> bool:
	return inspected_id != Constants.INVALID_ID


func process(db: GameStateDB) -> void:
	if inspected_id == Constants.INVALID_ID:
		return
	if not db.has_entity(inspected_id):
		close()
		return
	if db.has_component(inspected_id, &"desires"):
		content_type = ContentType.ANIMAL
	elif db.has_component(inspected_id, &"object_type"):
		content_type = ContentType.SERVER
	else:
		close()


func derive_status_keyword(db: GameStateDB) -> StringName:
	if content_type == ContentType.ANIMAL:
		if not db.has_component(inspected_id, &"contentment"):
			return &"Wanting"
		var c: Dictionary = db.get_component(inspected_id, &"contentment")
		if int(c.get(&"is_satisfied", 0)) == 1:
			return &"Content"
		return &"Wanting"
	if content_type == ContentType.SERVER:
		for hum_id: int in db.get_entities_with(&"hum"):
			var h: Dictionary = db.get_component(hum_id, &"hum")
			if int(h.get(&"reserve", 0)) > 0:
				return &"Powered"
		return &"Unpowered"
	return &""
