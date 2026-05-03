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
	# AI-DEV: Sort by String value, not Array.sort() default. Untyped
	# Array.sort() on StringNames compares by interned ID (creation order),
	# so lexical-vs-id collision passes in isolation but flips when the
	# full-suite run interns these literals in a different order.
	var result: Array[StringName] = []
	var keys: Array = _scenarios.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b))
	for k: StringName in keys:
		result.append(k)
	return result
