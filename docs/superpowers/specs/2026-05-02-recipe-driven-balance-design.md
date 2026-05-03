# Recipe-Driven Balance: Decay, Durations, Speed

**Date:** 2026-05-02
**Status:** Design draft
**Supersedes:** Parts of `2026-04-06-game-server-extraction-design.md` — see "Old spec cleanup"
**Sister mechanic (shipped):** the perception-channels work landed in PR #14 — `senses` block, `Constants.CHANNELS` registry, `effect_radius_px` / `effect_slot`, and aversion-via-effect-direction. Permanent docs: `.claude/rules/animal-ai.md` (senses, aversions, scoring) and `.claude/rules/objects.md` (advertisement schema).

## Coordination with the (now-shipped) perception-channels work

The perception-channels migration shipped in PR #14 (2026-05-03):

- Species recipes carry a `senses: {sight, hearing, smell, touch}` block (cap default `BAY_WIDTH_PX`).
- Ads use `channel`, `effect_radius_px` (radius delivery) or `effect_slot: true` (slot delivery), default `falloff: quadratic`.
- `Constants.CHANNELS` registry maps each channel to `{sense, desire, effect}`. Aversion is `effect: deplete`; receiver desires are all-positive (`quiet`, `peace` are dedicated rest desires).

This spec **does not** add a `senses` block, change perception radius, modify ad scoring/scatter shapes, or rename desire keys on its own. An earlier draft of this spec proposed a single `senses.radius_px` field; that's superseded by the per-sense design now permanent in `animal-ai.md`.

**Schema_version arithmetic.** Species recipes shipped post-PR #14 at `schema_version: 3`. Phase 2 of this spec bumps species recipes to `4`. Object recipes are unaffected (no `desires`).

**Validator coordination.** `SpeciesSchemaValidator` already enforces perception-channels' rules (`senses` block when desires present, `effect_slot: true` only on slot-anchored entities). Phase 2 of this spec adds: `desire_decay` (when desires present), per-entry `min_duration_ticks` on ambient_states, `special_states` (when ambient_states present), and `body_capabilities.walks.speed_px_per_tick` (when walks present). The grouped-error reporting documented at §"Component Materialization" merges all violations into one `push_error` call per recipe.

What this spec **does** cover (orthogonal to perception):

1. Per-recipe desire decay rates (replaces global `add_all` decay sweep).
2. Inline `min_duration_ticks` on each `ambient_states` entry (replaces engine-side `_min_durations` dict).
3. `special_states.STARTLED.min_duration_ticks` for event-triggered states.
4. `body_capabilities.walks.speed_px_per_tick` (replaces `ANIMAL_SPEED_PX` constant).
5. Extracting `_move_animals` and `_update_ambient_states` into pure-core systems.
6. The shared `BehaviorTimers` struct for cross-system state-timer dicts.
7. Promoting four food-finder helpers from `GameServer` private to `FoodSystem` public.

## Goal

Move three sets of balance numbers from hardcoded engine constants into per-recipe JSONC blocks, and extract the two pieces of inline logic in `nodes/game_server.gd` that consume them once recipes drive the values.

## Why

Today's engine has balance numbers that violate two project rules:

| Number | Location | What's wrong |
|---|---|---|
| `add_all(&"desires", &"comfort", -5)` etc. | `game_server.gd:165–173` | Config Is Not Code (`design-philosophy.md`); also "species are component recipes" — same rate applies to every entity regardless of recipe |
| `_min_durations: Dictionary` | `game_server.gd:29–36` | Same; six float-second durations baked into engine code |
| `ANIMAL_SPEED_PX = 2` | `game_server.gd:3` | Same; one walking speed for every animal that ever exists |

These aren't "balance numbers in code" in the abstract — they're *recipe-level properties* (a dog smells further than a cat; a kitten walks slower than an adult; a mechanical arm decays no desires) wedged into engine-level constants because the recipe schema didn't have homes for them.

The decay sweep is especially structurally wrong: `db.add_all(&"desires", &"comfort", -5)` applies to every entity carrying the `desires` column, with no way to express "this kind of entity decays differently" or "this kind of entity doesn't decay this channel at all."

## Scope

**In scope:**

