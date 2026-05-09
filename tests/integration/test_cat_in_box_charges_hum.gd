extends GutTest

# AI-DEV: End-to-end proof for the cat-jumps-into-box smoke goal: a
# satisfied cat settled inside a box (interior_origin position) emits
# purr each tick, and its emission disk intersects an adjacent-rack
# HUM's body rect, so the HUM's reserve grows. The two components
# tested in tandem here — SensoryEmissionSystem (intensity + radius_px)
# and HumSystem.tick_charge (disk-vs-rect intersection) — have unit
# tests that pass independently while the cross-rack chain still
# fails; the geometry only emerges when both run together. Don't split
# this test back into two; the bug it guards lives in the seam.

const EventsScript: GDScript = preload("res://nodes/events.gd")

var _db: GameStateDB
var _events: Object
var _sensory: SensoryEmissionSystem
var _hum: HumSystem


func _output_config() -> Dictionary:
	return {
		&"channels": {&"acoustic": {&"falloff": &"quadratic"}},
		&"outputs": {&"purr": {&"channel": &"acoustic"}},
	}


func _make_purr_emission(rate: int, radius_ru: int) -> Dictionary:
	return {&"purr": {
		&"trigger": {
			&"component": &"contentment",
			&"field": &"is_satisfied",
			&"equals": 1,
		},
		&"base_intensity": {&"kind": &"literal", &"value": rate},
		&"modifiers": [] as Array[Dictionary],
		&"base_radius_ru": {&"kind": &"literal", &"value": radius_ru},
	}}


func before_each() -> void:
	_db = GameStateDB.new()
	_events = EventsScript.new()
	_sensory = SensoryEmissionSystem.new(_db, _output_config())
	_hum = HumSystem.new(_db, _events)


func test_cat_in_box_one_rack_over_charges_hum_via_disk_intersection() -> void:
	# HUM at rack 0 slot 9 (top), 6U body; this is the tcp_base:hum_device shape.
	var hum_slot: Rect2i = Constants.slot_rect_world(0, 0, 9)
	var hum_id: int = _db.create_entity()
	_db.set_component(hum_id, &"hum", {&"reserve": 0, &"capacity": 10000})
	_db.set_component(hum_id, &"hum_receiver", {})
	_db.set_component(hum_id, &"physical", {&"mass": 20000, &"size_ru": 6})
	_db.set_component(hum_id, &"position", {
		&"x": hum_slot.position.x + hum_slot.size.x / 2,
		&"y": hum_slot.position.y + hum_slot.size.y / 2,
	})

	# Cat settled inside a box one rack over — interior anchor is 8 px above
	# the box slot's center (interior_origin_offset = (0, -8)). That's well
	# within the cat's 6 RU = 48 px purr radius once satisfied.
	var box_slot: Rect2i = Constants.slot_rect_world(0, 1, 1)
	var cat_x: int = box_slot.position.x + box_slot.size.x / 2
	var cat_y: int = (box_slot.position.y + box_slot.size.y / 2) - 8
	var cat_id: int = _db.create_entity()
	_db.set_component(cat_id, &"position", {&"x": cat_x, &"y": cat_y})
	_db.set_component(cat_id, &"contentment", {&"is_satisfied": 1, &"value": 800})
	_db.set_component(
		cat_id, &"purr", {&"intensity": 0, &"radius_px": 0},
	)
	_db.set_component(
		cat_id, &"sensory_emissions",
		_make_purr_emission(Constants.UNIT, 6),
	)

	# Tick once to materialize purr.intensity + purr.radius_px, then run
	# the charge pass.
	_sensory.tick()

	# Runner wrote the per-tick purr fields.
	assert_eq(
		_db.get_field(cat_id, &"purr", &"intensity"), Constants.UNIT,
		"satisfied cat intensity should be UNIT (full bliss)",
	)
	assert_eq(
		_db.get_field(cat_id, &"purr", &"radius_px"),
		6 * Constants.SLOT_HEIGHT_PX,
		"satisfied cat radius_px should be 48 px",
	)

	_hum.tick_charge()
	assert_gt(
		_hum.get_reserve(hum_id), 0,
		"HUM reserve should rise from a single tick of cross-rack purr",
	)


func test_unsatisfied_cat_does_not_charge_hum() -> void:
	# Same geometry; cat is unsatisfied. radius_px stays 0 -> no charge.
	var hum_slot: Rect2i = Constants.slot_rect_world(0, 0, 9)
	var hum_id: int = _db.create_entity()
	_db.set_component(hum_id, &"hum", {&"reserve": 0, &"capacity": 10000})
	_db.set_component(hum_id, &"hum_receiver", {})
	_db.set_component(hum_id, &"physical", {&"mass": 20000, &"size_ru": 6})
	_db.set_component(hum_id, &"position", {
		&"x": hum_slot.position.x + hum_slot.size.x / 2,
		&"y": hum_slot.position.y + hum_slot.size.y / 2,
	})
	var box_slot: Rect2i = Constants.slot_rect_world(0, 1, 1)
	var cat_id: int = _db.create_entity()
	_db.set_component(cat_id, &"position", {
		&"x": box_slot.position.x + box_slot.size.x / 2,
		&"y": (box_slot.position.y + box_slot.size.y / 2) - 8,
	})
	_db.set_component(cat_id, &"contentment", {&"is_satisfied": 0, &"value": 200})
	_db.set_component(cat_id, &"purr", {&"intensity": 0, &"radius_px": 0})
	_db.set_component(
		cat_id, &"sensory_emissions",
		_make_purr_emission(Constants.UNIT, 6),
	)

	_sensory.tick()
	_hum.tick_charge()
	assert_eq(
		_hum.get_reserve(hum_id), 0,
		"unsatisfied cat must not charge HUM (intensity 0 short-circuits)",
	)
