extends GutTest

# AI-DEV: Pins the runner's two-field contract. Each tick the system
# writes BOTH purr.intensity AND purr.radius_px. A regression that
# updates only intensity (the obvious one) leaves a stale radius from
# a previous tick — the disk shrinks or grows based on yesterday's
# intensity and charges the wrong HUMs. radius_px formula is exactly
# `base_radius_ru * SLOT_HEIGHT_PX * intensity / UNIT`; don't shortcut
# it (dropping the intensity scaling makes a half-purring cat charge
# at full radius).


func _make_db(satisfied: int, base_radius_ru: int, base_intensity: int) -> GameStateDB:
	var db := GameStateDB.new()
	var id: int = db.create_entity()
	db.set_component(id, &"contentment", {&"is_satisfied": satisfied})
	db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
	db.set_component(id, &"sensory_emissions", {&"purr": {
		&"trigger": {
			&"component": &"contentment",
			&"field": &"is_satisfied",
			&"equals": 1,
		},
		&"base_intensity": {&"kind": &"literal", &"value": base_intensity},
		&"modifiers": [] as Array[Dictionary],
		&"base_radius_ru": {&"kind": &"literal", &"value": base_radius_ru},
	}})
	return db


func _output_config() -> Dictionary:
	return {
		&"channels": {&"acoustic": {&"falloff": &"quadratic"}},
		&"outputs": {&"purr": {&"channel": &"acoustic"}},
	}


func test_radius_px_zero_when_not_satisfied() -> void:
	var db := _make_db(0, 6, 1000)
	var system := SensoryEmissionSystem.new(db, _output_config())
	system.tick()
	var ids: Array[int] = db.get_entities_with(&"purr")
	assert_eq(db.get_field(ids[0], &"purr", &"radius_px"), 0)


func test_radius_px_full_when_satisfied_at_full_intensity() -> void:
	var db := _make_db(1, 6, Constants.UNIT)
	var system := SensoryEmissionSystem.new(db, _output_config())
	system.tick()
	var ids: Array[int] = db.get_entities_with(&"purr")
	assert_eq(
		db.get_field(ids[0], &"purr", &"radius_px"),
		6 * Constants.SLOT_HEIGHT_PX,
	)


func test_radius_px_scales_linearly_with_intensity() -> void:
	var db := _make_db(1, 6, 500)
	var system := SensoryEmissionSystem.new(db, _output_config())
	system.tick()
	var ids: Array[int] = db.get_entities_with(&"purr")
	# 6 * 8 * 500 / 1000 = 24
	assert_eq(db.get_field(ids[0], &"purr", &"radius_px"), 24)


func test_stale_radius_zeroed_after_trigger_fails() -> void:
	# AI-DEV: regression guard, ported from
	# test_contentment_purr_bridge_radius. Tick once at full intensity
	# to seed radius_px. Tick again with trigger failing. radius_px
	# MUST be zero (not the previous tick's value). A regression that
	# returns early before writing radius_px on trigger fail leaves
	# stale data charging wrong HUMs.
	var db := _make_db(1, 6, Constants.UNIT)
	var system := SensoryEmissionSystem.new(db, _output_config())
	system.tick()
	var ids: Array[int] = db.get_entities_with(&"purr")
	assert_gt(db.get_field(ids[0], &"purr", &"radius_px"), 0,
		"Setup: radius should be non-zero after first tick")

	# Trigger now fails
	db.set_field(ids[0], &"contentment", &"is_satisfied", 0)
	system.tick()
	assert_eq(db.get_field(ids[0], &"purr", &"radius_px"), 0,
		"Trigger fail must zero radius_px (not leave stale value)")
