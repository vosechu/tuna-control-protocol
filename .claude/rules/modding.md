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
  "schema_version": 2,
  "id": "tcp_base:starter",
  "entities": [
    { "type": "tcp_base:hum_device", "rack": 0, "slot": 9, "ref_name": "hum_a" },
    { "type": "tcp_base:tuna_dispenser", "rack": 2, "slot": 8, "ref_name": "tuna_a" },
    { "type": "tcp_cats:cat", "floor_rack": 1, "floor_slot_offset": 0, "required": false }
  ]
}
```

- **Placement:** `{rack, slot}` for rack entities, `{floor_rack, floor_slot_offset}` for floor entities. Structured objects only — no in-band string DSL.
- **`ref_name`:** optional symbolic label so later entries can cross-reference this entity within the scenario (e.g. `settled_in_ref`).
- **`required`:** defaults to `true`. A missing type on a required entry aborts the whole population with `push_error`. Optional entries are silently skipped when their type isn't registered — this is how third-party species mods contribute starter animals without hard-coding tcp_base's file.
- **Load ordering:** scenarios are applied *after* every mod has registered its entity types. A scenario referencing `tcp_cats:cat` requires `tcp_cats` to be loaded.
- **Idempotency:** the save root stores `starter_scenario_applied: true` after population. `WorldInitSystem` checks the flag, not save presence — reloads, desync recoveries, and MP resyncs never double-populate.

Mods override by offering an alternative scenario and asking players to swap `settings.starter_scenario_id`, not by shadowing another mod's file.

## Object Recipes

Object content splits between an engine-side `OBJECT_CONFIG` const (state machines) and per-mod JSON under `mods/<mod_id>/objects/` (stateless device recipes). Some shadow JSON exists today (e.g. `tuna_can.jsonc`) but is non-binding. See `objects.md` §"Where to put what" for the authoritative routing rule before adding a new object.

## Capability Components

The framework branches on components, not species labels. These are the capability tags defined today:

| Tag | Shape | Purpose |
|---|---|---|
| `&"tends_servers"` | `{}` | Entity contributes to reclamation when near a server. |
| `&"hum_receiver"` | `{radius_px: int}` | Entity listens on the `&"purr"` channel within its radius. |
| `&"purr"` | `{intensity: int, radius_px: int}` | Entity emits on the purr channel — per-tick strength + reach written by `SensoryEmissionSystem`. |
| `&"sensory_emissions"` | `{<output_name>: {trigger?, base_intensity, modifiers, base_radius_ru}}` | Recipe-declared emission inputs read by `SensoryEmissionSystem` each tick. See "Sensory Emission vocabulary" below. |

Mechanics and invariants live in each subsystem's rule file (see `hum-cable-system.md`, `growth-system.md`). Adding a new capability is a narrow, first-use declaration; promote to a broader name only when a second system needs the same check. The cable subsystem (`hum_powered`, `hum_cable`, `cable_to` scenario field) is currently absent; the restoration design lives at `docs/superpowers/specs/2026-05-09-cables-restoration-design.md`.

## Sensory Emission vocabulary

The `SensoryEmissionSystem` reads recipe-declared emissions and writes per-output components (today: `purr`). Modders pick from a bounded engine-defined vocabulary; you cannot add new ops or falloff curves via JSON.

**Design split (load-bearing).** The recipe declares **what the entity knows about itself** — that it's contented, that stress dampens its output, that it produces purr at a certain loudness. The recipe does **not** declare its channel or its falloff curve — those are properties of *the channel*, not *the cat*, and live in `config/balance/sensory_outputs.jsonc` (mod-patchable). When a tuning fork ships a `ring` output sharing the `acoustic` channel, the recipe declares `ring` and the global config maps it to `acoustic`; falloff is shared because the physics is shared. If you find yourself adding `falloff` or `channel` to a species recipe, stop — you've crossed the split.

### Modifier ops

| Op | Effect on intensity |
|---|---|
| `factor` | `intensity * value / 1000` (multiplicative) |
| `inverse_factor` | `intensity * (1000 - value) / 1000` (dampener) |

Both ops are commutative against each other; order doesn't matter for mixed `factor`/`inverse_factor` modifiers. When non-commutative ops land (forecast: `additive`, `subtractive`), set explicit `priority` to control composition order.

### Falloff curves (channel-level, forward-compat metadata today)

| Falloff | Shape |
|---|---|
| `quadratic` | `(1 - dist/radius)²` |
| `linear` | `1 - dist/radius` |
| `step` | `1` inside radius, `0` outside |
| `inverse_square` | `1 / (1 + (dist/radius)²)` |

These match `DesireScatter._apply_falloff`. No consumer reads channel falloff for sensory emissions today; HUM reads `purr.intensity` directly.

### Value-source forms

`base_intensity` and `base_radius_ru` accept either form:

```jsonc
// Int literal (typical):
"base_intensity": 1000

