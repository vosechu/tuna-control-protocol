---
paths:
  - "mods/*/sprites/**"
  - "mods/*/sounds/**"
  - "**/*.png"
  - "**/*.ogg"
  - "**/*.wav"
---

# TCP Asset Pipeline

> Maintained alongside the `game-asset-creator` (Bento) agent. Dispatch that agent for review before substantive changes.

> **Use `/load-game-asset-creator`** when about to add a new asset directory, naming convention, or content layout and you want Bento's principles on how art and code share structure.
> **Spawn the `game-asset-creator` agent** when you have a content structure or naming/layout convention to review.

---

## 0. Design Principles

The philosophical foundations behind the mechanical rules below. They live here (rather than CLAUDE.md or `design-philosophy.md`) because they're specifically about the *bridge* between art and code.

1. **Config over code.** Every number in every formula — heat output per server, kitten gestation time, treat dispenser queue size, desire weight ranges — should be in a JSON file that can be overridden. This is a CLAUDE.md fundamental.
2. **Naming conventions are load-bearing.** File names encode metadata (`cat_white_idle_01.png`, `server_1u_powered_on.png`, `treat_tuna_seared.png`). Parseable names mean fewer manifest files and faster onboarding — "can a new contributor find the cat idle animation in under 10 seconds?" is a real test.
3. **Species as data, not code.** A new animal type should be a new JSON definition (needs, contributions, size, animations, sounds), not a new script. The animal behavior system reads these definitions. Adding a guinea pig shouldn't require a programmer.
4. **Version everything.** Save files include a schema version. Config files include a format version. Asset packs include a compatibility version. Migration paths exist between versions.
5. **Debug-friendly saves.** Game state exports to human-readable format (JSON or similar). A developer should be able to open a save file and understand what happened. This means save files include not just state but a brief history log.
6. **Hierarchy follows function, not source.** Files belonging to the same in-game thing live together (`sprites/cat/`, `sounds/cat/`), not segregated by file type. Folder boundaries match conceptual boundaries.
7. **Implicit dependencies are bugs.** If asset A requires asset B to exist, that dependency is declared (in `mod.json`, in a recipe field, or in the directory structure), not assumed.
8. **Platform-agnostic by construction.** Assets target the internal viewport (224×128), not specific output resolutions. Integer-only scaling. Palette + atlas conventions hold across desktop, web, console.

---

## Asset Directory Structure

All game content lives under `mods/tcp_base/` per the "base game is a mod" rule. Engine scenes (`.tscn`) live under `nodes/` since they are framework, not content.

```
mods/tcp_base/
├── sprites/
│   ├── cat/              # cat_white_idle.png, cat_orange_walk.png, etc.
│   ├── ferret/           # ferret_sable_idle.png, ferret_albino_drag.png, etc.
│   ├── infrastructure/
│   │   ├── server/       # server_1u_off.png, server_1u_on.png
│   │   ├── rack/         # rack_frame.png, rack_slot_empty.png, rack_slot_highlight.png
│   │   ├── cables/       # cable_ethernet_segment.png, cable_power_segment.png
│   │   └── pipes/        # pipe_cooling_horizontal.png, pipe_condensation_drop.png
│   ├── objects/          # box_cardboard_new.png, tuna_can_sealed.png, furball.png, etc.
│   ├── robot/            # arm_base.png, arm_segment_upper.png, arm_claw_open.png, etc.
│   ├── hud/              # drawer_frame.png, drawer_kitties_bg.png, bar_segment.png, etc.
│   ├── effects/          # heart_particle.png, zzz_particle.png, heat_shimmer.png, etc.
│   └── environment/      # floor_tile.png, wall_bg.png, moss_overlay.png
├── sounds/
│   ├── cat/              # cat_purr_loop.ogg, cat_meow_01.ogg, cat_mrrp.ogg, etc.
│   ├── ferret/           # ferret_dook_01.ogg, ferret_churr.ogg, etc.
│   ├── robot/            # arm_servo_move.ogg, arm_scan_beep.ogg, etc.
│   ├── infrastructure/   # server_fan_loop.ogg, cable_plug.ogg, pipe_drip.ogg
│   ├── objects/          # can_scrape_loop.ogg, can_open_chunk.ogg, box_shred.ogg, etc.
│   ├── ui/               # drawer_open.ogg, place_confirm.ogg, etc.
│   └── ambient/          # datacenter_hum_loop.ogg, room_tone_loop.ogg
├── species/              # cat.json, ferret.json
├── items/                # cardboard_box.json, tuna_can.json, comfy_pile.json
├── desires/              # hunger.json, warmth.json, social.json, comfort.json, curiosity.json
├── infrastructure/       # server_1u.json, pdu.json, cooling_pipe.json, gerbil_tube.json
├── behaviors/            # seek.json, consume.json, rest.json, play.json, wander.json, teach.json
├── config/               # balance.json, teaching.json, desire_thresholds.json, spawn_conditions.json
└── locale/               # en.json

nodes/                    # Engine scenes (framework, not content)
├── animal_node.tscn
├── infrastructure_node.tscn
├── robot_arm_node.tscn
├── hud/
└── camera/
```

