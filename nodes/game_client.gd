extends Node

const _RACK_TEX := preload(
	"res://mods/tcp_base/sprites/infrastructure/rack/rack_frame.png"
)
const _FLOOR_TEX := preload(
	"res://mods/tcp_base/sprites/environment/floor_tile.png"
)
const _SERVER_TEX := preload(
	"res://mods/tcp_base/sprites/infrastructure/server/server_2u_off.png"
)
const _BOX_TEX := preload(
	"res://mods/tcp_base/sprites/objects/box_cardboard_new.png"
)

const _ANIMAL_SCENE := preload("res://nodes/animal.tscn")

@onready var game_server: Node = get_node("../GameServer")


func _ready() -> void:
	_build_racks()
	_build_floor()
	_build_starter_objects()
	# Wait one frame for GameServer._ready() to create entities
	await get_tree().process_frame
	_spawn_animal_nodes()
	_setup_heat_overlay()


func _build_racks() -> void:
	var rack_row: Node2D = $World/RackRow
	for i in Constants.RACK_COUNT:
		var sprite := Sprite2D.new()
		sprite.texture = _RACK_TEX
		sprite.centered = false
		sprite.position = Vector2(
			i * (Constants.RACK_WIDTH_PX + Constants.RACK_GAP_PX),
			0.0
		)
		rack_row.add_child(sprite)


func _build_floor() -> void:
	var floor_node: Node2D = $World/Floor
	var floor_y: float = float(
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PX
	)
	for i in Constants.RACK_COUNT:
		var sprite := Sprite2D.new()
		sprite.texture = _FLOOR_TEX
		sprite.centered = false
		sprite.position = Vector2(
			i * (Constants.RACK_WIDTH_PX + Constants.RACK_GAP_PX),
			floor_y
		)
		floor_node.add_child(sprite)


func _build_starter_objects() -> void:
	# Server at rack 2, slot 38 (near bottom of rack, close to floor)
	var server_sprite := Sprite2D.new()
	server_sprite.texture = _SERVER_TEX
	server_sprite.centered = false
	server_sprite.position = Vector2(
		2 * (Constants.RACK_WIDTH_PX + Constants.RACK_GAP_PX) + 6,
		38 * Constants.SLOT_HEIGHT_PX
	)
	$World/PlacedObjects.add_child(server_sprite)

	# Box on the floor near rack 0
	var box_sprite := Sprite2D.new()
	box_sprite.texture = _BOX_TEX
	box_sprite.centered = false
	var floor_y: float = float(Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PX)
	box_sprite.position = Vector2(
		0 * (Constants.RACK_WIDTH_PX + Constants.RACK_GAP_PX) + 18,
		floor_y + 4.0
	)
	$World/PlacedObjects.add_child(box_sprite)


func _setup_heat_overlay() -> void:
	var overlay_script: GDScript = preload("res://nodes/heat_overlay.gd")
	# Remove the empty placeholder node and replace with a scripted one
	var old_overlay: Node2D = $World/HeatOverlay
	old_overlay.queue_free()
	var overlay: Node2D = Node2D.new()
	overlay.name = "HeatOverlay"
	overlay.set_script(overlay_script)
	$World.add_child(overlay)
	overlay.initialize(game_server.db, game_server.heat_grid)


func _spawn_animal_nodes() -> void:
	var db: GameStateDB = game_server.db
	var animals: Array[int] = db.get_entities_with(&"species")
	for entity_id: int in animals:
		var node: Node2D = _ANIMAL_SCENE.instantiate()
		$World/Animals.add_child(node)
		node.initialize(db, entity_id)
