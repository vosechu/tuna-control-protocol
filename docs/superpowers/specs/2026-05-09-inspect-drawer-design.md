# Inspect Drawer (Tier 2) — Design

**Status:** design draft, 2026-05-09. Brainstormed with user. Awaiting implementation plan.

**Companion rules:**
- `.claude/rules/input-design.md` §2 + §6 — long-form spec (multi-panel, trend arrows, 4-state shapes). This design is a v1 subset.
- `.claude/rules/scene-tree.md` — drawer parents to HUD CanvasLayer.
- `.claude/rules/signals.md` — HUD-only consumers, past-tense signal naming.
- `.claude/rules/test-philosophy.md` — Sandi Metz table for what to test.
- `.claude/rules/design-philosophy.md` — Pure-Core (RefCounted state, Node renders).

## Scope

**In v1:**
- Animals + servers (the two most-inspected entity types in current play).
- Tier 2 desire breakdown — all 8 channels, fully colored, current values, no trend arrows.
- Free Tier 3 reads — personality weights, current `ai_state`. No log infra.
- Single drawer at a time. Click-another-portrait re-targets.
- Left-edge anchored. Slides in/out.

**Out of v1** (spec'd elsewhere, not built):
- Multi-panel comparison (input-design.md says up to 3).
- Trend arrows (require per-channel history ring buffer).
- 4-state shape language: NOMINAL / ADVISORY / DEGRADED / CRITICAL with circle / triangle / diamond / octagon. v1 uses two states: `Content` / `Wanting`.
- Off-viewport tether, edge tag, follow-cam.
- Tier 3 history log, location history, robot notes.
- Filter shortcut `F`, multi-inspect aggregates (rack, bay).
- Inspect for boxes, piles, tuna cans, robot arm.

## The drawer primitive

A **drawer** is a screen-edge-anchored `Control` that slides in/out from one viewport edge, stays in screen space (HUD CanvasLayer), and follows a small contract:

- **Anchored to one viewport edge** (left, right, or bottom). Anchor is fixed at construction.
- **Two states** — open (visible, full size) and closed (hidden / off-edge). No half-open.
- **Open-close affordance** — keyboard shortcut, trigger event, or `X` button in the drawer header. Closing is symmetric — same trigger, `ESC`, click outside, or `X`.
- **Single-occupant per edge** (v1) — at most one drawer per edge. v2 may stack.
- **No layout-pushing** — an open drawer overlays content behind it. It does not reflow the rest of the HUD. Most-recent drawer wins z-order.
- **Slide animation** ~0.15s ease-out (humans perceive <300 ms as snappy). Skip if a `reduce_motion` setting is on.

The pattern lives as a small base script (`nodes/hud/drawer.gd`) that Inspect inherits. Future placement and narrator drawers reuse it.

## Inspect drawer specifics

### Edge & size

- **Edge:** left.
- **Size:** 56 × 72 px (tunable in playtest).
- **Position:** anchored at `(2, 54)` — sits below the stats portraits (which end ~y=52), above the centered narrator (y=110+). Will overlap the left edge of the narrator panel while both are open. Acceptable since drawers overlay by design.

### Triggers

Any of these opens (or re-targets) the inspect drawer for an entity:

- **Portrait click** (top-of-screen stats bar) → opens AND centers the camera on the entity.
- **Right-click** on an animal or server in the world.
- **Keyboard `I` or `F1`** while an entity is focused (focus = last-clicked, for v1).
- **Controller `X`** while an entity is focused.
- **Touch long-press (300 ms)** — same path.

### Closes

- `ESC`.
- Click outside the drawer.
- The drawer's `X` header button.
- Trigger fires for the entity already inspected (toggle).

### Content (top to bottom)

Fonts at size 3 to match the rest of the HUD.

1. **Header row** — name in entity's `hud_color`; status keyword (`Content` / `Wanting` for animals; `Powered` / `Unpowered` for servers); `X` close button.
2. **8 desire bars** (animals) — one per row, full 8-channel coloring from `DESIRE_COLORS`. Each bar = label-on-left + colored fill + numeric value. No trend arrows in v1.
3. **Current action** — one line, derived from `ai_state.state` (lowercased).
4. **Personality weights** — tight grid of raw weight values from the `personality` component (e.g. `w7 c7 cu1 h7 s5 q6 p5 sa8`). Player-facing intent: understanding, not narration.

For **servers**, replace #2 with: rack / slot, power state, fan speed, heat output + radius, nearby-animal count. #3 and #4 are omitted (not relevant to servers).

### Behavior

- One drawer max at a time. Re-targeting (clicking another portrait) updates content in place; no second panel opens.
- Drawer reads inspected entity's components per-frame in `_process` from GameStateDB. Cheap (one entity).
- Drawer auto-closes when `db.has_entity(_inspected_id)` becomes false (entity destroyed). No subscribed signal needed — the next-frame poll catches it.
- Drawer ignores camera position. Entity tracking (tether line, off-viewport edge tag) is a v2 addition.

### Status keyword derivation

- **Animals:** read `contentment.is_satisfied` → `Content` (true) or `Wanting` (false).
- **Servers:** read presence of an active power source. With cables out today (`hum-cable-system.md`), this is "any HUM has reserve" → `Powered`, otherwise `Unpowered`. Revisits when cables come back.

## Data flow & signals

The drawer is a HUD consumer. Per `signals.md`, HUD only touches `Events`, never reaches into GameServer children.

### Open / re-target path

1. Trigger fires (portrait click, right-click world, `I`, `X`, etc.).
2. Trigger site emits `Events.entity_inspect_requested(entity_id)`.
3. Drawer (subscribed to that signal) calls its own `open(entity_id)`.
4. Drawer stores `_inspected_id`, fades in if hidden, plays the slide tween if newly opening.
5. **Camera-center side-effect:** on portrait click only, the trigger handler in `animal_stats_bar.gd` ALSO tweens the camera to the entity's position. Other triggers (right-click world, `I`, `X`) do not touch the camera. The side-effect is co-located with the emission, not inside the drawer.

### Per-frame read (in `_process`, never `_physics_process`)

```gdscript
if _inspected_id == INVALID_ID:
    return
if not _db.has_entity(_inspected_id):
    close()
    return
# Read for animals:
#   species (name + hud_color)
#   desires (8 ints)
#   ai_state.state
#   personality (8 weights)
#   contentment.is_satisfied → status keyword
# Read for servers:
#   slot via Constants.bay_local_to_slot(position)
#   advertisements (heat radius / strength)
#   power-state aggregation
```

### New signals

| Signal | Payload | Emitted by | Listened by |
|---|---|---|---|
| `entity_inspect_requested` | `(entity_id: int)` | Portrait-click handler, right-click handler, `I`/`X` handler | InspectDrawer |

One new signal in `Events`. Well below the 50-signal split threshold.

### No new core systems

The drawer is pure HUD. Reads existing components; emits no events of its own beyond the trigger emission; never writes to GameStateDB.

## Migration notes — Placement and Narrator → drawers (v2 task)

Documented now so v2 isn't archaeology.

### Placement → right-edge drawer

1. Reparent `placement_ui.gd`'s VBoxContainer into a Drawer-derived control anchored to the right edge.
2. **Open trigger decision is open.** Two reasonable v2 shapes:
   - *Explicit:* dedicated key (input-design.md §1 spec uses `1-4` for drawer toggle, but `1-7` are bound for placement today, so this needs a new convention).
   - *Implicit:* pressing `1-7` opens-and-selects in one motion. Default state closed; the key both opens the drawer and confirms the selection.
3. Default state changes from always-visible → closed.
4. Pull `1-7` and `R` keypress handling out of `_unhandled_input` and into the drawer's open-state handler so keys are no-ops while closed.

### Narrator → bottom-edge drawer

1. Reparent NarratorPanel into a Drawer-derived control anchored to the bottom edge.
2. Replace `panel.visible = not panel.visible` (in `game_client.gd:_handle_key`'s `KEY_L` branch) with the drawer's `open()` / `close()` API so it slides instead of pop.
3. Default state stays **open** — narrator events are critical feedback; opting out should be deliberate (`L`).
4. Pinned-line behavior unchanged.
5. `L` keeps its current narrator-specific binding (no convergence to a single "open drawers" key).

## Open questions answered (record for v2 implementer)

| Question | Answer |
|---|---|
| Two drawers open at once? | Most-recent overlap. Both render; later renders on top. No auto-close. Re-validate when 2nd drawer arrives. |
| 0.15 s slide too slow? | Budget is <300 ms total. Tune via playtest. |
| Single "open drawers" key? | No. `L` stays narrator-specific. Each drawer keeps its own trigger. |
| Persistent open/closed setting per player? | No. Drawers default to a fixed state per type and reset each session. |

## Testing

Following `test-philosophy.md`.

### Refactor for testability

Extract the drawer's state machine into a RefCounted `InspectDrawerState` (in `engine/hud/`) so it can be unit-tested without the scene tree. The Control wrapper renders that state, plays the tween, routes input.

### Unit tests — `tests/unit/test_inspect_drawer_state.gd`

1. New state is closed; `inspected_id == INVALID_ID`.
2. `open(entity_id)` sets state to open and stores the id.
3. `open(other_id)` while already open re-targets — id changes, state stays "open".
4. `close()` resets state to closed and clears id.
5. `open(INVALID_ID)` is a no-op.
6. Status keyword derivation — `is_satisfied = true` → `Content`, false → `Wanting`.

### Integration tests — `tests/integration/test_inspect_drawer.gd`

1. **Trigger routing:** emit `Events.entity_inspect_requested(animal_id)` → drawer opens with that id.
2. **Auto-close on destroy:** drawer is open on entity X → `db.destroy_entity(X)` → drawer closes within one frame.

### Not tested

- Tween animation timing (Godot's responsibility).
- Individual Label / ColorRect rendering (would be testing GUI state, not behavior).
- Theme overrides (font sizes, colors).
- Camera-centering side-effect (lives outside the drawer).

## File layout

| File | Purpose |
|---|---|
| `nodes/hud/drawer.gd` (new) | Base Control with edge anchoring, open/close API, slide tween. |
| `nodes/hud/inspect_drawer.gd` (new) | Inspect-specific drawer; renders InspectDrawerState. |
| `engine/hud/inspect_drawer_state.gd` (new) | RefCounted state machine. Unit-testable. |
| `nodes/events.gd` | Add `entity_inspect_requested(entity_id: int)` signal. |
| `nodes/game_client.gd` | Wire right-click world entity to emit `entity_inspect_requested`. Add `_setup_inspect_drawer()` step. Add `I` / `F1` to `_handle_key`. |
| `nodes/hud/animal_stats_bar.gd` | Replace direct camera-center on portrait click with `Events.entity_inspect_requested.emit()` + camera-center side-effect (co-located). |
| `tests/unit/test_inspect_drawer_state.gd` (new) | Six unit tests. |
| `tests/integration/test_inspect_drawer.gd` (new) | Two integration tests. |
| `.claude/rules/scene-tree.md` | Add `InspectDrawer` under HUD. |
| `.claude/rules/input-design.md` | Update §1 keyboard map (add `I`/`F1`); §6 stays as the long-form target. |

## Out of scope (do not address in this design)

- Drawer system promotion for placement and narrator — separate v2 task; this spec is a pointer.
- Trend arrow data infrastructure (history ring buffers).
- Tier 3 log infrastructure (action log, location history, robot notes).
- 4-state shape icon system.
- Object inspection (boxes, piles, tuna cans, robot arm).
- Multi-panel comparison.
- Off-viewport entity tracking.
