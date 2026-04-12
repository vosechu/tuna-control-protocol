extends GutTest

const EventsScript: GDScript = preload("res://nodes/events.gd")

var _db: GameStateDB
var _events: Object
var _hum: HumSystem


func before_each() -> void:
	_db = GameStateDB.new()
	_events = EventsScript.new()
	_hum = HumSystem.new(_db, _events)


# ── Initialization ──────────────────────────────────────────────────────────

func test_facility_entity_created_on_init():
	assert_true(_db.has_entity(HumSystem.FACILITY_ID),
		"Facility entity (ID 0) should exist after HumSystem init")
	assert_true(_db.has_component(HumSystem.FACILITY_ID, &"hum"),
		"Facility entity should have a hum component")


func test_initial_reserve_is_at_capacity():
	assert_eq(_hum.get_reserve(), HumSystem.DEFAULT_CAPACITY,
		"Reserve should start at full capacity (%d)" % HumSystem.DEFAULT_CAPACITY)


# ── Charging ────────────────────────────────────────────────────────────────

func test_charge_adds_to_reserve():
	# Drain to 500, then charge 100
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", 500)
	_hum.charge(100)
	assert_eq(_hum.get_reserve(), 600,
		"Charging 100 from 500 should yield 600")


func test_charge_clamps_at_capacity():
	_hum.charge(5000)
	assert_eq(_hum.get_reserve(), HumSystem.DEFAULT_CAPACITY,
		"Overcharging should clamp at capacity (%d)" % HumSystem.DEFAULT_CAPACITY)


# ── Idle drain ──────────────────────────────────────────────────────────────

func test_drain_idle_reduces_reserve():
	var before: int = _hum.get_reserve()
	_hum.drain_idle()
	assert_lt(_hum.get_reserve(), before,
		"Idle drain should reduce reserve from full")


func test_drain_idle_slows_at_low_reserve():
	# Drain at full capacity
	var full_reserve: int = HumSystem.DEFAULT_CAPACITY
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", full_reserve)
	_hum.drain_idle()
	var drain_at_full: int = full_reserve - _hum.get_reserve()

	# Drain at 25% capacity
	@warning_ignore("integer_division")
	var quarter_reserve: int = HumSystem.DEFAULT_CAPACITY / 4
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", quarter_reserve)
	_hum.drain_idle()
	var drain_at_quarter: int = quarter_reserve - _hum.get_reserve()

	assert_lt(drain_at_quarter, drain_at_full,
		"Idle drain at 25%% reserve (%d) should be less than at 100%% (%d)" % [
			drain_at_quarter, drain_at_full])


# ── Action drain ────────────────────────────────────────────────────────────

func test_drain_action_is_fixed_cost():
	# Drain 50 at full reserve
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", HumSystem.DEFAULT_CAPACITY)
	_hum.drain_action(50)
	var after_full: int = _hum.get_reserve()
	var drain_from_full: int = HumSystem.DEFAULT_CAPACITY - after_full

	# Drain 50 at 10% reserve
	@warning_ignore("integer_division")
	var ten_pct: int = HumSystem.DEFAULT_CAPACITY / 10
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", ten_pct)
	_hum.drain_action(50)
	var drain_from_low: int = ten_pct - _hum.get_reserve()

	assert_eq(drain_from_full, 50, "Action drain should take exactly 50 from full")
	assert_eq(drain_from_low, 50, "Action drain should take exactly 50 from 10%%")


func test_drain_action_can_reach_zero():
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", 10)
	_hum.drain_action(100)
	assert_eq(_hum.get_reserve(), 0,
		"Draining 100 from reserve 10 should reach 0")


func test_reserve_never_goes_negative():
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", 5)
	_hum.drain_action(1000)
	assert_eq(_hum.get_reserve(), 0,
		"Reserve should clamp at 0, never go negative")


# ── Has reserve ─────────────────────────────────────────────────────────────

func test_has_reserve_for_action():
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", 50)
	assert_true(_hum.has_reserve(50),
		"has_reserve(50) should be true when reserve is exactly 50")
	assert_true(_hum.has_reserve(49),
		"has_reserve(49) should be true when reserve is 50")
	assert_false(_hum.has_reserve(51),
		"has_reserve(51) should be false when reserve is 50")


