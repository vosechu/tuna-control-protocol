---
paths:
  - "engine/core/object_state_manager.gd"
  - "engine/objects/**"
  - "mods/**/objects/**"
---

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
        &"<state_name>": {
            &"ads":  [<ad>, <ad>, ...],   # advertisements for this state
            &"join": { ... },             # optional — see "Join blocks" below
        },
        ...
    },
    &"hp_thresholds": [                   # optional; only for degradable objects
        {&"min_hp": 501, &"state": &"new"},
        {&"min_hp": 1,   &"state": &"worn"},
        {&"min_hp": 0,   &"state": &"scraps"},
    ],
}
```

Ordering inside `hp_thresholds`: highest `min_hp` first. `get_state_for_hp` returns the first match, so a descending list means the highest-qualifying state wins.

A state with no `join` key has no relationship-forming behavior in that state — when an object transitions into a `join`-less state while occupied (e.g. `cardboard_box` decaying into `scraps`), the navgraph drops the `add_box_enterable` edges and the position-coupling pass dissolves any incoming `&"settled_in"` bonds and STARTLEs the joiners. See `.claude/rules/navigation.md` §"Dynamic Updates".

### Advertisement fields

| Field | Required | Purpose |
|---|---|---|
| `channel` | yes | Emission name. Must exist in `Constants.CHANNELS` (12 entries: 6 attractor + 6 aversion). The registry maps each channel to its `{sense, desire, effect}` triple — see `animal-ai.md` §"Aversions". |
| `strength` | yes | 0–1000, always positive. Effect direction comes from `CHANNELS[channel].effect`. |
| `effect_radius_px` | one of | Hard cutoff for radius-delivery scatter. Cap: `BAY_WIDTH_PX`. Mutually exclusive with `effect_slot`. |
| `effect_slot` | one of | `true` selects slot delivery: full strength to every entity sharing the ad-owner's slot; zero elsewhere. Mutually exclusive with `effect_radius_px`. Validator rejects an `effect_slot: true` ad whose owner is not slot-anchored (zone returned by `bay_local_to_slot` must be `&"slot"`). |
| `falloff` | optional | Curve for radius delivery: `quadratic` (default), `linear`, `step`, `inverse_square`. Quadratic encodes "a buzzer across the bay should not bother a cat unless it's *really* loud." |
| `action` | optional | Sentinel (presence only — value not read). When present, `DesireScatter` skips the ad during passive satisfaction; consumers must do the work explicitly (PACING→EATING flow, arm tick, etc.). |
| `max_occupants` | optional | Soft cap for pile-on-style ads. Consumer decides enforcement. |
| `novelty_duration` | optional | On-arrival SNIFFING time for curiosity ads (in ticks/10, seconds). Read by arrival logic. |
| `novelty_cooldown` | optional | Per-tracker decay time before the same ad counts as novel again. |

Every passive-scatter ad declares **exactly one** of `effect_radius_px` (physics-of-emission curve — heat, sound, scent, body heat) or `effect_slot: true` (structural effect — boxes, beds, tubes, cat towers). An ad with neither is an action ad: it never lands via passive scatter; the effect only flows through direct consumption (e.g. `settle`/`eat` actions).

### Passive scatter vs. active consumption

`DesireScatter.scatter_from_ads` runs every tick in two passes:

1. **Slot delivery** — for each ad with `effect_slot: true`, resolve the ad-owner's slot and apply `strength / 10` per tick to every other entity in that slot. Sidesteps pixel-tuning: the cat *in* the slot gets full strength regardless of anchor offset; the cat in the next slot gets nothing.
2. **Radius delivery** — entity-first. Each entity reads its own `senses` once per tick, runs a broad-phase spatial query bounded by `BAY_WIDTH_PX`, then per-ad gates on `effect_radius_px` AND `senses[CHANNELS[channel].sense]`. Falloff per the ad's curve.

Both passes **skip any ad with an `action` key** unless the receiver is bonded to the ad-owner. That skip is the mechanism by which "cats must actively eat to be fed" is enforced — an open tuna can is only satisfying via the EATING state loop, never just by standing nearby. Bonds gate action-ad consumption only; they do **not** participate in passive scatter — the cat-in-box loop is handled by `effect_slot: true` on box ads, not by a bond bypass.

### Join blocks

A state's `join` block declares how a joiner couples to the host on arrival. Three join types:

| `type` | Joiner outcome | Position coupling | Z-order |
|---|---|---|---|
| `&"contained"` | Joiner sits *inside* the host (cat tucked into box) | `host.position + interior_origin_offset` | Joiner draws **behind** host (`Constants.Z_PLACED_OBJECTS_TUCKED`) so the host's lip occludes the body. |
| `&"stack"` | Joiner sits *on top of* the host (kitten on cat) | `host.position + slot_offset` | Joiner draws **in front of** host (default `200 + y/2`). |
| `&"nearby"` | Joiner stays *within radius* of the host (play partners) | No coupling — joiner free-walks; relationship dissolves when distance > `radius_px`. | Default. |

Today only `contained` is wired (cardboard_box). `stack` and `nearby` are reserved types described in the resting-on design and lit up by their respective implementation phases.

```gdscript
&"join": {
    &"type": &"contained",                          # one of the three above
    &"direction": &"any",                            # joiner-state filter; today &"any"
    &"capacity": 5,                                  # weight-capacity (5 kittens at weight=1, or 1 cat at weight=5)
    &"entry_origin_offset":    Vector2i(0, -16),    # px from host position to top-stand nav node (used by ENTER edge)
    &"interior_origin_offset": Vector2i(0, -8),     # px from host position to inside nav node (where joiner snaps)
    &"entry_threshold_ru": 1,                       # required jumps.max_height_ru to traverse the ENTER edge
    &"inner_size_ru": 2,                             # required body_geometry.size_ru ceiling for the joiner
}
```

`entry_origin_offset` and `interior_origin_offset` are pixel deltas from the host's stored position. `entry_threshold_ru` and `inner_size_ru` are integer rack-units (size dimension), gates against the joiner's `body_capabilities.jumps.max_height_ru` and `body_geometry.size_ru` respectively. See `.claude/rules/navigation.md` §"Edge Types" for the ENTER scanner.

### Bond components (action-ad bypass)

A "bond" is a marker component on an entity declaring an active relationship with a host (today: `&"settled_in"` for "tucked into this box"; future: `&"mounted_on"`, `&"holding"`, `&"inside_tube"`). The bond *is* the active state. While a bond is in place, action-tagged ads from the bonded host bypass the passive-proximity skip, so the bonded entity is satisfied by the host's ads directly.

**Convention:** every bond marker component carries a `&"host_id"` field pointing at the bonded host. New bond types register their component name once at boot via `Bonds.register_bond(&"my_marker")` (see `engine/core/bonds.gd`). The system that manages the bond owns the registration call (e.g. `SettledLifecycle._init` registers `&"settled_in"`).

Bonds gate **action-ad consumption only** — passive scatter never reads them. The cat-in-box satisfaction loop is delivered by `effect_slot: true` on the box's `safety` and `comfort` ads (see "Passive scatter vs. active consumption" above). Earlier drafts routed scatter through a bond bypass; that overreach is retired in favor of slot delivery.

## Shipped object types

| Type | States | Degradable? |
|---|---|---|
| `tuna_can` | `sealed` → `opened` → `eaten` | No |
| `cardboard_box` | `new` → `worn` → `scraps` | Yes (HP-driven) |

## Where to put what — authoritative paths

There are **two recipe surfaces today**, and they cover different things.
Adding a new object means picking the right one for the kind of object you
have. Mixing them silently is the most common modder mistake — pick
deliberately.

| Concern | Lives in | Example | Loaded? |
|---|---|---|---|
| **State machines** (`state_ads`, `hp_thresholds`, `join` blocks, transitions) | `OBJECT_CONFIG` const in `engine/objects/object_state_manager.gd` | `tuna_can`, `cardboard_box` | **Yes — this is what runs.** |
| **Stateless device recipes** (placement, physical, behavior-component fields) | `mods/<mod_id>/objects/<id>.jsonc` | `arm`, `hum_device`, `tuna_button`, `tuna_dispenser` | **Yes — loaded by mod pipeline.** |
| **Shadow state-machine JSON** (e.g. `mods/tcp_tuna/objects/tuna_can.jsonc`) | `mods/<mod_id>/objects/<id>.jsonc` | tuna_can mirrors OBJECT_CONFIG with `"states": {...}` | **No — non-binding documentation.** Listed for the future migration path; the loader does not consume `states` today. |

**Rule of thumb.** If your object has state transitions (sealed→open, new→worn→scraps, etc.), edit `OBJECT_CONFIG` in `engine/objects/object_state_manager.gd`. If it's a stateless device with one component to declare (an arm, a button, a battery), ship a JSON recipe under `mods/<mod_id>/objects/`. Do not write a `states` block in JSON expecting it to load — it won't, and tests won't catch the no-op until runtime.

The full state-machine→JSON migration (`OBJECT_CONFIG` collapses into per-mod JSON loaded by ConfigRegistry) is planned but not staffed. Until then, accept the two-surface split as the real interface, not a temporary glitch.

## Stateless device recipe schema (mod-side)

Stateless devices shipped as mod recipes follow this layout (see `mods/tcp_base/objects/`):

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

The component-name slot declares this object's specialized component (arms have `arm`, buttons have `tuna_button`, dispensers have `tuna_dispenser`). The component's fields are read by the system that owns that behavior (e.g. `FoodSystem` reads `arm.radius_px` and `arm.hum_cost`).

Stateless recipes do **not** declare a `states` block. If your object needs state transitions, see "Where to put what" above.

## Common slip patterns

| Slip | Why it bites | Fix |
|---|---|---|
| Writing a `states` block in a stateless device JSON recipe | Loader doesn't read it — silent no-op until runtime. State-machine content lives in `OBJECT_CONFIG`, not in JSON. | See "Where to put what" — pick the right surface deliberately. JSON recipes are stateless devices; engine `OBJECT_CONFIG` owns state machines. |
| Routing passive scatter through a bond bypass to satisfy "the cat in the box" | Overreach. Scatter never reads bonds; bonds gate action-ad consumption only. Earlier drafts shipped the bypass and had to be retired. | Use `effect_slot: true` on the host object's ads. The cat-in-box satisfaction loop is delivered by slot delivery, not by bonds. |
| Declaring an ad with both `effect_radius_px` and `effect_slot: true` | Mutually exclusive; validator rejects, but a missing rejection check would silently double-deliver. | Pick one per ad. Slot for structural effects (boxes, beds, tubes), radius for physics (heat, sound, scent). |

## Related rules

- Advertisement scoring and desire channels: `.claude/rules/animal-ai.md`
- Food chain (button → dispenser → can → arm → cat): `.claude/rules/food-system.md`
- Mod/recipe loading: `.claude/rules/modding.md`
