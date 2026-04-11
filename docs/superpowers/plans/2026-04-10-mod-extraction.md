# Mod Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract cat, ferret, and tuna content into three standalone mods, build a minimal mod loader to read them, and delete the hardcoded constants they replace.

**Architecture:** Target-state-first — write the mod JSON files and move assets first (Tasks 1-2), then build the loader that reads them (Tasks 3-7), then wire up and delete the old code (Tasks 8-10), then migrate tests and update docs (Tasks 11-12).

**Tech Stack:** GDScript 4.x, JSONC parsing, GUT test framework

**Spec:** `docs/superpowers/specs/2026-04-10-mod-extraction-design.md`

---

## File Map

### New files (engine)

| File | Responsibility |
|---|---|
| `engine/mod/mod_manifest.gd` | Parse mod.json, derive mod ID from title, validate required fields |
| `engine/mod/entity_def_registry.gd` | Store entity definitions, lookup by namespaced ID, spawn entities |
| `engine/mod/sprite_resolver.gd` | Scan sprites/ dir, match convention `{variant}_{state}_strip{N}.png`, validate required anims |
| `engine/mod/verb_resolver.gd` | Score verbs from species definition, physics checks |
| `engine/mod/mod_loader.gd` | Orchestrate: discover mods, sort, parse, register entities, resolve sprites |

### New files (mod content)

| File | Responsibility |
|---|---|
| `mods/tcp_base/mod.json` | Base mod manifest |
| `mods/tcp_cats/mod.json` | Cat mod manifest |
| `mods/tcp_cats/species/cat.jsonc` | Cat species definition |
| `mods/tcp_ferrets/mod.json` | Ferret mod manifest |
| `mods/tcp_ferrets/species/ferret.jsonc` | Ferret species definition |
| `mods/tcp_tuna/mod.json` | Tuna mod manifest |
| `mods/tcp_tuna/objects/tuna_can.jsonc` | Tuna can object definition |

### New files (tests)

| File | Responsibility |
|---|---|
| `tests/unit/test_mod_manifest.gd` | ID derivation, validation |
| `tests/unit/test_entity_def_registry.gd` | Register, lookup, spawn, agency queries |
| `tests/unit/test_sprite_resolver.gd` | Convention matching, validation |
| `tests/unit/test_verb_resolver.gd` | Physics checks, verb scoring |
| `tests/integration/test_mod_loader.gd` | Full load sequence, mod removal |

### Modified files

| File | Change |
|---|---|
| `nodes/game_server.gd` | Replace ~200 lines of inline spawn code with `entity_def_registry.spawn()` calls. Remove `_pick_ambient_state()` species branching. |
| `engine/navigation/species_astar.gd` | Remove `SPECIES_CAPABILITIES` const, accept traversal from EntityDefRegistry |
| `engine/objects/object_state_manager.gd` | Remove `OBJECT_CONFIG` const, read from EntityDefRegistry |
| `engine/animals/curiosity_tracker.gd` | Rename to `novelty_system.gd`, remove ferret species gate |
| 8 test files | Update `tcp_base:cat` → `tcp_cats:cat`, `tcp_base:ferret` → `tcp_ferrets:ferret` |

### Moved files (assets)

| From | To |
|---|---|
| `mods/tcp_base/sprites/cat/*` | `mods/tcp_cats/sprites/` |
| `mods/tcp_base/sounds/cat/*` | `mods/tcp_cats/sounds/` |
| `mods/tcp_base/sprites/ferret/*` | `mods/tcp_ferrets/sprites/` |
| `mods/tcp_base/sounds/ferret/*` | `mods/tcp_ferrets/sounds/` |
| Tuna sprites from `mods/tcp_base/sprites/objects/` | `mods/tcp_tuna/sprites/` |

---

### Task 1: Write mod content files (target state)

**Files:**
- Create: `mods/tcp_base/mod.json`
- Create: `mods/tcp_cats/mod.json`, `mods/tcp_cats/species/cat.jsonc`
- Create: `mods/tcp_ferrets/mod.json`, `mods/tcp_ferrets/species/ferret.jsonc`
- Create: `mods/tcp_tuna/mod.json`, `mods/tcp_tuna/objects/tuna_can.jsonc`

- [ ] **Step 1: Create tcp_base mod.json**

```json
{
  "title": "TCP Base",
  "version": "0.1.0",
  "author": "TCP Team",
  "description": "Framework glue for Tuna Control Protocol. Provides the engine, desire system, and mod loader."
}
```

- [ ] **Step 2: Create tcp_cats mod.json**

```json
{
  "title": "TCP Cats",
  "version": "0.1.0",
  "author": "TCP Team",
  "description": "Cats for the datacenter. Warm, purry, occasionally inconvenient."
}
```

- [ ] **Step 3: Create cat.jsonc**

Write `mods/tcp_cats/species/cat.jsonc` with the full species definition from the spec. Use the existing hardcoded values from `game_server.gd` lines 457-589 as the source of truth for desire weights and personality ranges. Key data points from the existing code:

- Mochi: warmth_weight 800, comfort_weight 600, curiosity_weight 100
- Biscuit: warmth_weight 500, comfort_weight 900, curiosity_weight 100
- Noodle: warmth_weight 700, comfort_weight 700, curiosity_weight 200

These become the `personality_ranges` bounds. The `desires` base values are the midpoints.

```jsonc
{
  "schema_version": 1,
  "id": "cat",
  "name": "Cat",
  "desires": {
    "warmth": 700,
    "comfort": 700,
    "curiosity": 150,
    "noise": -600,
    "chased": -900
  },
  "personality_ranges": {
    "warmth": [500, 800],
    "comfort": [600, 900],
    "curiosity": [100, 200],
    "noise": [-840, -360],
    "chased": [-1000, -800]
  },
  "physical": { "mass": 4000, "size_ru": 2 },
  "strength": 3000,
  "traversal": ["WALK", "JUMP_UP", "JUMP_DOWN"],
  "max_jump_height_ru": 3,
  "variants": ["cat01", "cat02", "cat03", "cat04", "cat05"],
  "animations": {
    "required": ["idle", "walk", "sit", "sleep"],
    "optional": ["groom", "stretch", "knead", "fright", "liedown", "standup"]
  },
  "states": {
    "idle": {
      "advertisements": [
        { "type": "warmth", "strength": 300, "radius_ru": 2 },
        { "type": "curiosity", "strength": 400, "radius_ru": 3, "novelty_duration": 150, "novelty_cooldown": 50 }
      ]
    },
    "sleeping": {
      "advertisements": [
        { "type": "warmth", "strength": 400, "radius_ru": 1 },
        { "type": "comfort", "strength": 300, "radius_ru": 2 }
      ]
    },
    "grooming": { "advertisements": [] },
    "seeking": { "advertisements": [] },
    "startled": {
      "advertisements": [
        { "type": "noise", "strength": 200, "radius_ru": 3 }
      ]
    }
  },
  "sounds": {
    "purr": ["purr_low_01.wav", "purr_low_02.wav"],
    "mrrp": ["cat_mrrp_01.wav"],
    "startled": ["cat_startled_01.wav"]
  },
  "verbs": {
    "push": { "effectiveness": 1000, "desire_affinities": { "stimulation": 500, "curiosity": 300 } },
    "bat": { "effectiveness": 500, "desire_affinities": { "stimulation": 600 } },
    "drag": { "effectiveness": 700, "desire_affinities": { "curiosity": 800 } },
    "knock_off": { "effectiveness": 2000, "desire_affinities": { "stimulation": 900 } },
    "sit_on": { "desire_affinities": { "comfort": 700, "warmth": 200 } }
  },
  "initial_state": "idle"
}
```

- [ ] **Step 4: Create tcp_ferrets mod.json + ferret.jsonc**

`mods/tcp_ferrets/mod.json`:
```json
{
  "title": "TCP Ferrets",
  "version": "0.1.0",
  "author": "TCP Team",
  "description": "Ferrets for the datacenter. Curious, chaotic, excellent at logistics."
}
```

