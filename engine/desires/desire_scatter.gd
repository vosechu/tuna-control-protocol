class_name DesireScatter extends RefCounted

# Scatters satisfaction from nearby object advertisements to animals.
# For each animal, finds the best (strongest) ad per desire type within
# range and applies that satisfaction using diminishing returns.
# Ads tagged with `action` are skipped — those satisfaction channels
# require an active consumer (PACING/EATING state loop, arm tick, etc.)
# rather than passive proximity. See .claude/rules/objects.md.
#
# Audit (2026-05-03): API is channel-agnostic. New channels extend
# Constants.CHANNELS; no new methods required. Per-channel names like
# scatter_warmth and per-channel match arms are forbidden — see
# 2026-04-06-game-server-extraction-design.md lesson 2.

var _db: GameStateDB


func _init(db: GameStateDB) -> void:
	_db = db


# For each entity with desires, find nearby advertisements and apply
# the best satisfaction per desire type.  Skips ads that have an
# `action` field (those are consumed by an active state loop, not
# passively).  Only affects desire types the entity actually has.
#
# Two passes: slot-delivery first (full strength to slot occupants),
# then radius-delivery (legacy gap-based gain pending Task 16 rewrite).
func scatter_from_ads() -> void:
	_scatter_slot_delivery()
	_scatter_radius_delivery()


# Slot delivery: full strength to every entity sharing the ad-owner's
# slot. Boxes, beds, tubes, cat towers — anything where the effect
# logically belongs to a slot occupant rather than to a radius around
# a position.
func _scatter_slot_delivery() -> void:
	var ad_owners: Array[int] = _db.get_entities_with(&"advertisements")
	for owner_id: int in ad_owners:
		if not _db.has_component(owner_id, &"position"):
			continue
		var owner_pos: Dictionary = _db.get_component(owner_id, &"position")
		var ads: Array = _db.get_component(owner_id, &"advertisements")[&"list"]
		for ad: Dictionary in ads:
			if not ad.get(&"effect_slot", false):
				continue
			var channel: StringName = ad.get(&"channel", ad.get(&"desire_type", &""))
			if not Constants.CHANNELS.has(channel):
				continue
			# Resolve owner's slot. Slot delivery requires the ad emitter
			# to be in a rack slot zone; emitters elsewhere are a content
			# error (push_error and skip rather than crash).
			var query: SlotQuery = Constants.bay_local_to_slot(
				0, Vector2i(owner_pos[&"x"], owner_pos[&"y"]),
			)
			if query.zone != &"slot":
				push_error(
					"DesireScatter: effect_slot ad on entity %d at %s is not slot-anchored (zone=%s)"
					% [owner_id, owner_pos, query.zone],
				)
				continue
			_apply_slot_ad(query.rack, query.slot, owner_id, ad, channel)


func _apply_slot_ad(
	rack: int, slot: int, owner_id: int, ad: Dictionary, channel: StringName,
) -> void:
	var meta: Dictionary = Constants.CHANNELS[channel]
	var target_desire: StringName = meta[&"desire"]
	var effect: StringName = meta[&"effect"]
	var strength: int = ad[&"strength"]

	var slot_rect: Rect2i = Constants.slot_rect_world(0, rack, slot)
	# Use a radius query around the slot center, then verify each hit
	# is in the same slot via bay_local_to_slot. Slots are 23×8 px,
	# diagonal ≤ 25 px — radius 16 reaches every position inside.
	var center_x: int = slot_rect.position.x + slot_rect.size.x / 2
	var center_y: int = slot_rect.position.y + slot_rect.size.y / 2
	var nearby: Array[int] = _db.query_radius(center_x, center_y, 16)
	for entity_id: int in nearby:
		if entity_id == owner_id:
			continue
		if not _db.has_component(entity_id, &"desires"):
			continue
		if not _db.has_component(entity_id, &"position"):
			continue
		var entity_pos: Dictionary = _db.get_component(entity_id, &"position")
		var entity_query: SlotQuery = Constants.bay_local_to_slot(
			0, Vector2i(entity_pos[&"x"], entity_pos[&"y"]),
		)
		if entity_query.zone != &"slot":
			continue
		if entity_query.rack != rack or entity_query.slot != slot:
			continue
		var desires: Dictionary = _db.get_component(entity_id, &"desires")
		if not desires.has(target_desire):
			continue
		var current: int = desires[target_desire]
		var new_val: int
		if effect == &"satisfy":
			new_val = mini(1000, current + strength / 10)
		else:
			new_val = maxi(0, current - strength / 10)
		_db.set_field(entity_id, &"desires", target_desire, new_val)


