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
	# Translate scenario placement keys into a &"position" override that
	# EntityDefRegistry.spawn() already consumes. Phase 0 uses bay index 0
	# for all entities; cross-bay scenarios can add a `bay` field later.
	#
	# Rack placement: (rack, slot) → rack_slot_to_pu center.
	# Floor placement: (floor_rack, floor_slot_offset) → rack X center,
	# Y midway through the floor strip. Matches game_server.gd:615's
	# FLOOR_Y_PU + FLOOR_HEIGHT_PU/2 pattern.
	var out: Dictionary = {}
	if entry.has("rack") and entry.has("slot"):
		var rack: int = int(entry["rack"])
		var slot: int = int(entry["slot"])
		var pu: Vector2i = Constants.rack_slot_to_pu(0, rack, slot)
		out[&"position"] = {&"x": pu.x, &"y": pu.y}
	elif entry.has("floor_rack"):
		var floor_rack: int = int(entry["floor_rack"])
		var floor_x: int = Constants.rack_slot_to_pu(0, floor_rack, 0).x
		var floor_y: int = (
			Constants.FLOOR_Y * Constants.POSITION_SCALE
			+ Constants.FLOOR_HEIGHT_PU / 2
		)
		out[&"position"] = {&"x": floor_x, &"y": floor_y}
	# dispenser_ref left unconsumed for now — tuna_button/dispenser wiring
	# is handled by game_server.place_object today; scenario-time resolution
	# is a later-phase concern.
	return out
