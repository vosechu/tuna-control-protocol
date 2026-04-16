# Component-Mindset Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove species-based dispatch from code paths. Systems check capabilities (components on entities), not species labels. Species labels stay as display/save data only. Game must boot and tests must stay green at every commit checkpoint.

**Architecture:** Three staged refactor per `docs/superpowers/specs/2026-04-16-component-mindset-refactor-design.md`. Stage 1 replaces functional species-dispatch with recipe fields + a schema validator (game stays shippable). Stage 2 renames symbols (`cat_presence` → `reclamation`, `is_purring` → `is_satisfied`, etc.) and re-verifies every affected test. Stage 3 is docs/memory/agent/linter cleanup. Each Stage 1 sub-item commit updates engine code + ALL species recipes atomically (see spec §1.11).

**Tech Stack:** GDScript, Godot 4.6, GUT tests, JSONC recipes, `script/checks/` shell-based linters, `script/stamp_tests` + `script/checks/verify_tests` for tamper-evident test stamps.

**Reference spec:** `docs/superpowers/specs/2026-04-16-component-mindset-refactor-design.md`

**Related rules:** `.claude/rules/llm-test-verification.md` (Stage 2 re-verification cadence), `.claude/rules/modding.md` (Stage 3.10 schema section), `.claude/rules/animal-ai.md` (Stage 3.2 edits).

---

## Stage ordering rationale (read before starting)

Order matters. The spec calls out three hard ordering constraints:

- **Task 1 before Task 2** — Task 1 (curiosity/stimulation merge) changes which desire channel the curiosity-tracker loop must see. Task 2 (hoist tracker init) reads the consolidated channel.
- **Task 3 (validator scaffold) before Tasks 6–9** — Tasks 6–9 each add a recipe field that the validator enforces. Without the validator scaffold in place first, Tasks 6–9 would allow a mod author to silently omit a mandatory field.
- **Stage 1 before Stage 2** — Stage 2 renames `cat_presence` → `reclamation`, which depends on the Stage 1.7 `tends_servers` query fix already having landed.

Stage 2 re-verification (Task 19) is unusually heavy because it touches ~10–12 test files. That task is a single commit (branch merge) per spec §Stage 2 success criteria, to avoid breaking `verify_tests` CI for other branches mid-stream.

---

# Stage 1 — Functional dispatch fixes

Goal: the game and all tests still work, but code no longer dispatches on species name. Each commit in Stage 1 must leave the game bootable and tests green.

---

### Task 1: Merge `stimulation` desire into `curiosity`

**Spec reference:** §1.6. Both recipes reference `stimulation` in `verbs.*.desire_affinities` but neither declares `stimulation` in their `desires` block. Merge into `curiosity` (already declared in both).

**Files:**
- Modify: `mods/tcp_cats/species/cat.jsonc:62-68` (verb block)
- Modify: `mods/tcp_ferrets/species/ferret.jsonc:45-48` (verb block)

- [ ] **Step 1: Update cat verbs to target `curiosity` instead of `stimulation`**

In `mods/tcp_cats/species/cat.jsonc`, replace the `verbs` block (lines 62–68):

```jsonc
  "verbs": {
    "push": { "effectiveness": 1000, "desire_affinities": { "curiosity": 500 } },
    "bat": { "effectiveness": 500, "desire_affinities": { "curiosity": 600 } },
    "drag": { "effectiveness": 700, "desire_affinities": { "curiosity": 800 } },
    "knock_off": { "effectiveness": 2000, "desire_affinities": { "curiosity": 900 } },
    "sit_on": { "desire_affinities": { "comfort": 700, "warmth": 200 } }
  },
```

- [ ] **Step 2: Update ferret verbs to target `curiosity` instead of `stimulation`**

In `mods/tcp_ferrets/species/ferret.jsonc`, replace the `verbs` block (lines 45–48):

```jsonc
  "verbs": {
    "push": { "effectiveness": 800, "desire_affinities": { "curiosity": 500 } },
    "drag": { "effectiveness": 1000, "desire_affinities": { "curiosity": 900 } }
  },
```

- [ ] **Step 3: Verify the game still boots**

Run: `/Applications/Godot.app/Contents/MacOS/godot --headless --import`
Expected: exits cleanly, no parse errors reported.

Run: `script/validate`
Expected: all checks pass.

- [ ] **Step 4: Commit**

```bash
git add mods/tcp_cats/species/cat.jsonc mods/tcp_ferrets/species/ferret.jsonc
git commit -m "refactor(recipes): merge stimulation into curiosity desire channel

Both species recipes referenced 'stimulation' in verb desire_affinities
but neither declared it in desires. Merge into curiosity per
component-mindset-refactor-design §1.6.

Future-axis note: when play/toy verbs land, curiosity (novelty-seeking)
and stimulation (active play) may re-split. Merge is forward-compatible."
```

---

### Task 2: Hoist curiosity-tracker initialization out of ferret-only branch

**Spec reference:** §1.5. `_curiosity_trackers` init lives inside the `tcp_ferrets:ferret` branch (`nodes/game_server.gd:699–708`). A third species declaring `curiosity` won't get a tracker. Move the init to iterate all spawned entities whose `desires` declares `curiosity`.

**Files:**
- Modify: `nodes/game_server.gd:699-708` (inside `_spawn_starter_entities`)

- [ ] **Step 1: Read current code location**

Read `nodes/game_server.gd` lines 700–710 to confirm the block:

```gdscript
			for overrides: Dictionary in ferret_spawns:
				var id: int = _entity_defs.spawn(
					&"tcp_ferrets:ferret", db, overrides,
				)
				var desires: Dictionary = _entity_defs.get_desires(
					&"tcp_ferrets:ferret",
				)
				if desires.has("curiosity"):
					_curiosity_trackers[id] = \
						CuriosityTracker.new()
```

- [ ] **Step 2: Remove the in-loop tracker init and add a generic post-spawn pass**

In `nodes/game_server.gd`, replace the ferret-spawn inner loop body:

```gdscript
			for overrides: Dictionary in ferret_spawns:
				_entity_defs.spawn(
					&"tcp_ferrets:ferret", db, overrides,
				)
```

Then after `_spawn_rack_entities()` call at line 710 (or equivalent — find the end of `_spawn_starter_entities`), append a generic pass:

```gdscript
	_init_curiosity_trackers()
```

- [ ] **Step 3: Add the generic init function**

Append a new function to `nodes/game_server.gd` near the starter-spawn section:

```gdscript
func _init_curiosity_trackers() -> void:
	var entities: Array[int] = db.get_entities_with(&"desires")
	for entity_id: int in entities:
		if _curiosity_trackers.has(entity_id):
			continue
		var desires: Dictionary = db.get_component(entity_id, &"desires")
		if desires.has(&"curiosity"):
			_curiosity_trackers[entity_id] = CuriosityTracker.new()
```

- [ ] **Step 4: Run the game and verify ferrets still patrol**

Run: `script/validate`
Expected: all tests green.

Run: `/Applications/Godot.app/Contents/MacOS/godot --path . --headless --quit-after 30` (boot for 3 seconds, then exit)
Expected: exits with status 0.

- [ ] **Step 5: Commit**

```bash
git add nodes/game_server.gd
git commit -m "refactor(server): hoist curiosity-tracker init out of ferret-only branch

Generic post-spawn pass initializes a CuriosityTracker for any entity
whose desires component declares 'curiosity'. Third species with
curiosity desire will now get tracker wiring for free.

Requires Task 1 to have landed — the consolidated curiosity channel
is what this loop detects."
```

---

### Task 3: Scaffold the species-recipe schema validator (permissive)

**Spec reference:** §1.10. Add a load-time validator next to `engine/mod/entity_def_registry.gd`. Initially validates only fields that already exist in all recipes (`id`, `traversal`, `desires`). Subsequent Stage 1 tasks extend it as they add new mandatory fields.

**Files:**
- Create: `engine/mod/species_schema_validator.gd`
- Modify: `engine/mod/mod_loader.gd:95-108` (inside `_load_jsonc_dir`)
- Create: `tests/unit/test_species_schema_validator.gd`

- [ ] **Step 1: Write failing test first**

Create `tests/unit/test_species_schema_validator.gd`:

```gdscript
extends GutTest


func test_valid_species_def_passes():
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {
		"id": "test:cat",
		"desires": {"warmth": 500},
		"traversal": ["WALK"],
	}
	assert_true(validator.is_valid_species(def))


func test_missing_desires_rejected():
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {
		"id": "test:cat",
		"traversal": ["WALK"],
	}
	assert_false(validator.is_valid_species(def))
	assert_push_error("missing required field: desires")


func test_missing_traversal_rejected():
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {
		"id": "test:cat",
		"desires": {"warmth": 500},
	}
	assert_false(validator.is_valid_species(def))
	assert_push_error("missing required field: traversal")


func test_non_species_def_passes_through():
	# Objects are loaded via the same jsonc pipeline; validator should
	# ignore defs that don't claim to be species.
	var validator := SpeciesSchemaValidator.new()
	var def: Dictionary = {"id": "test:box", "object_type_id": "box"}
	assert_true(validator.is_valid_species(def))
```

- [ ] **Step 2: Run tests to confirm they fail**

Run: `script/checks/gut_tests -f tests/unit/test_species_schema_validator.gd`
Expected: 4 failures — SpeciesSchemaValidator class not found.

- [ ] **Step 3: Create the validator**

Create `engine/mod/species_schema_validator.gd`:

```gdscript
class_name SpeciesSchemaValidator extends RefCounted

# Detects "is this recipe claiming to be a species?" by looking for
# the `desires` + `traversal` fields. Objects have `object_type_id`
# or `placement` and are skipped.
const _SPECIES_MARKER_FIELDS: Array[String] = ["desires", "traversal"]

# Fields that must be present on any species recipe. Extended by
# subsequent Stage 1 tasks as they add recipe-driven configuration.
var _required_fields: Array[String] = ["desires", "traversal"]


func add_required_field(field_name: String) -> void:
	if field_name in _required_fields:
		return
	_required_fields.append(field_name)


func is_valid_species(def: Dictionary) -> bool:
	if not _looks_like_species(def):
		return true
	for field: String in _required_fields:
		if not def.has(field) or _is_empty(def[field]):
			push_error(
				"SpeciesSchemaValidator: species '%s' missing required field: %s"
				% [def.get("id", "<unknown>"), field]
			)
			return false
	return true


func _looks_like_species(def: Dictionary) -> bool:
	# Any recipe declaring desires + traversal is a species.
	for marker: String in _SPECIES_MARKER_FIELDS:
		if not def.has(marker):
			return false
	return true


func _is_empty(value: Variant) -> bool:
	if value is Dictionary:
		return (value as Dictionary).is_empty()
	if value is Array:
		return (value as Array).is_empty()
	return value == null
```

- [ ] **Step 4: Wire the validator into the mod loader**

In `engine/mod/mod_loader.gd`, modify the constructor to hold a validator and update `_load_jsonc_dir`. Change the file:

Add at top of class:
```gdscript
var validator: SpeciesSchemaValidator = SpeciesSchemaValidator.new()
```

In `_load_jsonc_dir`, after `var entity_id := StringName(str(data["id"]))` (line ~106), add a validation gate:

```gdscript
			var entity_id := StringName(str(data["id"]))
			if not validator.is_valid_species(data):
				push_error(
					"ModLoader: rejecting invalid species '%s' from %s"
					% [entity_id, file_path]
				)
				entry = dir.get_next()
				continue
			entity_defs.register(entity_id, data)
```

- [ ] **Step 5: Verify tests pass**

Run: `script/checks/gut_tests -f tests/unit/test_species_schema_validator.gd`
Expected: 4 passes.

Run: `script/validate`
Expected: all checks pass (existing recipes already have `desires` + `traversal`).

- [ ] **Step 6: Mutate and re-test (per llm-test-verification Step 9)**

For `test_missing_desires_rejected`: in `species_schema_validator.gd`, comment out the `push_error` line in the `is_valid_species` loop. Run the single test:

Run: `script/checks/gut_tests -f tests/unit/test_species_schema_validator.gd -F test_missing_desires_rejected`
Expected: fail on the `assert_push_error` call (no error was emitted).

Restore the line.

For `test_valid_species_def_passes`: change `return true` at the end of `is_valid_species` to `return false`. Run tests. Expected: the positive cases fail. Restore.

Run: `script/checks/gut_tests -f tests/unit/test_species_schema_validator.gd`
Expected: all 4 pass again.

- [ ] **Step 7: Stamp the tests**

Run: `script/stamp_tests tests/unit/test_species_schema_validator.gd`
Run: `script/checks/verify_tests`
Expected: exits 0.

- [ ] **Step 8: Commit**

```bash
git add engine/mod/species_schema_validator.gd engine/mod/mod_loader.gd tests/unit/test_species_schema_validator.gd tests/unit/test_species_schema_validator.gd.stamp
git commit -m "feat(mod-loader): add species-recipe schema validator

Validator runs at mod load. Rejects species recipes missing required
fields (initially desires + traversal) with push_error. Subsequent
Stage 1 tasks will extend the required-field list as they introduce
new recipe-driven components.

Part of component-mindset-refactor §1.10."
```

---

### Task 4: Remove unused `register_cat` dispatch

**Spec reference:** §1.8. `sound_manager.register_cat` is a no-op (see `nodes/sound_manager.gd:31`). The dispatch in `nodes/game_client.gd:262–272` calls it with a species-string check. Delete both.

**Files:**
- Modify: `nodes/game_client.gd:262-272`
- Modify: `nodes/sound_manager.gd:31-32`

- [ ] **Step 1: Delete the register_cat call and loop in game_client.gd**

In `nodes/game_client.gd`, replace lines 261–272 (the `sm.initialize(...)` + registration loop) with just the initialize call:

```gdscript
	sm.initialize(game_server.db, Events)
```

- [ ] **Step 2: Delete the no-op register_cat function in sound_manager.gd**

In `nodes/sound_manager.gd`, delete lines 31–32:

```gdscript
func register_cat(_entity_id: int) -> void:
	pass
```

- [ ] **Step 3: Verify no other callers exist**

Run: `grep -rn "register_cat" nodes/ engine/ tests/ --include="*.gd"`
Expected: zero matches.

- [ ] **Step 4: Run tests and boot the game**

Run: `script/validate`
Expected: all checks pass.

- [ ] **Step 5: Commit**

```bash
git add nodes/game_client.gd nodes/sound_manager.gd
git commit -m "refactor(client): remove unused register_cat species dispatch

register_cat was a no-op. Deletes the species-string check in
game_client and the empty function in sound_manager. No behavior change.

Part of component-mindset-refactor §1.8."
```

---

### Task 5: Remove species default from nav graph builder

**Spec reference:** §1.3. `NavGraphBuilder.get_astar()` has a default of `&"tcp_cats:cat"`. `get_nearest_floor_node` falls back to the cat's astar for floor-node lookups. Neither is conceptually correct — floor node positions are species-agnostic. Move floor-node positions into the builder; require explicit species_id on `get_astar`.

**Files:**
- Modify: `engine/navigation/nav_graph_builder.gd:31-34` (remove default)
- Modify: `engine/navigation/nav_graph_builder.gd:37-57` (store floor positions on builder)
- Modify: `engine/navigation/nav_graph_builder.gd:107-112` (read from builder)
- Check: all callers of `get_astar()` pass explicit species_id

- [ ] **Step 1: Find callers of `get_astar()` with no species_id**

Run: `grep -rn "get_astar()" engine/ nodes/ tests/ --include="*.gd"`
Record the file:line for any caller relying on the default.

- [ ] **Step 2: Update callers to pass explicit species_id**