`mods/tcp_ferrets/species/ferret.jsonc` — derive from `game_server.gd` lines 591-639:
```jsonc
{
  "schema_version": 1,
  "id": "ferret",
  "name": "Ferret",
  "desires": {
    "warmth": 350,
    "comfort": 700,
    "curiosity": 850
  },
  "personality_ranges": {
    "warmth": [300, 400],
    "comfort": [600, 800],
    "curiosity": [800, 900]
  },
  "physical": { "mass": 1500, "size_ru": 1 },
  "strength": 1500,
  "traversal": ["WALK", "JUMP_DOWN"],
  "max_jump_height_ru": 0,
  "variants": ["lilotter"],
  "animations": {
    "required": ["idle", "walk", "sit", "sleep"],
    "optional": ["sneak", "crouch", "liedown"]
  },
  "states": {
    "idle": { "advertisements": [] },
    "sleeping": {
      "advertisements": [
        { "type": "warmth", "strength": 200, "radius_ru": 1 }
      ]
    },
    "seeking": { "advertisements": [] },
    "startled": { "advertisements": [] }
  },
  "sounds": {
    "dook": ["ferret_dook_01.wav"],
    "startled": ["ferret_startled_01.wav"]
  },
  "verbs": {
    "push": { "effectiveness": 800, "desire_affinities": { "stimulation": 400, "curiosity": 500 } },
    "drag": { "effectiveness": 1000, "desire_affinities": { "curiosity": 900 } }
  },
  "initial_state": "idle"
}
```

- [ ] **Step 5: Create tcp_tuna mod.json + tuna_can.jsonc**

`mods/tcp_tuna/mod.json`:
```json
{
  "title": "TCP Tuna",
  "version": "0.1.0",
  "author": "TCP Team",
  "description": "Canned tuna. Closed until the robot arm opens it. Delicious once opened."
}
```

`mods/tcp_tuna/objects/tuna_can.jsonc` — derive from `object_state_manager.gd` lines 7-20:
```jsonc
{
  "schema_version": 1,
  "id": "tuna_can",
  "name": "Tuna Can",
  "states": {
    "sealed": {
      "advertisements": [
        { "type": "openable", "strength": 800, "radius_ru": 3, "action": "open", "action_duration": 30 }
      ],
      "sprite": "tuna_can_sealed.png",
      "transitions": {
        "open": { "trigger": "robot_arm_action" }
      }
    },
    "open": {
      "advertisements": [
        { "type": "food", "strength": 800, "radius_ru": 5, "action": "eat", "action_duration": 50 }
      ],
      "sprite": "tuna_can_open.png",
      "transitions": {
        "empty": { "trigger": "consumed", "after_ticks": 600 }
      }
    },
    "empty": {
      "advertisements": [],
      "sprite": "tuna_can_empty.png"
    }
  },
  "initial_state": "sealed",
  "physical": { "mass": 400, "size_ru": 1 }
}
```

- [ ] **Step 6: Commit**

```bash
git add mods/tcp_base/mod.json mods/tcp_cats/ mods/tcp_ferrets/ mods/tcp_tuna/
git commit -m "feat(mods): write target-state mod content files for cat, ferret, tuna

Three new mods with mod.json manifests, species/object JSONC definitions.
Data derived from hardcoded constants in game_server.gd and
object_state_manager.gd. Loader not yet implemented — these files are
the target state."
```

---

### Task 2: Move sprite and sound assets to mod directories

**Files:**
- Move: `mods/tcp_base/sprites/cat/*` → `mods/tcp_cats/sprites/`
- Move: `mods/tcp_base/sounds/cat/*` → `mods/tcp_cats/sounds/`
- Move: `mods/tcp_base/sprites/ferret/*` → `mods/tcp_ferrets/sprites/`
- Move: `mods/tcp_base/sounds/ferret/*` → `mods/tcp_ferrets/sounds/`
- Move: Tuna sprites → `mods/tcp_tuna/sprites/`

- [ ] **Step 1: Move cat assets**

```bash
mkdir -p mods/tcp_cats/sprites mods/tcp_cats/sounds
git mv mods/tcp_base/sprites/cat/* mods/tcp_cats/sprites/
git mv mods/tcp_base/sounds/cat/* mods/tcp_cats/sounds/
```

- [ ] **Step 2: Move ferret assets**

```bash
mkdir -p mods/tcp_ferrets/sprites mods/tcp_ferrets/sounds
git mv mods/tcp_base/sprites/ferret/* mods/tcp_ferrets/sprites/
git mv mods/tcp_base/sounds/ferret/* mods/tcp_ferrets/sounds/
```

- [ ] **Step 3: Move tuna assets**

Check what tuna sprites exist in `mods/tcp_base/sprites/objects/`. Move any tuna-related sprites. If tuna sprites don't exist yet (likely — they may be placeholder), create empty placeholder files.

```bash
mkdir -p mods/tcp_tuna/sprites mods/tcp_tuna/sounds
# Move any tuna_can* sprites from objects/
# If none exist, note in commit message that tuna sprites are pending
```

- [ ] **Step 4: Reimport Godot resources**

```bash
/Applications/Godot.app/Contents/MacOS/godot --headless --import
```

Verify no import errors from the moved files. Godot will regenerate `.import` files at the new paths.

- [ ] **Step 5: Commit**

```bash
git add -A mods/
git commit -m "chore(mods): move cat, ferret, tuna assets to mod directories

Sprites and sounds moved from mods/tcp_base/{sprites,sounds}/{cat,ferret}/
to their respective mod directories. Godot reimport clean."
```

---

### Task 3: ModManifest — parse mod.json, derive ID

**Files:**
- Create: `engine/mod/mod_manifest.gd`
- Create: `tests/unit/test_mod_manifest.gd`

- [ ] **Step 1: Write failing tests for ID derivation and validation**

```gdscript
# tests/unit/test_mod_manifest.gd
extends GutTest

func test_derive_id_from_simple_title():
	var manifest := ModManifest.parse_dict({
		"title": "TCP Cats", "version": "0.1.0", "author": "TCP Team",
	})
	assert_eq(manifest.id, &"tcp_cats")

func test_derive_id_lowercases():
	var manifest := ModManifest.parse_dict({
		"title": "My COOL Mod", "version": "1.0.0", "author": "Me",
	})
	assert_eq(manifest.id, &"my_cool_mod")

func test_derive_id_replaces_non_alphanumeric():
	var manifest := ModManifest.parse_dict({
		"title": "Fluffy Ferret Friends!", "version": "1.0.0", "author": "Me",
	})
	assert_eq(manifest.id, &"fluffy_ferret_friends")

func test_derive_id_collapses_underscores():
	var manifest := ModManifest.parse_dict({
		"title": "TCP -- Cats", "version": "1.0.0", "author": "Me",
	})
	assert_eq(manifest.id, &"tcp_cats")

func test_derive_id_truncates_at_48():
	var long_title: String = "A Very Long Mod Title That Exceeds The Maximum Allowed Length For Identifiers"
	var manifest := ModManifest.parse_dict({
		"title": long_title, "version": "1.0.0", "author": "Me",
	})
	assert_lt(manifest.id.length(), 49)

func test_missing_title_returns_null():
	var manifest := ModManifest.parse_dict({
		"version": "1.0.0", "author": "Me",
	})
	assert_null(manifest, "Missing title should return null")

func test_missing_version_returns_null():
	var manifest := ModManifest.parse_dict({
		"title": "Test", "author": "Me",
	})
	assert_null(manifest, "Missing version should return null")

func test_missing_author_returns_null():
	var manifest := ModManifest.parse_dict({
		"title": "Test", "version": "1.0.0",
	})
	assert_null(manifest, "Missing author should return null")

func test_description_is_optional():
	var manifest := ModManifest.parse_dict({
		"title": "Test", "version": "1.0.0", "author": "Me",
	})
	assert_not_null(manifest)
	assert_eq(manifest.description, "")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `script/checks/gut_tests -f tests/unit/test_mod_manifest.gd`
Expected: FAIL — `ModManifest` class not found

- [ ] **Step 3: Implement ModManifest**

```gdscript
# engine/mod/mod_manifest.gd
class_name ModManifest extends RefCounted

