extends GutTest

const _DYNAMIC_PLANTS_SCRIPT := preload("res://nodes/dynamic_plants.gd")

var _node: Node
var _server_sprite: Sprite2D


func before_each() -> void:
	_node = Node.new()
	_node.set_script(_DYNAMIC_PLANTS_SCRIPT)
	add_child_autofree(_node)
	_server_sprite = Sprite2D.new()
	add_child_autofree(_server_sprite)
	_node.register_server_sprite(42, _server_sprite)


func test_plant_spawned_creates_sprite_child():
	assert_eq(_server_sprite.get_child_count(), 0,
		"Server sprite starts with no children")
	_node._on_plant_spawned(42)
	assert_eq(_server_sprite.get_child_count(), 1,
		"Plant spawn should add a Sprite2D child to the server")


func test_plant_despawned_removes_child():
	_node._on_plant_spawned(42)
	assert_eq(_server_sprite.get_child_count(), 1)
	_node._on_plant_despawned(42)
	await get_tree().process_frame
	assert_eq(_server_sprite.get_child_count(), 0,
		"Plant despawn should remove the Sprite2D child")


func test_unregistered_server_noops():
	_node._on_plant_spawned(999)
	pass_test("No crash")


func test_plant_sprite_clears_status_strip():
	_node._on_plant_spawned(42)
	var plant: Sprite2D = _server_sprite.get_child(0)
	var plant_rect: Rect2 = Rect2(plant.position, Vector2(8, 8))
	var strip_rect: Rect2 = Rect2(0, 0, 2, 8)
	assert_false(plant_rect.intersects(strip_rect),
		"Plant must not overlap status strip %s — got %s" % [
			strip_rect, plant_rect,
		])
