# Design Draft: Perception Channels

**Status:** draft, not yet implemented
**Author:** session 2026-05-02
**Triggered by:** Biscuit and Mittens stuck idle on rack-2 floor — too far from any box. Question raised: does it make sense for advertisements to carry distance at all?

---

## The conflation

Today, two things are wedged into a single field (`radius_px`) on every advertisement:

| Concept | What it answers | Lives where today |
|---|---|---|
| **Visibility (perception)** | Is the entity even aware this ad exists? | `radius_px` on each ad **+** a hardcoded `8 * SLOT_HEIGHT_PX = 64 px` spatial query in `DesireScatter` / `DesireResolver` |
| **Influence falloff** | If the entity is aware, how strong is the effect at distance? | Same `radius_px`, used in the `dist_factor` term |

`engine/desires/desire_resolver.gd:90-97` shows it directly: `radius_px` first hard-cuts to 0, then linearly scales the score from full-strength at distance 0 to zero at the radius edge.

This collapses two different domain questions:

- **"Can the cat *see* the box?"** — depends on the *animal*'s senses (sight, smell, hearing, social attention). Should be authored per-species, not per-ad.
- **"Does sitting *next to* the body-warm dog feel warmer than sitting one slot over?"** — depends on the *physics of the channel* (heat radiates intimately; smell drifts; sound carries). Per-ad makes sense here, but only for channels where physical proximity is genuinely the mechanic.

The bug surface today: a cat one rack from a box can't sense the box. That's wrong — boxes are visible from across the room. Conversely, body heat from a sleeping dog *should* fall off rapidly. Today's model treats both the same way.

---

## Worked examples (the design lives here)

These cases were the most useful tools for landing the rules. If you're skimming this doc, read this section in full before the rules.

### Cases by sensing modality

**The single rule everything below traces:** every channel has a carrier sense. Scoring is gated by `senses[carrier]`; scatter is gated by `senses[carrier]` AND `effect_radius_px`. No exceptions.

| Scenario | Receiver | Emitter ad(s) | Expected outcome | Why |
|---|---|---|---|---|
| **Cold cat 60 px from a powered server** | normal cat. `senses.sight: 186`, `senses.touch: 64`. `desires.warmth` low. | Server emits `warmth` (touch-carried, `effect_radius_px: 16`) and a small `comfort` (sight-carried — shelf-level, not a primary lure) | At 60 px: scoring passes (60 < senses.touch=64) → cat scores warmth as a goal and walks toward it. Scatter blocked (60 > effect_radius=16) → no warmth received yet. Cat arrives at ~12 px → both gates pass → scatter delivers warmth with falloff. | **Detection ≠ effect.** `senses.touch=64` is the cat's max range to detect warmth gradients (skin senses ambient temperature differences). `effect_radius_px=16` is how far the heat physically reaches. They're independently tunable — keeping touch wider than effect means cats can sense warmth from beyond touch contact and walk *toward* it. Without this distinction, wandering cats would never detect heat sources except by stumbling onto them. |
| **Truly deaf cat next to a buzzing PA speaker** (pure-auditory emitter) | `senses.hearing = 0` | `noise` (hearing, `effect_radius_px: 186`) — and *only* this ad; speaker is not visibly disruptive | Cat is completely unaffected — `desires.quiet` does not drop. | With hearing 0, both scoring and scatter are gated out. The auditory pathway doesn't exist; pretending the noise still "lands" would be a model bug. (Pure-auditory emitter chosen so the deaf-cat outcome isolates cleanly — see the multi-modal kitten row for the realistic case.) |
| **Hard-of-hearing cat next to the same speaker** | `senses.hearing = 32` | same | Cat receives noise within 32 px (binary in/out under the prototype rule). | The sense gate is binary — partial sensitivity (a multiplier on scatter strength) was considered and deferred (see Decided: "Soft falloff on the sense gate"). |
| **Hearing cat across the bay from the speaker** | `senses.hearing = 186` | same | Cat receives noise — `desires.quiet` drops and the cat may seek silence as a goal. | Both gates pass: in `effect_radius_px`, in `senses.hearing`. Scoring also enables noise as a planning input. |
| **Biscuit/Mittens on rack-2 floor, no box in arm's reach** | normal cat, `senses.sight: 186` | `safety`/`comfort` (sight-carried) on every box in the bay | Cats see all boxes in the bay, score the closest, walk to it. **They cannot see occupancy at distance** — if the closest box is full on arrival, the cat re-scores and tries the next, or sits nearby waiting. | The bug today: `radius_px: 24` on the box ad gated visibility too tightly. New model: scoring is gated by `senses.sight`, not the ad's reach. Cats see boxes (persistent visible structure), not vacancies (transient occupancy state). Resolution is on arrival, not at planning time. |
| **Old dog with poor sight** | `senses.sight: 32` | mixed bay (boxes, peers, interesting structure, visible distress) | Every visual channel dims past 32 px — boxes (`safety`/`comfort`), peers (`social`), interesting structure (`curiosity`), visible distress from a flailing kitten (`chaos`, depletes `peace`). | Vision is a *sense*, not a per-channel knob. Dimming `sight` dims every visual channel together — safety, comfort, social, curiosity, and visual aversions like chaos all clip together — without authoring N numbers. |
| **Bawling kitten — multi-modal chaos** | various cats | `noise` (hearing, 186) **+** `chaos` (sight, 96) | Blind cat: gets `noise` only (depletes `desires.quiet`). Deaf cat: gets `chaos` only (depletes `desires.peace`). Blind-deaf cat: undisturbed. Normal cat: both. | One ad per (channel, carrier sense). The registry maps each channel to its desire effect — `noise → quiet (deplete)` and `chaos → peace (deplete)`. Sensory partitioning falls out of the rules without a multi-modal schema. |
| **Cat tucked in a small box** | settled cat (bonded to box via `settled_in`) | `comfort` + `safety` ads on the box, `effect_slot: true` | Cat is at the box's anchor offset within the same slot as the box → slot lookup matches → cat receives full comfort + safety. No reliance on `effect_radius_px` or bond bypass. | Slot delivery handles the cat-in-box loop directly: whoever's *in* the slot gets full strength, regardless of pixel-level anchor offsets. The `settled_in` bond is still used by action-ad consumption (the `settle` action), but it does NOT participate in passive scatter. Earlier drafts routed scatter through a bond bypass to handle this case; slot delivery retired that overreach. |
| **Cat at the right edge of bay 0, comfort lure placed at left edge of bay 1** | normal cat at x=180 (right edge of bay 0). `senses.sight = 186`. | Adjacent bay has a `comfort` ad (sight, no `effect_radius_px`) at x=240 (just inside bay 1) | Cat's sight reaches x=180+186=366, comfortably covering x=240. Cat scores the lure, walks across the bay gap, may settle in the new bay. | The spatial query is centered on the *cat's* position with radius `BAY_WIDTH_PX`, not anchored to bay boundaries. Edge cats naturally see further into the neighbor than middle cats do — no migration-mode override needed. **This is the gameplay surface for inter-bay traffic:** players who want migration place lures near the boundaries of bays. Animals that can't sense the lure don't migrate; that's the rule, not a bug. |

