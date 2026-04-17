# Art Scale and TileMap Integration

> **Note (2026-04-16):** Identifiers referenced in this document may be outdated.
> `species_filter` was never implemented and is removed. `cat_presence` → `reclamation`,
> `cat_seconds` → `tended_seconds`, `is_purring` → `is_satisfied`. Anchor rule and
> species-recipe schema live in `CLAUDE.md` ("Species Are Component Recipes") and
> `.claude/rules/modding.md` (Species Recipe Schema).

> **Status:** design draft, 2026-04-10. Not yet implemented. Revised 2026-04-10 after team review (Mochi, Smudge, Bento, Bramble, Kibble, Pebble, Parcel).
> **Motivation:** The new pixel art assets (`tcp_props_tilesets/`) ship at a different pixel scale than the game's current grid constants, and the environment asset is a 16×16 tileset atlas rather than individual tiles. The current rendering code loads the atlas as a single sprite and procedurally builds a Sprite2D per rack column, so the game renders the full tileset under every rack and the rack sprites come out at the wrong scale. This spec reconciles the grid to the art, sets up a proper Godot TileMap for the environment, and preserves existing gameplay (heat grid, nav graph, AI, tests) through the transition.

## Goals

1. Game renders at the scale the artist drew. 1:1 pixel mapping — no scaling of pixel art sprites.
2. Environment (walls, ceiling, cables, baseboard, ground) is painted via a real Godot `TileMap` / `TileSet`, not by stretching the whole atlas image.
3. Rack row renders as designed: 5 playable racks using `rack_5set_idle_strip1.png`, with a visible peek of the neighboring bays on each side.
4. Coordinate system supports future horizontal scrolling through adjacent bays without a refactor.
5. Existing gameplay — cat AI, desires, heat propagation, nav graph, placement, starter objects — keeps working against the new grid.
6. Reclamation growth on servers (vine/moss/flower sprites) appears when cats have tended a slot long enough, supporting the reclamation aesthetic from `narrative.md`. Robot-voice narrative hooks included.
7. **Mockup-as-truth:** if `tcp_mockup.png` and this spec disagree, the mockup wins and the spec gets updated. Artists ship ground truth; specs catch up.

### Success criteria

1. `Constants.gd` holds the new grid values (table in Section 1) and every downstream system reads them via the constant or helper function, not literals.
2. `game_client.gd` places one `rack_5set` sprite per bay at `bay_index * BAY_STRIDE_PX`, with the active bay centered in the viewport.
3. A `TileMap` node paints the ceiling, wall, cables, baseboard, and ground from `tcp_environment.tres`, replacing the `_FLOOR_TEX` / `_build_floor()` quick fix.
4. Reclamation growth (plant sprite child of server) appears within 5 minutes of cumulative cat presence at a warm slot and survives HUM brownouts.
5. Robot log entries fire on growth spawn and despawn with the exact voice from narrative.md.
6. All existing tests pass against the new constants. There are no hardcoded grid values outside `constants.gd`.
7. Visual smoke test: running the game shows the 5-rack bay centered, ~47px peek of neighboring bays on each side, environment tiles filling the rest of the viewport, in proportions matching `tcp_mockup.png`.

### Non-goals (deferred)

- Full horizontal scrolling with multi-bay world generation. Coordinate system must permit it; camera stays centered on bay 0 in this spec.
- Sprite sheet animation support (`_stripN` → `AnimatedSprite2D`). Servers, dust balls, boxes render as static single-frame sprites for now. Separate follow-up spec.
- Multiplayer bay ownership and rack-strip mechanics from `CLAUDE.md`. Co-op uses 3-rack stripes per CLAUDE.md, which means `RACK_COUNT` may become per-bay-variable in the future. Flagged but not implemented.
- Rescaling cats, ferrets, robot arm, or any animal sprite. See the **Visual Regression Ledger** below for the explicit implications.
- Per-slot palette interpolation from `art-direction.md` §2. Incompatible with TileMap + Sprite2D racks without a shader. Demoted to "global warmth tint via canvas modulate on the rack decor layer" in this spec. Proper per-slot shader pass is a separate polish spec.
- Dynamic rack decor alpha tied to aggregate warmth. The overlay ramps from 0 at first run to 0.7 after the first plant spawns, but doesn't track ongoing warmth. Proper dynamic shader is future work.
- TOR switches. `TOR_SWITCH_SLOTS = 0` for the prototype because the top-of-rack hardware doesn't fit visually in a 10-slot rack at 8px/U. TOR switches will return when infrastructure diversity matters — the network-as-purr narrative hook in `narrative.md` is deferred, not cancelled.

---

## Visual Regression Ledger

This spec softens or defers several commitments in `.claude/rules/art-direction.md`. Listing them explicitly so nobody is surprised and so follow-up specs know exactly what's pending.

| Source | Commitment | Status in this spec | Path forward |
|---|---|---|---|
| art-direction.md §1 | 7 playable + 2 decorative half-racks = 640px | **Replaced.** 5 playable racks + 47px edge peeks = 640px. Peeks ARE the new half-racks. | CLAUDE.md gets updated in the same PR. |
| art-direction.md §2 | Per-slot palette interpolation (warmth shifts 6 colors) | **Deferred.** No per-slot shift. Global warmth tint on rack decor overlay only. | Follow-up spec: per-slot palette shader pass. |
| art-direction.md §3 | Five distinguishable cat models at 40×40 native | **Modified.** Cats stay 40×40, but the 23px rack interior means cats overflow the rack horizontally (~8px each side) and span ~5 slots vertically. Cats visually float in front of the rack plane. Accepted as canon — cats are physically bigger than servers per §1. | Accepted, no further work. |
| art-direction.md §4 | Three zoom levels (Z0 rack, Z1 drawer, Z2 overview) with separate sprites | **Z0 only.** The 24px/U Z0 scale from the old spec is gone; the new Z0 is 8px/U. Z1 drawer view and Z2 overview are not in this spec. | Follow-up specs if/when needed. |
| art-direction.md §5 | Warmth halos per animal, stacking additively | **Preserved.** Halo rendering is unchanged — it's a shader effect over the animals layer, independent of the rack scale. | No change. |
| art-direction.md §6 | 2px status strip per occupied slot | **Preserved but at risk.** At 8px slot height, a 2px strip is 25% of the slot — readable at 3× display. Status icon shapes (circle/triangle/diamond/octagon) can't fit inside the slot and move to the inspect tooltip only. | This spec: strip preserved, icons moved to tooltip. Follow-up: re-evaluate if cats/servers occlude the strip. |
| art-direction.md §7 | Z-order priority 0 = rack structure, cats on top | **Preserved with clarification.** Z-order: environment tilemap (0) → rack sprite (1) → rack decor (2) → placed objects (3) → cats/animals (4) → status strip (when focused, 5) → HUD (10). See Section 3. |
| asset-pipeline.md | `rack_frame` 1 frame 96×672 | **Obsolete.** Replaced by `rack_single_idle_strip1.png` (64×96) and `rack_5set_idle_strip1.png` (186×96). Asset-pipeline.md gets rewritten in the same PR. |
| asset-pipeline.md | `server_1u_off` 64×16, `server_1u_on` 64×16 | **Obsolete sprite files.** Replaced by `server01_static_strip1.png` (23×8) and `server02_static_strip1.png`. **The StringName `server_1u` stays as the entity type key** for this spec — see Section 4. |
| narrative.md | UNIT-C01 arrives in "Rack 03, slots 1-3" | **Preserved.** Rack 03 in a 5-rack bay is the center rack, which is still where the first cat logically goes. Log string is unchanged. |

