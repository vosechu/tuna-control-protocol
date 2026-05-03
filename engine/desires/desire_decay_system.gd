class_name DesireDecaySystem extends RefCounted

# Per-species desire decay. Reads each entity's `desire_decay` component
# (populated from the recipe by EntityDefRegistry) and applies the per-
# channel decay to that entity's `desires` via batched add_field_subset.
#
# The system never branches on species labels — it iterates entities that
# have a `desire_decay` component and trusts the recipe to declare what
# decays. Adding a new species is a recipe change, not a code change.

var _db: GameStateDB


func _init(db: GameStateDB) -> void:
	_db = db


func tick() -> void:
	var entities: Array[int] = _db.get_entities_with(&"desire_decay")
	if entities.is_empty():
		return
	# Bucket per channel so each channel's mutation is one db call instead
	# of N (one per entity). Channel keys are unknown ahead of time —
	# they're whatever recipes declare.
	var deltas_by_channel: Dictionary = {}
	for entity_id: int in entities:
		var decay: Dictionary = _db.get_component(entity_id, &"desire_decay")
		for channel: StringName in decay:
			var delta: int = decay[channel]
			if delta == 0:
				continue
			if not deltas_by_channel.has(channel):
				deltas_by_channel[channel] = {}
			deltas_by_channel[channel][entity_id] = delta
	for channel: StringName in deltas_by_channel:
		_db.add_field_subset(&"desires", channel, deltas_by_channel[channel])
