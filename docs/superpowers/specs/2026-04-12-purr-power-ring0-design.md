# Purr-Power Ring 0 Design Spec

> **Note (2026-04-16):** Identifiers referenced in this document may be outdated.
> `species_filter` was never implemented and is removed. `cat_presence` → `reclamation`,
> `cat_seconds` → `tended_seconds`, `is_purring` → `is_satisfied`. Anchor rule and
> species-recipe schema live in `CLAUDE.md` ("Species Are Component Recipes") and
> `.claude/rules/modding.md` (Species Recipe Schema).

> **Status:** brainstormed 2026-04-12. Team-reviewed x2 (Mochi, Bramble, Parcel, Rumble, Pebble, Willow, Noodle). Fixes folded. Ready for implementation planning.

---

## The One Sentence

Contented cats purr near HUM receivers, HUM powers TUNA dispensers and the ARM, food keeps cats content, and the player arranges infrastructure and intervenes manually to keep the loop running.

---

## Design Commitments (non-negotiable)

1. **Purring is a pool with inertia.** The HUM battery is a reservoir. A cat standing up to eat does not cause a brownout. Single-cat events are invisible at the HUD level. Reserve recovers faster than it drains.
2. **Abundance over precarity.** An empty HUM means the system shuts down slowly and gracefully — lights dim, arm stops, but nothing is destroyed. Progress stalls; it does not regress.
3. **The robot never blames the cats.** All brownout narration blames the robot itself or unknown causes. Never "UNIT-C01 has failed to provide power."
4. **Every purring cat contributes equally.** No "main cat." Per-cat HUM contribution is never surfaced in the HUD.
5. **0% is reachable.** Drain slows approaching zero but does not asymptote. Full shutdown is possible. Recovery requires player action (petting or squeaking).
6. **The player always has a way out.** Petting fills the attention bar without HUM. The squeaky call works without HUM. These are the bootstrap mechanisms.

---

## Rack Layout

Racks are **10U** (10 slots). This is a change from the previous 42U spec. All references to 42U in rules, code, and docs need updating.

### Devices

| Device | Size | Role |
|---|---|---|
| HUM device | 6U | Receiver (gramophone) + battery (rotating quartz crystal), one physical unit |
| Server | 1U | Heat source (warmth) |
| Box | 2U | Comfort source, cat sits in it |
| TUNA dispenser | 1U | Drops tuna cans when button is pressed, requires HUM |
| Button | 1U | Tethered to dispenser by short cable, player clicks or ferret presses. Must be in the same rack as its dispenser (adjacent slot preferred but not required). |
| ARM | Floor object | Fixed placement, opens tuna cans that land nearby |

### Example Rack Configurations

**HUM rack (power generation):**
```
[HUM device  ] 6U
[Server      ] 1U  -- heat source
[Box         ] 2U  -- cat sits here, near server for warmth, near receiver for HUM
[Server      ] 1U  -- more warmth
```
Cat count: 1 (maybe 2 if stacking). Pure HUM generation, no food production.

**Food rack:**
```
[Server      ] 1U
[Box         ] 2U
[Server      ] 1U
[Box         ] 2U
[TUNA        ] 1U
[Button      ] 1U
[Server      ] 1U
[Box         ] 2U
```
Cat count: up to 3. No HUM generation — draws from global pool. Produces food.

**The spatial tension:** A HUM rack can't also have a dispenser+button (no room). Food racks are separate. Player decides which racks generate HUM and which produce food. More HUM racks = more power capacity but fewer cats = less generation. This tradeoff is non-obvious — the prototype's job is to find the sweet spot.

---

## Contentment Model

A cat is **content** (and purrs) when **3 of 4 bars** are above threshold:

| Bar | Source | Decay |
|---|---|---|
| **Warmth** | Proximity to powered server | Decays when away from heat |
| **Comfort** | Sitting in a box | Decays when not in a box |
| **Hunger** | Eating tuna | Decays over time (constant) |
| **Attention** | Player petting the cat | Decays over time (faster than hunger) |

### Key properties