For each caller found in Step 1, modify the call to pass the species ID it is actually working with (e.g. from the entity's species component). If the call site is genuinely ambiguous, pass the species_id of the entity whose path is being queried.

- [ ] **Step 3: Remove the default from the signature**

In `engine/navigation/nav_graph_builder.gd`, change line 31–33:

```gdscript
func get_astar(species_id: StringName) -> AStar2D:
	return _astars.get(species_id, AStar2D.new())
```

- [ ] **Step 4: Store floor-node positions on the builder**

In `engine/navigation/nav_graph_builder.gd`, add a new field near `_floor_nodes`:

```gdscript
var _floor_node_positions: Dictionary = {}  # rack_index -> Vector2
```

Modify `_build_floor_nodes()` (lines 37–56) to record positions as it builds:

```gdscript
func _build_floor_nodes() -> void:
	for rack: int in Constants.RACK_COUNT:
		var nav_id: int = _next_nav_id
		_next_nav_id += 1
		var x: float = float(Constants.rack_slot_to_pu(0, rack, 0).x)
		var y: float = float(
			Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 2
		)
		var pos := Vector2(x, y)
		_floor_nodes[rack] = nav_id
		_floor_node_positions[rack] = pos
		for species_id: StringName in _astars:
			var astar: AStar2D = _astars[species_id]
			astar.add_point(nav_id, pos)
	for rack: int in range(Constants.RACK_COUNT - 1):
		var from_id: int = _floor_nodes[rack]
		var to_id: int = _floor_nodes[rack + 1]
		for species_id: StringName in _astars:
			var astar: AStar2D = _astars[species_id]
			astar.connect_points(from_id, to_id)
```

- [ ] **Step 5: Rewrite `get_nearest_floor_node` to use builder-owned map**

In `engine/navigation/nav_graph_builder.gd`, replace lines 107–112:

```gdscript
func get_nearest_floor_node(rack: int) -> Vector2:
	return _floor_node_positions.get(rack, Vector2.ZERO)
```

- [ ] **Step 6: Run tests**

Run: `script/validate`
Expected: all checks pass.

Run: `/Applications/Godot.app/Contents/MacOS/godot --path . --headless --quit-after 30`
Expected: exits 0. Animals pathfind correctly.

- [ ] **Step 7: Commit**

```bash
git add -u engine/navigation/ nodes/ engine/
git commit -m "refactor(nav): remove species default from nav graph builder

get_astar() now requires explicit species_id. Floor-node positions
moved onto the builder; get_nearest_floor_node no longer reaches into
the cat astar for species-agnostic data.

Part of component-mindset-refactor §1.3."
```

---

### Task 6: Add `tends_servers` capability and fix presence query

**Spec reference:** §1.7. `CatPresenceSystem._any_cat_nearby` queries `get_entities_with(&"species")` — returning every animal — and treats every returned entity as a "cat." Functionally wrong (ferrets falsely register). Add narrow `tends_servers: true` to cat recipe; change query to `get_entities_with(&"tends_servers")`; make the spawn path emit the component for any species with `tends_servers: true`.

**Files:**
- Modify: `mods/tcp_cats/species/cat.jsonc` (add `tends_servers: true` field)
- Modify: `engine/mod/entity_def_registry.gd:76-173` (set tag component on spawn if recipe declares it)
- Modify: `engine/growth/cat_presence_system.gd:35-45` (query `tends_servers` instead of `species`)
- Modify: `tests/unit/test_cat_presence_system.gd` (tests must set up `tends_servers` on test animals; body changes require Stage 1 re-stamp per llm-test-verification)

- [ ] **Step 1: Add `tends_servers` to cat recipe**

In `mods/tcp_cats/species/cat.jsonc`, insert before the closing `}`:

```jsonc
  "tends_servers": true,
```

(Place it near the top of the object, e.g. after `"name": "Cat",` for readability.)

- [ ] **Step 2: Spawn path: set capability component if recipe declares it**

In `engine/mod/entity_def_registry.gd`, inside `spawn()` (after the physical-properties block near line 158), append:

```gdscript
	# Capability tags: any recipe-level boolean field we want to project
	# onto the entity as a zero-data component.
	if def.get("tends_servers", false):
		db.set_component(id, &"tends_servers", {})
```

- [ ] **Step 3: Update the presence query**

In `engine/growth/cat_presence_system.gd`, replace lines 35–45:

```gdscript
func _any_cat_nearby(server_pos: Dictionary, max_dist_pu: int) -> bool:
	var tenders: Array[int] = _db.get_entities_with(&"tends_servers")
	for tender_id: int in tenders:
		if not _db.has_component(tender_id, &"position"):
			continue
		var tpos: Dictionary = _db.get_component(tender_id, &"position")
		var dx: int = absi(tpos[&"x"] - server_pos[&"x"])
		var dy: int = absi(tpos[&"y"] - server_pos[&"y"])
		if dx <= max_dist_pu and dy <= max_dist_pu:
			return true
	return false
```

> The rename to `ReclamationSystem` / `tended_seconds` / `_any_tender_nearby` happens in Stage 2 (Task 15). Stage 1 only fixes the query scope.

- [ ] **Step 4: Update the test to set up `tends_servers` on test cats**

Read `tests/unit/test_cat_presence_system.gd` first to see the test cat setup. For each helper that creates a test cat, ensure `tends_servers` component is set:

```gdscript
func _make_cat(pos: Dictionary) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {&"id": &"tcp_cats:cat"})
	_db.set_component(id, &"position", pos)
	_db.set_component(id, &"tends_servers", {})
	return id
```

Add one new test proving the fix:

```gdscript
func test_ferret_without_tends_servers_does_not_trigger_presence():
	var server_id: int = _db.create_entity()
	_db.set_component(server_id, &"position", {&"x": 0, &"y": 0})
	_db.set_component(server_id, &"cat_presence", {&"seconds": 0})
	var ferret_id: int = _db.create_entity()
	_db.set_component(ferret_id, &"species", {&"id": &"tcp_ferrets:ferret"})
	_db.set_component(ferret_id, &"position", {&"x": 0, &"y": 0})
	# Intentionally no tends_servers component
	var sys := CatPresenceSystem.new(_db)
	sys.tick()
	assert_eq(_db.get_field(server_id, &"cat_presence", &"seconds"), 0,
		"Ferret should not increment cat presence because it does not tend servers")
```

- [ ] **Step 5: Run tests red-green**

Run: `script/checks/gut_tests -f tests/unit/test_cat_presence_system.gd`
Expected: tests pass (including the new one).

- [ ] **Step 6: Mutate to verify the new test catches regressions**

Comment out the `if _db.get_entities_with(&"tends_servers")` change in `cat_presence_system.gd` and restore the prior `&"species"` query.

Run: `script/checks/gut_tests -f tests/unit/test_cat_presence_system.gd -F test_ferret_without_tends_servers_does_not_trigger_presence`
Expected: fail — the ferret now registers as presence.

Restore the `tends_servers` query.

Run: `script/checks/gut_tests -f tests/unit/test_cat_presence_system.gd`
Expected: all pass.

- [ ] **Step 7: Re-stamp the test (file body changed)**

Run: `script/stamp_tests tests/unit/test_cat_presence_system.gd`
Run: `script/checks/verify_tests`
Expected: exits 0.

- [ ] **Step 8: Commit**

```bash
git add mods/tcp_cats/species/cat.jsonc engine/mod/entity_def_registry.gd engine/growth/cat_presence_system.gd tests/unit/test_cat_presence_system.gd tests/unit/test_cat_presence_system.gd.stamp
git commit -m "fix(growth): plant presence counts only entities with tends_servers

CatPresenceSystem was over-scoped: get_entities_with(&\"species\") returned
every animal. Adding tends_servers: true to cat recipe + spawn path
projection makes the query capability-gated.

Rename to ReclamationSystem lands in Stage 2 per
component-mindset-refactor §1.7 + §2.1."
```

---

### Task 7: Move sprite config onto species recipes (§1.1)

**Spec reference:** §1.1. `nodes/animal_node.gd` (lines 11–23, 53, 63, 71, 90) dispatches on species string to pick sprite paths, Y-offset, and animation strips. Move into recipe as `sprite_config` component. Two maps: `animations` (state → animation key) and `animation_frames` (animation key → strip file + frame count + fps).

**Files:**
- Modify: `mods/tcp_cats/species/cat.jsonc` (add `sprite_config`)
- Modify: `mods/tcp_ferrets/species/ferret.jsonc` (add `sprite_config`)
- Modify: `nodes/animal_node.gd` (read from recipe instead of branching on species)
- Modify: `engine/mod/species_schema_validator.gd` (add `sprite_config` to required fields)
- Modify: `engine/mod/mod_loader.gd` OR where validator is constructed (call `validator.add_required_field("sprite_config")`)

- [ ] **Step 1: Add `sprite_config` to cat recipe**

In `mods/tcp_cats/species/cat.jsonc`, insert (near `variants`):

```jsonc
  "sprite_config": {
    "base_path": "res://mods/tcp_cats/sprites/{variant}",
    "offset_y": -12,
    "animations": {
      "IDLE":       { "animation": "idle" },
      "SEEKING":    { "animation": "walk" },
      "MOVING_TO":  { "animation": "walk" },
      "WANDERING":  { "animation": "walk" },
      "LOAFING":    { "animation": "sit" },
      "SETTLING":   { "animation": "sit" },
      "GROOMING":   { "animation": "crouch" },
      "SLEEPING":   { "animation": "sleep" },
      "STARTLED":   { "animation": "fright" }
    },
    "animation_frames": {
      "idle":   { "sprite": "_idle_strip8.png",   "frames": 8, "fps": 6.0 },
      "walk":   { "sprite": "_walk_strip8.png",   "frames": 8, "fps": 8.0 },
      "sit":    { "sprite": "_sit_strip8.png",    "frames": 8, "fps": 4.0 },
      "sleep":  { "sprite": "_sleep_strip8.png",  "frames": 8, "fps": 2.0 },
      "crouch": { "sprite": "_crouch_strip8.png", "frames": 8, "fps": 6.0 },
      "fright": { "sprite": "_fright_strip8.png", "frames": 8, "fps": 8.0 }
    }
  },
```

- [ ] **Step 2: Add `sprite_config` to ferret recipe**

In `mods/tcp_ferrets/species/ferret.jsonc`, insert (near `variants`):

```jsonc
  "sprite_config": {
    "base_path": "res://mods/tcp_ferrets/sprites/{variant}",
    "offset_y": -8,
    "animations": {
      "IDLE":       { "animation": "idle" },
      "SEEKING":    { "animation": "walk" },
      "MOVING_TO":  { "animation": "walk" },
      "WANDERING":  { "animation": "walk" },
      "LOAFING":    { "animation": "sit" },
      "SETTLING":   { "animation": "sit" },
      "SLEEPING":   { "animation": "sleep" },
      "SNIFFING":   { "animation": "sneak" },
      "SPEED_BUMP": { "animation": "liedown" }
    },
    "animation_frames": {
      "idle":    { "sprite": "_idle_strip8.png",    "frames": 8, "fps": 6.0 },
      "walk":    { "sprite": "_walk_strip8.png",    "frames": 8, "fps": 8.0 },
      "sit":     { "sprite": "_sit_strip8.png",     "frames": 8, "fps": 4.0 },
      "sleep":   { "sprite": "_sleep_strip4.png",   "frames": 4, "fps": 2.0 },
      "sneak":   { "sprite": "_sneak_strip4.png",   "frames": 4, "fps": 6.0 },
      "liedown": { "sprite": "_liedown_strip8.png", "frames": 8, "fps": 4.0 }
    }
  },
```

- [ ] **Step 3: Project `sprite_config` onto the entity at spawn**

In `engine/mod/entity_def_registry.gd`, inside `spawn()` alongside other component projections (near the physical-properties block), append:

```gdscript
	if def.has("sprite_config"):
		db.set_component(id, &"sprite_config", def["sprite_config"])
```

- [ ] **Step 4: Rewrite `animal_node.gd` to read from `sprite_config`**

In `nodes/animal_node.gd`, delete lines 11–23 (`_STATE_TO_ANIM` constant) and line 32 (`_is_ferret`).

Replace `_setup_sprite()` (lines 60–101) with:

```gdscript
func _setup_sprite() -> void:
	var species: Dictionary = _db.get_component(entity_id, &"species")
	var config: Dictionary = _db.get_component(entity_id, &"sprite_config")
	var variant: String = String(species.get(&"variant", &""))
	var base_path: String = String(config.get("base_path", "")).replace("{variant}", variant)
	_sprite.scale = Vector2(1.0, 1.0)
	_sprite.offset.y = float(config.get("offset_y", 0))

	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")

	var animation_frames: Dictionary = config.get("animation_frames", {})
	for anim_key: String in animation_frames:
		var entry: Dictionary = animation_frames[anim_key]
		var path: String = base_path + String(entry.get("sprite", ""))
		var frame_count: int = int(entry.get("frames", 1))
		var fps: float = float(entry.get("fps", 6.0))
		_load_strip(frames, StringName(anim_key), path, frame_count, fps)

	_sprite.sprite_frames = frames
	_sprite.play(&"idle")
```

Update `initialize()` (lines 42–57) — remove the `_is_ferret` logic and the `_setup_footstep_audio()` species-gated call. Replace with:

```gdscript
func initialize(db: GameStateDB, eid: int) -> void:
	_db = db
	entity_id = eid
	var pos: Dictionary = _db.get_component(entity_id, &"position")
	_target_pos = Vector2(
		Constants.to_world(pos[&"x"]),
		float(Constants.FLOOR_Y - 1)
	)
	_prev_pos = _target_pos
	global_position = _target_pos
	_setup_sprite()
	_setup_name_label(_db.get_component(entity_id, &"species"))
	_setup_footstep_audio()
```

(The footstep audio is currently ferret-only. For Stage 1 we make it universal; if that turns out wrong, move the footstep sound into `sounds.footsteps` in the recipe as a follow-up. Decision: acceptable for Stage 1 — cats gaining footstep sound is not a regression.)

Replace `_state_to_animation()` (lines 213–214) with recipe-driven lookup:

```gdscript
func _state_to_animation(state: StringName) -> StringName:
	var config: Dictionary = _db.get_component(entity_id, &"sprite_config")
	var animations: Dictionary = config.get("animations", {})
	var entry: Dictionary = animations.get(String(state), {})
	return StringName(entry.get("animation", "idle"))
```

- [ ] **Step 5: Add `sprite_config` as a required validator field**

In `engine/mod/mod_loader.gd`, where the validator is instantiated (top of the class or inside `load_all`), call:

```gdscript
validator.add_required_field("sprite_config")
```

(Put this in `load_all` before `_load_mod_content` is called.)

- [ ] **Step 6: Run tests and boot the game**

Run: `script/validate`
Expected: all tests green.

Run: `/Applications/Godot.app/Contents/MacOS/godot --path . --headless --quit-after 60`
Expected: exits 0, animals render correctly.

- [ ] **Step 7: Commit**

```bash
git add mods/tcp_cats/species/cat.jsonc mods/tcp_ferrets/species/ferret.jsonc engine/mod/entity_def_registry.gd nodes/animal_node.gd engine/mod/mod_loader.gd
git commit -m "refactor(animal-node): drive sprite + animation config from recipe

Species recipes now carry sprite_config: base_path with {variant}
substitution, offset_y, state→animation map, and animation key→strip
file/frames/fps map. animal_node reads entirely from the recipe;
is_cat / is_ferret dispatches deleted.

Added sprite_config to schema validator's required fields.

Part of component-mindset-refactor §1.1."
```

---

### Task 8: Move ambient-state weight pools onto recipes (§1.2)

**Spec reference:** §1.2. `_pick_ambient_state` in `nodes/game_server.gd:443–474` gates on `has_cat_states` (derived from whether the `grooming` state exists) and branches between two hardcoded weight tables. Move the tables into recipes.

**Files:**
- Modify: `mods/tcp_cats/species/cat.jsonc` (add `ambient_states`)
- Modify: `mods/tcp_ferrets/species/ferret.jsonc` (add `ambient_states`)
- Modify: `nodes/game_server.gd:420-475` (generic weighted pick)
- Modify: `engine/mod/species_schema_validator.gd` — add `ambient_states` as required

- [ ] **Step 1: Add `ambient_states` to cat recipe**

In `mods/tcp_cats/species/cat.jsonc`, insert:

```jsonc
  "ambient_states": {
    "warm": [
      { "state": "IDLE",     "weight": 10 },
      { "state": "GROOMING", "weight": 15 },
      { "state": "LOAFING",  "weight": 20 },
      { "state": "SLEEPING", "weight": 25 }
    ],
    "cold": [
      { "state": "IDLE",     "weight": 10 },
      { "state": "GROOMING", "weight": 5 },
      { "state": "LOAFING",  "weight": 10 }
    ]
  },
```

- [ ] **Step 2: Add `ambient_states` to ferret recipe**

In `mods/tcp_ferrets/species/ferret.jsonc`, insert:

```jsonc
  "ambient_states": {
    "warm": [
      { "state": "IDLE",       "weight": 10 },
      { "state": "SNIFFING",   "weight": 20 },
      { "state": "SPEED_BUMP", "weight": 10 },
      { "state": "SLEEPING",   "weight": 15 }
    ],
    "cold": [
      { "state": "IDLE",       "weight": 10 },
      { "state": "SNIFFING",   "weight": 20 },
      { "state": "SPEED_BUMP", "weight": 10 }
    ]
  },
```

- [ ] **Step 3: Project onto entity at spawn**

In `engine/mod/entity_def_registry.gd`, append to `spawn()`:

```gdscript
	if def.has("ambient_states"):
		db.set_component(id, &"ambient_states", def["ambient_states"])
```

- [ ] **Step 4: Rewrite the ambient picker in game_server.gd**

In `nodes/game_server.gd`, replace lines 420–475 (the `has_cat_states` branch and `_pick_ambient_state`):

Inside the caller (around line 420–440), replace with:

```gdscript
			var desires: Dictionary = db.get_component(entity_id, &"desires")
			var is_warm: bool = desires[&"warmth"] < 400
			if not db.has_component(entity_id, &"ambient_states"):
				return  # Entity has no ambient states configured — skip
			var pools: Dictionary = db.get_component(entity_id, &"ambient_states")
			var pool: Array = pools.get("warm" if is_warm else "cold", [])
			var new_state: StringName = _pick_ambient_state(pool)
			if new_state != current_state:
				db.set_component(entity_id, &"ai_state", {
					&"state": new_state,
					&"meta_state": &"AMBIENT",
					&"commitment_score": ai[&"commitment_score"],
				})
				_state_timers[entity_id] = 0.0
				_min_durations_override.erase(entity_id)
```

Replace `_pick_ambient_state`:

```gdscript
func _pick_ambient_state(pool: Array) -> StringName:
	if pool.is_empty():
		return &"IDLE"
	var total_weight: int = 0
	for entry: Dictionary in pool:
		total_weight += int(entry.get("weight", 0))
	if total_weight <= 0:
		return &"IDLE"
	var roll: int = randi_range(0, total_weight - 1)
	var cumulative: int = 0
	for entry: Dictionary in pool:
		cumulative += int(entry.get("weight", 0))
		if roll < cumulative:
			return StringName(entry.get("state", "IDLE"))
	return &"IDLE"
```

- [ ] **Step 5: Add `ambient_states` as required field in validator**

In `engine/mod/mod_loader.gd` (wherever `add_required_field` is being called — from Task 7), add:

```gdscript
validator.add_required_field("ambient_states")
```

- [ ] **Step 6: Run tests and boot the game**

Run: `script/validate`

Run: `/Applications/Godot.app/Contents/MacOS/godot --path . --headless --quit-after 60`
Expected: exits 0. Cats still groom/loaf/sleep; ferrets still sniff/speed-bump.

- [ ] **Step 7: Commit**

```bash
git add mods/tcp_cats/species/cat.jsonc mods/tcp_ferrets/species/ferret.jsonc nodes/game_server.gd engine/mod/entity_def_registry.gd engine/mod/mod_loader.gd
git commit -m "refactor(server): ambient-state pools driven by species recipe

_pick_ambient_state was two hardcoded weight tables gated on whether
the species declared a 'grooming' state. Replaced with recipe-provided
pools under ambient_states.warm / ambient_states.cold. Picker is a
generic weighted roll over whichever array the recipe supplies.

Added ambient_states to schema validator's required fields.

Part of component-mindset-refactor §1.2."
```

---

### Task 9: Move HUD name color onto recipes (§1.4)

**Spec reference:** §1.4. `nodes/animal_stats_bar.gd:59–63` picks name color by `contains("cat")`. Move to recipe as `hud_color: [r, g, b]`.

**Files:**
- Modify: `mods/tcp_cats/species/cat.jsonc`
- Modify: `mods/tcp_ferrets/species/ferret.jsonc`
- Modify: `engine/mod/entity_def_registry.gd` (project onto entity)
- Modify: `nodes/animal_stats_bar.gd:59-63`
- Modify: `engine/mod/mod_loader.gd` (add `hud_color` to validator)

- [ ] **Step 1: Add `hud_color` to cat recipe**

Insert into `mods/tcp_cats/species/cat.jsonc`:

```jsonc
  "hud_color": [0.9, 0.8, 0.6],
```

- [ ] **Step 2: Add `hud_color` to ferret recipe**

Insert into `mods/tcp_ferrets/species/ferret.jsonc`:

```jsonc
  "hud_color": [0.6, 0.9, 0.7],
```

- [ ] **Step 3: Project onto entity at spawn**

In `engine/mod/entity_def_registry.gd`, append to `spawn()`:

```gdscript
	if def.has("hud_color"):
		var c: Array = def["hud_color"]
		db.set_component(id, &"hud_color", {
			&"r": float(c[0]), &"g": float(c[1]), &"b": float(c[2]),
		})
```

- [ ] **Step 4: Read from component in stats bar**

In `nodes/animal_stats_bar.gd`, replace lines 59–63:

```gdscript
	var name_color := Color(0.9, 0.8, 0.6)
	if _db.has_component(entity_id, &"hud_color"):
		var c: Dictionary = _db.get_component(entity_id, &"hud_color")
		name_color = Color(c[&"r"], c[&"g"], c[&"b"])
	name_label.add_theme_color_override("font_color", name_color)
```

- [ ] **Step 5: Add `hud_color` as required validator field**

In `engine/mod/mod_loader.gd`:

```gdscript
validator.add_required_field("hud_color")
```

- [ ] **Step 6: Run tests and boot the game**

Run: `script/validate`
Expected: green.

- [ ] **Step 7: Commit**

```bash
git add mods/tcp_cats/species/cat.jsonc mods/tcp_ferrets/species/ferret.jsonc engine/mod/entity_def_registry.gd nodes/animal_stats_bar.gd engine/mod/mod_loader.gd
git commit -m "refactor(hud): name color driven by species recipe hud_color

animal_stats_bar no longer dispatches on species string. Recipe
declares an [r, g, b] triplet; missing triplet fails validation.

Added hud_color to schema validator's required fields.

Part of component-mindset-refactor §1.4."
```

---

### Task 10: Move starter-spawn lists into recipes (§1.9)

**Spec reference:** §1.9. `nodes/game_server.gd:640-702` hardcodes species IDs + inline name arrays. A third species mod cannot spawn starter entities without engine changes. Move into each recipe as optional `starters` array.

**Files:**
- Modify: `mods/tcp_cats/species/cat.jsonc` (add `starters`)
- Modify: `mods/tcp_ferrets/species/ferret.jsonc` (add `starters`)
- Modify: `nodes/game_server.gd:640-710` (iterate all loaded species)

- [ ] **Step 1: Add `starters` to cat recipe**

Insert into `mods/tcp_cats/species/cat.jsonc`:

```jsonc
  "starters": [
    { "name": "Mochi",   "rack": 1, "desires": { "hunger": 900, "attention": 600 } },
    { "name": "Biscuit", "rack": 2, "desires": { "hunger": 900, "attention": 600 } },
    { "name": "Noodle",  "rack": 3, "desires": { "hunger": 900, "attention": 600 } }
  ],
```

- [ ] **Step 2: Add `starters` to ferret recipe**

Insert into `mods/tcp_ferrets/species/ferret.jsonc`:

```jsonc
  "starters": [
    { "name": "Slinky", "rack": 1 },
    { "name": "Bandit", "rack": 2 }
  ],
```

- [ ] **Step 3: Replace hardcoded spawn block with generic loop**

In `nodes/game_server.gd`, replace lines 640–710 (the cat-spawn + ferret-spawn blocks) with a generic iteration:

```gdscript
	# Starter-entity spawn — driven by each loaded species recipe's `starters` array.
	var floor_y: int = FLOOR_Y_PU + Constants.FLOOR_HEIGHT_PU / 2
	for species_id: StringName in _entity_defs.get_all_entities():
		var def: Dictionary = _entity_defs.get_definition(species_id)
		if not def.has("starters"):
			continue
		var starters: Array = def["starters"]
		for entry: Dictionary in starters:
			var rack: int = int(entry.get("rack", 0))
			var overrides: Dictionary = {
				&"name": StringName(entry.get("name", "")),
				&"position": {
					&"x": Constants.rack_slot_to_pu(0, rack, 0).x,
					&"y": floor_y,
				},
			}
			if entry.has("desires"):
				var d: Dictionary = entry["desires"]
				var typed: Dictionary = {}
				for k: String in d:
					typed[StringName(k)] = int(d[k])
				overrides[&"desires"] = typed
			_entity_defs.spawn(species_id, db, overrides)

	_init_curiosity_trackers()
	_spawn_rack_entities()
```

Remove all references to hardcoded `&"tcp_cats:cat"` and `&"tcp_ferrets:ferret"` in this function.

- [ ] **Step 4: Run tests and boot the game — verify starter lineup**

Run: `/Applications/Godot.app/Contents/MacOS/godot --path . --headless --quit-after 30`
Expected: same 3 cats (Mochi/Biscuit/Noodle) + 2 ferrets (Slinky/Bandit) spawn.

Run: `script/validate`
Expected: green.

- [ ] **Step 5: Commit**

```bash
git add mods/tcp_cats/species/cat.jsonc mods/tcp_ferrets/species/ferret.jsonc nodes/game_server.gd
git commit -m "refactor(server): starter-spawn list driven by recipe.starters

Engine no longer references tcp_cats:cat or tcp_ferrets:ferret in the
starter-spawn path. Each species recipe declares its own starters
array with name + rack + optional desire overrides. Third-species mods
can now seed starter entities with zero engine changes.

Part of component-mindset-refactor §1.9."
```

---

### Task 11: Stage 1 integration test — synthetic third species

**Spec reference:** §1.11 Stage 1 success criteria. The mechanical verification of the anchor claim: a minimal synthetic species recipe loads, spawns, animates, and pathfinds without engine changes.

**Files:**
- Create: `tests/fixtures/tcp_test_species/mod.json`
- Create: `tests/fixtures/tcp_test_species/species/test_creature.jsonc`
- Create: `tests/integration/test_third_species_spawns.gd`

- [ ] **Step 1: Create the fixture mod manifest**

Create `tests/fixtures/tcp_test_species/mod.json`:

```json
{
  "title": "Test Creature",
  "version": "0.0.1",
  "author": "tcp-test",
  "description": "Fixture mod used by integration tests"
}
```

- [ ] **Step 2: Create the fixture species recipe**

Create `tests/fixtures/tcp_test_species/species/test_creature.jsonc`:

```jsonc
{
  "schema_version": 1,
  "id": "tcp_test_species:test_creature",
  "name": "TestCreature",
  "desires": { "warmth": 500, "comfort": 500 },
  "traversal": ["WALK"],
  "variants": ["cat01"],
  "hud_color": [0.5, 0.5, 0.5],
  "sprite_config": {
    "base_path": "res://mods/tcp_cats/sprites/{variant}",
    "offset_y": -12,
    "animations": {
      "IDLE":    { "animation": "idle" },
      "SEEKING": { "animation": "walk" }
    },
    "animation_frames": {
      "idle": { "sprite": "_idle_strip8.png", "frames": 8, "fps": 6.0 },
      "walk": { "sprite": "_walk_strip8.png", "frames": 8, "fps": 8.0 }
    }
  },
  "ambient_states": {
    "warm": [ { "state": "IDLE", "weight": 10 } ],
    "cold": [ { "state": "IDLE", "weight": 10 } ]
  },
  "states": { "idle": { "advertisements": [] } },
  "initial_state": "idle"
}
```

> Sprite borrows cat01 art so the test doesn't need its own PNGs. This is the point — the recipe composes existing assets.

- [ ] **Step 3: Write the integration test**

Create `tests/integration/test_third_species_spawns.gd`:

```gdscript
extends GutTest


func test_synthetic_species_loads_and_spawns_animated_animal():
	# Load all mods including tests/fixtures/tcp_test_species
	var loader := ModLoader.new()
	var result: Dictionary = loader.load_all("res://mods")
	var fixture_result: Dictionary = loader.load_all(
		"res://tests/fixtures"
	)
	var entity_defs: EntityDefRegistry = fixture_result["entity_defs"]

	assert_true(
		entity_defs.has_entity(&"tcp_test_species:test_creature"),
		"Fixture recipe must load without engine changes"
	)

	var db := GameStateDB.new()
	var entity_id: int = entity_defs.spawn(
		&"tcp_test_species:test_creature", db,
		{ &"position": { &"x": 0, &"y": 0 } }
	)

	# Assert core components projected from recipe
	assert_true(db.has_component(entity_id, &"species"))
	assert_true(db.has_component(entity_id, &"desires"))
	assert_true(db.has_component(entity_id, &"sprite_config"))
	assert_true(db.has_component(entity_id, &"ambient_states"))
	assert_true(db.has_component(entity_id, &"hud_color"))
	assert_true(db.has_component(entity_id, &"ai_state"))

	# Sprite config round-trips
	var config: Dictionary = db.get_component(entity_id, &"sprite_config")
	assert_true(config.has("animations"))
	assert_true(config["animations"].has("IDLE"))


func test_synthetic_species_is_rejected_when_missing_desires():
	# Compose a recipe missing `desires` and feed it directly to validator
	var validator := SpeciesSchemaValidator.new()
	validator.add_required_field("sprite_config")
	validator.add_required_field("ambient_states")
	validator.add_required_field("hud_color")
	var bad_def: Dictionary = {
		"id": "bad:creature",
		"traversal": ["WALK"],
		"hud_color": [0.5, 0.5, 0.5],
		"sprite_config": {},
		"ambient_states": {},
	}
	assert_false(validator.is_valid_species(bad_def))
	assert_push_error("missing required field: desires")
```

- [ ] **Step 4: Run the test**

Run: `script/checks/gut_tests -f tests/integration/test_third_species_spawns.gd`
Expected: both tests pass.

- [ ] **Step 5: Mutate to verify the test catches regressions**

In `engine/mod/entity_def_registry.gd`, comment out the `db.set_component(id, &"sprite_config", def["sprite_config"])` line (added in Task 7).

Run: `script/checks/gut_tests -f tests/integration/test_third_species_spawns.gd -F test_synthetic_species_loads_and_spawns_animated_animal`
Expected: failure — sprite_config not on entity.

Restore the line.

Run: `script/checks/gut_tests -f tests/integration/test_third_species_spawns.gd`
Expected: all pass.

- [ ] **Step 6: Stamp the test**

Run: `script/stamp_tests tests/integration/test_third_species_spawns.gd`
Run: `script/checks/verify_tests`
Expected: exits 0.

- [ ] **Step 7: Commit**

```bash
git add tests/fixtures/ tests/integration/test_third_species_spawns.gd tests/integration/test_third_species_spawns.gd.stamp
git commit -m "test: integration test for third-species recipe load + spawn

Fixture mod at tests/fixtures/tcp_test_species proves the component
mindset anchor: a synthetic species recipe loads, projects components,
and passes schema validation with zero engine changes. Validates
Stage 1 success criteria per component-mindset-refactor spec."
```

---

# Stage 2 — Capability-naming renames

**IMPORTANT:** Per spec §Stage 2 success criteria, **land Stage 2 on a single branch** with all re-verifications complete before merging. Per-rename commits on `main` would break `verify_tests` CI for other branches mid-stream. Create a dedicated branch for Stage 2.

**Branch setup:**

- [ ] Create the Stage 2 branch: `git checkout -b refactor/stage-2-renames` from the post-Stage-1 `main`

---

### Task 12: Rename `cat_presence` component → `reclamation`

**Spec reference:** §2.1. Rename the component name and its consumers.

**Files:**
- Modify (search-replace): every file referencing `&"cat_presence"` or `cat_presence` identifier.
  - Known sites: `engine/growth/cat_presence_system.gd`, `engine/growth/plant_growth_system.gd`, `nodes/game_server.gd`, `tests/unit/test_cat_presence_system.gd`, `tests/unit/test_plant_growth_system.gd`, `tests/integration/test_plant_comfort_advertisement.gd`

- [ ] **Step 1: Find every site**

Run: `grep -rn "cat_presence" engine/ nodes/ tests/ --include="*.gd"`
Record all files.

- [ ] **Step 2: Rename the component StringName everywhere**

For every site, replace `&"cat_presence"` with `&"reclamation"` and any `cat_presence` variable identifiers with `reclamation`.

Do not yet rename the class file or class itself — that's Task 13.

- [ ] **Step 3: Rename the field `cat_seconds` → `tended_seconds`**

Run: `grep -rn "cat_seconds" engine/ nodes/ tests/ --include="*.gd"`

For every site, replace `&"cat_seconds"` with `&"tended_seconds"` and any `cat_seconds` identifiers.

- [ ] **Step 4: Run tests**

Run: `script/validate`
Expected: tests may fail on the verify_tests stamp check (stamps are stale). That is expected — re-stamping is Task 19.

Run: `script/checks/gut_tests` (skip the stamp-check failure; focus on the test results)
Expected: behavior-level tests pass.

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "refactor: rename cat_presence component → reclamation, cat_seconds → tended_seconds

Component tracked 'tended time' — name now reflects mechanic rather
than species. Class/file/function rename in next commit.

Part of component-mindset-refactor §2.1."
```

---

### Task 13: Rename `CatPresenceSystem` class/file/function → `ReclamationSystem`

- [ ] **Step 1: Rename the file**

```bash
git mv engine/growth/cat_presence_system.gd engine/growth/reclamation_system.gd
git mv engine/growth/cat_presence_system.gd.uid engine/growth/reclamation_system.gd.uid
```

- [ ] **Step 2: Update the class declaration**

In `engine/growth/reclamation_system.gd`, change line 1:

```gdscript
class_name ReclamationSystem extends RefCounted
```

- [ ] **Step 3: Rename `_any_cat_nearby` → `_any_tender_nearby`**

Inside the file, rename the function and its caller. After the rename `tick()` should call `_any_tender_nearby(...)` not `_any_cat_nearby(...)`.

- [ ] **Step 4: Find and update all instantiations**

Run: `grep -rn "CatPresenceSystem\|cat_presence_system" nodes/ engine/ tests/ --include="*.gd"`

For each match, replace `CatPresenceSystem` with `ReclamationSystem` and any `cat_presence_system` identifier variable with `reclamation_system`.

- [ ] **Step 5: Rename the test file**

```bash
git mv tests/unit/test_cat_presence_system.gd tests/unit/test_reclamation_system.gd
git mv tests/unit/test_cat_presence_system.gd.uid tests/unit/test_reclamation_system.gd.uid
git rm tests/unit/test_cat_presence_system.gd.stamp  # stale stamp, will be re-stamped later
```

In the new file, update class references:
- `CatPresenceSystem.new` → `ReclamationSystem.new`
- Any test names referencing `cat_presence` — rename to `reclamation` (e.g., `test_cat_presence_increments` → `test_reclamation_increments`)

- [ ] **Step 6: Run tests**

Run: `script/checks/gut_tests -f tests/unit/test_reclamation_system.gd`
Expected: tests pass on behavior. Stamp mismatch at verify_tests is expected.

- [ ] **Step 7: Commit**

```bash
git add -u engine/growth/ tests/unit/ nodes/
git commit -m "refactor: CatPresenceSystem → ReclamationSystem

Class, file, and _any_cat_nearby → _any_tender_nearby rename.
Instantiations updated in game_server. Test file renamed.

Part of component-mindset-refactor §2.1."
```

---

### Task 14: Rename `is_purring` → `is_satisfied` in contentment system

**Spec reference:** §2.2. The signal is species-agnostic; the audio is species-specific. Rename the gameplay flag; keep the purr sound as a cat-sounds concern.

**Files:**
- Modify: `engine/core/contentment.gd` (field name, internal counter, getter)
- Modify: `engine/core/hum_system.gd:6, 63, 74-77` (charge constant + loop variables)
- Modify: every test referencing `is_purring` / `purring_count`

- [ ] **Step 1: Rename in `engine/core/contentment.gd`**

Replace every `is_purring` with `is_satisfied` and every `_purring_count` with `_satisfied_count`. Rename `get_purring_count()` → `get_satisfied_count()`.

- [ ] **Step 2: Rename in `engine/core/hum_system.gd`**

- `CHARGE_PER_PURRING_CAT` → `CHARGE_PER_SATISFIED_ENTITY`
- `purring_near_receiver` → `satisfied_near_receiver`
- The internal read: `_db.get_field(entity_id, &"contentment", &"is_purring")` → `_db.get_field(entity_id, &"contentment", &"is_satisfied")`

- [ ] **Step 3: Find other callers**

Run: `grep -rn "is_purring\|_purring_count\|get_purring_count\|CHARGE_PER_PURRING_CAT\|purring_near_receiver" engine/ nodes/ tests/ --include="*.gd"`

Replace each match per the table.

- [ ] **Step 4: Update the visual purr indicator in animal_node.gd**

Per spec §2.2, the audio/visual expression of purring stays species-specific. In `nodes/animal_node.gd`, the local variable `is_purring` (around line 206) can stay named `is_purring` — it describes the visual indicator, not the underlying gameplay flag. Leave it.

- [ ] **Step 5: Run tests**

Run: `script/checks/gut_tests`
Expected: behavior tests pass. Stamp-check failures are expected.

- [ ] **Step 6: Commit**

```bash
git add -u engine/core/ tests/
git commit -m "refactor(contentment): is_purring → is_satisfied

Gameplay signal is species-neutral — any contented entity with 3-of-4
bars raises HUM reserve. Audio expression (purr sound) stays cat-specific
through the sounds component.

Part of component-mindset-refactor §2.2."
```

---

### Task 15: Rename narrator events + event-bus signals

**Spec reference:** §2.3 and §2.4.

**Files:**
- Modify: `engine/core/narrator.gd` (match arms)
- Modify: `nodes/events.gd:22,25` (signal declarations)
- Modify: every emitter / listener of the renamed signals

- [ ] **Step 1: Narrator events**

In `engine/core/narrator.gd`, replace string match arms:

| Old | New |
|---|---|
| `&"first_cat_settles"` | `&"first_creature_settles"` |
| `&"cat_departed"` | `&"creature_departed"` |
| `&"cat_returned"` | `&"creature_returned"` |

Find callers: `grep -rn "first_cat_settles\|cat_departed\|cat_returned" engine/ nodes/ tests/ --include="*.gd"`. Replace each occurrence.

- [ ] **Step 2: Event-bus signals**

In `nodes/events.gd`:

```gdscript
signal creature_started_pacing(animal_id: int)
# ...
signal creature_petted(animal_id: int)
```

Find callers: `grep -rn "cat_started_pacing\|cat_petted" engine/ nodes/ tests/ --include="*.gd"`. Rename each emitter and listener.

- [ ] **Step 3: Run tests**

Run: `script/checks/gut_tests`
Expected: behavior tests pass.

- [ ] **Step 4: Commit**

```bash
git add -u engine/ nodes/ tests/
git commit -m "refactor(narrator+events): species-neutral signal names

first_cat_settles → first_creature_settles, cat_departed → creature_departed,
cat_returned → creature_returned, cat_started_pacing → creature_started_pacing,
cat_petted → creature_petted.

Event payloads still carry the species label for display text — only
the signal *names* become species-neutral.

Part of component-mindset-refactor §2.3 + §2.4."
```

---

### Task 16: Narrow `contentment` query scope (§2.5)

**File:** `engine/core/contentment.gd:17`

- [ ] **Step 1: Replace species query with desires query**

In `engine/core/contentment.gd`, replace `_db.get_entities_with(&"species")` with `_db.get_entities_with(&"desires")`.

- [ ] **Step 2: Verify no non-animal entity carries a `desires` component**

Run: `grep -rn "set_component.*&\"desires\"" engine/ nodes/ --include="*.gd"`
Confirm every such site attaches desires only to animals. (Entity-def-registry only sets desires from species recipes, which is the expected path.)

- [ ] **Step 3: Run tests**

Run: `script/checks/gut_tests -f tests/unit/test_contentment.gd`

- [ ] **Step 4: Commit**

```bash
git add engine/core/contentment.gd
git commit -m "refactor(contentment): query by desires instead of species

Species-less entities (facility, racks, placed objects) should never
have been in contentment's iteration set. Narrow the query to
entities that actually have desires.

Part of component-mindset-refactor §2.5."
```

---

### Task 17: Update tests that reference renamed identifiers

**Spec reference:** §Stage 2 success criteria + §Cross-cutting re-verification. The Stage 2 renames mean test bodies contain out-of-date identifiers. Each modified test requires full Phase 2–5 re-verification per `.claude/rules/llm-test-verification.md`.

**Expected test files to update:**
- `tests/unit/test_contentment.gd`
- `tests/unit/test_hum_system.gd`
- `tests/integration/test_hum_tick.gd`
- `tests/unit/test_plant_growth_system.gd`
- `tests/unit/test_reclamation_system.gd` (née test_cat_presence_system.gd)
- `tests/integration/test_plant_comfort_advertisement.gd`
- `tests/integration/test_tick_loop.gd`
- `tests/unit/test_robot_narrator_plants.gd` (check — narrator events may have renamed)
- Any other test file surfaced by the grep below

- [ ] **Step 1: Enumerate the affected test files**

Run: `grep -rln "cat_presence\|cat_seconds\|is_purring\|CHARGE_PER_PURRING_CAT\|purring_count\|first_cat_settles\|cat_departed\|cat_returned\|cat_started_pacing\|cat_petted" tests/ --include="*.gd"`

Record the list. This is the re-verification scope.

- [ ] **Step 2: For each affected test file, apply the identifier rename and re-run the Phase 2–5 cycle**

For each file in the list:

1. Apply the same rename mapping Stage 2 applied to engine/nodes code.
2. Run: `script/checks/gut_tests -f tests/path/to/file.gd` — confirm green.
3. Per `.claude/rules/llm-test-verification.md` Step 9–12: for each non-trivial test in the file, mutate the production code it covers, confirm the test fails, restore.

   Because we already mutated Stage 1 and Stage 2 code earlier, a representative spot-check per test file is acceptable: pick one test function per file, mutate the function it exercises, confirm failure, restore.

4. Re-stamp: `script/stamp_tests tests/path/to/file.gd`

- [ ] **Step 3: Verify all stamps**

Run: `script/checks/verify_tests`
Expected: exits 0.

- [ ] **Step 4: Commit**

```bash
git add tests/
git commit -m "test: re-verify + re-stamp after Stage 2 renames

Every test whose body referenced cat_presence, cat_seconds, is_purring,
or the renamed narrator/event signals has been re-run through the full
Phase 2-5 LLM test verification cycle. Stamp sidecars regenerated.

Part of component-mindset-refactor Stage 2 re-verification."
```

---

### Task 18: Stage 2 success-criteria grep verification

- [ ] **Step 1: Purring identifiers gone from logic**

Run: `grep -rn "purring" engine/ nodes/ --include="*.gd"`
Expected: matches only in comments, log strings, or the visual-indicator local variable in `animal_node.gd`. Any identifier (variable/function/constant) matching `purring` is a Stage-2 regression.

- [ ] **Step 2: Cat-identifier grep**

Run: `grep -rn "cat_" engine/ nodes/ --include="*.gd" | grep -v "tcp_cats:cat"`
Expected: zero matches. (Exclude the legitimate species-label references.)

- [ ] **Step 3: Class removed**

Run: `grep -rn "CatPresenceSystem" .`
Expected: zero matches.

- [ ] **Step 4: All tests green**

Run: `script/validate`
Expected: exits 0.

- [ ] **Step 5: Merge the Stage 2 branch**

Follow superpowers:finishing-a-development-branch to open a PR or merge directly per project convention. Do NOT merge piecemeal.

---

# Stage 3 — Documentation, memory, agent, linter cleanup

Text-only stage. No engine code changes. Land on `main` (or a short-lived `docs/stage-3-cleanup` branch).

---

### Task 19: CLAUDE.md updates (§3.1)

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add top-level "Species Are Component Recipes" section**

Insert a new section near the top of `CLAUDE.md` (after the project overview or the Core Design Philosophy section):

```markdown
## Species Are Component Recipes

Systems check capabilities, not species. A "capability" is a component on an
entity — either a zero-data tag (`&"tends_servers"`) or a component with a
payload (`&"sprite_config": {...}`). Species labels (`&"tcp_cats:cat"`) remain
only for save data, UI display, and narrator events. No code path selects
behavior by reading the species label. If you are about to write
`if species == "cat"`, stop and add a component to the recipe instead.

**Capability namespace:** capability tags are bare `StringName` keys (no
`tcp_base:` prefix), matching the desire-channel convention. Promoting a
capability from narrow to broad is a breaking change for mod authors —
document it in release notes.
```

- [ ] **Step 2: Rewrite `## Animal Types & Roles` → `## Species Recipes`**

Change the section header. Reframe each bullet from "cats need warmth" to "the cat recipe includes high warmth weighting, the purr sound, the `tends_servers` tag..." — keep the content, change the framing.

- [ ] **Step 3: Preserve Sandi Metz quote, add ECS gloss**

The existing Sandi Metz quote must stay verbatim. After it, add:

> In TCP this works because ClumsyHuman and CatWithLongTail are *recipes of components*, not classes in a hierarchy — emergence comes from components sharing space.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude-md): anchor the component-recipe framing

