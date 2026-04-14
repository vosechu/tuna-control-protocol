# Coordinate System Refactor

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all coordinate math so entities, nav nodes, sprites, and click detection use the same coordinate space — one derived from `rack_slot_to_pu()` and `rack_slot_to_world()`.

**Architecture:** The project has two coordinate systems: PU (position units for GameStateDB) and world pixels (for rendering/input). Most code predates the utility functions in `constants.gd` and uses `rack * RACK_WIDTH_PU` for X (missing the 25px bay offset and using 23px width instead of 31px stride). The fix: replace all manual coordinate math with the canonical helpers, and add a `world_to_pu()` function for click-to-entity spatial queries.

**Tech Stack:** GDScript, Godot 4, GUT tests

**Key numbers:**
- `LEFTMOST_RACK_OFFSET_PU = 2500` — racks don't start at X=0
- `RACK_STRIDE_PU = 3100` — distance between rack centers (not RACK_WIDTH_PU=2300)
- `RACK_SLOT0_Y = 20` — world pixel where slot 0 starts (not RACK_TOP_Y=16)
- `rack_slot_to_pu(bay, rack, slot)` — canonical PU position (X = center of rack)
- `rack_slot_to_world(bay, rack, slot)` — canonical world pixel position (top-left of slot)
- `world_to_rack_slot(world_x, world_y, bay)` — click position to rack/slot

**Entities currently "consistently wrong together":** Starter animals, nav graph floor nodes, wander targets, and rack curiosity entities all use the same broken `rack * RACK_WIDTH_PU` formula. They're internally consistent so things appear to work. The server (placed via `rack_slot_to_pu`) is in a *different* coordinate space — but currently the only rack object.

---

### Task 1: Fix starter entity X positions in game_server.gd

The core fix: all starter entities should use `rack_slot_to_pu()` for X positioning.

**Files:**
- Modify: `nodes/game_server.gd:627-732`

- [ ] **Step 1: Fix box X position**

`nodes/game_server.gd` line 627. Currently:
```gdscript
var box_x: int = 0 * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2
```

Replace with:
```gdscript
var box_x: int = Constants.rack_slot_to_pu(0, 0, 0).x
```

- [ ] **Step 2: Fix cat spawn X positions**

`nodes/game_server.gd` lines 650, 658-659, 667-668. Currently cats at racks 0, 1, 2 use `RACK_WIDTH_PU` as stride. Replace the three position overrides:

```gdscript
# Mochi at rack 1 (near the server)
&"x": Constants.rack_slot_to_pu(0, 1, 0).x,

# Biscuit at rack 2
&"x": Constants.rack_slot_to_pu(0, 2, 0).x,

# Noodle at rack 3
&"x": Constants.rack_slot_to_pu(0, 3, 0).x,
```

- [ ] **Step 3: Fix ferret spawn X positions**

`nodes/game_server.gd` lines 689-690, 697-698. Currently ferrets use `RACK_WIDTH_PU`. Replace:

```gdscript
# Slinky at rack 1
&"x": Constants.rack_slot_to_pu(0, 1, 0).x,

# Bandit at rack 2
&"x": Constants.rack_slot_to_pu(0, 2, 0).x,
```

- [ ] **Step 4: Fix rack curiosity entity X positions**

`nodes/game_server.gd` line 720. Currently:
```gdscript
var x: int = rack_idx * Constants.RACK_WIDTH_PU + Constants.RACK_WIDTH_PU / 2
```

Replace with:
```gdscript
var x: int = Constants.rack_slot_to_pu(0, rack_idx, 0).x
```

- [ ] **Step 5: Run script/validate**

```bash
script/validate
```

Expected: 10/10 pass.

- [ ] **Step 6: Commit**

```bash
git add nodes/game_server.gd
git commit -m "fix: starter entities use rack_slot_to_pu() for correct X positions"
```

---

### Task 2: Fix nav_graph_builder.gd to use canonical X positions

Nav nodes must be in the same PU coordinate space as entities placed via `rack_slot_to_pu()`.

**Files:**
- Modify: `engine/navigation/nav_graph_builder.gd:42,65`

- [ ] **Step 1: Fix floor node X**

`engine/navigation/nav_graph_builder.gd` line 42. Currently:
```gdscript
var x: float = float(rack * Constants.RACK_STRIDE_PU + Constants.RACK_STRIDE_PU / 2)
```

This uses RACK_STRIDE_PU but no LEFTMOST_RACK_OFFSET_PU. Replace with:
```gdscript
var x: float = float(Constants.rack_slot_to_pu(0, rack, 0).x)
```

- [ ] **Step 2: Fix slot node X**

