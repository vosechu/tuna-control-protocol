class_name Bonds extends RefCounted

# Bond markers: components that connect an entity to a host whose
# action-tagged advertisements the entity is entitled to consume.
# A "bond" is the active state itself — being settled in a box, mounted on
# a creature, holding a tool. While the bond is in place, passive-
# proximity gating is bypassed for the bonded host: action ads from that
# host satisfy the bonded entity directly.
#
# Convention: every bond marker component carries a `&"host_id"` field
# pointing at the host. Register components at boot via `register_bond`.
# A mod that ships a new bond (mounted_on, inside_tube, etc.) registers
# during its load phase — the engine never hardcodes the list.

static var _bond_components: Array[StringName] = []


# Register a component as a bond marker. Idempotent. Called at boot by
# whichever system owns the bond (e.g. SettledLifecycle owns
# `settled_in`).
static func register_bond(component_name: StringName) -> void:
	if component_name in _bond_components:
		return
	_bond_components.append(component_name)


# Cheap "does this entity carry any bond marker?" probe. Used to skip
# the allocation path in hot loops when ~most entities have no bonds.
static func has_any_bond(db: GameStateDB, entity_id: int) -> bool:
	for comp: StringName in _bond_components:
		if db.has_component(entity_id, comp):
			return true
	return false


# Returns the list of host entity IDs this entity is currently bonded
# to. Empty array when no bonds exist. Allocates — gate behind
# `has_any_bond` in hot paths.
static func get_bond_hosts(db: GameStateDB, entity_id: int) -> Array[int]:
	var out: Array[int] = []
	for comp: StringName in _bond_components:
		if not db.has_component(entity_id, comp):
			continue
		var host_id: int = db.get_field(entity_id, comp, &"host_id")
		if host_id != Constants.INVALID_ID:
			out.append(host_id)
	return out


# Test seam: forget every registered bond. Production code never calls
# this; a fresh GameServer is the production reset path.
static func _reset_for_tests() -> void:
	_bond_components.clear()
