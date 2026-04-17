class_name GameStateDB extends RefCounted

const INVALID_ID: int = -1

# _entities: entity_id -> { component_name -> { field -> value } }
var _entities: Dictionary = {}
var _next_id: int = 1
var _tick: int = 0

# _watchers: component_name -> Array[Callable]
var _watchers: Dictionary = {}

# _dirty_components: component_name -> { entity_id -> true } (set semantics)
var _dirty_components: Dictionary = {}

# _spatial: entity_id -> { &"x": int, &"y": int }
var _spatial: Dictionary = {}


# ── Entity lifecycle ──────────────────────────────────────────────────────────

func create_entity() -> int:
	var id: int = _next_id
	_next_id += 1
	_entities[id] = {}
	return id


func create_entity_with_id(entity_id: int) -> void:
	assert(not _entities.has(entity_id),
			"create_entity_with_id: entity %d already exists" % entity_id)
	_entities[entity_id] = {}
	if entity_id >= _next_id:
		_next_id = entity_id + 1


func destroy_entity(entity_id: int) -> void:
	assert(_entities.has(entity_id), "destroy_entity: unknown entity %d" % entity_id)
	_entities.erase(entity_id)
	_spatial.erase(entity_id)
	# Remove from any dirty sets
	for component: StringName in _dirty_components:
		_dirty_components[component].erase(entity_id)


func has_entity(entity_id: int) -> bool:
	return _entities.has(entity_id)


func entity_count() -> int:
	return _entities.size()


# ── Single-entity component access ───────────────────────────────────────────

func set_component(entity_id: int, component: StringName, data: Dictionary) -> void:
	assert(_entities.has(entity_id), "set_component: unknown entity %d" % entity_id)
	# Duplicate to prevent aliasing; caller's dict changes must not affect stored data.
	_entities[entity_id][component] = data.duplicate()
	_mark_dirty(entity_id, component)


func get_component(entity_id: int, component: StringName) -> Dictionary:
	assert(_entities.has(entity_id), "get_component: unknown entity %d" % entity_id)
	assert(_entities[entity_id].has(component),
			"get_component: entity %d has no component '%s'" % [entity_id, component])
	return _entities[entity_id][component]


func has_component(entity_id: int, component: StringName) -> bool:
	if not _entities.has(entity_id):
		return false
	return _entities[entity_id].has(component)


func remove_component(entity_id: int, component: StringName) -> void:
	assert(_entities.has(entity_id),
			"remove_component: unknown entity %d" % entity_id)
	_entities[entity_id].erase(component)


func get_field(entity_id: int, component: StringName, field: StringName) -> int:
	assert(_entities.has(entity_id), "get_field: unknown entity %d" % entity_id)
	assert(_entities[entity_id].has(component),
			"get_field: entity %d has no component '%s'" % [entity_id, component])
	return _entities[entity_id][component][field]


func set_field(entity_id: int, component: StringName, field: StringName, value: int) -> void:
	assert(_entities.has(entity_id), "set_field: unknown entity %d" % entity_id)
	assert(_entities[entity_id].has(component),
			"set_field: entity %d has no component '%s'" % [entity_id, component])
	_entities[entity_id][component][field] = value
	_mark_dirty(entity_id, component)


func add_field(entity_id: int, component: StringName, field: StringName, delta: int) -> void:
	var value: int = get_field(entity_id, component, field)
	set_field(entity_id, component, field, value + delta)


func clamp_field(
		entity_id: int, component: StringName,
		field: StringName, min_val: int, max_val: int,
) -> void:
	var value: int = get_field(entity_id, component, field)
	set_field(entity_id, component, field, clampi(value, min_val, max_val))


# ── Batch operations (hot path) ───────────────────────────────────────────────

func add_all(component: StringName, field: StringName, delta: int) -> void:
	for entity_id: int in _entities:
		var comps: Dictionary = _entities[entity_id]
		if comps.has(component) and comps[component].has(field):
			comps[component][field] += delta


func clamp_all(component: StringName, field: StringName, min_val: int, max_val: int) -> void:
	for entity_id: int in _entities:
		var comps: Dictionary = _entities[entity_id]
		if comps.has(component) and comps[component].has(field):
			comps[component][field] = clampi(comps[component][field], min_val, max_val)


# ── Working set queries ───────────────────────────────────────────────────────

func get_entities_with(component: StringName) -> Array[int]:
	var result: Array[int] = []
	for entity_id: int in _entities:
		if _entities[entity_id].has(component):
			result.append(entity_id)
	return result


# ── Spatial queries ───────────────────────────────────────────────────────────

func update_spatial(entity_id: int, x: int, y: int) -> void:
	_spatial[entity_id] = {&"x": x, &"y": y}


func remove_spatial(entity_id: int) -> void:
	_spatial.erase(entity_id)


func query_radius(x: int, y: int, radius: int) -> Array[int]:
	# Uses Manhattan distance: absi(dx) + absi(dy) <= radius
	var result: Array[int] = []
	for entity_id: int in _spatial:
		var pos: Dictionary = _spatial[entity_id]
		var dist: int = absi(pos[&"x"] - x) + absi(pos[&"y"] - y)
		if dist <= radius:
			result.append(entity_id)
	return result


# ── Watchers (end-of-tick batched notifications) ──────────────────────────────

func watch(component: StringName, callback: Callable) -> void:
	if not _watchers.has(component):
		_watchers[component] = []
	_watchers[component].append(callback)


func flush_notifications() -> void:
	for component: StringName in _dirty_components:
		if not _watchers.has(component):
			continue
		var dirty_set: Dictionary = _dirty_components[component]
		var callbacks: Array = _watchers[component]
		for entity_id: int in dirty_set:
			for cb: Callable in callbacks:
				cb.call(entity_id)
	_dirty_components.clear()


# ── Tick ──────────────────────────────────────────────────────────────────────

func get_tick() -> int:
	return _tick


func advance_tick() -> void:
	_tick += 1


# ── Private helpers ───────────────────────────────────────────────────────────

func _mark_dirty(entity_id: int, component: StringName) -> void:
	if not _dirty_components.has(component):
		_dirty_components[component] = {}
	_dirty_components[component][entity_id] = true