### Anti-cases (what the rules do *not* allow you to author)

| Tempting but wrong | Why it's wrong | Right shape |
|---|---|---|
| `cat.perception.warmth = 64` | Mixes emitter physics (heat falloff) onto the receiver. A cat with `warmth = 0` would still get hot if it was inside an oven; a cat with `warmth = bay-wide` doesn't feel anything from across the bay because heat doesn't travel that far. | Drop `warmth` from senses entirely. Put `effect_radius_px: 16` on the *server's* ad. |
| `cat.perception.comfort = 32` for a near-sighted cat | Per-channel acuity duplicates the same eye limit across every visual channel. A near-sighted cat that suddenly has 32-px comfort but bay-wide social acuity is incoherent. | `cat.senses.sight = 32`. Every visual channel dims together. |
| Compose senses and effect_radius with `min` to get "effective range" | Treats two unrelated questions as if they were the same gate. The cat-far-from-server case breaks: `min(186, 16) = 16` says the cat can't even *see* the heater past 16 px. | Apply each gate to its own operation. Senses gate scoring; effect_radius gates scatter; senses *also* gate scatter for sense-carried channels. |
| One ad with `senses: ["sight", "hearing"]` for a kitten's bawl | Multi-sense single-ad doesn't model the partial-loss cases (deaf-but-seeing, blind-but-hearing). | Two ads: `noise` (hearing) + `chaos` (sight). Each gated independently. |
| Use `radius_px` for both visibility and falloff (today's shipped model) | Forces designers to pick a number that's *both* the perception cap *and* the falloff curve length. Boxes today have `radius_px: 24` because the falloff felt right — and that incidentally makes them invisible past 24 px. | Drop the visibility role entirely from the ad. Senses handle visibility; `effect_radius_px` is *only* the physics-of-emission curve. |

---

## Proposed model

Split into two independent concepts. Both are integers (game-value scale, no floats). They live on **different sides of the bus** AND gate **different operations**:

| Field | Side | Gates Scoring? | Gates Scatter? |
|---|---|---|---|
| `species.senses[sense]` | Receiver | **Yes** — every channel has a carrier sense, so this gate always applies. (Warmth's carrier is `touch` with short-range default — see Worked Examples.) | **Yes** — for the same reason. A deaf cat with `senses.hearing = 0` doesn't have noise scatter into its desires; a cat with `senses.touch = 8` doesn't receive distant warmth even if `effect_radius_px` would otherwise reach. |
| `ad.effect_radius_px` | Emitter | No — scoring uses sense range for distance falloff (travel cost), not the ad's effect radius. | **Yes** — passive scatter only delivers within physical reach. |

**Don't compose senses and effect_radius with `min`** — they live on different sides of the bus and answer different questions. The Worked Examples table above traces specific cases through the rules; below is the schema each row exercises.

### 1. Per-species per-sense **acuity** (receiver side)

Add a `senses` block to species recipes. The receiver describes *what its senses can do*, not what each individual channel does — a near-sighted dog has poor *sight*, so it can't see boxes, peers, or structure equally. Per-channel acuity would duplicate the same underlying limit across every visual channel and force the spec drift the user pushed back on.

```jsonc
// mods/tcp_cats/species/cat.jsonc
"senses": {
  "sight":   186,  // good vision: sees anything visual across the bay
  "hearing": 186,  // sharp ears for kitten thunderstorms, distant brawls
  "smell":   186   // notices scent across the bay
}
```

Each ad declares which sense carries it. **The carrier sense IS the emission type** — there is no separate "what kind of thing is being emitted" concept. A noise emission travels via hearing; that's the same fact, named once. The channel→sense table lives in code:

| Channel | Carrier sense | Notes |
|---|---|---|
| `comfort`, `curiosity`, `social`, `safety`, `chaos`, `startle`, `hostility` | `sight` | Visual cues — boxes, peers, structure, visible distress, sudden movement, hissing/territorial displays |
| `noise` | `hearing` | Sound emissions |
| `food`, `stench` | `smell` | Scent — long-range sense for cats, dogs |
| `warmth`, `chill` | `touch` | Felt by skin/proximity. Short-range default (cats: `senses.touch ≈ 16`). |

Effective scoring perception for an ad = `species.senses[ad.sense]`. Every channel has a carrier sense — no exceptions. Add new senses (`vibration`, `taste`, etc.) if a future channel genuinely needs one.

- Entity-level field on a dedicated `senses` component. (The hot-path cost is handled by entity-first scatter iteration — see Decided: "Senses component placement.")
- **Default cap:** `Constants.BAY_WIDTH_PX = 186 px` (one bay). This is the prototype default — a deliberate game-design line that *bays are ecosystem boundaries*. It's a policy, not a physical law: specific behaviors (notably **migration** — an entity near a bay edge occasionally considers the next bay over) are explicitly allowed to use a wider scoring radius. The default just keeps day-to-day desire scoring scoped to one bay.
- **Default for an undeclared sense:** `BAY_WIDTH_PX`. Species opt into *short-range* sensing, never into long-range.
- This **replaces** the hardcoded 8-RU spatial query in `DesireResolver._evaluate_one` and `DesireScatter`. The new query is bounded by `BAY_WIDTH_PX` (3× wider than today, still bounded), and per-sense clipping happens after the spatial query returns the candidate set.

Different species declare different sensory profiles. An old dog with `sight: 32` is near-sighted on *every* visual channel — boxes, peers, structure are all dim past 32 px. A near-deaf hamster with `hearing: 16` reacts to noise only at contact range. The diversity comes from senses, not from per-channel gating.

**Detection range ≠ effect range.** `senses[carrier]` is how far the cat can *detect* a signal on this sense (perception/scoring). `effect_radius_px` (next section) is how far the emission *physically reaches* (scatter). These are independent and intentionally so. Body heat is the canonical case: cat skin can detect ambient temperature differences from ~64 px away (`senses.touch ≈ 64`), but a 1U server only physically warms a ~16 px radius (`effect_radius_px: 16`). The cat senses the gradient and walks toward warmth from outside the warming zone — without this gap, cats would only ever discover heat by accidentally stumbling into the 16 px effect zone.

### 2. Per-ad delivery: **radius** (geometric) or **slot** (structural)

Every passive-scatter ad chooses one of two delivery modes. They're mutually exclusive — exactly one must be specified.

**Radius delivery — for physical effects with real spatial extent.** Heat, sound, scent, body heat, anything that genuinely radiates and falls off with distance.

| Knob | What it controls | Required? |
|---|---|---|
| `strength` | Source intensity at `distance = 0` | **Yes** |
| `falloff` | Curve shape of decay with distance | Default: `quadratic`. |
| `effect_radius_px` | Hard cutoff: distance beyond which strength = 0. Also bounds the spatial query. | **Yes** for radius delivery |

```jsonc
// Buzzer ad: emits noise (carrier hearing). The registry maps noise → quiet (deplete);
// no per-ad effect field. Scatter depletes the cat's desires.quiet within radius.
{ "channel": "noise", "strength": 700, "effect_radius_px": 186, "falloff": "quadratic" }
```

**Default `falloff` is `quadratic`** (effective intensity = `strength × (1 - distance/effect_radius_px)²`), not linear. A 700-strength buzzer at distance 150 (radius 186) under quadratic produces ~26 effective — barely perturbs. Under linear, it'd be 135 — too much. **A buzzer across the bay should not bother a cat unless the buzzer is *really really loud* (high strength).** Quadratic encodes that. Other curves: `step` (hard cut), `linear` (old shape), `inverse_square` (physical realism, hard to tune). Cap: `BAY_WIDTH_PX`.

**Slot delivery — for structural effects that apply to whoever's *in* this thing.** Boxes, beds, tubes, cat towers, raised platforms — anything where the effect logically belongs to a slot occupant rather than to a radius around a position.

| Knob | What it controls | Required? |
|---|---|---|
| `strength` | Effect intensity. Full strength to slot occupants; zero to everyone else. | **Yes** |
| `effect_slot` | `true` selects this delivery mode | **Yes** for slot delivery |

```jsonc
// A box: safety + a small comfort, both slot-delivered. Registry handles effect direction.
{ "channel": "safety",  "strength": 800, "effect_slot": true }
{ "channel": "comfort", "strength": 200, "effect_slot": true }
```

Slot delivery sidesteps the entire pixel-tuning question. A box doesn't need `effect_radius_px: 8` (and to hope the falloff doesn't leak into adjacent slots). The cat *in* the slot gets full strength; the cat in the next slot gets nothing, regardless of how the slots are sized. No leak risk, no per-object tuning.

Implementation: scatter for slot-delivery ads queries `bay_local_to_slot(bay, world_pos)` (`engine/core/constants.gd`) for entities at the ad owner's slot rather than running a radial query. The `bay` argument is required — the helper is bay-scoped, so two entities at the same `(rack, slot)` in different bays don't collide.

**Validator rule:** an ad with `effect_slot: true` whose owner is not in a slot (e.g., a free-floating robot returning `&"floor"` or `&"other"` from `bay_local_to_slot`) is rejected at mod load. Slot-delivered ads only make sense on slot-anchored entities; there is no fallback to radius delivery.

Other rules (both modes):
- If neither delivery mode is specified, the ad has no passive scatter at all — the effect only lands via direct action consumption (e.g., `settle` action, `eat` action). These are *action ads*, gated by Bonds (see below).
- `strength` lives in 0–1000 like all game values.

### Bonds (and why they're not in scatter)

Bonds (`engine/core/bonds.gd`) capture entity-to-host action relationships: "this cat is currently settled in this box." Bonds gate **action-ad consumption** — the cat is allowed to receive the box's `settle` action effect because it's bonded to the box. Action ads are a different pipeline from passive scatter.

**Earlier drafts of this spec routed passive scatter through a "bond bypass" rule** so that a tucked-in cat received a small box's safety/comfort even if `effect_radius_px` was tighter than the cat's anchor offset. That was overreach. With slot delivery as a first-class mode, the box's safety/comfort ads use `effect_slot: true` and the cat-in-box loop just works — no bypass needed. Bonds revert to their original action-consumption role and stay out of the scatter pipeline.

### 3. Channel → desire mapping (the aversion rule)

Channel names describe *what's being emitted* (the emitter's perspective). Desire names describe *what's being affected on the receiver* (the cat's perspective). For some channels these align (a server emits `warmth`, the cat desires `warmth`); for others they don't (a robot-arm sudden movement emits `startle`, the cat's `safety` is depleted). TCP has no predators (CLAUDE.md "no adversarial relationships") — depleters are things like the robot arm doing a sudden sweep, a kitten thunderstorm, or a PDU buzzing. The mapping table records both the carrier sense (for sense-gating) and the desire-side effect:

