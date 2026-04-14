---
paths:
  - "mods/tcp_base/**"
  - "**/*.png"
  - "**/*.ogg"
---

# TCP Asset Pipeline — Bento's Spec

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

### Tilesets

`tcp_environment.tres` -- Godot TileSet resource pointing at `tcp_tileset01.png`. Hand-written text resource. Tile cell positions documented in `tcp_tileset01.md`. `TilePainter` (`engine/environment/tile_painter.gd`) references cells by `Vector2i(col, row)`.

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
