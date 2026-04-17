extends GutTest

const _STATE := preload("res://engine/growth/plant_growth_state.gd")

var _db: GameStateDB
var _desire_scatter: DesireScatter


func before_each() -> void:
	_db = GameStateDB.new()
	_desire_scatter = DesireScatter.new(_db)


func _create_server_at(bay: int, rack: int, slot: int) -> int:
	var eid: int = _db.create_entity()
	var pos: Vector2i = Constants.rack_slot_to_pu(bay, rack, slot)
	_db.set_component(eid, &"position", {&"x": pos.x, &"y": pos.y})
	_db.update_spatial(eid, pos.x, pos.y)
	return eid


func _create_cat_at(bay: int, rack: int, slot: int) -> int:
	var eid: int = _db.create_entity()
	var pos: Vector2i = Constants.rack_slot_to_pu(bay, rack, slot)
	_db.set_component(eid, &"position", {&"x": pos.x, &"y": pos.y})
	_db.update_spatial(eid, pos.x, pos.y)
	_db.set_component(eid, &"species", {&"id": &"tcp_cats:cat"})
	_db.set_component(eid, &"desires", {
		&"warmth": 500, &"comfort": 0, &"curiosity": 500,
	})
	return eid


func test_cat_comfort_higher_near_planted_server_than_unplanted():
	var planted: int = _create_server_at(0, 1, 5)
	var unplanted: int = _create_server_at(0, 3, 5)
	_db.set_component(planted, &"plant_growth", {
		&"state": _STATE.PRESENT,
		&"tended_seconds": 400,
		&"variant": _STATE.VARIANT_MOSS,
		&"attached_to": planted,
	})
	_db.set_component(planted, &"advertisements", {
		&"list": [{
			&"source": &"plant_growth",
			&"desire_type": &"comfort",
			&"strength": _STATE.PLANT_COMFORT_STRENGTH,
			&"radius_ru": _STATE.PLANT_ADVERT_RADIUS_RU,
		}]
	})
	var cat_near_plant: int = _create_cat_at(0, 1, 5)
	var cat_near_empty: int = _create_cat_at(0, 3, 5)
	_desire_scatter.scatter_from_ads()
	var comfort_near_plant: int = _db.get_field(
		cat_near_plant, &"desires", &"comfort"
	)
	var comfort_near_empty: int = _db.get_field(
		cat_near_empty, &"desires", &"comfort"
	)
	assert_gt(comfort_near_plant, comfort_near_empty,
		"Cat near planted server must have higher comfort than cat near unplanted server")
