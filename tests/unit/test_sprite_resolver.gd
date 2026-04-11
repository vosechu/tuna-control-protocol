extends GutTest


func test_parse_sprite_filename():
	var result: Dictionary = SpriteResolver.parse_sprite_filename(
		"cat01_idle_strip8.png",
	)
	assert_eq(result["variant"], "cat01")
	assert_eq(result["state"], "idle")
	assert_eq(result["frame_count"], 8)


func test_parse_sprite_filename_with_multi_word_state():
	var result: Dictionary = SpriteResolver.parse_sprite_filename(
		"cat01_standup_strip6.png",
	)
	assert_eq(result["variant"], "cat01")
	assert_eq(result["state"], "standup")
	assert_eq(result["frame_count"], 6)


func test_parse_sprite_filename_invalid_returns_empty():
	var result: Dictionary = SpriteResolver.parse_sprite_filename(
		"not_a_sprite.png",
	)
	assert_true(result.is_empty())


func test_resolve_matches_known_variants():
	var resolver := SpriteResolver.new()
	var sprites: Dictionary = resolver.resolve_from_list(
		[
			"cat01_idle_strip8.png",
			"cat01_walk_strip8.png",
			"cat02_idle_strip8.png",
		],
		["cat01", "cat02"],
	)
	assert_true(sprites.has("cat01"))
	assert_true(sprites["cat01"].has("idle"))
	assert_eq(sprites["cat01"]["idle"]["frame_count"], 8)
	assert_true(sprites.has("cat02"))
	assert_true(sprites["cat02"].has("idle"))


func test_validate_required_passes():
	var resolver := SpriteResolver.new()
	var sprites: Dictionary = {
		"cat01": {
			"idle": {}, "walk": {},
			"sit": {}, "sleep": {},
		},
	}
	var anims: Dictionary = {
		"required": ["idle", "walk", "sit", "sleep"],
		"optional": [],
	}
	var errors: Array[String] = resolver.validate_required(
		sprites, anims, ["cat01"],
	)
	assert_eq(errors.size(), 0)


func test_validate_required_fails_for_missing():
	var resolver := SpriteResolver.new()
	var sprites: Dictionary = {
		"cat01": {"idle": {}, "walk": {}},
	}
	var anims: Dictionary = {
		"required": ["idle", "walk", "sit", "sleep"],
		"optional": [],
	}
	var errors: Array[String] = resolver.validate_required(
		sprites, anims, ["cat01"],
	)
	assert_eq(
		errors.size(), 2,
		"Expected 2 errors for missing sit and sleep",
	)
