extends GutTest


func test_ferret_visits_multiple_racks_over_time():
	var db: GameStateDB = GameStateDB.new()
	var resolver: DesireResolver = DesireResolver.new(db)
	var trackers: Dictionary = {}

	# Create ferret
	var ferret_id: int = db.create_entity()
	db.set_component(ferret_id, &"species", {&"id": &"tcp_base:ferret"})
	db.set_component(ferret_id, &"position", {&"x": 0, &"y": 0})
	db.set_component(ferret_id, &"desires", {&"warmth": 200, &"comfort": 200, &"curiosity": 800})
	db.set_component(ferret_id, &"personality", {
		&"warmth_weight": 400, &"comfort_weight": 600, &"curiosity_weight": 900,
	})
	db.set_component(ferret_id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	db.set_component(ferret_id, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(ferret_id, 0, 0)
	trackers[ferret_id] = CuriosityTracker.new()

	# Create 5 racks spread across the floor
	var rack_ids: Array[int] = []
	for i: int in 5:
		var rack_id: int = db.create_entity()
		var x: int = i * 5000
		db.set_component(rack_id, &"position", {&"x": x, &"y": 0})
		db.set_component(rack_id, &"advertisements", {&"list": [
			{&"desire_type": &"curiosity", &"strength": 300, &"radius_ru": 30,
			 &"novelty_duration": 30, &"novelty_cooldown": 100},
		]})
		db.update_spatial(rack_id, x, 0)
		rack_ids.append(rack_id)

	# Track which racks the ferret targets over 500 ticks
	var visited_racks: Dictionary = {}  # rack_id -> true
	for tick: int in 500:
		db.advance_tick()
		resolver.mark_dirty(ferret_id)
		resolver.evaluate_budget(trackers)
		var target: Dictionary = db.get_component(ferret_id, &"target")
		if target[&"entity_id"] != Constants.INVALID_ID:
			visited_racks[target[&"entity_id"]] = true
			# Simulate arrival: teleport ferret to target, record visit, reset to IDLE
			db.set_component(ferret_id, &"position", {
				&"x": target[&"x"], &"y": target[&"y"],
			})
			db.update_spatial(ferret_id, target[&"x"], target[&"y"])
			trackers[ferret_id].visit(target[&"entity_id"], db.get_tick())
			db.set_component(ferret_id, &"ai_state", {
				&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
			})
			db.set_component(ferret_id, &"target", {
				&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
				&"entity_id": Constants.INVALID_ID,
			})

	assert_gte(visited_racks.size(), 3,
		"Ferret must visit at least 3 of 5 racks in 500 ticks, visited %d" % visited_racks.size())
