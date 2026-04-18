extends GutTest

const EventsScript: GDScript = preload("res://nodes/events.gd")

var _db: GameStateDB
var _events: Object
var _hum: HumSystem


func before_each() -> void:
	_db = GameStateDB.new()
	_events = EventsScript.new()
	_hum = HumSystem.new(_db, _events)


# ── Helpers ──────────────────────────────────────────────────────────────────

func _make_hum(capacity: int = HumSystem.DEFAULT_CAPACITY) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"hum", {
		&"reserve": capacity,
		&"capacity": capacity,
	})
	return id


func _make_hum_device(rack: int, slot: int, radius_ru: int) -> int:
	# Creates a combined hum+hum_receiver+position entity (mirrors the recipe).
	var id: int = _db.create_entity()
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = slot * Constants.SLOT_HEIGHT_PU
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"hum", {
		&"reserve": HumSystem.DEFAULT_CAPACITY,
		&"capacity": HumSystem.DEFAULT_CAPACITY,
	})
	_db.set_component(id, &"hum_receiver", {&"radius_ru": radius_ru})
	_db.update_spatial(id, x, y)
	return id


func _make_purring_entity(rack: int, slot: int, intensity: int) -> int:
	var id: int = _db.create_entity()
	var x: int = rack * Constants.RACK_WIDTH_PU
	var y: int = slot * Constants.SLOT_HEIGHT_PU
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"purr", {&"intensity": intensity})
	_db.update_spatial(id, x, y)
	return id


# ── Initialization ────────────────────────────────────────────────────────────

func test_new_hum_system_does_not_autocreate_entity():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# HumSystem is now stateless — no FACILITY_ID, no auto-spawned entity on init.
	assert_true(_db.get_entities_with(&"hum").is_empty(),
		"HumSystem constructor must NOT create any hum entity")


# ── Charging ──────────────────────────────────────────────────────────────────

func test_charge_adds_to_reserve():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum()
	_db.set_field(hum_id, &"hum", &"reserve", 500)
	_hum.charge(hum_id, 100)
	assert_eq(_hum.get_reserve(hum_id), 600,
		"Charging 100 from 500 should yield 600")


func test_charge_clamps_at_capacity():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum()
	_hum.charge(hum_id, 5000)
	assert_eq(_hum.get_reserve(hum_id), HumSystem.DEFAULT_CAPACITY,
		"Overcharging should clamp at capacity (%d)" % HumSystem.DEFAULT_CAPACITY)


# ── Idle drain ────────────────────────────────────────────────────────────────

func test_drain_idle_reduces_reserve():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum()
	var before: int = _hum.get_reserve(hum_id)
	_hum.drain_idle(hum_id)
	assert_lt(_hum.get_reserve(hum_id), before,
		"Idle drain should reduce reserve from full")


func test_drain_idle_slows_at_low_reserve():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum()
	# Drain at full capacity
	var full_reserve: int = HumSystem.DEFAULT_CAPACITY
	_db.set_field(hum_id, &"hum", &"reserve", full_reserve)
	_hum.drain_idle(hum_id)
	var drain_at_full: int = full_reserve - _hum.get_reserve(hum_id)

	# Drain at 25% capacity
	var quarter_reserve: int = HumSystem.DEFAULT_CAPACITY / 4
	_db.set_field(hum_id, &"hum", &"reserve", quarter_reserve)
	_hum.drain_idle(hum_id)
	var drain_at_quarter: int = quarter_reserve - _hum.get_reserve(hum_id)

	assert_lt(drain_at_quarter, drain_at_full,
		"Idle drain at 25%% reserve should be less than at 100%%")


func test_tick_idle_drain_iterates_all_hum_entities():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_a: int = _make_hum()
	var hum_b: int = _make_hum()
	var before_a: int = _hum.get_reserve(hum_a)
	var before_b: int = _hum.get_reserve(hum_b)
	_hum.tick_idle_drain()
	assert_lt(_hum.get_reserve(hum_a), before_a,
		"tick_idle_drain should drain hum_a")
	assert_lt(_hum.get_reserve(hum_b), before_b,
		"tick_idle_drain should drain hum_b")


# ── Action drain ──────────────────────────────────────────────────────────────

func test_drain_action_is_fixed_cost():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum()
	# Drain 50 at full reserve
	_db.set_field(hum_id, &"hum", &"reserve", HumSystem.DEFAULT_CAPACITY)
	_hum.drain_action(hum_id, 50)
	var after_full: int = _hum.get_reserve(hum_id)
	var drain_from_full: int = HumSystem.DEFAULT_CAPACITY - after_full

	# Drain 50 at 10% reserve
	var ten_pct: int = HumSystem.DEFAULT_CAPACITY / 10
	_db.set_field(hum_id, &"hum", &"reserve", ten_pct)
	_hum.drain_action(hum_id, 50)
	var drain_from_low: int = ten_pct - _hum.get_reserve(hum_id)

	assert_eq(drain_from_full, 50, "Action drain should take exactly 50 from full")
	assert_eq(drain_from_low, 50, "Action drain should take exactly 50 from 10%%")


