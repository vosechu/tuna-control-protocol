extends GutTest

var _db: GameStateDB


func before_each() -> void:
	_db = GameStateDB.new()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_tuna_can(state: StringName) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"object_type", {&"type": &"tuna_can"})
	_db.set_component(id, &"object_state", {&"state": state})
	_update_ads_for_tuna(id, state)
	return id


func _make_cardboard_box(hp: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"object_type", {&"type": &"cardboard_box"})
	_db.set_component(id, &"object_hp", {&"hp": hp})
	var state: StringName = _box_state_for_hp(hp)
	_db.set_component(id, &"object_state", {&"state": state})
	_update_ads_for_box(id, state)
	return id


# NOTE: These helpers reimplement transition_object_state, damage_object,
# and _box_state_for_hp from game_server.gd because GameServer requires a
# scene tree. If the production methods change, these must be updated.
func _transition_object(entity_id: int, new_state: StringName) -> void:
	var obj_type: Dictionary = _db.get_component(
		entity_id, &"object_type"
	)
	_db.set_component(
		entity_id, &"object_state", {&"state": new_state}
	)
	match obj_type[&"type"]:
		&"tuna_can":
			_update_ads_for_tuna(entity_id, new_state)
		&"cardboard_box":
			_update_ads_for_box(entity_id, new_state)


func _damage_object(entity_id: int, amount: int) -> void:
	var hp_data: Dictionary = _db.get_component(
		entity_id, &"object_hp"
	)
	var new_hp: int = maxi(0, hp_data[&"hp"] - amount)
	_db.set_component(entity_id, &"object_hp", {&"hp": new_hp})
	var new_state: StringName = _box_state_for_hp(new_hp)
	var old_state: Dictionary = _db.get_component(
		entity_id, &"object_state"
	)
	if new_state != old_state[&"state"]:
		_transition_object(entity_id, new_state)


func _update_ads_for_tuna(
	entity_id: int, state: StringName
) -> void:
	match state:
		&"sealed":
			_db.set_component(entity_id, &"advertisements", {
				&"list": [{
					&"desire_type": &"openable",
					&"strength": 800,
					&"radius_ru": 3,
					&"action": &"open",
					&"action_duration": 30,
				}],
			})
		&"open":
			_db.set_component(entity_id, &"advertisements", {
				&"list": [{
					&"desire_type": &"food",
					&"strength": 800,
					&"radius_ru": 5,
					&"action": &"eat",
					&"action_duration": 50,
				}],
			})
		&"empty":
			_db.remove_component(entity_id, &"advertisements")


func _update_ads_for_box(
	entity_id: int, state: StringName
) -> void:
	match state:
		&"new":
			_db.set_component(entity_id, &"advertisements", {
				&"list": [
					{
						&"desire_type": &"comfort",
						&"strength": 700,
						&"radius_ru": 4,
					},
					{
						&"desire_type": &"curiosity",
						&"strength": 500,
						&"radius_ru": 5,
						&"action": &"shred",
						&"action_duration": 20,
					},
				],
			})
		&"worn":
			_db.set_component(entity_id, &"advertisements", {
				&"list": [
					{
						&"desire_type": &"comfort",
						&"strength": 400,
						&"radius_ru": 3,
					},
					{
						&"desire_type": &"curiosity",
						&"strength": 300,
						&"radius_ru": 4,
						&"action": &"shred",
						&"action_duration": 20,
					},
				],
			})
		&"scraps":
			_db.set_component(entity_id, &"advertisements", {
				&"list": [{
					&"desire_type": &"comfort",
					&"strength": 600,
					&"radius_ru": 3,
				}],
			})


func _box_state_for_hp(hp: int) -> StringName:
	if hp <= 0:
		return &"scraps"
	if hp <= 500:
		return &"worn"
	return &"new"


# ── Tuna can state transitions ───────────────────────────────────────────────