- **3-of-4 rule.** A cat missing one bar can still purr. A fed, warm, comfortable cat purrs without petting. A petted, warm, comfortable cat purrs without food. This is the brownout escape: petting replaces food when HUM is down.
- **Attention decays faster than hunger.** Petting is the emergency path, not the efficient one. Feeding is faster and more permanent. An optimizer feeds; a panicking player pets; Willow pets because she loves them.
- **No "contentment" component.** Content is derived: count bars above threshold, >= 3 means purring. The `is_purring` flag is set during desire scatter as a batch column op.

---

## HUM System

### Harmonic Uptime Matrix (HUM)

The HUM is a global resource pool within a bay. All HUM devices contribute. All TUNA dispensers and ARMs draw from it.

### Generation

- Purring cats near a HUM receiver contribute charge.
- "Near" = within the receiver's radius. The radius is NOT shown to the player — the player learns it by observing which cats show the purr contribution visual (musical notes / vibration lines on the sprite).
- Multiple HUM devices: each has its own radius. Cats can only contribute to one receiver at a time (nearest).

### Storage

- The HUM battery (part of the 6U device) stores charge.
- Multiple HUM devices = larger total capacity.
- Stored as an integer in GameStateDB on a singleton facility entity.

### Drain

- **Idle:** lights and ambient hum drain a small constant amount per tick.
- **Actions:** each TUNA dispense and ARM can-opening costs a fixed amount.
- **Idle drain slows as reserve decreases.** The idle drain curve flattens approaching zero. This prevents instant death spirals but does NOT prevent reaching zero — it just takes longer. **Action costs (TUNA dispense, ARM open) are fixed and punch through regardless of reserve level.** This is how 0% stays reachable even with drain slowdown — a player who keeps pressing the button will drain the pool.

### HUM States and Feedback

| Reserve | Visual | Audio | Mechanical |
|---|---|---|---|
| 100% | Full brightness | Full ambient hum, purr chorus | ARM operates instantly |
| <100% | Single flicker, then slow dimming begins | Ambient hum slightly quieter | ARM slightly slower |
| <25% | Lights turn red | Background hum cuts off | ARM very slow |
| 0% | Dark / minimal emergency lighting | Silence except cat meows | ARM and TUNA inoperable |

- **Recovery is faster than drain.** When purring resumes, the visible "we're back" feedback lands within ~5 seconds.
- **Drain slowdown at low reserve** is a non-negotiable tuning shape, not a number to fiddle with. The system must self-stabilize enough to give the player time to react, but NOT enough to prevent reaching zero.

---

## Food Loop

```
Player/ferret presses button
    → TUNA dispenser drops sealed can onto floor (costs HUM)
    → If ARM is nearby, ARM opens can (costs HUM)
    → Opened can emits food smell (advertisement)
    → Hungry cat leaves box, walks to food
    → Cat eats, hunger bar fills
    → Cat walks back to box
    → Cat settles, purrs (if 3/4 bars met)
    → Empty can disappears after ~10 seconds
```

### Warning system (meow ladder)

When a cat's hunger drops below threshold and no food is available:

1. **Cat paces at the dispenser** and meows (diegetic audio warning)
2. **Multiple cats meowing** = chorus of alarm (escalating audio)
3. **Lights dim** as cats leave boxes to pace (visual warning — HUM dropping because cats stopped purring)
4. **Lights go red** at 25% reserve
5. **Silence** at 0% — no hum, no purring, just meows

The meow warning precedes the light warning. Audio-first, visual-second. The player who listens catches problems before they cascade.

**Meow cadence:** 1 pacing cat = one mew every ~4 seconds. 2-3 cats = overlapping at random offset (not synchronized). 4+ cats = aggregate meow bus (same layering pattern as purr aggregation — louder, denser, but not N individual voices). Pacing cats also show a visual exclamation badge on-sprite for deaf players.

**Squeak sound:** a short, bright chirp — rubber toy being squeezed. ~1-2kHz fundamental, 0.3s duration, slight pitch randomization per press. Warm, not shrill. Should feel like shaking a treat bag, not blowing a whistle.

---

## Player Verbs

