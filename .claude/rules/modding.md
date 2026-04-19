---
paths:
  - "mods/**"
  - "engine/mod/**"
---

# TCP Modding Architecture Rules

## Base Game Is a Mod — Day One, Not Later
`tcp_base` ships as a mod. The engine is a framework. If it can't be done via mod API, the framework needs work. This is not aspirational — it is a hard constraint from the first line of code, same as networking. The mod loading pipeline, config merging, and namespaced IDs must work before any game content exists. Every system is tested through the mod API, never through backdoor engine access.

## Mod Manifest
`mod.json` has: `title` (required), `version` (required), `author` (required), `description`, `tags`, `load_priority` ("first"/"last"/default), `previous_titles` (for renames). No `id`, `depends`, `load_after`, or `tcp_engine` fields.

## Mod IDs
Auto-derived from title via `derive_mod_id()`: ASCII, lowercase, non-alphanumeric -> `_`, collapse, strip, truncate 48. Never hand-written.

## Namespaced Entity IDs
All entities prefixed with mod ID: `fluffy_ferret_friends:arctic_ferret`. All `snake_case`. Local part starts with letter.

## Dependencies
Auto-detected by `ModAnalyzer` scanner. No manual declarations. Scanner reads namespaced IDs, schema versions, config paths, API calls. Produces `mod.lock`.

## Load Ordering
Three lanes (first/default/last). Within each lane: topological sort by auto-detected dependencies. Ties broken alphabetically. No manual ordering. Players never see load order.

## Config Schema Versioning
Every config file type (species, objects, behaviors, infrastructure) includes a `"schema_version": 1` field. Schema changes require migration functions, same as save files. Adding versioning now is trivial; adding it later requires touching every existing file.

## No magic defaults
Required fields must be declared in every recipe. A missing field is a validation error at mod load time, not a silent fallback to some engine-side default. Silent defaults produce mysterious behavior for mod authors who don't know the value exists; explicit errors point at the exact line to fix. Schema validators (`SpeciesSchemaValidator`, `ScenarioSchemaValidator`, etc.) own this check and must `push_error` + skip, not paper over the gap.

## Config Layering
Deep merge per-key. Later mods override earlier. `user://config/` always wins. To delete a key, set to `null`. ConfigRegistry produces frozen immutable dictionary.

### Array merge strategy
Arrays in config **concatenate by default** (KSP Module Manager model). Two mods adding `drain_sources` to the same object both append — no conflict. To remove an entry added by another mod, use an entry with `"_remove": "entry_id"`. To replace an entire array, use `"_replace": [...]`.

### Relative value operations (deferred — design now, implement before config loader)
Mods should be able to say "make boxes 20% weaker" without knowing the absolute value. Planned operations on int-scale values:
- `"field_name": {"_add": 100}` — add 100 to existing value
- `"field_name": {"_mul": 800}` — multiply by 0.8 (800/1000)
- `"field_name": 500` — absolute set (current behavior, last writer wins)

### Conditional application (deferred — design now, implement before config loader)
Patches that should only apply when another mod is present need a `:NEEDS` equivalent. Planned: `"_needs": ["mod_id"]` at config root or per-entry level.

## Rename Redirects
Old titles in `previous_titles` array. Redirects registered at load time. Save files migrated. Append-only.

## Scenarios

Scenarios live per-mod under `mods/<mod_id>/scenarios/<id>.jsonc`. On a fresh game, `WorldInitSystem` applies the scenario identified by `settings.starter_scenario_id` (default `&"tcp_base:starter"`). A scenario lists entity refs — type + placement — that populate a new world without hand-placed saves.

```jsonc
{
  "schema_version": 1,
  "id": "tcp_base:starter",
  "entities": [
    { "type": "tcp_base:hum_device", "rack": 0, "slot": 0, "ref_name": "hum_a" },
    {
      "type": "tcp_base:tuna_dispenser", "rack": 2, "slot": 1,
      "cable_to": { "ref_name": "hum_a" }
    },
    { "type": "tcp_cats:cat", "rack": 0, "slot": 7, "required": false }
  ]
}
```

- **Placement:** `{rack, slot}` for rack entities, `{floor_rack, floor_slot_offset}` for floor entities. Structured objects only — no in-band string DSL.
- **`ref_name`:** optional symbolic label so later entries can cross-reference this entity within the scenario.
- **`cable_to: { ref_name }`:** writes a `hum_cable` component on the spawned entity pointing at the named HUM. Links resolve in a deferred pass after every entry has spawned, so forward references work.
- **`required`:** defaults to `true`. A missing type on a required entry aborts the whole population with `push_error`. Optional entries are silently skipped when their type isn't registered — this is how third-party species mods contribute starter animals without hard-coding tcp_base's file.
- **Load ordering:** scenarios are applied *after* every mod has registered its entity types. A scenario referencing `tcp_cats:cat` requires `tcp_cats` to be loaded.
- **Idempotency:** the save root stores `starter_scenario_applied: true` after population. `WorldInitSystem` checks the flag, not save presence — reloads, desync recoveries, and MP resyncs never double-populate.

