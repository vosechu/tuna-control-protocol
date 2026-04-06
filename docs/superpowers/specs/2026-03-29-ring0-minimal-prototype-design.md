# Ring 0 Minimal Prototype — Design Spec

**Date:** 2026-03-29
**Status:** Review (post dev-team critique, pending user approval)
**Approach:** Vertical Slice (build one thin path through the full architecture, then widen)

---

## 1. Scope & Success Criteria

### What we're building

The thinnest vertical slice that proves: "Is watching animals react to infrastructure fun?"

Five pre-placed animals (3 cats, 2 ferrets) in a 5-rack datacenter. The player places servers, boxes, and clothes piles. Animals evaluate nearby objects against their individual desires and move toward what they want. Cats gravitate to heat; ferrets explore the floor. Hysteresis makes animals care about their choices. Purring is the audible success metric.

### Success milestone

A cat on screen walks toward a warm server, settles, and purrs. A ferret ignores the server and explores the floor. Moving the server causes the cat to relocate with a visible hysteresis delay. You watch this and think "that cat *cares* about that spot."

### In scope

- Godot project initialization (project.godot, autoloads, scene skeleton)
- GameStateDB (minimal subset: entities, components, get/set, tick, spatial queries)
- Heat grid (propagation from servers, diamond pattern, linear falloff)
- Desire system (warmth + comfort + curiosity, utility scoring against object advertisements)
- Animal AI (ambient/goal-directed state machine with hysteresis, 10 states)
- Navigation (AStar2D point graph, species-filtered, dynamic updates on placement)
- 5 animals on screen (3 cats using cat01-cat03 sprites, 2 ferrets using lilotter sprite)
- 3 placeable object types: server 2U, cardboard box, clothes pile
- Pre-placed starter infrastructure (1 server, 1 box) so animals have something to react to on tick 1
- Camera (pan across 5 racks)
- Purr sound (aggregate purr volume/pitch scales with number of content cats)
- Visual purr indicator (animated icon near purring cats) for deaf/muted players
- Base ambient hum (~-30dB datacenter electrical hum) so silence is relative
- Simple placement UI (sidebar buttons, click-to-place with removal toggle mode)
- Heat overlay toggle (color + pattern density for color-blind accessibility)
- Placeholder animal names (assigned at spawn for playtester storytelling)

### Out of scope (Ring 0 complete or later)

- Tuna cans, ferret dragging, robot arm sequence
- Furballs, feather + fan, cooling pipes
- Cardboard degradation / bedding scraps transformation
- Discovery events / proximity event manager
- HUD drawers, inspect panel, robot narrator
- Networking (architecture is server-authoritative, but solo only for Ring 0)
- Save/load
- Mod loader / config registry (hardcode tcp_base)
- All sound beyond purring and base ambient hum (meows, dooks, servos, fans)
- Body heat from sleeping animals
- Teaching system
- Kitten sprites (kittens are a later game phase)

---

## 2. Architecture

### Scene tree

```
Root (Node)
  GameServer (Node)                    # Authoritative state, even solo
    SimClock (Node)                    # Owns tick via physics_ticks_per_second = 10
    HeatGrid (Node)                   # Thin wrapper -> HeatGridCore (RefCounted)
    DesireResolver (Node)             # Thin wrapper -> DesireResolverCore (RefCounted)
    AnimalRegistry (Node)             # Thin wrapper -> manages animal entities
    ObjectRegistry (Node)             # Thin wrapper -> manages placed object entities

  GameClient (Node)
    Camera (Camera2D)                 # Pan across 5 racks
    World (Node2D)
      RackRow (Node2D)                # 5 Rack children (static sprites)
      Floor (Node2D)                  # Floor tile strip
      PlacedObjects (Node2D)          # Server, box, pile nodes
      Animals (Node2D)                # Cat and ferret nodes
      HeatOverlay (Node2D)            # Optional debug visualization
    PlacementUI (Control)             # Sidebar buttons for object selection
    SoundManager (Node)               # Aggregate purr mixing

  Events (Node)                       # Autoload: event bus singleton
```

### Tick order (10 Hz, every 100ms)