1. Recipe schema additions: `desire_decay`, inline `min_duration_ticks` on ambient_states entries, `special_states.<NAME>.min_duration_ticks` for event-triggered states (STARTLED today), `body_capabilities.walks.speed_px_per_tick`. Species recipes bump from `schema_version: 3` (post-PR #14) → `4`.
2. Loader changes in `entity_def_registry.gd` to materialize the new fields as components.
3. Schema validator updates in `species_schema_validator.gd` to enforce conditional-required-field rules per `modding.md`'s "no magic defaults" rule, with grouped per-recipe error reporting.
4. Recipe content updates in `mods/tcp_cats/species/cat.jsonc` and `mods/tcp_ferrets/species/ferret.jsonc`.
5. New `BehaviorTimers` RefCounted struct (`engine/animals/behavior_timers.gd`) holding the shared state-timer dicts, owned by `GameServer`, injected into both extracted systems.
6. Promoting four food-finder helpers from `GameServer` private methods to public methods on `FoodSystem`: `find_nearby_food`, `find_nearest_box`, `find_nearest_dispenser`, `mark_nearest_can_eaten`. Required for AiStateSystem to extract cleanly without a GameServer reference.
7. Consumer-side reads:
   - `_scatter_desires` reads per-species decay vectors (in-place change, no extraction).
   - `_move_animals` reads per-entity walking speed **and is extracted into `MovementSystem`** (the unfinished item from the older extraction spec).
   - `_update_ambient_states` reads per-entity min-durations **and is extracted into `AiStateSystem`**.
8. Update integration tests that inline `_move_animals` to call `MovementSystem` directly. Update `tests/integration/test_tick_loop.gd:EXPECTED_ORDER` for the renamed tick entries.
9. Update `2026-04-06-game-server-extraction-design.md` to mark the absorbed scope as superseded.
10. Document the `desires`-implies-`species` contract in `.claude/rules/animal-ai.md`.
11. Document the v2→v3 schema delta and the place_object two-track interim policy in `.claude/rules/modding.md`.

**Out of scope:**

- **Senses, perception radius, channel→sense mapping, ad scoring/scatter changes, signed-weight migration.** Shipped in PR #14; permanent docs in `.claude/rules/animal-ai.md` and `.claude/rules/objects.md`.
- `place_object` → `entity_defs.spawn()` migration. Separate Phase 2 spec.
- Writing recipes for `server_1u`, `cardboard_box`, `clothes_pile`. Phase 2 prerequisite.
- Extracting `_scatter_desires` or `_decay_commitment` into separate systems. Both stay in `game_server.gd` for now.
- **Hunger decay restoration.** `desire_decay.hunger` ships at `0` and stays at `0`. This is an intentional balance decision (pacing-cascade noise from non-zero hunger was drowning out other behaviors). When hunger decay does return, it'll be a recipe edit — out of scope for this spec. (Note: shipped recipes still use `hunger` as the desire key. The `Constants.CHANNELS` registry maps the `food` channel to a `food` desire, but cat.jsonc/ferret.jsonc and `cat_food_states.gd` continue to use `hunger` — that desire-key migration is a separate cleanup, not this spec's scope.)
- Per-individual variation (kitten-vs-adult, personality-derived rates). The next expected pass on this surface — flagged here so future work doesn't cement per-recipe as the only granularity.
- Promoting `BehaviorTimers`'s dicts to per-entity components in `GameStateDB`. They remain on `BehaviorTimers` for now; `BehaviorTimers` exists specifically to make that future promotion a one-file change.
- Save migration. No save system exists yet. When one is built, its first migration must synthesize default `desire_decay`/`special_states` from each entity's species_id at load time — the "explode early, no defensive null" stance crashes on save load otherwise. Document this constraint in the future save spec.
- Surfacing validator errors in the in-game UI. Today they go to `push_error` (Godot console). Mod author UX is good enough at the developer level; richer surfacing waits for the in-game mod manager.
- Object recipes adopting these new fields. While `place_object` stays hardcoded, no new tunable on an object goes into `place_object`'s match block — any new object-side balance value must land as a recipe field even if a temporary helper reads it. The two-track interim policy (animals via `entity_defs.spawn()`, objects via hardcoded `place_object`) is documented in `modding.md` as part of phase 2.

## Schema Additions

### 1. Per-type desire decay (co-located with weights)

Required on any recipe that declares `desires`. Recipes without `desires` (arms, dispensers) do not declare decay.

The recipe shape changes: every `desires` entry is now an object with `weight` (required) and `decay` (required) fields, replacing the bare-int `desires.<channel>: 700` shape.

```jsonc
// mods/tcp_cats/species/cat.jsonc
"desires": {
  "warmth":    { "weight": 700, "decay": -2 },
  "comfort":   { "weight": 700, "decay": -5 },
  "curiosity": { "weight": 150, "decay": -3 },
  "hunger":    { "weight": 700, "decay":  0 },   // intentionally disabled — see note below
  "social":    { "weight": 500, "decay": -2 },
  "quiet":     { "weight": 600, "decay":  0 },
  "peace":     { "weight": 500, "decay":  0 },
  "safety":    { "weight": 800, "decay":  0 }
}
```

`weight` is the personality weight (loader still seeds `personality.<channel>_weight` and `personality_ranges` still randomizes around `weight` when present). `decay` is the per-tick passive decay delta — always ≤ 0 (validator rejects values > 0); zero means "no passive decay this tick." `desire_decay` is decay-only as a mechanic; passive recovery, if it ever ships, is a different mechanic with its own field.

**No separate `desire_decay` block.** Earlier drafts of this spec proposed a sibling `desire_decay: {warmth: -2, ...}` block. The co-located shape replaces it: a desire and its decay rate live in the same place, mod authors physically can't add decay for an undeclared channel (because there's nowhere to put it), and the validator's "subset" rule disappears. The runtime side is unchanged — the loader materializes both `personality.<channel>_weight` and the `desire_decay` runtime component (a flat `{channel: int}` dict) from the same recipe block.

**Personality ranges stay a sibling.** `personality_ranges` continues to live as a top-level block keyed by channel (`"personality_ranges": {"warmth": [500, 800], ...}`). Folding ranges into the same dict was considered and dropped to keep the diff focused.

**No magic defaults.** Both `weight` and `decay` are required on every `desires` entry. A `decay: 0` is explicit "this channel does not passively decay" and must be written, not inferred. The validator rejects entries with `weight` missing, `decay` missing, or non-int values.

