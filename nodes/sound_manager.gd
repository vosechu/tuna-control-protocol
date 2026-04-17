extends Node

var _db: GameStateDB
var _entity_defs: EntityDefRegistry
var _purr_player_1: AudioStreamPlayer
var _purr_player_2: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer
var _pacing_players: Dictionary = {}  # species_id -> AudioStreamPlayer (or null)
var _squeak_player: AudioStreamPlayer
var _can_pop_player: AudioStreamPlayer
var _button_click_player: AudioStreamPlayer
var _hum_reserve_ratio: int = 1000


func initialize(
		db: GameStateDB, events: Object,
		entity_defs: EntityDefRegistry,
) -> void:
	_db = db
	_entity_defs = entity_defs
	_setup_audio_players()
	_setup_event_players()
	events.hum_reserve_changed.connect(
		_on_hum_reserve_changed,
	)
	events.creature_started_pacing.connect(
		_on_creature_started_pacing,
	)
	events.food_dispensed.connect(_on_food_dispensed)
	events.can_opened.connect(_on_can_opened)
	events.box_squeaked.connect(_on_box_squeaked)


func _setup_audio_players() -> void:
	var purr_stream_1: AudioStream = load(
		"res://mods/tcp_cats/sounds/purr_loop_01.wav"
	)
	var purr_stream_2: AudioStream = load(
		"res://mods/tcp_cats/sounds/purr_loop_02.wav"
	)

	_set_loop(purr_stream_1)
	_set_loop(purr_stream_2)

	_purr_player_1 = AudioStreamPlayer.new()
	_purr_player_1.stream = purr_stream_1
	_purr_player_1.volume_db = -40.0
	_purr_player_1.pitch_scale = 0.95
	add_child(_purr_player_1)
	_purr_player_1.play()

	_purr_player_2 = AudioStreamPlayer.new()
	_purr_player_2.stream = purr_stream_2
	_purr_player_2.volume_db = -40.0
	_purr_player_2.pitch_scale = 1.05
	add_child(_purr_player_2)
	_purr_player_2.play()

	_ambient_player = AudioStreamPlayer.new()
	if purr_stream_1:
		var ambient_stream: AudioStream = (
			purr_stream_1.duplicate()
		)
		_set_loop(ambient_stream)
		_ambient_player.stream = ambient_stream
		_ambient_player.volume_db = -30.0
		_ambient_player.pitch_scale = 0.3
	add_child(_ambient_player)
	_ambient_player.play()


func _set_loop(stream: AudioStream) -> void:
	if stream == null:
		return
	if stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = -1


func _setup_event_players() -> void:
	_squeak_player = _make_player(
		"res://mods/tcp_base/sounds/objects/squeak_toy_01.wav",
		-10.0,
	)
	_can_pop_player = _make_player(
		"res://mods/tcp_base/sounds/objects/can_pop_01.wav",
		-12.0,
	)
	_button_click_player = _make_player(
		"res://mods/tcp_base/sounds/objects/button_click_01.wav",
		-10.0,
	)


func _make_player(
		path: String, volume: float,
) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume
	add_child(player)
	return player


func _on_creature_started_pacing(animal_id: int) -> void:
	if not _db.has_component(animal_id, &"species"):
		return
	var species: Dictionary = _db.get_component(animal_id, &"species")
	var species_id: StringName = species.get(&"id", &"")
	if species_id == &"":
		return
	var player: AudioStreamPlayer = _get_pacing_player(species_id)
	if player and not player.playing:
		player.play()


func _get_pacing_player(species_id: StringName) -> AudioStreamPlayer:
	if _pacing_players.has(species_id):
		return _pacing_players[species_id]
	var player: AudioStreamPlayer = _load_pacing_player(species_id)
	_pacing_players[species_id] = player
	return player


func _load_pacing_player(species_id: StringName) -> AudioStreamPlayer:
	if _entity_defs == null or not _entity_defs.has_entity(species_id):
		return null
	var def: Dictionary = _entity_defs.get_definition(species_id)
	var sounds: Dictionary = def.get("sounds", {})
	var pacing_list: Array = sounds.get("pacing", [])
	if pacing_list.is_empty():
		return null
	var mod_id: String = String(species_id).split(":")[0]
	var filename: String = String(pacing_list[0])
	var path: String = "res://mods/%s/sounds/%s" % [mod_id, filename]
	return _make_player(path, -15.0)


func _on_food_dispensed(_can_id: int) -> void:
	if _button_click_player:
		_button_click_player.play()


func _on_can_opened(_can_id: int) -> void:
	if _can_pop_player:
		_can_pop_player.play()


func _on_box_squeaked(_box_id: int) -> void:
	if _squeak_player:
		_squeak_player.play()


func _on_hum_reserve_changed(
		_old: int, new_reserve: int,
) -> void:
	_hum_reserve_ratio = new_reserve * 1000 / HumSystem.DEFAULT_CAPACITY


func _process(_delta: float) -> void:
	# Purr volume tracks HUM reserve, not individual cats
	var target_db: float = -40.0
	if _hum_reserve_ratio > 0:
		var ratio_f: float = (
			float(_hum_reserve_ratio) / 1000.0
		)
		target_db = lerpf(-25.0, -6.0, ratio_f)

	var smooth: float = (
		0.08
		if target_db > _purr_player_1.volume_db
		else 0.03
	)
	_purr_player_1.volume_db = lerpf(
		_purr_player_1.volume_db, target_db, smooth,
	)
	_purr_player_2.volume_db = lerpf(
		_purr_player_2.volume_db, target_db - 3.0, smooth,
	)

	# Ambient hum: cut at brownout (<25%)
	var ambient_target: float = -40.0
	if _hum_reserve_ratio > 250:
		ambient_target = -30.0
	_ambient_player.volume_db = lerpf(
		_ambient_player.volume_db, ambient_target, 0.02,
	)

	if not _purr_player_1.playing and _purr_player_1.stream:
		_purr_player_1.play()
	if not _purr_player_2.playing and _purr_player_2.stream:
		_purr_player_2.play()
	if not _ambient_player.playing and _ambient_player.stream:
		_ambient_player.play()
