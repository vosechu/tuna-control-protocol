class_name HumSystem extends RefCounted

const FACILITY_ID: int = 0
const DEFAULT_CAPACITY: int = 10000
const IDLE_DRAIN_BASE: int = 5
const CHARGE_PER_SATISFIED_ENTITY: int = 10

const BROWNOUT_THRESHOLD: int = 250  # 25% of 1000 ratio

var _db: GameStateDB
var _events: Object
var _was_brownout: bool = false


func _init(db: GameStateDB, events: Object = null) -> void:
	_db = db
	_events = events
	_db.create_entity_with_id(FACILITY_ID)
	_db.set_component(FACILITY_ID, &"hum", {
		&"reserve": DEFAULT_CAPACITY,
		&"capacity": DEFAULT_CAPACITY,
	})


func charge(amount: int) -> void:
	var old_reserve: int = _db.get_field(FACILITY_ID, &"hum", &"reserve")
	var capacity: int = _db.get_field(FACILITY_ID, &"hum", &"capacity")
	_db.set_field(FACILITY_ID, &"hum", &"reserve", mini(old_reserve + amount, capacity))
	_emit_if_changed(old_reserve)


func drain_idle() -> void:
	var old_reserve: int = _db.get_field(FACILITY_ID, &"hum", &"reserve")
	var capacity: int = _db.get_field(FACILITY_ID, &"hum", &"capacity")
	if old_reserve <= 0 or capacity <= 0:
		return
	# Idle drain scales with reserve ratio: full drain at 100%, near-zero at 0%
	var drain: int = maxi(1, IDLE_DRAIN_BASE * old_reserve / capacity)
	_db.set_field(FACILITY_ID, &"hum", &"reserve", maxi(0, old_reserve - drain))
	_emit_if_changed(old_reserve)


func drain_action(cost: int) -> void:
	var old_reserve: int = _db.get_field(FACILITY_ID, &"hum", &"reserve")
	_db.set_field(FACILITY_ID, &"hum", &"reserve", maxi(0, old_reserve - cost))
	_emit_if_changed(old_reserve)


func has_reserve(cost: int) -> bool:
	return _db.get_field(FACILITY_ID, &"hum", &"reserve") >= cost


func get_reserve() -> int:
	return _db.get_field(FACILITY_ID, &"hum", &"reserve")


func get_capacity() -> int:
	return _db.get_field(FACILITY_ID, &"hum", &"capacity")


func tick_charge() -> void:
	var receivers: Array[int] = _db.get_entities_with(&"hum_receiver")
	var satisfied_near_receiver: int = 0
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
			if _db.get_field(entity_id, &"contentment", &"is_satisfied") == 1:
				satisfied_near_receiver += 1
	if satisfied_near_receiver > 0:
		charge(satisfied_near_receiver * CHARGE_PER_SATISFIED_ENTITY)


func get_reserve_ratio() -> int:
	var capacity: int = _db.get_field(FACILITY_ID, &"hum", &"capacity")
	if capacity <= 0:
		return 0
	var reserve: int = _db.get_field(FACILITY_ID, &"hum", &"reserve")
	return reserve * 1000 / capacity


func _emit_if_changed(old_reserve: int) -> void:
	if _events == null:
		return
	var new_reserve: int = _db.get_field(FACILITY_ID, &"hum", &"reserve")
	if old_reserve == new_reserve:
		return
	_events.hum_reserve_changed.emit(old_reserve, new_reserve)
	var ratio: int = get_reserve_ratio()
	var is_brownout: bool = ratio < BROWNOUT_THRESHOLD
	if is_brownout and not _was_brownout:
		_events.hum_brownout_entered.emit()
		_was_brownout = true
	elif not is_brownout and _was_brownout:
		_events.hum_brownout_recovered.emit()
		_was_brownout = false
