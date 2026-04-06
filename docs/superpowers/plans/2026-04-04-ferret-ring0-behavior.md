# Ferret Ring 0 Behavior Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ferrets visibly distinct from cats with two behaviors: curiosity patrol (sniffing around racks, cats, objects) and snuggle sleep (sleeping near warm/fuzzy things). All through existing desire/advertisement systems.

**Architecture:** Curiosity ads go on racks, cats, and objects with per-ad `novelty_duration` and `novelty_cooldown` values. Each ferret gets a CuriosityTracker that remembers what it has sniffed recently. The desire resolver checks the tracker when scoring curiosity ads — recently-sniffed targets score 0. Warmth ads on cats let ferrets find them for sleeping. No new systems; everything flows through existing scoring and movement.

**Tech Stack:** GDScript, GUT test framework, existing GameStateDB/DesireResolver/CuriosityTracker classes.

**Spec:** `docs/superpowers/specs/2026-04-04-ferret-ring0-behavior-design.md`

**Run tests:** `script/checks/gut_tests`
**Run all checks:** `script/validate`

---

### Task 1: Update CuriosityTracker to support per-target cooldowns

**Files:**
- Modify: `engine/animals/curiosity_tracker.gd`
- Modify: `tests/unit/test_curiosity_tracker.gd`

The current tracker has a single `NOVELTY_COOLDOWN_TICKS` constant and combines visiting + novelty checking into one method. We need two separate methods: `visit()` to record and `is_novel()` to check with a per-target cooldown.

- [ ] **Step 1: Write failing tests for new API**

Add to `tests/unit/test_curiosity_tracker.gd`:

```gdscript
func test_is_novel_returns_true_for_unvisited_entity():
	var result: bool = _tracker.is_novel(10, 0, 100)
	assert_true(result,
		"Unvisited entity must be novel")


func test_is_novel_returns_false_within_cooldown():
	_tracker.visit(10, 0)
	var result: bool = _tracker.is_novel(10, 50, 100)
	assert_false(result,
		"Entity visited 50 ticks ago with cooldown 100 must not be novel")


func test_is_novel_returns_true_after_cooldown_expires():
	_tracker.visit(10, 0)
	var result: bool = _tracker.is_novel(10, 101, 100)
	assert_true(result,
		"Entity visited 101 ticks ago with cooldown 100 must be novel again")


func test_short_cooldown_expires_before_long_cooldown():
	_tracker.visit(10, 0)
	# Short cooldown (30 ticks) — should be novel at tick 31
	var short_novel: bool = _tracker.is_novel(10, 31, 30)
	# Long cooldown (200 ticks) — should not be novel at tick 31
	var long_novel: bool = _tracker.is_novel(10, 31, 200)
	assert_true(short_novel,
		"Short cooldown (30) must expire by tick 31")
	assert_false(long_novel,
		"Long cooldown (200) must not expire by tick 31")


func test_visit_records_without_returning_novelty():
	_tracker.visit(10, 50)
	# Visiting again at tick 60 with cooldown 100 — not novel
	assert_false(_tracker.is_novel(10, 60, 100),
		"visit() must record the tick so is_novel() can check it")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `script/checks/gut_tests`
Expected: FAIL — `visit()` and `is_novel()` methods don't exist yet.

- [ ] **Step 3: Implement new API on CuriosityTracker**

Replace the contents of `engine/animals/curiosity_tracker.gd`:

```gdscript
class_name CuriosityTracker extends RefCounted

# entity_id -> tick of last visit
var _visit_times: Dictionary = {}


# Record that this entity was visited at the given tick.
func visit(entity_id: int, current_tick: int) -> void:
	_visit_times[entity_id] = current_tick


# Check whether an entity is novel (never visited, or cooldown has expired).
func is_novel(entity_id: int, current_tick: int, cooldown_ticks: int) -> bool:
	if not _visit_times.has(entity_id):
		return true
	return current_tick - _visit_times[entity_id] >= cooldown_ticks
```

- [ ] **Step 4: Update old tests to use new API**

The existing tests reference `visit_cell()` and `NOVELTY_COOLDOWN_TICKS` which no longer exist. Update them to use the new API. Replace the existing test functions in `tests/unit/test_curiosity_tracker.gd`:

```gdscript
func test_visiting_new_cell_is_novel():
	assert_true(_tracker.is_novel(42, 0, 100),
		"A never-visited entity must be novel")


