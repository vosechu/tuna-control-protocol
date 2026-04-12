# Purr-Power Feedback & Presentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the presentation layer for purr-power Ring 0: lighting that dims with HUM reserve, HUD reserve bar, sound refactoring (purr tracks reserve), meow/squeak/can-pop audio, HUM device tone, and the robot narrator CRT panel with log triggers.

**Architecture:** All feedback systems listen to `Events.hum_reserve_changed` and react. Lighting is a global CanvasModulate. Sound decomposes the current god-node into HumBus + PurrAggregator + AmbientLayer. Narrator is a diegetic CRT panel that renders log text. All one-way: HUM system → events → presentation.

**Tech Stack:** GDScript 4.x, Godot CanvasModulate, AudioStreamPlayer, GUT test framework

**Spec:** `docs/superpowers/specs/2026-04-12-purr-power-ring0-design.md`

**Prerequisites:** Plan 1 (Foundation) must be complete — HUM system with `hum_reserve_changed` signal. Plan 2 (Objects & Food Loop) should be complete for full integration but is not strictly required for most tasks here.

**Sibling plans:** This is Plan 3 of 3. Plans 1 (Foundation) and 2 (Objects & Food Loop) cover the logic layer.

---

## File Map

### New files

| File | Responsibility |
|---|---|
| `nodes/lighting_system.gd` | CanvasModulate driven by HUM reserve: brightness, color shift, brownout vignette |
| `nodes/hud/hum_bar.gd` | HUD element: numeric %, fill bar, state glyph, brownout indicator |
| `nodes/narrator_panel.gd` | Diegetic CRT: scrolling log, pin behavior, history access |
| `engine/core/narrator.gd` | Log message generation: templates, voice rules, attribution allowlist |
| `tests/unit/test_narrator.gd` | Unit tests for log generation, voice rules, blame-cat check |
| `tests/unit/test_lighting.gd` | Unit tests for reserve→brightness mapping |

### Modified files

| File | Change |
|---|---|
| `nodes/sound_manager.gd` | Refactor: purr tracks HUM reserve not cat count, add meow/squeak/can-pop players |
| `nodes/game_client.gd` | Initialize lighting system, HUM bar, narrator panel |
| `engine/core/events.gd` | Add narrator signals: `robot_log_posted`, `cat_started_pacing`, `food_dispensed` |

---

### Task 1: Lighting system — CanvasModulate driven by HUM

**Files:**
- Create: `nodes/lighting_system.gd`
- Create: `tests/unit/test_lighting.gd`
- Modify: `nodes/game_client.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_lighting.gd`:

```gdscript
extends GutTest

func test_full_reserve_returns_full_brightness():
	var brightness: float = LightingSystem.reserve_to_brightness(1000)
	assert_almost_eq(brightness, 1.0, 0.01,
		"Full reserve (1000) should return brightness 1.0")


func test_zero_reserve_returns_minimum_brightness():
	var brightness: float = LightingSystem.reserve_to_brightness(0)
	assert_almost_eq(brightness, 0.15, 0.01,
		"Zero reserve should return minimum brightness 0.15 (emergency lighting)")


func test_quarter_reserve_returns_red_tint():
	var color: Color = LightingSystem.reserve_to_color(250)
	assert_gt(color.r, color.g,
		"At 25%% reserve, red channel should dominate")


func test_full_reserve_returns_warm_white():
	var color: Color = LightingSystem.reserve_to_color(1000)
	assert_almost_eq(color.r, 1.0, 0.1,
		"Full reserve should be warm white")
	assert_almost_eq(color.g, 0.95, 0.1,
		"Full reserve should be warm white")
	assert_almost_eq(color.b, 0.85, 0.1,
		"Full reserve should have slight warm tint")


func test_brownout_threshold_at_250():
	assert_true(LightingSystem.is_brownout(249),
		"Below 250 ratio should be brownout")
	assert_false(LightingSystem.is_brownout(250),
		"At 250 ratio should not be brownout")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_lighting.gd`
Expected: FAIL — `LightingSystem` class not found.

- [ ] **Step 3: Implement LightingSystem**

