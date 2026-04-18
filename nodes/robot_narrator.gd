extends Node

const BULK_CABLE_THRESHOLD: int = 3

var _next_growth_id: int = 1
var _growth_names: Dictionary = {}
var _last_log_text: String = ""
var _any_cable_logged: bool = false
var _pending_connect_count: int = 0
var _recent_disconnect_ticks: Dictionary = {}  # device_id -> last disconnect tick
var _current_tick: int = 0


func _ready() -> void:
	Events.plant_spawned.connect(_on_plant_spawned)
	Events.plant_despawned.connect(_on_plant_despawned)
	Events.cable_connected.connect(_on_cable_connected)
	Events.cable_disconnected.connect(_on_cable_disconnected)


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


func _on_cable_connected(
		hum_id: int, device_id: int, _cable_type: StringName,
) -> void:
	_pending_connect_count += 1
	if _pending_connect_count > BULK_CABLE_THRESHOLD:
		# Starter scenario or a rapid topology change — coalesce.
		if _pending_connect_count == BULK_CABLE_THRESHOLD + 1:
			_emit_log(
				"[NOTE] Multiple harmonic bridges established simultaneously. "
				+ "Topology unexpectedly rich. Recording for review."
			)
		return
	if not _any_cable_logged:
		_any_cable_logged = true
		_emit_log(
			"[NOTE] New harmonic bridge detected in sector. I did not "
			+ "initiate this. The devices are coordinating. Excellent."
		)
		return
	if _recent_disconnect_ticks.has(device_id):
		_emit_log(
			("[STATUS] UNIT-T%02d re-coupled through alternate bridge. " % device_id)
			+ "Previous carrier retired."
		)
		_recent_disconnect_ticks.erase(device_id)
		return
	_emit_log(
		("[STATUS] UNIT-T%02d harmonic coupled to acoustic source UNIT-H%02d. " % [device_id, hum_id])
		+ "Spindle resonance routing nominal."
	)


func _on_cable_disconnected(hum_id: int, device_id: int) -> void:
	_recent_disconnect_ticks[device_id] = _current_tick
	_emit_log(
		("[ADVISORY] UNIT-T%02d lost harmonic link to UNIT-H%02d. " % [device_id, hum_id])
		+ "Servo torque reduced. Apologizing to nearby devices."
	)


func _emit_log(text: String) -> void:
	_last_log_text = text
	print(text)