# ── Reserve ratio ───────────────────────────────────────────────────────────

func test_get_reserve_ratio():
	# Full
	assert_eq(_hum.get_reserve_ratio(), 1000,
		"Full reserve should yield ratio 1000")

	# Empty
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", 0)
	assert_eq(_hum.get_reserve_ratio(), 0,
		"Empty reserve should yield ratio 0")

	# Half
	@warning_ignore("integer_division")
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", HumSystem.DEFAULT_CAPACITY / 2)
	assert_eq(_hum.get_reserve_ratio(), 500,
		"Half reserve should yield ratio 500")


# ── tick_charge ────────────────────────────────────────────────────────────

func test_tick_charges_from_purring_cat_near_receiver():
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", 500)
	_make_receiver(0, 5, 3)
	_make_purring_cat(0, 4)
	_hum.tick_charge()
	assert_gt(_hum.get_reserve(), 500,
		"Purring cat within receiver radius should charge the HUM reserve")


func test_tick_does_not_charge_from_cat_outside_radius():
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", 500)
	_make_receiver(0, 0, 3)
	_make_purring_cat(2, 0)  # Far away — rack 2 is thousands of PU from rack 0
	_hum.tick_charge()
	assert_eq(_hum.get_reserve(), 500,
		"Purring cat outside receiver radius should not charge the HUM")


func test_non_purring_cat_does_not_charge():
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", 500)
	_make_receiver(0, 5, 3)
	var cat_id: int = _make_purring_cat(0, 4)
	# Override is_purring to 0 (not purring)
	_db.set_field(cat_id, &"contentment", &"is_purring", 0)
	_hum.tick_charge()
	assert_eq(_hum.get_reserve(), 500,
		"Non-purring cat should not charge the HUM")


# ── HUM signals ────────────────────────────────────────────────────────────

func test_charge_emits_hum_reserve_changed():
	var received: Array[Array] = []
	_events.hum_reserve_changed.connect(func(old_val: int, new_val: int) -> void:
		received.append([old_val, new_val]))
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", 500)
	_hum.charge(100)
	assert_eq(received.size(), 1, "Should emit once")
	assert_eq(received[0][0], 500, "Old reserve should be 500")
	assert_eq(received[0][1], 600, "New reserve should be 600")


func test_brownout_entered_emitted_at_threshold():
	var entered: Array[int] = [0]
	_events.hum_brownout_entered.connect(func() -> void: entered[0] += 1)
	# Set reserve just above the 25% brownout threshold, then drain below
	var capacity: int = _db.get_field(HumSystem.FACILITY_ID, &"hum", &"capacity")
	@warning_ignore("integer_division")
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", capacity / 4 + 1)
	_hum.drain_action(10)
	assert_eq(entered[0], 1, "Should emit brownout_entered when crossing below 25%%")


func test_brownout_recovered_emitted_on_recovery():
	var recovered: Array[int] = [0]
	_events.hum_brownout_recovered.connect(func() -> void: recovered[0] += 1)
	# Put into brownout first
	_db.set_field(HumSystem.FACILITY_ID, &"hum", &"reserve", 100)
	_hum.drain_action(1)  # triggers brownout_entered, sets _was_brownout
	# Charge back above threshold
	var capacity: int = _db.get_field(HumSystem.FACILITY_ID, &"hum", &"capacity")
	@warning_ignore("integer_division")
	_hum.charge(capacity / 4 + 100)
	assert_eq(recovered[0], 1, "Should emit brownout_recovered when crossing above 25%%")


# ── Helpers ────────────────────────────────────────────────────────────────

func _make_receiver(rack: int, slot: int, radius_ru: int) -> int:
	var id: int = _db.create_entity()
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = slot * Constants.SLOT_HEIGHT_PU
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"hum_receiver", {&"radius_ru": radius_ru})
	_db.update_spatial(id, x, y)
	return id


func _make_purring_cat(rack: int, slot: int) -> int:
	var id: int = _db.create_entity()
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = slot * Constants.SLOT_HEIGHT_PU
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"contentment", {&"is_purring": 1})
	_db.set_component(id, &"species", {&"id": &"tcp_cats:cat", &"variant": &"cat01", &"name": &"Test"})
	_db.update_spatial(id, x, y)
	return id
