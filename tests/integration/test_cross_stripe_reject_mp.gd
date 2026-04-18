extends GutTest

# Stripe-aware deny stub. Solo mode always passes the stripe check because
# peer 1 owns every stripe in-fiction; this placeholder test documents the
# contract. The real cross-stripe behavior tests land with MP proper
# (see spec Section G, deferred until the peer roster is wired).


func test_solo_peer_always_passes_stripe_check() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var db := GameStateDB.new()
	var locks := WiringLockRegistry.new()
	var ws := WiringSystem.new(db, locks, null, {&"cable_max_length_ru": 20})
	# Place HUM in rack 0 and actuator in rack 6 — across the 5-rack stripe
	# boundary in a stripe-aware world. Solo mode ignores the boundary and
	# rejects only on out_of_reach.
	var hum: int = db.create_entity()
	db.set_component(hum, &"hum", {
		&"reserve": HumSystem.DEFAULT_CAPACITY,
		&"capacity": HumSystem.DEFAULT_CAPACITY,
	})
	db.set_component(hum, &"position", {&"x": 0, &"y": 0})
	var tuna: int = db.create_entity()
	db.set_component(tuna, &"tuna_dispenser", {&"hum_cost": 50})
	db.set_component(tuna, &"hum_powered", {})
	# In RU (SLOT_HEIGHT_PU units) within the 20 RU reach; in PU that's
	# still well under a single-stripe width.
	db.set_component(tuna, &"position", {&"x": Constants.ru_to_pu(5), &"y": 0})
	assert_true(ws.handle_connect(1, hum, tuna))
