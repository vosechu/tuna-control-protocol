# Coordinate System Redesign — Kill PU, Bay-Relative Addressing

**Status:** draft, 2026-04-19. Reviewed by Bramble (two passes); design direction refined by user through multiple rounds.

---

## What's in the game world

TCP renders in a 224×128 pixel viewport. The world contains **bays** — arrays of 5 datacenter **racks** side-by-side — and a **floor** strip at the bottom where animals walk. Each rack is a vertical stack of 10 **slots**. Each slot can hold one 1U server. Above the top slot is a decorative **rack top frame**, below the bottom slot is a **rack bottom frame**, and below that is the floor.

```
   ┌──────┬──────┬──────┬──────┬──────┐    ← rack top frame (12 px tall)
   │ slot │ slot │ slot │ slot │ slot │  9 (top slot)
   │ ...  │ ...  │ ...  │ ...  │ ...  │
   │ slot │ slot │ slot │ slot │ slot │  0 (bottom slot)
   └──────┴──────┴──────┴──────┴──────┘    ← rack bottom frame (4 px)
   ════════════════════════════════════    ← floor (16 px, animals walk here)
    rack 0 rack 1 rack 2 rack 3 rack 4
```

**Physical measurements from the current 5-set rack sprite:**

| Element | Size |
|---|---|
| Server sprite | 23 × 8 px |
| Rack cell (server + right shadow) | 24 × 8 px |
| Horizontal gap between rack cells | 7 px of frame, 1 px of shadow — 8 px visible |
| Rack horizontal stride (cell N left to cell N+1 left) | 31 px |
| Rack top frame height | 12 px |
| Rack interior (10 slots × 8 px) | 80 px |
| Rack bottom frame height | 4 px |
| Rack total height | 96 px |
| Floor height | 16 px |

**These measurements do not change.** The redesign is a pure coordinate-system rewrite. No art edits.

**User addressing intent:** `bay 0, rack 0, slot 0` = bottom-left slot of the starter bay. Bays run negative left, positive right (world Godot X). Racks are 0..4, left to right. Slots are 0..9, bottom to top.

---

## The bug this fixes

Positions in the simulation are stored as `(x, y)` pairs in **PU** (position units, `POSITION_SCALE=100`). PU was meant as a sub-pixel integer frame for smooth movement. Two helpers convert to PU:

- `rack_slot_to_pu(bay, rack, slot)` — returns a rack slot's coordinates. Y is `slot * SLOT_HEIGHT_PU`. Slot 0 top is Y=0 in this frame — **no offset for where the rack sits on screen**.
- `FLOOR_Y_PU = FLOOR_Y * POSITION_SCALE` — raw world-pixel Y scaled up. Y=0 is the viewport top.

These two frames are off by **2800 PU** — the distance from viewport top (world Y=0) to slot 0 top (world Y=28).

Consequence: a cat on the floor (stored at PU y=12000) and a server in slot 9 (stored at PU y=7200) appear 4800 PU apart. In the old "rack unit" system that's 6 RU. Actual visual gap is ~800 PU (~1 RU).

Every spatial query crossing these frames returns nonsense distances. Advertisement radii can't be tuned sanely. The Ring 0 "cat settles in box → HUM charges" golden path fails not because the purr chain is broken, but because cats can't detect anything within a reasonable radius.

CLAUDE.md already flags this in Known Issues: *"PU coordinate system adds unnecessary complexity. Candidate for removal refactor."*

---

## Design

### Kill PU. Kill U. Kill all abstract units.

- **No `POSITION_SCALE`.** All positions are integer Godot world pixels. If you had PU y=12000, you now have px y=120.
- **No `U_PX` or `RU` length unit.** The prior revision proposed `U = 8 px` as a universal length unit; we're dropping it. The rack doesn't tile cleanly on an 8-px grid horizontally (stride is 31 px, not a multiple of 8), and uniformly imposing U creates a false abstraction. Distances in config and code are in pixels, always.
- **No generic length-unit conversion functions.** `u_to_px`, `ru_to_pu`, etc. are deleted.