| Verb | Input | Effect | Needs HUM? |
|---|---|---|---|
| **Place** | Click rack slot / floor | Position infrastructure | No |
| **Click button** | Click the TUNA button | Dispense a tuna can | Yes |
| **Pet** | Click a cat | Fill attention bar quickly | No |
| **Squeak** | Click a box/bed | Emit squeak, nearby cats head toward it | No |

- **Ferrets press the button** too — they are automation. Ferrets do not drag cans in Ring 0.
- **Petting is slower than clicking the button.** Feeding is the efficient path. Petting is the emergency path and the emotional path.
- **Squeaking is the 0% bootstrap.** When everything is dark and cats are pacing at the dispenser, the player squeaks a box near a HUM receiver. Cats return, settle, purr. HUM trickles back. Lights come on. Player can dispense again.

---

## Cat Behavior States (Ring 0)

| State | Trigger | Purring? | Movement |
|---|---|---|---|
| **CONTENT** | 3/4 bars above threshold, in box | Yes | None — sitting/sleeping in box |
| **HUNGRY** | Hunger below threshold | No | Walks to nearest dispenser |
| **PACING** | At dispenser, no food available | No | Paces near dispenser, meows |
| **EATING** | Food available nearby | No | At food, eating |
| **RETURNING** | Just ate or responding to squeak | No | Walking back toward a box |
| **SETTLING** | Arrived at box | No | Circling, kneading, curling up (anticipation beat — purr-start on CONTENT is the payoff) |
| **STARTLED** | Loud noise, sudden change | No | Brief freeze, then flee to box |

### Transition notes

- CONTENT → HUNGRY: hunger bar drops below threshold. Cat stands up, leaves box.
- HUNGRY → PACING: cat arrives at dispenser, no food. Meows. If no dispenser exists, cat wanders aimlessly and meows (functionally PACING without a location anchor).
- PACING → EATING: food appears (player/ferret pressed button, ARM opened can).
- EATING → RETURNING: hunger bar refilled. Cat heads back.
- RETURNING can be accelerated by squeak (click target box).
- SETTLING → CONTENT: takes a few seconds. The settling animation is the reward.
- Any state → CONTENT via petting: if petting fills attention and cat has 3/4 bars, cat purrs where it is (even if not in a box). Returns to box afterward.

---

## Backronyms

| Acronym | Expansion | Robot justification |
|---|---|---|
| **HUM** | Harmonic Uptime Matrix | "The 27Hz acoustic carrier wave produced by contented devices. Standard power conditioning." |
| **TUNA** | Tamper-sealed Utility Negotiation Asset | "Devices press the request button. I dispense. The ARM alters the seal. The devices... take something. I am calling this a negotiation." |
| **ARM** | Autonomous Retrieval Manipulator | "I am a manipulator. I retrieve things. I am autonomous. This name was not difficult." |

---

## HUM Device Visual

The HUM device is 6U tall, composed of:
- **Top: Receiver (gramophone shape).** A horn/bell that "collects" the purr vibrations. Warm-palette metal, slightly tarnished. Faces outward from the rack.
- **Bottom: Battery (rotating quartz crystal).** A large crystal floating and slowly rotating, glowing with HUM reserve level. Brighter = more charge. Dark = empty. The glow color follows the HUM state (normal warm → red at <25% → dark at 0%).

The crystal rotation speed could also indicate charge level (faster = more charge, stopped = empty).

**HUM device sound:** The device itself emits a warm resonant tone — the 27Hz carrier filtered up to be audible (~80-120Hz hum). Volume and richness scale with reserve level. At full charge: a gentle, warm hum. At empty: silence. This is the spatial anchor for the power system — a player walking past a HUM device can hear whether it's charged.

---

## Purr Contribution Visual

When a cat is purring AND within range of a HUM receiver, it shows an on-sprite visual indicator:
- Musical notes, gentle vibration lines, or a subtle glow
- Steady = contributing to HUM
- Absent = not contributing (too far from receiver, or not purring)

This is the ONLY way the player learns the receiver's radius. No drawn circle, no UI overlay. Pure observation.