Mods override by offering an alternative scenario and asking players to swap `settings.starter_scenario_id`, not by shadowing another mod's file.

## Capability Components

The framework branches on components, not species labels. These are the capability tags defined today:

| Tag | Shape | Purpose |
|---|---|---|
| `&"tends_servers"` | `{}` | Entity contributes to reclamation when near a server. |
| `&"hum_powered"` | `{}` | Device needs a `hum_cable` to operate. |
| `&"hum_cable"` | `{hum_id: int}` | Device is currently cabled to this HUM. `Constants.INVALID_ID` when unplugged. |
| `&"hum_receiver"` | `{radius_px: int}` | Entity listens on the `&"purr"` channel within its radius. |
| `&"purr"` | `{intensity: int}` | Entity emits on the purr channel at this per-tick strength. |
| `&"purr_config"` | `{rate_when_satisfied: int}` | Recipe-level rate used by the contentment→purr bridge. |

Mechanics and invariants live in each subsystem's rule file (see `hum-cable-system.md`, `growth-system.md`). Adding a new capability is a narrow, first-use declaration; promote to a broader name only when a second system needs the same check.

---

## Reference: Observable State

```gdscript
game_state.watch("position", func(entity_id: int) -> void:
    var pos := game_state.get_component(entity_id, "position")
    # react
)
```

Available: entity position/behavior/desires/happiness, infrastructure state (heat, connectivity, occupancy), economy totals (population, IOPS), event bus signals.

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

Optional fields: `starters`, `personality_ranges`, `verbs`, `states`, `tends_servers` (tag capability), `role_tags` (designer summary).

Canonical example: `mods/tcp_cats/species/cat.jsonc`.

Loading: `SpeciesSchemaValidator` (in `engine/mod/`) runs at mod load and rejects recipes missing any required field via `push_error`. Malformed recipes do not register as species.

Regression guard: `script/checks/no_species_dispatch` runs in `script/validate` and the pre-commit hook. It flags `String(...species...).contains("cat")` / `contains("ferret")` patterns and hardcoded `&"tcp_cats:cat"` / `&"tcp_ferrets:ferret"` literals in `engine/` and `nodes/`. Exempt: `tests/`, log-string contexts, the species-label field itself. If a check fails, add a capability to the recipe instead of branching on the species label.

## Verbs (Physical Interactions)

Verbs are how one entity *acts on* another — push, bat, drag, knock_off, sit_on, etc. Each species recipe declares which verbs it knows and how well it performs each. Physics gates which verbs actually fire; desire weights score which one is chosen. There is no hardcoded list of verbs or "can_X" affordance booleans on objects — if the physics checks pass, the verb works.

### Recipe schema

```jsonc
"verbs": {
  "push":      { "effectiveness": 1000, "desire_affinities": { "curiosity": 500 } },
  "bat":       { "effectiveness": 500,  "desire_affinities": { "curiosity": 600 } },
  "drag":      { "effectiveness": 700,  "desire_affinities": { "curiosity": 800 } },
  "knock_off": { "effectiveness": 2000, "desire_affinities": { "curiosity": 900 } },
  "sit_on":    {                         "desire_affinities": { "comfort": 700, "warmth": 200 } }
}
```

Each verb has:
- `effectiveness` (optional): how much "force" the actor applies when performing this verb, in thousandths. Omitting it falls back to a size comparison on `physical.size_ru`.
- `desire_affinities`: which desires this verb satisfies, and how strongly. Used for scoring.

### Physics gate

```
actor.strength * verb.effectiveness / 1000  >  target.physical.mass   →   verb passes
```

Actor strength lives in `species.strength` (int). Target mass lives in `object_type`/`species` recipe's `physical.mass` block. If either value is missing, the verb cannot be resolved and is skipped. `VerbResolver.can_perform(verb_id, actor_id, target_id)` is the public entry point.

### Scoring

`VerbResolver.score_verbs(actor_id, target_id)` iterates the actor's declared verbs, filters by the physics gate, then scores each passing verb as:

```
score = sum over d in verb.desire_affinities:
          actor.desires[d] * affinity / 1000
```

The highest-scoring verb wins. Ties break in dictionary iteration order. An actor with no declared verbs, or whose verbs all fail the physics gate, returns an empty StringName.

### Current integration state

`VerbResolver` is built, unit-tested, and instantiated on `GameServer`. It is **not yet wired to the action loop** — no tick code calls `score_verbs` on arrival at a target. Verbs are a latent capability waiting for the next generation of action mechanics. Mod authors declaring verbs today are writing forward-compatible config; the scoring will start mattering when the action-dispatch layer ships.

Do not remove unused verbs from recipes. Do not add affordance booleans to objects "until verbs are ready" — the scoring infrastructure already works.