func test_drain_action_can_reach_zero():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum()
	_db.set_field(hum_id, &"hum", &"reserve", 10)
	_hum.drain_action(hum_id, 100)
	assert_eq(_hum.get_reserve(hum_id), 0,
		"Draining 100 from reserve 10 should reach 0")


func test_reserve_never_goes_negative():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum()
	_db.set_field(hum_id, &"hum", &"reserve", 5)
	_hum.drain_action(hum_id, 1000)
	assert_eq(_hum.get_reserve(hum_id), 0,
		"Reserve should clamp at 0, never go negative")


# ── Has reserve ───────────────────────────────────────────────────────────────

func test_has_reserve_for_action():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum()
	_db.set_field(hum_id, &"hum", &"reserve", 50)
	assert_true(_hum.has_reserve(hum_id, 50),
		"has_reserve(50) should be true when reserve is exactly 50")
	assert_true(_hum.has_reserve(hum_id, 49),
		"has_reserve(49) should be true when reserve is 50")
	assert_false(_hum.has_reserve(hum_id, 51),
		"has_reserve(51) should be false when reserve is 50")


# ── Reserve ratio ─────────────────────────────────────────────────────────────

func test_get_reserve_ratio():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum()
	# Full
	assert_eq(_hum.get_reserve_ratio(hum_id), 1000,
		"Full reserve should yield ratio 1000")

	# Empty
	_db.set_field(hum_id, &"hum", &"reserve", 0)
	assert_eq(_hum.get_reserve_ratio(hum_id), 0,
		"Empty reserve should yield ratio 0")

	# Half
	_db.set_field(hum_id, &"hum", &"reserve", HumSystem.DEFAULT_CAPACITY / 2)
	assert_eq(_hum.get_reserve_ratio(hum_id), 500,
		"Half reserve should yield ratio 500")


# ── tick_charge ───────────────────────────────────────────────────────────────

func test_tick_charges_from_purring_emitter_near_receiver():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum_device(0, 5, 3)
	_db.set_field(hum_id, &"hum", &"reserve", 500)
	_make_purring_entity(0, 4, 10)
	_hum.tick_charge()
	assert_gt(_hum.get_reserve(hum_id), 500,
		"Purring emitter within receiver radius should charge the HUM reserve")


func test_tick_does_not_charge_from_emitter_outside_radius():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum_device(0, 0, 3)
	_db.set_field(hum_id, &"hum", &"reserve", 500)
	# Far away — rack 2 is thousands of PU from rack 0
	_make_purring_entity(2, 0, 10)
	_hum.tick_charge()
	assert_eq(_hum.get_reserve(hum_id), 500,
		"Purring emitter outside receiver radius should not charge the HUM")


func test_zero_intensity_emitter_does_not_charge():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum_device(0, 5, 3)
	_db.set_field(hum_id, &"hum", &"reserve", 500)
	_make_purring_entity(0, 4, 0)  # intensity = 0, should not charge
	_hum.tick_charge()
	assert_eq(_hum.get_reserve(hum_id), 500,
		"Zero-intensity purr emitter should not charge the HUM")


# ── HUM signals ───────────────────────────────────────────────────────────────

func test_charge_emits_hum_reserve_changed():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum()
	var received: Array[Array] = []
	_events.hum_reserve_changed.connect(
		func(h_id: int, old_val: int, new_val: int) -> void:
			received.append([h_id, old_val, new_val])
	)
	_db.set_field(hum_id, &"hum", &"reserve", 500)
	_hum.charge(hum_id, 100)
	assert_eq(received.size(), 1, "Should emit once")
	assert_eq(received[0][0], hum_id, "hum_id should be first arg")
	assert_eq(received[0][1], 500, "Old reserve should be 500")
	assert_eq(received[0][2], 600, "New reserve should be 600")


func test_brownout_entered_emitted_at_threshold():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum()
	var entered: Array[int] = [0]
	_events.hum_brownout_entered.connect(func(_h_id: int) -> void: entered[0] += 1)
	# Set reserve just above the 25% brownout threshold, then drain below
	var capacity: int = _db.get_field(hum_id, &"hum", &"capacity")
	_db.set_field(hum_id, &"hum", &"reserve", capacity / 4 + 1)
	_hum.drain_action(hum_id, 10)
	assert_eq(entered[0], 1, "Should emit brownout_entered when crossing below 25%%")


func test_brownout_recovered_emitted_on_recovery():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum()
	var recovered: Array[int] = [0]
	_events.hum_brownout_recovered.connect(func(_h_id: int) -> void: recovered[0] += 1)
	# Put into brownout first
	_db.set_field(hum_id, &"hum", &"reserve", 100)
	_hum.drain_action(hum_id, 1)  # triggers brownout_entered, sets brownout active
	# Charge back above threshold
	var capacity: int = _db.get_field(hum_id, &"hum", &"capacity")
	_hum.charge(hum_id, capacity / 4 + 100)
	assert_eq(recovered[0], 1, "Should emit brownout_recovered when crossing above 25%%")