```gdscript
func _physics_process(_delta: float) -> void:
    db.advance_tick()

    # Step 1: Heat propagation
    heat_grid.propagate()

    # Step 2: Desire update
    scatter_heat_to_warmth()
    scatter_comfort_to_desires()
    db.add_all(&"desires", &"comfort", 5)      # comfort decays when not near source
    db.add_all(&"desires", &"curiosity", 3)    # curiosity builds constantly
    db.clamp_all(&"desires", &"warmth", 0, 1000)
    db.clamp_all(&"desires", &"comfort", 0, 1000)
    db.clamp_all(&"desires", &"curiosity", 0, 1000)

    # Step 3: AI scoring (adaptive time budget)
    desire_resolver.evaluate_budget()

    # Step 4: Movement
    movement_system.tick()

    # Step 5: Flush watcher notifications
    db.flush_notifications()
```

### Data flow

```
Player places server
  -> GameServer creates entity in GameStateDB (position + heat_source + advertisements)
  -> Events.object_placed emitted

Next tick:
  -> HeatGrid reads heat_source components, propagates to cells
  -> Scatter copies cell temperature to animal warmth satisfaction
  -> DesireResolver scores: cat warmth deficit * server ad strength * distance factor
  -> Score > commitment + 150 -> cat transitions IDLE -> SEEKING -> MOVING_TO
  -> Movement system walks cat toward server along nav path
  -> Cat arrives, enters SETTLING -> LOAFING (ambient)
  -> SoundManager detects cat is purring (LOAFING + warmth > 500)
  -> Purr volume increases

Player removes server:
  -> Events.object_removed emitted
  -> HeatGrid removes source, cells cool next tick
  -> Cat warmth drops below threshold
  -> But hysteresis: commitment score must decay first
  -> After 3-5 seconds, new score beats decayed commitment + 150
  -> Cat transitions to SEEKING next best option
  -> Purr fades as cat relocates
```

### Key architectural rules

- All game state in GameStateDB (integers, 0-1000 scale)
- Nodes are thin wrappers: delegate to RefCounted core objects
- Event bus (Events autoload) for cross-system broadcasts
- GameServer siblings read each other directly during tick
- No floats in core: conversion at rendering boundary only
- No null: sentinels (INVALID_ID = -1), empty arrays, asserts

---

## 3. GameStateDB (Ring 0 Subset)

### Interface

```gdscript
class_name GameStateDB extends RefCounted

const INVALID_ID: int = -1

# Entity lifecycle
func create_entity() -> int
func destroy_entity(entity_id: int) -> void
func has_entity(entity_id: int) -> bool

# Single-entity access
func get_field(entity_id: int, component: StringName, field: StringName) -> int
func set_field(entity_id: int, component: StringName, field: StringName, value: int) -> void
func get_component(entity_id: int, component: StringName) -> Dictionary
func set_component(entity_id: int, component: StringName, data: Dictionary) -> void
func has_component(entity_id: int, component: StringName) -> bool

# Batch operations (hot path)
func add_all(component: StringName, field: StringName, delta: int) -> void
func clamp_all(component: StringName, field: StringName, min_val: int, max_val: int) -> void

# Spatial queries
func update_spatial(entity_id: int, x: int, y: int) -> void
func query_radius(x: int, y: int, radius: int) -> Array[int]

# Watchers (end-of-tick batched)
func watch(component: StringName, callback: Callable) -> void
func flush_notifications() -> void

# Tick
func get_tick() -> int
func advance_tick() -> void
```

### Storage

Plain Dictionary internally for Ring 0. Interface designed for future swap to PackedInt32Array column storage without changing callers.

```gdscript
# Internal structure
var _entities: Dictionary = {}  # entity_id -> { component_name -> { field -> value } }
var _next_id: int = 1
var _tick: int = 0
var _watchers: Dictionary = {}  # component_name -> Array[Callable]
var _dirty_components: Dictionary = {}  # component_name -> Array[entity_id]
```

### Entity shapes

**Cat:**
```
species:     { id: "tcp_base:cat", variant: "cat01", name: "Mochi" }
position:    { x: 15200, y: 8400 }
desires:     { warmth: 200, comfort: 200, curiosity: 0 }
personality: { warmth_weight: 800, comfort_weight: 600, curiosity_weight: 100 }
ai_state:    { state: IDLE, meta_state: AMBIENT, commitment_score: 0 }
target:      { x: -1, y: -1, entity_id: -1 }
```