`engine/navigation/nav_graph_builder.gd` line 65. Same pattern. Replace:
```gdscript
var x: float = float(rack * Constants.RACK_STRIDE_PU + Constants.RACK_STRIDE_PU / 2)
```

With:
```gdscript
var x: float = float(Constants.rack_slot_to_pu(0, rack, slot).x)
```

Note: Y at line 66 (`float(slot * Constants.SLOT_HEIGHT_PU)`) already matches `rack_slot_to_pu().y`, so leave it.

- [ ] **Step 3: Run script/validate**

```bash
script/validate
```

Expected: 10/10 pass.

- [ ] **Step 4: Commit**

```bash
git add engine/navigation/nav_graph_builder.gd
git commit -m "fix: nav graph nodes use rack_slot_to_pu() for consistent X positions"
```

---

### Task 3: Fix place_object() and _find_dispenser_in_rack() rack derivation

These functions derive rack index from PU X by dividing by `RACK_WIDTH_PU`, which gives wrong results. Use `pu_to_bay_rack_slot()` instead.

**Files:**
- Modify: `nodes/game_server.gd:566-568, 738, 746`

- [ ] **Step 1: Fix place_object() rack/slot derivation**

`nodes/game_server.gd` lines 566-568. Currently:
```gdscript
db.update_spatial(entity, world_x, world_y)
var rack: int = world_x / Constants.RACK_WIDTH_PU
var slot: int = world_y / Constants.SLOT_HEIGHT_PU
```

Replace lines 567-568 with:
```gdscript
var layout: Dictionary = Constants.pu_to_bay_rack_slot(world_x, world_y)
var rack: int = int(layout[&"rack"])
var slot: int = int(layout[&"slot"])
```

- [ ] **Step 2: Fix _find_dispenser_in_rack() rack derivation**

`nodes/game_server.gd` line 738. Currently:
```gdscript
var rack: int = world_x / Constants.RACK_WIDTH_PU
```

Replace with:
```gdscript
var layout: Dictionary = Constants.pu_to_bay_rack_slot(world_x, _world_y)
var rack: int = int(layout[&"rack"])
```

Line 746. Currently:
```gdscript
var disp_rack: int = dpos[&"x"] / Constants.RACK_WIDTH_PU
```

Replace with:
```gdscript
var disp_layout: Dictionary = Constants.pu_to_bay_rack_slot(dpos[&"x"], dpos[&"y"])
var disp_rack: int = int(disp_layout[&"rack"])
```

- [ ] **Step 3: Run script/validate**

```bash
script/validate
```

Expected: 10/10 pass.

- [ ] **Step 4: Commit**

```bash
git add nodes/game_server.gd
git commit -m "fix: place_object and dispenser finder use pu_to_bay_rack_slot()"
```

---

### Task 4: Fix desire_resolver.gd wander positions

**Files:**
- Modify: `engine/desires/desire_resolver.gd:203-207`

- [ ] **Step 1: Fix _random_floor_position()**

`engine/desires/desire_resolver.gd` lines 203-207. Currently:
```gdscript
func _random_floor_position() -> Dictionary:
	var rack: int = randi_range(0, Constants.RACK_COUNT - 1)
	var x: int = rack * Constants.RACK_WIDTH_PU + randi_range(0, Constants.RACK_WIDTH_PU)
	var y: int = Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 2
	return {&"x": x, &"y": y}
```

Replace with:
```gdscript
func _random_floor_position() -> Dictionary:
	var rack: int = randi_range(0, Constants.RACK_COUNT - 1)
	var center_x: int = Constants.rack_slot_to_pu(0, rack, 0).x
	var jitter: int = randi_range(-Constants.RACK_WIDTH_PU / 2, Constants.RACK_WIDTH_PU / 2)
	var x: int = center_x + jitter
	var y: int = Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU + Constants.FLOOR_HEIGHT_PU / 2
	return {&"x": x, &"y": y}
```

- [ ] **Step 2: Run script/validate**

```bash
script/validate
```

Expected: 10/10 pass.

- [ ] **Step 3: Commit**

```bash
git add engine/desires/desire_resolver.gd
git commit -m "fix: wander targets use rack_slot_to_pu() for correct X positions"
```

---

### Task 5: Fix click detection and removal Y offset

`_try_click_entity` and `_try_remove_at` use `from_world(world_pos.y)` which gives PU values 2000 higher than where rack objects are stored (because PU slot 0 = Y 0, but world pixel slot 0 = Y 20). Add a `world_to_pu()` helper that accounts for the RACK_SLOT0_Y offset.

**Files:**
- Modify: `engine/core/constants.gd` (add `world_to_pu` function)
- Modify: `nodes/game_client.gd:397-403, 458-460`

- [ ] **Step 1: Add world_to_pu() to constants.gd**

