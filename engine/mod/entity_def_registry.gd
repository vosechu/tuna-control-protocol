class_name EntityDefRegistry extends RefCounted

# Per-channel default initial satisfaction for entities spawned without
# an explicit `desires` override. Hunger is seeded above the
# `CatFoodStates.HUNGER_THRESHOLD` (400) so a freshly-spawned animal
# doesn't immediately PACE for an unreachable dispenser; everything
# else stays at the conservative deficit baseline so the desire
# resolver still has work to do at boot.
# AI-DEV: tunable balance number. Move to config when the balance
# pass starts; keep in code for now so spawn can run without
# ConfigRegistry being threaded through.
const _DEFAULT_INITIAL_SATISFACTION: int = 200
const _DEFAULT_INITIAL_SATISFACTION_BY_KEY: Dictionary = {
	&"hunger": 600,
}

var _definitions: Dictionary = {}  # StringName -> Dictionary


# AI-DEV: One-shot migrator for the desire_type→channel and
# radius_px→effect_radius_px rename shipped in PR2 of the
# perception-channels migration. Called wherever an ad dict is
# materialized onto an entity so out-of-tree mods on the legacy shape
# still load. Stays in place after in-tree migration completes —
# rename is a breaking change (see CHANNELS namespace policy in
# docs/superpowers/specs/2026-05-02-perception-channels-design.md).
static func migrate_ad(ad: Dictionary) -> Dictionary:
	var out: Dictionary = ad.duplicate()
	if out.has(&"desire_type") and not out.has(&"channel"):
		out[&"channel"] = out[&"desire_type"]
		out.erase(&"desire_type")
	if out.has(&"radius_px") and not out.has(&"effect_radius_px"):
		out[&"effect_radius_px"] = out[&"radius_px"]
		out.erase(&"radius_px")
	# Same shape with String keys (out-of-tree mods loading from JSONC
	# may still have String-keyed dicts before _to_stringname_keys runs).
	if out.has("desire_type") and not out.has("channel") and not out.has(&"channel"):
		out["channel"] = out["desire_type"]
		out.erase("desire_type")
	if out.has("radius_px") and not out.has("effect_radius_px") and not out.has(&"effect_radius_px"):
		out["effect_radius_px"] = out["radius_px"]
		out.erase("radius_px")
	return out


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

	# Desires + personality + decay (species only).
	#
	# v4 shape: each desires entry is an object {weight: int, decay: int}.
	# v3 fallback: bare-int entries are tolerated as {weight: <int>, decay: 0}
	# so phase 1 doesn't require recipe rewrites; phase 2's validator rejects
	# bare-int entries and the fallback becomes dead code.
	if def.has("desires") and not def["desires"].is_empty():
		var base_desires: Dictionary = def["desires"]
		var desire_overrides: Dictionary = overrides.get(
			&"desires", {},
		)
		var personality: Dictionary = {}
		var initial_desires: Dictionary = {}
		var desire_decay: Dictionary = {}
		for key: String in base_desires:
			var skey: StringName = StringName(key)
			var entry_value: Variant = base_desires[key]

			var weight: int
			var decay: int
			if entry_value is Dictionary:
				weight = int((entry_value as Dictionary).get("weight", 0))
				decay = int((entry_value as Dictionary).get("decay", 0))
			else:
				weight = int(entry_value)
				decay = 0

			if def.has("personality_ranges") \
					and def["personality_ranges"].has(key):
				var bounds: Array = def["personality_ranges"][key]
				var min_val: int = int(bounds[0])
				var max_val: int = int(bounds[1])
				personality[StringName(key + "_weight")] = \
					randi_range(min_val, max_val)
			else:
				personality[StringName(key + "_weight")] = weight

			# Deep-merge: override wins if present, else per-channel default
			if desire_overrides.has(skey):
				initial_desires[skey] = int(desire_overrides[skey])
			else:
				initial_desires[skey] = _DEFAULT_INITIAL_SATISFACTION_BY_KEY.get(
					skey, _DEFAULT_INITIAL_SATISFACTION,
				)

			desire_decay[skey] = decay

		db.set_component(id, &"desires", initial_desires)
		db.set_component(id, &"personality", personality)
		db.set_component(id, &"desire_decay", desire_decay)

	# Senses: per-channel perception acuity (sight/hearing/smell/touch).
	# Required by SpeciesSchemaValidator at mod load — by the time we get
	# here the block must be present on any species recipe.
	if def.has("senses"):
		var senses: Dictionary = {}
		for skey: String in def["senses"]:
			senses[StringName(skey)] = int(def["senses"][skey])
		db.set_component(id, &"senses", senses)

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

	# Per-name special-state durations (STARTLED today; RELOCATING/BEING_CARRIED
	# future). Required on any recipe that declares ambient_states (validator
	# enforces in phase 2). Recipes without it just don't materialize.
	if def.has("special_states"):
		var specials: Dictionary = def["special_states"]
		var typed_specials: Dictionary = {}
		for state_name: String in specials:
			var entry: Dictionary = specials[state_name]
			typed_specials[StringName(state_name)] = _to_stringname_keys(entry)
		db.set_component(id, &"special_states", typed_specials)

	# Capability tags: any recipe-level boolean field we want to project
	# onto the entity as a zero-data component.
	if def.get("tends_servers", false):
		db.set_component(id, &"tends_servers", {})

	# Sensory emissions: data-driven multi-output emission. Recipes
	# declare what they emit (purr today; future channels gain their
	# own output entries). The materializer canonicalizes value sources
	# so the runtime sees no Variant.
	if def.has("sensory_emissions"):
		var emissions: Dictionary = _materialize_sensory_emissions(
			def["sensory_emissions"]
		)
		db.set_component(id, &"sensory_emissions", emissions)
		for output_name: StringName in emissions:
			db.set_component(
				id, output_name,
				{&"intensity": 0, &"radius_px": 0},
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

	# State-driven advertisements (set for initial state).
	#
	# Note: migrate_ad is intentionally NOT wired here. In-tree mods are
	# rewritten on the new shape (Tasks 12, 13 of perception-channels);
	# out-of-tree mods on the legacy shape will need migrate_ad at a
	# higher injection point — to be designed alongside score_ad's
	# channel-aware read (Task 14). Wiring migrate_ad here today would
	# break consumers that still read the legacy `desire_type` key.
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


# Materializes the recipe's sensory_emissions block:
#   - Recursively converts String keys to StringName at every nesting level.
#   - Canonicalizes value sources (base_intensity, base_radius_ru):
#       int literal -> {kind: &"literal", value: int}
#       {component, field} -> {kind: &"ref", component, field}
#   - Sorts each modifiers list by priority ascending; ties preserve list order.
func _materialize_sensory_emissions(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for output_name in raw:
		var entry: Dictionary = raw[output_name]
		out[StringName(output_name)] = _materialize_emission_entry(entry)
	return out


func _materialize_emission_entry(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if raw.has("trigger"):
		out[&"trigger"] = _to_stringname_keys_recursive(raw["trigger"])
	out[&"base_intensity"] = _canonicalize_value_source(raw["base_intensity"])
	out[&"base_radius_ru"] = _canonicalize_value_source(raw["base_radius_ru"])

	var raw_mods: Array = raw.get("modifiers", [])
	var typed_mods: Array[Dictionary] = []
	for m: Dictionary in raw_mods:
		typed_mods.append(_to_stringname_keys_recursive(m))
	typed_mods.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var pa: int = int(a.get(&"priority", 0))
			var pb: int = int(b.get(&"priority", 0))
			return pa < pb
	)
	out[&"modifiers"] = typed_mods
	return out


func _canonicalize_value_source(raw: Variant) -> Dictionary:
	# JSON.parse() returns numbers as float; recipes built in code use int.
	# Coerce both to int for the canonical form.
	if raw is int or raw is float:
		return {&"kind": &"literal", &"value": int(raw)}
	if raw is Dictionary:
		var d: Dictionary = raw
		return {
			&"kind": &"ref",
			&"component": StringName(d["component"]),
			&"field": StringName(d["field"]),
		}
	push_error("EntityDefRegistry: bad value source: %s" % raw)
	return {&"kind": &"literal", &"value": 0}


# Recursive variant of _to_stringname_keys. Converts String dict keys to
# StringName at every nesting level; String values are also converted to
# StringName (modifier op/component/field, trigger component/field).
# Numeric/bool/Array values pass through (Array elements that are dicts
# are recursed into; primitive Array elements pass through).
func _to_stringname_keys_recursive(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in d:
		var v: Variant = d[key]
		var sn_key: StringName = StringName(key)
		if v is Dictionary:
			out[sn_key] = _to_stringname_keys_recursive(v)
		elif v is String:
			out[sn_key] = StringName(v)
		else:
			out[sn_key] = v
	return out