**Ferret:**
```
species:     { id: "tcp_base:ferret", variant: "lilotter", name: "Noodle" }
position:    { x: 30000, y: 20000 }
desires:     { warmth: 200, comfort: 200, curiosity: 0 }
personality: { warmth_weight: 400, comfort_weight: 600, curiosity_weight: 900 }
ai_state:    { state: IDLE, meta_state: AMBIENT, commitment_score: 0 }
target:      { x: -1, y: -1, entity_id: -1 }
```

**Starting desires at 200 (mildly uncomfortable) instead of 500.** Combined with pre-placed starter infrastructure (1 server + 1 box), animals begin by calmly drifting toward existing objects rather than scattering desperately on tick 1.

**Placeholder names:** Cats are Mochi, Biscuit, Noodle. Ferrets are Slinky, Bandit. Displayed in a small floating label above each animal. These are not the robot's device registry names (those come later) — just human-readable handles so playtesters can say "Mochi keeps going back to the server."

**Server 2U:**
```
position:    { x: 9600, y: 2400 }
heat_source: { value: 800, radius_ru: 3 }
advertisements: [ { desire_type: "warmth", strength: 800, radius_ru: 3, max_occupants: 1 } ]
```

**Cardboard box:**
```
position:    { x: 4800, y: 7200 }
advertisements: [ { desire_type: "comfort", strength: 700, radius_ru: 1, max_occupants: 1 } ]
```

**Clothes pile:**
```
position:    { x: 14400, y: 19200 }
advertisements: [
  { desire_type: "comfort", strength: 800, radius_ru: 1, max_occupants: 3 },
]
```

All values are integers. Position in position-scale units (100 per pixel, per code-style.md). Desires 0-1000 (0 = satisfied, 1000 = desperate). Personality weights 0-1000.

### Unit conversion

One canonical conversion function, used everywhere (no ad-hoc multiplication at call sites):

```gdscript
const POSITION_SCALE: int = 100       # position units per pixel
const SLOT_HEIGHT_PX: int = 24        # pixels per rack unit
const SLOT_HEIGHT_PU: int = 2400      # SLOT_HEIGHT_PX * POSITION_SCALE
const RACK_WIDTH_PX: int = 96
const RACK_WIDTH_PU: int = 9600

static func ru_to_pu(ru: int) -> int:
    return ru * SLOT_HEIGHT_PU

static func pu_to_ru(pu: int) -> int:
    return pu / SLOT_HEIGHT_PU
```

---

## 4. Heat Grid

### Structure

One integer temperature value (0-1000) per rack unit cell.

- 5 racks x 42 U = 210 rack cells
- 5 floor cells (one per rack width)
- Total: 215 cells, stored as PackedInt32Array

### Cell addressing

```gdscript
func rack_cell(rack: int, slot: int) -> int:
    return rack * 42 + slot

func floor_cell(rack: int) -> int:
    return 210 + rack
```

### Propagation (runs once per tick)

```gdscript
func propagate() -> void:
    _grid.fill(0)
    var sources: Array[int] = db.get_entities_with(&"heat_source")
    for entity_id in sources:
        var pos := db.get_component(entity_id, &"position")
        var heat := db.get_component(entity_id, &"heat_source")
        _apply_diamond(pos, heat)

func _apply_diamond(pos: Dictionary, heat: Dictionary) -> void:
    var src_rack: int = pos.x / RACK_WIDTH_PU
    var src_slot: int = pos.y / SLOT_HEIGHT_PU
    var value: int = heat.value
    var radius: int = heat.radius_ru

    # Diamond: 3U up, 1U down within source rack. Weak spillover to adjacent racks.
    # "3U left/right" means 3 slots laterally, NOT 3 racks.
    for ds in range(-3, 2):  # slot offset: -3U up to +1U down (asymmetric per spec)
        var s: int = src_slot + ds
        if s < 0 or s >= 42:
            continue
        var dist: int = absi(ds)
        if dist > radius:
            continue
        var falloff: int = value * (radius - dist) / radius
        var idx: int = rack_cell(src_rack, s)
        _grid[idx] = mini(_grid[idx] + falloff, 1000)

    # Weak cross-rack spillover (1/4 strength to adjacent racks, same slot only)
    for dr in [-1, 1]:
        var r: int = src_rack + dr
        if r < 0 or r >= 5:
            continue
        var spillover: int = value / 4
        _grid[rack_cell(r, src_slot)] = mini(_grid[rack_cell(r, src_slot)] + spillover, 1000)

    # Heat also radiates to floor below
    var floor_idx: int = floor_cell(src_rack)
    var floor_heat: int = value / (radius + 1)  # weak floor radiation
    _grid[floor_idx] = mini(_grid[floor_idx] + floor_heat, 1000)
```

