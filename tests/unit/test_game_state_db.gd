extends GutTest

var _db: GameStateDB


func before_each() -> void:
	_db = GameStateDB.new()


# ── Entity lifecycle ──────────────────────────────────────────────────────────

func test_create_entity_returns_unique_ids():
	var id_a: int = _db.create_entity()
	var id_b: int = _db.create_entity()
	var id_c: int = _db.create_entity()
	assert_ne(id_a, id_b, "Each create_entity call must return a unique ID")
	assert_ne(id_b, id_c, "Each create_entity call must return a unique ID")
	assert_ne(id_a, id_c, "Each create_entity call must return a unique ID")


func test_create_entity_ids_are_not_invalid_id():
	var id: int = _db.create_entity()
	assert_ne(id, GameStateDB.INVALID_ID, "create_entity must never return INVALID_ID")


func test_has_entity_returns_true_after_create():
	var id: int = _db.create_entity()
	assert_true(_db.has_entity(id), "has_entity must return true for a created entity")


func test_has_entity_returns_false_for_unknown_id():
	assert_false(_db.has_entity(999), "has_entity must return false for an unknown ID")


func test_has_entity_returns_false_for_invalid_id():
	assert_false(_db.has_entity(GameStateDB.INVALID_ID), "has_entity must return false for INVALID_ID")


func test_destroy_entity_removes_entity():
	var id: int = _db.create_entity()
	_db.destroy_entity(id)
	assert_false(_db.has_entity(id), "has_entity must return false after destroy_entity")


func test_destroy_entity_removes_all_components():
	var id: int = _db.create_entity()
	_db.set_component(id, &"desires", {&"hunger": 500})
	_db.destroy_entity(id)
	assert_false(_db.has_entity(id), "Entity must be gone after destroy")
	assert_false(_db.has_component(id, &"desires"), "Components must be removed after destroy")


func test_ids_start_from_one():
	var id: int = _db.create_entity()
	assert_gt(id, 0, "Entity IDs must be positive integers (INVALID_ID is -1)")


# ── Component access ──────────────────────────────────────────────────────────

func test_set_and_get_component():
	var id: int = _db.create_entity()
	_db.set_component(id, &"desires", {&"hunger": 600, &"warmth": 800})
	var comp: Dictionary = _db.get_component(id, &"desires")
	assert_eq(comp[&"hunger"], 600, "get_component must return stored hunger value")
	assert_eq(comp[&"warmth"], 800, "get_component must return stored warmth value")


func test_has_component_returns_true_after_set():
	var id: int = _db.create_entity()
	_db.set_component(id, &"desires", {&"hunger": 500})
	assert_true(_db.has_component(id, &"desires"), "has_component must return true after set_component")


func test_has_component_returns_false_for_missing():
	var id: int = _db.create_entity()
	assert_false(_db.has_component(id, &"desires"), "has_component must return false when component not set")


func test_set_component_duplicates_data():
	# Modifying the original dict after set_component must not affect stored data.
	var id: int = _db.create_entity()
	var original: Dictionary = {&"hunger": 500}
	_db.set_component(id, &"desires", original)
	original[&"hunger"] = 999
	var comp: Dictionary = _db.get_component(id, &"desires")
	assert_eq(comp[&"hunger"], 500, "set_component must deep-copy data to prevent aliasing")


func test_get_field_returns_stored_value():
	var id: int = _db.create_entity()
	_db.set_component(id, &"desires", {&"hunger": 750})
	assert_eq(_db.get_field(id, &"desires", &"hunger"), 750, "get_field must return the stored integer value")


func test_set_field_updates_value():
	var id: int = _db.create_entity()
	_db.set_component(id, &"desires", {&"hunger": 500})
	_db.set_field(id, &"desires", &"hunger", 200)
	assert_eq(_db.get_field(id, &"desires", &"hunger"), 200, "set_field must update the stored value")


