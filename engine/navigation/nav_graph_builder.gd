class_name NavGraphBuilder extends RefCounted

# Per-species AStar2D instances: building edges only for traversable edge types avoids
# the INF-cost path problem — unreachable nodes simply have no path at all.
var _astars: Dictionary = {}  # StringName species_id -> AStar2D
var _next_nav_id: int = 0
var _floor_nodes: Dictionary = {}  # rack_index -> nav_id
var _floor_node_positions: Dictionary = {}  # rack_index -> Vector2
var _slot_nodes: Dictionary = {}   # "rack:slot" -> nav_id
# Box-style entry/interior anchors. Keys: "box_entry:rack:slot" and
# "box_interior:rack:slot". One pair per enterable host.
var _enterable_nodes: Dictionary = {}  # String -> nav_id


# Species body schema, indexed at register-time. Each species has:
#   body_capabilities: { verb -> {param_name: int, ...} }
#       e.g. {&"walks": {}, &"jumps": {&"max_height_ru": 3}, ...}
#   body_geometry: { &"size_ru": int }
# Edge scanners (add_rack_slot, add_box_enterable, ...) read these to decide
# whether to emit an edge for a given species.
var _body_capabilities: Dictionary = {}  # species_id -> Dictionary
var _body_geometry: Dictionary = {}      # species_id -> Dictionary


func _init() -> void:
	pass


func register_species(
		species_id: StringName,
		body_capabilities: Dictionary,
		body_geometry: Dictionary,
) -> void:
	_body_capabilities[species_id] = body_capabilities
	_body_geometry[species_id] = body_geometry
	if not _astars.has(species_id):
		_astars[species_id] = AStar2D.new()


func has_capability(species_id: StringName, verb: StringName) -> bool:
	var caps: Dictionary = _body_capabilities.get(species_id, {})
	return caps.has(verb)


func get_capability_param(
		species_id: StringName, verb: StringName, param: StringName,
		default_value: int = 0,
) -> int:
	var caps: Dictionary = _body_capabilities.get(species_id, {})
	var verb_data: Dictionary = caps.get(verb, {})
	return verb_data.get(param, default_value)


func get_body_size_ru(species_id: StringName) -> int:
	var geom: Dictionary = _body_geometry.get(species_id, {})
	return geom.get(&"size_ru", 0)


func build() -> void:
	_build_floor_nodes()


func get_astar(species_id: StringName) -> AStar2D:
	assert(
		_astars.has(species_id),
		"NavGraphBuilder: unregistered species: %s" % species_id,
	)
	return _astars[species_id]


func _build_floor_nodes() -> void:
	# One floor node per rack, positioned at floor level center
	var floor_rect: Rect2i = Constants.floor_rect_world(0)
	var floor_y: float = float(floor_rect.position.y + floor_rect.size.y / 2)
	for rack: int in Constants.RACK_COUNT:
		var nav_id: int = _next_nav_id
		_next_nav_id += 1
		var rack_col: Rect2i = Constants.rack_column_rect_world(0, rack)
		var x: float = float(rack_col.position.x + rack_col.size.x / 2)
		var pos := Vector2(x, floor_y)
		_floor_nodes[rack] = nav_id
		_floor_node_positions[rack] = pos
		for species_id: StringName in _astars:
			var astar: AStar2D = _astars[species_id]
			astar.add_point(nav_id, pos)
	# Connect adjacent floor nodes — WALK, all species can walk
	for rack: int in range(Constants.RACK_COUNT - 1):
		var from_id: int = _floor_nodes[rack]
		var to_id: int = _floor_nodes[rack + 1]
		for species_id: StringName in _astars:
			var astar: AStar2D = _astars[species_id]
			astar.connect_points(from_id, to_id)