func test_revisiting_within_cooldown_is_not_novel():
	_tracker.visit(42, 0)
	assert_false(_tracker.is_novel(42, 99, 100),
		"Entity visited at tick 0 must not be novel at tick 99 with cooldown 100")


func test_entity_becomes_novel_again_after_cooldown_expires():
	_tracker.visit(42, 0)
	assert_true(_tracker.is_novel(42, 101, 100),
		"Entity must become novel again after cooldown expires")


func test_multiple_entities_tracked_independently():
	_tracker.visit(1, 0)
	_tracker.visit(2, 0)
	# Entity 1: still in cooldown
	assert_false(_tracker.is_novel(1, 50, 100),
		"Entity 1 must still be known within cooldown")
	# Entity 2: check with shorter cooldown — novel again
	assert_true(_tracker.is_novel(2, 50, 30),
		"Entity 2 must be novel with shorter cooldown (30) at tick 50")


func test_visit_at_exact_cooldown_boundary():
	_tracker.visit(99, 100)
	assert_true(_tracker.is_novel(99, 200, 100),
		"Visiting at exactly the cooldown boundary must be novel")
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `script/checks/gut_tests`
Expected: All curiosity tracker tests PASS.

- [ ] **Step 6: Commit**

```bash
git add engine/animals/curiosity_tracker.gd tests/unit/test_curiosity_tracker.gd
git commit -m "feat: update CuriosityTracker to per-target cooldowns

Replace visit_cell()/NOVELTY_COOLDOWN_TICKS with visit() and
is_novel(cooldown_ticks) to support different novelty decay rates
per target type (racks vs cats vs objects)."
```

---

### Task 2: Wire CuriosityTracker into desire resolver

**Files:**
- Modify: `engine/desires/desire_resolver.gd`
- Modify: `tests/unit/test_desire_resolver.gd`

The resolver needs to check a ferret's CuriosityTracker when scoring curiosity ads. Pass a Dictionary of trackers into `evaluate_budget()`. The `score_ad()` method gets an optional tracker + current_tick for novelty checking.

- [ ] **Step 1: Write failing tests**

Add a helper and new tests to `tests/unit/test_desire_resolver.gd`:

