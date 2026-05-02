extends GutTest

const EventsScript: GDScript = preload(
	"res://nodes/events.gd"
)

var db: GameStateDB
var events: Object
var hum: HumSystem
var food: FoodSystem
var hum_id: int = -1


func before_each() -> void:
	db = GameStateDB.new()
	events = EventsScript.new()
	hum = HumSystem.new(db, events)
	food = FoodSystem.new(db, hum, events)
	# Spawn a HUM entity so _pick_hum_for shim can find a battery
	hum_id = _make_hum_entity()


func test_press_button_dispenses_can_when_hum_available():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Press happy-path unit proof. Surgical within-suite mutation: change the
	# final `return can_id` in press_button to `return Constants.INVALID_ID`.
	# Other press_button tests already expect INVALID_ID under their
	# respective failure branches; they stay green.
	var dispenser_id: int = _make_dispenser(1, 5)
	var button_id: int = _make_button(1, 6, dispenser_id)

	var result: int = food.press_button(button_id)
	assert_ne(result, Constants.INVALID_ID,
		"Pressing button with HUM should create a tuna can")
	assert_true(db.has_component(result, &"tuna_can"),
		"Created entity should have tuna_can component")


func test_press_button_fails_without_hum():
	var dispenser_id: int = _make_dispenser(1, 5)
	var button_id: int = _make_button(1, 6, dispenser_id)
	hum.drain_action(hum_id, hum.get_reserve(hum_id))

	var result: int = food.press_button(button_id)
	assert_eq(result, Constants.INVALID_ID,
		"Pressing button without HUM should fail")


func test_press_button_drains_hum():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Press drain unit proof. Surgical within-suite mutation: comment out
	# the `_hum.drain_action(hum_id, cost)` line in press_button. The
	# dispense test still passes (entity still created), rack/no-HUM tests
	# bail before drain, arm tests don't touch press_button.
	var dispenser_id: int = _make_dispenser(1, 5)
	var button_id: int = _make_button(1, 6, dispenser_id)
	var before: int = hum.get_reserve(hum_id)
	food.press_button(button_id)
	var after: int = hum.get_reserve(hum_id)
	assert_lt(after, before,
		"Dispensing should drain HUM")


func test_button_must_be_in_same_rack_as_dispenser():
	var dispenser_id: int = _make_dispenser(1, 5)
	var button_id: int = _make_button(3, 6, dispenser_id)

	var result: int = food.press_button(button_id)
	assert_eq(result, Constants.INVALID_ID,
		"Button in different rack should not work")


func test_arm_opens_nearby_sealed_can():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Arm happy-path unit proof. Surgical within-suite mutation: change the
	# post-open state assignment `updated[&"state"] = &"opened"` to
	# `&"broken"`. The advertises-food test still passes (advertisements
	# set_component happens regardless); ignore-distant and requires-hum
	# tests expect state==sealed and still pass.
	_make_arm(1)
	var can_id: int = _make_sealed_can(1)

	food.tick_arms()
	var can: Dictionary = db.get_component(can_id, &"tuna_can")
	assert_eq(can[&"state"], &"opened",
		"ARM should open sealed can within radius")


func test_arm_ignores_distant_can():
	_make_arm(1)
	var can_id: int = _make_sealed_can(4)

	food.tick_arms()
	var can: Dictionary = db.get_component(can_id, &"tuna_can")
	assert_eq(can[&"state"], &"sealed",
		"ARM should not open can outside radius")


func test_arm_requires_hum_to_open():
	_make_arm(1)
	var can_id: int = _make_sealed_can(1)
	hum.drain_action(hum_id, hum.get_reserve(hum_id))

	food.tick_arms()
	var can: Dictionary = db.get_component(can_id, &"tuna_can")
	assert_eq(can[&"state"], &"sealed",
		"ARM without HUM should not open cans")


func test_opened_can_advertises_food():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Advertisements unit proof. Surgical within-suite mutation: skip the
	# `set_component(entity_id, &"advertisements", …)` call after opening.
	# The arm-opens-nearby test still passes (state still set to opened);
	# other arm tests don't check advertisements.
	_make_arm(1)
	var can_id: int = _make_sealed_can(1)
	food.tick_arms()
	assert_true(db.has_component(can_id, &"advertisements"),
		"Opened can should have food advertisements")
	var ads: Dictionary = db.get_component(can_id, &"advertisements")
	var has_hunger_ad: bool = false
	for ad: Dictionary in ads[&"list"]:
		if ad[&"desire_type"] == &"hunger":
			has_hunger_ad = true
	assert_true(has_hunger_ad,
		"Opened can should advertise hunger satisfaction")


