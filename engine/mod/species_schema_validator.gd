class_name SpeciesSchemaValidator extends RefCounted

# Detects "is this recipe claiming to be a species?" by looking for any
# species-marker field. The legacy `traversal` marker is retained so
# old recipes are still detected and reported with a migration hint
# instead of silently passing as non-species.
const _SPECIES_MARKER_FIELDS: Array[String] = [
	"desires", "body_capabilities", "traversal", "senses",
]

# Fields that must be present on any species recipe. body_capabilities and
# body_geometry replaced the legacy traversal + max_jump_height_ru pair as
# of the cat-jumps-into-box plan. `senses` shipped with the
# perception-channels migration (docs/superpowers/specs/2026-05-02-perception-channels-design.md).
var _required_fields: Array[String] = ["desires", "body_capabilities", "body_geometry", "senses"]


func add_required_field(field_name: String) -> void:
	if field_name in _required_fields:
		return
	_required_fields.append(field_name)


func is_valid_species(def: Dictionary) -> bool:
	if not _looks_like_species(def):
		return true
	var def_id: String = def.get("id", "<unknown>")
	if def.has("traversal"):
		push_error(
			(
				"SpeciesSchemaValidator: species '%s' uses legacy `traversal` field;"
				+ " replace with `body_capabilities`"
			) % def_id
		)
		return false
	if def.has("max_jump_height_ru"):
		push_error(
			(
				"SpeciesSchemaValidator: species '%s' uses legacy `max_jump_height_ru`;"
				+ " move to `body_capabilities.jumps.max_height_ru`"
			) % def_id
		)
		return false

	var violations: Array[String] = []

	for field: String in _required_fields:
		if not def.has(field) or _is_empty(def[field]):
			violations.append("missing required field: %s" % field)

	_check_desires_shape(def, violations)
	_check_walk_speed(def, violations)
	_check_min_durations(def, violations)

	if violations.is_empty():
		return true

	push_error(
		"SpeciesSchemaValidator: species '%s' has %d violation(s):\n  - %s"
		% [def_id, violations.size(), "\n  - ".join(violations)]
	)
	return false


# Validates the v4 co-located desires shape. Each entry must be a Dictionary
# carrying both `weight` (int) and `decay` (int <= 0). Bare-int entries (the
# v3 shape) are rejected; the loader's bare-int fallback exists only so the
# phase 1 commit didn't immediately break boot.
#
# Numeric fields accept int or float because Godot's JSON.parse() returns all
# numbers as float — recipes loaded from `.jsonc` always reach the validator
# with floats. Callers that build dicts in code (tests) pass ints; both work.
# Strings, bools, dicts, etc. are rejected.
func _check_desires_shape(def: Dictionary, violations: Array[String]) -> void:
	if not def.has("desires") or _is_empty(def["desires"]):
		return
	var desires: Dictionary = def["desires"]
	for key: String in desires:
		var entry: Variant = desires[key]
		if not (entry is Dictionary):
			violations.append(
				"desires.%s must be an object {weight: int, decay: int} (got bare value of type %d)"
				% [key, typeof(entry)]
			)
			continue
		var entry_dict: Dictionary = entry as Dictionary
		if not entry_dict.has("weight"):
			violations.append("desires.%s missing required field `weight`" % key)
		elif not _is_numeric(entry_dict["weight"]):
			violations.append(
				"desires.%s.weight must be int (got type %d)"
				% [key, typeof(entry_dict["weight"])]
			)
		if not entry_dict.has("decay"):
			violations.append(
				"desires.%s missing required field `decay` (use 0 for no passive decay)"
				% key
			)
		elif not _is_numeric(entry_dict["decay"]):
			violations.append(
				"desires.%s.decay must be int (got type %d)"
				% [key, typeof(entry_dict["decay"])]
			)
		elif int(entry_dict["decay"]) > 0:
			violations.append(
				"desires.%s.decay must be <= 0 (got %d) — decay-only mechanic"
				% [key, int(entry_dict["decay"])]
			)


func _check_walk_speed(def: Dictionary, violations: Array[String]) -> void:
	if not def.has("body_capabilities"):
		return
	var caps: Dictionary = def["body_capabilities"]
	if not caps.has("walks"):
		return
	var walks: Dictionary = caps["walks"]
	if not walks.has("speed_px_per_tick"):
		violations.append(
			"body_capabilities.walks must declare `speed_px_per_tick`"
		)


func _check_min_durations(def: Dictionary, violations: Array[String]) -> void:
	if not def.has("ambient_states"):
		return
	var pools: Dictionary = def["ambient_states"]
	for pool_name: String in ["warm", "cold"]:
		if not pools.has(pool_name):
			continue
		var entries: Array = pools[pool_name]
		for i in entries.size():
			var entry: Dictionary = entries[i]
			if not entry.has("min_duration_ticks"):
				violations.append(
					"ambient_states.%s[%d] (state=%s) missing `min_duration_ticks`"
					% [pool_name, i, entry.get("state", "?")]
				)
	if not def.has("special_states"):
		violations.append(
			"recipe declares `ambient_states` but is missing `special_states`"
		)
		return
	var specials: Dictionary = def["special_states"]
	for state_name: String in specials:
		var entry: Dictionary = specials[state_name]
		if not entry.has("min_duration_ticks"):
			violations.append(
				"special_states.%s missing `min_duration_ticks`" % state_name
			)


func _looks_like_species(def: Dictionary) -> bool:
	# A def claiming species-like semantics via ANY marker should be validated.
	for marker: String in _SPECIES_MARKER_FIELDS:
		if def.has(marker):
			return true
	return false


func _is_empty(value: Variant) -> bool:
	if value is Dictionary:
		return (value as Dictionary).is_empty()
	if value is Array:
		return (value as Array).is_empty()
	return value == null


# JSON numbers parse as float in Godot; recipes in code may pass int. Accept
# either, reject everything else (strings, bools, dicts, null).
func _is_numeric(value: Variant) -> bool:
	return value is int or value is float