```gdscript
func _make_ferret(x: int, y: int, curiosity: int, curiosity_weight: int = 900) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {&"id": &"tcp_base:ferret"})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"desires", {&"warmth": 200, &"comfort": 200, &"curiosity": curiosity})
	_db.set_component(id, &"personality", {
		&"warmth_weight": 400, &"comfort_weight": 600, &"curiosity_weight": curiosity_weight,
	})
	_db.set_component(id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	_db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID, &"entity_id": Constants.INVALID_ID,
	})
	_db.update_spatial(id, x, y)
	return id


func _make_curiosity_source(x: int, y: int, strength: int = 300, radius_ru: int = 8, novelty_duration: int = 30, novelty_cooldown: int = 100) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"advertisements", {&"list": [
		{&"desire_type": &"curiosity", &"strength": strength, &"radius_ru": radius_ru,
		 &"novelty_duration": novelty_duration, &"novelty_cooldown": novelty_cooldown},
	]})
	_db.update_spatial(id, x, y)
	return id


# ── Curiosity + CuriosityTracker integration ─────────────────────────────────

func test_curious_ferret_scores_curiosity_ad_positively():
	var ferret_id: int = _make_ferret(0, 0, 800)
	var rack_id: int = _make_curiosity_source(0, 0)
	var ad: Dictionary = {
		&"desire_type": &"curiosity", &"strength": 300, &"radius_ru": 8,
		&"novelty_duration": 30, &"novelty_cooldown": 100,
	}
	var score: int = _resolver.score_ad(ferret_id, rack_id, ad)
	assert_gt(score, 0,
		"Curious ferret (curiosity=800) must score curiosity ad positively, got %d" % score)


func test_curiosity_ad_scores_zero_when_recently_visited():
	var ferret_id: int = _make_ferret(0, 0, 800)
	var rack_id: int = _make_curiosity_source(0, 0, 300, 8, 30, 100)
	var tracker: CuriosityTracker = CuriosityTracker.new()
	tracker.visit(rack_id, 0)
	var ad: Dictionary = {
		&"desire_type": &"curiosity", &"strength": 300, &"radius_ru": 8,
		&"novelty_duration": 30, &"novelty_cooldown": 100,
	}
	var score: int = _resolver.score_ad(ferret_id, rack_id, ad, tracker, 50)
	assert_eq(score, 0,
		"Recently visited curiosity ad must score 0, got %d" % score)


func test_curiosity_ad_scores_normally_after_cooldown():
	var ferret_id: int = _make_ferret(0, 0, 800)
	var rack_id: int = _make_curiosity_source(0, 0, 300, 8, 30, 100)
	var tracker: CuriosityTracker = CuriosityTracker.new()
	tracker.visit(rack_id, 0)
	var ad: Dictionary = {
		&"desire_type": &"curiosity", &"strength": 300, &"radius_ru": 8,
		&"novelty_duration": 30, &"novelty_cooldown": 100,
	}
	var score: int = _resolver.score_ad(ferret_id, rack_id, ad, tracker, 101)
	assert_gt(score, 0,
		"Curiosity ad must score positively after cooldown expires, got %d" % score)


func test_cat_ignores_curiosity_ad_due_to_low_weight():
	var cat_id: int = _make_cat(0, 0, 200, 500)
	var rack_id: int = _make_curiosity_source(0, 0)
	var ad: Dictionary = {
		&"desire_type": &"curiosity", &"strength": 300, &"radius_ru": 8,
		&"novelty_duration": 30, &"novelty_cooldown": 100,
	}
	var score: int = _resolver.score_ad(cat_id, rack_id, ad)
	# Cat has curiosity: 0 (desire value), so deficit is 0 → score is 0
	assert_eq(score, 0,
		"Cat with curiosity=0 must score curiosity ad at 0, got %d" % score)


func test_evaluate_budget_with_trackers_transitions_ferret():
	var ferret_id: int = _make_ferret(0, 0, 800)
	var rack_id: int = _make_curiosity_source(0, 0, 300, 8, 30, 100)
	var trackers: Dictionary = {ferret_id: CuriosityTracker.new()}
	_resolver.mark_dirty(ferret_id)
	_resolver.evaluate_budget(trackers)
	var ai_state: Dictionary = _db.get_component(ferret_id, &"ai_state")
	assert_eq(ai_state[&"state"], &"SEEKING",
		"Curious ferret near curiosity source must transition to SEEKING")


func test_evaluate_budget_without_trackers_still_works():
	# Existing behavior: cats with no tracker dict should work as before
	var cat_id: int = _make_cat(0, 0, 900)
	var server_id: int = _make_warm_server(0, 0)
	_resolver.mark_dirty(cat_id)
	_resolver.evaluate_budget()
	var ai_state: Dictionary = _db.get_component(cat_id, &"ai_state")
	assert_eq(ai_state[&"state"], &"SEEKING",
		"evaluate_budget() with no trackers arg must still work for cats")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `script/checks/gut_tests`
Expected: FAIL — `score_ad()` doesn't accept tracker/tick args, `evaluate_budget()` doesn't accept trackers.

- [ ] **Step 3: Update score_ad to accept optional tracker and tick**

In `engine/desires/desire_resolver.gd`, update the `score_ad` signature and add a novelty check:

```gdscript
# Score a single advertisement against an animal's desires.
# Returns 0 if the object is out of range, desire type is missing,
# or the curiosity target was recently visited (per tracker).
func score_ad(
	animal_id: int,
	object_id: int,
	ad: Dictionary,
	tracker: CuriosityTracker = null,
	current_tick: int = 0,
) -> int:
	var desire_type: StringName = ad[&"desire_type"]

	# Curiosity novelty check: if tracker provided and target was recently visited, score 0
	if tracker != null and desire_type == &"curiosity":
		var cooldown: int = ad.get(&"novelty_cooldown", 100)
		if not tracker.is_novel(object_id, current_tick, cooldown):
			return 0

	var personality: Dictionary = _db.get_component(animal_id, &"personality")
	var desires: Dictionary = _db.get_component(animal_id, &"desires")

	# Weight key derived from desire type, e.g. &"warmth" -> &"warmth_weight"
	var weight_key: StringName = StringName(String(desire_type) + "_weight")
	var desire_weight: int = personality.get(weight_key, 500)

	# Desire value IS the deficit: 0 = fully satisfied, 1000 = desperate.
	var deficit: int = desires.get(desire_type, 500)
	var strength: int = ad[&"strength"]

	var animal_pos: Dictionary = _db.get_component(animal_id, &"position")
	var object_pos: Dictionary = _db.get_component(object_id, &"position")
	var dist_pu: int = absi(animal_pos[&"x"] - object_pos[&"x"]) + absi(animal_pos[&"y"] - object_pos[&"y"])
	var radius_pu: int = Constants.ru_to_pu(ad[&"radius_ru"])

	if dist_pu > radius_pu:
		return 0

	@warning_ignore("integer_division")
	var dist_factor: int = 1000 - (dist_pu * 1000 / radius_pu) if radius_pu > 0 else 1000

	@warning_ignore("integer_division")
	return desire_weight * deficit / 1000 * strength / 1000 * dist_factor / 1000
