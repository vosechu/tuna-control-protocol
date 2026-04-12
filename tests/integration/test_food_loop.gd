extends GutTest

# Integration test: full button→can→arm→eat cycle using wired systems.

const EventsScript: GDScript = preload(
	"res://nodes/events.gd"
)

var _db: GameStateDB
var _events: Object
var _hum: HumSystem
var _food: FoodSystem


func before_each() -> void:
	_db = GameStateDB.new()
	_events = EventsScript.new()
	_hum = HumSystem.new(_db, _events)
	_food = FoodSystem.new(_db, _hum, _events)


func test_button_press_creates_sealed_can():
	var disp_id: int = _make_dispenser(1, 5)
	var button_id: int = _make_button(1, 6, disp_id)

	var can_id: int = _food.press_button(button_id)
	assert_ne(can_id, Constants.INVALID_ID,
		"Button press should create a can")
	assert_true(_db.has_component(can_id, &"tuna_can"),
		"Can should have tuna_can component")
	var can: Dictionary = _db.get_component(
		can_id, &"tuna_can",
	)
	assert_eq(can[&"state"], &"sealed",
		"Fresh can should be sealed")


func test_arm_opens_sealed_can_and_adds_food_ad():
	var disp_id: int = _make_dispenser(1, 5)
	var button_id: int = _make_button(1, 6, disp_id)
	_make_arm(1)

	var can_id: int = _food.press_button(button_id)
	_food.tick_arms()

	var can: Dictionary = _db.get_component(
		can_id, &"tuna_can",
	)
	assert_eq(can[&"state"], &"opened",
		"ARM should open the can")
	assert_true(
		_db.has_component(can_id, &"advertisements"),
		"Opened can should have food ads",
	)


func test_full_dispense_open_eat_cleanup_cycle():
	var disp_id: int = _make_dispenser(1, 5)
	var button_id: int = _make_button(1, 6, disp_id)
	_make_arm(1)

	# Press button → sealed can
	var can_id: int = _food.press_button(button_id)
	assert_ne(can_id, Constants.INVALID_ID,
		"Should dispense a can")

	# ARM opens can
	_food.tick_arms()
	var can: Dictionary = _db.get_component(
		can_id, &"tuna_can",
	)
	assert_eq(can[&"state"], &"opened",
		"ARM should open the can")

	# Mark as eaten (simulates cat finishing)
	can[&"state"] = &"eaten"
	_db.set_component(can_id, &"tuna_can", can)
	_db.remove_component(can_id, &"advertisements")

	# Cleanup despawns after 100 ticks
	for i in 100:
		_food.tick_cleanup()
	assert_false(_db.has_entity(can_id),
		"Eaten can should despawn after cleanup")


func test_dispense_drains_and_open_drains_hum():
	var disp_id: int = _make_dispenser(1, 5)
	var button_id: int = _make_button(1, 6, disp_id)
	_make_arm(1)

	var start_reserve: int = _hum.get_reserve()
	_food.press_button(button_id)
	var after_dispense: int = _hum.get_reserve()
	assert_eq(
		start_reserve - after_dispense, 50,
		"Dispense should drain 50 HUM",
	)

	_food.tick_arms()
	var after_open: int = _hum.get_reserve()
	assert_eq(
		after_dispense - after_open, 30,
		"ARM open should drain 30 HUM",
	)


# ── Helpers ──


func _make_dispenser(rack: int, slot: int) -> int:
	var id: int = _db.create_entity()
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = slot * Constants.SLOT_HEIGHT_PU
	_db.set_component(id, &"position", {
		&"x": x, &"y": y,
	})
	_db.set_component(id, &"tuna_dispenser", {
		&"hum_cost": 50,
		&"can_type": &"tcp_tuna:tuna_can",
	})
	_db.set_component(id, &"object_type", {
		&"type": &"tuna_dispenser",
	})
	_db.update_spatial(id, x, y)
	return id


func _make_button(
		rack: int, slot: int, dispenser_id: int,
) -> int:
	var id: int = _db.create_entity()
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = slot * Constants.SLOT_HEIGHT_PU
	_db.set_component(id, &"position", {
		&"x": x, &"y": y,
	})
	_db.set_component(id, &"tuna_button", {
		&"dispenser_id": dispenser_id,
	})
	_db.set_component(id, &"object_type", {
		&"type": &"tuna_button",
	})
	_db.update_spatial(id, x, y)
	return id


func _make_arm(rack: int) -> int:
	var id: int = _db.create_entity()
	var x: int = rack * Constants.RACK_WIDTH_PU
	@warning_ignore("integer_division")
	var y: int = (
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU
		+ Constants.FLOOR_HEIGHT_PU / 2
	)
	_db.set_component(id, &"position", {
		&"x": x, &"y": y,
	})
	_db.set_component(id, &"arm", {
		&"radius_ru": 3,
		&"hum_cost": 30,
		&"open_duration_ticks": 20,
	})
	_db.set_component(id, &"object_type", {
		&"type": &"arm",
	})
	_db.update_spatial(id, x, y)
	return id