### Query

```gdscript
func get_temperature(cell_index: int) -> int:
    return _grid[cell_index]
```

No overheating. Heat is purely beneficial. Values clamp at 1000.

Cross-rack spillover happens naturally via the `dr` loop extending to adjacent racks.

---

## 5. Desire System & Utility Scoring

### Desires for Ring 0

| Desire | Source of satisfaction | Decay per tick | Primary species |
|---|---|---|---|
| warmth | Heat grid cell temperature (scattered) | 0 (set directly from grid) | Cats |
| comfort | Proximity to comfort-advertising objects | 5 per tick (decays when not near source) | Both |
| curiosity | Visiting cells not recently visited | 3 per tick (constant low-grade itch) | Ferrets |

**Curiosity** is what makes ferrets visibly different from cats. While cats *settle* (find a warm spot and stay), ferrets *explore* (wander to new cells, satisfy curiosity briefly, then get restless again). A ferret with high curiosity_weight and low warmth_weight will patrol the floor even when warm spots are available. This produces a different verb from the same desire system.

Curiosity satisfaction: when a ferret enters a cell it hasn't visited in the last 100 ticks (~10 seconds), curiosity is set to 0 (fully satisfied). It then decays back up at 3/tick, driving the ferret to move again. Cats have curiosity_weight near 0, so they ignore this desire entirely.

### Scatter pattern (tick step 2)

Two-phase cached mapping from tick-architecture.md:

**Phase 1 — Maintain cell-to-entity mapping (on movement only):**
```gdscript
var _cell_entities: Dictionary = {}  # cell_index -> Array[int]

func _on_entity_moved(entity_id: int, old_cell: int, new_cell: int) -> void:
    if _cell_entities.has(old_cell):
        _cell_entities[old_cell].erase(entity_id)
    if not _cell_entities.has(new_cell):
        _cell_entities[new_cell] = []
    _cell_entities[new_cell].append(entity_id)
```

**Phase 2 — Scatter values (every tick):**
```gdscript
func scatter_heat_to_warmth() -> void:
    for cell_idx in _cell_entities:
        var temp: int = heat_grid.get_temperature(cell_idx)
        for entity_id in _cell_entities[cell_idx]:
            if db.has_component(entity_id, &"desires"):
                db.set_field(entity_id, &"desires", &"warmth", temp)
```

### Scoring (tick step 3)

```gdscript
const EVAL_TIME_BUDGET_USEC: int = 1000  # 1ms per tick
const SWITCH_THRESHOLD: int = 150

func evaluate_budget() -> void:
    var start: int = Time.get_ticks_usec()
    while _dirty.size() > 0:
        if Time.get_ticks_usec() - start >= EVAL_TIME_BUDGET_USEC:
            break
        var id: int = _pop_highest_deficit()
        _evaluate_one(id)

func _evaluate_one(entity_id: int) -> void:
    var pos: Dictionary = db.get_component(entity_id, &"position")
    var nearby: Array[int] = db.query_radius(pos.x, pos.y, 8 * SLOT_HEIGHT_PU)
    var best_score: int = 0
    var best_target: int = GameStateDB.INVALID_ID

    for other_id in nearby:
        if not db.has_component(other_id, &"advertisements"):
            continue
        var ads: Dictionary = db.get_component(other_id, &"advertisements")
        for ad in ads.list:
            var score: int = _score_ad(entity_id, other_id, ad)
            if score > best_score:
                best_score = score
                best_target = other_id

    var ai: Dictionary = db.get_component(entity_id, &"ai_state")
    if best_score > ai.commitment_score + SWITCH_THRESHOLD:
        _transition_to_seeking(entity_id, best_target, best_score)
```

### Scoring formula (all integer, from animal-ai.md)