```

- [ ] **Step 4: Update evaluate_budget and _evaluate_one to pass trackers through**

In `engine/desires/desire_resolver.gd`, update `evaluate_budget` and `_evaluate_one`:

```gdscript
# Evaluate dirty entities in priority order (highest deficit first) until the
# time budget is exhausted. Optional trackers dict maps entity_id -> CuriosityTracker.
func evaluate_budget(trackers: Dictionary = {}) -> void:
	var start: int = Time.get_ticks_usec()
	while _dirty.size() > 0:
		if Time.get_ticks_usec() - start >= Constants.EVAL_TIME_BUDGET_USEC:
			break
		var id: int = _pop_highest_deficit()
		if id == Constants.INVALID_ID:
			break
		_evaluate_one(id, trackers)
```

```gdscript
func _evaluate_one(entity_id: int, trackers: Dictionary = {}) -> void:
	if not _db.has_entity(entity_id):
		return
	if not _db.has_component(entity_id, &"position"):
		return
	if not _db.has_component(entity_id, &"desires"):
		return

	var pos: Dictionary = _db.get_component(entity_id, &"position")
	var perception_pu: int = Constants.ru_to_pu(8)
	var nearby: Array[int] = _db.query_radius(pos[&"x"], pos[&"y"], perception_pu)

	# Look up this entity's tracker (null if not a ferret or no trackers provided)
	var tracker: CuriosityTracker = trackers.get(entity_id, null)
	var current_tick: int = _db.get_tick()

	var best_score: int = 0
	var best_target_id: int = Constants.INVALID_ID
	var best_target_pos: Dictionary = {}

	for candidate_id: int in nearby:
		if candidate_id == entity_id:
			continue
		if not _db.has_component(candidate_id, &"advertisements"):
			continue
		if not _db.has_component(candidate_id, &"position"):
			continue
		var ads_component: Dictionary = _db.get_component(candidate_id, &"advertisements")
		var ad_list: Array = ads_component[&"list"]
		for ad: Dictionary in ad_list:
			var score: int = score_ad(entity_id, candidate_id, ad, tracker, current_tick)
			if score > best_score:
				best_score = score
				best_target_id = candidate_id
				best_target_pos = _db.get_component(candidate_id, &"position")

	var ai_state: Dictionary = _db.get_component(entity_id, &"ai_state")
	var commitment: int = ai_state.get(&"commitment_score", 0)

	if best_score > commitment + Constants.SWITCH_THRESHOLD:
		_db.set_component(entity_id, &"ai_state", {
			&"state": &"SEEKING",
			&"meta_state": &"GOAL_DIRECTED",
			&"commitment_score": best_score,
		})
		_db.set_component(entity_id, &"target", {
			&"x": best_target_pos[&"x"],
			&"y": best_target_pos[&"y"],
			&"entity_id": best_target_id,
		})
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `script/checks/gut_tests`
Expected: All desire resolver tests PASS (new and existing).

- [ ] **Step 6: Commit**

