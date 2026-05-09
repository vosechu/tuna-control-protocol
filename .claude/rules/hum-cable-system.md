---
paths:
  - "engine/core/hum_*"
  - "engine/core/contentment*"
  - "engine/core/food_system.gd"
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
| `purr` | `{intensity: int}` — per-tick broadcast strength | any "thing that purrs" (cats in Ring 1) | Server — saved, written by contentment→purr bridge |
| `purr_config` | `{rate_when_satisfied: int}` | same recipe that declares `purr` | Server — materialized from recipe at spawn |

## Emit / Listen, Not Produce / Consume

Cats don't produce HUM — cats purr. The HUM receiver listens for purrs and converts what it hears to stored charge. **The emitter never names HUM. The receiver never names cats.** Both sides talk only about the `purr` channel.

Consequences:
- New listeners on `purr` (future ferret-calm system, sound mixer, narrator) subscribe without touching cats.
- New emission kinds (chimes, rings, electrical current, thermal) get their **own** channel (`&"chime"`, `&"ring"`, `&"electrical_emission"`, …) and their **own** receiver. What the receiver does with the signal — charge HUM, calm ferrets, drive lights, narrate — is a per-channel decision; not every emission feeds HUM. They are not added to the `purr` channel post-hoc, and the `purr` channel and `hum_receiver` component aren't generalized to cover them.
- `HumSystem.tick_charge()` branches only on the `hum_receiver`, `purr`, and `position` capabilities. It never reads `contentment`, `is_satisfied`, or species labels.

### Contentment → purr bridge

A small system (`engine/core/contentment_purr_bridge.gd`) runs each tick **before** `tick_charge()`. For every entity carrying both `contentment` and `purr`:

```
intensity = purr_config.rate_when_satisfied   if contentment.is_satisfied == 1
intensity = 0                                  otherwise
```

The bridge knows `contentment` and `purr`. It does not know HUM exists. Entities that carry `purr` but not `contentment` are left alone — their intensity is whatever another system wrote, which is the correct shape for future non-contentment purr sources.

`rate_when_satisfied` lives in the species recipe (e.g. `mods/tcp_cats/species/cat.jsonc`), never as an engine constant. The recipe declares one `purr: {rate_when_satisfied: N}` block; spawn materializes it into two components — `purr {intensity: 0}` (per-tick scratch) and `purr_config {rate_when_satisfied: N}` (recipe value the bridge reads).

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

## Related

- `.claude/rules/core-loop.md` — design intent for the purr-power loop.
- `.claude/rules/tick-architecture.md` — contentment→purr bridge ordering.
- `.claude/rules/food-system.md` — how dispensers and arms call `is_powered`.
- `.claude/rules/signals.md` — signal patterns.
- `.claude/rules/modding.md` — `purr` as a capability tag.
- `.claude/rules/narrative.md` — Robot Cable Interpretation (player-facing log lines, including HUM brownout).
- `docs/superpowers/specs/2026-05-09-cables-restoration-design.md` — cable subsystem (currently absent; spec for restoration).
