extends GutTest


func test_derive_id_from_simple_title():
	var manifest := ModManifest.parse_dict({
		"title": "TCP Cats", "version": "0.1.0", "author": "TCP Team",
	})
	assert_eq(manifest.id, &"tcp_cats")


func test_derive_id_lowercases():
	var manifest := ModManifest.parse_dict({
		"title": "My COOL Mod", "version": "1.0.0", "author": "Me",
	})
	assert_eq(manifest.id, &"my_cool_mod")


func test_derive_id_replaces_non_alphanumeric():
	var manifest := ModManifest.parse_dict({
		"title": "Fluffy Ferret Friends!", "version": "1.0.0", "author": "Me",
	})
	assert_eq(manifest.id, &"fluffy_ferret_friends")


func test_derive_id_collapses_underscores():
	var manifest := ModManifest.parse_dict({
		"title": "TCP -- Cats", "version": "1.0.0", "author": "Me",
	})
	assert_eq(manifest.id, &"tcp_cats")


func test_derive_id_truncates_at_48():
	var long_title: String = \
		"A Very Long Mod Title That Exceeds The Maximum Allowed Length"
	var manifest := ModManifest.parse_dict({
		"title": long_title, "version": "1.0.0", "author": "Me",
	})
	assert_lt(manifest.id.length(), 49)


func test_missing_title_returns_null():
	var manifest := ModManifest.parse_dict({
		"version": "1.0.0", "author": "Me",
	})
	assert_null(manifest, "Missing title should return null")
	assert_push_error("missing required field")


func test_missing_version_returns_null():
	var manifest := ModManifest.parse_dict({
		"title": "Test", "author": "Me",
	})
	assert_null(manifest, "Missing version should return null")
	assert_push_error("missing required field")


func test_missing_author_returns_null():
	var manifest := ModManifest.parse_dict({
		"title": "Test", "version": "1.0.0",
	})
	assert_null(manifest, "Missing author should return null")
	assert_push_error("missing required field")


func test_description_is_optional():
	var manifest := ModManifest.parse_dict({
		"title": "Test", "version": "1.0.0", "author": "Me",
	})
	assert_not_null(manifest)
	assert_eq(manifest.description, "")