```bash
git add engine/desires/desire_resolver.gd tests/unit/test_desire_resolver.gd
git commit -m "feat: wire CuriosityTracker into desire resolver

score_ad() accepts optional tracker + tick to check novelty on
curiosity ads. evaluate_budget() accepts a trackers dict keyed
by entity_id. Existing callers without trackers work unchanged."
```

---

### Task 3: Create rack entities with curiosity ads

**Files:**
- Modify: `nodes/game_server.gd`

Racks need to be entities so the desire resolver can find them via spatial query. Create one per rack at startup with a position and curiosity advertisement.

- [ ] **Step 1: Add rack entity creation in _spawn_starter_entities**

In `nodes/game_server.gd`, add a new method and call it from `_spawn_starter_entities`. Add this after the existing entity spawning code:

```gdscript
func _spawn_rack_entities() -> void:
	for rack_idx: int in Constants.RACK_COUNT:
		var rack_entity: int = db.create_entity()
		@warning_ignore("integer_division")
		var x: int = rack_idx * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2
		var y: int = Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 2
		db.set_component(rack_entity, &"position", {&"x": x, &"y": y})
		db.set_component(rack_entity, &"advertisements", {&"list": [
			{
				&"desire_type": &"curiosity",
				&"strength": 300,
				&"radius_ru": 8,
				&"novelty_duration": 30,
				&"novelty_cooldown": 100,
			},
		]})
		db.update_spatial(rack_entity, x, y)
```

Add a call to `_spawn_rack_entities()` at the end of `_spawn_starter_entities()`.

- [ ] **Step 2: Run the game to verify no crash**

Run: `/Applications/Godot.app/Contents/MacOS/godot --path . --headless --quit-after 2`
Expected: No errors related to rack entities.

- [ ] **Step 3: Commit**

```bash
git add nodes/game_server.gd
git commit -m "feat: create rack entities with curiosity advertisements

Each rack gets a lightweight entity with position + curiosity ad.
Ferrets will score these through the desire resolver."
```

---

### Task 4: Add curiosity + warmth ads to cat entities

**Files:**
- Modify: `nodes/game_server.gd`

Cats should advertise both warmth (ferrets sleep near them) and curiosity (ferrets investigate them). Add advertisements components to each cat spawn.

- [ ] **Step 1: Add advertisements to cat spawns**

In `nodes/game_server.gd`, after each cat's `db.set_component(cat, &"ai_state", ...)` block, add:

For Mochi (and similarly for Biscuit and Noodle):
```gdscript
	db.set_component(cat, &"advertisements", {&"list": [
		{
			&"desire_type": &"warmth",
			&"strength": 300,
			&"radius_ru": 2,
		},
		{
			&"desire_type": &"curiosity",
			&"strength": 400,
			&"radius_ru": 3,
			&"novelty_duration": 150,
			&"novelty_cooldown": 50,
		},
	]})
```

Add the same advertisements block to cat2 (Biscuit) and cat3 (Noodle).

- [ ] **Step 2: Run tests to verify nothing broke**

Run: `script/checks/gut_tests`
Expected: All tests PASS.

- [ ] **Step 3: Commit**

```bash
git add nodes/game_server.gd
git commit -m "feat: add warmth + curiosity ads to cat entities

Cats advertise warmth (radius 2 RU) so ferrets sleep near them,
and curiosity (radius 3 RU, 15s novelty) so ferrets investigate."
```

---

### Task 5: Create CuriosityTrackers for ferrets and pass to resolver

**Files:**
- Modify: `nodes/game_server.gd`

Each ferret needs its own CuriosityTracker. Store them in a Dictionary on game_server and pass to `evaluate_budget()`.

- [ ] **Step 1: Add tracker storage and creation**

In `nodes/game_server.gd`, add a new instance variable:

```gdscript
var _curiosity_trackers: Dictionary = {}  # entity_id -> CuriosityTracker
```

In the ferret spawn sections (Slinky and Bandit), after the `db.update_spatial()` call, add:

```gdscript
	_curiosity_trackers[ferret1] = CuriosityTracker.new()
```

And for ferret2:

```gdscript
	_curiosity_trackers[ferret2] = CuriosityTracker.new()
```

- [ ] **Step 2: Pass trackers to evaluate_budget**

In `_physics_process`, change:

```gdscript
	desire_resolver.evaluate_budget()
```

