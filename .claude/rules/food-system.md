---
paths:
  - "engine/core/food_system.gd"
  - "engine/core/object_state_manager.gd"
  - "mods/tcp_tuna/**"
---

# TCP Food System

The shipped Ring 0 food chain: player clicks the button → dispenser drops a sealed can → arm auto-opens it → a hungry cat walks over and eats → can despawns. Every link spends HUM reserve from `HumSystem`; cat contentment replenishes it. This is the concrete loop that `core-loop.md` describes abstractly.

## Entities

| Entity | Component | Role |
|---|---|---|
| Button | `tuna_button: {tethered_to: "tcp_base:tuna_dispenser"}` | Player-clickable trigger. No AI. |
| Dispenser | `tuna_dispenser: {hum_cost, can_type}` | Spawns sealed cans when paired button is pressed. Advertises `hunger` to draw hungry cats to the right rack. |
| Arm | `arm: {radius_px, hum_cost, open_duration_ticks}` | Floor entity. Every tick, opens any sealed tuna_can within radius, paying HUM. No AI, no movement. |
| Tuna can | `tuna_can: {state, despawn_timer}` + `object_type: {type: "tuna_can"}` | Spawned by dispenser. State machine drives advertisements. |

All numbers (HUM costs, radii, durations) are declared in the mod recipes at `mods/tcp_base/objects/` — no hardcoded values in engine code.

## Tuna can state machine

| State | Advertisements | Transition in |
|---|---|---|
| `sealed` | `openable` strength 800 r=3 (action-tagged) | Created by dispenser |
| `opened` | `hunger` strength 900 r=6 (action-tagged, max_occupants=1) | `FoodSystem.tick_arms()` |
| `eaten` | none | `game_server._mark_nearest_can_eaten()` after EATING completes |

The `action` sentinel on both sealed and opened ads keeps `DesireScatter` from passively feeding cats (see `objects.md` — Passive scatter vs. active consumption). Cats must actively transition through PACING/EATING states to gain hunger satisfaction.

After entering `eaten`, the can's despawn timer runs; `FoodSystem.tick_cleanup()` destroys the entity after `CAN_DESPAWN_TICKS` (100 ticks = 10 s).

## Tick order

`FoodSystem` ticks in two phases, both called from `GameServer._physics_process`:

1. `tick_arms()` — for each entity with an `arm` component, query `radius_px` around its position for `tuna_can` entities. For each sealed can found, if `_hum.has_reserve(arm.hum_cost)`: drain, transition the can to `opened` (state + ad swap), emit `Events.can_opened(can_id)`. Stops early if HUM runs out.
2. `tick_cleanup()` — for each `tuna_can` in state `eaten`, increment despawn_timer. When it hits `CAN_DESPAWN_TICKS`, `remove_spatial` + `destroy_entity`.

The scheduler runs `tick_arms` before `tick_cleanup`, and both after `food_system.tick_arms()` in the documented tick order (see `nodes/game_server.gd::_physics_process`).

## Button press (player-driven)

`game_client._try_click_entity(world_pos)` runs on mouse click. It spatial-queries a 2-RU radius and, if any entity carries `tuna_button`, calls:

```gdscript
var can_id: int = game_server.food_system.press_button(button_id)
if can_id != Constants.INVALID_ID:
    Events.food_dispensed.emit(can_id)
```

`press_button(button_id)` validates:
1. Button has `tuna_button` component.
2. `button.dispenser_id` points to an entity with `tuna_dispenser`.
3. Button and dispenser are in the same rack (same `RACK_WIDTH_PU` bucket of `position.x`).
4. HUM reserve ≥ `dispenser.hum_cost`.

All four must pass; any failure returns `INVALID_ID` silently. On success: drain the dispenser's `hum_cost`, create a new entity with `position` at the dispenser (Y a quarter of `FLOOR_HEIGHT_PU` below the rack bottom), `tuna_can: {state: "sealed", despawn_timer: 0}`, `object_type: {type: "tuna_can"}`, and insert into the spatial index.

Ferret AI does not press buttons in the current design. The dispenser advertises `hunger` strength 300 r=6 so hungry cats route toward the right rack ahead of a can being available.

## Cat eating loop

Runs inside `game_server._update_ambient_states()`, driven by the `ai_state.state` field on each cat:

```
AMBIENT state
    ↓ (hunger < 400 → chosen target is a food ad)
HUNGRY (arrival pending)
    ↓ on arrival:
       food in range? → EATING   : PACING
PACING (1 Hz recheck for nearby food)
    ↓ food found
EATING (3 s, satisfies +30 hunger/tick, caps at 1000)
    ↓ timer elapsed
    — mark nearest eligible can as `eaten` (removes its advertisements)
    — return to AMBIENT (IDLE)
```

Transitions:
- `HUNGRY` → `PACING`: arrival, no food in range. Emits `Events.creature_started_pacing` so SoundManager can play the species-appropriate pacing sound (via `sounds.pacing` on the species recipe).
- `HUNGRY` → `EATING`: arrival, food in range. Commitment 300.
- `PACING` → `EATING`: tick-level recheck, food appeared within range.
- `EATING` → AMBIENT: 3 s elapsed. Commitment resets to 0. `_mark_nearest_can_eaten` finds the nearest can within range, sets its state to `eaten`, removes its `advertisements` component.

`_find_nearby_food(entity_id)` picks the nearest entity carrying `tuna_can` within pathfinding range. The 3 s duration is hardcoded in `game_server._update_ambient_states` (not in config — move to desire_thresholds.json if tuning becomes needed).

## HUM relationship

The HUM loop funds everything:

```
cat satisfied  →  HumSystem.tick_charge  →  reserve ++
                                             ↓
                                         dispenser.hum_cost (50)   when player presses
                                         arm.hum_cost (30)         when arm opens a can
                                         idle drain (−5 × ratio)   every tick
                                             ↓
                                         reserve approaches 0 → brownout visuals
```

Per-tick HUM accounting is managed by `HumSystem`; `FoodSystem` is a consumer. Dispensers and arms both route drain through `FoodSystem.is_powered(device_id, cost)`, which today returns the first HUM with enough reserve, ignoring `device_id` (cables are not implemented — see the banner on `hum-cable-system.md`). If no HUM has enough reserve, food actions silently no-op (button press returns `INVALID_ID`; arm tick skips the can). This is graceful-degradation, not an error state — the game is still playable, just slower to feed cats.

## Events

| Signal | Emitted by | Payload |
|---|---|---|
| `food_dispensed(can_id)` | `game_client._try_click_entity` | Can entity ID |
| `can_opened(can_id)` | `FoodSystem.tick_arms` | Can entity ID |
| `creature_started_pacing(animal_id)` | `game_server._update_ambient_states` (HUNGRY→PACING transition) | Animal entity ID |
| `hum_reserve_changed(hum_id, old, new)` | `HumSystem._emit_if_changed` | Per-HUM reserve values. HUD aggregates for display. |

The HUD's HumBar, SoundManager, and LightingSystem all subscribe to `hum_reserve_changed`. See `.claude/rules/signals.md` for the full signal taxonomy.

## Related rules

- `.claude/rules/objects.md` — Object state mechanics underlying the tuna can.
- `.claude/rules/core-loop.md` — Design intent for the purr-power loop this implements.
- `.claude/rules/hum-cable-system.md` — Per-HUM battery design (cable layer not currently implemented; banner explains).
- `.claude/rules/animal-ai.md` — Desire scoring (how hungry cats pick targets).
- `.claude/rules/signals.md` — Event bus ownership for cross-system signals.
