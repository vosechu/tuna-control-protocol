extends GutTest

# AI-DEV: Locks in FoodSystem's public food-finder surface. Promoted from
# GameServer private helpers so AiStateSystem (next task) can extract
# without holding a GameServer reference. Empty-world cases here; the
# happy paths already exist in test_food_loop.gd.

const EventsScript: GDScript = preload("res://nodes/events.gd")

var db: GameStateDB
var events: Object
var hum: HumSystem
var food: FoodSystem


func before_each() -> void:
	db = GameStateDB.new()
	events = EventsScript.new()
	hum = HumSystem.new(db, events)
	food = FoodSystem.new(db, hum, events)


func test_find_nearby_food_returns_invalid_when_no_food() -> void:
	var entity_id: int = db.create_entity()
	db.set_component(entity_id, &"position", {&"x": 100, &"y": 100})

	assert_eq(food.find_nearby_food(entity_id), GameStateDB.INVALID_ID,
		"no food in world returns INVALID_ID")


func test_find_nearest_box_returns_invalid_when_no_boxes() -> void:
	var entity_id: int = db.create_entity()
	db.set_component(entity_id, &"position", {&"x": 100, &"y": 100})

	assert_eq(food.find_nearest_box(entity_id), GameStateDB.INVALID_ID,
		"no boxes in world returns INVALID_ID")


func test_find_nearby_food_skips_sealed_cans() -> void:
	# `find_nearby_food` returns only `opened` cans. A sealed can (waiting
	# for the arm) must not be picked, otherwise hungry cats race the arm
	# and stand staring at sealed cans they can't eat.
	var cat: int = db.create_entity()
	db.set_component(cat, &"position", {&"x": 100, &"y": 100})
	var can: int = db.create_entity()
	db.set_component(can, &"position", {&"x": 100, &"y": 100})
	db.set_component(can, &"tuna_can", {&"state": &"sealed", &"despawn_timer": 0})
	db.update_spatial(can, 100, 100)

	assert_eq(food.find_nearby_food(cat), GameStateDB.INVALID_ID,
		"sealed cans must not be picked as food")


func test_mark_nearest_can_eaten_is_noop_when_no_food() -> void:
	# Locks in graceful degradation. EATING-state cleanup sometimes runs
	# after every nearby can has already despawned (e.g. another cat ate
	# faster). The helper must silently return rather than asserting.
	var cat: int = db.create_entity()
	db.set_component(cat, &"position", {&"x": 100, &"y": 100})

	food.mark_nearest_can_eaten(cat)
	# Reaching this line means the call did not crash.
	pass_test("mark_nearest_can_eaten with no food in range did not crash")
