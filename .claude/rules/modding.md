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

Related spec: `docs/superpowers/specs/2026-04-16-component-mindset-refactor-design.md`.
Capability-namespace convention: `docs/superpowers/specs/2026-04-10-mod-extraction-design.md`.
