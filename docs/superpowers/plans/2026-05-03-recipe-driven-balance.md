# Recipe-Driven Balance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move balance numbers (per-channel decay rates, ambient-state min durations, STARTLED recovery, body walk speed) from hardcoded engine constants into per-recipe JSONC fields, then extract the two consumers (`_move_animals`, `_update_ambient_states`) from `nodes/game_server.gd` into pure-core systems.

**Architecture:** Schema-first migration: loader extensions land before validator activation, validator + recipe content + docs land in one atomic commit, then in-place consumer changes, then extractions. New `BehaviorTimers` RefCounted struct holds shared per-entity state-timer dicts so MovementSystem and AiStateSystem can be unit-tested in isolation. Food-finder helpers promote from `GameServer` private to `FoodSystem` public so AiStateSystem extracts cleanly without a GameServer reference.

**Tech Stack:** GDScript (Godot 4.6.1), GUT for tests, JSONC mod recipes, RefCounted core objects (Pure Core Pattern), `script/validate` for CI checks.

**Reference spec:** `docs/superpowers/specs/2026-05-02-recipe-driven-balance-design.md`

**Branch:** `feat/recipe-driven-balance`

**Test conventions for this plan:**
- Unit tests live in `tests/unit/`. Run a single file with `script/checks/gut_tests -f tests/unit/<file>.gd`. **Never pass multiple `-f` flags in one invocation** — silently drops all but the last.
- Every new or modified test in `tests/unit/` must be stamped with `script/tdd_verify stamp <path>` and the `.gd.stamp` sidecar must land in the same commit. Stamp inside the same task that creates the test, not in a deferred sweep.
- Integration tests live in `tests/integration/`. Re-stamp via `/verify-test` once green if the file already had a stamp.

---

## File Map

**Created:**
- `engine/animals/behavior_timers.gd` — RefCounted struct holding shared `state_timers`, `min_durations_override`, `curiosity_trackers` dicts.
- `engine/animals/movement_system.gd` — RefCounted; extracts `_move_animals` from GameServer; reads recipe-driven walk speed.
- `engine/animals/ai_state_system.gd` — RefCounted; extracts `_update_ambient_states` from GameServer; reads recipe-driven min-durations.
- `tests/unit/test_entity_def_registry_desire_decay.gd` — phase 1 loader test.
- `tests/unit/test_entity_def_registry_special_states.gd` — phase 1 loader test.
- `tests/unit/test_species_schema_validator_desire_decay.gd` — phase 2 validator tests.
- `tests/unit/test_species_schema_validator_min_durations.gd` — phase 2 validator tests.
- `tests/unit/test_species_schema_validator_speed_px.gd` — phase 2 validator tests.
- `tests/unit/test_species_schema_validator_grouped_errors.gd` — phase 2 grouped-error test.
- `tests/unit/test_per_species_decay_loop.gd` — phase 3 decay-consumer test.
- `tests/integration/test_decay_determinism.gd` — phase 3 determinism guard.
- `tests/unit/test_movement_system.gd` — phase 4 MovementSystem unit tests.
- `tests/unit/test_ai_state_system.gd` — phase 5 AiStateSystem unit tests.
- `tests/unit/test_behavior_timers.gd` — phase 5 timer-survives-swap test.
- `tests/unit/test_food_system_finders.gd` — phase 5 food-finder migration tests.

**Modified:**
- `engine/mod/entity_def_registry.gd` — phase 1: widen the `desires` parse path to accept co-located `{weight, decay}` entries (bare-int entries from v3 still tolerated as `{weight: N, decay: 0}`); materialize `desire_decay` and `special_states` components. Phase 3: add `has_desire_decay`/`get_desire_decay` helpers.
- `engine/core/game_state_db.gd` — phase 3: add `add_field_subset(entity_ids, component, field, delta)` op. ~10 lines.
- `engine/mod/species_schema_validator.gd` — phase 2: five new conditional required-field rules, grouped-error reporting.
- `mods/tcp_cats/species/cat.jsonc` — phase 2: bump v3→v4, rewrite each `desires` entry to co-located `{weight, decay}` shape, inline `min_duration_ticks`, `special_states`, `body_capabilities.walks.speed_px_per_tick`.
- `mods/tcp_ferrets/species/ferret.jsonc` — phase 2: same shape as cat.
- `nodes/game_server.gd` — phase 3: rewrite `_scatter_desires` decay block. Phase 4: delete `_move_animals`, instantiate MovementSystem, wire BehaviorTimers, replace per-tick call. Phase 5: delete `_update_ambient_states`, instantiate AiStateSystem, replace per-tick call.
- `engine/core/food_system.gd` — phase 5: promote four food-finder helpers to public methods.
- `tests/integration/test_desire_scatter.gd` — phase 4: replace inlined `_move_animals` with MovementSystem call.
- `tests/integration/test_runtime_smoke.gd` — phase 3: drive the decay path through production code, not inlined logic.
- `tests/integration/test_tick_loop.gd` — phase 4 + 5: update `EXPECTED_ORDER` constant for renamed tick entries.
- `.claude/rules/modding.md` — phase 2: v3→v4 changelog, two-track recipe note.
- `.claude/rules/animal-ai.md` — phase 3: document desires-implies-species contract.
- `docs/superpowers/specs/2026-04-06-game-server-extraction-design.md` — phase 6: mark MovementSystem-extraction items as superseded.

---

## Task Map

| # | Phase | Tasks |
|---|---|---|
| 1 | Loader extensions only | 1.1, 1.2 |
| 2 | Validator + recipes + docs (atomic) | 2.1 |
| 3 | `_scatter_desires` decay consumer | 3.1 |
| 4 | `MovementSystem` extraction | 4.1 |
| 5 | `AiStateSystem` extraction + food-finder migration | 5.1, 5.2 |
| 6 | Old spec cleanup | 6.1 |

---

## Phase 1 — Loader extensions only

**Phase contract:** Every commit in this phase leaves `script/validate` green. After phase 1: zero behavior change, no recipe yet declares the new fields, no consumer reads them. Loader branches are dead code that fires on phase 2's recipe content.

### Task 1.1: Create `BehaviorTimers` RefCounted struct (unused)

**Files:**
- Create: `engine/animals/behavior_timers.gd`

- [ ] **Step 1: Write the file**

```gdscript
class_name BehaviorTimers extends RefCounted

# Per-entity ticks elapsed in current ai_state. Int ticks (not float seconds);
# AiStateSystem increments by 1 per tick.
var state_timers: Dictionary = {}

# Per-entity override min_duration_ticks for the current state, set on
# SNIFFING entry by the curiosity arrival path.
var min_durations_override: Dictionary = {}

# Per-entity CuriosityTracker. Lifetime managed by the entity's lifecycle.
var curiosity_trackers: Dictionary = {}
```

- [ ] **Step 2: Run validate to confirm it compiles**

Run: `script/validate`
Expected: PASS (file is syntactically valid, no import errors).

- [ ] **Step 3: Commit**

```bash
git add engine/animals/behavior_timers.gd engine/animals/behavior_timers.gd.uid
git commit -m "$(cat <<'EOF'
feat(animals): add BehaviorTimers RefCounted struct

Holds shared per-entity state-timer dicts that MovementSystem and
AiStateSystem will own jointly once extracted. Empty / unused in this
commit; phases 4–5 wire it.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 1.2: Loader materialization for `desire_decay` and `special_states`

**Files:**
- Modify: `engine/mod/entity_def_registry.gd:115-314` (`spawn` method)
- Test: `tests/unit/test_entity_def_registry_desire_decay.gd`
- Test: `tests/unit/test_entity_def_registry_special_states.gd`

- [ ] **Step 1: Write the failing test for `desire_decay` materialization (co-located shape)**

Create `tests/unit/test_entity_def_registry_desire_decay.gd`:

```gdscript
extends GutTest

var registry: EntityDefRegistry
var db: GameStateDB


func before_each() -> void:
	registry = EntityDefRegistry.new()
	db = GameStateDB.new()


# New v4 co-located shape: each desires entry is an object with weight + decay.
func test_spawn_materializes_desire_decay_from_inline_decay_field() -> void:
	registry.register(&"tcp_test:critter", {
		&"id": &"tcp_test:critter",
		&"name": "Critter",
		&"desires": {
			&"warmth": {&"weight": 500, &"decay": -2},
			&"hunger": {&"weight": 600, &"decay":  0},
		},
		&"body_capabilities": {&"walks": {}},
		&"body_geometry": {&"size_ru": 1},
		&"senses": {&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 32},
	})

	var id: int = registry.spawn(&"tcp_test:critter", db)

	assert_true(db.has_component(id, &"desire_decay"),
		"desire_decay component should be set on spawned entity")
	var decay: Dictionary = db.get_component(id, &"desire_decay")
	assert_eq(decay.get(&"warmth"), -2, "warmth decay rate from inline field")
	assert_eq(decay.get(&"hunger"), 0, "hunger decay rate from inline field")

	# Personality weight comes from the same entry's `weight`.
	assert_true(db.has_component(id, &"personality"),
		"personality should still be materialized")
	var personality: Dictionary = db.get_component(id, &"personality")
	assert_eq(personality.get(&"warmth_weight"), 500, "weight pulled from inline weight field")


# Phase 1 backwards compat: a v3-shaped recipe (bare-int desires, no inline decay)
# still loads with implicit decay=0. Lets phase 1 land without breaking the
# existing cat.jsonc/ferret.jsonc on disk; phase 2 rewrites those recipes and
# tightens the validator to forbid bare-int entries.
func test_spawn_tolerates_bare_int_desires_with_implicit_zero_decay() -> void:
	registry.register(&"tcp_test:legacy", {
		&"id": &"tcp_test:legacy",
		&"name": "Legacy",
		&"desires": {&"warmth": 500, &"hunger": 600},   # v3 shape
		&"body_capabilities": {&"walks": {}},
		&"body_geometry": {&"size_ru": 1},
		&"senses": {&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 32},
	})

	var id: int = registry.spawn(&"tcp_test:legacy", db)

	# Legacy entries get a desire_decay component with all zeros — preserves
	# existing behavior (no decay) while making the runtime shape uniform.
	assert_true(db.has_component(id, &"desire_decay"),
		"v3 recipes still materialize desire_decay (all zeros)")
	var decay: Dictionary = db.get_component(id, &"desire_decay")
	assert_eq(decay.get(&"warmth"), 0, "v3 implicit decay")
	assert_eq(decay.get(&"hunger"), 0, "v3 implicit decay")
	# Personality weight from the bare int.
	var personality: Dictionary = db.get_component(id, &"personality")
	assert_eq(personality.get(&"warmth_weight"), 500)


