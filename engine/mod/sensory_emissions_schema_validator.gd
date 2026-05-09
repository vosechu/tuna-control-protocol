class_name SensoryEmissionsSchemaValidator extends RefCounted

# Validates `sensory_emissions` blocks declared on species recipes against
# a global output/channel registry (config/balance/sensory_outputs.jsonc).
# Each rule rejection emits a distinct `push_error` so tests can assert
# substring per rule. The runtime materializer trusts a recipe that
# passed this validator — it does not re-check shape.

const _KNOWN_OPS: Array[StringName] = [&"factor", &"inverse_factor"]
const _KNOWN_FALLOFFS: Array[StringName] = [
	&"quadratic", &"linear", &"step", &"inverse_square",
]

var _output_config: Dictionary


func _init(output_config: Dictionary) -> void:
	_output_config = output_config


func validate(
		emissions: Dictionary,
		known_components: Array[String] = []) -> bool:
	var all_ok: bool = true
	var outputs: Dictionary = _get_outputs()
	for output_name: Variant in emissions:
		var entry: Variant = emissions[output_name]
		if not (entry is Dictionary):
			push_error(
				"SensoryEmissions: %s entry is not a Dictionary" % output_name
			)
			all_ok = false
			continue
		if not _validate_entry(
				output_name, entry, outputs, known_components):
			all_ok = false
	_validate_channels()
	return all_ok


func _get_outputs() -> Dictionary:
	if _output_config.has(&"outputs"):
		return _output_config[&"outputs"]
	if _output_config.has("outputs"):
		return _output_config["outputs"]
	return {}


func _get_channels() -> Dictionary:
	if _output_config.has(&"channels"):
		return _output_config[&"channels"]
	if _output_config.has("channels"):
		return _output_config["channels"]
	return {}


func _validate_entry(
		entry_name: Variant, entry: Dictionary, outputs: Dictionary,
		known_comps: Array[String]) -> bool:
	var ok: bool = true

	# Rule 9: output_name must exist in global outputs registry.
	if not _has_key_either(outputs, entry_name):
		push_error(
			"SensoryEmissions: unknown output_name '%s' (not in outputs config)"
			% entry_name
		)
		ok = false

	# Rule 4: modifiers must be present (may be empty).
	if not entry.has("modifiers"):
		push_error(
			"SensoryEmissions[%s]: missing required field 'modifiers'"
			% entry_name
		)
		ok = false
	elif not (entry["modifiers"] is Array):
		push_error(
			"SensoryEmissions[%s]: 'modifiers' must be an Array" % entry_name
		)
		ok = false

	# Rule 1: base_intensity required, int OR {component, field} dict.
	if not entry.has("base_intensity"):
		push_error(
			"SensoryEmissions[%s]: missing required field 'base_intensity'"
			% entry_name
		)
		ok = false
	elif not _is_valid_value_source(
			entry["base_intensity"], "%s.base_intensity" % entry_name):
		ok = false

	# Rule 2: base_radius_ru required, int OR {component, field} dict.
	if not entry.has("base_radius_ru"):
		push_error(
			"SensoryEmissions[%s]: missing required field 'base_radius_ru'"
			% entry_name
		)
		ok = false
	elif not _is_valid_value_source(
			entry["base_radius_ru"], "%s.base_radius_ru" % entry_name):
		ok = false

	# Rule 3: trigger (optional) shape check.
	if entry.has("trigger"):
		if not _is_valid_trigger(entry["trigger"], entry_name):
			ok = false

	# Rules 5-8: each modifier shape; rule 8: ids unique within emission.
	if entry.has("modifiers") and entry["modifiers"] is Array:
		var seen_ids: Dictionary = {}
		for mod: Variant in entry["modifiers"]:
			if not _is_valid_modifier(mod, entry_name, seen_ids):
				ok = false

	# Warning: unresolved component refs (typo guard, not a rejection).
	if not known_comps.is_empty():
		_warn_unresolved_components(entry, entry_name, known_comps)

	return ok


func _is_valid_value_source(source: Variant, ctx: String) -> bool:
	# Godot's JSON.parse() returns numbers as float; accept both so
	# JSONC-loaded recipes and code-built test recipes both validate.
	if source is int or source is float:
		return true
	if source is Dictionary:
		var d: Dictionary = source
		if not d.has("component") or not (d["component"] is String):
			push_error(
				"SensoryEmissions[%s]: ref-form 'component' must be string" % ctx
			)
			return false
		if not d.has("field") or not (d["field"] is String):
			push_error(
				"SensoryEmissions[%s]: ref-form 'field' must be string" % ctx
			)
			return false
		return true
	push_error(
		"SensoryEmissions[%s]: value source must be int or {component, field}"
		% ctx
	)
	return false


