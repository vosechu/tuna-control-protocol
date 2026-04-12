extends Node

var _db: GameStateDB
var _purr_player_1: AudioStreamPlayer
var _purr_player_2: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer
var _hum_reserve_ratio: int = 1000


func initialize(
		db: GameStateDB, events: RefCounted,
) -> void:
	_db = db
	_setup_audio_players()
	events.hum_reserve_changed.connect(
		_on_hum_reserve_changed,
	)


func register_cat(_entity_id: int) -> void:
	pass


func _setup_audio_players() -> void:
	var purr_stream_1: AudioStream = load(
		"res://mods/tcp_base/sounds/cat/purr_loop_01.wav"
	)
	var purr_stream_2: AudioStream = load(
		"res://mods/tcp_base/sounds/cat/purr_loop_02.wav"
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


func _on_hum_reserve_changed(
		_old: int, new_reserve: int,
) -> void:
	_hum_reserve_ratio = new_reserve


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
