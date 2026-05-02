---
paths:
  - "engine/core/hum_*"
  - "engine/core/contentment*"
  - "engine/core/food_system.gd"
  - "nodes/hud/hum_bar.gd"
---

# TCP HUM & Cable System

> **Status — 2026-05-02:** **CABLES NOT IMPLEMENTED.** The cable subsystem
> (WiringSystem, CableLayer/View, WiringController, DanglingTip, the
> `hum_powered` / `hum_cable` capability tags, the `cable_connected` /
> `cable_disconnected` events, and `mods/tcp_base/config/hum.jsonc`) was
> removed in May 2026 to simplify Ring 0. The HUM battery, the
> contentment→purr bridge, and the per-device charge loop remain live; the
> cable layer between HUMs and actuators is the only piece that's gone.
>
> Today's `FoodSystem.is_powered(device_id, cost)` returns the first HUM
> with enough reserve, ignoring `device_id`. When cables come back, restore
> this spec's gating contract verbatim.
>
> Everything below this banner is the **target design**, kept for the day
> cables ship again. Do not assume any of it is currently wired.

Per-device HUM batteries, emit/listen charging, and player-placed power cables to kinetic actuators. This is the mechanical spine of the purr-power loop described in `core-loop.md`.

## Components

| Component | Shape | Carried by | Authority |
|---|---|---|---|
| `hum` | `{reserve: int, capacity: int}` | HUM entities | Server — saved |
| `hum_receiver` | `{radius_px: int}` | HUM entities | Server — saved |
| `purr` | `{intensity: int}` — per-tick broadcast strength | any "thing that purrs" (cats in Ring 1) | Server — saved, written by contentment→purr bridge |
| `purr_config` | `{rate_when_satisfied: int}` | same recipe that declares `purr` | Server — materialized from recipe at spawn |
| `hum_powered` | `{}` (capability tag) | any device that needs a cable to operate | Server — saved |
| `hum_cable` | `{hum_id: int}` — which HUM this actuator is cabled to | a `hum_powered` device | Server — saved |

`hum_powered` is presence-only: the component's presence means "this device needs a HUM cable." The actuator's own `hum_cost` stays on its device-specific component (e.g. `tuna_dispenser.hum_cost`, `arm.hum_cost`).

## Emit / Listen, Not Produce / Consume

Cats don't produce HUM — cats purr. The HUM receiver listens for purrs and converts what it hears to stored charge. **The emitter never names HUM. The receiver never names cats.** Both sides talk only about the `purr` channel.

Consequences:
- New listeners on `purr` (future ferret-calm system, sound mixer, narrator) subscribe without touching cats.
- New emission kinds (chimes, rings, electrical current, thermal) get their **own** channel (`&"chime"`, `&"ring"`, `&"electrical_emission"`, …) and their **own** receiver + converter into the `hum` battery. They are not added to the purr channel post-hoc.
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

## Cables

### Placement is a player decision, not automation

The player explicitly plugs each cable by clicking source → target in wiring mode. Servers and passive devices are wireless — they pick up the HUM's acoustic carrier from the field. Only kinetic actuators (dispensers, arms, future motors) need a direct cable for the concentrated carrier to perform physical work.

### "Needs a cable" is a capability, not a species

An entity needs a cable iff it carries `&"hum_powered"`. Mods add `hum_powered: {}` to any entity recipe and inherit the full cable pipeline without engine changes.

### Power check

One helper, one gate — called by every drain site:

```gdscript
func _is_powered(device_id: int, cost: int) -> int:
    # Returns hum_id if the device can drain `cost`, else Constants.INVALID_ID.
    if not db.has_component(device_id, &"hum_powered"): return INVALID_ID
    if not db.has_component(device_id, &"hum_cable"):   return INVALID_ID
    var hum_id := db.get_field(device_id, &"hum_cable", &"hum_id")
    if hum_id == INVALID_ID:                            return INVALID_ID
    if not db.has_entity(hum_id):                       return INVALID_ID  # tombstone
    if not db.has_component(hum_id, &"hum"):            return INVALID_ID
    if not hum.has_reserve(hum_id, cost):               return INVALID_ID
    return hum_id
```

Drain sites (`food_system.press_button`, `food_system.tick_arms`) call `_is_powered`, bail silently on `INVALID_ID`, and drain the returned HUM otherwise.

### Tombstone model (no eager cleanup)

When a HUM entity is destroyed, cables pointing at it become **tombstones**: the `hum_cable` component is still on the actuator but `has_entity(hum_id)` is false. `_is_powered` treats tombstones as unpowered. No `cable_disconnected` event fires on HUM destruction — the HUM is gone; there's nothing to narrate. Stale components are cleaned up by the reload-validation pass. Forward-compatible: when `GameStateDB` gains lifecycle hooks (see `design-philosophy.md`), upgrade to eager cleanup with a `cable_disconnected` emit.

### Disconnect is instant

No grace period. Player pulls the cable → device stops this tick. Event emission is cause-agnostic — player disconnect, system cleanup, future kitten disconnect all go through the same write-then-emit path.

## Signal Ordering (Write Then Emit)

Every cable mutation follows this order. Listeners always observe either the pre-write state or the post-write state, never mid-transition.

**Fresh connect:**
1. `db.set_component(device_id, &"hum_cable", {hum_id})`
2. `Events.cable_connected.emit(hum_id, device_id, &"hum_power")`

