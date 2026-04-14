# Art Asset Tracker

Living list of all sprite/animation assets — what exists, what's needed, and what's placeholder. See `.claude/rules/asset-pipeline.md` for naming conventions, format specs, and directory structure.

---

## Existing Assets

### Cats (5 variants: cat01-05)

All at 32x32. Strip format: `cat{NN}_{action}_strip{N}.png`

| Animation | Frames | Status | Notes |
|---|---|---|---|
| idle | 8 | Done | |
| idle_blink | 8 | Done | |
| sit | 8 | Done | |
| liedown | 24 | Done | Full lying-down sequence |
| crouch | 8 | Done | |
| fright | 8 | Done | Startled reaction |
| run | 4 | Done | |
| sneak | 8 | Done | |
| jump | 4 | Done | |
| land | 2 | Done | |
| fall | 3 | Done | |
| wallclimb | 8 | Done | |
| wallgrab | 8 | Done | |
| dash | 9 | Done | |
| attack | 7 | Done | |
| hurt | 4 | Done | |
| die | 8 | Done | |

### Kittens (5 variants: kitten01-05)

All at 32x32. Strip format: `kitten{NN}_{action}_strip{N}.png`

Same animation set as cats (idle, idle_blink, sit, liedown, crouch, run, sneak, jump, land, fall, wallclimb, wallgrab, dash, attack, hurt, die).

### Ferrets (1 variant: lilotter)

Mix of 32x16 and 32x32. Strip format: `lilotter_{action}_strip{N}.png`

| Animation | Frames | Status | Notes |
|---|---|---|---|
| idle | 8 | Done | |
| idle_blink | 8 | Done | |
| sit | 8 | Done | |
| liedown | 8 | Done | Limp/flat |
| sleep | 4 | Done | Sprawled sleeping |
| walk | 8 | Done | |
| run | 4 | Done | |
| sneak | 4 | Done | |
| jump | 5 | Done | |
| land | 3 | Done | |
| fall | 1 | Done | |
| crouch | 8 | Done | |
| wallclimb | 4 | Done | |
| wallgrab | 8 | Done | |
| dash | 10 | Done | |
| attack | 7 | Done | |
| hurt | 5 | Done | |
| die | 8 | Done | |
| swim | 4 | Done | |
| swim_idle | 4 | Done | |

### Infrastructure

| Asset | File | Status |
|---|---|---|
| Rack frame | `infrastructure/rack/rack_frame.png` | Done |
| Rack slot empty | `infrastructure/rack/rack_slot_empty.png` | Done |
| Rack slot highlight | `infrastructure/rack/rack_slot_highlight.png` | Done |
| Rack slot deny | `infrastructure/rack/rack_slot_deny.png` | Done |
| Server 2U off | `infrastructure/server/server_1u_off.png` | Done |
| Server 2U on | `infrastructure/server/server_1u_on.png` | Done |

### Objects

| Asset | File | Status |
|---|---|---|
| Cardboard box (new) | `objects/box_cardboard_new.png` | Done |
| Cardboard box (front) | `objects/box_cardboard_front.png` | Done |
| Cardboard box (back) | `objects/box_cardboard_back.png` | Done |
| Clothes pile | `objects/pile_clothes.png` | Done |
| Clothes pile (front) | `objects/pile_clothes_front.png` | Done |
| Clothes pile (back) | `objects/pile_clothes_back.png` | Done |
| Tuna can sealed | `objects/tuna_can_sealed.png` | Done |
| Tuna can open | `objects/tuna_can_open.png` | Done |
| Furball | `objects/furball.png` | Done |
| Feather | `objects/feather.png` | Done |
| Desk fan | `objects/fan_desk.png` | Done |
| Bedding scraps | `objects/bedding_scraps.png` | Done |

### Environment

| Asset | File | Status |
|---|---|---|
| Floor tile | `environment/floor_tile.png` | Done |

---

## Needed Assets

### Resting-On Feature (Ring 1)

