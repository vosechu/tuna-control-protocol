extends GutTest

var _db: GameStateDB
var _resolver: DesireResolver


func before_each() -> void:
	_db = GameStateDB.new()
	_resolver = DesireResolver.new(_db)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_cat(x: int, y: int, warmth: int, warmth_weight: int = 500) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {&"id": &"tcp_base:cat"})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"desires", {
		&"warmth": warmth, &"comfort": 800, &"curiosity": 1000,
	})
	_db.set_component(id, &"personality", {
		&"warmth_weight": warmth_weight,
		&"comfort_weight": 600,
		&"curiosity_weight": 100,
	})
	_db.set_component(id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	_db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	_db.update_spatial(id, x, y)
	return id


func _make_warm_server(x: int, y: int, strength: int = 800, radius_ru: int = 3) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"advertisements", {&"list": [
		{&"desire_type": &"warmth", &"strength": strength, &"radius_ru": radius_ru, &"max_occupants": 1}
	]})
	_db.update_spatial(id, x, y)
	return id


func _make_ferret(x: int, y: int, curiosity: int, curiosity_weight: int = 900) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {&"id": &"tcp_base:ferret"})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"desires", {&"warmth": 800, &"comfort": 800, &"curiosity": curiosity})
	_db.set_component(id, &"personality", {
		&"warmth_weight": 400, &"comfort_weight": 600, &"curiosity_weight": curiosity_weight,
	})
	_db.set_component(id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	_db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID, &"entity_id": Constants.INVALID_ID,
	})
	_db.update_spatial(id, x, y)
	return id


func _make_curiosity_source(
	x: int,
	y: int,
	strength: int = 300,
	radius_ru: int = 8,
	novelty_duration: int = 30,
	novelty_cooldown: int = 100,
) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"advertisements", {&"list": [
		{&"desire_type": &"curiosity", &"strength": strength,
			&"radius_ru": radius_ru,
			&"novelty_duration": novelty_duration,
			&"novelty_cooldown": novelty_cooldown},
	]})
	_db.update_spatial(id, x, y)
	return id


# ── score_ad: basic scoring ───────────────────────────────────────────────────

func test_cold_cat_scores_warm_server_positively():
	# warmth=200 (deprived/cold), weight=500, strength=800;
	# same position -> no distance penalty
	var cat_id: int = _make_cat(0, 0, 200)
	var server_id: int = _make_warm_server(0, 0)
	var ad: Dictionary = {
		&"desire_type": &"warmth", &"strength": 800,
		&"radius_ru": 3, &"max_occupants": 1,
	}
	var score: int = _resolver.score_ad(cat_id, server_id, ad)
	assert_gt(
		score, 0,
		"Cold cat (warmth=200) must score a warm server positively, got %d" % score,
	)


func test_warm_cat_scores_server_very_low():
	# warmth=900 (satisfied/warm), weight=500, strength=800
	var cat_id: int = _make_cat(0, 0, 900)
	var server_id: int = _make_warm_server(0, 0)
	var ad: Dictionary = {
		&"desire_type": &"warmth", &"strength": 800,
		&"radius_ru": 3, &"max_occupants": 1,
	}
	var score: int = _resolver.score_ad(cat_id, server_id, ad)
	assert_lt(
		score, 50,
		"Warm cat (warmth=900) must score server very low, got %d" % score,
	)


func test_out_of_radius_scores_zero():
	# Server at 0,0 with radius_ru=3 (3 * 700 = 2100 pu)
	# Cat at 0, 8000 — beyond radius
	var cat_id: int = _make_cat(0, 8000, 100)
	var server_id: int = _make_warm_server(0, 0, 800, 3)
	var ad: Dictionary = {
		&"desire_type": &"warmth", &"strength": 800,
		&"radius_ru": 3, &"max_occupants": 1,
	}
	var score: int = _resolver.score_ad(cat_id, server_id, ad)
	assert_eq(
		score, 0,
		"Entity beyond advertisement radius must score 0, got %d" % score,
	)


func test_higher_personality_weight_produces_higher_score():
	var cat_low_weight: int = _make_cat(0, 0, 200, 200)
	var cat_high_weight: int = _make_cat(0, 0, 200, 900)
	var server_id: int = _make_warm_server(0, 0)
	var ad: Dictionary = {
		&"desire_type": &"warmth", &"strength": 800,
		&"radius_ru": 3, &"max_occupants": 1,
	}
	var score_low: int = _resolver.score_ad(cat_low_weight, server_id, ad)
	var score_high: int = _resolver.score_ad(cat_high_weight, server_id, ad)
	assert_gt(
		score_high, score_low,
		"Higher personality weight (%d) must produce higher score than lower (%d)"
			% [score_high, score_low],
	)


