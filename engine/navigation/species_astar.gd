class_name SpeciesAStar extends AStar2D

# Edge type constants
const WALK: StringName = &"WALK"
const JUMP_UP: StringName = &"JUMP_UP"
const JUMP_DOWN: StringName = &"JUMP_DOWN"

# Species traversal capabilities
const SPECIES_CAPABILITIES: Dictionary = {
	&"tcp_base:cat": [WALK, JUMP_UP, JUMP_DOWN],
	&"tcp_base:ferret": [WALK, JUMP_DOWN],
}

var _species: StringName = &""
var _edge_types: Dictionary = {}  # "from_id:to_id" -> StringName


func set_species(species_id: StringName) -> void:
	_species = species_id


func set_edge_type(from_id: int, to_id: int, edge_type: StringName) -> void:
	_edge_types[_edge_key(from_id, to_id)] = edge_type
	_edge_types[_edge_key(to_id, from_id)] = edge_type


func _edge_key(from_id: int, to_id: int) -> String:
	return "%d:%d" % [from_id, to_id]


func _compute_cost(from_id: int, to_id: int) -> float:
	var key: String = _edge_key(from_id, to_id)
	var edge_type: StringName = _edge_types.get(key, WALK)
	var capabilities: Array = SPECIES_CAPABILITIES.get(_species, [WALK])
	if edge_type not in capabilities:
		return INF
	# Default AStar2D cost: Euclidean distance between the two points
	return get_point_position(from_id).distance_to(get_point_position(to_id))
