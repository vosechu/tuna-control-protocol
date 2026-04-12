extends GutTest

var _client: Node


func before_each() -> void:
	var scene: PackedScene = preload("res://nodes/main.tscn")
	_client = scene.instantiate()
	add_child_autofree(_client)
	await get_tree().process_frame


func test_three_bays_rendered():
	var rack_row: Node2D = _client.get_node(
		"GameClient/World/RackRow"
	)
	# RackRow has bay sprites + RuGridOverlay child
	var bay_count: int = 0
	for child: Node in rack_row.get_children():
		if child is Sprite2D:
			bay_count += 1
	assert_eq(bay_count, 3, "Should render 3 bay sprites")


func test_bay_0_not_desaturated():
	var bay_0: Sprite2D = _client.get_node(
		"GameClient/World/RackRow/Bay_0"
	)
	assert_null(bay_0.material,
		"Bay 0 should NOT have a shader material")


func test_peek_bays_render_same_as_active():
	var bay_neg: Sprite2D = _client.get_node(
		"GameClient/World/RackRow/Bay_-1"
	)
	var bay_pos: Sprite2D = _client.get_node(
		"GameClient/World/RackRow/Bay_1"
	)
	assert_null(bay_neg.material, "Bay -1 should have no shader")
	assert_null(bay_pos.material, "Bay 1 should have no shader")


func test_environment_tilemap_has_cells():
	var tilemap: TileMap = _client.get_node(
		"GameClient/World/EnvironmentTileMap"
	)
	var used: Array[Vector2i] = tilemap.get_used_cells(0)
	assert_gt(used.size(), 0,
		"Tilemap should have painted cells")


func test_z_order_contract():
	var env: Node = _client.get_node(
		"GameClient/World/EnvironmentTileMap"
	)
	var rack_row: Node = _client.get_node(
		"GameClient/World/RackRow"
	)
	var animals: Node = _client.get_node(
		"GameClient/World/Animals"
	)
	assert_eq(env.z_index, 0, "Environment z=0")
	assert_eq(rack_row.z_index, 1, "RackRow z=1")
	assert_eq(animals.z_index, 4, "Animals z=4")


func test_rack_decor_starts_invisible():
	var decor: Sprite2D = _client.get_node_or_null(
		"GameClient/World/RackDecor/Bay_0_decor"
	) as Sprite2D
	if decor == null:
		return
	assert_almost_eq(decor.modulate.a, 0.0, 0.01,
		"Rack decor starts at alpha 0")


func test_dynamic_plants_wired():
	var dp: Node = _client.get_node_or_null(
		"GameClient/World/DynamicPlants"
	)
	assert_not_null(dp, "DynamicPlants node should exist")


func test_camera_at_bay_center():
	var camera: Camera2D = _client.get_node(
		"GameClient/Camera"
	)
	var expected: Vector2 = Constants.bay_center(0)
	assert_almost_eq(
		camera.position.x, expected.x, 1.0,
		"Camera should be at bay 0 center",
	)
