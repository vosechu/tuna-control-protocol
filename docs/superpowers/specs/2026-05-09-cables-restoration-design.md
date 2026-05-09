# Cable Subsystem Restoration Design

> **Status:** spec for restoration. The cable layer between HUMs and HUM-powered actuators was removed in May 2026 to simplify Ring 0 and is not currently implemented. This document is the contract to restore.
>
> **Currently live (see `.claude/rules/hum-cable-system.md`):** HUM batteries, purr emission, contentment→purr bridge, per-tick charge. `FoodSystem.is_powered(device_id, cost)` ignores `device_id` and returns the first HUM with enough reserve.
>
> **Currently absent:** WiringSystem, CableLayer/View, WiringController, DanglingTip, the `hum_powered`/`hum_cable` capability tags, the `cable_connected`/`cable_disconnected` events, and `mods/tcp_base/config/hum.jsonc`.
>
> When restoration ships, fold this spec back into `.claude/rules/hum-cable-system.md` (or split a `cables.md`) and rewrite `FoodSystem.is_powered()` per the "Power check" section below.

## Components added

| Component | Shape | Carried by | Authority |
|---|---|---|---|
| `hum_powered` | `{}` (capability tag) | any device that needs a cable to operate | Server — saved |
| `hum_cable` | `{hum_id: int}` — which HUM this actuator is cabled to | a `hum_powered` device | Server — saved |

`hum_powered` is presence-only: the component's presence means "this device needs a HUM cable." The actuator's own `hum_cost` stays on its device-specific component (e.g. `tuna_dispenser.hum_cost`, `arm.hum_cost`).

## Cables

### Placement is a player decision, not automation

The player explicitly plugs each cable by clicking source → target in wiring mode. Servers and passive devices are wireless — they pick up the HUM's acoustic carrier from the field. Only kinetic actuators (dispensers, arms, future motors) need a direct cable for the concentrated carrier to perform physical work.

### "Needs a cable" is a capability, not a species

An entity needs a cable iff it carries `&"hum_powered"`. Mods add `hum_powered: {}` to any entity recipe and inherit the full cable pipeline without engine changes.

### Power check (replaces today's `is_powered`)

One helper, one gate — called by every drain site:

```gdscript
func is_powered(device_id: int, cost: int) -> int:
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

Drain sites (`food_system.press_button`, `food_system.tick_arms`) call `is_powered`, bail silently on `INVALID_ID`, and drain the returned HUM otherwise.

### Tombstone model (no eager cleanup)

When a HUM entity is destroyed, cables pointing at it become **tombstones**: the `hum_cable` component is still on the actuator but `has_entity(hum_id)` is false. `is_powered` treats tombstones as unpowered. No `cable_disconnected` event fires on HUM destruction — the HUM is gone; there's nothing to narrate. Stale components are cleaned up by the reload-validation pass. Forward-compatible: when `GameStateDB` gains lifecycle hooks (see `design-philosophy.md`), upgrade to eager cleanup with a `cable_disconnected` emit.

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

Each player owns a rack stripe (see `.claude/rules/networking.md`). Cables cannot cross stripes; `CABLE_CONNECT_INTENT` with endpoints on different stripes is rejected (`CABLE_DENIED{reason: "cross_stripe"}`). The global `cable_max_length_ru` is a separate check applied on top.

Floor entities (ARM) belong to the stripe whose rack range covers `nearest_rack_for(world_x)`; round toward the lower rack index if exactly on a boundary.

## Events added

| Signal | Payload | Emitted by |
|---|---|---|
| `cable_connected` | `(hum_id, device_id, cable_type)` — `cable_type = &"hum_power"` today | `WiringSystem` (write-then-emit) |
| `cable_disconnected` | `(old_hum_id, device_id)` | `WiringSystem` (write-then-emit) |

## Config added

`mods/tcp_base/config/hum.jsonc`:

```jsonc
{
  "schema_version": 1,
  "cable_max_length_ru": 20,   // max Euclidean distance between HUM and device in rack units
  "cable_sag_factor":   150    // catenary droop: max(3, length_px * factor / 1000)
}
```

## Wiring view (UI)

Tab (keyboard) or LB+RB (controller) toggles wiring mode. Click a HUM to start a fresh cable, or click an existing cable endpoint to **pick it up**. While a cable is in hand, the tip follows the cursor. Click a valid HUM-powered device to connect; the cable replaces any previous source atomically (one disconnect + one connect signal in the same tick). X (keyboard) / Y (controller) **deletes** the held cable. Escape / B **cancels** and retracts the cable to its original HUM. If the original HUM vanished mid-drag, the cable silently drops rather than stranding the cursor. Disconnect-without-pickup is gone: disconnect is always mediated through a pickup.
