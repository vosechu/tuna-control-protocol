# TCP Viewport LOD & Subscription Zones

## Zone Model
World divided into **zones** aligned to rack boundaries (1 rack = 1 zone). Zones are the atomic unit of subscription, simulation, and rendering.

## Subscription Tiers

| Tier | Distance | Server sends | Client renders | Client simulates |
|---|---|---|---|---|
| **Active** | Viewport + 1 zone buffer | All deltas | Full detail | Full AI (if solo) |
| **Nearby** | +2-4 zones | Major deltas only | Billboard sprites, no animation | Statistical approximation |
| **Distant** | +5-10 zones | Aggregate stats only | Cluster glows with count badge | None |
| **Dormant** | Beyond 10 zones | Nothing (unsubscribed) | Nothing | Nothing |

## Billboard Rendering
- **Nearby:** Single-frame sprite (idle frame). Correct species/color. Updated on major delta.
- **Distant:** Cluster sprites. "Cat cluster" glow with count badge. Color temperature = warmth/happiness.
- Transitions use fade. Approaching Active boundary: gradually gains animation. Leaving: gradually simplifies.

## Server-Side
Server runs full sim for all zones. Bandwidth managed via subscription — only sends what client subscribed to. Client sends subscription update when camera moves:
```
{action: "subscribe", zones: [3, 4, 5, 6, 7], tier: "active"}
{action: "subscribe", zones: [1, 2, 8, 9], tier: "nearby"}
```

## Wandering Cats Across Boundaries
Cosmetic on receiving client. Real entities on server with authoritative positions. Receiving client follows position deltas, doesn't simulate AI. Exit subscribed zones = disappear. No stuck state.

## Camera ownership
Camera position and zoom are set in `nodes/camera/camera_controller.gd` — the script attached to the `Camera2D` node. `GameClient` must not touch `$Camera.position` or `$Camera.zoom`; observed behavior is that `camera_controller`'s initialization wins and any changes from `game_client._ready()` silently have no effect. If the camera needs to react to game state (follow an entity, zoom on an event), that logic lives in `camera_controller.gd` and reads from state or signals; the controller is the single authority.

## Physical Layout

**Prototype:** 7 playable racks + 2 decorative half-racks, 42U per rack. Internal viewport 640×360. Floor strip ~40px below racks. Pixel scale: 7px/U (real-world proportioned). Full layout in `art-direction.md`.

Animals move on continuous coordinate plane. Player-placed objects snap to 1U grid. Interior view is view-only in prototype (not a placement grid).

### Interaction Radii

All distances in rack units, stored in `config/balance/spatial.json`:

| Interaction | Radius | Notes |
|---|---|---|
| Robot arm activation | 3U | Hazard paint marks this visually |
| Robot arm reach | 2U | |
| Heat radiation onto floor | 3U below Y=1 | Linear falloff |
| Object advertisement (default) | 5U | Per-object override in config |
| Animal-to-animal ambient | 2U | Nose boops, grooming, tail chase |
| Animal social awareness | 6U | Head-tracking, approach decisions |
| Ferret drag step | 1.5U | 4-8U per session |
| Ferret stash radius | 1U | |
| Furball bat distance | 3-6U | Random, ballistic arc |
| Sound full volume / max | 4U / 20U | Linear falloff between |
| Same spot (pile-on) | 0.5U | Body heat stacking |

Vertical access: see `navigation.md` for species traversal capabilities.

## Heat Propagation

**Sources:** Powered, connected servers. Heat value per server type in config.

**Pattern:** Diamond/cross from source — 3U up, 1U down, 3U left/right (centered on vertical center of source). Linear falloff per U.

**Cross-rack spillover:** Heat crosses rack boundaries into adjacent racks. Positive externality in multiplayer.

**Body heat:** Sleeping animals add heat to their slot. Stacks additively. Creates warmth feedback loop.

**Prototype:** No overheating. Heat is purely beneficial.
