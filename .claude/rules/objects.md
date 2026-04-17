# TCP Object Mechanics

Placed/spawned objects are regular entities with a small set of components. Their behavior — state transitions, advertisement swaps, HP-driven degradation — is driven by `ObjectStateManager` reading a per-type config.

## Components

| Component | Shape | Purpose |
|---|---|---|
| `object_type` | `{type: StringName}` | Type identifier (e.g. `&"tuna_can"`, `&"cardboard_box"`). |
| `object_state` | `{state: StringName}` | Current lifecycle state for the type. |
| `object_hp` | `{hp: int}` | Optional. Present on degradable objects only. |
| `advertisements` | `{list: Array[Dictionary]}` | The current ad list. Swapped in/out by state transitions. |
| `position` | `{x: int, y: int}` | Position-unit coordinates. Required for spatial queries and ads. |

Objects without `object_hp` have no degradation path; their state changes only via explicit `transition_state` calls (e.g. the arm opening a can).

## ObjectStateManager

`class_name ObjectStateManager extends RefCounted`. Owns all state transitions and the `OBJECT_CONFIG` dictionary. One instance lives under `GameServer`.

```gdscript
func transition_state(entity_id: int, new_state: StringName) -> void
func damage(entity_id: int, amount: int) -> void
func get_state_for_hp(object_type: StringName, hp: int) -> StringName
func get_ads_for_state(object_type: StringName, state: StringName) -> Array
```

- `transition_state` sets `object_state.state` and swaps the `advertisements` component to match the new state's ad list. Setting state to one whose ad list is empty removes the `advertisements` component.
- `damage` reduces `object_hp.hp`, then calls `get_state_for_hp` against the `hp_thresholds` table; if the state changed, auto-invokes `transition_state`.
- `get_state_for_hp` returns the first entry whose `min_hp` is ≤ current hp. Entries must be ordered highest `min_hp` first. Returns empty StringName if the type has no `hp_thresholds`.
- `get_ads_for_state` is a pure lookup into `state_ads`. Empty array for unknown type/state combinations — never errors.

## OBJECT_CONFIG schema

Each object type declares its state machine under `OBJECT_CONFIG[&"type_name"]`:

```gdscript
{
    &"state_ads": {
        &"<state_name>": [<ad>, <ad>, ...],   # list of advertisements for this state
        ...
    },
    &"hp_thresholds": [                         # optional; only for degradable objects
        {&"min_hp": 501, &"state": &"new"},
        {&"min_hp": 1,   &"state": &"worn"},
        {&"min_hp": 0,   &"state": &"scraps"},
    ],
}
```

Ordering inside `hp_thresholds`: highest `min_hp` first. `get_state_for_hp` returns the first match, so a descending list means the highest-qualifying state wins.

### Advertisement fields

| Field | Required | Purpose |
|---|---|---|
| `desire_type` | yes | Desire channel (`&"warmth"`, `&"hunger"`, `&"comfort"`, `&"curiosity"`, `&"openable"`, ...). |
| `strength` | yes | 0–1000 scoring weight, matches the desire scale. |
| `radius_ru` | yes | Effect radius in rack units. Converted to PU via `Constants.ru_to_pu`. |
| `action` | optional | Sentinel (presence only — value not read). When present, `DesireScatter` skips the ad during passive satisfaction; consumers must do the work explicitly (PACING→EATING flow, arm tick, etc.). |
| `max_occupants` | optional | Soft cap for pile-on-style ads. Consumer decides enforcement. |
| `novelty_duration` | optional | On-arrival SNIFFING time for curiosity ads (in ticks/10, seconds). Read by arrival logic. |
| `novelty_cooldown` | optional | Per-tracker decay time before the same ad counts as novel again. |

### Passive scatter vs. active consumption

`DesireScatter.scatter_from_ads` (engine/desires) runs every tick and applies the strongest in-range ad per desire-type to each entity with matching desires. It **skips any ad with an `action` key**. That skip is the mechanism by which "cats must actively eat to be fed" is enforced — an open tuna can is only satisfying via the EATING state loop, never just by standing nearby.

## Shipped object types

| Type | States | Degradable? |
|---|---|---|
| `tuna_can` | `sealed` → `opened` → `eaten` | No |
| `cardboard_box` | `new` → `worn` → `scraps` | Yes (HP-driven) |

Per-type specifics live next to the mod — `mods/tcp_tuna/objects/tuna_can.jsonc` and `OBJECT_CONFIG[&"cardboard_box"]` in `object_state_manager.gd`. Two sources today; future work moves everything into mod recipes.

## Mod-side object recipes

Objects shipped as mod recipes follow this layout (see `mods/tcp_base/objects/`):

```jsonc
{
  "schema_version": 1,
  "id": "tcp_base:<name>",
  "name": "<display>",
  "size_ru": 1,
  "placement": "rack" | "floor",
  "<component_name>": { ...component fields... },  // e.g. "arm", "tuna_button"
  "physical": {"mass": <grams>, "size_ru": <int>},
  "advertisements": [<ad>, ...]
}
```

The component-name slot declares this object's specialized component (arms have `arm`, buttons have `tuna_button`, dispensers have `tuna_dispenser`). The component's fields are read by the system that owns that behavior (e.g. `FoodSystem` reads `arm.radius_ru` and `arm.hum_cost`).

## Related rules

- Advertisement scoring and desire channels: `.claude/rules/animal-ai.md`
- Food chain (button → dispenser → can → arm → cat): `.claude/rules/food-system.md`
- Mod/recipe loading: `.claude/rules/modding.md`
