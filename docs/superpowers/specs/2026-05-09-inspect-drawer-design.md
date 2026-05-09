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
- **Partial `input-design.md` §5 regression — accepted, with v2 ticket.** §5 mandates four redundant channels per desire (color + fill pattern + icon + text). v1 ships color + numeric value only. The full 4-channel encoding lands together with the 4-state shape language below in v2; until then, the inspect drawer is a known accessibility downgrade vs. the §5 target.
- 4-state shape language: NOMINAL / ADVISORY / DEGRADED / CRITICAL with circle / triangle / diamond / octagon. v1 uses two states: `Content` / `Wanting`.
- `reduce_motion` settings hook — there is no settings surface in v1, so the slide tween is unconditional. Add the hook in v2 alongside the settings menu.
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
- **Slide animation** ~0.15s ease-out (humans perceive <300 ms as snappy). Unconditional in v1; the `reduce_motion` settings hook is a v2 addition once a settings surface exists.

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

- `ESC` (keyboard).
- Controller `B`.
- Click outside the drawer rect.
- The drawer's `X` header button.
- Trigger fires for the entity already inspected (toggle).

### Focus & navigation

- On open, focus lands on the **first desire bar** (or the close `X` if no bars — i.e. servers).
- `Tab` / D-pad cycles through bars top-to-bottom, then `X`. `Shift+Tab` reverses.
- On close, focus returns to the **triggering element** (the portrait that was clicked, the world entity, etc.). For triggers without a focus parent (right-click, controller `X` on world entity), focus returns to the placement drawer's first button or the camera focus, whichever was last.
- Click-outside hit-test: drawer rect captures clicks within its bounds. The narrator panel (which the drawer overlaps) captures clicks in its non-overlapped region. Hit-priority within the overlap belongs to the drawer.

### Content (top to bottom)

Fonts at size 3 to match the rest of the HUD.

The render path branches on **capability presence**, not species: `db.has_component(_inspected_id, &"desires")` selects the animal layout; absence selects the object layout. No species-label dispatch.

**Animal layout:**

1. **Header row** — name in entity's `hud_color`; status keyword (`Content` / `Wanting`); `X` close button.
2. **8 desire bars** — one per row, full 8-channel coloring from `DESIRE_COLORS`. Each bar = label-on-left + colored fill + numeric value. No trend arrows in v1. Channels with `decay == 0` and no live scatter source in the active scenario are rendered **greyed out with a `—` value** to mark them as system-frontier scaffolding (cf. abundance principle: a `Wanting` reading from an unmodeled channel would feel like the player failed at an unshipped feature).
3. **Current action** — one line, derived from `ai_state.state` (lowercased).
4. **Personality** — labeled grid of raw weight values from the `personality` component, e.g. `Wa 7  Co 7  Cu 1  Hu 7  So 5  Qu 6  Pe 5  Sa 8`. Two-letter abbreviations are stable so the player learns the column. Raw numbers are intentional; the panel is a discovery surface, not a paraphrase.

**Server layout:**

1. **Header row** — display id (`Server 0/3` for bay 0 / rack 3 / slot N), status keyword (`Powered` / `Unpowered`), `X` close button.
2. **Real fields** (read from existing components):
   - rack / slot — derived via `Constants.bay_local_to_slot(position)`
   - power state — derived from "any HUM has reserve" while cables are out
   - heat output + radius — read from this entity's `advertisements` for the `warmth` channel
   - nearby-animal count — `db.query_radius_with(x, y, BAY_WIDTH_PX, &"desires").size()`
3. **Mock fields** — display only, no backing component. Marked with a leading `~` so the implementer doesn't wire imaginary state. Concretely:
   - `~ Fan: 1200 RPM` — there is no fan-speed component today; show a fixed-or-randomized number for visual fidelity. Replace with a real read when fans ship.

The `~` prefix is the spec's contract that those rows render placeholder data and must NOT be wired to fabricated GameStateDB writes. When real components arrive, the prefix drops and the row reads live state.

### Behavior

- One drawer max at a time. Re-targeting (another trigger emission) updates content in place; no second panel opens.
- Drawer reads inspected entity's components per-frame in `_process` from GameStateDB. Cheap (one entity, one dict-shaped row, ~1 µs).
- **Auto-close**: drawer auto-closes when `db.has_entity(_inspected_id)` returns false. The `has_entity` check is the **first** statement in `_process`, before any component reads, so a destroyed entity never produces a stale-state frame.
- **Trigger races**: if two `entity_inspect_opened` events fire in the same frame for different entities, the **last emission wins**. Any in-flight slide tween continues — only the bound `entity_id` is updated, the tween does not restart.
- Drawer ignores camera position. Entity tracking (tether line, off-viewport edge tag) is a v2 addition.
- **Multiplayer**: `_inspected_id` is purely local HUD state. The trigger emission is HUD-local only — never serialized over the network. A peer inspecting their own cat does not open another peer's drawer.
- **Save/load**: `_inspected_id` is **not persisted**. On save, ignored; on load, drawer starts closed.
- **Scale**: `db.has_entity` is one dict lookup. Even at 1 000-entity datacenters with mass despawns, the close path is constant time.

