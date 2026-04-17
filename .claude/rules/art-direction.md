---
paths:
  - "**/*.png"
  - "**/*.tscn"
  - "sprites/**"
---

# TCP Art Direction — Smudge's Spec

## 1. Pixel Resolution and Base Grid

**Target viewport:** 224×128 internal (14×8 tiles, 1.75:1), scaled to any display via Godot `canvas_items` stretch mode. 8× → 1792×1024. Fullscreen by default.

**Real-world-proportioned grid.** 1 pixel ≈ 0.25 inches. Sprites render at native 1×, no scaling.

**Base unit: 8px per rack unit (1U).** A 10U rack body is 80px tall. Rack interior width is **23px**. 5 playable racks rendered as one `rack_5set_idle_strip1.png` sprite (186px wide). Bay stride 226px with ~20px of the neighboring bay visible at each viewport edge.

### Grid constants (authoritative values in `engine/core/constants.gd`)

| Constant | Value | Meaning |
|---|---|---|
| `SLOT_HEIGHT_PX` | 8 | One rack unit (1U) in display pixels |
| `SLOTS_PER_RACK` | 10 | Visible slots per rack |
| `RACK_WIDTH_PX` | 23 | Interior width of a single rack (one server fills it) |
| `RACK_STRIDE_PX` | 31 | Rack center-to-center (interior + shared wall) |
| `RACK_GAP_PX` | 8 | Wall between adjacent racks |
| `RACK_COUNT` | 5 | Playable racks per bay |
| `LEFTMOST_RACK_OFFSET_PX` | 25 | Shelf-detail padding at left of 5-set sprite |
| `BAY_WIDTH_PX` | 186 | Width of `rack_5set` sprite |
| `BAY_STRIDE_PX` | 226 | Bay center-to-center |
| `BAY_PEEK_PX` | 20 | Visible slice of each neighboring bay |
| `FLOOR_HEIGHT_PX` | 16 | One tile row (animals walk at `FLOOR_Y = 112`) |

Every constant has a `_PU` twin (multiplied by `POSITION_SCALE = 100`) for the integer-core math. Downstream callers never compute `rack * 31 + 25` by hand — use the helpers in `constants.gd` (`rack_slot_to_pu`, `pu_to_bay_rack_slot`, `rack_slot_to_world`, `world_to_rack_slot`, `bay_center`). See CLAUDE.md → "Coordinate system — use canonical helpers."

### Layout (8 tile rows, y-down)

```
Row 0 (y=0-15):   ceiling
Rows 1-5 (y=16-95): wall fill — rack sprite overlays most of this starting at y=16
Row 6 (y=96-111): baseboard (behind rack bottom frame)
Row 7 (y=112-127): floor surface — animals walk at FLOOR_Y = 112
```

Rack sprite top-anchors at `RACK_TOP_Y = 16`. The sprite has 8px transparent padding above the visible rack + 4px visible frame, so `RACK_SLOT0_Y = 28` (top of slot 0 interior). Neighboring bay peeks render identically to the active bay (no desaturation) — abandonment contrast is conveyed by tile painting, not modulation.

**Cat silhouette at this scale:** a sitting cat is 40×40px native — about 5U tall. Cats are bigger than servers, which is physically accurate. Cats visually overflow rack interior horizontally (~8px each side) and span multiple slots vertically; they float in front of the rack plane in z-order.

**Floor strip:** 16px tall floor row at the bottom of the viewport. Ferrets operate here, tuna cans sit here, and the robot arm station lives here.

---

## 2. Color Palette

Six colors define the cold datacenter. Six define the warm, thriving state. The room interpolates between them as aggregate animal happiness rises.

### Cold Datacenter (starting state)

| Name | Hex | Role |
|---|---|---|
| **Slate Void** | `#1A1E2E` | Deepest shadows, empty rack interiors, the abyss behind servers |
| **Cable Gray** | `#3B4157` | Primary surface color: rack frames, floor tiles, structural metal |
| **Dust Blue** | `#5B6B8A` | Secondary surfaces: server faces, pipe casings, ambient fill |
| **Indicator Teal** | `#4A9B9B` | Active electronics: LEDs, status lights, the robot arm's scanning beam |
| **Warning Amber** | `#C4A24E` | Hazard paint, the robot arm's caution stripe, sparse warm accent |
| **Breath White** | `#D4DAE8` | Condensation, text, highlights on metal edges, kitten fur |

### Warm Datacenter (thriving state)

| Name | Hex | Role |
|---|---|---|
| **Den Brown** | `#2E2018` | Deepest shadows shift warm — no more blue in the darkness |
| **Worn Wood** | `#6B5240` | Surfaces pick up warmth from fur, cardboard scraps, nesting materials |
| **Sunpatch Gold** | `#C49548` | The dominant mid-tone: warm light pooling where animals gather |
| **Purr Orange** | `#D4763A` | Accent for peak happiness areas, glowing status indicators, heat halos |
| **Moss Green** | `#5B8B4A` | Plants growing in cracks, nature reclaiming, life spreading |
| **Cream** | `#F0E6D0` | Highlights shift from cold white to warm cream, fur tones, soft glow |