```gdscript
# Constants.gd or a registry module
const CHANNELS: Dictionary = {
    # Attractors — channel name and desire align (overlap is fine when natural)
    &"warmth":    { &"sense": &"touch",   &"desire": &"warmth",    &"effect": &"satisfy" },
    &"comfort":   { &"sense": &"sight",   &"desire": &"comfort",   &"effect": &"satisfy" },
    &"safety":    { &"sense": &"sight",   &"desire": &"safety",    &"effect": &"satisfy" },
    &"food":      { &"sense": &"smell",   &"desire": &"food",      &"effect": &"satisfy" },
    &"social":    { &"sense": &"sight",   &"desire": &"social",    &"effect": &"satisfy" },
    &"curiosity": { &"sense": &"sight",   &"desire": &"curiosity", &"effect": &"satisfy" },

    # Aversions — six depleters mirroring the six attractors
    &"chill":     { &"sense": &"touch",   &"desire": &"warmth",    &"effect": &"deplete" },  # AC vents, cold drafts
    &"chaos":     { &"sense": &"sight",   &"desire": &"peace",     &"effect": &"deplete" },  # flailing kittens, falling stuff (depletes a dedicated visual-rest desire)
    &"startle":   { &"sense": &"sight",   &"desire": &"safety",    &"effect": &"deplete" },  # robot-arm sudden sweeps, surprise drops
    &"stench":    { &"sense": &"smell",   &"desire": &"food",      &"effect": &"deplete" },  # spoiled tuna, dirty litter
    &"hostility": { &"sense": &"sight",   &"desire": &"social",    &"effect": &"deplete" },  # hissing, snubbing, territorial displays
    &"noise":     { &"sense": &"hearing", &"desire": &"quiet",     &"effect": &"deplete" },  # buzzers, fans, kitten thunderstorms (depletes a dedicated auditory-rest desire)
}
```