func test_score_decreases_with_distance():
	# Cat at edge of radius should score lower than cat at center
	var radius_ru: int = 3
	var radius_pu: int = Constants.ru_to_pu(radius_ru)
	var cat_near: int = _make_cat(0, 0, 200)
	var cat_far: int = _make_cat(0, radius_pu - 1, 200)
	var server_id: int = _make_warm_server(0, 0, 800, radius_ru)
	var ad: Dictionary = {
		&"desire_type": &"warmth", &"strength": 800,
		&"radius_ru": radius_ru, &"max_occupants": 1,
	}
	var score_near: int = _resolver.score_ad(cat_near, server_id, ad)
	var score_far: int = _resolver.score_ad(cat_far, server_id, ad)
	assert_gt(
		score_near, score_far,
		"Closer entity must score higher (%d) than farther entity (%d)"
			% [score_near, score_far],
	)


# ── evaluate_budget: state transitions ───────────────────────────────────────

func test_evaluate_budget_transitions_cold_cat_to_seeking_toward_server():
	# Cat at origin, cold (warmth=100). Server at same position. After
	# evaluate_budget the cat must be GOAL_DIRECTED/SEEKING with the
	# server as its target. State + target are coupled — one test.
	var cat_id: int = _make_cat(0, 0, 100)
	var server_id: int = _make_warm_server(0, 0)
	_resolver.mark_dirty(cat_id)
	_resolver.evaluate_budget()
	var ai_state: Dictionary = _db.get_component(cat_id, &"ai_state")
	var target: Dictionary = _db.get_component(cat_id, &"target")
	assert_eq(ai_state[&"meta_state"], &"GOAL_DIRECTED",
		"Cold cat near warm server must transition to GOAL_DIRECTED, got %s" % ai_state[&"meta_state"])
	assert_eq(ai_state[&"state"], &"SEEKING",
		"Cold cat near warm server must transition to SEEKING, got %s" % ai_state[&"state"])
	assert_eq(target[&"entity_id"], server_id,
		"Target entity_id must be the server id (%d), got %d" % [server_id, target[&"entity_id"]])


func test_evaluate_budget_does_not_transition_if_score_below_threshold():
	# Warm cat (warmth=950) near a weak server should not transition
	var cat_id: int = _make_cat(0, 0, 950)
	# Very weak advertisement — max possible score will be well below SWITCH_THRESHOLD
	var server_id: int = _make_warm_server(0, 0, 100, 3)
	_resolver.mark_dirty(cat_id)
	_resolver.evaluate_budget()
	var ai_state: Dictionary = _db.get_component(cat_id, &"ai_state")
	assert_eq(ai_state[&"meta_state"], &"AMBIENT",
		"Satisfied cat must remain AMBIENT, got %s" % ai_state[&"meta_state"])


func test_evaluate_budget_does_not_transition_if_score_below_commitment_plus_threshold():
	# Cat with high commitment should not switch to a lower-scoring target
	var cat_id: int = _make_cat(0, 0, 200)
	var server_id: int = _make_warm_server(0, 0, 400, 3)
	# Pre-set a high commitment score so any ad will lose
	_db.set_component(cat_id, &"ai_state", {
		&"state": &"SEEKING",
		&"meta_state": &"GOAL_DIRECTED",
		&"commitment_score": 900
	})
	_resolver.mark_dirty(cat_id)
	_resolver.evaluate_budget()
	var ai_state: Dictionary = _db.get_component(cat_id, &"ai_state")
	assert_eq(
		ai_state[&"commitment_score"], 900,
		"Commitment score must remain 900 when no better option found, got %d"
			% ai_state[&"commitment_score"],
	)


# ── dirty set management ──────────────────────────────────────────────────────

func test_mark_dirty_dedupes_and_evaluate_drains():
	# Two properties of the dirty set, exercised in one flow so a
	# mutation to dirty_count() shows up as a single test failure:
	#   1. mark_dirty is idempotent — 3 calls → 1 entry
	#   2. evaluate_budget drains the set — post-call → 0 entries
	var cat_id: int = _make_cat(0, 0, 100)
	_make_warm_server(0, 0)  # so evaluate_one has something to score
	_resolver.mark_dirty(cat_id)
	_resolver.mark_dirty(cat_id)
	_resolver.mark_dirty(cat_id)
	assert_eq(_resolver.dirty_count(), 1,
		"mark_dirty must dedupe — 3× on same entity should leave dirty_count() == 1")
	_resolver.evaluate_budget()
	assert_eq(_resolver.dirty_count(), 0,
		"evaluate_budget must drain the dirty set")


# ── _pop_highest_deficit: priority ordering ───────────────────────────────────

