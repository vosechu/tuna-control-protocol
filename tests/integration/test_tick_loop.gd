extends GutTest

var _db: GameStateDB
var _heat_grid: HeatGrid
var _resolver: DesireResolver


func before_each() -> void:
	_db = GameStateDB.new()
	_heat_grid = HeatGrid.new(_db)
	_resolver = DesireResolver.new(_db)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_animal(x: int, y: int, warmth_weight: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {
		&"id": &"tcp_cats:cat", &"variant": &"cat01", &"name": &"Test",
	})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"desires", {&"warmth": 200, &"comfort": 800, &"curiosity": 1000})
	_db.set_component(id, &"personality", {
		&"warmth_weight": warmth_weight, &"comfort_weight": 600, &"curiosity_weight": 100,
	})
	_db.set_component(id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	_db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	_db.update_spatial(id, x, y)
	return id


func _make_ad_object(x: int, y: int, desire_type: StringName, strength: int, radius_ru: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"advertisements", {&"list": [
		{&"desire_type": desire_type, &"strength": strength, &"radius_ru": radius_ru, &"max_occupants": 1}
	]})
	_db.update_spatial(id, x, y)
	return id


# NOTE: Reimplements commitment decay from game_server._decay_commitment
# because GameServer requires a scene tree we cannot instantiate in
# integration tests. If _decay_commitment changes, this must be updated.
func _decay_commitment_once(entity_id: int) -> void:
	var ai: Dictionary = _db.get_component(entity_id, &"ai_state")
	var commitment: int = ai[&"commitment_score"]
	if commitment > 0:
		_db.set_component(entity_id, &"ai_state", {
			&"state": ai[&"state"],
			&"meta_state": ai[&"meta_state"],
			&"commitment_score": maxi(0, commitment - 1),
		})


# ── Tests ─────────────────────────────────────────────────────────────────────

func test_commitment_decays_over_ticks() -> void:
	var cat: int = _make_animal(0, 0, 800)
	# Set high commitment as if cat just chose a target
	_db.set_component(cat, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 200,
	})
	# Decay 50 ticks
	for _tick: int in 50:
		_decay_commitment_once(cat)
	var ai: Dictionary = _db.get_component(cat, &"ai_state")
	assert_eq(ai[&"commitment_score"], 150, "Should decay by 1/tick: 200 - 50 = 150")


func test_commitment_prevents_premature_transition() -> void:
	var cat: int = _make_animal(0, 0, 800)
	# Cat has high commitment from previous choice
	_db.set_component(cat, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 300,
	})
	# Weak ad nearby — score will be less than 300 + 150 = 450
	_make_ad_object(2400, 0, &"warmth", 400, 8)

	_resolver.mark_dirty(cat)
	_resolver.evaluate_budget()

	var ai: Dictionary = _db.get_component(cat, &"ai_state")
	assert_eq(ai[&"state"], &"IDLE",
		"Cat should NOT transition — ad score too low vs commitment + threshold")


func test_commitment_eventually_allows_transition() -> void:
	var cat: int = _make_animal(0, 0, 800)
	_make_ad_object(2400, 0, &"warmth", 800, 8)
	# Cat has moderate commitment that will decay
	_db.set_component(cat, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 200,
	})

	# Decay commitment over many ticks until resolver can transition
	var transitioned: bool = false
	for _tick: int in 300:
		_decay_commitment_once(cat)
		_resolver.mark_dirty(cat)
		_resolver.evaluate_budget()
		var ai: Dictionary = _db.get_component(cat, &"ai_state")
		if ai[&"state"] == &"SEEKING":
			transitioned = true
			break

	assert_true(transitioned,
		"Cat should eventually transition once commitment decays enough")


func test_commitment_floors_at_zero() -> void:
	var cat: int = _make_animal(0, 0, 800)
	_db.set_component(cat, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 5,
	})
	for _tick: int in 20:
		_decay_commitment_once(cat)
	var ai: Dictionary = _db.get_component(cat, &"ai_state")
	assert_eq(ai[&"commitment_score"], 0, "Commitment should not go below 0")
