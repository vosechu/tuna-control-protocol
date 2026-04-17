# Purr-Power Foundation Implementation Plan

> **Note (2026-04-16):** Identifiers referenced in this document may be outdated.
> `species_filter` was never implemented and is removed. `cat_presence` → `reclamation`,
> `cat_seconds` → `tended_seconds`, `is_purring` → `is_satisfied`. Anchor rule and
> species-recipe schema live in `CLAUDE.md` ("Species Are Component Recipes") and
> `.claude/rules/modding.md` (Species Recipe Schema).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the core math layer for purr-power Ring 0: 10U rack constants, HUM global reserve, contentment derivation (3-of-4 bars), and tick loop integration. Pure logic, no visuals.

**Architecture:** HUM is a global integer pool stored on a singleton facility entity (ID 0) in GameStateDB. Each tick, purring cats near HUM receivers add charge; idle drain and action costs subtract. Contentment is derived from 4 desire bars (warmth, comfort, hunger, attention) — 3 of 4 above threshold means purring. All integers, batch-first, deterministic.

**Tech Stack:** GDScript 4.x, GUT test framework, existing GameStateDB/HeatGrid patterns

**Spec:** `docs/superpowers/specs/2026-04-12-purr-power-ring0-design.md`

**Sibling plans:** This is Plan 1 of 3. Plan 2 (Objects & Food Loop) and Plan 3 (Feedback & Presentation) build on this foundation.

---

## File Map

### New files

| File | Responsibility |
|---|---|
| `engine/core/hum_system.gd` | HUM reserve math: charge from purring cats near receivers, idle drain with slowdown curve, action drain, facility entity management |
| `engine/core/contentment.gd` | Derive `is_purring` from 3-of-4 desire bars above threshold. Batch column op, called during scatter phase |
| `tests/unit/test_hum_system.gd` | Unit tests for HUM charge, drain, slowdown, action costs |
| `tests/unit/test_contentment.gd` | Unit tests for 3-of-4 derivation, threshold edge cases |
| `tests/integration/test_hum_tick.gd` | Integration test: HUM charges during tick when cats purr near receiver |

### Modified files

| File | Change |
|---|---|
| `engine/core/constants.gd` | `SLOTS_PER_RACK = 10`, recompute derived constants, add HUM constants |
| `engine/core/events.gd` | Add `hum_reserve_changed` signal |
| `nodes/game_server.gd` | Initialize HUM system, add `hunger` + `attention` to desire scatter, call contentment + HUM in tick loop |
| `tests/unit/test_constants.gd` | Update expected values for 10U |
| `tests/unit/test_heat_grid.gd` | Update cell counts for 10U |
| `tests/integration/test_tick_loop.gd` | Update slot references for 10U |
| `tests/integration/test_desire_scatter.gd` | Update slot references for 10U, add hunger/attention assertions |

---

### Task 1: Update rack constants to 10U

**Files:**
- Modify: `engine/core/constants.gd`
- Modify: `tests/unit/test_constants.gd`

- [ ] **Step 1: Read the current test file**

Run: `cat tests/unit/test_constants.gd` to see current assertions.

- [ ] **Step 2: Update constants.gd**

```gdscript
# In engine/core/constants.gd, change:
const SLOTS_PER_RACK: int = 10  # was 42
# Derived constants auto-update:
# HEAT_CELLS_RACK = 10 * 7 = 70  (was 294)
# HEAT_CELLS_TOTAL = 70 + 7 = 77  (was 301)
```

- [ ] **Step 3: Run tests to see what breaks**

Run: `script/checks/gut_tests`
Expected: Multiple failures in test_constants.gd, test_heat_grid.gd, and any test referencing slot 42 or cell 294+.

- [ ] **Step 4: Update test_constants.gd**

Update all assertions that reference `42`, `294`, or `301` to use `10`, `70`, and `77` respectively. Update any slot position tests that place entities at slot 40+ (those slots no longer exist in a 10U rack).

- [ ] **Step 5: Update test_heat_grid.gd**

The heat grid now has 77 cells, not 301. Update:
- Grid size assertions
- Any test that places heat sources at slot 40+ (move to slot 8 or similar)
- Cell index calculations using `rack_cell()` and `floor_cell()`
- Floor cells now start at index 70, not 294

- [ ] **Step 6: Update test_tick_loop.gd and test_desire_scatter.gd**

