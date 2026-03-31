---
paths:
  - "**/*.png"
  - "**/*.tscn"
  - "sprites/**"
---

# TCP Art Direction — Smudge's Spec

## 1. Pixel Resolution and Base Grid

**Target viewport:** 640×360 internal (16:9), scaled to any display via Godot `canvas_items` stretch mode. 3x→1920×1080, 2x→1280×720, 4x→2560×1440. Tablet and phone friendly.

**Real-world-proportioned grid.** 1 pixel ≈ 0.25 inches. Cat sprites render at native 1x — no scaling artifacts.

**Base unit: 7px per rack unit.** 1U = 1.75 inches real = 7px. A 4U server is 28×76px. A 42U rack is 294px tall. Rack width is **76px** (19" real). 7 playable racks + 2 decorative half-racks = 7×80 + 2×40 = **640px** — exactly fills the viewport width.

**Layout:**
```
[half|  1  |  2  |  3  |  4  |  5  |  6  |  7  |half]
 40px  80px  80px  80px  80px  80px  80px  80px  40px = 640px
```

Half-racks are decorative (no placement grid). They imply the datacenter continues beyond the viewport. May have ambient details: dangling cables, moss, a kitten paw reaching from offscreen.

**Cat silhouette at this scale:** A sitting cat is 40×40px native — about 5.7U tall. Cats are bigger than servers, which is physically accurate. At 40px, a cat silhouette has room for body shape, ear shape, tail position, and color pattern — highly readable. Five distinct cat models are visually distinguishable.

**Floor strip:** ~40px tall, running the full width below the racks. This is where ferrets operate, tuna cans sit, and the robot arm station lives.

**Sub-grid for interior (drawer) view:** When a rack slot is clicked and the drawer pulls out, the interior renders at **2x zoom** (14px per U), giving detailed visibility of animals and equipment inside the slot.

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

Each rack slot maintains a **warmth float (0.0 to 1.0)** driven by heat propagation and animal presence. The palette for that slot interpolates between cold and warm versions per-channel. Non-linear: the first 20% of warmth shifts colors noticeably (the room "wakes up" fast), and the last 20% is subtle (diminishing returns).

Plants (Moss Green) only appear above 0.6 warmth. They start as single-pixel dots in tile cracks and grow to 4-8px clusters.

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

Three zoom levels. Not four, not five.

| Level | Name | Scale | What You See | When |
|---|---|---|---|---|
| **Z0** | **Rack View** (default) | 1x (24px/U) | Full rack height, 5 racks wide. Individual animals as silhouettes. Can identify species and cat model. | 90% of play. |
| **Z1** | **Drawer View** | 2x (48px/U) | Interior of one rack slot. Individual expressions readable. Kittens distinguishable. Status bar detail. | Checking on a specific spot. |
| **Z2** | **Overview** | 0.5x (12px/U) | All 5 racks plus neighbors. Animals as colored dots with species-shape coding. Heat halo as color wash. Individual identity lost. | Assessing the whole datacenter. |

**LOD strategy: separate sprites, not scale-and-filter.** Pixel art does not survive arbitrary scaling.
- **Z0 sprites:** Full detail within 24px grid. This is where the art budget goes.
- **Z1 sprites:** 2x versions with added detail (expressions, fur texture). Redrawn at 48px, not upscaled.
- **Z2 sprites:** Simplified 12px. 2-3 colors max. Species silhouette only. Static or two-frame idle.

**Transition:** 200ms crossfade between sprite sets. No interpolation frames.

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

| Priority | Layer | Contents |
|---|---|---|
| 0 | **Rack structure** | Frames, empty slots, back panels, cable runs |
| 1 | **Infrastructure** | Servers, pipes, PDUs, switches, tubes |
| 2 | **Passive objects** | Boxes, clothes pile, scraps, clustered furballs |
| 3 | **Warmth halos** | Translucent overlay, tints but doesn't occlude |
| 4 | **Active objects** | Tuna cans being dragged, furballs in motion, feather |
| 5 | **Plants and moss** | Growing vegetation, translucent edges |
| 6 | **Animals (ambient)** | Sleeping, loafing, grooming |
| 7 | **Animals (active)** | Moving, playing, interacting |
| 8 | **Robot arm** | Always visible, never occluded by game objects |
| 9 | **Status indicators** | Summary strips, hover panels, semitransparent |
| 10 | **HUD and drawers** | UI layer, always on top |

**High-density stacking:** 4+ animals in same column stack with 2-4px vertical jitter and 1-2px lateral offset. Distinguishing features (ears, tails) get +1 z within their sprite layers.

**Furballs:** Lowest-priority visible entity. Below 3 in a cluster: not rendered at Z0 (cluster sprites only). At Z2: invisible entirely.

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