func test_sealed_tuna_advertises_openable():
	var id: int = _make_tuna_can(&"sealed")
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_eq(ads[&"list"].size(), 1,
		"Sealed tuna must have exactly one advertisement")
	assert_eq(ads[&"list"][0][&"desire_type"], &"openable",
		"Sealed tuna must advertise openable")
	assert_eq(ads[&"list"][0][&"strength"], 800,
		"Sealed tuna openable strength must be 800")
	assert_eq(ads[&"list"][0][&"radius_ru"], 3,
		"Sealed tuna openable radius must be 3")


func test_sealed_to_open_changes_ads_to_food():
	var id: int = _make_tuna_can(&"sealed")
	_transition_object(id, &"open")
	var state: Dictionary = _db.get_component(id, &"object_state")
	assert_eq(state[&"state"], &"open",
		"State must be open after transition")
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_eq(ads[&"list"][0][&"desire_type"], &"food",
		"Open tuna must advertise food")
	assert_eq(ads[&"list"][0][&"strength"], 800,
		"Open tuna food strength must be 800")
	assert_eq(ads[&"list"][0][&"radius_ru"], 5,
		"Open tuna food radius must be 5")


func test_open_to_empty_removes_advertisements():
	var id: int = _make_tuna_can(&"open")
	_transition_object(id, &"empty")
	var state: Dictionary = _db.get_component(id, &"object_state")
	assert_eq(state[&"state"], &"empty",
		"State must be empty after transition")
	assert_false(_db.has_component(id, &"advertisements"),
		"Empty tuna must have no advertisements component")


func test_sealed_to_open_to_empty_full_lifecycle():
	var id: int = _make_tuna_can(&"sealed")
	assert_true(_db.has_component(id, &"advertisements"),
		"Sealed tuna must have advertisements")
	_transition_object(id, &"open")
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_eq(ads[&"list"][0][&"desire_type"], &"food",
		"Open tuna must advertise food")
	_transition_object(id, &"empty")
	assert_false(_db.has_component(id, &"advertisements"),
		"Empty tuna must have no advertisements")


func test_tuna_open_ad_has_eat_action():
	var id: int = _make_tuna_can(&"open")
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_eq(ads[&"list"][0][&"action"], &"eat",
		"Open tuna action must be eat")
	assert_eq(ads[&"list"][0][&"action_duration"], 50,
		"Open tuna action_duration must be 50 (5.0 sec)")


func test_tuna_sealed_ad_has_open_action():
	var id: int = _make_tuna_can(&"sealed")
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_eq(ads[&"list"][0][&"action"], &"open",
		"Sealed tuna action must be open")
	assert_eq(ads[&"list"][0][&"action_duration"], 30,
		"Sealed tuna action_duration must be 30 (3.0 sec)")


# ── Cardboard box degradation ────────────────────────────────────────────────

func test_new_box_advertises_comfort_and_curiosity():
	var id: int = _make_cardboard_box(1000)
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_eq(ads[&"list"].size(), 2,
		"New box must have two advertisements")
	assert_eq(ads[&"list"][0][&"desire_type"], &"comfort",
		"New box first ad must be comfort")
	assert_eq(ads[&"list"][0][&"strength"], 700,
		"New box comfort strength must be 700")
	assert_eq(ads[&"list"][0][&"radius_ru"], 4,
		"New box comfort radius must be 4")
	assert_eq(ads[&"list"][1][&"desire_type"], &"curiosity",
		"New box second ad must be curiosity")
	assert_eq(ads[&"list"][1][&"strength"], 500,
		"New box curiosity strength must be 500")


