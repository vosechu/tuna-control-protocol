class_name FoodSystem extends RefCounted

const CAN_DESPAWN_TICKS: int = 100  # ~10 seconds at 10Hz

var _db: GameStateDB
var _hum: HumSystem
var _events: RefCounted


func _init(
		db: GameStateDB, hum: HumSystem, events: RefCounted,
) -> void:
	_db = db
	_hum = hum
	_events = events


func press_button(button_id: int) -> int:
	if not _db.has_component(button_id, &"tuna_button"):
		return Constants.INVALID_ID

	var button_data: Dictionary = _db.get_component(
		button_id, &"tuna_button",
	)
	var dispenser_id: int = button_data[&"dispenser_id"]

	if not _db.has_entity(dispenser_id):
		return Constants.INVALID_ID
	if not _db.has_component(dispenser_id, &"tuna_dispenser"):
		return Constants.INVALID_ID

	# Same-rack check
	var button_pos: Dictionary = _db.get_component(
		button_id, &"position",
	)
	var disp_pos: Dictionary = _db.get_component(
		dispenser_id, &"position",
	)
	@warning_ignore("integer_division")
	var button_rack: int = (
		button_pos[&"x"] / Constants.RACK_WIDTH_PU
	)
	@warning_ignore("integer_division")
	var disp_rack: int = (
		disp_pos[&"x"] / Constants.RACK_WIDTH_PU
	)
	if button_rack != disp_rack:
		return Constants.INVALID_ID

	# HUM cost check
	var disp_data: Dictionary = _db.get_component(
		dispenser_id, &"tuna_dispenser",
	)
	var cost: int = disp_data[&"hum_cost"]
	if not _hum.has_reserve(cost):
		return Constants.INVALID_ID

	# Dispense
	_hum.drain_action(cost)
	var can_id: int = _db.create_entity()
	var can_x: int = disp_pos[&"x"]
	@warning_ignore("integer_division")
	var can_y: int = (
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU
		+ Constants.FLOOR_HEIGHT_PU / 4
	)
	_db.set_component(can_id, &"position", {
		&"x": can_x, &"y": can_y,
	})
	_db.set_component(can_id, &"tuna_can", {
		&"state": &"sealed", &"despawn_timer": 0,
	})
	_db.set_component(can_id, &"object_type", {
		&"type": &"tuna_can",
	})
	_db.update_spatial(can_id, can_x, can_y)
	return can_id


func tick_arms() -> void:
	var arms: Array[int] = _db.get_entities_with(&"arm")
	for arm_id: int in arms:
		if not _db.has_component(arm_id, &"position"):
			continue
		var arm_data: Dictionary = _db.get_component(
			arm_id, &"arm",
		)
		var arm_pos: Dictionary = _db.get_component(
			arm_id, &"position",
		)
		var radius_pu: int = Constants.ru_to_pu(
			arm_data[&"radius_ru"],
		)
		var cost: int = arm_data[&"hum_cost"]

		if not _hum.has_reserve(cost):
			continue

		var nearby: Array[int] = _db.query_radius(
			arm_pos[&"x"], arm_pos[&"y"], radius_pu,
		)
		for entity_id: int in nearby:
			if not _db.has_component(entity_id, &"tuna_can"):
				continue
			var can: Dictionary = _db.get_component(
				entity_id, &"tuna_can",
			)
			if can[&"state"] != &"sealed":
				continue
			if not _hum.has_reserve(cost):
				break
			_hum.drain_action(cost)
			var updated: Dictionary = _db.get_component(
				entity_id, &"tuna_can",
			)
			updated[&"state"] = &"opened"
			_db.set_component(
				entity_id, &"tuna_can", updated,
			)
			_db.set_component(
				entity_id, &"advertisements",
				{&"list": [{
					&"desire_type": &"hunger",
					&"strength": 900,
					&"radius_ru": 6,
					&"max_occupants": 1,
				}]},
			)


func tick_cleanup() -> void:
	var cans: Array[int] = _db.get_entities_with(&"tuna_can")
	var to_remove: Array[int] = []
	for can_id: int in cans:
		var can: Dictionary = _db.get_component(
			can_id, &"tuna_can",
		)
		if can[&"state"] == &"eaten":
			var timer: int = can[&"despawn_timer"] + 1
			if timer >= CAN_DESPAWN_TICKS:
				to_remove.append(can_id)
			else:
				_db.set_field(
					can_id, &"tuna_can",
					&"despawn_timer", timer,
				)
	for can_id: int in to_remove:
		_db.remove_spatial(can_id)
		_db.destroy_entity(can_id)