### Status keyword derivation

- **Animals:** read `contentment.is_satisfied` → `Content` (true) or `Wanting` (false). The `is_satisfied` calculation already aggregates only desires that have live scatter sources (the same condition that drives the greyed-bar render in §Content). Frozen system-frontier channels do not flip the keyword.
- **Servers:** read presence of an active power source. With cables out today (`hum-cable-system.md`), this is "any HUM has reserve" → `Powered`, otherwise `Unpowered`. Revisits when cables come back.

## Data flow & signals

The drawer is a HUD consumer. Per `signals.md`, HUD only touches `Events`, never reaches into GameServer children.

### Open / re-target path

1. Trigger fires (portrait click, right-click world, `I`, `X`, etc.).
2. Trigger site emits `Events.entity_inspect_opened(entity_id)`.
3. Drawer (subscribed to that signal) calls its own `open(entity_id)`.
4. Drawer stores `_inspected_id`, fades in if hidden, plays the slide tween if newly opening.
5. **Camera-center side-effect:** on portrait click only, the trigger handler in `animal_stats_bar.gd` ALSO tweens the camera to the entity's position. Other triggers (right-click world, `I`, `X`) do not touch the camera. The side-effect is co-located with the emission, not inside the drawer.

### Per-frame read (in `_process`, never `_physics_process`)

```gdscript
# Guard order matters — has_entity FIRST, then component reads.
if _inspected_id == INVALID_ID:
    return
if not _db.has_entity(_inspected_id):
    close()
    return
# Capability branch — animal vs object via component presence, never species.
if _db.has_component(_inspected_id, &"desires"):
    # Animal layout reads:
    #   species (name + hud_color)
    #   desires (8 ints)
    #   ai_state.state
    #   personality (8 weights)
    #   contentment.is_satisfied → status keyword
else:
    # Object layout reads (servers in v1):
    #   position → Constants.bay_local_to_slot(position)
    #   advertisements (heat radius / strength)
    #   spatial.query_radius_with(...) for nearby-animal count
    #   any HUM reserve > 0 → Powered/Unpowered
```

`db.get_component()` returns a reference to the internal row, not a copy (per `CLAUDE.md` GameStateDB Gotchas). The drawer treats every read as read-only and never mutates returned dicts.

### New signals

| Signal | Payload | Emitted by | Listened by |
|---|---|---|---|
| `entity_inspect_opened` | `(entity_id: int)` | Portrait-click handler, right-click handler, `I`/`X` handler | InspectDrawer |

One new signal in `Events`. Well below the 50-signal split threshold.

### No new core systems

The drawer is pure HUD. Reads existing components; emits no events of its own beyond the trigger emission; never writes to GameStateDB.

## Migration of Placement and Narrator into the drawer pattern

Out of scope for this spec. See `docs/superpowers/specs/2026-05-09-drawer-migration-design.md` for the placement-drawer and narrator-drawer migrations. That spec depends on this one shipping first (the drawer primitive lives in `nodes/hud/drawer.gd`, introduced here).

## Open questions answered (record for v2 implementer)

| Question | Answer |
|---|---|
| Two drawers open at once? | Most-recent overlap. Both render; later renders on top. No auto-close. Re-validate when 2nd drawer arrives. |
| 0.15 s slide too slow? | Budget is <300 ms total. Tune via playtest. |
| Single "open drawers" key? | No. `L` stays narrator-specific. Each drawer keeps its own trigger. |
| Persistent open/closed setting per player? | No. Drawers default to a fixed state per type and reset each session. |

## Testing

Following `test-philosophy.md`. **Heavy unit coverage; minimal integration.** Reuse existing integration tests where possible — do not add a new integration suite if a smoke test already covers the wire-up.

### Refactor for testability

Extract the drawer's state machine and its content-building functions into a RefCounted `InspectDrawerState` (in `engine/inspect/`). The state object takes a `GameStateDB` reference, exposes pure methods (`open(id)`, `close()`, `process(db) -> InspectView`, `derive_status_keyword(db, id) -> StringName`, `build_animal_view(db, id) -> Dictionary`, `build_server_view(db, id) -> Dictionary`), and never touches the scene tree.

