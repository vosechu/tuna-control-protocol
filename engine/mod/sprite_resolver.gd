class_name SpriteResolver extends RefCounted


static func parse_sprite_filename(
		filename: String,
) -> Dictionary:
	var base: String = filename.get_basename()
	var strip_idx: int = base.rfind("_strip")
	if strip_idx < 0:
		return {}
	var frame_str: String = base.substr(strip_idx + 6)
	if not frame_str.is_valid_int():
		return {}
	var prefix: String = base.left(strip_idx)
	var last_us: int = prefix.rfind("_")
	if last_us < 1:
		return {}
	return {
		"variant": prefix.left(last_us),
		"state": prefix.substr(last_us + 1),
		"frame_count": int(frame_str),
	}


func resolve_from_list(
		filenames: Array, known_variants: Array,
) -> Dictionary:
	var result: Dictionary = {}
	for variant: String in known_variants:
		result[variant] = {}
	for filename in filenames:
		var base: String = String(filename).get_basename()
		var strip_idx: int = base.rfind("_strip")
		if strip_idx < 0:
			continue
		var frame_str: String = base.substr(strip_idx + 6)
		if not frame_str.is_valid_int():
			continue
		var prefix: String = base.left(strip_idx)
		for variant: String in known_variants:
			if prefix.begins_with(variant + "_"):
				var state: String = prefix.substr(
					variant.length() + 1,
				)
				result[variant][state] = {
					"frame_count": int(frame_str),
					"filename": String(filename),
				}
				break
	return result


func validate_required(
		sprites: Dictionary, animations: Dictionary,
		variants: Array,
) -> Array[String]:
	var errors: Array[String] = []
	var required: Array = animations.get("required", [])
	for variant: String in variants:
		if not sprites.has(variant):
			for state: String in required:
				errors.append(
					"Missing sprite: %s_%s_strip*.png"
					% [variant, state],
				)
			continue
		for state: String in required:
			if not sprites[variant].has(state):
				errors.append(
					"Missing required sprite: "
					+ "%s_%s_strip*.png" % [variant, state],
				)
	return errors
