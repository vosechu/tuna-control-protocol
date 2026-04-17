class_name ModLoader extends RefCounted

var validator: SpeciesSchemaValidator = SpeciesSchemaValidator.new()
var scenario_validator: ScenarioSchemaValidator = ScenarioSchemaValidator.new()


func load_all(mods_path: String) -> Dictionary:
	var entity_defs := EntityDefRegistry.new()
	var manifests: Array[ModManifest] = []
	var sprite_resolver := SpriteResolver.new()
	var scenarios := ScenarioRegistry.new()
	validator.add_required_field("sprite_config")
	validator.add_required_field("ambient_states")
	validator.add_required_field("hud_color")

	var mod_dirs: Array[String] = _discover_mods(mods_path)

	var parsed: Array[ModManifest] = []
	for dir_path: String in mod_dirs:
		var manifest := ModManifest.parse_file(
			dir_path + "/mod.json",
		)
		if manifest == null:
			push_error(
				"ModLoader: failed to parse %s/mod.json"
				% dir_path,
			)
			continue
		parsed.append(manifest)

	parsed.sort_custom(
		func(a: ModManifest, b: ModManifest) -> bool:
			return String(a.id) < String(b.id)
	)

	var seen_ids: Dictionary = {}
	for manifest: ModManifest in parsed:
		assert(
			not seen_ids.has(manifest.id),
			"ModLoader: duplicate mod ID '%s'" % manifest.id,
		)
		seen_ids[manifest.id] = manifest.title

	for manifest: ModManifest in parsed:
		_load_mod_content(manifest, entity_defs, scenarios)
		manifests.append(manifest)

	return {
		"entity_defs": entity_defs,
		"manifests": manifests,
		"sprite_resolver": sprite_resolver,
		"scenarios": scenarios,
	}


func _discover_mods(mods_path: String) -> Array[String]:
	var dirs: Array[String] = []
	var dir := DirAccess.open(mods_path)
	if dir == null:
		push_error(
			"ModLoader: cannot open mods directory: %s"
			% mods_path,
		)
		return dirs
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() \
				and not entry.begins_with("."):
			var mod_json: String = \
				mods_path + entry + "/mod.json"
			if FileAccess.file_exists(mod_json):
				dirs.append(mods_path + entry)
		entry = dir.get_next()
	return dirs


func _load_mod_content(
		manifest: ModManifest,
		entity_defs: EntityDefRegistry,
		scenarios: ScenarioRegistry,
) -> void:
	var mod_path: String = manifest.mod_path
	_load_jsonc_dir(mod_path + "/species", entity_defs)
	_load_jsonc_dir(mod_path + "/objects", entity_defs)
	_load_scenarios_dir(mod_path + "/scenarios", scenarios)


func _load_scenarios_dir(
		dir_path: String,
		registry: ScenarioRegistry,
) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and (
				entry.ends_with(".jsonc")
				or entry.ends_with(".json")):
			var file_path: String = dir_path + "/" + entry
			var data: Dictionary = _parse_jsonc(file_path)
			if data.is_empty():
				entry = dir.get_next()
				continue
			if not data.has("id"):
				push_error(
					"ModLoader: missing 'id' in %s"
					% file_path,
				)
				entry = dir.get_next()
				continue
			if not scenario_validator.is_valid(data):
				push_error(
					"ModLoader: rejecting invalid scenario from %s"
					% file_path,
				)
				entry = dir.get_next()
				continue
			var scenario_id := StringName(str(data["id"]))
			registry.register(scenario_id, data)
		entry = dir.get_next()


func _load_jsonc_dir(
		dir_path: String,
		entity_defs: EntityDefRegistry,
) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and (
				entry.ends_with(".jsonc")
				or entry.ends_with(".json")):
			var file_path: String = dir_path + "/" + entry
			var data: Dictionary = _parse_jsonc(file_path)
			if data.is_empty():
				entry = dir.get_next()
				continue
			if not data.has("id"):
				push_error(
					"ModLoader: missing 'id' in %s"
					% file_path,
				)
				entry = dir.get_next()
				continue
			var entity_id := StringName(str(data["id"]))
			if not validator.is_valid_species(data):
				push_error(
					"ModLoader: rejecting invalid species '%s' from %s"
					% [entity_id, file_path]
				)
				entry = dir.get_next()
				continue
			entity_defs.register(entity_id, data)
		entry = dir.get_next()


func _parse_jsonc(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ModLoader: file not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	var lines: PackedStringArray = text.split("\n")
	var cleaned: String = ""
	for line: String in lines:
		var comment_idx: int = line.find("//")
		if comment_idx >= 0:
			var before: String = line.left(comment_idx)
			if before.count('"') % 2 == 0:
				line = before
		cleaned += line + "\n"
	var json := JSON.new()
	var err := json.parse(cleaned)
	if err != OK:
		push_error(
			"ModLoader: JSON parse error in %s: %s"
			% [path, json.get_error_message()],
		)
		return {}
	if json.data is Dictionary:
		return json.data
	push_error(
		"ModLoader: expected Dictionary in %s, got %s"
		% [path, typeof(json.data)],
	)
	return {}