(A future channel like `interest → novelty (satisfy)` would also fit the attractor-with-different-names pattern; TCP today uses `curiosity` for both because the names happened to overlap naturally. Both shapes are valid.)

Each ad declares only its channel — the effect direction is fixed by the registry, not per-ad. This keeps the world predictable: `startle` always depletes safety, `warmth` always satisfies warmth, no per-ad sign-flipping.

```jsonc
// Box: safety + a small comfort, slot-delivered
{ "channel": "safety",  "strength": 800, "effect_slot": true }
{ "channel": "comfort", "strength": 200, "effect_slot": true }

// Buzzer: noise emission, radius-delivered
{ "channel": "noise",   "strength": 700, "effect_radius_px": 186 }

// Robot arm sudden sweep: startle emission, radius-delivered
{ "channel": "startle", "strength": 800, "effect_radius_px": 96 }
```

**Scatter** (looks up the registry):
- `effect == satisfy` → `desires[CHANNELS[ad.channel].desire] += strength × falloff`, clamped to 1000.
- `effect == deplete` → `desires[CHANNELS[ad.channel].desire] -= strength × falloff`, clamped at 0.

**Scoring** (looks up the registry):
- `satisfy` channels contribute positively. Deficit term applies (`1000 - desires[target]`) — a cat with full safety doesn't seek more safety.
- `deplete` channels contribute negatively. No deficit term — a cat avoids danger regardless of current safety level.

```gdscript
# desire_resolver.gd — score one ad
var meta: Dictionary = Constants.CHANNELS[ad[&"channel"]]
var target: StringName = meta[&"desire"]
var weight: int = desire_weights.get(target, 500)               # always positive
var dist_factor: int = ...                                       # travel-cost falloff over sense range
var contribution: int
if meta[&"effect"] == &"satisfy":
    var deficit: int = 1000 - desires[target]
    contribution = weight * ad[&"strength"] / 1000 * deficit / 1000 * dist_factor / 1000
else:  # deplete
    contribution = -1 * weight * ad[&"strength"] / 1000 * dist_factor / 1000
```