to:

```gdscript
	desire_resolver.evaluate_budget(_curiosity_trackers)
```

- [ ] **Step 3: Run tests to verify nothing broke**

Run: `script/checks/gut_tests`
Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add nodes/game_server.gd
git commit -m "feat: create CuriosityTracker per ferret, pass to resolver

Each ferret gets its own tracker instance. The trackers dict is
passed to evaluate_budget() so curiosity ads get novelty checks."
```

---

### Task 6: Handle ferret arrival — SNIFFING with novelty_duration

**Files:**
- Modify: `nodes/game_server.gd`

When a ferret arrives at a curiosity target, it should enter SNIFFING (not IDLE) and record the visit. The SNIFFING duration comes from the ad's `novelty_duration`.

- [ ] **Step 1: Update arrival logic in _move_animals**

In `nodes/game_server.gd`, replace the arrival block in `_move_animals()` (the `if dist <= ANIMAL_SPEED_PU:` block, currently lines 185-201) with:

```gdscript
		if dist <= ANIMAL_SPEED_PU:
			# Arrived
			db.set_component(entity_id, &"position", {
				&"x": target[&"x"], &"y": target[&"y"],
			})
			db.update_spatial(entity_id, target[&"x"], target[&"y"])

			# Determine arrival state based on what drew the animal here
			var arrival_state: StringName = &"IDLE"
			var arrival_duration: float = -1.0
			if _curiosity_trackers.has(entity_id) and target[&"entity_id"] != Constants.INVALID_ID:
				var target_id: int = target[&"entity_id"]
				if db.has_component(target_id, &"advertisements"):
					var ads: Dictionary = db.get_component(target_id, &"advertisements")
					for ad: Dictionary in ads[&"list"]:
						if ad[&"desire_type"] == &"curiosity":
							arrival_state = &"SNIFFING"
							arrival_duration = float(ad.get(&"novelty_duration", 100)) / 10.0
							_curiosity_trackers[entity_id].visit(
								target_id, db.get_tick()
							)
							break

			db.set_component(entity_id, &"ai_state", {
				&"state": arrival_state,
				&"meta_state": &"AMBIENT",
				&"commitment_score": ai[&"commitment_score"],
			})
			db.set_component(entity_id, &"target", {
				&"x": Constants.INVALID_ID,
				&"y": Constants.INVALID_ID,
				&"entity_id": Constants.INVALID_ID,
			})
			# Override min duration for this SNIFFING session if set
			if arrival_duration > 0.0:
				_state_timers[entity_id] = 0.0
				_min_durations_override[entity_id] = arrival_duration
```

- [ ] **Step 2: Add the _min_durations_override dict**

Add a new instance variable near the top of game_server.gd alongside `_state_timers`:

```gdscript
var _min_durations_override: Dictionary = {}  # entity_id -> float (per-session override)
```

- [ ] **Step 3: Use override in _update_ambient_states**

In `_update_ambient_states()`, change the min duration lookup (currently line 240):

```gdscript
		var min_dur: float = _min_durations.get(current_state, 3.0)
```

to:

```gdscript
		var min_dur: float = _min_durations_override.get(entity_id, _min_durations.get(current_state, 3.0))
```

And when the state transitions (after `_state_timers[entity_id] = 0.0`), clear the override:

```gdscript
			if new_state != current_state:
				db.set_component(entity_id, &"ai_state", {
					&"state": new_state,
					&"meta_state": &"AMBIENT",
					&"commitment_score": ai[&"commitment_score"],
				})
				_state_timers[entity_id] = 0.0
				_min_durations_override.erase(entity_id)
```

- [ ] **Step 4: Run the game and observe ferret behavior**

Run: `/Applications/Godot.app/Contents/MacOS/godot --path .`
Expected: Ferrets should move toward racks, enter SNIFFING for ~3 seconds, then move to the next rack or a cat.

- [ ] **Step 5: Run tests to verify nothing broke**

Run: `script/checks/gut_tests`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add nodes/game_server.gd
git commit -m "feat: ferrets enter SNIFFING on curiosity arrival

On arriving at a curiosity target, ferrets enter SNIFFING with
duration from the ad's novelty_duration. Visit is recorded in
the CuriosityTracker so the same target scores 0 until cooldown."
```

