extends GutTest

const GAME_SERVER_SCRIPT: GDScript = preload("res://nodes/game_server.gd")


# AI-DEV: This is a quiet-failure regression guard — do not relax the
# threshold. The previous nav implementation oscillated entities by ±2 px
# at the midpoint between two nav nodes (closest_point flipped each
# tick). On screen the animals visibly twitched but appeared to "move,"
# so a softened assertion (e.g. `assert_gt(max_distance, 0)`) would
# silently pass while the bug returned. The `> 4` threshold is exactly
# "more than one ping-pong cycle" — it must stay at 4 or higher.
#
# AI-DEV: Pixel is force-tucked at boot, so `settled_count >= 1` is
# trivial — that's why the assertion is `> 1`, not `>= 1`. Loosening to
# `>= 1` would silently pass with only Pixel settled, hiding any
# regression in the AI/movement chain. Each of these has been a real
# bug in the same week:
#   - max_height_ru gate too tight → cat can't path to box at slot 2
#   - SETTLING completion never writes settled_in
#   - Resolver re-targets SETTLING cats and resets the 2s timer
#   - Sticky waypoints absent → cat ping-pongs and never arrives
# The 600-tick window (60s simulated) is the loosest deadline that still
# surfaces all four; longer is fine, shorter risks flakiness.

func test_starter_animals_move_then_settle_within_60s_simulated() -> void:
	# Combined smoke: forward-progress over the first 30 ticks AND the
	# settle-within-600 window. Same boot, same scene instance, two
	# assertions — drives the simulation directly via _physics_process
	# instead of waiting on real wall-clock physics frames. Was 60+
	# real seconds; now milliseconds.
	var server: Node = GAME_SERVER_SCRIPT.new()
	get_tree().root.add_child(server)
	# Let _ready, mod loading, and starter spawning settle. The bulk
	# work below uses direct _physics_process calls so the full test
	# runs in milliseconds instead of awaiting 600 real wall-clock
	# physics frames at 10 Hz (which would be ~60 real seconds).
	await get_tree().process_frame
	await get_tree().process_frame

	var animals: Array[int] = []
	for id: int in server.db.get_entities_with(&"ai_state"):
		if server.db.has_component(id, &"species"):
			animals.append(id)

	var starts: Dictionary = {}
	for id: int in animals:
		var p: Dictionary = server.db.get_component(id, &"position")
		starts[id] = Vector2i(p[&"x"], p[&"y"])

	# First 30 ticks — at least one animal must move >4 px.
	for _t: int in 30:
		server._physics_process(0.1)

	var max_distance: int = 0
	for id: int in animals:
		var p: Dictionary = server.db.get_component(id, &"position")
		var now := Vector2i(p[&"x"], p[&"y"])
		var d: int = absi(now.x - starts[id].x) + absi(now.y - starts[id].y)
		if d > max_distance:
			max_distance = d
	assert_gt(
		max_distance, 4,
		"At least one animal must move >4 px in 30 ticks (ping-pong regression: %d)" % max_distance,
	)

	# Continue to tick 600 — at least one non-Pixel cat must settle in a box.
	for _t: int in 570:
		server._physics_process(0.1)

	var settled_count: int = 0
	for id: int in server.db.get_entities_with(&"ai_state"):
		if not server.db.has_component(id, &"species"):
			continue
		if server.db.has_component(id, &"settled_in"):
			settled_count += 1

	server.queue_free()

	assert_gt(
		settled_count, 1,
		"At least 2 cats must be settled_in after 600 ticks (Pixel + ≥1 starter); got %d" % settled_count,
	)
