class_name CuriosityTracker extends RefCounted

# entity_id -> tick of last visit
var _visit_times: Dictionary = {}


# Record that this entity was visited at the given tick.
func visit(entity_id: int, current_tick: int) -> void:
	_visit_times[entity_id] = current_tick


# Check whether an entity is novel (never visited, or cooldown has expired).
func is_novel(entity_id: int, current_tick: int, cooldown_ticks: int) -> bool:
	if not _visit_times.has(entity_id):
		return true
	return current_tick - _visit_times[entity_id] >= cooldown_ticks
