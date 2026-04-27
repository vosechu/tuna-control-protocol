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


func has_body_capabilities(entity_id: StringName) -> bool:
	if not _definitions.has(entity_id):
		return false
	var def: Dictionary = _definitions[entity_id]
	return (
		def.has("body_capabilities")
		and not (def["body_capabilities"] as Dictionary).is_empty()
	)


func has_desires(entity_id: StringName) -> bool:
	if not _definitions.has(entity_id):
		return false
	var def: Dictionary = _definitions[entity_id]
	return def.has("desires") and not def["desires"].is_empty()


func get_body_capabilities(entity_id: StringName) -> Dictionary:
	var def: Dictionary = get_definition(entity_id)
	return def.get("body_capabilities", {})


func get_body_geometry(entity_id: StringName) -> Dictionary:
	var def: Dictionary = get_definition(entity_id)
	return def.get("body_geometry", {})


func get_desires(entity_id: StringName) -> Dictionary:
	var def: Dictionary = get_definition(entity_id)
	return def.get("desires", {})


func get_states(entity_id: StringName) -> Dictionary:
	var def: Dictionary = get_definition(entity_id)
	return def.get("states", {})


func get_initial_state(entity_id: StringName) -> StringName:
	var def: Dictionary = get_definition(entity_id)
	return StringName(def.get("initial_state", "idle"))


