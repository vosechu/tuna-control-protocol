# Mod Extraction Design — Cat, Ferret, Tuna

> **Status:** design draft, 2026-04-10. Not yet implemented.
> **Approach:** Target-state-first — write the mod files, build the loader to read them, delete the hardcoded constants.

## Goal

Extract cat, ferret, and tuna content from hardcoded engine constants into three standalone mods. Build a minimal mod loader that makes them work. Validate that the desire-channel system is a sufficient cross-mod API — no mod needs to know about any other mod's content.

### Success criteria

1. `mods/tcp_cats/`, `mods/tcp_ferrets/`, `mods/tcp_tuna/` each contain a `mod.json`, species/object `.jsonc` files, sprites, and sounds.
2. `tcp_base` contains zero species or object content — only framework glue and assets not yet extracted (infrastructure, environment, robot).
3. Removing `mods/tcp_cats/` from disk causes the game to start with no cats and no errors. The ferrets and tuna still work. Same for any single mod removal.
4. The hardcoded `OBJECT_CONFIG` in `object_state_manager.gd`, `SPECIES_CAPABILITIES` in `species_astar.gd`, and inline `db.set_component()` spawn blocks in `game_server.gd` are deleted. The loader replaces them.
5. All existing tests pass against the loader path, not the hardcoded path.

### Non-goals (deferred)