---

### Task 7: Integration scenario tests

**Files:**
- Create: `tests/scenario/test_ferret_curiosity.gd`

Verify the full loop: ferret scores curiosity ad → moves → arrives → SNIFFING → tracker records visit → same target scores 0 → ferret picks different target.

- [ ] **Step 1: Write scenario tests**

Create `tests/scenario/test_ferret_curiosity.gd`:

```gdscript
extends GutTest

var _db: GameStateDB
var _resolver: DesireResolver
var _trackers: Dictionary = {}


func before_each() -> void:
	_db = GameStateDB.new()
	_resolver = DesireResolver.new(_db)
	_trackers = {}


func _make_ferret(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {&"id": &"tcp_base:ferret"})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"desires", {&"warmth": 200, &"comfort": 200, &"curiosity": 800})
	_db.set_component(id, &"personality", {
		&"warmth_weight": 400, &"comfort_weight": 600, &"curiosity_weight": 900,
	})
	_db.set_component(id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	_db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	_db.update_spatial(id, x, y)
	_trackers[id] = CuriosityTracker.new()
	return id


func _make_rack(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"advertisements", {&"list": [
		{&"desire_type": &"curiosity", &"strength": 300, &"radius_ru": 8,
		 &"novelty_duration": 30, &"novelty_cooldown": 100},
	]})
	_db.update_spatial(id, x, y)
	return id


func test_ferret_seeks_curiosity_source():
	var ferret_id: int = _make_ferret(0, 5000)
	var rack_id: int = _make_rack(0, 0)
	_resolver.mark_dirty(ferret_id)
	_resolver.evaluate_budget(_trackers)
	var ai: Dictionary = _db.get_component(ferret_id, &"ai_state")
	var target: Dictionary = _db.get_component(ferret_id, &"target")
	assert_eq(ai[&"state"], &"SEEKING",
		"Ferret must transition to SEEKING toward curiosity source")
	assert_eq(target[&"entity_id"], rack_id,
		"Ferret must target the rack entity")


func test_visited_rack_scores_zero_ferret_picks_other():
	var ferret_id: int = _make_ferret(0, 5000)
	var rack_a: int = _make_rack(0, 0)
	var rack_b: int = _make_rack(5000, 0)
	# Pre-visit rack_a
	_trackers[ferret_id].visit(rack_a, 0)
	_db.advance_tick()
	_resolver.mark_dirty(ferret_id)
	_resolver.evaluate_budget(_trackers)
	var target: Dictionary = _db.get_component(ferret_id, &"target")
	assert_eq(target[&"entity_id"], rack_b,
		"Ferret must pick unvisited rack_b over recently-visited rack_a")


func test_ferret_prefers_novel_object_over_rack():
	var ferret_id: int = _make_ferret(0, 5000)
	var rack_id: int = _make_rack(0, 0)
	# Novel pillow — higher strength, never visited
	var pillow_id: int = _db.create_entity()
	_db.set_component(pillow_id, &"position", {&"x": 0, &"y": 2000})
	_db.set_component(pillow_id, &"advertisements", {&"list": [
		{&"desire_type": &"curiosity", &"strength": 500, &"radius_ru": 8,
		 &"novelty_duration": 500, &"novelty_cooldown": 200},
	]})
	_db.update_spatial(pillow_id, 0, 2000)
	_resolver.mark_dirty(ferret_id)
	_resolver.evaluate_budget(_trackers)
	var target: Dictionary = _db.get_component(ferret_id, &"target")
	assert_eq(target[&"entity_id"], pillow_id,
		"Ferret must prefer novel high-strength pillow over rack")


func test_cat_ignores_curiosity_ads():
	var cat_id: int = _db.create_entity()
	_db.set_component(cat_id, &"species", {&"id": &"tcp_base:cat"})
	_db.set_component(cat_id, &"position", {&"x": 0, &"y": 5000})
	_db.set_component(cat_id, &"desires", {&"warmth": 200, &"comfort": 200, &"curiosity": 0})
	_db.set_component(cat_id, &"personality", {
		&"warmth_weight": 800, &"comfort_weight": 600, &"curiosity_weight": 100,
	})
	_db.set_component(cat_id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	_db.set_component(cat_id, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	_db.update_spatial(cat_id, 0, 5000)
	var _rack_id: int = _make_rack(0, 0)
	_resolver.mark_dirty(cat_id)
	_resolver.evaluate_budget()
	var ai: Dictionary = _db.get_component(cat_id, &"ai_state")
	assert_eq(ai[&"meta_state"], &"AMBIENT",
		"Cat with curiosity=0 must stay AMBIENT, not seek curiosity source")
```

