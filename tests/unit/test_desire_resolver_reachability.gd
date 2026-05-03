extends GutTest

# Reachability filter for AI target selection. The architecture rule
# ("navgraph owns reachability, AI's next pass observes zero progress and
# reassigns") relies on the resolver NOT picking targets the entity cannot
# reach. Without this, an animal commits to an unreachable target, the
# move loop reports zero progress every tick, and commitment decay alone
# isn't enough to escape — the next re-evaluation picks the same
# unreachable target again. The visible failure was hungry cats sitting
# on the floor under a slot-8 dispenser forever.
#
# Wiring: DesireResolver gets an optional NavGraphBuilder via
# `set_nav_builder(nav)`. When set, `_evaluate_one` consults
# `nav.can_reach(species, from_pos, target_pos)` and skips unreachable
# candidates before scoring. When unset (existing tests, isolated unit
# work) behavior is unchanged.


var _db: GameStateDB
var _resolver: DesireResolver
var _nav: NavGraphBuilder


func before_each() -> void:
	_db = GameStateDB.new()
	_resolver = DesireResolver.new(_db)
	_nav = NavGraphBuilder.new()
	# The species id used by `_make_cat` matches a real recipe; register it
	# here as floor-bound (no jumps) so the slot-8 server is genuinely
	# unreachable in this navgraph.
	_nav.register_species(
		&"tcp_cats:cat", {&"walks": {}}, {&"size_ru": 1},
	)
	_nav.build()


func _make_cat_at(x: int, y: int, warmth: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"species", {&"id": &"tcp_cats:cat"})
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"desires", {
		&"warmth": warmth, &"comfort": 800, &"curiosity": 1000,
	})
	_db.set_component(id, &"personality", {
		&"warmth_weight": 800,
		&"comfort_weight": 600,
		&"curiosity_weight": 100,
	})
	_db.set_component(id, &"ai_state", {
		&"state": &"IDLE", &"meta_state": &"AMBIENT", &"commitment_score": 0,
	})
	_db.set_component(id, &"target", {
		&"x": Constants.INVALID_ID,
		&"y": Constants.INVALID_ID,
		&"entity_id": Constants.INVALID_ID,
	})
	_db.update_spatial(id, x, y)
	return id


func _make_warm_server_at(x: int, y: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"advertisements", {&"list": [
		{
			&"desire_type": &"warmth",
			&"strength": 900,
			&"radius_px": 10 * Constants.SLOT_HEIGHT_PX,
			&"max_occupants": 1,
		},
	]})
	_db.update_spatial(id, x, y)
	return id


func test_unreachable_warm_server_does_not_pull_cat_into_seeking() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Cat on floor, only ad in range is a warmth ad on a slot-8 server. The
	# floor-bound species (no jumps) cannot reach slot 8 — the navgraph has
	# no edge. Without the reachability filter, the strong warmth deficit
	# pulls the cat into SEEKING toward an unreachable target and the
	# movement layer can never close the gap. With the filter, the cat
	# stays AMBIENT (and `evaluate_budget` may still trigger the
	# wander-elif branch downstream, but the SEEKING transition is what
	# this test pins).
	_resolver.set_nav_builder(_nav)
	var floor_pos: Vector2 = _nav.get_nearest_floor_node(0)
	var cat_id: int = _make_cat_at(
		int(floor_pos.x), int(floor_pos.y), 50,
	)
	var slot_rect: Rect2i = Constants.slot_rect_world(0, 0, 8)
	var server_x: int = slot_rect.position.x + slot_rect.size.x / 2
	var server_y: int = slot_rect.position.y + slot_rect.size.y / 2
	_make_warm_server_at(server_x, server_y)

	_resolver.mark_dirty(cat_id)
	_resolver.evaluate_budget()

	var ai: Dictionary = _db.get_component(cat_id, &"ai_state")
	var target: Dictionary = _db.get_component(cat_id, &"target")
	assert_ne(
		ai[&"state"], &"SEEKING",
		"Cat must not commit to SEEKING when the only ad is unreachable",
	)
	assert_eq(
		target[&"entity_id"], Constants.INVALID_ID,
		"Target entity must remain unset when no reachable candidate exists",
	)


func test_reachable_warm_server_still_pulls_cat_into_seeking() -> void:
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Companion to the above: with a navgraph wired, a warm server placed AT
	# a reachable nav node (the floor itself) must still trigger SEEKING.
	# Otherwise the filter has lobotomized the resolver entirely.
	_resolver.set_nav_builder(_nav)
	var floor_pos: Vector2 = _nav.get_nearest_floor_node(0)
	var cat_id: int = _make_cat_at(
		int(floor_pos.x), int(floor_pos.y), 50,
	)
	# Server at the same floor node — trivially reachable.
	var server_id: int = _make_warm_server_at(
		int(floor_pos.x), int(floor_pos.y),
	)

	_resolver.mark_dirty(cat_id)
	_resolver.evaluate_budget()

	var ai: Dictionary = _db.get_component(cat_id, &"ai_state")
	var target: Dictionary = _db.get_component(cat_id, &"target")
	assert_eq(
		ai[&"state"], &"SEEKING",
		"Cat must commit to SEEKING when a reachable warm server is in range",
	)
	assert_eq(
		target[&"entity_id"], server_id,
		"Target entity must be the reachable server",
	)