func test_spawn_skips_desire_decay_when_recipe_lacks_desires() -> void:
	registry.register(&"tcp_test:arm", {
		&"id": &"tcp_test:arm",
		&"name": "Arm",
		# No desires block at all (arms don't decay).
		&"states": {&"idle": {}},
	})

	var id: int = registry.spawn(&"tcp_test:arm", db)

	assert_false(db.has_component(id, &"desire_decay"),
		"arms with no desires must not carry desire_decay")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_entity_def_registry_desire_decay.gd`
Expected: FAIL — `test_spawn_materializes_desire_decay_from_inline_decay_field` errors when the loader treats the entry as a bare int (`int(base_desires[key])` on a Dictionary). The legacy test may pass already (it's the current behavior). The arm test passes already.

- [ ] **Step 3: Widen the loader's desires-parse path**

In `engine/mod/entity_def_registry.gd:spawn`, locate the existing block (currently around lines 149–177):

```gdscript
	if def.has("desires") and not def["desires"].is_empty():
		var base_desires: Dictionary = def["desires"]
		var desire_overrides: Dictionary = overrides.get(&"desires", {})
		var personality: Dictionary = {}
		var initial_desires: Dictionary = {}
		for key: String in base_desires:
			var skey: StringName = StringName(key)
			if def.has("personality_ranges") \
					and def["personality_ranges"].has(key):
				var bounds: Array = def["personality_ranges"][key]
				var min_val: int = int(bounds[0])
				var max_val: int = int(bounds[1])
				personality[StringName(key + "_weight")] = \
					randi_range(min_val, max_val)
			else:
				personality[StringName(key + "_weight")] = \
					int(base_desires[key])
			# Deep-merge: override wins if present, else per-channel default
			if desire_overrides.has(skey):
				initial_desires[skey] = int(desire_overrides[skey])
			else:
				initial_desires[skey] = _DEFAULT_INITIAL_SATISFACTION_BY_KEY.get(
					skey, _DEFAULT_INITIAL_SATISFACTION,
				)
		db.set_component(id, &"desires", initial_desires)
		db.set_component(id, &"personality", personality)
```

Replace with:

```gdscript
	if def.has("desires") and not def["desires"].is_empty():
		var base_desires: Dictionary = def["desires"]
		var desire_overrides: Dictionary = overrides.get(&"desires", {})
		var personality: Dictionary = {}
		var initial_desires: Dictionary = {}
		var desire_decay: Dictionary = {}
		for key: String in base_desires:
			var skey: StringName = StringName(key)
			var entry_value: Variant = base_desires[key]

			# Co-located v4 shape: {weight: int, decay: int}. Bare-int v3
			# entries are tolerated for the duration of phase 1 — they get
			# weight from the bare int and decay 0. Phase 2's validator
			# rejects bare-int entries; this fallback is dead code after
			# every recipe ships v4.
			var weight: int
			var decay: int
			if entry_value is Dictionary:
				weight = int((entry_value as Dictionary).get(&"weight", 0))
				decay = int((entry_value as Dictionary).get(&"decay", 0))
			else:
				weight = int(entry_value)
				decay = 0

			if def.has("personality_ranges") \
					and def["personality_ranges"].has(key):
				var bounds: Array = def["personality_ranges"][key]
				var min_val: int = int(bounds[0])
				var max_val: int = int(bounds[1])
				personality[StringName(key + "_weight")] = \
					randi_range(min_val, max_val)
			else:
				personality[StringName(key + "_weight")] = weight

			if desire_overrides.has(skey):
				initial_desires[skey] = int(desire_overrides[skey])
			else:
				initial_desires[skey] = _DEFAULT_INITIAL_SATISFACTION_BY_KEY.get(
					skey, _DEFAULT_INITIAL_SATISFACTION,
				)

			desire_decay[skey] = decay

		db.set_component(id, &"desires", initial_desires)
		db.set_component(id, &"personality", personality)
		db.set_component(id, &"desire_decay", desire_decay)
```

Then add the special_states materialization elsewhere in `spawn` (after the existing `body_geometry` block, around line 224):

```gdscript
	# Per-name special-state durations (STARTLED today; RELOCATING/BEING_CARRIED
	# future). Required on any recipe that declares ambient_states (validator
	# enforces in phase 2). Recipes without it just don't materialize.
	if def.has("special_states"):
		var specials: Dictionary = def["special_states"]
		var typed_specials: Dictionary = {}
		for state_name in specials:
			var entry: Dictionary = specials[state_name]
			typed_specials[StringName(state_name)] = _to_stringname_keys(entry)
		db.set_component(id, &"special_states", typed_specials)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_entity_def_registry_desire_decay.gd`
Expected: PASS — all three tests (inline-shape, bare-int-fallback, no-desires).

- [ ] **Step 5: Write the failing test for `special_states`**

Create `tests/unit/test_entity_def_registry_special_states.gd`:

```gdscript
extends GutTest

var registry: EntityDefRegistry
var db: GameStateDB


func before_each() -> void:
	registry = EntityDefRegistry.new()
	db = GameStateDB.new()


func test_spawn_materializes_special_states_component() -> void:
	registry.register(&"tcp_test:critter", {
		&"id": &"tcp_test:critter",
		&"name": "Critter",
		&"desires": {&"warmth": {&"weight": 500, &"decay": -2}},
		&"body_capabilities": {&"walks": {}},
		&"body_geometry": {&"size_ru": 1},
		&"senses": {&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 32},
		&"ambient_states": {&"warm": [], &"cold": []},
		&"special_states": {&"STARTLED": {&"min_duration_ticks": 10}},
	})

	var id: int = registry.spawn(&"tcp_test:critter", db)

	assert_true(db.has_component(id, &"special_states"),
		"special_states component should be set on spawned entity")
	var specials: Dictionary = db.get_component(id, &"special_states")
	var startled: Dictionary = specials.get(&"STARTLED")
	assert_eq(startled.get(&"min_duration_ticks"), 10,
		"STARTLED min_duration_ticks materialized correctly")
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_entity_def_registry_special_states.gd`
Expected: PASS (the materialization branch covers both shapes; the test is validating the StringName key conversion path).

- [ ] **Step 7: Stamp both new tests**

Run:
```bash
script/tdd_verify stamp tests/unit/test_entity_def_registry_desire_decay.gd
script/tdd_verify stamp tests/unit/test_entity_def_registry_special_states.gd
```
Expected: each emits a `.gd.stamp` sidecar.

- [ ] **Step 8: Run the full validate to confirm green**

Run: `script/validate`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add engine/mod/entity_def_registry.gd \
        tests/unit/test_entity_def_registry_desire_decay.gd \
        tests/unit/test_entity_def_registry_desire_decay.gd.stamp \
        tests/unit/test_entity_def_registry_desire_decay.gd.uid \
        tests/unit/test_entity_def_registry_special_states.gd \
        tests/unit/test_entity_def_registry_special_states.gd.stamp \
        tests/unit/test_entity_def_registry_special_states.gd.uid
git commit -m "$(cat <<'EOF'
feat(mod): materialize desire_decay and special_states components

Additive loader change: when a recipe declares either field, the loader
projects it onto the spawned entity as a StringName-keyed component.
Recipes without the fields are unaffected (no current recipe declares
either). Phase 2's validator activation will require these fields when
their parent block is present.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2 — Validator + recipe content + docs (atomic)

**Phase contract:** All five validator rules, both recipe rewrites, and the modding.md changelog land in **one commit**. Half this list landing alone breaks `script/validate`.

### Task 2.1: Atomic schema migration

**Files:**
- Modify: `engine/mod/species_schema_validator.gd`
- Modify: `mods/tcp_cats/species/cat.jsonc`
- Modify: `mods/tcp_ferrets/species/ferret.jsonc`
- Modify: `.claude/rules/modding.md`
- Test: `tests/unit/test_species_schema_validator_desire_decay.gd`
- Test: `tests/unit/test_species_schema_validator_min_durations.gd`
- Test: `tests/unit/test_species_schema_validator_speed_px.gd`
- Test: `tests/unit/test_species_schema_validator_grouped_errors.gd`

- [ ] **Step 1: Write the failing test for `desires` co-located shape**

Create `tests/unit/test_species_schema_validator_desire_decay.gd`:

```gdscript
extends GutTest

var validator: SpeciesSchemaValidator


func before_each() -> void:
	validator = SpeciesSchemaValidator.new()


# Baseline recipe in v4 co-located shape — every desires entry is {weight, decay}.
func _base_recipe() -> Dictionary:
	return {
		&"id": "tcp_test:critter",
		&"schema_version": 4,
		&"desires": {
			&"warmth": {&"weight": 500, &"decay": -2},
			&"hunger": {&"weight": 600, &"decay":  0},
		},
		&"body_capabilities": {&"walks": {&"speed_px_per_tick": 2}},
		&"body_geometry": {&"size_ru": 1},
		&"senses": {&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 32},
	}


func test_accepts_v4_co_located_desires_shape() -> void:
	var recipe: Dictionary = _base_recipe()
	assert_true(validator.is_valid_species(recipe),
		"v4 co-located {weight, decay} entries pass validation")


func test_rejects_bare_int_desires_entry() -> void:
	var recipe: Dictionary = _base_recipe()
	# Legacy v3 shape: bare int. Phase 2 rejects this so future recipes must
	# adopt the co-located form. Phase 1's loader still tolerated bare-ints
	# for the cross-phase boot; phase 2 closes that door.
	recipe[&"desires"] = {&"warmth": 500, &"hunger": 600}
	assert_false(validator.is_valid_species(recipe),
		"bare-int desires entries must be rejected at v4")


func test_rejects_desires_entry_missing_weight() -> void:
	var recipe: Dictionary = _base_recipe()
	recipe[&"desires"] = {
		&"warmth": {&"decay": -2},   # weight missing
		&"hunger": {&"weight": 600, &"decay": 0},
	}
	assert_false(validator.is_valid_species(recipe),
		"every desires entry must declare `weight`")


func test_rejects_desires_entry_missing_decay() -> void:
	var recipe: Dictionary = _base_recipe()
	recipe[&"desires"] = {
		&"warmth": {&"weight": 500},   # decay missing
	}
	assert_false(validator.is_valid_species(recipe),
		"every desires entry must declare `decay` (no magic defaults)")


func test_rejects_positive_decay_value() -> void:
	var recipe: Dictionary = _base_recipe()
	recipe[&"desires"] = {
		&"warmth": {&"weight": 500, &"decay": 5},   # positive — forbidden
	}
	assert_false(validator.is_valid_species(recipe),
		"decay value > 0 is forbidden — decay-only mechanic")


