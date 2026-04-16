class_name SpeciesSchemaValidator extends RefCounted

# Detects "is this recipe claiming to be a species?" by looking for
# the `desires` + `traversal` fields. Objects have `object_type_id`
# or `placement` and are skipped.
const _SPECIES_MARKER_FIELDS: Array[String] = ["desires", "traversal"]

# Fields that must be present on any species recipe. Extended by
# subsequent Stage 1 tasks as they add recipe-driven configuration.
var _required_fields: Array[String] = ["desires", "traversal"]


func add_required_field(field_name: String) -> void:
	if field_name in _required_fields:
		return
	_required_fields.append(field_name)


func is_valid_species(def: Dictionary) -> bool:
	if not _looks_like_species(def):
		return true
	for field: String in _required_fields:
		if not def.has(field) or _is_empty(def[field]):
			push_error(
				"SpeciesSchemaValidator: species '%s' missing required field: %s"
				% [def.get("id", "<unknown>"), field]
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
