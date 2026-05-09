---
paths:
  - "engine/core/hum_*"
  - "engine/core/contentment*"
  - "engine/core/food_system.gd"
  - "engine/core/sensory_emission*"
  - "nodes/hud/hum_bar.gd"
---

# TCP HUM & Cable System

Per-device HUM batteries charged by purr emissions, drained by every action that costs power. The mechanical spine of the purr-power loop described in `core-loop.md`.

The cable layer between HUMs and HUM-powered actuators is not currently implemented. `FoodSystem.is_powered()` returns the first HUM with enough reserve regardless of which device is asking. The cable-restoration design (player-placed power cables, per-device routing, mid-drag save semantics, the `hum_powered`/`hum_cable` capability tags, the `cable_connected`/`cable_disconnected` events, `mods/tcp_base/config/hum.jsonc`) lives at `docs/superpowers/specs/2026-05-09-cables-restoration-design.md` for the day it ships again.

## Components

| Component | Shape | Carried by | Authority |
|---|---|---|---|
| `hum` | `{reserve: int, capacity: int}` | HUM entities | Server — saved |
| `hum_receiver` | `{radius_px: int}` | HUM entities | Server — saved |
| `purr` | `{intensity: int, radius_px: int}` — per-tick broadcast strength + reach | any "thing that purrs" (cats in Ring 1) | Server — saved, written by `SensoryEmissionSystem` |
| `sensory_emissions` | `{<output_name>: {trigger?, base_intensity, modifiers, base_radius_ru}}` | recipe-declared emitters | Server — saved, materialized from recipe at spawn |

## Emit / Listen, Not Produce / Consume

Cats don't produce HUM — cats purr. The HUM receiver listens for purrs and converts what it hears to stored charge. **The emitter never names HUM. The receiver never names cats.** Both sides talk only about the `purr` channel.

Consequences:
- New listeners on `purr` (future ferret-calm system, sound mixer, narrator) subscribe without touching cats.
- New emission kinds (chimes, rings, electrical current, thermal) get their **own** channel (`&"chime"`, `&"ring"`, `&"electrical_emission"`, …) and their **own** receiver. What the receiver does with the signal — charge HUM, calm ferrets, drive lights, narrate — is a per-channel decision; not every emission feeds HUM. They are not added to the `purr` channel post-hoc, and the `purr` channel and `hum_receiver` component aren't generalized to cover them.
- `HumSystem.tick_charge()` branches only on the `hum_receiver`, `purr`, and `position` capabilities. It never reads `contentment`, `is_satisfied`, or species labels.

### Contentment → purr via SensoryEmissionSystem

`engine/core/sensory_emission_system.gd` runs each tick **before** `tick_charge()`. For every entity carrying `sensory_emissions`, the runner evaluates each declared output:

```
for output in sensory_emissions:                # e.g. "purr"
    if trigger fails:                           # cat.contentment.is_satisfied != 1
        intensity = 0
    else:
        intensity = base_intensity              # 1000 for cat
        for mod in modifiers: intensity = mod(intensity)
    radius_px = base_radius_ru * SLOT_HEIGHT_PX * intensity / UNIT
    write {intensity, radius_px} to output's per-tick component
```

The runner knows about `sensory_emissions` and the per-output component (`purr`). It does not know HUM exists. The recipe-declared trigger is what couples contentment to purr — `cat.jsonc` declares `trigger: {component: "contentment", field: "is_satisfied", equals: 1}`. Future emitters that don't gate on contentment simply omit the trigger or declare a different one.

Recipe shape lives in the species file (e.g. `mods/tcp_cats/species/cat.jsonc`):

```jsonc
"sensory_emissions": {
  "purr": {
    "trigger":         { "component": "contentment", "field": "is_satisfied", "equals": 1 },
    "base_intensity":  1000,
    "modifiers":       [],
    "base_radius_ru":  6
  }
}
```

Spawn materializes the block into the `sensory_emissions` component (canonicalized: value sources become `{kind: literal|ref, ...}`, modifiers sort by `priority`) plus an empty per-output `purr {intensity: 0, radius_px: 0}` component. See `modding.md` §"Sensory Emission vocabulary" for the bounded modifier-op and falloff vocabularies modders draw from.

## Charging (tick_charge)

Each tick, for every entity with `purr.intensity > 0`, pick the **nearest** HUM receiver whose radius covers the emitter and credit that receiver's `hum` reserve by `intensity`. Ties broken by lower `entity_id` for determinism.

```gdscript
func tick_charge() -> void:
    var per_hum_charge: Dictionary = {}
    for emitter_id in db.get_entities_with(&"purr"):
        var intensity := db.get_field(emitter_id, &"purr", &"intensity")
        if intensity <= 0: continue
        var best_id := nearest_receiver_in_range(emitter_id)  # id-tiebreak on equal distance
        if best_id == INVALID_ID: continue
        per_hum_charge[best_id] = per_hum_charge.get(best_id, 0) + intensity
    for hum_id in per_hum_charge:
        charge(hum_id, per_hum_charge[hum_id])
```

