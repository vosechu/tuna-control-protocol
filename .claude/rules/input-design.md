---
paths:
  - "nodes/**"
  - "**/*.tscn"
  - "config/input/**"
---

# TCP Input Design

> Maintained alongside the `accessibility-advocate` (Pebble) agent. Dispatch that agent for review before substantive changes.

## 1. Keyboard Shortcut Map

All shortcuts remappable via settings. Stored in `config/input/keyboard_map.json`.

### Global

| Key | Action |
|---|---|
| `1` `2` `3` `4` | Open/close Kitties / Cables / Infrastructure / Utilities drawer |
| `Shift+1-4` | Focus inside open drawer (select first item) |
| `Tab` | Toggle front/back (wiring) view |
| `Shift+Tab` | Toggle heat overlay |
| `+` / `-` / `0` | Zoom in / out / reset |
| `Home` / `End` | Pan to leftmost / rightmost rack |
| Arrow keys | Navigate between rack slots (L/R = racks, U/D = within rack) |
| `Enter` | Select highlighted slot / confirm action |
| `Escape` | Back out one level |
| `Space` | Interact with selected element (pick up, place, pet) |
| `I` or `F1` | Inspect selected element |
| `T` | Open/focus skill tower |
| `Q` | Quick-select last used item |
| `R` | Rotate held object |
| `Delete` | Return held object to drawer |
| `F` | Follow-cam: lock camera to selected animal |
| `M` | Mute/unmute |
| `?` or `F12` | Show shortcut overlay |

### Placement Mode

| Key | Action |
|---|---|
| Arrow keys | Move placement ghost |
| `Enter` | Place |
| `Escape` | Cancel |
| `Shift+Up/Down` | Adjust vertical offset for multi-U objects |

### Dev Toggles (shipped, not in player remap UI)

These are diagnostic overlays wired in `nodes/game_client.gd` and `nodes/animal_node.gd`. They predate the player-facing keymap above and are intentionally separate — they should not appear in the future remap UI.

| Key | Action |
|---|---|
| `G` | Toggle slot grid overlay (debug) |
| `N` | Toggle purr-note glyphs around purring entities (default off) |
| `L` | Toggle narrator log panel (default on) |
| `C` | Toggle per-animal data/sprite-position outlines (debug) |
| `Cmd/Ctrl+W` or `Cmd/Ctrl+Q` | Quit |

`N` defaults to **off** — the orbit-note glyphs are debug-flavored coverage feedback for HUM receivers (see `purr-power-ring0-design.md` §"Generation"); toggle on when you need to see which cats are within range. `L` hides the bottom-edge narrator panel for screenshots and uncluttered viewing.

---

## 2. Right-Click / Inspect Interaction

Right-click (mouse), `I` (keyboard), or `X` (controller) opens an inspect panel adjacent to the selected entity.

### Panel Content by Entity Type

**Cat/Kitten:** Name + robot ID, species/age, status (NOMINAL/ADVISORY/etc.), 5 desire bars with icons + fill + text label + trend arrow, current action, location, personality summary.

**Ferret:** Same structure, plus stash inventory and location, cans dragged count.

**Server:** Rack position, power/network state, fan speed, heat output + radius, nearby animals count.

**Tuna Can:** State (sealed/opened), last moved by, distance + direction arrow to robot arm.

**Empty Rack Slot:** Current heat, heat source, fits what size, cozy status, occupancy history.

**Robot Arm:** Status, activation radius, cans processed, device registry count, last log entry + scroll for full log.

### Panel Behavior

- Appears <100ms. Non-modal (game continues). Tracks its entity if it moves.
- Desire bars use FOUR channels: color + fill level + icon + text label.
- Status keywords also communicated by icon shape: circle (NOMINAL), triangle (ADVISORY), diamond (DEGRADED), octagon (CRITICAL).

---

## 3. Controller Flow (Xbox layout)

| Button | Action |
|---|---|
| Left Stick / D-Pad | Navigate racks (L/R) and slots (U/D). On floor: between floor objects. |
| A | Select / Confirm / Place / Open drawer |
| B | Back / Cancel / Close panel / Drop held object |
| X | Inspect selected element |
| Y | Quick action: pet (animal), toggle power (server), pick up (object) |
| LB / RB | Cycle drawers / racks / panel sections |
| LT / RT | Zoom out / in (analog) |
| L3 | Toggle heat overlay |
| R3 | Toggle follow-cam |
| Right Stick | Pan camera / scroll inspect panel |
| Start | Pause menu |
| Select | Shortcut reminder overlay |

### Key Flows

**Floor navigation:** D-Pad Down from lowest rack slot → floor level. L/R between floor objects in spatial order. D-Pad Up returns to rack.

**Skill tower:** LB+Y opens tower. D-Pad navigates nodes (follows link paths). A places cat. B closes.

