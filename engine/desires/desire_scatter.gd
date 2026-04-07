class_name DesireScatter extends RefCounted

# Scatters satisfaction from nearby object advertisements to animals.
# For each animal, finds the best (strongest) ad per desire type within
# range and applies that satisfaction using diminishing returns.
# Action-only ads are skipped — their benefit comes from PERFORMING.

var _db: GameStateDB


func _init(db: GameStateDB) -> void:
	_db = db


# For each entity with desires, find nearby advertisements and apply
# the best satisfaction per desire type.  Skips ads that have an action
# field (those require PERFORMING).  Only affects desire types the
# entity actually has.
func scatter_from_ads() -> void:
	var animals: Array[int] = _db.get_entities_with(&"desires")
	for entity_id: int in animals:
		if not _db.has_component(entity_id, &"position"):
			continue
		var pos: Dictionary = _db.get_component(entity_id, &"position")
		var nearby: Array[int] = _db.query_radius(
			pos[&"x"], pos[&"y"], Constants.ru_to_pu(8),
		)
		# Track best strength per desire type
		var best: Dictionary = {}  # desire_type -> strength
		for other_id: int in nearby:
			if other_id == entity_id:
				continue
			if not _db.has_component(other_id, &"advertisements"):
				continue
			var ads: Dictionary = _db.get_component(
				other_id, &"advertisements",
			)
			var other_pos: Dictionary = _db.get_component(
				other_id, &"position",
			)
			var dist: int = (
				absi(pos[&"x"] - other_pos[&"x"])
				+ absi(pos[&"y"] - other_pos[&"y"])
			)
			for ad: Dictionary in ads[&"list"]:
				var radius_pu: int = Constants.ru_to_pu(
					ad[&"radius_ru"],
				)
				if dist > radius_pu:
					continue
				# Skip action ads — their benefit comes from performing
				if ad.has(&"action"):
					continue
				var dtype: StringName = ad[&"desire_type"]
				var strength: int = ad[&"strength"]
				if strength > best.get(dtype, 0):
					best[dtype] = strength
		# Apply best satisfaction per desire type with diminishing returns.
		# Desire scale: 0 = desperate (cold/hungry/lonely), 1000 = satisfied.
		# gap = 1000 - current (headroom remaining to fully satisfied)
		# gain = best_strength * gap / 1000
		# new_desire = min(1000, current + gain / 10)
		var desires: Dictionary = _db.get_component(entity_id, &"desires")
		for dtype: StringName in best:
			if not desires.has(dtype):
				continue
			var current: int = desires[dtype]
			@warning_ignore("integer_division")
			var gain: int = best[dtype] * (1000 - current) / 1000
			@warning_ignore("integer_division")
			var new_val: int = mini(1000, current + gain / 10)
			_db.set_field(entity_id, &"desires", dtype, new_val)