### Three-layer addressing, each rooted in the bay

The three things the game needs to address are bays, racks, and slots. Each layer has its own API:

- **Bay layer:** `(bay: int)` → world coords (Godot Y-down).
- **Rack layer:** `(bay: int, rack: int)` → world coords. Rack-column-wide rects and named zones (top frame, bottom frame) live here.
- **Slot layer:** `(bay: int, rack: int, slot: int)` → world coords. Slot is strictly 0..9 (interior only).

Callers always compose the layers they need. There is no "U coordinate" and no "bay-local coordinate" exposed publicly — bay-relative positioning is an implementation detail of the helpers.

### Named zones are not slots

The rack top frame (where plants grow) is **not** addressable as `slot = 10`. It's a named zone with its own helper: `rack_frame_rect(bay, rack)` — the frame that outlines the rack, which plants perch on top of. Same for the rack baseboard and the floor. These zones don't participate in the slot grid, don't use slot math, and don't have slot-like indices.

Plants get their coordinates from `rack_frame_rect(bay, rack)`, not from `slot_origin_world(bay, rack, 10)`.

### Y stays Godot-native

Slot 0 is the bottom slot and slot 9 is the top slot — this is a **labeling convention**, not a coordinate-axis choice. All pixel coordinates returned by the public API are Godot-standard Y-down. `slot_origin_world(bay, rack, 0)` returns a world position with a *higher* Y than `slot_origin_world(bay, rack, 9)`, because slot 0 is visually lower.

No Y-up coordinates exist anywhere in the public API. The slot-number-to-world-Y math inverts inside the helper implementation. Callers never do manual flips.

### Bay atomicity

Inside a bay, rack positions are pixel-exact. Between bays, world spacing is arbitrary Godot positioning (current `BAY_STRIDE_PX=226` with `BAY_PEEK_PX=20` is fine). The public API talks only in world-pixel terms; bay-origin composition is the helpers' job.

---

## API

Complete replacement for `engine/core/constants.gd`.

### Public constants

```gdscript
const SLOTS_PER_RACK: int = 10    # slot count, valid indices 0..9
const RACKS_PER_BAY: int = 5
const INVALID_BAY: int = -1
const INVALID_SLOT: int = -1      # sentinel for reverse queries (never a valid slot)
```

### Private constants (implementation detail of helpers)

```gdscript
# AI-DEV: These numbers match the current 5-set rack sprite exactly. If a mod
# pack ships differently-sized rack art, promote them to art-pack config
# loaded by ModLoader. Do not expose them publicly — the helpers' job is to
# hide art measurements behind the three-layer addressing API.
const _SLOT_HEIGHT_PX: int = 8
const _SERVER_WIDTH_PX: int = 23
const _RACK_CELL_WIDTH_PX: int = 24             # server + 1 px shadow
const _RACK_STRIDE_PX: int = 31                 # horizontal stride between adjacent rack cells
const _RACK_LEFT_MARGIN_PX: int = 16            # bay sprite left edge to rack 0 cell left edge
const _RACK_TOP_FRAME_HEIGHT_PX: int = 12
const _RACK_BOTTOM_FRAME_HEIGHT_PX: int = 4
const _RACK_INTERIOR_HEIGHT_PX: int = 80        # 10 slots × 8 px
const _FLOOR_HEIGHT_PX: int = 16
const _RACK_TOP_Y_IN_BAY: int = 16              # Y within bay sprite of rack sprite top edge
```

No caller reads these. They exist solely so the helpers can compute rects.

### Bay layer

```gdscript
static func bay_origin_world(bay: int) -> Vector2i    # upper-left pixel of bay sprite
static func bay_rect_world(bay: int) -> Rect2i        # full bay sprite area
static func world_to_bay(world_pos: Vector2i) -> int  # bay index, or INVALID_BAY if outside any bay
```

### Rack layer

