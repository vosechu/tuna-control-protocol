class_name WiringSystem extends RefCounted

# Server-authoritative cable intents. Every mutation to the hum_cable
# component on an actuator flows through one of the handle_* methods so
# the WiringLockRegistry, event bus, and DB stay in lockstep.
#
# Events: the adapter passed as `events` may either be a plain Object
# exposing emit_cable_connected / emit_cable_disconnected / emit_cable_deny
# helpers (the shape used by tests and the fake harness), or the real
# Events autoload which carries raw signals. `_emit_*` below normalizes both.

const CABLE_TYPE_HUM: StringName = &"hum_power"

var _db: GameStateDB
var _locks: WiringLockRegistry
var _events: Object
var _config: Dictionary


func _init(
		db: GameStateDB,
		locks: WiringLockRegistry,
		events: Object,
		config: Dictionary,
) -> void:
	_db = db
	_locks = locks
	_events = events
	_config = config


func handle_connect(peer_id: int, hum_id: int, device_id: int) -> bool:
	if not _db.has_entity(hum_id) or not _db.has_entity(device_id):
		return false
	if not _db.has_component(hum_id, &"hum"):
		return false
	if not _db.has_component(device_id, &"hum_powered"):
		return false
	if not _within_range(hum_id, device_id):
		_emit_deny(&"out_of_reach")
		return false
	if not _same_stripe(peer_id, hum_id, device_id):
		_emit_deny(&"cross_stripe")
		return false
	var old_hum: int = Constants.INVALID_ID
	if _db.has_component(device_id, &"hum_cable"):
		old_hum = _db.get_field(device_id, &"hum_cable", &"hum_id")
	_db.set_component(device_id, &"hum_cable", {&"hum_id": hum_id})
	if old_hum != Constants.INVALID_ID and old_hum != hum_id:
		_emit_disconnect(old_hum, device_id)
	_emit_connect(hum_id, device_id)
	return true


func handle_pickup_actuator_end(
		peer_id: int, current_tick: int, actuator_id: int,
) -> bool:
	if _locks.is_locked_actuator(actuator_id):
		return false
	if not _db.has_component(actuator_id, &"hum_cable"):
		return false
	var hum_id: int = _db.get_field(actuator_id, &"hum_cable", &"hum_id")
	var ok: bool = _locks.acquire_actuator(
		actuator_id, peer_id, current_tick, hum_id, actuator_id,
	)
	if not ok:
		return false
	_db.remove_component(actuator_id, &"hum_cable")
	_emit_disconnect(hum_id, actuator_id)
	return true


func handle_pickup_hum_end(
		peer_id: int,
		current_tick: int,
		hum_id: int,
		cable_actuator_id: int,
) -> bool:
	if _locks.is_locked_hum_end(hum_id, cable_actuator_id):
		return false
	if not _db.has_component(cable_actuator_id, &"hum_cable"):
		return false
	var orig_hum: int = _db.get_field(
		cable_actuator_id, &"hum_cable", &"hum_id",
	)
	if orig_hum != hum_id:
		return false
	var ok: bool = _locks.acquire_hum_end(
		hum_id, cable_actuator_id, peer_id, current_tick,
		hum_id, cable_actuator_id,
	)
	if not ok:
		return false
	_db.remove_component(cable_actuator_id, &"hum_cable")
	_emit_disconnect(hum_id, cable_actuator_id)
	return true


func handle_cancel(_peer_id: int, actuator_id: int) -> bool:
	# Retract: re-attach the original cable if both endpoints still live.
	# If the source HUM is gone we silently drop the pickup (ergonomic for
	# the player — the alternative is leaving a stuck cursor).
	if not _locks.is_locked_actuator(actuator_id):
		return false
	var entry: Dictionary = _locks.get_actuator_entry(actuator_id)
	var orig_hum: int = int(entry.get(&"original_hum_id", Constants.INVALID_ID))
	_locks.release_actuator(actuator_id)
	var can_retract: bool = (
		orig_hum != Constants.INVALID_ID
		and _db.has_entity(orig_hum)
		and _db.has_component(orig_hum, &"hum")
		and _db.has_entity(actuator_id)
	)
	if not can_retract:
		return false
	_db.set_component(actuator_id, &"hum_cable", {&"hum_id": orig_hum})
	_emit_connect(orig_hum, actuator_id)
	return true


func handle_delete(_peer_id: int, actuator_id: int) -> bool:
	if not _locks.is_locked_actuator(actuator_id):
		return false
	_locks.release_actuator(actuator_id)
	return true


func handle_start(_peer_id: int, hum_id: int) -> bool:
	# Validation-only; no mutation. UX uses this to confirm the click
	# landed on a valid HUM before animating the drag state.
	return _db.has_entity(hum_id) and _db.has_component(hum_id, &"hum")


func entries_for_peer(peer_id: int) -> Array:
	return _locks.entries_for_peer(peer_id)


func _within_range(hum_id: int, device_id: int) -> bool:
	var hx: int = _db.get_field(hum_id, &"position", &"x")
	var hy: int = _db.get_field(hum_id, &"position", &"y")
	var dx: int = _db.get_field(device_id, &"position", &"x")
	var dy: int = _db.get_field(device_id, &"position", &"y")
	var max_ru: int = int(_config.get(&"cable_max_length_ru", 20))
	var max_pu: int = Constants.ru_to_pu(max_ru)
	var delta_x: int = hx - dx
	var delta_y: int = hy - dy
	return (delta_x * delta_x + delta_y * delta_y) <= (max_pu * max_pu)


func _same_stripe(
		_peer_id: int, _hum_id: int, _device_id: int,
) -> bool:
	# Solo baseline: single peer owns every stripe. MP wires a real check
	# into this slot (see Task 17).
	return true


func _emit_connect(hum_id: int, device_id: int) -> void:
	if _events == null:
		return
	if _events.has_method(&"emit_cable_connected"):
		_events.emit_cable_connected(hum_id, device_id, CABLE_TYPE_HUM)
	elif _events.has_signal(&"cable_connected"):
		_events.cable_connected.emit(hum_id, device_id, CABLE_TYPE_HUM)


func _emit_disconnect(hum_id: int, device_id: int) -> void:
	if _events == null:
		return
	if _events.has_method(&"emit_cable_disconnected"):
		_events.emit_cable_disconnected(hum_id, device_id)
	elif _events.has_signal(&"cable_disconnected"):
		_events.cable_disconnected.emit(hum_id, device_id)


func _emit_deny(reason: StringName) -> void:
	if _events == null:
		return
	if _events.has_method(&"emit_cable_deny"):
		_events.emit_cable_deny(reason)
