---
paths:
  - "engine/core/game_state_db*"
  - "engine/core/entity_registry.gd"
---

# GameStateDB Interface

Companion to `design-philosophy.md` (which holds the design principles). This file is the API contract: full method signatures, hot-path call frequency, column-storage internals. Path-gated narrowly so it only loads when working on the DB itself or its closest collaborator.

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
func add_field_subset(component: StringName, field: StringName, deltas_by_entity: Dictionary) -> void   # per-entity deltas in one pass
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

## Hot path call frequency

| Per tick | Methods |
|---|---|
| Thousands | `add_all`, `add_field_subset`, `mul_all`, `clamp_all`, `get_field`, `set_field` |
| Tens | `get_entities_with`, `query_radius_with`, `update_spatial`, `was_changed`, `get_changed_entities` |
| Once | `advance_tick`, `flush_notifications`, `pop_dirty` |
| On network tick | `snapshot_delta`, `apply_delta` |
| Rare (events) | `create_entity`, `destroy_entity`, `set_component`, `spawn_from_template`, `add_relationship`, `remove_relationship` |
| Very rare (save/load) | `snapshot`, `load_snapshot`, `create_entities_bulk` |

## Column storage internals

Each component+field pair maps to a PackedInt32Array. Entity IDs map to array indices via a lookup table. `add_all` is a tight native loop over the packed array — no Variant boxing, no Dictionary chasing.

```gdscript
# Internal: add_all(&"desires", &"hunger", 5)
var col: PackedInt32Array = _columns[&"desires.hunger"]
for i in col.size():
    col[i] += 5
```

The row view (`get_component`) assembles a Dictionary from columns on demand. Only used for AI scoring (~20 calls/tick) and inspect panel.