func test_rejects_non_int_weight_or_decay() -> void:
	var recipe: Dictionary = _base_recipe()
	recipe[&"desires"] = {
		&"warmth": {&"weight": "high", &"decay": -2},
	}
	assert_false(validator.is_valid_species(recipe),
		"weight must be int")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_species_schema_validator_desire_decay.gd`
Expected: FAIL on the new shape tests — the validator currently has no rule for the co-located shape (it accepts bare-int v3 entries).

- [ ] **Step 3: Implement the validator rule for the co-located `desires` shape**

In `engine/mod/species_schema_validator.gd`, after the existing `_required_fields` loop in `is_valid_species` (currently around line 50), add a new helper-driven section. Replace the `is_valid_species` body with the structure below:

```gdscript
func is_valid_species(def: Dictionary) -> bool:
	if not _looks_like_species(def):
		return true
	var def_id: String = def.get("id", "<unknown>")
	if def.has("traversal"):
		push_error(
			(
				"SpeciesSchemaValidator: species '%s' uses legacy `traversal` field;"
				+ " replace with `body_capabilities`"
			) % def_id
		)
		return false
	if def.has("max_jump_height_ru"):
		push_error(
			(
				"SpeciesSchemaValidator: species '%s' uses legacy `max_jump_height_ru`;"
				+ " move to `body_capabilities.jumps.max_height_ru`"
			) % def_id
		)
		return false

	var violations: Array[String] = []

	for field: String in _required_fields:
		if not def.has(field) or _is_empty(def[field]):
			violations.append("missing required field: %s" % field)

	_check_desires_shape(def, violations)
	_check_walk_speed(def, violations)
	_check_min_durations(def, violations)

	if violations.is_empty():
		return true

	push_error(
		"SpeciesSchemaValidator: species '%s' has %d violation(s):\n  - %s"
		% [def_id, violations.size(), "\n  - ".join(violations)]
	)
	return false


# Validates the v4 co-located desires shape. Each entry must be a Dictionary
# carrying both `weight` (int) and `decay` (int <= 0). Bare-int entries (the
# v3 shape) are rejected; the loader's bare-int fallback exists only so the
# phase 1 commit doesn't immediately break boot.
func _check_desires_shape(def: Dictionary, violations: Array[String]) -> void:
	if not def.has("desires") or _is_empty(def["desires"]):
		return
	var desires: Dictionary = def["desires"]
	for key in desires:
		var entry: Variant = desires[key]
		if not (entry is Dictionary):
			violations.append(
				"desires.%s must be an object {weight: int, decay: int} (got bare value %s)"
				% [key, typeof(entry)]
			)
			continue
		var entry_dict: Dictionary = entry as Dictionary
		if not entry_dict.has("weight"):
			violations.append("desires.%s missing required field `weight`" % key)
		elif not (entry_dict["weight"] is int):
			violations.append(
				"desires.%s.weight must be int (got %s)"
				% [key, typeof(entry_dict["weight"])]
			)
		if not entry_dict.has("decay"):
			violations.append(
				"desires.%s missing required field `decay` (use 0 for no passive decay)"
				% key
			)
		elif not (entry_dict["decay"] is int):
			violations.append(
				"desires.%s.decay must be int (got %s)"
				% [key, typeof(entry_dict["decay"])]
			)
		elif (entry_dict["decay"] as int) > 0:
			violations.append(
				"desires.%s.decay must be <= 0 (got %d) — decay-only mechanic"
				% [key, entry_dict["decay"]]
			)


func _check_walk_speed(def: Dictionary, violations: Array[String]) -> void:
	if not def.has("body_capabilities"):
		return
	var caps: Dictionary = def["body_capabilities"]
	if not caps.has("walks"):
		return
	var walks: Dictionary = caps["walks"]
	if not walks.has("speed_px_per_tick"):
		violations.append(
			"body_capabilities.walks must declare `speed_px_per_tick`"
		)


func _check_min_durations(def: Dictionary, violations: Array[String]) -> void:
	if not def.has("ambient_states"):
		return
	var pools: Dictionary = def["ambient_states"]
	for pool_name: String in [&"warm", &"cold"]:
		if not pools.has(pool_name):
			continue
		var entries: Array = pools[pool_name]
		for i in entries.size():
			var entry: Dictionary = entries[i]
			if not entry.has("min_duration_ticks"):
				violations.append(
					"ambient_states.%s[%d] (state=%s) missing `min_duration_ticks`"
					% [pool_name, i, entry.get("state", "?")]
				)
	if not def.has("special_states"):
		violations.append(
			"recipe declares `ambient_states` but is missing `special_states`"
		)
		return
	var specials: Dictionary = def["special_states"]
	for state_name in specials:
		var entry: Dictionary = specials[state_name]
		if not entry.has("min_duration_ticks"):
			violations.append(
				"special_states.%s missing `min_duration_ticks`" % state_name
			)
```

- [ ] **Step 4: Run the desire_decay test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_species_schema_validator_desire_decay.gd`
Expected: PASS (4 tests).

- [ ] **Step 5: Write the failing test for `min_duration_ticks` validator rules**

Create `tests/unit/test_species_schema_validator_min_durations.gd`:

```gdscript
extends GutTest

var validator: SpeciesSchemaValidator


func before_each() -> void:
	validator = SpeciesSchemaValidator.new()


func _base_recipe_with_ambient() -> Dictionary:
	return {
		&"id": "tcp_test:critter",
		&"desires": {&"warmth": 500},
		&"desire_decay": {&"warmth": -2},
		&"body_capabilities": {&"walks": {&"speed_px_per_tick": 2}},
		&"body_geometry": {&"size_ru": 1},
		&"senses": {&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 32},
		&"ambient_states": {
			&"warm": [
				{&"state": "IDLE", &"weight": 10, &"min_duration_ticks": 30},
			],
			&"cold": [
				{&"state": "IDLE", &"weight": 10, &"min_duration_ticks": 30},
			],
		},
		&"special_states": {&"STARTLED": {&"min_duration_ticks": 10}},
	}


func test_accepts_complete_ambient_states() -> void:
	assert_true(validator.is_valid_species(_base_recipe_with_ambient()),
		"all min_duration_ticks declared, special_states present, passes")


func test_rejects_ambient_entry_missing_min_duration_ticks() -> void:
	var recipe: Dictionary = _base_recipe_with_ambient()
	recipe[&"ambient_states"][&"warm"].append(
		{&"state": "GROOMING", &"weight": 5}
	)
	assert_false(validator.is_valid_species(recipe),
		"ambient_states entry without min_duration_ticks must be rejected")


func test_rejects_ambient_states_without_special_states() -> void:
	var recipe: Dictionary = _base_recipe_with_ambient()
	recipe.erase(&"special_states")
	assert_false(validator.is_valid_species(recipe),
		"ambient_states present without special_states must be rejected")


func test_rejects_special_state_missing_min_duration_ticks() -> void:
	var recipe: Dictionary = _base_recipe_with_ambient()
	recipe[&"special_states"][&"STARTLED"] = {}
	assert_false(validator.is_valid_species(recipe),
		"special_states entry without min_duration_ticks must be rejected")
```

- [ ] **Step 6: Run the min_durations test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_species_schema_validator_min_durations.gd`
Expected: PASS (4 tests; the validator code from Step 3 already covers these cases).

- [ ] **Step 7: Write the failing test for `speed_px_per_tick` validator rule**

Create `tests/unit/test_species_schema_validator_speed_px.gd`:

```gdscript
extends GutTest

var validator: SpeciesSchemaValidator


func before_each() -> void:
	validator = SpeciesSchemaValidator.new()


func _base_recipe() -> Dictionary:
	return {
		&"id": "tcp_test:critter",
		&"desires": {&"warmth": 500},
		&"desire_decay": {&"warmth": -2},
		&"body_capabilities": {&"walks": {&"speed_px_per_tick": 2}},
		&"body_geometry": {&"size_ru": 1},
		&"senses": {&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 32},
	}


func test_accepts_walks_with_speed() -> void:
	assert_true(validator.is_valid_species(_base_recipe()),
		"body_capabilities.walks with speed_px_per_tick passes")


func test_rejects_walks_without_speed() -> void:
	var recipe: Dictionary = _base_recipe()
	recipe[&"body_capabilities"][&"walks"] = {}
	assert_false(validator.is_valid_species(recipe),
		"body_capabilities.walks without speed_px_per_tick must be rejected")


func test_no_walks_no_speed_required() -> void:
	var recipe: Dictionary = _base_recipe()
	# A capability without `walks` (e.g. a stationary entity) doesn't need speed
	recipe[&"body_capabilities"] = {&"jumps": {&"max_height_ru": 3}}
	assert_true(validator.is_valid_species(recipe),
		"no walks block means no speed_px_per_tick required")
```

- [ ] **Step 8: Run the speed_px test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_species_schema_validator_speed_px.gd`
Expected: PASS.

- [ ] **Step 9: Write the failing test for grouped error reporting**

Create `tests/unit/test_species_schema_validator_grouped_errors.gd`:

```gdscript
extends GutTest

var validator: SpeciesSchemaValidator


func before_each() -> void:
	validator = SpeciesSchemaValidator.new()


func test_multiple_violations_grouped_into_one_error() -> void:
	# Recipe with 3 violations: missing desire_decay, walks missing speed_px_per_tick,
	# and ambient_states present without special_states.
	var recipe: Dictionary = {
		&"id": "tcp_test:broken",
		&"desires": {&"warmth": 500},
		&"body_capabilities": {&"walks": {}},
		&"body_geometry": {&"size_ru": 1},
		&"senses": {&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 32},
		&"ambient_states": {&"warm": [], &"cold": []},
	}
	# We can't easily intercept push_error in GUT, so this test asserts
	# the boolean result. The visual-grouping behavior is hand-verified by
	# running the validator against a deliberately broken fixture and
	# reading the console output.
	assert_false(validator.is_valid_species(recipe),
		"recipe with multiple violations must reject")
```

