class_name ObjectStateManager extends RefCounted

# Generic object state management: state transitions, damage, and
# state-driven advertisement updates.  Config data lives here as a
# Dictionary constant for now — will move to JSON via ConfigRegistry later.

const OBJECT_CONFIG: Dictionary = {
	&"tuna_can": {
		&"state_ads": {
			&"sealed": [{
				&"desire_type": &"openable", &"strength": 800,
				&"radius_ru": 3, &"action": &"open", &"action_duration": 30,
			}],
			&"open": [{
				&"desire_type": &"food", &"strength": 800,
				&"radius_ru": 5, &"action": &"eat", &"action_duration": 50,
			}],
			&"empty": [],
		},
	},
	&"cardboard_box": {
		&"state_ads": {
			&"new": [
				{&"desire_type": &"comfort", &"strength": 700, &"radius_ru": 4},
				{&"desire_type": &"curiosity", &"strength": 500,
					&"radius_ru": 5, &"action": &"shred", &"action_duration": 20},
			],
			&"worn": [
				{&"desire_type": &"comfort", &"strength": 400, &"radius_ru": 3},
				{&"desire_type": &"curiosity", &"strength": 300,
					&"radius_ru": 4, &"action": &"shred", &"action_duration": 20},
			],
			&"scraps": [
				{&"desire_type": &"comfort", &"strength": 600, &"radius_ru": 3},
			],
		},
		&"hp_thresholds": [
			{&"min_hp": 501, &"state": &"new"},
			{&"min_hp": 1, &"state": &"worn"},
			{&"min_hp": 0, &"state": &"scraps"},
		],
	},
}

var _db: GameStateDB


func _init(db: GameStateDB) -> void:
	_db = db


# Transition an object to a new state and update its advertisements
# based on the state→ads mapping in config.
func transition_state(entity_id: int, new_state: StringName) -> void:
	if not _db.has_entity(entity_id):
		assert(false, "transition_state: unknown entity %d" % entity_id)
		return
	if not _db.has_component(entity_id, &"object_type"):
		assert(false, "transition_state: no object_type on %d" % entity_id)
		return
	_db.set_component(entity_id, &"object_state", {&"state": new_state})
	var obj_type: Dictionary = _db.get_component(entity_id, &"object_type")
	var type_name: StringName = obj_type[&"type"]
	var ads: Array = get_ads_for_state(type_name, new_state)
	if ads.is_empty():
		if _db.has_component(entity_id, &"advertisements"):
			_db.remove_component(entity_id, &"advertisements")
	else:
		_db.set_component(entity_id, &"advertisements", {&"list": ads})


# Reduce HP by amount, then check HP→state thresholds and transition
# if the state changed.  Object types without hp_thresholds are rejected
# via assert.
func damage(entity_id: int, amount: int) -> void:
	if not _db.has_entity(entity_id):
		assert(false, "damage: unknown entity %d" % entity_id)
		return
	if not _db.has_component(entity_id, &"object_hp"):
		assert(false, "damage: no object_hp on %d" % entity_id)
		return
	var hp_comp: Dictionary = _db.get_component(entity_id, &"object_hp")
	var new_hp: int = maxi(0, hp_comp[&"hp"] - amount)
	_db.set_component(entity_id, &"object_hp", {&"hp": new_hp})

	var obj_type: Dictionary = _db.get_component(entity_id, &"object_type")
	var type_name: StringName = obj_type[&"type"]
	var new_state: StringName = get_state_for_hp(type_name, new_hp)
	if new_state == &"":
		return
	var old: Dictionary = _db.get_component(entity_id, &"object_state")
	if new_state != old[&"state"]:
		transition_state(entity_id, new_state)


# Generic HP→state lookup.  Returns the first threshold whose min_hp
# is <= the given hp.  Returns empty StringName if the object type has
# no hp_thresholds config.
func get_state_for_hp(object_type: StringName, hp: int) -> StringName:
	if not OBJECT_CONFIG.has(object_type):
		return &""
	var cfg: Dictionary = OBJECT_CONFIG[object_type]
	if not cfg.has(&"hp_thresholds"):
		return &""
	var thresholds: Array = cfg[&"hp_thresholds"]
	for entry: Dictionary in thresholds:
		if hp >= entry[&"min_hp"]:
			return entry[&"state"]
	return &""


# Generic state→ads lookup.  Returns the ad list for the given state,
# or an empty array if the object type or state is unknown.
func get_ads_for_state(object_type: StringName, state: StringName) -> Array:
	if not OBJECT_CONFIG.has(object_type):
		return []
	var cfg: Dictionary = OBJECT_CONFIG[object_type]
	if not cfg.has(&"state_ads"):
		return []
	var state_ads: Dictionary = cfg[&"state_ads"]
	if not state_ads.has(state):
		return []
	return state_ads[state]