Cat personalities have `desire_weights` (all positive — "how much I value each desire"). The signed-weight encoding from today's `animal-ai.md` is deprecated. **The paired animal-ai.md "Aversions" rewrite is drafted in this branch** (in `.claude/rules/animal-ai.md`) and lands with PR2 of the migration. The doc and code must ship together — committing PR2 means committing both files.

Species-specific reactions (ferret loves novelty, old cat hates it) are handled by `desire_weights`, not by sign-flipping. `curiosity` is always an attractor channel; ferrets weight it heavily, old cats weight it near 0. A satisfy ad on `curiosity` only meaningfully scores for entities that weight curiosity above some threshold.

Naming notes — some emitter-side channel names are content-tuning concerns, not architectural:
- The six aversion pairs are: `chill → warmth`, `chaos → peace`, `startle → safety`, `stench → food`, `hostility → social`, `noise → quiet`. Three deplete a positive attractor desire (warmth, safety, food, social — "the world is hurting what I want"); two deplete dedicated rest desires (`peace`, `quiet` — "the world is too busy"). The pattern is content-tunable; designers can mix.
- Channel/desire name overlap (warmth/warmth, comfort/comfort) is fine when there's no natural distinction. Don't force different names just to be different — that creates noise.
- The architecture supports any pair; specific names are content-tuning concerns, not architectural ones.

### What changes in the resolver

```gdscript
# desire_resolver.gd — gates scoring on the receiver's sense acuity
func _evaluate_one(entity_id: int, ...) -> void:
    # Settled entities still early-return (today's behavior; not driven by bonds-in-scatter).
    if _db.has_field(entity_id, &"action_state", &"settled_in"):
        return
    var pos := _db.get_component(entity_id, &"position")
    var senses := _db.get_component(entity_id, &"senses")
    var nearby: Array[int] = _db.query_radius_with(
        pos[&"x"], pos[&"y"], Constants.BAY_WIDTH_PX, &"advertisements",
    )
    for ad_id in nearby:
        var ad := _db.get_component(ad_id, &"advertisement")
        var dist := _manhattan(pos, ad_pos)
        var sense: StringName = Constants.CHANNELS[ad[&"channel"]][&"sense"]
        if dist > senses.get(sense, Constants.BAY_WIDTH_PX):
            continue                                                # outside this entity's acuity for the carrier sense
        # Distance term scales over sense range (travel cost preference).
        # NOT effect_radius — the cat plans to walk to the ad; the question is
        # "how far must I go," not "is the effect reaching me right now."
        var score := _score_advertisement(entity_id, ad_id, dist, senses)
        ...

# desire_scatter.gd — gates effect application on emitter physics.
# No bond carve-out: slot delivery (effect_slot: true) handles the cat-in-box case
# directly. Bonds gate action-ad consumption only; passive scatter doesn't read them.
func scatter_from_ads() -> void:
    # Slot-delivery ads: full strength to slot occupants, zero elsewhere.
    for ad_id in _db.get_entities_with(&"advertisement"):
        var ad := _db.get_component(ad_id, &"advertisement")
        if not ad.get(&"effect_slot", false):
            continue
        var owner_pos := _db.get_component(ad_owner_id(ad_id), &"position")
        var query: SlotQuery = Constants.bay_local_to_slot(owner_bay, owner_pos)
        if query.zone != &"slot":
            continue                                                # validator should have caught this at mod load
        for entity_id in _entities_at_slot(query.bay, query.rack, query.slot):
            _db.add_field(entity_id, &"desires", ad[&"channel"], ad[&"strength"])

    # Radius-delivery ads: entity-first iteration. Each entity reads its own
    # senses once per tick, then runs a broad-phase spatial query bounded by
    # its widest sense. The narrow-phase per-sense gate is applied per-ad
    # below — comfort (sight) is NOT treated as if it has smell's range just
    # because smell happened to be the broadest sense. The broad-phase bound
    # only avoids scanning ads that are too far for ANY sense.
    for entity_id in _db.get_entities_with(&"desires"):
        var senses := _db.get_component(entity_id, &"senses")
        var broad_phase_range: int = _max_sense_range(senses)
        var entity_pos := _db.get_component(entity_id, &"position")
        var nearby_ads := _db.query_radius_with(
            entity_pos.x, entity_pos.y, broad_phase_range, &"advertisement",
        )
        for ad_id in nearby_ads:
            var ad := _db.get_component(ad_id, &"advertisement")
            if not ad.has(&"effect_radius_px"):
                continue
            var ad_pos := _db.get_component(ad_owner_id(ad_id), &"position")
            var dist := _manhattan(entity_pos, ad_pos)
            var radius: int = ad[&"effect_radius_px"]
            if dist > radius:
                continue                                            # outside ad's physical reach
            var ad_sense: StringName = Constants.CHANNELS[ad[&"channel"]][&"sense"]
            # Narrow-phase per-sense gate. Default for an undeclared sense is
            # BAY_WIDTH_PX (a forgiving fallback for the bootstrap case;
            # script/checks/species_requires_senses lints for explicit declaration).
            if dist > senses.get(ad_sense, Constants.BAY_WIDTH_PX):
                continue
            var falloff_factor := _apply_falloff(dist, radius, ad.get(&"falloff", &"quadratic"))
            var delta := ad[&"strength"] * falloff_factor / 1000
            _db.add_field(entity_id, &"desires", ad[&"channel"], delta)
```