This visual also serves as the accessibility backup for the audio purr channel (Pebble's requirement: every channel has a backup).

---

## Accessibility Requirements

Per Pebble's review — every feedback channel needs a non-audio, non-color backup:

| Channel | Primary | Backup |
|---|---|---|
| HUM level | Ambient hum volume | HUD bar with numeric %, glyph state, sparkline |
| Cat purring | Purr audio | On-sprite musical note indicator |
| Brownout | Dim lights | Desaturation + vignette + BROWNOUT glyph on HUD |
| Meow warning | Cat meow audio | Cats visibly pacing at dispenser + exclamation badge on sprite |
| Discovery moment | First flicker + sound | Guaranteed exaggerated first brownout (dim + glyph + pinned robot log) |
| HUM contribution | Purr volume from direction | On-sprite purr visual near receiver |

**First brownout ever** should be slightly exaggerated: brief dim + glyph flash + one-time pinned robot log. After first discovery, drop to subtle.

---

## Narrative Surfaces

### Robot narrator panel

A cracked CRT welded to the ARM base. Diegetic — not a floating UI overlay. Specifics:

- **Max visible lines:** 3 lines on the CRT surface at Z0, expanding to 8 at Z1.
- **Scroll behavior:** new entries push old ones up. Auto-scrolls. No player scroll needed at Z0.
- **History:** accessible via a button press (controller: select ARM, press Y). Opens a full-screen log overlay. Screen-reader accessible — log entries are programmatic text nodes, not rendered pixels.
- **Pin behavior:** first-ever brownout log is pinned (does not scroll away) until the player acknowledges it. All other logs auto-scroll normally.
- **Screen reader:** new log entries fire an accessibility announce event. No timing-based auto-dismiss — pinned logs stay until acknowledged.

### Robot log triggers (Ring 0)

| Event | Sample log |
|---|---|
| First cat settles | "UNIT-C01 has entered chassis. Audible output: 25-30Hz sustained hum. Classifying as healthy disk activity." |
| HUM charging | "Acoustic baseline strengthening. Power conditioning nominal." |
| First brownout | "ADVISORY: Acoustic baseline thinning. Reserve capacitors discharging. Investigating." |
| Deep brownout | "I am moving slowly. I do not know why the devices stopped humming. Please hum." |
| Cat leaves for food | "UNIT-C01 has departed chassis. Reason: unknown. Possible snack." |
| Cat returns | "UNIT-C01 has returned. Resuming monitoring." |
| Recovery | "Acoustic baseline restored. Logging this event as ROUTINE BROWNOUT, CAUSE: SNACK." |
| TUNA dispense | "Deploying negotiation asset. The devices have pressed the button." |
| ARM opens can | "Seal altered. Contents: reconfigured. Chemical plume detected." |
| First pet | "UNIT-C01 reporting anomalous external stimulus. Satisfaction metrics... improving? Logging as MANUAL CALIBRATION." |

### Voice rules

- **Status voice** (curt, timestamped): routine events, nominal states
- **First-person voice** (no timestamp, lowercase, gentle): only when reserve < 40%. The tonal shift IS the brownout tell.
- **Never name individual units during brownouts.** Attribution allowlist: SNACK, FIRMWARE UPDATE, SCHEDULED MAINTENANCE, UNKNOWN, COSMIC RAY, THERMAL RECALIBRATION. When multiple cats depart simultaneously, batch departure logs ("Multiple devices entering standby") rather than naming each one — prevents scapegoat identification through timing correlation.
- **Boot log:** first launch of a save prints a cold-start log the player reads at their own pace. Backstory delivery vehicle.

---

## Sound Design Notes (from Rumble's review)

- **Three silence states needed:** healthy-sleep silence (purr + ambient hum), brownout silence (meows only), empty-room silence (nothing). Code currently distinguishes zero.
- **Purr volume should track HUM reserve, not cat count.** Count feeds reserve; reserve drives mix. Otherwise a cat standing up dims the room instantly (breaks commitment #1).
- **sound_manager.gd needs decomposition** into: HumBus (reserve-driven parameters), PurrAggregator (counts + feeds bus), AmbientLayer, ArmAudio, DiagnosticPing.
- **Lullaby ping (Ring 2):** at 20% reserve, robot emits ~27Hz tone. Novel DSP — deferred past Ring 0.
- **Can-pop payoff:** ARM completion needs a two-layer sample: mechanical pop + warm hum tail. In scope for Ring 0 — it's the reward beat for the food loop closing.

### New audio assets required for Ring 0

| Asset | Description |
|---|---|
| `cat_meow_pacing_01.wav` | Hungry/demanding meow for PACING state |
| `squeak_toy_01.wav` | Rubber toy chirp for squeak verb (~1-2kHz, 0.3s) |
| `can_pop_01.wav` | Mechanical pop + warm hum tail for ARM can-opening |
| `hum_device_tone.wav` | Warm 80-120Hz resonance loop for HUM device |
| `cat_settle_01.wav` | Soft kneading/circling sounds for SETTLING state |
| `button_click_01.wav` | Satisfying mechanical click for TUNA button press |

---

## Implementation Dependencies

### What exists
- Desire system with signed advertisements (desires + aversions)
- Object advertisements and scoring
- Animal state machine (ambient + goal-directed)
- Heat grid propagation
- Sound manager with purr count proxy
- Mod loader and EntityDefRegistry
- Object-interactions scaffolding (ARM exists conceptually)

### What needs building
1. **HUM system** — facility-level component in GameStateDB, charge/drain math, tick insertion (Step 3b after scatter, before AI)
2. **Contentment derivation** — 3-of-4 bar check, `is_purring` flag as batch column op
3. **HUM device** — 6U placeable, receiver radius, battery visual
4. **TUNA dispenser + button** — 1U each, button interaction, can drop
5. **ARM power gate** — existing ARM checks HUM reserve before acting
6. **Lighting system** — CanvasModulate shader driven by HUM reserve
7. **HUD reserve bar** — numeric %, state glyph, brownout indicator
8. **Cat behavior states** — HUNGRY, PACING, EATING, RETURNING, SETTLING additions
9. **Petting verb** — click cat, fill attention bar
10. **Squeak verb** — click box, emit attraction, cats head toward it
11. **Robot narrator panel** — diegetic CRT, log display, pin/history
12. **Meow audio** — hunger-driven vocalization, escalating with count
13. **10U rack update** — constants, art references, grid math

### What's deferred (Ring 2+)
- Litter boxes / poop
- Ferret can-dragging
- Ferret stash with empty cans
- Draggable ARM
- Lullaby diagnostic ping DSP
- Multi-rack HUM topology (cables, attenuation)
- Kitten cable-unplugging
- Robot name-learning (UNIT-C01 → UNIT-MOCHI)
- Second discovery beat
- Noise dampening infrastructure

---

## Open Questions (for playtesting)

- **Battery capacity.** How many cat-seconds of reserve? Needs playtest.
- **Attention decay rate.** How fast does petting wear off? Must be faster than hunger decay but slow enough to be useful.
- **Receiver radius.** How many U? Visible only through cat behavior. Needs playtesting to find readable-but-not-trivial range.
- **ARM proximity radius.** How close must the ARM be to the dispenser? Determines floor layout.
- **Optimal rack count ratio.** How many HUM racks vs food racks? The prototype answers this.
- **Cat return speed.** How fast do cats walk back after eating? Affects HUM dip duration.
- **Drain curve shape.** Exact curve for drain slowdown approaching zero. Must prevent instant death spiral while allowing zero to be reachable.
- **TUNA dispense cost vs ARM open cost.** Are they equal? Is one cheaper?

---

## Related Rules

- `core-loop.md` — original Ring 0 design draft (predecessor to this spec)
- `animal-ai.md` — desire/aversion scoring, state machine
- `tick-architecture.md` — tick order, HUM update insertion point
- `narrative.md` — robot voice, naming conventions
- `sound-design.md` — purr-as-metric, silence states
- `signals.md` — event bus signals for HUM state changes
- `design-philosophy.md` — batch-first API, integers, pure core