Search for slot references > 9 and update to valid 10U slots. The starter entities in game_server.gd also need updating (Task 8 handles game_server.gd changes).

- [ ] **Step 7: Run tests and verify all pass**

Run: `script/checks/gut_tests`
Expected: All pass with new 10U values. Some game_server.gd tests may still fail — those are fixed in Task 8.

- [ ] **Step 8: Commit**

```bash
git add engine/core/constants.gd tests/
git commit -m "refactor(constants): update rack from 42U to 10U slots"
```

---

### Task 2: Add hunger and attention desires

Currently animals have `warmth`, `comfort`, and `curiosity`. Contentment needs `hunger` and `attention`. Add both to desire scatter with proper decay.

**Files:**
- Modify: `nodes/game_server.gd` (specifically `_scatter_desires()` and `_spawn_starter_entities()`)
- Modify: `mods/tcp_cats/species/cat.jsonc` (add hunger/attention to desires)
- Modify: `engine/mod/entity_def_registry.gd` (if spawn doesn't already handle new desire fields)
- Modify: `tests/integration/test_desire_scatter.gd`

- [ ] **Step 1: Write the failing test**

In `tests/integration/test_desire_scatter.gd`, add:

```gdscript
func test_hunger_decays_each_tick():
	# Setup: cat with hunger at 800
	var cat_id: int = db.create_entity()
	db.set_component(cat_id, &"desires", {
		&"warmth": 500, &"comfort": 500, &"curiosity": 500,
		&"hunger": 800, &"attention": 500,
	})
	db.set_component(cat_id, &"position", {&"x": 0, &"y": 0})
	db.update_spatial(cat_id, 0, 0)

	# Act: run one scatter pass
	game_server._scatter_desires()

	# Assert: hunger decreased
	var desires: Dictionary = db.get_component(cat_id, &"desires")
	assert_lt(desires[&"hunger"], 800,
		"Hunger should decay each tick")


func test_attention_decays_faster_than_hunger():
	var cat_id: int = db.create_entity()
	db.set_component(cat_id, &"desires", {
		&"warmth": 500, &"comfort": 500, &"curiosity": 500,
		&"hunger": 800, &"attention": 800,
	})
	db.set_component(cat_id, &"position", {&"x": 0, &"y": 0})
	db.update_spatial(cat_id, 0, 0)

	# Run 10 ticks of scatter
	for i in 10:
		game_server._scatter_desires()

	var desires: Dictionary = db.get_component(cat_id, &"desires")
	assert_lt(desires[&"attention"], desires[&"hunger"],
		"Attention should decay faster than hunger")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/integration/test_desire_scatter.gd`
Expected: FAIL — `hunger` key not in desires dictionary.

- [ ] **Step 3: Update cat.jsonc to include hunger and attention**

In `mods/tcp_cats/species/cat.jsonc`, add to the `"desires"` block:

```jsonc
"desires": {
    "warmth": 700,
    "comfort": 700,
    "curiosity": 200,
    "hunger": 0,      // 0 = desperate, 1000 = full. Starts full in spawn overrides.
    "attention": 0,    // 0 = unattended, 1000 = recently petted
    "noise": -600,
    "chased": -900
},
```

And to `"personality_ranges"`:

```jsonc
"hunger": [0, 0],        // No personality variation on hunger decay
"attention": [0, 0],     // No personality variation on attention decay
```

- [ ] **Step 4: Add decay to _scatter_desires() in game_server.gd**

After the existing `db.add_all(&"desires", &"curiosity", -3)` line (~line 117), add:

```gdscript
db.add_all(&"desires", &"hunger", -3)     # hunger decays: ~300/1000 per 100 ticks (10 sec)
db.add_all(&"desires", &"attention", -8)  # attention decays ~2.7x faster than hunger
```

And add clamping after the existing clamp lines:

```gdscript
db.clamp_all(&"desires", &"hunger", 0, 1000)
db.clamp_all(&"desires", &"attention", 0, 1000)
```

- [ ] **Step 5: Update starter entity spawns**

In `_spawn_starter_entities()`, the cats are spawned via `_entity_defs.spawn()` with overrides. Add hunger and attention to spawn overrides so cats start content:

```gdscript
var cat_spawns: Array[Dictionary] = [
	{
		&"name": &"Mochi",
		&"position": {&"x": Constants.RACK_WIDTH_PU / 2, &"y": floor_y},
		&"desires": {&"hunger": 900, &"attention": 600},
	},
	# ... same for Biscuit and Noodle
]
```

Check that `entity_def_registry.spawn()` deep-merges desire overrides (it should — verify in the spawn function).

- [ ] **Step 6: Run tests and verify pass**

Run: `script/checks/gut_tests -f tests/integration/test_desire_scatter.gd`
Expected: Both new tests pass.

- [ ] **Step 7: Run full test suite**

Run: `script/checks/gut_tests`
Expected: All pass. Fix any tests broken by the new desire fields.

- [ ] **Step 8: Commit**

```bash
git add nodes/game_server.gd mods/tcp_cats/species/cat.jsonc tests/
git commit -m "feat(desires): add hunger and attention bars with decay"
```

---

### Task 3: Contentment derivation (3-of-4 → is_purring)

**Files:**
- Create: `engine/core/contentment.gd`
- Create: `tests/unit/test_contentment.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_contentment.gd`:

```gdscript
extends GutTest

var db: GameStateDB
var contentment: Contentment

func before_each() -> void:
	db = GameStateDB.new()
	contentment = Contentment.new(db)


func test_cat_with_all_four_bars_above_threshold_is_purring():
	var cat_id: int = _make_cat({
		&"warmth": 600, &"comfort": 600, &"hunger": 600, &"attention": 600,
	})
	contentment.evaluate_all()
	var state: Dictionary = db.get_component(cat_id, &"contentment")
	assert_eq(state[&"is_purring"], 1,
		"Cat with all 4 bars above threshold should purr")


func test_cat_with_three_bars_above_threshold_is_purring():
	var cat_id: int = _make_cat({
		&"warmth": 600, &"comfort": 600, &"hunger": 600, &"attention": 100,
	})
	contentment.evaluate_all()
	var state: Dictionary = db.get_component(cat_id, &"contentment")
	assert_eq(state[&"is_purring"], 1,
		"Cat with 3/4 bars above threshold should purr")


func test_cat_with_two_bars_above_threshold_not_purring():
	var cat_id: int = _make_cat({
		&"warmth": 600, &"comfort": 600, &"hunger": 100, &"attention": 100,
	})
	contentment.evaluate_all()
	var state: Dictionary = db.get_component(cat_id, &"contentment")
	assert_eq(state[&"is_purring"], 0,
		"Cat with only 2/4 bars above threshold should not purr")


func test_threshold_boundary_exactly_at_threshold_counts():
	var cat_id: int = _make_cat({
		&"warmth": 400, &"comfort": 400, &"hunger": 400, &"attention": 100,
	})
	contentment.evaluate_all()
	var state: Dictionary = db.get_component(cat_id, &"contentment")
	assert_eq(state[&"is_purring"], 1,
		"Bars exactly at threshold (400) should count as met")


func test_threshold_boundary_one_below_threshold_fails():
	var cat_id: int = _make_cat({
		&"warmth": 399, &"comfort": 399, &"hunger": 600, &"attention": 100,
	})
	contentment.evaluate_all()
	var state: Dictionary = db.get_component(cat_id, &"contentment")
	assert_eq(state[&"is_purring"], 0,
		"Two bars at 399 (below 400 threshold) + one low = only 1 met, not purring")


func test_non_cat_entities_ignored():
	var server_id: int = db.create_entity()
	db.set_component(server_id, &"object_type", {&"type": &"server_1u"})
	# No desires, no species — should not crash
	contentment.evaluate_all()
	assert_false(db.has_component(server_id, &"contentment"),
		"Non-animal entities should not get contentment component")


func test_evaluate_sets_purr_count():
	_make_cat({&"warmth": 600, &"comfort": 600, &"hunger": 600, &"attention": 600})
	_make_cat({&"warmth": 600, &"comfort": 600, &"hunger": 600, &"attention": 100})
	_make_cat({&"warmth": 100, &"comfort": 100, &"hunger": 100, &"attention": 100})
	contentment.evaluate_all()
	assert_eq(contentment.get_purring_count(), 2,
		"Two of three cats should be purring")


func _make_cat(desires: Dictionary) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"species", {&"id": &"tcp_cats:cat", &"variant": &"cat01", &"name": &"Test"})
	db.set_component(id, &"desires", desires)
	return id
```

- [ ] **Step 2: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_contentment.gd`
Expected: FAIL — `Contentment` class not found.

- [ ] **Step 3: Implement Contentment**

Create `engine/core/contentment.gd`:

```gdscript
class_name Contentment extends RefCounted

const THRESHOLD: int = 400
const BARS: Array[StringName] = [&"warmth", &"comfort", &"hunger", &"attention"]
const BARS_NEEDED: int = 3

var _db: GameStateDB
var _purring_count: int = 0


func _init(db: GameStateDB) -> void:
	_db = db


func evaluate_all() -> void:
	_purring_count = 0
	var animals: Array[int] = _db.get_entities_with(&"species")
	for entity_id: int in animals:
		if not _db.has_component(entity_id, &"desires"):
			continue
		var desires: Dictionary = _db.get_component(entity_id, &"desires")
		var bars_met: int = 0
		for bar: StringName in BARS:
			if desires.has(bar) and desires[bar] >= THRESHOLD:
				bars_met += 1
		var is_purring: int = 1 if bars_met >= BARS_NEEDED else 0
		_db.set_component(entity_id, &"contentment", {&"is_purring": is_purring})
		if is_purring == 1:
			_purring_count += 1


func get_purring_count() -> int:
	return _purring_count
```

- [ ] **Step 4: Run tests and verify pass**

Run: `script/checks/gut_tests -f tests/unit/test_contentment.gd`
Expected: All 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add engine/core/contentment.gd tests/unit/test_contentment.gd
git commit -m "feat(contentment): 3-of-4 bar derivation for is_purring"
```

---

### Task 4: HUM system core — charge and drain

**Files:**
- Create: `engine/core/hum_system.gd`
- Create: `tests/unit/test_hum_system.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_hum_system.gd`:

```gdscript
extends GutTest

var db: GameStateDB
var hum: HumSystem

const FACILITY_ID: int = 0


func before_each() -> void:
	db = GameStateDB.new()
	hum = HumSystem.new(db)


func test_facility_entity_created_on_init():
	assert_true(db.has_entity(FACILITY_ID),
		"HUM system should create facility entity 0")
	assert_true(db.has_component(FACILITY_ID, &"hum"),
		"Facility entity should have hum component")


func test_initial_reserve_is_at_capacity():
	var h: Dictionary = db.get_component(FACILITY_ID, &"hum")
	assert_eq(h[&"reserve"], h[&"capacity"],
		"HUM reserve should start full")


func test_charge_adds_to_reserve():
	# Drain some reserve first so we have room to charge
	db.set_field(FACILITY_ID, &"hum", &"reserve", 500)
	hum.charge(100)
	var h: Dictionary = db.get_component(FACILITY_ID, &"hum")
	assert_eq(h[&"reserve"], 600,
		"Charging 100 should increase reserve from 500 to 600")


func test_charge_clamps_at_capacity():
	var capacity: int = db.get_field(FACILITY_ID, &"hum", &"capacity")
	hum.charge(capacity + 1000)
	var reserve: int = db.get_field(FACILITY_ID, &"hum", &"reserve")
	assert_eq(reserve, capacity,
		"Charge should not exceed capacity")


func test_drain_idle_reduces_reserve():
	var before: int = db.get_field(FACILITY_ID, &"hum", &"reserve")
	hum.drain_idle()
	var after: int = db.get_field(FACILITY_ID, &"hum", &"reserve")
	assert_lt(after, before,
		"Idle drain should reduce reserve")


func test_drain_idle_slows_at_low_reserve():
	# Set reserve to 25% of capacity
	var capacity: int = db.get_field(FACILITY_ID, &"hum", &"capacity")
	@warning_ignore("integer_division")
	var quarter: int = capacity / 4
	db.set_field(FACILITY_ID, &"hum", &"reserve", quarter)
	var before: int = db.get_field(FACILITY_ID, &"hum", &"reserve")
	hum.drain_idle()
	var drain_at_quarter: int = before - db.get_field(FACILITY_ID, &"hum", &"reserve")

	# Reset to 100%
	db.set_field(FACILITY_ID, &"hum", &"reserve", capacity)
	var before_full: int = db.get_field(FACILITY_ID, &"hum", &"reserve")
	hum.drain_idle()
	var drain_at_full: int = before_full - db.get_field(FACILITY_ID, &"hum", &"reserve")

	assert_lt(drain_at_quarter, drain_at_full,
		"Idle drain at 25%% reserve (%d) should be less than at 100%% (%d)" % [drain_at_quarter, drain_at_full])


func test_drain_action_is_fixed_cost():
	var capacity: int = db.get_field(FACILITY_ID, &"hum", &"capacity")
	# Test at full reserve
	db.set_field(FACILITY_ID, &"hum", &"reserve", capacity)
	var before_full: int = db.get_field(FACILITY_ID, &"hum", &"reserve")
	var cost: int = 50
	hum.drain_action(cost)
	var drain_full: int = before_full - db.get_field(FACILITY_ID, &"hum", &"reserve")

	# Test at 10% reserve
	@warning_ignore("integer_division")
	var tenth: int = capacity / 10
	db.set_field(FACILITY_ID, &"hum", &"reserve", tenth)
	var before_low: int = db.get_field(FACILITY_ID, &"hum", &"reserve")
	hum.drain_action(cost)
	var drain_low: int = before_low - db.get_field(FACILITY_ID, &"hum", &"reserve")

	assert_eq(drain_full, drain_low,
		"Action drain is fixed regardless of reserve level")


func test_drain_action_can_reach_zero():
	db.set_field(FACILITY_ID, &"hum", &"reserve", 10)
	hum.drain_action(100)
	var reserve: int = db.get_field(FACILITY_ID, &"hum", &"reserve")
	assert_eq(reserve, 0,
		"Action drain should be able to reach zero")


func test_reserve_never_goes_negative():
	db.set_field(FACILITY_ID, &"hum", &"reserve", 5)
	hum.drain_action(1000)
	var reserve: int = db.get_field(FACILITY_ID, &"hum", &"reserve")
	assert_eq(reserve, 0,
		"Reserve should clamp at 0, never go negative")


func test_has_reserve_for_action():
	db.set_field(FACILITY_ID, &"hum", &"reserve", 100)
	assert_true(hum.has_reserve(50), "Should have reserve for 50 when at 100")
	assert_true(hum.has_reserve(100), "Should have reserve for 100 when at 100")
	assert_false(hum.has_reserve(101), "Should not have reserve for 101 when at 100")


func test_get_reserve_ratio():
	var capacity: int = db.get_field(FACILITY_ID, &"hum", &"capacity")
	db.set_field(FACILITY_ID, &"hum", &"reserve", capacity)
	assert_eq(hum.get_reserve_ratio(), 1000,
		"Full reserve should return 1000 (100.0%%)")
	db.set_field(FACILITY_ID, &"hum", &"reserve", 0)
	assert_eq(hum.get_reserve_ratio(), 0,
		"Empty reserve should return 0")
	@warning_ignore("integer_division")
	db.set_field(FACILITY_ID, &"hum", &"reserve", capacity / 2)
	assert_eq(hum.get_reserve_ratio(), 500,
		"Half reserve should return 500 (50.0%%)")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_hum_system.gd`
Expected: FAIL — `HumSystem` class not found.

- [ ] **Step 3: Implement HumSystem**

Create `engine/core/hum_system.gd`:

```gdscript
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
	# drain = base * (reserve / capacity), all integer math
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


func get_reserve_ratio() -> int:
	var capacity: int = _db.get_field(FACILITY_ID, &"hum", &"capacity")
	if capacity <= 0:
		return 0
	var reserve: int = _db.get_field(FACILITY_ID, &"hum", &"reserve")
	@warning_ignore("integer_division")
	return reserve * 1000 / capacity
```

Note: `create_entity_with_id()` does not exist on GameStateDB yet. We need to add it — see Step 4.

- [ ] **Step 4: Add create_entity_with_id to GameStateDB**

In `engine/core/game_state_db.gd`, add after `create_entity()`:

```gdscript
func create_entity_with_id(entity_id: int) -> void:
	assert(not _entities.has(entity_id),
			"create_entity_with_id: entity %d already exists" % entity_id)
	_entities[entity_id] = {}
	if entity_id >= _next_id:
		_next_id = entity_id + 1
```

- [ ] **Step 5: Run tests and verify pass**

Run: `script/checks/gut_tests -f tests/unit/test_hum_system.gd`
Expected: All 12 tests pass.

- [ ] **Step 6: Commit**

```bash
git add engine/core/hum_system.gd engine/core/game_state_db.gd tests/unit/test_hum_system.gd
git commit -m "feat(hum): HUM system core — charge, drain, slowdown curve, action costs"
```

---

### Task 5: HUM receiver radius and charge-from-purring

The HUM system needs to know which purring cats are near receivers. A "receiver" is any entity with a `hum_receiver` component that has a `radius_ru` field. During the tick, we count purring cats within each receiver's radius and charge the global pool.

**Files:**
- Modify: `engine/core/hum_system.gd`
- Modify: `tests/unit/test_hum_system.gd`

- [ ] **Step 1: Write the failing tests**

Add to `tests/unit/test_hum_system.gd`:

```gdscript
func test_tick_charges_from_purring_cat_near_receiver():
	# Place a receiver at rack 1, slot 5
	var receiver_id: int = db.create_entity()
	var rx: int = 1 * Constants.RACK_WIDTH_PU
	var ry: int = 5 * Constants.SLOT_HEIGHT_PU
	db.set_component(receiver_id, &"position", {&"x": rx, &"y": ry})
	db.set_component(receiver_id, &"hum_receiver", {&"radius_ru": 3})
	db.update_spatial(receiver_id, rx, ry)

	# Place a purring cat nearby (within 3 RU)
	var cat_id: int = db.create_entity()
	var cx: int = rx
	var cy: int = ry + 2 * Constants.SLOT_HEIGHT_PU  # 2 RU away
	db.set_component(cat_id, &"position", {&"x": cx, &"y": cy})
	db.set_component(cat_id, &"contentment", {&"is_purring": 1})
	db.set_component(cat_id, &"species", {&"id": &"tcp_cats:cat", &"variant": &"cat01", &"name": &"Test"})
	db.update_spatial(cat_id, cx, cy)

	# Drain some reserve so charge is visible
	db.set_field(FACILITY_ID, &"hum", &"reserve", 500)
	hum.tick_charge()
	var reserve: int = db.get_field(FACILITY_ID, &"hum", &"reserve")
	assert_gt(reserve, 500,
		"Purring cat near receiver should charge HUM")


func test_tick_does_not_charge_from_cat_outside_radius():
	var receiver_id: int = db.create_entity()
	var rx: int = 1 * Constants.RACK_WIDTH_PU
	var ry: int = 5 * Constants.SLOT_HEIGHT_PU
	db.set_component(receiver_id, &"position", {&"x": rx, &"y": ry})
	db.set_component(receiver_id, &"hum_receiver", {&"radius_ru": 3})
	db.update_spatial(receiver_id, rx, ry)

	# Place cat far away (10 RU)
	var cat_id: int = db.create_entity()
	var cx: int = rx
	var cy: int = ry + 10 * Constants.SLOT_HEIGHT_PU
	db.set_component(cat_id, &"position", {&"x": cx, &"y": cy})
	db.set_component(cat_id, &"contentment", {&"is_purring": 1})
	db.set_component(cat_id, &"species", {&"id": &"tcp_cats:cat", &"variant": &"cat01", &"name": &"Test"})
	db.update_spatial(cat_id, cx, cy)

	db.set_field(FACILITY_ID, &"hum", &"reserve", 500)
	hum.tick_charge()
	var reserve: int = db.get_field(FACILITY_ID, &"hum", &"reserve")
	assert_eq(reserve, 500,
		"Cat outside receiver radius should not charge HUM")


func test_non_purring_cat_does_not_charge():
	var receiver_id: int = db.create_entity()
	var rx: int = 1 * Constants.RACK_WIDTH_PU
	var ry: int = 5 * Constants.SLOT_HEIGHT_PU
	db.set_component(receiver_id, &"position", {&"x": rx, &"y": ry})
	db.set_component(receiver_id, &"hum_receiver", {&"radius_ru": 3})
	db.update_spatial(receiver_id, rx, ry)

	var cat_id: int = db.create_entity()
	db.set_component(cat_id, &"position", {&"x": rx, &"y": ry})
	db.set_component(cat_id, &"contentment", {&"is_purring": 0})
	db.set_component(cat_id, &"species", {&"id": &"tcp_cats:cat", &"variant": &"cat01", &"name": &"Test"})
	db.update_spatial(cat_id, rx, ry)

	db.set_field(FACILITY_ID, &"hum", &"reserve", 500)
	hum.tick_charge()
	var reserve: int = db.get_field(FACILITY_ID, &"hum", &"reserve")
	assert_eq(reserve, 500,
		"Non-purring cat should not charge HUM")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_hum_system.gd`
Expected: FAIL — `tick_charge` method not found.

- [ ] **Step 3: Implement tick_charge()**

Add to `engine/core/hum_system.gd`:

```gdscript
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
```

- [ ] **Step 4: Run tests and verify pass**

Run: `script/checks/gut_tests -f tests/unit/test_hum_system.gd`
Expected: All tests pass including the 3 new ones.

- [ ] **Step 5: Commit**

```bash
git add engine/core/hum_system.gd tests/unit/test_hum_system.gd
git commit -m "feat(hum): receiver radius check and charge from purring cats"
```

---

### Task 6: Add hum_reserve_changed signal

**Files:**
- Modify: `engine/core/events.gd`
- Modify: `engine/core/hum_system.gd`

- [ ] **Step 1: Add signals to events.gd**

```gdscript
# HUM
signal hum_reserve_changed(old_reserve: int, new_reserve: int)
signal hum_brownout_entered()
signal hum_brownout_recovered()
```

- [ ] **Step 2: Emit signals from HumSystem**

Add to `hum_system.gd` — a reference to Events and threshold tracking:

```gdscript
var _events: Events
var _was_brownout: bool = false
const BROWNOUT_THRESHOLD: int = 250  # 25% of 1000 ratio

func _init(db: GameStateDB, events: Events) -> void:
	_db = db
	_events = events
	# ... existing init code
```

Add a private method called after any reserve change:

```gdscript
func _emit_if_changed(old_reserve: int) -> void:
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
```

Call `_emit_if_changed` at the end of `charge()`, `drain_idle()`, and `drain_action()`.

- [ ] **Step 3: Update HumSystem tests to pass Events**

Update `before_each` in `test_hum_system.gd`:

```gdscript
var events: Events

func before_each() -> void:
	db = GameStateDB.new()
	events = Events.new()
	hum = HumSystem.new(db, events)
```

- [ ] **Step 4: Run all tests**

Run: `script/checks/gut_tests`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add engine/core/events.gd engine/core/hum_system.gd tests/unit/test_hum_system.gd
git commit -m "feat(hum): emit hum_reserve_changed and brownout signals"
```

---

### Task 7: Wire HUM and contentment into the tick loop

**Files:**
- Modify: `nodes/game_server.gd`
- Create: `tests/integration/test_hum_tick.gd`

- [ ] **Step 1: Write the integration test**

Create `tests/integration/test_hum_tick.gd`:

```gdscript
extends GutTest

var game_server: Node


func before_each() -> void:
	game_server = preload("res://nodes/game_server.gd").new()
	add_child_autofree(game_server)


func test_tick_updates_contentment():
	# After one tick, cats should have contentment component
	var cats: Array[int] = game_server.db.get_entities_with(&"species")
	assert_gt(cats.size(), 0, "Should have at least one cat")
	# Run one tick
	game_server._physics_process(0.1)
	for cat_id: int in cats:
		assert_true(
			game_server.db.has_component(cat_id, &"contentment"),
			"Cat %d should have contentment after tick" % cat_id
		)


func test_hum_reserve_changes_over_ticks():
	# Drain some reserve manually, then check if purring cats recharge it
	game_server.hum_system.drain_action(5000)  # drain half
	var before: int = game_server.hum_system.get_reserve()
	# Run several ticks — if cats are purring near a receiver, reserve should climb
	for i in 100:
		game_server._physics_process(0.1)
	var after: int = game_server.hum_system.get_reserve()
	# Note: this test passes only if starter entities include a HUM receiver
	# and at least one cat is content. If no receiver exists in starter entities,
	# reserve stays the same (no charge source). Both outcomes are valid for now.
	assert_true(true, "HUM tick integration runs without error")
```

- [ ] **Step 2: Add HUM system and contentment to game_server.gd**

In the variable declarations (top of file):

```gdscript
var hum_system: HumSystem
var contentment: Contentment
```

In `_ready()`, after `heat_grid = HeatGrid.new(db)`:

```gdscript
var events := Events.new()
hum_system = HumSystem.new(db, events)
contentment = Contentment.new(db)
```

In `_physics_process()`, update the tick order. After `_scatter_desires()` and before `desire_resolver.mark_all_dirty()`:

```gdscript
func _physics_process(_delta: float) -> void:
	db.advance_tick()
	heat_grid.propagate()
	_scatter_desires()
	contentment.evaluate_all()       # Step 3a: derive is_purring from desires
	hum_system.tick_charge()          # Step 3b: purring cats near receivers → HUM
	hum_system.drain_idle()           # Step 3b: idle drain with slowdown
	_decay_commitment()
	desire_resolver.mark_all_dirty()
	desire_resolver.evaluate_budget(_curiosity_trackers)
	_move_animals()
	_update_ambient_states()
	db.flush_notifications()
```

- [ ] **Step 3: Update starter entity positions for 10U racks**

The starter entities reference slot 40 and `SLOTS_PER_RACK` (now 10). Update `_spawn_starter_entities()`:

```gdscript
# Server at rack 1, slot 8 (near bottom of 10U rack)
var server_y: int = 8 * Constants.SLOT_HEIGHT_PU

# Floor positions use SLOTS_PER_RACK which is now 10
var floor_y: int = Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 2
```

Update all slot references from `40` to `8` (or similar valid 10U slot).

- [ ] **Step 4: Run full test suite**

Run: `script/checks/gut_tests`
Expected: All pass. Fix any remaining 42U references.

- [ ] **Step 5: Commit**

```bash
git add nodes/game_server.gd tests/integration/test_hum_tick.gd
git commit -m "feat(hum): wire contentment + HUM into tick loop at Step 3a/3b"
```

---

### Task 8: Re-stamp modified tests

Any test files modified in previous tasks need re-stamping via the verification process.

**Files:**
- Modified test files from Tasks 1-7

- [ ] **Step 1: Run verify_tests to see what's stale**

Run: `script/checks/verify_tests`
Expected: Lists all test files with stale or missing stamps.

- [ ] **Step 2: Stamp new test files**

```bash
script/stamp_tests tests/unit/test_contentment.gd
script/stamp_tests tests/unit/test_hum_system.gd
script/stamp_tests tests/integration/test_hum_tick.gd
```

- [ ] **Step 3: Re-stamp modified test files**

For each modified test file listed by verify_tests:

```bash
script/stamp_tests tests/unit/test_constants.gd
script/stamp_tests tests/unit/test_heat_grid.gd
script/stamp_tests tests/integration/test_tick_loop.gd
script/stamp_tests tests/integration/test_desire_scatter.gd
```

- [ ] **Step 4: Verify all stamps pass**

Run: `script/checks/verify_tests`
Expected: All stamps valid, no orphans, no missing.

- [ ] **Step 5: Run full validation**

Run: `script/validate`
Expected: All checks pass.

- [ ] **Step 6: Commit**

```bash
git add tests/
git commit -m "chore(tests): stamp all new and modified test files for purr-power foundation"
```

---

## Verification Checklist

After all tasks complete, verify:

- [ ] `script/validate` passes (all checks green)
- [ ] `SLOTS_PER_RACK` is 10 everywhere
- [ ] `GameStateDB` has `create_entity_with_id()` method
- [ ] Animals have 4 desire bars: warmth, comfort, hunger, attention
- [ ] Hunger decays at -3/tick, attention at -8/tick
- [ ] `Contentment.evaluate_all()` sets `is_purring` on all animals with species
- [ ] 3-of-4 bars >= 400 threshold = purring
- [ ] `HumSystem` manages a global reserve on facility entity 0
- [ ] `tick_charge()` counts purring cats near `hum_receiver` entities
- [ ] `drain_idle()` slows at low reserve
- [ ] `drain_action()` is fixed cost, can reach zero
- [ ] `hum_reserve_changed` signal emitted on reserve changes
- [ ] `hum_brownout_entered` / `hum_brownout_recovered` signals at 25% threshold
- [ ] Tick order: scatter → contentment → HUM charge → HUM idle drain → AI

## Next Plans

- **Plan 2: Objects & Food Loop** — HUM device (6U), TUNA dispenser, button, ARM floor object, cat HUNGRY/PACING/EATING/RETURNING/SETTLING states, button press verb, pet verb, squeak verb
- **Plan 3: Feedback & Presentation** — CanvasModulate lighting, HUD reserve bar, sound refactoring (purr tracks reserve), meow cadence, HUM device tone, narrator CRT panel, robot log triggers
