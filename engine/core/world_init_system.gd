class_name WorldInitSystem extends RefCounted

# Applies a scenario definition by spawning its entities into a fresh
# GameStateDB. A scenario is a list of entity refs (type + placement) that
# lets tests and dev builds stand up a specific configuration without hand-
# placed saves. Required entities abort the whole population on failure;
# optional entries (`required: false`) are silently skipped when their type
# is not registered.
var _db: GameStateDB
var _entity_defs: EntityDefRegistry
var _scenarios: ScenarioRegistry


func _init(
		db: GameStateDB,
		entity_defs: EntityDefRegistry,
		scenarios: ScenarioRegistry,
) -> void:
	_db = db
	_entity_defs = entity_defs
	_scenarios = scenarios


func apply(scenario_id: StringName) -> void:
	if not _scenarios.has_scenario(scenario_id):
		push_error("world_init: scenario not found: %s" % scenario_id)
		return
	var def: Dictionary = _scenarios.get_scenario(scenario_id)
	var entities: Array = def.get("entities", [])
	# Two-pass: verify required entities resolve, then spawn.
	for entry: Dictionary in entities:
		var required: bool = entry.get("required", true)
		var type_id: StringName = StringName(entry["type"])
		if required and not _entity_defs.has_entity(type_id):
			push_error(
				"world_init aborted: required type missing: %s" % type_id
			)
			return
	for entry: Dictionary in entities:
		var type_id: StringName = StringName(entry["type"])
		if not _entity_defs.has_entity(type_id):
			continue  # optional entry, silently skipped
		var overrides: Dictionary = _overrides_for(entry)
		_entity_defs.spawn(type_id, _db, overrides)


func _overrides_for(entry: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if entry.has("rack"):
		out["rack"] = entry["rack"]
	if entry.has("slot"):
		out["slot"] = entry["slot"]
	if entry.has("floor_rack"):
		out["floor_rack"] = entry["floor_rack"]
	if entry.has("floor_slot_offset"):
		out["floor_slot_offset"] = entry["floor_slot_offset"]
	if entry.has("dispenser_ref"):
		out["dispenser_ref"] = entry["dispenser_ref"]
	return out
