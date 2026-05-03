extends GutTest

# AI-DEV: Pins the bridge's two-field contract. Each tick the bridge
# writes BOTH purr.intensity AND purr.radius_px. A regression that
# updates only intensity (the obvious one) leaves a stale radius from a
# previous tick — the disk shrinks or grows based on yesterday's
# intensity and charges the wrong HUMs. radius_px formula is exactly
# `base_radius_ru * SLOT_HEIGHT_PX * intensity / UNIT`; don't shortcut
# it (dropping the intensity scaling makes a half-purring cat charge at
# full radius).

# ContentmentPurrBridge writes BOTH purr.intensity and purr.radius_px each
# tick. radius_px = base_radius_ru * SLOT_HEIGHT_PX * intensity / UNIT.


func _make_db_with_purrer(
	is_satisfied: int, base_radius_ru: int, rate: int
) -> GameStateDB:
	var db := GameStateDB.new()
	var eid: int = db.create_entity()
	db.set_component(
		eid, &"contentment", {&"is_satisfied": is_satisfied, &"value": 800}
	)
	db.set_component(eid, &"purr", {&"intensity": 0, &"radius_px": 0})
	db.set_component(
		eid, &"purr_config",
		{&"rate_when_satisfied": rate, &"base_radius_ru": base_radius_ru},
	)
	return db


func test_radius_px_zero_when_not_satisfied() -> void:
	var db := _make_db_with_purrer(0, 6, 10)
	var bridge := ContentmentPurrBridge.new(db)
	bridge.tick()
	var ids: Array[int] = db.get_entities_with(&"purr")
	assert_eq(db.get_field(ids[0], &"purr", &"radius_px"), 0)


func test_radius_px_full_when_satisfied_at_full_intensity() -> void:
	# base_radius_ru=6, rate=UNIT means full intensity. radius = 6 * 8 = 48 px.
	var db := _make_db_with_purrer(1, 6, Constants.UNIT)
	var bridge := ContentmentPurrBridge.new(db)
	bridge.tick()
	var ids: Array[int] = db.get_entities_with(&"purr")
	assert_eq(
		db.get_field(ids[0], &"purr", &"radius_px"),
		6 * Constants.SLOT_HEIGHT_PX,
	)


func test_radius_px_scales_linearly_with_intensity() -> void:
	# rate=500 (half intensity) -> 6 * 8 * 500 / 1000 = 24 px.
	var db := _make_db_with_purrer(1, 6, 500)
	var bridge := ContentmentPurrBridge.new(db)
	bridge.tick()
	var ids: Array[int] = db.get_entities_with(&"purr")
	assert_eq(db.get_field(ids[0], &"purr", &"radius_px"), 24)


func test_no_purr_config_skipped() -> void:
	var db := GameStateDB.new()
	var eid: int = db.create_entity()
	db.set_component(
		eid, &"contentment", {&"is_satisfied": 1, &"value": 800}
	)
	db.set_component(eid, &"purr", {&"intensity": 0, &"radius_px": 0})
	# No purr_config — bridge should skip.
	var bridge := ContentmentPurrBridge.new(db)
	bridge.tick()
	assert_eq(db.get_field(eid, &"purr", &"intensity"), 0)
	assert_eq(db.get_field(eid, &"purr", &"radius_px"), 0)