---

## Section 1 — New grid constants

| Constant | Current | New | Source |
|---|---|---|---|
| `SLOT_HEIGHT_PX` | 7 | **8** | `server01_static_strip1.png` is 23×8 |
| `SLOTS_PER_RACK` | 42 | **10** | 10 visible server bays in `rack_single_idle_strip1.png` body |
| `RACK_WIDTH_PX` (interior) | 76 | **23** | Server sprite width, one server fills the interior |
| `RACK_STRIDE_PX` (within 5-set) | 80 | **31** | 23 interior + 8 shared wall |
| `RACK_GAP_PX` (wall between racks) | 4 | **8** | Pixel-scan of 5-set between racks |
| `RACK_COUNT` (visible per bay) | 7 | **5** | Five racks in `rack_5set_idle_strip1.png` |
| `FLOOR_HEIGHT_PX` | 40 | **40** | Unchanged |
| `TOR_SWITCH_SLOTS` | 4 | **0** | Deferred (see non-goals) |
| Viewport | 640×360 | 640×360 | Unchanged — mockup is 3× this |
| `LEFTMOST_RACK_OFFSET_PX` (new) | — | **25** | Shelf-detail padding inside 5-set sprite |
| `BAY_WIDTH_PX` (new) | — | **186** | 5-set sprite width |
| `BAY_STRIDE_PX` (new) | — | **366** | Bay width + 180px environment gap |
| `BAY_PEEK_PX` (new) | — | **47** | Visible portion of each neighboring bay |

**Integer-in-core rule:** all the above are the display values. The core math uses PU (position units, ×100 integer). `Constants.gd` also exports the PU versions so no downstream caller computes `PX * POSITION_SCALE` by hand:

```gdscript
const SLOT_HEIGHT_PX: int = 8
const SLOT_HEIGHT_PU: int = SLOT_HEIGHT_PX * POSITION_SCALE  # 800

const RACK_WIDTH_PX: int = 23
const RACK_WIDTH_PU: int = RACK_WIDTH_PX * POSITION_SCALE  # 2300

const RACK_STRIDE_PX: int = 31
const RACK_STRIDE_PU: int = RACK_STRIDE_PX * POSITION_SCALE  # 3100

const LEFTMOST_RACK_OFFSET_PX: int = 25
const LEFTMOST_RACK_OFFSET_PU: int = LEFTMOST_RACK_OFFSET_PX * POSITION_SCALE  # 2500

const BAY_WIDTH_PX: int = 186
const BAY_WIDTH_PU: int = BAY_WIDTH_PX * POSITION_SCALE  # 18600

const BAY_STRIDE_PX: int = 366
const BAY_STRIDE_PU: int = BAY_STRIDE_PX * POSITION_SCALE  # 36600
```

And helper functions — **single source of truth for bay/rack/slot coordinate conversions**:

```gdscript
static func bay_origin_pu(bay_index: int) -> Vector2i:
    return Vector2i(bay_index * BAY_STRIDE_PU, 0)

static func rack_interior_pu(bay_index: int, rack_in_bay: int) -> int:
    # x-coordinate of the interior's left edge in PU
    return bay_index * BAY_STRIDE_PU + LEFTMOST_RACK_OFFSET_PU + (rack_in_bay * RACK_STRIDE_PU)

static func rack_slot_to_pu(bay_index: int, rack_in_bay: int, slot: int) -> Vector2i:
    # Full coordinate for a specific rack slot
    var x: int = rack_interior_pu(bay_index, rack_in_bay) + (RACK_WIDTH_PU / 2)
    var y: int = slot * SLOT_HEIGHT_PU
    return Vector2i(x, y)

static func pu_to_bay_rack_slot(pu_x: int, pu_y: int) -> Dictionary:
    # Inverse — used by _try_place_at() for snap math
    var bay_index: int = int(floori(float(pu_x) / float(BAY_STRIDE_PU)))
    var bay_local_x: int = pu_x - (bay_index * BAY_STRIDE_PU)
    var rack_in_bay: int = (bay_local_x - LEFTMOST_RACK_OFFSET_PU) / RACK_STRIDE_PU
    var slot: int = pu_y / SLOT_HEIGHT_PU
    return {"bay": bay_index, "rack": rack_in_bay, "slot": slot}
```

Every downstream caller uses these helpers. No downstream file should ever compute `25 + i * 31` or `bay_index * 366` by hand.

**Rack body height:** 10 slots × 8 px = 80px. Sprite is 96px tall, leaving ~16px for header/top trim above slot 0.

---

## Section 2 — Viewport composition

The viewport stays at 640×360 internal resolution, scaled to any display via Godot's `canvas_items` stretch mode (3× → 1920×1080 matches the mockup exactly).

### Horizontal layout

Bays are placed in world coordinates at `bay_index * BAY_STRIDE_PX`. The camera centers on the active bay. For `bay_index = 0` centered:

