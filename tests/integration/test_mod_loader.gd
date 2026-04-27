extends GutTest


func test_load_all_discovers_mods():
	var loader := ModLoader.new()
	var result: Dictionary = loader.load_all("res://mods/")
	assert_true(result["entity_defs"] is EntityDefRegistry)
	var defs: EntityDefRegistry = result["entity_defs"]
	assert_true(
		defs.has_entity(&"tcp_cats:cat"),
		"Cat should be registered",
	)
	assert_true(
		defs.has_entity(&"tcp_ferrets:ferret"),
		"Ferret should be registered",
	)
	assert_true(
		defs.has_entity(&"tcp_tuna:tuna_can"),
		"Tuna can should be registered",
	)


func test_load_all_returns_manifests():
	var loader := ModLoader.new()
	var result: Dictionary = loader.load_all("res://mods/")
	var manifests: Array = result["manifests"]
	assert_gte(
		manifests.size(), 3,
		"Should load at least 3 mods",
	)
	var ids: Array[StringName] = []
	for m: ModManifest in manifests:
		ids.append(m.id)
	assert_has(ids, &"tcp_cats")
	assert_has(ids, &"tcp_ferrets")
	assert_has(ids, &"tcp_tuna")


func test_species_has_body_capabilities():
	var loader := ModLoader.new()
	var result: Dictionary = loader.load_all("res://mods/")
	var defs: EntityDefRegistry = result["entity_defs"]
	assert_true(defs.has_body_capabilities(&"tcp_cats:cat"))
	assert_true(defs.has_body_capabilities(&"tcp_ferrets:ferret"))
	assert_false(defs.has_body_capabilities(&"tcp_tuna:tuna_can"))


func test_object_has_states():
	var loader := ModLoader.new()
	var result: Dictionary = loader.load_all("res://mods/")
	var defs: EntityDefRegistry = result["entity_defs"]
	var states: Dictionary = defs.get_states(
		&"tcp_tuna:tuna_can",
	)
	assert_true(states.has("sealed"))
	assert_true(states.has("open"))
	assert_true(states.has("empty"))