New 'Species Are Component Recipes' section restates the anchor rule
from component-mindset-refactor. 'Animal Types & Roles' → 'Species
Recipes' with same content, recipe-oriented framing. Sandi Metz quote
preserved with ECS gloss appended.

Part of component-mindset-refactor §3.1."
```

---

### Task 20: `.claude/rules/animal-ai.md` updates (§3.2)

- [ ] **Step 1: Remove `species_filter` from ObjectAdvertisement class reference**

In `.claude/rules/animal-ai.md`, find the `ObjectAdvertisement` class block (around lines 55–69). Delete the `@export var species_filter: ...` line and any `species_filter` check in the score function.

- [ ] **Step 2: Remove `species_filter` from the config example (line ~78)**

Delete any `"species_filter": [...]` key in the JSONC example.

- [ ] **Step 3: Rewrite cat-centric scoring comments (lines ~150–152)**

Replace "a cat" / "cats" in scoring logic commentary with "an entity with X component" or equivalent neutral phrasing.

- [ ] **Step 4: Commit**

```bash
git add .claude/rules/animal-ai.md
git commit -m "docs(animal-ai): remove species_filter references; species-neutral framing

species_filter was never implemented in code — only documented.
Desire weights handle per-species filtering. Scoring examples rewritten
to frame entities by components, not species.

