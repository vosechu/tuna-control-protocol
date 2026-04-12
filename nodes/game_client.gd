extends Node

const _RACK_TEX := preload(
	"res://mods/tcp_base/sprites/infrastructure/rack/rack_single_idle_strip1.png"
)
const _TILESET_ATLAS := preload(
	"res://mods/tcp_base/sprites/environment/tcp_tileset01.png"
)
const _SERVER_TEX := preload(
	"res://mods/tcp_base/sprites/infrastructure/server/server01_static_strip1.png"
)
const _BOX_TEX := preload(
	"res://mods/tcp_base/sprites/objects/box01_idle_strip1.png"
)
const _PILE_TEX := preload(
	"res://mods/tcp_base/sprites/objects/pile_clothes.png"
)
const _ANIMAL_SCENE := preload("res://nodes/animal.tscn")

# Floor tile extracted from tileset atlas — dark ground strip at y=48
const _FLOOR_REGION := Rect2(64, 48, 80, 16)

var _placement_ui_node: Control
var _object_sprites: Dictionary = {}  # entity_id -> Sprite2D
# entity_id -> float (seconds elapsed in clearing)
var _clearing_objects: Dictionary = {}
var _starter_sprites: Array[Sprite2D] = []
var _floor_tex: AtlasTexture

@onready var game_server: Node = %GameServer


func _ready() -> void:
	_floor_tex = AtlasTexture.new()
	_floor_tex.atlas = _TILESET_ATLAS
	_floor_tex.region = _FLOOR_REGION
	_build_racks()
	_build_floor()
	_build_starter_objects()
	# Wait one frame for GameServer._ready() to create entities
	await get_tree().process_frame
	_register_starter_sprites()
	_spawn_animal_nodes()
	_setup_heat_overlay()
	_setup_sound_manager()
	_setup_placement_ui()
	_setup_lighting()
	_setup_hum_bar()


func _setup_hum_bar() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	var hum_bar := HumBar.new()
	hum_bar.position = Vector2(10, 10)
	hum_bar.name = "HumBar"
	hud.add_child(hum_bar)
	hum_bar.initialize(Events)


func _setup_lighting() -> void:
	var lighting := LightingSystem.new()
	lighting.name = "LightingSystem"
	$World.add_child(lighting)
	lighting.initialize(Events)


func _build_racks() -> void:
	var rack_row: Node2D = $World/RackRow
	# Bottom-align rack sprite to the floor — sprite is smaller than
	# the 42U budget so we anchor its bottom edge to the floor top.
	var rack_bottom_y: float = float(
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PX
	)
	var rack_top_y: float = rack_bottom_y - float(_RACK_TEX.get_height())
	for i in Constants.RACK_COUNT:
		var sprite := Sprite2D.new()
		sprite.texture = _RACK_TEX
		sprite.centered = false
		sprite.position = Vector2(
			i * Constants.RACK_STRIDE_PX,
			rack_top_y,
		)
		rack_row.add_child(sprite)
	_build_ru_grid_overlay()


func _build_ru_grid_overlay() -> void:
	var OverlayScript: GDScript = preload("res://nodes/ru_grid_overlay.gd")
	var overlay := Node2D.new()
	overlay.name = "RuGridOverlay"
	overlay.set_script(OverlayScript)
	overlay.z_index = 100
	$World.add_child(overlay)


func _build_floor() -> void:
	var floor_node: Node2D = $World/Floor
	var floor_y: float = float(
		Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PX
	)
	for i in Constants.RACK_COUNT:
		var sprite := Sprite2D.new()
		sprite.texture = _floor_tex
		sprite.centered = false
		sprite.position = Vector2(
			i * (Constants.RACK_WIDTH_PX + Constants.RACK_GAP_PX),
			floor_y
		)
		floor_node.add_child(sprite)


func _build_starter_objects() -> void:
	# Server at rack 1, slot 40 (bottom of rack, right above floor, near Mochi)
	var server_sprite := Sprite2D.new()
	server_sprite.texture = _SERVER_TEX
	server_sprite.centered = false
	server_sprite.position = Vector2(
		1 * (Constants.RACK_WIDTH_PX + Constants.RACK_GAP_PX) + 6,
		40 * Constants.SLOT_HEIGHT_PX
	)
	$World/PlacedObjects.add_child(server_sprite)
	_starter_sprites.append(server_sprite)

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
	_starter_sprites.append(box_sprite)

	# Clothes pile on the floor near rack 2
	var pile_sprite := Sprite2D.new()
	pile_sprite.texture = _PILE_TEX
	pile_sprite.centered = false
	var pile_x: float = 2.0 * float(Constants.RACK_WIDTH_PX + Constants.RACK_GAP_PX) + 12.0
	pile_sprite.position = Vector2(pile_x, floor_y + 4.0)
	$World/PlacedObjects.add_child(pile_sprite)
	_starter_sprites.append(pile_sprite)


