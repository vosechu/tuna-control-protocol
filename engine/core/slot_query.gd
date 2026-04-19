class_name SlotQuery extends RefCounted

# AI-DEV: Returned by Constants.bay_local_to_slot. `zone` is the typed
# discriminator. Use get_slot()/get_rack() accessors — they assert on misuse.
# Construct with the explicit factory helpers below, not bare .new(...).

var rack: int = Constants.INVALID_ID
var slot: int = Constants.INVALID_SLOT
var zone: StringName = &"other"


static func make_slot(rack_idx: int, slot_idx: int) -> SlotQuery:
	var q := SlotQuery.new()
	q.rack = rack_idx
	q.slot = slot_idx
	q.zone = &"slot"
	return q


static func make_frame(rack_idx: int) -> SlotQuery:
	var q := SlotQuery.new()
	q.rack = rack_idx
	q.zone = &"frame"
	return q


static func make_baseboard(rack_idx: int) -> SlotQuery:
	var q := SlotQuery.new()
	q.rack = rack_idx
	q.zone = &"baseboard"
	return q


static func make_floor(rack_idx: int) -> SlotQuery:
	var q := SlotQuery.new()
	q.rack = rack_idx
	q.zone = &"floor"
	return q


static func make_other() -> SlotQuery:
	return SlotQuery.new()


func get_slot() -> int:
	assert(zone == &"slot", "SlotQuery.get_slot() called with zone=%s" % zone)
	return slot


func get_rack() -> int:
	assert(zone != &"other", "SlotQuery.get_rack() called with zone=&\"other\"")
	return rack
