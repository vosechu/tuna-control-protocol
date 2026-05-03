extends GutTest

# AI-DEV: Locks in per-species decay. The system reads each entity's
# `desire_decay` component (set from recipe) and applies the per-channel
# decay to that entity's `desires` via add_field_subset. The system must
# NOT branch on species labels — it just reads the component.

var db: GameStateDB
var sys: DesireDecaySystem


func before_each() -> void:
	db = GameStateDB.new()
	sys = DesireDecaySystem.new(db)


func _make_animal(decays: Dictionary, desires: Dictionary) -> int:
	var id: int = db.create_entity()
	db.set_component(id, &"desires", desires)
	db.set_component(id, &"desire_decay", decays)
	return id


func test_applies_per_entity_decay_per_channel() -> void:
	var a: int = _make_animal(
		{&"comfort": -5, &"hunger": -3},
		{&"comfort": 800, &"hunger": 700, &"safety": 500},
	)

	sys.tick()

	assert_eq(db.get_field(a, &"desires", &"comfort"), 795)
	assert_eq(db.get_field(a, &"desires", &"hunger"), 697)
	assert_eq(db.get_field(a, &"desires", &"safety"), 500,
		"channel without decay entry must be untouched")


func test_different_entities_get_their_own_decay_values() -> void:
	# Cat: comfort -5, ferret-shaped: comfort -3
	var cat: int = _make_animal({&"comfort": -5}, {&"comfort": 800})
	var ferret: int = _make_animal({&"comfort": -3}, {&"comfort": 800})

	sys.tick()

	assert_eq(db.get_field(cat, &"desires", &"comfort"), 795)
	assert_eq(db.get_field(ferret, &"desires", &"comfort"), 797)


func test_entity_without_desire_decay_is_skipped() -> void:
	var a: int = db.create_entity()
	db.set_component(a, &"desires", {&"comfort": 800})
	# No desire_decay component.

	sys.tick()

	assert_eq(db.get_field(a, &"desires", &"comfort"), 800)


func test_zero_decay_channel_is_a_noop_for_value() -> void:
	var a: int = _make_animal({&"hunger": 0}, {&"hunger": 700})

	sys.tick()

	assert_eq(db.get_field(a, &"desires", &"hunger"), 700)


func test_decay_does_not_branch_on_species() -> void:
	# Two entities with identical decay components but different species
	# labels MUST receive identical treatment. Locks in capability-not-
	# species: the system reads `desire_decay`, not `species.id`.
	var cat: int = _make_animal({&"comfort": -7}, {&"comfort": 500})
	db.set_component(cat, &"species", {&"id": &"tcp_cats:cat"})
	var ferret: int = _make_animal({&"comfort": -7}, {&"comfort": 500})
	db.set_component(ferret, &"species", {&"id": &"tcp_ferrets:ferret"})

	sys.tick()

	assert_eq(
		db.get_field(cat, &"desires", &"comfort"),
		db.get_field(ferret, &"desires", &"comfort"),
		"identical decay components must produce identical deltas"
	)
