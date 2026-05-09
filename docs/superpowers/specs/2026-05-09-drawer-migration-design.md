# Drawer Migration — Placement & Narrator → Drawer Pattern

**Status:** design draft, 2026-05-09. The drawer primitive (`nodes/hud/drawer.gd`) and its contract are documented in `.claude/rules/ui-patterns.md` §Drawers; this spec extends that pattern to placement and narrator.

**Companion rules:**
- `.claude/rules/input-design.md` §1 — keyboard shortcut map.
- `.claude/rules/scene-tree.md` — HUD parenting.
- `.claude/rules/signals.md` — HUD-only consumers.

## Why now?

The inspect-drawer spec introduced a generic drawer primitive. Two existing always-on HUD elements — placement buttons (right edge) and narrator panel (bottom edge) — fit the pattern but currently live as ad-hoc anchored controls. Promoting them into the pattern:

- Standardizes open/close affordances.
- Lets the player declutter the screen for screenshots, observation, or focused inspection.
- Validates the drawer pattern at three of its three planned anchor edges.

This spec deliberately ships **after** inspect — the inspect drawer surfaces the open questions (overlap rules, animation budget, persistence) that this spec assumes are answered.

## Placement → right-edge drawer

### Target shape

- Inherit `nodes/hud/drawer.gd`. Edge: right.
- Default state: **closed**. (Today the placement column is always-visible.)
- Triggers (decision below): pressing the placement keys opens-and-selects in one motion (implicit) OR a dedicated key opens, then the placement keys select (explicit).
- Closes on `ESC`, click outside, the drawer's `X` button, controller `B`.

### Open trigger — fork

| Option | Pros | Cons |
|---|---|---|
| **Implicit** — `1`–`7` open the drawer AND select the type in one motion. Pressing the key for the already-selected type cancels (closes drawer + clears selection). | One-keystroke parity with current behavior; nothing for player to learn. | Mixes "open UI" and "make game change" into the same press. |
| **Explicit** — dedicated key (e.g. `D` for "drawer", or one of the freed numbers if `1`–`7` repurpose) opens the drawer; `1`–`7` select while open. | Cleanest UX shape; matches input-design.md §1 spec where `1`–`4` toggle drawers. | Two keystrokes for what is one today. Forces a binding shuffle. |

**Recommendation:** Implicit. Preserves muscle memory; a `D` key can be added in v3 if power-users want pure-keyboard navigation without hitting a placement type accidentally.

### Implementation steps

1. Reparent `placement_ui.gd`'s `VBoxContainer` into a `PlacementDrawer` (Drawer-derived `Control`), anchored right.
2. Move `1`–`7` and `R` keypress handling out of `_unhandled_input` and into the drawer's open-state handler. Keys are no-ops while closed (with implicit trigger, the same key opens + dispatches).
3. Default state: closed. The drawer slides in on first key press.
4. The `Esc` cancel behavior in `placement_ui.gd:_unhandled_input` now also closes the drawer.

### Migration risk

- **Power players** with current muscle memory will hit `1` expecting placement and find a slide animation first. The 0.15 s slide should be invisible enough that the next click lands on the just-revealed button.
- The current `_buttons[&"remove"]` toggle stays the same; it just lives inside the drawer.

## Narrator → bottom-edge drawer

### Target shape

- Inherit `nodes/hud/drawer.gd`. Edge: bottom.
- Default state: **open** — narrator events are critical feedback; opt-out should be deliberate.
- Triggers: `L` toggles open/closed (existing binding kept).
- Closes on `L`, `ESC`, click outside, controller `B`.

### Implementation steps