func test_set_component_overwrites_existing():
	var id: int = _db.create_entity()
	_db.set_component(id, &"desires", {&"hunger": 500})
	_db.set_component(id, &"desires", {&"hunger": 999, &"warmth": 400})
	var comp: Dictionary = _db.get_component(id, &"desires")
	assert_eq(comp[&"hunger"], 999, "set_component must overwrite existing component data")
	assert_eq(comp[&"warmth"], 400, "set_component must store new keys")


# ── Batch operations ──────────────────────────────────────────────────────────

func test_add_all_adds_delta_to_all_matching_entities():
	var id_a: int = _db.create_entity()
	var id_b: int = _db.create_entity()
	_db.set_component(id_a, &"desires", {&"hunger": 500})
	_db.set_component(id_b, &"desires", {&"hunger": 300})
	_db.add_all(&"desires", &"hunger", 50)
	assert_eq(_db.get_field(id_a, &"desires", &"hunger"), 550, "add_all must add delta to entity A")
	assert_eq(_db.get_field(id_b, &"desires", &"hunger"), 350, "add_all must add delta to entity B")


func test_add_all_ignores_entities_without_component():
	var id_a: int = _db.create_entity()
	var id_b: int = _db.create_entity()
	_db.set_component(id_a, &"desires", {&"hunger": 500})
	# id_b has no desires component
	_db.add_all(&"desires", &"hunger", 50)
	assert_eq(_db.get_field(id_a, &"desires", &"hunger"), 550, "add_all must update entity A")
	assert_false(_db.has_component(id_b, &"desires"), "Entity B must still have no desires component")


func test_add_all_with_negative_delta():
	var id: int = _db.create_entity()
	_db.set_component(id, &"desires", {&"hunger": 500})
	_db.add_all(&"desires", &"hunger", -100)
	assert_eq(_db.get_field(id, &"desires", &"hunger"), 400, "add_all must support negative delta")


func test_clamp_all_clamps_values_within_range():
	var id_a: int = _db.create_entity()
	var id_b: int = _db.create_entity()
	var id_c: int = _db.create_entity()
	_db.set_component(id_a, &"desires", {&"hunger": 1200})
	_db.set_component(id_b, &"desires", {&"hunger": -50})
	_db.set_component(id_c, &"desires", {&"hunger": 500})
	_db.clamp_all(&"desires", &"hunger", 0, 1000)
	assert_eq(_db.get_field(id_a, &"desires", &"hunger"), 1000, "clamp_all must cap at max")
	assert_eq(_db.get_field(id_b, &"desires", &"hunger"), 0, "clamp_all must floor at min")
	assert_eq(_db.get_field(id_c, &"desires", &"hunger"), 500, "clamp_all must leave in-range values unchanged")


# ── Working set queries ───────────────────────────────────────────────────────

func test_get_entities_with_returns_entities_having_component():
	var id_a: int = _db.create_entity()
	var id_b: int = _db.create_entity()
	var id_c: int = _db.create_entity()
	_db.set_component(id_a, &"desires", {&"hunger": 500})
	_db.set_component(id_b, &"desires", {&"hunger": 300})
	# id_c has no desires
	var result: Array[int] = _db.get_entities_with(&"desires")
	assert_eq(result.size(), 2, "get_entities_with must return only entities with the component")
	assert_true(id_a in result, "Entity A must be in result")
	assert_true(id_b in result, "Entity B must be in result")
	assert_false(id_c in result, "Entity C (no component) must not be in result")


func test_get_entities_with_returns_empty_when_none_match():
	_db.create_entity()
	_db.create_entity()
	var result: Array[int] = _db.get_entities_with(&"desires")
	assert_eq(result.size(), 0, "get_entities_with must return empty array when no entities have component")