| # | Asset | Species | Frames | Size | Priority | Description |
|---|---|---|---|---|---|---|
| 1 | `ferret_curl` | Ferret | 1-2 | 32x16 | **High** | Tucked, content curl. Nose tucked into tail. Compact ball shape. Distinct from sprawled `sleep` and limp `liedown`. The "cinnamon roll" pose. Reusable on any surface (cat, server, clothes pile). **V1 placeholder:** existing `sleep` strip. |
| 2 | `ferret_climb_on` | Ferret | 2-3 | 32x16 | **High** | One-shot: body elongates ~2px vertically, front paws reach up onto surface, body follows. 6 FPS. Without this, ferret teleports onto cat and looks like a rendering bug. **V1 placeholder:** position tween using walk frames. |
| 3 | `cat_liedown_weighted` | Cat (x5) | 1-2 each | 32x32 | **Medium** | Subtle liedown variant: slightly flatter loaf, ears tilted ~5 degrees back. Reads as "something small is on my back." Could be single-frame swap. Ship cat01 first. **V1 placeholder:** existing `liedown` (cat shows no reaction). |
| 4 | `kitten_curl` | Kitten (x5) | 1 each | 32x32 | **Medium** | Tiny tucked ball. Rounder/smaller than ferret curl. May be extractable from last frame of `liedown_strip24`. **V1 placeholder:** existing `liedown` last frame. |
| 5 | `cat_mrrp_react` | Cat (x5) | 2 each | 32x32 | **Low** | Ears perk, slight head lift, settle back. The "oh, hello" reaction when ferret lands. 6 FPS one-shot. **V1 placeholder:** none (cat is oblivious). |
| 6 | `ferret_startled_drop` | Ferret | 1 | 32x16 | **Low** | Legs splayed mid-air, surprised expression. Comedy frame for falling off cat. **V1 placeholder:** existing animation + downward tween. |

### Ambient Behavior Animations (Ring 0)

Dedicated animations for ambient states. Currently using existing animations as placeholders.

| # | Asset | Species | Frames | Size | Priority | Description |
|---|---|---|---|---|---|---|
| A1 | `cat_stretch` | Cat (x5) | 3-4 | 32x32 | **Medium** | One-shot: body elongates, front paws extend, yawn. After sleeping. **V1 placeholder:** `idle`. |
| A2 | `cat_knead` | Cat (x5) | 3-4 | 32x32 | **Medium** | Loop: alternating paw press on surface, eyes half-closed. **V1 placeholder:** `sit`. |
| A3 | `cat_tail_flick` | Cat (x5) | 4 | 32x32 | **Low** | Loop: body still, tail tip moves side to side. **V1 placeholder:** `idle`. |
| A4 | `ferret_wardance` | Ferret | 6 | 32x32 | **Low** | Arched back, sideways hopping, mouth open. The excited ferret hop. **V1 placeholder:** `dash`. |
| A5 | `zzz_particle` | — | 3 | 8x8 | **Low** | Floating Z's above sleeping animals. Procedural position. |
| A6 | `heart_particle` | — | 3 | 8x8 | **Low** | Floating hearts for content animals near companions. |

### Prototype Gaps (from asset-pipeline.md spec)

Assets listed in the pipeline spec's "Must-Have" list that don't exist yet:

| # | Asset | Frames | Size | Priority | Description |
|---|---|---|---|---|---|
| 7 | Robot arm base | 1 | 32x32 | **High** | Static base mount |
| 8 | Robot arm segment | 1 | 8x48 | **High** | Reusable limb piece |
| 9 | Robot arm claw (open/closed) | 1 each | 16x16 | **High** | |
| 10 | HUD drawer frame | 1 | 192x48 | **Medium** | |
| 11 | HUD drawer backgrounds (x4) | 1 each | 192x48 | **Medium** | Kitties, cable, infra, utility |
| 12 | HUD drawer paw poke | 3 | 32x16 | **Medium** | Iconic kitten paw |
| 13 | HUD bar segment + icons | 1 + 6 | various | **Medium** | |
| 14 | Cooling pipe (h/v) | 1 each | 64x8 / 8x64 | **Low** | |
| 15 | Pipe condensation | 3 | 8x16 | **Low** | Droplet forming + falling |
| 16 | Cable segments (ethernet/power) | 1 each | various | **Low** | |
| 17 | Heat shimmer effect | — | — | **Low** | Shader, not hand-drawn |
| 18 | Heart / zzz / particles | 1 each | various | **Low** | |
| 19 | Wall background | 1 | tileable | **Low** | |
| 20 | Moss overlay | 1 | tileable | **Low** | |