Create `nodes/lighting_system.gd`:

```gdscript
class_name LightingSystem extends CanvasModulate

const MIN_BRIGHTNESS: float = 0.15
const BROWNOUT_RATIO: int = 250
const SMOOTHING_SPEED: float = 2.0

var _target_brightness: float = 1.0
var _target_color: Color = Color.WHITE
var _events: Events


func initialize(events: Events) -> void:
	_events = events
	_events.hum_reserve_changed.connect(_on_hum_reserve_changed)
	color = Color.WHITE


static func reserve_to_brightness(ratio: int) -> float:
	# ratio: 0-1000 (0=empty, 1000=full)
	# Linear map: 0 → MIN_BRIGHTNESS, 1000 → 1.0
	return MIN_BRIGHTNESS + float(ratio) / 1000.0 * (1.0 - MIN_BRIGHTNESS)


static func reserve_to_color(ratio: int) -> Color:
	if ratio >= 500:
		# Warm white: slight gold tint
		return Color(1.0, 0.95, 0.85)
	elif ratio >= BROWNOUT_RATIO:
		# Transition: warm white → amber
		var t: float = float(ratio - BROWNOUT_RATIO) / float(500 - BROWNOUT_RATIO)
		return Color(1.0, 0.6 + 0.35 * t, 0.3 + 0.55 * t)
	else:
		# Brownout: red-amber
		var t: float = float(ratio) / float(BROWNOUT_RATIO)
		return Color(0.8 + 0.2 * t, 0.2 + 0.4 * t, 0.1 + 0.2 * t)


static func is_brownout(ratio: int) -> bool:
	return ratio < BROWNOUT_RATIO


func _on_hum_reserve_changed(_old: int, new_reserve: int) -> void:
	# Convert raw reserve to ratio (0-1000) via HumSystem
	# For now, assume the signal carries raw values and we need the ratio
	# The implementing agent should check whether to pass ratio or raw values
	_target_brightness = reserve_to_brightness(new_reserve)
	_target_color = reserve_to_color(new_reserve)


func _process(delta: float) -> void:
	# Smooth transition
	var current_b: float = color.v
	var target_b: float = _target_brightness
	var new_b: float = lerpf(current_b, target_b, SMOOTHING_SPEED * delta)
	color = _target_color * new_b
```

- [ ] **Step 4: Wire into game_client.gd**

After sound manager setup, add:

```gdscript
var lighting := LightingSystem.new()
lighting.name = "LightingSystem"
add_child(lighting)
lighting.initialize(game_server.events)
```

- [ ] **Step 5: Run tests and verify pass**

Run: `script/checks/gut_tests -f tests/unit/test_lighting.gd`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add nodes/lighting_system.gd tests/unit/test_lighting.gd nodes/game_client.gd
git commit -m "feat(lighting): CanvasModulate driven by HUM reserve — brightness, color, brownout"
```

---

### Task 2: HUD reserve bar

**Files:**
- Create: `nodes/hud/hum_bar.gd`
- Modify: `nodes/game_client.gd`

- [ ] **Step 1: Implement HumBar**

Create `nodes/hud/hum_bar.gd`:

```gdscript
class_name HumBar extends Control

var _reserve_label: Label
var _bar_fill: ColorRect
var _bar_bg: ColorRect
var _glyph_label: Label
var _events: Events

const BAR_WIDTH: int = 120
const BAR_HEIGHT: int = 12


func initialize(events: Events) -> void:
	_events = events
	_events.hum_reserve_changed.connect(_on_hum_reserve_changed)
	_build_ui()
	_update_display(1000)


func _build_ui() -> void:
	# Background
	_bar_bg = ColorRect.new()
	_bar_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_bg.color = Color(0.15, 0.15, 0.2, 0.8)
	add_child(_bar_bg)

	# Fill
	_bar_fill = ColorRect.new()
	_bar_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_fill.color = Color(0.3, 0.8, 0.4)
	add_child(_bar_fill)

	# Label: "HUM RESERVE: 100%"
	_reserve_label = Label.new()
	_reserve_label.position = Vector2(BAR_WIDTH + 8, -2)
	_reserve_label.add_theme_font_size_override("font_size", 10)
	add_child(_reserve_label)

	# State glyph
	_glyph_label = Label.new()
	_glyph_label.position = Vector2(-16, -2)
	_glyph_label.add_theme_font_size_override("font_size", 10)
	add_child(_glyph_label)


