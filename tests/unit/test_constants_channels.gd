extends GutTest


# AI-DEV: Pins the Constants.CHANNELS registry shape — every channel must
# carry {sense, desire, effect}. The `effect` value must be one of
# `satisfy`/`deplete`. Adding a channel without these keys is a content
# error; the lint `script/checks/channels_complete` catches it at validate
# time, this test catches it at GUT time. Extend `_REQUIRED_KEYS` only
# when the registry shape itself changes — not for new channels.
const _REQUIRED_KEYS: Array[StringName] = [&"sense", &"desire", &"effect"]
const _VALID_EFFECTS: Array[StringName] = [&"satisfy", &"deplete"]


func test_channels_registry_exists() -> void:
	assert_gt(
		Constants.CHANNELS.size(), 0,
		"Constants.CHANNELS must be populated",
	)


func test_every_channel_has_required_keys() -> void:
	for channel: StringName in Constants.CHANNELS:
		var entry: Dictionary = Constants.CHANNELS[channel]
		for key: StringName in _REQUIRED_KEYS:
			assert_true(
				entry.has(key),
				"Channel %s missing required key %s" % [channel, key],
			)


func test_every_channel_effect_is_satisfy_or_deplete() -> void:
	for channel: StringName in Constants.CHANNELS:
		var effect: StringName = Constants.CHANNELS[channel][&"effect"]
		assert_true(
			effect in _VALID_EFFECTS,
			"Channel %s has invalid effect %s" % [channel, effect],
		)
