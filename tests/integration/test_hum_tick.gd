extends GutTest

# Integration test: verifies contentment + HUM system wired into the tick loop.
# Mirrors game_server._physics_process order without requiring a scene tree.
# Uses ContentmentPurrBridge (option b) so purr.intensity is set realistically.

const EventsScript: GDScript = preload("res://nodes/events.gd")

var _db: GameStateDB
var _heat_grid: HeatGrid
var _contentment: Contentment
var _bridge: ContentmentPurrBridge
var _hum: HumSystem
var _events: Object
var _resolver: DesireResolver
var _desire_scatter: DesireScatter


func before_each() -> void:
	_db = GameStateDB.new()
	_events = EventsScript.new()
	_heat_grid = HeatGrid.new(_db)
	_contentment = Contentment.new(_db)
	_bridge = ContentmentPurrBridge.new(_db)
	_hum = HumSystem.new(_db, _events)
	_resolver = DesireResolver.new(_db)
	_desire_scatter = DesireScatter.new(_db)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_cat(x: int, y: int, desires: Dictionary) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {
		&"id": &"tcp_cats:cat", &"variant": &"cat01", &"name": &"Test",
	})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"desires", desires)
	_db.set_component(id, &"personality", {
		&"warmth_weight": 800, &"comfort_weight": 600, &"curiosity_weight": 100,
	})
	_db.set_component(id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	_db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	# Purr components so ContentmentPurrBridge can set intensity + radius_px
	_db.set_component(id, &"purr", {&"intensity": 0, &"radius_px": 0})
	_db.set_component(id, &"purr_config", {
		&"rate_when_satisfied": Constants.UNIT, &"base_radius_ru": 6,
	})
	_db.update_spatial(id, x, y)
	return id


func _make_server_with_receiver(rack: int, slot: int, size_ru: int) -> int:
	var id: int = _db.create_entity()
	var x: int = rack * Constants.RACK_WIDTH_PX
	var y: int = slot * Constants.SLOT_HEIGHT_PX
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"heat_source", {
		&"value": 1000, &"radius_px": 5 * Constants.SLOT_HEIGHT_PX,
	})
	_db.set_component(id, &"hum_receiver", {})
	_db.set_component(id, &"physical", {&"mass": 20000, &"size_ru": size_ru})
	_db.update_spatial(id, x, y)
	return id


func _make_hum_device(rack: int, slot: int, size_ru: int) -> int:
	var id: int = _db.create_entity()
	var x: int = rack * Constants.RACK_WIDTH_PX
	var y: int = slot * Constants.SLOT_HEIGHT_PX
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"hum", {
		&"reserve": HumSystem.DEFAULT_CAPACITY,
		&"capacity": HumSystem.DEFAULT_CAPACITY,
	})
	_db.set_component(id, &"hum_receiver", {})
	_db.set_component(id, &"physical", {&"mass": 20000, &"size_ru": size_ru})
	_db.update_spatial(id, x, y)
	return id


func _run_tick() -> void:
	_db.advance_tick()
	_heat_grid.propagate()
	# Desire scatter (simplified — just clamp, no decay for test clarity)
	_db.clamp_all(&"desires", &"warmth", 0, 1000)
	_db.clamp_all(&"desires", &"comfort", 0, 1000)
	_db.clamp_all(&"desires", &"hunger", 0, 1000)
	_db.clamp_all(&"desires", &"attention", 0, 1000)
	_contentment.evaluate_all()
	_bridge.tick()
	_hum.tick_charge()
	_hum.tick_idle_drain()
	_db.flush_notifications()


# ── Tests ─────────────────────────────────────────────────────────────────────

func test_tick_creates_contentment_component_on_animals() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var cat: int = _make_cat(0, 0, {
		&"warmth": 800, &"comfort": 800, &"hunger": 800, &"attention": 800,
	})
	_run_tick()
	assert_true(
		_db.has_component(cat, &"contentment"),
		"Cat should have contentment component after tick"
	)


func test_contented_cat_near_hum_device_charges_hum() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum_device(0, 5, 5)
	_make_cat(
		0, 5 * Constants.SLOT_HEIGHT_PX,
		{&"warmth": 800, &"comfort": 800, &"hunger": 800, &"attention": 800},
	)
	# Drain reserve to a known value so we can measure charge
	_db.set_field(hum_id, &"hum", &"reserve", 500)
	_run_tick()
	# After tick: contentment sets is_satisfied=1, bridge sets purr.intensity>0,
	# tick_charge finds emitter near hum device, charges.
	# tick_idle_drain also runs, but charge should exceed idle drain.
	assert_gt(_hum.get_reserve(hum_id), 500,
		"Contented cat near hum device should net-charge the HUM")


func test_discontented_cat_does_not_charge_hum() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	var hum_id: int = _make_hum_device(0, 5, 5)
	# Cat with LOW desires — not contented, should not purr
	_make_cat(
		0, 5 * Constants.SLOT_HEIGHT_PX,
		{&"warmth": 100, &"comfort": 100, &"hunger": 100, &"attention": 100},
	)
	_db.set_field(hum_id, &"hum", &"reserve", 500)
	_run_tick()
	# No purring (intensity=0), only idle drain — reserve should decrease
	assert_lt(_hum.get_reserve(hum_id), 500,
		"Discontented cat should not charge HUM; reserve should drain")


func test_100_ticks_with_hum_no_crash() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	_make_hum_device(1, 8, 5)
	_make_cat(
		Constants.RACK_WIDTH_PX, 8 * Constants.SLOT_HEIGHT_PX,
		{&"warmth": 600, &"comfort": 700, &"hunger": 500, &"attention": 600},
	)
	for _tick: int in 100:
		_run_tick()
	assert_true(true, "100 ticks with HUM system should run without crashing")


func test_hum_reserve_stays_non_negative_over_time() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# No receivers, no purring cats — pure drain
	var hum_id: int = _make_hum_device(0, 0, 1)
	_make_cat(0, 0, {
		&"warmth": 100, &"comfort": 100, &"hunger": 100, &"attention": 100,
	})
	_db.set_field(hum_id, &"hum", &"reserve", 50)
	for _tick: int in 200:
		_run_tick()
	assert_gte(_hum.get_reserve(hum_id), 0,
		"HUM reserve must never go negative even after prolonged drain")