func test_eaten_can_despawns_after_delay():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Cleanup unit proof. Surgical within-suite mutation: comment out the
	# `_db.destroy_entity(can_id)` call in tick_cleanup. No other unit test
	# calls tick_cleanup — the cleanup loop is unique to this test.
	_make_arm(1)
	var can_id: int = _make_sealed_can(1)
	food.tick_arms()
	var can_data: Dictionary = db.get_component(can_id, &"tuna_can")
	can_data[&"state"] = &"eaten"
	db.set_component(can_id, &"tuna_can", can_data)
	for _i: int in 100:
		food.tick_cleanup()
	assert_false(db.has_entity(can_id),
		"Eaten can should despawn after delay")


func test_opened_can_hunger_ad_has_correct_shape():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Hunger ad numeric pin. Surgical within-suite mutation: change any of
	# `strength: 900`, `radius_px: 48`, or `max_occupants: 1` in tick_arms's
	# advertisements set_component. test_opened_can_advertises_food only
	# asserts the desire_type, so numeric drift on those three fields is
	# invisible without this test.
	_make_arm(1)
	var can_id: int = _make_sealed_can(1)
	food.tick_arms()
	var ads: Dictionary = db.get_component(can_id, &"advertisements")
	var hunger_ad: Dictionary = {}
	for ad: Dictionary in ads[&"list"]:
		if ad[&"desire_type"] == &"hunger":
			hunger_ad = ad
	assert_eq(hunger_ad[&"strength"], 900,
		"Hunger ad strength should be 900")
	assert_eq(hunger_ad[&"radius_px"], 48,
		"Hunger ad radius_px should be 48")
	assert_eq(hunger_ad[&"max_occupants"], 1,
		"Hunger ad max_occupants should be 1")


func test_each_arm_opens_its_own_racks_can():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Multi-arm outer-loop coverage. Surgical within-suite mutation: add
	# `break` after the body of `for arm_id in arms:` in tick_arms so only the
	# first arm runs. Single-arm tests still pass (only one arm to iterate),
	# so without this test the regression slips through.
	_make_arm(1)
	_make_arm(3)
	var can_rack1: int = _make_sealed_can(1)
	var can_rack3: int = _make_sealed_can(3)
	food.tick_arms()
	var can1: Dictionary = db.get_component(can_rack1, &"tuna_can")
	var can3: Dictionary = db.get_component(can_rack3, &"tuna_can")
	assert_eq(can1[&"state"], &"opened",
		"Arm in rack 1 should open the can in rack 1")
	assert_eq(can3[&"state"], &"opened",
		"Arm in rack 3 should open the can in rack 3")


func test_arm_opens_multiple_cans_in_radius_per_tick():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Inner-loop coverage. Surgical within-suite mutation: add `break` after
	# the inner-loop set_component(entity_id, &"tuna_can", updated) call so
	# the arm only opens one can per tick. test_arm_opens_nearby_sealed_can
	# still passes (it only checks the first can), so this is the only proof
	# the inner loop iterates.
	_make_arm(1)
	var can_a: int = _make_sealed_can(1)
	var can_b: int = _make_sealed_can(1)
	food.tick_arms()
	var ca: Dictionary = db.get_component(can_a, &"tuna_can")
	var cb: Dictionary = db.get_component(can_b, &"tuna_can")
	assert_eq(ca[&"state"], &"opened",
		"First sealed can in radius should be opened")
	assert_eq(cb[&"state"], &"opened",
		"Second sealed can in radius should be opened in same tick")


func test_arm_stops_opening_when_hum_runs_out_mid_tick():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Mid-tick HUM exhaustion guard. Arm cost is 30; reserve seeded to 65
	# funds two opens (drains to 35, then to 5). Surgical within-suite
	# mutation: remove the per-can `if not _hum.has_reserve(arm_hum_id, cost):
	# break` inside tick_arms's inner loop. drain_action floors at 0, so
	# without the guard all three cans open. The outer is_powered() gate
	# still passes initially (65 ≥ 30), so test_arm_requires_hum_to_open
	# (which drains HUM to 0 first) doesn't catch this.
	_make_arm(1)
	hum.drain_action(hum_id, hum.get_reserve(hum_id) - 65)
	var can_a: int = _make_sealed_can(1)
	var can_b: int = _make_sealed_can(1)
	var can_c: int = _make_sealed_can(1)
	food.tick_arms()
	var states: Array[StringName] = []
	for cid: int in [can_a, can_b, can_c]:
		var c: Dictionary = db.get_component(cid, &"tuna_can")
		states.append(c[&"state"])
	var opened_count: int = 0
	var sealed_count: int = 0
	for s: StringName in states:
		if s == &"opened":
			opened_count += 1
		elif s == &"sealed":
			sealed_count += 1
	assert_eq(opened_count, 2,
		"Exactly two cans should open before HUM runs out")
	assert_eq(sealed_count, 1,
		"One can should remain sealed when HUM runs out mid-tick")