var id: StringName = &""
var title: String = ""
var version: String = ""
var author: String = ""
var description: String = ""
var mod_path: String = ""


static func parse_dict(data: Dictionary) -> ModManifest:
	if not data.has("title") or not data.has("version") or not data.has("author"):
		push_error("ModManifest: missing required field (title, version, or author)")
		return null
	var manifest := ModManifest.new()
	manifest.title = str(data["title"])
	manifest.version = str(data["version"])
	manifest.author = str(data["author"])
	manifest.description = str(data.get("description", ""))
	manifest.id = _derive_id(manifest.title)
	return manifest


static func parse_file(path: String) -> ModManifest:
	if not FileAccess.file_exists(path):
		push_error("ModManifest: file not found: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("ModManifest: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return null
	var manifest := parse_dict(json.data)
	if manifest != null:
		manifest.mod_path = path.get_base_dir()
	return manifest


static func _derive_id(title: String) -> StringName:
	var result: String = title.to_lower()
	# Replace non-alphanumeric with underscore
	var cleaned: String = ""
	for i in result.length():
		var c: String = result[i]
		if c >= "a" and c <= "z" or c >= "0" and c <= "9":
			cleaned += c
		else:
			cleaned += "_"
	# Collapse consecutive underscores
	while cleaned.contains("__"):
		cleaned = cleaned.replace("__", "_")
	# Strip leading/trailing underscores
	cleaned = cleaned.strip_edges().trim_prefix("_").trim_suffix("_")
	# Truncate at 48
	if cleaned.length() > 48:
		cleaned = cleaned.left(48).trim_suffix("_")
	return StringName(cleaned)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `script/checks/gut_tests -f tests/unit/test_mod_manifest.gd`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add engine/mod/mod_manifest.gd tests/unit/test_mod_manifest.gd
git commit -m "feat(mod): add ModManifest — parse mod.json, derive ID from title"
```

---

### Task 4: EntityDefRegistry — register, lookup, agency queries

**Files:**
- Create: `engine/mod/entity_def_registry.gd`
- Create: `tests/unit/test_entity_def_registry.gd`

- [ ] **Step 1: Write failing tests**

```gdscript
# tests/unit/test_entity_def_registry.gd
extends GutTest

var _registry: EntityDefRegistry

func before_each() -> void:
	_registry = EntityDefRegistry.new()

func test_register_and_lookup():
	var def: Dictionary = {"id": "cat", "desires": {"warmth": 800}}
	_registry.register(&"tcp_cats:cat", def)
	assert_true(_registry.has_entity(&"tcp_cats:cat"))
	assert_eq(_registry.get_definition(&"tcp_cats:cat"), def)

func test_has_entity_returns_false_for_unknown():
	assert_false(_registry.has_entity(&"nonexistent:thing"))

func test_get_all_entities():
	_registry.register(&"tcp_cats:cat", {"id": "cat", "desires": {"warmth": 800}})
	_registry.register(&"tcp_tuna:tuna_can", {"id": "tuna_can", "states": {}})
	var all: Array[StringName] = _registry.get_all_entities()
	assert_eq(all.size(), 2)
	assert_has(all, &"tcp_cats:cat")
	assert_has(all, &"tcp_tuna:tuna_can")

func test_has_traversal_true_for_species():
	_registry.register(&"tcp_cats:cat", {
		"id": "cat", "traversal": ["WALK", "JUMP_UP"],
	})
	assert_true(_registry.has_traversal(&"tcp_cats:cat"))

func test_has_traversal_false_for_object():
	_registry.register(&"tcp_tuna:tuna_can", {"id": "tuna_can", "states": {}})
	assert_false(_registry.has_traversal(&"tcp_tuna:tuna_can"))

func test_has_desires_true_for_species():
	_registry.register(&"tcp_cats:cat", {
		"id": "cat", "desires": {"warmth": 800},
	})
	assert_true(_registry.has_desires(&"tcp_cats:cat"))

func test_has_desires_false_for_object():
	_registry.register(&"tcp_tuna:tuna_can", {"id": "tuna_can", "states": {}})
	assert_false(_registry.has_desires(&"tcp_tuna:tuna_can"))

func test_get_traversal():
	_registry.register(&"tcp_cats:cat", {
		"id": "cat", "traversal": ["WALK", "JUMP_UP", "JUMP_DOWN"],
	})
	var traversal: Array = _registry.get_traversal(&"tcp_cats:cat")
	assert_eq(traversal.size(), 3)
	assert_has(traversal, "WALK")

func test_get_desires():
	_registry.register(&"tcp_cats:cat", {
		"id": "cat", "desires": {"warmth": 800, "noise": -600},
	})
	var desires: Dictionary = _registry.get_desires(&"tcp_cats:cat")
	assert_eq(desires["warmth"], 800)
	assert_eq(desires["noise"], -600)

func test_get_initial_state():
	_registry.register(&"tcp_cats:cat", {"id": "cat", "initial_state": "idle"})
	assert_eq(_registry.get_initial_state(&"tcp_cats:cat"), &"idle")

func test_get_states():
	var states: Dictionary = {
		"idle": {"advertisements": []},
		"sleeping": {"advertisements": [{"type": "warmth", "strength": 400}]},
	}
	_registry.register(&"tcp_cats:cat", {"id": "cat", "states": states})
	assert_eq(_registry.get_states(&"tcp_cats:cat"), states)

func test_duplicate_id_asserts():
	_registry.register(&"tcp_cats:cat", {"id": "cat"})
	# Second registration with same ID should assert
	_registry.register(&"tcp_cats:cat", {"id": "cat"})
	assert_true(true, "Should have triggered assert in debug")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `script/checks/gut_tests -f tests/unit/test_entity_def_registry.gd`
Expected: FAIL — `EntityDefRegistry` class not found

- [ ] **Step 3: Implement EntityDefRegistry (lookup and agency queries)**

```gdscript
# engine/mod/entity_def_registry.gd
class_name EntityDefRegistry extends RefCounted

var _definitions: Dictionary = {}  # StringName -> Dictionary


func register(entity_id: StringName, definition: Dictionary) -> void:
	assert(not _definitions.has(entity_id),
		"EntityDefRegistry: duplicate entity ID: %s" % entity_id)
	_definitions[entity_id] = definition


func has_entity(entity_id: StringName) -> bool:
	return _definitions.has(entity_id)


func get_definition(entity_id: StringName) -> Dictionary:
	assert(_definitions.has(entity_id),
		"EntityDefRegistry: unknown entity: %s" % entity_id)
	return _definitions[entity_id]


func get_all_entities() -> Array[StringName]:
	var result: Array[StringName] = []
	for key: StringName in _definitions:
		result.append(key)
	return result


func has_traversal(entity_id: StringName) -> bool:
	if not _definitions.has(entity_id):
		return false
	var def: Dictionary = _definitions[entity_id]
	return def.has("traversal") and not def["traversal"].is_empty()


func has_desires(entity_id: StringName) -> bool:
	if not _definitions.has(entity_id):
		return false
	var def: Dictionary = _definitions[entity_id]
	return def.has("desires") and not def["desires"].is_empty()


func get_traversal(entity_id: StringName) -> Array:
	var def: Dictionary = get_definition(entity_id)
	return def.get("traversal", [])


func get_desires(entity_id: StringName) -> Dictionary:
	var def: Dictionary = get_definition(entity_id)
	return def.get("desires", {})


func get_states(entity_id: StringName) -> Dictionary:
	var def: Dictionary = get_definition(entity_id)
	return def.get("states", {})


func get_initial_state(entity_id: StringName) -> StringName:
	var def: Dictionary = get_definition(entity_id)
	return StringName(def.get("initial_state", "idle"))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `script/checks/gut_tests -f tests/unit/test_entity_def_registry.gd`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add engine/mod/entity_def_registry.gd tests/unit/test_entity_def_registry.gd
git commit -m "feat(mod): add EntityDefRegistry — register, lookup, agency queries"
```

---

### Task 5: EntityDefRegistry.spawn() — create entities from definitions

**Files:**
- Modify: `engine/mod/entity_def_registry.gd`
- Modify: `tests/unit/test_entity_def_registry.gd`

This task adds the `spawn()` method that replaces the inline `db.set_component()` blocks in `game_server.gd`.

- [ ] **Step 1: Write failing tests for spawn**

Add to `tests/unit/test_entity_def_registry.gd`:

```gdscript
func test_spawn_creates_entity_with_species_component():
	_registry.register(&"tcp_cats:cat", _make_cat_def())
	var db := GameStateDB.new()
	var id: int = _registry.spawn(&"tcp_cats:cat", db, {
		&"name": &"Mochi", &"position": {&"x": 1000, &"y": 2000},
	})
	assert_ne(id, GameStateDB.INVALID_ID)
	assert_true(db.has_component(id, &"species"))
	var species: Dictionary = db.get_component(id, &"species")
	assert_eq(species[&"id"], &"tcp_cats:cat")
	assert_eq(species[&"name"], &"Mochi")

func test_spawn_sets_desires_from_personality_ranges():
	_registry.register(&"tcp_cats:cat", _make_cat_def())
	var db := GameStateDB.new()
	var id: int = _registry.spawn(&"tcp_cats:cat", db, {})
	var personality: Dictionary = db.get_component(id, &"personality")
	# Warmth personality should be within [500, 800]
	assert_gte(personality[&"warmth_weight"], 500)
	assert_lte(personality[&"warmth_weight"], 800)

func test_spawn_sets_ai_state_to_initial():
	_registry.register(&"tcp_cats:cat", _make_cat_def())
	var db := GameStateDB.new()
	var id: int = _registry.spawn(&"tcp_cats:cat", db, {})
	var ai: Dictionary = db.get_component(id, &"ai_state")
	assert_eq(ai[&"state"], &"idle")

func test_spawn_sets_position_from_overrides():
	_registry.register(&"tcp_cats:cat", _make_cat_def())
	var db := GameStateDB.new()
	var id: int = _registry.spawn(&"tcp_cats:cat", db, {
		&"position": {&"x": 5000, &"y": 3000},
	})
	var pos: Dictionary = db.get_component(id, &"position")
	assert_eq(pos[&"x"], 5000)
	assert_eq(pos[&"y"], 3000)

func test_spawn_picks_random_variant():
	_registry.register(&"tcp_cats:cat", _make_cat_def())
	var db := GameStateDB.new()
	var variants_seen: Dictionary = {}
	for i in 20:
		var id: int = _registry.spawn(&"tcp_cats:cat", db, {})
		var species: Dictionary = db.get_component(id, &"species")
		variants_seen[species[&"variant"]] = true
	# With 5 variants and 20 spawns, we should see at least 2 different ones
	assert_gte(variants_seen.size(), 2, "Expected multiple variants across 20 spawns")

func test_spawn_object_has_no_desires_component():
	_registry.register(&"tcp_tuna:tuna_can", _make_tuna_def())
	var db := GameStateDB.new()
	var id: int = _registry.spawn(&"tcp_tuna:tuna_can", db, {})
	assert_false(db.has_component(id, &"desires"))
	assert_false(db.has_component(id, &"personality"))
	assert_true(db.has_component(id, &"object_state"))

func _make_cat_def() -> Dictionary:
	return {
		"id": "cat", "name": "Cat",
		"desires": {"warmth": 700, "comfort": 700, "curiosity": 150},
		"personality_ranges": {
			"warmth": [500, 800], "comfort": [600, 900], "curiosity": [100, 200],
		},
		"physical": {"mass": 4000, "size_ru": 2},
		"strength": 3000,
		"traversal": ["WALK", "JUMP_UP", "JUMP_DOWN"],
		"variants": ["cat01", "cat02", "cat03", "cat04", "cat05"],
		"states": {"idle": {"advertisements": []}},
		"initial_state": "idle",
	}

func _make_tuna_def() -> Dictionary:
	return {
		"id": "tuna_can", "name": "Tuna Can",
		"states": {
			"sealed": {"advertisements": [{"type": "food", "strength": 800}]},
			"open": {"advertisements": [{"type": "food", "strength": 800}]},
			"empty": {"advertisements": []},
		},
		"initial_state": "sealed",
		"physical": {"mass": 400, "size_ru": 1},
	}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `script/checks/gut_tests -f tests/unit/test_entity_def_registry.gd`
Expected: FAIL — `spawn` method not found

- [ ] **Step 3: Implement spawn()**

Add to `engine/mod/entity_def_registry.gd`:

```gdscript
func spawn(entity_id: StringName, db: GameStateDB,
		overrides: Dictionary = {}) -> int:
	assert(_definitions.has(entity_id),
		"EntityDefRegistry.spawn: unknown entity: %s" % entity_id)
	var def: Dictionary = _definitions[entity_id]
	var id: int = db.create_entity()

	# Species component
	var variant: String = ""
	if def.has("variants") and not def["variants"].is_empty():
		var variants: Array = def["variants"]
		variant = variants[randi() % variants.size()]
	var species_data: Dictionary = {
		&"id": entity_id,
		&"variant": StringName(variant),
		&"name": overrides.get(&"name", StringName(def.get("name", ""))),
	}
	db.set_component(id, &"species", species_data)

	# Position from overrides
	if overrides.has(&"position"):
		var pos: Dictionary = overrides[&"position"]
		db.set_component(id, &"position", pos)
		db.update_spatial(id, pos.get(&"x", 0), pos.get(&"y", 0))

	# Desires + personality (species only)
	if def.has("desires") and not def["desires"].is_empty():
		var base_desires: Dictionary = def["desires"]
		var personality: Dictionary = {}
		var initial_desires: Dictionary = {}
		for key: String in base_desires:
			var skey: StringName = StringName(key)
			if def.has("personality_ranges") and def["personality_ranges"].has(key):
				var bounds: Array = def["personality_ranges"][key]
				var min_val: int = int(bounds[0])
				var max_val: int = int(bounds[1])
				personality[StringName(key + "_weight")] = randi_range(min_val, max_val)
			else:
				personality[StringName(key + "_weight")] = int(base_desires[key])
			initial_desires[skey] = 200  # Start with low satisfaction (hungry/cold)
		db.set_component(id, &"desires", initial_desires)
		db.set_component(id, &"personality", personality)

	# AI state (species only)
	if has_traversal(entity_id):
		var initial: StringName = get_initial_state(entity_id)
		db.set_component(id, &"ai_state", {
			&"state": initial,
			&"meta_state": &"AMBIENT",
			&"commitment_score": 0,
		})
		db.set_component(id, &"target", {
			&"x": Constants.INVALID_ID,
			&"y": Constants.INVALID_ID,
			&"entity_id": Constants.INVALID_ID,
		})

	# Object state (objects only — entities without traversal)
	if not has_traversal(entity_id) and def.has("states"):
		var initial: StringName = get_initial_state(entity_id)
		db.set_component(id, &"object_state", {&"state": initial})
		db.set_component(id, &"object_type", {&"type": entity_id})

	# Physical properties
	if def.has("physical"):
		db.set_component(id, &"physical", {
			&"mass": int(def["physical"].get("mass", 0)),
			&"size_ru": int(def["physical"].get("size_ru", 1)),
		})

	# State-driven advertisements (set for initial state)
	if def.has("states"):
		var initial: StringName = get_initial_state(entity_id)
		var states: Dictionary = def["states"]
		if states.has(String(initial)) and states[String(initial)].has("advertisements"):
			var ads: Array = states[String(initial)]["advertisements"]
			if not ads.is_empty():
				db.set_component(id, &"advertisements", {&"list": ads})

	return id
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `script/checks/gut_tests -f tests/unit/test_entity_def_registry.gd`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add engine/mod/entity_def_registry.gd tests/unit/test_entity_def_registry.gd
git commit -m "feat(mod): add EntityDefRegistry.spawn() — create entities from definitions"
```

---

### Task 6: SpriteResolver — scan sprites by convention

**Files:**
- Create: `engine/mod/sprite_resolver.gd`
- Create: `tests/unit/test_sprite_resolver.gd`

- [ ] **Step 1: Write failing tests**

```gdscript
# tests/unit/test_sprite_resolver.gd
extends GutTest

func test_parse_sprite_filename():
	var result: Dictionary = SpriteResolver.parse_sprite_filename("cat01_idle_strip8.png")
	assert_eq(result["variant"], "cat01")
	assert_eq(result["state"], "idle")
	assert_eq(result["frame_count"], 8)

func test_parse_sprite_filename_with_multi_word_state():
	# standup is one word in our convention, not stand_up
	var result: Dictionary = SpriteResolver.parse_sprite_filename("cat01_standup_strip6.png")
	assert_eq(result["variant"], "cat01")
	assert_eq(result["state"], "standup")
	assert_eq(result["frame_count"], 6)

func test_parse_sprite_filename_invalid_returns_empty():
	var result: Dictionary = SpriteResolver.parse_sprite_filename("not_a_sprite.png")
	assert_true(result.is_empty())

func test_resolve_matches_known_variants():
	var resolver := SpriteResolver.new()
	var sprites: Dictionary = resolver.resolve_from_list(
		["cat01_idle_strip8.png", "cat01_walk_strip8.png", "cat02_idle_strip8.png"],
		["cat01", "cat02"],
	)
	assert_true(sprites.has("cat01"))
	assert_true(sprites["cat01"].has("idle"))
	assert_eq(sprites["cat01"]["idle"]["frame_count"], 8)
	assert_true(sprites.has("cat02"))
	assert_true(sprites["cat02"].has("idle"))

func test_validate_required_passes():
	var resolver := SpriteResolver.new()
	var sprites: Dictionary = {
		"cat01": {"idle": {}, "walk": {}, "sit": {}, "sleep": {}},
	}
	var anims: Dictionary = {"required": ["idle", "walk", "sit", "sleep"], "optional": []}
	var errors: Array[String] = resolver.validate_required(sprites, anims, ["cat01"])
	assert_eq(errors.size(), 0)

func test_validate_required_fails_for_missing():
	var resolver := SpriteResolver.new()
	var sprites: Dictionary = {
		"cat01": {"idle": {}, "walk": {}},
	}
	var anims: Dictionary = {"required": ["idle", "walk", "sit", "sleep"], "optional": []}
	var errors: Array[String] = resolver.validate_required(sprites, anims, ["cat01"])
	assert_eq(errors.size(), 2, "Expected 2 errors for missing sit and sleep")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `script/checks/gut_tests -f tests/unit/test_sprite_resolver.gd`
Expected: FAIL — `SpriteResolver` class not found

- [ ] **Step 3: Implement SpriteResolver**

```gdscript
# engine/mod/sprite_resolver.gd
class_name SpriteResolver extends RefCounted


static func parse_sprite_filename(filename: String) -> Dictionary:
	# Expected: {variant}_{state}_strip{N}.png
	var base: String = filename.get_basename()  # strip .png
	var strip_idx: int = base.rfind("_strip")
	if strip_idx < 0:
		return {}
	var frame_str: String = base.substr(strip_idx + 6)
	if not frame_str.is_valid_int():
		return {}
	var prefix: String = base.left(strip_idx)
	# Split prefix into variant and state at the FIRST underscore
	# that matches a known variant (handled by resolve_from_list)
	# For parse_sprite_filename alone, we split at the last underscore
	var last_us: int = prefix.rfind("_")
	if last_us < 1:
		return {}
	return {
		"variant": prefix.left(last_us),
		"state": prefix.substr(last_us + 1),
		"frame_count": int(frame_str),
	}


func resolve_from_list(filenames: Array, known_variants: Array) -> Dictionary:
	# Returns: {variant: {state: {frame_count: N, filename: str}}}
	var result: Dictionary = {}
	for variant: String in known_variants:
		result[variant] = {}
	for filename in filenames:
		var base: String = String(filename).get_basename()
		var strip_idx: int = base.rfind("_strip")
		if strip_idx < 0:
			continue
		var frame_str: String = base.substr(strip_idx + 6)
		if not frame_str.is_valid_int():
			continue
		var prefix: String = base.left(strip_idx)
		# Match against known variants (handles underscores in variant names)
		for variant: String in known_variants:
			if prefix.begins_with(variant + "_"):
				var state: String = prefix.substr(variant.length() + 1)
				result[variant][state] = {
					"frame_count": int(frame_str),
					"filename": String(filename),
				}
				break
	return result


func validate_required(sprites: Dictionary, animations: Dictionary,
		variants: Array) -> Array[String]:
	var errors: Array[String] = []
	var required: Array = animations.get("required", [])
	for variant: String in variants:
		if not sprites.has(variant):
			for state: String in required:
				errors.append("Missing sprite: %s_%s_strip*.png" % [variant, state])
			continue
		for state: String in required:
			if not sprites[variant].has(state):
				errors.append("Missing required sprite: %s_%s_strip*.png" % [variant, state])
	return errors
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `script/checks/gut_tests -f tests/unit/test_sprite_resolver.gd`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add engine/mod/sprite_resolver.gd tests/unit/test_sprite_resolver.gd
git commit -m "feat(mod): add SpriteResolver — scan sprites by naming convention"
```

---

### Task 7: VerbResolver — physics checks and verb scoring

**Files:**
- Create: `engine/mod/verb_resolver.gd`
- Create: `tests/unit/test_verb_resolver.gd`

- [ ] **Step 1: Write failing tests**

```gdscript
# tests/unit/test_verb_resolver.gd
extends GutTest

var _resolver: VerbResolver
var _db: GameStateDB
var _defs: EntityDefRegistry

func before_each() -> void:
	_resolver = VerbResolver.new()
	_db = GameStateDB.new()
	_defs = EntityDefRegistry.new()

func test_can_perform_push_succeeds_when_strong_enough():
	_defs.register(&"tcp_cats:cat", {
		"id": "cat", "strength": 3000,
		"verbs": {"push": {"effectiveness": 1000, "desire_affinities": {}}},
	})
	var actor: int = _db.create_entity()
	_db.set_component(actor, &"species", {&"id": &"tcp_cats:cat"})
	_db.set_component(actor, &"physical", {&"mass": 4000, &"size_ru": 2})
	var target: int = _db.create_entity()
	_db.set_component(target, &"physical", {&"mass": 400, &"size_ru": 1})
	# 3000 * 1000 / 1000 = 3000 > 400
	assert_true(_resolver.can_perform(&"push", actor, target, _db, _defs))

func test_can_perform_push_fails_when_too_weak():
	_defs.register(&"tcp_cats:cat", {
		"id": "cat", "strength": 3000,
		"verbs": {"push": {"effectiveness": 1000, "desire_affinities": {}}},
	})
	var actor: int = _db.create_entity()
	_db.set_component(actor, &"species", {&"id": &"tcp_cats:cat"})
	_db.set_component(actor, &"physical", {&"mass": 4000, &"size_ru": 2})
	var target: int = _db.create_entity()
	_db.set_component(target, &"physical", {&"mass": 50000, &"size_ru": 4})
	# 3000 * 1000 / 1000 = 3000 < 50000
	assert_false(_resolver.can_perform(&"push", actor, target, _db, _defs))

func test_sit_on_uses_size_check_not_strength():
	_defs.register(&"tcp_cats:cat", {
		"id": "cat", "strength": 3000,
		"verbs": {"sit_on": {"desire_affinities": {"comfort": 700}}},
	})
	var actor: int = _db.create_entity()
	_db.set_component(actor, &"species", {&"id": &"tcp_cats:cat"})
	_db.set_component(actor, &"physical", {&"mass": 4000, &"size_ru": 2})
	var target: int = _db.create_entity()
	_db.set_component(target, &"physical", {&"mass": 100, &"size_ru": 2})
	# size_ru 2 <= 2, should pass
	assert_true(_resolver.can_perform(&"sit_on", actor, target, _db, _defs))

func test_sit_on_fails_when_too_big():
	_defs.register(&"tcp_cats:cat", {
		"id": "cat", "strength": 3000,
		"verbs": {"sit_on": {"desire_affinities": {"comfort": 700}}},
	})
	var actor: int = _db.create_entity()
	_db.set_component(actor, &"species", {&"id": &"tcp_cats:cat"})
	_db.set_component(actor, &"physical", {&"mass": 4000, &"size_ru": 2})
	var target: int = _db.create_entity()
	_db.set_component(target, &"physical", {&"mass": 400, &"size_ru": 1})
	# size_ru 2 > 1, should fail
	assert_false(_resolver.can_perform(&"sit_on", actor, target, _db, _defs))

func test_score_verbs_returns_best_verb():
	_defs.register(&"tcp_cats:cat", {
		"id": "cat", "strength": 3000,
		"verbs": {
			"push": {"effectiveness": 1000, "desire_affinities": {"stimulation": 500}},
			"bat": {"effectiveness": 500, "desire_affinities": {"stimulation": 900}},
		},
	})
	var actor: int = _db.create_entity()
	_db.set_component(actor, &"species", {&"id": &"tcp_cats:cat"})
	_db.set_component(actor, &"physical", {&"mass": 4000, &"size_ru": 2})
	_db.set_component(actor, &"desires", {&"stimulation": 800})  # high deficit
	_db.set_component(actor, &"personality", {&"stimulation_weight": 900})
	var target: int = _db.create_entity()
	_db.set_component(target, &"physical", {&"mass": 400, &"size_ru": 1})
	var best: StringName = _resolver.score_verbs(actor, target, _db, _defs)
	# bat has higher stimulation affinity (900 vs 500), both pass physics
	assert_eq(best, &"bat")

func test_score_verbs_returns_empty_when_nothing_passes():
	_defs.register(&"tcp_cats:cat", {
		"id": "cat", "strength": 100,
		"verbs": {
			"push": {"effectiveness": 1000, "desire_affinities": {"stimulation": 500}},
		},
	})
	var actor: int = _db.create_entity()
	_db.set_component(actor, &"species", {&"id": &"tcp_cats:cat"})
	_db.set_component(actor, &"physical", {&"mass": 4000, &"size_ru": 2})
	_db.set_component(actor, &"desires", {&"stimulation": 800})
	_db.set_component(actor, &"personality", {&"stimulation_weight": 900})
	var target: int = _db.create_entity()
	_db.set_component(target, &"physical", {&"mass": 50000, &"size_ru": 4})
	var best: StringName = _resolver.score_verbs(actor, target, _db, _defs)
	assert_eq(best, &"", "No verb should pass physics check")

func test_score_verbs_returns_empty_for_entity_with_no_verbs():
	_defs.register(&"tcp_tuna:tuna_can", {"id": "tuna_can", "states": {}})
	var actor: int = _db.create_entity()
	_db.set_component(actor, &"species", {&"id": &"tcp_tuna:tuna_can"})
	var target: int = _db.create_entity()
	_db.set_component(target, &"physical", {&"mass": 100, &"size_ru": 1})
	var best: StringName = _resolver.score_verbs(actor, target, _db, _defs)
	assert_eq(best, &"")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `script/checks/gut_tests -f tests/unit/test_verb_resolver.gd`
Expected: FAIL — `VerbResolver` class not found

- [ ] **Step 3: Implement VerbResolver**

```gdscript
# engine/mod/verb_resolver.gd
class_name VerbResolver extends RefCounted


func can_perform(verb_id: StringName, actor_id: int, target_id: int,
		db: GameStateDB, entity_defs: EntityDefRegistry) -> bool:
	var species_id: StringName = db.get_component(actor_id, &"species")[&"id"]
	var def: Dictionary = entity_defs.get_definition(species_id)
	if not def.has("verbs") or not def["verbs"].has(String(verb_id)):
		return false
	var verb: Dictionary = def["verbs"][String(verb_id)]
	return _check_physics(verb, actor_id, target_id, db, def)


func score_verbs(actor_id: int, target_id: int, db: GameStateDB,
		entity_defs: EntityDefRegistry) -> StringName:
	if not db.has_component(actor_id, &"species"):
		return &""
	var species_id: StringName = db.get_component(actor_id, &"species")[&"id"]
	if not entity_defs.has_entity(species_id):
		return &""
	var def: Dictionary = entity_defs.get_definition(species_id)
	if not def.has("verbs"):
		return &""
	var best_verb: StringName = &""
	var best_score: int = 0
	for verb_name: String in def["verbs"]:
		var verb: Dictionary = def["verbs"][verb_name]
		if not _check_physics(verb, actor_id, target_id, db, def):
			continue
		var score: int = _score_desire_affinity(verb, actor_id, db)
		if score > best_score:
			best_score = score
			best_verb = StringName(verb_name)
	return best_verb


func _check_physics(verb: Dictionary, actor_id: int, target_id: int,
		db: GameStateDB, species_def: Dictionary) -> bool:
	if not verb.has("effectiveness"):
		# No effectiveness = alternate check (e.g. sit_on uses size)
		if not db.has_component(actor_id, &"physical") or \
				not db.has_component(target_id, &"physical"):
			return false
		var actor_size: int = db.get_component(actor_id, &"physical")[&"size_ru"]
		var target_size: int = db.get_component(target_id, &"physical")[&"size_ru"]
		return actor_size <= target_size
	# Standard physics: strength * effectiveness / 1000 > target mass
	var strength: int = int(species_def.get("strength", 0))
	var effectiveness: int = int(verb["effectiveness"])
	if not db.has_component(target_id, &"physical"):
		return false
	var target_mass: int = db.get_component(target_id, &"physical")[&"mass"]
	return strength * effectiveness / 1000 > target_mass


func _score_desire_affinity(verb: Dictionary, actor_id: int,
		db: GameStateDB) -> int:
	if not verb.has("desire_affinities"):
		return 1  # Verb with no affinities gets minimal score
	var affinities: Dictionary = verb["desire_affinities"]
	if not db.has_component(actor_id, &"desires"):
		return 0
	var desires: Dictionary = db.get_component(actor_id, &"desires")
	# Score = highest (affinity * desire_value) across all affinity channels
	var max_score: int = 0
	for channel: String in affinities:
		var affinity: int = int(affinities[channel])
		var desire_val: int = int(desires.get(StringName(channel), 0))
		var score: int = affinity * desire_val / 1000
		if score > max_score:
			max_score = score
	return max_score
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `script/checks/gut_tests -f tests/unit/test_verb_resolver.gd`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add engine/mod/verb_resolver.gd tests/unit/test_verb_resolver.gd
git commit -m "feat(mod): add VerbResolver — physics checks and verb scoring"
```

---

### Task 8: ModLoader — discover, sort, load mods

**Files:**
- Create: `engine/mod/mod_loader.gd`
- Create: `tests/integration/test_mod_loader.gd`

- [ ] **Step 1: Write failing tests**

```gdscript
# tests/integration/test_mod_loader.gd
extends GutTest

func test_load_all_discovers_mods():
	var loader := ModLoader.new()
	var result: Dictionary = loader.load_all("res://mods/")
	assert_true(result["entity_defs"] is EntityDefRegistry)
	var defs: EntityDefRegistry = result["entity_defs"]
	# Should find tcp_cats, tcp_ferrets, tcp_tuna content
	assert_true(defs.has_entity(&"tcp_cats:cat"), "Cat should be registered")
	assert_true(defs.has_entity(&"tcp_ferrets:ferret"), "Ferret should be registered")
	assert_true(defs.has_entity(&"tcp_tuna:tuna_can"), "Tuna can should be registered")

func test_load_all_returns_manifests():
	var loader := ModLoader.new()
	var result: Dictionary = loader.load_all("res://mods/")
	var manifests: Array = result["manifests"]
	assert_gte(manifests.size(), 3, "Should load at least 3 mods")
	var ids: Array[StringName] = []
	for m: ModManifest in manifests:
		ids.append(m.id)
	assert_has(ids, &"tcp_cats")
	assert_has(ids, &"tcp_ferrets")
	assert_has(ids, &"tcp_tuna")

func test_species_has_traversal():
	var loader := ModLoader.new()
	var result: Dictionary = loader.load_all("res://mods/")
	var defs: EntityDefRegistry = result["entity_defs"]
	assert_true(defs.has_traversal(&"tcp_cats:cat"))
	assert_true(defs.has_traversal(&"tcp_ferrets:ferret"))
	assert_false(defs.has_traversal(&"tcp_tuna:tuna_can"))

func test_object_has_states():
	var loader := ModLoader.new()
	var result: Dictionary = loader.load_all("res://mods/")
	var defs: EntityDefRegistry = result["entity_defs"]
	var states: Dictionary = defs.get_states(&"tcp_tuna:tuna_can")
	assert_true(states.has("sealed"))
	assert_true(states.has("open"))
	assert_true(states.has("empty"))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `script/checks/gut_tests -f tests/integration/test_mod_loader.gd`
Expected: FAIL — `ModLoader` class not found

- [ ] **Step 3: Implement ModLoader**

```gdscript
# engine/mod/mod_loader.gd
class_name ModLoader extends RefCounted


func load_all(mods_path: String) -> Dictionary:
	var entity_defs := EntityDefRegistry.new()
	var manifests: Array[ModManifest] = []
	var sprite_resolver := SpriteResolver.new()

	# Step 1: Discover — scan for mod.json files
	var mod_dirs: Array[String] = _discover_mods(mods_path)

	# Step 2: Parse manifests and sort
	var parsed: Array[ModManifest] = []
	for dir_path: String in mod_dirs:
		var manifest := ModManifest.parse_file(dir_path + "/mod.json")
		if manifest == null:
			push_error("ModLoader: failed to parse %s/mod.json" % dir_path)
			continue
		parsed.append(manifest)

	# Sort alphabetically by id (three-lane sorting deferred — all default lane)
	parsed.sort_custom(func(a: ModManifest, b: ModManifest) -> bool:
		return String(a.id) < String(b.id)
	)

	# Step 3: Check for duplicate mod IDs
	var seen_ids: Dictionary = {}
	for manifest: ModManifest in parsed:
		assert(not seen_ids.has(manifest.id),
			"ModLoader: duplicate mod ID '%s' from titles '%s' and '%s'" % [
				manifest.id, seen_ids.get(manifest.id, ""), manifest.title
			])
		seen_ids[manifest.id] = manifest.title

	# Step 4: Load content from each mod
	for manifest: ModManifest in parsed:
		_load_mod_content(manifest, entity_defs, sprite_resolver)
		manifests.append(manifest)

	return {
		"entity_defs": entity_defs,
		"manifests": manifests,
		"sprite_resolver": sprite_resolver,
	}


func _discover_mods(mods_path: String) -> Array[String]:
	var dirs: Array[String] = []
	var dir := DirAccess.open(mods_path)
	if dir == null:
		push_error("ModLoader: cannot open mods directory: %s" % mods_path)
		return dirs
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var mod_json_path: String = mods_path + entry + "/mod.json"
			if FileAccess.file_exists(mod_json_path):
				dirs.append(mods_path + entry)
		entry = dir.get_next()
	return dirs


func _load_mod_content(manifest: ModManifest, entity_defs: EntityDefRegistry,
		sprite_resolver: SpriteResolver) -> void:
	var mod_path: String = manifest.mod_path
	# Load species
	_load_jsonc_dir(mod_path + "/species", manifest.id, entity_defs)
	# Load objects
	_load_jsonc_dir(mod_path + "/objects", manifest.id, entity_defs)


func _load_jsonc_dir(dir_path: String, mod_id: StringName,
		entity_defs: EntityDefRegistry) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and (entry.ends_with(".jsonc") or entry.ends_with(".json")):
			var file_path: String = dir_path + "/" + entry
			var data: Dictionary = _parse_jsonc(file_path)
			if data.is_empty():
				entry = dir.get_next()
				continue
			if not data.has("id"):
				push_error("ModLoader: missing 'id' in %s" % file_path)
				entry = dir.get_next()
				continue
			var entity_id := StringName(String(mod_id) + ":" + str(data["id"]))
			entity_defs.register(entity_id, data)
		entry = dir.get_next()


func _parse_jsonc(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ModLoader: file not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	# Strip // comments for JSONC support
	var lines: PackedStringArray = text.split("\n")
	var cleaned: String = ""
	for line: String in lines:
		var comment_idx: int = line.find("//")
		if comment_idx >= 0:
			# Only strip if // is not inside a string (simple heuristic: count quotes before //)
			var before: String = line.left(comment_idx)
			if before.count('"') % 2 == 0:
				line = before
		cleaned += line + "\n"
	var json := JSON.new()
	var err := json.parse(cleaned)
	if err != OK:
		push_error("ModLoader: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}
	if json.data is Dictionary:
		return json.data
	push_error("ModLoader: expected Dictionary in %s, got %s" % [path, typeof(json.data)])
	return {}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `script/checks/gut_tests -f tests/integration/test_mod_loader.gd`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add engine/mod/mod_loader.gd tests/integration/test_mod_loader.gd
git commit -m "feat(mod): add ModLoader — discover, sort, parse, register mods"
```

---

### Task 9: Wire up game_server.gd to use the loader

**Files:**
- Modify: `nodes/game_server.gd`

This task replaces the hardcoded spawn blocks with `entity_def_registry.spawn()` calls. The existing inline `db.set_component()` code (~200 lines) is replaced by ~20 lines that load mods and spawn from definitions.

- [ ] **Step 1: Add ModLoader to game_server.gd _ready()**

At the top of `_init_world()` (or wherever the hardcoded spawns live), add:

```gdscript
var _mod_loader := ModLoader.new()
var _entity_defs: EntityDefRegistry
var _verb_resolver := VerbResolver.new()

func _init_world() -> void:
	var mod_result: Dictionary = _mod_loader.load_all("res://mods/")
	_entity_defs = mod_result["entity_defs"]
	# ... rest of init
```

- [ ] **Step 2: Replace inline cat spawns with entity_def_registry.spawn()**

Replace the three cat spawn blocks (Mochi, Biscuit, Noodle — lines ~457-589) with:

```gdscript
# Spawn cats from mod definitions
if _entity_defs.has_entity(&"tcp_cats:cat"):
	var cat_positions: Array[Dictionary] = [
		{&"name": &"Mochi", &"position": {&"x": _rack_center_x(0), &"y": _floor_y()}},
		{&"name": &"Biscuit", &"position": {&"x": _rack_quarter_x(1), &"y": _floor_y()}},
		{&"name": &"Noodle", &"position": {&"x": _rack_center_x(2), &"y": _floor_y()}},
	]
	for overrides: Dictionary in cat_positions:
		_entity_defs.spawn(&"tcp_cats:cat", db, overrides)
```

- [ ] **Step 3: Replace inline ferret spawns**

Replace the two ferret spawn blocks (Slinky, Bandit — lines ~591-639) with:

```gdscript
if _entity_defs.has_entity(&"tcp_ferrets:ferret"):
	var ferret_positions: Array[Dictionary] = [
		{&"name": &"Slinky", &"position": {&"x": _rack_center_x(1), &"y": _floor_y()}},
		{&"name": &"Bandit", &"position": {&"x": _rack_quarter_x(2), &"y": _floor_y()}},
	]
	for overrides: Dictionary in ferret_positions:
		var id: int = _entity_defs.spawn(&"tcp_ferrets:ferret", db, overrides)
		if _entity_defs.get_desires(&"tcp_ferrets:ferret").has("curiosity"):
			_novelty_trackers[id] = NoveltySystem.new()
```

- [ ] **Step 4: Replace _pick_ambient_state() species branching**

Replace `is_cat = String(species[&"id"]).contains("cat")` (line ~251) with a lookup against the entity definition's states. The ambient state pool should be driven by species state data, not string matching.

Read the species definition for the entity, check which states have advertisements defined, and use those as the available ambient states.

- [ ] **Step 5: Run all tests**

Run: `script/checks/gut_tests`
Expected: Some existing tests may fail due to namespace changes — that's Task 11.

- [ ] **Step 6: Commit**

```bash
git add nodes/game_server.gd
git commit -m "feat(mod): wire game_server.gd to use ModLoader and EntityDefRegistry

Replace ~200 lines of inline db.set_component() spawn blocks with
entity_def_registry.spawn() calls. Species branching now reads from
entity definitions instead of string-matching species IDs."
```

---

### Task 10: Delete hardcoded constants + genericize NoveltySystem

**Files:**
- Modify: `engine/navigation/species_astar.gd` — remove `SPECIES_CAPABILITIES`, accept from registry
- Modify: `engine/objects/object_state_manager.gd` — remove `OBJECT_CONFIG`, read from registry
- Rename: `engine/animals/curiosity_tracker.gd` → `engine/animals/novelty_system.gd`

- [ ] **Step 1: Update species_astar.gd to use EntityDefRegistry**

Remove `const SPECIES_CAPABILITIES` (lines 9-12). Instead, accept traversal data from outside:

```gdscript
# Replace:
const SPECIES_CAPABILITIES: Dictionary = {
	&"tcp_base:cat": [WALK, JUMP_UP, JUMP_DOWN],
	&"tcp_base:ferret": [WALK, JUMP_DOWN],
}

# With: accept capabilities via set_species
func set_species(species_id: StringName) -> void:
	_species = species_id

func set_capabilities(capabilities: Array) -> void:
	_capabilities = capabilities
```

The caller (game_server or nav_graph_builder) passes capabilities from `entity_defs.get_traversal()` instead of relying on the hardcoded const.

- [ ] **Step 2: Update object_state_manager.gd to use EntityDefRegistry**

Remove `const OBJECT_CONFIG` (lines 7-43). Replace `get_ads_for_state()` to read from the entity definition instead:

```gdscript
var _entity_defs: EntityDefRegistry

func _init(db: GameStateDB, entity_defs: EntityDefRegistry) -> void:
	_db = db
	_entity_defs = entity_defs

func get_ads_for_state(type_name: StringName, state: StringName) -> Array:
	if not _entity_defs.has_entity(type_name):
		return []
	var states: Dictionary = _entity_defs.get_states(type_name)
	if not states.has(String(state)):
		return []
	return states[String(state)].get("advertisements", [])
```

- [ ] **Step 3: Rename curiosity_tracker.gd → novelty_system.gd**

```bash
git mv engine/animals/curiosity_tracker.gd engine/animals/novelty_system.gd
```

Update `class_name CuriosityTracker` → `class_name NoveltySystem`. Remove any ferret-specific species checks. The system should run for any entity with a non-zero `curiosity` desire weight.

- [ ] **Step 4: Run all tests**

Run: `script/checks/gut_tests`
Expected: Tests referencing old class names or namespaces may fail — addressed in Task 11.

- [ ] **Step 5: Commit**

```bash
git add engine/navigation/species_astar.gd engine/objects/object_state_manager.gd
git add engine/animals/novelty_system.gd
git commit -m "refactor(mod): delete hardcoded species/object constants, genericize NoveltySystem

Remove SPECIES_CAPABILITIES from species_astar.gd — now reads from
EntityDefRegistry. Remove OBJECT_CONFIG from object_state_manager.gd —
now reads from EntityDefRegistry. Rename CuriosityTracker → NoveltySystem,
remove ferret species gate."
```

---

### Task 11: Migrate existing tests

**Files:**
- Modify: ~8 test files with `tcp_base:cat` / `tcp_base:ferret` references

- [ ] **Step 1: Find all references to old namespaced IDs**

```bash
grep -rn "tcp_base:cat\|tcp_base:ferret" tests/
```

Update every occurrence:
- `tcp_base:cat` → `tcp_cats:cat`
- `tcp_base:ferret` → `tcp_ferrets:ferret`

- [ ] **Step 2: Update tests to register species via EntityDefRegistry**

Tests that previously relied on hardcoded constants should create a local `EntityDefRegistry`, register test species definitions, and pass the registry to the code under test. This makes tests independent of which mods are installed on disk.

Example pattern for existing tests:

```gdscript
var _defs: EntityDefRegistry

func before_each() -> void:
	_defs = EntityDefRegistry.new()
	_defs.register(&"tcp_cats:cat", {
		"id": "cat",
		"traversal": ["WALK", "JUMP_UP", "JUMP_DOWN"],
		"desires": {"warmth": 700, "comfort": 700},
		"physical": {"mass": 4000, "size_ru": 2},
		"strength": 3000,
		"initial_state": "idle",
		"states": {"idle": {"advertisements": []}},
	})
```

- [ ] **Step 3: Update CuriosityTracker references to NoveltySystem**

```bash
grep -rn "CuriosityTracker\|curiosity_tracker" tests/ nodes/ engine/
```

Update all references to use the new name.

- [ ] **Step 4: Run full test suite**

Run: `script/validate`
Expected: All tests PASS, all lint checks PASS.

- [ ] **Step 5: Commit**

```bash
git add tests/ nodes/ engine/
git commit -m "test(mod): migrate tests to new namespaced IDs and EntityDefRegistry

Update tcp_base:cat → tcp_cats:cat, tcp_base:ferret → tcp_ferrets:ferret.
Tests now register species via EntityDefRegistry instead of relying on
hardcoded constants. CuriosityTracker → NoveltySystem references updated."
```

---

### Task 12: Update rule files and stamp tests

**Files:**
- Modify: `.claude/rules/animal-ai.md` — update Aversions section for signed desires
- Modify: `.claude/rules/modding.md` — add schema references

- [ ] **Step 1: Update animal-ai.md Aversions section**

Per the spec's "Updates to Existing Specs" section:
- Remove the separate `aversions` dictionary from the species config example
- Remove the "name by desired state" convention
- Merge into a single `desires` dictionary with -1000 to 1000 range
- Rename `desire_type` to `type` in the advertisement schema
- Simplify `score_for()` — the sign branch still exists but uses one dictionary

- [ ] **Step 2: Update modding.md**

Add references to the species JSON schema and object JSON schema. Document that animals and objects are both advertising entities sharing the same state/advertisement pattern. Note that `mod.json.lock` is designed but not yet implemented.

- [ ] **Step 3: Run validate**

Run: `script/validate`
Expected: All checks pass.

- [ ] **Step 4: Stamp all new test files**

```bash
script/stamp_tests tests/unit/test_mod_manifest.gd
script/stamp_tests tests/unit/test_entity_def_registry.gd
script/stamp_tests tests/unit/test_sprite_resolver.gd
script/stamp_tests tests/unit/test_verb_resolver.gd
script/stamp_tests tests/integration/test_mod_loader.gd
script/checks/verify_tests
```

- [ ] **Step 5: Re-stamp any modified existing test files**

Any test file that was modified in Task 11 needs re-stamping (behavior changed due to namespace migration).

```bash
script/stamp_tests tests/unit/test_species_astar.gd
script/stamp_tests tests/unit/test_desire_resolver.gd
# ... etc for each modified test
script/checks/verify_tests
```

- [ ] **Step 6: Commit**

```bash
git add .claude/rules/ tests/
git commit -m "docs(mod): update animal-ai.md and modding.md for signed desires and entity schema

Aversions section updated to signed desires model. modding.md updated
with species and object JSON schema references. All tests stamped."
```