Part of component-mindset-refactor §3.2."
```

---

### Task 21: `.claude/rules/navigation.md` updates (§3.3)

- [ ] **Step 1: Rewrite edge type table**

Replace "JUMP_UP — cats only, max 3U height" with capability-based phrasing: "JUMP_UP — entities whose `traversal` array includes `JUMP_UP`." Same treatment for every edge-type row.

- [ ] **Step 2: Rewrite the species JSON example**

Replace `cat`/`ferret` keys with neutral placeholders (`species_a`/`species_b`).

- [ ] **Step 3: Add framing note**

Below the JSON example, add:

> The JSON groups capabilities under species for readability, but the pathfinder checks the `traversal` array on the entity's species definition, not the species name.

- [ ] **Step 4: Commit**

```bash
git add .claude/rules/navigation.md
git commit -m "docs(navigation): capability-based edge-type framing

Edge table reads in terms of traversal capabilities, not species names.
Part of component-mindset-refactor §3.3."
```

---

### Task 22: `.claude/rules/core-loop.md` and `.claude/rules/art-direction.md` edits (§3.4, §3.5)

- [ ] **Step 1: core-loop.md**

Replace the line ~26 comment "most cats stop purring" with "most purring entities stop producing output."

- [ ] **Step 2: art-direction.md**

Replace (around lines 101–103) "species-shape coding" with "component-driven shape coding — species recipes declare silhouette shape via a `visual` component."

- [ ] **Step 3: Commit**

```bash
git add .claude/rules/core-loop.md .claude/rules/art-direction.md
git commit -m "docs(rules): species-neutral phrasing in core-loop and art-direction

