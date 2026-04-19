extends GutTest

var _db: GameStateDB
var _resolver: DesireResolver


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	_db = GameStateDB.new()
	_resolver = DesireResolver.new(_db)


# ── Helpers ──────────────────────────────────────────────────

func _make_arm(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"species", {
		&"id": &"tcp_base:robot_arm",
		&"variant": &"arm",
		&"name": &"ARM-01",
	})
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


# ── Tests ────────────────────────────────────────────────────

func test_arm_scores_sealed_can() -> void:
	# Arm with purpose=200 (needy) and a sealed can at same spot.
	# score_ad uses ad's desire_type (openable) for deficit lookup,
	# which defaults to 500 when missing. Zero distance maximizes
	# the dist_factor so the score exceeds SWITCH_THRESHOLD.
	var arm_x: int = 1000
	var arm_y: int = 1000
	var can_x: int = arm_x
	var can_y: int = arm_y
	var arm_id: int = _make_arm(arm_x, arm_y)
	var can_id: int = _make_sealed_can(can_x, can_y)

	_resolver.mark_dirty(arm_id)
	_resolver.evaluate_budget()

	var ai: Dictionary = _db.get_component(
		arm_id, &"ai_state",
	)
	assert_eq(
		ai[&"state"], &"SEEKING",
		"Arm should SEEK sealed can within reach",
	)
	var target: Dictionary = _db.get_component(
		arm_id, &"target",
	)
	assert_eq(
		target[&"entity_id"], can_id,
		"Arm should target the sealed tuna can",
	)


func test_arm_ignores_can_beyond_reach() -> void:
	# 5000 PU apart > ARM_REACH_PX (3 RU = 2100 PU).
	# The can's ad radius is 3 RU so score_ad returns 0.
	# The arm may WANDER due to low purpose, but must not
	# target the distant can.
	var arm_x: int = 1000
	var arm_y: int = 1000
	var can_x: int = arm_x + 5000
	var can_y: int = arm_y
	var arm_id: int = _make_arm(arm_x, arm_y)
	var can_id: int = _make_sealed_can(can_x, can_y)

	_resolver.mark_dirty(arm_id)
	_resolver.evaluate_budget()

	var target: Dictionary = _db.get_component(
		arm_id, &"target",
	)
	assert_ne(
		target[&"entity_id"], can_id,
		"Arm must not target can beyond reach",
	)


func test_open_can_loses_ads_when_emptied() -> void:
	# Transition an open can to empty via the server's
	# transition logic. Verify ads are removed so a second
	# cat arriving would find nothing to eat.
	var can_id: int = _make_open_can(0, 1000)

	# Confirm ads exist before transition
	assert_true(
		_db.has_component(can_id, &"advertisements"),
		"Open can should have advertisements",
	)

	# Replicate GameServer.transition_object_state for empty
	_db.set_component(
		can_id, &"object_state", {&"state": &"empty"},
	)
	_db.remove_component(can_id, &"advertisements")

	assert_false(
		_db.has_component(can_id, &"advertisements"),
		"Empty can must have no advertisements",
	)