```gdscript
func _score_ad(animal_id: int, object_id: int, ad: Dictionary) -> int:
    var desire_type: StringName = ad.desire_type
    var personality: Dictionary = db.get_component(animal_id, &"personality")
    var desires: Dictionary = db.get_component(animal_id, &"desires")

    var weight_key: StringName = StringName(desire_type + "_weight")
    var desire_weight: int = personality.get(weight_key, 500)
    var deficit: int = 1000 - desires.get(desire_type, 500)
    var strength: int = ad.strength

    var animal_pos: Dictionary = db.get_component(animal_id, &"position")
    var object_pos: Dictionary = db.get_component(object_id, &"position")
    var dist_pu: int = absi(animal_pos.x - object_pos.x) + absi(animal_pos.y - object_pos.y)
    var radius_pu: int = ad.radius_ru * SLOT_HEIGHT_PU
    if dist_pu > radius_pu:
        return 0
    var dist_factor: int = 1000 - (dist_pu * 1000 / radius_pu)

    return desire_weight * deficit / 1000 * strength / 1000 * dist_factor / 1000
```

### Dirty marking

Entities marked dirty when:
- Desire value crosses a threshold band (multiples of 100)
- Entity crosses a cell boundary
- Object placed or removed within perception radius (8 RU)

---

## 6. Animal AI State Machine

### States

| State | Meta | Animation | Min Duration | Species |
|---|---|---|---|---|
| IDLE | AMBIENT | idle_strip8 | 3s | Both |
| GROOMING | AMBIENT | crouch_strip8 | 10s | Cat |
| LOAFING | AMBIENT | sit_strip8 | 15s | Cat |
| SLEEPING | AMBIENT | sleep_strip8 / liedown_strip24 | 30s | Both |
| SNIFFING | AMBIENT | sneak_strip4 | 10s | Ferret |
| SPEED_BUMP | AMBIENT | liedown_strip8 | 15s | Ferret |
| SEEKING | GOAL_DIRECTED | idle_strip8 | 0s | Both |
| MOVING_TO | GOAL_DIRECTED | walk_strip8 | 0s | Both |
| SETTLING | GOAL_DIRECTED | sit_strip8 | 2s | Both |
| STARTLED | SPECIAL | fright_strip8 / dash_strip10 | 0.5s | Both |

### Transitions

```
AMBIENT -> GOAL_DIRECTED:  score > commitment + SWITCH_THRESHOLD (150)
GOAL_DIRECTED -> AMBIENT:  arrived at target, desire satisfied
Any -> STARTLED:           object removed while occupying, or pounced
STARTLED -> IDLE:          after 0.5-1.5s flee to nearest floor node
```

### Hysteresis

```gdscript
var commitment_score: int = 0

func try_transition(new_state: int, score: int) -> bool:
    if state_timer < min_duration:
        return false
    if meta_state == GOAL_DIRECTED:
        if score < commitment_score + SWITCH_THRESHOLD:
            return false
    _enter_state(new_state, score)
    return true

# Commitment decays 10 per second (1 per tick at 10Hz)
func tick() -> void:
    commitment_score = maxi(0, commitment_score - 1)
```

### Ambient state selection

Weighted random pool filtered by context:
- Warm + comfortable: GROOMING, LOAFING, SLEEPING eligible (cats)
- Warm: SLEEPING eligible (both)
- Default: IDLE, species-specific ambient states
- Weights tunable in config (hardcoded for Ring 0)

### Purr condition

A cat is "purring" when:
- ai_state.state is LOAFING or SLEEPING
- desires.warmth > 500

---

## 7. Navigation

### Graph structure

AStar2D point graph.

**Node types:**
- FLOOR_NODE: one per rack width, along the floor strip (Y = floor level)
- RACK_SLOT_NODE: one per occupied/accessible rack slot

**Edge types:**
- WALK: all species, between adjacent floor nodes
- JUMP_UP: cats only, floor to low rack slots (max 3U height)
- JUMP_DOWN: cats any height, ferrets max 1U

### Species filtering

```gdscript
class_name SpeciesAStar extends AStar2D

var _species: StringName = &""
var _edge_types: Dictionary = {}  # point_pair -> StringName

func _compute_cost(from_id: int, to_id: int) -> float:
    var edge_type: StringName = _edge_types.get(_edge_key(from_id, to_id), &"WALK")
    if not _can_traverse(_species, edge_type):
        return INF
    return super._compute_cost(from_id, to_id)
```

### Dynamic updates

```gdscript
func on_object_placed(entity_id: int, rack: int, slot: int) -> void:
    var nav_id: int = _add_rack_slot_node(rack, slot)
    _connect_to_adjacent(nav_id, rack, slot)

func on_object_removed(entity_id: int, rack: int, slot: int) -> void:
    var nav_id: int = _get_rack_slot_node(rack, slot)
    _disconnect_and_remove(nav_id)
    # Animals on this node get STARTLED
```

