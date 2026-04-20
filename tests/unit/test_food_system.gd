extends GutTest

const EventsScript: GDScript = preload(
	"res://nodes/events.gd"
)

var db: GameStateDB
var events: Object
var hum: HumSystem
var food: FoodSystem
var hum_id: int = -1


func before_each() -> void:
	db = GameStateDB.new()
	events = EventsScript.new()
	hum = HumSystem.new(db, events)
	food = FoodSystem.new(db, hum, events)
	# Spawn a HUM entity so _pick_hum_for shim can find a battery
	hum_id = _make_hum_entity()


func test_press_button_dispenses_can_when_hum_available():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Press happy-path unit proof. Surgical within-suite mutation: change the
	# final `return can_id` in press_button to `return Constants.INVALID_ID`.
	# Other press_button tests already expect INVALID_ID under their
	# respective failure branches; they stay green.
	var dispenser_id: int = _make_dispenser(1, 5)
	var button_id: int = _make_button(1, 6, dispenser_id)

	var result: int = food.press_button(button_id)
	assert_ne(result, Constants.INVALID_ID,
		"Pressing button with HUM should create a tuna can")
	assert_true(db.has_component(result, &"tuna_can"),
		"Created entity should have tuna_can component")


func test_press_button_fails_without_hum():
	var dispenser_id: int = _make_dispenser(1, 5)
	var button_id: int = _make_button(1, 6, dispenser_id)
	hum.drain_action(hum_id, hum.get_reserve(hum_id))

	var result: int = food.press_button(button_id)
	assert_eq(result, Constants.INVALID_ID,
		"Pressing button without HUM should fail")


func test_press_button_drains_hum():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Press drain unit proof. Surgical within-suite mutation: comment out
	# the `_hum.drain_action(hum_id, cost)` line in press_button. The
	# dispense test still passes (entity still created), rack/no-HUM tests
	# bail before drain, arm tests don't touch press_button.
	var dispenser_id: int = _make_dispenser(1, 5)
	var button_id: int = _make_button(1, 6, dispenser_id)
	var before: int = hum.get_reserve(hum_id)
	food.press_button(button_id)
	var after: int = hum.get_reserve(hum_id)
	assert_lt(after, before,
		"Dispensing should drain HUM")


func test_button_must_be_in_same_rack_as_dispenser():
	var dispenser_id: int = _make_dispenser(1, 5)
	var button_id: int = _make_button(3, 6, dispenser_id)

	var result: int = food.press_button(button_id)
	assert_eq(result, Constants.INVALID_ID,
		"Button in different rack should not work")


func test_arm_opens_nearby_sealed_can():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Arm happy-path unit proof. Surgical within-suite mutation: change the
	# post-open state assignment `updated[&"state"] = &"opened"` to
	# `&"broken"`. The advertises-food test still passes (advertisements
	# set_component happens regardless); ignore-distant and requires-hum
	# tests expect state==sealed and still pass.
	_make_arm(1)
	var can_id: int = _make_sealed_can(1)

	food.tick_arms()
	var can: Dictionary = db.get_component(can_id, &"tuna_can")
	assert_eq(can[&"state"], &"opened",
		"ARM should open sealed can within radius")


func test_arm_ignores_distant_can():
	_make_arm(1)
	var can_id: int = _make_sealed_can(4)

	food.tick_arms()
	var can: Dictionary = db.get_component(can_id, &"tuna_can")
	assert_eq(can[&"state"], &"sealed",
		"ARM should not open can outside radius")


func test_arm_requires_hum_to_open():
	_make_arm(1)
	var can_id: int = _make_sealed_can(1)
	hum.drain_action(hum_id, hum.get_reserve(hum_id))

	food.tick_arms()
	var can: Dictionary = db.get_component(can_id, &"tuna_can")
	assert_eq(can[&"state"], &"sealed",
		"ARM without HUM should not open cans")


func test_opened_can_advertises_food():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Advertisements unit proof. Surgical within-suite mutation: skip the
	# `set_component(entity_id, &"advertisements", …)` call after opening.
	# The arm-opens-nearby test still passes (state still set to opened);
	# other arm tests don't check advertisements.
	_make_arm(1)
	var can_id: int = _make_sealed_can(1)
	food.tick_arms()
	assert_true(db.has_component(can_id, &"advertisements"),
		"Opened can should have food advertisements")
	var ads: Dictionary = db.get_component(can_id, &"advertisements")
	var has_hunger_ad: bool = false
	for ad: Dictionary in ads[&"list"]:
		if ad[&"desire_type"] == &"hunger":
			has_hunger_ad = true
	assert_true(has_hunger_ad,
		"Opened can should advertise hunger satisfaction")