Part of component-mindset-refactor §3.4 + §3.5."
```

---

### Task 23: Schema files (§3.6)

- [ ] **Step 1: Remove `species_filter` from object_definition.jsonc**

In `schemas/object_definition.jsonc`, remove every `"species_filter": [...]` line and the comment describing it.

- [ ] **Step 2: Commit**

```bash
git add schemas/object_definition.jsonc
git commit -m "schemas: remove species_filter from object_definition

species_filter was never implemented. Desire weights filter scoring
by species. Part of component-mindset-refactor §3.6."
```

---

### Task 24: Superseded-notice banners on old specs (§3.7)

**Files (verify by grep before editing):**
- `docs/superpowers/specs/2026-04-04-ferret-ring0-behavior-design.md`
- `docs/superpowers/specs/2026-04-05-animal-resting-on-design.md`
- `docs/superpowers/plans/2026-04-12-purr-power-*.md` (all four)

- [ ] **Step 1: Confirm the list**

Run: `grep -rln "species_filter\|cat_presence\|cat_seconds\|is_purring" docs/superpowers/`
Record every file found.

- [ ] **Step 2: Prepend the banner to every file**

For each file found in Step 1, add this banner immediately after the `# Title` line (use `Edit` with the file's existing first line as `old_string`):

```markdown
> **Note (2026-04-16):** Identifiers referenced in this document may be superseded by
> `2026-04-16-component-mindset-refactor-design.md`. `species_filter` was never
> implemented in code and is removed from the schema. `cat_presence` → `reclamation`,
> `cat_seconds` → `tended_seconds`, `is_purring` → `is_satisfied` per Stage 2 renames.
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/
git commit -m "docs: superseded-notice banners on pre-refactor specs/plans

Readers cross-reference component-mindset-refactor-design for current
identifiers. Part of §3.7."
```

