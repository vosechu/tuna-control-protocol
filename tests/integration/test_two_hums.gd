extends GutTest

var _db: GameStateDB
var _sys: HumSystem


func before_each() -> void:
	_db = GameStateDB.new()
	_sys = HumSystem.new(_db)


func test_purr_near_hum_a_does_not_charge_hum_b() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	var a: int = _make_hum(0, 0)
	var b: int = _make_hum((50 * Constants.SLOT_HEIGHT_PX), 0)  # far outside any radius
	_sys.drain_action(a, 5000)
	_sys.drain_action(b, 5000)
	_make_purr_emitter(0, 0, 10)  # near A
	_sys.tick_charge()
	assert_eq(_sys.get_reserve(a), 5010, "HUM A charged by 10")
	assert_eq(_sys.get_reserve(b), 5000, "HUM B unchanged")


func test_nearest_receiver_tie_break_by_lower_id() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	var a: int = _make_hum(0, 0)
	var b: int = _make_hum(0, 0)  # identical position
	_sys.drain_action(a, 5000)
	_sys.drain_action(b, 5000)
	_make_purr_emitter(0, 0, 7)
	_sys.tick_charge()
	assert_eq(_sys.get_reserve(a), 5007, "Lower id wins tie")
	assert_eq(_sys.get_reserve(b), 5000)


func _make_hum(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"hum", {&"reserve": 10000, &"capacity": 10000})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"hum_receiver", {&"radius_px": 10})
	return id


func _make_purr_emitter(x: int, y: int, intensity: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"purr", {&"intensity": intensity})
	return id