**Wiring view:** *Not implemented — cable subsystem is parked (see banner on `hum-cable-system.md`).* Target design: Tab (keyboard) or LB+RB (controller) toggles wiring mode. Click a HUM to start a fresh cable, or click an existing cable endpoint to **pick it up**. While a cable is in hand, the tip follows the cursor. Click a valid HUM-powered device to connect; the cable replaces any previous source atomically (one disconnect + one connect signal in the same tick). X (keyboard) / Y (controller) **deletes** the held cable. Escape / B **cancels** and retracts the cable to its original HUM. If the original HUM vanished mid-drag, the cable silently drops rather than stranding the cursor. Ability to disconnect without picking up is gone: disconnect is always mediated through a pickup.

**Drawer items:** RB/LB cycles drawers (opens on focus). Left Stick navigates items inside. A picks up → placement mode. B cancels.

**Rumble:** Placement confirmation (short pulse), animal purring (gentle continuous), wire connection (click pulse), inspect open (soft tap). All disableable.

---

## 4. Hover Tooltip Spec

Appear on mouse-over (or on focus for keyboard/controller). <100ms target. Max 2 lines, 240px wide. Same info available in full via inspect panel.

**Rack slot (occupied):** `[Icon] "Marmalade" - Loafing` / `Warmth: Cozy | IOPS: 847`

**Rack slot (empty):** `Rack 2, Slot 14 - Empty` / `Heat: 2.1 (warm) | Fits: 1U`

**Animal:** `[Species icon] "Pixel" (Kitten)` / `Status: ADVISORY | Restless`

**Server:** `Server 2A [2U]` / `Power: On | Heat: 4.2 units`

**Drawer tab (closed):** `Kitties (1) | Press 1`

Tooltips announced by screen readers. High-contrast (4.5:1 minimum). Font size follows global scaling. On touch: long-press (300ms).

---

## 5. Color-Independent Visual Indicators

Every color-based indicator has a mandatory secondary channel. Game should be playable in grayscale. Verified by grayscale debug mode.

### Heat

| Color indicator | Secondary channel |
|---|---|
| Red heat vignette | Animated shimmer/wave lines (speed = intensity). Cold areas perfectly still. |
| Heat status bar fill (red→blue) | Fill pattern: warm = solid, cool = hatched, cold = dotted. Plus thermometer icon. |
| Cross-rack heat spillover | Animated directional arrows, pulse rate = intensity. |

### Placement

| Color indicator | Secondary channel |
|---|---|
| Green = valid | Solid 2px outline + checkmark icon + gentle 1Hz pulse |
| Red = invalid | Dashed 2px outline + X icon + static (no pulse) |
| White = browsing | Dotted 1px outline + no icon |

### Animal Status

| Color indicator | Secondary channel |
|---|---|
| Green tint (content) | Circle icon (NOMINAL). Steady breathing animation. |
| Amber shift (uncomfortable) | Triangle icon (ADVISORY). Occasional fidget. |
| Red shift (unhappy) | Diamond icon (DEGRADED). Pacing, quick head turns. |

### Desire Bars (Inspect Panel)

Five levels with independent color, fill pattern, icon shape, and text: Thriving (solid/filled circle), Content (solid/three-quarter), Neutral (hatched/half), Wanting (sparse hatch/quarter), Deprived (dotted/empty circle).

### Wiring View

Power cables: thick 3px + zigzag pattern. Ethernet: thin 1.5px + dash pattern. Disconnected ports: empty circle outline + dotted leader line.

### Notes

- All secondary indicators ON by default (not an accessibility toggle — part of the visual language).
- "High contrast" setting: +50% outline thickness, icon size, animation amplitude.
- "Reduce motion" setting: animations → static equivalents (pulsing → thicker outline).

---

## 6. Full Inspect Interaction Design

### How to Trigger

| Input | Action |
|---|---|
| Mouse | Right-click on entity |
| Keyboard | Navigate + press `I` or `F1` |
| Controller | Focus + press X |
| Touch | Long-press (300ms) |

### Three Progressive Detail Tiers

**Tier 1 — Summary (immediate):** Name, species, current action, overall status, one-line mood sentence.

**Tier 2 — Desire Breakdown (scroll/Tab):** All desire bars with satisfaction, each showing icon + label + fill + text + trend arrow (improving/declining/stable).

**Tier 3 — History & Detail (second scroll/Tab):** Personality weights, recent action log, location history, robot notes, ferret stash inventory, kitten mischief log.

### Panel Behavior

- Non-modal, game continues.
- Panel tracks entity (tether line if it moves).
- Auto-updates in real-time.
- Up to 3 panels open simultaneously for comparison.
- If entity leaves viewport: persistent tag at edge showing direction + distance.
- Positioned adjacent to entity (priority: right, left, above, below). Never overlaps it.

### Multi-Inspect at Scale

- Inspect a rack slot → aggregate of all animals in that slot
- Inspect a rack → aggregate for entire rack
- Filter shortcut (`F`): highlight all animals at same status level across all racks
