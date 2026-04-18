extends GutTest

var _db: GameStateDB
var _ws: WiringSystem


func before_each() -> void:
	_db = GameStateDB.new()
	var locks := WiringLockRegistry.new()
	# Max-length probed through handle_connect; the helper reach test covers
	# the euclidean squared distance branch without poking internals.
	_ws = WiringSystem.new(_db, locks, null, {&"cable_max_length_ru": 2})


func test_reach_allows_distance_below_max() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum: int = _make_hum(0, 0)
	var tuna: int = _make_tuna(Constants.ru_to_pu(1), 0)
	assert_true(_ws.handle_connect(1, hum, tuna))


func test_reach_rejects_distance_above_max() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum: int = _make_hum(0, 0)
	var tuna: int = _make_tuna(Constants.ru_to_pu(3), 0)
	assert_false(_ws.handle_connect(1, hum, tuna))


func test_reach_uses_euclidean_not_manhattan() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Max 2 RU → 1600 PU. Point at (1200, 1200) is manhattan 2400 (would reject)
	# but euclidean sqrt(1200^2 * 2) ≈ 1697 (exceeds 1600 → reject).
	var hum: int = _make_hum(0, 0)
	var tuna: int = _make_tuna(1200, 1200)
	assert_false(_ws.handle_connect(1, hum, tuna))
	# Same manhattan but euclidean under: (900, 900) → sqrt(1620000) ≈ 1273 (<1600).
	var tuna_near: int = _make_tuna(900, 900)
	assert_true(_ws.handle_connect(1, hum, tuna_near))


func _make_hum(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"hum", {
		&"reserve": HumSystem.DEFAULT_CAPACITY,
		&"capacity": HumSystem.DEFAULT_CAPACITY,
	})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.update_spatial(id, x, y)
	return id


func _make_tuna(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"tuna_dispenser", {&"hum_cost": 50})
	_db.set_component(id, &"hum_powered", {})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.update_spatial(id, x, y)
	return id
