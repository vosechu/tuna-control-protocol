extends GutTest

var _db: GameStateDB
var _hum: HumSystem


func before_each() -> void:
	_db = GameStateDB.new()
	_hum = HumSystem.new(_db)


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