```gdscript
static func rack_column_rect_world(bay: int, rack: int) -> Rect2i    # full rack column incl. frame + interior
static func rack_interior_rect_world(bay: int, rack: int) -> Rect2i  # just the 80 px covering slots 0..9
static func rack_frame_rect(bay: int, rack: int) -> Rect2i           # 12 px tall top frame — plants live here
static func rack_baseboard_rect(bay: int, rack: int) -> Rect2i       # 4 px tall bottom frame — baseboard
```

`rack_frame_rect` is the "rack outline" zone where plants perch. `rack_baseboard_rect` is the baseboard strip below the bottom slot. Both are named zones, distinct from slot addressing.

### Slot layer

```gdscript
static func slot_rect_world(bay: int, rack: int, slot: int) -> Rect2i    # slot strictly 0..9
static func slot_origin_world(bay: int, rack: int, slot: int) -> Vector2i  # top-left of slot
```

If a caller passes `slot = 10` or any other out-of-range value, the helper asserts.

### Floor

```gdscript
static func floor_rect_world(bay: int) -> Rect2i     # 16 px tall strip
```

### Reverse — world → address

Split so each return is unambiguous:

```gdscript
static func world_to_bay(world_pos: Vector2i) -> int
# (same as Bay layer — listed there; returns INVALID_BAY if outside)

static func bay_local_to_slot(bay: int, world_pos: Vector2i) -> SlotQuery
```

`SlotQuery` is a small RefCounted class:

```gdscript
class_name SlotQuery extends RefCounted

var rack: int = Constants.INVALID_ID   # 0..4 when zone identifies a rack column; INVALID_ID when zone == &"other"
var slot: int = Constants.INVALID_SLOT # 0..9 only when zone == &"slot"
var zone: StringName = &"other"        # &"slot", &"frame", &"baseboard", &"floor", &"other"

func get_slot() -> int:
    assert(zone == &"slot", "SlotQuery.get_slot() called with zone=%s" % zone)
    return slot

func get_rack() -> int:
    assert(zone != &"other", "SlotQuery.get_rack() called with zone=&\"other\"")
    return rack
```

`zone` covers the possible places a world position can fall:
- `&"slot"` — inside one of the 10 interior slots; `slot` is set.
- `&"frame"` — inside the rack's top frame (plant zone); `slot` is INVALID_SLOT.
- `&"baseboard"` — inside the rack's bottom baseboard strip; `slot` is INVALID_SLOT.
- `&"floor"` — on the floor strip; `slot` is INVALID_SLOT, `rack` identifies the column above.
- `&"other"` — between racks, in the gap or margin; `rack` and `slot` are INVALID.

Caller pattern:

```gdscript
var bay := Constants.world_to_bay(pos)
if bay == Constants.INVALID_BAY:
    return
var q := Constants.bay_local_to_slot(bay, pos)
match q.zone:
    &"slot":
        handle_slot(bay, q.rack, q.get_slot())
    &"floor":
        handle_floor(bay, q.rack)
    &"frame":
        handle_plant_zone(bay, q.rack)
    _:
        pass  # ignore gaps and margins
```

This matches TCP's "no null, explode early" philosophy. The `zone` tag is a typed discriminator; the `get_slot()` accessor asserts if misused.

---

## Config and constant renames

No U means no `radius_ru`, no `ARM_REACH_RU`. Every distance or radius gets a pixel value.

- Config schema: `"radius_ru": N` → `"radius_px": M`. **Not blindly `M = N × 8`** — `RU` historically meant different things in different fields. A vertical scatter radius of 4 RU means 4 slot-heights = 32 px, but `ARM_REACH_RU = 3` may semantically mean "3 racks of horizontal reach" (= 93 px) or "3 slot-heights" (= 24 px). Before rewrite, grep every `_ru` / `_RU` use and categorize as slot-height-distance, rack-stride-distance, or other. The mechanical multiplier applies per category, not globally.
- Engine constants: `ARM_REACH_RU = 3` → `ARM_REACH_PX = ?`. Audit whether arm reach is vertical or horizontal before picking the multiplier.
- Tests: any `ru_to_pu(N)` call becomes the pixel literal that matches the field's semantics.

