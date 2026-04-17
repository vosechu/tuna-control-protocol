# HUM Cable Hookup — Design Spec

> **Status:** brainstormed + dev-team reviewed 2026-04-17. Ready for implementation planning. Scope: Ring 1 of purr-power.
>
> **Supersedes:** "The HUM is a global resource pool within a bay" language in `docs/superpowers/specs/2026-04-12-purr-power-ring0-design.md`. Ring 1 moves HUM from a singleton facility pool to per-device batteries (see Phase 1 below).

---

## The One Sentence

The player runs HUM power cables from HUM devices to kinetic actuators (TUNA dispenser, ARM); each HUM is its own battery, each actuator draws only from the HUM it's cabled to, and servers and other passive devices stay wireless.

---

## Design Commitments (non-negotiable)

1. **Cable is a placement decision, not automation.** The player explicitly plugs each cable. No auto-wiring.
2. **Servers and passive devices are wireless.** The HUM device's gramophone radiates an acoustic harmonic carrier; passive devices (servers, lights) pick it up from the field. Only kinetic actuators (TUNA, ARM) need a direct cable for the concentrated carrier required to perform physical work.
3. **Each HUM is its own battery.** No global pool. Any entity emitting on the `&"purr"` channel near HUM-A contributes to HUM-A's reserve at the emission's intensity. A cable from HUM-A to a TUNA drains HUM-A. HUM-B and its cables are independent. Discovered-through-play tension: "why is this dispenser dark when the other one's fine?" → because you cabled it to a HUM without purring animals in range.

4. **Emit / listen, not produce / consume.** Cats don't produce HUM — cats purr. HUM receivers (the gramophone on top of the HUM device) listen for purrs and convert what they hear into stored charge on the HUM battery. The emitter never names HUM. The receiver never names cats. Both sides talk only about the purr channel. Future listeners on the purr channel (ferret-calm system, sound mixer, narrator) can subscribe without touching cats. Future *other* signals (chimes, rings, electrical current) get their *own* channels and their *own* receivers — they're not added to the purr channel post-hoc.

5. **Purring is a cat capability in Ring 1. It is not a generic acoustic channel.** `&"purr"` is the emitter component specifically for cats. `intensity` is the per-tick broadcast strength. A small *contentment→purr* bridge writes `intensity = rate_when_satisfied` while the cat is content, and `0` otherwise — so in tcp_base the sole source of HUM charge is contented cats, preserving the "encourage meeting needs" loop. The bridge is scoped: it knows `contentment` and `purr`, never HUM. Any future cat-like species with a `contentment` component can participate by declaring `purr` in its recipe; that's species-agnostic within "things that purr."

6. **Other emission types are designed when they ship, not speculatively.** A wind chime doesn't purr — it chimes. A tuning fork rings. A solar panel is electrical. Each gets its own emission capability (`&"chime"`, `&"ring"`, `&"electrical_emission"`) and its own listener / input chain to the HUM battery when the feature actually lands. Ring 1 ships exactly one input: `purr` → `hum_receiver` → `hum` battery. The HUM battery is future-compatible: any later input chain writes to the same `hum` component on the HUM entity via its own converter. No work-to-be-done here — just don't foreclose.
7. **"Needs a cable" is a capability, not a species.** An entity needs a power cable iff it has the `&"hum_powered"` component. Any mod can add this component to any entity and inherit the full cable pipeline without touching engine code.
8. **Distance limit is a config number, not a constant.** Ring 1 ships with 20 RU (≈ 2 racks, permissive). Tightens when tech tower redefines rack density.
9. **Disconnect is instant off, no grace period.** Player pulls the cable, the device stops this tick. No hidden buffer.
10. **Event emission is cause-agnostic.** Player disconnect, kitten disconnect (Ring 2), system cleanup on HUM despawn — all emit the same `cable_disconnected` via the same path. Subscribers never branch on cause.
11. **Cables visible at all times.** Faded in normal mode, full-opacity in wiring mode. No hidden state.
12. **Server-authoritative wiring state.** `hum_cable` components and pickup locks live on the server. Clients send intents; server validates and broadcasts deltas. Matches TCP's "networking from day one" commitment.
13. **Unpowered devices are never blamed.** Dim LED + "no carrier" subtle flicker is the whole visual language. No warning badges, no red outlines, no exclamation marks. The player learns through gentle absence, not accusation.

---

## Scope

### In Ring 1

