class_name DesireResolver extends RefCounted

var _db: GameStateDB
# Set semantics: entity_id -> true. Prevents duplicate entries.
var _dirty: Dictionary = {}


func _init(db: GameStateDB) -> void:
	_db = db


# Mark an entity as needing AI re-evaluation. Deduplicates automatically.
func mark_dirty(entity_id: int) -> void:
	_dirty[entity_id] = true


# Evaluate dirty entities in priority order (highest deficit first) until the
# time budget is exhausted.
func evaluate_budget() -> void:
	var start: int = Time.get_ticks_usec()
	while _dirty.size() > 0:
		if Time.get_ticks_usec() - start >= Constants.EVAL_TIME_BUDGET_USEC:
			break
		var id: int = _pop_highest_deficit()
		if id == Constants.INVALID_ID:
			break
		_evaluate_one(id)


# Score a single advertisement against an animal's desires.
# Returns 0 if the object is out of range or desire type is missing.
func score_ad(animal_id: int, object_id: int, ad: Dictionary) -> int:
	var desire_type: StringName = ad[&"desire_type"]

	var personality: Dictionary = _db.get_component(animal_id, &"personality")
	var desires: Dictionary = _db.get_component(animal_id, &"desires")

	# Weight key derived from desire type, e.g. &"warmth" -> &"warmth_weight"
	var weight_key: StringName = StringName(String(desire_type) + "_weight")
	var desire_weight: int = personality.get(weight_key, 500)

	# Desire value IS the deficit: 0 = fully satisfied, 1000 = desperate.
	var deficit: int = desires.get(desire_type, 500)
	var strength: int = ad[&"strength"]

	var animal_pos: Dictionary = _db.get_component(animal_id, &"position")
	var object_pos: Dictionary = _db.get_component(object_id, &"position")
	var dist_pu: int = absi(animal_pos[&"x"] - object_pos[&"x"]) + absi(animal_pos[&"y"] - object_pos[&"y"])
	var radius_pu: int = Constants.ru_to_pu(ad[&"radius_ru"])

	if dist_pu > radius_pu:
		return 0

	var dist_factor: int = 1000 - (dist_pu * 1000 / radius_pu) if radius_pu > 0 else 1000

	return desire_weight * deficit / 1000 * strength / 1000 * dist_factor / 1000


# ── Private ───────────────────────────────────────────────────────────────────

func _evaluate_one(entity_id: int) -> void:
	if not _db.has_entity(entity_id):
		return
	if not _db.has_component(entity_id, &"position"):
		return
	if not _db.has_component(entity_id, &"desires"):
		return

	var pos: Dictionary = _db.get_component(entity_id, &"position")
	var perception_pu: int = Constants.ru_to_pu(8)
	var nearby: Array[int] = _db.query_radius(pos[&"x"], pos[&"y"], perception_pu)

	var best_score: int = 0
	var best_target_id: int = Constants.INVALID_ID
	var best_target_pos: Dictionary = {}

	for candidate_id: int in nearby:
		if candidate_id == entity_id:
			continue
		if not _db.has_component(candidate_id, &"advertisements"):
			continue
		if not _db.has_component(candidate_id, &"position"):
			continue
		var ads_component: Dictionary = _db.get_component(candidate_id, &"advertisements")
		var ad_list: Array = ads_component[&"list"]
		for ad: Dictionary in ad_list:
			var score: int = score_ad(entity_id, candidate_id, ad)
			if score > best_score:
				best_score = score
				best_target_id = candidate_id
				best_target_pos = _db.get_component(candidate_id, &"position")

	var ai_state: Dictionary = _db.get_component(entity_id, &"ai_state")
	var commitment: int = ai_state.get(&"commitment_score", 0)

	if best_score > commitment + Constants.SWITCH_THRESHOLD:
		_db.set_component(entity_id, &"ai_state", {
			&"state": &"SEEKING",
			&"meta_state": &"GOAL_DIRECTED",
			&"commitment_score": best_score,
		})
		_db.set_component(entity_id, &"target", {
			&"x": best_target_pos[&"x"],
			&"y": best_target_pos[&"y"],
			&"entity_id": best_target_id,
		})


# Returns and removes the dirty entity with the highest desire deficit.
# Skips entities that no longer exist or lack a desires component.
# Returns INVALID_ID if the dirty set is empty or all entities are stale.
func _pop_highest_deficit() -> int:
	var best_id: int = Constants.INVALID_ID
	var best_deficit: int = -1

	var stale: Array[int] = []

	for entity_id: int in _dirty:
		if not _db.has_entity(entity_id) or not _db.has_component(entity_id, &"desires"):
			stale.append(entity_id)
			continue
		var desires: Dictionary = _db.get_component(entity_id, &"desires")
		# Find the maximum desire value (highest deficit) across all desire types.
		var max_val: int = 0
		for key: StringName in desires:
			var val: int = desires[key]
			if val > max_val:
				max_val = val
		if max_val > best_deficit:
			best_deficit = max_val
			best_id = entity_id

	# Remove stale entities
	for stale_id: int in stale:
		_dirty.erase(stale_id)

	if best_id != Constants.INVALID_ID:
		_dirty.erase(best_id)

	return best_id
