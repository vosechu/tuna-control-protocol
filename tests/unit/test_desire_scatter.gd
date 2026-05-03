extends GutTest

# AI-DEV: Unit tests for slot-delivery + radius-delivery passes added in
# the perception-channels migration (PR2). The two-pass split is in
# engine/desires/desire_scatter.gd. If a test starts failing because
# desires didn't change, suspect: bay_local_to_slot returning a non-slot
# zone, the slot-occupant filter rejecting the receiver, or the channel
# not being in Constants.CHANNELS.

var _db: GameStateDB
var _scatter: DesireScatter


func before_each() -> void:
	_db = GameStateDB.new()
	_scatter = DesireScatter.new(_db)


func test_slot_delivery_lands_full_strength_on_slot_occupant():
	# Box at bay 0, rack 1, slot 5 (interior slot).
	var slot_origin: Vector2i = Constants.slot_origin_world(0, 1, 5)
	var box_x: int = slot_origin.x + 4
	var box_y: int = slot_origin.y + 4
	var box_id: int = _db.create_entity()
	_db.set_component(box_id, &"position", {&"x": box_x, &"y": box_y})
	_db.set_component(box_id, &"advertisements", {&"list": [
		{&"channel": &"comfort", &"strength": 700, &"effect_slot": true},
	]})
	_db.update_spatial(box_id, box_x, box_y)

	# Cat in the same slot, anchor offset
	var cat_id: int = _db.create_entity()
	var cat_x: int = box_x + 2
	var cat_y: int = box_y + 2
	_db.set_component(cat_id, &"position", {&"x": cat_x, &"y": cat_y})
	_db.set_component(cat_id, &"desires", {&"comfort": 100})
	_db.set_component(cat_id, &"senses", {
		&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 64,
	})
	_db.update_spatial(cat_id, cat_x, cat_y)

	_scatter.scatter_from_ads()

	var desires: Dictionary = _db.get_component(cat_id, &"desires")
	assert_gt(
		desires[&"comfort"], 100,
		"Slot-delivered comfort must raise the cat's comfort desire (got %d)"
			% desires[&"comfort"],
	)


func test_radius_delivery_applies_quadratic_falloff_at_half_radius():
	# Buzzer at origin emits noise (deplete on quiet) over 200 px radius.
	# Cat at half radius (100 px). Quadratic falloff factor at half
	# radius: ((1 - 100/200))² = 0.25. delta_per_tick =
	# strength * 0.25 / 10 = 1000 * 0.25 / 10 = 25.
	# Starting quiet = 1000, expected ≈ 975 (allow ±5 for rounding).
	# Surgical mutation: changing the falloff exponent (1, 3, etc.)
	# moves the result outside the [970, 980] window.
	var buzzer_id: int = _db.create_entity()
	_db.set_component(buzzer_id, &"position", {&"x": 0, &"y": 0})
	_db.set_component(buzzer_id, &"advertisements", {&"list": [
		{&"channel": &"noise", &"strength": 1000, &"effect_radius_px": 200,
			&"falloff": &"quadratic"},
	]})
	_db.update_spatial(buzzer_id, 0, 0)

	var cat_id: int = _db.create_entity()
	_db.set_component(cat_id, &"position", {&"x": 100, &"y": 0})
	_db.set_component(cat_id, &"desires", {&"quiet": 1000})
	_db.set_component(cat_id, &"senses", {
		&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 64,
	})
	_db.update_spatial(cat_id, 100, 0)

	_scatter.scatter_from_ads()

	var quiet: int = _db.get_component(cat_id, &"desires")[&"quiet"]
	assert_true(
		quiet >= 970 and quiet <= 980,
		"Quadratic falloff at half-radius must deplete ~25/tick from quiet, got %d"
			% quiet,
	)


func test_slot_delivery_does_not_reach_adjacent_slot():
	# Surgical mutation guard: dropping the slot-zone check from
	# _apply_slot_ad would let an adjacent-slot cat pick up comfort
	# (the radius query around slot center extends 16 px and reaches
	# the next slot vertically). The slot equality test rejects them.
	# Box at slot (0, 1, 5), cat at slot (0, 1, 6) — directly above,
	# inside the radius query but in a different slot.
	var box_origin: Vector2i = Constants.slot_origin_world(0, 1, 5)
	var box_x: int = box_origin.x + 4
	var box_y: int = box_origin.y + 4
	var box_id: int = _db.create_entity()
	_db.set_component(box_id, &"position", {&"x": box_x, &"y": box_y})
	_db.set_component(box_id, &"advertisements", {&"list": [
		{&"channel": &"comfort", &"strength": 700, &"effect_slot": true},
	]})
	_db.update_spatial(box_id, box_x, box_y)

	var cat_origin: Vector2i = Constants.slot_origin_world(0, 1, 6)
	var cat_x: int = cat_origin.x + 4
	var cat_y: int = cat_origin.y + 4
	var cat_id: int = _db.create_entity()
	_db.set_component(cat_id, &"position", {&"x": cat_x, &"y": cat_y})
	_db.set_component(cat_id, &"desires", {&"comfort": 100})
	_db.set_component(cat_id, &"senses", {
		&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 64,
	})
	_db.update_spatial(cat_id, cat_x, cat_y)

	# Test setup invariant: cat is within radius query but different slot.
	var dist: int = absi(cat_x - box_x) + absi(cat_y - box_y)
	assert_lte(
		dist, 16,
		"Test setup: cat must be within slot-delivery radius query (got %d)" % dist,
	)

	_scatter.scatter_from_ads()

	var desires: Dictionary = _db.get_component(cat_id, &"desires")
	assert_eq(
		desires[&"comfort"], 100,
		"Cat in adjacent slot must not receive slot-delivered comfort (got %d)"
			% desires[&"comfort"],
	)
