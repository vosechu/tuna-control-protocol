extends GutTest

const _NARRATOR_SCRIPT := preload("res://nodes/robot_narrator.gd")

var _narrator: Node


func before_each() -> void:
	_narrator = Node.new()
	_narrator.set_script(_NARRATOR_SCRIPT)
	add_child_autofree(_narrator)


func test_spawn_log_contains_growth_id():
	_narrator._on_plant_spawned(10)
	assert_string_contains(_narrator._last_log_text, "DECORATIVE-GROWTH-01",
		"Spawn log should contain the assigned growth ID")


func test_spawn_log_contains_server_unit_name():
	_narrator._on_plant_spawned(10)
	assert_string_contains(_narrator._last_log_text, "UNIT-S10",
		"Spawn log should reference the server unit name")


func test_despawn_log_names_correct_plant():
	_narrator._on_plant_spawned(10)
	_narrator._on_plant_spawned(20)
	_narrator._on_plant_despawned(10)
	assert_string_contains(
		_narrator._last_log_text, "DECORATIVE-GROWTH-01",
		"Despawn should name the specific plant, not the latest ID",
	)


func test_despawn_unknown_server_uses_placeholder():
	_narrator._on_plant_despawned(999)
	assert_string_contains(
		_narrator._last_log_text, "DECORATIVE-GROWTH-??",
		"Unknown server despawn should use ?? placeholder",
	)