func _register_starter_sprites() -> void:
	# Match starter sprites to DB entities with object_type
	var db: GameStateDB = game_server.db
	var objects: Array[int] = db.get_entities_with(
		&"object_type"
	)
	# Starter objects are created in order: server, box, pile
	# Match by index (same creation order as sprites)
	var sprite_idx: int = 0
	for entity_id: int in objects:
		if sprite_idx >= _starter_sprites.size():
			break
		_object_sprites[entity_id] = (
			_starter_sprites[sprite_idx]
		)
		sprite_idx += 1
	_starter_sprites.clear()


func _setup_heat_overlay() -> void:
	var HeatOverlayScript: GDScript = preload("res://nodes/heat_overlay.gd")
	# Remove the empty placeholder node and replace with a scripted one
	var old_overlay: Node2D = $World/HeatOverlay
	old_overlay.queue_free()
	var overlay: Node2D = Node2D.new()
	overlay.name = "HeatOverlay"
	overlay.set_script(HeatOverlayScript)
	$World.add_child(overlay)
	overlay.initialize(game_server.db, game_server.heat_grid)


func _setup_sound_manager() -> void:
	var SoundManagerScript: GDScript = preload("res://nodes/sound_manager.gd")
	# Replace the empty placeholder node with a scripted one
	var old_sm: Node = $SoundManager
	old_sm.queue_free()
	var sm: Node = Node.new()
	sm.name = "SoundManager"
	sm.set_script(SoundManagerScript)
	add_child(sm)
	sm.initialize(game_server.db)
	# Register cat entities with the sound manager
	var db: GameStateDB = game_server.db
	var animals: Array[int] = db.get_entities_with(&"species")
	for entity_id: int in animals:
		var species: Dictionary = db.get_component(entity_id, &"species")
		if String(species[&"id"]).contains("cat"):
			sm.register_cat(entity_id)


func _spawn_animal_nodes() -> void:
	var db: GameStateDB = game_server.db
	var animals: Array[int] = db.get_entities_with(&"species")
	for entity_id: int in animals:
		var node: Node2D = _ANIMAL_SCENE.instantiate()
		$World/Animals.add_child(node)
		node.initialize(db, entity_id)


func _setup_placement_ui() -> void:
	var PlacementUIScript: GDScript = preload(
		"res://nodes/placement_ui.gd"
	)
	var old_ui: Control = $PlacementUI
	old_ui.queue_free()
	_placement_ui_node = Control.new()
	_placement_ui_node.name = "PlacementUI"
	_placement_ui_node.set_script(PlacementUIScript)
	add_child(_placement_ui_node)


func _unhandled_input(event: InputEvent) -> void:
	# Cmd+W / Cmd+Q (Mac) or Ctrl+W / Ctrl+Q to quit
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_W and event.is_command_or_control_pressed():
			get_tree().quit()
			return
		if event.keycode == KEY_Q and event.is_command_or_control_pressed():
			get_tree().quit()
			return

	if not event is InputEventMouseButton:
		return
	if not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	var camera: Camera2D = $Camera
	var world_pos: Vector2 = (
		camera.get_global_mouse_position()
	)

	if _placement_ui_node.is_remove_mode():
		_try_remove_at(world_pos)
	elif _placement_ui_node.get_selected_type() != &"":
		_try_place_at(
			world_pos,
			_placement_ui_node.get_selected_type(),
		)
	else:
		_try_click_entity(world_pos)


func _try_place_at(
	world_pos: Vector2,
	object_type: StringName,
) -> void:
	var total_rack_px: int = (
		Constants.RACK_WIDTH_PX + Constants.RACK_GAP_PX
	)
	@warning_ignore("integer_division")
	var rack: int = int(world_pos.x) / total_rack_px
	rack = clampi(rack, 0, Constants.RACK_COUNT - 1)
	@warning_ignore("integer_division")
	var slot: int = int(world_pos.y) / Constants.SLOT_HEIGHT_PX

	var place_x: int
	var place_y: int

	var is_rack_object: bool = (
		object_type == &"server_2u"
		or object_type == &"hum_device"
		or object_type == &"tuna_dispenser"
		or object_type == &"tuna_button"
	)
	if is_rack_object:
		var size_ru: int = 1
		if object_type == &"hum_device":
			size_ru = 6
		elif object_type == &"server_2u":
			size_ru = 2
		slot = clampi(
			slot,
			Constants.TOR_SWITCH_SLOTS,
			Constants.SLOTS_PER_RACK - size_ru,
		)
		place_x = rack * Constants.RACK_WIDTH_PU
		place_y = slot * Constants.SLOT_HEIGHT_PU
	elif object_type == &"arm":
		# ARM goes on the floor
		place_x = rack * Constants.RACK_WIDTH_PU
		@warning_ignore("integer_division")
		place_y = (
			Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU
			+ Constants.FLOOR_HEIGHT_PU / 2
		)
	else:
		# Boxes and piles go on the floor
		@warning_ignore("integer_division")
		var half_rack: int = Constants.RACK_WIDTH_PU / 2
		place_x = rack * Constants.RACK_WIDTH_PU + half_rack
		@warning_ignore("integer_division")
		var floor_third: int = Constants.FLOOR_HEIGHT_PU / 3
		place_y = (
			Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU
			+ floor_third
		)

	var entity_id: int = game_server.place_object(
		object_type, place_x, place_y
	)
	_create_object_sprite(
		entity_id, object_type, place_x, place_y
	)
	_placement_ui_node.clear_selection()


