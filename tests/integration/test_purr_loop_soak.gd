extends GutTest

# AI-DEV: AI **MUST NOT** touch this test. If the test is failing, it is
# because you removed or broke code.

# Run the contentment->purr->charge loop for many ticks and assert no
# pathological state emerges. Specifically:
#   * a satisfied cat keeps emitting purr.intensity > 0 (not toggled off
#     by some accidental side-effect of the bridge or HUM charge)
#   * HUM reserve climbs monotonically toward capacity (no transient
#     negatives, no runaway above capacity)
#   * intensity short-circuit still works once unsatisfied

const EventsScript: GDScript = preload("res://nodes/events.gd")


func _make_world() -> Dictionary:
	var db := GameStateDB.new()
	var events: Object = EventsScript.new()
	var bridge := ContentmentPurrBridge.new(db)
	var hum := HumSystem.new(db, events)

	var hum_slot: Rect2i = Constants.slot_rect_world(0, 0, 9)
	var hum_id: int = db.create_entity()
	db.set_component(hum_id, &"hum", {&"reserve": 0, &"capacity": 10000})
	db.set_component(hum_id, &"hum_receiver", {})
	db.set_component(hum_id, &"physical", {&"mass": 20000, &"size_ru": 6})
	db.set_component(hum_id, &"position", {
		&"x": hum_slot.position.x + hum_slot.size.x / 2,
		&"y": hum_slot.position.y + hum_slot.size.y / 2,
	})

	var box_slot: Rect2i = Constants.slot_rect_world(0, 1, 1)
	var cat_id: int = db.create_entity()
	db.set_component(cat_id, &"position", {
		&"x": box_slot.position.x + box_slot.size.x / 2,
		&"y": (box_slot.position.y + box_slot.size.y / 2) - 8,
	})
	db.set_component(cat_id, &"contentment", {&"is_satisfied": 1, &"value": 800})
	db.set_component(cat_id, &"purr", {&"intensity": 0, &"radius_px": 0})
	db.set_component(
		cat_id, &"purr_config",
		{&"rate_when_satisfied": Constants.UNIT, &"base_radius_ru": 6},
	)
	return {&"db": db, &"bridge": bridge, &"hum": hum, &"hum_id": hum_id, &"cat_id": cat_id}


func test_loop_stays_stable_over_500_ticks() -> void:
	var w: Dictionary = _make_world()
	var hum_sys: HumSystem = w[&"hum"]
	var bridge: ContentmentPurrBridge = w[&"bridge"]
	var db: GameStateDB = w[&"db"]
	var hum_id: int = w[&"hum_id"]
	var cat_id: int = w[&"cat_id"]
	var capacity: int = db.get_field(hum_id, &"hum", &"capacity")

	for _i: int in 500:
		bridge.tick()
		hum_sys.tick_charge()
		hum_sys.tick_idle_drain()

		var reserve: int = hum_sys.get_reserve(hum_id)
		assert_true(
			reserve >= 0,
			"reserve must never be negative; saw %d at tick %d" % [reserve, _i],
		)
		assert_true(
			reserve <= capacity,
			"reserve must never exceed capacity; saw %d > %d" % [reserve, capacity],
		)
		assert_gt(
			db.get_field(cat_id, &"purr", &"intensity"), 0,
			"satisfied cat should keep emitting; intensity dropped at tick %d" % _i,
		)

	# After hundreds of ticks of net-positive charge, the HUM should be at
	# (or very near) capacity. Steady state sits one idle-drain tick below
	# capacity because charge clamps at capacity then drain takes a few off
	# before next charge restores.
	assert_gt(
		hum_sys.get_reserve(hum_id), capacity - 100,
		"reserve should saturate near capacity (~99%%+) after long run",
	)


func test_unsatisfied_cat_never_creeps_charge_into_hum() -> void:
	var w: Dictionary = _make_world()
	var hum_sys: HumSystem = w[&"hum"]
	var bridge: ContentmentPurrBridge = w[&"bridge"]
	var db: GameStateDB = w[&"db"]
	var hum_id: int = w[&"hum_id"]
	var cat_id: int = w[&"cat_id"]
	# Flip cat to unsatisfied; bridge should write 0/0 each tick.
	db.set_component(cat_id, &"contentment", {&"is_satisfied": 0, &"value": 100})

	for _i: int in 200:
		bridge.tick()
		hum_sys.tick_charge()
		# Skip idle drain — we want to assert charge() is never called, not
		# that drain dominates.

	assert_eq(
		hum_sys.get_reserve(hum_id), 0,
		"unsatisfied cat must not charge HUM at any tick of the soak window",
	)