func _on_hum_reserve_changed(_old: int, _new: int) -> void:
	# The signal passes raw reserve values. We need the ratio.
	# The implementing agent should wire this to get the ratio from HumSystem.
	pass


func _update_display(ratio: int) -> void:
	# Fill width
	var fill_pct: float = float(ratio) / 1000.0
	_bar_fill.size.x = BAR_WIDTH * fill_pct

	# Color: green → amber → red
	if ratio >= 500:
		_bar_fill.color = Color(0.3, 0.8, 0.4)
	elif ratio >= 250:
		_bar_fill.color = Color(0.9, 0.7, 0.2)
	else:
		_bar_fill.color = Color(0.9, 0.2, 0.1)

	# Numeric label
	@warning_ignore("integer_division")
	var pct: int = ratio / 10
	_reserve_label.text = "HUM: %d%%" % pct

	# State glyph (shape-coded, not just color)
	if ratio >= 500:
		_glyph_label.text = "O"  # circle = nominal
	elif ratio >= 250:
		_glyph_label.text = "^"  # triangle = advisory
	else:
		_glyph_label.text = "!"  # exclamation = critical
```

- [ ] **Step 2: Wire into game_client.gd**

```gdscript
var hum_bar := HumBar.new()
hum_bar.position = Vector2(10, 10)  # top-left corner
hum_bar.name = "HumBar"
$HUD.add_child(hum_bar)  # or add to a CanvasLayer
hum_bar.initialize(game_server.events)
```

Note: If no `$HUD` CanvasLayer exists yet, create one:

```gdscript
var hud := CanvasLayer.new()
hud.name = "HUD"
add_child(hud)
```

- [ ] **Step 3: Test visually**

Run the game, verify the HUM bar appears and updates.

- [ ] **Step 4: Commit**

```bash
git add nodes/hud/hum_bar.gd nodes/game_client.gd
git commit -m "feat(hud): HUM reserve bar with numeric %, fill, state glyph"
```

---

### Task 3: Sound refactoring — purr tracks reserve, not count

**Files:**
- Modify: `nodes/sound_manager.gd`

- [ ] **Step 1: Refactor SoundManager to accept HUM reserve**

Replace the `_recount_purring()` logic. Instead of counting purring cats and deriving volume, listen to `hum_reserve_changed` and drive purr volume from the reserve ratio:

```gdscript
var _hum_reserve_ratio: int = 1000  # 0-1000

func initialize(db: GameStateDB, events: Events) -> void:
	_db = db
	_setup_audio_players()
	events.hum_reserve_changed.connect(_on_hum_reserve_changed)
	# Still register cats for the purring visual indicator (separate from volume)
	var cat_ids: Array[int] = _db.get_entities_with(&"species")
	for entity_id: int in cat_ids:
		_cat_entity_ids.append(entity_id)
	_total_cats = _cat_entity_ids.size()


func _on_hum_reserve_changed(_old: int, new_reserve: int) -> void:
	# The implementing agent should convert raw reserve to ratio here
	# or receive ratio directly from the signal
	_hum_reserve_ratio = new_reserve  # placeholder — fix during wiring
