class_name NavGraphBuilder extends RefCounted

# Per-species AStar2D instances: building edges only for traversable edge types avoids
# the INF-cost path problem — unreachable nodes simply have no path at all.
var _astars: Dictionary = {}  # StringName species_id -> AStar2D
var _next_nav_id: int = 0
var _floor_nodes: Dictionary = {}  # rack_index -> nav_id
var _slot_nodes: Dictionary = {}   # "rack:slot" -> nav_id


func _init() -> void:
	# Create one AStar2D per known species
	for species_id: StringName in SpeciesAStar.SPECIES_CAPABILITIES:
		_astars[species_id] = AStar2D.new()
	_build_floor_nodes()


func get_astar() -> AStar2D:
	# Returns the cat astar for debug/test use; cats have the most connectivity
	return _astars.get(&"tcp_base:cat", AStar2D.new())


func _build_floor_nodes() -> void:
	# One floor node per rack, positioned at floor level center
	for rack: int in Constants.RACK_COUNT:
		var nav_id: int = _next_nav_id
		_next_nav_id += 1
		@warning_ignore("integer_division")
		var x: float = float(rack * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2)
		var y: float = float(
			Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 2
		)
		_floor_nodes[rack] = nav_id
		for species_id: StringName in _astars:
			var astar: AStar2D = _astars[species_id]
			astar.add_point(nav_id, Vector2(x, y))
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
	@warning_ignore("integer_division")
	var x: float = float(rack * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2)
	var y: float = float(slot * Constants.SLOT_HEIGHT_PU)
	_slot_nodes[key] = nav_id
	for species_id: StringName in _astars:
		var astar: AStar2D = _astars[species_id]
		astar.add_point(nav_id, Vector2(x, y))
		var capabilities: Array = SpeciesAStar.SPECIES_CAPABILITIES.get(species_id, [])
		# Connect to floor node — only if species can JUMP_UP
		if _floor_nodes.has(rack) and SpeciesAStar.JUMP_UP in capabilities:
			astar.connect_points(_floor_nodes[rack], nav_id)
		# Connect to adjacent occupied slots via WALK
		if SpeciesAStar.WALK in capabilities:
			for ds: int in [-1, 1]:
				var adj_key: String = "%d:%d" % [rack, slot + ds]
				if _slot_nodes.has(adj_key):
					var adj_id: int = _slot_nodes[adj_key]
					astar.connect_points(nav_id, adj_id)


func remove_rack_slot(rack: int, slot: int) -> void:
	var key: String = "%d:%d" % [rack, slot]
	if not _slot_nodes.has(key):
		return
	var nav_id: int = _slot_nodes[key]
	for species_id: StringName in _astars:
		(_astars[species_id] as AStar2D).remove_point(nav_id)
	_slot_nodes.erase(key)


func get_path_points(species_id: StringName, from_pos: Vector2, to_pos: Vector2) -> PackedVector2Array:
	var astar: AStar2D = _astars.get(species_id, null)
	if astar == null:
		return PackedVector2Array()
	var from_id: int = astar.get_closest_point(from_pos)
	var to_id: int = astar.get_closest_point(to_pos)
	if from_id == -1 or to_id == -1:
		return PackedVector2Array()
	return astar.get_point_path(from_id, to_id)


func get_nearest_floor_node(rack: int) -> Vector2:
	# All species share the same floor node positions
	var astar: AStar2D = _astars.get(&"tcp_base:cat", null)
	if astar == null or not _floor_nodes.has(rack):
		return Vector2.ZERO
	return astar.get_point_position(_floor_nodes[rack])


func can_reach(species_id: StringName, from_pos: Vector2, to_pos: Vector2) -> bool:
	# Returns true if a valid path exists for this species between the two positions.
	# Per-species AStar instances have only traversable edges, so empty path = unreachable.
	var astar: AStar2D = _astars.get(species_id, null)
	if astar == null:
		return false
	var to_id: int = astar.get_closest_point(to_pos)
	if to_id == -1:
		return false
	var target_node_pos: Vector2 = astar.get_point_position(to_id)
	var path: PackedVector2Array = get_path_points(species_id, from_pos, to_pos)
	if path.size() == 0:
		return false
	# Verify the path actually reaches the intended target node (not just the closest floor node)
	return path[path.size() - 1].is_equal_approx(target_node_pos)
