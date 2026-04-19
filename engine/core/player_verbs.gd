class_name PlayerVerbs extends RefCounted

# Pure-core helpers for player-initiated verbs (pet, squeak).
# Called from nodes/game_client.gd; live here so the behavior is unit-testable
# without a scene tree.

const PET_FILL_AMOUNT: int = 500
const SQUEAK_RADIUS_SLOTS: int = 6
const SQUEAK_COMMITMENT: int = 200


static func pet_animal(db: GameStateDB, entity_id: int) -> void:
	if not db.has_component(entity_id, &"desires"):
		return
	var attention: int = db.get_field(entity_id, &"desires", &"attention")
	db.set_field(
		entity_id, &"desires", &"attention",
		mini(1000, attention + PET_FILL_AMOUNT),
	)


static func squeak_box(db: GameStateDB, box_id: int) -> void:
	# AI-DEV: Callers also emit Events.box_squeaked.emit(box_id) for audio.
	# That is a cross-system concern (see signals.md, Pattern 2) and lives at
	# the node boundary — this helper owns only the DB mutation.
	if not db.has_component(box_id, &"position"):
		return
	var box_pos: Dictionary = db.get_component(box_id, &"position")
	var nearby: Array[int] = db.query_radius(
		box_pos[&"x"], box_pos[&"y"],
		SQUEAK_RADIUS_SLOTS * Constants.SLOT_HEIGHT_PX,
	)
	for entity_id: int in nearby:
		if not db.has_component(entity_id, &"species"):
			continue
		if not db.has_component(entity_id, &"ai_state"):
			continue
		var ai: Dictionary = db.get_component(entity_id, &"ai_state")
		var s: StringName = ai[&"state"]
		if s == &"PACING" or s == &"HUNGRY" \
				or s == &"RETURNING" or s == &"EATING":
			db.set_component(
				entity_id, &"ai_state", {
					&"state": &"RETURNING",
					&"meta_state": &"GOAL_DIRECTED",
					&"commitment_score": SQUEAK_COMMITMENT,
				},
			)
			db.set_component(
				entity_id, &"target", {
					&"x": box_pos[&"x"],
					&"y": box_pos[&"y"],
					&"entity_id": box_id,
				},
			)
