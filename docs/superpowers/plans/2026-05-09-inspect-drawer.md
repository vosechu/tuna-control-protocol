# Inspect Drawer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the v1 inspect drawer — a left-edge sliding panel that shows Tier-2 desire breakdown (animals) or server stats (servers), triggered by portrait click, right-click world entity, or `I`/`F1`. One drawer at a time, click-portrait re-targets and centers camera, all per `docs/superpowers/specs/2026-05-09-inspect-drawer-design.md`.

**Architecture:** RefCounted state machine (`InspectDrawerState` in `engine/inspect/`) holds id + content type, exposes `process(db) -> view_dict` for per-frame reads. Two Control nodes — `Drawer` (base, in `nodes/hud/drawer.gd`, edge anchoring + slide tween) and `InspectDrawer` (extends Drawer, owns the State, renders the view). One new Events signal `entity_inspect_opened(entity_id)`; HUD-local; never crosses the network boundary.

**Tech Stack:** Godot 4.6.1, GDScript, GUT for tests. Existing autoloads: `Events`, `Constants`. Existing component schema in GameStateDB: `species`, `desires`, `ai_state`, `personality`, `contentment`, `position`, `object_type`, `advertisements`, `hum`.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `engine/inspect/inspect_drawer_state.gd` | **new** | RefCounted state machine + content builders. Pure logic. |
| `nodes/hud/drawer.gd` | **new** | Base Control: edge anchoring, `open()` / `close()` API, slide tween. |
| `nodes/hud/inspect_drawer.gd` | **new** | Extends Drawer. Owns `InspectDrawerState`. Subscribes to `Events.entity_inspect_opened`. Renders the view. |
| `nodes/events.gd` | modify | Add `signal entity_inspect_opened(entity_id: int)`. |
| `nodes/game_client.gd` | modify | Add `_setup_inspect_drawer()` after `_setup_stats_bar()`, before `_setup_debug_hud()`. Wire right-click world-entity → emit. Add `I` / `F1` to `_handle_key`. Track `_last_clicked_entity_id` for keyboard triggers. |
| `nodes/hud/animal_stats_bar.gd` | modify | Replace direct camera-center on portrait click with `Events.entity_inspect_opened.emit()` + co-located camera-center. |
| `tests/unit/test_inspect_drawer_state.gd` | **new** | 15 unit tests. |
| `tests/integration/test_visual_smoke.gd` | modify | Add `test_inspect_drawer_opens_on_event()`. |
| `.claude/rules/scene-tree.md` | modify | Add `InspectDrawer` under HUD. |
| `.claude/rules/file-structure.md` | modify | Add `engine/inspect/` to the canonical tree. |

---

## Task 1: Add `entity_inspect_opened` signal

**Files:**
- Modify: `nodes/events.gd`

- [ ] **Step 1: Add the signal**

Open `nodes/events.gd` and add this block near the existing signal groups (after `creature_petted` / `box_squeaked`, before `# Plant growth`):

```gdscript
# Inspect (HUD-local; never serialized over the network)
signal entity_inspect_opened(entity_id: int)
```

- [ ] **Step 2: Validate**

```bash
script/validate
```

Expected: 14/14 pass.

- [ ] **Step 3: Commit**

```bash
git add nodes/events.gd
git commit -m "$(cat <<'EOF'
feat(events): add entity_inspect_opened signal

HUD-local trigger for the inspect drawer. Per the inspect-drawer
spec, emitted by portrait clicks, right-click world entity, and
keyboard I/F1.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `InspectDrawerState` — state machine basics (tests 1-5)

**Files:**
- Create: `engine/inspect/inspect_drawer_state.gd`
- Create: `tests/unit/test_inspect_drawer_state.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/unit/test_inspect_drawer_state.gd`:

```gdscript
extends GutTest

const InspectDrawerState := preload("res://engine/inspect/inspect_drawer_state.gd")


func test_new_state_is_closed() -> void:
	var state := InspectDrawerState.new()
	assert_eq(state.inspected_id, Constants.INVALID_ID)
	assert_false(state.is_open())


func test_open_with_valid_id_sets_open() -> void:
	var state := InspectDrawerState.new()
	state.open(42)
	assert_eq(state.inspected_id, 42)
	assert_true(state.is_open())


func test_open_while_open_retargets() -> void:
	var state := InspectDrawerState.new()
	state.open(42)
	state.open(43)
	assert_eq(state.inspected_id, 43)
	assert_true(state.is_open())


func test_open_with_invalid_id_is_noop() -> void:
	var state := InspectDrawerState.new()
	state.open(Constants.INVALID_ID)
	assert_eq(state.inspected_id, Constants.INVALID_ID)
	assert_false(state.is_open())


func test_close_resets() -> void:
	var state := InspectDrawerState.new()
	state.open(42)
	state.close()
	assert_eq(state.inspected_id, Constants.INVALID_ID)
	assert_false(state.is_open())
```

- [ ] **Step 2: Run, verify failure**

```bash
script/checks/gut_tests -f tests/unit/test_inspect_drawer_state.gd
```

Expected: parse error (file `engine/inspect/inspect_drawer_state.gd` does not exist).

- [ ] **Step 3: Create the implementation**

Create `engine/inspect/inspect_drawer_state.gd`:

```gdscript
class_name InspectDrawerState extends RefCounted

# State machine + content builders for the inspect drawer.
# Pure RefCounted — no scene tree, no signals.
# Per docs/superpowers/specs/2026-05-09-inspect-drawer-design.md.

enum ContentType { CLOSED, ANIMAL, SERVER }

var inspected_id: int = Constants.INVALID_ID
var content_type: int = ContentType.CLOSED


func open(entity_id: int) -> void:
	if entity_id == Constants.INVALID_ID:
		return
	inspected_id = entity_id


func close() -> void:
	inspected_id = Constants.INVALID_ID
	content_type = ContentType.CLOSED


func is_open() -> bool:
	return inspected_id != Constants.INVALID_ID