The `Control` wrapper (`nodes/hud/inspect_drawer.gd`) renders the View, plays the tween, and routes input — all of which are out-of-scope for unit tests.

### Unit tests — `tests/unit/test_inspect_drawer_state.gd`

State machine:
1. New state is closed; `inspected_id == INVALID_ID`.
2. `open(entity_id)` on a valid entity → state is open, id matches.
3. `open(other_id)` while already open → id updates, state stays open (re-target).
4. `open(INVALID_ID)` → no-op; state stays closed; id stays `INVALID_ID`.
5. `close()` → state closed, id `INVALID_ID`.
6. `process(db)` after target entity destroyed → state transitions to closed within one call.
7. `process(db)` while closed → no-op (does not read db).

Content branch (capability dispatch):
8. `process(db)` on entity with `desires` component → returns animal view.
9. `process(db)` on entity without `desires`, with `object_type` → returns server view.
10. `process(db)` on entity with neither → returns closed view (defensive; matches drawer auto-close).

Status keyword:
11. Animal with `contentment.is_satisfied = 1` → `Content`.
12. Animal with `contentment.is_satisfied = 0` → `Wanting`.
13. Server with at least one HUM having reserve > 0 → `Powered`.
14. Server with all HUM at 0 reserve → `Unpowered`.

Frozen-channel rendering:
15. Desire channel with `decay == 0` and no scatter source in scenario → animal view marks that bar `is_frozen = true`.
16. Desire channel with `decay < 0` (live) → animal view marks that bar `is_frozen = false`.

Trigger races / re-target during tween:
17. Two `open()` calls in the same logical "frame" (no `process` between) → second call wins; id reflects second.

### Integration test — extend, don't add

Reuse `tests/integration/test_visual_smoke.gd` (the existing scene-boot smoke test). Add **one** assertion block at the end:
- After main scene boots, emit `Events.entity_inspect_opened.emit(<spawned_animal_id>)`.
- Assert `$HUD/InspectDrawer.visible == true` and `$HUD/InspectDrawer.get_state().inspected_id == <spawned_animal_id>`.

This avoids a new integration file and inherits the existing smoke test's setup.

### Not tested (deliberate)

- Tween animation timing (Godot's responsibility).
- Individual `Label` / `ColorRect` rendering (would test GUI state, not behavior).
- Theme overrides (font sizes, colors).
- Camera-centering side-effect (lives outside the drawer; covered by whatever test exists for `animal_stats_bar.gd:_on_panel_clicked`, if any).
- Slide-anchor pixel positions (visual concern, hand-tune in playtest).

## File layout

| File | Purpose |
|---|---|
| `nodes/hud/drawer.gd` (new) | Base `Control` with edge anchoring, open/close API, slide tween. |
| `nodes/hud/inspect_drawer.gd` (new) | Inspect-specific drawer; renders an `InspectDrawerState` view. |
| `engine/inspect/inspect_drawer_state.gd` (new) | RefCounted state machine + content builders. Unit-testable; takes `GameStateDB` as a dependency. |
| `nodes/events.gd` | Add `entity_inspect_opened(entity_id: int)` signal. |
| `nodes/game_client.gd` | Add `_setup_inspect_drawer()` to `_ready()` **after `_setup_stats_bar()` and before `_setup_debug_hud()`** (DebugHud's TODO at lines 81–83 wants an inspect ref). Wire right-click world-entity → emit `entity_inspect_opened`. Add `I` / `F1` to `_handle_key`. |
| `nodes/hud/animal_stats_bar.gd` | Replace direct camera-center on portrait click with `Events.entity_inspect_opened.emit()` + camera-center side-effect (co-located). The unused `_camera` field may be deletable after the change — verify before removing. |
| `tests/unit/test_inspect_drawer_state.gd` (new) | 17 unit tests. |
| `tests/integration/test_visual_smoke.gd` | Extend with one assertion block — see §Testing. No new integration file. |
| `.claude/rules/scene-tree.md` | Add `InspectDrawer` under HUD. |
| `.claude/rules/input-design.md` | Update §1 keyboard map (add `I`/`F1`); §6 stays as the long-form target. |
| `.claude/rules/file-structure.md` | Add `engine/inspect/` to the canonical tree. |

## Out of scope (do not address in this design)

- Drawer system promotion for placement and narrator — separate v2 task; this spec is a pointer.
- Trend arrow data infrastructure (history ring buffers).
- Tier 3 log infrastructure (action log, location history, robot notes).
- 4-state shape icon system.
- Object inspection (boxes, piles, tuna cans, robot arm).
- Multi-panel comparison.
- Off-viewport entity tracking.