Two paths, two fields, two meanings. The Biscuit/Mittens bug is structurally impossible: with `cat.senses.sight` defaulting to `BAY_WIDTH_PX`, every box in the same bay enters scoring.

### Tick discipline

**Tick ordering:** scatter runs *before* scoring within each tick. Scoring's deficit term reads `desires[target]` — letting scatter write first means the deficit reflects the current scatter contribution, not last-tick's. Pin this in `tick_scheduler.gd` ordering and in a unit test.

**Server-only:** scatter is server-authoritative. Clients receive `desires` via state sync, never compute it locally.

**Settled early-return:** the resolver already early-returns on entities with `action_state == &"settled_in"` (preserving today's behavior). This is independent of the bonds system — the action state is checked directly. A cat tucked in a box continues to receive comfort/safety from the box via the slot-delivery scatter path; it just doesn't score new goals while settled.

## What this fixes

- **Biscuit/Mittens stuck idle** — boxes anywhere in their bay become visible to floor cats.
- **Food signaling within a bay** — open tuna at one end of the bay attracts cats at the other end without making body heat global.
- **Bays as ecosystems by default, with natural edge mixing** — the bay-width sense default means most ambient behavior scopes to one bay (a center-of-bay cat reaches only a thin sliver of the neighbor). Edge cats see further into the next bay because the radius is anchored on the *cat*, not the bay. **No migration-mode override** — if a player wants animals to flow between bays, they place lures (boxes, food, social signals) near the boundary. Animals that can't sense the lure don't migrate; that's the gameplay loop.
- **Species diversity via senses, not channels** — the species recipe declares one number per sense (sight/hearing/smell), not one number per channel. A near-sighted hamster has poor sight on *every* visual channel — boxes, peers, structure all dim together. A hawk-sighted ferret sees them all sharply. Authoring effort drops; semantic correctness goes up.
- **Spec/code clarity** — designers writing object configs stop guessing at radii. The default ("constant within sense range") is what most ads want; emitter-side falloff is opt-in for channels with real physics.

## The tradeoff (stay aware of this)

Removing per-ad falloff means a single high-`strength` attractor could become a magnet that pulls every animal of a sensing species. Two mitigations are already structural:

1. **Per-sense acuity preserves attractor diversity.** Species can be tuned blind, deaf, or anosmic on any channel-carrier sense. Body heat is bounded by emitter physics regardless. The map can have many simultaneous attractors of different shapes within a bay; cross-bay scoring is deliberately rare (migration only).
2. **Existing scoring math is multiplicative.** A box at `comfort: 600 strength` only beats a closer box at `comfort: 500 strength` if the deficit term agrees. Multiple boxes at parity scoring → nearest wins. Single boxes at runaway strength → designer error to flag.

The risk reduces to: *don't author one ad with strength 5× anything else on the same channel*. That's a content rule, not an architecture rule.

## Migration

**Day-1 reach delta (read first):** today's effective scoring reach is `min(8 RU = 64 px, ad.radius_px)`. Default-of-bay-wide on senses + dropping the hardcoded 8 RU cap pushes day-1 reach from `64 px` to `BAY_WIDTH_PX = 186 px` — a ~3× increase before any ad is re-tuned. Existing tests with distance assertions (boxes scoring 0 at "far," cats not seeing things "across the rack") will *change behavior, not just rename*. Plan for re-tuning, not just s/// search-replace.

Mechanical:
- `mods/*/objects/**.jsonc`: rename `radius_px` → `effect_radius_px` in ad blocks. Remove the field where the intent was visibility, not falloff (most cases — comfort, curiosity, social). Keep it where physical proximity is the mechanic (warmth, food scent, noise) and tune it explicitly — the cap is `BAY_WIDTH_PX`.
- `mods/*/species/**.jsonc`: add `senses` block (sight / hearing / smell). Bootstrap defaults to bay-wide on every sense so behavior matches "remove all radii within a bay" baseline; tune down per sense to introduce species differences.
- Channel registry (`Constants.CHANNELS`) lives in code. Every channel declares `{sense, desire, effect}`. Adding a channel without these fields is a content error and is caught by `script/checks/channels_complete`.
- `engine/desires/desire_resolver.gd`: gate scoring on `senses[CHANNELS[channel].sense]` instead of `radius_px`. Distance falloff in scoring scales over sense range (travel-cost preference), not effect_radius.
- `engine/desires/desire_scatter.gd`: split into two passes — slot-delivery pass and radius-delivery pass. Replace the hardcoded `8 * SLOT_HEIGHT_PX` spatial bound with `Constants.BAY_WIDTH_PX`.
- **Schema version bump.** Object and species schemas change shape (`radius_px` → `effect_radius_px`, new `senses` block, new `effect_slot` field). Bump `schema_version` per `modding.md` "Config Schema Versioning" and provide a one-shot auto-migrator for existing mods so authors with shipped content don't break silently on update.

Tests that need attention:
- `tests/integration/test_movement_smoke.gd` — should still pass, likely improve (settling test cat finds box from anywhere on the floor).
- `tests/unit/test_desire_resolver_*` — assertions that depend on `radius_px` gating need updating to use `senses` (scoring) + `effect_radius_px` (scatter) semantics.
- `tests/integration/test_cat_in_box_charges_hum.gd` — unaffected; HUM uses `purr.radius_px`, a separate physical channel from desire ads.
- `tests/unit/test_hum_system_emission_intersection.gd` — unaffected for the same reason.
- New: `tests/unit/test_sense_gating.gd` — pin the cases from the Worked Examples table:
  - Deaf cat (`senses.hearing = 0`) next to a pure-auditory emitter: noise scatter does **not** land (sense-gated). `desires.quiet` does not drop.
  - Cat far from a server (`warmth` ad, touch-carried, `effect_radius_px: 16`): does not receive heat at distance 100 — both gates fail (`senses.touch = 16` and `effect_radius_px = 16`).
  - Hearing cat across the bay from the kitten: receives noise (within effect_radius and within senses.hearing).
  - Multi-modal kitten emitting both `noise` (hearing) and `chaos` (sight): blind cat gets `noise` only (depletes quiet); deaf cat gets `chaos` only (depletes peace); blind-deaf cat gets neither.
  - Cat sitting at a box's anchor offset (~6 px from box center), box ad uses `effect_slot: true`: cat receives full strength via slot delivery, regardless of distance to the box's pixel center. Slot delivery is the cat-in-box mechanism — no bond bypass exists.

## Boundaries — what this is NOT

- **Not a vision/LOS system.** No raycasts, no line-of-sight blocking. A wall doesn't block scent or sound today and shouldn't here. Channels are abstract influence types, not literal sensory rays.
- **Not physics.** `effect_radius_px` doesn't propagate through grid cells. Heat propagation has its own pipeline (`heat_grid.propagate`); this design is only for the `advertisements` → `desires` coupling.
- **Not relationship-aware.** Familiar/stranger weighting (a cat reacting differently to its own kitten vs. an unknown ferret) lives in the `relationships` table, not on the senses block. Senses decide *whether* an ad is considered; the relationship table can later modulate the resulting score.
- **Not the audio mix.** Sense gating is on the sim side (does this cat's `desires.quiet` drop?). Audio playback is independent — the *player* hears the buzzer regardless of which cats are perceiving it. The audio system listens to ad-creation events on the event bus (per `signals.md`) and mounts an `AudioStreamPlayer2D` at the emitter's position, with its own attenuation curve decoupled from `effect_radius_px`.

## Open questions

1. ✓ **Migration of `radius_px` on existing ads — drop or rename to `effect_radius_px`?**
   Resolved: split into two PRs. PR1 adds `senses` + swaps the 8-RU spatial cap for `BAY_WIDTH_PX`, leaves `radius_px` in ads as-is — this alone fixes the Biscuit/Mittens bug. PR2 renames `radius_px` → `effect_radius_px` on the ~7 callsites in `engine/objects/object_state_manager.gd`, drops the field where intent was visibility (`comfort`, `social`, `curiosity`), keeps + re-tunes where physics matters (`warmth`, `food`, `noise`), adds `effect_slot` for boxes, and lands animal-ai.md aversion rewrite alongside.
2. ✓ **Channel taxonomy: is `comfort` doing too much work?**
   Resolved (deferred to ad-tuning pass): the registry already has `safety` and `comfort` as separate channels — this is a content-tuning question, not architectural. The lean is split: boxes are `safety: high, comfort: low` (den-shaped); cat beds are `comfort: high, safety: medium` (open-shaped); clothes piles add `warmth`; servers are `comfort: low (shelf-level), warmth: high`. Settle during the ad-tuning soak test once Ring 0 stabilizes, not in this spec.
3. ✓ **Mod-extensible channel registry?**
   Resolved (deferred to v2): ship `Constants.CHANNELS` as code-side `const Dictionary` for the prototype. The 12 channels cover everything `tcp_base` ships. Document the punt in `modding.md` so external mod authors know to file a request rather than fork `engine/`. Promote to a mod-loaded `ChannelRegistry` (parallel to `engine/mod/entity_def_registry.gd`) when a second mod actually needs a custom channel. Until v2, this means the namespace-collision question (next) is theoretical, not load-bearing.
4. ✓ **Channel name namespace collisions.**
   Resolved: last-mod-wins by `load_priority`, with a startup warning logged when a collision happens. Matches the rename-redirect pattern already in `modding.md`. Gives mod authors a deterministic override mechanism (a high-priority "rebalance" mod can intentionally redefine `&"comfort"` with different feel), and the warning surfaces the conflict for debugging. Theoretical until the v2 mod-extensible registry ships. Acknowledged that real-world conflicts may surface a sharper rule later — fix when it bites.

## Decided in this revision (no longer open)

These came up as questions and were resolved during spec iteration. Listed here for traceability:

- **Receiver-side desire naming for aversions.** Resolved: pair table (`CHANNELS` registry). Receivers track positive desires only (`desires.quiet` for auditory rest, `desires.peace` for visual rest, never `desires.noise` or `desires.chaos`). Aversion is encoded by the registry's `effect: deplete`, not by signed weights. Animal-ai.md's "Aversions (Signed Advertisements)" section needs a parallel rule update — land together.
- **Default falloff curve.** Resolved: `quadratic`. Linear was too gentle and made distant emitters disturb cats unrealistically. `step`, `linear`, `inverse_square` remain available per-ad.
- **Bay cap as policy or law.** Resolved: policy default. No migration-mode override. Sense radius is anchored on the entity, so edge cats already see into the neighbor; lures-at-bay-edges is the gameplay surface for inter-bay flow.
- **`intimate_radius_px` naming.** Resolved: renamed to `effect_radius_px` (more direct, less precious).
- **Sense vs emission type as separate concepts.** Resolved: same concept, named once. The carrier sense field IS the emission type.
- **Occupancy visibility at distance.** Resolved: invisible. Cats see the *box* (a persistent visible thing), not the *vacancy* (a transient state). They over-commit, walk to the closest scored box, and resolve on arrival. **Animal-ai.md's `ObjectAdvertisement.score_for()` `is_available()` check has to be removed from scoring** — it would gate full boxes out of the consideration set, which is omniscient under this perception model. The "soft occupancy" rule (cap reduces comfort proportionally as occupants accumulate) handles the actual capacity dynamic without the omniscience.
- **One spatial query at `BAY_WIDTH_PX`, or per-sense queries?** Resolved: one query at `BAY_WIDTH_PX`. Cheap and sufficient — the candidate set is bay-bounded. Per-sense gating happens after the query returns. Single-query wins.
- **Default `senses` for a freshly-spawned species without the block.** Resolved: lint rule (`script/checks/species_requires_senses`) enforces explicit declaration; bay-wide on every sense is the bootstrap fallback for save-load forward-compatibility only. Designers cannot rely on the fallback for new species.
- **Edge sensing and inter-bay flow.** Resolved: no override exists or is needed. Sense radius is anchored on the entity's position, so a cat at the right edge of bay 0 already queries ~140 px into bay 1. Inter-bay flow happens *iff* a lure is within sense reach of an animal in the adjacent bay. Genuine gameplay surface — promote to `modding.md` so layout authors discover it.
- **Multi-sensory channels.** Resolved (deferred): YAGNI for prototype. One carrier sense per channel today. The channel→sense map can later become channel→Array[sense] with `max(senses[s] for s in carriers)` if needed.
- **Signed-ad summing under the new model.** Resolved: spec sketch and shipped resolver code both use best-score. The `desires.noise = -600` signed-weight encoding documented in `animal-ai.md` does NOT match shipped behavior — that's a doc bug, fixed by the paired animal-ai.md "Aversions" rewrite. Sum-with-aversion semantics is its own future spec.
- **Bonds in the scatter pipeline.** Resolved: removed. With `effect_slot: true` as a first-class delivery mode, the cat-in-box loop is handled by slot delivery without any bond carve-out. Bonds gate action-ad consumption only and are invisible to passive scatter. Earlier drafts of this spec routed scatter through a bond bypass; that overreach is retired.
- **`effect_slot: true` on a free-floating entity.** Resolved: rejected at mod load by the validator. Slot delivery only makes sense on slot-anchored entities; there is no fallback to radius delivery.
- **Tick ordering.** Resolved: scatter runs before scoring within each tick. Pinned in `tick_scheduler.gd` and a unit test.
- **Multiplayer authority.** Resolved: scatter is server-authoritative. Clients receive `desires` via state sync, never compute it locally.
- **Senses component placement.** Resolved: `senses` stays its own component. Coupling it into `desires` for one fewer lookup confused two unrelated concepts. The hot-path concern is addressed by inverting the radius-delivery scatter loop (entity-first instead of ad-first), so each entity reads its own `senses` once per tick regardless of how many ads are nearby. See the scatter pseudocode in §"What changes in the resolver."
- **Soft falloff on the sense gate.** Resolved (deferred): keep the binary gate. Determinism wins — RNG-based noticing breaks save replay and multiplayer; deterministic strength multipliers stack two soft curves (sense-side + ad-side) and double the tuning burden. The existing `dist_factor` in scoring already gives "closer goals are preferred" softness. Revisit *only* if a narrow-sensed species (old dog with `sight: 32`, near-deaf hamster) shows visible flip-flop scoring at its sense boundary in playtest; if needed then, use Option 1 (deterministic multiplier), never RNG.

## Out of scope for this draft

- **Memory.** Several worked examples (cold cat finds heat, cat returns to a known box, "I've been zapped here before") implicitly assume an episodic memory system. Today's spec leans on **WANDERING** (per `animal-ai.md`) as the fallback when a cat's `desires.warmth` drops below threshold and no warmth ad is in `senses.touch` range. With the detection > effect gap (touch=64, effect_radius=16), wandering cats *do* eventually detect ambient warmth and walk toward it — better than blind random walk — but without memory they'll re-discover the same server every time their warmth drops. Memory is the natural successor.
- **Per-individual desire targets / satisfaction thresholds.** A cat sitting *near* a server gets partial warmth (e.g., 400) via falloff. A cat sitting *on* it gets full warmth (e.g., 800). What stops the near-cat from being satisfied with 400 and never moving closer? The hysteresis thresholds in `animal-ai.md` (activation/deactivation per channel) — and ideally per-cat personality knobs (`warmth_target = 600` for an easygoing cat, `1000` for a perfectionist). This spec doesn't define those thresholds; it assumes they exist and are tuned in `config/balance/desire_thresholds.json`. The interaction is: with detection > effect, cats *can* find heat; with proper thresholds, they bother to move close enough to actually be satisfied. Both pieces are required for cats to settle on heat sources rather than near them.
- **Per-individual sense variation** (one near-sighted cat in a litter). Possible via per-entity `senses` overrides at spawn; not load-bearing for the initial cut.
