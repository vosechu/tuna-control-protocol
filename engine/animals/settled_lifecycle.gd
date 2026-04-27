class_name SettledLifecycle extends RefCounted

# Minimum tracker for "this entity is intentionally resting at this host."
# Writes a one-field `&"settled_in"` component on the joiner. Used by the
# rendering layer (z-order tuck-in) and by the move-loop's stranded-animal
# safety net to distinguish "deep in a box on purpose" from "stranded high
# by a stale movement target."

var _db: GameStateDB


func _init(db: GameStateDB) -> void:
	_db = db


func enter(joiner_id: int, host_id: int) -> void:
	_db.set_component(joiner_id, &"settled_in", {&"host_id": host_id})


func exit(joiner_id: int) -> void:
	if _db.has_component(joiner_id, &"settled_in"):
		_db.remove_component(joiner_id, &"settled_in")


func is_settled(joiner_id: int) -> bool:
	return _db.has_component(joiner_id, &"settled_in")