Add after the existing `world_to_rack_slot` function:

```gdscript
## Convert world-pixel position to PU coordinates.
## Accounts for RACK_SLOT0_Y offset on Y axis.
static func world_to_pu(world_x: float, world_y: float) -> Vector2i:
	return Vector2i(
		from_world(world_x),
		from_world(world_y - float(RACK_SLOT0_Y)),
	)
```

- [ ] **Step 2: Fix _try_remove_at()**

`nodes/game_client.gd` lines 397-403. Currently:
```gdscript
func _try_remove_at(world_pos: Vector2) -> void:
	var click_pu_x: int = Constants.from_world(
		world_pos.x
	)
	var click_pu_y: int = Constants.from_world(
		world_pos.y
	)
	var nearby: Array[int] = game_server.db.query_radius(
		click_pu_x, click_pu_y, Constants.ru_to_pu(2)
```

Replace with:
```gdscript
func _try_remove_at(world_pos: Vector2) -> void:
	var click_pu: Vector2i = Constants.world_to_pu(
		world_pos.x, world_pos.y
	)
	var nearby: Array[int] = game_server.db.query_radius(
		click_pu.x, click_pu.y, Constants.ru_to_pu(2)
```

- [ ] **Step 3: Fix _try_click_entity()**

`nodes/game_client.gd` lines 458-460. Currently:
```gdscript
var click_x: int = Constants.from_world(world_pos.x)
var click_y: int = Constants.from_world(world_pos.y)
var nearby: Array[int] = game_server.db.query_radius(
	click_x, click_y, Constants.ru_to_pu(2),
```

Replace with:
```gdscript
var click_pu: Vector2i = Constants.world_to_pu(
	world_pos.x, world_pos.y
)
var nearby: Array[int] = game_server.db.query_radius(
	click_pu.x, click_pu.y, Constants.ru_to_pu(2),
```

- [ ] **Step 4: Run script/validate**

```bash
script/validate
```

Expected: 10/10 pass.

- [ ] **Step 5: Commit**

```bash
git add engine/core/constants.gd nodes/game_client.gd
git commit -m "fix: click detection uses world_to_pu() for correct Y offset"
```

---

### Task 6: Fix floor object sprite rendering

`_create_object_sprite` routes through `pu_to_bay_rack_slot()` which clamps slot to 0-9, so floor objects (PU Y > 8000) render at rack slot 9 instead of the floor. Floor objects need a different render path.

**Files:**
- Modify: `nodes/game_client.gd:430-455` (_create_object_sprite)

- [ ] **Step 1: Add floor detection to _create_object_sprite**

Currently the function converts PU→rack/slot→world for ALL objects. Floor objects need to bypass this and render at FLOOR_Y. Replace the sprite positioning block:

```gdscript
func _create_object_sprite(
	entity_id: int,
	object_type: StringName,
	pu_x: int,
	pu_y: int,
) -> void:
	var sprite := Sprite2D.new()
	match object_type:
		&"server_1u":
			sprite.texture = _SERVER_TEX
		&"cardboard_box":
			sprite.texture = _BOX_TEX
		&"clothes_pile":
			sprite.texture = _PILE_TEX
		&"hum_device":
			sprite.texture = _HUM_TEX
	sprite.centered = false
	var layout: Dictionary = Constants.pu_to_bay_rack_slot(
		pu_x, pu_y
	)
	sprite.position = Constants.rack_slot_to_world(
		int(layout[&"bay"]),
		int(layout[&"rack"]),
		int(layout[&"slot"]),
	)
	$World/PlacedObjects.add_child(sprite)
	_object_sprites[entity_id] = sprite
```

Replace the positioning section (after the match block) with:

```gdscript
	sprite.centered = false
	var floor_pu_y: int = Constants.SLOTS_PER_RACK * Constants.SLOT_HEIGHT_PU
	if pu_y >= floor_pu_y:
		# Floor object: render at floor level
		sprite.position = Vector2(
			Constants.to_world(pu_x),
			float(Constants.FLOOR_Y) - sprite.texture.get_height(),
		)
	else:
		# Rack object: convert PU → rack/slot → world pixels
		var layout: Dictionary = Constants.pu_to_bay_rack_slot(
			pu_x, pu_y
		)
		sprite.position = Constants.rack_slot_to_world(
			int(layout[&"bay"]),
			int(layout[&"rack"]),
			int(layout[&"slot"]),
		)
	$World/PlacedObjects.add_child(sprite)
	_object_sprites[entity_id] = sprite
```

- [ ] **Step 2: Run script/validate**

```bash
script/validate
```

Expected: 10/10 pass.

- [ ] **Step 3: Commit**