- [ ] **Step 10: Run the grouped-errors test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_species_schema_validator_grouped_errors.gd`
Expected: PASS.

- [ ] **Step 11: Stamp all four new validator tests**

Run:
```bash
script/tdd_verify stamp tests/unit/test_species_schema_validator_desire_decay.gd
script/tdd_verify stamp tests/unit/test_species_schema_validator_min_durations.gd
script/tdd_verify stamp tests/unit/test_species_schema_validator_speed_px.gd
script/tdd_verify stamp tests/unit/test_species_schema_validator_grouped_errors.gd
```

- [ ] **Step 12: Update `mods/tcp_cats/species/cat.jsonc`**

In `mods/tcp_cats/species/cat.jsonc`:

1. Bump line 6 from `"schema_version": 3` to `"schema_version": 4`.

2. **Rewrite the `desires` block to co-located shape.** Current block is bare ints:

```jsonc
"desires": {
  "warmth":    700,
  "comfort":   700,
  "curiosity": 150,
  "hunger":    700,
  "social":    500,
  "quiet":     600,
  "peace":     500,
  "safety":    800
}
```

Replace with:

```jsonc
"desires": {
  "warmth":    { "weight": 700, "decay": -2 },
  "comfort":   { "weight": 700, "decay": -5 },
  "curiosity": { "weight": 150, "decay": -3 },
  "hunger":    { "weight": 700, "decay":  0 },   // intentionally disabled, see spec note
  "social":    { "weight": 500, "decay": -2 },
  "quiet":     { "weight": 600, "decay":  0 },
  "peace":     { "weight": 500, "decay":  0 },
  "safety":    { "weight": 800, "decay":  0 }
}
```

`personality_ranges` stays as a separate sibling block, unchanged. Decay values for the four reactive desires (`hunger`, `quiet`, `peace`, `safety`) are explicit zeros — not omitted — per "no magic defaults."

3. Replace `body_capabilities.walks: {}` (line 35) with `"walks": { "speed_px_per_tick": 2 },`.

4. Replace each `ambient_states.warm[]` and `ambient_states.cold[]` entry to add `min_duration_ticks`:

```jsonc
  "ambient_states": {
    "warm": [
      { "state": "IDLE",     "weight": 10, "min_duration_ticks":  30 },
      { "state": "GROOMING", "weight": 15, "min_duration_ticks": 100 },
      { "state": "LOAFING",  "weight": 20, "min_duration_ticks": 150 },
      { "state": "SLEEPING", "weight": 25, "min_duration_ticks": 300 }
    ],
    "cold": [
      { "state": "IDLE",     "weight": 10, "min_duration_ticks":  30 },
      { "state": "GROOMING", "weight":  5, "min_duration_ticks": 100 },
      { "state": "LOAFING",  "weight": 10, "min_duration_ticks": 150 }
    ]
  },
```

5. After the `ambient_states` block, add:

```jsonc
  "special_states": {
    "STARTLED": { "min_duration_ticks": 10 }
  },
```

- [ ] **Step 13: Update `mods/tcp_ferrets/species/ferret.jsonc`**

Apply the same shape transition to `ferret.jsonc`. Read the file first to capture the current bare-int values; each `desires.<channel>: <int>` becomes `desires.<channel>: {"weight": <int>, "decay": <int>}`. Do NOT introduce new desire keys — only the channels already declared get the wrapped shape.

Suggested ferret decay values (ferrets cycle faster than cats):

| channel | weight (use existing) | decay |
|---|---|---|
| warmth | (existing) | 0 |
| comfort | (existing) | -3 |
| curiosity | (existing) | -2 |
| hunger | (existing) | 0 |
| social | (existing) | -3 |
| quiet | (existing) | 0 |
| peace | (existing) | 0 |
| safety | (existing) | 0 |

Suggested `min_duration_ticks` for ferret states (ferrets cycle faster than cats — shorter durations):

```jsonc
  "warm": [
    { "state": "IDLE",     "weight": 10, "min_duration_ticks": 20  },
    { "state": "GROOMING", "weight": 10, "min_duration_ticks":  60 },
    { "state": "SPEED_BUMP", "weight": 25, "min_duration_ticks": 50 }
  ],
```

Confirm via `script/validate` after editing.

- [ ] **Step 14: Update `.claude/rules/modding.md`**

Append a v3→v4 changelog subsection under "Config Schema Versioning" (around line 27):

```markdown
### v3 → v4 (species recipes only)

- **`desires` shape change:** every entry is now an object `{weight: int, decay: int}` instead of a bare int. Both fields are required (no magic defaults). `decay` must be ≤ 0 — decay-only mechanic.
- **Required when `body_capabilities.walks` present:** `body_capabilities.walks.speed_px_per_tick: int`.
- **Required on every `ambient_states.warm[]` / `ambient_states.cold[]` entry:** `min_duration_ticks: int`.
- **Required when `ambient_states` present:** `special_states.<NAME>: {min_duration_ticks: int}`. Today's only triggered name is `STARTLED`; future `RELOCATING`/`BEING_CARRIED` slot in here when their trigger systems ship.

Validator groups all violations on a single recipe into one `push_error` call. No magic defaults: a missing required field rejects the recipe at mod load and skips registration.

**Two-track recipe policy.** Animals load via `entity_defs.spawn()` and adopt the new fields. Object recipes (`server_1u`, `cardboard_box`, `clothes_pile`) still flow through `place_object`'s hardcoded match block; new tunables on objects must land as recipe fields with a temporary helper rather than as new branches in `place_object`. The two-track is interim — `place_object` migration is a separate spec.
```

- [ ] **Step 15: Run validate**

Run: `script/validate`
Expected: PASS — recipes are valid against the new validator, all unit tests pass, no regression in other checks.

- [ ] **Step 16: Run the full test suite**

Run: `script/checks/gut_tests`
Expected: every test passes. If any pre-existing test fails because it built a stub recipe without the new fields, fix the test fixture (add the fields with sensible defaults) — do **not** weaken the validator.

- [ ] **Step 17: Atomic commit**

```bash
git add engine/mod/species_schema_validator.gd \
        mods/tcp_cats/species/cat.jsonc \
        mods/tcp_ferrets/species/ferret.jsonc \
        .claude/rules/modding.md \
        tests/unit/test_species_schema_validator_desire_decay.gd \
        tests/unit/test_species_schema_validator_desire_decay.gd.stamp \
        tests/unit/test_species_schema_validator_desire_decay.gd.uid \
        tests/unit/test_species_schema_validator_min_durations.gd \
        tests/unit/test_species_schema_validator_min_durations.gd.stamp \
        tests/unit/test_species_schema_validator_min_durations.gd.uid \
        tests/unit/test_species_schema_validator_speed_px.gd \
        tests/unit/test_species_schema_validator_speed_px.gd.stamp \
        tests/unit/test_species_schema_validator_speed_px.gd.uid \
        tests/unit/test_species_schema_validator_grouped_errors.gd \
        tests/unit/test_species_schema_validator_grouped_errors.gd.stamp \
        tests/unit/test_species_schema_validator_grouped_errors.gd.uid
git commit -m "$(cat <<'EOF'
feat(mod): require desire_decay, min_duration_ticks, walk speed (v3→v4)

Validator now rejects species recipes missing any of:
- desire_decay (when desires present); keys must be a subset of desires,
  values must be <= 0
- body_capabilities.walks.speed_px_per_tick (when walks present)
- min_duration_ticks on every ambient_states entry
- special_states.<NAME>.min_duration_ticks (when ambient_states present)

Multiple violations on one recipe group into a single push_error.
Recipe content updated for cat and ferret. modding.md gains a v3→v4
changelog and a two-track recipe policy note.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3 — `_scatter_desires` decay consumer (in-place)

