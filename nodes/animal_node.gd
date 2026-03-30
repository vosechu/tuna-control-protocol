extends Node2D

var entity_id: int = Constants.INVALID_ID

var _db: GameStateDB
var _prev_pos: Vector2
var _target_pos: Vector2

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _name_label: Label = $NameLabel


func initialize(db: GameStateDB, eid: int) -> void:
	_db = db
	entity_id = eid
	var pos: Dictionary = _db.get_component(entity_id, &"position")
	_target_pos = Vector2(
		Constants.to_world(pos[&"x"]),
		Constants.to_world(pos[&"y"])
	)
	_prev_pos = _target_pos
	global_position = _target_pos
	var species: Dictionary = _db.get_component(entity_id, &"species")
	_setup_sprite(species)
	_setup_name_label(species)


func _setup_sprite(species: Dictionary) -> void:
	var variant: String = String(
		species.get(&"variant", &"cat01")
	)
	var base_path: String = ""
	if String(species[&"id"]).contains("cat"):
		base_path = (
			"res://mods/tcp_base/sprites/cat/"
			+ "%s" % variant
		)
		_sprite.scale = Vector2(2.0, 2.0)
	else:
		base_path = (
			"res://mods/tcp_base/sprites/ferret/"
			+ "%s" % variant
		)
		_sprite.scale = Vector2(2.0, 2.0)
	var idle_tex: Texture2D = load(
		base_path + "_idle_strip8.png"
	)
	if idle_tex == null:
		push_error(
			"Could not load idle sprite: %s"
			% (base_path + "_idle_strip8.png")
		)
		return
	var walk_tex: Texture2D = load(
		base_path + "_walk_strip8.png"
	)
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	_add_strip_animation(frames, &"idle", idle_tex, 8, 6.0)
	if walk_tex:
		_add_strip_animation(
			frames, &"walk", walk_tex, 8, 8.0
		)
	_sprite.sprite_frames = frames
	_sprite.play(&"idle")


func _setup_name_label(species: Dictionary) -> void:
	var animal_name: String = String(
		species.get(&"name", &"???")
	)
	_name_label.text = animal_name


func _add_strip_animation(
	frames: SpriteFrames,
	anim_name: StringName,
	sheet: Texture2D,
	frame_count: int,
	fps: float,
) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, true)
	@warning_ignore("integer_division")
	var frame_width: int = sheet.get_width() / frame_count
	var frame_height: int = sheet.get_height()
	for i: int in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(
			i * frame_width, 0,
			frame_width, frame_height
		)
		frames.add_frame(anim_name, atlas)


func _physics_process(_delta: float) -> void:
	if _db == null or not _db.has_entity(entity_id):
		return
	_prev_pos = _target_pos
	var pos: Dictionary = _db.get_component(
		entity_id, &"position"
	)
	_target_pos = Vector2(
		Constants.to_world(pos[&"x"]),
		Constants.to_world(pos[&"y"])
	)

	# Update animation based on AI state
	if _db.has_component(entity_id, &"ai_state"):
		var ai: Dictionary = _db.get_component(
			entity_id, &"ai_state"
		)
		var state: StringName = ai[&"state"]
		var anim: StringName = &"idle"
		if state == &"MOVING_TO" or state == &"SEEKING":
			anim = &"walk"
		if (
			_sprite.sprite_frames
			and _sprite.sprite_frames.has_animation(anim)
		):
			if _sprite.animation != anim:
				_sprite.play(anim)

	# Flip sprite based on movement direction
	if _target_pos.x < _prev_pos.x:
		_sprite.flip_h = true
	elif _target_pos.x > _prev_pos.x:
		_sprite.flip_h = false


func _process(_delta: float) -> void:
	var t: float = Engine.get_physics_interpolation_fraction()
	global_position = _prev_pos.lerp(_target_pos, t)
	z_index = 200 + int(global_position.y / 2.0)
