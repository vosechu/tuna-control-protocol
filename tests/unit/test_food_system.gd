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
	_make_arm(1)
	var can_id: int = _make_sealed_can(1)

	food.tick_arms()
	var can: Dictionary = db.get_component(can_id, &"tuna_can")
	assert_eq(can[&"state"], &"opened",
		"ARM should open sealed can within radius")


func test_arm_ignores_distant_can():
	_make_arm(1)
	var can_id: int = _make_sealed_can(5)

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
	_make_arm(1)
	var can_id: int = _make_sealed_can(1)
	food.tick_arms()
	assert_true(
		db.has_component(can_id, &"advertisements"),
		"Opened can should have food advertisements",
	)
	var ads: Dictionary = db.get_component(
		can_id, &"advertisements",
	)
	var has_hunger_ad: bool = false
	for ad: Dictionary in ads[&"list"]:
		if ad[&"desire_type"] == &"hunger":
			has_hunger_ad = true
	assert_true(has_hunger_ad,
		"Opened can should advertise hunger satisfaction")


func test_eaten_can_despawns_after_delay():
	_make_arm(1)
	var can_id: int = _make_sealed_can(1)
	food.tick_arms()
	var can_data: Dictionary = db.get_component(
		can_id, &"tuna_can",
	)
	can_data[&"state"] = &"eaten"
	db.set_component(can_id, &"tuna_can", can_data)
	for i in 100:
		food.tick_cleanup()
	assert_false(db.has_entity(can_id),
		"Eaten can should despawn after delay")


# ── Helpers ──


func _make_dispenser(rack: int, slot: int) -> int:
	var id: int = db.create_entity()
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = slot * Constants.SLOT_HEIGHT_PU
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
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = slot * Constants.SLOT_HEIGHT_PU
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
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = (
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU
		+ Constants.FLOOR_HEIGHT_PU / 2
	)
	db.set_component(id, &"position", {
		&"x": x, &"y": y,
	})
	db.set_component(id, &"arm", {
		&"radius_ru": 3,
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
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = (
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU
		+ Constants.FLOOR_HEIGHT_PU / 4
	)
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