func spawn(
		entity_id: StringName, db: GameStateDB,
		overrides: Dictionary = {},
) -> int:
	assert(
		_definitions.has(entity_id),
		"EntityDefRegistry.spawn: unknown entity: %s"
		% entity_id,
	)
	var def: Dictionary = _definitions[entity_id]
	var id: int = db.create_entity()

	# Species component
	var variant: String = ""
	if def.has("variants") and not def["variants"].is_empty():
		var variants: Array = def["variants"]
		variant = variants[randi() % variants.size()]
	var species_data: Dictionary = {
		&"id": entity_id,
		&"variant": StringName(variant),
		&"name": overrides.get(
			&"name", StringName(def.get("name", "")),
		),
	}
	db.set_component(id, &"species", species_data)

	# Position from overrides
	if overrides.has(&"position"):
		var pos: Dictionary = overrides[&"position"]
		db.set_component(id, &"position", pos)
		db.update_spatial(
			id, pos.get(&"x", 0), pos.get(&"y", 0),
		)

	# Desires + personality (species only)
	if def.has("desires") and not def["desires"].is_empty():
		var base_desires: Dictionary = def["desires"]
		var desire_overrides: Dictionary = overrides.get(
			&"desires", {},
		)
		var personality: Dictionary = {}
		var initial_desires: Dictionary = {}
		for key: String in base_desires:
			var skey: StringName = StringName(key)
			if def.has("personality_ranges") \
					and def["personality_ranges"].has(key):
				var bounds: Array = def["personality_ranges"][key]
				var min_val: int = int(bounds[0])
				var max_val: int = int(bounds[1])
				personality[StringName(key + "_weight")] = \
					randi_range(min_val, max_val)
			else:
				personality[StringName(key + "_weight")] = \
					int(base_desires[key])
			# Deep-merge: override wins if present, else default
			if desire_overrides.has(skey):
				initial_desires[skey] = int(desire_overrides[skey])
			else:
				initial_desires[skey] = 200
		db.set_component(id, &"desires", initial_desires)
		db.set_component(id, &"personality", personality)

	# AI state (species only — entities with body_capabilities)
	if has_body_capabilities(entity_id):
		var initial: StringName = get_initial_state(entity_id)
		db.set_component(id, &"ai_state", {
			&"state": initial,
			&"meta_state": &"AMBIENT",
			&"commitment_score": 0,
		})
		db.set_component(id, &"target", {
			&"x": Constants.INVALID_ID,
			&"y": Constants.INVALID_ID,
			&"entity_id": Constants.INVALID_ID,
		})

	# Object state (entities without body_capabilities that have states)
	if not has_body_capabilities(entity_id) and def.has("states"):
		var initial: StringName = get_initial_state(entity_id)
		db.set_component(
			id, &"object_state", {&"state": initial},
		)
		db.set_component(
			id, &"object_type", {&"type": entity_id},
		)

	# Physical properties
	if def.has("physical"):
		db.set_component(id, &"physical", {
			&"mass": int(def["physical"].get("mass", 0)),
			&"size_ru": int(def["physical"].get("size_ru", 1)),
		})

	# Body schema: capabilities (verbs the body knows) + geometry (physical
	# extents the navgraph and fit-checks read).
	if def.has("body_capabilities"):
		db.set_component(id, &"body_capabilities", def["body_capabilities"])
	if def.has("body_geometry"):
		db.set_component(id, &"body_geometry", def["body_geometry"])

	# Capability tags: any recipe-level boolean field we want to project
	# onto the entity as a zero-data component.
	if def.get("tends_servers", false):
		db.set_component(id, &"tends_servers", {})

	# Zero-data capability tag: presence of the key materializes the component,
	# regardless of the value (recipes write `"hum_powered": {}`).
	if def.has("hum_powered"):
		db.set_component(id, &"hum_powered", {})

	# Purr emitter: split recipe dict into two DB components.
	# purr.intensity is the per-tick broadcast value (hot path, read by HumSystem).
	# purr.radius_px is also per-tick, written by ContentmentPurrBridge.
	# purr_config holds cold recipe snapshots (rate_when_satisfied, base_radius_ru).
	if def.has("purr"):
		var purr_cfg: Dictionary = def["purr"]
		var rate: int = int(purr_cfg.get("rate_when_satisfied", 0))
		var base_radius_ru: int = int(purr_cfg.get("base_radius_ru", 0))
		db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
		db.set_component(
			id, &"purr_config",
			{&"rate_when_satisfied": rate, &"base_radius_ru": base_radius_ru},
		)

	# HUM battery: recipe declares capacity; entity starts at full reserve.
	# Falls back to HumSystem.DEFAULT_CAPACITY when recipe omits the field.
	if def.has("hum"):
		var hum_cfg: Dictionary = def["hum"]
		var capacity: int = int(hum_cfg.get("capacity", HumSystem.DEFAULT_CAPACITY))
		db.set_component(id, &"hum", {&"reserve": capacity, &"capacity": capacity})

	if def.has("sprite_config"):
		db.set_component(id, &"sprite_config", def["sprite_config"])

	if def.has("ambient_states"):
		db.set_component(id, &"ambient_states", def["ambient_states"])

	if def.has("hud_color"):
		var c: Array = def["hud_color"]
		db.set_component(id, &"hud_color", {
			&"r": float(c[0]), &"g": float(c[1]), &"b": float(c[2]),
		})

	# Object-component projections: recipe-level dicts for known object
	# component names are promoted directly onto the entity. Keys are
	# rewritten to StringName so the hot path can use get_field()/set_field()
	# with StringName dict keys.
	for comp_name: StringName in [
		&"hum_receiver",
		&"arm",
		&"tuna_dispenser",
		&"tuna_button",
		&"heat_source",
	]:
		var comp_str: String = String(comp_name)
		if def.has(comp_str):
			var data: Dictionary = def[comp_str]
			db.set_component(id, comp_name, _to_stringname_keys(data))

	# State-driven advertisements (set for initial state)
	var state_ads_set: bool = false
	if def.has("states"):
		var initial: StringName = get_initial_state(entity_id)
		var states: Dictionary = def["states"]
		var istr: String = String(initial)
		if states.has(istr) \
				and states[istr].has("advertisements"):
			var ads: Array = states[istr]["advertisements"]
			if not ads.is_empty():
				db.set_component(
					id, &"advertisements", {&"list": ads},
				)
				state_ads_set = true

	# Top-level advertisements (for stateless objects like dispensers).
	# Skip if the state-driven path already set them.
	if not state_ads_set and def.has("advertisements"):
		var top_ads: Array = def["advertisements"]
		if not top_ads.is_empty():
			var typed_list: Array = []
			for ad: Dictionary in top_ads:
				typed_list.append(_to_stringname_keys(ad))
			db.set_component(
				id, &"advertisements", {&"list": typed_list},
			)

	return id


# Convert a Dictionary with String keys to the same Dictionary with
# StringName keys. Values passed through unchanged. Needed because JSONC
# parsing produces String keys but the component hot paths use StringName.
func _to_stringname_keys(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in d:
		out[StringName(key)] = d[key]
	return out
