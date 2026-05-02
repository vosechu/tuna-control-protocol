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
const _BOX_RACK_TEX := preload(
	"res://mods/tcp_base/sprites/objects/box01_rack_idle_strip1.png"
)
const _BOX_FLOOR_TEX := preload(
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
var _cable_layer: CableLayer
var _dangling_tip: DanglingTip
var _wiring_controller: WiringController

@onready var game_server: Node = %GameServer


func _ready() -> void:
	_build_environment_tilemap()
	_build_bays()
	_build_rack_decor()
	_build_dynamic_plants()
	$World/PlacedObjects.z_index = _Z_PLACED
	$World/Animals.z_index = _Z_ANIMALS
	# Wait one frame for GameServer._ready() to create entities
	await get_tree().process_frame
	_render_scenario_placed_objects()
	_spawn_animal_nodes()
	_setup_heat_overlay()
	_setup_sound_manager()
	_setup_placement_ui()
	_setup_lighting()
	_setup_hum_bar()
	_setup_stats_bar()
	_setup_narrator_panel()
	_setup_debug_hud()
	_setup_cable_layer()
	_setup_wiring_controller()
	# Camera position/zoom handled by camera_controller.gd


func _setup_cable_layer() -> void:
	var layer := CableLayer.new()
	layer.name = "CableLayer"
	layer.z_index = _Z_PLACED + 1
	$World.add_child(layer)
	layer.initialize(game_server.db, Events)
	var tip := DanglingTip.new()
	tip.name = "DanglingTip"
	tip.z_index = _Z_PLACED + 2
	$World.add_child(tip)
	_cable_layer = layer
	_dangling_tip = tip


func _setup_wiring_controller() -> void:
	var wc := WiringController.new()
	wc.name = "WiringController"
	$HUD.add_child(wc)
	wc.initialize(self)
	if _cable_layer != null:
		wc.wiring_mode_changed.connect(_cable_layer.set_wiring_mode)
	if _dangling_tip != null:
		_dangling_tip.initialize(wc)
	_wiring_controller = wc


# ── Wiring-intent client adapter ──
# Single-peer local loop. Networking rewires these to an ENet send when MP
# ships; WiringController doesn't care which path is used.


func send_wiring_intent(peer_id: int, intent: StringName, payload: Dictionary) -> void:
	var ws: WiringSystem = game_server.wiring_system
	match intent:
		&"CABLE_START_INTENT":
			ws.handle_start(peer_id, int(payload[&"hum_id"]))
		&"CABLE_CONNECT_INTENT":
			ws.handle_connect(
				peer_id,
				int(payload[&"source_hum_id"]),
				int(payload[&"target_id"]),
			)
		&"CABLE_PICKUP_INTENT":
			ws.handle_pickup_actuator_end(
				peer_id,
				game_server.db.get_tick(),
				int(payload[&"actuator_id"]),
			)
		&"CABLE_CANCEL_INTENT":
			ws.handle_cancel(peer_id, int(payload[&"actuator_id"]))
		&"CABLE_DELETE_INTENT":
			ws.handle_delete(peer_id, int(payload[&"actuator_id"]))


func screen_to_world(screen_pos: Vector2) -> Vector2:
	# Screen → world via the active camera's transform.
	return $Camera.get_canvas_transform().affine_inverse() * screen_pos


func entity_under_point(world_pos: Vector2) -> int:
	var px := Vector2i(roundi(world_pos.x), roundi(world_pos.y))
	var nearby: Array[int] = game_server.db.query_radius(
		px.x, px.y, 2 * Constants.SLOT_HEIGHT_PX,
	)
	if nearby.is_empty():
		return Constants.INVALID_ID
	return nearby[0]


func is_hum(entity_id: int) -> bool:
	return game_server.db.has_component(entity_id, &"hum")


func has_existing_cable(entity_id: int) -> bool:
	return game_server.db.has_component(entity_id, &"hum_cable")


func is_hum_powered_device(entity_id: int) -> bool:
	return game_server.db.has_component(entity_id, &"hum_powered")


func _setup_debug_hud() -> void:
	if not has_node("HUD"):
		var hud := CanvasLayer.new()
		hud.name = "HUD"
		add_child(hud)
	var debug_hud := DebugHud.new()
	debug_hud.name = "DebugHud"
	$HUD.add_child(debug_hud)
	# Phase 0: no inspect panel exists yet; pass null so DebugHud falls
	# back to toggling all contentment-bearing entities on Shift+F1.
	debug_hud.initialize(game_server.db, game_server.settings, null)


func _setup_narrator_panel() -> void:
	var narrator := Narrator.new()
	var panel := NarratorPanel.new()
	panel.position = Vector2(2, 118)
	panel.name = "NarratorPanel"
	$HUD.add_child(panel)
	panel.initialize(Events, narrator)


func _setup_hum_bar() -> void:
	if not has_node("HUD"):
		var hud := CanvasLayer.new()
		hud.name = "HUD"
		add_child(hud)
	var hum_bar := HumBar.new()
	hum_bar.position = Vector2(2, 2)
	hum_bar.name = "HumBar"
	$HUD.add_child(hum_bar)
	hum_bar.initialize(Events, game_server.db)


func _setup_stats_bar() -> void:
	var StatsBarScript: GDScript = preload(
		"res://nodes/animal_stats_bar.gd"
	)
	var stats_bar: HBoxContainer = HBoxContainer.new()
	stats_bar.set_script(StatsBarScript)
	stats_bar.name = "StatsBar"
	stats_bar.position = Vector2(2, 14)
	stats_bar.add_theme_constant_override("separation", 2)
	$HUD.add_child(stats_bar)
	stats_bar.initialize(game_server.db, $Camera)


func _setup_lighting() -> void:
	# Disabled — CanvasModulate washes out colors at 224x128 viewport.
	# Needs redesign for the new viewport scale.
	pass


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
	_build_slot_grid_overlay()


func _build_slot_grid_overlay() -> void:
	var OverlayScript: GDScript = preload(
		"res://nodes/slot_grid_overlay.gd"
	)
	var overlay := Node2D.new()
	overlay.name = "SlotGridOverlay"
	overlay.set_script(OverlayScript)
	overlay.z_index = _Z_DEBUG
	overlay.visible = false
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
	Events.object_placed.connect(_on_object_placed_render)


func _on_object_placed_render(
		object_id: int, _rack: int, _slot: int, object_type: StringName,
) -> void:
	# Render server-spawned objects (e.g. scenario seed) by mirroring the
	# placement-UI sprite path. Objects already wired by the UI are
	# idempotent — we never overwrite an existing sprite entry.
	if _object_sprites.has(object_id):
		return
	if not game_server.db.has_component(object_id, &"position"):
		return
	var pos: Dictionary = game_server.db.get_component(object_id, &"position")
	_create_object_sprite(object_id, object_type, int(pos[&"x"]), int(pos[&"y"]))


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


func _render_scenario_placed_objects() -> void:
	# Scenario-spawned placeable entities (HUM device, etc.) take the
	# entity_defs.spawn path, which doesn't fire Events.object_placed —
	# only game_server.place_object does that. Sweep the DB once at boot
	# and create the missing sprites. Identified by capability components
	# rather than object_type because entity_def_registry only sets
	# object_type for entities that declare a `states` block.
	var db: GameStateDB = game_server.db
	for entity_id: int in db.get_entities_with(&"hum_receiver"):
		if _object_sprites.has(entity_id):
			continue
		if not db.has_component(entity_id, &"position"):
			continue
		var pos: Dictionary = db.get_component(entity_id, &"position")
		_create_object_sprite(
			entity_id, &"hum_device", int(pos[&"x"]), int(pos[&"y"])
		)


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
	overlay.z_index = _Z_DEBUG
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
	sm.initialize(game_server.db, Events, game_server.entity_defs)


func _spawn_animal_nodes() -> void:
	var db: GameStateDB = game_server.db
	# Filter by sprite_config — objects (hum_device, arm, etc.) now carry
	# a species component from EntityDefRegistry.spawn() but have no
	# sprite_config. Only sprite-bearing entities get an AnimalNode.
	var animals: Array[int] = db.get_entities_with(
		&"sprite_config"
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
			var grid: Node2D = $World.get_node_or_null("SlotGridOverlay")
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
	var click_px := Vector2i(roundi(world_pos.x), roundi(world_pos.y))
	var bay: int = Constants.world_to_bay(click_px)
	if bay == Constants.INVALID_BAY:
		return
	var query: SlotQuery = Constants.bay_local_to_slot(bay, click_px)

	var always_rack: bool = (
		object_type == &"server_1u"
		or object_type == &"hum_device"
		or object_type == &"tuna_dispenser"
		or object_type == &"tuna_button"
	)
	var is_floor_click: bool = query.zone == &"floor"
	var place_in_rack: bool = always_rack or (
		not is_floor_click and object_type != &"arm"
		and query.zone != &"other"
	)

	var place_x: int
	var place_y: int

	if place_in_rack:
		var rack_idx: int = query.rack if query.rack != Constants.INVALID_ID else 0
		var slot_idx: int = 0
		if query.zone == &"slot":
			slot_idx = query.get_slot()
		elif query.zone == &"frame":
			slot_idx = Constants.SLOTS_PER_RACK - 1  # top slot
		var size_slots: int = 1
		if object_type == &"hum_device":
			size_slots = 6
		elif object_type == &"cardboard_box":
			size_slots = 2
		elif object_type == &"clothes_pile":
			size_slots = 2
		# Slot 0 is bottom; largest valid "lowest" slot for a size-N object is
		# SLOTS_PER_RACK - size_slots when indexed from top, but since slot 0 is
		# bottom, we clamp the placement slot to [0, SLOTS_PER_RACK - size_slots].
		slot_idx = clampi(
			slot_idx,
			Constants.TOR_SWITCH_SLOTS,
			Constants.SLOTS_PER_RACK - size_slots,
		)
		var slot_rect: Rect2i = Constants.slot_rect_world(0, rack_idx, slot_idx)
		place_x = slot_rect.position.x + slot_rect.size.x / 2
		place_y = slot_rect.position.y + slot_rect.size.y / 2
	else:
		# Floor placement (box, pile, arm)
		var rack_idx: int = query.rack if query.rack != Constants.INVALID_ID else 0
		var rack_col: Rect2i = Constants.rack_column_rect_world(0, rack_idx)
		place_x = rack_col.position.x + rack_col.size.x / 2
		var floor_rect: Rect2i = Constants.floor_rect_world(0)
		place_y = floor_rect.position.y + floor_rect.size.y / 2

	var entity_id: int = game_server.place_object(
		object_type, place_x, place_y
	)
	_create_object_sprite(
		entity_id, object_type, place_x, place_y
	)
	_placement_ui_node.clear_selection()


func _try_remove_at(world_pos: Vector2) -> void:
	var click_px := Vector2i(roundi(world_pos.x), roundi(world_pos.y))
	var nearby: Array[int] = game_server.db.query_radius(
		click_px.x, click_px.y, 2 * Constants.SLOT_HEIGHT_PX
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
	px_x: int,
	px_y: int,
) -> void:
	# Idempotent: signal-driven and UI-driven calls both arrive here.
	if _object_sprites.has(entity_id):
		return
	var sprite := Sprite2D.new()
	var is_on_floor: bool = px_y >= Constants.FLOOR_Y
	match object_type:
		&"server_1u":
			sprite.texture = _SERVER_TEX
		&"cardboard_box":
			sprite.texture = _BOX_FLOOR_TEX if is_on_floor else _BOX_RACK_TEX
		&"clothes_pile":
			sprite.texture = _PILE_TEX
		&"hum_device":
			sprite.texture = _HUM_TEX
	sprite.centered = false
	if is_on_floor:
		# Floor object: render at floor level (anchor bottom to FLOOR_Y)
		sprite.position = Vector2(
			float(px_x) - float(sprite.texture.get_width()) / 2.0,
			float(Constants.FLOOR_Y) - float(sprite.texture.get_height()),
		)
	else:
		# Rack object: use slot origin (top-left of slot)
		var world_px := Vector2i(px_x, px_y)
		var bay: int = Constants.world_to_bay(world_px)
		if bay == Constants.INVALID_BAY:
			bay = 0
		var query: SlotQuery = Constants.bay_local_to_slot(bay, world_px)
		if query.zone == &"slot":
			sprite.position = Vector2(Constants.slot_origin_world(
				bay, query.get_rack(), query.get_slot(),
			))
		else:
			sprite.position = Vector2(float(px_x), float(px_y))
	$World/PlacedObjects.add_child(sprite)
	_object_sprites[entity_id] = sprite


func _try_click_entity(world_pos: Vector2) -> void:
	var click_px := Vector2i(roundi(world_pos.x), roundi(world_pos.y))
	var nearby: Array[int] = game_server.db.query_radius(
		click_px.x, click_px.y, 2 * Constants.SLOT_HEIGHT_PX,
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
	PlayerVerbs.pet_animal(game_server.db, entity_id)


func _squeak_box(box_id: int) -> void:
	Events.box_squeaked.emit(box_id)
	PlayerVerbs.squeak_box(game_server.db, box_id)


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
