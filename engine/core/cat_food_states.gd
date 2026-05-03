class_name CatFoodStates extends RefCounted

# Pure-core helpers for cat hunger/eating state transitions. Called from
# nodes/game_server.gd inside _update_ambient_states, and also exercised
# directly by unit tests so the behavior is verifiable without a scene tree.

# Hunger threshold below which an AMBIENT cat switches to HUNGRY/PACING.
# Desires scale 0..1000; 400 is "starting to feel it but not starving".
const HUNGER_THRESHOLD: int = 400

# When a cat starts EATING, each food-intake pulse raises hunger by this much.
const EAT_GAIN_PER_PULSE: int = 500


static func should_become_hungry(db: GameStateDB, entity_id: int) -> bool:
	if not db.has_component(entity_id, &"desires"):
		return false
	var hunger: int = db.get_field(entity_id, &"desires", &"hunger")
	return hunger < HUNGER_THRESHOLD


static func find_nearest_dispenser(
		db: GameStateDB, entity_id: int, nav: NavGraphBuilder = null,
) -> int:
	# Linear manhattan-distance search over every tuna_dispenser. Used only in
	# the HUNGRY->target path; at prototype scale (<20 dispensers) this is
	# fine. Upgrade to spatial-hash query when dispenser count demands it.
	# When `nav` is supplied AND the entity has a registered species, only
	# dispensers reachable for that species are considered. Without that
	# filter the cat would commit to a dispenser the navgraph can never
	# walk it to (e.g. slot 8) and sit in HUNGRY forever.
	if not db.has_component(entity_id, &"position"):
		return Constants.INVALID_ID
	var pos: Dictionary = db.get_component(entity_id, &"position")
	var dispensers: Array[int] = db.get_entities_with(&"tuna_dispenser")
	if dispensers.is_empty():
		return Constants.INVALID_ID
	var has_species: bool = nav != null and db.has_component(entity_id, &"species")
	var species_id: StringName = &""
	var from_v := Vector2.ZERO
	if has_species:
		species_id = db.get_component(entity_id, &"species")[&"id"]
		from_v = Vector2(float(pos[&"x"]), float(pos[&"y"]))
	var best_id: int = Constants.INVALID_ID
	var best_dist: int = 999999
	for disp_id: int in dispensers:
		var dpos: Dictionary = db.get_component(disp_id, &"position")
		var dist: int = (
			absi(dpos[&"x"] - pos[&"x"])
			+ absi(dpos[&"y"] - pos[&"y"])
		)
		if dist >= best_dist:
			continue
		if has_species:
			var to_v := Vector2(float(dpos[&"x"]), float(dpos[&"y"]))
			if not nav.can_reach(species_id, from_v, to_v):
				continue
		best_dist = dist
		best_id = disp_id
	return best_id


static func apply_eat_pulse(db: GameStateDB, entity_id: int) -> void:
	if not db.has_component(entity_id, &"desires"):
		return
	var hunger: int = db.get_field(entity_id, &"desires", &"hunger")
	db.set_field(
		entity_id, &"desires", &"hunger",
		mini(1000, hunger + EAT_GAIN_PER_PULSE),
	)
