extends GutTest

# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
# Smoke test for the ping-pong fix: spawn the starter scenario, run 30 ticks,
# assert that at least one animal moved more than 4 px (twice the per-tick
# step) over the run. Without the fix, animals oscillated 2 px and never
# made forward progress, so this would fail.

func test_animals_make_forward_progress_over_30_ticks() -> void:
	var server_script = preload("res://nodes/game_server.gd")
	var server: Node = server_script.new()
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
