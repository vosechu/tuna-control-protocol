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
	# Inversion: cats own emission geometry (purr.radius_px). HUMs are passive
	# bodies whose receiving area is their physical body rect. Every receiver
	# whose body rect intersects the cat's emission disk is charged.
	var receivers: Array[int] = _db.get_entities_with(&"hum_receiver")
	if receivers.is_empty():
		return
	var per_hum_charge: Dictionary = {}
	for emitter_id: int in _db.get_entities_with(&"purr"):
		var intensity: int = _db.get_field(emitter_id, &"purr", &"intensity")
		if intensity <= 0:
			continue
		var radius_px: int = _db.get_field(emitter_id, &"purr", &"radius_px")
		if radius_px <= 0:
			continue
		var ex: int = _db.get_field(emitter_id, &"position", &"x")
		var ey: int = _db.get_field(emitter_id, &"position", &"y")
		for r_id: int in receivers:
			var rect: Rect2i = _hum_body_rect(r_id)
			if not _disk_intersects_rect(ex, ey, radius_px, rect):
				continue
			per_hum_charge[r_id] = per_hum_charge.get(r_id, 0) + intensity
	for hum_id: int in per_hum_charge:
		charge(hum_id, per_hum_charge[hum_id])


# HUM body rect: anchored at the slot containing the HUM's position; extends
# upward through size_ru slots (slot 0 is bottom, so a 6U HUM placed with its
# anchor at slot 9 occupies slots 4..9 — the rect's top sits at the anchor
# slot's top edge and runs down size_ru * SLOT_HEIGHT_PX).
func _hum_body_rect(hum_id: int) -> Rect2i:
	var px: int = _db.get_field(hum_id, &"position", &"x")
	var py: int = _db.get_field(hum_id, &"position", &"y")
	var size_ru: int = _db.get_field(hum_id, &"physical", &"size_ru")
	var height_px: int = size_ru * Constants.SLOT_HEIGHT_PX
	var anchor_slot_rect: Rect2i = _slot_rect_for_position(px, py)
	return Rect2i(
		anchor_slot_rect.position.x,
		anchor_slot_rect.position.y,
		Constants.RACK_WIDTH_PX,
		height_px,
	)


func _slot_rect_for_position(px: int, py: int) -> Rect2i:
	var bay_origin: Vector2i = Constants.bay_origin_world(0)
	var bay_local: Vector2i = Vector2i(px - bay_origin.x, py - bay_origin.y)
	var query: SlotQuery = Constants.bay_local_to_slot(0, bay_local)
	if query.zone != &"slot":
		return Rect2i(
			px - Constants.RACK_WIDTH_PX / 2,
			py - Constants.SLOT_HEIGHT_PX / 2,
			Constants.RACK_WIDTH_PX,
			Constants.SLOT_HEIGHT_PX,
		)
	return Constants.slot_rect_world(0, query.get_rack(), query.get_slot())


func _disk_intersects_rect(cx: int, cy: int, radius_px: int, rect: Rect2i) -> bool:
	var rx_min: int = rect.position.x
	var rx_max: int = rect.position.x + rect.size.x
	var ry_min: int = rect.position.y
	var ry_max: int = rect.position.y + rect.size.y
	var qx: int = clampi(cx, rx_min, rx_max)
	var qy: int = clampi(cy, ry_min, ry_max)
	var dx: int = cx - qx
	var dy: int = cy - qy
	return dx * dx + dy * dy <= radius_px * radius_px


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
