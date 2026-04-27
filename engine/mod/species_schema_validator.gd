class_name SpeciesSchemaValidator extends RefCounted

# Detects "is this recipe claiming to be a species?" by looking for any
# species-marker field. The legacy `traversal` marker is retained so
# old recipes are still detected and reported with a migration hint
# instead of silently passing as non-species.
const _SPECIES_MARKER_FIELDS: Array[String] = ["desires", "body_capabilities", "traversal"]

# Fields that must be present on any species recipe. body_capabilities and
# body_geometry replaced the legacy traversal + max_jump_height_ru pair as
# of the cat-jumps-into-box plan.
var _required_fields: Array[String] = ["desires", "body_capabilities", "body_geometry"]


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
	for field: String in _required_fields:
		if not def.has(field) or _is_empty(def[field]):
			push_error(
				"SpeciesSchemaValidator: species '%s' missing required field: %s"
				% [def_id, field]
			)
			return false
	return true


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