```
camera.x = BAY_WIDTH_PX / 2 = 93
visible world x range = [93 - 320, 93 + 320] = [-227, 413]
```

| Visible range | Width | Content |
|---|---|---|
| -227 → -180 | 47 | Right edge of bay -1 (peek) |
| -180 → 0 | 180 | Environment gap (wall + cables + plants) |
| 0 → 186 | 186 | **Active bay 0** (5-set rack sprite) |
| 186 → 366 | 180 | Environment gap (wall + cables + plants) |
| 366 → 413 | 47 | Left edge of bay 1 (peek, starts with 17px shelf detail) |

Total: 47 + 180 + 186 + 180 + 47 = 640 ✓

**The 47px peeks replace the 40px decorative half-racks from the old art-direction.md §1 layout.** Each peek shows the edge of a real neighboring bay rather than a standalone half-rack sprite. Per Pebble's accessibility review, peek bays render at **-30% brightness** (`modulate = Color(0.7, 0.7, 0.7, 1.0)`) so they don't compete with the active bay for attention and improve visual parsing.

### Vertical layout

| y range | Height | Content |
|---|---|---|
| 0 → 32 | 32 | Ceiling + hanging cables (tileset row 0) |
| 32 → 224 | 192 | Wall fill (tileset cols 0–3, rows 0–2, tiled vertically) |
| 224 → 320 | 96 | Rack row — `rack_5set` sprite top-anchored at y=224 |
| 320 → 360 | 40 | Floor strip (baseboard row 3, ground surface rows 3–5) |

Total: 32 + 192 + 96 + 40 = 360 ✓

### Camera position

```gdscript
static func bay_center(bay_index: int) -> Vector2:
    var bay_x: float = float(bay_index * BAY_STRIDE_PX) + float(BAY_WIDTH_PX) / 2.0
    return Vector2(bay_x, 180.0)
```

Follow-cam `F` key (per `input-design.md`) calls this to center a specific bay. Single source of truth, no duplicated math.

### Scroll-support compatibility

Bays at `i * BAY_STRIDE_PX` and environment tiles painted into the same coordinate space mean adding bays `-2, -1, 1, 2, ...` in a follow-up spec is purely a "paint more tiles, place more rack sprites" exercise.

**Bay 0 is the only simulated bay in this spec.** `nav_graph_builder` and `heat_grid` scope their node/cell generation to `bay_index == 0`. Bays -1 and 1 are rendered visually (rack sprite + environment tiles + peeks) but have no game state — no cats, no heat propagation, no placement. Follow-up specs add simulation for more bays.

Per Parcel's review, the peek bays are **painted with extra vines and plants in the tilemap** to imply the "untended parts of the datacenter." This is pure tile painting, no code — but it contrasts the active bay as "your rescued corner" from the surrounding neglect.

---

## Section 3 — TileMap architecture + rack rendering

### File layout

Per Bento's directory convention feedback, the tileset resource lives beside the PNG it references:

```
mods/tcp_base/
  sprites/
    environment/
      tcp_tileset01.png
      tcp_tileset01.png.import
      tcp_environment.tres          # TileSet resource beside the atlas
engine/
  environment/
    tile_painter.gd                 # RefCounted — calls set_cell() on a TileMap reference
nodes/
  environment_tilemap.tscn          # Vanilla TileMap node, no custom script
```

### TileSet resource

`tcp_environment.tres` wraps a `TileSetAtlasSource` pointing at `res://mods/tcp_base/sprites/environment/tcp_tileset01.png`:

- Atlas size: 192×96 pixels
- Tile size: 16×16
- Tile grid: 12 columns × 6 rows = 72 tile cells
- Only non-transparent cells are registered

### Tile cell map (flat list, greppable)

Per Bento's format feedback — one line per tile, easy to copy, diff, and extend:

| tile_name | row | col | description |
|---|---|---|---|
| `env_ceiling` | 0 | 0 | Ceiling corner |
| `env_wall` | 0 | 1 | Wall tile (also row 0 col 2, 3; row 1 col 0-3; row 2 col 0-3 — same art) |
| `env_cable_a_left` | 0 | 4 | Cable A, left half |
| `env_cable_a_right` | 0 | 5 | Cable A, right half |
| `env_cable_b_left_top` | 0 | 6 | Cable B, left half, top |
| `env_cable_b_right_top` | 0 | 7 | Cable B, right half, top |
| `env_cable_c_left_top` | 0 | 8 | Cable C, left half, top |
| `env_cable_c_right_top` | 0 | 9 | Cable C, right half, top |
| `env_cable_d_left_top` | 0 | 9 | (same tile; cable C right = cable D left) |
| `env_cable_d_right_top` | 0 | 10 | Cable D, right half, top |
| `env_cable_e_u` | 0 | 11 | Cable E (U-bend, single tile) |
| `env_cable_b_left_bot` | 1 | 6 | Cable B, left half, bottom |
| `env_cable_b_right_bot` | 1 | 7 | Cable B, right half, bottom |
| `env_cable_c_left_bot` | 1 | 8 | Cable C, left half, bottom |
| `env_cable_c_right_bot` | 1 | 9 | Cable C, right half, bottom |
| `env_cable_d_right_bot` | 1 | 10 | Cable D, right half, bottom |
| `env_flower_orange` | 2 | 4 | Orange flowers |
| `env_flower_yellow` | 2 | 5 | Yellow/orange flowers |
| `env_leaves` | 2 | 6 | Leaves |
| `env_grass` | 2 | 7 | Grass |
| `env_blossoms_orange` | 2 | 8 | Orange blossoms |
| `env_blossom_single` | 2 | 9 | Single orange blossom |
| `env_grass_small` | 2 | 10 | Little grass |
| `env_baseboard_a` | 3 | 0 | Baseboard (left variant) |
| `env_baseboard_b` | 3 | 1 | Baseboard |
| `env_baseboard_c` | 3 | 2 | Baseboard |
| `env_wall_lower` | 3 | 3 | Wall surface (lighter, at floor level) |
| `env_ground_a` | 3 | 4 | Ground surface |
| `env_ground_b` | 3 | 5 | Ground surface |
| `env_ground_c` | 3 | 6 | Ground surface |
| `env_ground_d` | 3 | 7 | Ground surface |
| `env_ground_e` | 3 | 8 | Ground surface |
| `env_ground_f` | 3 | 9 | Ground surface |
| `env_ground_g` | 3 | 10 | Ground surface |
| `env_dark_edge` | 4 | 0 | Dark edge piece |
| `env_plants_small` | 4 | 4 | Small plants |
| `env_ground_h` | 5 | 4 | Ground surface (continuation) |
| `env_ground_i` | 5 | 5 | Ground surface |
| `env_ground_j` | 5 | 6 | Ground surface |
| `env_ground_k` | 5 | 7 | Ground surface |

