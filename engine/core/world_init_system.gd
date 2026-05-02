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
	# Second pass: spawn, record ref_name → entity_id and defer cable_to /
	# settled_in_ref links until every ref has resolved.
	var refs: Dictionary = {}
	var pending_cables: Array = []
	var pending_settled: Array = []
	for entry: Dictionary in entities:
		var type_id: StringName = StringName(entry["type"])
		if not _entity_defs.has_entity(type_id):
			continue  # optional entry, silently skipped
		var overrides: Dictionary = _overrides_for(entry)
		var entity_id: int = _entity_defs.spawn(type_id, _db, overrides)
		if entry.has("ref_name"):
			refs[StringName(entry["ref_name"])] = entity_id
		if entry.has("cable_to"):
			var cable: Dictionary = entry["cable_to"]
			if cable.has("ref_name"):
				pending_cables.append({
					&"actuator_id": entity_id,
					&"ref_name": StringName(cable["ref_name"]),
				})
		if entry.has("ai_state"):
			# Seed the AI state component before scoring runs, so a
			# pre-settled cat doesn't immediately reroute somewhere.
			_db.set_component(entity_id, &"ai_state", {
				&"state": StringName(entry["ai_state"]),
				&"meta_state": &"AMBIENT",
				&"commitment_score": 0,
			})
		if entry.has("settled_in_ref"):
			pending_settled.append({
				&"joiner_id": entity_id,
				&"ref_name": StringName(entry["settled_in_ref"]),
			})
	# Third pass: resolve cable_to links now that every ref is registered.
	for cable: Dictionary in pending_cables:
		var actuator_id: int = cable[&"actuator_id"]
		var ref_name: StringName = cable[&"ref_name"]
		if not refs.has(ref_name):
			push_error(
				"world_init: cable_to.ref_name not found: %s" % ref_name
			)
			continue
		var hum_id: int = refs[ref_name]
		_db.set_component(actuator_id, &"hum_cable", {&"hum_id": hum_id})
	# Fourth pass: resolve settled_in_ref. Position the joiner at the host's
	# anchor and write the settled_in marker, so the rendering tuck-in and
	# the move-loop's stranded-animal heuristic both see a deliberate rest.
	if pending_settled.is_empty():
		return
	var lifecycle := SettledLifecycle.new(_db)
	for s: Dictionary in pending_settled:
		var joiner_id: int = s[&"joiner_id"]
		var s_ref: StringName = s[&"ref_name"]
		if not refs.has(s_ref):
			push_error(
				"world_init: settled_in_ref not found: %s" % s_ref
			)
			continue
		var host_id: int = refs[s_ref]
		var host_pos: Dictionary = _db.get_component(host_id, &"position")
		var hx: int = host_pos[&"x"]
		var hy: int = host_pos[&"y"]
		_db.set_component(joiner_id, &"position", {&"x": hx, &"y": hy})
		_db.update_spatial(joiner_id, hx, hy)
		lifecycle.enter(joiner_id, host_id)


func _overrides_for(entry: Dictionary) -> Dictionary:
	# Translate scenario placement keys into a &"position" override that
	# EntityDefRegistry.spawn() already consumes. Phase 0 uses bay index 0
	# for all entities; cross-bay scenarios can add a `bay` field later.
	#
	# Rack placement: (rack, slot) → center of slot in world pixels.
	# Floor placement: (floor_rack, floor_slot_offset) → rack X center,
	# Y midway through the floor strip.
	var out: Dictionary = {}
	if entry.has("name"):
		out[&"name"] = StringName(entry["name"])
	if entry.has("rack") and entry.has("slot"):
		var rack: int = int(entry["rack"])
		var slot: int = int(entry["slot"])
		var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
		var cx: int = slot_rect.position.x + slot_rect.size.x / 2
		var cy: int = slot_rect.position.y + slot_rect.size.y / 2
		out[&"position"] = {&"x": cx, &"y": cy}
	elif entry.has("floor_rack"):
		var floor_rack: int = int(entry["floor_rack"])
		var rack_col: Rect2i = Constants.rack_column_rect_world(0, floor_rack)
		var floor_x: int = rack_col.position.x + rack_col.size.x / 2
		var floor_rect: Rect2i = Constants.floor_rect_world(0)
		var floor_y: int = floor_rect.position.y + floor_rect.size.y / 2
		out[&"position"] = {&"x": floor_x, &"y": floor_y}
	# dispenser_ref left unconsumed for now — tuna_button/dispenser wiring
	# is handled by game_server.place_object today; scenario-time resolution
	# is a later-phase concern.
	return out