// Component-field ref (forward-compat, for per-instance variation):
"base_intensity": { "component": "purr_quality", "field": "rate" }
```

A "loud purr" trait mod would declare a `purr_quality: {rate: int}` component on its species recipe and use the ref form.

### Modifier shape

Each entry in the `modifiers` array:

```jsonc
{
  "id":        "tcp_stress_writer:dampening",  // mod-namespaced; required for _remove targetability
  "component": "stress",
  "field":     "level",
  "op":        "inverse_factor",
  "priority":  0                                // optional; default 0; lower applies first
}
```

### Channel registry

`config/balance/sensory_outputs.jsonc` declares `outputs` (output_name → channel) and `channels` (channel → falloff). Recipes can only reference output names registered there. Mods extend the registry through standard config-layering; the schema validator rejects recipes that reference unknown outputs or channels.

### Validator rejection contract

`SensoryEmissionsSchemaValidator` runs at mod load (after config layering completes — cross-mod patches must be visible before validation). Each rule below is a `push_error` that rejects the recipe; one assertion per rule lives in `tests/unit/test_sensory_emissions_schema_validator.gd`.

**Per-emission entry rules:**

1. `base_intensity` required; must be int OR `{component, field}` ref dict.
2. `base_radius_ru` required; same forms as `base_intensity`.
3. `trigger` is optional. If present, must be a dict with `component` (string), `field` (string), `equals` (int).
4. `modifiers` required (may be `[]`); must be an Array.
5. Each modifier dict must have `id` (mod-namespaced string), `component` (string), `field` (string), `op` (string).
6. Each modifier's `op` must be in the engine's known set (today: `factor`, `inverse_factor`). Error message lists the known set so the modder can pick a valid one without grepping engine source.
7. Each modifier's `priority` (if present) must be an int.
8. Modifier `id`s must be unique within an emission. Cross-emission duplicates are allowed.
9. Each emission's output_name (the dict key) must exist in the `outputs` global config.
10. Ref-form value sources (`{component, field}`) must have string `component` and string `field`; non-string types are rejected.

**Cross-referenced (against `sensory_outputs.jsonc`):**
- Each `outputs.<name>.channel` must reference a name in `channels`.
- Each `channels.<name>.falloff` must be in the engine's known set (today: `quadratic`, `linear`, `step`, `inverse_square`).

**Warn-not-error: unresolved component refs.** If a `trigger.component`, modifier `component`, or value-source `component` doesn't resolve to any component declared by the recipe or known to the engine, the validator emits `push_warning` — not `push_error`. Conditionally-present components are a valid pattern (e.g. a stress modifier that only matters when another mod ships the stress writer); rejecting unresolved refs would break cross-mod composition. Typos still surface as warnings at load. Don't "tighten" this to an error without ripping out the cross-mod-composition affordance.

### Runtime failure semantics

Recipe-author-facing behaviors of the runner. The validator catches malformed recipes at load; these rules cover what happens when a recipe is well-formed but references a component absent at *runtime* (a conditionally-present component, a forward reference to another mod's writer, a component the entity hasn't gained yet):

| Situation | Result |
|---|---|
| `trigger.component` not on entity | Trigger fails. `intensity = 0`, `radius_px = 0`. Both fields written each tick — never left stale. |
| `trigger` field/value mismatch | Same as above. |
| Modifier `component` not on entity | Modifier is identity (skipped). Lets recipes declare modifiers for conditionally-present components without the entity needing them yet. |
| `value_source` ref's component not on entity | `_read_value` reads a default int (zero); design assumes the validator's component-ref warning has already been heeded. |
| Unknown modifier `op` | `push_error` + identity. The validator should have rejected this at mod load; runtime error means a mod was patched in without revalidation. |
| Unknown `value_source.kind` | `push_error` + 0. Same source — validator should have caught. |
| Modifier drives intensity negative | Clamped to 0 floor. `radius_px` follows (also 0). |

The "absent component → identity" rule is the design's load-bearing affordance for cross-mod composition. A recipe declaring `inverse_factor stress` works correctly whether the stress writer mod is loaded or not.

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
| `schema_version` | int | Recipe schema version. Current: `4`. Older versions may be tolerated by the loader (see migration notes) but new recipes must use the latest. |
| `id` | `"mod_id:entity_id"` | Namespaced species identifier |
| `name` | string | Display name |
| `desires` | `{channel: {weight: int, decay: int}}` | Per-channel desire spec. `weight` is personality strength (0–1000); `decay` is per-tick passive decay and **must be ≤ 0** (decay-only mechanic). Use `decay: 0` for channels with no passive decay. |
| `body_capabilities` | object | Capability components (`walks`, `jumps`, `drops`, …). `walks.speed_px_per_tick` is required when `walks` is present. |
| `body_geometry` | object | Physical dimensions (`size_ru`, etc.). |
| `senses` | `{sight: int, hearing: int, smell: int, touch: int}` | Perception acuity per channel. |
| `sprite_config` | object | `base_path` (with optional `{variant}`), `offset_y`, `animations` (state→key), `animation_frames` (key→strip+frames+fps) |
| `ambient_states` | object | `warm` and `cold` arrays of `{state, weight, min_duration_ticks}` entries. `min_duration_ticks` is required on every entry. |
| `special_states` | `{STATE_NAME: {min_duration_ticks: int}}` | Required when `ambient_states` is present. Declares non-pool states (e.g. `STARTLED`) that the AI can enter and how long they pin the entity. |
| `hud_color` | `[r, g, b]` | Floats 0.0–1.0 for name labels |

Optional fields: `starters`, `personality_ranges`, `verbs`, `states`, `tends_servers` (tag capability), `role_tags` (designer summary), `sensory_emissions` (recipe-declared emission inputs — see vocabulary section above).

### v3 → v4 migration

Schema v4 (recipe-driven balance) tightened the desires shape and required new explicit fields. The full migration list:

1. **Desires are now objects, not bare ints.** Replace `"warmth": 500` with `"warmth": {"weight": 500, "decay": 0}`. Decay must be `<= 0` — positive values are rejected. Use `0` for "no passive decay."
2. **`body_capabilities.walks.speed_px_per_tick` is required** when `walks` is declared. The legacy hardcoded default no longer exists.
3. **`ambient_states` entries require `min_duration_ticks`.** Every entry in `warm` and `cold` arrays must declare how long the entity stays in the chosen state.
4. **`special_states` is required when `ambient_states` is declared.** Provide each non-pool state's `min_duration_ticks`. The base recipes ship `STARTLED: {min_duration_ticks: 10}`.
5. **Bump `schema_version` to `4`** to signal the migration.

The loader still tolerates v3 bare-int desires entries during the transition (treated as `{weight: <int>, decay: 0}`), but `SpeciesSchemaValidator` rejects them. Update recipes to v4 — the fallback exists only so a missed mod doesn't take the boot down.

Canonical example: `mods/tcp_cats/species/cat.jsonc`.

Loading: `SpeciesSchemaValidator` (in `engine/mod/`) runs at mod load and rejects recipes missing any required field via `push_error`. Malformed recipes do not register as species. The validator collects every violation in a recipe and emits them as a single grouped error so modders fixing a recipe don't need a reload cycle per problem.

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

## Common slip patterns

| Slip | Why it bites | Fix |
|---|---|---|
| Hand-writing a mod ID in `mod.json` | IDs are derived from `title` via `derive_mod_id()`. A hand-written `id` field will diverge from the derived value silently. | Don't add an `id` field. Set `title`; the loader derives the ID. |
| Adding `depends:` / `load_after:` / `tcp_engine` to `mod.json` | Manual ordering doesn't exist. Dependencies are auto-detected by `ModAnalyzer` from referenced IDs. | Reference the other mod's namespaced IDs in your config; the analyzer picks up the dependency. |
| Providing a "default" for a missing required field in a recipe to avoid validation errors | Silent defaults produce mysterious behavior modders can't trace. Schema validators are the only contract that points modders at the line to fix. | Let validators `push_error` + skip. Add the required field to the recipe. |
| Removing unused `verbs` blocks because "verbs aren't wired yet" | Verbs are forward-compatible config. The scoring infrastructure is in place; the action loop will consume them when shipped. Removed verbs need to be re-derived later from playtesting. | Leave verbs declared. |
| Branching engine code on species labels (`if species == "cat"`, hardcoded `&"tcp_cats:cat"`) | `script/checks/no_species_dispatch` blocks this in `engine/` and `nodes/` — the regression guard exists because every species branch is a step toward a non-moddable engine. | Add a capability tag to the recipe and branch on `has_component`. |