```

Update `_process()` to drive purr volume from reserve ratio instead of purring count:

```gdscript
func _process(_delta: float) -> void:
	# Purr volume tracks HUM reserve, not individual cat count
	# This is commitment #1: single-cat events are invisible at audio level
	var target_db: float = -40.0  # silence floor
	if _hum_reserve_ratio > 0:
		var ratio_f: float = float(_hum_reserve_ratio) / 1000.0
		# Scale from -25dB (trickle) to -6dB (full reserve)
		target_db = lerpf(-25.0, -6.0, ratio_f)

	# Asymmetric smoothing: faster ramp-up (0.08), slower decay (0.03)
	var smooth: float = 0.08 if target_db > _purr_player_1.volume_db else 0.03
	_purr_player_1.volume_db = lerpf(_purr_player_1.volume_db, target_db, smooth)
	_purr_player_2.volume_db = lerpf(_purr_player_2.volume_db, target_db - 3.0, smooth)

	# Ambient hum: cut at brownout (<25%)
	var ambient_target: float = -40.0
	if _hum_reserve_ratio > 250:
		ambient_target = -30.0
	_ambient_player.volume_db = lerpf(_ambient_player.volume_db, ambient_target, 0.02)

	# Restart players if stopped
	if not _purr_player_1.playing and _purr_player_1.stream:
		_purr_player_1.play()
	if not _purr_player_2.playing and _purr_player_2.stream:
		_purr_player_2.play()
	if not _ambient_player.playing and _ambient_player.stream:
		_ambient_player.play()
```

- [ ] **Step 2: Update game_client.gd to pass events to sound manager**

Change the sound manager initialization:

```gdscript
sm.initialize(game_server.db, game_server.events)
```

- [ ] **Step 3: Test audibly**

Run the game. Verify purr volume responds to HUM reserve changes, not individual cat state transitions.

- [ ] **Step 4: Commit**

```bash
git add nodes/sound_manager.gd nodes/game_client.gd
git commit -m "refactor(sound): purr volume tracks HUM reserve, not cat count"
```

---

### Task 4: Meow, squeak, and can-pop audio

**Files:**
- Modify: `nodes/sound_manager.gd`
- Modify: `engine/core/events.gd`

- [ ] **Step 1: Add new event signals**

In `events.gd`:

```gdscript
signal cat_started_pacing(animal_id: int)
signal food_dispensed(can_id: int)
signal can_opened(can_id: int)
signal cat_petted(animal_id: int)
signal box_squeaked(box_id: int)
```

- [ ] **Step 2: Add audio players to SoundManager**

```gdscript
var _meow_player: AudioStreamPlayer
var _squeak_player: AudioStreamPlayer
var _can_pop_player: AudioStreamPlayer
var _button_click_player: AudioStreamPlayer
```

In `_setup_audio_players()`, load and configure each. Use placeholder sounds if the actual WAV files don't exist yet — the sound-designer will provide them. Load from `mods/tcp_base/sounds/`:

```gdscript
# Meow — plays when cat enters PACING state
var meow_stream: AudioStream = _try_load("res://mods/tcp_base/sounds/cat/cat_meow_pacing_01.wav")
if meow_stream:
	_meow_player = AudioStreamPlayer.new()
	_meow_player.stream = meow_stream
	_meow_player.volume_db = -15.0
	add_child(_meow_player)

# Squeak — plays when player clicks a box
var squeak_stream: AudioStream = _try_load("res://mods/tcp_base/sounds/objects/squeak_toy_01.wav")
if squeak_stream:
	_squeak_player = AudioStreamPlayer.new()
	_squeak_player.stream = squeak_stream
	_squeak_player.volume_db = -10.0
	add_child(_squeak_player)

# Can pop — plays when ARM opens a can
var pop_stream: AudioStream = _try_load("res://mods/tcp_base/sounds/objects/can_pop_01.wav")
if pop_stream:
	_can_pop_player = AudioStreamPlayer.new()
	_can_pop_player.stream = pop_stream
	_can_pop_player.volume_db = -12.0
	add_child(_can_pop_player)

# Button click
var click_stream: AudioStream = _try_load("res://mods/tcp_base/sounds/objects/button_click_01.wav")
if click_stream:
	_button_click_player = AudioStreamPlayer.new()
	_button_click_player.stream = click_stream
	_button_click_player.volume_db = -10.0
	add_child(_button_click_player)
```

Add a safe loader:

```gdscript
func _try_load(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path)
	return null
```

- [ ] **Step 3: Connect to events**

In `initialize()`:

```gdscript
events.cat_started_pacing.connect(_on_cat_started_pacing)
events.food_dispensed.connect(_on_food_dispensed)
events.can_opened.connect(_on_can_opened)
events.box_squeaked.connect(_on_box_squeaked)
```

Handlers:

```gdscript
func _on_cat_started_pacing(_animal_id: int) -> void:
	if _meow_player and not _meow_player.playing:
		_meow_player.play()