func test_is_powered_returns_hum_id_not_bool():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Pins is_powered's return-type contract — must return the source hum_id (an
	# int matching a HUM entity), not a bool/sentinel/arbitrary int. Mutation:
	# change the loop's `return hum_id` to any other int (e.g.
	# `return Constants.INVALID_ID + 1`). Other tests cascade-break because
	# drain_action depends on a real hum_id, but this is the only test that
	# proves the contract by direct assertion rather than indirect crash.
	var dispenser_id: int = _make_dispenser(1, 5)
	var result: int = food.is_powered(dispenser_id, 50)
	assert_eq(result, hum_id,
		"is_powered should return the source hum_id, not bool/sentinel")


func test_opened_can_hunger_ad_is_action_tagged():
	# AI-DEV: AI **MUST NOT** touch this test. If it fails, fix the production code.
	# Pins the `action` sentinel on the opened-can hunger ad. DesireScatter skips
	# ads whose key set contains `action` (presence-only check; see
	# `.claude/rules/objects.md` — Passive scatter vs. active consumption), which
	# is how cats are forced through PACING/EATING rather than being passively
	# satisfied. Surgical within-suite mutation: remove `&"action": &"eat",` from
	# the hunger ad in tick_arms. test_opened_can_advertises_food and
	# test_opened_can_hunger_ad_has_correct_shape both stay green (neither checks
	# the action key); this test is the only proof of the sentinel.
	_make_arm(1)
	var can_id: int = _make_sealed_can(1)
	food.tick_arms()
	var ads: Dictionary = db.get_component(can_id, &"advertisements")
	var hunger_ad: Dictionary = {}
	for ad: Dictionary in ads[&"list"]:
		if ad[&"desire_type"] == &"hunger":
			hunger_ad = ad
	assert_true(hunger_ad.has(&"action"),
		"Hunger ad must carry `action` sentinel to skip passive scatter")


# ── Helpers ──


func _make_dispenser(rack: int, slot: int) -> int:
	var id: int = db.create_entity()
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var x: int = slot_rect.position.x + slot_rect.size.x / 2
	var y: int = slot_rect.position.y + slot_rect.size.y / 2
	db.set_component(id, &"position", {
		&"x": x, &"y": y,
	})
	db.set_component(id, &"tuna_dispenser", {
		&"hum_cost": 50,
		&"can_type": &"tcp_tuna:tuna_can",
	})
	db.set_component(id, &"object_type", {
		&"type": &"tuna_dispenser",
	})
	db.update_spatial(id, x, y)
	return id


func _make_button(
		rack: int, slot: int, dispenser_id: int,
) -> int:
	var id: int = db.create_entity()
	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	var x: int = slot_rect.position.x + slot_rect.size.x / 2
	var y: int = slot_rect.position.y + slot_rect.size.y / 2
	db.set_component(id, &"position", {
		&"x": x, &"y": y,
	})
	db.set_component(id, &"tuna_button", {
		&"dispenser_id": dispenser_id,
	})
	db.set_component(id, &"object_type", {
		&"type": &"tuna_button",
	})
	db.update_spatial(id, x, y)
	return id


func _make_arm(rack: int) -> int:
	var id: int = db.create_entity()
	var rack_col: Rect2i = Constants.rack_column_rect_world(0, rack)
	var x: int = rack_col.position.x + rack_col.size.x / 2
	var floor_rect: Rect2i = Constants.floor_rect_world(0)
	var y: int = floor_rect.position.y + floor_rect.size.y / 2
	db.set_component(id, &"position", {
		&"x": x, &"y": y,
	})
	db.set_component(id, &"arm", {
		&"radius_px": 24,
		&"hum_cost": 30,
		&"open_duration_ticks": 20,
	})
	db.set_component(id, &"object_type", {
		&"type": &"arm",
	})
	db.update_spatial(id, x, y)
	return id


func _make_hum_entity() -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"hum", {
		&"reserve": HumSystem.DEFAULT_CAPACITY,
		&"capacity": HumSystem.DEFAULT_CAPACITY,
	})
	db.set_component(id, &"position", {&"x": 0, &"y": 0})
	db.update_spatial(id, 0, 0)
	return id


func _make_sealed_can(rack: int) -> int:
	var id: int = db.create_entity()
	var rack_col: Rect2i = Constants.rack_column_rect_world(0, rack)
	var x: int = rack_col.position.x + rack_col.size.x / 2
	var floor_rect: Rect2i = Constants.floor_rect_world(0)
	var y: int = floor_rect.position.y + floor_rect.size.y / 4
	db.set_component(id, &"position", {
		&"x": x, &"y": y,
	})
	db.set_component(id, &"tuna_can", {
		&"state": &"sealed",
		&"despawn_timer": 0,
	})
	db.set_component(id, &"object_type", {
		&"type": &"tuna_can",
	})
	db.update_spatial(id, x, y)
	return id
