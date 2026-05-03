extends GutTest

var _db: GameStateDB
var _heat_grid: HeatGrid
var _resolver: DesireResolver


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	_db = GameStateDB.new()
	_heat_grid = HeatGrid.new(_db)
	_resolver = DesireResolver.new(_db)


# ── Helpers ──────────────────────────────────────────────────

func _make_cat(
	x: int, y: int, food: int = 800,
) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {
		&"id": &"tcp_cats:cat",
		&"variant": &"cat01",
		&"name": &"TestCat",
	})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"desires", {
		&"warmth": 800,
		&"comfort": 800,
		&"curiosity": 1000,
		&"food": food,
	})
	_db.set_component(id, &"personality", {
		&"warmth_weight": 800,
		&"comfort_weight": 600,
		&"curiosity_weight": 100,
		&"food_weight": 700,
	})
	_db.set_component(id, &"ai_state", {
		&"state": &"IDLE",
		&"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	_db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	_db.update_spatial(id, x, y)
	return id


func _make_open_can(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(
		id, &"object_type", {&"type": &"tuna_can"},
	)
	_db.set_component(
		id, &"object_state", {&"state": &"open"},
	)
	_db.set_component(id, &"advertisements", {&"list": [{
		&"desire_type": &"food",
		&"strength": 800,
		&"radius_px": 40,
		&"action": &"eat",
		&"action_duration": 50,
	}]})
	_db.update_spatial(id, x, y)
	return id


func _make_arm(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {
		&"id": &"tcp_base:robot_arm",
		&"variant": &"arm",
		&"name": &"ARM-01",
	})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"desires", {&"purpose": 200})
	_db.set_component(id, &"personality", {
		&"openable_weight": 900,
		&"scannable_weight": 500,
	})
	_db.set_component(id, &"ai_state", {
		&"state": &"IDLE",
		&"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	_db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	_db.update_spatial(id, x, y)
	return id


func _make_sealed_can(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(
		id, &"object_type", {&"type": &"tuna_can"},
	)
	_db.set_component(
		id, &"object_state", {&"state": &"sealed"},
	)
	_db.set_component(id, &"advertisements", {&"list": [{
		&"desire_type": &"openable",
		&"strength": 800,
		&"radius_px": 24,
		&"action": &"open",
		&"action_duration": 30,
	}]})
	_db.update_spatial(id, x, y)
	return id


func _make_box(x: int, y: int, hp: int = 1000) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(
		id, &"object_type", {&"type": &"cardboard_box"},
	)
	_db.set_component(
		id, &"object_state", {&"state": &"new"},
	)
	_db.set_component(id, &"object_hp", {&"hp": hp})
	_db.set_component(id, &"advertisements", {&"list": [
		{
			&"desire_type": &"comfort",
			&"strength": 700,
			&"radius_px": 32,
		},
		{
			&"desire_type": &"curiosity",
			&"strength": 500,
			&"radius_px": 40,
			&"action": &"shred",
			&"action_duration": 20,
		},
	]})
	_db.update_spatial(id, x, y)
	return id


# Mirrors GameServer.transition_object_state / _update_ads_for_*
# (inline helper, same pattern as test_tuna_chain.gd)
func _transition_object(
	entity_id: int, new_state: StringName,
) -> void:
	_db.set_component(
		entity_id, &"object_state",
		{&"state": new_state},
	)
	var obj: Dictionary = _db.get_component(
		entity_id, &"object_type",
	)
	match obj[&"type"]:
		&"tuna_can":
			_transition_tuna_ads(entity_id, new_state)
		&"cardboard_box":
			_transition_box_ads(entity_id, new_state)


func _transition_tuna_ads(
	entity_id: int, state: StringName,
) -> void:
	match state:
		&"sealed":
			_db.set_component(entity_id, &"advertisements", {
				&"list": [{
					&"desire_type": &"openable",
					&"strength": 800,
					&"radius_px": 24,
					&"action": &"open",
					&"action_duration": 30,
				}],
			})
		&"open":
			_db.set_component(entity_id, &"advertisements", {
				&"list": [{
					&"desire_type": &"food",
					&"strength": 800,
					&"radius_px": 40,
					&"action": &"eat",
					&"action_duration": 50,
				}],
			})
		&"empty":
			_db.remove_component(entity_id, &"advertisements")


func _transition_box_ads(
	entity_id: int, state: StringName,
) -> void:
	match state:
		&"new":
			_db.set_component(entity_id, &"advertisements", {
				&"list": [
					{
						&"desire_type": &"comfort",
						&"strength": 700,
						&"radius_px": 32,
					},
					{
						&"desire_type": &"curiosity",
						&"strength": 500,
						&"radius_px": 40,
						&"action": &"shred",
						&"action_duration": 20,
					},
				],
			})
		&"worn":
			_db.set_component(entity_id, &"advertisements", {
				&"list": [
					{
						&"desire_type": &"comfort",
						&"strength": 400,
						&"radius_px": 24,
					},
					{
						&"desire_type": &"curiosity",
						&"strength": 300,
						&"radius_px": 32,
						&"action": &"shred",
						&"action_duration": 20,
					},
				],
			})
		&"scraps":
			_db.set_component(entity_id, &"advertisements", {
				&"list": [{
					&"desire_type": &"comfort",
					&"strength": 600,
					&"radius_px": 24,
				}],
			})


# Mirrors GameServer.damage_object / _box_state_for_hp
func _damage_object(entity_id: int, amount: int) -> void:
	var hp: Dictionary = _db.get_component(
		entity_id, &"object_hp",
	)
	var new_hp: int = maxi(0, hp[&"hp"] - amount)
	_db.set_component(
		entity_id, &"object_hp", {&"hp": new_hp},
	)
	var new_state: StringName = _box_state_for_hp(new_hp)
	var old: Dictionary = _db.get_component(
		entity_id, &"object_state",
	)
	if new_state != old[&"state"]:
		_transition_object(entity_id, new_state)


func _box_state_for_hp(hp: int) -> StringName:
	if hp <= 0:
		return &"scraps"
	if hp <= 500:
		return &"worn"
	return &"new"


# ── Tests ────────────────────────────────────────────────────

func test_hungry_cat_targets_open_can() -> void:
	# Cat with food=200 (hungry) near an open tuna can
	var can_id: int = _make_open_can(0, 10)
	var cat_id: int = _make_cat(0, 20, 200)

	_resolver.mark_dirty(cat_id)
	_resolver.evaluate_budget()

	var ai: Dictionary = _db.get_component(cat_id, &"ai_state")
	assert_eq(
		ai[&"state"], &"SEEKING",
		"Hungry cat near open can should transition to SEEKING",
	)
	var target: Dictionary = _db.get_component(
		cat_id, &"target",
	)
	assert_eq(
		target[&"entity_id"], can_id,
		"Cat should target the open tuna can",
	)


func test_fed_cat_ignores_open_can() -> void:
	# Cat with food=950 (satisfied) near an open tuna can
	_make_open_can(0, 10)
	var cat_id: int = _make_cat(0, 20, 950)

	_resolver.mark_dirty(cat_id)
	_resolver.evaluate_budget()

	var ai: Dictionary = _db.get_component(cat_id, &"ai_state")
	assert_eq(
		ai[&"meta_state"], &"AMBIENT",
		"Fed cat (food=950) must stay AMBIENT near open can",
	)


func test_food_not_scattered_passively() -> void:
	# Food desire must not increase from passive scatter;
	# it is action-only (in _ACTION_ONLY_DESIRES).
	_make_open_can(0, 10)
	var cat_id: int = _make_cat(0, 10, 200)

	# Manually replicate the scatter logic from GameServer.
	# _scatter_from_ads skips _ACTION_ONLY_DESIRES.
	var pos: Dictionary = _db.get_component(
		cat_id, &"position",
	)
	var nearby: Array[int] = _db.query_radius(
		pos[&"x"], pos[&"y"], (8 * Constants.SLOT_HEIGHT_PX),
	)
	var best: Dictionary = {}
	for other_id: int in nearby:
		if other_id == cat_id:
			continue
		if not _db.has_component(other_id, &"advertisements"):
			continue
		var ads: Dictionary = _db.get_component(
			other_id, &"advertisements",
		)
		var other_pos: Dictionary = _db.get_component(
			other_id, &"position",
		)
		var dist: int = (
			absi(pos[&"x"] - other_pos[&"x"])
			+ absi(pos[&"y"] - other_pos[&"y"])
		)
		for ad: Dictionary in ads[&"list"]:
			var radius_px: int = ad[&"radius_px"]
			if dist > radius_px:
				continue
			var dtype: StringName = ad[&"desire_type"]
			var strength: int = ad[&"strength"]
			if strength > best.get(dtype, 0):
				best[dtype] = strength

	# Apply, respecting action-only exclusion
	var action_only: Array[StringName] = [
		&"food", &"openable", &"scannable",
	]
	for dtype: StringName in best:
		if dtype in action_only:
			continue
		var desires: Dictionary = _db.get_component(
			cat_id, &"desires",
		)
		if not desires.has(dtype):
			continue
		var current: int = desires[dtype]
		_db.set_field(
			cat_id, &"desires", dtype,
			mini(1000, current + best[dtype]),
		)

	var desires: Dictionary = _db.get_component(
		cat_id, &"desires",
	)
	assert_eq(
		desires[&"food"], 200,
		"Food must not increase from passive scatter",
	)


# test_arm_scores_sealed_can_within_reach was deleted in the
# perception-channels migration. The arm doesn't go through the desire
# resolver in production — FoodSystem.tick_arms() finds nearby sealed
# cans by direct query and opens them. score_ad now correctly returns 0
# for action ads outside Constants.CHANNELS (e.g. `openable`), matching
# the architecture: channels are perceptual, action ads are state-loop
# consumed.


func test_arm_ignores_can_beyond_reach() -> void:
	# 5000 PU apart > ARM_REACH_PX (3 RU = 2100 PU).
	# The can's ad radius is 3 RU so score_ad returns 0
	# and the arm cannot target it.
	var arm_id: int = _make_arm(1000, 1000)
	var can_id: int = _make_sealed_can(6000, 1000)

	_resolver.mark_dirty(arm_id)
	_resolver.evaluate_budget()

	var target: Dictionary = _db.get_component(
		arm_id, &"target",
	)
	assert_ne(
		target[&"entity_id"], can_id,
		"Arm must not target can beyond reach",
	)


func test_object_state_transition_swaps_ads() -> void:
	# Create a sealed can, transition to open. Assert ads
	# changed from openable to food.
	# (Inline helper mirrors game_server logic)
	var can_id: int = _make_sealed_can(0, 1000)

	# Verify sealed ads
	var ads_before: Dictionary = _db.get_component(
		can_id, &"advertisements",
	)
	assert_eq(
		ads_before[&"list"][0][&"desire_type"], &"openable",
		"Sealed can should advertise openable",
	)

	_transition_object(can_id, &"open")

	var ads_after: Dictionary = _db.get_component(
		can_id, &"advertisements",
	)
	assert_eq(
		ads_after[&"list"][0][&"desire_type"], &"food",
		"Open can should advertise food",
	)
	assert_eq(
		ads_after[&"list"][0][&"radius_px"], 40,
		"Open can food ad radius should be 40 px (5 slot-heights)",
	)
	var state: Dictionary = _db.get_component(
		can_id, &"object_state",
	)
	assert_eq(
		state[&"state"], &"open",
		"Can state should be open",
	)


func test_box_damage_transitions_at_threshold() -> void:
	# Box starts at HP 1000 (new). Damage 600 -> HP 400
	# (worn). Damage 400 more -> HP 0 (scraps, comfort only).
	# (Inline helper mirrors game_server logic)
	var box_id: int = _make_box(0, 1000)

	# Verify initial state
	var state: Dictionary = _db.get_component(
		box_id, &"object_state",
	)
	assert_eq(
		state[&"state"], &"new",
		"Box should start as new",
	)

	# Damage by 600 -> HP 400 -> worn
	_damage_object(box_id, 600)
	state = _db.get_component(box_id, &"object_state")
	assert_eq(
		state[&"state"], &"worn",
		"Box at HP 400 should be worn",
	)
	var hp: Dictionary = _db.get_component(
		box_id, &"object_hp",
	)
	assert_eq(hp[&"hp"], 400, "HP should be 400 after 600 dmg")

	# Damage by 400 more -> HP 0 -> scraps
	_damage_object(box_id, 400)
	state = _db.get_component(box_id, &"object_state")
	assert_eq(
		state[&"state"], &"scraps",
		"Box at HP 0 should be scraps",
	)
	# Scraps have comfort-only ads
	var ads: Dictionary = _db.get_component(
		box_id, &"advertisements",
	)
	assert_eq(
		ads[&"list"].size(), 1,
		"Scraps should have exactly 1 ad",
	)
	assert_eq(
		ads[&"list"][0][&"desire_type"], &"comfort",
		"Scraps ad should be comfort-only",
	)
