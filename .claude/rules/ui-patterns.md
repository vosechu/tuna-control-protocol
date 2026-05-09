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