Bumping scenario/recipe `schema_version` covers first-party data; release notes warn mod authors to port `_ru` → `_px` fields in their own configs.

---

## Migration plan

Five commits in order. The forcing-rename commit ensures no caller survives without either migration or an explicit deprecation.

### Commit 1 — Add new API alongside old

- Add new `Constants` helpers (`bay_origin_world`, `slot_rect_world`, `rack_frame_rect`, `rack_baseboard_rect`, `floor_rect_world`, `world_to_bay`, `bay_local_to_slot`), `SlotQuery` class, and the private pixel constants.
- Old API (`rack_slot_to_pu`, `POSITION_SCALE`, `FLOOR_Y_PU`, etc.) stays in place, untouched.
- No callers migrated. Pure additive.

### Commit 2 — Migrate leaf callers

Local callers that compute positions from rack/slot without crossing system boundaries:

- `engine/navigation/nav_graph_builder.gd`
- `tests/integration/test_desire_scatter.gd`
- `tests/unit/test_species_astar.gd`
- `tests/integration/test_hum_tick.gd`

Mechanical swap — `rack_slot_to_pu(b, r, s)` becomes `slot_origin_world(b, r, s)` (slot values inverted: `s_new = 9 - s_old`).

### Commit 3 — Migrate spatial systems (atomic)

Slot-inversion semantics must land coherently across systems that talk to each other:

- `engine/spatial/heat_grid.gd`
- `engine/desires/desire_resolver.gd`
- `engine/growth/plant_growth_system.gd` — `plant_sprite.position = ...` now reads from `rack_frame_rect`
- `engine/core/food_system.gd`

All four in one commit so slot 0 = bottom is consistent everywhere.

### Commit 4a — Forcing-function rename (code)

The compile-error sweep for GDScript.

- Rename `rack_slot_to_pu` → `DEPRECATED_rack_slot_to_pu` (same for `pu_to_bay_rack_slot`, `world_to_pu`, `RACK_SLOT0_Y`, `POSITION_SCALE`, `FLOOR_Y_PU`, `ru_to_pu`, `pu_to_ru`, etc.). Do NOT delete yet.
- Every remaining GDScript callsite fails to compile. Fix them, migrating to the new API. If this is too large to finish in one sitting, keep old names as thin forwarding shims (`func rack_slot_to_pu(...): return ...`) and remove the shims at the end of the commit.
- Audit `.tscn` files for hand-coded `position = Vector2(...)` constants. Stride stays 31 so these probably don't need changes, but verify.

After this commit: `script/validate` and `script/checks/gut_tests` are green. No saves load yet (schema mismatch); game boots fresh.

### Commit 4b — Config JSONC rewrite

- Bump `mods/tcp_base/scenarios/starter.jsonc` `schema_version` 1 → 2. Rewrite slot indices in place: `slot: N` → `slot: 9 - N`. First-party fix; no load-time migrator needed.
- Per-field audit of every `_ru` / `_RU` reference in `mods/tcp_base/**/*.jsonc` and engine constants. Categorize each as vertical (slot-height) or horizontal (rack-stride) distance before renaming. Rewrite to `_px` with the correct multiplier.
- Rename `ARM_REACH_RU` → `ARM_REACH_PX` (or whatever the audit determines — may end up horizontal).

After this commit: validate green, all first-party scenarios and configs consistent with pixel-based world.

### Commit 4c — Save migrator + position rescale

- Save migrator v2→v3:
  - For every rack entity, `slot_new = 9 - slot_old` (slot inversion).
  - For every `position` component, divide x and y by 100 (PU → pixel). Required because the old storage was PU, the new storage is pixels.
- Run existing save fixtures through the migrator; confirm round-trip behavior.

After this commit: old saves load cleanly. Validate green.

### Commit 5 — Delete old API

- Delete all `DEPRECATED_*` functions and constants.
- Final `script/validate`, `script/checks/gut_tests`, and manual game-boot smoke. Verify the Ring 0 "cat settles in box → HUM charges" golden path works.

