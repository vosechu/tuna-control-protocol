class_name ModManifest extends RefCounted

var id: StringName = &""
var title: String = ""
var version: String = ""
var author: String = ""
var description: String = ""
var mod_path: String = ""


static func parse_dict(data: Dictionary) -> ModManifest:
	if not data.has("title") or not data.has("version") \
			or not data.has("author"):
		push_error(
			"ModManifest: missing required field "
			+ "(title, version, or author)"
		)
		return null
	var manifest := ModManifest.new()
	manifest.title = str(data["title"])
	manifest.version = str(data["version"])
	manifest.author = str(data["author"])
	manifest.description = str(data.get("description", ""))
	manifest.id = _derive_id(manifest.title)
	return manifest


static func parse_file(path: String) -> ModManifest:
	if not FileAccess.file_exists(path):
		push_error("ModManifest: file not found: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error(
			"ModManifest: JSON parse error in %s: %s"
			% [path, json.get_error_message()]
		)
		return null
	var manifest := parse_dict(json.data)
	if manifest != null:
		manifest.mod_path = path.get_base_dir()
	return manifest


static func _derive_id(title: String) -> StringName:
	var result: String = title.to_lower()
	var cleaned: String = ""
	for i in result.length():
		var c: String = result[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			cleaned += c
		else:
			cleaned += "_"
	while cleaned.contains("__"):
		cleaned = cleaned.replace("__", "_")
	cleaned = cleaned.strip_edges()
	cleaned = cleaned.trim_prefix("_").trim_suffix("_")
	if cleaned.length() > 48:
		cleaned = cleaned.left(48).trim_suffix("_")
	return StringName(cleaned)
