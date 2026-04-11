class_name EntityDefRegistry extends RefCounted

var _definitions: Dictionary = {}  # StringName -> Dictionary


func register(entity_id: StringName, definition: Dictionary) -> void:
	assert(
		not _definitions.has(entity_id),
		"EntityDefRegistry: duplicate entity ID: %s" % entity_id,
	)
	_definitions[entity_id] = definition


func has_entity(entity_id: StringName) -> bool:
	return _definitions.has(entity_id)


func get_definition(entity_id: StringName) -> Dictionary:
	assert(
		_definitions.has(entity_id),
		"EntityDefRegistry: unknown entity: %s" % entity_id,
	)
	return _definitions[entity_id]


func get_all_entities() -> Array[StringName]:
	var result: Array[StringName] = []
	for key: StringName in _definitions:
		result.append(key)
	return result


func has_traversal(entity_id: StringName) -> bool:
	if not _definitions.has(entity_id):
		return false
	var def: Dictionary = _definitions[entity_id]
	return def.has("traversal") and not def["traversal"].is_empty()


func has_desires(entity_id: StringName) -> bool:
	if not _definitions.has(entity_id):
		return false
	var def: Dictionary = _definitions[entity_id]
	return def.has("desires") and not def["desires"].is_empty()


func get_traversal(entity_id: StringName) -> Array:
	var def: Dictionary = get_definition(entity_id)
	return def.get("traversal", [])


func get_desires(entity_id: StringName) -> Dictionary:
	var def: Dictionary = get_definition(entity_id)
	return def.get("desires", {})


func get_states(entity_id: StringName) -> Dictionary:
	var def: Dictionary = get_definition(entity_id)
	return def.get("states", {})


func get_initial_state(entity_id: StringName) -> StringName:
	var def: Dictionary = get_definition(entity_id)
	return StringName(def.get("initial_state", "idle"))