### Movement

Animals follow A* path at fixed speed per species. Position updated in tick step 4 as integer position-scale units. Sprite position interpolated in `_process` using `Engine.get_physics_interpolation_fraction()`.

---

## 8. Rendering

### Sprite scaling

Animal sprites render at **integer 2x scale** for pixel-perfect crispness. Infrastructure stays at native 1x (already built to 24px/U spec). Cats at 2x are 80px tall (~3.3U) — slightly oversized for a rack slot, which reads naturally (cats spill over edges). Ferrets at 2x are 64px (~2.7U).

| Asset | Native size | Scale | On screen | Notes |
|---|---|---|---|---|
| Cat (40x40 frame) | 40px | 2x | 80px (~3.3U) | Slightly oversized, looks natural |
| Ferret/otter (32x32 frame) | 32px | 2x | 64px (~2.7U) | Lower profile, correct for ferrets |
| Kitten (32x32 frame) | 32px | 2x | 64px (~2.7U) | Same as ferret, smaller than adult cat |
| Server 2U | 84x48 native | 1x | 84x48 | Built to 24px/U spec |
| Rack frame | 96x1008 native | 1x | 96x1008 | Built to 24px/U spec |
| Cardboard box | 60x72 native | 1x | 60x72 | Built to 24px/U spec |

All sprites use `texture_filter = TEXTURE_FILTER_NEAREST`. Integer scaling guarantees every source pixel maps to a perfect 2x2 block — no blurring, no shimmering.

### Z-ordering

Rendering bottom-to-top:
1. Floor tiles (Y = floor level, lowest)
2. Rack frames (static background)
3. Placed objects (z-sorted by Y position within rack)
4. Animals (z-sorted by Y position)
5. Heat overlay (semi-transparent, toggled)

Godot's YSort (or manual z_index assignment per Y position) handles animal/object overlap.

### Z-ordering

Animals and objects share a continuous Y-sorted space. Z-index formula:

```gdscript
# Base layer values (set once)
const Z_FLOOR: int = 0
const Z_RACK_BG: int = 10
const Z_PLACED_OBJECT_BASE: int = 100
const Z_ANIMAL_BASE: int = 200
const Z_OVERLAY: int = 1000

# Dynamic z_index for Y-sorted entities (set in _process)
# Y position in pixels / 2 gives sub-slot granularity
node.z_index = Z_ANIMAL_BASE + (screen_y / 2)
```

Rack slots and floor are separate coordinate spaces visually but share one Y axis for sorting. A cat at rack slot 8 (Y=192px) sorts above a ferret on the floor (Y=1008px+). Objects use the same formula with `Z_PLACED_OBJECT_BASE`. Animals always render above objects at the same Y position.

### Heat overlay

Optional toggle (press H or click toggle button). Dual-channel display for color-blind accessibility:

- **Color:** 0 = invisible, 1-500 = blue to yellow, 500-1000 = yellow to red, alpha 0.25
- **Pattern:** hatching density increases with temperature (0 = none, 500 = sparse diagonal lines, 1000 = dense cross-hatch)

Both channels encode the same information. Color-blind players read the pattern; color-sighted players read either. For debug/tuning, not final art.

---

## 9. Sound

### Base ambient hum

A constant low datacenter electrical hum at -30dB. Always playing. This grounds the space so that "no cats purring" feels like *relative* silence (quieter than baseline), not dead air. One AudioStreamPlayer with a looping tone.

### Purr system

Purr state is maintained incrementally via watchers on `ai_state` and `desires` components, not recomputed by polling every frame. When a cat's ai_state or warmth changes, the watcher updates a `_purring_count` integer. The `_process` function only reads this cached count.

