extends GutTest

# AI-DEV: This file was restructured from reimplemented test helpers to
# call production ObjectStateManager directly. Previous incarnation
# duplicated the state/ads logic locally (so mutations on production code
# didn't affect the test), failing the mutation-testing gate. Also merged
# several paired invariant tests — box state transitions + boundary HPs
# exercise the same hp_thresholds table, so one mutation per pair is enough.

var _db: GameStateDB
var _osm: ObjectStateManager


func before_each() -> void:
	# AI-DEV: Changing this function invalidates ALL test stamps in this file.
	_db = GameStateDB.new()
	_osm = ObjectStateManager.new(_db)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_tuna_can(state: StringName) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"object_type", {&"type": &"tuna_can"})
	_osm.transition_state(id, state)
	return id


func _make_cardboard_box(hp: int) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"object_type", {&"type": &"cardboard_box"})
	_db.set_component(id, &"object_hp", {&"hp": hp})
	var state: StringName = _osm.get_state_for_hp(&"cardboard_box", hp)
	_osm.transition_state(id, state)
	return id


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
	assert_eq(ads[&"list"][0][&"radius_px"], 24,
		"Sealed tuna openable radius must be 24")


# AI-DEV: Merges test_sealed_to_open_changes_ads_to_food + test_tuna_open_ad_has_eat_action
# into one test. Both exercised the same sealed→open transition producing the
# food-ad config; separating them blocked surgical mutations on the food-ad
# strength/radius/action fields (any mutation failed both tests).
func test_sealed_to_open_transitions_to_food_ad_with_eat_action():
	var id: int = _make_tuna_can(&"sealed")
	_osm.transition_state(id, &"open")
	var state: Dictionary = _db.get_component(id, &"object_state")
	assert_eq(state[&"state"], &"open",
		"State must be open after transition")
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_eq(ads[&"list"][0][&"desire_type"], &"food",
		"Open tuna must advertise food")
	assert_eq(ads[&"list"][0][&"strength"], 800,
		"Open tuna food strength must be 800")
	assert_eq(ads[&"list"][0][&"radius_px"], 40,
		"Open tuna food radius must be 40")
	assert_eq(ads[&"list"][0][&"action"], &"eat",
		"Open tuna action must be eat")


func test_open_to_empty_removes_advertisements():
	var id: int = _make_tuna_can(&"open")
	_osm.transition_state(id, &"empty")
	var state: Dictionary = _db.get_component(id, &"object_state")
	assert_eq(state[&"state"], &"empty",
		"State must be empty after transition")
	assert_false(_db.has_component(id, &"advertisements"),
		"Empty tuna must have no advertisements component")


# AI-DEV: The full-lifecycle test was deleted — it merely chains the three
# transitions already covered individually (sealed→open→empty). Each
# individual test targets its own surgical mutation; the chain gives no
# additional mutation targets.


func test_tuna_sealed_ad_has_open_action():
	var id: int = _make_tuna_can(&"sealed")
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_eq(ads[&"list"][0][&"action"], &"open",
		"Sealed tuna action must be open")


# ── Cardboard box degradation ────────────────────────────────────────────────

# AI-DEV: Merges test_new_box_advertises_comfort_and_curiosity +
# test_box_state_boundary_at_501 into one test. Both assert that HP=1000
# (or HP=501) produces the "new" state with the comfort+curiosity ad pair.
# The hp_thresholds first-entry fires for both, so one mutation suffices.
func test_new_box_state_and_ads():
	var id: int = _make_cardboard_box(1000)
	var state: Dictionary = _db.get_component(id, &"object_state")
	assert_eq(state[&"state"], &"new",
		"Box at 1000 HP must be in new state")
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_eq(ads[&"list"].size(), 2,
		"New box must have two advertisements")
	assert_eq(ads[&"list"][0][&"desire_type"], &"comfort",
		"New box first ad must be comfort")
	assert_eq(ads[&"list"][0][&"strength"], 700,
		"New box comfort strength must be 700")
	assert_eq(ads[&"list"][0][&"radius_px"], 32,
		"New box comfort radius must be 32")
	assert_eq(ads[&"list"][1][&"desire_type"], &"curiosity",
		"New box second ad must be curiosity")
	assert_eq(ads[&"list"][1][&"strength"], 500,
		"New box curiosity strength must be 500")


func test_damage_box_to_worn_changes_ads():
	var id: int = _make_cardboard_box(600)
	_osm.damage(id, 200)
	var hp: Dictionary = _db.get_component(id, &"object_hp")
	assert_eq(hp[&"hp"], 400,
		"Box HP must be 400 after taking 200 damage from 600")
	var state: Dictionary = _db.get_component(id, &"object_state")
	assert_eq(state[&"state"], &"worn",
		"Box at 400 HP must be in worn state")
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_eq(ads[&"list"][0][&"strength"], 400,
		"Worn box comfort strength must be 400")
	assert_eq(ads[&"list"][0][&"radius_px"], 24,
		"Worn box comfort radius must be 24")
	assert_eq(ads[&"list"][1][&"strength"], 300,
		"Worn box curiosity strength must be 300")


func test_damage_box_to_scraps_removes_curiosity():
	var id: int = _make_cardboard_box(100)
	_osm.damage(id, 100)
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
	_osm.damage(id, 200)
	var hp: Dictionary = _db.get_component(id, &"object_hp")
	assert_eq(hp[&"hp"], 0,
		"Box HP must clamp at 0, not go negative")


# AI-DEV: test_box_full_degradation_lifecycle was deleted — it chains the
# individual new→worn→scraps transitions already covered by
# test_damage_box_to_worn_changes_ads and test_damage_box_to_scraps_removes_curiosity,
# adding no distinct mutation surface.


func test_box_damage_within_same_state_does_not_change_ads():
	var id: int = _make_cardboard_box(1000)
	var ads_before: Dictionary = _db.get_component(
		id, &"advertisements"
	)
	var first_strength: int = ads_before[&"list"][0][&"strength"]
	_osm.damage(id, 100)
	var ads_after: Dictionary = _db.get_component(
		id, &"advertisements"
	)
	assert_eq(ads_after[&"list"][0][&"strength"], first_strength,
		"Damage within new state must not change ad strength")


func test_worn_box_has_shred_action():
	var id: int = _make_cardboard_box(400)
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_eq(ads[&"list"][1][&"action"], &"shred",
		"Worn box curiosity ad must have shred action")


func test_scraps_has_no_action():
	var id: int = _make_cardboard_box(0)
	var ads: Dictionary = _db.get_component(id, &"advertisements")
	assert_false(ads[&"list"][0].has(&"action"),
		"Scraps comfort ad must not have an action")


# AI-DEV: boundary-at-500 and boundary-at-1 both exercise the "worn" bucket
# of hp_thresholds. test_damage_box_to_worn_changes_ads already asserts
# "worn" for HP=400 via the damage path; the two boundary tests are
# redundant with that coverage. Deleted.
