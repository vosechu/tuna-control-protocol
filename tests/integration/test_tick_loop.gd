extends GutTest

# AI-DEV: AI **MUST NOT** modify this constant. It must match
# game_server.gd:_physics_process step numbers 1-17.
const EXPECTED_ORDER: Array[String] = [
	"db.advance_tick",
	"heat_grid.propagate",
	"_scatter_desires",
	"contentment.evaluate_all",
	"contentment_purr_bridge.tick",
	"hum_system.tick_charge",
	"hum_system.tick_idle_drain",
	"_decay_commitment",
	"desire_resolver.mark_all_dirty",
	"desire_resolver.evaluate_budget",
	"movement_system.tick",
	"food_system.tick_arms",
	"food_system.tick_cleanup",
	"reclamation_system.tick",
	"plant_growth_system.tick",
	"ai_state_system.tick",
	"db.flush_notifications",
]

var _db: GameStateDB
var _heat_grid: HeatGrid
var _resolver: DesireResolver


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	_db = GameStateDB.new()
	_heat_grid = HeatGrid.new(_db)
	_resolver = DesireResolver.new(_db)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_animal(x: int, y: int, warmth_weight: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {
		&"id": &"tcp_cats:cat", &"variant": &"cat01", &"name": &"Test",
	})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"desires", {&"warmth": 200, &"comfort": 800, &"curiosity": 1000})
	_db.set_component(id, &"personality", {
		&"warmth_weight": warmth_weight, &"comfort_weight": 600, &"curiosity_weight": 100,
	})
	_db.set_component(id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	_db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID, &"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	_db.update_spatial(id, x, y)
	return id


func _make_ad_object(x: int, y: int, desire_type: StringName, strength: int, radius_px: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"advertisements", {&"list": [
		{&"desire_type": desire_type, &"strength": strength, &"radius_px": radius_px, &"max_occupants": 1}
	]})
	_db.update_spatial(id, x, y)
	return id


# NOTE: Reimplements commitment decay from game_server._decay_commitment
# because GameServer requires a scene tree we cannot instantiate in
# integration tests. If _decay_commitment changes, this must be updated.
func _decay_commitment_once(entity_id: int) -> void:
	var ai: Dictionary = _db.get_component(entity_id, &"ai_state")
	var commitment: int = ai[&"commitment_score"]
	if commitment > 0:
		_db.set_component(entity_id, &"ai_state", {
			&"state": ai[&"state"],
			&"meta_state": ai[&"meta_state"],
			&"commitment_score": maxi(0, commitment - 1),
		})


# ── Tick order contract ──────────────────────────────────────────────────────

func test_tick_order_matches_game_server():
	# AI-DEV: AI **MUST NOT** touch this test. If the test is failing,
	# it is because you changed the tick order in game_server.gd.
	var source: String = FileAccess.get_file_as_string(
		"res://nodes/game_server.gd"
	)
	# Extract the _physics_process body by finding the numbered steps
	var lines: PackedStringArray = source.split("\n")
	var in_physics: bool = false
	var step_calls: Array[String] = []
	for line: String in lines:
		if "func _physics_process" in line:
			in_physics = true
			continue
		if in_physics:
			if line.begins_with("func "):
				break
			var stripped: String = line.strip_edges()
			if stripped.is_empty() or stripped.begins_with("#"):
				continue
			# Extract the call name before the (
			var paren: int = stripped.find("(")
			if paren > 0:
				step_calls.append(stripped.substr(0, paren))
	assert_eq(step_calls.size(), EXPECTED_ORDER.size(),
		"Tick step count mismatch: got %d, expected %d" % [
			step_calls.size(), EXPECTED_ORDER.size(),
		])
	for i: int in mini(step_calls.size(), EXPECTED_ORDER.size()):
		assert_eq(step_calls[i], EXPECTED_ORDER[i],
			"Tick step %d: got '%s', expected '%s'" % [
				i + 1, step_calls[i], EXPECTED_ORDER[i],
			])


# ── Tests ─────────────────────────────────────────────────────────────────────

func test_commitment_decays_over_ticks() -> void:
	var cat: int = _make_animal(0, 0, 800)
	# Set high commitment as if cat just chose a target
	_db.set_component(cat, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 200,
	})
	# Decay 50 ticks
	for _tick: int in 50:
		_decay_commitment_once(cat)
	var ai: Dictionary = _db.get_component(cat, &"ai_state")
	assert_eq(ai[&"commitment_score"], 150, "Should decay by 1/tick: 200 - 50 = 150")


func test_commitment_prevents_premature_transition() -> void:
	var cat: int = _make_animal(0, 0, 800)
	# Cat has high commitment from previous choice
	_db.set_component(cat, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 300,
	})
	# Weak ad nearby — score will be less than 300 + 150 = 450
	_make_ad_object(24, 0, &"warmth", 400, 64)

	_resolver.mark_dirty(cat)
	_resolver.evaluate_budget()

	var ai: Dictionary = _db.get_component(cat, &"ai_state")
	assert_eq(ai[&"state"], &"IDLE",
		"Cat should NOT transition — ad score too low vs commitment + threshold")


func test_commitment_eventually_allows_transition() -> void:
	var cat: int = _make_animal(0, 0, 800)
	_make_ad_object(24, 0, &"warmth", 800, 64)
	# Cat has moderate commitment that will decay
	_db.set_component(cat, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 200,
	})

	# Decay commitment over many ticks until resolver can transition
	var transitioned: bool = false
	for _tick: int in 300:
		_decay_commitment_once(cat)
		_resolver.mark_dirty(cat)
		_resolver.evaluate_budget()
		var ai: Dictionary = _db.get_component(cat, &"ai_state")
		if ai[&"state"] == &"SEEKING":
			transitioned = true
			break

	assert_true(transitioned,
		"Cat should eventually transition once commitment decays enough")


func test_commitment_floors_at_zero() -> void:
	var cat: int = _make_animal(0, 0, 800)
	_db.set_component(cat, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 5,
	})
	for _tick: int in 20:
		_decay_commitment_once(cat)
	var ai: Dictionary = _db.get_component(cat, &"ai_state")
	assert_eq(ai[&"commitment_score"], 0, "Commitment should not go below 0")