func test_damage_box_to_worn_changes_ads():
	var id: int = _make_cardboard_box(600)
	_damage_object(id, 200)
	var hp: Dictionary = _db.get_component(id, &"object_hp")
	assert_eq(hp[&"hp"], 400,
		"Box HP must be 400 after taking 200 damage from 600")
	var state: Dictionary = _db.get_component(id, &"object_state")
	assert_eq(state[&"state"], &"worn",
		"Box at 400 HP must be in worn state")
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_eq(ads[&"list"][0][&"strength"], 400,
		"Worn box comfort strength must be 400")
	assert_eq(ads[&"list"][0][&"radius_ru"], 3,
		"Worn box comfort radius must be 3")
	assert_eq(ads[&"list"][1][&"strength"], 300,
		"Worn box curiosity strength must be 300")


func test_damage_box_to_scraps_removes_curiosity():
	var id: int = _make_cardboard_box(100)
	_damage_object(id, 100)
	var hp: Dictionary = _db.get_component(id, &"object_hp")
	assert_eq(hp[&"hp"], 0,
		"Box HP must be 0 after taking all remaining damage")
	var state: Dictionary = _db.get_component(id, &"object_state")
	assert_eq(state[&"state"], &"scraps",
		"Box at 0 HP must be in scraps state")
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_eq(ads[&"list"].size(), 1,
		"Scraps must have only one advertisement")
	assert_eq(ads[&"list"][0][&"desire_type"], &"comfort",
		"Scraps must only advertise comfort")
	assert_eq(ads[&"list"][0][&"strength"], 600,
		"Scraps comfort strength must be 600")


func test_box_hp_does_not_go_below_zero():
	var id: int = _make_cardboard_box(50)
	_damage_object(id, 200)
	var hp: Dictionary = _db.get_component(id, &"object_hp")
	assert_eq(hp[&"hp"], 0,
		"Box HP must clamp at 0, not go negative")


func test_box_full_degradation_lifecycle():
	var id: int = _make_cardboard_box(1000)
	var state: Dictionary = _db.get_component(id, &"object_state")
	assert_eq(state[&"state"], &"new",
		"Box at 1000 HP must start as new")

	_damage_object(id, 500)
	state = _db.get_component(id, &"object_state")
	assert_eq(state[&"state"], &"worn",
		"Box at 500 HP must be worn")

	_damage_object(id, 500)
	state = _db.get_component(id, &"object_state")
	assert_eq(state[&"state"], &"scraps",
		"Box at 0 HP must be scraps")


func test_box_damage_within_same_state_does_not_change_ads():
	var id: int = _make_cardboard_box(1000)
	var ads_before: Dictionary = _db.get_component(
		id, &"advertisements"
	)
	_damage_object(id, 100)
	var ads_after: Dictionary = _db.get_component(
		id, &"advertisements"
	)
	assert_eq(ads_after[&"list"][0][&"strength"],
		ads_before[&"list"][0][&"strength"],
		"Damage within new state must not change ad strength")


func test_worn_box_has_shred_action():
	var id: int = _make_cardboard_box(400)
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_eq(ads[&"list"][1][&"action"], &"shred",
		"Worn box curiosity ad must have shred action")
	assert_eq(ads[&"list"][1][&"action_duration"], 20,
		"Worn box shred action_duration must be 20 (2.0 sec)")


func test_scraps_has_no_action():
	var id: int = _make_cardboard_box(0)
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_false(ads[&"list"][0].has(&"action"),
		"Scraps comfort ad must not have an action")


func test_box_state_boundary_at_501():
	var id: int = _make_cardboard_box(501)
	var state: Dictionary = _db.get_component(id, &"object_state")
	assert_eq(state[&"state"], &"new",
		"Box at 501 HP must be in new state")


func test_box_state_boundary_at_500():
	var id: int = _make_cardboard_box(500)
	var state: Dictionary = _db.get_component(id, &"object_state")
	assert_eq(state[&"state"], &"worn",
		"Box at 500 HP must be in worn state")


func test_box_state_boundary_at_1():
	var id: int = _make_cardboard_box(1)
	var state: Dictionary = _db.get_component(id, &"object_state")
	assert_eq(state[&"state"], &"worn",
		"Box at 1 HP must be in worn state")
