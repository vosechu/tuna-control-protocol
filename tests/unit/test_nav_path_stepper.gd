extends GutTest

# AI-DEV: These tests exercise the pure path-stepping math used by
# `_move_animals` in nodes/game_server.gd. Each test pins down a distinct
# branch; mutation verified via script/tdd_verify.


func test_snaps_to_waypoint_when_within_speed():
	# Manhattan dist 150 <= speed 200 → snap onto waypoint, arrived=true.
	var result: Dictionary = NavPathStepper.step(
		Vector2i(0, 0), Vector2i(100, 50), 200,
	)
	assert_eq(result[&"pos"], Vector2i(100, 50),
		"Must snap onto waypoint when reachable in one step")
	assert_true(result[&"arrived"],
		"arrived=true when snapping onto the waypoint")


func test_formula_splits_budget_proportionally():
	# dx=200, dy=400 (asymmetric so mx ≠ my). Manhattan=600, speed=200.
	# mx=200*200/600=66, my=200*400/600=133. No truncation guard needed.
	var result: Dictionary = NavPathStepper.step(
		Vector2i(0, 0), Vector2i(200, 400), 200,
	)
	assert_eq(result[&"pos"], Vector2i(66, 133),
		"Budget must split proportionally across X and Y by the formula")
	assert_false(result[&"arrived"],
		"arrived=false when waypoint is still beyond one step")


func test_x_guard_bumps_positive_dx_to_one():
	# dx=1, dy=999, speed=200. Raw mx = 200*1/1000 = 0 → guard bumps to +1.
	# This test pins the positive branch of the x-truncation guard.
	var result: Dictionary = NavPathStepper.step(
		Vector2i(0, 0), Vector2i(1, 999), 200,
	)
	assert_eq(result[&"pos"].x, 1,
		"X must advance by +1 when formula truncates a positive dx to zero")


func test_x_guard_bumps_negative_dx_to_minus_one():
	# dx=-1, dy=999, speed=200. Raw mx = 200*(-1)/1000 = 0 → guard bumps to -1.
	# This test pins the negative branch of the x-truncation guard.
	var result: Dictionary = NavPathStepper.step(
		Vector2i(1, 0), Vector2i(0, 999), 200,
	)
	assert_eq(result[&"pos"].x, 0,
		"X must advance by -1 when formula truncates a negative dx to zero")


func test_y_guard_bumps_positive_dy_to_one():
	# dx=999, dy=1, speed=200. Raw my = 200*1/1000 = 0 → guard bumps to +1.
	var result: Dictionary = NavPathStepper.step(
		Vector2i(0, 0), Vector2i(999, 1), 200,
	)
	assert_eq(result[&"pos"].y, 1,
		"Y must advance by +1 when formula truncates a positive dy to zero")


func test_y_guard_bumps_negative_dy_to_minus_one():
	# dx=999, dy=-1, speed=200. Raw my = 200*(-1)/1000 = 0 → guard bumps to -1.
	var result: Dictionary = NavPathStepper.step(
		Vector2i(0, 1), Vector2i(999, 0), 200,
	)
	assert_eq(result[&"pos"].y, 0,
		"Y must advance by -1 when formula truncates a negative dy to zero")
