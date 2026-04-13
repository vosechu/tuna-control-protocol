class_name VerbResolver extends RefCounted


func can_perform(
		verb_id: StringName, actor_id: int,
		target_id: int, db: GameStateDB,
		entity_defs: EntityDefRegistry,
) -> bool:
	var species_id: StringName = db.get_component(
		actor_id, &"species",
	)[&"id"]
	var def: Dictionary = entity_defs.get_definition(species_id)
	if not def.has("verbs") \
			or not def["verbs"].has(String(verb_id)):
		return false
	var verb: Dictionary = def["verbs"][String(verb_id)]
	return _check_physics(
		verb, actor_id, target_id, db, def,
	)


func score_verbs(
		actor_id: int, target_id: int,
		db: GameStateDB,
		entity_defs: EntityDefRegistry,
) -> StringName:
	if not db.has_component(actor_id, &"species"):
		return &""
	var species_id: StringName = db.get_component(
		actor_id, &"species",
	)[&"id"]
	if not entity_defs.has_entity(species_id):
		return &""
	var def: Dictionary = entity_defs.get_definition(species_id)
	if not def.has("verbs"):
		return &""
	var best_verb: StringName = &""
	var best_score: int = 0
	for verb_name: String in def["verbs"]:
		var verb: Dictionary = def["verbs"][verb_name]
		if not _check_physics(
				verb, actor_id, target_id, db, def):
			continue
		var score: int = _score_desire_affinity(
			verb, actor_id, db,
		)
		if score > best_score:
			best_score = score
			best_verb = StringName(verb_name)
	return best_verb


func _check_physics(
		verb: Dictionary, actor_id: int,
		target_id: int, db: GameStateDB,
		species_def: Dictionary,
) -> bool:
	if not verb.has("effectiveness"):
		if not db.has_component(actor_id, &"physical") \
				or not db.has_component(
					target_id, &"physical"):
			return false
		var actor_size: int = db.get_component(
			actor_id, &"physical",
		)[&"size_ru"]
		var target_size: int = db.get_component(
			target_id, &"physical",
		)[&"size_ru"]
		return actor_size <= target_size
	var strength: int = int(species_def.get("strength", 0))
	var effectiveness: int = int(verb["effectiveness"])
	if not db.has_component(target_id, &"physical"):
		return false
	var target_mass: int = db.get_component(
		target_id, &"physical",
	)[&"mass"]
	return strength * effectiveness / 1000 > target_mass


func _score_desire_affinity(
		verb: Dictionary, actor_id: int,
		db: GameStateDB,
) -> int:
	if not verb.has("desire_affinities"):
		return 1
	var affinities: Dictionary = verb["desire_affinities"]
	if not db.has_component(actor_id, &"desires"):
		return 0
	var desires: Dictionary = db.get_component(
		actor_id, &"desires",
	)
	var max_score: int = 0
	for channel: String in affinities:
		var affinity: int = int(affinities[channel])
		var desire_val: int = int(
			desires.get(StringName(channel), 0),
		)
		var score: int = affinity * desire_val / 1000
		if score > max_score:
			max_score = score
	return max_score