**Decay channels.** Today's cat decays comfort, curiosity, and social passively; warmth gets a slow drift toward cold; hunger stays at 0 (see below); safety/quiet/peace are reactive (depleted by aversion ads), not passively-decaying. The shipped cat recipe carries all eight desire channels; each entry now carries an explicit decay value (mostly 0 for the non-decaying channels).

**Hunger stays at 0.** The `hunger: 0` value reflects an intentional balance decision — passive hunger decay was causing pacing-cascade noise that drowned out other behaviors. The `_scatter_desires` AI-DEV comment at `game_server.gd:167` describing it as "TEMP" is stale; treat the recipe value as authoritative going forward. When/if hunger decay returns, it returns through a recipe edit (not a code revert), which is exactly the win this whole spec is about.

### 2. Inline ambient-state min durations

Each ambient-state pool entry gains a required `min_duration_ticks`. Tick-based to match the rest of the simulation; no float-seconds drift.

```jsonc
// mods/tcp_cats/species/cat.jsonc
"ambient_states": {
  "warm": [
    { "state": "IDLE",     "weight": 10, "min_duration_ticks": 30  },
    { "state": "GROOMING", "weight": 15, "min_duration_ticks": 100 },
    { "state": "LOAFING",  "weight": 20, "min_duration_ticks": 150 },
    { "state": "SLEEPING", "weight": 25, "min_duration_ticks": 300 }
  ],
  "cold": [
    { "state": "IDLE",     "weight": 10, "min_duration_ticks": 30 },
    { "state": "GROOMING", "weight":  5, "min_duration_ticks": 100 },
    { "state": "LOAFING",  "weight": 10, "min_duration_ticks": 150 }
  ]
}
```

A state appearing in both pools may declare different durations; the active pool's value wins.

### 2b. Special-state durations

STARTLED isn't an ambient state — it's not picked from a weighted pool, it's forced from outside by an event (object removal nearby, future startle triggers). Different selection mechanism, so different recipe block:

```jsonc
// mods/tcp_cats/species/cat.jsonc
"special_states": {
  "STARTLED": { "min_duration_ticks": 10 }
  // future: "RELOCATING", "BEING_CARRIED" slot in here
}
```

Required on any recipe that declares ambient_states (i.e. has any per-state durations at all). Same shape as ambient_states entries — just `{min_duration_ticks: int}` per state, no weight or pool context because special states aren't probabilistically picked.

**Mod author minimum.** A new species recipe needs at minimum:

```jsonc
"special_states": {
  "STARTLED": { "min_duration_ticks": 10 }
}
```

Copy-pasteable. STARTLED is the only currently-triggered special state; future RELOCATING / BEING_CARRIED entries become required when their respective trigger systems ship.

**Triggers stay in code.** This block declares only the *duration* of an event-triggered state — what triggers it lives in the system that owns the trigger. Two trigger paths exist or are planned:

- **Direct (today):** STARTLED is set on entities within proximity of `remove_object` at `game_server.gd:705`. Bypasses the desire pipeline; the special_state is written directly.
- **Channel-derived (future):** the `startle` channel (in `Constants.CHANNELS`) depletes `desires.safety`. A future system could escalate to STARTLED when safety drops past a threshold. Not part of this spec.

Adding a key here doesn't make a state triggerable; the trigger system has to exist.

Today every recipe declares the same STARTLED duration; the value lives per-recipe rather than as an engine constant so a kitten recipe can startle longer than an adult, or an entity with `senses.hearing: 0` can declare `STARTLED.min_duration_ticks: 0` to opt out of startle entirely (the recovery exits on the same tick it enters, so the state is effectively no-op). The engine contains zero tuning.

### 3. Walking speed

```jsonc
// mods/tcp_cats/species/cat.jsonc
"body_capabilities": {
  "walks":  { "speed_px_per_tick": 2 },     // 2 px × 10 Hz tick = 20 px/sec; viewport is 224 px wide
  "jumps":  { "max_height_ru": 4 },
  "drops":  { "max_height_ru": 5 },
  "settles_in_containers": { "max_body_size_ru": 2 }
}
```

Required when `walks` is present. No top-level `locomotion` block — the existing `body_capabilities.walks` is the right home for "how walking works."

### Senses (shipped, owned by animal-ai.md)

The senses block on species recipes — `senses.{sight, hearing, smell, touch}` — shipped in PR #14 and is now documented in `.claude/rules/animal-ai.md` §"Species configuration". This spec doesn't duplicate it.

## Component Materialization

`entity_def_registry.gd:spawn()` already passes `body_capabilities` and `ambient_states` through verbatim, so two of the four additions need zero loader changes — the new sub-fields (`speed_px_per_tick` inside `walks`, `min_duration_ticks` on each ambient entry) ride along on existing components.

The two that need new materialization (~3 lines each):

```gdscript
# Modify spawn()'s existing "Desires + personality" block (~line 150).
# Each entry in def["desires"] is now an object {weight, decay}, not a bare int.
#
# Pseudo-shape of the rewrite:
#   for key, entry in def["desires"]:
#       weight     = entry["weight"]                         # int, was the old bare value
#       decay      = entry["decay"]                          # int, new field, ≤ 0
#       personality[key + "_weight"] = randomize_or_pass(weight, personality_ranges)
#       initial_desires[key] = default_satisfaction(key, overrides)
#       desire_decay[key] = decay
#   db.set_component(id, &"desires", initial_desires)
#   db.set_component(id, &"personality", personality)
#   db.set_component(id, &"desire_decay", desire_decay)   # new: flat {channel: int} runtime dict

if def.has("special_states"):
    var specials: Dictionary = def["special_states"]
    db.set_component(id, &"special_states", _to_stringname_keys(specials))
```

