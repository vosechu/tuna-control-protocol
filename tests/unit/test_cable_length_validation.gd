extends GutTest

var _db: GameStateDB
var _ws: WiringSystem


func before_each() -> void:
	_db = GameStateDB.new()
	var locks := WiringLockRegistry.new()
	# Max-length probed through handle_connect; the helper reach test covers
	# the euclidean squared distance branch without poking internals.
	# Cap: 2 slot-heights = 16 pixels.
	_ws = WiringSystem.new(_db, locks, null, {&"cable_max_length_px": 16})


func test_reach_uses_euclidean_distance_with_max_cap() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# AI-DEV: Covers accept-under-max, reject-over-max, AND euclidean-not-manhattan
	# in one test — they all exercise the same single line in `_within_range`
	# (`(dx*dx + dy*dy) <= (max_px * max_px)`) and any mutation that breaks one
	# inevitably breaks the others. Testing separately was redundant and blocked
	# surgical mutation targeting.
	var hum: int = _make_hum(0, 0)
	# Under max: distance 8px (<16) → accept.
	var tuna_near_x: int = _make_tuna(Constants.SLOT_HEIGHT_PX, 0)
	assert_true(_ws.handle_connect(1, hum, tuna_near_x),
		"8px distance should connect (below 16px max)")
	# Over max: distance 24px (>16) → reject.
	var tuna_far_x: int = _make_tuna(3 * Constants.SLOT_HEIGHT_PX, 0)
	assert_false(_ws.handle_connect(1, hum, tuna_far_x),
		"24px distance should reject (above 16px max)")
	# Manhattan 24 (|12|+|12|) but Euclidean sqrt(288)≈17 → reject via euclidean.
	var tuna_diag_far: int = _make_tuna(12, 12)
	assert_false(_ws.handle_connect(1, hum, tuna_diag_far),
		"(12,12) should reject — euclidean sqrt(288)>16, not manhattan 24")
	# Manhattan 18 but Euclidean sqrt(162)≈12.7 → accept via euclidean.
	var tuna_diag_near: int = _make_tuna(9, 9)
	assert_true(_ws.handle_connect(1, hum, tuna_diag_near),
		"(9,9) should accept — euclidean sqrt(162)<16, proves not manhattan")


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