func test_pop_highest_deficit_picks_most_desperate_first():
	# pop_highest_deficit returns the dirty entity whose lowest desire
	# satisfaction is the smallest (i.e. highest deficit). Tested directly
	# against pop_highest_deficit — no scoring, no server, no evaluation.
	var cold_cat_id: int = _make_cat(0, 0, 50)   # warmth 50 = most desperate
	var mild_cat_id: int = _make_cat(0, 0, 500)
	var warm_cat_id: int = _make_cat(0, 0, 900)  # warmth 900 = least desperate
	_resolver.mark_dirty(mild_cat_id)
	_resolver.mark_dirty(cold_cat_id)
	_resolver.mark_dirty(warm_cat_id)
	assert_eq(_resolver.pop_highest_deficit(), cold_cat_id,
		"Cold cat (warmth=50) must be popped first — highest deficit")
	assert_eq(_resolver.pop_highest_deficit(), mild_cat_id,
		"Mild cat (warmth=500) must be popped second")
	assert_eq(_resolver.pop_highest_deficit(), warm_cat_id,
		"Warm cat (warmth=900) must be popped last — lowest deficit")
	assert_eq(_resolver.pop_highest_deficit(), Constants.INVALID_ID,
		"After draining, pop must return INVALID_ID")


# ── Curiosity + CuriosityTracker integration ─────────────────────────────────

func test_curious_ferret_scores_curiosity_ad_positively():
	var ferret_id: int = _make_ferret(0, 0, 200)
	var rack_id: int = _make_curiosity_source(0, 0)
	var ad: Dictionary = {
		&"desire_type": &"curiosity", &"strength": 300, &"radius_ru": 8,
		&"novelty_duration": 30, &"novelty_cooldown": 100,
	}
	var score: int = _resolver.score_ad(ferret_id, rack_id, ad)
	assert_gt(score, 0,
		"Curious ferret (curiosity=200) must score curiosity ad positively, got %d" % score)


func test_curiosity_ad_scores_zero_when_recently_visited():
	var ferret_id: int = _make_ferret(0, 0, 200)
	var rack_id: int = _make_curiosity_source(0, 0, 300, 8, 30, 100)
	var tracker: CuriosityTracker = CuriosityTracker.new()
	tracker.visit(rack_id, 0)
	var ad: Dictionary = {
		&"desire_type": &"curiosity", &"strength": 300, &"radius_ru": 8,
		&"novelty_duration": 30, &"novelty_cooldown": 100,
	}
	var score: int = _resolver.score_ad(ferret_id, rack_id, ad, tracker, 50)
	assert_eq(score, 0,
		"Recently visited curiosity ad must score 0, got %d" % score)


func test_curiosity_ad_scores_normally_after_cooldown():
	var ferret_id: int = _make_ferret(0, 0, 200)
	var rack_id: int = _make_curiosity_source(0, 0, 300, 8, 30, 100)
	var tracker: CuriosityTracker = CuriosityTracker.new()
	tracker.visit(rack_id, 0)
	var ad: Dictionary = {
		&"desire_type": &"curiosity", &"strength": 300, &"radius_ru": 8,
		&"novelty_duration": 30, &"novelty_cooldown": 100,
	}
	var score: int = _resolver.score_ad(ferret_id, rack_id, ad, tracker, 101)
	assert_gt(score, 0,
		"Curiosity ad must score positively after cooldown expires, got %d" % score)


func test_satisfied_cat_scores_curiosity_at_zero():
	var cat_id: int = _make_cat(0, 0, 800, 500)
	var rack_id: int = _make_curiosity_source(0, 0)
	var ad: Dictionary = {
		&"desire_type": &"curiosity", &"strength": 300, &"radius_ru": 8,
		&"novelty_duration": 30, &"novelty_cooldown": 100,
	}
	var score: int = _resolver.score_ad(cat_id, rack_id, ad)
	assert_eq(score, 0,
		"Cat with curiosity=1000 (satisfied) scores 0 — zero deficit")


func test_evaluate_budget_honors_trackers_dict():
	# Verifies evaluate_budget threads the trackers dict through to
	# score_ad. A ferret next to a recently-visited curiosity source
	# must NOT transition — proving the tracker was consulted and
	# scored the ad at 0. This test deliberately asserts on the
	# non-transition path so it does not duplicate the "SEEKING
	# transition" coverage from test_evaluate_budget_transitions_...
	var ferret_id: int = _make_ferret(0, 0, 200)
	var rack_id: int = _make_curiosity_source(0, 0, 300, 8, 30, 100)
	var tracker: CuriosityTracker = CuriosityTracker.new()
	tracker.visit(rack_id, 0)  # mark rack as recently visited
	var trackers: Dictionary = {ferret_id: tracker}
	_resolver.mark_dirty(ferret_id)
	_resolver.evaluate_budget(trackers)
	var ai_state: Dictionary = _db.get_component(ferret_id, &"ai_state")
	assert_ne(ai_state[&"state"], &"SEEKING",
		"Ferret must not transition to SEEKING — recently-visited rack scored 0 by tracker")