```gdscript
# SoundManager
var _purr_player_1: AudioStreamPlayer
var _purr_player_2: AudioStreamPlayer
var _purring_count: int = 0
var _total_cats: int = 0

func _ready() -> void:
    db.watch(&"ai_state", _on_ai_state_changed)
    db.watch(&"desires", _on_desires_changed)

func _on_ai_state_changed(entity_id: int) -> void:
    _recount_purring()

func _on_desires_changed(entity_id: int) -> void:
    _recount_purring()

func _recount_purring() -> void:
    # Recount from cached entity list (not a full scan)
    _purring_count = 0
    for entity_id in _cat_entity_ids:
        var ai: Dictionary = db.get_component(entity_id, &"ai_state")
        var desires: Dictionary = db.get_component(entity_id, &"desires")
        if (ai.state == &"LOAFING" or ai.state == &"SLEEPING") and desires.warmth > 500:
            _purring_count += 1

func _process(delta: float) -> void:
    var target_db: float = -40.0  # silence
    if _purring_count > 0 and _total_cats > 0:
        var ratio: float = float(_purring_count) / float(_total_cats)
        target_db = lerpf(-20.0, -6.0, ratio)  # ceiling at -6dB, not 0dB

    # Asymmetric smoothing: faster ramp-up, slower decay
    var smooth: float = 0.08 if target_db > _purr_player_1.volume_db else 0.03
    _purr_player_1.volume_db = lerpf(_purr_player_1.volume_db, target_db, smooth)
    _purr_player_2.volume_db = lerpf(_purr_player_2.volume_db, target_db - 3.0, smooth)
```

Two purr loops running simultaneously with slight pitch offset (0.95 and 1.05) for organic layered sound. Volume scales with the ratio of purring cats to total cats, ceiling at -6dB. Asymmetric smoothing: ramp-up is faster (0.08) for a satisfying rush when a cat settles, decay is slower (0.03) so the purr lingers.

### Visual purr indicator

Deaf and muted players need a visual equivalent of purring. Each purring cat displays a small animated icon: a subtle "zzz" or stylized sound wave near the sprite, pulsing gently. This is the accessibility backup for the core mechanic — not optional.

The purr is the heartbeat of the game. Relative silence means something is wrong. A rich, layered purr means the datacenter is thriving.

---

## 10. Player Interaction

### Placement

- Simple sidebar with 3 buttons: Server, Box, Pile
- Click button to select object type (or press 1/2/3 keyboard shortcut)
- Mouse over rack shows placement ghost (highlight valid slots, red for invalid)
- Server: 2U tall, must be in rack slots 5-41 (below TOR switch)
- Box: 3U tall, rack slots only
- Pile: floor level only, within a rack width
- Click to confirm placement
- **Collision with animals:** if an animal occupies the target slot, placement is blocked (ghost shows red). The player must wait for the animal to move or place elsewhere. Animals are never forcibly displaced by placement — only by removal of objects they're sitting on.
- Events.object_placed emitted

### Removal

- Sidebar has a "Remove" toggle button (or press R keyboard shortcut). When active, cursor changes to indicate removal mode.
- Click on a placed object in removal mode starts 2-second CLEARING state
- Object sprite pulses (alpha oscillation accelerating as timer progresses — visual countdown)
- Occupying animals receive eviction stimulus -> STARTLED
- After 2 seconds, object destroyed, nav node removed
- Events.object_removed emitted
- Cancel: click the object again during CLEARING to cancel
- Click elsewhere or press R/Escape to exit removal mode
- **No right-click required.** Right-click is a shortcut for removal (for players who have it) but the toggle mode works with any single-button input device.

### Empty datacenter behavior

When no objects are placed (or all are removed), animals enter a "nothing to seek" state:
- All desires remain at their current values (warmth decays toward 0 without heat sources)
- Animals cycle through ambient behaviors at floor level (IDLE, SNIFFING for ferrets)
- No desperation, no panic — they're mildly bored, not suffering (abundance principle)
- This naturally prompts the player to place something without punishing them

### Pre-placed starter infrastructure

The prototype starts with:
- 1 server at rack 2, slots 20-21 (center of the scene, producing heat)
- 1 cardboard box at rack 1, slots 8-10 (nearby but not adjacent — creates a choice)

This gives animals something to react to immediately while still leaving most of the 5-rack space empty for the player to fill.

### Camera

- Click-drag or WASD/arrow keys to pan horizontally
- Scroll wheel or +/- keys or PgUp/PgDn to zoom (2 levels: rack view and overview)
- Clamp to world bounds (5 racks + margins)

---

## 11. Available Assets

### Sprites