func test_get_entities_with_excludes_destroyed_entities():
	var id_a: int = _db.create_entity()
	var id_b: int = _db.create_entity()
	_db.set_component(id_a, &"desires", {&"hunger": 500})
	_db.set_component(id_b, &"desires", {&"hunger": 300})
	_db.destroy_entity(id_a)
	var result: Array[int] = _db.get_entities_with(&"desires")
	assert_eq(result.size(), 1, "Destroyed entities must not appear in get_entities_with")
	assert_true(id_b in result, "Surviving entity must still appear")


# ── Tick ──────────────────────────────────────────────────────────────────────

func test_tick_starts_at_zero():
	assert_eq(_db.get_tick(), 0, "Tick must start at 0")


func test_advance_tick_increments_by_one():
	_db.advance_tick()
	assert_eq(_db.get_tick(), 1, "advance_tick must increment tick by 1")
	_db.advance_tick()
	assert_eq(_db.get_tick(), 2, "advance_tick must continue incrementing")


# ── Watchers ──────────────────────────────────────────────────────────────────

func test_watcher_fires_after_flush_when_component_dirty():
	var id: int = _db.create_entity()
	_db.set_component(id, &"desires", {&"hunger": 500})
	var fired_ids: Array[int] = []
	_db.watch(&"desires", func(entity_id: int) -> void: fired_ids.append(entity_id))
	# set_component marks component dirty; watcher fires on flush
	_db.set_component(id, &"desires", {&"hunger": 600})
	assert_eq(fired_ids.size(), 0, "Watcher must not fire before flush_notifications")
	_db.flush_notifications()
	assert_eq(fired_ids.size(), 1, "Watcher must fire once after flush")
	assert_eq(fired_ids[0], id, "Watcher must receive the correct entity_id")


func test_watcher_fires_after_set_field():
	var id: int = _db.create_entity()
	_db.set_component(id, &"desires", {&"hunger": 500})
	var fired_ids: Array[int] = []
	_db.watch(&"desires", func(entity_id: int) -> void: fired_ids.append(entity_id))
	_db.set_field(id, &"desires", &"hunger", 700)
	_db.flush_notifications()
	assert_eq(fired_ids.size(), 1, "set_field must mark component dirty, triggering watcher on flush")
	assert_eq(fired_ids[0], id, "Watcher must receive the correct entity_id")


func test_watcher_deduplicates_multiple_changes_to_same_entity():
	var id: int = _db.create_entity()
	_db.set_component(id, &"desires", {&"hunger": 500})
	# Use Array to hold count — GDScript closures capture objects by reference, not primitives.
	var fired: Array[int] = [0]
	_db.watch(&"desires", func(_entity_id: int) -> void: fired[0] += 1)
	# Multiple mutations to same entity before flush
	_db.set_field(id, &"desires", &"hunger", 600)
	_db.set_field(id, &"desires", &"hunger", 700)
	_db.set_field(id, &"desires", &"hunger", 800)
	_db.flush_notifications()
	assert_eq(fired[0], 1, "Multiple changes to same entity must only fire watcher once per flush")


func test_watcher_clears_dirty_set_after_flush():
	var id: int = _db.create_entity()
	_db.set_component(id, &"desires", {&"hunger": 500})
	var fired: Array[int] = [0]
	_db.watch(&"desires", func(_entity_id: int) -> void: fired[0] += 1)
	_db.set_field(id, &"desires", &"hunger", 700)
	_db.flush_notifications()
	_db.flush_notifications()  # Second flush without new changes
	assert_eq(fired[0], 1, "Watcher must not fire on second flush without new changes")


func test_multiple_watchers_on_same_component_all_fire():
	var id: int = _db.create_entity()
	_db.set_component(id, &"desires", {&"hunger": 500})
	var count_a: Array[int] = [0]
	var count_b: Array[int] = [0]
	_db.watch(&"desires", func(_entity_id: int) -> void: count_a[0] += 1)
	_db.watch(&"desires", func(_entity_id: int) -> void: count_b[0] += 1)
	_db.set_field(id, &"desires", &"hunger", 700)
	_db.flush_notifications()
	assert_eq(count_a[0], 1, "First watcher must fire")
	assert_eq(count_b[0], 1, "Second watcher must also fire")


