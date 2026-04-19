extends GutTest

# Smoke test: runs a full game_server tick loop with all entity types
# to catch runtime errors that compile checks miss (e.g., Dictionary
# key access on entities with different component shapes).


func test_100_ticks_no_errors() -> void:
	var db := GameStateDB.new()
	var heat_grid := HeatGrid.new(db)
	var resolver := DesireResolver.new(db)

	# Spawn a cat with food desire
	var cat: int = db.create_entity()
	db.set_component(cat, &"species", {
		&"id": &"tcp_cats:cat",
		&"variant": &"cat01", &"name": &"Smoke",
	})
	db.set_component(cat, &"position", {&"x": 4000, &"y": 31000})
	db.set_component(cat, &"desires", {
		&"warmth": 800, &"comfort": 800,
		&"curiosity": 500, &"food": 800,
	})
	db.set_component(cat, &"personality", {
		&"warmth_weight": 800, &"comfort_weight": 600,
		&"curiosity_weight": 100, &"food_weight": 700,
	})
	db.set_component(cat, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	db.set_component(cat, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(cat, 4000, 31000)

	# Spawn a ferret WITHOUT food desire
	var ferret: int = db.create_entity()
	db.set_component(ferret, &"species", {
		&"id": &"tcp_ferrets:ferret",
		&"variant": &"lilotter", &"name": &"Smokey",
	})
	db.set_component(ferret, &"position", {
		&"x": 8000, &"y": 31000,
	})
	db.set_component(ferret, &"desires", {
		&"warmth": 800, &"comfort": 800, &"curiosity": 300,
	})
	db.set_component(ferret, &"personality", {
		&"warmth_weight": 300, &"comfort_weight": 600,
		&"curiosity_weight": 900,
	})
	db.set_component(ferret, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	db.set_component(ferret, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(ferret, 8000, 31000)

	# Spawn arm with purpose desire (no warmth/comfort/food)
	var arm: int = db.create_entity()
	db.set_component(arm, &"species", {
		&"id": &"tcp_base:robot_arm",
		&"variant": &"arm", &"name": &"ARM-T",
	})
	db.set_component(arm, &"position", {
		&"x": 20000, &"y": 31000,
	})
	db.set_component(arm, &"desires", {&"purpose": 800})
	db.set_component(arm, &"personality", {
		&"openable_weight": 900, &"scannable_weight": 500,
	})
	db.set_component(arm, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	db.set_component(arm, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(arm, 20000, 31000)

	# Spawn a server (heat source, no desires)
	var server: int = db.create_entity()
	db.set_component(server, &"position", {
		&"x": 8000, &"y": 28000,
	})
	db.set_component(server, &"heat_source", {
		&"value": 1000, &"radius_px": 5,
	})
	db.update_spatial(server, 8000, 28000)

	# Run 100 ticks of the core loop (no scene tree needed)
	for _tick: int in 100:
		db.advance_tick()
		heat_grid.propagate()

		# Decay + scatter (mirrors game_server._scatter_desires)
		db.add_all(&"desires", &"warmth", -8)
		db.add_all(&"desires", &"comfort", -5)
		db.add_all(&"desires", &"curiosity", -3)
		db.add_all(&"desires", &"food", -2)
		db.add_all(&"desires", &"purpose", -6)
		db.clamp_all(&"desires", &"warmth", 0, 1000)
		db.clamp_all(&"desires", &"comfort", 0, 1000)
		db.clamp_all(&"desires", &"curiosity", 0, 1000)
		db.clamp_all(&"desires", &"food", 0, 1000)
		db.clamp_all(&"desires", &"purpose", 0, 1000)

		# Evaluate desires
		var animals: Array[int] = db.get_entities_with(
			&"species",
		)
		for eid: int in animals:
			resolver.mark_dirty(eid)
		resolver.evaluate_budget()

	# If we got here without crashing, the smoke test passed.
	# Verify entities still exist and have valid state.
	assert_true(db.has_entity(cat), "Cat must survive 100 ticks")
	assert_true(
		db.has_entity(ferret), "Ferret must survive 100 ticks",
	)
	assert_true(db.has_entity(arm), "Arm must survive 100 ticks")

	for eid: int in [cat, ferret, arm]:
		var desires: Dictionary = db.get_component(
			eid, &"desires",
		)
		for key: StringName in desires:
			assert_gte(desires[key], 0,
				"Desire %s must be >= 0" % key)
			assert_lte(desires[key], 1000,
				"Desire %s must be <= 1000" % key)