func _try_remove_at(world_pos: Vector2) -> void:
	var click_pu_x: int = Constants.from_world(world_pos.x)
	var click_pu_y: int = Constants.from_world(world_pos.y)
	var nearby: Array[int] = game_server.db.query_radius(
		click_pu_x, click_pu_y, Constants.ru_to_pu(2)
	)
	for entity_id: int in nearby:
		if not game_server.db.has_component(
			entity_id, &"object_type"
		):
			continue
		_start_clearing(entity_id)
		break


func _start_clearing(entity_id: int) -> void:
	if _clearing_objects.has(entity_id):
		# Click again to cancel
		_clearing_objects.erase(entity_id)
		if _object_sprites.has(entity_id):
			_object_sprites[entity_id].modulate = Color.WHITE
		return
	if _object_sprites.has(entity_id):
		_clearing_objects[entity_id] = 0.0


func _create_object_sprite(
	entity_id: int,
	object_type: StringName,
	pu_x: int,
	pu_y: int,
) -> void:
	var sprite := Sprite2D.new()
	match object_type:
		&"server_2u":
			sprite.texture = _SERVER_TEX
		&"cardboard_box":
			sprite.texture = _BOX_TEX
		&"clothes_pile":
			sprite.texture = _PILE_TEX
	sprite.centered = false
	sprite.position = Vector2(
		Constants.to_world(pu_x),
		Constants.to_world(pu_y),
	)
	$World/PlacedObjects.add_child(sprite)
	_object_sprites[entity_id] = sprite


func _try_click_entity(world_pos: Vector2) -> void:
	var click_x: int = Constants.from_world(world_pos.x)
	var click_y: int = Constants.from_world(world_pos.y)
	var nearby: Array[int] = game_server.db.query_radius(
		click_x, click_y, Constants.ru_to_pu(2),
	)
	for entity_id: int in nearby:
		# Click on button → press it
		if game_server.db.has_component(
			entity_id, &"tuna_button",
		):
			game_server.food_system.press_button(entity_id)
			return
		# Click on cat/ferret → pet it
		if game_server.db.has_component(
			entity_id, &"species",
		):
			_pet_animal(entity_id)
			return
		# Click on box → squeak it
		if game_server.db.has_component(
			entity_id, &"object_type",
		):
			var otype: Dictionary = (
				game_server.db.get_component(
					entity_id, &"object_type",
				)
			)
			if otype[&"type"] == &"cardboard_box":
				_squeak_box(entity_id)
				return


func _pet_animal(entity_id: int) -> void:
	if not game_server.db.has_component(
		entity_id, &"desires",
	):
		return
	var attention: int = game_server.db.get_field(
		entity_id, &"desires", &"attention",
	)
	game_server.db.set_field(
		entity_id, &"desires", &"attention",
		mini(1000, attention + 500),
	)


func _squeak_box(box_id: int) -> void:
	var box_pos: Dictionary = game_server.db.get_component(
		box_id, &"position",
	)
	var nearby: Array[int] = game_server.db.query_radius(
		box_pos[&"x"], box_pos[&"y"],
		Constants.ru_to_pu(6),
	)
	for entity_id: int in nearby:
		if not game_server.db.has_component(
			entity_id, &"species",
		):
			continue
		if not game_server.db.has_component(
			entity_id, &"ai_state",
		):
			continue
		var ai: Dictionary = game_server.db.get_component(
			entity_id, &"ai_state",
		)
		var s: StringName = ai[&"state"]
		if s == &"PACING" or s == &"HUNGRY" \
				or s == &"RETURNING" or s == &"EATING":
			game_server.db.set_component(
				entity_id, &"ai_state", {
					&"state": &"RETURNING",
					&"meta_state": &"GOAL_DIRECTED",
					&"commitment_score": 200,
				},
			)
			game_server.db.set_component(
				entity_id, &"target", {
					&"x": box_pos[&"x"],
					&"y": box_pos[&"y"],
					&"entity_id": box_id,
				},
			)


func _process(delta: float) -> void:
	var to_remove: Array[int] = []
	for entity_id: int in _clearing_objects:
		_clearing_objects[entity_id] += delta
		var timer: float = _clearing_objects[entity_id]
		# Pulse the sprite with accelerating frequency
		if _object_sprites.has(entity_id):
			var pulse: float = (
				0.5
				+ 0.5 * sin(
					timer * PI * (2.0 + timer * 2.0)
				)
			)
			_object_sprites[entity_id].modulate = Color(
				1.0, 1.0, 1.0, pulse
			)
		# After 2 seconds, remove
		if timer >= 2.0:
			to_remove.append(entity_id)
	for entity_id: int in to_remove:
		_clearing_objects.erase(entity_id)
		if _object_sprites.has(entity_id):
			_object_sprites[entity_id].queue_free()
			_object_sprites.erase(entity_id)
		game_server.remove_object(entity_id)
