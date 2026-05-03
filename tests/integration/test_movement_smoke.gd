extends GutTest

const GAME_SERVER_SCRIPT: GDScript = preload("res://nodes/game_server.gd")


# AI-DEV: This is a quiet-failure regression guard — do not relax the
# threshold. The previous nav implementation oscillated entities by ±2 px
# at the midpoint between two nav nodes (closest_point flipped each
# tick). On screen the animals visibly twitched but appeared to "move,"
# so a softened assertion (e.g. `assert_gt(max_distance, 0)`) would
# silently pass while the bug returned. The `> 4` threshold is exactly
# "more than one ping-pong cycle" — it must stay at 4 or higher.

func test_animals_make_forward_progress_over_30_ticks() -> void:
	var server: Node = GAME_SERVER_SCRIPT.new()
	get_tree().root.add_child(server)
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

	for _t: int in range(30):
		await get_tree().physics_frame

	var max_distance: int = 0
	for id: int in animals:
		var p: Dictionary = server.db.get_component(id, &"position")
		var now := Vector2i(p[&"x"], p[&"y"])
		var d: int = absi(now.x - starts[id].x) + absi(now.y - starts[id].y)
		if d > max_distance:
			max_distance = d

	server.queue_free()

	assert_gt(
		max_distance, 4,
		"At least one animal must move >4 px in 30 ticks (ping-pong regression: %d)" % max_distance,
	)


# AI-DEV: Pixel is force-tucked at boot, so `settled_count >= 1` is
# trivial — that's why the assertion is `> 1`, not `>= 1`. Loosening to
# `>= 1` would silently pass with only Pixel settled, hiding any
# regression in the AI/movement chain. Each of these has been a real
# bug in the same week:
#   - max_height_ru gate too tight → cat can't path to box at slot 2
#   - SETTLING completion never writes settled_in
#   - Resolver re-targets SETTLING cats and resets the 2s timer
#   - Sticky waypoints absent → cat ping-pongs and never arrives
# The 60s window is the loosest deadline that still surfaces all four;
# longer is fine, shorter risks flakiness on slow CI.
func test_starter_cat_other_than_pixel_settles_in_box_within_60s() -> void:
	var server: Node = GAME_SERVER_SCRIPT.new()
	get_tree().root.add_child(server)
	await get_tree().process_frame
	await get_tree().process_frame

	for _t: int in range(600):
		await get_tree().physics_frame

	var settled_count: int = 0
	for id: int in server.db.get_entities_with(&"ai_state"):
		if not server.db.has_component(id, &"species"):
			continue
		if server.db.has_component(id, &"settled_in"):
			settled_count += 1

	server.queue_free()

	assert_gt(
		settled_count, 1,
		"At least 2 cats must be settled_in after 60s (Pixel + ≥1 starter); got %d" % settled_count,
	)
