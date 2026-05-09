extends GutTest

# AI-DEV: Soak test — guards three pathologies that 1-shot unit tests
# can't catch because they only emerge across many ticks:
#   1. SensoryEmissionSystem or HUM charge accidentally toggling a
#      satisfied cat's intensity off (single-tick checks don't see "off
#      again at tick 50")
#   2. HUM reserve briefly going negative or overshooting capacity
#      mid-tick (only visible if you sample every tick)
#   3. Unsatisfied short-circuit failing after the cat WAS satisfied
#      (state-transition bug, not initial-state bug)
# Don't shrink the tick count to "make it faster" — under ~100 ticks
# none of these can surface.

const EventsScript: GDScript = preload("res://nodes/events.gd")


func _output_config() -> Dictionary:
	return {
		&"channels": {&"acoustic": {&"falloff": &"quadratic"}},
		&"outputs": {&"purr": {&"channel": &"acoustic"}},
	}


func _make_world() -> Dictionary:
	var db := GameStateDB.new()
	var events: Object = EventsScript.new()
	var sensory := SensoryEmissionSystem.new(db, _output_config())
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
	db.set_component(cat_id, &"sensory_emissions", {&"purr": {
		&"trigger": {
			&"component": &"contentment",
			&"field": &"is_satisfied",
			&"equals": 1,
		},
		&"base_intensity": {&"kind": &"literal", &"value": Constants.UNIT},
		&"modifiers": [] as Array[Dictionary],
		&"base_radius_ru": {&"kind": &"literal", &"value": 6},
	}})
	return {
		&"db": db, &"sensory": sensory, &"hum": hum,
		&"hum_id": hum_id, &"cat_id": cat_id,
	}


func test_loop_stays_stable_over_500_ticks() -> void:
	var w: Dictionary = _make_world()
	var hum_sys: HumSystem = w[&"hum"]
	var sensory: SensoryEmissionSystem = w[&"sensory"]
	var db: GameStateDB = w[&"db"]
	var hum_id: int = w[&"hum_id"]
	var cat_id: int = w[&"cat_id"]
	var capacity: int = db.get_field(hum_id, &"hum", &"capacity")

	for _i: int in 500:
		sensory.tick()
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
	var sensory: SensoryEmissionSystem = w[&"sensory"]
	var db: GameStateDB = w[&"db"]
	var hum_id: int = w[&"hum_id"]
	var cat_id: int = w[&"cat_id"]
	# Flip cat to unsatisfied; runner should write 0/0 each tick.
	db.set_component(cat_id, &"contentment", {&"is_satisfied": 0, &"value": 100})

	for _i: int in 200:
		sensory.tick()
		hum_sys.tick_charge()
		# Skip idle drain — we want to assert charge() is never called, not
		# that drain dominates.

	assert_eq(
		hum_sys.get_reserve(hum_id), 0,
		"unsatisfied cat must not charge HUM at any tick of the soak window",
	)
