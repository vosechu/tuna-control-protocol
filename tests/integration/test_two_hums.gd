extends GutTest

var _db: GameStateDB
var _sys: HumSystem


func before_each() -> void:
	_db = GameStateDB.new()
	_sys = HumSystem.new(_db)


func test_purr_near_hum_a_does_not_charge_hum_b() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	# Disk-vs-rect: cat at A's position with small radius reaches A's body
	# rect but not B's, which sits hundreds of pixels away.
	var a: int = _make_hum(0, 0)
	var b: int = _make_hum(50 * Constants.SLOT_HEIGHT_PX, 0)  # far outside any radius
	_sys.drain_action(a, 5000)
	_sys.drain_action(b, 5000)
	_make_purr_emitter(0, 0, 10, 16)  # 16px radius — only reaches A
	_sys.tick_charge()
	assert_eq(_sys.get_reserve(a), 5010, "HUM A charged by 10")
	assert_eq(_sys.get_reserve(b), 5000, "HUM B unchanged")


func test_disk_intersecting_two_hums_charges_both() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the code.
	# Inversion model: every receiver whose body rect intersects a cat's
	# emission disk gets charged. Co-located HUMs each receive intensity.
	var a: int = _make_hum(0, 0)
	var b: int = _make_hum(0, 0)  # identical position
	_sys.drain_action(a, 5000)
	_sys.drain_action(b, 5000)
	_make_purr_emitter(0, 0, 7, 16)
	_sys.tick_charge()
	assert_eq(_sys.get_reserve(a), 5007, "HUM A charged")
	assert_eq(_sys.get_reserve(b), 5007, "HUM B charged independently")


func _make_hum(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"hum", {&"reserve": 10000, &"capacity": 10000})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"hum_receiver", {})
	_db.set_component(id, &"physical", {&"mass": 20000, &"size_ru": 1})
	return id


func _make_purr_emitter(x: int, y: int, intensity: int, radius_px: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"purr", {&"intensity": intensity, &"radius_px": radius_px})
	return id
