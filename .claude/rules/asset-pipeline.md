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
│   │   ├── server/       # server_2u_off.png, server_2u_on.png
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
├── infrastructure/       # server_2u.json, pdu.json, cooling_pipe.json, gerbil_tube.json
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

### Must-Have Sprites (~42 assets)

| Asset | Frames | Size | Notes |
|---|---|---|---|
| **Cats (x3 variants: white, orange, grey)** | | | |
| cat_{variant}_idle | 4 | 32x32 | Loaf + tail flick + slow blink + stare |
| cat_{variant}_walk | 6 | 32x32 | Walk cycle |
| cat_{variant}_sleep | 2 | 32x32 | Breathing loop |
| cat_{variant}_eat | 3 | 32x32 | Head down, chewing |
| **Ferrets (x2 variants: sable, albino)** | | | Albino = palette swap |
| ferret_{variant}_idle | 3 | 32x16 | Sniffing, alert, speed bump |
| ferret_{variant}_walk | 6 | 32x16 | Low slinky walk |
| ferret_{variant}_drag | 4 | 32x16 | Dragging tuna can |
| ferret_{variant}_wardance | 6 | 32x32 | Arched back, sideways hop |
| ferret_{variant}_deadsleep | 1 | 32x16 | Completely limp. Single frame. |
| **Objects** | | | |
| server_2u_off | 1 | 64x16 | Dark, no LEDs |
| server_2u_on | 2 | 64x16 | LED blink cycle |
| box_cardboard_new | 1 | 32x32 | Clean box |
| pile_clothes | 2 | 48x24 | Full + flattened |
| tuna_can_sealed | 1 | 12x10 | |
| tuna_can_open | 1 | 12x10 | |
| furball | 1 | 8x8 | |
| feather | 1 | 16x16 | |
| fan_desk | 2 | 16x16 | Blade rotation |
| pipe_cooling_h/v | 1 each | 64x8 / 8x64 | |
| pipe_condensation | 3 | 8x16 | Droplet forming + falling |
| **Robot Arm** | | | |
| arm_base | 1 | 32x32 | |
| arm_segment | 1 | 8x48 | Reusable limb piece |
| arm_claw_open / closed | 1 each | 16x16 | |
| **HUD** | | | |
| drawer_frame | 1 | 192x48 | |
| drawer_{type}_bg (x4) | 1 each | 192x48 | |
| drawer_paw_poke | 3 | 32x16 | Iconic kitten paw |
| bar_segment + bar_icons | 1 + 6 | various | |
| rack_frame | 1 | 96x672 | 42U tall |
| rack_slot_highlight / deny | 1 each | 96x16 | |

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
