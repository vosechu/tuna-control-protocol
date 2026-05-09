extends GutTest

# Boot-time visual contract: instantiating main.tscn produces the right
# scene-tree shape, z-order, and bay rendering. Combined into one test
# because each assertion needed an independent scene instantiation
# under the previous shape — the cost of seven extra boots dwarfs the
# debugging benefit of one-assertion-per-test for what is fundamentally
# a single boot-smoke contract.

const _MAIN_SCENE: PackedScene = preload("res://nodes/main.tscn")


func test_main_scene_boot_state() -> void:
	var client: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(client)
	await get_tree().process_frame

	var rack_row: Node2D = client.get_node("GameClient/World/RackRow")
	# RackRow has bay sprites + RuGridOverlay child
	var bay_count: int = 0
	for child: Node in rack_row.get_children():
		if child is Sprite2D:
			bay_count += 1
	assert_eq(bay_count, 3, "Should render 3 bay sprites")

	var bay_0: Sprite2D = client.get_node("GameClient/World/RackRow/Bay_0")
	assert_null(bay_0.material, "Bay 0 should NOT have a shader material")

	var bay_neg: Sprite2D = client.get_node("GameClient/World/RackRow/Bay_-1")
	var bay_pos: Sprite2D = client.get_node("GameClient/World/RackRow/Bay_1")
	assert_null(bay_neg.material, "Bay -1 should have no shader")
	assert_null(bay_pos.material, "Bay 1 should have no shader")

	var tilemap: TileMap = client.get_node("GameClient/World/EnvironmentTileMap")
	var used: Array[Vector2i] = tilemap.get_used_cells(0)
	assert_gt(used.size(), 0, "Tilemap should have painted cells")

	# Z-order contract
	assert_eq(tilemap.z_index, 0, "Environment z=0")
	assert_eq(rack_row.z_index, 1, "RackRow z=1")
	var animals: Node = client.get_node("GameClient/World/Animals")
	assert_eq(animals.z_index, 4, "Animals z=4")

	# Rack decor invisible at boot (alpha ramps in on first plant_spawned)
	var decor: Sprite2D = client.get_node_or_null(
		"GameClient/World/RackDecor/Bay_0_decor"
	) as Sprite2D
	if decor != null:
		assert_almost_eq(decor.modulate.a, 0.0, 0.01,
			"Rack decor starts at alpha 0")

	# DynamicPlants projection node wired
	var dp: Node = client.get_node_or_null("GameClient/World/DynamicPlants")
	assert_not_null(dp, "DynamicPlants node should exist")

	# Camera at bay 0 center
	var camera: Camera2D = client.get_node("GameClient/Camera")
	var expected: Vector2 = Constants.bay_center(0)
	assert_almost_eq(
		camera.position.x, expected.x, 1.0,
		"Camera should be at bay 0 center",
	)


func test_inspect_drawer_opens_on_event() -> void:
	var client: Node = _MAIN_SCENE.instantiate()
	add_child_autofree(client)
	# Two frames: GameClient._ready() awaits one frame internally before
	# setting up the HUD.
	await get_tree().process_frame
	await get_tree().process_frame

	var drawer: PanelContainer = client.get_node(
		"GameClient/HUD/InspectDrawer",
	) as PanelContainer
	assert_not_null(drawer, "InspectDrawer should exist under HUD")
	assert_false(drawer.is_open(), "Drawer is closed at boot")

	var server: Node = client.get_node("GameServer")
	var db: GameStateDB = server.db
	var animals: Array[int] = db.get_entities_with(&"sprite_config")
	assert_gt(animals.size(), 0, "At least one animal should spawn")

	Events.entity_inspect_opened.emit(animals[0])
	await get_tree().process_frame

	assert_true(drawer.is_open(), "Drawer opens on emit")
	assert_eq(drawer._state.inspected_id, animals[0])