# Radius delivery: entity-first iteration. For each receiver, find
# advertisement-emitters within bay range, gate by sense + ad's
# effect_radius_px, then apply per-ad delta with the ad's falloff curve.
# Quadratic by default (matches the perception-channels spec).
func _scatter_radius_delivery() -> void:
	var animals: Array[int] = _db.get_entities_with(&"desires")
	for entity_id: int in animals:
		if not _db.has_component(entity_id, &"position"):
			continue
		var entity_pos: Dictionary = _db.get_component(entity_id, &"position")
		var senses: Dictionary = (
			_db.get_component(entity_id, &"senses")
			if _db.has_component(entity_id, &"senses")
			else {}
		)
		# Bonds let the receiver bypass the action-ad skip on its bonded
		# host (e.g. cat settled in this box). See engine/core/bonds.gd.
		var bond_hosts: Array[int] = []
		if Bonds.has_any_bond(_db, entity_id):
			bond_hosts = Bonds.get_bond_hosts(_db, entity_id)

		var nearby: Array[int] = _db.query_radius(
			entity_pos[&"x"], entity_pos[&"y"], Constants.BAY_WIDTH_PX,
		)
		var desires: Dictionary = _db.get_component(entity_id, &"desires")

		for ad_owner_id: int in nearby:
			if ad_owner_id == entity_id:
				continue
			if not _db.has_component(ad_owner_id, &"advertisements"):
				continue
			if not _db.has_component(ad_owner_id, &"position"):
				continue
			var ads: Array = _db.get_component(ad_owner_id, &"advertisements")[&"list"]
			var owner_pos: Dictionary = _db.get_component(ad_owner_id, &"position")
			var dist: int = (
				absi(entity_pos[&"x"] - owner_pos[&"x"])
				+ absi(entity_pos[&"y"] - owner_pos[&"y"])
			)

			for ad: Dictionary in ads:
				# Slot-delivered ads run in _scatter_slot_delivery.
				if ad.get(&"effect_slot", false):
					continue
				var radius_px: int = ad.get(
					&"effect_radius_px", ad.get(&"radius_px", 0),
				)
				if radius_px <= 0:
					continue
				if dist > radius_px:
					continue
				# Action ads only flow to bonded receivers.
				if ad.has(&"action") and not bond_hosts.has(ad_owner_id):
					continue
				var channel: StringName = ad.get(
					&"channel", ad.get(&"desire_type", &""),
				)
				if not Constants.CHANNELS.has(channel):
					continue
				var meta: Dictionary = Constants.CHANNELS[channel]
				var sense_key: StringName = meta[&"sense"]
				var sense_range: int = senses.get(
					sense_key, Constants.BAY_WIDTH_PX,
				)
				if dist > sense_range:
					continue
				var target_desire: StringName = meta[&"desire"]
				if not desires.has(target_desire):
					continue
				var falloff_kind: StringName = ad.get(&"falloff", &"quadratic")
				var falloff_factor: int = _apply_falloff(
					dist, radius_px, falloff_kind,
				)
				var strength: int = ad[&"strength"]
				var delta: int = strength * falloff_factor / 1000 / 10
				var current: int = desires[target_desire]
				var new_val: int
				if meta[&"effect"] == &"satisfy":
					new_val = mini(1000, current + delta)
				else:
					new_val = maxi(0, current - delta)
				if new_val != current:
					_db.set_field(entity_id, &"desires", target_desire, new_val)
					desires[target_desire] = new_val


# Returns falloff factor in 0–1000 (thousandths). Distance >= radius → 0.
# `step` always returns 1000 inside radius (no falloff). `linear` is t.
# `quadratic` is t² — the spec default. `inverse_square` is the
# physics shape, kept for future use.
func _apply_falloff(dist: int, radius: int, kind: StringName) -> int:
	if dist >= radius:
		return 0
	if radius <= 0:
		return 1000
	var t: int = (radius - dist) * 1000 / radius   # 0..1000
	if kind == &"step":
		return 1000
	if kind == &"linear":
		return t
	if kind == &"inverse_square":
		var d_norm: int = dist * 1000 / radius
		var denom: int = 1000 + d_norm * d_norm / 1000
		return 1_000_000 / denom
	# Default: quadratic. Includes &"quadratic" and any unknown kind.
	return t * t / 1000