The runtime `desire_decay` component is the same shape as the (now-deleted) sibling-block proposal: `{channel: int}` flat dict. Consumer code in phase 3 reads it identically. Only the recipe-side parse path widens.

`SpeciesSchemaValidator` gets these new conditional required-field checks (perception-channels' rules already shipped; this phase appends to the existing validator and reuses the grouped-error path):

- Every entry in `desires` must be an object (not a bare int) with `weight: int` and `decay: int` fields. Both are required; bare-int entries (the v3 shape) are rejected.
- Every `decay` value must be ≤ 0 (decay-only mechanic).
- If a recipe has `body_capabilities.walks`, that block must declare `speed_px_per_tick`.
- Every `ambient_states.warm[]` and `ambient_states.cold[]` entry must declare `min_duration_ticks`.
- A recipe that declares `ambient_states` must also declare `special_states`, and every `special_states.<NAME>` entry must declare `min_duration_ticks`.

**Grouped errors.** The validator collects all missing-field violations for a single recipe into one `push_error` call rather than firing one per missing field — modders fixing a recipe shouldn't need five reload cycles. Validation failures skip registering the recipe; no silent fallback.

**Schema version bump.** Species recipes are at `schema_version: 3` post-PR #14. Phase 2 of this spec bumps them to `4`. Per `.claude/rules/modding.md`, schema changes need migration functions; today no third-party species mods exist (TCP is pre-release and the only species recipes ship from inside this repo), so no migration code is required at this point. When third-party mods exist, future schema bumps will need migration. Document the v3→v4 delta in `modding.md` as part of phase 2's commit.

**Recipes for entities without `desires`.** Arms, dispensers, buttons, HUM devices, tuna cans don't declare `desires` and therefore don't need `desire_decay`, `ambient_states`, or `special_states`. Their schema_versions stay where they are — no required-field violations apply, no version bump required from this spec.

**Audit before phase 2.** Before phase 2 commits, scan all recipe files (`mods/**/*.jsonc`) for any that declare `desires` to make sure all are updated. The only such recipes are `mods/tcp_cats/species/cat.jsonc` and `mods/tcp_ferrets/species/ferret.jsonc`.

## Consumer Changes

### `_scatter_desires` (in-place, no extraction)

Replace the four global `add_all` calls (lines 165–173) with per-species batched decay using `db.get_entities_by_species`:

```gdscript
# Replaces add_all calls. desire_scatter.scatter_from_ads() and the global
# clamp_all calls (lines 187–191 today) still run after.
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
            continue                           # no-op; skip the inner loop
        db.add_field_subset(entities, &"desires", desire_type, rate)
```

`EntityDefRegistry` gains two query helpers: `has_desire_decay(species_id) -> bool` (returns true iff the species recipe has any `desires` entry with a non-zero `decay`) and `get_desire_decay(species_id) -> Dictionary` (returns the flat `{channel: int}` decay dict materialized at spawn time, or `{}` for species without decay).

**`clamp_all` calls stay as global sweeps.** The clamp_all sweep at lines 176–180 (today) clamps every cell in each desires column to `[0, 1000]` regardless of species. That stays as-is — clamping is a column-friendly safety net with no per-species variation, and replacing it with per-species clamps would lose the packed-array fast path for no benefit.

**`add_field_subset` is a new GameStateDB op.** Per Open Question 1's resolution (decided yes): `GameStateDB.add_field_subset(entity_ids: Array[int], component: StringName, field: StringName, delta: int) -> void` walks the entity_ids and applies the delta to each entity's `component.field`. Lands as part of phase 3, before the consumer rewrite. Wraps the existing single-entity `add_field` path (so dirty marking and watchers fire correctly per entity) but accepts the entity list up front so callers don't need their own loop. ~10 lines.

**Performance.** At ~5 species × 4 channels × ~10 entities, the per-entity loop runs ~200 times per tick versus the four `add_all` calls today. Negligible at prototype scale. The `add_field_subset` wrapper above is a single function-call layer over `add_field` — doesn't speed things up by itself, but gives a single seam to optimize later (column-friendly fast path when the entity_ids are dense in the column).

**Arms don't decay.** An arm has no `desires` block in its recipe, so `entity_defs.has_desire_decay(&"tcp_base:arm")` returns false and the inner loop never runs against arm entities. The current `add_all` sweep would silently apply to any entity that happened to have a desires column; the new path is structurally incapable of writing to entities outside its declared species set.

**`desires` requires `species`.** The new decay loop iterates `db.get_entities_by_species(species_id)`, so any entity with a `desires` component but no `species` component is silently skipped. This was previously not the contract — `add_all` covered every column entry regardless of species. To keep "explode early" honest, add an assertion at the top of the loop body:

```gdscript
# Contract: every entity with desires has a species. Catches scenario bugs
# and test fixtures that wrote desires without going through entity_defs.spawn().
if OS.is_debug_build():
    var with_desires: Array[int] = db.get_entities_with(&"desires")
    var with_species: Array[int] = db.get_entities_with_all([&"desires", &"species"])
    assert(with_desires.size() == with_species.size(),
        "Entity with desires but no species — desire_decay won't apply")
```

Document the contract in `.claude/rules/animal-ai.md`: any entity carrying `desires` must also carry `species`. Test fixtures that violate this should add a stub species or stop adding desires.

### Perception radius (already shipped in PR #14)

The hardcoded `8 * Constants.SLOT_HEIGHT_PX` perception radius was replaced by the perception-channels work: spatial queries bound at `BAY_WIDTH_PX`, per-sense gating happens after the broad-phase query. This spec does not touch that path.

### `_move_animals` → `MovementSystem` (extraction)

Extract the entire **~163-line** method (post cat-jumps-into-box merge; pre-merge it was ~115 lines) into `engine/animals/movement_system.gd`. This is the unfinished item from `2026-04-06-game-server-extraction-design.md`, with two changes from that older design:

1. `MovementSystem.tick()` reads each entity's walking speed from the entity's `body_capabilities.walks.speed_px_per_tick` instead of the engine constant `ANIMAL_SPEED_PX`. The constant is removed from `game_server.gd`.
2. `MovementSystem.tick()` returns `void`, not `Array[int]`. The arrival logic in `_move_animals` is intertwined with the move loop (state-transitions on arrival happen within the same per-entity iteration); separating "arrived IDs" from "arrival handling" creates an awkward two-pass shape. Keep the arrival logic inside the system. The older spec proposed returning arrived IDs to keep movement focused on positions; cost-benefit at prototype scale doesn't justify the split.

```gdscript
class_name MovementSystem extends RefCounted

var _db: GameStateDB
var _nav: NavGraphBuilder
var _entity_defs: EntityDefRegistry
var _object_state_manager: ObjectStateManager  # for _can_settle_in's join lookup
var _events: Object             # Events autoload — duck-typed Object injection (FoodSystem precedent)
var _timers: BehaviorTimers     # shared with AiStateSystem; see below
var _waypoints: Dictionary = {} # entity_id -> stored waypoint dict; MovementSystem-private

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
    # ... migrated from game_server._move_animals; speed read per-entity, events
    # emitted via _events.creature_started_pacing.emit(entity_id) at HUNGRY-arrival
    # branches that fail to find food in range. _can_settle_in becomes a private
    # method on MovementSystem (uses _nav, _object_state_manager, _db).
```

**`_movement_waypoints` is MovementSystem-private, not shared.** The cat-jumps-into-box merge added `_movement_waypoints: Dictionary` to GameServer at line 38, used exclusively inside `_move_animals` (5 references in the move loop, none elsewhere). It moves into `MovementSystem` as a private instance field rather than into `BehaviorTimers`. `BehaviorTimers` is reserved for dicts that genuinely cross between MovementSystem and AiStateSystem.

**`_can_settle_in` becomes a private MovementSystem method.** The cat-jumps-into-box merge added `_can_settle_in(entity_id, host_id) -> bool` (lines 907–933) called only from `_move_animals` at line 318 (arrival branch). After extraction it's a private MovementSystem method using injected `_nav`, `_object_state_manager`, and `_db` — no GameServer reference needed.

**Walking speed read.** `body_capabilities` is a nested Dictionary, so the read is `db.get_component(entity_id, &"body_capabilities").walks.speed_px_per_tick` rather than `db.get_field` (which only works on flat fields). The value flows into the existing `NavPathStepper.step(from_px, waypoint, speed)` call site.

**Events injection precedent.** `engine/core/food_system.gd:11` already takes the Events autoload as `events: Object`. Engine code never `extends Node` and never imports the Node type; the duck-typed Object injection lets engine systems emit on the autoload without depending on a Node hierarchy. MovementSystem follows the same pattern. This is a documented carve-out from "no Node references in engine/" — the interface is "anything with `.creature_started_pacing.emit(int)` callable on it."

### Shared state: `BehaviorTimers`

`_state_timers`, `_min_durations_override`, and `_curiosity_trackers` currently live as instance dicts on `GameServer` and are read/written by `_move_animals`, `_update_ambient_states`, and `remove_object`. After extraction they belong on a small RefCounted struct that both systems take by reference:

```gdscript
class_name BehaviorTimers extends RefCounted

# entity_id -> ticks elapsed in current ai_state. Int ticks (not float seconds);
# the legacy float-seconds accumulation via tick_delta=0.1 is replaced by
# integer increments per tick.
var state_timers: Dictionary = {}

# entity_id -> override min_duration_ticks for the current state, set on
# SNIFFING entry by the curiosity arrival path.
var min_durations_override: Dictionary = {}

# entity_id -> CuriosityTracker. Lifetime managed by the entity's lifecycle.
var curiosity_trackers: Dictionary = {}
```

Both `MovementSystem` and `AiStateSystem` take `BehaviorTimers` in their constructor; `GameServer` instantiates it once and passes the reference. This:

- Replaces the proposed "AiStateSystem holds a reference to MovementSystem and reads its dicts" coupling, which three reviewers flagged as a smell.
- Migrates timers from `float seconds` (accumulated via `tick_delta = 0.1`) to `int ticks` — eliminating float drift over long-running sessions.
- Makes both extracted systems unit-testable in isolation by injecting a fresh `BehaviorTimers` per test.
- Leaves a clean upgrade path: when `_state_timers` etc. eventually promote to per-entity components on `GameStateDB` (out of scope; follow-up), only `BehaviorTimers` and its consumers change. MovementSystem and AiStateSystem don't need to know about the storage shape.

**In-flight timers across the extraction commit.** When phase 5 lands, every entity mid-LOAFING has its timer reset (BehaviorTimers starts empty; the GameServer-instance dict is dropped). This matches existing save/load behavior — `_state_timers` was never serialized — so it's "rerun the cycle from this state" rather than data loss. Document the reset; don't try to migrate timers across the commit. Same applies to phase 6 for the AiStateSystem-only timer keys.

**Promotion to per-entity components.** Moving `BehaviorTimers`'s dicts into `GameStateDB` as components on each entity is the right long-term shape (saves carry timers automatically; entity destruction cleans them up). Out of scope here. With BehaviorTimers in place, that future move is a one-file change rather than touching both extracted systems.

### `_update_ambient_states` → `AiStateSystem` (extraction)

Extract the **~183-line** method (post cat-jumps-into-box merge; pre-merge it was ~167 lines — the ~16-line growth is the SETTLING completion writing `settled_in` via `settled_lifecycle.enter()`) into `engine/animals/ai_state_system.gd`. The name `AiStateSystem` mirrors `Contentment`-style "name what it computes/ticks" — the system advances per-entity `ai_state` components.

The system covers:

- STARTLED recovery (reads `special_states.STARTLED.min_duration_ticks` from the entity's recipe-derived component; missing component crashes per the assertion below — there is no engine-side default).
- Food state machine (PACING, EATING, SETTLING transitions).
- AMBIENT-state hunger detection (AMBIENT → HUNGRY/PACING).
- Min-duration-gated ambient state cycling — reads recipe-driven `min_duration_ticks` from each entity's `ambient_states` component instead of the engine-side `_min_durations` dict.

```gdscript
class_name AiStateSystem extends RefCounted

var _db: GameStateDB
var _food_system: FoodSystem
var _entity_defs: EntityDefRegistry
var _events: Object                       # Events autoload (duck-typed)
var _settled_lifecycle: SettledLifecycle  # for SETTLING completion
var _timers: BehaviorTimers               # shared with MovementSystem

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
    # ... migrated from game_server._update_ambient_states
    # food finders called via _food_system.find_nearby_food/find_nearest_box/etc.
```

The engine-side `_min_durations: Dictionary` constant on `game_server.gd` is removed. Per-entity reads pull `min_duration_ticks` from the matching state entry in the entity's `ambient_states.warm` or `ambient_states.cold` pool (whichever is active for current warmth).

**STARTLED assertion.** STARTLED is set on entities by `remove_object` proximity at `game_server.gd:705`. If a future entity ends up STARTLED without a `special_states` component (mod skips it, scenario seed, test fixture), the no-defensive-null stance must crash loud rather than fall through silently. Add at the STARTLED branch top:

```gdscript
assert(_db.has_component(entity_id, &"special_states"),
    "Entity in STARTLED but recipe declared no special_states block")
```

**Food-finder migration to FoodSystem.** Today `_update_ambient_states` calls `_find_nearby_food`, `_find_nearest_box`, `_find_nearest_dispenser`, and `_mark_nearest_can_eaten` — all private helpers on `GameServer`. Extracting AiStateSystem cleanly requires these to be reachable from outside the Node. Promote all four to **public methods on `FoodSystem`** as part of phase 5:

| Old GameServer private | New FoodSystem public |
|---|---|
| `_find_nearby_food(entity_id) -> int` | `food_system.find_nearby_food(entity_id) -> int` |
| `_find_nearest_box(entity_id) -> int` | `food_system.find_nearest_box(entity_id) -> int` |
| `_find_nearest_dispenser(entity_id) -> int` | `food_system.find_nearest_dispenser(entity_id) -> int` |
| `_mark_nearest_can_eaten(entity_id) -> void` | `food_system.mark_nearest_can_eaten(entity_id) -> void` |

`food_system.find_nearest_dispenser` already delegates to `CatFoodStates.find_nearest_dispenser`; the migration just renames the GameServer wrapper to a FoodSystem method. The other three are pure spatial queries that fit FoodSystem's existing scope. This is a small, atomic API addition to FoodSystem — not the larger Open Question 1 (moving the entire food state machine into FoodSystem).

**Re-baseline before cutting phases 4 and 5.** The cat-jumps-into-box thread merged before this spec lands. Before each extraction phase:

1. Re-read the current `_move_animals` and `_update_ambient_states` methods to confirm the touchable surface against the merged base.
2. Update phase 4/5 implementation against the current method bodies, not the snapshot this spec captured.
3. Note any state-timer keys, `_min_durations` entries, or state-machine branches added by the merged thread; they enter `BehaviorTimers` or `special_states`/`ambient_states` accordingly.
4. Update `tests/integration/test_tick_loop.gd`'s `EXPECTED_ORDER` constant with the new method names (`movement_system.tick()`, `ai_state_system.tick()`). The AI-DEV note "MUST NOT modify" is about preventing reorder, not preventing renames; the tick order stays the same, only the symbol strings change.

### Test updates

Two integration tests inline production logic that this extraction makes proper:

- `tests/integration/test_desire_scatter.gd:130` — inlines `_move_animals`. Replace with calls to `MovementSystem.tick()`.
- `tests/integration/test_runtime_smoke.gd:105` — inlines decay logic from `_scatter_desires`. Replace with calls to the production code path or a focused unit test of the new per-species decay loop.

Re-stamp both per `/verify-test` once green.

`tests/integration/test_tick_loop.gd` (which inlines `_decay_commitment`) is **out of scope** — `_decay_commitment` isn't being extracted. The inlining persists until a separate extraction pass.

## Order of Work

Each step is one atomic commit. Each leaves `script/validate` green. Both perception-channels and cat-jumps-into-box have merged; this spec lands on a clean base.

| # | Phase | Touches | Conflict risk |
|---|---|---|---|
| 1 | Loader extensions only (no validator activation) | `engine/mod/entity_def_registry.gd` (additive — new component materializations for `desire_decay` and `special_states`), `engine/animals/behavior_timers.gd` (new struct, unused) | None |
| 2 | Validator rules + recipe content (atomic) | `engine/mod/species_schema_validator.gd` (new required-field rules), `mods/tcp_cats/species/cat.jsonc`, `mods/tcp_ferrets/species/ferret.jsonc` (v3→v4 bump, all new blocks), `.claude/rules/modding.md` (v3→v4 changelog, two-track recipe note) | None |
| 3 | `_scatter_desires` decay consumer (in-place) | `nodes/game_server.gd:_scatter_desires`, `engine/mod/entity_def_registry.gd` (helper queries `has_desire_decay`/`get_desire_decay`), `.claude/rules/animal-ai.md` (desires-implies-species contract) | None |
| 4 | `MovementSystem` extraction + speed consumer + BehaviorTimers wired | `nodes/game_server.gd:_move_animals` (delete), `engine/animals/movement_system.gd` (new), `tests/integration/test_desire_scatter.gd`, `tests/integration/test_tick_loop.gd` (EXPECTED_ORDER update) | None |
| 5 | `AiStateSystem` extraction + min-duration consumer + food-finder migration | `nodes/game_server.gd:_update_ambient_states` (delete), `engine/animals/ai_state_system.gd` (new), `engine/core/food_system.gd` (4 promoted public methods), `tests/integration/test_tick_loop.gd` (EXPECTED_ORDER update) | None |
| 6 | Old spec cleanup | `docs/superpowers/specs/2026-04-06-game-server-extraction-design.md` | None |

After phase 1, phase 2 must follow before any consumer phase. Phase 3 is independent after phase 2 lands.

**Phase 1 atomicity.** Phase 1 is loader-only and additive. New `if def.has(...)` branches in `entity_def_registry.spawn()` materialize the new components when a recipe declares them — but no recipe declares them yet, and no consumer reads them yet. After phase 1: zero behavior change, validate green. The validator changes do NOT land in phase 1 — landing them before recipe content is updated would break validate immediately.

**Phase 2 atomicity.** Validator rules + recipe content + `modding.md` documentation ship as one commit. The validator now requires the new fields when their parent block exists; the recipes carry them; the rule doc explains the v3→v4 delta. Half this list landing alone would break validate.

**Phases 3–5.** Each consumer phase reads the components materialized in phase 1 and validated in phase 2. The hunger value in the recipe stays at `0` (intentional balance decision); the refactor does not touch it.

## Old Spec Cleanup (Phase 6)

`2026-04-06-game-server-extraction-design.md` carried unfinished MovementSystem extraction as ongoing work. This spec absorbs that scope. Update the older spec by:

- Marking "MovementSystem extraction" in the Implementation Status table as **Superseded by `2026-05-02-recipe-driven-balance-design.md`** rather than "Never written."
- Marking item 2 of the older spec's "Remaining work" list (the MovementSystem extraction) as superseded.
- Marking item 3 (test file updates) as **partially superseded** — the two tests that inline `_move_animals` are now tracked here; `test_tick_loop.gd` (inlines `_decay_commitment`) and the `_mark_animals_dirty`-era inlining stay tracked in the older spec.
- Adding a "Successor specs" section linking to this one.

No content removed from the older spec — the lessons-learned section is durable knowledge worth keeping.

## Test Plan

**Unit (new tests):**

- `entity_def_registry.spawn()` materializes `desire_decay` from a recipe (assert exact dict on the spawned entity).
- `entity_def_registry.spawn()` materializes `special_states` from a recipe (assert exact dict).
- `SpeciesSchemaValidator` rejects a recipe with `desires` but no `desire_decay` (assert `push_error` fired, recipe not registered).
- `SpeciesSchemaValidator` rejects a recipe with `body_capabilities.walks` but no `speed_px_per_tick`.
- `SpeciesSchemaValidator` rejects an `ambient_states` entry missing `min_duration_ticks`.
- `SpeciesSchemaValidator` rejects a recipe with `ambient_states` but no `special_states` block, and rejects a `special_states.<NAME>` entry missing `min_duration_ticks`.
- `SpeciesSchemaValidator` groups multiple violations on a single recipe into one `push_error` call (assert single error message lists every missing field).
- `MovementSystem.tick()` advances an entity by its recipe-declared `speed_px_per_tick`, not the old constant.
- `AiStateSystem.tick()` honors per-entity `min_duration_ticks` for state cycling (cat in LOAFING for 149 ticks does not switch; 150 ticks may switch).
- `AiStateSystem.tick()` asserts on STARTLED entities lacking `special_states` (assert hits `assert(false)`, debug build only).
- "Arms don't decay" guard: spawn an arm-shaped recipe (no `desires`), run the new decay path, assert no `desires` writes.
- `BehaviorTimers` survives a swap of the owning system (instantiate a fresh MovementSystem with the same BehaviorTimers, verify timers persist across the swap).

**Integration (existing, updated):**

- `test_desire_scatter.gd` calls `MovementSystem` directly instead of inlining.
- `test_runtime_smoke.gd` exercises the recipe-driven decay path.
- `test_tick_loop.gd` continues to pin tick order; ordering unchanged. EXPECTED_ORDER constant updated to match renamed `movement_system.tick()` and `ai_state_system.tick()` strings.

**Integration (new tests):**

- **Determinism guard.** Spawn 5 cats and 5 ferrets, run 100 ticks, snapshot all `desires` values, run again from the same seed, assert identical results. The new per-species decay loop iterates `entity_defs.get_all_entities()` whose order is Dictionary-iteration-order; this test catches a regression where iteration order shifts between runs and produces non-deterministic decay outcomes.

**Behavior (verify with playable build):**

- Hunger stays at 0 decay (recipe carries `hunger: 0`); behavior identical to today. No new pacing, no missing pacing.
- Cats stay in LOAFING for ~15 sec before switching (150 ticks), matching recipe declaration.
- No regression in cat-settling behavior on the merged base.

## What This Does NOT Do

- Does not refactor `place_object` or write recipes for `server_1u` / `cardboard_box` / `clothes_pile`. (Separate Phase 2 spec.)
- Does not extract `_scatter_desires` or `_decay_commitment` into separate systems. They stay in `game_server.gd`.
- Does not move the food state machine (PACING/EATING/SETTLING transitions) into `FoodSystem`. AiStateSystem keeps the state-machine logic; only the four spatial-query helpers (`find_nearby_food` etc.) migrate to FoodSystem.
- Does not change tuning values. Existing values (including `hunger: 0`) move to recipes verbatim.
- Does not touch the `senses` block, perception radius, ad scoring/scatter shape, channel registry, signed-weight migration, or desire-key rename. Those shipped in PR #14 (perception-channels).
- Does not promote `BehaviorTimers`'s dicts to per-entity components in `GameStateDB`. The struct is the staging ground for that future move.
- ~~Does not introduce a `GameStateDB.add_field_subset(entity_ids, component, field, delta)` op.~~ **Reversed (2026-05-03):** Open Question 1 resolved as yes. Phase 3 introduces the op. See "Consumer Changes → `_scatter_desires`" for the API.
- Does not write a schema migration function. No third-party species mods exist yet (TCP is pre-release); when they do, future schema bumps will need migration.
- Does not surface validator errors in-game. `push_error` to the Godot console is the developer-grade UX; in-game mod-load toasts wait for the in-game mod manager.

## Trigger Sources Stay In Code

`special_states` declares only the *duration* of an event-triggered state, not what triggers it. Triggers stay in code:

- STARTLED is set by `remove_object` on entities within proximity (see `game_server.gd:610–625`).
- Future RELOCATING / BEING_CARRIED triggers will be set by their respective owning systems (relocation orchestrator, robot-arm carry code, etc.).

Recipes tune "how long does the entity stay in this state once an external event sets it." Adding `special_states.RELOCATING.min_duration_ticks` to a recipe doesn't make the entity relocatable — the trigger system has to exist.

## Resolved Questions

1. **~~Do we want a small batched-subset op in `GameStateDB` now?~~** Resolved 2026-05-03: **yes**. Phase 3 introduces `GameStateDB.add_field_subset(entity_ids, component, field, delta)` as a precondition for the consumer rewrite. ~10 lines. Single-call seam for the per-species decay loop and a hook point for a future column-friendly fast path.

2. **~~Co-locate `desire_decay` next to weights in `desires`?~~** Resolved 2026-05-03: **yes**. Recipe shape is now `desires.<channel>: {weight, decay}` — the sibling `desire_decay` block proposed in earlier drafts is gone. See "Schema Additions → 1. Per-type desire decay (co-located with weights)."

3. **~~`ambient_states` array → dict shape?~~** Resolved 2026-05-03: **stay array**. Order preservation matters for deterministic random selection; the validator rejects duplicate `state` keys.

4. **~~Cache `body_capabilities.walks.speed_px_per_tick` somewhere flat?~~** Resolved 2026-05-03: **no cache**. MovementSystem reads via `db.get_component(...).walks.speed_px_per_tick` each tick. Microsecond performance hit at prototype scale; correctness over perf.

5. **~~`assert` vs `push_error` on STARTLED-without-special_states?~~** Resolved 2026-05-03: **assert (debug-only)**. Matches `design-philosophy.md` "Explode Early." Production behavior on missing `special_states` is "the assert was stripped; the next read will null-error in `set_field` anyway." Trade for an observability solution post-launch.

6. **~~`desire_decay` naming — accommodate future passive recovery?~~** Resolved 2026-05-03: **decay-only**. Validator rejects values > 0. If passive recovery ever ships, it ships as a separate field with its own validator rule. Renaming is cheap (single grep) if priorities change.
