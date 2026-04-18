class_name WiringSaveAdapter extends RefCounted

# Serializes/deserializes the hum_cable portion of a save payload.
# Builds rows from (a) live hum_cable components in the DB and (b) the
# synthetic rows the WiringLockRegistry exposes for pickups that were in
# flight when the save was taken. On reload a tombstone guard drops any
# cable whose HUM endpoint no longer resolves.
#
# Integration point: engine/save/save_writer.gd (not yet implemented)
# should splice write_snapshot()'s dict into the top-level payload; the
# reader calls read_snapshot after every entity is loaded so both ends of
# each cable resolve.

var _db: GameStateDB
var _locks: WiringLockRegistry


func _init(db: GameStateDB, locks: WiringLockRegistry) -> void:
	_db = db
	_locks = locks


func write_snapshot() -> Dictionary:
	var rows: Array = []
	for actuator_id: int in _db.get_entities_with(&"hum_cable"):
		var hum_id: int = _db.get_field(
			actuator_id, &"hum_cable", &"hum_id",
		)
		rows.append({
			&"actuator_id": actuator_id,
			&"hum_id": hum_id,
		})
	for row: Dictionary in _locks.synthetic_hum_cable_rows():
		rows.append(row)
	return {&"hum_cables": rows}


func read_snapshot(payload: Dictionary) -> void:
	var rows: Array = payload.get(&"hum_cables", [])
	for row: Dictionary in rows:
		var actuator_id: int = int(row[&"actuator_id"])
		var hum_id: int = int(row[&"hum_id"])
		if not _db.has_entity(hum_id) or not _db.has_component(hum_id, &"hum"):
			push_warning(
				"wiring_save_adapter: dropping stale cable; hum %d missing" % hum_id
			)
			continue
		if not _db.has_entity(actuator_id):
			push_warning(
				"wiring_save_adapter: dropping cable; actuator %d missing" % actuator_id
			)
			continue
		_db.set_component(
			actuator_id, &"hum_cable", {&"hum_id": hum_id},
		)
