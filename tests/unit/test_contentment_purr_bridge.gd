extends GutTest

var _db: GameStateDB
var _b: ContentmentPurrBridge


func before_each() -> void:
	_db = GameStateDB.new()
	_b = ContentmentPurrBridge.new(_db)


func test_satisfied_entity_writes_recipe_rate() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	var id: int = _db.create_entity()
	_db.set_component(id, &"contentment", {&"is_satisfied": 1})
	_db.set_component(id, &"purr", {&"intensity": 0})
	_db.set_component(id, &"purr_config", {&"rate_when_satisfied": 10})
	_b.tick()
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 10)


func test_unsatisfied_entity_writes_zero() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	var id: int = _db.create_entity()
	_db.set_component(id, &"contentment", {&"is_satisfied": 0})
	_db.set_component(id, &"purr", {&"intensity": 50})  # prior value
	_db.set_component(id, &"purr_config", {&"rate_when_satisfied": 10})
	_b.tick()
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 0,
		"Unsatisfied entity has intensity reset to 0")


func test_entity_without_contentment_is_untouched() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	var id: int = _db.create_entity()
	_db.set_component(id, &"purr", {&"intensity": 99})
	_db.set_component(id, &"purr_config", {&"rate_when_satisfied": 10})
	_b.tick()
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 99,
		"Non-contentment-bearing purr emitter keeps its intensity")


func test_entity_without_purr_is_untouched() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	var id: int = _db.create_entity()
	_db.set_component(id, &"contentment", {&"is_satisfied": 1})
	_b.tick()
	assert_false(_db.has_component(id, &"purr"))


func test_bridge_does_not_read_species() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	var id: int = _db.create_entity()
	_db.set_component(id, &"contentment", {&"is_satisfied": 1})
	_db.set_component(id, &"purr", {&"intensity": 0})
	_db.set_component(id, &"purr_config", {&"rate_when_satisfied": 7})
	_b.tick()
	assert_eq(_db.get_field(id, &"purr", &"intensity"), 7)
