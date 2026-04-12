extends Node2D

const _NAME_COLORS: Array[Color] = [
	Color.CORAL,       # Mochi
	Color.CYAN,        # Biscuit
	Color.YELLOW,      # Noodle
	Color.LIME_GREEN,  # Slinky
	Color.ORCHID,      # Bandit
]

const _STATE_TO_ANIM: Dictionary = {
	&"IDLE": &"idle",
	&"GROOMING": &"crouch",
	&"LOAFING": &"sit",
	&"SLEEPING": &"sleep",
	&"SNIFFING": &"sneak",
	&"SPEED_BUMP": &"liedown",
	&"SEEKING": &"walk",
	&"MOVING_TO": &"walk",
	&"WANDERING": &"walk",
	&"STARTLED": &"fright",
	&"SETTLING": &"sit",
}

static var _next_color: int = 0

var entity_id: int = Constants.INVALID_ID

var _db: GameStateDB
var _prev_pos: Vector2
var _target_pos: Vector2
var _is_ferret: bool = false
var _footstep_player: AudioStreamPlayer2D
var _color_index: int = 0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _name_label: Label = $NameLabel
@onready var _state_label: Label = $StateLabel
@onready var _purr_indicator: Label = $PurrIndicator


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
	_is_ferret = not String(species[&"id"]).contains("cat")
	_setup_sprite(species)
	_setup_name_label(species)
	if _is_ferret:
		_setup_footstep_audio()


func _setup_sprite(species: Dictionary) -> void:
	var variant: String = String(species.get(&"variant", &"cat01"))
	var base_path: String = ""
	var is_cat: bool = String(species[&"id"]).contains("cat")
	if is_cat:
		base_path = "res://mods/tcp_cats/sprites/%s" % variant
	else:
		base_path = "res://mods/tcp_ferrets/sprites/%s" % variant
	_sprite.scale = Vector2(2.0, 2.0)

	var idle_tex: Texture2D = load(base_path + "_idle_strip8.png")
	if idle_tex == null:
		push_error("Could not load idle sprite: %s" % (base_path + "_idle_strip8.png"))
		return

	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")

	# Load common animations
	_load_strip(frames, &"idle", base_path + "_idle_strip8.png", 8, 6.0)
	_load_strip(frames, &"walk", base_path + "_walk_strip8.png", 8, 8.0)
	_load_strip(frames, &"sit", base_path + "_sit_strip8.png", 8, 4.0)

	if is_cat:
		_load_strip(frames, &"sleep", base_path + "_sleep_strip8.png", 8, 2.0)
		_load_strip(frames, &"crouch", base_path + "_crouch_strip8.png", 8, 6.0)
		_load_strip(frames, &"fright", base_path + "_fright_strip8.png", 8, 8.0)
	else:
		_load_strip(frames, &"sleep", base_path + "_sleep_strip4.png", 4, 2.0)
		_load_strip(frames, &"sneak", base_path + "_sneak_strip4.png", 4, 6.0)
		_load_strip(frames, &"liedown", base_path + "_liedown_strip8.png", 8, 4.0)
		_load_strip(frames, &"dash", base_path + "_dash_strip10.png", 10, 10.0)

	_sprite.sprite_frames = frames
	_sprite.play(&"idle")


func _load_strip(
	frames: SpriteFrames,
	anim_name: StringName,
	path: String,
	frame_count: int,
	fps: float,
) -> void:
	var tex: Texture2D = load(path)
	if tex == null:
		return
	_add_strip_animation(frames, anim_name, tex, frame_count, fps)


func _setup_name_label(species: Dictionary) -> void:
	var animal_name: String = String(
		species.get(&"name", &"???")
	)
	_name_label.text = animal_name
	_color_index = _next_color % _NAME_COLORS.size()
	_next_color += 1
	_name_label.add_theme_color_override("font_color", _NAME_COLORS[_color_index])


func _setup_footstep_audio() -> void:
	var stream: AudioStream = load(
		"res://mods/tcp_base/sounds/objects/animal_footsteps_01.wav"
	)
	if stream == null:
		return
	_footstep_player = AudioStreamPlayer2D.new()
	_footstep_player.stream = stream
	_footstep_player.volume_db = -15.0
	_footstep_player.max_distance = 500.0
	add_child(_footstep_player)


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

	# Update animation and state label based on AI state
	if _db.has_component(entity_id, &"ai_state"):
		var ai: Dictionary = _db.get_component(entity_id, &"ai_state")
		var state: StringName = ai[&"state"]
		var anim: StringName = _state_to_animation(state)
		if _sprite.sprite_frames and _sprite.sprite_frames.has_animation(anim):
			if _sprite.animation != anim:
				_sprite.play(anim)
		_state_label.text = String(state).to_lower().replace("_", " ")

		# Ferret footstep audio — play when moving, restart when clip ends
		if _footstep_player:
			var is_moving: bool = (
				state == &"SEEKING" or state == &"MOVING_TO"
				or state == &"WANDERING"
			)
			if is_moving and not _footstep_player.playing:
				_footstep_player.play()
			elif not is_moving and _footstep_player.playing:
				_footstep_player.stop()

	# Flip sprite based on movement direction
	if _target_pos.x < _prev_pos.x:
		_sprite.flip_h = true
	elif _target_pos.x > _prev_pos.x:
		_sprite.flip_h = false

	# Visual purr indicator (accessibility: visual equivalent of purring sound)
	if _purr_indicator and _db.has_component(entity_id, &"desires"):
		var desires: Dictionary = _db.get_component(entity_id, &"desires")
		var ai_dict: Dictionary = _db.get_component(entity_id, &"ai_state")
		var current_state: StringName = ai_dict[&"state"]
		var is_purring: bool = (
			(current_state == &"LOAFING" or current_state == &"SLEEPING")
			and desires[&"warmth"] < 500
		)
		_purr_indicator.visible = is_purring


func _state_to_animation(state: StringName) -> StringName:
	return _STATE_TO_ANIM.get(state, &"idle")


func _process(_delta: float) -> void:
	var t: float = Engine.get_physics_interpolation_fraction()
	global_position = _prev_pos.lerp(_target_pos, t)
	z_index = 200 + int(global_position.y / 2.0)