- [ ] **Step 2: Run tests**

Run: `script/checks/gut_tests`
Expected: All scenario tests PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/scenario/test_ferret_curiosity.gd
git commit -m "test: add ferret curiosity patrol scenario tests

Covers: ferret seeks curiosity source, prefers unvisited target,
prefers novel objects over racks, cat ignores curiosity ads."
```

---

### Task 8: Soak test — ferret visits multiple racks

**Files:**
- Create: `tests/scenario/test_ferret_soak.gd`

Verify that over many ticks, a ferret actually patrols multiple racks and doesn't get stuck.

- [ ] **Step 1: Write soak test**

Create `tests/scenario/test_ferret_soak.gd`:

```gdscript
extends GutTest


func test_ferret_visits_multiple_racks_over_time():
	var db: GameStateDB = GameStateDB.new()
	var resolver: DesireResolver = DesireResolver.new(db)
	var trackers: Dictionary = {}

	# Create ferret
	var ferret_id: int = db.create_entity()
	db.set_component(ferret_id, &"species", {&"id": &"tcp_base:ferret"})
	db.set_component(ferret_id, &"position", {&"x": 0, &"y": 0})
	db.set_component(ferret_id, &"desires", {&"warmth": 200, &"comfort": 200, &"curiosity": 800})
	db.set_component(ferret_id, &"personality", {
		&"warmth_weight": 400, &"comfort_weight": 600, &"curiosity_weight": 900,
	})
	db.set_component(ferret_id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	db.set_component(ferret_id, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(ferret_id, 0, 0)
	trackers[ferret_id] = CuriosityTracker.new()

	# Create 5 racks spread across the floor
	var rack_ids: Array[int] = []
	for i: int in 5:
		var rack_id: int = db.create_entity()
		var x: int = i * 5000
		db.set_component(rack_id, &"position", {&"x": x, &"y": 0})
		db.set_component(rack_id, &"advertisements", {&"list": [
			{&"desire_type": &"curiosity", &"strength": 300, &"radius_ru": 30,
			 &"novelty_duration": 30, &"novelty_cooldown": 100},
		]})
		db.update_spatial(rack_id, x, 0)
		rack_ids.append(rack_id)

	# Track which racks the ferret targets over 500 ticks
	var visited_racks: Dictionary = {}  # rack_id -> true
	for tick: int in 500:
		db.advance_tick()
		resolver.mark_dirty(ferret_id)
		resolver.evaluate_budget(trackers)
		var target: Dictionary = db.get_component(ferret_id, &"target")
		if target[&"entity_id"] != Constants.INVALID_ID:
			visited_racks[target[&"entity_id"]] = true
			# Simulate arrival: teleport ferret to target, record visit, reset to IDLE
			db.set_component(ferret_id, &"position", {
				&"x": target[&"x"], &"y": target[&"y"],
			})
			db.update_spatial(ferret_id, target[&"x"], target[&"y"])
			trackers[ferret_id].visit(target[&"entity_id"], db.get_tick())
			db.set_component(ferret_id, &"ai_state", {
				&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
			})
			db.set_component(ferret_id, &"target", {
				&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
				&"entity_id": Constants.INVALID_ID,
			})

	assert_gte(visited_racks.size(), 3,
		"Ferret must visit at least 3 of 5 racks in 500 ticks, visited %d" % visited_racks.size())
```

- [ ] **Step 2: Run tests**

Run: `script/checks/gut_tests`
Expected: Soak test PASSES — ferret visits at least 3 racks.

- [ ] **Step 3: Commit**

```bash
git add tests/scenario/test_ferret_soak.gd
git commit -m "test: soak test verifying ferret patrols multiple racks

Runs 500 ticks with 5 racks, asserts ferret visits at least 3."
```
