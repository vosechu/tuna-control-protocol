class_name FoodSystem extends RefCounted

const CAN_DESPAWN_TICKS: int = 100  # ~10 seconds at 10Hz

var _db: GameStateDB
var _hum: HumSystem
var _events: Object


func _init(
		db: GameStateDB, hum: HumSystem, events: Object,
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

	if not _db.has_entity(dispenser_id) \
			or not _db.has_component(dispenser_id, &"tuna_dispenser"):
		return Constants.INVALID_ID

	# Same-rack check
	var button_pos: Dictionary = _db.get_component(
		button_id, &"position",
	)
	var disp_pos: Dictionary = _db.get_component(
		dispenser_id, &"position",
	)
	var button_rack: int = _rack_of(button_pos)
	var disp_rack: int = _rack_of(disp_pos)
	if button_rack != disp_rack or button_rack == Constants.INVALID_ID:
		return Constants.INVALID_ID

	# HUM cost check — drains the first HUM with reserve (cable-free).
	var disp_data: Dictionary = _db.get_component(
		dispenser_id, &"tuna_dispenser",
	)
	var cost: int = disp_data[&"hum_cost"]
	var hum_id: int = is_powered(dispenser_id, cost)
	if hum_id == Constants.INVALID_ID:
		return Constants.INVALID_ID

	# Dispense
	_hum.drain_action(hum_id, cost)
	var can_id: int = _db.create_entity()
	var can_x: int = disp_pos[&"x"]
	# Drop at floor level (quarter-depth into the floor strip).
	var floor_rect: Rect2i = Constants.floor_rect_world(0)
	var can_y: int = floor_rect.position.y + floor_rect.size.y / 4
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
		var radius_px: int = arm_data[&"radius_px"]
		var cost: int = arm_data[&"hum_cost"]
		var arm_hum_id: int = is_powered(arm_id, cost)
		if arm_hum_id == Constants.INVALID_ID:
			continue

		var nearby: Array[int] = _db.query_radius(
			arm_pos[&"x"], arm_pos[&"y"], radius_px,
		)
		for entity_id: int in nearby:
			if not _db.has_component(entity_id, &"tuna_can"):
				continue
			var can: Dictionary = _db.get_component(
				entity_id, &"tuna_can",
			)
			if can[&"state"] != &"sealed":
				continue
			if not _hum.has_reserve(arm_hum_id, cost):
				break
			_hum.drain_action(arm_hum_id, cost)
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
					&"radius_px": 48,
					&"max_occupants": 1,
					&"action": &"eat",
				}]},
			)
			if _events and _events.has_signal(&"can_opened"):
				_events.can_opened.emit(entity_id)


func is_powered(_device_id: int, cost: int) -> int:
	# AI-DEV: Cable-free reduction of the original gate. Returns the first
	# HUM with enough reserve to cover `cost`, or Constants.INVALID_ID. When
	# the cable layer comes back (see hum-cable-system.md) restore the
	# hum_powered / hum_cable / per-device routing here.
	for hum_id: int in _db.get_entities_with(&"hum"):
		if _hum.has_reserve(hum_id, cost):
			return hum_id
	return Constants.INVALID_ID


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


# ── Food-finders ─────────────────────────────────────────────────────────────
# Promoted from GameServer private helpers so AiStateSystem can call them
# without a GameServer reference.

func find_nearby_food(entity_id: int) -> int:
	# Returns the nearest entity carrying an `opened` tuna_can within ~3
	# slot heights, or INVALID_ID. Sealed cans are deliberately excluded:
	# hungry cats must wait for the arm to open them, otherwise they'd
	# crowd a can the arm hasn't processed yet.
	var pos: Dictionary = _db.get_component(entity_id, &"position")
	var nearby: Array[int] = _db.query_radius(
		pos[&"x"], pos[&"y"], 3 * Constants.SLOT_HEIGHT_PX,
	)
	for other_id: int in nearby:
		if _db.has_component(other_id, &"tuna_can"):
			var can: Dictionary = _db.get_component(other_id, &"tuna_can")
			if can[&"state"] == &"opened":
				return other_id
	return Constants.INVALID_ID


func find_nearest_box(entity_id: int) -> int:
	# Returns the nearest cardboard_box anywhere in the world, by Manhattan
	# distance. No radius cap — RETURNING after EATING walks across a bay.
	var pos: Dictionary = _db.get_component(entity_id, &"position")
	var objects: Array[int] = _db.get_entities_with(&"object_type")
	var best_id: int = Constants.INVALID_ID
	var best_dist: int = 999999
	for obj_id: int in objects:
		var otype: Dictionary = _db.get_component(obj_id, &"object_type")
		if otype[&"type"] != &"cardboard_box":
			continue
		var opos: Dictionary = _db.get_component(obj_id, &"position")
		var dist: int = (
			absi(opos[&"x"] - pos[&"x"])
			+ absi(opos[&"y"] - pos[&"y"])
		)
		if dist < best_dist:
			best_dist = dist
			best_id = obj_id
	return best_id


func find_nearest_dispenser(entity_id: int, nav: NavGraphBuilder) -> int:
	# Thin wrapper over CatFoodStates so EATING completion has a single
	# canonical lookup. Takes nav as a param because AiStateSystem doesn't
	# hold a reference and the existing helper signature requires it.
	return CatFoodStates.find_nearest_dispenser(_db, entity_id, nav)


func mark_nearest_can_eaten(entity_id: int) -> void:
	# Called by EATING completion. Finds the nearest opened can and marks
	# it `eaten` (which kills its advertisements so other cats stop
	# routing toward it). No-op when there's no food in range — losing a
	# race to another cat is normal.
	var food_id: int = find_nearby_food(entity_id)
	if food_id != Constants.INVALID_ID:
		var can: Dictionary = _db.get_component(food_id, &"tuna_can")
		can[&"state"] = &"eaten"
		_db.set_component(food_id, &"tuna_can", can)
		_db.remove_component(food_id, &"advertisements")


func _rack_of(pos: Dictionary) -> int:
	var world_pos := Vector2i(pos[&"x"], pos[&"y"])
	var bay: int = Constants.world_to_bay(world_pos)
	if bay == Constants.INVALID_BAY:
		return Constants.INVALID_ID
	var q: SlotQuery = Constants.bay_local_to_slot(bay, world_pos)
	if q.zone == &"other":
		return Constants.INVALID_ID
	return q.rack