An emitter in range of two HUMs contributes only to the winner — purr is a broadcast signal, but a given purring cat is "sitting closer to this HUM than that one." Multiple cats within one receiver's radius sum additively.

## Drain

Per-HUM API on `HumSystem`:

```gdscript
func has_reserve(hum_id: int, cost: int) -> bool
func charge(hum_id: int, amount: int) -> void          # caps at capacity
func drain_action(hum_id: int, cost: int) -> void      # floors at 0
func drain_idle(hum_id: int) -> void                   # scales with reserve ratio
func get_reserve(hum_id: int) -> int
func get_capacity(hum_id: int) -> int
func get_reserve_ratio(hum_id: int) -> int             # 0..1000
func tick_idle_drain() -> void                         # iterates every hum entity
func tick_charge() -> void                             # emit/listen pass described above
```

There is no facility-wide reserve. Each HUM is its own battery. `FACILITY_ID=0` is reserved for non-HUM facility state; it does not carry a `hum` component.

## Power gate

`FoodSystem.is_powered(device_id, cost)` is the single power gate every drain site calls (button press, arm tick). Today it ignores `device_id` and returns the first HUM with enough reserve, or `INVALID_ID`:

```gdscript
func is_powered(_device_id: int, cost: int) -> int:
    for hum_id: int in _db.get_entities_with(&"hum"):
        if _hum.has_reserve(hum_id, cost):
            return hum_id
    return Constants.INVALID_ID
```

When the cable layer returns, this function takes per-device routing back: check for `&"hum_powered"`, look up the device's `&"hum_cable"` component, validate the wired HUM still exists, then check reserve. The contract for callers stays the same — `is_powered` returns a HUM id or `INVALID_ID`. See `docs/superpowers/specs/2026-05-09-cables-restoration-design.md`.

If `is_powered` returns `INVALID_ID`, the drain site no-ops silently — button presses return `INVALID_ID`, arm ticks skip the can. Graceful degradation, not an error state.

## Events

| Signal | Payload | Emitted by |
|---|---|---|
| `hum_reserve_changed` | `(hum_id, old_reserve, new_reserve)` | `HumSystem._emit_if_changed` |
| `hum_brownout_entered` | `(hum_id)` | `HumSystem._emit_if_changed` on cross into brownout band |
| `hum_brownout_recovered` | `(hum_id)` | inverse of above |

Aggregation for the HUD's single `HumBar` is a **display-side** sum across all HUM entities. Core brownout signals stay per-HUM — the HUD decides whether to aggregate, per-device dim, or both.

`cable_connected` and `cable_disconnected` are part of the cable-restoration spec, not currently emitted.

## Config

HUM internals (`DEFAULT_CAPACITY`, `IDLE_DRAIN_BASE`, `BROWNOUT_THRESHOLD`) live in `engine/core/hum_system.gd`. A config-externalization pass is future work. The cable-layer config (`mods/tcp_base/config/hum.jsonc` with `cable_max_length_ru`, `cable_sag_factor`) is detailed in the cable-restoration spec; it is not currently loaded.

## Non-goals (stay out of `purr` and HUM scope)

- Signal cables (button→dispenser wiring stays a same-rack placement rule).
- Server cabling (servers are wireless permanently).
- Multiple input ports per device (each actuator has exactly one input).
- Multiple cable types per device (`hum_cable` is the only cable type when cables return).
- Per-device `cable_max_length_ru` overrides.
- HUM output-port caps.
- Non-purr emission channels (chime, ring, electrical, thermal, kinetic) — each ships its own capability + receiver chain when the feature lands. Don't generalize the `purr` channel or the `hum_receiver` component to cover them.
- **Unifying `sensory_emissions` with `advertisements`.** Animals' dynamic emissions and objects' static ads are shaped similarly but stay separate surfaces. Ads carry occupant capacity, channel-effect direction, and slot-vs-radius delivery; emissions carry trigger gating, recipe-declared modifiers, and per-output components. Premature unification erases both surfaces' specific affordances.
- **Independent radius modifiers.** `radius_px` scales linearly with intensity (`base_radius_ru × SLOT_HEIGHT_PX × intensity / UNIT`) and only via that path. A future "muffler" component that reduces reach without reducing intensity is its own spec — do not add a separate `radius` modifier list inline.
- **dB or physically-correct acoustic units.** TCP doesn't simulate acoustic propagation; `radius_px` is a hard cutoff in rack-unit-derived pixels, not a dB-vs-distance computation. Linear thousandths (`UNIT = 1000`) stay the convention. Revisit only if real acoustic simulation (occlusion, Doppler, reverb) ships.

## Related

- `.claude/rules/core-loop.md` — design intent for the purr-power loop.
- `.claude/rules/tick-architecture.md` — contentment→purr bridge ordering.
- `.claude/rules/food-system.md` — how dispensers and arms call `is_powered`.
- `.claude/rules/signals.md` — signal patterns.
- `.claude/rules/modding.md` — `purr` as a capability tag.
- `.claude/rules/narrative.md` — Robot Cable Interpretation (player-facing log lines, including HUM brownout).
- `docs/superpowers/specs/2026-05-09-cables-restoration-design.md` — cable subsystem (currently absent; spec for restoration).
