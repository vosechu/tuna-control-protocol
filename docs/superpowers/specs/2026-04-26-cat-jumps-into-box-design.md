# Cat Jumps Into Box - Design Spec

**Date:** 2026-04-26
**Ring:** 1
**Status:** Draft
**Prerequisites:**
- Animal Resting-On Design Spec (`2026-04-05-animal-resting-on-design.md`) - state_advertisements + join blocks, relationship lifecycle
- Coordinate-system redesign (`2026-04-19-coordinate-system-redesign.md`) - `_px` for distances, `_ru` for sizes
- Purr-power Ring 0/1 (`2026-04-12-purr-power-foundation.md`, `2026-04-12-purr-power-objects-food-loop.md`) - the `purr` channel and HUM charging exist

## Summary

Cats discover boxes, climb up, jump in, settle, purr, and charge HUMs. The user-visible slice is "see a cat in a box, purring, lighting up the HUM device." The architectural work behind that is bigger: an inversion that ends with the **entity owning its physical capabilities and emission geometry**, while infrastructure publishes only its dimensions. This unlocks ferrets-through-tubes, kittens-on-cats, dogs-on-stairs, and shelf-jumping with no further engine surgery - only new species recipes and new infrastructure publishing geometry.

## Goals

**The slice (visible loop, ships in this spec's plan):**
- Two server+box stacks at the bottoms of two adjacent racks. One HUM (rack 1).
- One cat pre-settled inside box-0 at startup; one cat starts on the floor and finds box-1 by emergent desire scoring.
- Both cats end up purring. Cat B's purr charges the HUM directly. Cat A's purr reaches across the rack gap when contented enough.
- The HUM bar visibly fills. Pixel-note rings radiate from each purring cat.

**The architecture (described in spec; only what the slice needs ships now):**
- `body_capabilities` on species - entities know what they can do.
- Per-species navigation graphs computed from world geometry by capability scanners.
- Real Y for animals (kill the `FLOOR_Y - 1` snap).
- New `contained` join type for `state_advertisements`, alongside existing `stack` / `nearby`.
- Cat-owned purr emission geometry (`{intensity, radius_px}`); HUM `hum_receiver` becomes a tag with a body-rect derived from `physical.size_ru` and `RACK_WIDTH_PX`.

## The Inversion Principle

The single architectural rule running through this spec:

> **The entity is responsible for knowing what *it* can do. Infrastructure publishes only its physical reality.**

Concretely, this means:

- A 4" dryer tube has `inner_diameter_ru: 1`. It does not say which species can crawl through.
- A box has `entry_threshold_ru: 1` and `inner_size_ru: 2`. It does not say which animals can enter.
- A sleeping cat publishes its back-surface dimensions and warmth. It does not say which animals can curl up on it.
- A purring cat broadcasts an emission disk of `radius_px`. It does not check who's listening.

In every case, the consumer is the active party - its body_capabilities query the world geometry and decide. New species get to use existing infrastructure for free; new infrastructure gets used by every species that fits, without modification.

## Architecture

### 1. body_capabilities - entity self-knowledge

Each species recipe declares the verbs its body knows. Each verb has its own parameters.

```jsonc
// mods/tcp_cats/species/cat.jsonc - addition
"body_capabilities": {
  "walks": {},
  "jumps":  {"max_height_ru": 3},
  "drops":  {"max_height_ru": 5},
  "climbs": {"max_height_ru": 8},
  "settles_in_containers": {"max_body_size_ru": 2},
  "settles_on_surfaces":   {"max_body_size_ru": 2}
}

// Future - illustrative
// ferret.jsonc:  walks{}, jumps{max_height_ru:1}, fits_in_tubes{max_bore_ru:1}, settles_in_containers{max_body_size_ru:1}
// gerbil.jsonc:  walks{}, fits_in_tubes{max_bore_ru:1}, settles_in_containers{max_body_size_ru:1}
// dog.jsonc:     walks{}, climbs_stairs{}, settles_on_surfaces{max_body_size_ru:5}
```

`body_capabilities` is a top-level field on the species recipe. No engine code branches on species id; the navgraph builder reads `body_capabilities` and runs whatever scanners match.

The existing `traversal: ["WALK","JUMP_UP","JUMP_DOWN"]` and `max_jump_height_ru: 3` fields in `cat.jsonc` are folded into `body_capabilities` and removed from the recipe schema.

**Body geometry** (a parallel field used by scanners that compare body size to opening size):

```jsonc
"body_geometry": {
  "size_ru": 2   // cat body cross-section in rack units; used for fit checks
}
```

Adult cats `size_ru: 2`, kittens `size_ru: 1`, ferret `size_ru: 1`, dog `size_ru: 4`. Engine never reads species id - only `body_geometry.size_ru`.

### 2. Per-species navgraph

The navigation graph is computed per species from shared world geometry.

**Nodes** are positions where an animal can stand or rest. Sources:

| Source | Node it produces |
|---|---|
| Floor | One node per rack column at `FLOOR_Y - 1` |
| `surface_top` component | One node at `position + surface_top_offset` |
| `state_advertisements[state].join` of type `contained` | Two nodes per slot: `entry_origin_offset` (top-stand) and `interior_origin_offset` (inside) |
| `state_advertisements[state].join` of type `stack` | One node per slot: `slot_offset` (on host) |
| Tube endpoints (future) | Two nodes per tube |
| Ramp/staircase endpoints (future) | Two nodes per ramp |

**Edges** are emitted by *body_capability scanners*. Each capability declared on the species runs a scanner over the node set:

| Capability | Scanner emits |
|---|---|
| `walks {}` | WALK between any two floor/surface nodes on a continuous walkable line |
| `jumps {max_height_ru}` | JUMP_UP edge A -> B if `B.y < A.y` AND `(A.y - B.y) <= max_height_ru x SLOT_HEIGHT_PX` AND horizontal alignment within tolerance |
| `drops {max_height_ru}` | JUMP_DOWN, mirror of `jumps` |
| `climbs {max_height_ru}` | CLIMB between nodes connected by a vertical surface (rack frame, cable, future wall) |
| `fits_in_tubes {max_bore_ru}` | THROUGH_TUBE between tube endpoints if `body_geometry.size_ru <= tube.inner_diameter_ru` |
| `settles_in_containers {max_body_size_ru}` | ENTER from `entry_origin` to `interior_origin` if `body_geometry.size_ru <= container.inner_size_ru` AND `container.entry_threshold_ru <= jumps.max_height_ru` |
| `settles_on_surfaces {max_body_size_ru}` | SETTLE from a node adjacent to the host to the host's `slot_offset` if surface accommodates body weight |

**A\* runs on the per-species graph.** Edge cost = `pixel_distance x per_type_multiplier`. Initial multipliers:

```jsonc
// config/balance.jsonc
"navgraph_edge_cost_multipliers": {
  "WALK": 1000,
  "JUMP_UP": 1500,
  "JUMP_DOWN": 1200,
  "CLIMB": 3000,
  "THROUGH_TUBE": 1000,
  "ENTER": 500,
  "SETTLE": 500
}
```

(Stored in thousandths; engine divides by `UNIT` when scoring.)

**Caching.** One cached graph per species. Lifecycle hooks (`Lifecycle.ADDED`, `REMOVED`) on `surface_top`, `state_advertisements` (join sub-block specifically), `tube_segment`, etc., mark all per-species graphs dirty. At prototype scale (<=200 entities) full rebuild on invalidate is fine. Future: dirty-region rebuilds only.

**Edge type carries forward to animation.** Whichever edge A* chose tells the animator which clip to play during traversal. See Section 6.

**Existing scaffolding:** `engine/navigation/NavGraphBuilder` exists. It currently produces a single graph with `WALK` segments along the floor. Extension/replacement is implementation work - the builder reads `body_capabilities`, runs the appropriate scanners, returns a per-species graph.

### 3. Real Y for animals

Today `nodes/animal_node.gd` sets `sprite.y = FLOOR_Y - 1` regardless of what the Position component says (the AI-DEV note in `CLAUDE.md` flags this as a known issue). Change: render Y comes from `position.y` directly, cast to float at the int -> float boundary. The Position component already stores integer pixel Y; the data model is fine; the render layer is the only thing lying.

This unlocks cats on servers (`y ~ FLOOR_Y - 8 = 104`), cats inside boxes (`y ~ FLOOR_Y - 16 = 96`), shelves, bridges, sleeping atop other cats. One file change.

### 4. The `contained` join type

The Animal Resting-On spec defines `state_advertisements` with `{ads, join}` blocks and two join types: `stack` (joiner sits on host) and `nearby` (joiner stays within radius). This spec adds a third join type, `contained`:

```jsonc
"join": {
  "type": "contained",
  "direction": "any",
  "capacity": 5,                                // weight-capacity (1 cat at join_weight=5, OR 5 kittens at join_weight=1)
  "entry_origin_offset":    {"x": 0, "y": -16}, // px from host position to top-stand node
  "interior_origin_offset": {"x": 0, "y": -8},  // px from host position to inside node
  "entry_threshold_ru": 1,                      // jump-up requirement (used by ENTER scanner)
  "inner_size_ru": 2                            // body-size constraint (used by ENTER scanner)
}
```

`contained` is identical to `stack` in lifecycle (joiner gets a relationship, position-coupling pass updates joiner position from host position + offset, dissolution rules apply) and differs only in:

- Two nodes per occupied slot (entry + interior), not one (stack offset).
- Render z-order: joiner draws *behind* the container (`container.z - 1`) instead of in front.
- Scanner: `settles_in_containers` (this spec) instead of `settles_on_surfaces`.

This makes the cardboard box's existing `state_ads` block extend naturally:

```jsonc
// Boxes today (in engine/objects/object_state_manager.gd OBJECT_CONFIG, future-migrated to mod recipe):
&"new": {
  &"ads": [
    {&"desire_type": &"comfort",   &"strength": 700, &"radius_px": 32},
    {&"desire_type": &"curiosity", &"strength": 500, &"radius_px": 40, &"action": &"shred"},
  ],
  &"join": {
    &"type": &"contained",
    &"direction": &"any",
    &"capacity": 5,
    &"entry_origin_offset":    Vector2i(0, -16),
    &"interior_origin_offset": Vector2i(0, -8),
    &"entry_threshold_ru": 1,
    &"inner_size_ru": 2,
  },
},
&"worn": { ... same join, fewer ads ... },
&"scraps": { ... no join (capacity 0 or omit) ... }
```

A box in `scraps` state has no `join` - cats can't enter a destroyed box. Consistent with how the Resting-On spec dissolves `stack` joins when host transitions out.

### 5. Cat-owned purr emission geometry

Today `purr` is `{intensity: int}` and `hum_receiver` is `{radius_px: int}`. Today's `tick_charge` finds, for each purring cat, the nearest receiver in range, and adds intensity. The cat is passive ("there is a sound"); the HUM is the geometric agent ("I listen at radius 32").

**Inversion.** The cat owns the geometry; the HUM owns nothing.

```gdscript
// Cat (and any future purr-emitter):
&"purr": {
  &"intensity": int,    // 0-1000, written by ContentmentPurrBridge
  &"radius_px": int,    // 0-N, also written by ContentmentPurrBridge
}

// HUM (and any future hum-receiver):
&"hum_receiver": {}     // marker tag; no fields
```

**`tick_charge` flips.** For each entity with `purr`:

1. Compute its emission disk: `circle(position, purr.radius_px)`.
2. For each entity with `hum_receiver`: compute its body rect using `Constants.rack_column_rect_world(bay, rack)` clipped to the slot range the HUM occupies. The HUM's anchor slot is its top slot (rack-slot position from `world_init_system`); the body extends downward through `physical.size_ru` slots. Resulting rect: width = `RACK_WIDTH_PX = 23`, height = `physical.size_ru x SLOT_HEIGHT_PX`, top edge = top of anchor slot.
3. If disk  AND  rect non-empty, add `purr.intensity` to that HUM's reserve (clamped at capacity).

The body rect is computed each tick (cheap - 4 ints + an intersect test per receiver per cat). It's not cached; HUMs don't move.

A cat can charge multiple HUMs simultaneously if its disk intersects more than one body rect. The HUM has no per-tick cap on incoming charge; capacity ceiling is the only limit.

**ContentmentPurrBridge** writes both fields each tick:

```gdscript
const BASE_RADIUS_RU: int = 6   // 48 px at full intensity for adult cats
                                 // tunable in config/balance.jsonc

func tick() -> void:
    for cat_id in _purring_entities:
        var contentment: int = _db.get_field(cat_id, &"contentment", &"value")
        var is_satisfied: bool = contentment >= _satisfaction_threshold
        var rate: int = _db.get_field(cat_id, &"purr_config", &"rate_when_satisfied")
        var intensity: int = rate if is_satisfied else 0
        _db.set_field(cat_id, &"purr", &"intensity", intensity)

        var base_radius_px: int = _db.get_field(cat_id, &"purr_config", &"base_radius_ru") * SLOT_HEIGHT_PX
        var radius_px: int = base_radius_px * intensity / UNIT
        _db.set_field(cat_id, &"purr", &"radius_px", radius_px)
```

`base_radius_ru` is intrinsic to the body (kittens ~3 RU, adult cats 6 RU, large cats more). Stored in the species recipe under `purr_config`. Future inputs (mood, species traits, kitten amplifier) fold into the bridge formula without changing the field shape.

### 6. Animation + render

**`cat.jsonc` gains `edge_animations`** alongside the existing `animations` (state -> strip):

```jsonc
"edge_animations": {
  "WALK":      "walk",
  "JUMP_UP":   "jump",        // cat01_jump_strip4 (4 frames @ 8 fps)
  "JUMP_DOWN": "fall",        // cat01_fall_strip3
  "ENTER":     "ledgeclimb",  // cat01_ledgeclimb_strip11 (11 frames @ 8 fps - slow, deliberate)
  "CLIMB":     "wallclimb"    // cat01_wallclimb_strip8 (future)
}
```

Edge animations play during MOVING_TO traversal of that edge type. The frame counts and fps live in the existing `animation_frames` block; the orphan strips (`jump`, `fall`, `ledgeclimb`, `wallclimb`) already have entries and just aren't referenced by any state or edge today.

**Render z-order** in `animal_node.gd`:

```
default:                     z = z_floor
relationship "sleeping"
  joined via stack:          z = host.z + 1   (existing - Resting-On spec)
  joined via contained:      z = host.z - 1   (new - this spec; lip occludes lower body)
relationship "playing"
  joined via nearby:         z = z_floor      (existing - Resting-On spec)
```

The "cat tucked into box, ears poking out" effect comes from the z = box.z - 1 offset combined with the cat's natural sprite size relative to the 16-px box sprite. No per-asset masking needed.

**Purr emission VFX.** A `nodes/effects/purr_ring.gd` draws pixel-note glyphs at `purr.radius_px`, count/brightness scaling with `purr.intensity`. Reads GameStateDB; renders at display framerate; pure visual decoupling from sim.

## Data shapes summary

| Component | On | Shape | Notes |
|---|---|---|---|
| `body_capabilities` | Species recipe | `Dictionary<verb, params>` | Entity self-knowledge. Engine never branches on species id. |
| `body_geometry` | Species recipe | `{size_ru: int}` | Body cross-section for fit checks. |
| `purr_config` | Species recipe | `{rate_when_satisfied: int, base_radius_ru: int}` | Recipe-level inputs to ContentmentPurrBridge. |
| `purr` | Animal entity | `{intensity: int, radius_px: int}` | Per-tick. Both written by the bridge. |
| `hum_receiver` | HUM entity | `{}` | Marker tag. Body rect derived from `physical.size_ru x SLOT_HEIGHT_PX`. |
| `state_advertisements[state].join.type = "contained"` | Object recipe | `{type, direction, capacity, entry_origin_offset, interior_origin_offset, entry_threshold_ru, inner_size_ru}` | New join type. |
| `surface_top` | Object recipe | `{offset: Vector2i, width_px: int}` | Standable top edge. (Used by `walks` + `jumps` scanners; also a future `settles_on_surfaces` host.) |
| Relationship `&"sleeping"` | Joiner -> Host | - | Same name regardless of join type (stack on cat, contained in box). Created when joiner enters and cat ai_state is SLEEPING (or LOAFING etc.). |

## End-to-end loop

**Game launch (starter scenario applies):**

| Rack | Slot | Object | Notes |
|---|---|---|---|
| 0 | 0 | server_1u | |
| 0 | 1 | cardboard_box | Cat A pre-placed inside; relationship `&"sleeping"` to box-0; ai_state = SLEEPING |
| 1 | 0 | server_1u | |
| 1 | 1 | cardboard_box | Empty |
| 1 | 4-9 | hum_device | Single HUM in the demo |
| (floor) | - | Cat B | Pre-placed at `FLOOR_Y - 1` near rack 1's column; ai_state = IDLE |

**Tick 1+:** Cat A is already sleeping. ContentmentPurrBridge writes `purr.intensity` and `purr.radius_px`. `hum_system.tick_charge` computes Cat A's emission disk. Whether it intersects HUM-1's body rect depends on Cat A's contentment-driven `radius_px` value - at full bliss (`base_radius_ru: 6` x `intensity: 1000` / `UNIT` = 48 px) the disk easily reaches across the rack gap. Visible: pixel-note ring on Cat A; HUM bar charges *if and only if* Cat A is happy enough.

**Tick N - Cat B reaches a comfort threshold.** `DesireScatter` updates Cat B's comfort deficit. Box-1's `state_advertisements.new.ads[0]` (comfort, strength 700, radius_px 32) is in range. `DesireResolver.evaluate_budget` scores it. Highest score -> transition IDLE -> SEEKING(box-1).

**Path query.** `NavGraphBuilder` returns Cat B's per-species graph. Three relevant edges:

1. WALK: Cat B's current floor node -> floor-near-rack-1
2. JUMP_UP: floor-near-rack-1 -> entry_origin on box-1 (`delta_y = 16 px = 2 RU`; cat allowed: `jumps.max_height_ru = 3`)
3. ENTER: entry_origin -> interior_origin (`body_geometry.size_ru = 2 <= inner_size_ru = 2`; `entry_threshold_ru = 1 <= jumps.max_height_ru = 3`)

A* returns the path. SEEKING -> MOVING_TO.

**Traversal.** `MovementSystem.tick` advances Cat B one edge at a time. Edge type drives the animation clip:

- WALK -> walk strip, normal locomotion
- JUMP_UP -> jump_strip4 (4 frames) + land_strip2 (2 frames)
- ENTER -> ledgeclimb_strip11 (11 frames @ 8 fps)

On ENTER edge completion: `db.add_relationship(&"sleeping", cat_b_id, box_1_id)` (relationship name = lowercase joiner state-on-arrival, which is SETTLING -> SLEEPING for box-occupants); position-coupling pass snaps Cat B to `box-1.position + interior_origin_offset`. ai_state transitions through SETTLING -> SLEEPING.

**Purr -> charge.** Same loop as Cat A. Cat B's emission disk overlaps HUM-1's body rect (close range). HUM-1 charges. Visible: second pixel-note ring; HUM bar fills faster.

**Leaving the box.** When some other desire wins the score battle (hunger spike, novelty draw), the AI transitions Cat B from its ambient state to SEEKING(target). The state transition triggers an `on_state_change` hook that dissolves any incoming `&"sleeping"`, `&"loafing"`, etc. relationship the entity has as joiner. The cat's `position` snaps to the host's `entry_origin_offset` (lifting it back to the top-stand node). The path query for the new target then runs A* starting from the entry_origin node - the first edge in the returned path is typically a JUMP_DOWN to floor. The position-coupling pass no longer applies once the relationship is gone. The animator plays JUMP_DOWN's clip on traversal. No new "EXIT" edge type is needed: leaving is just (relationship dissolves) + (path A* finds from entry_origin).

**Pre-existing relationships in starter scenarios.** Scenario entries gain an optional `settled_in_ref` field for joiner-side entities:

```jsonc
{ "type": "tcp_cats:cat", "settled_in_ref": "box_0", "ai_state": "SLEEPING", "required": false }
```

`WorldInitSystem` resolves the ref after all entities have spawned (deferred pass, same as existing `cable_to`), then calls `db.add_relationship(&"sleeping", cat_id, host_id)` and snaps the cat's position to `host.position + interior_origin_offset`. The optional `ai_state` field (defaults to IDLE) lets the scenario seed an initial state so ContentmentPurrBridge has something to read on tick 1. Cat A in the slice uses both fields. This format extension is small and reusable for any future "start the world with X already happening" scenario.

**Failure modes (graceful):**

- Box-1 destroyed (HP -> 0, transitions to `scraps`) while Cat B is en route -> A* path invalidated next tick -> Cat B falls back to wandering. (Existing pattern.)
- Box-1 destroyed while Cat B is inside -> box transitions to `scraps` -> no `join` block -> safety check in position-coupling pass fires -> Cat B STARTLED, drops to floor. (Existing Resting-On dissolution.)
- Box-1 capacity reached -> ENTER edge not emitted in next path build -> Cat B targets next-best comfort ad.
- No path to box-1 (graph build returned no path) -> Cat B stays in WANDERING.

## Implementation slice - what ships in the plan

**Code touchpoints (estimated):**

1. **`engine/animals/`** - extend `body_capabilities` schema in species recipe loader; add `body_geometry`. Migrate `cat.jsonc` to use `body_capabilities` + `body_geometry`; remove the old `traversal` array and `max_jump_height_ru` field.
2. **`engine/navigation/NavGraphBuilder`** - replace single-graph build with per-species graph build. Add scanners for `walks`, `jumps`, `drops`, `settles_in_containers`. (Defer `climbs`, `fits_in_tubes`, `settles_on_surfaces` scanners - declared in spec, not wired.)
3. **`engine/objects/object_state_manager.gd`** - extend `OBJECT_CONFIG[&"cardboard_box"]` `state_ads` entries to support `{ads, join}` shape (currently bare ads array). Add `contained` join handling in the position-coupling pass alongside the existing `stack` handling.
4. **`engine/core/contentment_purr_bridge.gd`** - write both `purr.intensity` and `purr.radius_px` each tick.
5. **`engine/core/hum_system.gd`** - flip `tick_charge`: iterate purring entities, compute emission disk, check intersection with each receiver's body rect, sum intensity into matching HUMs.
6. **`mods/tcp_base/objects/hum_device.jsonc`** - drop `radius_px: 32` from `hum_receiver` (becomes `{}`). The body rect derives from `physical.size_ru`.
7. **`nodes/animal_node.gd`** - render Y from `position.y` directly. Add z-order rule for `contained` join (z = host.z - 1). Remove the `FLOOR_Y - 1` hardcode + matching AI-DEV note.
8. **`mods/tcp_cats/species/cat.jsonc`** - add `body_capabilities`, `body_geometry`, `purr_config.base_radius_ru`, `edge_animations` map.
9. **`mods/tcp_base/scenarios/starter.jsonc`** - replace existing layout with the demo: rack 0 server+box, rack 1 server+box, single HUM in rack 1, two cats (one pre-settled, one floor-spawned).
10. **`nodes/effects/purr_ring.gd`** - new scene, draws pixel-note glyphs at `purr.radius_px`. Listens to `purr` component changes via watcher.
11. **`docs/art-asset-tracker.md`** - note that `cat01_jump_strip4`, `cat01_land_strip2`, `cat01_ledgeclimb_strip11` are now wired; tracker entries removed from "orphaned."

**Defer (declared in spec, scanners absent in slice):**
- `fits_in_tubes` scanner
- `settles_on_surfaces` scanner
- `climbs` scanner
- `climbs_stairs` scanner

These ship when the matching infrastructure (tubes, shelves, walls, staircases) ships. Their absence does not affect the cat-jumps-into-box slice.

## Tests

**Unit tests (each gets `verify-test` stamp via the `/verify-test` skill):**

1. `tests/unit/test_nav_graph_builder_enter_edges.gd`
   - ENTER edge emitted when `body_geometry.size_ru <= container.inner_size_ru`
   - ENTER edge NOT emitted when body too big
   - ENTER edge NOT emitted when `entry_threshold_ru > jumps.max_height_ru`
   - ENTER edge NOT emitted when container has no `join` block (e.g., box in `scraps` state)

2. `tests/unit/test_nav_graph_builder_jump_up_edges.gd`
   - JUMP_UP edge emitted when `delta_y <= max_height_ru x SLOT_HEIGHT_PX`
   - JUMP_UP edge NOT emitted when too tall
   - JUMP_UP edge NOT emitted when horizontally misaligned beyond tolerance

3. `tests/unit/test_hum_system_emission_intersection.gd`
   - Disk that intersects HUM body rect -> reserve increases by `purr.intensity`
   - Disk that does NOT intersect -> reserve unchanged
   - Disk intersecting two HUMs -> both reserves increase
   - Cross-rack reach: cat-in-rack-0 with `radius_px = 48` charges HUM-in-rack-1; with `radius_px = 16` does not

4. `tests/unit/test_contentment_purr_bridge_radius.gd`
   - At intensity 0 -> radius_px = 0
   - At intensity = UNIT -> radius_px = base_radius_ru x SLOT_HEIGHT_PX
   - Linear interpolation between

5. `tests/unit/test_settled_in_relationship_lifecycle.gd`
   - ENTER edge traversal: relationship `&"sleeping"` added; cat position snaps to interior_origin
   - EXIT edge traversal: relationship removed; cat position snaps to entry_origin
   - Capacity gate: scanner emits ENTER edge for first joiner; emits no ENTER for joiner N+1 when capacity full
   - Box transitions `new` -> `scraps` while occupied: relationship dissolves; cat STARTLED (existing safety-check path)

**Integration tests:**

6. `tests/integration/test_cat_into_box_charges_hum.gd`
   - Apply starter scenario. Run N ticks (N tuned for sim convergence - likely 50-200).
   - Assert: Cat B has relationship `&"sleeping"` to box-1 by end of run.
   - Assert: HUM-1's reserve increased by >= K (K tuned to a clear above-noise threshold).
   - Spans desire scoring -> A* -> traversal -> settle -> purr -> charge in one assertion.

**Soak invariant (10,000+ ticks):**

7. `tests/simulation/test_no_orphaned_settled_relationships.gd`
   - At any tick, `db.get_targets(&"sleeping", any_id)` for animal IDs always points to entities that exist.
   - At any tick, `db.get_sources(&"sleeping", host_id)` count never exceeds `host.join.capacity`.

## Out of scope (deferred to later specs)

- Other body sizes wired in: ferret, kitten, gerbil, dog. Spec describes the recipe shape; no code needed to support them once the slice's scanners exist.
- `climbs`, `fits_in_tubes`, `settles_on_surfaces`, `climbs_stairs` scanners. Declared in spec; ship when the infrastructure ships.
- Multi-occupant boxes (`capacity > 1`). Schema supports it; tested only at capacity = 1 because the slice's body has `join_weight` not yet configured. (`join_weight` is from the Resting-On spec; this spec defers wiring it for boxes-as-host.)
- `surface_top` component on servers (would let cats stand on top of servers). Not needed for the slice - the box's own `entry_origin_offset` provides the top-stand node above the server.
- Cat-on-cat sleeping (the `sleepable_surface` / `settles_on_surfaces` pair). Spec describes how it composes with this work; implementation is its own follow-up.
- Saving/loading the cat's `settled_in` relationship across a save round-trip. Relies on existing `relationships` snapshot path (Resting-On spec Section 3 Save/load). Verify it works on `&"sleeping"` relationships pointing to objects (not animals); no new code expected.
- Multi-bay scaling for the navgraph builder (only bay 0 is simulated today; scanners run only on bay 0 entities).
- Box "shredded by claws" state transitions while occupied. Existing HP-decay path stays as-is. Curiosity-driven `shred` action ad is unchanged.
- Procedural purr-ring particle effects beyond the pixel-glyph ring.

## Open questions (tunable values to lock in implementation)

1. **`base_radius_ru` per recipe.** Adult cat: 6 (locked: 48 px at full bliss -> just reaches across rack gap). Kitten: TBD (likely 3 RU = 24 px -> strictly intra-rack). Lock kitten value when kittens are wired.
2. **Edge cost multipliers** (initial values in spec; tune empirically once the slice is playable).
3. **Horizontal alignment tolerance for `jumps` scanner** (proposed: 1/2 rack stride = ~15 px). Tune in implementation.
4. **Box `inner_size_ru: 2`** - locks adult cats in, kittens in, ferrets in. Tune if larger animals (dog) need to squeeze in or smaller animals (gerbil) need to be excluded for design reasons.
5. **`base_radius_ru` location.** Currently in `purr_config` block on the species recipe. Could move to `body_geometry`; defer until a second consumer needs it.

## Cross-spec alignment notes

- This spec uses **`state_advertisements` with `{ads, join}` blocks** as defined by the Resting-On spec. Box `state_ads` migrate from bare-array to `{ads, join}`. Implementation includes the structural migration.
- Relationships are named **lowercase joiner-state**, per Resting-On spec convention: `&"sleeping"` for a cat sleeping inside a box, identical to a cat sleeping on top of a cat. Join type (stack/nearby/contained) is recorded separately on the relationship's metadata if needed by the position-coupling pass.
- The Resting-On spec's **safety check** in the position-coupling pass extends to `contained` joins. Same logic: if host disappears, has no current join, or join type changes, dissolve the relationship and STARTLED the joiner.
- The Resting-On spec assumed host = animal. This spec extends host to also = object. The position-coupling pass already reads `position` from `db`; objects have a `position` component already; no special-case needed.
- The 2026-04-19 coordinate-system redesign converted `radius_ru` -> `radius_px` everywhere. This spec keeps that convention: distances/radii in `_px`, sizes/heights in `_ru`.

## Implementation estimate

Order-of-magnitude estimates from the touchpoints in Section "Implementation slice":

| Touchpoint | Lines | Risk |
|---|---|---|
| body_capabilities + body_geometry recipe schema | ~50 | Low |
| NavGraphBuilder per-species + scanners (walks, jumps, drops, settles_in_containers) | ~300 | Medium |
| state_advertisements `contained` join handling in OSM + position-coupling pass | ~80 | Low |
| ContentmentPurrBridge writes radius_px | ~20 | Low |
| HumSystem.tick_charge inversion | ~50 | Medium (logic flip) |
| animal_node.gd render Y + z-order | ~30 | Low |
| cat.jsonc additions | ~30 | Low |
| starter.jsonc rewrite | ~20 | Low |
| purr_ring.gd | ~80 | Low |
| Tests (5 unit + 1 integration + 1 soak) | ~400 | Low |

Roughly **800-1100 lines** including tests. About a day of focused work plus a half-day for tuning the tunables in Section "Open questions."
