extends GutTest

# Golden-path scenario: server with a box "on top", a HUM device in range,
# and a cat that wants both warmth and comfort. Exercises the full
# contentment → purr → HUM charge chain in the same order game_server.gd
# runs it, bypassing only the movement + nav portions.
#
# Scenario tests live outside tests/unit/ and are not stamped — see
# script/checks/verify_tests. The integration layer is covered here; the
# individual hops (Contentment, ContentmentPurrBridge, HumSystem,
# DesireScatter) have their own stamped unit tests under tests/unit/.
#
# Two tests — one per phase of the chain:
#   1. The cat wants to go there (resolver picks the cluster as a target).
#   2. Once there, the full chain fires end-to-end: warmth & comfort rise
#      past the Contentment threshold, is_satisfied flips, the bridge
#      writes purr.intensity, and HumSystem.tick_charge lifts the reserve.
#
# KNOWN GAP (2026-04-19): the synthetic chain here passes, but an actual
# game boot does not converge to a purring cat. The gap is somewhere
# upstream of scatter — likely in movement, arrival, or in the gameserver
# path that differs from this test's direct system wiring. This test
# stays as a regression harness for the satisfaction half of the chain.

var _db: GameStateDB
var _resolver: DesireResolver
var _scatter: DesireScatter
var _contentment: Contentment
var _purr_bridge: ContentmentPurrBridge
var _hum: HumSystem


func before_each() -> void:
	_db = GameStateDB.new()
	_resolver = DesireResolver.new(_db)
	_scatter = DesireScatter.new(_db)
	_contentment = Contentment.new(_db)
	_purr_bridge = ContentmentPurrBridge.new(_db)
	_hum = HumSystem.new(_db, null)


# ── Helpers ─────────────────────────────────────────────────

func _place_server(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"object_type", {&"type": &"server_1u"})
	_db.set_component(id, &"advertisements", {&"list": [{
		&"desire_type": &"warmth",
		&"strength": 800,
		&"radius_px": 64,
		&"max_occupants": 1,
	}]})
	_db.update_spatial(id, x, y)
	return id


func _place_box(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"object_type", {&"type": &"cardboard_box"})
	_db.set_component(id, &"advertisements", {&"list": [
		{&"desire_type": &"comfort", &"strength": 700, &"radius_px": 32},
		{
			&"desire_type": &"curiosity", &"strength": 500,
			&"radius_px": 40, &"action": &"shred",
		},
	]})
	_db.update_spatial(id, x, y)
	return id


func _place_hum(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"hum_receiver", {})
	_db.set_component(id, &"physical", {&"mass": 20000, &"size_ru": 6})
	_db.set_component(id, &"hum", {&"reserve": 0, &"capacity": 10000})
	_db.update_spatial(id, x, y)
	return id


func _spawn_cat(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"species", {
		&"id": &"tcp_cats:cat",
		&"variant": &"cat01",
		&"name": &"Mochi",
	})
	_db.set_component(id, &"desires", {
		&"warmth": 0,
		&"comfort": 0,
		&"hunger": 500,
		&"attention": 200,
		&"curiosity": 200,
	})
	_db.set_component(id, &"personality", {
		&"warmth_weight": 700,
		&"comfort_weight": 700,
		&"hunger_weight": 700,
		&"attention_weight": 500,
		&"curiosity_weight": 150,
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
	_db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
	_db.set_component(id, &"purr_config", {
		&"rate_when_satisfied": Constants.UNIT, &"base_radius_ru": 6,
	})
	_db.update_spatial(id, x, y)
	return id


func _tick_satisfaction_chain() -> void:
	_scatter.scatter_from_ads()
	_db.clamp_all(&"desires", &"warmth", 0, 1000)
	_db.clamp_all(&"desires", &"comfort", 0, 1000)
	_contentment.evaluate_all()
	_purr_bridge.tick()
	_hum.tick_charge()


# ── Tests ───────────────────────────────────────────────────

func test_cat_seeks_the_cluster() -> void:
	var site_x: int = 10000
	var site_y: int = 5000
	var server_id: int = _place_server(site_x, site_y)
	var box_id: int = _place_box(site_x, site_y)
	_place_hum(site_x, site_y)
	var cat_id: int = _spawn_cat(site_x + (3 * Constants.SLOT_HEIGHT_PX), site_y)

	_resolver.mark_dirty(cat_id)
	_resolver.evaluate_budget()

	var ai: Dictionary = _db.get_component(cat_id, &"ai_state")
	assert_eq(
		ai[&"state"], &"SEEKING",
		"Cat should SEEK the cluster; got %s" % ai[&"state"],
	)

	var target: Dictionary = _db.get_component(cat_id, &"target")
	var targeted: int = target[&"entity_id"]
	assert_true(
		targeted == server_id or targeted == box_id,
		"Cat should target server or box; got %d (server=%d box=%d)"
			% [targeted, server_id, box_id],
	)


func test_satisfied_cat_purrs_and_charges_hum() -> void:
	var site_x: int = 10000
	var site_y: int = 5000
	_place_server(site_x, site_y)
	_place_box(site_x, site_y)
	var hum_id: int = _place_hum(site_x, site_y)
	var cat_id: int = _spawn_cat(site_x, site_y)

	var baseline_reserve: int = _hum.get_reserve(hum_id)

	for _i in 20:
		_tick_satisfaction_chain()

	# Hop A: scatter raised both deprived bars.
	var desires: Dictionary = _db.get_component(cat_id, &"desires")
	assert_gt(
		desires[&"warmth"], Contentment.THRESHOLD,
		"HOP A (scatter): warmth should exceed THRESHOLD(%d); got %d"
			% [Contentment.THRESHOLD, desires[&"warmth"]],
	)
	assert_gt(
		desires[&"comfort"], Contentment.THRESHOLD,
		"HOP A (scatter): comfort should exceed THRESHOLD(%d); got %d"
			% [Contentment.THRESHOLD, desires[&"comfort"]],
	)

	# Hop B: 3-of-4 contentment rule flips is_satisfied.
	var cont: Dictionary = _db.get_component(cat_id, &"contentment")
	assert_eq(
		cont[&"is_satisfied"], 1,
		"HOP B (contentment): is_satisfied should be 1 with 3/4 bars met",
	)

	# Hop C: contentment_purr_bridge writes rate_when_satisfied.
	var purr: Dictionary = _db.get_component(cat_id, &"purr")
	assert_gt(
		purr[&"intensity"], 0,
		"HOP C (purr bridge): intensity should be >0 once satisfied; got %d"
			% purr[&"intensity"],
	)

	# Hop D: hum_system.tick_charge sums purr into the nearest receiver.
	var after_reserve: int = _hum.get_reserve(hum_id)
	assert_gt(
		after_reserve, baseline_reserve,
		"HOP D (hum charge): reserve should climb with satisfied cat in range; "
			+ "baseline=%d after=%d" % [baseline_reserve, after_reserve],
	)