func add_rack_slot(rack: int, slot: int) -> void:
	var key: String = "%d:%d" % [rack, slot]
	if _slot_nodes.has(key):
		return  # already exists
	var nav_id: int = _next_nav_id
	_next_nav_id += 1
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var x: float = float(slot_rect.position.x + slot_rect.size.x / 2)
	var y: float = float(slot_rect.position.y + slot_rect.size.y / 2)
	_slot_nodes[key] = nav_id
	for species_id: StringName in _astars:
		var astar: AStar2D = _astars[species_id]
		astar.add_point(nav_id, Vector2(x, y))
		# Connect to floor node only if species jumps and the slot is within
		# its max_height_ru. Species without `jumps` get no edge.
		if _floor_nodes.has(rack) and has_capability(species_id, &"jumps"):
			var max_height_ru: int = get_capability_param(
				species_id, &"jumps", &"max_height_ru",
			)
			var max_height_px: int = max_height_ru * Constants.SLOT_HEIGHT_PX
			var floor_pos: Vector2 = _floor_node_positions[rack]
			if int(floor_pos.y) - int(y) <= max_height_px:
				astar.connect_points(_floor_nodes[rack], nav_id)
		# Connect to adjacent occupied slots via WALK
		if has_capability(species_id, &"walks"):
			for ds: int in [-1, 1]:
				var adj_key: String = "%d:%d" % [rack, slot + ds]
				if _slot_nodes.has(adj_key):
					var adj_id: int = _slot_nodes[adj_key]
					astar.connect_points(nav_id, adj_id)


# Box-style enterable host. `join` is the contained-type join dict from
# OBJECT_CONFIG[type].state_ads[state].join. Adds two nav points:
#   - entry: the spot above the box where an animal lands before stepping in
#   - interior: where the animal sits while settled
# Wires per-species edges:
#   floor -> entry  via JUMP_UP (species.jumps.max_height_ru >= delta to entry)
#   entry -> interior via ENTER (species has settles_in_containers AND
#                                body.size_ru <= join.inner_size_ru)
func add_box_enterable(rack: int, slot: int, join: Dictionary) -> void:
	if join.get(&"type", &"") != &"contained":
		return
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var box_x: int = slot_rect.position.x + slot_rect.size.x / 2
	var box_y: int = slot_rect.position.y + slot_rect.size.y / 2
	var entry_off: Vector2i = join.get(&"entry_origin_offset", Vector2i.ZERO)
	var inter_off: Vector2i = join.get(&"interior_origin_offset", Vector2i.ZERO)
	var entry_pos := Vector2(
		float(box_x + entry_off.x), float(box_y + entry_off.y),
	)
	var inter_pos := Vector2(
		float(box_x + inter_off.x), float(box_y + inter_off.y),
	)
	var entry_id: int = _next_nav_id
	_next_nav_id += 1
	var inter_id: int = _next_nav_id
	_next_nav_id += 1
	var entry_key: String = "box_entry:%d:%d" % [rack, slot]
	var inter_key: String = "box_interior:%d:%d" % [rack, slot]
	_enterable_nodes[entry_key] = entry_id
	_enterable_nodes[inter_key] = inter_id

	var inner_size_ru: int = join.get(&"inner_size_ru", 0)
	var entry_threshold_ru: int = join.get(&"entry_threshold_ru", 0)

	for species_id: StringName in _astars:
		var astar: AStar2D = _astars[species_id]
		astar.add_point(entry_id, entry_pos)
		astar.add_point(inter_id, inter_pos)
		if not has_capability(species_id, &"jumps"):
			continue
		var max_jump_ru: int = get_capability_param(
			species_id, &"jumps", &"max_height_ru",
		)
		if entry_threshold_ru > max_jump_ru:
			continue
		if not _floor_nodes.has(rack):
			continue
		var floor_pos: Vector2 = _floor_node_positions[rack]
		var delta_y: int = int(floor_pos.y) - int(entry_pos.y)
		if delta_y > max_jump_ru * Constants.SLOT_HEIGHT_PX:
			continue
		astar.connect_points(_floor_nodes[rack], entry_id)
		if not has_capability(species_id, &"settles_in_containers"):
			continue
		var body_size: int = get_body_size_ru(species_id)
		if body_size > inner_size_ru:
			continue
		astar.connect_points(entry_id, inter_id)


func remove_box_enterable(rack: int, slot: int) -> void:
	var entry_key: String = "box_entry:%d:%d" % [rack, slot]
	var inter_key: String = "box_interior:%d:%d" % [rack, slot]
	for k: String in [entry_key, inter_key]:
		if not _enterable_nodes.has(k):
			continue
		var nav_id: int = _enterable_nodes[k]
		for species_id: StringName in _astars:
			var astar: AStar2D = _astars[species_id]
			if astar.has_point(nav_id):
				astar.remove_point(nav_id)
		_enterable_nodes.erase(k)