func _on_food_dispensed(_can_id: int) -> void:
	if _button_click_player:
		_button_click_player.play()

func _on_can_opened(_can_id: int) -> void:
	if _can_pop_player:
		_can_pop_player.play()

func _on_box_squeaked(_box_id: int) -> void:
	if _squeak_player:
		_squeak_player.play()
```

- [ ] **Step 4: Emit events from game_server.gd and game_client.gd**

In game_server.gd, when a cat transitions to PACING:

```gdscript
events.cat_started_pacing.emit(entity_id)
```

In game_client.gd, when player clicks button/box:

```gdscript
events.food_dispensed.emit(can_id)
events.box_squeaked.emit(box_id)
```

In food_system.gd, when ARM opens a can:

```gdscript
_events.can_opened.emit(entity_id)
```

- [ ] **Step 5: Commit**

```bash
git add nodes/sound_manager.gd engine/core/events.gd nodes/game_client.gd nodes/game_server.gd engine/core/food_system.gd
git commit -m "feat(sound): meow, squeak, can-pop, button-click audio events"
```

---

### Task 5: Robot narrator — log generation engine

**Files:**
- Create: `engine/core/narrator.gd`
- Create: `tests/unit/test_narrator.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_narrator.gd`:

```gdscript
extends GutTest

var narrator: Narrator


func before_each() -> void:
	narrator = Narrator.new()


func test_status_voice_has_timestamp():
	var log: String = narrator.format_status("Acoustic baseline nominal.")
	assert_true(log.begins_with("["),
		"Status voice should start with timestamp bracket")


func test_first_person_voice_has_no_timestamp():
	var log: String = narrator.format_first_person("I am moving slowly.")
	assert_false(log.begins_with("["),
		"First-person voice should not start with timestamp")


func test_brownout_attribution_never_names_cats():
	var log: String = narrator.format_brownout_cause()
	for banned: String in ["UNIT-C", "UNIT-F", "UNIT-K"]:
		assert_false(log.contains(banned),
			"Brownout attribution must never name individual units, found: %s" % banned)


func test_brownout_cause_from_allowlist():
	var allowlist: Array[String] = [
		"SNACK", "FIRMWARE UPDATE", "SCHEDULED MAINTENANCE",
		"UNKNOWN", "COSMIC RAY", "THERMAL RECALIBRATION",
	]
	for i in 20:
		var cause: String = narrator.pick_brownout_cause()
		assert_true(cause in allowlist,
			"Brownout cause '%s' not in allowlist" % cause)


func test_first_pet_log():
	var log: String = narrator.get_log_for_event(&"first_pet", {&"animal_id": 1})
	assert_true(log.contains("MANUAL CALIBRATION"),
		"First pet log should mention MANUAL CALIBRATION")


func test_cat_departure_log():
	var log: String = narrator.get_log_for_event(&"cat_departed", {&"name": &"Mochi"})
	assert_true(log.contains("departed") or log.contains("standby"),
		"Cat departure log should mention departure")


func test_batch_departure_log_when_multiple():
	var log: String = narrator.get_log_for_event(&"batch_departure", {&"count": 3})
	assert_false(log.contains("UNIT-"),
		"Batch departure should not name individuals")
	assert_true(log.contains("3") or log.contains("Multiple"),
		"Batch departure should mention the count")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `script/checks/gut_tests -f tests/unit/test_narrator.gd`
Expected: FAIL — `Narrator` class not found.

- [ ] **Step 3: Implement Narrator**

Create `engine/core/narrator.gd`:

```gdscript
class_name Narrator extends RefCounted

const BROWNOUT_CAUSES: Array[String] = [
	"SNACK", "FIRMWARE UPDATE", "SCHEDULED MAINTENANCE",
	"UNKNOWN", "COSMIC RAY", "THERMAL RECALIBRATION",
]

var _tick: int = 0
var _first_pet_seen: bool = false


func set_tick(tick: int) -> void:
	_tick = tick


func format_status(message: String) -> String:
	@warning_ignore("integer_division")
	var minutes: int = _tick / 600  # 10Hz * 60s
	@warning_ignore("integer_division")
	var seconds: int = (_tick / 10) % 60
	return "[%02d:%02d] %s" % [minutes, seconds, message]


func format_first_person(message: String) -> String:
	return message


func pick_brownout_cause() -> String:
	return BROWNOUT_CAUSES[randi() % BROWNOUT_CAUSES.size()]


func format_brownout_cause() -> String:
	return "CAUSE: %s" % pick_brownout_cause()


func get_log_for_event(event_type: StringName, data: Dictionary) -> String:
	match event_type:
		&"first_cat_settles":
			var name: StringName = data.get(&"name", &"UNKNOWN")
			return format_status(
				"UNIT-%s has entered chassis. Audible output: 25-30Hz sustained hum. Classifying as healthy disk activity." % name
			)
		&"hum_charging":
			return format_status("Acoustic baseline strengthening. Power conditioning nominal.")
		&"first_brownout":
			return format_status(
				"ADVISORY: Acoustic baseline thinning. Reserve capacitors discharging. Investigating."
			)
		&"deep_brownout":
			return format_first_person(
				"I am moving slowly. I do not know why the devices stopped humming. Please hum."
			)
		&"cat_departed":
			var name: StringName = data.get(&"name", &"UNKNOWN")
			return format_status(
				"UNIT-%s has departed chassis. Reason: unknown. Possible snack." % name
			)
		&"batch_departure":
			var count: int = data.get(&"count", 2)
			return format_status(
				"Multiple devices (%d) entering standby simultaneously. Scheduling group diagnostic." % count
			)
		&"cat_returned":
			var name: StringName = data.get(&"name", &"UNKNOWN")
			return format_status("UNIT-%s has returned. Resuming monitoring." % name)
		&"recovery":
			return format_status(
				"Acoustic baseline restored. Logging this event as ROUTINE BROWNOUT, %s." % format_brownout_cause()
			)
		&"tuna_dispense":
			return format_status("Deploying negotiation asset. The devices have pressed the button.")
		&"arm_opens_can":
			return format_status("Seal altered. Contents: reconfigured. Chemical plume detected.")
		&"first_pet":
			_first_pet_seen = true
			return format_status(
				"UNIT reporting anomalous external stimulus. Satisfaction metrics... improving? Logging as MANUAL CALIBRATION."
			)
	return format_status("Event logged: %s" % event_type)
```

- [ ] **Step 4: Run tests and verify pass**

Run: `script/checks/gut_tests -f tests/unit/test_narrator.gd`
Expected: All 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add engine/core/narrator.gd tests/unit/test_narrator.gd
git commit -m "feat(narrator): log generation engine with voice rules and blame-cat protection"
```

---

### Task 6: Narrator CRT panel (visual)

**Files:**
- Create: `nodes/narrator_panel.gd`
- Modify: `nodes/game_client.gd`

- [ ] **Step 1: Implement NarratorPanel**

Create `nodes/narrator_panel.gd`:

```gdscript
class_name NarratorPanel extends PanelContainer

const MAX_VISIBLE_LINES: int = 3
const MAX_HISTORY: int = 50

var _label: RichTextLabel
var _history: Array[String] = []
var _pinned_log: String = ""
var _events: Events
var _narrator: Narrator


func initialize(events: Events, narrator: Narrator) -> void:
	_events = events
	_narrator = narrator
	_build_ui()
	_events.hum_brownout_entered.connect(_on_brownout_entered)
	_events.hum_brownout_recovered.connect(_on_brownout_recovered)
	_events.hum_reserve_changed.connect(_on_hum_reserve_changed)


