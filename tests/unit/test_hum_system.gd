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


func _make_hum_device(rack: int, slot: int, radius_slots: int) -> int:
	# Entity with hum + hum_receiver + position, used by tick_charge tests.
	var id: int = _db.create_entity()
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var x: int = slot_rect.position.x + slot_rect.size.x / 2
	var y: int = slot_rect.position.y + slot_rect.size.y / 2
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"hum", {
		&"reserve": HumSystem.DEFAULT_CAPACITY,
		&"capacity": HumSystem.DEFAULT_CAPACITY,
	})
	_db.set_component(id, &"hum_receiver", {
		&"radius_px": radius_slots * Constants.SLOT_HEIGHT_PX,
	})
	_db.update_spatial(id, x, y)
	return id


func _make_purring_entity(rack: int, slot: int, intensity: int) -> int:
	var id: int = _db.create_entity()
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var x: int = slot_rect.position.x + slot_rect.size.x / 2
	var y: int = slot_rect.position.y + slot_rect.size.y / 2
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"purr", {&"intensity": intensity})
	_db.update_spatial(id, x, y)
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

# AI-DEV: Three tick_charge unit tests cover the near-receiver charge,
# the out-of-radius gate, and the zero-intensity short-circuit. Integration
# coverage (test_two_hums.gd, test_hum_tick.gd) exercises the same
# production paths, but cross-suite cascades are acceptable under
# script/tdd_verify — the constraint is one failing test per mutation
# within the unit suite, not across the whole test tree.


func test_tick_charges_from_purring_emitter_near_receiver():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Unit-level purr→charge proof. Surgical within-suite mutation: skip the
	# `charge(hum_id, per_hum_charge[hum_id])` call at the tail of tick_charge
	# so nothing charges. Other hum_system unit tests either call charge()
	# directly (emit test) or don't use tick_charge — they stay green.
	var hum_id: int = _make_hum_device(0, 5, 3)
	_db.set_field(hum_id, &"hum", &"reserve", 500)
	_make_purring_entity(0, 4, 10)
	_hum.tick_charge()
	assert_gt(_hum.get_reserve(hum_id), 500,
		"Purring emitter within receiver radius should charge the HUM reserve")


func test_tick_does_not_charge_from_emitter_outside_radius():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Radius gate unit proof. Surgical within-suite mutation: delete the
	# `if dist_sq > radius_px * radius_px: continue` guard. Positive test still
	# charges (inside radius either way), zero-intensity test short-circuits
	# earlier on intensity check.
	var hum_id: int = _make_hum_device(0, 0, 3)
	_db.set_field(hum_id, &"hum", &"reserve", 500)
	_make_purring_entity(2, 0, 10)  # rack 2, far outside 24px radius
	_hum.tick_charge()
	assert_eq(_hum.get_reserve(hum_id), 500,
		"Purring emitter outside receiver radius should not charge the HUM")


func test_zero_intensity_emitter_does_not_charge():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Intensity short-circuit unit proof. Surgical within-suite mutation:
	# replace `if intensity <= 0: continue` with `if intensity < 0: continue`
	# AND add `if intensity == 0: intensity = 1` so a zero-intensity emitter
	# now charges 1. Positive and outside-radius tests use intensity=10 and
	# are unaffected.
	var hum_id: int = _make_hum_device(0, 5, 3)
	_db.set_field(hum_id, &"hum", &"reserve", 500)
	_make_purring_entity(0, 4, 0)  # intensity=0
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
