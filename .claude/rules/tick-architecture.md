---
paths:
  - "nodes/game_server.gd"
  - "engine/core/**"
  - "engine/desires/**"
  - "engine/growth/**"
---

# TCP Tick Architecture

## Fixed 10 Hz Simulation Tick

Set `Engine.physics_ticks_per_second = 10` in project settings (or in an autoload's `_ready()`). Each `_physics_process` call IS one tick — no accumulator needed. `delta` is always `0.1` (1/10 Hz).

## Tick Order

```gdscript
func _physics_process(_delta: float) -> void:
    db.advance_tick()

    # Step 1: Heat propagation (grid math, no entities)
    heat_grid.propagate()

    # Step 2: Object decay — batch column op
    db.add_all(&"integrity", &"value", -1)

    # Step 3: Desire update — batch ops + cached scatter
    db.add_all(&"desires", &"hunger", 5)
    db.add_all(&"desires", &"curiosity", 3)
    scatter_heat_to_warmth()        # cached cell→entities mapping
    scatter_comfort_to_desires()     # cached surface→occupants mapping
    scatter_social_to_desires()      # cached cell→neighbor_count
    db.clamp_all(&"desires", &"hunger", 0, 1000)
    db.clamp_all(&"desires", &"warmth", 0, 1000)
    db.clamp_all(&"desires", &"social", 0, 1000)

    # Step 3b: Purr emitter update — contentment→purr bridge
    #   For every entity with both `contentment` and `purr`:
    #     purr.intensity = purr_config.rate_when_satisfied if satisfied else 0
    #   Must run before tick_charge so charge reads current intensity.
    contentment_purr_bridge.tick()

    # Step 3c: HUM charge — emit/listen, per-entity batteries
    hum_system.tick_charge()       # sum purr intensity at nearest hum_receiver
    hum_system.tick_idle_drain()   # per-HUM decay

    # Step 4: AI scoring — adaptive time budget, priority ordered
    desire_resolver.evaluate_budget()

    # Step 5: Movement — per-entity, updates cell mappings
    movement_system.tick()

    # Step 6: Proximity event checks
    proximity_event_manager.check_triggers()

    # Step 7: Flush watcher notifications
    db.flush_notifications()
```

## Scatter Pattern (Steps 3)

Two-phase cached mapping eliminates per-entity spatial lookups from the hot tick.

**Phase 1 — Maintain mappings (incremental, on movement only):**

```gdscript
# cell→entities mapping, updated when entities cross cell boundaries
var _cell_entities: Array[Array[int]]  # cell_index -> [entity_ids]

func _on_entity_moved(entity_id: int, old_cell: int, new_cell: int) -> void:
    _cell_entities[old_cell].erase(entity_id)
    _cell_entities[new_cell].append(entity_id)
    # Mark affected cells dirty for social recount
    _dirty_social_cells.append(old_cell)
    _dirty_social_cells.append(new_cell)
```

**Phase 2 — Scatter values (every tick, O(n) with no lookups):**

```gdscript
func scatter_heat_to_warmth() -> void:
    for cell_idx in heat_grid.cell_count():
        var temp: int = heat_grid.get_temp(cell_idx)
        for entity_id in _cell_entities[cell_idx]:
            db.set_field(entity_id, &"desires", &"warmth", temp)

func scatter_social_to_desires() -> void:
    for cell_idx in _occupied_cells:
        var count: int = _cell_neighbor_count[cell_idx]
        var social_val: int = _social_curve(count)
        for entity_id in _cell_entities[cell_idx]:
            db.set_field(entity_id, &"desires", &"social", social_val)
```

**Cache invalidation:** ~70% of animals are ambient/stationary. Only entities crossing cell boundaries update mappings. Social neighbor counts recomputed only for dirty cells.

| Mapping | Caches | Invalidated by |
|---|---|---|
| cell → entities | entity positions | Entity moves to new cell |
| cell → neighbor_count | nearby entity density | Entity moves (recount adjacent cells) |
| surface → occupants | what's sitting on what | Entity arrives/departs surface |

## Adaptive Time Budget (Step 4)

AI evaluation uses a **fixed time budget per tick**, not a fixed entity count. The tick always completes in constant wall-clock time regardless of entity count or evaluation complexity.

```gdscript
const EVAL_TIME_BUDGET_USEC: int = 1000  # 1ms per tick

func evaluate_budget() -> void:
    var start := Time.get_ticks_usec()
    while _dirty.size() > 0:
        if Time.get_ticks_usec() - start >= EVAL_TIME_BUDGET_USEC:
            break
        var id: int = _pop_highest_deficit()
        _evaluate_one(id)
```

**Priority ordering:** Entities with the highest desire deficit are evaluated first. A cat at warmth 100 (freezing) gets evaluated before one at warmth 600 (slightly chilly). Most-uncomfortable entities react first within the budget.

**Dirty flag, not dirty queue:** An entity is either dirty or not — re-dirtying doesn't duplicate it. The scatter system marks entities dirty when a desire value crosses a threshold band (multiples of 100). The dirty set is bounded by total entity count.

**Latency characteristics:**
- Stable datacenter: almost no dirty entities, near-zero AI work per tick
- Single disruption (server removed): ~50 dirty entities, cleared in 3-5 ticks (~300-500ms)
- Cascade: dirty set bounded by entity count, budget ensures constant tick time, most-affected entities react first

## Rendering at Display Framerate

`_process` runs at display framerate (60fps+). Interpolate positions using `Engine.get_physics_interpolation_fraction()`:

```gdscript
func _process(_delta: float) -> void:
    var t := Engine.get_physics_interpolation_fraction()  # 0.0 to 1.0
    global_position = _prev_pos.lerp(_target_pos, t)
```

## Staggered Evaluation

The adaptive time budget replaces fixed round-robin scheduling. At 1ms budget per tick with ~50μs per evaluation, ~20 entities are evaluated per tick in normal conditions. At 1000 animals where most are content, the dirty set stays small and evaluations are infrequent.

## Key Numbers

| Parameter | Prototype | Scale Target |
|---|---|---|
| Sim tick rate | 10 Hz | 10 Hz |
| Render rate | 60 Hz | 60 Hz |
| AI eval time budget | 1ms/tick | 1-2ms/tick (tunable) |
| Max ads per object | ~3 | ~5 |
| Perception radius | 8 RU | 8 RU (spatial hash) |
| Hysteresis switch threshold | 150 | Tunable |
| Nav graph nodes | ~50-80 | ~500-2000 |
| Furball pool cap | 200 | 300 |
| Heat grid cells | 210 | Per-room |