### Interpolation model

Per-slot palette interpolation (6-color cold → warm palette shift, driven by a warmth float per slot) is **deferred**. At the 8px-per-slot scale it requires a shader pass, not per-cell palette swapping. Current build renders the cold palette globally. A follow-up spec restores per-slot tint via a shader.

**Rack decor overlay** (`rack_5set_decor_strip1.png`) is a single transparent vine layer drawn over the rack sprite. Alpha starts at 0 and ramps to 0.7 the first time a reclamation plant spawns in bay 0 — preserving the "I grew these" feeling. Target alpha lives in `config/balance/rendering.jsonc` (`rack_decor_final_alpha`, `rack_decor_ramp_duration_ticks`).

Plants (Moss Green, via the reclamation growth system — see `growth-system.md`) appear on servers where cats have tended long enough. Rendered as 8×8 cropped sprites from the environment tileset, offset onto the top edge of the host server.

The robot arm always renders in the cold palette. It is metal and electricity — that contrast makes the organic warmth around it more visible.

---

## 3. The Five Cat Models

Five cats, distinguishable at 24px wide in a pile. Color alone is not enough — silhouette must do the work.

| Model | Silhouette | Key Feature | At Small Scale |
|---|---|---|---|
| **Round Floof** | Wide, circular body. Small rounded ears almost lost in fur. Enormous bushy tail curls over back like a question mark. | The tail. Always visible, even in a pile — sticks up and curls. | A circle with a curved line rising from it. |
| **Long Lean** | Narrow, elongated body. Tall pointed ears with visible inner triangles. Thin whip tail in a gentle S-curve. | The ears. Tallest ear silhouette — two sharp triangles that read even at min zoom. | A thin oval with two spikes on top. |
| **Tuxedo Chonk** | Stocky, rectangular body. Medium rounded ears. Medium-length tail. High-contrast two-tone pattern (dark body, light chest/paws). | The contrast pattern. Only cat with a strong two-tone split, readable even as a 6px blob. | A dark rectangle with a light front. |
| **Tufted Ear** | Medium build, slightly angular. Distinctive ear tufts (lynx tips) extending the ear silhouette. Tail is medium-bushy with dark tip. | The ear tufts. Add 2-3px of height to ear silhouette. | Medium oval with spiky ear extensions. |
| **Stubby** | Compact, low-to-ground. Very short rounded ears close to head. Bob tail — just a puff. Widest stance. | The bob tail (its absence). Lowest overall silhouette. | A low wide lump with no tail line. |

**In a pile:** Distinguishing features are the parts that stick out: Round Floof's curled tail, Long Lean's tall ears, Tuxedo Chonk's light chest, Tufted Ear's lynx tips, Stubby's low profile.

**Kittens:** Proportionally scaled — bigger head-to-body ratio, rounder features, stubbier limbs. 60% height of adults. Distinguishing features are exaggerated, not reduced.

---

## 4. Zoom Levels

**Z0 only in the shipped prototype.** The viewport renders at 224×128 internal and scales to the display via `canvas_items` stretch mode. Z1 drawer view and Z2 overview are deferred follow-up specs.

**LOD strategy when Z1/Z2 return: separate sprites, not scale-and-filter.** Pixel art does not survive arbitrary scaling.
- **Z0 sprites:** 8px per rack unit. Full detail. This is where the art budget goes.
- **Z1 sprites (deferred):** drawer view, 2× zoom, redrawn with added expression detail.
- **Z2 sprites (deferred):** overview, simplified silhouettes 2-3 colors max.

Transitions (when added): 200ms crossfade between sprite sets. No interpolation frames.

---

## 5. Lighting Model

No windows in the prototype. All light is artificial. Light is pure information.

**Three light layers, composited additively:**

**Layer 1 — Ambient base.** Dim cool wash. Cold state: Dust Blue at ~15% intensity. Warm state: shifts toward Sunpatch Gold, brightens to ~25%. The room never gets bright — stays cozy-dim.

**Layer 2 — Point lights (infrastructure).** Each powered server emits a small cone of Indicator Teal light (2-3U radius). Status LEDs are single-pixel points. Robot arm has a focused Warning Amber work light. Always cold palette — mechanical light.

**Layer 3 — Warmth halos (animal-driven).** Each animal above 0.5 satisfaction emits a subtle warm glow (Purr Orange at 8-12% intensity, 2U radius). Single cat's halo barely visible. Three piled together create a noticeable warm pool. Ten in adjacent slots make the section visibly warmer. **This is the primary visual reward loop.** Halos stack additively, cap at 40% intensity.

**Focus:** When a rack slot is selected, its point light brightens 20% and everything outside 5U dims 10%. Layer 1 only — warmth halos remain visible in periphery.

**Robot arm scanning beam:** One bright, saturated Indicator Teal line. Visually distinct from everything else.

---

## 6. Status Bar Visual Language

**Empty slots have no status bars.** An unoccupied rack unit is a dark rectangle.