- Config deep-merge across mods (one mod overriding another's values)
- `mod.json.lock` scanner/generator
- Dependency auto-detection or enforcement
- Asset overlay / virtual filesystem
- Hot-reload or code loading from mods
- Extracting infrastructure, environment, or robot content into mods
- Spatial resolution of physical interactions (collision, chain reactions, gravity, boundaries) — verb scoring is in scope; what happens to the world when the verb succeeds is a follow-up brainstorm

---

## Design Philosophy

### Everything is a mod, tcp_base is framework

`tcp_base` ships zero content — no species, no objects. Every noun (cat, ferret, tuna can, server, cable, comfy pile) is a mod. `tcp_base` provides verbs: the desire system, advertisement scoring, tick loop, navigation, heat propagation, robot arm framework, mod loader.

### Desire channels are the cross-mod API

Mods communicate through desire channels — `StringName` keys like `"warmth"`, `"food"`, `"noise"`, `"social"`. Objects advertise channels with a strength. Animals have desire weights per channel. The scoring function matches them without knowing what species or object is involved. A ferret tries a guinea pig wheel because both speak `"stimulation"` — neither mod references the other.

### Animals and objects are both advertising entities

Both have states. Both advertise desire channels from their current state. Both transition between states via triggers. The engine has one advertisement scanner, not two. The distinction is emergent from the data: entities with `traversal` have agency (they move and evaluate ads). Entities with `desires` but no `traversal` could exist (a plant wanting sunlight) but don't act. Entities with neither are passive objects that radiate advertisements from their current state.

### Signed desires replace separate aversions

One `desires` dictionary per species, values from -1000 to 1000. Positive = attracted. Negative = averse. `noise: -600` means the animal dislikes noise. A loud PDU advertises `{type: "noise", strength: 700}`. Score: `-600 * 700 * distance_factor = negative`. Repulsion falls out from the math. No separate aversion system, no double-negative naming conventions.

### No manual dependency declarations

Per `modding.md`: dependencies are auto-detected by scanning, not hand-declared. For this first pass, the scanner is deferred — mods load independently with no dependency enforcement. The `mod.json.lock` concept (auto-generated file listing provided desire channels, advertisement channels, traversal types, and computed `enhances` suggestions) is documented but not implemented.

---

## Mod Directory Layout

```
mods/
  tcp_base/                        # Framework glue — no species or object content
    mod.json

  tcp_cats/
    mod.json
    species/
      cat.jsonc
    sprites/
      cat01_idle_strip8.png        # Moved from mods/tcp_base/sprites/cat/
      cat01_walk_strip8.png
      ...                          # All cat + kitten sprite variants
    sounds/
      purr_low_01.wav              # Moved from mods/tcp_base/sounds/cat/
      ...

  tcp_ferrets/
    mod.json
    species/
      ferret.jsonc
    sprites/
      lilotter_idle_strip8.png     # Kept as lilotter for now (artist redraw pending)
      ...
    sounds/
      ferret_dook_01.wav
      ...

  tcp_tuna/
    mod.json
    objects/
      tuna_can.jsonc
    sprites/
      tuna_can_closed.png
      tuna_can_open.png
      tuna_can_empty.png
    sounds/
      can_pop.wav
```

---

## Mod Manifest

**`mod.json`** — human-authored, minimal:

```json
{
  "title": "TCP Cats",
  "version": "0.1.0",
  "author": "TCP Team",
  "description": "Cats for the datacenter. Warm, purry, occasionally inconvenient."
}
```

- `id` is auto-derived from title: `"TCP Cats"` -> `tcp_cats` (ASCII lowercase, non-alphanumeric to `_`, collapse, strip, truncate 48).
- No `tags`, `depends`, `load_after`, or `id` fields. Per `modding.md`.
- `schema_version` is not in the manifest — it's in each content file (species, object) so they version independently.

### Future: mod.json.lock (not implemented this pass)

Auto-generated by a scanner tool, regenerated on mod install/update:

```json
{
  "id": "tcp_cats",
  "provides": {
    "species": ["tcp_cats:cat"],
    "desire_channels": {
      "warmth": 800, "food": 700, "comfort": 900, "social": 600,
      "noise": -600, "chased": -900
    },
    "traversal": ["WALK", "JUMP_UP", "JUMP_DOWN"],
    "advertisement_channels": ["social", "warmth", "comfort", "purr", "noise"]
  },
  "requires": [],
  "enhances": ["tcp_tuna"]
}
```

`enhances` is computed: scanner sees cats desire `food`, finds `tcp_tuna` provides food advertisements, suggests the pairing. Modders never think about dependencies — the scanner figures out ecosystem relationships from desire channel overlap.

---

## Species JSON Schema

**`mods/tcp_cats/species/cat.jsonc`:**

```jsonc
{
  "schema_version": 1,
  "id": "cat",
  "name": "Cat",

  // Desire weights: -1000 (strong aversion) to 1000 (strong attraction)
  "desires": {
    "warmth": 800,
    "food": 700,
    "comfort": 900,
    "social": 600,
    "noise": -600,
    "chased": -900
  },

  // Per-individual randomization: final desire weight picked from this range at spawn
  "personality_ranges": {
    "warmth": [640, 960],
    "food": [560, 840],
    "comfort": [630, 1000],
    "social": [300, 600],
    "noise": [-840, -360],
    "chased": [-1000, -800]
  },

  // Physical properties
  "physical": { "mass": 4000, "size_ru": 2 },
  "strength": 3000,

  // Navigation
  "traversal": ["WALK", "JUMP_UP", "JUMP_DOWN"],
  "max_jump_height_ru": 3,

  // Visual variants — loader scans sprites/ for {variant}_{state}_strip{N}.png
  "variants": ["cat01", "cat02", "cat03", "cat04", "cat05"],

  // Animation states — loader validates required sprites exist per variant
  "animations": {
    "required": ["idle", "walk", "sit", "sleep"],
    "optional": ["groom", "stretch", "knead", "fright", "liedown", "standup"]
  },

  // State-driven advertisements — what this animal radiates in each state
  "states": {
    "idle": {
      "advertisements": [
        { "type": "social", "strength": 200, "radius_ru": 2 },
        { "type": "warmth", "strength": 100, "radius_ru": 1 }
      ]
    },
    "sleeping": {
      "advertisements": [
        { "type": "warmth", "strength": 400, "radius_ru": 1 },
        { "type": "comfort", "strength": 300, "radius_ru": 2 }
      ]
    },
    "purring": {
      "advertisements": [
        { "type": "social", "strength": 500, "radius_ru": 3 },
        { "type": "purr", "strength": 600, "radius_ru": 5 },
        { "type": "warmth", "strength": 300, "radius_ru": 1 }
      ]
    },
    "grooming": {
      "advertisements": []
    },
    "seeking": {
      "advertisements": []
    },
    "startled": {
      "advertisements": [
        { "type": "noise", "strength": 200, "radius_ru": 3 }
      ]
    }
  },

  // Sound mapping — event name to filename(s), loader picks randomly from arrays
  "sounds": {
    "purr": ["purr_low_01.wav", "purr_low_02.wav"],
    "mrrp": ["cat_mrrp_01.wav"],
    "startled": ["cat_startled_01.wav"]
  },

  // Physical interaction verbs — what this animal attempts and how effectively
  "verbs": {
    "push":     { "effectiveness": 1000, "desire_affinities": { "stimulation": 500, "curiosity": 300 } },
    "bat":      { "effectiveness": 500,  "desire_affinities": { "stimulation": 600 } },
    "drag":     { "effectiveness": 700,  "desire_affinities": { "curiosity": 800 } },
    "knock_off": { "effectiveness": 2000, "desire_affinities": { "stimulation": 900 } },
    "sit_on":   { "desire_affinities": { "comfort": 700, "warmth": 200 } }
  },

  "initial_state": "idle"
}
```

### Key schema decisions

1. **`id` is local, namespaced at load time.** Modder writes `"id": "cat"`, loader registers as `tcp_cats:cat`.
2. **`desires` is a single signed dictionary.** Positive = attraction, negative = aversion. `noise: -600` means averse to noise. Objects advertise `{type: "noise", strength: 700}`. Score: `-600 * 700 * distance = negative`. Repulsion from math, no special case.
3. **`personality_ranges` are final value bounds, not multipliers.** `warmth: [640, 960]` means this individual cat's warmth desire is randomly picked from 640 to 960 at spawn. The base `desires.warmth: 800` is the species average — used for documentation, scanning, and balancing.
4. **Sprites resolved by convention.** Loader scans `sprites/` for `{variant}_{state}_strip*.png`. Frame count parsed from filename. No sprite manifest in JSON.
5. **Required vs optional animations.** Loader errors if a required animation is missing for any variant. Optional animations fall back to idle silently.
6. **States with advertisements.** Animals radiate desire channels from their current state, same as objects. A sleeping cat advertises warmth — other cold cats are attracted — pile behavior emerges with no pile-on code.
7. **Sounds mapped by event name.** Keys are engine-defined event names (state entries, triggers). Values are filenames or arrays for random selection. All sound files live in the mod's `sounds/` directory. No variant-per-sound — all individuals of a species share the same sound set.

---

## Object JSON Schema

**`mods/tcp_tuna/objects/tuna_can.jsonc`:**

```jsonc
{
  "schema_version": 1,
  "id": "tuna_can",
  "name": "Tuna Can",

  "states": {
    "closed": {
      "advertisements": [
        { "type": "food", "strength": 200, "radius_ru": 3 }
      ],
      "sprite": "tuna_can_closed.png",
      "transitions": {
        "opened": {
          "trigger": "robot_arm_action",
          "sound": "can_pop.wav"
        }
      }
    },
    "opened": {
      "advertisements": [
        { "type": "food", "strength": 800, "radius_ru": 5 }
      ],
      "sprite": "tuna_can_open.png",
      "transitions": {
        "empty": {
          "trigger": "consumed",
          "after_ticks": 600
        }
      }
    },
    "empty": {
      "advertisements": [],
      "sprite": "tuna_can_empty.png"
    }
  },

  "initial_state": "closed",

  "physical": { "mass": 400, "size_ru": 1 }
}
```

### Key schema decisions

1. **Objects are state machines.** Each state has its own advertisements, sprite, and transition rules. A closed can smells like food weakly; an opened can is a strong food source; an empty can advertises nothing.
2. **Advertisements live on states, not objects.** Same pattern as species — current state determines what the entity radiates.
3. **Transitions are trigger-based.** `"robot_arm_action"` and `"consumed"` are engine-defined triggers. The set of known triggers is an engine constant — same as the animation state registry.
4. **No affordance booleans.** No `draggable`, `pushable`, `battable`. Whether an animal can move an object is resolved from physics: `actor.strength * verb.effectiveness > target.mass`. See Physical Interactions section.

---

## Physical Interactions

### No affordance booleans — mass + strength + verbs

Animals don't check if something is "pushable." They try, and physics determines the outcome. A turtle pushes a box with a cat in it because `turtle.strength * push.effectiveness > box.mass + cat.mass`. A cat bats a tuna can off a shelf because `cat.strength * bat.effectiveness > can.mass`. A kitten fails to push a server because `kitten.strength * push.effectiveness < server.mass`. All emergent from numbers, no permission flags.

### Entity physical properties

Every entity has:
```jsonc
"physical": { "mass": 4000, "size_ru": 2 }  // mass in grams, size in rack units
```

Animals additionally have:
```jsonc
"strength": 3000  // grams of force this species can exert
```

### Verb definitions live on species

Each species declares what physical interactions it can attempt, with what effectiveness and for what motivations. Verbs are part of the species JSON — no separate verb files needed:

```jsonc
// In species JSON
"verbs": {
  "push":      { "effectiveness": 1000, "desire_affinities": { "stimulation": 500, "curiosity": 300 } },
  "bat":       { "effectiveness": 500,  "desire_affinities": { "stimulation": 600 } },
  "drag":      { "effectiveness": 700,  "desire_affinities": { "curiosity": 800 } },
  "knock_off": { "effectiveness": 2000, "desire_affinities": { "stimulation": 900 } },
  "sit_on":    { "desire_affinities": { "comfort": 700, "warmth": 200 } }
}
```

A turtle mod's species JSON defines its own verb set inline:

```jsonc
"verbs": {
  "push": { "effectiveness": 1500, "desire_affinities": { "stimulation": 800 } }
}
```

The species is fully self-contained — desires, traversal, verbs, sprites, all in one JSON file.

### Physics resolution

The engine's verb resolver evaluates one comparison per verb:

```
actor.strength * verb.effectiveness / 1000 > target.mass
```

If true, the interaction succeeds. If false, the animal strains visibly and gives up — the verb's animation plays, nothing moves, the animal does its confused-idle.

**Missing `effectiveness` = skip strength check.** Verbs without an `effectiveness` field (like `sit_on`) use an alternate check instead of the strength formula. For `sit_on`: `actor.physical.size_ru <= target.physical.size_ru`. This is explicit in the verb definition — if `effectiveness` is absent, the engine does not attempt the strength comparison.

**Spatial consequences** of successful interactions (where does the pushed object end up? what if it hits something?) are deferred to a follow-up brainstorm. For this pass, the verb scoring system determines what the animal ATTEMPTS; the world response is a simple stub.

### How animals choose a verb

When an animal arrives at a target (PERFORMING state), the AI scores each verb from its species definition:

```
verb_score = verb.desire_affinities[animal_highest_deficit] * can_physically_do_it
```

Highest-scoring verb wins. A frustrated hungry cat near a light tuna can scores `knock_off` or `bat` high. A curious ferret scores `drag`. A cold dog near a sleeping cat scores `sit_on`. The desire system provides motivation; the verb model provides the action; mass + strength determine the outcome.

### Animation mapping

The verb id is used as the animation state name. The sprite resolver looks for `{variant}_{verb_id}_strip*.png`. If no sprite exists for that verb, falls back to idle. Each species has its own sprites — a cat's `push` and a turtle's `push` both resolve via the same convention but use different art.

---

## Minimal Mod Loader

### Architecture

```
engine/
  mod/
    mod_loader.gd          # Discovery, sorting, orchestration
    mod_manifest.gd        # Parses mod.json, derives ID, validates
    entity_def_registry.gd  # Stores ALL entity definitions (species + objects), spawn()
    sprite_resolver.gd     # Scans sprites/, matches convention, validates required anims
    verb_resolver.gd       # Scores verbs from species definition against target, physics checks
```

All `RefCounted`, no nodes — per Pure Core pattern.

### Load sequence

```
game_server._ready()
  -> ModLoader.load_all("res://mods/")
    -> scan for mod.json files
    -> sort: three-lane ordering (first/default/last), alphabetical within lane
    -> for each mod:
      -> ModManifest.parse(mod.json) — derive id, validate required fields
      -> scan species/*.jsonc -> EntityDefRegistry.register(namespaced_id, definition)
      -> scan objects/*.jsonc -> EntityDefRegistry.register(namespaced_id, definition)
      -> SpriteResolver.scan(mod_path + "/sprites/", variants, animations)
      -> SpriteResolver.validate_required(entity_definition)
      -> sound scan (same pattern as sprites)
```

### EntityDefRegistry API

```gdscript
class_name EntityDefRegistry extends RefCounted

# Registration (called by loader)
func register(entity_id: StringName, definition: Dictionary) -> void

# Lookup
func has_entity(entity_id: StringName) -> bool
func get_definition(entity_id: StringName) -> Dictionary
func get_all_entities() -> Array[StringName]
func get_states(entity_id: StringName) -> Dictionary
func get_initial_state(entity_id: StringName) -> StringName

# Agency queries
func has_traversal(entity_id: StringName) -> bool  # "does this entity move and evaluate ads?"
func has_desires(entity_id: StringName) -> bool     # "does this entity want things?" (component setup)
func get_traversal(entity_id: StringName) -> Array[StringName]
func get_desires(entity_id: StringName) -> Dictionary

# Replaces the inline db.set_component() blocks in game_server.gd
func spawn(entity_id: StringName, db: GameStateDB, overrides: Dictionary = {}) -> int:
    # 1. Read entity definition
    # 2. If has personality_ranges: randomize desires within bounds
    # 3. If has variants: pick a random variant
    # 4. Resolve sprites via SpriteResolver
    # 5. Create entity, set all components from definition
    # 6. Return entity ID
```

### VerbResolver API

```gdscript
class_name VerbResolver extends RefCounted

# Called by AI when animal arrives at target in PERFORMING state
func score_verbs(actor_id: int, target_id: int, db: GameStateDB,
        entity_defs: EntityDefRegistry) -> StringName:
    # 1. Read actor's verb definitions from species JSON via entity_defs
    # 2. For each verb:
    #    a. Check physics: actor.strength * verb.effectiveness / 1000 > target.mass
    #    b. Score: verb.desire_affinities matched against actor's highest desire deficit
    # 3. Return highest-scoring verb that passes physics check
    # Returns &"" if no verb passes (animal gives up)

func can_perform(verb_id: StringName, actor_id: int, target_id: int,
        db: GameStateDB, entity_defs: EntityDefRegistry) -> bool:
    # Single verb physics check
```

### What gets deleted from existing code

| File | What's removed | What replaces it |
|---|---|---|
| `nodes/game_server.gd` | ~60 lines of inline `db.set_component()` per animal, `_pick_ambient_state()` species branching, `is_cat` string matching | `entity_def_registry.spawn()` calls, state lookup from entity definition |
| `engine/navigation/species_astar.gd` | `const SPECIES_CAPABILITIES` hardcoded Dictionary | `entity_def_registry.get_traversal()` |
| `engine/objects/object_state_manager.gd` | `const OBJECT_CONFIG` hardcoded Dictionary | `entity_def_registry.get_definition()` |

**Test migration:** ~19 references to `tcp_base:cat` and `tcp_base:ferret` across 8 test files (`test_species_astar.gd`, `test_desire_resolver.gd`, `test_runtime_smoke.gd`, `test_ferret_curiosity.gd`, `test_performing.gd`, `test_desire_scatter.gd`, `test_tick_loop.gd`, `test_ferret_soak.gd`) must be updated to `tcp_cats:cat` and `tcp_ferrets:ferret`. Tests should register species via `EntityDefRegistry` rather than depending on mod directory structure — this makes tests independent of which mods are installed.

---

## Curiosity Tracker Genericization

`engine/animals/curiosity_tracker.gd` is currently ferret-specific. It maintains a per-entity novelty map — which cells/objects has this entity visited? Novelty decays. High novelty = high curiosity satisfaction.

### Change

Rename `CuriosityTracker` -> `NoveltySystem`. Remove the ferret species check. The system runs for ANY entity with a non-zero `curiosity` desire weight, which it reads from the entity definition via `EntityDefRegistry`.

The ferret species JSON declares `"curiosity": 900`. A cat JSON could declare `"curiosity": 200` (mildly curious). A guinea pig JSON could declare `"curiosity": 700`. The engine code is identical for all of them — the species data controls the intensity.

This is one small refactor: same logic, remove the species gate, key off desire weight instead.

---

## Updates to Existing Specs

### animal-ai.md — Aversions section

The Aversions (Signed Advertisements) section landed in the `claude/cat-resource-graph-8SgHO` PR needs updating to reflect the signed-desires model:

- Remove the separate `aversions` dictionary from species config
- Remove the "name by desired state" convention (`quiet` -> `noise`, `unchased` -> `chased`)
- Merge into a single `desires` dictionary with -1000 to 1000 range
- Simplify `score_for()` — the sign branch still exists but uses one dictionary, not two
- Rename `desire_type` to `type` in the advertisement schema

### modding.md

- Add species JSON schema reference
- Add object JSON schema reference
- Document the state/advertisement pattern shared by both
- Note that `mod.json.lock` is designed but not yet implemented

---

## Testing Strategy

1. **Unit: mod_manifest.gd** — ID derivation from title, required field validation, malformed JSON handling.
2. **Unit: entity_def_registry.gd** — register, lookup, spawn with personality randomization within ranges, missing entity assertion. Verify that entities with `desires` are treated as animals and entities without are treated as objects.
3. **Unit: verb_resolver.gd** — physics check (`strength * effectiveness > mass`), verb scoring against desire deficits from species definition, no-verb-passes returns empty.
4. **Unit: sprite_resolver.gd** — convention matching, required animation validation errors, frame count parsing from filename, missing variant handling.
5. **Integration: full load sequence** — `ModLoader.load_all()` loads all three mods, entities and verbs are registered, spawn produces entities with correct components.
6. **Integration: mod removal** — remove `mods/tcp_cats/` directory, game starts with ferrets and tuna only, no errors.
7. **Scenario: cross-mod desire matching** — ferret with `food: 700` moves toward opened tuna can from `tcp_tuna` that advertises `food: 800`. No cross-mod reference needed.
8. **Scenario: animal-as-advertiser** — sleeping cat advertises `warmth: 400`, nearby cold cat moves toward it. Pile behavior from advertisements alone.
9. **Scenario: physical interaction** — cat with `strength: 3000` bats tuna can with `mass: 400` (succeeds). Cat attempts to push server with `mass: 50000` (fails, plays confused-idle). Verb scoring selects `bat` over `push` when cat's highest deficit is stimulation.

---

## Open Questions (documented, not blocking)

1. **Kitten as separate species or variant?** Kittens have different sprites (32x32 vs 40x40), different sizes, different behaviors (pounce, tangle cables). Are they `tcp_cats:kitten` (a separate species in the cat mod) or a lifecycle stage of `tcp_cats:cat`? Leaning toward separate species in the same mod for simplicity.
2. **Object sprites don't follow the variant/state convention.** Objects have one sprite per state, named directly in the JSON (`"sprite": "tuna_can_closed.png"`). This is intentionally different from the species convention — objects don't have visual variants (yet). If variant objects are needed later (e.g. tuna brands), the convention can expand.
3. **Engine-defined registries.** The loader needs to know valid animation states, valid triggers, valid traversal types. Where does this master list live? Probably `engine/mod/engine_schema.jsonc` that documents the engine's API surface for modders.
4. **Spawn conditions.** Species JSON has no field for when animals arrive ("Terry Pratchett logic" — get enough warmth in one room and cats show up). Needs a data-driven expression eventually, but fine to defer.
5. **Non-monotonic desire responses.** A dog comforted by moderate noise but bothered by extreme noise can't be expressed with a flat weight. Response curves (already in `animal-ai.md`) will need to layer on top of the signed desire weight eventually. Not blocking.