| Category | Assets | Source |
|---|---|---|
| Cats (5 variants) | 23 animations each, 40x40px frames | catset pack (itch.io) |
| Kittens (5 variants) | 17 animations each, 32x32px frames | kittens pack (itch.io) |
| Ferret (1 variant) | 20 animations, 32x32px frames | lilotter pack (itch.io, otter stand-in) |
| Infrastructure | rack_frame, server_2u_off, pipe_cooling_vertical | Generated (Pillow) |
| Objects | box_cardboard_new, pile_clothes, tuna_can_sealed/open, furball, feather, fan_desk, bedding_scraps | Generated (Pillow) |
| Robot | arm_station | Generated (Pillow) |
| Environment | floor_tile | Generated (Pillow) |

### Sounds

| Asset | Source |
|---|---|
| purr_loop_01.wav | Freesound (megrez7274) |
| purr_loop_02.wav | Freesound (megrez7274) |

### Animation mapping (Ring 0)

| AI State | Cat animation | Ferret animation |
|---|---|---|
| IDLE | cat{NN}_idle_strip8 | lilotter_idle_strip8 |
| GROOMING | cat{NN}_crouch_strip8 | — |
| LOAFING | cat{NN}_sit_strip8 | — |
| SLEEPING | cat{NN}_sleep_strip8 | lilotter_sleep_strip4 |
| SNIFFING | — | lilotter_sneak_strip4 |
| SPEED_BUMP | — | lilotter_liedown_strip8 |
| MOVING_TO | cat{NN}_walk_strip8 | lilotter_walk_strip8 |
| STARTLED | cat{NN}_fright_strip8 | lilotter_dash_strip10 |

---

## 12. Known Gaps & Future Work

| Gap | When to address |
|---|---|
| Only 1 otter model, need 2 distinct ferrets | Palette swap (warm vs cool hue shift) before Ring 0 complete |
| No mod loader — tcp_base content hardcoded | First task after Ring 0 |
| Entity shapes hardcoded in GDScript, not JSON | Write species/object JSON files alongside code; mod loader reads them in Ring 1 |
| Dictionary storage in GameStateDB | Profile at 100+ entities, swap at 500+ |
| No save/load | Before Ring 1 |
| No networking | Architecture is ready; wire up before multiplayer |
| Placeholder infrastructure art | Replace incrementally, no code changes needed |
| Comfort decay is simplistic (flat 5/tick) | Tune after playtesting Ring 0 |
| No occupancy enforcement in scoring | Add soft occupancy checks in Ring 0 complete |
| Ferret sprite naming (lilotter_ prefix) | Alias to ferret_ convention when second variant arrives |
| No spatial audio for purring | Add AudioStreamPlayer2D per cat in Ring 0 complete |
| No `spawn_from_template` in GameStateDB | Add when dynamic spawning needed (Ring 1) |

---

## 13. Build Order (Vertical Slice)

Each step adds one visible behavior. Tests written alongside each step.

| Step | What | Visible result |
|---|---|---|
| 1 | project.godot, autoloads, Events bus | Godot opens, empty scene |
| 2 | GameStateDB (RefCounted, minimal interface) | Unit tests pass |
| 3 | Scene skeleton: racks, floor, camera, pre-placed server + box | 5 racks visible, camera pans, starter objects in place |
| 4 | One cat entity + AnimalNode (with name label) | Cat named "Mochi" on screen, idle animation |
| 5 | HeatGrid + heat overlay | Temperature visualization around pre-placed server |
| 6 | Desire scatter + DesireResolver (warmth only) | Mochi walks toward warm server |
| 7 | Hysteresis + commitment | Mochi stays put when server removed, then reluctantly relocates |
| 8 | Ambient state machine | Mochi cycles through idle/grooming/loafing/sleeping |
| 9 | Purr sound + visual purr indicator + ambient hum | Hear purring when Mochi is content; see visual indicator; base hum grounds the space |
| 10 | Add comfort desire + clothes pile | Mochi chooses between warmth and comfort |
| 11 | Add curiosity desire | Foundation for ferret exploration behavior |
| 12 | Add 2 more cats (different personality weights) | Biscuit and Noodle make different choices than Mochi |
| 13 | Add 2 ferrets (curiosity-driven exploration) | Slinky and Bandit patrol the floor, visibly different behavior from cats |
| 14 | Placement UI (place + remove toggle) + keyboard shortcuts | Player can rearrange, animals react |
| 15 | Nav graph (dynamic, species-filtered) | Cats jump to rack slots, ferrets can't |

**Milestone after step 9:** First Lens of the Toy test. Can you watch Mochi and feel something?

**Milestone after step 15:** Full Ring 0 minimal. Ready for playtesting and tuning.
