extends GutTest

# Reachability filter for HUNGRY-target selection. CatFoodStates does the
# nearest-dispenser scan; without a navgraph it only considers manhattan
# distance, which is what every existing test pins. Adding the optional
# `nav` parameter makes a hungry cat skip dispensers whose nav-graph
# `can_reach` is false — closing the failure mode where a slot-8 dispenser
# pulled cats into HUNGRY/MOVING_TO and they sat under it forever.

var db: GameStateDB
var nav: NavGraphBuilder


func before_each() -> void:
	db = GameStateDB.new()
	nav = NavGraphBuilder.new()
	# Floor-bound species: walks but doesn't jump. Slot dispensers are
	# unreachable without `add_rack_slot` registering edges, even before
	# the no-jump constraint matters.
	nav.register_species(
		&"tcp_cats:cat", {&"walks": {}}, {&"size_ru": 1},
	)
	nav.build()


func _make_cat_on_floor() -> int:
	var id: int = db.create_entity()
	var floor_pos: Vector2 = nav.get_nearest_floor_node(0)
	db.set_component(id, &"species", {&"id": &"tcp_cats:cat"})
	db.set_component(id, &"position", {
		&"x": int(floor_pos.x), &"y": int(floor_pos.y),
	})
	db.update_spatial(id, int(floor_pos.x), int(floor_pos.y))
	return id


func _make_dispenser_at(rack: int, slot: int) -> int:
	var id: int = db.create_entity()
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var x: int = slot_rect.position.x + slot_rect.size.x / 2
	var y: int = slot_rect.position.y + slot_rect.size.y / 2
	db.set_component(id, &"position", {&"x": x, &"y": y})
	db.set_component(id, &"tuna_dispenser", {
		&"hum_cost": 50, &"can_type": &"tcp_tuna:tuna_can",
	})
	db.update_spatial(id, x, y)
	return id


func test_unreachable_dispenser_returns_invalid_with_nav() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Cat on floor, only dispenser is at slot 8 with no nav-graph edge.
	# Without nav: legacy linear scan returns the dispenser id.
	# With nav: filter rejects it, INVALID_ID returned, caller stays in
	# the AMBIENT/PACING fallback branch.
	var cat: int = _make_cat_on_floor()
	db.set_field(cat, &"position", &"x", db.get_field(cat, &"position", &"x"))
	# Set a hungry cat (irrelevant to the helper, included for realism).
	db.set_component(cat, &"desires", {
		&"hunger": 200, &"warmth": 700, &"comfort": 700, &"curiosity": 500,
	})
	var disp: int = _make_dispenser_at(0, 8)

	# Sanity: legacy call (no nav) returns the dispenser as before.
	assert_eq(
		CatFoodStates.find_nearest_dispenser(db, cat), disp,
		"Without a navgraph the legacy linear scan still returns the dispenser",
	)

	# With nav wired: filter rejects unreachable dispenser.
	assert_eq(
		CatFoodStates.find_nearest_dispenser(db, cat, nav),
		Constants.INVALID_ID,
		"With navgraph wired, unreachable dispenser must be filtered out",
	)


func test_reachable_dispenser_still_picked_with_nav() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Companion to the above: a dispenser placed at the floor node is
	# trivially reachable, so the filter must not lobotomize the helper
	# entirely. Without this guard, a "filter everything" bug in the
	# can_reach call site would silently break HUNGRY for every species.
	var cat: int = _make_cat_on_floor()
	var floor_pos: Vector2 = nav.get_nearest_floor_node(0)
	# Reachable dispenser: placed at the floor node itself.
	var disp: int = db.create_entity()
	db.set_component(disp, &"position", {
		&"x": int(floor_pos.x), &"y": int(floor_pos.y),
	})
	db.set_component(disp, &"tuna_dispenser", {
		&"hum_cost": 50, &"can_type": &"tcp_tuna:tuna_can",
	})
	db.update_spatial(disp, int(floor_pos.x), int(floor_pos.y))

	assert_eq(
		CatFoodStates.find_nearest_dispenser(db, cat, nav), disp,
		"Reachable dispenser must still be returned when navgraph is wired",
	)