The reclamation-growth sprites (Section 5) are **cropped 8×8 sub-tiles** from `env_flower_orange`, `env_grass`, `env_blossoms_orange`, and `env_grass_small`. Cropping happens at runtime via `AtlasTexture` with a smaller region; we don't add new files.

### Scene tree for the world

Inside `GameClient.World` — Z-order from back to front:

```
World (Node2D)
├── EnvironmentTileMap (TileMap, z=0)         # Walls, ceiling, cables, baseboard, ground
├── RackRow (Node2D, z=1)
│   ├── Bay_-1 (Sprite2D, modulate=(0.7,0.7,0.7,1))  # Peek bay (muted)
│   ├── Bay_0 (Sprite2D)                      # rack_5set_idle_strip1.png @ (0, 224)
│   └── Bay_1 (Sprite2D, modulate=(0.7,0.7,0.7,1))   # Peek bay (muted)
├── RackDecor (Node2D, z=2)                   # Vine overlays
│   └── Bay_0_decor (Sprite2D)                # rack_5set_decor_strip1.png, modulate alpha
├── PlacedObjects (Node2D, z=3)               # Servers, boxes, piles
├── DynamicPlants (Node2D, z=3)               # Growth sprites — child of their server
├── Animals (Node2D, z=4)                     # Cats, ferrets — overflow racks, float in front
├── StatusStrips (Node2D, z=5)                # 2px per-slot strips (when focused)
├── FocusHalo (Node2D, z=6)                   # Keyboard/controller focus ring — see Pebble notes
├── HeatOverlay (Node2D, z=7)                 # Existing — unchanged
└── RuGridOverlay (Node2D, z=100)             # Debug — toggleable
```

### Environment painter (RefCounted, not TileMap subclass)

Per Bramble's review, logic lives in RefCounted. The TileMap node is vanilla — `environment_tilemap.tscn` instances a `TileMap` with `tcp_environment.tres` assigned, nothing custom.

The painter is a RefCounted helper:

```gdscript
class_name TilePainter extends RefCounted

var _tilemap: TileMap
var _source_id: int  # TileSet source ID for tcp_environment.tres

func _init(tilemap: TileMap) -> void:
    _tilemap = tilemap
    _source_id = 0  # Assuming single source in the tileset

func paint_bay(bay_index: int) -> void:
    # Paints ceiling, wall, cables, baseboard, ground for a bay range.
    # Coordinates computed from Constants.BAY_STRIDE_PX + bay_index.
    var bay_start_cell: Vector2i = _world_px_to_cell(bay_index * Constants.BAY_STRIDE_PX, 0)
    var bay_end_cell: Vector2i = _world_px_to_cell((bay_index + 1) * Constants.BAY_STRIDE_PX, 360)
    _paint_ceiling_range(bay_start_cell.x, bay_end_cell.x)
    _paint_wall_range(bay_start_cell.x, bay_end_cell.x)
    _paint_baseboard_and_ground(bay_start_cell.x, bay_end_cell.x)
    _paint_cables_in_gap(bay_index)  # only in the environment gap on each side
    if bay_index != 0:
        _paint_abandonment_decor(bay_start_cell.x, bay_end_cell.x)  # Extra vines for peek bays

func clear_bay(bay_index: int) -> void: ...

func _world_px_to_cell(x_px: int, y_px: int) -> Vector2i: ...
```

`TilePainter` is unit-testable without a scene tree — the constructor takes any TileMap reference, including a minimal stub in tests.

### Rack rendering (still Sprite2D, per Smudge)

Each bay is rendered as a single `Sprite2D` placed at `(bay_index * BAY_STRIDE_PX, 224)` with `rack_5set_idle_strip1.png` as its texture, not centered. Splitting the 5-set into 16×16 tiles would be fragile if the artist ships updated racks — a sprite is a single source of truth. Peek bays (-1 and 1) get `modulate = Color(0.7, 0.7, 0.7, 1.0)` for the muted look.

### Rack decor overlay

`rack_5set_decor_strip1.png` is a single-frame transparent overlay of vines draped around the rack row. Rendered as a second `Sprite2D` at the same position as the bay. **Alpha is not constant** — per Parcel's review, it ramps from 0 to 0.7 the first time a reclamation plant spawns in bay 0. This preserves the "I grew these" feeling for the first ~minutes of play.

```gdscript
# In dynamic_plants.gd, on first plant spawn:
rack_decor_alpha = 0.7  # stored in game state, persists through game
```

The target alpha lives in `config/balance/rendering.jsonc`:

```jsonc
{
  "rack_decor_final_alpha": 700,  // 0.7 in UNIT (0-1000) scale
  "rack_decor_ramp_duration_ticks": 100
}
```

Per Bramble's review, rendering constants live in config, not code.

### `rack_single_decor_strip6.png` (unused in this spec)

