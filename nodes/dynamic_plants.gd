extends Node

const _TILESET_ATLAS := preload(
	"res://mods/tcp_base/sprites/environment/tcp_tileset01.png"
)

const REGIONS: Dictionary = {
	&"moss": Rect2(96, 32, 8, 8),
	&"grass": Rect2(112, 32, 8, 8),
	&"blossom": Rect2(128, 32, 8, 8),
	&"flower": Rect2(64, 32, 8, 8),
}

var _server_sprites: Dictionary = {}
var _plant_sprites: Dictionary = {}


func _ready() -> void:
	Events.plant_spawned.connect(_on_plant_spawned)
	Events.plant_despawned.connect(_on_plant_despawned)


func register_server_sprite(server_id: int, sprite: Sprite2D) -> void:
	_server_sprites[server_id] = sprite


func unregister_server_sprite(server_id: int) -> void:
	if _plant_sprites.has(server_id):
		_on_plant_despawned(server_id)
	_server_sprites.erase(server_id)


func _on_plant_spawned(server_id: int) -> void:
	if not _server_sprites.has(server_id):
		return
	if _plant_sprites.has(server_id):
		return
	var server_sprite: Sprite2D = _server_sprites[server_id]
	var plant: Sprite2D = _create_plant_sprite(&"moss")
	server_sprite.add_child(plant)
	_plant_sprites[server_id] = plant


func _on_plant_despawned(server_id: int) -> void:
	if not _plant_sprites.has(server_id):
		return
	var plant: Sprite2D = _plant_sprites[server_id]
	plant.queue_free()
	_plant_sprites.erase(server_id)


func _create_plant_sprite(variant: StringName) -> Sprite2D:
	var sprite := Sprite2D.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = _TILESET_ATLAS
	atlas.region = REGIONS.get(variant, REGIONS[&"moss"])
	sprite.texture = atlas
	sprite.centered = false
	sprite.position = Vector2(3, -6)
	return sprite
