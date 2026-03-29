# TCP Navigation

Point graph using Godot's `AStar2D`. Not navmesh (too structured) or tile grid (too vertical).

## Node Types

- `FLOOR_NODE` — walkable floor positions, spaced ~1 rack-width apart
- `RACK_SLOT_NODE` — each occupied/accessible rack slot
- `SHELF_NODE` — player-placed shelf/ledge
- `TUBE_ENTRANCE` / `TUBE_WAYPOINT` — tube path points

## Edge Types (tagged with traversal requirements)

- `WALK` — all species
- `JUMP_UP` — cats only, max 3U height
- `JUMP_DOWN` — cats any height, ferrets max 1U
- `CLIMB_TUBE` — ferrets + small animals only
- `CLIMB_CABLE` — cats only
- `RAMP` — all species

## Species Capability Matrix (from JSON)

```json
{"cat": {"traversal": ["WALK","JUMP_UP","JUMP_DOWN","CLIMB_CABLE","RAMP"], "max_jump_height_ru": 3},
 "ferret": {"traversal": ["WALK","JUMP_DOWN","CLIMB_TUBE","RAMP"], "max_drop_ru": 1}}
```

## Pathfinding

Species-filtered A* via `_compute_cost()` override on a custom AStar2D subclass. Return `INF` for edges the species can't traverse, causing the pathfinder to skip them. Fine for prototype scale (~50-80 nodes). At scale: per-species AStar2D instances (avoids virtual call overhead).

## Dynamic Updates

`on_object_placed()` adds nav nodes and connects to adjacent slots. `on_object_removed()` disconnects and removes nodes. Any animal whose path passes through a removed node gets STARTLED and drops to nearest floor node.

Dead-end tubes: ferrets reverse out. No stuck states.