func test_eaten_can_despawns_after_delay():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Cleanup unit proof. Surgical within-suite mutation: comment out the
	# `_db.destroy_entity(can_id)` call in tick_cleanup. No other unit test
	# calls tick_cleanup — the cleanup loop is unique to this test.
	_make_arm(1)
	var can_id: int = _make_sealed_can(1)
	food.tick_arms()
	var can_data: Dictionary = db.get_component(can_id, &"tuna_can")
	can_data[&"state"] = &"eaten"
	db.set_component(can_id, &"tuna_can", can_data)
	for _i: int in 100:
		food.tick_cleanup()
	assert_false(db.has_entity(can_id),
		"Eaten can should despawn after delay")


# ── Helpers ──


func _make_dispenser(rack: int, slot: int) -> int:
	var id: int = db.create_entity()
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var x: int = slot_rect.position.x + slot_rect.size.x / 2
	var y: int = slot_rect.position.y + slot_rect.size.y / 2
	db.set_component(id, &"position", {
		&"x": x, &"y": y,
	})
	db.set_component(id, &"tuna_dispenser", {
		&"hum_cost": 50,
		&"can_type": &"tcp_tuna:tuna_can",
	})
	db.set_component(id, &"object_type", {
		&"type": &"tuna_dispenser",
	})
	db.set_component(id, &"hum_powered", {})
	db.set_component(id, &"hum_cable", {&"hum_id": hum_id})
	db.update_spatial(id, x, y)
	return id


func _make_button(
		rack: int, slot: int, dispenser_id: int,
) -> int:
	var id: int = db.create_entity()
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var x: int = slot_rect.position.x + slot_rect.size.x / 2
	var y: int = slot_rect.position.y + slot_rect.size.y / 2
	db.set_component(id, &"position", {
		&"x": x, &"y": y,
	})
	db.set_component(id, &"tuna_button", {
		&"dispenser_id": dispenser_id,
	})
	db.set_component(id, &"object_type", {
		&"type": &"tuna_button",
	})
	db.update_spatial(id, x, y)
	return id


func _make_arm(rack: int) -> int:
	var id: int = db.create_entity()
	var rack_col: Rect2i = Constants.rack_column_rect_world(0, rack)
	var x: int = rack_col.position.x + rack_col.size.x / 2
	var floor_rect: Rect2i = Constants.floor_rect_world(0)
	var y: int = floor_rect.position.y + floor_rect.size.y / 2
	db.set_component(id, &"position", {
		&"x": x, &"y": y,
	})
	db.set_component(id, &"arm", {
		&"radius_px": 24,
		&"hum_cost": 30,
		&"open_duration_ticks": 20,
	})
	db.set_component(id, &"object_type", {
		&"type": &"arm",
	})
	db.set_component(id, &"hum_powered", {})
	db.set_component(id, &"hum_cable", {&"hum_id": hum_id})
	db.update_spatial(id, x, y)
	return id


func _make_hum_entity() -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"hum", {
		&"reserve": HumSystem.DEFAULT_CAPACITY,
		&"capacity": HumSystem.DEFAULT_CAPACITY,
	})
	db.set_component(id, &"position", {&"x": 0, &"y": 0})
	db.update_spatial(id, 0, 0)
	return id


func _make_sealed_can(rack: int) -> int:
	var id: int = db.create_entity()
	var rack_col: Rect2i = Constants.rack_column_rect_world(0, rack)
	var x: int = rack_col.position.x + rack_col.size.x / 2
	var floor_rect: Rect2i = Constants.floor_rect_world(0)
	var y: int = floor_rect.position.y + floor_rect.size.y / 4
	db.set_component(id, &"position", {
		&"x": x, &"y": y,
	})
	db.set_component(id, &"tuna_can", {
		&"state": &"sealed",
		&"despawn_timer": 0,
	})
	db.set_component(id, &"object_type", {
		&"type": &"tuna_can",
	})
	db.update_spatial(id, x, y)
	return id