**Disconnect:**
1. Capture `old_hum_id = db.get_field(device_id, &"hum_cable", &"hum_id")`
2. `db.remove_component(device_id, &"hum_cable")`
3. `Events.cable_disconnected.emit(old_hum_id, device_id)`

**Replace (connect on an already-cabled device):**
1. Capture `old_hum_id`.
2. `db.set_component(device_id, &"hum_cable", {hum_id: new_hum_id})` — single write overwrites.
3. `Events.cable_disconnected.emit(old_hum_id, device_id)`
4. `Events.cable_connected.emit(new_hum_id, device_id, &"hum_power")`

Same-tick disconnect+connect pairs are coalesced into one narrator line ("re-coupled through alternate bridge"). See `.claude/rules/narrative.md`.

## Server Authority & Pickup Locks

Wiring state is server-authoritative; clients send intents, server validates and broadcasts deltas.

**Transient pickup state table** (server, not saved to GameStateDB, but *readable by the save serializer*):

```
endpoint_key → {owner_peer_id, tick, original_hum_id, original_actuator_id}
```

`endpoint_key = "hum:<hum_id>:cable:<actuator_id>"` for HUM-end pickup; `"actuator:<actuator_id>"` for actuator-end pickup. Keying by the cable's actuator id on both sides means two players picking up two different cables out of the same HUM get distinct lock entries.

The table serves two purposes:
1. **MP pickup lock** — prevents two peers grabbing the same endpoint.
2. **Mid-drag source of truth** — the save serializer reads this table together with live DB rows to reconstruct any cable currently being dragged.

Locks auto-expire after ~200 ticks (20s @ 10Hz) of peer inactivity.

### Save mid-drag

The serializer does **not** mutate live state to "retract" a held cable. It writes the union of:

1. All live `hum_cable` components, plus
2. For any pickup entry with `original_hum_id != INVALID_ID`, a synthetic `hum_cable` row on `original_actuator_id` → `original_hum_id`.

Live state stays whatever it is; saved state represents "what we'd restore to if the drag cancelled." Pickup ordering: the pickup intent populates the table *before* it removes the `hum_cable` component (steps 1→2 above), so a same-tick save always sees a consistent synthetic row.

### Reload

Load entities first. On a second pass, drop any `hum_cable` whose `hum_id` doesn't resolve to a live `hum`-carrying entity. Log each drop.

### Rack-stripe validation

Each player owns a rack stripe (see `networking.md`). Cables cannot cross stripes; `CABLE_CONNECT_INTENT` with endpoints on different stripes is rejected (`CABLE_DENIED{reason: "cross_stripe"}`). The global `cable_max_length_ru` is a separate check applied on top.

Floor entities (ARM) belong to the stripe whose rack range covers `nearest_rack_for(world_x)`; round toward the lower rack index if exactly on a boundary.

## Events

| Signal | Payload | Emitted by |
|---|---|---|
| `hum_reserve_changed` | `(hum_id, old_reserve, new_reserve)` | `HumSystem._emit_if_changed` |
| `hum_brownout_entered` | `(hum_id)` | `HumSystem._emit_if_changed` on cross into brownout band |
| `hum_brownout_recovered` | `(hum_id)` | inverse of above |
| `cable_connected` | `(hum_id, device_id, cable_type)` — `cable_type = &"hum_power"` today | `WiringSystem` (write-then-emit) |
| `cable_disconnected` | `(old_hum_id, device_id)` | `WiringSystem` (write-then-emit) |

Aggregation for the HUD's single `HumBar` is a **display-side** sum across all HUM entities. Core brownout signals stay per-HUM — the HUD decides whether to aggregate, per-device dim, or both.

## Config

`mods/tcp_base/config/hum.jsonc`:

```jsonc
{
  "schema_version": 1,
  "cable_max_length_ru": 20,   // max Euclidean distance between HUM and device in rack units
  "cable_sag_factor":   150    // catenary droop: max(3, length_px * factor / 1000)
}
```

HUM internals (`DEFAULT_CAPACITY`, `IDLE_DRAIN_BASE`, `BROWNOUT_THRESHOLD`) currently live in `engine/core/hum_system.gd`. A config-externalization pass is future work.

## Non-goals (stay out of `purr` / `hum_cable`)

- Signal cables (button→dispenser wiring stays a same-rack placement rule).
- Server cabling (servers are wireless permanently).
- Multiple input ports per device (each actuator has exactly one input).
- Multiple cable types per device (`hum_cable` is the only cable today).
- Per-device `cable_max_length_ru` overrides.
- HUM output-port caps.
- Non-purr emission channels (chime, ring, electrical, thermal, kinetic) — each ships its own capability + receiver chain when the feature lands. Don't generalize the `purr` channel or the `hum_receiver` component to cover them.

## Related

- `.claude/rules/core-loop.md` — design intent for the purr-power loop.
- `.claude/rules/tick-architecture.md` — contentment→purr bridge ordering.
- `.claude/rules/food-system.md` — how dispensers and arms call `_is_powered`.
- `.claude/rules/signals.md` — signal patterns, cable scenario trace.
- `.claude/rules/modding.md` — `hum_powered` / `hum_cable` / `purr` as capability tags.
- `.claude/rules/narrative.md` — Robot Cable Interpretation (player-facing log lines).