---

### Task 25: Agent updates (§3.8)

**Files:**
- `.claude/agents/mochi*.md` (Designer)
- `.claude/agents/bramble*.md` (Programmer)
- `.claude/agents/patches*.md` (Community/Modding)

Do NOT modify player-persona agents.

- [ ] **Step 1: Locate the dev-team agent files**

Run: `ls .claude/agents/` and identify Mochi/Bramble/Patches files.

- [ ] **Step 2: Append the recipe-framing line to each**

Add this paragraph to each of the three agent prompts (insert at the end of their role description, before any behavioral rules):

> Treat species as recipes of components. Never design around "what cats do vs. what ferrets do"; design around "what this capability does, regardless of which recipes currently include it."

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/
git commit -m "agents: add component-recipe framing to dev-team agents

Mochi, Bramble, and Patches now prompted to frame designs in
capabilities, not species. Player persona agents unchanged — real
players think in species, and that's fine.

Part of component-mindset-refactor §3.8."
```

---

### Task 26: Memory updates (§3.9)

**Files:**
- New: `~/.claude/projects/-Users-chucklauervose-Documents-github-tuna-control-protocol/memory/feedback_capability_not_species.md`
- Modify: `memory/project_ferret_behavior.md`
- Modify: `memory/MEMORY.md`

- [ ] **Step 1: Create the new memory file**

Write to `/Users/chucklauervose/.claude/projects/-Users-chucklauervose-Documents-github-tuna-control-protocol/memory/feedback_capability_not_species.md`:

```markdown
---
name: Capability not species
description: Systems check capabilities (components), never species labels. Species is display/save data only.
type: feedback
---

Code branches on capabilities, not species. A capability is a component on an entity — zero-data tag (`&"tends_servers"`) or data-bearing component (`&"sprite_config"`). If you're about to write `if species == "cat"`, stop and add a component to the recipe instead. Species labels remain only for saves, UI, and narrator text.

**Why:** Per 2026-04-16-component-mindset-refactor-design — species dispatch was blocking third-species mods, creating functional bugs (ferrets falsely registering as cat-presence), and drifting docs. Refactor converted ~35 sites.

**How to apply:** When reviewing or writing code that branches on animal behavior: if the branch key is the species name, move it into a recipe field. Capability names are bare StringNames (no `tcp_base:` prefix). Promoting a capability from narrow-scope to shared-vocabulary is a breaking change for mod authors.

**Future axis:** `curiosity` (novelty-seeking) and `stimulation` (active play) are merged for now (§1.6 merge). When play/toy mechanics land, expect to re-split. The merge is forward-compatible — reintroducing `stimulation` as a new channel won't break the refactor.
```

- [ ] **Step 2: Reframe `project_ferret_behavior.md`**

Read the existing file. Replace phrasing that implies ferret-specific *code paths* with capability-driven phrasing. Example: "ferret curiosity patrol" → "curiosity-driven patrol (which ferrets currently use because their recipe heavily weights curiosity)." Do not delete — rephrase.

- [ ] **Step 3: Add the new entry to MEMORY.md**

In `~/.claude/projects/.../memory/MEMORY.md`, under the "## User Preferences" section, add:

```markdown
- [Capability not species](feedback_capability_not_species.md) — Branch on components, never species labels; species is display/save data only
```

- [ ] **Step 4: Commit (memory is user-level, outside the repo — no git commit needed)**

Memory files live outside the repo. Just confirm the files exist and the MEMORY.md index has the new entry.

---

### Task 27: Mod documentation — species-recipe schema section (§3.10)

**Files:**
- Modify: `.claude/rules/modding.md` (add "Species Recipe Schema" section)
- Overwrite: `schemas/species_definition.jsonc` (existing file is outdated design scaffold — replace with current schema)

- [ ] **Step 1: Add Species Recipe Schema section to modding.md**

Append to `.claude/rules/modding.md` (after the existing "Rename Redirects" section):

```markdown
## Species Recipe Schema

