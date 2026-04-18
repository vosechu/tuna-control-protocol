class_name WiringLockRegistry extends RefCounted

# Tracks pickup-state locks for cable endpoints. Two sub-tables:
#   _actuator_locks — the actuator side of a cable is held by a peer
#   _hum_locks      — the HUM side of a specific cable is held by a peer
# An entry records who holds it, when they acquired, and which (hum, actuator)
# pair the cable originally connected. The originals let the save system
# reconstruct in-flight cables as if the drag never happened.

var _actuator_locks: Dictionary = {}
var _hum_locks: Dictionary = {}


func acquire_actuator(
		actuator_id: int,
		peer_id: int,
		tick: int,
		original_hum_id: int,
		original_actuator_id: int,
) -> bool:
	if _actuator_locks.has(actuator_id):
		return false
	_actuator_locks[actuator_id] = {
		&"owner_peer_id": peer_id,
		&"tick": tick,
		&"original_hum_id": original_hum_id,
		&"original_actuator_id": original_actuator_id,
	}
	return true


func acquire_hum_end(
		hum_id: int,
		cable_actuator_id: int,
		peer_id: int,
		tick: int,
		original_hum_id: int,
		original_actuator_id: int,
) -> bool:
	var key: int = _hum_end_key(hum_id, cable_actuator_id)
	if _hum_locks.has(key):
		return false
	_hum_locks[key] = {
		&"owner_peer_id": peer_id,
		&"tick": tick,
		&"original_hum_id": original_hum_id,
		&"original_actuator_id": original_actuator_id,
	}
	return true


func release_actuator(actuator_id: int) -> void:
	_actuator_locks.erase(actuator_id)


func release_hum_end(hum_id: int, cable_actuator_id: int) -> void:
	_hum_locks.erase(_hum_end_key(hum_id, cable_actuator_id))


func is_locked_actuator(actuator_id: int) -> bool:
	return _actuator_locks.has(actuator_id)


func is_locked_hum_end(hum_id: int, cable_actuator_id: int) -> bool:
	return _hum_locks.has(_hum_end_key(hum_id, cable_actuator_id))


func get_actuator_entry(actuator_id: int) -> Dictionary:
	return _actuator_locks.get(actuator_id, {})


func tick_expire(current_tick: int, ttl_ticks: int) -> void:
	var expired: Array = []
	for key: int in _actuator_locks.keys():
		var lock: Dictionary = _actuator_locks[key]
		if current_tick - int(lock[&"tick"]) > ttl_ticks:
			expired.append(key)
	for key: int in expired:
		_actuator_locks.erase(key)
	expired.clear()
	for key: int in _hum_locks.keys():
		var lock: Dictionary = _hum_locks[key]
		if current_tick - int(lock[&"tick"]) > ttl_ticks:
			expired.append(key)
	for key: int in expired:
		_hum_locks.erase(key)


func entries_for_peer(peer_id: int) -> Array:
	var out: Array = []
	for entry: Dictionary in _actuator_locks.values():
		if int(entry[&"owner_peer_id"]) == peer_id:
			out.append(entry)
	for entry: Dictionary in _hum_locks.values():
		if int(entry[&"owner_peer_id"]) == peer_id:
			out.append(entry)
	return out


func synthetic_hum_cable_rows() -> Array:
	# Save adapter: each active lock implies a cable that was live before the
	# drag started. Synthesize rows so the save captures the pre-pickup state.
	var rows: Array = []
	for entry: Dictionary in _actuator_locks.values():
		_append_row(rows, entry)
	for entry: Dictionary in _hum_locks.values():
		_append_row(rows, entry)
	return rows


func _append_row(rows: Array, entry: Dictionary) -> void:
	var hum_id: int = int(entry[&"original_hum_id"])
	if hum_id == Constants.INVALID_ID:
		return
	rows.append({
		&"actuator_id": int(entry[&"original_actuator_id"]),
		&"hum_id": hum_id,
	})


func _hum_end_key(hum_id: int, actuator_id: int) -> int:
	return (hum_id << 32) | (actuator_id & 0xFFFFFFFF)
