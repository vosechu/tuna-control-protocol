extends GutTest

const EventsScript: GDScript = preload("res://nodes/events.gd")


func test_destroying_hum_leaves_stale_cable_but_drain_fails() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var db := GameStateDB.new()
	var events: Object = EventsScript.new()
	var hum_sys := HumSystem.new(db, events)
	var food := FoodSystem.new(db, hum_sys, events)
	var hum_id: int = db.create_entity()
	db.set_component(hum_id, &"hum", {
		&"reserve": HumSystem.DEFAULT_CAPACITY,
		&"capacity": HumSystem.DEFAULT_CAPACITY,
	})
	db.set_component(hum_id, &"position", {&"x": 0, &"y": 0})
	var tuna_id: int = db.create_entity()
	db.set_component(tuna_id, &"tuna_dispenser", {&"hum_cost": 50})
	db.set_component(tuna_id, &"hum_powered", {})
	db.set_component(tuna_id, &"hum_cable", {&"hum_id": hum_id})
	db.set_component(tuna_id, &"position", {&"x": 0, &"y": 0})
	# Sanity: while HUM exists, is_powered resolves.
	assert_eq(food.is_powered(tuna_id, 50), hum_id)
	# Destroy HUM; cable now points at a tombstone.
	db.destroy_entity(hum_id)
	assert_eq(
		food.is_powered(tuna_id, 50),
		Constants.INVALID_ID,
		"Cable to despawned HUM reports not-powered",
	)
	assert_true(
		db.has_component(tuna_id, &"hum_cable"),
		"Cable component persists; no eager cleanup on HUM despawn",
	)