Every species recipe (`mods/<mod_id>/species/<id>.jsonc`) must declare:

| Field | Type | Purpose |
|---|---|---|
| `id` | `"mod_id:entity_id"` | Namespaced species identifier |
| `name` | string | Display name |
| `desires` | `{channel: int}` | Desire weights (see animal-ai.md) |
| `traversal` | array | Capability tags for path edges (e.g. `["WALK", "JUMP_UP"]`) |
| `sprite_config` | object | `base_path` (with optional `{variant}`), `offset_y`, `animations` (state→key), `animation_frames` (key→strip+frames+fps) |
| `ambient_states` | object | `warm` and `cold` arrays of `{state, weight}` entries |
| `hud_color` | `[r, g, b]` | Floats 0.0–1.0 for name labels |

Optional fields: `starters`, `personality_ranges`, `verbs`, `states`, `animations.required/optional`, `tends_servers` (tag capability), `role_tags` (designer summary).

Canonical example: `mods/tcp_cats/species/cat.jsonc`.

Loading: `SpeciesSchemaValidator` (in `engine/mod/`) runs at mod load and rejects recipes missing any required field via `push_error`. Malformed recipes do not register as species.

Related spec: `docs/superpowers/specs/2026-04-16-component-mindset-refactor-design.md`.
Capability-namespace convention: `docs/superpowers/specs/2026-04-10-mod-extraction-design.md`.
```

- [ ] **Step 2: Replace `schemas/species_definition.jsonc`**

The existing file is an outdated design sketch, not the current recipe format. Replace its contents with a schema documenting the current format (use `mods/tcp_cats/species/cat.jsonc` as the template shape):

```jsonc
// Species Recipe Schema — authoritative shape for species definitions
// Located at: mods/<mod_id>/species/<species_id>.jsonc
// Loader: engine/mod/mod_loader.gd + engine/mod/species_schema_validator.gd
// Spec: docs/superpowers/specs/2026-04-16-component-mindset-refactor-design.md

{
  "schema_version": 1,

  // --- Identity ---
  "id": "mod_id:entity_id",
  "name": "Display Name",

  // --- Required ---
  "desires": { "warmth": 700, "comfort": 700, "curiosity": 150 },
  "personality_ranges": { "warmth": [500, 800] },
  "traversal": ["WALK", "JUMP_UP"],
  "hud_color": [0.9, 0.8, 0.6],

  "sprite_config": {
    "base_path": "res://mods/mod_id/sprites/{variant}",
    "offset_y": -12,
    "animations": {
      "IDLE": { "animation": "idle" }
    },
    "animation_frames": {
      "idle": { "sprite": "_idle_strip8.png", "frames": 8, "fps": 6.0 }
    }
  },

  "ambient_states": {
    "warm": [ { "state": "IDLE", "weight": 10 } ],
    "cold": [ { "state": "IDLE", "weight": 10 } ]
  },

  // --- Optional ---
  "variants": ["variant_a", "variant_b"],
  "states": { "idle": { "advertisements": [] } },
  "initial_state": "idle",
  "sounds": { "purr": ["purr_loop_01.wav"] },
  "verbs": { "push": { "effectiveness": 1000, "desire_affinities": { "curiosity": 500 } } },
  "physical": { "mass": 4000, "size_ru": 2 },
  "strength": 3000,
  "max_jump_height_ru": 3,

  // Capability tags
  "tends_servers": true,

  // Starter-spawn list (engine iterates at bootup)
  "starters": [
    { "name": "DisplayName", "rack": 1, "desires": { "hunger": 900 } }
  ],

  // Designer-facing role summary (non-enforced)
  "role_tags": ["tender", "purrer", "climber"]
}
```

- [ ] **Step 3: Commit**

```bash
git add .claude/rules/modding.md schemas/species_definition.jsonc
git commit -m "docs(modding): species-recipe schema documentation

modding.md now has a Species Recipe Schema section listing required
vs optional fields with references to cat.jsonc as canonical example.
schemas/species_definition.jsonc replaced with a current-format
template (was an outdated design sketch).

Part of component-mindset-refactor §3.10."
```

---

### Task 28: Add `no_species_dispatch` linter check (§3.11)

**Files:**
- Create: `script/checks/no_species_dispatch`
- Modify: `script/validate` (invoke the new check)
- Modify: `script/pre_commit` or equivalent (invoke on staged files)

- [ ] **Step 1: Write the check**

Create `script/checks/no_species_dispatch` (executable shell script, mirroring `script/checks/no_secrets` structure):

```bash
#!/bin/bash
# Flags species-name dispatch in engine/ and nodes/ code.
# Species labels are display/save data only — never used for branching.
# Reference: .claude/rules/modding.md + component-mindset-refactor spec.
#
# Usage: no_species_dispatch              (scan all relevant files)
#        no_species_dispatch file1 file2  (scan specific files)

set -e

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
cd "$REPO_ROOT"

if [ $# -gt 0 ]; then
  FILES=("$@")
else
  FILES=($(find engine nodes -name "*.gd" 2>/dev/null))
fi

FAIL=0

# Pattern 1: String(*species*).contains("cat") or ("ferret")
# Pattern 2: hardcoded &"tcp_cats:cat" / &"tcp_ferrets:ferret" outside string-literal contexts.
# Heuristic: warn on any match; exemptions listed below.
PATTERNS=(
  'String\([^)]*species[^)]*\)\.contains\("cat"\)'
  'String\([^)]*species[^)]*\)\.contains\("ferret"\)'
  '&"tcp_cats:cat"'
  '&"tcp_ferrets:ferret"'
)

EXEMPT_FILES=(
  "nodes/animal_node.gd:is_purring"     # local variable name only, OK to have "cat" in non-dispatch context
)

for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  # Skip test files
  case "$f" in tests/*) continue;; esac
  for pat in "${PATTERNS[@]}"; do
    MATCHES=$(grep -nE "$pat" "$f" || true)
    if [ -n "$MATCHES" ]; then
      echo "FAIL: species dispatch found in $f:"
      echo "$MATCHES"
      FAIL=1
    fi
  done
done

if [ "$FAIL" -eq 1 ]; then
  echo ""
  echo "Species labels must not drive branching in engine/ or nodes/."
  echo "Add a capability component to the species recipe instead."
  echo "See component-mindset-refactor spec + .claude/rules/modding.md."
  exit 1
fi

echo "no_species_dispatch: clean"
exit 0
```

Make it executable: `chmod +x script/checks/no_species_dispatch`

- [ ] **Step 2: Run the check**

Run: `script/checks/no_species_dispatch`
Expected: exits 0 (post-Stage-2 codebase is clean).

- [ ] **Step 3: Wire into `script/validate`**

Read `script/validate` to find where other checks are invoked. Add a line to run `script/checks/no_species_dispatch`.

- [ ] **Step 4: Wire into pre-commit hook**

Read `script/pre_commit` (or whatever invokes checks on staged files). Add an invocation of `no_species_dispatch` scoped to staged files.

- [ ] **Step 5: Prove the check catches regressions**

Temporarily introduce a species-dispatch line into `engine/growth/reclamation_system.gd`:

```gdscript
var test_regression: bool = String(species[&"id"]).contains("cat")
```

Run: `script/checks/no_species_dispatch`
Expected: exits 1, reports the line.

Remove the line. Re-run. Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add script/checks/no_species_dispatch script/validate script/pre_commit
git commit -m "script(checks): add no_species_dispatch regression guard

Flags String(species[\"id\"]).contains(\"cat\"/\"ferret\") and
hardcoded tcp_cats:cat / tcp_ferrets:ferret StringName references in
engine/ and nodes/. Excludes tests and string-literal log contexts.

Wired into script/validate and the pre-commit hook.

Part of component-mindset-refactor §3.11."
```

---

### Task 29: Final Stage 3 success-criteria grep

- [ ] **Step 1: Superseded references exist only in banner-marked spec files**

Run: `grep -rn "cats only\|ferrets only\|species_filter" .claude/ CLAUDE.md docs/ schemas/`
Expected: matches only in files under `docs/superpowers/` that have Stage 3.7 banners, or in `feedback_no_species_filter_on_ads.md` (which documents the decision).

- [ ] **Step 2: No legacy identifiers in docs/CLAUDE.md**

Run: `grep -rn "cat_presence\|is_purring\|cat_seconds" .claude/ CLAUDE.md`
Expected: zero matches.

- [ ] **Step 3: Final validation**

Run: `script/validate`
Expected: exits 0. `no_species_dispatch` clean, `verify_tests` clean, all tests green.

---

# Completion checklist

When all tasks are done:

- [ ] Game boots cleanly
- [ ] `script/validate` exits 0
- [ ] `script/checks/no_species_dispatch` runs and is wired into `script/validate`
- [ ] `script/checks/verify_tests` exits 0 (all stamps match)
- [ ] Stage 1 third-species fixture test passes
- [ ] `grep -rn "purring" engine/ nodes/ --include="*.gd"` reports only non-logic identifier contexts (local visual-indicator var, comments, log strings)
- [ ] `grep -rn "cat_" engine/ nodes/ --include="*.gd" | grep -v "tcp_cats:cat"` returns zero lines
- [ ] No `CatPresenceSystem` class anywhere in the repo
- [ ] `memory/feedback_capability_not_species.md` exists and is linked in `MEMORY.md`
- [ ] `.claude/agents/mochi*.md`, `bramble*.md`, `patches*.md` each carry the recipe-framing paragraph
- [ ] `schemas/species_definition.jsonc` matches the current recipe format
- [ ] `.claude/rules/modding.md` has the Species Recipe Schema section
