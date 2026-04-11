extends GutTest

var _resolver: VerbResolver
var _db: GameStateDB
var _defs: EntityDefRegistry


func before_each() -> void:
	_resolver = VerbResolver.new()
	_db = GameStateDB.new()
	_defs = EntityDefRegistry.new()


func test_can_perform_push_succeeds_when_strong_enough():
	_defs.register(&"tcp_cats:cat", {
		"id": "cat", "strength": 3000,
		"verbs": {
			"push": {
				"effectiveness": 1000,
				"desire_affinities": {},
			},
		},
	})
	var actor: int = _db.create_entity()
	_db.set_component(
		actor, &"species", {&"id": &"tcp_cats:cat"},
	)
	_db.set_component(
		actor, &"physical", {&"mass": 4000, &"size_ru": 2},
	)
	var target: int = _db.create_entity()
	_db.set_component(
		target, &"physical", {&"mass": 400, &"size_ru": 1},
	)
	assert_true(
		_resolver.can_perform(
			&"push", actor, target, _db, _defs,
		),
	)


func test_can_perform_push_fails_when_too_weak():
	_defs.register(&"tcp_cats:cat", {
		"id": "cat", "strength": 3000,
		"verbs": {
			"push": {
				"effectiveness": 1000,
				"desire_affinities": {},
			},
		},
	})
	var actor: int = _db.create_entity()
	_db.set_component(
		actor, &"species", {&"id": &"tcp_cats:cat"},
	)
	_db.set_component(
		actor, &"physical", {&"mass": 4000, &"size_ru": 2},
	)
	var target: int = _db.create_entity()
	_db.set_component(
		target, &"physical",
		{&"mass": 50000, &"size_ru": 4},
	)
	assert_false(
		_resolver.can_perform(
			&"push", actor, target, _db, _defs,
		),
	)


func test_sit_on_uses_size_check_not_strength():
	_defs.register(&"tcp_cats:cat", {
		"id": "cat", "strength": 3000,
		"verbs": {
			"sit_on": {
				"desire_affinities": {"comfort": 700},
			},
		},
	})
	var actor: int = _db.create_entity()
	_db.set_component(
		actor, &"species", {&"id": &"tcp_cats:cat"},
	)
	_db.set_component(
		actor, &"physical", {&"mass": 4000, &"size_ru": 2},
	)
	var target: int = _db.create_entity()
	_db.set_component(
		target, &"physical", {&"mass": 100, &"size_ru": 2},
	)
	assert_true(
		_resolver.can_perform(
			&"sit_on", actor, target, _db, _defs,
		),
	)


func test_sit_on_fails_when_too_big():
	_defs.register(&"tcp_cats:cat", {
		"id": "cat", "strength": 3000,
		"verbs": {
			"sit_on": {
				"desire_affinities": {"comfort": 700},
			},
		},
	})
	var actor: int = _db.create_entity()
	_db.set_component(
		actor, &"species", {&"id": &"tcp_cats:cat"},
	)
	_db.set_component(
		actor, &"physical", {&"mass": 4000, &"size_ru": 2},
	)
	var target: int = _db.create_entity()
	_db.set_component(
		target, &"physical", {&"mass": 400, &"size_ru": 1},
	)
	assert_false(
		_resolver.can_perform(
			&"sit_on", actor, target, _db, _defs,
		),
	)


func test_score_verbs_returns_best_verb():
	_defs.register(&"tcp_cats:cat", {
		"id": "cat", "strength": 3000,
		"verbs": {
			"push": {
				"effectiveness": 1000,
				"desire_affinities": {"stimulation": 500},
			},
			"bat": {
				"effectiveness": 500,
				"desire_affinities": {"stimulation": 900},
			},
		},
	})
	var actor: int = _db.create_entity()
	_db.set_component(
		actor, &"species", {&"id": &"tcp_cats:cat"},
	)
	_db.set_component(
		actor, &"physical", {&"mass": 4000, &"size_ru": 2},
	)
	_db.set_component(
		actor, &"desires", {&"stimulation": 800},
	)
	_db.set_component(
		actor, &"personality",
		{&"stimulation_weight": 900},
	)
	var target: int = _db.create_entity()
	_db.set_component(
		target, &"physical", {&"mass": 400, &"size_ru": 1},
	)
	var best: StringName = _resolver.score_verbs(
		actor, target, _db, _defs,
	)
	assert_eq(best, &"bat")


func test_score_verbs_returns_empty_when_nothing_passes():
	_defs.register(&"tcp_cats:cat", {
		"id": "cat", "strength": 100,
		"verbs": {
			"push": {
				"effectiveness": 1000,
				"desire_affinities": {"stimulation": 500},
			},
		},
	})
	var actor: int = _db.create_entity()
	_db.set_component(
		actor, &"species", {&"id": &"tcp_cats:cat"},
	)
	_db.set_component(
		actor, &"physical", {&"mass": 4000, &"size_ru": 2},
	)
	_db.set_component(
		actor, &"desires", {&"stimulation": 800},
	)
	_db.set_component(
		actor, &"personality",
		{&"stimulation_weight": 900},
	)
	var target: int = _db.create_entity()
	_db.set_component(
		target, &"physical",
		{&"mass": 50000, &"size_ru": 4},
	)
	var best: StringName = _resolver.score_verbs(
		actor, target, _db, _defs,
	)
	assert_eq(
		best, &"",
		"No verb should pass physics check",
	)


func test_score_verbs_returns_empty_for_no_verbs():
	_defs.register(
		&"tcp_tuna:tuna_can",
		{"id": "tuna_can", "states": {}},
	)
	var actor: int = _db.create_entity()
	_db.set_component(
		actor, &"species",
		{&"id": &"tcp_tuna:tuna_can"},
	)
	var target: int = _db.create_entity()
	_db.set_component(
		target, &"physical", {&"mass": 100, &"size_ru": 1},
	)
	var best: StringName = _resolver.score_verbs(
		actor, target, _db, _defs,
	)
	assert_eq(best, &"")
