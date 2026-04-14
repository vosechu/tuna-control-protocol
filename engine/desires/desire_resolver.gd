class_name DesireResolver extends RefCounted

const WANDER_THRESHOLD: int = 800

var _db: GameStateDB
# Set semantics: entity_id -> true. Prevents duplicate entries.
var _dirty: Dictionary = {}


func _init(db: GameStateDB) -> void:
	_db = db


# Mark an entity as needing AI re-evaluation. Deduplicates automatically.
func mark_dirty(entity_id: int) -> void:
	_dirty[entity_id] = true


# Number of unique entities currently dirty. Exposed for test observability.
func dirty_count() -> int:
	return _dirty.size()


# Mark every entity that has a desires component as dirty.
# Replaces per-species filtering — any entity with desires gets evaluated.
func mark_all_dirty() -> void:
	var entities: Array[int] = _db.get_entities_with(&"desires")
	for entity_id: int in entities:
		mark_dirty(entity_id)


# Evaluate dirty entities in priority order (highest deficit first) until the
# time budget is exhausted. Pass a trackers dict (entity_id -> CuriosityTracker)
# to enable novelty checks for curiosity ads.
func evaluate_budget(trackers: Dictionary = {}) -> void:
	var start: int = Time.get_ticks_usec()
	while _dirty.size() > 0:
		if Time.get_ticks_usec() - start >= Constants.EVAL_TIME_BUDGET_USEC:
			break
		var id: int = pop_highest_deficit()
		if id == Constants.INVALID_ID:
			break
		_evaluate_one(id, trackers)


# Score a single advertisement against an animal's desires.
# Returns 0 if the object is out of range or desire type is missing.
# Pass tracker + current_tick to apply novelty filtering for curiosity ads.
func score_ad(
	animal_id: int,
	object_id: int,
	ad: Dictionary,
	tracker: CuriosityTracker = null,
	current_tick: int = 0,
) -> int:
	var desire_type: StringName = ad[&"desire_type"]

	# Curiosity novelty check: if tracker provided and target was recently visited, score 0.
	if tracker != null and desire_type == &"curiosity":
		var cooldown: int = ad.get(&"novelty_cooldown", 100)
		if not tracker.is_novel(object_id, current_tick, cooldown):
			return 0

	var personality: Dictionary = _db.get_component(animal_id, &"personality")
	var desires: Dictionary = _db.get_component(animal_id, &"desires")

	# Weight key derived from desire type, e.g. &"warmth" -> &"warmth_weight"
	var weight_key: StringName = StringName(String(desire_type) + "_weight")
	var desire_weight: int = personality.get(weight_key, 500)

	# Desire value is satisfaction: 0 = desperate (cold/hungry/lonely),
	# 1000 = fully satisfied. Deficit is the complement.
	var deficit: int = 1000 - desires.get(desire_type, 500)
	var strength: int = ad[&"strength"]

	var animal_pos: Dictionary = _db.get_component(animal_id, &"position")
	var object_pos: Dictionary = _db.get_component(object_id, &"position")
	var dist_pu: int = (
		absi(animal_pos[&"x"] - object_pos[&"x"])
		+ absi(animal_pos[&"y"] - object_pos[&"y"])
	)
	var radius_pu: int = Constants.ru_to_pu(ad[&"radius_ru"])

	if dist_pu > radius_pu:
		return 0

	var dist_factor: int = 1000 - (dist_pu * 1000 / radius_pu) if radius_pu > 0 else 1000

	return desire_weight * deficit / 1000 * strength / 1000 * dist_factor / 1000


# ── Private ───────────────────────────────────────────────────────────────────

func _evaluate_one(entity_id: int, trackers: Dictionary = {}) -> void:
	if not _db.has_entity(entity_id):
		return
	if not _db.has_component(entity_id, &"position"):
		return
	if not _db.has_component(entity_id, &"desires"):
		return

	var pos: Dictionary = _db.get_component(entity_id, &"position")
	var perception_pu: int = Constants.ru_to_pu(8)
	var nearby: Array[int] = _db.query_radius(pos[&"x"], pos[&"y"], perception_pu)

	var tracker: CuriosityTracker = trackers.get(entity_id, null)
	var current_tick: int = _db.get_tick()

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
			var score: int = score_ad(entity_id, candidate_id, ad, tracker, current_tick)
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
	elif ai_state[&"meta_state"] == &"AMBIENT" and commitment == 0:
		# No good ad in range — wander if any desire is low enough (deprived).
		# Desire value is satisfaction: 0 = desperate, 1000 = satisfied.
		# Worst deficit = 1000 - min(satisfaction).
		var desires: Dictionary = _db.get_component(entity_id, &"desires")
		var min_satisfaction: int = 1000
		for key: StringName in desires:
			if desires[key] < min_satisfaction:
				min_satisfaction = desires[key]
		var worst_deficit: int = 1000 - min_satisfaction
		if worst_deficit >= WANDER_THRESHOLD:
			var wander_pos: Dictionary = _random_floor_position()
			_db.set_component(entity_id, &"ai_state", {
				&"state": &"WANDERING",
				&"meta_state": &"GOAL_DIRECTED",
				&"commitment_score": 0,
			})
			_db.set_component(entity_id, &"target", {
				&"x": wander_pos[&"x"],
				&"y": wander_pos[&"y"],
				&"entity_id": Constants.INVALID_ID,
			})


# Returns and removes the dirty entity with the highest desire deficit.
# Skips entities that no longer exist or lack a desires component.
# Returns INVALID_ID if the dirty set is empty or all entities are stale.
func pop_highest_deficit() -> int:
	var best_id: int = Constants.INVALID_ID
	var best_deficit: int = -1

	var stale: Array[int] = []

	for entity_id: int in _dirty:
		if not _db.has_entity(entity_id) or not _db.has_component(entity_id, &"desires"):
			stale.append(entity_id)
			continue
		var desires: Dictionary = _db.get_component(entity_id, &"desires")
		# Desire value is satisfaction (0 = desperate, 1000 = satisfied).
		# Highest deficit = lowest satisfaction across all desire types.
		var min_val: int = 1000
		for key: StringName in desires:
			var val: int = desires[key]
			if val < min_val:
				min_val = val
		var deficit: int = 1000 - min_val
		if deficit > best_deficit:
			best_deficit = deficit
			best_id = entity_id

	# Remove stale entities
	for stale_id: int in stale:
		_dirty.erase(stale_id)

	if best_id != Constants.INVALID_ID:
		_dirty.erase(best_id)

	return best_id


func _random_floor_position() -> Dictionary:
	var rack: int = randi_range(0, Constants.RACK_COUNT - 1)
	var center_x: int = Constants.rack_slot_to_pu(0, rack, 0).x
	var jitter: int = randi_range(-Constants.RACK_WIDTH_PU / 2, Constants.RACK_WIDTH_PU / 2)
	var x: int = center_x + jitter
	var y: int = Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 2
	return {&"x": x, &"y": y}