func test_watcher_fires_for_each_dirty_entity():
	var id_a: int = _db.create_entity()
	var id_b: int = _db.create_entity()
	_db.set_component(id_a, &"desires", {&"hunger": 500})
	_db.set_component(id_b, &"desires", {&"hunger": 300})
	var fired_ids: Array[int] = []
	_db.watch(&"desires", func(entity_id: int) -> void: fired_ids.append(entity_id))
	_db.set_field(id_a, &"desires", &"hunger", 600)
	_db.set_field(id_b, &"desires", &"hunger", 400)
	_db.flush_notifications()
	assert_eq(fired_ids.size(), 2, "Watcher must fire once per dirty entity")
	assert_true(id_a in fired_ids, "Entity A must trigger watcher")
	assert_true(id_b in fired_ids, "Entity B must trigger watcher")


# ── Spatial queries ───────────────────────────────────────────────────────────

func test_query_radius_finds_entity_at_exact_radius():
	var id: int = _db.create_entity()
	_db.update_spatial(id, 0, 0)
	# Manhattan distance (3, 0) = 3; query radius 3 must include it
	var id_b: int = _db.create_entity()
	_db.update_spatial(id_b, 3, 0)
	var result: Array[int] = _db.query_radius(0, 0, 3)
	assert_true(id in result, "Entity at origin must be found within radius 3")
	assert_true(id_b in result, "Entity at Manhattan distance 3 must be found at radius 3")


func test_query_radius_ignores_entity_beyond_radius():
	var id: int = _db.create_entity()
	_db.update_spatial(id, 0, 0)
	var id_far: int = _db.create_entity()
	_db.update_spatial(id_far, 10, 10)  # Manhattan distance = 20
	var result: Array[int] = _db.query_radius(0, 0, 5)
	assert_true(id in result, "Nearby entity must be found")
	assert_false(id_far in result, "Far entity (Manhattan 20) must not be in radius 5")


func test_query_radius_uses_manhattan_distance():
	# Euclidean distance of (4, 3) = 5, Manhattan = 7
	# With radius 6: Euclidean would include, Manhattan must not
	var id: int = _db.create_entity()
	_db.update_spatial(id, 4, 3)
	var result: Array[int] = _db.query_radius(0, 0, 6)
	assert_false(id in result, "query_radius uses Manhattan distance; (4,3) has Manhattan 7, exceeds radius 6")


func test_remove_spatial_removes_entity_from_queries():
	var id: int = _db.create_entity()
	_db.update_spatial(id, 0, 0)
	_db.remove_spatial(id)
	var result: Array[int] = _db.query_radius(0, 0, 10)
	assert_false(id in result, "remove_spatial must remove entity from spatial queries")


func test_update_spatial_moves_entity():
	var id: int = _db.create_entity()
	_db.update_spatial(id, 0, 0)
	_db.update_spatial(id, 100, 100)  # Move to new position
	var result_origin: Array[int] = _db.query_radius(0, 0, 5)
	var result_new: Array[int] = _db.query_radius(100, 100, 5)
	assert_false(id in result_origin, "Entity must no longer appear at old position")
	assert_true(id in result_new, "Entity must appear at new position")


func test_query_radius_returns_empty_when_no_spatial_entities():
	_db.create_entity()  # Entity with no spatial registration
	var result: Array[int] = _db.query_radius(0, 0, 100)
	assert_eq(result.size(), 0, "Entities without spatial registration must not appear in queries")


func test_query_radius_center_entity_included():
	var id: int = _db.create_entity()
	_db.update_spatial(id, 50, 50)
	var result: Array[int] = _db.query_radius(50, 50, 0)
	assert_true(id in result, "Entity at query center (distance 0) must be included")
