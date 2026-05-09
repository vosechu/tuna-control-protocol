---
paths:
  - "nodes/hud/**"
---

# TCP UI Patterns

Conventions for HUD code under `nodes/hud/`. The HUD is a `CanvasLayer` child of `GameClient`. It never holds references to `GameServer` children — `Events` is the client/server membrane.

## Signal listening

The HUD subscribes directly to the `Events` autoload. No ViewModel, no UI dispatcher, no push model. Each panel self-subscribes in its own `_ready()`.

```gdscript
# inspect_panel.gd — part of the HUD CanvasLayer
extends PanelContainer

var _inspected_animal_id: int = -1

func _ready() -> void:
    Events.animal_state_changed.connect(_on_animal_state_changed)
    Events.animal_desire_critical.connect(_on_animal_desire_critical)
    Events.heat_cell_changed.connect(_on_heat_cell_changed)
    Events.robot_arm_activated.connect(_on_robot_arm_activated)

func inspect(animal_id: int) -> void:
    _inspected_animal_id = animal_id
    _refresh()

func _on_animal_state_changed(animal_id: int, _old: StringName, new_state: StringName) -> void:
    if animal_id != _inspected_animal_id: return
    %StateLabel.text = tr("STATE_" + new_state.to_upper())

func _on_animal_desire_critical(animal_id: int, desire_type: StringName, value: float) -> void:
    if animal_id != _inspected_animal_id: return
    %DesireBar.update_desire(desire_type, value)

func _on_heat_cell_changed(cell_id: int, _old: float, new_temp: float) -> void:
    if not _is_cell_relevant(cell_id): return
    %TempReadout.value = new_temp
```

**Why not a ViewModel?** At prototype scale (5 animals, 210 heat cells), the bus has trivial traffic. A ViewModel adds indirection that helps nobody and makes debugging harder. If we hit 1000 animals and 10,000 events/sec the UI doesn't need, add filtering at the bus level (interest management) — not an intermediate ViewModel. Cross that bridge if we reach it.

**Why not direct references?** The HUD is a CanvasLayer child of GameClient. GameServer owns simulation state. These live on different sides of the client/server boundary. The HUD must never hold a reference to a GameServer child.

## Drawers

A **drawer** is a screen-edge-anchored `PanelContainer` that slides in/out from one viewport edge, stays in screen space (HUD CanvasLayer), and follows this contract. The base lives at `nodes/hud/drawer.gd`; subclasses `InspectDrawer` (left), `PlacementDrawer` (right), and `NarratorDrawer` (bottom) inherit it.

| Rule | What it means |
|---|---|
| Anchored to one edge | `AnchorEdge.LEFT` / `RIGHT` / `BOTTOM`. Fixed at construction. |
| Two states | Open (visible, full size) or closed (hidden / off-edge). No half-open. |
| Slide ~0.15s ease-out | Tween position only; do not restart the tween on re-target — only rebind the bound id. |
| Single-occupant per edge | At most one drawer per edge (v1 contract; v2 may stack). |
| No layout-pushing | An open drawer overlays content behind it. Most-recent drawer wins z-order. |
| One close path | All affordances (X button, click-outside, ESC, controller B, toggle re-emit) route through one `_close_drawer()` method that closes both the state and the Control. |

**Subclass authoring — set size before `super._ready()`.** The `Drawer` base computes `_closed_position` from `custom_minimum_size` inside its own `_ready()`. Subclasses MUST set `custom_minimum_size`, `anchor_edge`, and `open_position` in their own `_ready()` *before* calling `super._ready()` — otherwise the base reads zero, `_closed_position` collapses to `open_position`, and `close()` never actually slides off-edge (it just fades via the trailing `visible = false`, which masks the bug). All three current subclasses follow this. If a subclass needs runtime data (a `db` reference, an event bus binding), put internal setup in `_ready()` and accept the runtime data through a separate `initialize()` called after `add_child()`.

**Click-outside policy is per-drawer.** The "One close path" row above governs HOW close happens (single `_close_drawer()` method); WHICH inputs trigger close is each drawer's own choice. Current shipped policy: inspect closes on any outside-click; placement closes on outside-click ONLY when no type/remove selection is active (when one IS active, the world click is the placement action and the drawer stays open so the player can place multiples); narrator closes via `L` only. A re-implementer who assumes "click-outside always closes" will break placement.

**Click-outside detection comes free.** A `Control` auto-consumes `_gui_input` events within its rect, so `_unhandled_input` only fires for clicks outside the drawer. Don't compute the drawer's rect manually — let the control hierarchy do it.

**ESC + controller B parity.** Godot's default `ui_cancel` action maps both. Handle `event.is_action_pressed("ui_cancel")` once in `GameClient._unhandled_input` for full parity.

## Inspect drawer specifics

The inspect drawer (`nodes/hud/inspect_drawer.gd` + `engine/inspect/inspect_drawer_state.gd`) is the canonical worked example of the drawer pattern. The state machine is pure RefCounted — unit-tested without a scene tree.

### Per-frame read order — `has_entity` FIRST

```gdscript
func process(db: GameStateDB) -> void:
    if inspected_id == Constants.INVALID_ID:
        return
    if not db.has_entity(inspected_id):
        close()
        return
    # Capability dispatch — never branch on species labels.
    if db.has_component(inspected_id, &"desires"):
        content_type = ContentType.ANIMAL
    elif db.has_component(inspected_id, &"object_type"):
        content_type = ContentType.SERVER
    else:
        close()
```

The `has_entity` check is load-bearing: it must run before any component read so a destroyed entity never produces a stale-state frame. `db.has_entity` is one dict lookup; even with mass despawns the close path is constant time.

### Capability dispatch, never species

Animal layout is selected by `has_component(&"desires")`; server layout by `has_component(&"object_type")`; entities with neither close defensively. No species labels reach the UI. This is the project-wide rule applied in HUD code — see CLAUDE.md → "Species Are Component Recipes".

### Status keyword derivation

| Content type | Source | Output |
|---|---|---|
| Animal | `contentment.is_satisfied == 1` | `Content` / `Wanting` |
| Server | any `hum.reserve > 0` in the world (cables out) | `Powered` / `Unpowered` |

The drawer reads what the contentment system reports — it does not second-guess the aggregation. If a frozen-decay channel makes `Wanting` feel unfair, fix it in the contentment system or in scenario content (add a satisfier), not in the drawer. When cables return, server power becomes per-device.

### State invariants

- `_inspected_id` is HUD-local. Never serialized to save. Never crosses the network. A peer inspecting their own cat does not open another peer's drawer.
- Trigger races: when two `entity_inspect_opened` events fire in the same frame for different entities, **last emission wins**. Any in-flight slide tween continues — only the bound `entity_id` updates, the tween does not restart.
- Re-emitting on the same entity toggles the drawer closed.

### Camera-center side-effect lives at the trigger

Portrait click is the only trigger that pairs inspect with camera-center. The side-effect is co-located with the emission in `nodes/hud/animal_stats_bar.gd::_on_panel_clicked`, **not** inside the drawer. The drawer stays pure HUD with no reach into camera state. Other triggers (right-click world, `I`/`F1`, controller `X`) emit only.