1. Reparent `NarratorPanel` into a `NarratorDrawer` (Drawer-derived `PanelContainer`), anchored bottom.
2. Replace `panel.visible = not panel.visible` (in `nodes/game_client.gd:_handle_key`'s `KEY_L` branch) with `narrator_drawer.toggle()` so the drawer slides instead of pop.
3. Default state: open. Drawer is visible at boot.
4. Pinned-line behavior unchanged; pinned text persists across open/close.

### Why narrator stays its own key (not a unified "drawer" key)

Narrator is high-frequency, single-purpose, and the player learns `L` once. Folding it into a generic "drawer toggle" cycle would force the player to count their way through a list to dismiss one panel. Per-drawer keys is the cheaper UX.

## Drawer-system invariants this spec validates

After both migrations land, the drawer pattern has run on **all three** anchor edges (left/inspect, right/placement, bottom/narrator). The following invariants are observable at that point and should be confirmed in playtest before declaring the pattern stable:

| Invariant | How to observe |
|---|---|
| Most-recent overlap (no auto-close on conflict) | Open inspect, then placement; both render, placement on top within overlap region. |
| 0.15 s slide budget | All three drawers feel equally snappy. None feels sluggish, none feels jarring. |
| No persistent setting | Reload — inspect closed, placement closed, narrator open. |
| Per-drawer triggers (no unified key) | `L` only narrator; `1`–`7` only placement; `I`/`X`/click-portrait only inspect. |

If any invariant fails in playtest, file a new spec; do not patch this one in flight.

## Tests

Unit tests on each drawer's state machine follow the inspect spec's pattern (state in `engine/<topic>/`, Control renders View). Specifically:

- `tests/unit/test_placement_drawer_state.gd` — open/close, key dispatch while open, no-op while closed.
- `tests/unit/test_narrator_drawer_state.gd` — toggle correctness, pinned-line preservation across toggles.

Integration test extension: add **one** smoke assertion in `tests/integration/test_visual_smoke.gd` that all three drawers exist and have the expected default visibility (inspect closed, placement closed, narrator open).

## Out of scope for this spec

- Drawer **system** features beyond the three migrations: drag-to-close, multi-edge stacking, persistent open-closed state per player, settings-driven overrides.
- A unified "open drawers" UI key.
- Touch / mobile gestures.
- Drawer-edge LEDs / glow / decoration.
- Anything that affects the **shape** of the drawer primitive in `nodes/hud/drawer.gd` — that file is owned by the inspect spec; if a need arises here, file an amendment to the inspect spec.

## File layout

| File | Purpose |
|---|---|
| `nodes/hud/placement_drawer.gd` (new) | Drawer-derived right-anchored placement column. Replaces `placement_ui.gd`'s VBox-in-Control shape. |
| `nodes/hud/narrator_drawer.gd` (new) | Drawer-derived bottom-anchored narrator panel. |
| `engine/placement/placement_drawer_state.gd` (new) | RefCounted state machine for the placement drawer (open/closed + selected type). |
| `engine/narrator/narrator_drawer_state.gd` (new) | RefCounted state machine for the narrator drawer (open/closed + pinned message + history). Hosts what `NarratorPanel`'s `_history` and `_pinned_log` currently track in the node. |
| `nodes/placement_ui.gd` | Slim down to a thin Control that hosts `PlacementDrawer`. Or delete and inline into `placement_drawer.gd` if simpler. |
| `nodes/narrator_panel.gd` | Slim down or fold into `narrator_drawer.gd`. |
| `nodes/game_client.gd` | `_setup_placement_ui()` becomes `_setup_placement_drawer()`; `_setup_narrator_panel()` becomes `_setup_narrator_drawer()`. `KEY_L` branch in `_handle_key` calls `narrator_drawer.toggle()`. |
| `tests/unit/test_placement_drawer_state.gd` (new) | Open/close, key dispatch tests. |
| `tests/unit/test_narrator_drawer_state.gd` (new) | Toggle, pinned-line tests. |
| `tests/integration/test_visual_smoke.gd` | One added assertion for default-visibility per drawer. |
| `.claude/rules/scene-tree.md` | Update HUD listing — `PlacementDrawer`, `NarratorDrawer`. |
| `.claude/rules/input-design.md` | Note placement-drawer trigger (implicit/explicit decision).