```

- [ ] **Step 4: Run, verify pass**

```bash
script/checks/gut_tests -f tests/unit/test_inspect_drawer_state.gd
```

Expected: 5/5 passing.

- [ ] **Step 5: Stamp the test file via /verify-test**

Invoke the `/verify-test` skill on `tests/unit/test_inspect_drawer_state.gd`. This runs the red-green stamp protocol and writes the hash seal.

- [ ] **Step 6: Commit**

```bash
git add engine/inspect/inspect_drawer_state.gd \
        tests/unit/test_inspect_drawer_state.gd \
        tests/unit/test_inspect_drawer_state.gd.uid
git commit -m "$(cat <<'EOF'
feat(inspect): InspectDrawerState skeleton + state machine

Open/close/re-target API. Pure RefCounted; uses Constants.INVALID_ID
sentinel. No scene tree dependency.

Tests cover: closed-by-default, open with valid id, re-target,
INVALID_ID no-op, close-resets. Five tests stamped.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `process(db)` with auto-close (tests 6-7)

**Files:**
- Modify: `engine/inspect/inspect_drawer_state.gd`
- Modify: `tests/unit/test_inspect_drawer_state.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_inspect_drawer_state.gd`:

```gdscript
func test_process_after_destroy_closes_state() -> void:
	var db := GameStateDB.new()
	var entity_id: int = db.create_entity()
	db.set_component(entity_id, &"desires", {&"warmth": 500})
	var state := InspectDrawerState.new()
	state.open(entity_id)
	# Process once with the entity alive — state stays open.
	state.process(db)
	assert_true(state.is_open())
	# Destroy the entity — next process should close the drawer.
	db.destroy_entity(entity_id)
	state.process(db)
	assert_false(state.is_open())
	assert_eq(state.inspected_id, Constants.INVALID_ID)


func test_process_while_closed_is_noop() -> void:
	var db := GameStateDB.new()
	var state := InspectDrawerState.new()
	# No exception, no state change, just an early return.
	state.process(db)
	assert_false(state.is_open())
	assert_eq(state.content_type, InspectDrawerState.ContentType.CLOSED)
```

- [ ] **Step 2: Run, verify failure**

```bash
script/checks/gut_tests -f tests/unit/test_inspect_drawer_state.gd
```

Expected: 2 failures — `process` method does not exist.

- [ ] **Step 3: Add `process()` to the state class**

Append to `engine/inspect/inspect_drawer_state.gd`:

```gdscript
# Per-frame poll. Called from the InspectDrawer Control's _process.
# Has-entity check FIRST, then component reads — no stale-state frame.
func process(db: GameStateDB) -> void:
	if inspected_id == Constants.INVALID_ID:
		return
	if not db.has_entity(inspected_id):
		close()
		return
	# Capability dispatch happens in Task 4.
```

- [ ] **Step 4: Run, verify pass**

```bash
script/checks/gut_tests -f tests/unit/test_inspect_drawer_state.gd
```

Expected: 7/7 passing.

- [ ] **Step 5: Re-stamp via /verify-test**

Test file changed; re-stamp.

- [ ] **Step 6: Commit**

```bash
git add engine/inspect/inspect_drawer_state.gd \
        tests/unit/test_inspect_drawer_state.gd \
        tests/unit/test_inspect_drawer_state.gd.uid
git commit -m "$(cat <<'EOF'
feat(inspect): per-frame process() with auto-close

Per spec: has_entity check FIRST so destroyed entities never produce
a stale-state frame. process() while closed is a cheap early-return.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Capability branch for content type (tests 8-10)

**Files:**
- Modify: `engine/inspect/inspect_drawer_state.gd`
- Modify: `tests/unit/test_inspect_drawer_state.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_inspect_drawer_state.gd`:

```gdscript
func test_process_animal_sets_content_animal() -> void:
	var db := GameStateDB.new()
	var animal_id: int = db.create_entity()
	db.set_component(animal_id, &"desires", {&"warmth": 500})
	var state := InspectDrawerState.new()
	state.open(animal_id)
	state.process(db)
	assert_eq(state.content_type, InspectDrawerState.ContentType.ANIMAL)


func test_process_server_sets_content_server() -> void:
	var db := GameStateDB.new()
	var server_id: int = db.create_entity()
	db.set_component(server_id, &"object_type", {&"type": &"server_1u"})
	var state := InspectDrawerState.new()
	state.open(server_id)
	state.process(db)
	assert_eq(state.content_type, InspectDrawerState.ContentType.SERVER)


func test_process_neither_capability_closes() -> void:
	var db := GameStateDB.new()
	# Entity has no `desires` and no `object_type` — defensive close.
	var orphan_id: int = db.create_entity()
	var state := InspectDrawerState.new()
	state.open(orphan_id)
	state.process(db)
	assert_false(state.is_open())
	assert_eq(state.content_type, InspectDrawerState.ContentType.CLOSED)
```

- [ ] **Step 2: Run, verify failure**

```bash
script/checks/gut_tests -f tests/unit/test_inspect_drawer_state.gd
```

Expected: 3 failures — content_type stays CLOSED for all three.

- [ ] **Step 3: Add capability branch to `process()`**

Replace the `process()` body in `engine/inspect/inspect_drawer_state.gd` with:

```gdscript
func process(db: GameStateDB) -> void:
	if inspected_id == Constants.INVALID_ID:
		return
	if not db.has_entity(inspected_id):
		close()
		return
	# Capability dispatch — never branch on species labels.
	if db.has_component(inspected_id, &"desires"):
		content_type = ContentType.ANIMAL
	elif db.has_component(inspected_id, &"object_type"):
		content_type = ContentType.SERVER
	else:
		close()
```

- [ ] **Step 4: Run, verify pass**

```bash
script/checks/gut_tests -f tests/unit/test_inspect_drawer_state.gd
```

Expected: 10/10 passing.

- [ ] **Step 5: Re-stamp via /verify-test**

- [ ] **Step 6: Commit**

```bash
git add engine/inspect/inspect_drawer_state.gd \
        tests/unit/test_inspect_drawer_state.gd \
        tests/unit/test_inspect_drawer_state.gd.uid
