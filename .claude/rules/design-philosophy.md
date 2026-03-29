# TCP Design Philosophy Rules

These rules apply to ALL code written for TCP.

## Pure Core Pattern
All game logic lives in `RefCounted` or `Resource`, never `Node`. Nodes are thin wrappers that delegate to core objects. Test: if you can't unit-test without a scene tree, it's in the wrong place.

## Base Game Is a Mod
The engine is a framework; `tcp_base` is a mod. If something can't be done via the mod API, the framework needs work — not a special case. This is a day-one hard constraint like networking — not aspirational, not "we'll add it later." The mod loading pipeline, config merging, and namespaced IDs must work before any game content exists.

## Redux-Style Central State
All mutable game state in `GameStateDB`. Commands mutate (return void). Queries read (never null). State flows: Intent -> Command -> GameStateDB -> Event Bus -> Nodes React. Nodes never hold authoritative state.

## Batch-First API
The primary GameStateDB operations are "given a component, apply this to all matching entities" — not entity-by-entity access. Column-oriented storage for hot components (PackedInt32Array) behind a row-oriented single-entity view for AI scoring. Single-entity access exists but is not the default path.

## Integers Over Floats
Use integers for game values (0-1000 for 0.0-1.0). Floats only at rendering boundary (positions, audio, shaders, Vector2/Vector3). No float drift over ticks.

## Null Is the Enemy
Validate at system boundaries. Once past validation, data is trusted. Never accept/return null. Model absence explicitly: `NullDesireSource`, empty arrays, sentinel IDs (`INVALID_ID`).

## Explode Early
Invalid state crashes in debug, not propagates silently. Assert is a contract, not error handling. Production: log + skip.

## Deterministic Simulation
Same seed + same commands = identical output. Integer math, fixed tick rate, seeded RNG, deterministic iteration order.

## Config Is Not Code
Every tunable number in JSON. Only structural numbers in code (0, 1, -1, INVALID_ID, array indices, loop bounds).

## Change Detection
GameStateDB tracks which tick each component was last modified. `set_field` and `set_component` skip the write and notification if data is identical. Systems query `was_changed(entity_id, component, since_tick)` or `get_changed_entities(component, since_tick)` to react only to real mutations. This eliminates watcher noise at scale (1000 animals with desire decay every tick = 1000 no-op callbacks without this).

## Spawn Templates
Spawning an entity uses species JSON to auto-populate all required components. `spawn_from_template(species_id, overrides)` reads the species definition, creates the entity, deep-merges overrides. No manual component assembly. Every animal is guaranteed to have desires, personality, position, behavior — the template defines the *shape*, personality randomization provides the *values*.

## Lifecycle Hooks
GameStateDB fires callbacks on component lifecycle events — not just value changes. Three hooks beyond the existing watcher:
- **on_add**: component added to entity for the first time (spatial hash insertion, teaching system registration)
- **on_remove**: component removed from entity (spatial hash eviction, advertisement withdrawal)
- **on_despawn**: entity destroyed (relationship cleanup, nav graph removal, proximity cooldown purge)

Hooks are batched to end-of-tick like watchers. They do not execute synchronously during the mutation.

## Entity Relationships
GameStateDB maintains a relationship table for entity-to-entity connections: teaching lineages, social bonds, infrastructure links. Lightweight bidirectional lookup — forward (`get_targets`) and reverse (`get_sources`). Relationships auto-clean on entity despawn via lifecycle hooks. Relationship types are defined in config, not code.

---

## Reference: GameStateDB Interface

Batch-first API. Column-oriented storage for hot components (PackedInt32Array internally). Row view assembled on demand for AI scoring.