func _is_valid_trigger(trigger: Variant, ctx: Variant) -> bool:
	if not (trigger is Dictionary):
		push_error(
			"SensoryEmissions[%s]: trigger must be a Dictionary" % ctx
		)
		return false
	var t: Dictionary = trigger
	var ok: bool = true
	if not t.has("component") or not (t["component"] is String):
		push_error(
			"SensoryEmissions[%s]: trigger missing/non-string 'component'" % ctx
		)
		ok = false
	if not t.has("field") or not (t["field"] is String):
		push_error(
			"SensoryEmissions[%s]: trigger missing/non-string 'field'" % ctx
		)
		ok = false
	if not t.has("equals"):
		push_error(
			"SensoryEmissions[%s]: trigger missing 'equals'" % ctx
		)
		ok = false
	elif not (t["equals"] is int or t["equals"] is float):
		# JSON.parse() returns numbers as float; accept both.
		push_error(
			"SensoryEmissions[%s]: trigger 'equals' must be int" % ctx
		)
		ok = false
	return ok


func _is_valid_modifier(
		mod: Variant, emission_name: Variant,
		seen_ids: Dictionary) -> bool:
	if not (mod is Dictionary):
		push_error(
			"SensoryEmissions[%s]: modifier must be a Dictionary" % emission_name
		)
		return false
	var m: Dictionary = mod
	var ok: bool = true

	if not m.has("id") or not (m["id"] is String):
		push_error(
			"SensoryEmissions[%s]: modifier missing/non-string 'id'"
			% emission_name
		)
		ok = false
	else:
		var mid: String = m["id"]
		if seen_ids.has(mid):
			push_error(
				"SensoryEmissions[%s]: duplicate modifier id '%s'"
				% [emission_name, mid]
			)
			ok = false
		seen_ids[mid] = true

	for required: String in ["component", "field", "op"]:
		if not m.has(required) or not (m[required] is String):
			push_error(
				"SensoryEmissions[%s]: modifier missing/non-string '%s'"
				% [emission_name, required]
			)
			ok = false

	if m.has("op") and m["op"] is String:
		var op_sn: StringName = StringName(m["op"])
		if not _KNOWN_OPS.has(op_sn):
			push_error(
				"SensoryEmissions[%s]: unknown op '%s'; known ops: %s"
				% [emission_name, m["op"], _format_known_ops()]
			)
			ok = false

	if m.has("priority") and not (m["priority"] is int or m["priority"] is float):
		# JSON.parse() returns numbers as float; accept both.
		push_error(
			"SensoryEmissions[%s]: modifier 'priority' must be int"
			% emission_name
		)
		ok = false

	return ok


func _format_known_ops() -> String:
	var parts: Array[String] = []
	for op: StringName in _KNOWN_OPS:
		parts.append(String(op))
	return ", ".join(parts)


func _format_known_falloffs() -> String:
	var parts: Array[String] = []
	for f: StringName in _KNOWN_FALLOFFS:
		parts.append(String(f))
	return ", ".join(parts)


func _validate_channels() -> void:
	var channels: Dictionary = _get_channels()
	var outputs: Dictionary = _get_outputs()
	for output_name: Variant in outputs:
		var output: Dictionary = outputs[output_name]
		var ch: Variant = _get_either(output, "channel")
		if ch == null:
			continue
		if not _has_key_either(channels, ch):
			push_error(
				"SensoryEmissions: output '%s' references unknown channel '%s'"
				% [output_name, ch]
			)
	for ch_name: Variant in channels:
		var ch_def: Dictionary = channels[ch_name]
		var f: Variant = _get_either(ch_def, "falloff")
		if f == null:
			push_error(
				"SensoryEmissions: channel '%s' missing 'falloff'" % ch_name
			)
			continue
		var f_sn: StringName = StringName(f)
		if not _KNOWN_FALLOFFS.has(f_sn):
			push_error(
				"SensoryEmissions: channel '%s' unknown falloff '%s'; known: %s"
				% [ch_name, f, _format_known_falloffs()]
			)


func _has_key_either(d: Dictionary, key: Variant) -> bool:
	return d.has(String(key)) or d.has(StringName(key))


func _get_either(d: Dictionary, key: String) -> Variant:
	if d.has(key):
		return d[key]
	if d.has(StringName(key)):
		return d[StringName(key)]
	return null


func _warn_unresolved_components(
		entry: Dictionary, entry_name: Variant,
		known_comps: Array[String]) -> void:
	var refs: Array[String] = []
	if entry.has("trigger") and entry["trigger"] is Dictionary:
		var t: Dictionary = entry["trigger"]
		if t.has("component") and t["component"] is String:
			refs.append(t["component"])
	for vs: Variant in [entry.get("base_intensity"), entry.get("base_radius_ru")]:
		if vs is Dictionary and (vs as Dictionary).has("component"):
			var c: Variant = (vs as Dictionary)["component"]
			if c is String:
				refs.append(c)
	if entry.has("modifiers") and entry["modifiers"] is Array:
		for mod: Variant in entry["modifiers"]:
			if mod is Dictionary and (mod as Dictionary).has("component"):
				var c: Variant = (mod as Dictionary)["component"]
				if c is String:
					refs.append(c)
	for ref_name: String in refs:
		if not known_comps.has(ref_name):
			push_warning(
				(
					"SensoryEmissions[%s]: component '%s' not declared by this"
					+ " recipe or engine; may be a typo or a forward reference"
					+ " to another mod's component"
				) % [entry_name, ref_name]
			)
