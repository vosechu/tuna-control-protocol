# TCP Scene Tree Skeleton

Godot 4.3+, GDScript, prototype scope (5 racks, 3 cats, 2 ferrets, 8 object types).

```
Root (Node)
  GameServer (Node)                     # Authoritative state, even in solo
    SimClock (Node)                     # Owns tick timer, emits tick signals
    HeatGrid (Node)                     # Heat propagation system
    DesireResolver (Node)               # Utility AI scoring each tick
    ProximityEventManager (Node)        # Discovery events, cooldowns
    AnimalRegistry (Node)               # animal_id -> AnimalAgent
    ObjectRegistry (Node)               # object_id -> PlacedObject

  GameClient (Node)
    Camera (Camera2D)                   # Pans across 5 racks, zoom
    World (Node2D)
      RackRow (Node2D)
        Rack_0..4 (Node2D)
          SlotGrid (Node2D)             # 42 children, one per U
            RackSlot_00..41 (Area2D)    # 1U hitbox each
              OccupantAnchor (Marker2D)
          PDU (Sprite2D)
          TOR_Switch (Sprite2D)
          StatusPanel (Control)
      Floor (Node2D)
        FloorArea (Area2D)              # Walkable ground
        RobotArmStation (Node2D)        # Fixed position
          ArmSprite (AnimatedSprite2D)
          ActivationZone (Area2D)       # 3U radius trigger
          AudioEmitter (AudioStreamPlayer2D)
      NavGraph (Node2D)                 # Debug overlay for nav nodes
      Animals (Node2D)
        Cat_0..2 (Node2D)
        Ferret_0..1 (Node2D)
      PlacedObjects (Node2D)
      FurballPool (Node2D)              # Object pool, max ~200
      Cables (Node2D)                   # Line2D instances

    HUD (CanvasLayer)
      DrawerBar (HBoxContainer)
        KittyDrawer / CableDrawer / InfraDrawer / UtilityDrawer
      WiringViewToggle (Button)
      InspectPanel (PanelContainer)
      RobotNarrator (RichTextLabel)

    SoundManager (Node)
      AmbientLayer (AudioStreamPlayer)
```

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
