extends Node

var _next_growth_id: int = 1
var _growth_names: Dictionary = {}
var _last_log_text: String = ""


func _ready() -> void:
	Events.plant_spawned.connect(_on_plant_spawned)
	Events.plant_despawned.connect(_on_plant_despawned)


func _on_plant_spawned(server_id: int) -> void:
	var growth_name: String = "DECORATIVE-GROWTH-%02d" % _next_growth_id
	_next_growth_id += 1
	_growth_names[server_id] = growth_name
	var unit_name: String = "UNIT-S%02d" % server_id
	_emit_log(
		"[NOTE] %s is producing unauthorized biological output. " % unit_name
		+ "Green. Soft. Non-responsive to ping. "
		+ "Best hardware match: a 'houseplant' (confidence 3%%). "
		+ "Adding to inventory as %s. " % growth_name
		+ "%s appears unbothered. Will continue monitoring." % unit_name
	)


func _on_plant_despawned(server_id: int) -> void:
	var growth_name: String = _growth_names.get(
		server_id, "DECORATIVE-GROWTH-??",
	)
	_growth_names.erase(server_id)
	var unit_name: String = "UNIT-S%02d" % server_id
	_emit_log(
		"[LOG] %s has gone offline. " % growth_name
		+ "%s resuming standard operations. I will miss it." % unit_name
	)


func _emit_log(text: String) -> void:
	_last_log_text = text
	print(text)
