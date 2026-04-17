class_name ScenarioRegistry extends RefCounted

# Holds scenario definitions (validated JSONC) for lookup by id. A scenario
# names a set of entities that should be spawned into a fresh game state so
# tests and dev builds can exercise specific configurations without hand-
# placed saves. Validation lives in ScenarioSchemaValidator; this class only
# stores and retrieves.
var _scenarios: Dictionary = {}  # StringName -> Dictionary


func register(id: StringName, def: Dictionary) -> void:
	_scenarios[id] = def


func has_scenario(id: StringName) -> bool:
	return _scenarios.has(id)


func get_scenario(id: StringName) -> Dictionary:
	if not _scenarios.has(id):
		return {}
	return _scenarios[id]


func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	var keys: Array = _scenarios.keys()
	keys.sort()
	for k: StringName in keys:
		result.append(k)
	return result
