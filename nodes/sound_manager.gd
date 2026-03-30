extends Node

var _db: GameStateDB
var _purr_player_1: AudioStreamPlayer
var _purr_player_2: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer
var _purring_count: int = 0
var _total_cats: int = 0
var _cat_entity_ids: Array[int] = []


func initialize(db: GameStateDB) -> void:
	_db = db
	_setup_audio_players()
	# Register watchers for purr state changes
	_db.watch(&"ai_state", _on_state_or_desire_changed)
	_db.watch(&"desires", _on_state_or_desire_changed)


func register_cat(entity_id: int) -> void:
	if entity_id not in _cat_entity_ids:
		_cat_entity_ids.append(entity_id)
		_total_cats = _cat_entity_ids.size()
		_recount_purring()


func _setup_audio_players() -> void:
	# Purr loop 1
	_purr_player_1 = AudioStreamPlayer.new()
	var purr_stream_1: AudioStream = load(
		"res://mods/tcp_base/sounds/cat/purr_loop_01.wav"
	)
	if purr_stream_1:
		# Enable looping on the WAV stream
		if purr_stream_1 is AudioStreamWAV:
			var wav_1: AudioStreamWAV = purr_stream_1 as AudioStreamWAV
			wav_1.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav_1.loop_end = -1
		_purr_player_1.stream = purr_stream_1
		_purr_player_1.volume_db = -40.0
		_purr_player_1.pitch_scale = 0.95
		_purr_player_1.autoplay = true
	add_child(_purr_player_1)

	# Purr loop 2 — slight pitch offset for organic layering
	_purr_player_2 = AudioStreamPlayer.new()
	var purr_stream_2: AudioStream = load(
		"res://mods/tcp_base/sounds/cat/purr_loop_02.wav"
	)
	if purr_stream_2:
		if purr_stream_2 is AudioStreamWAV:
			var wav_2: AudioStreamWAV = purr_stream_2 as AudioStreamWAV
			wav_2.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav_2.loop_end = -1
		_purr_player_2.stream = purr_stream_2
		_purr_player_2.volume_db = -40.0
		_purr_player_2.pitch_scale = 1.05
		_purr_player_2.autoplay = true
	add_child(_purr_player_2)

	# Ambient datacenter hum — always on at low volume
	# Placeholder: use purr at very low pitch as a rumble until we have a
	# proper datacenter_hum_loop asset
	_ambient_player = AudioStreamPlayer.new()
	if purr_stream_1:
		# Duplicate so loop settings don't conflict with purr player
		var ambient_stream: AudioStream = purr_stream_1.duplicate()
		if ambient_stream is AudioStreamWAV:
			var wav_amb: AudioStreamWAV = ambient_stream as AudioStreamWAV
			wav_amb.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav_amb.loop_end = -1
		_ambient_player.stream = ambient_stream
		_ambient_player.volume_db = -35.0
		_ambient_player.pitch_scale = 0.3  # Very low rumble
		_ambient_player.autoplay = true
	add_child(_ambient_player)


func _on_state_or_desire_changed(_entity_id: int) -> void:
	_recount_purring()


func _recount_purring() -> void:
	_purring_count = 0
	for entity_id: int in _cat_entity_ids:
		if not _db.has_entity(entity_id):
			continue
		if not _db.has_component(entity_id, &"ai_state"):
			continue
		if not _db.has_component(entity_id, &"desires"):
			continue
		var ai: Dictionary = _db.get_component(entity_id, &"ai_state")
		var desires: Dictionary = _db.get_component(entity_id, &"desires")
		var state: StringName = ai[&"state"]
		# Cat purrs when in a content ambient state AND warm enough
		# warmth desire: 0 = satisfied, 1000 = desperate
		var is_content_state: bool = (
			state == &"LOAFING" or state == &"SLEEPING"
		)
		var is_warm: bool = desires[&"warmth"] < 500
		if is_content_state and is_warm:
			_purring_count += 1


func _process(_delta: float) -> void:
	if _total_cats == 0:
		return

	# Target volume based on purring ratio
	var target_db: float = -40.0  # silence floor
	if _purring_count > 0:
		var ratio: float = float(_purring_count) / float(_total_cats)
		# Scale from -20dB (one cat) to -6dB (all cats purring)
		target_db = lerpf(-20.0, -6.0, ratio)

	# Asymmetric smoothing: faster ramp-up (0.08), slower decay (0.03)
	var smooth: float = 0.08 if target_db > _purr_player_1.volume_db else 0.03
	_purr_player_1.volume_db = lerpf(
		_purr_player_1.volume_db, target_db, smooth
	)
	_purr_player_2.volume_db = lerpf(
		_purr_player_2.volume_db, target_db - 3.0, smooth
	)
