class_name CableLayer extends Node2D

# Parent of every live CableView. Subscribes to cable_connected /
# cable_disconnected on the event bus and keeps its children in sync
# with the DB. Populates any cables that existed at scene entry so the
# starter scenario's pre-cabled TUNA/ARM render immediately.

var _db: GameStateDB
var _events: Object
var _cables: Dictionary = {}  # key: [hum_id, actuator_id] -> CableView


func initialize(db: GameStateDB, events: Object) -> void:
	_db = db
	_events = events
	if _events != null:
		_events.cable_connected.connect(_on_cable_connected)
		_events.cable_disconnected.connect(_on_cable_disconnected)
	for actuator_id: int in _db.get_entities_with(&"hum_cable"):
		var hum_id: int = _db.get_field(actuator_id, &"hum_cable", &"hum_id")
		_spawn(hum_id, actuator_id)


func set_wiring_mode(on: bool) -> void:
	for view: Node in _cables.values():
		if view is CableView:
			view.set_wiring_mode(on)


func _on_cable_connected(
		hum_id: int, device_id: int, _cable_type: StringName,
) -> void:
	var key: Array = [hum_id, device_id]
	if _cables.has(key):
		return
	_spawn(hum_id, device_id)


func _on_cable_disconnected(hum_id: int, device_id: int) -> void:
	var key: Array = [hum_id, device_id]
	if not _cables.has(key):
		return
	var view: Node = _cables[key]
	view.queue_free()
	_cables.erase(key)


func _spawn(hum_id: int, actuator_id: int) -> void:
	var view := CableView.new()
	add_child(view)
	view.initialize(_db, hum_id, actuator_id)
	_cables[[hum_id, actuator_id]] = view
