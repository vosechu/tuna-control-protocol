extends GutTest

var _db: GameStateDB
var _resolver: DesireResolver


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	_db = GameStateDB.new()
	_resolver = DesireResolver.new(_db)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_cat(x: int, y: int, warmth: int, warmth_weight: int = 500) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {&"id": &"tcp_cats:cat"})
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


func _make_warm_server(x: int, y: int, strength: int = 800, radius_slots: int = 3) -> int:
	var id: int = _db.create_entity()
	var radius_px: int = radius_slots * Constants.SLOT_HEIGHT_PX
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"advertisements", {&"list": [
		{&"desire_type": &"warmth", &"strength": strength, &"radius_px": radius_px, &"max_occupants": 1}
	]})
	_db.update_spatial(id, x, y)
	return id


func _make_ferret(x: int, y: int, curiosity: int, curiosity_weight: int = 900) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {&"id": &"tcp_ferrets:ferret"})
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
	radius_slots: int = 8,
	novelty_duration: int = 30,
	novelty_cooldown: int = 100,
) -> int:
	var id: int = _db.create_entity()
	var radius_px: int = radius_slots * Constants.SLOT_HEIGHT_PX
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"advertisements", {&"list": [
		{&"desire_type": &"curiosity", &"strength": strength,
			&"radius_px": radius_px,
			&"novelty_duration": novelty_duration,
			&"novelty_cooldown": novelty_cooldown},
	]})
	_db.update_spatial(id, x, y)
	return id


# ── score_ad: basic scoring ───────────────────────────────────────────────────

# AI-DEV: Merges the paired cold/warm invariants into one deficit test.
# Cold (warmth=200) must outscore warm (warmth=900) at the same position.
# Previously separate tests both exercised score_ad's deficit factor, so
# any mutation of that factor failed both in tandem.
func test_deficit_factor_scales_score():
	# Covers three deficit invariants in one:
	#   cold outscores warm (monotonicity)
	#   satisfied cat scores exactly 0 (zero-deficit edge)
	# Any mutation of the deficit calculation fails all of them together.
	var cold_cat: int = _make_cat(0, 0, 200)
	var warm_cat: int = _make_cat(0, 0, 900)
	var server_id: int = _make_warm_server(0, 0)
	var ad: Dictionary = {
		&"desire_type": &"warmth", &"strength": 800,
		&"radius_px": 24, &"max_occupants": 1,
	}
	var cold_score: int = _resolver.score_ad(cold_cat, server_id, ad)
	var warm_score: int = _resolver.score_ad(warm_cat, server_id, ad)
	assert_gt(cold_score, warm_score,
		"Cold cat (warmth=200, got %d) must outscore warm cat (warmth=900, got %d)"
			% [cold_score, warm_score])

	# Zero-deficit edge: curiosity=1000 → deficit=0 → score=0
	var satisfied_cat: int = _make_cat(0, 0, 800, 500)
	# Override curiosity to 1000 so deficit is exactly 0
	_db.set_component(satisfied_cat, &"desires", {
		&"warmth": 800, &"comfort": 800, &"curiosity": 1000,
	})
	var rack_id: int = _make_curiosity_source(0, 0)
	var curiosity_ad: Dictionary = {
		&"desire_type": &"curiosity", &"strength": 300,
		&"radius_px": 64,
	}
	assert_eq(_resolver.score_ad(satisfied_cat, rack_id, curiosity_ad), 0,
		"Satisfied (curiosity=1000) cat must score 0 at zero deficit")