**Phase 0 — Testability prerequisites (must land first):**
- **Minimal starter content.** On new game, world-init places a known layout of: 1 HUM device (rack 0, slots 0-5), 1 TUNA dispenser (rack 2, slot 1), 1 TUNA button (rack 2, slot 2), 1 ARM on the floor, 2 starter `tcp_cats:cat` entities (starter scenario uses this concrete species; the system itself only reads capabilities). Enough infrastructure to demonstrate and QA the cable loop end-to-end in a fresh session. Implementation: a small scenario file at `mods/tcp_base/scenarios/starter.jsonc` consumed by a world-init system; zero new placement UI required.
- **Debug contentment override.** A dev-only key (`Shift+F1`, gated behind a `debug.enabled` flag in settings; **not F11** — that conflicts with Godot's default fullscreen toggle) that sets `debug_force_satisfied = true` on the currently-inspected contentment-bearing entity (or all entities with `contentment` components if no inspection target). The contentment system honors the debug flag when deriving `is_satisfied` — overriding the desires→contentment derivation rather than writing directly to the derived flag (which would fight the state machine). Required because the Ring 0 pet→satisfied→purr chain is currently non-functional — without this, QA cannot verify the cable loop's drain behavior. Cost: ~30 lines. Must be stripped or behind the debug gate in release builds; spec includes a release-build assertion that debug binds are not registered.

**Phase 1 — HUM refactor prerequisite (must land first):**
- Move `hum` component (reserve, capacity) from singleton `FACILITY_ID` to per-entity HUM devices.
- Multiple HUM devices supported.
- Introduce `&"purr"` emitter component (field: `intensity: int`, current broadcast strength). Ring 1 only attaches this component to cats.
- Charge (`tick_charge`): each HUM receiver queries entities with `&"purr"` within `hum_receiver.radius_ru`, sums their intensities, credits the HUM's reserve. The HumSystem hardcodes `&"purr"` as its one input channel in Ring 1; it does not read `contentment`, `is_satisfied`, or species labels. Non-purr channels (future chimes, rings, electrical inputs) are out of scope — each ships with its own receiver variant and its own converter into the `hum` battery, not by being added to the purr pipeline.
- Introduce a "contentment→purr bridge" (small system or a step in the existing contentment logic). Each tick, for entities with both `contentment` and `purr`: if `contentment.is_satisfied == 1`, write `purr.intensity = rate_when_satisfied` from the species recipe; else `purr.intensity = 0`. Bridge knows `contentment` and `purr` only — it does not know HUM exists.
- `rate_when_satisfied` lives in the cat recipe (`mods/tcp_cats/species/cat.jsonc`) — not a hardcoded engine constant. Any future species that also purrs (a hypothetical tcp_base purring ferret variant, modded purring species) can declare the same `purr` component in its recipe; no engine change required. Species that make *different* sounds (chimes, rings) get their own emission capability and their own receiver chain when added.
- **Multiple listeners on the purr channel (forward-compatible):** the HUM receiver is the only Ring 1 listener, but the shape supports adding more. A future ferret-calm system reads `purr` components within its own listening radius. A future sound-mix system reads them too. None of these listeners modify each other; the emitter writes once, multiple readers consume independently.
- Drain (`drain_action(hum_id, cost)`): operates on a specific HUM's reserve.
- Brownout state: per-HUM. HUD aggregates for display but core logic is per-entity.

**Phase 2 — Cable system:**
- `&"hum_powered"` capability tag on TUNA and ARM configs.
- `&"hum_cable"` component on HUM-powered devices (field: `hum_id: int`, sentinel `Constants.INVALID_ID`).
- HUM → TUNA dispenser cable (power).
- HUM → ARM cable (power).
- Cable placement UX (wiring mode: click source → click target).
- Cable disconnection UX (wiring mode: click endpoint → cable dangles → click target to reconnect / `X` to delete / `Escape` to retract to original).
- Wiring overlay mode (keyboard `Tab`, controller `LB+RB`, existing `WiringViewToggle` button on HUD).
- Cable rendering (catenary curve with min-sag floor; warm-amber cloth-cord material).
- Power check in `food_system.gd::press_button()` and `food_system.gd::tick_arms()` gated by `hum_cable` + `has_entity(hum_id)` + `has_reserve`.
- Save format (see Data Model below).
- Server-authoritative pickup locks (MP safety).
- Event emission: `cable_connected(hum_id, device_id, &"hum_power")` and `cable_disconnected(hum_id, device_id)`.
- Assets: `cable_pop_01.wav` (new), pickup cue `cable_lift_01.wav` (new). Reuse existing place-deny audio.
- Robot narrator log lines for connect / disconnect / deny / pressed-unpowered / first-ever-cable.
- Cross-rack-stripe connect rejection (multiplayer safety).

### Explicit non-goals / deferred to other specs

These are known gaps that **affect** testability of this feature but are **not** part of this spec's scope. Surfacing them so nothing gets absorbed by accident:

- **Fix the pet→satisfied→purr→charge chain.** Confirmed broken as of 2026-04-17 (petting does nothing observable). Ring 0 regression or incomplete Ring 0 wiring. This spec works around it with the debug contentment override in Phase 0; **fixing the real chain is a separate ticket** and is a prerequisite for the feature to be playable without debug overrides. Flag it for the Ring 0 work queue.
- **Controller petting interaction.** Ring 0 pet verb assumes click-on-animal. Controller equivalent (focus-an-animal + Y?) is undefined. Out of scope here. Same Ring 0 ticket as the chain fix.
- **Animals entering boxes / sitting on servers.** The "visible contentment feedback loop" depends on animals using infrastructure (occupying boxes, resting on servers). This is a larger animal-interaction feature; not this spec. Debug contentment override is the dev workaround.
- **HUM device placement drawer.** TCP doesn't have a placement drawer concept yet. Starter content (Phase 0) provides pre-placed HUMs. If/when the drawer system lands, HUM slots into it; no spec update needed.

### Out of scope (Ring 2+)

- Signal cables (button → TUNA dispenser remains a same-rack placement rule).
- Server cabling (servers stay wireless permanently).
- Kitten disconnect behavior (event hooks exist; AI deferred).
- Cable runs / conduits / organizers (the eventual solution to both visual clutter and kitten disconnects).
- Cable length re-validation on device relocation (devices don't move post-placement in Ring 1).
- Multiple input ports per device (each actuator has exactly 1 input).
- Multiple cable types per device (`hum_cable` is the only cable type; no coolant, no signal).
- Per-device `cable_max_length_ru` overrides (global only).
- HUM output-port caps (unlimited in Ring 1).
- Non-purr emission channels (chime, ring, electrical, thermal, kinetic). Each gets its own capability + receiver chain when the feature that needs it ships. Not a generic "acoustic" or "carrier" channel.

---

## Phase 0: Testability Prerequisites

### Starter scenario

New file: `mods/tcp_base/scenarios/starter.jsonc` (under a new `scenarios/` subdir — follows the `objects/`, `species/`, `sounds/`, `sprites/`, `config/` typed-subdir convention; root-level files in `tcp_base/` stay reserved for `mod.json`).

```jsonc
{
  "schema_version": 1,
  "id": "tcp_base:starter",
  "entities": [
    { "type": "tcp_base:hum_device",     "rack": 0, "slot": 0 },
    { "type": "tcp_base:tuna_dispenser", "rack": 2, "slot": 1 },
    {
      "type": "tcp_base:tuna_button",
      "rack": 2, "slot": 2,
      "dispenser_ref": { "rack": 2, "slot": 1 }
    },
    { "type": "tcp_base:arm",  "floor_rack": 0, "floor_slot_offset": 0 },
    { "type": "tcp_cats:cat",  "rack": 0, "slot": 7, "required": false },
    { "type": "tcp_cats:cat",  "rack": 0, "slot": 8, "required": false }
  ]
}
```

Reference-resolution uses structured objects (`{rack, slot}`), not an in-band string DSL. The mod loader validates via JSON schema.

Scenarios live per-mod under `mods/<mod_id>/scenarios/<id>.jsonc`. The world-init system scans all loaded mods, and on new game reads the scenario identified by `settings.starter_scenario_id` (default `"tcp_base:starter"`). ID-based selection — mods override by offering an alternative, not by shadowing tcp_base's file. Single setting swap enables "hard mode," tutorial, or bay-only scenarios without forking `tcp_base`.

**Load ordering:** scenarios load after all mods have registered their entity types (otherwise `tcp_cats:cat` won't resolve). World-init runs at the GameServer new-game branch (not the save-load branch), *after* mod init finishes.

**Required vs. optional entities:** each entry accepts an optional `"required": true|false` (default: `true`). If any required entity fails resolution (e.g., `tcp_base:hum_device` missing because `tcp_base` didn't load — shouldn't happen, but guard), world-init aborts with a dev-visible `push_error`. Optional entities (like starter species from a third-party species mod) are skipped silently if their type fails. Prevents "HUM in empty world" partial-populate.

**Idempotency:** world-init only runs on new games. The save root stores `starter_scenario_applied: true` after population. On any reload — corrupt save fallback, schema-mismatch recovery, MP peer state sync — the flag prevents re-population. World-init checks the flag, not save presence.

**Screen reader onboarding:** on first boot of a new scenario, the robot narrator emits a one-time inventory log: `"Boot complete. Inventory shows pre-arranged devices and two unidentified spindles already present. I do not recall placing them. Continuing."` Enumerates the populated entities in a follow-up log line accessible to assistive tech via the existing narrator log surface.

### Debug contentment override

In the HUD's existing inspect flow (or a new debug-only path): `Shift+F1` sets `debug_force_satisfied = true` on the inspected contentment-bearing entity (or all entities with `contentment` components if inspection is empty). The contentment derivation honors this flag and sets `is_satisfied = 1` regardless of desire levels. Gated behind `settings.debug.enabled = true` — zero-cost in release.

Purpose: let QA exercise the cable drain loop (cable connects HUM to TUNA → satisfied entity within HUM's receiver radius → HUM charges → TUNA button works) without depending on the broken pet chain.

### Exit criteria for Phase 0

- New game loads into a world with 1 HUM, 1 TUNA (+button), 1 ARM, 2 starter cats visible (starter scenario concrete species; system itself is species-agnostic).
- `Shift+F1` on an inspected contentment-bearing entity toggles satisfaction visibly (entity shows purr indicator, HUM starts charging).
- No existing tests regress; Phase 0 is purely additive.

---

## Phase 1: HUM Per-Device Refactor

### What changes

**Before (current code):**
```gdscript
# hum_system.gd
const FACILITY_ID: int = 0
func _init(db, events): _db.create_entity_with_id(FACILITY_ID); ...
func charge(amount): var r = _db.get_field(FACILITY_ID, &"hum", &"reserve"); ...
func drain_action(cost): var r = _db.get_field(FACILITY_ID, &"hum", &"reserve"); ...
```

**After:**
```gdscript
func charge(hum_id: int, amount: int) -> void:
    assert(_db.has_component(hum_id, &"hum"), "charge() on non-HUM entity")
    ...
func drain_action(hum_id: int, cost: int) -> void:
    assert(_db.has_component(hum_id, &"hum"), "drain_action() on non-HUM entity")
    ...
func has_reserve(hum_id: int, cost: int) -> bool: ...
func get_reserve(hum_id: int) -> int: ...
func get_capacity(hum_id: int) -> int: ...
func get_reserve_ratio(hum_id: int) -> int: ...
```

`tick_charge()` groups entities with `&"purr"` (purr emitters) by nearest HUM receiver and credits each HUM the sum of `purr.intensity` within that receiver's `hum_receiver.radius_ru`. An ambiguous emitter (in range of two HUMs) goes to the nearest; ties broken by lower entity id. The HumSystem code branches only on the `hum_receiver` and `purr` capabilities — it never reads `contentment`, `is_satisfied`, or species labels.

**Contentment→purr bridge:** a small system (a step in the contentment system, or a sibling helper) updates `purr.intensity` each tick for any entity that has both `contentment` and `purr` components. Pseudocode:

```gdscript
# Runs each tick, before tick_charge (batch column op):
# For every entity e with both components:
#   rate_cfg = e.species_recipe.purr.rate_when_satisfied
#   e.purr.intensity = rate_cfg if e.contentment.is_satisfied == 1 else 0
```

Idempotent — runs every tick regardless of transitions. Cheap. The HumSystem reads whatever is there at scatter time. This bridge knows about `contentment` and `purr`; it does not know HUM exists.

**Other emission types** (wind chimes, tuning forks, solar panels, hamster wheels, generators) are **not** purr emitters and are out of scope for Ring 1. Each earns its own emission capability and its own listener / converter chain when implemented. The `hum` battery component on the HUM entity is shared — any future input path writes to the same battery via its own dedicated converter. Ring 1 ships exactly one input chain: cats → `purr` → `hum_receiver` (gramophone) → `hum` battery.

**Multiple listeners on the purr channel.** Ring 1 ships only the HUM listener, but the shape is ready for more: a future ferret-calm listener reads `purr` components within its own hearing radius and adjusts calm state; a future sound-mix listener reads them to decide aggregate purr volume. Listeners don't interact; each is an independent reader of the emitter side.

**Tick ordering:** the contentment→purr bridge runs **before** `tick_charge()` each tick, so charge reads the current intensity. `tick_charge()` itself runs before any HUM despawn processing. Document in `tick-architecture.md` alongside the existing scatter order.

`tick_idle_drain()` iterates all HUMs, each drains independently on the existing decaying curve.

### HUD aggregation

The existing `hum_bar.gd` shows a single reserve bar. Post-refactor: the bar shows **aggregate** reserve summed across all HUMs (with capacity also summed). The brownout trigger becomes "any HUM below threshold" OR "aggregate below threshold" — playtest picks. Per-HUM bars deferred.

### Facility entity

`FACILITY_ID=0` continues to exist for non-HUM facility state (future: facility-level settings). It loses the `hum` component.

### Events

- `hum_reserve_changed(hum_id, old_reserve, new_reserve)` — now takes a HUM entity id.
- `hum_brownout_entered(hum_id)` — per HUM.
- `hum_brownout_recovered(hum_id)` — per HUM.

All three signals get a `hum_id` parameter added. Existing HUD / narrator listeners update to filter or aggregate.

### Migration

No save migration needed for Ring 1 (no player saves have multiple HUMs today). The migrator bumps schema version and the loader constructs `hum` components on all HUM entities from their config defaults.

### Tests (Phase 1 exit criteria)

- Unit: `test_hum_per_entity_charge` — two HUMs, purr emitter near HUM-A, HUM-A's reserve increases, HUM-B's unchanged.
- Unit: `test_hum_per_entity_drain` — two HUMs, drain HUM-A; HUM-B untouched.
- Unit: `test_hum_receiver_nearest_assignment` — emitter equidistant to HUM-A and HUM-B, deterministic tie-break by entity id.
- Unit: `test_purr_intensity_drives_charge` — entity with `purr.intensity = 10` charges the nearest HUM receiver +10/tick when in range; intensity = 0 contributes nothing; no contentment component required on the emitter.
- Unit: `test_contentment_bridge_writes_purr_intensity` — entity with both `contentment` and `purr`; satisfied → intensity matches recipe's `rate_when_satisfied`; unsatisfied → intensity = 0.
- Unit: `test_purr_without_contentment_is_stable` — entity with only `purr` (no contentment) keeps its intensity across ticks; the contentment bridge's `has_component(&"contentment")` guard leaves it alone. Not a user-facing Ring 1 case, but the test proves the bridge's guard is correct so future purring species without contentment (if ever) don't get their intensity zeroed.
- Unit: `test_hum_listener_does_not_read_contentment` — HumSystem's charge loop is verified not to branch on `contentment` / `is_satisfied` / species labels. Only `hum_receiver`, `purr`, `position`.
- Integration: existing HUD shows sum; existing food/arm systems still work with one HUM (no regression).

---

## Phase 2: Cable System

### Capability tag: `&"hum_powered"`

A new component on any entity that needs a HUM cable to operate:

```jsonc
// In tuna_dispenser.jsonc
"hum_powered": {},

// In arm.jsonc
"hum_powered": {},
```

Empty-dict component (a capability tag per `design-philosophy.md`). Presence of the component = "this entity needs a HUM cable to operate." `hum_cost` stays on the device-specific component (`tuna_dispenser.hum_cost`, `arm.hum_cost`) — don't overextend the refactor.

The existing `tuna_dispenser` and `arm` component definitions remain intact. They describe *what the device does*. `hum_powered` describes *what the device needs*. Orthogonal.

**Narrative note:** the robot-voice framing of "kinetic actuators vs passive resonators" stays in narrative surfaces (robot logs, narrator.md lore). The tag is named `hum_powered` because that's mechanically precise for modders and readers; the narrative distinction between kinetic-work-devices and passive-broadcast-devices lives in the robot's in-fiction vocabulary, not the component name.

### Component: `&"hum_cable"`

```
Component: &"hum_cable"
Fields:
  hum_id: int   # entity id of the HUM this actuator is cabled to (Constants.INVALID_ID = no cable)
```

Naming: `hum_cable` (not `powered_by`) — reads as a connection, not a boolean state. Upgrades to an `add_relationship(&"hum_cable", actuator, hum)` entry if/when the generic relationship table lands in GameStateDB.

### Power check (inserted in existing drain sites)

Helper lives on `FoodSystem`:

```gdscript
func _is_powered(device_id: int, cost: int) -> int:
    # Returns hum_id if device can drain `cost`, else Constants.INVALID_ID.
    if not _db.has_component(device_id, &"hum_powered"):
        return Constants.INVALID_ID   # device doesn't need a cable (shouldn't reach here)
    if not _db.has_component(device_id, &"hum_cable"):
        return Constants.INVALID_ID
    var hum_id: int = _db.get_field(device_id, &"hum_cable", &"hum_id")
    if hum_id == Constants.INVALID_ID:
        return Constants.INVALID_ID
    if not _db.has_entity(hum_id):
        return Constants.INVALID_ID   # dangling ref after HUM despawn
    if not _db.has_component(hum_id, &"hum"):
        return Constants.INVALID_ID   # entity exists but isn't a HUM anymore
    if not _hum.has_reserve(hum_id, cost):
        return Constants.INVALID_ID
    return hum_id
```

Called from `press_button()` (TUNA path) and `tick_arms()` (ARM path). Drain becomes `_hum.drain_action(hum_id, cost)`. If `_is_powered` returns `INVALID_ID`, bail before drain; emit "pressed while unpowered" event for narrator (TUNA path only).

### HUM despawn: tombstone model (not eager cleanup)

Round 2 Bramble flagged that eager pre-despawn cleanup requires a lifecycle hook that doesn't exist yet (`Events.object_removed` fires *after* `destroy_entity`). Rather than inventing a new signal, `hum_cable` components become **tombstones** when their `hum_id` points at a destroyed entity.

The `_is_powered` guard (`if not _db.has_entity(hum_id): return INVALID_ID`) makes tombstone cables safe at read time — no drain, no stale state mutation. The stale component is cleaned up by the reload-validation pass (see Save/reload below) or by explicit disconnect/replace actions.

**Tradeoffs:**
- **Narrator silent on HUM despawn.** No `cable_disconnected` fires when the HUM is destroyed out from under a cable. Arguably correct — the HUM is gone, there's nothing left to narrate. Robot narrator doesn't learn about it until the player tries to drain and the button fails (existing button-pressed-unpowered log covers this).
- **Mid-drag safety.** If a player has a cable picked up and the HUM referenced by the pickup entry's `original_hum_id` despawns, that reference becomes a tombstone. The wiring controller's "click target to reconnect" path validates the target exists; "Escape to retract" validates the server's pickup entry still refers to a live HUM via `has_entity(original_hum_id)`. If either validation fails, retract-on-cancel falls back to delete (same as cross-stripe denial — audio + log, no re-add).
- **Double-destroy race.** If two peers destroy the same HUM, the second `destroy_entity` call hits a no-op because `has_entity` returns false. Safe.

**Forward-compatible:** when `GameStateDB` gains lifecycle hooks per `design-philosophy.md`, this spec upgrades to eager cleanup with a `cable_disconnected` emit.

### Cable state

**Persistent (in GameStateDB, server-authoritative, saved):**
- `hum_cable` component on each cabled actuator.

**Transient (server-side, not saved):**
- Pickup state table: `Dictionary[endpoint_key -> {owner_peer_id: int, tick: int, original_hum_id: int, original_actuator_id: int}]`. `endpoint_key` = `"hum:<hum_id>:cable:<actuator_id>"` for a HUM-end pickup, or `"actuator:<actuator_id>"` for an actuator-end pickup. Keying by the cable's actuator_id in both cases means two players picking up two different cables out of the same HUM get distinct lock entries and never collide on the same key. Serves two purposes: (a) pickup lock for MP (prevents contested grabs); (b) original-connection record so mid-drag saves can reconstruct the pre-pickup cable. Locks auto-expire after N ticks of peer inactivity (e.g., 20s @ 10Hz = 200 ticks). Original-connection fields use `Constants.INVALID_ID` when a fresh cable is being dragged (no prior connection to restore).

**Transient (client-side, not saved, not networked):**
- Local drag state for the active wiring-mode drag: `{picked_up_from, cursor_world_pos}`. Used only for rendering the catenary between the fixed end and the cursor. The authoritative "what was this cable originally connected to" lives in the server's pickup state table.

### Write-then-emit signal ordering (blocking fix)

All cable mutations follow this order, end-of-tick batched where possible:

**Fresh connect:**
1. `db.set_component(device_id, &"hum_cable", {hum_id: hum_id})`
2. `Events.cable_connected.emit(hum_id, device_id, &"hum_power")`

**Disconnect (player pickup, kitten later, system cleanup):**
1. Capture `old_hum_id = db.get_field(device_id, &"hum_cable", &"hum_id")`
2. `db.remove_component(device_id, &"hum_cable")`
3. `Events.cable_disconnected.emit(old_hum_id, device_id)`

**Replace (connecting to a new HUM):**
1. Capture `old_hum_id`.
2. `db.set_component(device_id, &"hum_cable", {hum_id: new_hum_id})` *(single write; overwrites)*
3. `Events.cable_disconnected.emit(old_hum_id, device_id)`
4. `Events.cable_connected.emit(new_hum_id, device_id, &"hum_power")`

Within a single tick, listeners see exactly one of: pre-write state, post-write state. Never a mid-transition observation of "connected to both." Narrator coalesces same-tick disconnect+connect pairs into a single "re-coupled through alternate bridge" log line.

### Save/reload

**Save mid-drag (no live-state mutation):** Round 2 Bramble flagged that mutating GameStateDB during snapshot breaks the determinism guarantee. Revised: the snapshot serializer reads **from the pickup state table**, not from the live DB alone, to reconstruct the pre-pickup cable. The snapshot payload contains `hum_cable` rows derived from:
  1. All live `hum_cable` components in the DB (normal path), PLUS
  2. For any active pickup entry with `original_hum_id != INVALID_ID` and `original_actuator_id != INVALID_ID`, a synthetic `hum_cable` row on the original actuator pointing at the original HUM.

No DB mutation. Live state remains whatever the tick said; the saved state represents "what we'd restore to if the drag cancelled."

**Pickup → save ordering race:** intents for a tick are dequeued in arrival order, and each intent's handler runs synchronously to completion before the next dequeue. So if a `CABLE_PICKUP_INTENT` arrives before a save request in the same tick, the pickup handler's three steps complete atomically before the save intent is dequeued:
  1. Server writes the pickup entry into the pickup state table, capturing `original_hum_id` and `original_actuator_id` from the existing `hum_cable` component.
  2. Server removes the `hum_cable` component.
  3. Server emits `cable_disconnected`.
  4. (Next dequeue) Save intent runs; serializer reads live DB + pickup state table; synthetic `hum_cable` row for the mid-drag cable is included.

Step 1 populates the pickup state table *before* step 2 removes the component, so when the save serializer runs it has the info it needs. Documented alongside the tick-order reference in `tick-architecture.md`.

**Multiplayer autosave (every minute per Ring 0 networking spec):** same path — the save serializer reads the pickup state table + live DB together. The player keeps their in-progress drag post-sync.

**Reload order:** load all entities first, then validate `hum_cable` references in a second pass. Any cable whose `hum_id` points at a missing or non-HUM entity gets its component dropped with a migration log entry.

---

## Multiplayer (server-authoritative pickup locks)

### Intent / delta protocol

Following `.claude/rules/networking.md`:

**Client → server intents:**
- `CABLE_PICKUP_INTENT{endpoint_key}` — request pickup of an existing cable's endpoint
- `CABLE_START_INTENT{hum_id}` — start a new cable from this HUM
- `CABLE_CONNECT_INTENT{source_hum_id, target_device_id}` — complete a cable to this target
- `CABLE_CANCEL_INTENT` — retract-on-cancel (Escape)
- `CABLE_DELETE_INTENT` — delete held cable (X)

**Server validation:**
- `CABLE_PICKUP_INTENT`: endpoint not already locked. If locked, deny.
- `CABLE_CONNECT_INTENT`: source and target both exist, target has `hum_powered` and no existing `hum_cable` OR existing `hum_cable` is in the initiating player's rack stripe, Euclidean distance² ≤ `max_ru²`, both endpoints in the initiating player's rack stripe (no cross-stripe connects).
- Cross-stripe: reject with `CABLE_DENIED{reason: "cross_stripe"}`. Client renders red tint on held cable end briefly, plays deny audio, robot logs "endpoint outside maintenance boundary."

**Server → client deltas:**
- Standard `cable_connected` / `cable_disconnected` events propagated via existing event-bus broadcast.
- Pickup locks broadcast as dimmed-endpoint hints to other clients (cosmetic; prevents wasted attempts).

### Rack-stripe boundaries

Per Ring 0 networking: each player owns a 5-rack stripe (solo), 3-rack collaborative stripe, etc. Cables can't cross stripes. The spec's 20 RU max length comfortably stays within a 5-rack stripe; cross-stripe rejection is an extra guard.

**Stripe membership for floor entities** (ARM): a floor entity at world-x `fx` belongs to the stripe whose rack range covers `nearest_rack_for(fx)`. If the ARM sits exactly between stripes (shouldn't happen given starter-scene placement, but defensive), round toward the lower rack index.

### Lock registry location

The server-side pickup state table lives in a new `WiringLockRegistry` (thin Node wrapping a RefCounted core) as a sibling under `GameServer`, next to `AnimalRegistry` and `ObjectRegistry`. The class name keeps "Lock" for continuity with the MP-safety framing; the table itself carries both the ownership lock *and* the `original_hum_id`/`original_actuator_id` fields the save serializer needs. Not inside `WiringController` (which is HUD-side and client-only).

### Solo play

Solo mode starts a local server (`.claude/rules/networking.md` commitment). Pickup locks still apply; the solo player is the only peer, so locks are never contested. This keeps the code path identical between solo and MP — one less divergence surface.

### Resync / rejoin

On peer reconnect (MP) or client-side desync recovery, the server sends the client its current pickup-state-table entries for that peer. The client reconciles local drag state against the server's view: any local drag without a matching server entry (e.g. the lock auto-expired during a disconnect) is cleared — the cable visually retracts with no event, the client exits drag mode, and a best-effort robot log notes that the connection state was re-synchronized. Prevents "client thinks it's dragging, server doesn't" from turning a later `CABLE_CONNECT_INTENT` into a phantom-cable creation.

---

## UX Flow

### Entering / exiting wiring mode

- Keyboard: `Tab` (toggles sticky mode; press-press, not hold).
- Controller: `LB+RB`.
- HUD: existing `WiringViewToggle` button.

Rumble (controller): short pulse on entry/exit.

### Placing a new cable

1. Enter wiring mode.
2. Focus / click **anywhere on the HUM device body** (whole sprite is the hitbox; the socket inset is a visual indicator, not a precise click target). Send `CABLE_START_INTENT`. On server approval: cable origin locks to HUM's output anchor; cable end follows cursor / focus reticle as a catenary curve.
3. Focus / click a valid target:
   - **Valid:** unpowered or differently-powered HUM-powered device within `cable_max_length_ru` and same rack stripe. Server processes `CABLE_CONNECT_INTENT`. On approval: `hum_cable` written, `cable_connected` event, `cable_plug.wav` (audio duck: -3 dB purr for 600 ms), socket glyph lights.
   - **Already cabled to another HUM:** silent swap via Replace ordering above. Brief visual animation: old cable fades over ~0.2s while new one snaps in.
   - **Out-of-reach:** cable end tints red while hovering invalid target; clicking on an out-of-reach target triggers deny audio + robot log + cable stays on cursor. Not silent.
   - **Cross-stripe (MP):** same treatment as out-of-reach; specific log line.
4. Press `B` / `Escape` / re-click source HUM / exit wiring mode: send `CABLE_CANCEL_INTENT`, no state change.

### Disconnecting an existing cable

1. Enter wiring mode.
2. Focus / click either endpoint of an existing cable:
   - Client sends `CABLE_PICKUP_INTENT`.
   - Server: if endpoint unlocked, locks endpoint; removes `hum_cable`; emits `cable_disconnected`; broadcasts the pickup state.
   - Client: cable picks up. One end snaps to the *other* endpoint of the original cable; the other follows the cursor / focus. UI enters "holding cable" state.
3. Three resolutions:
   - **Click valid target:** reconnect via `CABLE_CONNECT_INTENT`. Same effects as step 3 of placement.
   - **Press `X`:** delete. Send `CABLE_DELETE_INTENT`. Server releases lock, no new component, no additional events (`cable_disconnected` already fired at pickup). Client plays `cable_pop_01.wav`.
   - **Press `Escape` / `B` / exit wiring mode / target/source device despawns during drag:** retract. Send `CABLE_CANCEL_INTENT`. Server re-adds `hum_cable` with the original `hum_id` (if both endpoints still exist); emits `cable_connected` again. If either endpoint has despawned mid-drag, treat as delete with audio + log.

### Pickup / delete audio distinction

- **Pickup cue** (`cable_lift_01.wav`): dry, sharp, 2-3 kHz, ~0.1 s. Distinct from delete.
- **Delete cue** (`cable_pop_01.wav`): dry pop, broader spectrum, ~0.2 s. Reuses the RJ45-clip-release timbre, **not** reversed `cable_plug`.
- **Retract:** silent. The cable goes back to where it was; no event for the narrator or audio listener to react to.

### Pressing the TUNA button while unpowered

- Button click registers (`button_click_01.wav` with hum-tail muted — same asset, runtime mute on the sustained layer).
- `press_button` returns `INVALID_ID` early; no drain, no can spawn.
- Narrator emits the button-pressed-unpowered log (first-person voice): `"no carrier. i am sorry, little device. i can do nothing from here."`

### Controller focus model

- In wiring mode, focus cycles between three categories of focus targets:
  1. **HUM output anchors** (each HUM has one).
  2. **Device input anchors** on any entity with `&"hum_powered"`.
  3. **Endpoints of existing cables** (both ends of each cable).
- `Left Stick` or `D-Pad` moves between adjacent focus targets. `LB`/`RB` jumps to next category.
- `A` confirms (start cable / connect / pickup). `B` cancels or retracts. `X` deletes held cable. `Y` inspects the focused target (reuses inspect panel).
- Focus target has a visible reticle and a rumble pulse on transition. Accessibility: focus never relies on hover time; each move is explicit.

---

## Rendering

### Catenary cable

- 4-control-point cubic Bezier between source world position and target (or cursor during drag).
- Sag formula: `sag_px = max(3, length_px * sag_factor / 1000)`. At 20 RU (160 px at 224×128 internal viewport) with `sag_factor = 150`, mid-point drops ~24 px. Short cables (3-5 RU) get the 3 px floor, preventing "looks straight" on short hops. Long cables droop proportionally.
- Cable is 2 px thick, warm-amber cloth cord with a 1 px Breath White highlight on the top edge. Reads at faded opacity against Cable Gray and Dust Blue backgrounds (Smudge's review).

### Opacity by mode

| Mode | Cable opacity | Socket glyphs | Non-cable world |
|---|---|---|---|
| Normal view | **60%** (not 30%; 30% vanished against rack grays per Smudge) | Visible as unlit recessed insets on device sprite | Full saturation |
| Wiring view | 100% | Teal-lit recessed insets | Desaturated 40% (inverse of heat overlay — no collision) |
| Holding cable | 100% for held cable; 60% for all others | Lit; valid-in-reach targets pulse gently, out-of-reach targets dim to 20% | Same as wiring view |

### Dangling-end terminator glyph (accessibility fix)

When a cable has been picked up / is being dragged, the free end renders an **empty socket glyph** (dotted circle, 8 px) on the cursor. This glyph is visible in both modes — a colorblind player in normal mode distinguishes "live cable" (both ends socketed) from "dangling cable" (one end has the dotted glyph) without relying on opacity or color.

### Unpowered device visual

- **No new `no_carrier_glyph`.** Reuse the existing LED vocabulary from art-direction.md §8: dim the device's status LED to Slate Void; add a 1-frame flicker every ~2 seconds.
- Idle animation stops (static frame).
- **No warning badge, no red tint, no exclamation.** Per Mochi's review: the device's absence is its own signal. Dim LED + flicker = "device waiting." Not "device failed."

### Held-cable visual hints

- Hovering over valid target: cable end tinted warm, socket glyph on target pulses.
- **Hovering over out-of-reach or cross-stripe target:** cable end **desaturates to Cable Gray and dims to 50% brightness** (no red tint — red reads as "fire hazard" in a cozy world and breaks Commitment #10's no-blame rule). A deny glyph appears on the target.
- Hovering over empty/non-pluggable space: cable end neutral, cursor shows "will delete" preview on X-press.

### Controller focus reticle

- Reticle renders as a 12×12 square outline on the focused target, Breath White with 1 px shadow.
- On focus transition: scale-pop (100% → 115% → 100% over 100 ms) AND color flash (Teal → Breath White over 100 ms). This provides motion + color shifts for players without rumble-capable controllers.
- Optional rumble pulse (50 ms short) when `accessibility.rumble_enabled`. Rumble is supplementary; the visual motion cue is the primary channel.

### Cursor compositing while holding cable

While holding a cable, the default cursor sprite is **replaced** (not overlaid) with the dangling-tip glyph at 10×10 (upsized from 8×8 for readability). A 1 px Breath White inner ring separates glyph from background. Cable catenary draws up to the cursor position; the tip glyph anchors there.

### Z-ordering / crossing cables

- Cables z-sort by **sag-depth** (deeper sag = drawn later = visually above crossings).
- At crossing pixels, the lower-z cable dims to 40% opacity for 2 px to read as "underneath." Prevents the "false junction node" pattern Smudge flagged for multi-cable scenes.

### Crystal animation

Per-HUM battery crystal rotation is capped at **0.5 Hz** (2 s/cycle). No faster variant. `accessibility.reduced_motion = true` swaps the rotating crystal for a static segmented charge bar inside the same 6U frame.

---

## Config

Ring 1 creates a new file: `mods/tcp_base/config/hum.jsonc` (flat config dir, matching existing sibling conventions — **not** `config/balance/`).

```jsonc
{
  "schema_version": 1,
  // Max cable length between HUM device and a powered device, in rack units.
  // Ring 1 is permissive (~2 racks). Tightens when tech tower redefines density.
  "cable_max_length_ru": 20,
  // Catenary visual droop. Mid control point of the curve drops by
  // max(3, length_px * sag_factor / 1000) world units.
  "cable_sag_factor": 150
}
```

Existing HUM constants (`DEFAULT_CAPACITY`, `IDLE_DRAIN_BASE`, `CHARGE_PER_SATISFIED_ENTITY`, `BROWNOUT_THRESHOLD`) stay in `engine/core/hum_system.gd` for this spec. A dedicated config-externalization pass is out of scope.

`mods/tcp_base/sprites/infrastructure/cables/` directory is reserved for future themed cable sprites; Ring 1 render pipeline checks for `cable_power_strip1.png` and falls back to procedural rendering if absent. This is the hook for mods that want to theme cables.

---

## Narrative Surfaces

Following Parcel's rewrites. Robot voice stays in-character across all events.

### Robot log lines

| Event | Voice | Log |
|---|---|---|
| First cable ever placed (once per save) | Status | `New harmonic bridge detected in sector. I did not initiate this. The devices are coordinating. Excellent.` |
| Cable connected (subsequent) | Status | `UNIT-T03 harmonic coupled to acoustic source. Spindle resonance routing nominal.` |
| Cable disconnected (cause-agnostic, non-despawn) | Status | `UNIT-T03 harmonic bridge severed. Cause: unclear. Device awaiting reconnection.` |
| Replace-on-connect (same-tick disconnect+connect) | Status | `UNIT-T03 re-coupled through alternate bridge. Previous carrier retired.` |
| Out-of-reach (max length exceeded) | Status | `Harmonic carrier attenuation exceeds acceptable range. Endpoint refused bridge.` |
| Cross-stripe (MP) | Status | `Endpoint outside this carrier's broadcast jurisdiction. Bridge refused. Try a closer source.` |
| TUNA button pressed while unpowered | First-person | `no carrier. i am sorry, little device. i can do nothing from here.` |
| Retract-on-cancel | *(silent)* | — |
| Bulk connects (>3 same-tick) | Status, coalesced | `Multiple harmonic bridges established simultaneously. Topology unexpectedly rich. Recording for review.` |
| Second HUM ever placed (once per save) | Status | `Second harmonic source detected. Carrier domains will not interfere; harmonics are orthogonal. Operating two independent acoustic facilities. Acceptable.` |
| Per-HUM brownout entered | First-person | `carrier weakening at sector-A source. sector-B nominal. i am moving slowly only on devices bridged to A. apologies are localized.` |
| Starter-scenario cold boot | Status | `Boot complete. Inventory shows pre-arranged devices and two unidentified spindles already present. I do not recall placing them. Continuing.` |

**Precedence rule:** during a starter-scenario boot or any world load that would trigger both "first cable ever" and "bulk connects" (>3 cables), the first-ever-cable log is suppressed — bulk-coalesce wins. The first-cable discovery beat is only meaningful when it's the player's first live action, not a system-driven batch.

### Ring 2 seeds (pre-written now for consistency)

When kitten-cable-disconnect behavior ships, its log line ties into the same path:

> `UNIT-T03 carrier lost. Small device UNIT-C01b observed in vicinity immediately prior. Coincidence probable. Coincidence logged.`

The robot's increasingly strained denial is the joke. This line isn't wired in Ring 1 — just documented so the narrator knows what's coming and the vocabulary stays consistent.

### Update `.claude/rules/narrative.md`

Append a "Robot Cable Interpretation" section mirroring the existing "Robot Sound Interpretation" and "Satisfaction Interpretation" tables. Small doc maintenance in the implementation plan.

---

## Assets

### New audio

| Asset | Format | Description |
|---|---|---|
| `cable_pop_01.wav` | 16-bit 48kHz, QOA, loop_mode=0 | Dry pop on delete, ~0.2 s, RJ45-clip-release timbre |
| `cable_lift_01.wav` | 16-bit 48kHz, QOA, loop_mode=0 | Sharp dry click on pickup, 2-3 kHz, ~0.1 s |
| `hum_brownout_enter_01.wav` | 16-bit 48kHz, QOA, loop_mode=0 | Detune-and-die tone, ~0.4 s, per-HUM brownout entry |
| `hum_brownout_recover_01.wav` | 16-bit 48kHz, QOA, loop_mode=0 | Soft re-engage swell, ~0.4 s, per-HUM brownout recovery |

All per `.claude/rules/asset-pipeline.md` conventions: normalize to -1 dBFS with `sox ... gain -n -1`. Credits.md entry per sound (author, source URL, license). Update `docs/sound-asset-tracker.md` with a new "Infrastructure" section listing all four.

### Existing audio reused

- `cable_plug.wav` (verify extension; rename from `.ogg` if mis-listed in prototype spec)
- `button_click_01.wav`
- Existing place-deny audio (whichever dull 200-400 Hz bonk is already in use for rejected placement). **No new `place_deny` asset.**

### New sprites

Reconsidered post-review:
- **Socket glyphs:** 10×10 recessed insets *baked into* the HUM and HUM-powered device sprites. Always present; teal-lit in wiring mode via palette swap or shader tint. **No separate overlay sprites needed.**
- **Dangling-end terminator:** 10×10 empty-circle glyph with 1 px Breath White inner ring, single sprite (`cable_tip_dangling_strip1.png`). Always shown on cable free ends regardless of mode. Replaces cursor entirely while holding (see Cursor compositing).
- **No `no_carrier_glyph`:** reuse existing status-LED vocabulary (dim to Slate Void + 1-frame flicker every ~2 s).

Update `docs/art-asset-tracker.md` with the new sprite entry under Infrastructure → Cables.

### Mod extension hook

`mods/tcp_base/sprites/infrastructure/cables/` reserved. If a mod provides `cable_power_strip1.png`, the renderer uses it as a tiled segment texture. Otherwise procedural.

### Audio mix tuning

- Plug: -3 dB purr duck for 600 ms on connect (matches existing place-object rule).
- Pop: sits in 1-2 kHz, no masking conflict with HUM hum or purr bands.
- Pickup: high-frequency transient, safely above purr band.

### Per-HUM ambient audio

- Each HUM device emits a positional warm hum loop (~80-120 Hz fundamental, volume scaled by reserve ratio).
- **Deterministic detune per HUM:** each HUM's fundamental is offset ±2-4 Hz from the base, hash-derived from `entity_id`. Two HUMs produce a gentle chord, not a phase-cancellation wobble. Spec this in `sound-design.md`.
- **Brownout enter/recover:** per-HUM `hum_brownout_entered(hum_id)` → short detune-and-die tone (~0.4 s). `hum_brownout_recovered(hum_id)` → soft re-engage swell (~0.4 s). Two new small assets: `hum_brownout_enter_01.wav`, `hum_brownout_recover_01.wav`. Brownout exit fade across 600 ms to smooth the mix recenter.
- **Starter-scenario boot:** HUM ambient hum fades in over ~1.5 s on world load (not snap-on). Purr layer ramps independently as entities settle and become satisfied. Avoids startup acoustic pop.
- **Debug contentment toggle (`Shift+F1`):** intentionally silent. Dev-only; audio would leak into recordings.

---

## Accessibility

Every primary feedback channel has at least one backup:

| Channel | Primary | Backups |
|---|---|---|
| Cable connection state | Catenary curve between devices | Dangling-end terminator glyph (visible in normal mode too); socket glyph lit state |
| Cable plug | `cable_plug.wav` | Visible cable appears; socket glyph lights; robot log; controller rumble pulse |
| Cable pickup | `cable_lift_01.wav` | Cable visibly detaches one end; cursor shows dangling glyph; controller rumble |
| Cable delete | `cable_pop_01.wav` | Cable vanishes; robot log; controller rumble |
| Connect attempt denied | existing deny audio | Held cable end tints red; deny glyph on target; robot log; controller rumble pulse |
| Device powered | LED lit, idle animation plays | Cable visibly connected; socket glyph lit |
| Device unpowered | LED dim + flicker | Cable absent or dangling; idle animation stopped; socket glyph unlit |
| Wiring mode on/off | Viewport desaturation on/off | Tab key feedback; controller rumble; HUD button state |

**Controller parity:** every verb in the UX Flow has an explicit controller binding (see Controller focus model above). No cursor-dependent gestures.

**No time pressure:** held cable state persists until the player acts. No auto-cancel after N seconds. Retract-on-cancel is the forgiving default for accidental picks-ups.

**Sticky mode toggle:** `Tab` / `LB+RB` are press-press (sticky), not hold-to-maintain.

**`.claude/rules/input-design.md` update required:** replace the old "hold Y to disconnect" paragraph with the new click-to-pickup flow (accessibility section above is the source of truth for the update text).

---

## Data Model Summary

| Location | What | Persistence | Authority |
|---|---|---|---|
| `hum` component on HUM entity | `{reserve: int, capacity: int}` | Saved | Server |
| `hum_receiver` component on HUM entity | `{radius_ru: int}` (existing) | Saved | Server |
| `purr` component on purring entity (cats in Ring 1) | `{intensity: int}` — per-tick broadcast strength | Saved | Server (written by contentment→purr bridge) |
| `hum_powered` component on TUNA/ARM | `{}` (tag) | Saved | Server |
| `hum_cable` component on actuator | `{hum_id: int}` | Saved | Server |
| Pickup state table | `Dictionary[endpoint_key -> {owner_peer_id, tick, original_hum_id, original_actuator_id}]` | Not saved (authoritative mid-drag record; also read by save serializer) | Server |
| Active drag rendering state | `{picked_up_from, cursor_world_pos}` | Not saved | Client local |

---

## Implementation Dependencies

### What already exists

- `HumSystem` (`engine/core/hum_system.gd`) with `has_reserve`, `drain_action`, `charge` — **needs Phase 1 refactor**.
- `FoodSystem` (`engine/core/food_system.gd`) with `press_button` and `tick_arms` drain sites — **needs `_is_powered` helper and per-HUM drain call**.
- `Events` autoload (`nodes/events.gd`) — **needs `cable_connected`, `cable_disconnected` added; `hum_reserve_changed` signature update**.
- `WiringViewToggle` button in HUD scene tree.
- `cable_plug.wav` in prototype asset list.
- Object placement pipeline (`nodes/placement_ui.gd`) — reference for click-target state machine.
- Input bindings scaffold in `.claude/rules/input-design.md` — **needs the click-to-pickup paragraph update**.
- `hum_bar.gd` HUD element — **needs aggregate-across-HUMs update for Phase 1**.

### Phase 0 implementation

1. Create `mods/tcp_base/scenarios/starter.jsonc` per the schema above.
2. Add `engine/core/world_init_system.gd` (RefCounted core + thin Node wrapper under `GameServer`). Scans all mods' `scenarios/*.jsonc`, selects via `settings.starter_scenario_id` (default `"tcp_base:starter"`), populates entities in a post-mod-init phase. Checks save-root `starter_scenario_applied` flag before running (idempotent).
3. Add `Shift+F1` binding (debug-gated via `settings.debug.enabled`) that sets `debug_force_satisfied = true` on the inspected contentment-bearing entity. Contentment derivation honors this flag.
4. Smoke-test: fresh game → world populates → Shift+F1 on an entity → entity becomes satisfied → HUM reserve visibly climbs.

### Phase 1 implementation

5. Add `hum` component to each HUM entity at spawn (read capacity from `hum_device.jsonc`).
6. Rewrite `HumSystem` API to take `hum_id` parameter on charge/drain/query.
7. Rewrite `HumSystem.tick_charge()` to sum `purr.intensity` on entities within each HUM receiver's `hum_receiver.radius_ru`, grouped by nearest receiver. No contentment references; no species references.
7a. Introduce `&"purr"` emitter component schema (field: `intensity: int`, default 0).
7b. Add contentment→purr bridge (a step in the contentment system, or a small dedicated helper) that writes `purr.intensity` on entities with both `contentment` and `purr` components each tick, per their species recipe's `purr.rate_when_satisfied`.
7c. Migrate `CHARGE_PER_SATISFIED_ENTITY = 10` out of `hum_system.gd` into `mods/tcp_cats/species/cat.jsonc` as `purr.rate_when_satisfied: 10`. In Ring 1 only cats declare `purr`. Other species (ferrets, etc.) are out of scope for HUM charging — if a non-cat contribution path lands later, it gets its own emission capability (e.g. `&"dook"`, `&"chime"`) and its own receiver + converter, not a `purr` component bolted onto a non-purring recipe.
8. Rewrite `HumSystem.tick_idle_drain()` for per-HUM drain.
9. Update `hum_reserve_changed` / brownout signals to include `hum_id`.
10. Update `hum_bar.gd` to aggregate.
11. Update narrator subscriptions to filter or aggregate by `hum_id`.
12. Unit and integration tests per Phase 1 exit criteria.
13. Commit + verify existing game still runs with one HUM.

### Phase 2 implementation

14. Add `cable_connected` and `cable_disconnected` to `nodes/events.gd`.
15. Add `hum_powered` tag to `tuna_dispenser.jsonc` and `arm.jsonc`.
16. Define `hum_cable` component schema (a new section in modding docs).
17. Add `FoodSystem._is_powered(device_id, cost) -> int` helper; refactor `press_button` and `tick_arms` to use it.
18. Add HUM-despawn cleanup hook (reverse-scan `hum_cable` rows, emit disconnects).
19. Implement `nodes/hud/wiring_controller.gd` — overlay toggle, click-routing, drag state, intent emission.
20. Implement cable renderer (`nodes/cable_view.gd`) — catenary curve, opacity by mode, dangling-end glyph.
21. Implement pickup lock table in the server authority layer.
22. Implement intent/delta protocol for cable operations.
23. Cross-stripe validation in connect intent.
24. Config file `mods/tcp_base/config/hum.jsonc`; config loader for `cable_max_length_ru`, `cable_sag_factor`.
25. Controller focus model: cable endpoints join the existing focus graph.
26. Narrator subscriptions for new log events (connect / disconnect / deny / pressed-unpowered / first-ever / bulk-coalesce).
27. Implicit retract-on-save in snapshot pipeline.
28. Reload-order validation pass (second-pass `hum_cable` integrity check).
29. New audio assets (`cable_pop_01.wav`, `cable_lift_01.wav`) imported per pipeline.
30. Cable material sprite (`cable_tip_dangling_strip1.png`); socket-inset baking into HUM / TUNA / ARM sprites.
31. Update `.claude/rules/input-design.md` wiring-view binding paragraph.
32. Update `.claude/rules/narrative.md` with a "Robot Cable Interpretation" section.
33. Tests per Phase 2 exit criteria.

### Tests

**Phase 1 (in addition to the exit criteria above):**
- Integration: two HUM devices in separate racks; brownout triggers correctly when one is depleted but the other is full.

**Phase 2:**
- Unit: `test_hum_powered_tag_required` — entity without `hum_powered` component bypasses the power check (not relevant to Ring 1 actuators, but verifies the gate is tag-based).
- Unit: `test_hum_cable_absent_means_unpowered` — TUNA with no `hum_cable` component cannot dispense.
- Unit: `test_hum_cable_dangling_ref_after_despawn` — cable to HUM-A; destroy HUM-A; TUNA's `hum_cable` is removed; `cable_disconnected` fires; subsequent press dispenses nothing.
- Unit: `test_cable_length_validation` — within range succeeds; beyond range denied with no mutation.
- Unit: `test_replace_on_connect` — second connect emits exactly one disconnect (old) + one connect (new), in that order, in the same tick; only one `hum_cable` component afterward.
- Unit: `test_retract_on_cancel` — pickup → cancel → `hum_cable` matches pre-pickup state; `cable_connected` re-fires.
- Unit: `test_delete_on_x` — pickup → X → `hum_cable` absent; only pickup's `cable_disconnected` fired; no `cable_connected` fires.
- Integration: `test_cable_drain_loop` — place HUM, place TUNA, connect, press button, observe HUM-A drain + can spawn; disconnect, press button, observe no drain.
- Integration: `test_cross_stripe_reject_mp` — simulate two-peer stripes; attempt cable across stripe boundary; denied.
- Integration: `test_pickup_lock_mp` — peer A picks up a cable endpoint; peer B's pickup intent on the same endpoint denied; peer A's retract releases the lock.
- Integration: `test_save_midDrag_retract_on_save` — pickup → save → saved state has `hum_cable` restored to original; reload matches.
- Integration: `test_same_tick_bulk_load` — world load with 10 cables; narrator emits coalesced bulk log, not 10 individual lines.
- Scene: cable renderer's catenary sag floor clamps at 3 px for short cables.
- Soak: 10-minute run with 3 HUMs, 5 actuators, periodic cable re-plugs — no dangling refs, no leaked components.

---

## Open Questions for Playtest

- **`cable_max_length_ru = 20` is a guess.** Does 2-rack reach feel good? Tighter or looser?
- **`cable_sag_factor = 150` is a visual guess.** Droop reads "abandoned datacenter" or "drunk electrician"?
- **Retract-on-cancel vs delete-on-cancel.** Proposed retract (forgiving). If playtesters report "I can't figure out how to delete," swap the X/Escape roles or add a dedicated delete gesture.
- **Replace-on-connect silent swap.** If the player clicks a new HUM on a device that's already cabled, silent swap with a visible animation. If playtesters get confused, add a brief confirmation prompt.
- **Brownout model: per-HUM vs aggregate.** Ring 1 ships with **aggregate HUD bar + per-HUM device dimming** as the default (Mochi's round-2 recommendation — per-HUM brownout panic would violate the precarity-creep mitigation from `core-loop.md`). The per-HUM brownout signals still fire (for Sound / narrator), but the HUD aggregates and the player-facing "brownout" state is aggregate-driven. Per-HUM dimming on the connected device is the local tell. If playtest says the aggregate makes it hard to know which HUM is struggling, flip to per-HUM brownout HUD.
- **Per-HUM receiver assignment when capacities differ.** Ring 1 uses nearest-HUM-with-entity-id-tiebreak. Once capacities vary (Ring 2+), receivers may prefer the lower-fill HUM over the strict-nearest. Flag for playtest when that variation lands.

---

## Test Plan (Ring 1 exit criteria, manual)

*Prerequisite: `Shift+F1` debug contentment override is used throughout to flag entities satisfied. Real pet→satisfied chain is out of scope and tracked separately.*

- [ ] New game boots into starter scene with 1 HUM, 1 TUNA (+button), 1 ARM, 2 cats pre-placed.
- [ ] Place a HUM device, place a TUNA within 20 RU. Enter wiring mode. Draw a cable. `Shift+F1` on a cat near the HUM to force satisfaction. TUNA button press dispenses a can and drains that HUM.
- [ ] Place a second HUM with cats around it. First HUM's reserve can deplete while second HUM's stays full; aggregated HUD bar behaves correctly.
- [ ] Connect a TUNA to HUM-A, another TUNA to HUM-B. Deplete HUM-A; TUNA on A goes dark (LED dim + flicker, no warning badge); TUNA on B still works.
- [ ] Pick up the cable (click endpoint). TUNA's button does nothing; first-person robot apology log.
- [ ] Reconnect same cable. Button works again.
- [ ] Pick up, press X. Cable gone. Button does nothing.
- [ ] Pick up, press Escape. Cable retracts to original. Button works.
- [ ] Attempt to connect to a device beyond 20 RU. Cable-end tints red on hover; clicking denies with audio + log; held cable stays.
- [ ] Connect TUNA to HUM-A; connect same TUNA to HUM-B. Old cable fades out, new snaps in; narrator says "re-coupled through alternate bridge."
- [ ] Delete the HUM entity (debug). All cables to it disappear; `cable_disconnected` fires for each; devices go dark.
- [ ] Toggle wiring view off. Cables still visible at 60% opacity. Socket insets unlit. Non-cable world restored to full saturation.
- [ ] Save mid-drag. Reload. Cable restored to pre-pickup state. No drag held.
- [ ] (MP) Two peers, same cable endpoint, simultaneous pickup. Only one grabs; other sees deny.
- [ ] (MP) Attempt to cable across a rack-stripe boundary. Denied with log.
- [ ] Controller: complete all verbs above without mouse. Focus reticle visible. Rumble on all verb boundaries.

---

## Related Specs & Rules

- `docs/superpowers/specs/2026-04-12-purr-power-ring0-design.md` — supersedes "global pool" language
- `.claude/rules/core-loop.md` — purr-power architecture
- `.claude/rules/signals.md` — signal patterns (`cable_connected` / `cable_disconnected` examples)
- `.claude/rules/input-design.md` — wiring-view bindings (update required)
- `.claude/rules/narrative.md` — robot voice (new "Robot Cable Interpretation" section required)
- `.claude/rules/design-philosophy.md` — capability tags, relationship table (future upgrade target)
- `.claude/rules/modding.md` — component schemas; document `hum_powered` and `hum_cable` in mod-facing docs
- `.claude/rules/networking.md` — intent/delta protocol, rack stripes
- `.claude/rules/asset-pipeline.md` — audio format, naming, credits
- `.claude/rules/art-direction.md` — palette, LED vocabulary, reclamation aesthetic
- `.claude/rules/sound-design.md` — audio mix, purr duck rule
- `engine/core/hum_system.gd` — Phase 1 refactor target
- `engine/core/food_system.gd::press_button`, `::tick_arms` — Phase 2 `_is_powered` insertion
- `nodes/events.gd` — signal additions
- `nodes/hud/hum_bar.gd` — HUD aggregate update