git commit -m "$(cat <<'EOF'
feat(inspect): capability dispatch (animal vs server vs closed)

Branches on has_component(&\"desires\") for animals, has_component(
&\"object_type\") for servers, defensive close otherwise. Never reads
species labels — passes the no_species_dispatch check.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Status keyword derivation (tests 11-14)

**Files:**
- Modify: `engine/inspect/inspect_drawer_state.gd`
- Modify: `tests/unit/test_inspect_drawer_state.gd`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_inspect_drawer_state.gd`:

```gdscript
func test_animal_content_when_satisfied() -> void:
	var db := GameStateDB.new()
	var animal_id: int = db.create_entity()
	db.set_component(animal_id, &"desires", {&"warmth": 800})
	db.set_component(animal_id, &"contentment", {&"is_satisfied": 1})
	var state := InspectDrawerState.new()
	state.open(animal_id)
	state.process(db)
	assert_eq(state.derive_status_keyword(db), &"Content")


func test_animal_wanting_when_unsatisfied() -> void:
	var db := GameStateDB.new()
	var animal_id: int = db.create_entity()
	db.set_component(animal_id, &"desires", {&"warmth": 100})
	db.set_component(animal_id, &"contentment", {&"is_satisfied": 0})
	var state := InspectDrawerState.new()
	state.open(animal_id)
	state.process(db)
	assert_eq(state.derive_status_keyword(db), &"Wanting")


func test_server_powered_when_any_hum_has_reserve() -> void:
	var db := GameStateDB.new()
	var server_id: int = db.create_entity()
	db.set_component(server_id, &"object_type", {&"type": &"server_1u"})
	var hum_id: int = db.create_entity()
	db.set_component(hum_id, &"hum", {&"reserve": 500, &"capacity": 1000})
	var state := InspectDrawerState.new()
	state.open(server_id)
	state.process(db)
	assert_eq(state.derive_status_keyword(db), &"Powered")


func test_server_unpowered_when_all_hum_at_zero() -> void:
	var db := GameStateDB.new()
	var server_id: int = db.create_entity()
	db.set_component(server_id, &"object_type", {&"type": &"server_1u"})
	var hum_id: int = db.create_entity()
	db.set_component(hum_id, &"hum", {&"reserve": 0, &"capacity": 1000})
	var state := InspectDrawerState.new()
	state.open(server_id)
	state.process(db)
	assert_eq(state.derive_status_keyword(db), &"Unpowered")
```

- [ ] **Step 2: Run, verify failure**

```bash
script/checks/gut_tests -f tests/unit/test_inspect_drawer_state.gd
```

Expected: 4 failures — `derive_status_keyword` does not exist.

- [ ] **Step 3: Implement the method**

Append to `engine/inspect/inspect_drawer_state.gd`:

```gdscript
func derive_status_keyword(db: GameStateDB) -> StringName:
	if content_type == ContentType.ANIMAL:
		if not db.has_component(inspected_id, &"contentment"):
			return &"Wanting"
		var c: Dictionary = db.get_component(inspected_id, &"contentment")
		if int(c.get(&"is_satisfied", 0)) == 1:
			return &"Content"
		return &"Wanting"
	if content_type == ContentType.SERVER:
		# Powered iff any HUM in the world has reserve > 0.
		# Cables are out today — when they return, route per-device.
		for hum_id: int in db.get_entities_with(&"hum"):
			var h: Dictionary = db.get_component(hum_id, &"hum")
			if int(h.get(&"reserve", 0)) > 0:
				return &"Powered"
		return &"Unpowered"
	return &""
```

- [ ] **Step 4: Run, verify pass**

```bash
script/checks/gut_tests -f tests/unit/test_inspect_drawer_state.gd
```

Expected: 14/14 passing.

- [ ] **Step 5: Re-stamp via /verify-test**

- [ ] **Step 6: Commit**

```bash
git add engine/inspect/inspect_drawer_state.gd \
        tests/unit/test_inspect_drawer_state.gd \
        tests/unit/test_inspect_drawer_state.gd.uid
git commit -m "$(cat <<'EOF'
feat(inspect): derive_status_keyword for animals + servers

Animals: Content/Wanting from contentment.is_satisfied. Servers:
Powered if any HUM has reserve > 0, else Unpowered. Drawer reads the
contentment system as-is; doesn't second-guess the aggregation.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Trigger-race semantics (test 15)

**Files:**
- Modify: `tests/unit/test_inspect_drawer_state.gd`

The current `open()` already implements last-write-wins (test 3 covered re-target after `process`); test 15 documents that two `open()` calls without an intervening `process()` work the same way.

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_inspect_drawer_state.gd`:

```gdscript
func test_two_opens_in_one_frame_last_wins() -> void:
	# Trigger-race contract: when two emissions happen in the same frame,
	# the last one binds. The drawer's slide tween (in the Control wrapper)
	# does not restart on re-target — it just rebinds the entity_id.
	var state := InspectDrawerState.new()
	state.open(42)
	state.open(99)
	# No process() between — direct re-target.
	assert_eq(state.inspected_id, 99)
	assert_true(state.is_open())
```

- [ ] **Step 2: Run, verify pass directly**

```bash
script/checks/gut_tests -f tests/unit/test_inspect_drawer_state.gd
```

Expected: 15/15 passing. (The behavior was already correct; the test pins the contract so a future "open ignores while already open" regression is caught.)

- [ ] **Step 3: Re-stamp via /verify-test**

- [ ] **Step 4: Commit**

```bash
git add tests/unit/test_inspect_drawer_state.gd \
        tests/unit/test_inspect_drawer_state.gd.uid
git commit -m "$(cat <<'EOF'
test(inspect): pin trigger-race contract

Two open() calls in one frame — last wins. The behavior was already
correct; this test guards against a future "ignore re-target while
open" regression.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `Drawer` base Control primitive

**Files:**
- Create: `nodes/hud/drawer.gd`

This is a Control with a scene-tree dependency, so it has no unit tests. Coverage comes from the integration smoke test in Task 12. Its API is intentionally tiny: `open()`, `close()`, `is_open()`, an `_anchor_edge` enum.

- [ ] **Step 1: Write the implementation**

Create `nodes/hud/drawer.gd`:

```gdscript
class_name Drawer extends Control

# Base for HUD drawers. Subclasses (InspectDrawer, future
# PlacementDrawer, NarratorDrawer) inherit edge anchoring + slide
# tween. Per docs/superpowers/specs/2026-05-09-inspect-drawer-design.md
# §"The drawer primitive".

enum AnchorEdge { LEFT, RIGHT, BOTTOM }

const _SLIDE_SECONDS: float = 0.15

@export var anchor_edge: AnchorEdge = AnchorEdge.LEFT
@export var open_position: Vector2 = Vector2.ZERO

var _is_open: bool = false
var _closed_position: Vector2 = Vector2.ZERO
var _tween: Tween


func _ready() -> void:
	_closed_position = _compute_closed_position()
	# Start hidden off-edge.
	position = _closed_position
	visible = false


func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "position", open_position, _SLIDE_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "position", _closed_position, _SLIDE_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void: visible = false)


func is_open() -> bool:
	return _is_open


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _compute_closed_position() -> Vector2:
	# Fully off-screen along the anchored edge.
	var w: float = float(size.x if size.x > 0.0 else custom_minimum_size.x)
	var h: float = float(size.y if size.y > 0.0 else custom_minimum_size.y)
	match anchor_edge:
		AnchorEdge.LEFT:
			return Vector2(open_position.x - w, open_position.y)
		AnchorEdge.RIGHT:
			return Vector2(open_position.x + w, open_position.y)
		AnchorEdge.BOTTOM:
			return Vector2(open_position.x, open_position.y + h)
	return open_position
```

- [ ] **Step 2: Validate (parse only — Drawer never instantiated yet)**

```bash
script/validate
```

Expected: 14/14 pass. (Parse check is the main gate; Drawer's behaviour is exercised in Task 12.)

- [ ] **Step 3: Commit**

```bash
git add nodes/hud/drawer.gd nodes/hud/drawer.gd.uid
git commit -m "$(cat <<'EOF'
feat(hud): Drawer base Control primitive

Edge anchoring (left/right/bottom), open/close API, 0.15s slide tween.
No unit tests — exercised via integration smoke test. Future placement
and narrator drawers inherit this.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: `InspectDrawer` Control wrapper

**Files:**
- Create: `nodes/hud/inspect_drawer.gd`

- [ ] **Step 1: Write the implementation**

Create `nodes/hud/inspect_drawer.gd`:

```gdscript
class_name InspectDrawer extends Drawer

# Per docs/superpowers/specs/2026-05-09-inspect-drawer-design.md.
# Reads InspectDrawerState per-frame; renders header + bars + action +
# personality. HUD-only consumer; never writes to GameStateDB.

const _DESIRE_KEYS: Array[StringName] = [
	&"warmth", &"comfort", &"curiosity", &"hunger",
	&"social", &"quiet", &"peace", &"safety",
]
const _DESIRE_LABELS: Dictionary = {
	&"warmth": "Warmth", &"comfort": "Comfort",
	&"curiosity": "Curiosity", &"hunger": "Hunger",
	&"social": "Social", &"quiet": "Quiet",
	&"peace": "Peace", &"safety": "Safety",
}
const _DESIRE_COLORS: Dictionary = {
	&"warmth":    Color(0.85, 0.35, 0.20),
	&"comfort":   Color(0.45, 0.65, 0.85),
	&"curiosity": Color(0.60, 0.80, 0.30),
	&"hunger":    Color(0.90, 0.55, 0.20),
	&"social":    Color(0.95, 0.50, 0.65),
	&"quiet":     Color(0.30, 0.45, 0.75),
	&"peace":     Color(0.65, 0.50, 0.85),
	&"safety":    Color(0.40, 0.75, 0.45),
}
const _BAR_WIDTH: int = 36
const _BAR_HEIGHT: int = 3
const _FONT_SIZE: int = 3

var _db: GameStateDB
var _state: InspectDrawerState

var _header_label: Label
var _status_label: Label
var _bars_container: VBoxContainer
var _bar_fills: Dictionary = {}  # StringName -> ColorRect
var _bar_values: Dictionary = {}  # StringName -> Label
var _action_label: Label
var _personality_label: Label


func initialize(db: GameStateDB) -> void:
	_db = db
	_state = InspectDrawerState.new()
	custom_minimum_size = Vector2(56, 72)
	anchor_edge = Drawer.AnchorEdge.LEFT
	open_position = Vector2(2, 54)
	_build_ui()
	Events.entity_inspect_opened.connect(_on_entity_inspect_opened)


func _build_ui() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.10, 0.15, 0.92)
	bg.border_color = Color(0.25, 0.30, 0.40)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.position = Vector2(2, 2)
	add_child(vbox)

	_header_label = _make_label(_FONT_SIZE, Color(0.9, 0.85, 0.7))
	vbox.add_child(_header_label)

	_status_label = _make_label(_FONT_SIZE, Color(0.7, 0.85, 0.7))
	vbox.add_child(_status_label)

	_bars_container = VBoxContainer.new()
	_bars_container.add_theme_constant_override("separation", 0)
	vbox.add_child(_bars_container)

	for key: StringName in _DESIRE_KEYS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		var lbl := _make_label(_FONT_SIZE, Color(0.7, 0.7, 0.75))
		lbl.text = String(_DESIRE_LABELS[key])
		lbl.custom_minimum_size = Vector2(14, _BAR_HEIGHT)
		row.add_child(lbl)
		var bg_rect := ColorRect.new()
		bg_rect.color = Color(0.15, 0.15, 0.20)
		bg_rect.custom_minimum_size = Vector2(_BAR_WIDTH, _BAR_HEIGHT)
		var fill := ColorRect.new()
		fill.color = _DESIRE_COLORS[key]
		fill.size = Vector2(0, _BAR_HEIGHT)
		fill.position = Vector2.ZERO
		bg_rect.add_child(fill)
		row.add_child(bg_rect)
		var val := _make_label(_FONT_SIZE, Color(0.85, 0.85, 0.9))
		row.add_child(val)
		_bar_fills[key] = fill
		_bar_values[key] = val
		_bars_container.add_child(row)

	_action_label = _make_label(_FONT_SIZE, Color(0.85, 0.7, 0.95))
	vbox.add_child(_action_label)

	_personality_label = _make_label(_FONT_SIZE, Color(0.6, 0.7, 0.75))
	_personality_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_personality_label.custom_minimum_size = Vector2(52, 0)
	vbox.add_child(_personality_label)


func _make_label(font_size: int, font_color: Color) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", font_color)
	return lbl


func _on_entity_inspect_opened(entity_id: int) -> void:
	if _state.is_open() and _state.inspected_id == entity_id:
		# Toggle: same entity already inspected → close.
		_state.close()
		close()
		return
	_state.open(entity_id)
	open()


func _process(_delta: float) -> void:
	if _db == null or _state == null:
		return
	if not _state.is_open():
		return
	_state.process(_db)
	if not _state.is_open():
		# process() may have auto-closed due to entity destruction.
		close()
		return
	_render_view()


func _render_view() -> void:
	if _state.content_type == InspectDrawerState.ContentType.ANIMAL:
		_render_animal()
	elif _state.content_type == InspectDrawerState.ContentType.SERVER:
		_render_server()


func _render_animal() -> void:
	var id: int = _state.inspected_id
	var species: Dictionary = _db.get_component(id, &"species")
	_header_label.text = String(species.get(&"name", &"???"))
	if _db.has_component(id, &"hud_color"):
		var c: Dictionary = _db.get_component(id, &"hud_color")
		_header_label.add_theme_color_override(
			"font_color", Color(c[&"r"], c[&"g"], c[&"b"]),
		)
	_status_label.text = String(_state.derive_status_keyword(_db))
	_bars_container.visible = true
	if _db.has_component(id, &"desires"):
		var desires: Dictionary = _db.get_component(id, &"desires")
		for key: StringName in _DESIRE_KEYS:
			var v: int = int(desires.get(key, 0))
			var ratio: float = clamp(float(v) / 1000.0, 0.0, 1.0)
			(_bar_fills[key] as ColorRect).size = Vector2(
				_BAR_WIDTH * ratio, _BAR_HEIGHT,
			)
			(_bar_values[key] as Label).text = "%d" % v
	if _db.has_component(id, &"ai_state"):
		var ai: Dictionary = _db.get_component(id, &"ai_state")
		_action_label.text = String(ai.get(&"state", &"")).to_lower()
	if _db.has_component(id, &"personality"):
		var p: Dictionary = _db.get_component(id, &"personality")
		var parts: Array[String] = []
		for key: StringName in _DESIRE_KEYS:
			var pkey: StringName = StringName(String(key) + "_weight")
			parts.append("%s %d" % [_DESIRE_LABELS[key], int(p.get(pkey, 0)) / 100])
		_personality_label.text = "  ".join(parts)


func _render_server() -> void:
	var id: int = _state.inspected_id
	var pos: Dictionary = _db.get_component(id, &"position")
	var query: SlotQuery = Constants.bay_local_to_slot(
		Constants.world_to_bay(Vector2i(int(pos[&"x"]), int(pos[&"y"]))),
		Vector2i(int(pos[&"x"]), int(pos[&"y"])),
	)
	_header_label.text = "Server %d/%d" % [query.get_rack(), query.get_slot()]
	_status_label.text = String(_state.derive_status_keyword(_db))
	_bars_container.visible = false
	# Heat output from advertisements (channel == &"warmth").
	var heat_strength: int = 0
	var heat_radius: int = 0
	if _db.has_component(id, &"advertisements"):
		var ads: Dictionary = _db.get_component(id, &"advertisements")
		for ad: Dictionary in ads.get(&"list", []):
			if ad.get(&"channel", &"") == &"warmth":
				heat_strength = int(ad.get(&"strength", 0))
				heat_radius = int(ad.get(&"effect_radius_px", 0))
				break
	# Nearby animals.
	var nearby: Array[int] = _db.query_radius_with(
		int(pos[&"x"]), int(pos[&"y"]),
		Constants.BAY_WIDTH_PX, &"desires",
	)
	_action_label.text = "Heat %d  r%dpx  near %d" % [
		heat_strength, heat_radius, nearby.size(),
	]
	# Mock fan speed (~ prefix marks placeholder per spec §Content).
	_personality_label.text = "~ Fan: 1200 RPM"
```

- [ ] **Step 2: Validate**

```bash
script/validate
```

Expected: 14/14 pass.

- [ ] **Step 3: Commit**

```bash
git add nodes/hud/inspect_drawer.gd nodes/hud/inspect_drawer.gd.uid
git commit -m "$(cat <<'EOF'
feat(hud): InspectDrawer Control — renders InspectDrawerState

Subscribes to Events.entity_inspect_opened. Re-targeting on the same
entity toggles closed. Renders animal layout (header, status, 8
desire bars, ai_state, personality) or server layout (slot label,
power state, heat output, nearby animals, mock fan). All branching
on capability presence — no species labels.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Wire `_setup_inspect_drawer()` in game_client

**Files:**
- Modify: `nodes/game_client.gd`

- [ ] **Step 1: Add the preload constant**

After the existing `const _PURR_RING_SCRIPT := preload(...)` line in `nodes/game_client.gd`, add:

```gdscript
const _INSPECT_DRAWER_SCRIPT := preload("res://nodes/hud/inspect_drawer.gd")
```

- [ ] **Step 2: Add `_setup_inspect_drawer()`**

In `nodes/game_client.gd`, add a new function (place it near `_setup_stats_bar()`):

```gdscript
func _setup_inspect_drawer() -> void:
	if not has_node("HUD"):
		var hud := CanvasLayer.new()
		hud.name = "HUD"
		add_child(hud)
	var drawer: Drawer = PanelContainer.new()
	drawer.set_script(_INSPECT_DRAWER_SCRIPT)
	drawer.name = "InspectDrawer"
	$HUD.add_child(drawer)
	drawer.initialize(game_server.db)
```

- [ ] **Step 3: Call it in `_ready()`**

In `_ready()`, between `_setup_stats_bar()` and `_setup_narrator_panel()`, add the new call:

```gdscript
	_setup_stats_bar()
	_setup_inspect_drawer()
	_setup_narrator_panel()
	_setup_debug_hud()
```

- [ ] **Step 4: Validate**

```bash
script/validate
```

Expected: 14/14 pass.

- [ ] **Step 5: Commit**

```bash
git add nodes/game_client.gd
git commit -m "$(cat <<'EOF'
feat(client): wire _setup_inspect_drawer between stats_bar and narrator

Per spec, ordering matters: after _setup_stats_bar (the portrait
emitter exists) and before _setup_debug_hud (which has a TODO for an
inspect ref).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Portrait click → emit + camera

**Files:**
- Modify: `nodes/hud/animal_stats_bar.gd`

- [ ] **Step 1: Locate the existing `_on_panel_clicked` handler**

The current implementation in `nodes/hud/animal_stats_bar.gd` centers the camera on a portrait click:

```gdscript
func _on_panel_clicked(
	event: InputEvent, entity_id: int,
) -> void:
	if not event is InputEventMouseButton:
		return
	if not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _db.has_entity(entity_id):
		return
	var pos: Dictionary = _db.get_component(
		entity_id, &"position",
	)
	_camera.position = Vector2(
		float(pos[&"x"]) + float(Constants.RACK_WIDTH_PX / 2),
		float(pos[&"y"]),
	)
```

- [ ] **Step 2: Add the emission alongside the camera-center**

Replace the body of `_on_panel_clicked` so it emits the inspect event in addition to the camera-center side-effect (per spec, both happen on portrait click):

```gdscript
func _on_panel_clicked(
	event: InputEvent, entity_id: int,
) -> void:
	if not event is InputEventMouseButton:
		return
	if not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _db.has_entity(entity_id):
		return
	# Per spec: portrait click fires inspect AND centers the camera.
	# Co-located here so the drawer never reaches into camera state.
	Events.entity_inspect_opened.emit(entity_id)
	var pos: Dictionary = _db.get_component(
		entity_id, &"position",
	)
	_camera.position = Vector2(
		float(pos[&"x"]) + float(Constants.RACK_WIDTH_PX / 2),
		float(pos[&"y"]),
	)
```

- [ ] **Step 3: Validate**

```bash
script/validate
```

Expected: 14/14 pass.

- [ ] **Step 4: Commit**

```bash
git add nodes/hud/animal_stats_bar.gd
git commit -m "$(cat <<'EOF'
feat(hud): portrait click emits entity_inspect_opened + camera-center

Per spec, the portrait click is the only trigger that pairs inspect
with camera-center. Co-located here (not inside the drawer) so the
drawer stays pure HUD with no reach into camera state.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Right-click world entity, `I` / `F1` keyboard triggers

**Files:**
- Modify: `nodes/game_client.gd`

- [ ] **Step 1: Add a `_last_clicked_entity_id` field**

Near the other vars at the top of `nodes/game_client.gd`, add:

```gdscript
var _last_clicked_entity_id: int = Constants.INVALID_ID
```

- [ ] **Step 2: Track last-clicked in `_try_click_entity`**

In `_try_click_entity` (the existing left-click handler), after the existing `if game_server.db.has_component(entity_id, &"species"):` branch, set `_last_clicked_entity_id = entity_id`. Refactor the function so the assignment runs whenever a clickable entity is found:

```gdscript
func _try_click_entity(world_pos: Vector2) -> void:
	var click_px := Vector2i(roundi(world_pos.x), roundi(world_pos.y))
	var nearby: Array[int] = game_server.db.query_radius(
		click_px.x, click_px.y, 2 * Constants.SLOT_HEIGHT_PX,
	)
	for entity_id: int in nearby:
		if game_server.db.has_component(entity_id, &"tuna_button"):
			_last_clicked_entity_id = entity_id
			var can_id: int = (
				game_server.food_system.press_button(entity_id)
			)
			if can_id != Constants.INVALID_ID:
				Events.food_dispensed.emit(can_id)
			return
		if game_server.db.has_component(entity_id, &"species"):
			_last_clicked_entity_id = entity_id
			_pet_animal(entity_id)
			return
		if game_server.db.has_component(entity_id, &"object_type"):
			_last_clicked_entity_id = entity_id
			var otype: Dictionary = (
				game_server.db.get_component(entity_id, &"object_type")
			)
			if otype[&"type"] == &"cardboard_box":
				_squeak_box(entity_id)
				return
```

- [ ] **Step 3: Add right-click-world emit in `_unhandled_input`**

In `_unhandled_input`, before the existing left-click branch, add a right-click-emits-inspect branch:

```gdscript
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			var camera_rc: Camera2D = $Camera
			var world_pos_rc: Vector2 = camera_rc.get_global_mouse_position()
			var click_px := Vector2i(
				roundi(world_pos_rc.x), roundi(world_pos_rc.y),
			)
			var nearby: Array[int] = game_server.db.query_radius(
				click_px.x, click_px.y, 2 * Constants.SLOT_HEIGHT_PX,
			)
			for eid: int in nearby:
				if (
					game_server.db.has_component(eid, &"species")
					or game_server.db.has_component(eid, &"object_type")
				):
					_last_clicked_entity_id = eid
					Events.entity_inspect_opened.emit(eid)
					return
			return
```

- [ ] **Step 4: Add `I` / `F1` to `_handle_key`**

In `_handle_key`, add an `I`/`F1` branch that emits using the last-clicked entity:

```gdscript
	if event.keycode == KEY_I or event.keycode == KEY_F1:
		if _last_clicked_entity_id != Constants.INVALID_ID:
			Events.entity_inspect_opened.emit(_last_clicked_entity_id)
		return true
```

Place this branch alongside the other key branches inside `_handle_key`, before the final `return false`.

- [ ] **Step 5: Validate**

```bash
script/validate
```

Expected: 14/14 pass. (If `_handle_key` exceeds the 6-return lint cap, extract another helper or consolidate branches; recent precedent in `nodes/game_client.gd` already shows the helper-extraction pattern.)

- [ ] **Step 6: Commit**

```bash
git add nodes/game_client.gd
git commit -m "$(cat <<'EOF'
feat(client): right-click and I/F1 emit entity_inspect_opened

Right-click on an entity in the world: emit inspect for that entity.
I or F1 keyboard: emit for the last-clicked entity (focus = last
click for v1 per spec). Tracks _last_clicked_entity_id whenever a
clickable entity is hit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Integration test extension

**Files:**
- Modify: `tests/integration/test_visual_smoke.gd`

- [ ] **Step 1: Add a new test method**

At the end of `tests/integration/test_visual_smoke.gd`, append:

```gdscript
func test_inspect_drawer_opens_on_event() -> void:
	var scene: PackedScene = preload("res://nodes/main.tscn")
	var client: Node = scene.instantiate()
	add_child_autofree(client)
	await get_tree().process_frame

	var drawer: Control = client.get_node("GameClient/HUD/InspectDrawer")
	assert_not_null(drawer, "InspectDrawer should exist under HUD")
	assert_false(drawer.is_open(), "Drawer is closed at boot")

	# Pick any spawned animal id.
	var server: Node = client.get_node("GameClient").game_server
	var db: GameStateDB = server.db
	var animals: Array[int] = db.get_entities_with(&"sprite_config")
	assert_gt(animals.size(), 0, "At least one animal should spawn")

	Events.entity_inspect_opened.emit(animals[0])
	await get_tree().process_frame

	assert_true(drawer.is_open(), "Drawer opens on emit")
	assert_eq(drawer._state.inspected_id, animals[0])
```

- [ ] **Step 2: Run the integration test**

```bash
script/checks/gut_tests -f tests/integration/test_visual_smoke.gd
```

Expected: both tests pass (the existing `test_main_scene_boot_state` plus the new one).

- [ ] **Step 3: Commit**

```bash
git add tests/integration/test_visual_smoke.gd
git commit -m "$(cat <<'EOF'
test(integration): inspect drawer opens on Events emit

Extends the existing visual-smoke test with one assertion block. No
new integration file; reuses existing scene-boot setup.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Documentation updates

**Files:**
- Modify: `.claude/rules/scene-tree.md`
- Modify: `.claude/rules/file-structure.md`

- [ ] **Step 1: Update `scene-tree.md`**

In `.claude/rules/scene-tree.md`, find the HUD block (the one listing `HumBar`, `StatsBar`, `NarratorPanel`, `PlacementUI`, `InspectPanel`). Replace `InspectPanel (PanelContainer)     # On right-click / I / X (planned)` with:

```
      InspectDrawer (Control)           # Tier-2 inspect (left edge)
```

- [ ] **Step 2: Update `file-structure.md`**

In `.claude/rules/file-structure.md`, in the `engine/` block, add an `inspect/` entry alongside the other system directories:

```
    inspect/                       # Inspect drawer state (RefCounted)
      inspect_drawer_state.gd      # State machine + content builders
```

Place it alphabetically (between `economy/` and `mod/`, or wherever the project's existing alpha order indicates).

- [ ] **Step 3: Validate**

```bash
script/validate
```

Expected: 14/14 pass.

- [ ] **Step 4: Commit**

```bash
git add .claude/rules/scene-tree.md .claude/rules/file-structure.md
git commit -m "$(cat <<'EOF'
docs(rules): scene-tree + file-structure reflect InspectDrawer

InspectDrawer takes InspectPanel's slot under HUD. engine/inspect/
joins the canonical engine/ tree.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: Full close-affordance set (ESC, `X` button, click-outside, controller `B`)

**Files:**
- Modify: `nodes/hud/inspect_drawer.gd` (add header `X` button + `_close_drawer()` helper)
- Modify: `nodes/game_client.gd` (`ui_cancel` action handling + outside-click detection)

Toggle-via-re-emit (already in Task 8) handled the trivial close; this task ships the four explicit affordances the spec lists. Godot's default `ui_cancel` action covers both `ESC` and the controller `B` button in one path, so we get controller parity with one branch.

- [ ] **Step 1: Add a `_close_drawer()` helper to `InspectDrawer`**

In `nodes/hud/inspect_drawer.gd`, near the existing `_on_entity_inspect_opened` handler, add:

```gdscript
# Single source of truth for closing — used by the X button, click-outside,
# ESC, controller B, and entity-destroy auto-close.
func _close_drawer() -> void:
	if _state == null:
		return
	_state.close()
	close()
```

Also update `_process` to call this helper instead of `close()` directly:

```gdscript
func _process(_delta: float) -> void:
	if _db == null or _state == null:
		return
	if not _state.is_open():
		return
	_state.process(_db)
	if not _state.is_open():
		# process() may have auto-closed due to entity destruction.
		close()  # Drawer's slide-out only — _state already cleared by process().
		return
	_render_view()
```

(That branch keeps `close()` because `_state.process` already cleared state internally; calling `_close_drawer` would `close()` the state twice — harmless but noisy.)

- [ ] **Step 2: Add the `X` close button in the header**

In `_build_ui` (in `nodes/hud/inspect_drawer.gd`), modify the header construction so the header row is an `HBoxContainer` containing the name label and a small `X` button. Replace the existing header creation:

```gdscript
	_header_label = _make_label(_FONT_SIZE, Color(0.9, 0.85, 0.7))
	vbox.add_child(_header_label)
```

with:

```gdscript
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 1)
	_header_label = _make_label(_FONT_SIZE, Color(0.9, 0.85, 0.7))
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_header_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.add_theme_font_size_override("font_size", _FONT_SIZE)
	close_btn.custom_minimum_size = Vector2(6, 5)
	close_btn.pressed.connect(_close_drawer)
	header_row.add_child(close_btn)

	vbox.add_child(header_row)
```

- [ ] **Step 3: Validate parse + visual smoke**

```bash
script/validate
```

Expected: 14/14 pass. The integration test from Task 12 still asserts the drawer opens; it doesn't depend on the X button.

- [ ] **Step 4: Add `ui_cancel` (ESC + controller `B`) handling in `game_client.gd`**

In `nodes/game_client.gd`'s `_unhandled_input`, **at the top** (before any other branch), add:

```gdscript
	if event.is_action_pressed("ui_cancel"):
		var drawer: Control = null
		if has_node("HUD"):
			drawer = $HUD.get_node_or_null("InspectDrawer") as Control
		if drawer != null and drawer.is_open():
			drawer._close_drawer()
			get_viewport().set_input_as_handled()
			return
```

`ui_cancel` is a default Godot input action that maps `ESC` and controller `B` (Xbox) / `Circle` (PS) to the same handler — one branch, full controller parity.

- [ ] **Step 5: Add click-outside handling in `game_client.gd`**

Still in `_unhandled_input`, add this branch **after** the `ui_cancel` branch and **before** the existing left-click handler:

```gdscript
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		var drawer_co: Control = null
		if has_node("HUD"):
			drawer_co = $HUD.get_node_or_null("InspectDrawer") as Control
		if drawer_co != null and drawer_co.is_open():
			# Controls auto-consume gui_input within their rect, so reaching
			# here means the click was outside the drawer.
			drawer_co._close_drawer()
			get_viewport().set_input_as_handled()
			return
```

The reasoning embedded in the comment matters: `Control` automatically consumes `_gui_input` events within its rect, so `_unhandled_input` only fires for clicks outside the drawer. We don't need to compute the drawer's rect manually.

- [ ] **Step 6: Validate**

```bash
script/validate
```

Expected: 14/14 pass.

- [ ] **Step 7: Commit**

```bash
git add nodes/hud/inspect_drawer.gd nodes/game_client.gd
git commit -m "$(cat <<'EOF'
feat(hud): full close-affordance set on InspectDrawer

ESC + controller B via ui_cancel (one branch, full parity). X header
button. Click-outside detected by relying on Control's auto-consumed
_gui_input — _unhandled_input only fires for clicks outside the
drawer's rect. _close_drawer() is now the single-source close path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage (every In-v1 requirement → task):**

- Animals + servers as inspect targets → Task 4 (capability dispatch), Task 8 (render paths).
- Tier 2 desire breakdown — all 8 channels, fully colored → Task 8 (`_DESIRE_KEYS`, `_DESIRE_COLORS`, `_render_animal`).
- Free Tier 3 reads — personality, ai_state → Task 8 (`_render_animal` reads both).
- Single drawer, click-portrait re-targets → Task 8 (`_on_entity_inspect_opened` toggle / re-target).
- Left-edge anchored, slides in/out → Task 7 (Drawer base), Task 8 (`anchor_edge`, `open_position`).
- Triggers: portrait, right-click, `I`/`F1`, controller `X`, long-press → Task 10 (portrait), Task 11 (right-click + `I`/`F1`); controller `X` and long-press are out-of-scope-this-plan since focus tracking and touch input aren't yet wired (note in plan).
- Closes on `ESC`, click outside, `X` button, toggle, controller `B` → Task 8 ships toggle-via-re-emit; Task 14 ships the explicit four (`ESC` + controller `B` via `ui_cancel`, `X` header button, click-outside).
- Capability branch (no species labels) → Task 4 + Task 8.
- Per-frame `_process` reads, never `_physics_process` → Task 8 `_process`.
- Auto-close on entity destroy → Task 3 + Task 8 (`_state.process()` close cascade).
- Trigger-race semantics (last wins, no tween restart) → Task 6 unit test pins the State; Task 8's `_on_entity_inspect_opened` rebinds without restarting the slide.
- Integration test on `Events.entity_inspect_opened` → Task 12.
- 15 unit tests on `InspectDrawerState` → Tasks 2-6.
- Doc updates (scene-tree, file-structure) → Task 13.
- input-design.md `I`/`F1` documentation → already present in the existing keyboard map; no edit needed unless an audit pass shows drift.

**Known gaps (documented, not blockers for v1):**

- **Controller `X` trigger** and **touch long-press** — depend on controller focus tracking + touch input plumbing, neither of which exists today. Out of scope this plan.
- **Reduce-motion hook** — explicitly deferred to v2 in the spec.
- **§5 partial regression** — accepted; documented in spec's Out-of-v1.

**Placeholder scan:** No "TBD" / "TODO" / "implement later" in any task body. Code blocks are concrete in every step.

**Type consistency:** `InspectDrawerState.ContentType` enum used identically in Tasks 2, 3, 4, 5, 6, 8. `Constants.INVALID_ID` used everywhere. `Events.entity_inspect_opened` signature `(entity_id: int)` matches across Tasks 1, 8, 10, 11, 12.

---

## Out of scope (deliberate, do not tack on)

- Drawer migration for placement and narrator (own spec at `docs/superpowers/specs/2026-05-09-drawer-migration-design.md`).
- Trend arrows / history ring buffers.
- 4-state shape language (NOMINAL / ADVISORY / DEGRADED / CRITICAL with circle / triangle / diamond / octagon).
- Off-viewport tether, edge tag, follow-cam.
- Tier 3 history log infrastructure.
- Filter shortcut `F`, multi-inspect aggregates.
- Inspect for boxes, piles, tuna cans, robot arm.
- Settings surface for `reduce_motion`.

If any of these creep into a task, reject the change and file a follow-up.
