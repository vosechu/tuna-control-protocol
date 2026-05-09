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
