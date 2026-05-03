class_name DesireResolver extends RefCounted

const WANDER_THRESHOLD: int = 800

var _db: GameStateDB
# Set semantics: entity_id -> true. Prevents duplicate entries.
var _dirty: Dictionary = {}
# Optional. When wired, candidate ads on entities the animal cannot reach
# are skipped in `_evaluate_one`. Tests that don't care about reachability
# leave this null (legacy behavior).
var _nav: NavGraphBuilder = null


func _init(db: GameStateDB) -> void:
	_db = db


func set_nav_builder(nav: NavGraphBuilder) -> void:
	_nav = nav


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
	# `channel` is the new (PR2) ad field name; `desire_type` is legacy
	# and supported during the rollover for any out-of-tree mod still on
	# the old shape.
	var channel: StringName = ad.get(&"channel", ad.get(&"desire_type", &""))

	# Curiosity novelty check: if tracker provided and target was
	# recently visited, score 0. Runs before the CHANNELS lookup so a
	# new `curiosity_action` channel wouldn't break the gate.
	if tracker != null and channel == &"curiosity":
		var cooldown: int = ad.get(&"novelty_cooldown", 100)
		if not tracker.is_novel(object_id, current_tick, cooldown):
			return 0

	# Action ads outside the channel registry (e.g. `openable` consumed
	# by the food system) score 0 in the regular AI scoring loop. They
	# get consumed by their own state-loop ticker.
	if not Constants.CHANNELS.has(channel):
		return 0

	var meta: Dictionary = Constants.CHANNELS[channel]
	var target_desire: StringName = meta[&"desire"]
	var effect: StringName = meta[&"effect"]
	var sense_key: StringName = meta[&"sense"]

	var personality: Dictionary = _db.get_component(animal_id, &"personality")
	var weight_key: StringName = StringName(String(target_desire) + "_weight")
	var desire_weight: int = personality.get(weight_key, 500)

	var animal_pos: Dictionary = _db.get_component(animal_id, &"position")
	var object_pos: Dictionary = _db.get_component(object_id, &"position")
	var dist_px: int = (
		absi(animal_pos[&"x"] - object_pos[&"x"])
		+ absi(animal_pos[&"y"] - object_pos[&"y"])
	)

	var senses: Dictionary = (
		_db.get_component(animal_id, &"senses")
		if _db.has_component(animal_id, &"senses")
		else {}
	)
	var sense_range: int = senses.get(sense_key, Constants.BAY_WIDTH_PX)

	if dist_px > sense_range:
		return 0

	# Distance falloff scales over sense range (travel-cost preference) —
	# NOT over the ad's effect_radius_px. Scoring answers "how far must
	# I walk?"; emitter physics is a scatter concern, not a scoring concern.
	var dist_factor: int = (
		1000 - (dist_px * 1000 / sense_range) if sense_range > 0 else 1000
	)
	var strength: int = ad[&"strength"]

	if effect == &"satisfy":
		var desires: Dictionary = _db.get_component(animal_id, &"desires")
		var deficit: int = 1000 - desires.get(target_desire, 500)
		return desire_weight * deficit / 1000 * strength / 1000 * dist_factor / 1000

	# deplete: no deficit term — a cat is not "deficit-hungry for quiet".
	return -1 * desire_weight * strength / 1000 * dist_factor / 1000


# ── Private ───────────────────────────────────────────────────────────────────

func _evaluate_one(entity_id: int, trackers: Dictionary = {}) -> void:
	if not _db.has_entity(entity_id):
		return
	if not _db.has_component(entity_id, &"position"):
		return
	if not _db.has_component(entity_id, &"desires"):
		return
	# Settled entities are deliberately resting (e.g. cat tucked in box).
	# Skipping AI evaluation keeps them put — without this guard the resolver
	# would re-score nearby ads, transition out of SLEEPING, and the move loop
	# would pull the cat out of the box on the very next tick.
	if _db.has_component(entity_id, &"settled_in"):
		return
	# SETTLING is the 2s commit between arrival-at-host and settled_in. The
	# host's ad still scores high (cat is at distance 0, comfort deficit
	# still 1000 because the bond hasn't been written yet) so without this
	# guard the resolver re-targets each tick, the move loop converts back
	# to SEEKING/MOVING_TO, arrival fires again, the SETTLING timer resets
	# to 0, and the cat never accumulates the 2s needed to complete.
	if _db.has_component(entity_id, &"ai_state"):
		var ai_state: Dictionary = _db.get_component(entity_id, &"ai_state")
		if ai_state.get(&"state", &"") == &"SETTLING":
			return

	var pos: Dictionary = _db.get_component(entity_id, &"position")
	# Spatial bound: one bay. Per-sense clipping happens inside score_ad,
	# so per-channel acuity (touch=64 etc.) still narrows the actual
	# candidate set after this query returns.
	var nearby: Array[int] = _db.query_radius(
		pos[&"x"], pos[&"y"], Constants.BAY_WIDTH_PX,
	)

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
		if not _is_reachable(entity_id, candidate_id):
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


func _is_reachable(animal_id: int, target_id: int) -> bool:
	# When no navgraph is wired, every candidate is treated as reachable —
	# matches the pre-filter behavior so isolated unit tests don't need to
	# build a graph. With a graph, only species we've registered participate;
	# unregistered species (test fixtures) also pass through unfiltered.
	if _nav == null:
		return true
	if not _db.has_component(animal_id, &"species"):
		return true
	var species_id: StringName = _db.get_component(animal_id, &"species")[&"id"]
	var animal_pos: Dictionary = _db.get_component(animal_id, &"position")
	var target_pos: Dictionary = _db.get_component(target_id, &"position")
	var from_v := Vector2(float(animal_pos[&"x"]), float(animal_pos[&"y"]))
	var to_v := Vector2(float(target_pos[&"x"]), float(target_pos[&"y"]))
	return _nav.can_reach(species_id, from_v, to_v)


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
	var rack_col: Rect2i = Constants.rack_column_rect_world(0, rack)
	var center_x: int = rack_col.position.x + rack_col.size.x / 2
	var jitter: int = randi_range(-Constants.RACK_WIDTH_PX / 2, Constants.RACK_WIDTH_PX / 2)
	var x: int = center_x + jitter
	var floor_rect: Rect2i = Constants.floor_rect_world(0)
	var y: int = floor_rect.position.y + floor_rect.size.y / 2
	return {&"x": x, &"y": y}