### Naming Conventions

**Pattern:** `{type}_{variant}_{state}_{frame}.{ext}`

- All lowercase, underscores only, no spaces, no hyphens.
- `.ogg` for loops and music (compressed, streaming). `.wav` for short SFX (uncompressed, low latency). `.png` for all sprites.
- Sound variants use `_01`, `_02` suffixes for random selection pools.
- Config files named after the thing they configure, not the system that reads them.

### Audio Format & Import Standards

- **Format:** All WAVs must be 16-bit 48kHz. Normalize to -1 dBFS peak using `sox input.wav -b 16 -r 48000 output.wav gain -n -1`.
- **Import settings:** `.import` files must have `compress/mode=2` (QOA) and `edit/loop_mode=0`. Looping is handled in code via restart-on-finish, not via import settings.
- **Credits:** Every imported sound gets an entry in `../game_assets/Credits.md` with author name and source URL.
- **Archive:** Original files (pre-normalization) are kept in `../game_assets/`.
- **Tools:** `sox` (install via `brew install sox`) for normalization and format conversion.

### AI Sprite Generation (GPT Images 2.0)

Constraint-template workflow for generating new pixel-art sprites via GPT Images 2.0 lives at `../game_assets/gpt_templates/` (per-asset subfolders with `template_prefilled.png` + `prompt.md`). Full prompt skeleton, TCP palette reference, channel-selection guide (Codex vs ChatGPT web), and post-generation checklist at `../game_assets/gpt_pixel_template_PROMPT.md`. Generators: `scripts/make_gpt_pixel_template.py` (blank templates, single- or multi-row, `--native` mode) and `scripts/make_gpt_asset_templates.py` (pre-fills templates with frame 0 of existing sprites as a reference for GPT).

**Native-size + calibration-strip approach (default):** Templates are sized to match one of GPT's fixed output resolutions (2048×2048 for Codex / gpt-image-2, 1024-class for ChatGPT web UI / gpt-image-1) so GPT doesn't rescale at render time. Each logical sprite pixel is a uniform N×N block of real pixels (N=4–6 in 2K). A 24-real-pixel calibration strip at the top of every template holds three test patches (1-px checkerboard, resolution gauge, N-px checkerboard) that detect resampling and let the user reject degraded outputs before wasting review time.

**Known limitation (unmitigated):** GPT's diffusion model may still smooth across logical-pixel blocks even with the constraint template — the N-px checkerboard in the calibration strip is the specific reject filter for this. For tiny sprites (like 23×48 at N=3–4) expect multiple re-rolls; treat usable GPT output as *composition reference* and hand-pixel the final sprite when the calibration strip fails. Behavior at larger sprite sizes and with fresh 2K (Codex) output is still being validated.

---

## Asset Trackers

Living lists of what exists, what's needed, and what's placeholder:

- **Art/sprites:** [`docs/art-asset-tracker.md`](../../docs/art-asset-tracker.md)
- **Sound:** [`docs/sound-asset-tracker.md`](../../docs/sound-asset-tracker.md)

The lists below are the original prototype targets. The tracker docs above are the up-to-date working lists.

## Minimum Prototype Asset List

### Infrastructure Sprites

