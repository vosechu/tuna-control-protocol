---
paths:
  - "engine/growth/**"
  - "nodes/dynamic_plants.gd"
  - "mods/*/species/**"
---

# TCP Reclamation Growth

The datacenter is being reclaimed. When an entity that carries the `&"tends_servers"` capability settles on a host long enough in a warm-enough slot, a plant grows on that host. This is the mechanical core of the reclamation aesthetic from `narrative.md` and the slow-burn reward loop for "this slot is a good slot."

## Two systems, one chain

```
ReclamationSystem  →  writes  reclamation.seconds  on each host
PlantGrowthSystem  →  reads   reclamation.seconds  + heat_grid temperature
                      writes  plant_growth.state   on each host
                      emits   Events.plant_spawned / plant_despawned
```

Both are RefCounted (pure core, see `design-philosophy.md`). `ReclamationSystem.tick()` runs before `PlantGrowthSystem.tick()` each frame so growth transitions see fresh presence values.

## Components

| Component | Shape | Carried by | Purpose |
|---|---|---|---|
| `reclamation` | `{seconds: int}` | host entity | Accumulated tender-seconds at this slot. 0–1000. |
| `plant_growth` | `{state: StringName, tended_seconds: int}` | host entity | State machine + threshold accumulator. |
| `advertisements` | `{list: Array}` | host entity | `PRESENT` growth appends a `comfort` ad with `source: &"plant_growth"`; `DORMANT` removes only that source. Other ad sources are preserved. |

"Host" means any entity that advertises `reclamation`. In the shipped build that's server entities from `tcp_base`; mods that want their own growable objects opt in by adding the `reclamation` and `plant_growth` components to their recipe — no engine change needed.

## Tender gating (ReclamationSystem)

Per tick, for each entity with a `reclamation` component:

1. Query all entities tagged `&"tends_servers"`. Capability, not species label — any recipe that carries the tag counts. See CLAUDE.md → "Species Are Component Recipes."
2. Check whether any tender is within `±2 × SLOT_HEIGHT_PX` of the host's position in both X and Y (bounding box, not radius — cheap).
3. If nearby: `seconds = min(seconds + 10, 1000)`.
4. Else: `seconds = max(seconds - 5, 0)`.

Numbers above are the shipped tuning — increment is twice the decay so drifting tenders still grow plants, but abandonment reverses within ~3 minutes of wall-clock play. 1000 is a cap, not a target.

## State machine (PlantGrowthSystem)

Four states; three transitions fire today. `GROWING` is reserved for future animation frames and not currently visited.

```
DORMANT  →(warmth ≥ 600 and tender present)→  ARMED
ARMED    →(tended_seconds ≥ 300)→             PRESENT
ARMED    →(warmth < 300 and no tender)→       DORMANT  (zeroes tended_seconds)
PRESENT  →(reclamation.seconds < 100)→        DORMANT
```

`tended_seconds` accumulates `+10` per tick while in `ARMED` with a tender present. It does **not** decay in `ARMED` — if the tender leaves but warmth holds, the counter sits until either the threshold is met or both conditions collapse. This rewards return visits.

**Thresholds live in `engine/growth/plant_growth_state.gd`:**
- `WARMTH_MIN = 600` (heat_grid temperature on the 0–1000 scale)
- `GROW_THRESHOLD_SECONDS = 300` (tick-scaled: 30 s wall clock of continuous tending)
- `DECAY_THRESHOLD_SECONDS = 100` (reclamation.seconds floor for keeping a plant)
- `PLANT_COMFORT_STRENGTH = 100`, `PLANT_ADVERT_RADIUS_PX = 8` (one slot-height)

## Invariants

- **HUM brownout immunity.** The plant tick never reads HUM reserve. A datacenter running at 10% power keeps its moss. Reclamation is cumulative; brownouts are transient. This reinforces the "no guilt" commitment in `core-loop.md`.
- **Hysteresis is state-based, not threshold-based.** The `DORMANT ↔ ARMED` boundary uses different thresholds than the `ARMED → PRESENT` jump. Warmth dipping briefly while tended_seconds climbs never rolls the state back.
- **Plants are additive comfort.** A `PRESENT` plant appends one advertisement to the host's `advertisements.list` with `source: &"plant_growth"`. Despawn filters by `source` so it never removes an unrelated ad.
- **Capability-gated tending.** Only entities carrying `&"tends_servers"` contribute. New recipes opt in by adding the tag — no code path checks species.

## Projection (dynamic_plants.gd)

`nodes/dynamic_plants.gd` is a projection-only Node. It:

1. Subscribes to `Events.plant_spawned` and `Events.plant_despawned`.
2. Holds a map `host_id → Sprite2D` registered by `GameClient` when placing host sprites.
3. On `plant_spawned`: creates an `AtlasTexture` Sprite2D (8×8 region), adds it as a child of the host's sprite at offset `(3, -6)`.
4. On `plant_despawned`: `queue_free()`s the plant sprite and removes it from the map.

No game logic in the projection. Variant choice (moss / grass / blossom / flower) is a display-only decision; the shipped build defaults to `moss`. A future capability-driven variant selector (recipes declare which `plant_variant` tag they contribute, projection picks the dominant tag from recent tenders) can slot in without changing the core state machine — keep any future branching on component tags, never on species labels.

## Narrative hooks

Robot log strings for plant spawn/despawn are documented in `narrative.md` ("Reclamation Growth"). The robot never says "plant" — see the voice constraint there.

## Related rules

- `animal-ai.md` — advertisement scoring; `comfort` channel and radius semantics.
- `core-loop.md` — plants are HUM-brownout-resistant by design.
- `design-philosophy.md` — Pure Core, change detection, spawn templates.
- `modding.md` — capability tags, how recipes opt in to `tends_servers`.
- `narrative.md` — reclamation aesthetic, robot voice for plant events.
- `objects.md` — advertisement list shape on host entities.
- `tick-architecture.md` — where reclamation/growth fit in the 10 Hz tick order.
