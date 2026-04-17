class_name ScenarioSchemaValidator extends RefCounted

# Validates scenario JSONC definitions loaded at startup. A scenario lists
# entities to spawn into a fresh game state so tests and dev builds can
# exercise specific configurations without relying on hand-placed saves.
const _REQUIRED_TOP_FIELDS: Array[String] = ["schema_version", "id", "entities"]


func is_valid(def: Dictionary) -> bool:
	for field: String in _REQUIRED_TOP_FIELDS:
		if not def.has(field):
			return false
	var entities: Array = def.get("entities", [])
	for entry: Dictionary in entities:
		if not _entry_is_valid(entry):
			return false
	return true


func _entry_is_valid(entry: Dictionary) -> bool:
	if not entry.has("type"):
		return false
	var has_rack_slot: bool = entry.has("rack") and entry.has("slot")
	var has_floor: bool = entry.has("floor_rack") and entry.has("floor_slot_offset")
	return has_rack_slot or has_floor
