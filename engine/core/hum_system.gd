class_name HumSystem extends RefCounted

const FACILITY_ID: int = 0
const DEFAULT_CAPACITY: int = 10000
const IDLE_DRAIN_BASE: int = 5
const CHARGE_PER_PURRING_CAT: int = 10

var _db: GameStateDB


func _init(db: GameStateDB) -> void:
	_db = db
	_db.create_entity_with_id(FACILITY_ID)
	_db.set_component(FACILITY_ID, &"hum", {
		&"reserve": DEFAULT_CAPACITY,
		&"capacity": DEFAULT_CAPACITY,
	})


func charge(amount: int) -> void:
	var capacity: int = _db.get_field(FACILITY_ID, &"hum", &"capacity")
	var reserve: int = _db.get_field(FACILITY_ID, &"hum", &"reserve")
	_db.set_field(FACILITY_ID, &"hum", &"reserve", mini(reserve + amount, capacity))


func drain_idle() -> void:
	var reserve: int = _db.get_field(FACILITY_ID, &"hum", &"reserve")
	var capacity: int = _db.get_field(FACILITY_ID, &"hum", &"capacity")
	if reserve <= 0 or capacity <= 0:
		return
	# Idle drain scales with reserve ratio: full drain at 100%, near-zero at 0%
	@warning_ignore("integer_division")
	var drain: int = maxi(1, IDLE_DRAIN_BASE * reserve / capacity)
	_db.set_field(FACILITY_ID, &"hum", &"reserve", maxi(0, reserve - drain))


func drain_action(cost: int) -> void:
	var reserve: int = _db.get_field(FACILITY_ID, &"hum", &"reserve")
	_db.set_field(FACILITY_ID, &"hum", &"reserve", maxi(0, reserve - cost))


func has_reserve(cost: int) -> bool:
	return _db.get_field(FACILITY_ID, &"hum", &"reserve") >= cost


func get_reserve() -> int:
	return _db.get_field(FACILITY_ID, &"hum", &"reserve")


func get_capacity() -> int:
	return _db.get_field(FACILITY_ID, &"hum", &"capacity")


func tick_charge() -> void:
	var receivers: Array[int] = _db.get_entities_with(&"hum_receiver")
	var purring_near_receiver: int = 0
	for receiver_id: int in receivers:
		if not _db.has_component(receiver_id, &"position"):
			continue
		var rpos: Dictionary = _db.get_component(receiver_id, &"position")
		var radius_ru: int = _db.get_field(receiver_id, &"hum_receiver", &"radius_ru")
		var radius_pu: int = Constants.ru_to_pu(radius_ru)
		var nearby: Array[int] = _db.query_radius(rpos[&"x"], rpos[&"y"], radius_pu)
		for entity_id: int in nearby:
			if not _db.has_component(entity_id, &"contentment"):
				continue
			if _db.get_field(entity_id, &"contentment", &"is_purring") == 1:
				purring_near_receiver += 1
	if purring_near_receiver > 0:
		charge(purring_near_receiver * CHARGE_PER_PURRING_CAT)


func get_reserve_ratio() -> int:
	var capacity: int = _db.get_field(FACILITY_ID, &"hum", &"capacity")
	if capacity <= 0:
		return 0
	var reserve: int = _db.get_field(FACILITY_ID, &"hum", &"reserve")
	@warning_ignore("integer_division")
	return reserve * 1000 / capacity
