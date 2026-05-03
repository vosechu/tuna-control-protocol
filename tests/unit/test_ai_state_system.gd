extends GutTest

# AI-DEV: Locks in AiStateSystem's recipe-driven min_duration_ticks.
# The system extracts _update_ambient_states from GameServer; these
# tests pin the contract that matters most: state durations come from
# the recipe's ambient_states[pool][i].min_duration_ticks (int ticks),
# not from an engine-side _min_durations dict.

const EventsScript: GDScript = preload("res://nodes/events.gd")

var db: GameStateDB
var events: Object
var hum: HumSystem
var food: FoodSystem
var settled: SettledLifecycle
var nav: NavGraphBuilder
var timers: BehaviorTimers
var system: AiStateSystem


func before_each() -> void:
	db = GameStateDB.new()
	events = EventsScript.new()
	hum = HumSystem.new(db, events)
	food = FoodSystem.new(db, hum, events)
	settled = SettledLifecycle.new(db)
	nav = NavGraphBuilder.new()
	timers = BehaviorTimers.new()
	system = AiStateSystem.new(db, food, events, settled, nav, timers)


# Spawn a minimal AMBIENT entity — well-fed, well-warm, in LOAFING.
# Recipe declares LOAFING with `min_duration_ticks` so the test can
# control how long the entity must stay in state.
func _make_ambient_loafer(loafing_duration: int) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"position", {&"x": 50, &"y": 100})
	db.set_component(id, &"species", {&"id": &"tcp_test:loafer"})
	db.set_component(id, &"desires", {
		&"warmth": 800, &"comfort": 800, &"hunger": 800,
	})
	db.set_component(id, &"ai_state", {
		&"state": &"LOAFING", &"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})
	db.set_component(id, &"ambient_states", {
		"warm": [
			{"state": "LOAFING", "weight": 100, "min_duration_ticks": loafing_duration},
		],
		"cold": [],
	})
	db.set_component(id, &"special_states", {
		&"STARTLED": {&"min_duration_ticks": 10},
	})
	return id


func test_loafing_holds_until_recipe_min_duration_ticks() -> void:
	var id: int = _make_ambient_loafer(150)

	# Tick 149 — entity must still be LOAFING.
	for _i in 149:
		system.tick()

	var state: StringName = db.get_component(id, &"ai_state")[&"state"]
	assert_eq(state, &"LOAFING",
		"entity holds state until recipe min_duration_ticks elapses")


func test_startled_recovers_from_special_states_recipe() -> void:
	# STARTLED duration comes from special_states[STARTLED].min_duration_ticks
	# (recipe), not a hardcoded engine value.
	var id: int = _make_ambient_loafer(150)
	db.set_component(id, &"ai_state", {
		&"state": &"STARTLED", &"meta_state": &"AMBIENT",
		&"commitment_score": 0,
	})

	# Recipe says STARTLED min_duration_ticks=10 — at 9 ticks still STARTLED.
	for _i in 9:
		system.tick()
	var state_at_9: StringName = db.get_component(id, &"ai_state")[&"state"]
	assert_eq(state_at_9, &"STARTLED",
		"STARTLED holds for at least min_duration_ticks-1")

	# At tick 10+ recovers to IDLE.
	for _i in 5:
		system.tick()
	var state_after: StringName = db.get_component(id, &"ai_state")[&"state"]
	assert_eq(state_after, &"IDLE",
		"STARTLED recovers to IDLE after min_duration_ticks")


func test_capability_not_species() -> void:
	# Two entities with identical components but different species labels
	# MUST receive identical treatment. The system reads `ambient_states`
	# / `special_states`, never the species id.
	var a: int = _make_ambient_loafer(50)
	db.set_component(a, &"species", {&"id": &"tcp_cats:cat"})
	var b: int = _make_ambient_loafer(50)
	db.set_component(b, &"species", {&"id": &"tcp_ferrets:ferret"})

	for _i in 49:
		system.tick()

	assert_eq(
		db.get_component(a, &"ai_state")[&"state"],
		db.get_component(b, &"ai_state")[&"state"],
		"same recipe shape → same state regardless of species label",
	)