func remove_rack_slot(rack: int, slot: int) -> void:
	var key: String = "%d:%d" % [rack, slot]
	if not _slot_nodes.has(key):
		return
	var nav_id: int = _slot_nodes[key]
	for species_id: StringName in _astars:
		(_astars[species_id] as AStar2D).remove_point(nav_id)
	_slot_nodes.erase(key)


func get_path_points(
	species_id: StringName, from_pos: Vector2, to_pos: Vector2
) -> PackedVector2Array:
	var astar: AStar2D = _astars.get(species_id, null)
	if astar == null:
		return PackedVector2Array()
	var from_id: int = astar.get_closest_point(from_pos)
	var to_id: int = astar.get_closest_point(to_pos)
	if from_id == -1 or to_id == -1:
		return PackedVector2Array()
	return astar.get_point_path(from_id, to_id)


func get_nearest_floor_node(rack: int) -> Vector2:
	return _floor_node_positions.get(rack, Vector2.ZERO)


# Movement-side query: returns the next nav node to step toward, or the
# `from` position unchanged when no path exists. Owning this on the
# navgraph means the move loop never needs a separate can_reach gate —
# entities with unreachable targets simply stay put, and the AI layer
# notices on its next evaluation pass.
func next_waypoint_or_stay(
		species_id: StringName, from_px: Vector2i, to_px: Vector2i,
) -> Vector2i:
	var fallback: Vector2i = from_px
	var astar: AStar2D = _astars.get(species_id, null)
	if from_px == to_px or astar == null:
		return fallback
	var to_pos := Vector2(float(to_px.x), float(to_px.y))
	var to_id: int = astar.get_closest_point(to_pos)
	if to_id == -1:
		return fallback
	var node_pos: Vector2 = astar.get_point_position(to_id)
	# Off-graph: if the target sits more than a slot-height from any nav
	# node, the entity can only ever reach the nearest-but-far node and
	# never the actual target. Treat that as unreachable so the AI re-picks.
	var off_graph: bool = (node_pos - to_pos).length() > float(Constants.SLOT_HEIGHT_PX)
	if off_graph:
		return fallback
	var path: PackedVector2Array = get_path_points(
		species_id, Vector2(float(from_px.x), float(from_px.y)), to_pos,
	)
	var path_terminates_at_target: bool = (
		path.size() > 0
		and path[path.size() - 1].is_equal_approx(node_pos)
	)
	if not path_terminates_at_target:
		return fallback
	# path.size() == 1 → from and to map to the SAME nav node; entity is
	# inside that node's domain but offset from it, so walk straight to
	# the node and let arrival fire on the move loop's next pass.
	# path.size() >= 2 → path[0] is the anchor (closest nav node to
	# from_px); when from_px is offset from it the anchor sits *behind*
	# the entity, so returning it walks backward and the next-tick's
	# closest-point flip walks forward — the 2-px ping-pong. Skip the
	# anchor and return path[1] (the first real step).
	var step: Vector2 = node_pos if path.size() == 1 else path[1]
	return Vector2i(roundi(step.x), roundi(step.y))


func can_reach(species_id: StringName, from_pos: Vector2, to_pos: Vector2) -> bool:
	# Returns true if a valid path exists for this species between the two positions.
	# Per-species AStar instances have only traversable edges, so empty path = unreachable.
	# Stricter than "any path exists": the destination must lie on (or
	# essentially at) a registered nav node — `astar.get_closest_point` will
	# happily return a far-off floor node when the real target sits in
	# unregistered air (e.g. slot 8 with no `add_rack_slot`), and treating
	# that as reachable lets the AI commit to targets the entity can never
	# actually walk to. The threshold is one slot height; tighter would
	# reject placement-jitter that's tolerated everywhere else.
	var astar: AStar2D = _astars.get(species_id, null)
	if astar == null:
		return false
	var to_id: int = astar.get_closest_point(to_pos)
	if to_id == -1:
		return false
	var target_node_pos: Vector2 = astar.get_point_position(to_id)
	var off_graph_threshold: float = float(Constants.SLOT_HEIGHT_PX)
	if (target_node_pos - to_pos).length() > off_graph_threshold:
		return false
	var path: PackedVector2Array = get_path_points(species_id, from_pos, to_pos)
	if path.size() == 0:
		return false
	# Verify the path actually reaches the intended target node (not just the closest floor node)
	return path[path.size() - 1].is_equal_approx(target_node_pos)
