class_name SensoryEmissionSystem extends RefCounted

# Per-tick translator from animal interior state to broadcast emission
# components. Reads `sensory_emissions` (materialized from recipe at
# spawn) and writes per-output components like `purr {intensity,
# radius_px}`. Trigger fail OR base evaluating to ≤0 produces a
# zero-intensity, zero-radius emission — both fields are written every
# tick to prevent stale values from charging downstream receivers
# (regression: see test_sensory_emission_radius.test_stale_radius_zeroed_after_trigger_fails).
#
# AI-DEV: All data is canonicalized at materialization. Value sources
# arrive here as {kind: &"literal"|&"ref", ...} dicts; modifiers arrive
# pre-sorted by priority. Do NOT add Variant-handling fallbacks in this
# hot path — if the materializer changes shape, fix the materializer
# (engine/mod/entity_def_registry.gd) and the schema validator first.

var _db: GameStateDB


func _init(db: GameStateDB, _output_config: Dictionary) -> void:
	# output_config is reserved for future channel-aware behavior
	# (falloff queries, channel→listener mapping). Today the runner only
	# needs the recipe data on each entity.
	_db = db


func tick() -> void:
	for entity_id: int in _db.get_entities_with(&"sensory_emissions"):
		_emit_one(entity_id)


func _emit_one(entity_id: int) -> void:
	var emissions: Dictionary = _db.get_component(
		entity_id, &"sensory_emissions"
	)
	for output_name: StringName in emissions:
		var def: Dictionary = emissions[output_name]
		var intensity: int = _evaluate_intensity(entity_id, def)
		_db.set_field(entity_id, output_name, &"intensity", intensity)
		var base_radius_ru: int = _read_value(
			entity_id, def[&"base_radius_ru"]
		)
		var radius_px: int = (
			base_radius_ru * Constants.SLOT_HEIGHT_PX * intensity
			/ Constants.UNIT
		)
		_db.set_field(entity_id, output_name, &"radius_px", radius_px)


func _evaluate_intensity(entity_id: int, def: Dictionary) -> int:
	if def.has(&"trigger") and not _trigger_passes(entity_id, def[&"trigger"]):
		return 0
	var intensity: int = _read_value(entity_id, def[&"base_intensity"])
	for modifier: Dictionary in def[&"modifiers"]:
		intensity = _apply_modifier(entity_id, intensity, modifier)
	if intensity < 0:
		return 0
	return intensity


func _trigger_passes(entity_id: int, trigger: Dictionary) -> bool:
	var component: StringName = trigger[&"component"]
	if not _db.has_component(entity_id, component):
		return false
	var actual: int = _db.get_field(
		entity_id, component, trigger[&"field"]
	)
	return actual == int(trigger[&"equals"])


func _apply_modifier(
		entity_id: int, intensity: int, modifier: Dictionary) -> int:
	var component: StringName = modifier[&"component"]
	if not _db.has_component(entity_id, component):
		return intensity
	var value: int = _db.get_field(
		entity_id, component, modifier[&"field"]
	)
	var op: StringName = modifier[&"op"]
	match op:
		&"factor":
			return intensity * value / Constants.UNIT
		&"inverse_factor":
			return intensity * (Constants.UNIT - value) / Constants.UNIT
		_:
			push_error(
				"SensoryEmissionSystem: unknown modifier op '%s'" % op
			)
			return intensity


func _read_value(entity_id: int, source: Dictionary) -> int:
	var kind: StringName = source[&"kind"]
	match kind:
		&"literal":
			return int(source[&"value"])
		&"ref":
			return _db.get_field(
				entity_id, source[&"component"], source[&"field"]
			)
		_:
			push_error(
				"SensoryEmissionSystem: unknown value source kind '%s'" % kind
			)
			return 0