| Asset | Size | Frames | Notes |
|---|---|---|---|
| rack_single_idle_strip1 | 64x96 | 1 | Single rack frame |
| rack_5set_idle_strip1 | 186x96 | 1 | Five-rack bay (primary) |
| rack_single_decor_strip6 | 384x96 | 6 | Vine variants (reserved) |
| rack_5set_decor_strip1 | 186x96 | 1 | Vine overlay for 5-set |
| server01_static_strip1 | 23x8 | 1 | Server (static) |
| server01_idle_strip11 | 253x8 | 11 | Server (blink animation) |
| server02_static_strip1 | 23x8 | 1 | Server variant B (static) |
| server02_idle_strip7 | 161x8 | 7 | Server variant B (blink) |
| rack_slot_highlight | 23x8 | 1 | Placement highlight |
| rack_slot_deny | 23x8 | 1 | Invalid placement |
| rack_slot_empty | 23x8 | 1 | Empty slot indicator |

### Object Sprites (tcp_base)

| Asset | Size | Frames | Notes |
|---|---|---|---|
| box01_idle_strip1 | 32x16 | 1 | Small box (static) |
| box01_activated_strip8 | 256x16 | 8 | Small box (activation) |
| box02_idle_strip1 | 48x32 | 1 | Large box (static) |
| box02_activated_strip8 | 384x32 | 8 | Large box (activation) |
| pile_clothes | 48x24 | 1 | Comfort object |
| dustball01_idle_strip16 | 256x16 | 16 | Dust ball (idle) |
| dustball01_spin_strip8 | 128x16 | 8 | Dust ball (spin) |
| dustball02_idle_strip16 | 256x16 | 16 | Variant B |
| dustball02_spin_strip8 | 128x16 | 8 | Variant B |

Note: dust ball animation support deferred per spec. Sprites imported but render first frame only.

### Environment

| Asset | Size | Frames | Notes |
|---|---|---|---|
| tcp_tileset01 | 192x96 | -- | 16x16 tile atlas (12x6 grid) |

### TileSet + TilePainter architecture

The environment (walls, ceiling, cables, baseboard, floor, growth) is painted by a Godot `TileMap`, not stretched as a single atlas sprite. Three files cooperate:

```
mods/tcp_base/sprites/environment/
  tcp_tileset01.png              # the atlas
  tcp_environment.tres           # TileSet resource — registers non-transparent cells
  tcp_tileset01.md               # greppable cell map (col, row → purpose)
engine/environment/
  tile_painter.gd                # RefCounted helper that calls set_cell() on a TileMap
nodes/
  environment_tilemap.tscn       # vanilla TileMap node instance, no custom script
```

**TileSet resource (`tcp_environment.tres`):**
- Atlas size 192×96, tile size 16×16, 12 × 6 = 72 cells (transparent cells not registered).
- Authored by hand as a text resource. Regenerate by re-opening in the Godot editor if the artist ships a new atlas.

**Tile cell map:** single source of truth is `tcp_tileset01.md` — a greppable flat table of every cell, its atlas coordinate, and its semantic purpose (ceiling, wall, baseboard, substrate, surface overlay, cables A–E, plant variants). Whenever the atlas changes, update the markdown and `tile_painter.gd` constants in one commit.

**TilePainter contract:**

```gdscript
class_name TilePainter extends RefCounted
func _init(tilemap: Object, seed_value: int = 42) -> void
func paint_bay(bay_index: int) -> void   # paints ceiling, wall, baseboard, floor, cables for one bay
func clear_bay(bay_index: int) -> void   # clears every layer in bay_index's x-range
```

The painter uses three TileMap layers:

| Layer | Index | Contents |
|---|---|---|
| `_WALL_LAYER` | 0 | Ceiling row, wall fill, baseboard, substrate (bottom of every floor tile) |
| `_CABLE_LAYER` | 1 | Hanging cable decor (rows 0-1) — transparent gaps let wall show through |
| `_PLANT_LAYER` | 2 | Row-6 edge cap + row-7 grass/flower variants |

