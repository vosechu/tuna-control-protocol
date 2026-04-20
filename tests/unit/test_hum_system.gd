extends GutTest

# AI-DEV: This file was restructured to eliminate paired invariants and
# integration-duplicates. HumSystem's API is small but broadly used — the
# charge/drain_action/drain_idle paths are also exercised by
# tests/integration/{test_hum_tick,test_two_hums,test_hum_despawn_tombstone}.
# Several unit tests were merged or deleted to keep each remaining test
# targetable with a single surgical mutation.

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


# ── Initialization ────────────────────────────────────────────────────────────

func test_new_hum_system_does_not_autocreate_entity():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# HumSystem is stateless — no FACILITY_ID, no auto-spawn on construct.
	assert_true(_db.get_entities_with(&"hum").is_empty(),
		"HumSystem constructor must NOT create any hum entity")


# ── Charging ──────────────────────────────────────────────────────────────────

# AI-DEV: test_charge_adds_to_reserve was deleted. Integration
# test_contented_cat_near_hum_device_charges_hum (test_hum_tick.gd) and
# test_purr_near_hum_a_does_not_charge_hum_b (test_two_hums.gd) both assert
# that charge increases the reserve. Any mutation against the charge math
# cascaded into those.
func test_charge_clamps_at_capacity():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Overcharging a full HUM must NOT exceed capacity. This is the only
	# unit test targeting the mini() clamp — integrations exercise the
	# addition path but not the over-capacity branch.
	var hum_id: int = _make_hum()
	_hum.charge(hum_id, 5000)
	assert_eq(_hum.get_reserve(hum_id), HumSystem.DEFAULT_CAPACITY,
		"Overcharging should clamp at capacity (%d)" % HumSystem.DEFAULT_CAPACITY)


# ── Idle drain ────────────────────────────────────────────────────────────────

# AI-DEV: test_drain_idle_reduces_reserve was deleted. Integration
# test_discontented_cat_does_not_charge_hum + test_hum_reserve_stays_non_negative_over_time
# (test_hum_tick.gd) both assert idle drain happens; any mutation on the
# core drain formula cascaded into those.
func test_drain_idle_slows_at_low_reserve():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# The ratio-scaled drain formula is only tested here — integrations
	# assert drain happens, not that it scales down.
	var hum_id: int = _make_hum()
	var full_reserve: int = HumSystem.DEFAULT_CAPACITY
	_db.set_field(hum_id, &"hum", &"reserve", full_reserve)
	_hum.drain_idle(hum_id)
	var drain_at_full: int = full_reserve - _hum.get_reserve(hum_id)

	var quarter_reserve: int = HumSystem.DEFAULT_CAPACITY / 4
	_db.set_field(hum_id, &"hum", &"reserve", quarter_reserve)
	_hum.drain_idle(hum_id)
	var drain_at_quarter: int = quarter_reserve - _hum.get_reserve(hum_id)

	assert_lt(drain_at_quarter, drain_at_full,
		"Idle drain at 25%% reserve should be less than at 100%%")


func test_tick_idle_drain_iterates_all_hum_entities():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Verifies tick_idle_drain's fan-out — one mutation on the iteration
	# loop (e.g. `break` after first) fails only this test.
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
	# Asserts drain_action takes a constant amount regardless of reserve,
	# i.e. it is NOT ratio-scaled like drain_idle.
	var hum_id: int = _make_hum()
	_db.set_field(hum_id, &"hum", &"reserve", HumSystem.DEFAULT_CAPACITY)
	_hum.drain_action(hum_id, 50)
	var drain_from_full: int = HumSystem.DEFAULT_CAPACITY - _hum.get_reserve(hum_id)

	var ten_pct: int = HumSystem.DEFAULT_CAPACITY / 10
	_db.set_field(hum_id, &"hum", &"reserve", ten_pct)
	_hum.drain_action(hum_id, 50)
	var drain_from_low: int = ten_pct - _hum.get_reserve(hum_id)

	assert_eq(drain_from_full, 50, "Action drain should take exactly 50 from full")
	assert_eq(drain_from_low, 50, "Action drain should take exactly 50 from 10%%")


# AI-DEV: Merged the prior tests test_drain_action_can_reach_zero +
# test_reserve_never_goes_negative. Both exercise the same
# maxi(0, reserve - cost) floor — one branch, one mutation point.
func test_drain_action_floors_at_zero():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum()
	_db.set_field(hum_id, &"hum", &"reserve", 10)
	_hum.drain_action(hum_id, 100)
	assert_eq(_hum.get_reserve(hum_id), 0,
		"Draining 100 from reserve 10 should reach exactly 0 (floor, not negative)")


# ── Has reserve ───────────────────────────────────────────────────────────────

func test_has_reserve_for_action():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Boundary test for the >= comparator — exact-match passes, +1 fails.
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
	assert_eq(_hum.get_reserve_ratio(hum_id), 1000,
		"Full reserve should yield ratio 1000")

	_db.set_field(hum_id, &"hum", &"reserve", 0)
	assert_eq(_hum.get_reserve_ratio(hum_id), 0,
		"Empty reserve should yield ratio 0")

	_db.set_field(hum_id, &"hum", &"reserve", HumSystem.DEFAULT_CAPACITY / 2)
	assert_eq(_hum.get_reserve_ratio(hum_id), 500,
		"Half reserve should yield ratio 500")


# ── tick_charge ───────────────────────────────────────────────────────────────

# AI-DEV: The three per-condition tick_charge unit tests
# (near-receiver, out-of-range, zero-intensity) were deleted. All three
# behaviors are covered by tests/integration/test_two_hums.gd
# (test_purr_near_hum_a_does_not_charge_hum_b asserts range gating;
# test_nearest_receiver_tie_break_by_lower_id asserts positive charge)
# and test_hum_tick.gd's full-flow tests (zero-intensity implicit in
# discontented-cat coverage). The tick_charge loop itself is small and
# any mutation on the range check or the intensity guard failed both
# the unit and integration suites together.


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


# AI-DEV: Merges brownout entered + recovered into one test. The recovered
# path depends on having-entered-first, so a single mutation on the brownout
# branch failed both tests in tandem. One assertion sequence now captures
# the whole enter→recover cycle.
func test_brownout_entered_and_recovered_signals():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum()
	var entered: Array[int] = [0]
	var recovered: Array[int] = [0]
	_events.hum_brownout_entered.connect(func(_h_id: int) -> void: entered[0] += 1)
	_events.hum_brownout_recovered.connect(func(_h_id: int) -> void: recovered[0] += 1)

	# Enter: set just above 25% threshold, drain below it
	var capacity: int = _db.get_field(hum_id, &"hum", &"capacity")
	_db.set_field(hum_id, &"hum", &"reserve", capacity / 4 + 1)
	_hum.drain_action(hum_id, 10)
	assert_eq(entered[0], 1,
		"Should emit brownout_entered when crossing below 25%%")

	# Recover: charge back above threshold
	_hum.charge(hum_id, capacity / 4 + 100)
	assert_eq(recovered[0], 1,
		"Should emit brownout_recovered when crossing above 25%%")
