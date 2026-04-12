extends Node

const _RACK_5SET_TEX := preload(
	"res://mods/tcp_base/sprites/infrastructure/rack/rack_5set_idle_strip1.png"
)
const _RACK_DECOR_TEX := preload(
	"res://mods/tcp_base/sprites/infrastructure/rack/rack_5set_decor_strip1.png"
)
const _ENVIRONMENT_TILEMAP_SCENE := preload(
	"res://nodes/environment_tilemap.tscn"
)
const _PEEK_BAY_SHADER := preload(
	"res://mods/tcp_base/shaders/peek_bay_desaturate.gdshader"
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
const _HUM_TEX := preload(
	"res://mods/tcp_base/sprites/infrastructure/server/hum_device_static_strip1.png"
)
const _ANIMAL_SCENE := preload("res://nodes/animal.tscn")

const _VISIBLE_BAY_INDICES: Array[int] = [-1, 0, 1]

const _Z_ENVIRONMENT: int = 0
const _Z_RACK_ROW: int = 1
const _Z_RACK_DECOR: int = 2
const _Z_PLACED: int = 3
const _Z_ANIMALS: int = 4
const _Z_HEAT: int = 7
const _Z_DEBUG: int = 100

var _placement_ui_node: Control
var _object_sprites: Dictionary = {}  # entity_id -> Sprite2D
# entity_id -> float (seconds elapsed in clearing)
var _clearing_objects: Dictionary = {}
var _starter_sprites: Array[Sprite2D] = []

@onready var game_server: Node = %GameServer


func _ready() -> void:
	_build_environment_tilemap()
	_build_bays()
	_build_rack_decor()
	_build_dynamic_plants()
	_build_starter_objects()
	$World/PlacedObjects.z_index = _Z_PLACED
	$World/Animals.z_index = _Z_ANIMALS
	# Wait one frame for GameServer._ready() to create entities
	await get_tree().process_frame
	_register_starter_sprites()
	_spawn_animal_nodes()
	_setup_heat_overlay()
	_setup_sound_manager()
	_setup_placement_ui()
	_setup_lighting()
	_setup_hum_bar()
	_setup_narrator_panel()
	# Camera position/zoom handled by camera_controller.gd


func _setup_narrator_panel() -> void:
	var narrator := Narrator.new()
	var panel := NarratorPanel.new()
	panel.position = Vector2(10, 340)
	panel.name = "NarratorPanel"
	$HUD.add_child(panel)
	panel.initialize(Events, narrator)


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


func _build_environment_tilemap() -> void:
	var tilemap_node: TileMap = _ENVIRONMENT_TILEMAP_SCENE.instantiate()
	tilemap_node.name = "EnvironmentTileMap"
	tilemap_node.z_index = _Z_ENVIRONMENT
	$World.add_child(tilemap_node)
	var painter := TilePainter.new(tilemap_node)
	for bay_index: int in _VISIBLE_BAY_INDICES:
		painter.paint_bay(bay_index)


func _build_bays() -> void:
	var rack_row: Node2D = $World/RackRow
	rack_row.z_index = _Z_RACK_ROW
	for bay_index: int in _VISIBLE_BAY_INDICES:
		var sprite := Sprite2D.new()
		sprite.name = "Bay_%d" % bay_index
		sprite.texture = _RACK_5SET_TEX
		sprite.centered = false
		sprite.position = Vector2(
			float(bay_index * Constants.BAY_STRIDE_PX),
			float(Constants.RACK_TOP_Y),
		)
		# All bays render the same — no desaturation for neighboring bays
		rack_row.add_child(sprite)
	_build_ru_grid_overlay()


func _build_ru_grid_overlay() -> void:
	var OverlayScript: GDScript = preload(
		"res://nodes/ru_grid_overlay.gd"
	)
	var overlay := Node2D.new()
	overlay.name = "RuGridOverlay"
	overlay.set_script(OverlayScript)
	overlay.z_index = _Z_DEBUG
	$World.add_child(overlay)


func _build_rack_decor() -> void:
	var decor_node := Node2D.new()
	decor_node.name = "RackDecor"
	decor_node.z_index = _Z_RACK_DECOR
	$World.add_child(decor_node)
	var decor := Sprite2D.new()
	decor.name = "Bay_0_decor"
	decor.texture = _RACK_DECOR_TEX
	decor.centered = false
	decor.position = Vector2(0.0, float(Constants.RACK_TOP_Y))
	decor.modulate = Color(1.0, 1.0, 1.0, 0.0)
	decor_node.add_child(decor)
	Events.plant_spawned.connect(
		_on_plant_spawned_ramp_decor
	)


func _on_plant_spawned_ramp_decor(
	_server_id: int,
) -> void:
	var decor_node: Node2D = $World.get_node_or_null(
		"RackDecor"
	)
	if decor_node == null:
		return
	var decor: Sprite2D = decor_node.get_node_or_null(
		"Bay_0_decor"
	) as Sprite2D
	if decor == null or decor.modulate.a >= 0.69:
		return
	var tween: Tween = create_tween()
	tween.tween_property(decor, "modulate:a", 0.7, 3.0)


func _build_dynamic_plants() -> void:
	var dp_script: GDScript = preload(
		"res://nodes/dynamic_plants.gd"
	)
	var dp_node: Node = Node.new()
	dp_node.name = "DynamicPlants"
	dp_node.set_script(dp_script)
	$World.add_child(dp_node)


func _build_starter_objects() -> void:
	var server_sprite := Sprite2D.new()
	server_sprite.texture = _SERVER_TEX
	server_sprite.centered = false
	var server_pu: Vector2i = Constants.rack_slot_to_pu(
		0, 1, 8
	)
	# Server Y: rack top + 4px frame + slot position in PU
	server_sprite.position = Vector2(
		Constants.to_world(server_pu.x)
			- float(Constants.RACK_WIDTH_PX) / 2.0,
		Constants.to_world(server_pu.y) + float(Constants.RACK_TOP_Y) + 4.0,
	)
	$World/PlacedObjects.add_child(server_sprite)
	_starter_sprites.append(server_sprite)

	var box_sprite := Sprite2D.new()
	box_sprite.texture = _BOX_TEX
	box_sprite.centered = false
	# Box is 16px tall, centered=false (top-left at position).
	# Place top-left so bottom edge sits on the floor surface.
	box_sprite.position = Vector2(
		float(Constants.LEFTMOST_RACK_OFFSET_PX),
		float(Constants.FLOOR_Y) - 16.0,
	)
	$World/PlacedObjects.add_child(box_sprite)
	_starter_sprites.append(box_sprite)



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
	var HeatOverlayScript: GDScript = preload(
		"res://nodes/heat_overlay.gd"
	)
	# Remove the empty placeholder node and replace
	var old_overlay: Node2D = $World/HeatOverlay
	old_overlay.queue_free()
	var overlay: Node2D = Node2D.new()
	overlay.name = "HeatOverlay"
	overlay.set_script(HeatOverlayScript)
	overlay.z_index = _Z_HEAT
	$World.add_child(overlay)
	overlay.initialize(
		game_server.db, game_server.heat_grid
	)


func _setup_sound_manager() -> void:
	var SoundManagerScript: GDScript = preload(
		"res://nodes/sound_manager.gd"
	)
	# Replace the empty placeholder with a scripted one
	var old_sm: Node = $SoundManager
	old_sm.queue_free()
	var sm: Node = Node.new()
	sm.name = "SoundManager"
	sm.set_script(SoundManagerScript)
	add_child(sm)
	sm.initialize(game_server.db, Events)
	# Register cat entities with the sound manager
	var db: GameStateDB = game_server.db
	var animals: Array[int] = db.get_entities_with(
		&"species"
	)
	for entity_id: int in animals:
		var species: Dictionary = db.get_component(
			entity_id, &"species"
		)
		if String(species[&"id"]).contains("cat"):
			sm.register_cat(entity_id)


func _spawn_animal_nodes() -> void:
	var db: GameStateDB = game_server.db
	var animals: Array[int] = db.get_entities_with(
		&"species"
	)
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
		if (
			event.keycode == KEY_W
			and event.is_command_or_control_pressed()
		):
			get_tree().quit()
			return
		if (
			event.keycode == KEY_Q
			and event.is_command_or_control_pressed()
		):
			get_tree().quit()
			return
		if event.keycode == KEY_G:
			var grid: Node2D = $World.get_node_or_null("RuGridOverlay")
			if grid:
				grid.visible = not grid.visible
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
	var slot: int = (
		int(world_pos.y) / Constants.SLOT_HEIGHT_PX
	)

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
		var half_rack: int = (
			Constants.RACK_WIDTH_PU / 2
		)
		place_x = (
			rack * Constants.RACK_WIDTH_PU + half_rack
		)
		@warning_ignore("integer_division")
		var floor_third: int = (
			Constants.FLOOR_HEIGHT_PU / 3
		)
		place_y = (
			Constants.SLOTS_PER_RACK
			* Constants.SLOT_HEIGHT_PU
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
	var click_pu_x: int = Constants.from_world(
		world_pos.x
	)
	var click_pu_y: int = Constants.from_world(
		world_pos.y
	)
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
			_object_sprites[entity_id].modulate = (
				Color.WHITE
			)
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
		&"hum_device":
			sprite.texture = _HUM_TEX
	sprite.centered = false
	sprite.position = Vector2(
		Constants.to_world(pu_x),
		Constants.to_world(pu_y) + float(Constants.RACK_TOP_Y) + 4.0,
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
			var can_id: int = (
				game_server.food_system.press_button(
					entity_id,
				)
			)
			if can_id != Constants.INVALID_ID:
				Events.food_dispensed.emit(can_id)
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
	Events.box_squeaked.emit(box_id)
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
		var timer: float = (
			_clearing_objects[entity_id]
		)
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