```gdscript
class_name GameStateDB extends RefCounted

const INVALID_ID: int = -1

# ── Entity lifecycle (cold path) ──

func create_entity() -> int                                    # allocates ID, returns it
func create_entity_with_id(entity_id: int) -> void             # for save loading / networking
func destroy_entity(entity_id: int) -> void                    # removes all components, fires notification
func has_entity(entity_id: int) -> bool                        # O(1) guard check
func entity_count() -> int

# ── Batch column operations (hot path — backed by PackedInt32Array) ──

func add_all(component: StringName, field: StringName, delta: int) -> void
func mul_all(component: StringName, field: StringName, factor: int) -> void   # factor in 0-1000 scale
func clamp_all(component: StringName, field: StringName, min_val: int, max_val: int) -> void
func set_all(component: StringName, field: StringName, value: int) -> void

# ── Working set queries (return entity IDs for iteration) ──

func get_entities_with(component: StringName) -> Array[int]
func get_entities_with_all(components: Array[StringName]) -> Array[int]
func get_entities_by_species(species_id: StringName) -> Array[int]
func count_by_species(species_id: StringName) -> int

# ── Spatial queries (backed by SpatialHash, updated incrementally) ──

func update_spatial(entity_id: int, x: int, y: int) -> void
func remove_spatial(entity_id: int) -> void
func query_radius(x: int, y: int, radius: int) -> Array[int]
func query_radius_with(x: int, y: int, radius: int, component: StringName) -> Array[int]
func query_rect(min_x: int, min_y: int, max_x: int, max_y: int) -> Array[int]

# ── Single-entity access (AI scoring, inspect panel) ──

func get_field(entity_id: int, component: StringName, field: StringName) -> int
func set_field(entity_id: int, component: StringName, field: StringName, value: int) -> void
func add_field(entity_id: int, component: StringName, field: StringName, delta: int) -> void
func get_component(entity_id: int, component: StringName) -> Dictionary   # row view (assembled from columns)
func set_component(entity_id: int, component: StringName, data: Dictionary) -> void
func has_component(entity_id: int, component: StringName) -> bool
func remove_component(entity_id: int, component: StringName) -> void

# ── Watchers (end-of-tick batched) ──

func watch(component: StringName, callback: Callable) -> void
func unwatch(component: StringName, callback: Callable) -> void
func flush_notifications() -> void                             # called once at end of tick

# ── Lifecycle hooks (end-of-tick batched, like watchers) ──

enum Lifecycle { ADDED, REMOVED, DESPAWNED }

func watch_lifecycle(component: StringName, event: Lifecycle, callback: Callable) -> void
func watch_entity(entity_id: int, component: StringName, callback: Callable) -> void  # entity-scoped

# ── Change detection ──

func was_changed(entity_id: int, component: StringName, since_tick: int) -> bool
func get_changed_entities(component: StringName, since_tick: int) -> Array[int]

# ── Relationships ──

func add_relationship(rel: StringName, from_id: int, to_id: int) -> void
func remove_relationship(rel: StringName, from_id: int, to_id: int) -> void
func get_targets(rel: StringName, from_id: int) -> Array[int]          # forward: who does from_id point to?
func get_sources(rel: StringName, to_id: int) -> Array[int]            # reverse: who points to to_id?
func get_all_relationships(entity_id: int) -> Dictionary               # all rels involving this entity

# ── Spawn templates ──

func spawn_from_template(species_id: StringName, overrides: Dictionary = {}) -> int  # creates entity with all required components

# ── Dirty tracking (drives AI evaluation priority) ──

func mark_dirty(entity_id: int) -> void                        # entity needs AI re-evaluation
func pop_dirty(budget_usec: int) -> Array[int]                 # returns up to budget's worth, highest deficit first

# ── Tick state ──

func get_tick() -> int
func advance_tick() -> void

# ── Snapshot / serialization (cold path) ──

func snapshot() -> Dictionary                                   # full state for saves
func load_snapshot(data: Dictionary) -> void                    # restore from save
func snapshot_delta(since_tick: int) -> Dictionary              # changes since tick (networking)
func apply_delta(delta: Dictionary) -> void                     # apply server delta (client)

# ── Bulk operations (cold path — save loading, world gen) ──

func create_entities_bulk(entity_defs: Array[Dictionary]) -> Array[int]
func destroy_entities_bulk(entity_ids: Array[int]) -> void
```

### Hot path call frequency

| Per tick | Methods |
|---|---|
| Thousands | `add_all`, `mul_all`, `clamp_all`, `get_field`, `set_field` |
| Tens | `get_entities_with`, `query_radius_with`, `update_spatial`, `was_changed`, `get_changed_entities` |
| Once | `advance_tick`, `flush_notifications`, `pop_dirty` |
| On network tick | `snapshot_delta`, `apply_delta` |
| Rare (events) | `create_entity`, `destroy_entity`, `set_component`, `spawn_from_template`, `add_relationship`, `remove_relationship` |
| Very rare (save/load) | `snapshot`, `load_snapshot`, `create_entities_bulk` |

### Column storage internals

Each component+field pair maps to a PackedInt32Array. Entity IDs map to array indices via a lookup table. `add_all` is a tight native loop over the packed array — no Variant boxing, no Dictionary chasing.

```gdscript
# Internal: add_all(&"desires", &"hunger", 5)
var col: PackedInt32Array = _columns[&"desires.hunger"]
for i in col.size():
    col[i] += 5
```

The row view (`get_component`) assembles a Dictionary from columns on demand. Only used for AI scoring (~20 calls/tick) and inspect panel.
