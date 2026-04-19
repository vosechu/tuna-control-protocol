class_name HumSystem extends RefCounted

const DEFAULT_CAPACITY: int = 10000
const IDLE_DRAIN_BASE: int = 5
const BROWNOUT_THRESHOLD: int = 250  # 25% of 1000 ratio

var _db: GameStateDB
var _events: Object
var _brownout_active: Dictionary = {}  # hum_id: int -> bool


func _init(db: GameStateDB, events: Object = null) -> void:
	_db = db
	_events = events


func has_reserve(hum_id: int, cost: int) -> bool:
	return _db.get_field(hum_id, &"hum", &"reserve") >= cost


func get_reserve(hum_id: int) -> int:
	return _db.get_field(hum_id, &"hum", &"reserve")


func get_capacity(hum_id: int) -> int:
	return _db.get_field(hum_id, &"hum", &"capacity")


func get_reserve_ratio(hum_id: int) -> int:
	var capacity: int = _db.get_field(hum_id, &"hum", &"capacity")
	if capacity <= 0:
		return 0
	var reserve: int = _db.get_field(hum_id, &"hum", &"reserve")
	return reserve * 1000 / capacity


func charge(hum_id: int, amount: int) -> void:
	var old_reserve: int = _db.get_field(hum_id, &"hum", &"reserve")
	var capacity: int = _db.get_field(hum_id, &"hum", &"capacity")
	_db.set_field(hum_id, &"hum", &"reserve", mini(old_reserve + amount, capacity))
	_emit_if_changed(hum_id, old_reserve)


func drain_action(hum_id: int, cost: int) -> void:
	var old_reserve: int = _db.get_field(hum_id, &"hum", &"reserve")
	_db.set_field(hum_id, &"hum", &"reserve", maxi(0, old_reserve - cost))
	_emit_if_changed(hum_id, old_reserve)


func drain_idle(hum_id: int) -> void:
	var old_reserve: int = _db.get_field(hum_id, &"hum", &"reserve")
	var capacity: int = _db.get_field(hum_id, &"hum", &"capacity")
	if old_reserve <= 0 or capacity <= 0:
		return
	# Idle drain scales with reserve ratio: full drain at 100%, near-zero at 0%
	var drain: int = maxi(1, IDLE_DRAIN_BASE * old_reserve / capacity)
	_db.set_field(hum_id, &"hum", &"reserve", maxi(0, old_reserve - drain))
	_emit_if_changed(hum_id, old_reserve)


func tick_idle_drain() -> void:
	for hum_id: int in _db.get_entities_with(&"hum"):
		drain_idle(hum_id)


func tick_charge() -> void:
	var receivers: Array[int] = _db.get_entities_with(&"hum_receiver")
	if receivers.is_empty():
		return
	var per_hum_charge: Dictionary = {}
	for emitter_id: int in _db.get_entities_with(&"purr"):
		var intensity: int = _db.get_field(emitter_id, &"purr", &"intensity")
		if intensity <= 0:
			continue
		var ex: int = _db.get_field(emitter_id, &"position", &"x")
		var ey: int = _db.get_field(emitter_id, &"position", &"y")
		var best_id: int = Constants.INVALID_ID
		var best_dist_sq: int = -1
		for r_id: int in receivers:
			var radius_px: int = _db.get_field(r_id, &"hum_receiver", &"radius_px")
			var rx: int = _db.get_field(r_id, &"position", &"x")
			var ry: int = _db.get_field(r_id, &"position", &"y")
			var dx: int = ex - rx
			var dy: int = ey - ry
			var dist_sq: int = dx * dx + dy * dy
			if dist_sq > radius_px * radius_px:
				continue
			if best_id == Constants.INVALID_ID \
					or dist_sq < best_dist_sq \
					or (dist_sq == best_dist_sq and r_id < best_id):
				best_id = r_id
				best_dist_sq = dist_sq
		if best_id == Constants.INVALID_ID:
			continue
		per_hum_charge[best_id] = per_hum_charge.get(best_id, 0) + intensity
	for hum_id: int in per_hum_charge:
		charge(hum_id, per_hum_charge[hum_id])


func _emit_if_changed(hum_id: int, old_reserve: int) -> void:
	if _events == null:
		return
	var new_reserve: int = _db.get_field(hum_id, &"hum", &"reserve")
	if old_reserve == new_reserve:
		return
	_events.hum_reserve_changed.emit(hum_id, old_reserve, new_reserve)
	var ratio: int = get_reserve_ratio(hum_id)
	var is_brownout: bool = ratio < BROWNOUT_THRESHOLD
	var was_brownout: bool = _brownout_active.get(hum_id, false)
	if is_brownout and not was_brownout:
		_events.hum_brownout_entered.emit(hum_id)
		_brownout_active[hum_id] = true
	elif not is_brownout and was_brownout:
		_events.hum_brownout_recovered.emit(hum_id)
		_brownout_active[hum_id] = false