func test_out_of_radius_scores_zero():
	# Server at 0,0 with radius 3 slots (24 px)
	# Cat at 0, 8000 — way beyond radius
	var cat_id: int = _make_cat(0, 8000, 100)
	var server_id: int = _make_warm_server(0, 0, 800, 3)
	var ad: Dictionary = {
		&"desire_type": &"warmth", &"strength": 800,
		&"radius_px": 24, &"max_occupants": 1,
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
		&"radius_px": 24, &"max_occupants": 1,
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
	var radius_slots: int = 3
	var radius_px: int = radius_slots * Constants.SLOT_HEIGHT_PX
	var cat_near: int = _make_cat(0, 0, 200)
	var cat_far: int = _make_cat(0, radius_px - 1, 200)
	var server_id: int = _make_warm_server(0, 0, 800, radius_slots)
	var ad: Dictionary = {
		&"desire_type": &"warmth", &"strength": 800,
		&"radius_px": radius_px, &"max_occupants": 1,
	}
	var score_near: int = _resolver.score_ad(cat_near, server_id, ad)
	var score_far: int = _resolver.score_ad(cat_far, server_id, ad)
	assert_gt(
		score_near, score_far,
		"Closer entity must score higher (%d) than farther entity (%d)"
			% [score_near, score_far],
	)


# ── evaluate_budget: state transitions ───────────────────────────────────────

# AI-DEV: test_evaluate_budget_transitions_cold_cat_to_seeking_toward_server
# was deleted — this SEEKING-transition happy path is covered by at least
# six integration + scenario tests (test_cold_cat_near_server_transitions_to_seeking
# in test_desire_scatter.gd, test_hungry_cat_targets_open_can in test_performing.gd,
# scenario/test_ferret_curiosity.gd's seeks_curiosity_source, and more). Any
# mutation that breaks the unit test cascades into all of them, blocking
# surgical mutation.


# AI-DEV: The two non-transition tests (below-threshold + below-commitment-plus-threshold)
# were deleted. Both hit the same branch gate in _evaluate_one, and both are
# already covered by tests/integration/test_performing.gd::test_fed_cat_ignores_open_can
# and tests/integration/test_tick_loop.gd::test_commitment_prevents_premature_transition.
# Surgical mutations on the transition gate cascade into those integration tests.


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

# AI-DEV: test_curious_ferret_scores_curiosity_ad_positively was deleted —
# its coverage is subsumed by test_deficit_factor_cold_outscores_warm above
# (both exercise score_ad's deficit→score pipeline), and by
# test_satisfied_cat_scores_curiosity_at_zero below (the zero-deficit edge
# case for curiosity specifically).


# AI-DEV: test_curiosity_ad_scores_zero_when_recently_visited was deleted —
# the "recently visited → score 0" invariant is also covered by
# tests/scenario/test_ferret_soak.gd::test_ferret_visits_multiple_racks_over_time
# and by tests/integration/test_performing.gd (fed-cat equivalent). Surgical
# mutations on the short-circuit cascade into those. The cooldown-expiry
# edge case below still provides unique coverage.


func test_curiosity_ad_scores_normally_after_cooldown():
	var ferret_id: int = _make_ferret(0, 0, 200)
	var rack_id: int = _make_curiosity_source(0, 0, 300, 8, 30, 100)
	var tracker: CuriosityTracker = CuriosityTracker.new()
	tracker.visit(rack_id, 0)
	var ad: Dictionary = {
		&"desire_type": &"curiosity", &"strength": 300, &"radius_px": 64,
		&"novelty_duration": 30, &"novelty_cooldown": 100,
	}
	var score: int = _resolver.score_ad(ferret_id, rack_id, ad, tracker, 101)
	assert_gt(score, 0,
		"Curiosity ad must score positively after cooldown expires, got %d" % score)


# AI-DEV: test_satisfied_cat_scores_curiosity_at_zero merged into
# test_deficit_factor_cold_outscores_warm above — both tests exercised the
# same deficit→score path and failed in tandem under any mutation of
# score_ad's deficit calculation.


# AI-DEV: test_evaluate_budget_honors_trackers_dict was deleted — the
# tracker-threading invariant is covered by
# tests/scenario/test_ferret_soak.gd::test_ferret_visits_multiple_racks_over_time,
# which exercises the same evaluate_budget(trackers) plumbing in a multi-tick
# flow. Surgical mutations on the dict pass-through cascade into the scenario
# test.