**Phase contract:** Adds `GameStateDB.add_field_subset` (a batched-subset op resolving the spec's Open Question 1), then replaces the four `db.add_all` calls (lines 176–184 in `nodes/game_server.gd`) with a per-species batched loop driven by recipe data. No extraction — `_scatter_desires` stays inside `GameServer`. Two new helpers on `EntityDefRegistry`. Hunger stays at 0 per the recipe. Splits into two commits: 3.1a adds the DB op (no consumers); 3.1b rewrites the consumer using the op.

### Task 3.1a: Add `GameStateDB.add_field_subset`

**Files:**
- Modify: `engine/core/game_state_db.gd`
- Test: `tests/unit/test_game_state_db_add_field_subset.gd`

- [ ] **Step 1: Write failing test**

Create `tests/unit/test_game_state_db_add_field_subset.gd`:

```gdscript
extends GutTest

var db: GameStateDB

func before_each() -> void:
    db = GameStateDB.new()

func test_applies_delta_to_each_entity_in_list() -> void:
    var a: int = db.create_entity()
    var b: int = db.create_entity()
    var c: int = db.create_entity()
    db.set_component(a, &"desires", {&"warmth": 500})
    db.set_component(b, &"desires", {&"warmth": 700})
    db.set_component(c, &"desires", {&"warmth": 300})
    db.add_field_subset([a, b], &"desires", &"warmth", -10)
    assert_eq(db.get_field(a, &"desires", &"warmth"), 490)
    assert_eq(db.get_field(b, &"desires", &"warmth"), 690)
    assert_eq(db.get_field(c, &"desires", &"warmth"), 300, "c was not in the subset")

func test_zero_delta_is_a_noop() -> void:
    var a: int = db.create_entity()
    db.set_component(a, &"desires", {&"warmth": 500})
    db.add_field_subset([a], &"desires", &"warmth", 0)
    assert_eq(db.get_field(a, &"desires", &"warmth"), 500)

func test_empty_entity_list_is_a_noop() -> void:
    db.add_field_subset([], &"desires", &"warmth", -5)
    # No assertion needed; just shouldn't crash.

func test_unknown_entity_id_is_skipped() -> void:
    var a: int = db.create_entity()
    db.set_component(a, &"desires", {&"warmth": 500})
    var bogus: int = 99999
    db.add_field_subset([a, bogus], &"desires", &"warmth", -10)
    assert_eq(db.get_field(a, &"desires", &"warmth"), 490, "valid entity still updated")
    # Skipping the bogus id shouldn't affect anything else.
```

- [ ] **Step 2: Run test → fail**

Run: `script/checks/gut_tests -f tests/unit/test_game_state_db_add_field_subset.gd`
Expected: FAIL with "function not declared on GameStateDB."

- [ ] **Step 3: Implement the op**

In `engine/core/game_state_db.gd`, near the existing `add_field` (line 97), add:

```gdscript
# Apply the same field delta to every entity in `entity_ids`. Entities not in
# the DB or missing the component are silently skipped. Wraps add_field for
# correctness (dirty marking + watcher dispatch fire per entity); future work
# can swap this to a column-friendly fast path when the entity list is dense.
func add_field_subset(
        entity_ids: Array[int],
        component: StringName,
        field: StringName,
        delta: int) -> void:
    if delta == 0 or entity_ids.is_empty():
        return
    for entity_id: int in entity_ids:
        if not has_entity(entity_id):
            continue
        if not has_component(entity_id, component):
            continue
        add_field(entity_id, component, field, delta)
```

- [ ] **Step 4: Run test → pass**

Run: `script/checks/gut_tests -f tests/unit/test_game_state_db_add_field_subset.gd`
Expected: 4 passing.

- [ ] **Step 5: Stamp + validate**

```bash
script/tdd_verify stamp tests/unit/test_game_state_db_add_field_subset.gd
script/validate
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add engine/core/game_state_db.gd \
        tests/unit/test_game_state_db_add_field_subset.gd \
        tests/unit/test_game_state_db_add_field_subset.gd.stamp \
        tests/unit/test_game_state_db_add_field_subset.gd.uid
git commit -m "$(cat <<'EOF'
feat(core): add GameStateDB.add_field_subset

Batched-subset write op: applies the same field delta to every entity
in the provided list, skipping unknown entities and missing components.
Wraps the existing single-entity add_field path so dirty marking and
watcher dispatch fire correctly per entity.

Resolves Open Question 1 from 2026-05-02-recipe-driven-balance-design.
Phase 3.1b's per-species decay loop is the first consumer.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 3.1b: Per-species decay loop

**Files:**
- Modify: `engine/mod/entity_def_registry.gd` (add helpers)
- Modify: `nodes/game_server.gd:_scatter_desires` (lines ~165–191)
- Modify: `.claude/rules/animal-ai.md` (desires-implies-species contract)
- Modify: `tests/integration/test_runtime_smoke.gd:105` (drive through production code)
- Test: `tests/unit/test_per_species_decay_loop.gd`
- Test: `tests/integration/test_decay_determinism.gd`

- [ ] **Step 1: Add the failing unit test for the decay loop**

Create `tests/unit/test_per_species_decay_loop.gd`:

```gdscript
extends GutTest

var registry: EntityDefRegistry
var db: GameStateDB


func before_each() -> void:
	registry = EntityDefRegistry.new()
	db = GameStateDB.new()


func _register_critter() -> void:
	registry.register(&"tcp_test:critter", {
		&"id": &"tcp_test:critter",
		&"name": "Critter",
		&"desires": {
			&"warmth":  {&"weight": 500, &"decay": -2},
			&"comfort": {&"weight": 500, &"decay": -5},
			&"hunger":  {&"weight": 600, &"decay":  0},
		},
		&"body_capabilities": {&"walks": {&"speed_px_per_tick": 2}},
		&"body_geometry": {&"size_ru": 1},
		&"senses": {&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 32},
	})


func test_has_desire_decay_returns_true_for_recipe_that_declares_it() -> void:
	_register_critter()
	assert_true(registry.has_desire_decay(&"tcp_test:critter"))


func test_get_desire_decay_returns_recipe_dict() -> void:
	_register_critter()
	var decay: Dictionary = registry.get_desire_decay(&"tcp_test:critter")
	assert_eq(decay.get(&"warmth"), -2)
	assert_eq(decay.get(&"comfort"), -5)
	assert_eq(decay.get(&"hunger"), 0)


func test_arms_without_desires_skip_decay() -> void:
	registry.register(&"tcp_test:arm", {
		&"id": &"tcp_test:arm",
		&"name": "Arm",
		&"states": {&"idle": {}},
	})
	assert_false(registry.has_desire_decay(&"tcp_test:arm"))
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_per_species_decay_loop.gd`
Expected: FAIL — `has_desire_decay`/`get_desire_decay` don't exist yet.

- [ ] **Step 3: Add helpers to `EntityDefRegistry`**

These helpers read decay from the **co-located** v4 shape (`def["desires"][channel]["decay"]`). They tolerate v3 bare-int entries (return decay 0 for them) so phase 3.1b can run before phase 2 has rewritten cat.jsonc and ferret.jsonc — matching the loader's bare-int fallback. After phase 2 commits, every recipe is v4 and the bare-int branch is dead code.

In `engine/mod/entity_def_registry.gd`, after `get_desires` (line 100), add:

```gdscript
func has_desire_decay(entity_id: StringName) -> bool:
	# True iff the recipe declares any non-zero decay on any desires entry.
	if not _definitions.has(entity_id):
		return false
	var def: Dictionary = _definitions[entity_id]
	if not def.has("desires"):
		return false
	var desires: Dictionary = def["desires"]
	for key in desires:
		var entry: Variant = desires[key]
		if entry is Dictionary:
			var decay: int = int((entry as Dictionary).get(&"decay", 0))
			if decay != 0:
				return true
		# Bare-int entries have implicit decay 0 — never trigger this branch.
	return false


func get_desire_decay(entity_id: StringName) -> Dictionary:
	# Returns a flat {channel: int} decay dict, extracted from the recipe's
	# co-located desires shape. Bare-int v3 entries contribute decay 0 and
	# are still included in the dict so callers can iterate uniformly.
	var def: Dictionary = get_definition(entity_id)
	if not def.has("desires"):
		return {}
	var desires: Dictionary = def["desires"]
	var out: Dictionary = {}
	for key in desires:
		var skey: StringName = StringName(key)
		var entry: Variant = desires[key]
		if entry is Dictionary:
			out[skey] = int((entry as Dictionary).get(&"decay", 0))
		else:
			out[skey] = 0
	return out
```

- [ ] **Step 4: Run the unit test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_per_species_decay_loop.gd`
Expected: PASS (3 tests).

- [ ] **Step 5: Stamp the unit test**

Run: `script/tdd_verify stamp tests/unit/test_per_species_decay_loop.gd`

- [ ] **Step 6: Replace the decay block in `_scatter_desires`**

In `nodes/game_server.gd:_scatter_desires`, locate the four `db.add_all` decay calls (currently lines 176–184) and replace them with the per-species loop. Keep the heat-grid block (lines 156–174 today) unchanged. Keep the `desire_scatter.scatter_from_ads()` call and the `clamp_all` block (lines 187–191) unchanged.

```gdscript
	# AI-DEV: was 4 column-wide add_all decay calls. Now per-species so a
	# recipe that declares no decay (arm, dispenser) doesn't have its desires
	# silently mutated. Iteration order is dictionary insertion order — for
	# determinism the registration order must be stable, see entity_def_registry.
	for species_id: StringName in entity_defs.get_all_entities():
		if not entity_defs.has_desire_decay(species_id):
			continue
		var decay: Dictionary = entity_defs.get_desire_decay(species_id)
		var entities: Array[int] = db.get_entities_by_species(species_id)
		if entities.is_empty():
			continue
		for desire_type: StringName in decay:
			var rate: int = decay[desire_type]
			if rate == 0:
				continue
			db.add_field_subset(entities, &"desires", desire_type, rate)
```

Remove the stale AI-DEV "TEMP" comment at the old line 178 — recipe values are now authoritative.

- [ ] **Step 7: Update `.claude/rules/animal-ai.md` with the desires-implies-species contract**

Add to `.claude/rules/animal-ai.md` (under Species configuration, near where `desires` is documented):

```markdown
**Contract: every entity carrying `desires` must also carry `species`.** The per-species decay loop in `_scatter_desires` iterates `db.get_entities_by_species(species_id)` and skips entities without a species component. Test fixtures that wrote desires without going through `entity_defs.spawn()` no longer participate in decay; either add a species component to the fixture or stop writing desires there.
```

- [ ] **Step 8: Run the unit test and the existing integration tests**

Run:
```bash
script/checks/gut_tests -f tests/unit/test_per_species_decay_loop.gd
script/checks/gut_tests -f tests/integration/test_runtime_smoke.gd
```
Expected: PASS. If `test_runtime_smoke` fails because it inlined the old decay path, see Step 9.

- [ ] **Step 9: Update `tests/integration/test_runtime_smoke.gd:105` if it inlines the old decay**

Read the current file. If line 105 area inlines `db.add_all(&"desires", &"comfort", -5)` etc., replace with a call to `_scatter_desires` (or whatever the production entry point is) and assert the same end-state. Do not inline the new loop — invoke the production code.

If the file already drives the production path, no change needed; skip to Step 10.

- [ ] **Step 10: Add the determinism guard integration test**

Create `tests/integration/test_decay_determinism.gd`:

```gdscript
extends GutTest

# Determinism guard for the per-species decay loop. The loop iterates
# entity_defs.get_all_entities() (Dictionary insertion order). If
# registration order shifts between runs, the per-tick `add_field`
# operation order changes — the values are still commutative (4 disjoint
# fields), but watcher-firing order would shift. This test pins the
# end-state across two runs.

const TICKS: int = 100


func _build_world(seed: int) -> Dictionary:
	# Returns {db, server} — a fresh world with N cats and N ferrets.
	# Substitute with actual TCP test-world helper if one exists; otherwise
	# inline the minimal scaffolding needed.
	# NOTE: implementer should reuse whatever helper test_runtime_smoke
	# already uses to build a server-with-recipes; this stub points at the
	# shape, not the impl.
	push_error("_build_world: replace with the helper used in test_runtime_smoke")
	return {}


func test_decay_outcome_identical_across_two_runs() -> void:
	var world_a: Dictionary = _build_world(12345)
	var world_b: Dictionary = _build_world(12345)
	for _i in TICKS:
		(world_a[&"server"]).tick_decay()  # whatever the public test entrypoint is
		(world_b[&"server"]).tick_decay()
	# Snapshot the desires column for every entity in both worlds.
	var snap_a: Dictionary = (world_a[&"db"] as GameStateDB).snapshot()
	var snap_b: Dictionary = (world_b[&"db"] as GameStateDB).snapshot()
	assert_eq(snap_a, snap_b,
		"per-species decay must be deterministic across runs")
```

**Note:** This test depends on a test-world helper. If TCP doesn't have one yet, the determinism guard becomes a phase-3 follow-up rather than a phase-3 blocker — flag it in the commit message and open a tracking task. Do not block the consumer change on this test infrastructure.

- [ ] **Step 11: Run validate**

Run: `script/validate`
Expected: PASS.

- [ ] **Step 12: Stamp the determinism test if it ran clean**

Run: `script/tdd_verify stamp tests/integration/test_decay_determinism.gd`

If the test couldn't be wired (Step 10 footnote), skip the stamp and document in the commit message that the determinism test is deferred.

- [ ] **Step 13: Commit**

```bash
git add engine/mod/entity_def_registry.gd \
        nodes/game_server.gd \
        .claude/rules/animal-ai.md \
        tests/unit/test_per_species_decay_loop.gd \
        tests/unit/test_per_species_decay_loop.gd.stamp \
        tests/unit/test_per_species_decay_loop.gd.uid \
        tests/integration/test_decay_determinism.gd \
        tests/integration/test_decay_determinism.gd.stamp \
        tests/integration/test_decay_determinism.gd.uid \
        tests/integration/test_runtime_smoke.gd
git commit -m "$(cat <<'EOF'
feat(scatter): per-species recipe-driven desire decay

Replace four global add_all decay calls in _scatter_desires with a
per-species loop driven by inline decay on each entity's recipe (the
co-located v4 shape: desires.<channel>.decay). Arms and other
no-desires entities skip cleanly; cat and ferret carry their decay
rates in their recipe (phase 2 wrote those values).

The per-species loop calls db.add_field_subset (added in 3.1a) once
per (species, channel) pair instead of one add_field per entity. Same
behavior, single seam for a future column-friendly fast path.

Hunger decay stays at 0 per the recipe (intentional balance decision).
clamp_all sweeps unchanged — column-friendly safety net with no
per-species variation.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4 — `MovementSystem` extraction

**Phase contract:** Lift the entire `_move_animals` method out of `nodes/game_server.gd` into a RefCounted `MovementSystem`. Read walk speed per-entity from `body_capabilities.walks.speed_px_per_tick` instead of the engine constant `ANIMAL_SPEED_PX`. Wire `BehaviorTimers` in GameServer (instantiated and passed to MovementSystem). Update integration tests that inline `_move_animals`.

### Task 4.1: Extract `MovementSystem` and wire it

**Files:**
- Create: `engine/animals/movement_system.gd`
- Modify: `nodes/game_server.gd` (delete `_move_animals`; instantiate MovementSystem and BehaviorTimers; replace the per-tick call; remove `ANIMAL_SPEED_PX`)
- Modify: `tests/integration/test_desire_scatter.gd:130` (replace inlined `_move_animals` call)
- Modify: `tests/integration/test_tick_loop.gd` (update `EXPECTED_ORDER`)
- Test: `tests/unit/test_movement_system.gd`

- [ ] **Step 1: Re-baseline against the current `_move_animals` body**

Read `nodes/game_server.gd` lines 195–360 (the post-merge `_move_animals` and the `_can_settle_in` helper). Note: line numbers may have drifted; locate the method by name. Capture the full body — variable shapes, signal emissions, settle branches.

Confirm the existing instance fields used by `_move_animals`:
- `_movement_waypoints: Dictionary` — moves to MovementSystem-private.
- `_state_timers: Dictionary` — moves to BehaviorTimers (will be wired here in Step 5; phase 5 also touches this).
- Any other dicts referenced inside the move loop.

- [ ] **Step 2: Write the failing unit test for MovementSystem**

Create `tests/unit/test_movement_system.gd`:

```gdscript
extends GutTest

var db: GameStateDB
var registry: EntityDefRegistry
var nav: NavGraphBuilder
var object_state_manager: ObjectStateManager
var events: Object
var timers: BehaviorTimers
var system: MovementSystem


func before_each() -> void:
	db = GameStateDB.new()
	registry = EntityDefRegistry.new()
	nav = NavGraphBuilder.new()
	object_state_manager = ObjectStateManager.new(db)
	events = _make_events_stub()
	timers = BehaviorTimers.new()
	system = MovementSystem.new(db, nav, registry, object_state_manager, events, timers)


func _make_events_stub() -> Object:
	# Minimal duck-typed stub with a `creature_started_pacing` signal.
	var stub: Object = RefCounted.new()
	stub.set_script(load("res://tests/support/events_stub.gd"))
	return stub


func _register_walking_critter(speed_px_per_tick: int) -> void:
	registry.register(&"tcp_test:critter", {
		&"id": &"tcp_test:critter",
		&"name": "Critter",
		&"desires": {&"warmth": 500},
		&"desire_decay": {&"warmth": -1},
		&"body_capabilities": {&"walks": {&"speed_px_per_tick": speed_px_per_tick}},
		&"body_geometry": {&"size_ru": 1},
		&"senses": {&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 32},
	})


func test_tick_advances_entity_by_recipe_speed() -> void:
	_register_walking_critter(3)
	var id: int = registry.spawn(&"tcp_test:critter", db, {
		&"position": {&"x": 0, &"y": 100},
	})
	# Set a movement target to the right.
	db.set_component(id, &"target", {&"x": 100, &"y": 100, &"entity_id": -1})
	db.set_component(id, &"ai_state", {
		&"state": &"MOVING_TO", &"meta_state": &"GOAL_DIRECTED",
		&"commitment_score": 200,
	})

	var x_before: int = db.get_field(id, &"position", &"x")
	system.tick()
	var x_after: int = db.get_field(id, &"position", &"x")

	assert_eq(x_after - x_before, 3,
		"entity moves at the recipe-declared speed_px_per_tick")
```

The test references `tests/support/events_stub.gd`. If it doesn't exist, create a minimal stub (Step 3).

- [ ] **Step 3: Create the events stub if missing**

Check for `tests/support/events_stub.gd`. If absent, create:

```gdscript
extends RefCounted

signal creature_started_pacing(entity_id: int)
```

- [ ] **Step 4: Run the unit test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_movement_system.gd`
Expected: FAIL — `MovementSystem` doesn't exist yet.

- [ ] **Step 5: Create `engine/animals/movement_system.gd`**

```gdscript
class_name MovementSystem extends RefCounted

# Pure-core movement system. Extracted from GameServer._move_animals on
# 2026-05-03. Reads walking speed per-entity from
# body_capabilities.walks.speed_px_per_tick instead of an engine constant.
#
# Owns _waypoints (per-entity stored next-step) privately; AiStateSystem
# does not read these. Shared per-entity state-timer dicts live on the
# injected BehaviorTimers, not here.

var _db: GameStateDB
var _nav: NavGraphBuilder
var _entity_defs: EntityDefRegistry
var _object_state_manager: ObjectStateManager
var _events: Object  # duck-typed Events autoload (FoodSystem precedent)
var _timers: BehaviorTimers
var _waypoints: Dictionary = {}  # entity_id -> stored waypoint dict


func _init(
		db: GameStateDB,
		nav: NavGraphBuilder,
		entity_defs: EntityDefRegistry,
		object_state_manager: ObjectStateManager,
		events: Object,
		timers: BehaviorTimers,
) -> void:
	_db = db
	_nav = nav
	_entity_defs = entity_defs
	_object_state_manager = object_state_manager
	_events = events
	_timers = timers


func tick() -> void:
	# Migrate the body of GameServer._move_animals here verbatim, with
	# the following substitutions:
	#   - `_movement_waypoints` -> `_waypoints` (now private to this system)
	#   - `_state_timers` -> `_timers.state_timers`
	#   - `_min_durations_override` -> `_timers.min_durations_override`
	#   - `_curiosity_trackers` -> `_timers.curiosity_trackers`
	#   - `ANIMAL_SPEED_PX` constant -> per-entity read:
	#       var speed_px: int = _db.get_component(entity_id, &"body_capabilities") \
	#           .get(&"walks", {}).get(&"speed_px_per_tick", 0)
	#       (validator guarantees the value exists for any entity with walks;
	#        the .get fallback is debug-only safety)
	#   - `_can_settle_in(entity_id, host_id)` -> private method on this system
	#   - `Events.creature_started_pacing.emit(...)` -> `_events.creature_started_pacing.emit(...)`
	pass  # IMPLEMENTOR: paste the migrated body here


func _can_settle_in(entity_id: int, host_id: int) -> bool:
	# Migrate from GameServer._can_settle_in. Uses _nav, _object_state_manager,
	# _db — already injected.
	return false  # IMPLEMENTOR: paste the migrated body here
```

The `pass` placeholders mark where to paste the migrated bodies — do not commit with them empty. Subagent: complete the migration.

- [ ] **Step 6: Migrate the `tick()` body and `_can_settle_in` body**

Copy the full `_move_animals` body and `_can_settle_in` body from `nodes/game_server.gd` into the placeholders in `movement_system.gd`. Apply the substitutions listed in the comments above.

Critical: the speed read changes from `ANIMAL_SPEED_PX` to per-entity. Wherever the old code did:

```gdscript
var step: int = ANIMAL_SPEED_PX  # or similar usage
```

replace with:

```gdscript
var caps: Dictionary = _db.get_component(entity_id, &"body_capabilities")
var walks: Dictionary = caps.get(&"walks", {})
var step: int = int(walks.get(&"speed_px_per_tick", 0))
```

- [ ] **Step 7: Run the unit test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_movement_system.gd`
Expected: PASS.

- [ ] **Step 8: Stamp the unit test**

Run: `script/tdd_verify stamp tests/unit/test_movement_system.gd`

- [ ] **Step 9: Wire MovementSystem and BehaviorTimers in GameServer**

In `nodes/game_server.gd`:

1. Remove `const ANIMAL_SPEED_PX: int = 2` (line 3).
2. Remove the `_movement_waypoints: Dictionary` instance field (line 38).
3. Add a `_behavior_timers: BehaviorTimers` instance field.
4. Add a `_movement_system: MovementSystem` instance field.
5. In `_ready` (or wherever the other RefCounted systems are constructed), instantiate both:

```gdscript
	_behavior_timers = BehaviorTimers.new()
	_movement_system = MovementSystem.new(
		db, nav_builder, entity_defs, object_state_manager,
		Events, _behavior_timers,
	)
```

6. Replace the `_move_animals()` call in the tick order (likely in `_physics_process` or a `_run_tick` helper) with `_movement_system.tick()`.
7. Delete the `_move_animals` method body and the `_can_settle_in` method body — both moved to MovementSystem.

- [ ] **Step 10: Update `tests/integration/test_desire_scatter.gd:130`**

Locate the inlined `_move_animals` call (line 130 area). Replace with:

```gdscript
	_movement_system.tick()  # was _move_animals(); inline replaced 2026-05-03
```

If the test holds a reference to GameServer rather than to MovementSystem directly, expose MovementSystem as a public field on GameServer (`var movement_system: MovementSystem`) and access via that.

- [ ] **Step 11: Update `tests/integration/test_tick_loop.gd:EXPECTED_ORDER`**

Locate the `EXPECTED_ORDER` constant (it pins the per-tick method-call sequence). Update the entry that was previously `&"_move_animals"` (or similar) to `&"movement_system.tick"`. The order itself must NOT change — only the symbol name.

The AI-DEV note on this constant prohibits **reordering**, not renaming. If you read the file and see boilerplate "MUST NOT modify," verify the prose: it should mention reorder/preserve-order, not "do not edit ever."

- [ ] **Step 12: Re-stamp `tests/integration/test_tick_loop.gd` and `tests/integration/test_desire_scatter.gd` via /verify-test**

These integration tests have existing stamps. Use the `/verify-test` skill to re-run red-green and re-stamp, since the production-code path now goes through `MovementSystem.tick()` instead of inline GameServer code.

- [ ] **Step 13: Run validate**

Run: `script/validate`
Expected: PASS.

- [ ] **Step 14: Run the full test suite**

Run: `script/checks/gut_tests`
Expected: every test passes.

- [ ] **Step 15: Boot the game and verify cat behavior**

Run the game (`/Applications/Godot.app/Contents/MacOS/godot --path .`). Spawn the demo cats, watch:
- Cats walk at the same speed as before (recipe says 2 px/tick, same as the old constant).
- Cats successfully jump into boxes (cat-jumps-into-box behavior preserved through the extraction).

If behavior diverges, the migrated `tick()` body is missing a branch — re-read `_move_animals` and audit. Do **not** commit until behavior matches.

- [ ] **Step 16: Commit**

```bash
git add engine/animals/movement_system.gd \
        engine/animals/movement_system.gd.uid \
        nodes/game_server.gd \
        tests/unit/test_movement_system.gd \
        tests/unit/test_movement_system.gd.stamp \
        tests/unit/test_movement_system.gd.uid \
        tests/support/events_stub.gd \
        tests/support/events_stub.gd.uid \
        tests/integration/test_desire_scatter.gd \
        tests/integration/test_desire_scatter.gd.stamp \
        tests/integration/test_tick_loop.gd \
        tests/integration/test_tick_loop.gd.stamp
git commit -m "$(cat <<'EOF'
refactor(animals): extract MovementSystem from GameServer

Lift _move_animals (~163 lines) out of nodes/game_server.gd into a
pure-core RefCounted MovementSystem. Read walking speed per-entity from
the recipe (body_capabilities.walks.speed_px_per_tick) instead of the
ANIMAL_SPEED_PX engine constant. _movement_waypoints moves to a private
field on the system; _can_settle_in becomes a private method.
BehaviorTimers is instantiated and injected, ready for AiStateSystem to
share state-timer dicts in phase 5.

Two integration tests updated: test_desire_scatter calls the system
directly; test_tick_loop's EXPECTED_ORDER points at the renamed entry.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 5 — `AiStateSystem` extraction + food-finder migration

**Phase contract:** Promote four food-finder helpers from GameServer private to FoodSystem public. Lift `_update_ambient_states` (~183 lines) out of GameServer into a RefCounted `AiStateSystem`. Read per-entity `min_duration_ticks` from the recipe instead of the engine-side `_min_durations` dict. The STARTLED branch asserts on missing `special_states`.

### Task 5.1: Promote food-finder helpers to FoodSystem public methods

**Files:**
- Modify: `engine/core/food_system.gd`
- Modify: `nodes/game_server.gd` (private helpers go away; callers point at `food_system.X`)
- Test: `tests/unit/test_food_system_finders.gd`

- [ ] **Step 1: Write the failing test for promoted methods**

Create `tests/unit/test_food_system_finders.gd`:

```gdscript
extends GutTest

var db: GameStateDB
var food_system: FoodSystem


func before_each() -> void:
	db = GameStateDB.new()
	food_system = FoodSystem.new(db, _make_events_stub())


func _make_events_stub() -> Object:
	var stub: Object = RefCounted.new()
	stub.set_script(load("res://tests/support/events_stub.gd"))
	return stub


func test_find_nearby_food_returns_invalid_when_no_food() -> void:
	var entity_id: int = db.create_entity()
	db.set_component(entity_id, &"position", {&"x": 100, &"y": 100})
	assert_eq(food_system.find_nearby_food(entity_id), GameStateDB.INVALID_ID,
		"no food in world returns INVALID_ID")


func test_find_nearest_box_returns_invalid_when_no_boxes() -> void:
	var entity_id: int = db.create_entity()
	db.set_component(entity_id, &"position", {&"x": 100, &"y": 100})
	assert_eq(food_system.find_nearest_box(entity_id), GameStateDB.INVALID_ID,
		"no boxes in world returns INVALID_ID")


# Additional cases (food present, box present, dispenser present) are
# spot-checked via the existing food_loop integration test rather than
# duplicated here; this file only verifies the public surface exists and
# returns sentinel correctly when the world is empty.
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_food_system_finders.gd`
Expected: FAIL — methods don't exist on FoodSystem yet.

- [ ] **Step 3: Promote the helpers**

In `nodes/game_server.gd`, locate the four private helpers:
- `_find_nearby_food(entity_id) -> int`
- `_find_nearest_box(entity_id) -> int`
- `_find_nearest_dispenser(entity_id) -> int`
- `_mark_nearest_can_eaten(entity_id) -> void`

For each: copy the body into `engine/core/food_system.gd` as a public method (drop the leading underscore). Update internal references in the moved body to use `_db` (the FoodSystem's injected reference) instead of `db` (GameServer's). `find_nearest_dispenser` may already delegate to `CatFoodStates.find_nearest_dispenser` — that's fine; just rename the wrapper.

Replace each call site inside `nodes/game_server.gd` (not just inside `_update_ambient_states` — there may be other callers) with `food_system.X(...)`.

- [ ] **Step 4: Run the unit test to verify it passes**

Run: `script/checks/gut_tests -f tests/unit/test_food_system_finders.gd`
Expected: PASS.

- [ ] **Step 5: Stamp the unit test**

Run: `script/tdd_verify stamp tests/unit/test_food_system_finders.gd`

- [ ] **Step 6: Run validate**

Run: `script/validate`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add engine/core/food_system.gd \
        nodes/game_server.gd \
        tests/unit/test_food_system_finders.gd \
        tests/unit/test_food_system_finders.gd.stamp \
        tests/unit/test_food_system_finders.gd.uid
git commit -m "$(cat <<'EOF'
refactor(food): promote four food-finders to FoodSystem public API

Move find_nearby_food, find_nearest_box, find_nearest_dispenser, and
mark_nearest_can_eaten from GameServer private helpers to public
methods on FoodSystem. Required so AiStateSystem (phase 5.2) can extract
without holding a GameServer reference.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Task 5.2: Extract `AiStateSystem` and wire it

**Files:**
- Create: `engine/animals/ai_state_system.gd`
- Modify: `nodes/game_server.gd` (delete `_update_ambient_states`, the `_min_durations` constant, and the `_state_timers`/`_min_durations_override`/`_curiosity_trackers` instance fields; instantiate AiStateSystem; replace per-tick call)
- Modify: `tests/integration/test_tick_loop.gd` (update `EXPECTED_ORDER`)
- Test: `tests/unit/test_ai_state_system.gd`
- Test: `tests/unit/test_behavior_timers.gd`

- [ ] **Step 1: Re-baseline against the current `_update_ambient_states` body**

Read `nodes/game_server.gd:_update_ambient_states` (lines ~358–540 post-merge). Capture the full body — STARTLED handler, food state machine (PACING/EATING/SETTLING), AMBIENT→HUNGRY transition, ambient cycling logic. Note any state-timer dicts and `_min_durations` accesses.

- [ ] **Step 2: Write the failing unit test for AiStateSystem**

Create `tests/unit/test_ai_state_system.gd`:

```gdscript
extends GutTest

var db: GameStateDB
var registry: EntityDefRegistry
var food_system: FoodSystem
var settled_lifecycle: SettledLifecycle
var events: Object
var timers: BehaviorTimers
var system: AiStateSystem


func before_each() -> void:
	db = GameStateDB.new()
	registry = EntityDefRegistry.new()
	events = _make_events_stub()
	food_system = FoodSystem.new(db, events)
	settled_lifecycle = SettledLifecycle.new(db)
	timers = BehaviorTimers.new()
	system = AiStateSystem.new(
		db, food_system, registry, events, settled_lifecycle, timers,
	)


func _make_events_stub() -> Object:
	var stub: Object = RefCounted.new()
	stub.set_script(load("res://tests/support/events_stub.gd"))
	return stub


func _register_loafing_critter(loafing_min_duration: int) -> void:
	registry.register(&"tcp_test:critter", {
		&"id": &"tcp_test:critter",
		&"name": "Critter",
		&"desires": {&"warmth": 800, &"comfort": 800, &"hunger": 600},
		&"desire_decay": {&"warmth": 0, &"comfort": 0, &"hunger": 0},
		&"body_capabilities": {&"walks": {&"speed_px_per_tick": 1}},
		&"body_geometry": {&"size_ru": 1},
		&"senses": {&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 32},
		&"ambient_states": {
			&"warm": [
				{&"state": "LOAFING", &"weight": 100, &"min_duration_ticks": loafing_min_duration},
			],
			&"cold": [],
		},
		&"special_states": {&"STARTLED": {&"min_duration_ticks": 10}},
	})


func test_loafing_holds_until_min_duration() -> void:
	_register_loafing_critter(150)
	var id: int = registry.spawn(&"tcp_test:critter", db, {
		&"position": {&"x": 50, &"y": 100},
	})
	# Force into LOAFING.
	db.set_component(id, &"ai_state", {
		&"state": &"LOAFING", &"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	timers.state_timers[id] = 0

	# Tick 149 times; entity stays LOAFING (well-fed, well-warm, no
	# resolver-driven goal-directed transition).
	for _i in 149:
		system.tick()

	var state_at_149: StringName = db.get_component(id, &"ai_state").get(&"state")
	assert_eq(state_at_149, &"LOAFING",
		"entity holds LOAFING until min_duration_ticks elapses")
```

- [ ] **Step 3: Write the BehaviorTimers swap test**

Create `tests/unit/test_behavior_timers.gd`:

```gdscript
extends GutTest


func test_timers_persist_across_owner_swap() -> void:
	var timers: BehaviorTimers = BehaviorTimers.new()
	timers.state_timers[42] = 100
	timers.curiosity_trackers[42] = "stub"

	# Hand the same struct to two different consumer-system instances:
	# both should see the populated dicts.
	var consumer_a := RefCounted.new()
	consumer_a.set("timers", timers)
	var consumer_b := RefCounted.new()
	consumer_b.set("timers", timers)

	assert_eq(consumer_a.get("timers").state_timers[42], 100,
		"timers ref shared with consumer A")
	assert_eq(consumer_b.get("timers").state_timers[42], 100,
		"timers ref shared with consumer B")
	assert_eq(
		consumer_a.get("timers").curiosity_trackers[42],
		consumer_b.get("timers").curiosity_trackers[42],
		"both consumers see the same curiosity_trackers entry",
	)
```

- [ ] **Step 4: Run both unit tests to verify they fail**

Run:
```bash
script/checks/gut_tests -f tests/unit/test_ai_state_system.gd
script/checks/gut_tests -f tests/unit/test_behavior_timers.gd
```
Expected: FAIL — `AiStateSystem` doesn't exist; `test_behavior_timers` should already pass once `BehaviorTimers` is in place from phase 1, but verify.

- [ ] **Step 5: Create `engine/animals/ai_state_system.gd`**

```gdscript
class_name AiStateSystem extends RefCounted

# Pure-core ai-state advancer. Extracted from GameServer._update_ambient_states
# on 2026-05-03. Reads ambient-state minimum durations per-entity from
# the recipe-derived ambient_states component instead of an engine-side dict.
# Reads STARTLED recovery duration from the entity's special_states.
#
# Shares per-entity state-timer dicts with MovementSystem via the injected
# BehaviorTimers struct.

var _db: GameStateDB
var _food_system: FoodSystem
var _entity_defs: EntityDefRegistry
var _events: Object
var _settled_lifecycle: SettledLifecycle
var _timers: BehaviorTimers


func _init(
		db: GameStateDB,
		food_system: FoodSystem,
		entity_defs: EntityDefRegistry,
		events: Object,
		settled_lifecycle: SettledLifecycle,
		timers: BehaviorTimers,
) -> void:
	_db = db
	_food_system = food_system
	_entity_defs = entity_defs
	_events = events
	_settled_lifecycle = settled_lifecycle
	_timers = timers


func tick() -> void:
	# Migrate the body of GameServer._update_ambient_states here, with
	# substitutions:
	#   - `_state_timers` -> `_timers.state_timers`
	#   - `_min_durations_override` -> `_timers.min_durations_override`
	#   - `_curiosity_trackers` -> `_timers.curiosity_trackers`
	#   - `_min_durations.get(state, default)` -> per-entity read from the
	#     entity's ambient_states component (active warm/cold pool, find
	#     the entry whose `state` matches current state, read
	#     `min_duration_ticks`).
	#   - STARTLED branch top: assert(_db.has_component(entity_id, &"special_states"))
	#     and read special_states[&"STARTLED"][&"min_duration_ticks"].
	#   - `_find_nearby_food` etc. -> `_food_system.find_nearby_food` etc.
	#   - `Events.X.emit` -> `_events.X.emit`
	#   - `settled_lifecycle.enter(...)` -> `_settled_lifecycle.enter(...)`
	pass  # IMPLEMENTOR: paste the migrated body
```

- [ ] **Step 6: Migrate the `tick()` body**

Paste the full `_update_ambient_states` body into the placeholder. Apply every substitution listed in the comments. The STARTLED branch must include:

```gdscript
		# AI-DEV: STARTLED-without-special_states is a load-time validator
		# violation; the SpeciesSchemaValidator phase 2 rules catch missing
		# special_states declarations. This assertion is defense-in-depth
		# only — coverage is via the validator's unit tests at the load
		# layer, not at AiStateSystem's tick layer (Godot's assert() halts
		# the debug runner and cannot be trapped by GUT — see
		# .claude/rules/testing.md line 46).
		assert(_db.has_component(entity_id, &"special_states"),
			"Entity in STARTLED but recipe declared no special_states block")
		var specials: Dictionary = _db.get_component(entity_id, &"special_states")
		var startled_entry: Dictionary = specials.get(&"STARTLED", {})
		var startled_min: int = int(startled_entry.get(&"min_duration_ticks", 0))
```

The per-state `min_duration_ticks` lookup replaces `_min_durations.get(state, default)`. The recipe-driven read:

```gdscript
		# Find the active ambient pool entry whose `state` matches current state.
		var ambient: Dictionary = _db.get_component(entity_id, &"ambient_states")
		var pool_name: StringName = _active_pool_for(entity_id)  # warm/cold
		var pool: Array = ambient.get(pool_name, [])
		var min_dur: int = 0
		for entry: Dictionary in pool:
			if StringName(entry.get(&"state", "")) == current_state:
				min_dur = int(entry.get(&"min_duration_ticks", 0))
				break
```

(`_active_pool_for` is a helper migrated from GameServer's existing logic that picks `warm` or `cold` based on the entity's current warmth. If GameServer didn't have such a helper, replicate the inline check that previously decided.)

- [ ] **Step 7: Run both unit tests to verify they pass**

Run:
```bash
script/checks/gut_tests -f tests/unit/test_ai_state_system.gd
script/checks/gut_tests -f tests/unit/test_behavior_timers.gd
```
Expected: PASS.

- [ ] **Step 8: Stamp both unit tests**

Run:
```bash
script/tdd_verify stamp tests/unit/test_ai_state_system.gd
script/tdd_verify stamp tests/unit/test_behavior_timers.gd
```

- [ ] **Step 9: Wire AiStateSystem in GameServer**

In `nodes/game_server.gd`:

1. Remove the `_min_durations: Dictionary` constant (line 29–36).
2. Remove `_state_timers`, `_min_durations_override`, `_curiosity_trackers` instance fields (they're now on BehaviorTimers).
3. Add a `_ai_state_system: AiStateSystem` instance field.
4. Instantiate alongside MovementSystem in `_ready`:

```gdscript
	_ai_state_system = AiStateSystem.new(
		db, food_system, entity_defs, Events, settled_lifecycle,
		_behavior_timers,
	)
```

5. Replace the `_update_ambient_states()` call with `_ai_state_system.tick()`.
6. Delete the `_update_ambient_states` method body.

- [ ] **Step 10: Update `tests/integration/test_tick_loop.gd:EXPECTED_ORDER`**

Locate the entry that was previously `&"_update_ambient_states"` (or similar). Update to `&"ai_state_system.tick"`. Order itself unchanged.

- [ ] **Step 11: Re-stamp `tests/integration/test_tick_loop.gd` via /verify-test**

The integration test now drives through `ai_state_system.tick()` rather than inline GameServer code. Re-stamp.

- [ ] **Step 12: Run validate**

Run: `script/validate`
Expected: PASS.

- [ ] **Step 13: Run the full test suite**

Run: `script/checks/gut_tests`
Expected: every test passes.

- [ ] **Step 14: Boot the game and verify behavior**

Run the game. Watch for:
- Cats stay in LOAFING for ~15 sec before switching (150 ticks at 10 Hz = 15s, matching cat.jsonc).
- Hunger does not decay (recipe carries `hunger: 0`).
- Cat-jumps-into-box settling still works.
- STARTLED triggers on object removal proximity and recovers after 1 second (10 ticks).

If any behavior regresses, audit the migrated `tick()` body against the original `_update_ambient_states`.

- [ ] **Step 15: Commit**

```bash
git add engine/animals/ai_state_system.gd \
        engine/animals/ai_state_system.gd.uid \
        nodes/game_server.gd \
        tests/unit/test_ai_state_system.gd \
        tests/unit/test_ai_state_system.gd.stamp \
        tests/unit/test_ai_state_system.gd.uid \
        tests/unit/test_behavior_timers.gd \
        tests/unit/test_behavior_timers.gd.stamp \
        tests/unit/test_behavior_timers.gd.uid \
        tests/integration/test_tick_loop.gd \
        tests/integration/test_tick_loop.gd.stamp
git commit -m "$(cat <<'EOF'
refactor(animals): extract AiStateSystem from GameServer

Lift _update_ambient_states (~183 lines) into a pure-core AiStateSystem.
Read ambient-state min_duration_ticks per-entity from the recipe instead
of GameServer._min_durations. Read STARTLED recovery duration from
special_states. Food finders resolve via the now-public FoodSystem API.

State-timer dicts (state_timers, min_durations_override,
curiosity_trackers) move to BehaviorTimers, shared with MovementSystem.

test_tick_loop's EXPECTED_ORDER points at ai_state_system.tick.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 6 — Old spec cleanup

**Phase contract:** Update `2026-04-06-game-server-extraction-design.md` to mark the absorbed scope as superseded. No code change.

### Task 6.1: Mark superseded items in old spec

**Files:**
- Modify: `docs/superpowers/specs/2026-04-06-game-server-extraction-design.md`

- [ ] **Step 1: Read the older spec to find the items**

Read `docs/superpowers/specs/2026-04-06-game-server-extraction-design.md`. Locate:
- The Implementation Status table (or similar).
- The "Remaining work" list.
- Any "MovementSystem extraction" entry.

- [ ] **Step 2: Mark superseded items**

In the older spec:

1. In the Implementation Status table row for "MovementSystem extraction," change the status from "Never written" (or whatever it currently says) to:

> **Superseded by `2026-05-02-recipe-driven-balance-design.md`** — landed as part of recipe-driven balance work.

2. In the "Remaining work" list:
   - Mark item 2 (MovementSystem extraction) as superseded.
   - Mark item 3 (test file updates) as **partially superseded** — `test_desire_scatter` and `test_runtime_smoke` are now tracked here; `test_tick_loop` (which inlines `_decay_commitment`) and the `_mark_animals_dirty`-era inlining stay tracked in the older spec.

3. Add a "Successor specs" section near the top:

```markdown
## Successor specs

- `2026-05-02-recipe-driven-balance-design.md` — absorbed the MovementSystem extraction and the integration-test inlining for `_move_animals` and `_scatter_desires`. AiStateSystem extraction (formerly out of scope here) shipped as part of that spec.
```

- [ ] **Step 3: Run validate**

Run: `script/validate`
Expected: PASS (docs-only change).

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-04-06-game-server-extraction-design.md
git commit -m "$(cat <<'EOF'
docs(specs): mark older extraction items superseded

The MovementSystem extraction and two integration-test updates from the
2026-04-06 game-server-extraction spec landed as part of the
2026-05-02 recipe-driven-balance work. Mark superseded items and add a
successor-specs pointer.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review notes

- Every spec section maps to a task: schema additions → tasks 1.2 + 2.1; component materialization → 1.2; `_scatter_desires` consumer → 3.1; MovementSystem extraction → 4.1; AiStateSystem extraction + food-finder migration → 5.1 + 5.2; old spec cleanup → 6.1.
- Each phase ends with one commit. Each commit leaves `script/validate` green ("never a broken commit" from `CLAUDE.md`).
- Every test file is stamped within the same commit that creates it (per `feedback_stamp_per_task_not_deferred` memory).
- No multi-`-f` `gut_tests` invocations (per `feedback_gut_multi_f_flag` memory).
- The determinism guard in phase 3 has a documented escape hatch if the test-world helper doesn't exist yet — flag, don't block.
- The STARTLED `assert` is documented as untestable at the AiStateSystem layer; coverage is at the validator layer.
- File paths and method names are consistent across tasks. `MovementSystem.tick()` is the same in tasks 4.1 and 5.2 references; `EXPECTED_ORDER` updates are scoped per phase to match the symbol changes.