The 6-frame single-rack vine overlay is **reserved for future use** by mod extensions that render single-rack bays (e.g., narrow mod-added bays that don't fit the 5-set). Not deleted. Documented here so the next agent doesn't remove it as dead weight.

### Floor Sprite2D-per-column code is deleted

- `_build_floor()` in `game_client.gd` goes away.
- `_FLOOR_REGION` constant and `_floor_tex: AtlasTexture` field go away.
- `_TILESET_ATLAS` preload stays — moved into the TileSet resource.
- Old floor positioning logic in `_build_starter_objects()` updates to the new rack coordinate system.

---

## Section 4 — State preservation

Every subsystem that reads the old grid constants must read the new ones from `Constants.gd` **via the helper functions**, not literal constants or recomputed offsets. The rule: **no hardcoded grid values or bay coordinate math outside `constants.gd`**.

| Subsystem | What changes | Action |
|---|---|---|
| `engine/core/constants.gd` | New values, new PU constants, new helper functions (Section 1) | Update literals + add helpers |
| `engine/spatial/heat_grid.gd` | Cell count drops from 301 (42×7 + 7) to 55 (10×5 + 5) | **Explicit scope:** only bay 0. Formula uses constants + helpers |
| `engine/navigation/nav_graph_builder.gd` | Fewer nav nodes, different spacing | **Explicit scope:** only bay 0. Uses helpers |
| `engine/desires/desire_resolver.gd` | Random placement ranges shrink | No code change — reads constants |
| `nodes/game_client.gd` | Rack building, bay layout, delete `_build_floor()`, add tilemap wiring, update starter objects | Real edits — see below |
| `nodes/ru_grid_overlay.gd` | Grid spacing changes | No code change — reads constants |
| Server type key | **StringName `server_1u` stays unchanged.** Only the sprite file renames | See rename strategy below |
| Starter object positions | Hardcoded literal offsets | Rebase on `Constants.rack_slot_to_pu()` |
| Tests with hardcoded grid values | Break on the constant change | Audit checklist (Section 7) |

### Server sprite rename strategy (NOT type rename)

Per Bento's and Bramble's reviews — the cleanest path is to keep the entity type key `server_1u` as a StringName, and only update the sprite file path reference:

- **Keep:** `StringName("server_1u")` everywhere it appears (`_try_place_at`, placement UI, starter objects, match statements, tests).
- **Change:** the sprite file lookup for that type points at `server01_static_strip1.png` instead of the old `server_1u_off.png`.
- **Why:** decoupling the type key from the sprite file. The name `server_1u` is an abstract ID that happens to have historical meaning — renaming it ripples across 5+ call sites, breaks placement tests, and creates a save migration requirement. The sprite file is cosmetic. When mod extraction lands and servers move to JSON entity definitions, the string `"server_1u"` becomes a `"id"` field in JSON — still no rename needed.
- **Follow-up:** when mod extraction lands, the JSON entity definition can use a clearer name (`server` or `server_small`). That's a mod-extraction concern, not this spec's.

### Edits to `game_client.gd`

- Delete `_build_floor()`, `_FLOOR_REGION`, `_floor_tex`, `_TILESET_ATLAS`.
- Rename `_build_racks()` → `_build_bays()`, place one `rack_5set` sprite per bay at `Constants.bay_center(i) - Vector2(BAY_WIDTH_PX/2, 0)`.
- Add `_build_environment_tilemap()` — instances `environment_tilemap.tscn`, creates a `TilePainter(tilemap)`, calls `painter.paint_bay(i)` for `i ∈ {-1, 0, 1}`.
- Add `_build_rack_decor()` — single decor sprite for bay 0 with alpha 0 initially.
- Update `_build_starter_objects()` to use `Constants.rack_slot_to_pu(0, 1, 8)` style calls — no literal coordinates.
- Update `_try_place_at()` — use `Constants.pu_to_bay_rack_slot()` for snap math.
- Update camera initial position via `Constants.bay_center(0)`.

### Test audit checklist

**Not grep-alone.** Per Kibble and Bramble, the audit must cover:

1. **Text grep** for literals in `.gd` files:
   ```
   grep -rE '\b(42|294|80|76|96)\b' tests/ engine/ nodes/
   grep -rE 'SLOTS_PER_RACK|RACK_COUNT|RACK_WIDTH_PX|SLOT_HEIGHT_PX|RACK_STRIDE_PX' tests/ engine/ nodes/
   ```
2. **Text grep** for expressions that compute grid math:
   ```
   grep -rE '\*\s*(7|8|42|80)' tests/ engine/ nodes/
   grep -rE 'SLOTS_PER_RACK\s*-' tests/ engine/ nodes/     # e.g. SLOTS_PER_RACK - 2
   ```
3. **Scene/resource file scan:**
   ```
   grep -rE '\b(42|294|80|76|96)\b' nodes/*.tscn mods/tcp_base/**/*.tres
   ```
4. **Vector2 position literals** in tests — these hide grid assumptions:
   ```
   grep -rE 'Vector2(\b|[0-9])' tests/scenario/ tests/integration/
   ```
5. **Manual scan** of `tests/scenario/` for behavioral assertions that embed coordinates (`cat ends up in slot 40`).
6. **"server_1u" string literal sites:**
   ```
   grep -rn '"server_1u"\|&"server_1u"' .
   ```
   Expected hits: `game_server.gd`, `game_client.gd`, `placement_ui.gd`, starter config, tests. All stay unchanged (we're not renaming the type key).

The audit step produces a checklist file `tests/.audit/2026-04-10-grid-rescale-audit.md` that's deleted after the rescale is complete. Each hit becomes a task in the implementation plan.

### Migration of save files

Not applicable — prototype has no persistent saves. Any leftover dev saves are deleted.

---

## Section 5 — Reclamation growth on servers

Supports the reclamation aesthetic from `narrative.md` with a mechanical hook and narrative voice.

### Trigger (per Parcel and Mochi)

Reclamation growth appears on a server when **both** conditions hold:

1. Warmth at the server's slot is above **0.6** (permissive precondition — cold slots never grow anything)
2. Cumulative cat-presence at the slot reaches **300 cat-seconds** (~5 minutes of a cat loafing there, or 5 cats loafing for 1 minute each)

Removal: growth is removed when cumulative cat-presence decays below **100 cat-seconds**. Warmth alone doesn't kill the growth — **reclamation is cumulative, brownouts are transient** (per Parcel). Plants survive HUM reserve drops, they survive cold snaps from the 0.4 warmth threshold. They only disappear when the cat presence decays.

**Hysteresis is state-based, not threshold-based** (per Mochi's concern #3). The state machine has four explicit states:

```
DORMANT  →(warmth ≥ 0.6 and cat present)→  ARMED
ARMED    →(300 cat-seconds accumulated)→     GROWING
GROWING  →(one tick)→                        PRESENT
PRESENT  →(cat-seconds decays < 100)→        DORMANT
```

Entering ARMED from DORMANT starts the cat-second accumulator. Leaving ARMED back to DORMANT (cat leaves before 300 seconds) zeroes the accumulator. PRESENT is sticky — once grown, a plant stays as long as cats tend the slot.

### Pure Core architecture (per Bramble)

Plant state is a GameStateDB component, not a Node-local dictionary.

**Component:** `plant_growth`
```
{
  "state": StringName,           # DORMANT / ARMED / GROWING / PRESENT
  "cat_seconds": int,            # in UNIT (1000 = 1 second)
  "variant": StringName,         # moss / grass / blossom / flower
  "attached_to": int             # entity ID of the server
}
```

**System:** `engine/growth/plant_growth_system.gd` (RefCounted)
```gdscript
class_name PlantGrowthSystem extends RefCounted

var _db: GameStateDB
var _heat_grid: HeatGrid

func _init(db: GameStateDB, heat_grid: HeatGrid) -> void: ...

# Called by GameServer in _physics_process, after scatter_heat_to_warmth()
func tick() -> void:
    # Use change detection — only process entities whose warmth or cat_presence changed this tick
    var dirty: Array[int] = _db.get_changed_entities(&"warmth", _last_tick)
    for entity_id in dirty:
        _evaluate(entity_id)
    _db.get_changed_entities(&"cat_presence", _last_tick).map(_evaluate)
    _last_tick = _db.get_tick()

func _evaluate(server_id: int) -> void:
    # State machine transitions — all state in GameStateDB
```

Per `design-philosophy.md`'s change detection rule, the system only re-evaluates entities whose warmth or cat_presence components changed this tick. At 50 servers this is trivially small, but the pattern matters — no per-tick full scans.

**Node layer** — `nodes/dynamic_plants.gd` is a projection-only Node:
```gdscript
extends Node

# Subscribes to plant_growth component add/remove via db.watch_lifecycle
# When PRESENT: instantiate a Sprite2D child of the server's sprite
# When not PRESENT: despawn the Sprite2D
# No game logic. No state. Projects DB state to Sprite2Ds.
```

Per `design-philosophy.md` Pure Core pattern.

### Cat presence tracking

`cat_presence` is a per-slot integer in GameStateDB. Incremented each tick a cat is within 1 rack of the slot. Decays by 1 per tick when no cat is nearby. Natural cap at some sensible value (e.g. 1000 cat-seconds = 100 seconds wall-clock).

This is a small new component, not a whole system — it tracks one integer. Updates happen inside the existing `desire_resolver` or `animal_registry` on cat movement. Specifically, the movement system has a "which slot is this cat in" hook already (for heat grid targeting); extend it to bump `cat_presence` on the slot the cat occupies.

### Sprite size and placement

Per Smudge's review — **8×8 cropped sprites**, not 16×16 tileset tiles:

```gdscript
const PLANT_SPRITE_SIZE: int = 8

func _create_plant_sprite(variant: StringName) -> Sprite2D:
    var sprite := Sprite2D.new()
    var atlas := AtlasTexture.new()
    atlas.atlas = preload("res://mods/tcp_base/sprites/environment/tcp_tileset01.png")
    atlas.region = _region_for_variant(variant)  # 8×8 sub-region of a 16×16 plant tile
    sprite.texture = atlas
    sprite.centered = false
    sprite.position = Vector2(-2, -2)  # overlap server top edge slightly
    return sprite

func _region_for_variant(variant: StringName) -> Rect2:
    match variant:
        &"moss":    return Rect2(96, 32, 8, 8)    # top-left quarter of env_leaves
        &"grass":   return Rect2(112, 32, 8, 8)   # top-left of env_grass
        &"blossom": return Rect2(128, 32, 8, 8)   # top-left of env_blossoms_orange
        &"flower":  return Rect2(64, 32, 8, 8)    # top-left of env_flower_orange
```

At `(-2, -2)` the plant overlaps the top edge of the server. Per Pebble's review, the plant MUST NOT occlude the left 2px of the server (that's the status strip real estate). `(-2, -2)` clears the status strip region.

### Plant variant meaning (per Parcel)

Variant is **determined by which species accumulated the most cat-seconds** at that slot:

```
cat-dominant slot  → variant = moss or grass (cats bring earthy growth)
ferret-dominant    → variant = blossom (ferrets drag flowers around)
mixed              → variant = flower (pick deterministically from slot coordinates)
```

The robot never explains this. Players eventually notice. Zero extra assets.

### Narrative hooks (per Parcel — non-negotiable)

When a plant first spawns on a server, emit a robot log entry via the event bus:

> `[NOTE] UNIT-S04 is producing unauthorized biological output. Green. Soft. Non-responsive to ping. Best hardware match: a 'houseplant' (confidence 3%). Adding to inventory as DECORATIVE-GROWTH-01. UNIT-S04 appears unbothered. Will continue monitoring.`

When a plant despawns (cat presence decays):

> `[LOG] DECORATIVE-GROWTH-01 has gone offline. UNIT-S04 resuming standard operations. I will miss it.`

The last line is the whole reclamation arc in six words. **Required, not optional.**

Implementation: emit `Events.plant_spawned(server_id, variant, growth_id)` and `Events.plant_despawned(server_id, growth_id)`. The robot narrator subscribes and formats the log message. Growth IDs are sequential integers prefixed `DECORATIVE-GROWTH-NN`.

### Voice constraint

**Never use the word "plant" in robot-facing strings.** The robot doesn't know that word. Use `DECORATIVE-GROWTH-NN`, `BIOLOGICAL-ARTIFACT-NN`, `UNSCHEDULED-FLORA`. Player-facing UI (inspect panel) can say "plant."

### HUM compatibility

Plants are **unaffected by HUM reserve state.** When HUM brownout fires (<20% reserve, per `core-loop.md`), lights dim, servos slow, the robot narrates apologies — but the moss stays. Reclamation is cumulative; brownouts are transient. This reinforces commitment #1 from core-loop.md (no cat-guilt, no precarity creep).

### Mechanical hook

Each `plant_growth` component in PRESENT state advertises `comfort +100, radius 2 RU` on the event bus (per Mochi's concern #2). Small enough that it's not balance-critical. Big enough that a thriving area compounds — more comfort ads attract more cats, more cats accumulate more presence, more plants grow. This is the emergent feedback Mochi asked for.

---

## Section 6 — Coordination with mod extraction

`docs/superpowers/specs/2026-04-10-mod-extraction-design.md` is being authored in parallel. It extracts species/object content into standalone mods and replaces the hardcoded `db.set_component()` spawn blocks in `game_server.gd` with `entity_def_registry.spawn()`.

### Interface agreement (per Bramble — needed before either merges)

Both specs need to agree on `entity_def_registry.spawn()`'s signature **now**, not after the merge:

```gdscript
# Agreed interface — copy this signature into both specs
func spawn(
    entity_id: StringName,
    db: GameStateDB,
    overrides: Dictionary = {}
) -> int
```

Where `overrides` supports:
- `"position": Vector2i` — in PU coordinates (not PX)
- `"slot": { "bay": int, "rack": int, "slot": int }` — alternative to position, uses `Constants.rack_slot_to_pu()` internally
- Additional component overrides (desires, species variant, etc.)

The art-scale spec uses `overrides.slot` for starter objects so the caller doesn't do PX-to-PU conversion. The mod-extraction spec treats `overrides.position` as the primary path for its own tests.

### Shared files — conflict map

| File | Mod extraction change | Art scale change | Resolution |
|---|---|---|---|
| `engine/desires/desire_resolver.gd` | Consume species data from registry | Random placement ranges auto-update via constants | **No conflict** — orthogonal |
| `nodes/game_server.gd` | Delete inline spawn blocks, replace with registry calls | Not touched | No conflict here for this spec |
| `nodes/game_client.gd` | Not touched | Rewritten (bays, tilemap, starter objects) | No conflict |
| `engine/core/constants.gd` | Not touched | New values + helpers | No conflict |
| `.claude/rules/art-direction.md` | Not touched | Updated | No conflict |
| `.claude/rules/asset-pipeline.md` | Not touched | Restructured | No conflict |
| Sprite locations | Cat/tuna to separate mods | Environment/rack/server stay in tcp_base | **No conflict** — confirmed in Section 5 below |
| Starter object spawning | Routed through `entity_def_registry.spawn()` | Updated starter coordinates | **Overlap — resolved by interface agreement above** |

### Sprite ownership

Per Bento's review — confirm in this spec that:

- **Stays in tcp_base:** `sprites/environment/*`, `sprites/infrastructure/rack/*`, `sprites/infrastructure/server/*`, `sprites/objects/*` (boxes, dust balls, cables), and the new `tcp_environment.tres` tileset resource. Environment and infrastructure ARE the framework's aesthetic.
- **Moves to satellite mods (mod-extraction):** `sprites/cat/*` → `mods/tcp_cats/sprites/`, animal sounds similarly, tuna can sprites → `mods/tcp_tuna/sprites/`.

Mod extraction's scanner must not reach into `tcp_base/sprites/infrastructure/` or `environment/`.

### Spec updates not covered here

Mod extraction flags an `animal-ai.md` update (signed desires merging aversions into `desires`). Independent of this spec — we don't touch desire scoring.

---

## Section 7 — Testing strategy

### Red-green-refactor per test

Full `.claude/rules/llm-test-verification.md` cycle for every changed test. Per Kibble: the "cosmetic exception" does NOT apply when constant values change (`assert_eq(cell_count, 301)` → `55` is a behavioral assertion change). Hold the line.

### Soak test stuck-animal threshold (per Kibble)

Current soak code uses a hardcoded `distance < 50` to detect stuck animals. The new `RACK_STRIDE_PX = 31` means 50px is >1.5 rack widths — stuck animals hide in the tolerance. **MUST** parameterize on constants:

```gdscript
const STUCK_THRESHOLD_PX: int = Constants.RACK_STRIDE_PX / 2   # 15px = half a rack width
```

Update the existing soak tests in the audit phase (Section 4).

### New tests

| Test file | Type | What it verifies |
|---|---|---|
| `tests/unit/test_bay_layout.gd` | Unit | `bay_origin_pu`, `rack_interior_pu`, `rack_slot_to_pu`, `pu_to_bay_rack_slot`, `bay_center` — round-trip conversions, positive and negative bay indices |
| `tests/unit/test_tile_painter.gd` | Unit | `paint_bay(0)`, `paint_bay(-1)`, `paint_bay(1)` — verify cell coordinates match expected tilemap positions; test with mock TileMap |
| `tests/unit/test_plant_growth_system.gd` | Unit | State machine transitions (DORMANT → ARMED → GROWING → PRESENT → DORMANT), cat-seconds accumulator, **explicit hysteresis dip test** (warmth goes 0.7 → 0.5 → 0.7 with cat still present), HUM brownout doesn't despawn |
| `tests/unit/test_plant_projection.gd` | Unit | `dynamic_plants.gd` Node spawns/despawns Sprite2D children in response to lifecycle events on the `plant_growth` component |
| `tests/unit/test_placement_boundary.gd` | Unit | `_try_place_at` snap math at `(0, LEFTMOST_RACK_OFFSET_PX - 1, LEFTMOST_RACK_OFFSET_PX, LEFTMOST_RACK_OFFSET_PX + RACK_STRIDE_PX - 1)` — off-by-one risk |
| `tests/integration/test_bay_rendering.gd` | Integration | Instantiate `GameClient`, verify bay sprites at correct positions, environment tilemap painted, camera centered, peek bays muted |
| `tests/perf/test_heat_grid_cell_count.gd` | Perf | 55 cells should be ~6× faster than 301; add perf assertion that catches regression to old cell count |
| `tests/scenario/test_bay_scale_scenarios.gd` | Scenario | Re-run existing scenarios against new grid — cat seeks warmth, ferret drags can — with updated expected coordinate ranges and a determinism snapshot |
| `tests/scenario/test_plant_narrative.gd` | Scenario | Robot log entries fire on plant spawn and despawn with the exact voice from Section 5 |

### Over-tested — removed from Section 5 of the original draft

`test_environment_tilemap_scene.gd` (scene test) is redundant with `test_bay_rendering.gd` (integration). Folded into the integration test.

### Visual smoke automation (per Kibble)

Partially automated via headless render:

```bash
# New script: script/checks/visual_smoke
/Applications/Godot.app/Contents/MacOS/godot --headless --render-thread main \
    --path . --script script/render_snapshot.gd --output tests/snapshots/visual/bay0_centered.png
```

The snapshot script loads `main.tscn`, advances one physics frame, dumps the viewport to PNG. CI diffs pixel-exact against `tests/snapshots/visual/golden/bay0_centered.png`. Golden regeneration is a manual opt-in (`script/regen_visual_goldens`) so accidents are hard.

Scoped narrowly: one frame, one resolution, exact match. Don't try to diff animations. Don't try to diff during transitions.

### Accessibility smoke tests (per Pebble)

Add to the visual smoke:
- Grayscale mode render — verify placement validity, animal status, and heat overlay are still distinguishable without color
- Reduce-motion mode render — verify the shimmer animations are replaced by static equivalents per `input-design.md`

Both land as additional PNG diffs in CI.

### Audit checklist

The grep commands from Section 4 produce a list file. Each hit is a checklist item in the implementation plan. The audit runs BEFORE any code changes — we know the scope before we start editing.

### Stamp re-verification

Per `.claude/rules/llm-test-verification.md`: every test file that changes (new or existing) goes through full Phase 1–5 verification and gets re-stamped. Rough estimate: 30+ tests need re-stamping. The plan calls this out explicitly — "do not batch-stamp without re-running the verification cycle."

---

## Section 8 — Implementation order

The plan for executing this spec lands in `docs/superpowers/plans/2026-04-10-art-scale-and-tilemap.md` (written by the `superpowers:writing-plans` skill after this spec is approved).

**CI note:** Steps 2–6 will leave the build red — constants change ripples through many systems. The branch is NOT mergeable until step 11. Plan must make this explicit so nobody panics.

1. **Test audit** — run all grep commands from Section 4, produce checklist.
2. **Update `constants.gd`** — new values + new PU constants + helper functions. Single commit. Build will go red.
3. **Fix compile errors** cascading from the constant change. Commit per subsystem (heat_grid, nav_graph, desire_resolver, placement UI, etc.).
4. **Fix failing unit tests** one file at a time, red-green-refactor, re-stamp each.
5. **Build `tcp_environment.tres`** in Godot editor. Commit as a resource file.
6. **Write `engine/environment/tile_painter.gd`** RefCounted + `nodes/environment_tilemap.tscn` vanilla node. Unit tests for painter.
7. **Write `engine/growth/plant_growth_system.gd`** + `nodes/dynamic_plants.gd` + `cat_presence` tracking hook + robot log event emission.
8. **Rewrite `game_client.gd` rendering code** — delete floor builder, add bay builder, tilemap wiring, update starter objects via `rack_slot_to_pu()`.
9. **Update `art-direction.md`** and `asset-pipeline.md` to match new numbers. Restructure asset-pipeline.md tables per Bento's format. Update CLAUDE.md's layout description to reference peeks instead of half-racks.
10. **Credit new art assets** in `../game_assets/Credits.md`.
11. **Visual smoke test** — run the game, verify mockup match. Regenerate goldens if needed.
12. **Fix scenario tests** that fail against new coordinates. Re-stamp.
13. **Accessibility smoke tests** — grayscale + reduce-motion goldens.
14. **Delete dead code** — `_FLOOR_REGION`, `_build_floor()`, `_TILESET_ATLAS` const, `_floor_tex` field.
15. **Merge gate** — all tests green, visual goldens match, audit checklist fully addressed.

---

## Open questions (documented, not blocking)

1. **Wall height vs. mockup.** The mockup may show slightly taller or shorter wall above the racks than the 192px assigned. Visual verification finds the truth; tuning, not architecture.
2. **Focus halo for accessibility.** Pebble requires a keyboard/controller focus halo exceeding slot bounds. This spec commits to building it but doesn't specify the exact rendering — color, thickness, animation. Follow-up when implementation starts.
3. **Status icon placement at new scale.** Pebble requires status shape icons to move from the per-slot strip (no room) to the inspect tooltip. Tooltip layout is outside this spec's scope; input-design.md gets updated separately.
4. **Heat overlay shimmer per slot vs per rack column.** At 8px slot height, per-cell shimmer has ~2 pixels to work with. Pebble recommends full-rack shimmer column. Implementation detail — defer to the visual smoke phase.
5. **Follow-up: shader-based palette interpolation** for per-slot warmth tint. The downgrade in this spec is intentional; a follow-up spec restores it via a shader pass.
6. **Follow-up: dynamic rack decor alpha** tied to ongoing warmth rather than a one-time ramp. Ties to the same shader pass.
7. **Follow-up: half-rack-style standalone rack bays** using `rack_single_idle_strip1.png` — currently reserved but unused. Mod extension surface.
8. **Follow-up: multi-bay simulation.** Bays -1 and 1 are visually-only in this spec. Extending simulation (cats, heat, AI) to more bays is its own spec.

---

## Related rules

- `.claude/rules/art-direction.md` — grid constants, pixel scale. Updated by this spec. See Visual Regression Ledger.
- `.claude/rules/asset-pipeline.md` — asset directory structure, naming. Restructured by this spec.
- `.claude/rules/design-philosophy.md` — Pure Core, config-not-code, change detection. This spec's plant system and tilemap architecture comply.
- `.claude/rules/viewport-lod.md` — zone model, heat propagation. Heat cell count changes; zone logic unchanged.
- `.claude/rules/tick-architecture.md` — 10 Hz tick, scatter pattern. Plant system uses change detection, not per-tick scans.
- `.claude/rules/animal-ai.md` — desire resolver. Uses constants via helpers; no change beyond propagation.
- `.claude/rules/narrative.md` — reclamation aesthetic, robot voice. Section 5 narrative hooks are required per Parcel.
- `.claude/rules/core-loop.md` — purr-powered core loop. Plants are HUM-brownout-resistant per Section 5.
- `.claude/rules/input-design.md` — accessibility commitments. Pebble's requirements land in open question #2 and #3.
- `.claude/rules/llm-test-verification.md` — test stamp discipline. Full cycle required per Section 7.
- `docs/superpowers/specs/2026-04-10-mod-extraction-design.md` — sibling spec. Interface agreement in Section 6.