```bash
git add nodes/game_client.gd
git commit -m "fix: floor object sprites render at FLOOR_Y, not clamped rack slot"
```

---

### Task 7: Fix animal_stats_bar.gd compile error

References nonexistent `Constants.HALF_RACK_PX`. This file likely doesn't get loaded in the current prototype (no stats bar shown), but it's a latent compile error.

**Files:**
- Modify: `nodes/animal_stats_bar.gd:131-135`

- [ ] **Step 1: Read the full function to understand intent**

Read `nodes/animal_stats_bar.gd` around line 131 to see what the camera positioning is trying to do.

- [ ] **Step 2: Fix the reference**

Replace `Constants.HALF_RACK_PX` with `Constants.RACK_WIDTH_PX / 2`. The intent is to offset the camera by half a rack width in world pixels. Since `to_world(pos.x)` returns world pixels from PU, and the offset is also in world pixels, this is correct:

```gdscript
_camera.position = Vector2(
	Constants.to_world(pos[&"x"])
		+ float(Constants.RACK_WIDTH_PX / 2),
	Constants.to_world(pos[&"y"]),
)
```

- [ ] **Step 3: Run script/validate**

```bash
script/validate
```

Expected: 10/10 pass.

- [ ] **Step 4: Commit**

```bash
git add nodes/animal_stats_bar.gd
git commit -m "fix: replace nonexistent HALF_RACK_PX with RACK_WIDTH_PX / 2"
```

---

### Task 8: Fix box starter sprite position to match DB

The box sprite renders at `LEFTMOST_RACK_OFFSET_PX` (x=25) but the DB entity is now at `rack_slot_to_pu(0, 0, 0).x` (after Task 1). The sprite should use the same coordinate conversion.

**Files:**
- Modify: `nodes/game_client.gd:186-196` (_build_starter_objects box section)

- [ ] **Step 1: Fix box sprite position**

Currently:
```gdscript
box_sprite.position = Vector2(
	float(Constants.LEFTMOST_RACK_OFFSET_PX),
	float(Constants.FLOOR_Y) - 16.0,
)
```

The DB position after Task 1 is `rack_slot_to_pu(0, 0, 0).x` which is the center of rack 0. The box sprite should be centered under that rack. Replace with:

```gdscript
var box_world_x: float = Constants.rack_slot_to_world(0, 0, 0).x
box_sprite.position = Vector2(
	box_world_x,
	float(Constants.FLOOR_Y) - float(box_sprite.texture.get_height()),
)
```

- [ ] **Step 2: Run script/validate**

```bash
script/validate
```

Expected: 10/10 pass.

- [ ] **Step 3: Run the game and visually verify**

```bash
/Applications/Godot.app/Contents/MacOS/godot --path .
```

Check: server at rack 1 slot 8, cats/ferrets visible under racks (not shifted left), box on the floor near rack 0, heat overlay aligned with rack slots, RU grid overlay aligned with rack slots.

- [ ] **Step 4: Commit**

```bash
git add nodes/game_client.gd
git commit -m "fix: box sprite position matches DB entity via rack_slot_to_world()"
```

---

## Summary of changes

| Finding | Task | Fix |
|---------|------|-----|
| F1: place_object rack derivation | 3 | Use `pu_to_bay_rack_slot()` |
| F2: dispenser finder rack derivation | 3 | Use `pu_to_bay_rack_slot()` |
| F3: starter entity X positions | 1 | Use `rack_slot_to_pu()` |
| F4: rack curiosity entity X | 1 | Use `rack_slot_to_pu()` |
| F5: animal_node Y hardcoded | — | Not fixed (FRAGILE, works for floor-only animals) |
| F6: _try_click_entity Y offset | 5 | Use new `world_to_pu()` |
| F7: _try_remove_at Y offset | 5 | Use new `world_to_pu()` |
| F8: box sprite X mismatch | 8 | Use `rack_slot_to_world()` |
| F10: floor object sprite clamping | 6 | Floor detection in `_create_object_sprite` |
| F13: nav graph X positions | 2 | Use `rack_slot_to_pu()` |
| F14: wander positions | 4 | Use `rack_slot_to_pu()` |
| F15: HALF_RACK_PX missing | 7 | Use `RACK_WIDTH_PX / 2` |

**Not fixed (deliberate):**
- F5 (animal_node Y = FLOOR_Y): Animals currently only walk on the floor. When rack-climbing is added, this needs real work. Flagged as FRAGILE.
- F17 (PU Y origin vs RACK_SLOT0_Y): The `world_to_pu()` helper in Task 5 bridges this gap for click detection. The underlying mismatch is a known debt item (tracked in CLAUDE.md as "PU coordinate system adds unnecessary complexity").
