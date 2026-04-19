---
paths:
  - "nodes/**"
  - "**/*.tscn"
---

# TCP Scene Tree Skeleton

Godot 4.6, GDScript. Prototype scope: 1 simulated bay (5 racks × 10 slots), a handful of cats/ferrets, tuna-can food chain.

```
Root (Node)
  GameServer (Node)                     # Authoritative state (RefCounted systems live here)
    # No child nodes — GameServer owns RefCounted systems directly:
    #   HeatGrid, DesireResolver, ProximityEventManager, AnimalRegistry,
    #   ObjectRegistry, HumSystem, FoodSystem, ReclamationSystem,
    #   PlantGrowthSystem, ObjectStateManager. See `design-philosophy.md`.

  GameClient (Node)
    Camera (Camera2D)                   # camera_controller.gd — bay follow, zoom
    World (Node2D)
      EnvironmentTileMap (TileMap)      # tcp_environment.tres; painted by TilePainter for bays {-1, 0, 1}
      RackRow (Node2D)
        Bay_-1 (Sprite2D)               # peek, muted modulate
        Bay_0 (Sprite2D)                # rack_5set_idle_strip1.png at (0, RACK_TOP_Y)
        Bay_1 (Sprite2D)                # peek, muted modulate
      RackDecor (Node2D)
        Bay_0_decor (Sprite2D)          # rack_5set_decor_strip1.png, alpha ramps on first plant_spawned
      PlacedObjects (Node2D)            # Servers, boxes, tuna cans — flat children
      DynamicPlants (Node)              # Projection: Sprite2D children of server sprites
      Animals (Node2D)
        animal_0..N (Node2D)            # Instances of animal.tscn, one per entity
      HeatOverlay (Node2D)              # Debug heat view

    HUD (CanvasLayer)
      HumBar                            # HUM reserve readout
      StatsBar                          # Per-frame diagnostics
      InspectPanel (PanelContainer)     # On right-click / I / X
      (RobotNarrator as a Node subscribes to Events.plant_spawned/despawned;
       renders to its own log surface.)

    PlacementUI (Control)               # Ghost + highlights for drag placement
    SoundManager (Node)
      AmbientLayer (AudioStreamPlayer)
```

**What moved since the 2026-04-10 rescale:**
- Racks are no longer five separate `Rack_N` nodes with `SlotGrid` children. A bay is one `rack_5set` sprite; slots are resolved by `Constants.bay_local_to_slot()` on click.
- `EnvironmentTileMap` replaces the old `Floor` FloorArea / wall Sprite2D-per-column approach. See `asset-pipeline.md` for `TilePainter`.
- `DynamicPlants` is a projection Node that watches `Events.plant_spawned` / `Events.plant_despawned` (see `growth-system.md`) and parents plant sprites onto the server sprites registered by `GameClient` during placement.

## Animal Scene (instanced per animal)

```
AnimalRoot (Node2D)
  Sprite (AnimatedSprite2D)
  SoundEmitter (AudioStreamPlayer2D)
  BodyArea (Area2D)                     # Soft occupancy (pile-on, no blocking)
    BodyShape (CollisionShape2D)
  DesireArea (Area2D)                   # Perception radius (~8U)
    PerceptionShape (CollisionShape2D)
  AnimalAgent (Node)                    # State machine + utility AI
```

**Key ownership:** GameServer owns all authoritative state. GameClient owns rendering, input, HUD, sound. AnimalAgent runs server-side; client interpolates.

**Thin wrapper rule:** Every Node listed under GameServer (SimClock, HeatGrid, DesireResolver, etc.) is a thin wrapper around a RefCounted core object. The Node handles lifecycle (_ready, scene tree integration) and delegates all logic to its core object. This is NOT a contradiction of the Pure Core pattern — Nodes exist to participate in the scene tree; they do not hold authoritative game logic.

Nodes legitimately handle: rendering, input capture, collision shape management, audio playback, and scene tree lifecycle. These feed data INTO core objects but don't hold authoritative state.
