extends GutTest

var _db: GameStateDB
var _resolver: DesireResolver
var _trackers: Dictionary = {}


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	_db = GameStateDB.new()
	_resolver = DesireResolver.new(_db)
	_trackers = {}


func _make_ferret(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {&"id": &"tcp_ferrets:ferret"})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"desires", {&"warmth": 800, &"comfort": 800, &"curiosity": 200})
	_db.set_component(id, &"personality", {
		&"warmth_weight": 400, &"comfort_weight": 600, &"curiosity_weight": 900,
	})
	_db.set_component(id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	_db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	_db.update_spatial(id, x, y)
	_trackers[id] = CuriosityTracker.new()
	return id


func _make_rack(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"advertisements", {&"list": [
		{&"desire_type": &"curiosity", &"strength": 300, &"radius_ru": 8,
			&"novelty_duration": 30, &"novelty_cooldown": 100},
	]})
	_db.update_spatial(id, x, y)
	return id


func test_ferret_seeks_curiosity_source():
	var ferret_id: int = _make_ferret(0, 1000)
	var rack_id: int = _make_rack(0, 0)
	_resolver.mark_dirty(ferret_id)
	_resolver.evaluate_budget(_trackers)
	var ai: Dictionary = _db.get_component(ferret_id, &"ai_state")
	var target: Dictionary = _db.get_component(ferret_id, &"target")
	assert_eq(ai[&"state"], &"SEEKING",
		"Ferret must transition to SEEKING toward curiosity source")
	assert_eq(target[&"entity_id"], rack_id,
		"Ferret must target the rack entity")


func test_visited_rack_scores_zero_ferret_picks_other():
	# Ferret at (0, 1500). rack_a at (0, 0), rack_b at (0, 700).
	# Both within perception radius (8 RU = 5600 pu). After visiting rack_a,
	# the ferret must target rack_b instead.
	var ferret_id: int = _make_ferret(0, 1500)
	var rack_a: int = _make_rack(0, 0)
	var rack_b: int = _make_rack(0, 700)
	# Pre-visit rack_a
	_trackers[ferret_id].visit(rack_a, 0)
	_db.advance_tick()
	_resolver.mark_dirty(ferret_id)
	_resolver.evaluate_budget(_trackers)
	var target: Dictionary = _db.get_component(ferret_id, &"target")
	assert_eq(target[&"entity_id"], rack_b,
		"Ferret must pick unvisited rack_b over recently-visited rack_a")


func test_ferret_prefers_novel_object_over_rack():
	var ferret_id: int = _make_ferret(0, 2000)
	var rack_id: int = _make_rack(0, 0)
	# Novel pillow — higher strength, never visited
	var pillow_id: int = _db.create_entity()
	_db.set_component(pillow_id, &"position", {&"x": 0, &"y": 1000})
	_db.set_component(pillow_id, &"advertisements", {&"list": [
		{&"desire_type": &"curiosity", &"strength": 500, &"radius_ru": 8,
			&"novelty_duration": 500, &"novelty_cooldown": 200},
	]})
	_db.update_spatial(pillow_id, 0, 1000)
	_resolver.mark_dirty(ferret_id)
	_resolver.evaluate_budget(_trackers)
	var target: Dictionary = _db.get_component(ferret_id, &"target")
	assert_eq(target[&"entity_id"], pillow_id,
		"Ferret must prefer novel high-strength pillow over rack")


func test_cat_ignores_curiosity_ads():
	var cat_id: int = _db.create_entity()
	_db.set_component(cat_id, &"species", {&"id": &"tcp_cats:cat"})
	_db.set_component(cat_id, &"position", {&"x": 0, &"y": 2000})
	_db.set_component(cat_id, &"desires", {&"warmth": 800, &"comfort": 800, &"curiosity": 1000})
	_db.set_component(cat_id, &"personality", {
		&"warmth_weight": 800, &"comfort_weight": 600, &"curiosity_weight": 100,
	})
	_db.set_component(cat_id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	_db.set_component(cat_id, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	_db.update_spatial(cat_id, 0, 2000)
	_make_rack(0, 0)
	_resolver.mark_dirty(cat_id)
	_resolver.evaluate_budget()
	var ai: Dictionary = _db.get_component(cat_id, &"ai_state")
	assert_eq(ai[&"meta_state"], &"AMBIENT",
		"Cat with curiosity=1000 must stay AMBIENT, not seek curiosity source")
