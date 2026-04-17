class_name PlantGrowthSystem extends RefCounted

const _STATE := preload("res://engine/growth/plant_growth_state.gd")

var _db: GameStateDB
var _heat_grid: Object


func _init(db: GameStateDB, heat_grid: Object) -> void:
	_db = db
	_heat_grid = heat_grid


func tick() -> void:
	var entities: Array[int] = _db.get_entities_with(&"plant_growth")
	for entity_id: int in entities:
		_evaluate(entity_id)


func _evaluate(entity_id: int) -> void:
	var growth: Dictionary = _db.get_component(entity_id, &"plant_growth")
	var state: StringName = growth[&"state"]
	var tended_seconds: int = growth[&"tended_seconds"]

	var pos: Dictionary = _db.get_component(entity_id, &"position")
	var slot_key: int = _slot_key_for(pos)
	var warmth: int = _heat_grid.get_temperature(slot_key)

	var reclamation: Dictionary = _db.get_component(entity_id, &"reclamation")
	var cats_here: bool = reclamation[&"seconds"] > 0

	match state:
		_STATE.DORMANT:
			if warmth >= _STATE.WARMTH_MIN and cats_here:
				_transition(entity_id, _STATE.ARMED, tended_seconds)
		_STATE.ARMED:
			if cats_here:
				tended_seconds += 10
			if tended_seconds >= _STATE.GROW_THRESHOLD_SECONDS:
				_transition(entity_id, _STATE.PRESENT, tended_seconds)
			elif warmth < _STATE.WARMTH_MIN / 2 and not cats_here:
				_transition(entity_id, _STATE.DORMANT, 0)
			else:
				_db.set_field(entity_id, &"plant_growth", &"tended_seconds", tended_seconds)
		_STATE.PRESENT:
			if reclamation[&"seconds"] < _STATE.DECAY_THRESHOLD_SECONDS:
				_transition(entity_id, _STATE.DORMANT, 0)


func _transition(entity_id: int, new_state: StringName, new_tended_seconds: int) -> void:
	var growth: Dictionary = _db.get_component(entity_id, &"plant_growth")
	var old_state: StringName = growth[&"state"]
	growth[&"state"] = new_state
	growth[&"tended_seconds"] = new_tended_seconds
	_db.set_component(entity_id, &"plant_growth", growth)

	if old_state != _STATE.PRESENT and new_state == _STATE.PRESENT:
		_register_comfort_advertisement(entity_id)
		Events.plant_spawned.emit(entity_id)
	elif old_state == _STATE.PRESENT and new_state != _STATE.PRESENT:
		_remove_comfort_advertisement(entity_id)
		Events.plant_despawned.emit(entity_id)


func _register_comfort_advertisement(server_id: int) -> void:
	var ads: Array = []
	if _db.has_component(server_id, &"advertisements"):
		ads = _db.get_component(server_id, &"advertisements").get(&"list", [])
	ads.append({
		&"source": &"plant_growth",
		&"desire_type": &"comfort",
		&"strength": _STATE.PLANT_COMFORT_STRENGTH,
		&"radius_ru": _STATE.PLANT_ADVERT_RADIUS_RU,
	})
	_db.set_component(server_id, &"advertisements", {&"list": ads})


func _remove_comfort_advertisement(server_id: int) -> void:
	if not _db.has_component(server_id, &"advertisements"):
		return
	var ads: Array = _db.get_component(server_id, &"advertisements").get(&"list", [])
	var filtered: Array = []
	for ad: Dictionary in ads:
		if ad.get(&"source", &"") != &"plant_growth":
			filtered.append(ad)
	_db.set_component(server_id, &"advertisements", {&"list": filtered})


func _slot_key_for(pos: Dictionary) -> int:
	var info: Dictionary = Constants.pu_to_bay_rack_slot(pos[&"x"], pos[&"y"])
	return Constants.rack_cell(info[&"rack"], info[&"slot"])
