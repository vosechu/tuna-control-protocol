---
paths:
  - "engine/navigation/**"
  - "mods/*/species/**"
---

# TCP Navigation

Point graph using Godot's `AStar2D`. Not navmesh (too structured) or tile grid (too vertical). One `AStar2D` per species so traversable edges are the *only* edges in that species' graph — unreachable nodes simply have no path, no `INF`-cost workaround.

## Node Types

- `FLOOR_NODE` — walkable floor positions, one per rack
- `RACK_SLOT_NODE` — each occupied/accessible rack slot (added by `add_rack_slot`)
- `BOX_ENTRY_NODE` / `BOX_INTERIOR_NODE` — paired anchors emitted by `add_box_enterable` for any object whose state advertises a `contained` join (cardboard_box today)
- `SHELF_NODE` — player-placed shelf/ledge (deferred)
- `TUBE_ENTRANCE` / `TUBE_WAYPOINT` — tube path points (deferred)

## Edge Types

- `WALK` — emitted between adjacent rack-slot nodes for any species carrying `body_capabilities.walks`
- `JUMP_UP` — emitted from a floor node to a rack slot iff the species carries `body_capabilities.jumps` AND `(floor.y - slot.y) <= max_height_ru * SLOT_HEIGHT_PX`
- `JUMP_DOWN` — drop-down equivalent (gate by `body_capabilities.drops.max_height_ru`)
- `ENTER` — emitted from a box entry node to its interior iff the species carries `body_capabilities.settles_in_containers` AND `body_geometry.size_ru <= join.inner_size_ru`
- `CLIMB_TUBE` / `CLIMB_CABLE` / `RAMP` — deferred; future capability tags

The dict form (each verb carries its own parametric data) replaced an older `traversal: ["WALK", …]` array with scalars on the species root. Modders writing new species recipes always use the dict form; the array form is gone.

## Species Body Schema

```jsonc
"body_capabilities": {
  "walks":  {},
  "jumps":  { "max_height_ru": 3 },
  "drops":  { "max_height_ru": 5 },
  "settles_in_containers": { "max_body_size_ru": 2 }
},
"body_geometry": { "size_ru": 2 }
```

`NavGraphBuilder.register_species(species_id, body_capabilities, body_geometry)` indexes both at registration time. Helpers:

- `has_capability(species_id, verb)` — does this species carry the verb at all?
- `get_capability_param(species_id, verb, param, default)` — read a specific parametric value (e.g. `max_height_ru`)
- `get_body_size_ru(species_id)` — read body geometry

Edge scanners (`add_rack_slot`, `add_box_enterable`) iterate species and emit edges per the gates above.

## Reachability Belongs to the Navgraph

The *movement layer* — not the AI layer — decides whether an entity actually advances toward its target. `nav_builder.next_waypoint_or_stay(species, from_px, to_px)` returns:

- `from_px` (entity stays put) when no path exists for that species
- `from_px` when the path stops short of the requested target node (orphan slot)
- the next nav node along the path otherwise

The move loop calls this and trusts the result. **Do not add `can_reach` gates at AI transition sites** — SEEKING/HUNGRY/RETURNING all set targets unconditionally; the navgraph rejects movement when there's no path, and the AI's next desire-resolver pass observes zero progress and reassigns. This avoids the duct-tape pattern where every new state-transition site has to remember a defensive check, and it kills the "ferret hovering above the rack" failure mode that surfaced when `_next_path_waypoint`'s pre-refactor fallback returned `target_px` directly.

`can_reach(species, from, to)` still exists for AI-side scoring (e.g. "score 0 for unreachable ads") but is *not* part of the movement contract.

## Pathfinding

Per-species `AStar2D` instances. `get_path_points(species, from_pos, to_pos)` runs A* and returns the path as `PackedVector2Array`. Empty result = unreachable. Fine for prototype scale (~5–80 nodes per species).

## Dynamic Updates

- `add_rack_slot(rack, slot)` / `remove_rack_slot(rack, slot)` — server placement / removal
- `add_box_enterable(rack, slot, join)` / `remove_box_enterable(rack, slot)` — when an object's state gains/loses a `contained` join
- Any animal whose path passes through a removed node gets STARTLED and drops to nearest floor node

Dead-end tubes (when wired): ferrets reverse out. No stuck states.

## Related

- `.claude/rules/animal-ai.md` — ad scoring; ads at unreachable positions still score, the navgraph just won't move the entity there
- `.claude/rules/objects.md` — `state_ads` / `join` schema
- `engine/navigation/nav_graph_builder.gd` — the implementation