func _build_ui() -> void:
	# CRT-style panel: dark background, green text, monospace
	custom_minimum_size = Vector2(280, 48)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.05, 0.9)
	style.border_color = Color(0.2, 0.3, 0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	add_theme_stylebox_override("panel", style)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.add_theme_font_size_override("normal_font_size", 8)
	_label.add_theme_color_override("default_color", Color(0.3, 0.9, 0.3))
	add_child(_label)


func post_log(message: String) -> void:
	_history.append(message)
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	_refresh_display()


func pin_log(message: String) -> void:
	_pinned_log = message
	_refresh_display()


func clear_pin() -> void:
	_pinned_log = ""
	_refresh_display()


func _refresh_display() -> void:
	var lines: Array[String] = []
	if _pinned_log != "":
		lines.append("[b]%s[/b]" % _pinned_log)
	var start: int = maxi(0, _history.size() - MAX_VISIBLE_LINES)
	for i in range(start, _history.size()):
		lines.append(_history[i])
	_label.text = "\n".join(lines)


func _on_brownout_entered() -> void:
	var log: String = _narrator.get_log_for_event(&"first_brownout", {})
	post_log(log)


func _on_brownout_recovered() -> void:
	var log: String = _narrator.get_log_for_event(&"recovery", {})
	post_log(log)


func _on_hum_reserve_changed(_old: int, _new: int) -> void:
	pass  # Could post charging logs on significant changes
```

- [ ] **Step 2: Wire into game_client.gd**

```gdscript
var narrator := Narrator.new()
var narrator_panel := NarratorPanel.new()
narrator_panel.position = Vector2(10, 340)  # bottom-left, above floor
narrator_panel.name = "NarratorPanel"
$HUD.add_child(narrator_panel)
narrator_panel.initialize(game_server.events, narrator)
```

- [ ] **Step 3: Test visually**

Run the game, verify the narrator panel appears and shows logs when HUM events occur.

- [ ] **Step 4: Commit**

```bash
git add nodes/narrator_panel.gd nodes/game_client.gd
git commit -m "feat(narrator): diegetic CRT panel with scrolling log display"
```

---

### Task 7: Stamp all tests and validate

- [ ] **Step 1: Stamp new test files**

```bash
script/stamp_tests tests/unit/test_lighting.gd
script/stamp_tests tests/unit/test_narrator.gd
```

- [ ] **Step 2: Re-stamp any modified files**

Check `script/checks/verify_tests` for stale stamps and re-stamp.

- [ ] **Step 3: Run full validation**

Run: `script/validate`
Expected: All checks pass.

- [ ] **Step 4: Commit**

```bash
git add tests/
git commit -m "chore(tests): stamp feedback and presentation test files"
```

---

## Verification Checklist

After all tasks complete, verify:

- [ ] Lights dim when HUM reserve drops
- [ ] Lights turn red-amber below 25%
- [ ] Lights reach minimum brightness (0.15) at 0%, not full dark
- [ ] HUD bar shows numeric percentage and state glyph
- [ ] HUD glyph changes shape at each threshold (circle/triangle/exclamation)
- [ ] Purr volume tracks HUM reserve, not individual cat count
- [ ] Ambient hum cuts off below 25% reserve
- [ ] Meow plays when cat enters PACING state
- [ ] Squeak plays when player clicks a box
- [ ] Can-pop plays when ARM opens a can
- [ ] Narrator panel shows green-on-dark text
- [ ] Brownout log appears when reserve crosses 25%
- [ ] Recovery log appears when reserve climbs back above 25%
- [ ] Brownout attribution never names individual cats
- [ ] First brownout log is pinned until acknowledged
- [ ] `script/validate` passes

## Audio Assets Needed

These files need to be created (by sound designer or sourced) before full audio works. The sound manager loads them safely — missing files = no crash, just no sound:

| File | Description |
|---|---|
| `mods/tcp_base/sounds/cat/cat_meow_pacing_01.wav` | Hungry/demanding meow |
| `mods/tcp_base/sounds/objects/squeak_toy_01.wav` | Rubber toy chirp (~1-2kHz, 0.3s) |
| `mods/tcp_base/sounds/objects/can_pop_01.wav` | Mechanical pop + warm hum tail |
| `mods/tcp_base/sounds/objects/hum_device_tone.wav` | Warm 80-120Hz resonance loop |
| `mods/tcp_base/sounds/cat/cat_settle_01.wav` | Soft kneading/circling sounds |
| `mods/tcp_base/sounds/objects/button_click_01.wav` | Satisfying mechanical click |
