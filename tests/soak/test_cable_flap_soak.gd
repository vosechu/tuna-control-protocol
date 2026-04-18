extends GutTest

# Hammer the cable intents for 600 iterations (~10 minutes of sim at
# the 1-op-per-10-tick rate) and assert the DB + lock registry end in
# a consistent state. Catches leaks from partial cleanup, stranded
# locks, and cross-wired components.


func test_flap_ends_clean() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var db := GameStateDB.new()
	var locks := WiringLockRegistry.new()
	var ws := WiringSystem.new(db, locks, null, {&"cable_max_length_ru": 40})
	var hums: Array = []
	var actuators: Array = []
	for i: int in 3:
		hums.append(_make_hum(db, i * 800))
	for i: int in 5:
		actuators.append(_make_tuna(db, i * 400))
	for tick: int in 600:
		var act: int = actuators[tick % actuators.size()]
		var hum: int = hums[tick % hums.size()]
		ws.handle_connect(1, hum, act)
		if tick % 3 == 0:
			ws.handle_pickup_actuator_end(1, tick, act)
			ws.handle_cancel(1, act)
		locks.tick_expire(tick, 200)
	# Every surviving cable must reference a live HUM.
	for act: int in actuators:
		if db.has_component(act, &"hum_cable"):
			var hum_id: int = db.get_field(act, &"hum_cable", &"hum_id")
			assert_true(db.has_entity(hum_id), "Live cable → live HUM")
			assert_true(db.has_component(hum_id, &"hum"))
	# No lingering pickups (tick_expire at tick=599 with ttl=200 → nothing
	# acquired after tick 399 would survive; pickups are acquired and
	# cancelled in the same tick above so expiry is belt-and-braces).
	assert_eq(
		locks.entries_for_peer(1).size(),
		0,
		"No stranded pickups after flap",
	)


func _make_hum(db: GameStateDB, x: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"hum", {
		&"reserve": HumSystem.DEFAULT_CAPACITY,
		&"capacity": HumSystem.DEFAULT_CAPACITY,
	})
	db.set_component(id, &"position", {&"x": x, &"y": 0})
	db.update_spatial(id, x, 0)
	return id


func _make_tuna(db: GameStateDB, x: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"tuna_dispenser", {&"hum_cost": 50})
	db.set_component(id, &"hum_powered", {})
	db.set_component(id, &"position", {&"x": x, &"y": 0})
	db.update_spatial(id, x, 0)
	return id
