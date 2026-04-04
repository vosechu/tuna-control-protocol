extends GutTest

var _scene: PackedScene


func before_each() -> void:
	_scene = load("res://nodes/animal.tscn")


func test_animal_scene_loads():
	assert_not_null(_scene,
		"animal.tscn must load without parse errors")


func test_animal_scene_instantiates():
	var node: Node2D = _scene.instantiate() as Node2D
	add_child_autofree(node)
	assert_not_null(node,
		"animal.tscn must instantiate as Node2D")


func test_sprite_node_exists():
	var node: Node2D = _scene.instantiate() as Node2D
	add_child_autofree(node)
	var sprite: AnimatedSprite2D = node.get_node("Sprite") as AnimatedSprite2D
	assert_not_null(sprite,
		"Sprite (AnimatedSprite2D) must exist")


func test_name_label_exists():
	var node: Node2D = _scene.instantiate() as Node2D
	add_child_autofree(node)
	var label: Label = node.get_node("NameLabel") as Label
	assert_not_null(label,
		"NameLabel must exist")


func test_state_label_exists():
	var node: Node2D = _scene.instantiate() as Node2D
	add_child_autofree(node)
	var label: Label = node.get_node("StateLabel") as Label
	assert_not_null(label,
		"StateLabel must exist")


func test_purr_indicator_exists():
	var node: Node2D = _scene.instantiate() as Node2D
	add_child_autofree(node)
	var label: Label = node.get_node("PurrIndicator") as Label
	assert_not_null(label,
		"PurrIndicator must exist")
	assert_false(label.visible,
		"PurrIndicator must start hidden")