When an animal occupies a slot or an object is placed: a **2px vertical strip** appears on the left edge — a single color communicating aggregate state:

| Color | Meaning |
|---|---|
| No strip | Empty |
| Dust Blue | Infrastructure only, no animal |
| Moss Green | All needs met, thriving |
| Sunpatch Gold | Most needs met, one or two below optimal |
| Warning Amber | Significant unmet need |
| Purr Orange (pulsing) | Critical unmet need |

**On hover (Z0):** Strip expands to 6px sidebar showing individual need bars. Appears and disappears with hover.

**On click / Z1:** Full status panel with labeled bars, numerical values, robot interpretation text.

**Rack aggregate:** 4px bar at top of each rack column — average satisfaction as a color. At Z2, this is the primary status indicator.

**Animal posture stages (three tiers):**
- **Settled:** Body low, eyes half-lidded, slow blink, faint warmth halo. Reads as "content."
- **Alert:** Ears back, body lifts slightly, tail tip twitches. Reads as "something's off" — before any meter moves.
- **Relocating:** Stands, moves purposefully. Disruption happened.

---

## 7. Visual Priority Hierarchy (z-order, back to front)

Shipped z-order inside `GameClient.World`:

| z | Layer | Contents |
|---|---|---|
| 0 | **EnvironmentTileMap** | Walls, ceiling, cables, baseboard, ground — painted by `TilePainter` |
| 1 | **RackRow** | `rack_5set` sprite per bay |
| 2 | **RackDecor** | Vine overlay (`rack_5set_decor_strip1.png`), alpha ramps on first plant spawn |
| 3 | **PlacedObjects / DynamicPlants** | Servers, boxes, tuna cans; plant sprites attached as children of their host servers |
| 4 | **Animals** | Cats, ferrets — overflow rack interiors, float in front of the rack plane |
| 5 | **StatusStrips** | 2px per-slot strips when focused |
| 6 | **FocusHalo** | Keyboard/controller focus ring |
| 7 | **HeatOverlay** | Debug/diagnostic heat view |
| 10 | **HUD** | CanvasLayer, always on top |
| 100 | **RuGridOverlay** | Dev-only grid debug |

**Bay rendering:** each bay is a single `Sprite2D` placed at `(bay_index * BAY_STRIDE_PX, RACK_TOP_Y)` with `rack_5set_idle_strip1.png` as its texture. One sprite per bay is the single source of truth — never split into tiles (fragile when the artist updates the rack art).

**High-density stacking:** 4+ animals in the same column stack with 2-4px vertical jitter and 1-2px lateral offset. Distinguishing features (ears, tails) get +1 z within their sprite layers.

**Robot arm** renders above placed objects but below HUD — floor entity, interacts with tuna cans. See `objects.md` for the arm component and `food-system.md` for its open-can loop.

---

## 8. Robot Arm Visual Design

**Silhouette:** Ceiling-mounted industrial arm with three segments: vertical rail, upper arm, forearm + two-pronged gripper. Three joints: rail slide, shoulder, elbow, plus gripper open/close. Reference: inverted Pixar lamp.

**Scale:** Forearm ~4U (96px) fully extended. Gripper 1U wide (24px). Retracted: only rail mount and shoulder visible (~2U).

**Material:** Cold palette permanently. Cable Gray structure, Dust Blue joint housings, Breath White gripper prongs. Faded yellow hazard stripes (chipped, worn).

**Indicator lights:** Three single-pixel LEDs on gripper housing:
- **Power:** Indicator Teal, steady
- **Status:** Teal (idle), Sunpatch Gold (processing), Purr Orange (confused)
- **Scan:** Teal, blinks when scanning

**Personality through body language:**

| State | Pose | Movement | What It Communicates |
|---|---|---|---|
| **Idle** | Retracted, gripper slightly open, 1px sway | Slow, breathing-like | "I'm here. I'm watching." |
| **Curious** | Extends toward entity, gripper tilts (head-tilt) | Smooth extension, sudden tilt, hold | "What is this?" |
| **Working** | Fully extended, gripper closes with purpose | Confident, efficient | Can-opening sequence. |
| **Confused** | Extends, tilts one way then other, gripper opens/closes without grabbing | Jerky, oscillating | "This is not a standard component." |
| **Satisfied** | Brief upward bounce after task, then retracts | Quick nod-like bounce | "Job done." |
| **Following cursor** | Tracks cursor with 200ms delay | Lagging, slightly imprecise | Physical object with mass and intention. |

**The 200ms cursor-follow delay is non-negotiable.** Instant tracking = UI element. Lagging = physical object.

**Animation:** Inverse kinematics visually. Gripper moves to target, segments follow. 2-3 intermediate frames. Joint rotation as sprite-swap (4 angles per joint).

---

## Implementation Priority

1. Rack structure and grid
2. Five cat models at Z0
3. Robot arm at Z0 (idle + working)
4. Cold palette applied
5. Warmth halos and palette interpolation
6. Status bar summary strips
7. Ferret models at Z0
8. Z1 (drawer view) sprites
9. Z2 (overview) sprites — can use placeholder dots initially
