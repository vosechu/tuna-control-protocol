extends GutTest

# AI-DEV: Locks in MovementSystem's recipe-driven walk speed. The system
# extracts _move_animals from GameServer; this test pins the contract that
# matters most for the extraction: speed comes from the entity's recipe
# (body_capabilities.walks.speed_px_per_tick), not from an engine constant.

const EventsScript: GDScript = preload("res://nodes/events.gd")

var db: GameStateDB
var nav: NavGraphBuilder
var osm: ObjectStateManager
var events: Object
var hum: HumSystem
var food: FoodSystem
var timers: BehaviorTimers
var system: MovementSystem


func before_each() -> void:
	db = GameStateDB.new()
	events = EventsScript.new()
	hum = HumSystem.new(db, events)
	food = FoodSystem.new(db, hum, events)
	nav = NavGraphBuilder.new()
	osm = ObjectStateManager.new(db)
	timers = BehaviorTimers.new()
	system = MovementSystem.new(db, nav, osm, events, timers, food)


# WANDERING bypasses the navgraph (random floor positions are always
# reachable, no graph query needed) so the test exercises only the
# speed-driven step. MOVING_TO/SEEKING would require registering the
# species with NavGraphBuilder, which is integration territory.
func _make_walker(speed: int, x: int, y: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"position", {&"x": x, &"y": y})
	db.set_component(id, &"body_capabilities", {
		&"walks": {&"speed_px_per_tick": speed},
	})
	db.set_component(id, &"species", {&"id": &"tcp_test:walker"})
	db.set_component(id, &"ai_state", {
		&"state": &"WANDERING", &"meta_state": &"GOAL_DIRECTED",
		&"commitment_score": 200,
	})
	db.set_component(id, &"target", {
		&"x": x + 100, &"y": y, &"entity_id": Constants.INVALID_ID,
	})
	db.update_spatial(id, x, y)
	return id


func test_wandering_entity_advances_by_recipe_speed() -> void:
	var id: int = _make_walker(3, 0, 100)

	system.tick()

	assert_eq(db.get_field(id, &"position", &"x"), 3,
		"WANDERING entity advances by speed_px_per_tick from recipe")


func test_idle_entity_does_not_move() -> void:
	var id: int = _make_walker(2, 0, 100)
	db.set_component(id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})

	system.tick()

	assert_eq(db.get_field(id, &"position", &"x"), 0,
		"IDLE entity must not move")


func test_different_entities_use_different_speeds() -> void:
	# Capability not species: same code path reads each entity's recipe.
	var slow: int = _make_walker(1, 0, 100)
	var fast: int = _make_walker(4, 0, 200)

	system.tick()

	assert_eq(db.get_field(slow, &"position", &"x"), 1)
	assert_eq(db.get_field(fast, &"position", &"x"), 4,
		"speed read from each entity's body_capabilities, not a constant")