### Risks & mitigations

| Risk | Mitigation |
|---|---|
| Scenario JSONC files in third-party mods carry pre-inversion slot indices | Release note for mod authors; no load-time migrator (too complex for the single tcp_base scenario) |
| MP networking payloads encode slot indices | No `engine/network/*` exists today and no MP payload carries slot indices. **When it does** (future Ring 2+ work), migration for the network protocol is the implementer's responsibility. The event-bus signal `object_placed(object_id, rack, slot, object_type)` is same-process only and needs no migration. |
| Heat grid cell state crosses the slot-inversion boundary | **No migration needed.** `heat_grid.propagate()` zeros the grid and rebuilds it from `heat_source` entities every tick. Heat is transient; no save data, no network deltas carry heat cells. The only concern is tests that assert specific cell indices — they migrate with the leaf callers in Commit 2. |
| Hand-coded positions in tests outside the known list | Commit 4a's compile-error sweep catches them |
| Config JSONC files reference positions/radii in RU with mixed semantics | Commit 4b does a per-field audit, not mechanical × 8 |
| `world_to_pu` callsites "compile fine" after rename but are semantically wrong | Each audited in Commit 3, not just compile-fixed. Add TODO comments for uncertain sites |
| Position components stored in PU need pixel conversion on save load | Save migrator v2→v3 handles it in Commit 4c; failure mode is a game that loads with animals stuck at wrong scale |

---

## Non-goals

- Art changes of any kind (rack sprite, frame art, stride, bay sprite placements). Current art is authoritative.
- Extended slot indices (no `slot = 10`, no negative slots). Plant zone and frames are separate named zones.
- Generic length-unit conversions. Everything is pixels.
- Sub-pixel movement or smooth interpolation. Positions are integer pixels, period.
- Exposing bay-local or Y-up coordinates in the public API. Implementation detail only.

---

## Success criteria

- `script/validate` green after each commit.
- `script/checks/gut_tests` green after each commit.
- After Commit 5: no references to `PU`, `POSITION_SCALE`, `RACK_SLOT0_Y`, `FLOOR_Y_PU`, `rack_slot_to_pu`, `RU`, or `ru_to_pu` anywhere in the tree except migration logs.
- Unit test locks in the Y-axis convention: `slot_origin_world(0, 0, 0).y > slot_origin_world(0, 0, 9).y` — slot 0 (bottom) has a *larger* Y than slot 9 (top). One assertion, one file, catches any future refactor that accidentally re-flips the axis.
- Golden-path smoke: load the game. Cat spawns on floor. Cat detects a nearby comfort source, approaches, settles, purrs. HUM reserve climbs. **The original bug is demonstrably fixed.**

---

## Files touched

- `engine/core/constants.gd` — rewritten
- `engine/spatial/heat_grid.gd`
- `engine/navigation/nav_graph_builder.gd`
- `engine/desires/desire_resolver.gd`
- `engine/growth/plant_growth_system.gd`
- `engine/core/food_system.gd`
- `nodes/game_server.gd` — `FLOOR_Y_PU`, `_scatter_desires`, `_move_animals`, `_place_starter_hardcoded_objects`
- `nodes/game_client.gd` — `rack_slot_to_world` callers
- `nodes/ru_grid_overlay.gd` — rename file + contents (RU→PX or similar)
- `mods/tcp_base/scenarios/starter.jsonc` — schema v2, slot inversion
- `mods/**/*.jsonc` — `radius_ru` → `radius_px`
- `engine/save/save_migrator.gd` (or equivalent) — v2→v3 slot inversion + PU→pixel position scaling

---

## References

- CLAUDE.md "Known Issues (Ring 0)" — acknowledges PU complexity
- `.claude/rules/design-philosophy.md` — Integers Over Floats, Null Is the Enemy, Explode Early
- `.claude/rules/growth-system.md` — plant zone semantics (lives in rack top frame)
- Bramble's reviews (two passes, this session)
