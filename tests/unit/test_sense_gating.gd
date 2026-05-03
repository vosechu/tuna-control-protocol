extends GutTest

# AI-DEV: Worked-example regression guard. Each test pins a row from
# docs/superpowers/specs/2026-05-02-perception-channels-design.md
# § "Worked examples." If a regression makes one of these pass for the
# wrong reason (e.g. the sense gate stops firing), the others usually
# fail too. Read the spec row before relaxing any assertion.

var _db: GameStateDB
var _scatter: DesireScatter


func before_each() -> void:
	_db = GameStateDB.new()
	_scatter = DesireScatter.new(_db)


func _make_receiver(x: int, y: int, senses: Dictionary, desires: Dictionary) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"senses", senses)
	_db.set_component(id, &"desires", desires)
	_db.update_spatial(id, x, y)
	return id


func _make_emitter(x: int, y: int, ad: Dictionary) -> int:
	var id: int = _db.create_entity()
	_db.set_component(id, &"position", {&"x": x, &"y": y})
	_db.set_component(id, &"advertisements", {&"list": [ad]})
	_db.update_spatial(id, x, y)
	return id


func test_deaf_cat_does_not_receive_noise():
	var cat_id: int = _make_receiver(0, 0,
		{&"sight": 186, &"hearing": 0, &"smell": 186, &"touch": 64},
		{&"quiet": 800})
	_make_emitter(8, 0,
		{&"channel": &"noise", &"strength": 800, &"effect_radius_px": 186,
			&"falloff": &"quadratic"})

	_scatter.scatter_from_ads()

	var quiet: int = _db.get_component(cat_id, &"desires")[&"quiet"]
	assert_eq(
		quiet, 800,
		"Deaf cat (hearing=0) must not have quiet depleted by adjacent noise (got %d)"
			% quiet,
	)


func test_cat_far_from_warm_server_does_not_receive_warmth():
	var cat_id: int = _make_receiver(0, 0,
		{&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 16},
		{&"warmth": 200})
	_make_emitter(100, 0,
		{&"channel": &"warmth", &"strength": 800, &"effect_radius_px": 16,
			&"falloff": &"quadratic"})

	_scatter.scatter_from_ads()

	var warmth: int = _db.get_component(cat_id, &"desires")[&"warmth"]
	assert_eq(
		warmth, 200,
		"Cat far from warm server must not gain warmth (got %d)" % warmth,
	)


func test_hearing_cat_across_bay_receives_noise():
	var cat_id: int = _make_receiver(150, 0,
		{&"sight": 186, &"hearing": 186, &"smell": 186, &"touch": 64},
		{&"quiet": 1000})
	_make_emitter(0, 0,
		{&"channel": &"noise", &"strength": 800, &"effect_radius_px": 186,
			&"falloff": &"quadratic"})

	_scatter.scatter_from_ads()

	var quiet: int = _db.get_component(cat_id, &"desires")[&"quiet"]
	assert_lt(
		quiet, 1000,
		"Hearing cat across bay must have quiet depleted by noise (got %d)" % quiet,
	)


func test_blind_cat_gets_only_noise_from_bawling_kitten():
	var cat_id: int = _make_receiver(0, 0,
		{&"sight": 0, &"hearing": 186, &"smell": 186, &"touch": 64},
		{&"peace": 1000, &"quiet": 1000})
	var kitten_id: int = _db.create_entity()
	_db.set_component(kitten_id, &"position", {&"x": 8, &"y": 0})
	_db.set_component(kitten_id, &"advertisements", {&"list": [
		{&"channel": &"noise", &"strength": 800, &"effect_radius_px": 186,
			&"falloff": &"quadratic"},
		{&"channel": &"chaos", &"strength": 800, &"effect_radius_px": 96,
			&"falloff": &"quadratic"},
	]})
	_db.update_spatial(kitten_id, 8, 0)

	_scatter.scatter_from_ads()

	var desires: Dictionary = _db.get_component(cat_id, &"desires")
	assert_lt(desires[&"quiet"], 1000,
		"Blind cat must hear noise → quiet drops (got %d)" % desires[&"quiet"])
	assert_eq(desires[&"peace"], 1000,
		"Blind cat must not see chaos → peace unchanged (got %d)" % desires[&"peace"])


func test_deaf_cat_gets_only_chaos_from_bawling_kitten():
	var cat_id: int = _make_receiver(0, 0,
		{&"sight": 186, &"hearing": 0, &"smell": 186, &"touch": 64},
		{&"peace": 1000, &"quiet": 1000})
	var kitten_id: int = _db.create_entity()
	_db.set_component(kitten_id, &"position", {&"x": 8, &"y": 0})
	_db.set_component(kitten_id, &"advertisements", {&"list": [
		{&"channel": &"noise", &"strength": 800, &"effect_radius_px": 186,
			&"falloff": &"quadratic"},
		{&"channel": &"chaos", &"strength": 800, &"effect_radius_px": 96,
			&"falloff": &"quadratic"},
	]})
	_db.update_spatial(kitten_id, 8, 0)

	_scatter.scatter_from_ads()

	var desires: Dictionary = _db.get_component(cat_id, &"desires")
	assert_lt(desires[&"peace"], 1000,
		"Deaf cat must see chaos → peace drops (got %d)" % desires[&"peace"])
	assert_eq(desires[&"quiet"], 1000,
		"Deaf cat must not hear noise → quiet unchanged (got %d)" % desires[&"quiet"])
