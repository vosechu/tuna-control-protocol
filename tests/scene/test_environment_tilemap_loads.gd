extends GutTest

const _SCENE := preload("res://nodes/environment_tilemap.tscn")

func test_scene_instantiates():
	var node: TileMap = _SCENE.instantiate()
	add_child_autofree(node)
	assert_not_null(node, "Scene should instantiate")

func test_tile_set_is_loaded():
	var node: TileMap = _SCENE.instantiate()
	add_child_autofree(node)
	assert_not_null(node.tile_set,
		"TileMap should have a tile_set assigned")

func test_tile_set_has_atlas_source():
	var node: TileMap = _SCENE.instantiate()
	add_child_autofree(node)
	var source_count: int = node.tile_set.get_source_count()
	assert_gt(source_count, 0,
		"TileSet should have at least one source")