Floor tiles use a **two-layer paired theme**: substrate `(7,5)` on `_WALL_LAYER` row 7 always, then `_PLANT_LAYER` paints either (a) bare edge cap `(7,4)` on row 6 — ~85% of tiles — or (b) `(4,4)` small plants on row 6 paired with a row-3 grass/flower variant on row 7 — ~15% of tiles. Pairing keeps the edge cap consistent with the surface (bare-edge above bare-substrate, or plants-edge above grass-surface). The row-6 edge cap's 16 black pixels render at world y=111, producing the horizontal black line at the top of the floor.

The painter is a RefCounted helper, not a TileMap subclass. The TileMap node stays vanilla so a mockup tool or editor can paint cells without going through code. `TilePainter` is unit-testable by passing in any object with a `set_cell(layer, coords, source_id, atlas_coords)` method and a `get_layers_count()` / `add_layer()` pair — tests use a minimal stub, no scene tree required.

### Reclamation plant sprites

The growth system (see `growth-system.md`) attaches 8×8 plant sprites to servers as children. Source pixels are cropped from `tcp_tileset01.png` via `AtlasTexture.region`:

```gdscript
const REGIONS: Dictionary = {
    &"moss":    Rect2(96, 32, 8, 8),    # top-left quarter of env_leaves
    &"grass":   Rect2(112, 32, 8, 8),   # top-left of env_grass
    &"blossom": Rect2(128, 32, 8, 8),   # top-left of env_blossoms_orange
    &"flower":  Rect2(64, 32, 8, 8),    # top-left of env_flower_orange
}
```

No new sprite files — the plant variants are all sub-regions of the existing atlas. Local sprite offset `(3, -6)` places the plant on the top edge of the host server without occluding the status strip real estate on the server's left 2px.

### Mod-specific sprites (reference only)

Cat/ferret sprites in `mods/tcp_cats/sprites/` and `mods/tcp_ferrets/sprites/`. Tuna sprites in `mods/tcp_tuna/sprites/`. Do not add to tcp_base tables.

### Must-Have Sounds (~15 assets)

| Asset | Notes |
|---|---|
| cat_purr_loop.ogg | Core metric. Layerable. |
| cat_meow_01.ogg | Calling attention / unhappy |
| cat_mrrp.ogg | Mild annoyance / acknowledgment |
| ferret_dook_01.ogg | Happy excitement |
| arm_servo_move.ogg | Robot arm repositioning |
| arm_scan_beep.ogg | Scanning an animal |
| can_scrape_loop.ogg | Ferret dragging can |
| can_open_chunk.ogg | Robot arm opening can |
| server_fan_loop.ogg | Ambient per-server |
| cable_plug.ogg | Satisfying click |
| drawer_open.ogg / drawer_close.ogg | HUD interaction |
| place_confirm.ogg | Placement feedback |
| datacenter_hum_loop.ogg | Base ambient layer |

---

## Animation Frame Budget

**Target: 8 FPS playback** for hand-drawn animations. Procedural animation runs at display framerate.

### Hand-Drawn Frame Counts

| Behavior | Frames | FPS | Loop? |
|---|---|---|---|
| Idle (loaf/alert) | 4 | 4 | Yes |
| Walk | 6 | 8 | Yes |
| Sleep | 2 | 1 | Yes |
| Eat | 3 | 6 | Yes |
| Groom | 4 | 6 | Yes |
| Stretch | 3 | 4 | No (one-shot) |
| Knead | 3 | 4 | Yes |
| War dance (ferret) | 6 | 8 | Yes |
| Drag (ferret) | 4 | 6 | Yes |
| Dead sleep (ferret) | 1 | — | No (static) |

### Procedural Animation (zero hand-drawn frames)

Robot arm movement (Tween + IK), feather floating (sine wave + perturbation), furball rolling (sprite rotation), tail flick (Tween), head tracking (offset), drawer slide (Tween), heat shimmer (shader), condensation drip (Tween), LED blink (modulate alpha), dust motes + particles (GPUParticles2D), can dragging (follow with lag).

### Budget Summary

- ~130 hand-drawn frames total
- ~60% of visible motion from procedural animation, ~40% from hand-drawn
- Ferret albino = palette swap of sable (0 new drawing)
- Cat variants share silhouette/pose, differ in color/pattern layer
