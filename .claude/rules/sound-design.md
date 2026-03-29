---
paths:
  - "**/*.ogg"
  - "mods/tcp_base/sounds/**"
  - "mods/tcp_base/config/**"
---

# TCP Sound Design Spec — Rumble's Proposals

Six proposals to fill the gaps in the sound system section of PLANNING.md. Each is self-contained. All parameter values belong in `mods/tcp_base/config/*.json` and are tunable per the project's "every number in overridable JSON" rule.

---

## 1. Mixing Strategy

### Frequency Band Allocation

The mix is carved into four bands. Each band has a primary owner; secondary sources are sidechain-compressed against the owner so the owner always wins clarity.

| Band | Range | Primary Owner | Secondary Sources |
|---|---|---|---|
| Sub-bass | 20-80 Hz | Server fan hum (fundamental) | Body heat rumble (future), building settling |
| Low-mid | 80-300 Hz | Cat purring (fundamental at 80-120 Hz, first overtone at 160-240 Hz) | Ferret churring, robot arm servo |
| Mid | 300-2000 Hz | Animal vocalizations (mews, chirps, dooks, squeaks), robot arm mechanical sequences | Cardboard bonks, can scraping, tube scrabbling |
| High / Air | 2000-16000 Hz | UI feedback, placement confirmations, feather flutter | Cooling pipe drips, furball fwips, claw taps on tile |

**Why these divisions:** Purring sits in the low-mid because that is the game's heartbeat. It must never be masked by infrastructure. Server hum sits below it — they coexist without competing because their fundamentals are a full octave apart. Vocalizations (the "something needs attention" channel) own the mid where human hearing is most sensitive.

### Dynamic Ducking Rules

Ducking is per-band, not global. Each rule has an attack time (how fast the duck kicks in), release time (how fast it fades back), and depth (max attenuation in dB).

| Trigger | Ducks | Attack | Release | Depth | Reason |
|---|---|---|---|---|---|
| Any animal vocalization (mew, chirp, dook, yowl) | Server fan hum, ambient purr layer | 50 ms | 400 ms | -6 dB | Vocalizations are information; they must cut through |
| Robot arm activation sequence | All ambient layers | 100 ms | 800 ms | -4 dB | The arm sequence is the most complex sound; give it space |
| Player places/picks up object | Ambient animal layer | 30 ms | 200 ms | -3 dB | Action feedback must feel immediate and crisp |
| Ferret discovery mini-event | Everything except the event's own sounds | 200 ms | 1200 ms | -5 dB | Scene dims visually; sound should narrow focus too |
| UI drawer open/close | Mid + High ambient | 40 ms | 300 ms | -4 dB | Drawer sounds are close/intimate; far sounds should recede |

### Voice Management

**Max simultaneous voices:** 32 (Godot's default is 32 `AudioStreamPlayer` nodes active; we match this).

**Voice budget allocation:**

| Category | Reserved Voices | Notes |
|---|---|---|
| UI / Player actions | 4 | Always available. Highest priority. |
| Robot arm | 3 | One per concurrent arm action. |
| Animal vocalizations (non-purr) | 8 | Individual mews, chirps, dooks. |
| Purr aggregate | 4 | See purr variation section below. Not one-per-cat. |
| Server / infrastructure hum | 3 | Pooled across all servers; they blend into one texture. |
| Environmental (drips, fan, furballs) | 4 | Ambient texture layer. |
| Spatial event sounds (can scrape, tube traverse, thuds) | 6 | Highest turnover category. |

**Total:** 32.

### Priority Culling

When a category exceeds its budget, voices are culled by priority score. Score = `base_priority + distance_penalty + recency_bonus`.

- `base_priority`: defined per sound type in config. Vocalizations = 100, spatial events = 70, ambient = 30.
- `distance_penalty`: -10 per rack-width of distance from camera center. Offscreen sounds cull first.
- `recency_bonus`: +20 if the sound started within the last 500 ms (prevents popping from immediate re-cull).

Lowest-scoring voice in the over-budget category is faded out over 80 ms (not hard-cut — hard cuts are audible and jarring) and its voice slot is freed.

---

## 2. Purr Variation from 2 Source Files

We have 2 purr recordings. We need 5 perceptually distinct purrs (one per cat model in the prototype). Here is how to get there without recording new audio.

### Source Material Assumptions

- `purr_A.ogg`: lower-pitched recording, rumbly character
- `purr_B.ogg`: slightly higher-pitched recording, breathier character
- Both are loopable or at least 10+ seconds with clean loop points

### The 5 Variants

| Cat Model | Source | Pitch Shift (semitones) | Playback Speed | EQ / Filter | Character |
|---|---|---|---|---|---|
| Cat 1 (Momma) | purr_A | 0 (original) | 1.0x | Subtle low shelf boost at 60 Hz (+2 dB) | Deep, authoritative, the warmest purr in the room |
| Cat 2 | purr_A | +3 semitones | 1.0x (pitch-shift without time-stretch) | High-pass at 50 Hz to thin the sub | Lighter version of A; same timbre family but clearly higher |
| Cat 3 | purr_B | 0 (original) | 1.0x | None | The breathier, airier purr — distinct texture from A-family |
| Cat 4 | purr_B | -2 semitones | 0.92x (slight slow-down, adds weight) | Low-pass at 800 Hz, rolls off air | Heavier, sleepier, slightly slower rhythm — the "big lazy cat" |
| Cat 5 | purr_A + purr_B | A at +5 semitones, B at -3 semitones | A at 1.1x, B at 0.9x | Band-pass both: A gets 200-600 Hz, B gets 60-200 Hz | Layered hybrid: feels like a single complex purr with unusual harmonic richness. The "special" cat. |

### Parameter Ranges for Runtime Modulation

Each cat's purr is not static. It shifts with satisfaction level. These are continuous interpolations, not discrete steps.

| Parameter | Content (satisfaction > 700) | Neutral (400-700) | Uncomfortable (< 400) |
|---|---|---|---|
| Volume | 0 dB (full) | -6 dB | -14 dB (barely audible, then silent below 200) |
| Pitch offset | +0 cents | +15 cents | +30 to +50 cents (slight anxious rise) |
| Overtone presence (low-pass cutoff) | 2400 Hz (rich harmonics) | 1200 Hz (thinner) | 600 Hz (fundamental only, hollow) |
| Rhythm regularity | Steady loop, minimal variation | Occasional micro-pauses (50-100 ms gaps every 4-6 sec) | Irregular, frequent pauses, loop sounds broken |
| Stereo width | Slight spread (0.2) | Mono (0.0) | Mono (0.0) |

### Aggregate Purr Mix

Individual cat purrs do NOT all play simultaneously as separate voices once there are more than 4-5 cats. Instead:

1. **0-4 cats:** Each cat gets its own voice. Full spatial positioning. Player can distinguish individuals.
2. **5-12 cats:** Nearest 4 cats get individual voices. Remaining cats contribute to an "aggregate purr bus" — a single stereo voice that is a real-time mix of their variants, panned to their average position, volume proportional to count.
3. **13+ cats:** Nearest 2 get individual voices. The rest feed the aggregate bus. Aggregate bus adds subtle chorus effect (+/- 5 cents detuning, 0.3 Hz LFO) to simulate many overlapping purrs without needing many voices.

This scales to hundreds of cats without scaling voice count.

### Godot Implementation Notes

- Use `AudioStreamPlayer2D` per individual cat purr.
- Use `AudioEffectPitchShift` on per-cat audio buses for real-time pitch variation.
- Use `AudioEffectFilter` (BandPass / LowPass) for overtone control.
- Playback speed adjustment via `AudioStreamPlayer2D.pitch_scale` (this changes both pitch and speed simultaneously; for pitch-only shift, route through the pitch-shift effect and counter-adjust speed).
- Aggregate purr bus: a dedicated audio bus with `AudioEffectChorus` for the many-cats shimmer.

---

## 3. Silence Disambiguation

The design doc says "silence = sadness." But ferrets go dead-silent during dead sleep, which is comedy, not sadness. We need the player to hear the difference between "something is wrong" and "something adorable is happening." The server hum baseline is the key.

### The Baseline Hum

As long as at least one server is powered and connected, the room has a **non-zero audio floor**: the server fan hum at 40-60 Hz. This hum is always present, like the idle tone of a living building. It is the acoustic equivalent of a power LED.

The hum tells the player: "Infrastructure is on. The room is alive. The absence you're hearing is biological, not systemic."

### Three Silence States

| State | What the player hears | What is absent | Baseline hum? | Visual backup | Emotional read |
|---|---|---|---|---|---|
| **Healthy silence** (ferret dead sleep, cat deep nap) | Server hum present and steady. Occasional ambient sounds from other animals continue. The *specific location* of the sleeping animal is quiet, but the room is not. | Vocalization and movement from the sleeping animal only | Yes, steady | Animal visually limp/curled. Breathing animation (slow for cat, imperceptible for ferret). No distress pose. | Cozy. Peaceful. Maybe a little alarming for the ferret, which is the joke. |
| **Degraded silence** (animals uncomfortable, needs unmet) | Server hum still present but purring has thinned or dropped out. The *room* feels emptier. Remaining sounds are sparse: isolated drips, lone fan, no vocal warmth. Quality of remaining sounds shifts — reverb tail gets longer (room sounds bigger when it is emptier of soft bodies absorbing reflections). | Aggregate purr layer. Grooming, kneading, comfort sounds. Happy vocalizations (dook, chirp, trill). | Yes, steady. Hum becomes more prominent in the mix because purring is not masking it. | Cats in alert/restless poses. Ferrets pacing, not playing. Comfort indicators amber/red. | Lonely. The hum feels cold when it stands alone. |
| **Empty silence** (no animals, or all animals have wandered off) | Server hum only. No biological sounds at all. A single drip echoes. The reverb is long and hollow. | Everything biological. | Yes, if servers are on. If servers are also off: true silence — only building settling (very rare, quiet creaks). | Empty racks. No movement. The room looks and sounds like the backstory: an abandoned datacenter. | Desolate. The intended emotional floor. This is what the player is working to fill. |

### How the Player Learns the Difference

1. **Ferret dead sleep** is localized silence. The ferret goes quiet, but the cat two rack slots over is still purring. The room's aggregate soundscape barely changes. The player learns: "one quiet spot in a noisy room = something sleeping."

2. **Room-wide unhappiness** is distributed silence. Purring thins across multiple cats simultaneously. The aggregate purr bus volume drops. The server hum rises in relative prominence. The player learns: "the hum is louder than usual = cats are not happy."

3. **The robot helps.** During ferret dead sleep, the robot does a health check scan and logs concern: "Device F01 unresponsive. No IOPS. No thermal output. Paging... Device F01 still unresponsive. Scheduling follow-up in 30 seconds." This is comedy, but it also tells the player "the game knows this animal is fine." During actual unhappiness, the robot logs differently: "IOPS aggregate trending below baseline. Multiple devices reporting reduced throughput."

### Technical Implementation

- Track `aggregate_purr_volume` as a smoothed int (exponential moving average, tau = 2 seconds). Expose it as a global audio parameter.
- Track `active_biological_sound_count` (number of animal sound emitters currently producing sound).
- When `aggregate_purr_volume` drops below 400/1000 of its recent peak (measured over last 60 seconds), and `active_biological_sound_count` drops below 500/1000 of animal count: classify room state as DEGRADED.
- When `active_biological_sound_count` is 0: classify as EMPTY.
- When individual animal sound is 0 but room state is NOMINAL: classify that animal as SLEEPING.
- Feed room state classification to the reverb send: NOMINAL = short reverb (0.3s decay, room is full of absorptive bodies). DEGRADED = medium reverb (0.8s decay). EMPTY = long reverb (1.5s decay). Reverb crossfades over 3 seconds to avoid abrupt shifts.

---

## 4. Player Action Feedback Sounds

Every player action gets immediate audio feedback. These are in the UI / Player Actions voice category (4 reserved voices). They are non-spatial (centered in the mix, no distance attenuation) because they represent the player's own agency, not the world.

| Action | Sound Description | Duration | Frequency Range | Notes |
|---|---|---|---|---|
| **Hover over rack slot** | Faint electrical tick — like a relay engaging. Barely there. | ~60 ms | 2-4 kHz click | Subtle enough to not annoy during rapid mouse movement. Cooldown: max 1 per 150 ms. |
| **Select rack slot (click/A)** | Soft mechanical latch — a rack rail engaging. Satisfying but quiet. Like sliding a server into guides and hearing it seat. | ~120 ms | 800 Hz-3 kHz, sharp transient | Slightly different pitch depending on whether the slot is empty vs. occupied. |
| **Pick up object** | Two-part: brief magnetic disengage "chk" + sustained light hum while held (object hovering on the arm's magnetic gripper). | Chk: 80 ms. Hum: looping while held. | Chk: 1-2 kHz. Hum: 200 Hz, very quiet. | The hum stops the instant the object is placed. Absence of hum = hands are empty. |
| **Place object (valid)** | Satisfying mechanical thunk-settle. Weight implied by pitch: heavy objects (server) = lower, 150-300 Hz. Light objects (feather toy) = higher, 400-800 Hz. Followed by a micro-whir as the arm retracts. | ~200 ms thunk + 150 ms whir | 150-800 Hz (varies) | This is the most important "feel good" sound in the UI. It must feel *right*. Like a LEGO brick clicking in. |
| **Place object (invalid / red highlight)** | Dull, muted bonk. The sound of trying to put something where it does not fit. Not a buzzer — a physical "that didn't seat." | ~100 ms | 200-400 Hz, no high-frequency content (feels soft, not alarming) | Never punishing. Just informational. |
| **Open drawer (Kitties)** | Soft wooden slide + tiny muffled mews from inside. The mews are very quiet — you almost imagined them. | Slide: 300 ms. Mews: 200 ms, delayed 100 ms. | Slide: 100-600 Hz. Mews: 800-2000 Hz. | The kitten paws poking out could have a tiny scritch sound too. |
| **Open drawer (Cables)** | Metal slide (heavier than kitty drawer) + a faint tangled rustling, like pulling headphones out of a pocket. | 300 ms slide + 200 ms rustle | Slide: 80-400 Hz. Rustle: 2-6 kHz. | Should feel slightly chaotic compared to the neat infrastructure drawer. |
| **Open drawer (Infrastructure)** | Clean metal slide. Click-stops at full extension. Professional. | 250 ms slide + 50 ms click | Slide: 100-500 Hz. Click: 2 kHz transient. | This drawer shuts nicely, remember? The sound reflects that. |
| **Open drawer (Utilities)** | Wood slide (same family as kitty drawer but deeper). Lighter, emptier at start. As items accumulate, faint rattling of contents. | 300 ms | 100-500 Hz + rattle overlay proportional to item count | Sound evolves with game progression. |
| **Close any drawer** | Reverse of open. Slide back + soft latch. Slightly faster than open (drawers fall shut). | 200 ms | Same as open, reversed envelope | |
| **Plug in cable (power or ethernet)** | Two-phase: stretchy cable pull (as it routes from source to destination) + final snap-click of the RJ45/power connector seating. | Pull: 400-800 ms (scales with cable length). Click: 50 ms. | Pull: 200-1000 Hz, filtered noise. Click: 3-5 kHz, sharp. | The click should feel as satisfying as plugging in a real ethernet cable. That snap is iconic. |
| **Unplug cable (manual)** | Clip release + light spring-back of cable retracting. | 150 ms | Clip: 3 kHz click. Retract: 200-800 Hz descending swoosh. | |
| **Cable unplugged by kitten** | Same unplug sound but with a tiny mrrp layered on top and a faint jingle (kitten batting the connector). | 200 ms | Same + 1-3 kHz mrrp | Comedy sound. Player hears it and knows exactly what happened. |
| **Switch to wiring view** | See Section 5 below (its own section). | | | |
| **Zoom in (click rack / interior view)** | World sounds muffle slightly as if moving through a wall, then open up into the close-up acoustic space. A subtle "focusing" tonal shift — like putting on headphones. | 400 ms crossfade | Full spectrum transition | See Section 5 for details. |
| **Zoom out (exit interior view)** | Reverse of zoom in. Close-up acoustics widen back to room scale. | 400 ms crossfade | | |
| **Scroll / pan camera** | No sound. Camera movement should be silent. Sound follows the world, not the camera. | 0 | N/A | Adding a scroll sound would be constant and maddening. |
| **Pspsps / kissy noise (click on wandering cat)** | Breathy "pspsps" or a mouth-click sound. Gentle, human, warm. The one sound in the game that comes from "outside" the datacenter. | 300 ms | 2-8 kHz, sibilant | This is the player's voice, implied. It breaks the fourth wall just slightly. |
| **Robot arm idle scan** | Soft servo pan + scanning tone (ascending two-note beep, like a barcode reader). | 600 ms | Servo: 200-400 Hz. Beep: 1 kHz + 1.2 kHz. | Happens during lost-player detection. Friendly, not alarming. |
| **Milestone / first discovery** | Not a fanfare. A single warm chime that rings and decays slowly — like a singing bowl struck once. The room briefly feels more resonant. | 2-3 seconds decay | Fundamental at 400 Hz, harmonics at 800, 1200, 1600 Hz | Rare enough to feel special. Used for: first purr, first ferret arrival, first can opened, first kitten born. |

---

## 5. View Transition Audio

### Front View (default) to Wiring View (back of racks)

The player clicks the coil-of-wire button and the camera swings around to show the back of the racks. Acoustically, this is like walking from the front of a server row to the hot aisle behind it.

**Transition (400 ms crossfade):**

1. **Low-pass filter sweeps down** from open (20 kHz cutoff) to muffled (800 Hz cutoff) over the first 200 ms. This simulates passing through/around the rack — high frequencies are blocked by the metal enclosure.

2. **Reverb character changes.** Front view has a wider, more diffuse reverb (open room). Wiring view switches to a tighter, more reflective reverb (enclosed hot aisle between rack backs). Pre-delay shortens from 20 ms to 5 ms. Decay shortens from 0.3s to 0.15s. Early reflections become denser and more metallic.

3. **Low-pass filter sweeps back up** from 800 Hz to 2000 Hz over the next 200 ms. We don't return to fully open — wiring view stays slightly muffled compared to front view (cutoff at 2 kHz vs. front view's open 20 kHz). Animal sounds feel "behind a wall."

4. **Fan noise increases by +3 dB.** The back of the racks is where the hot exhaust exits. Fans are louder here. This is physically accurate and creates an immediate "I'm in a different place" feeling.

5. **Cable-specific sounds become prominent.** In wiring view, every cable has a faint electrical hum scaled to its load. Active ethernet cables have a barely-perceptible data chatter (very quiet filtered white noise, like distant hard drive activity). Power cables hum at 60 Hz. These sounds are inaudible from the front; they only appear in wiring view, giving this perspective its own audio identity.

6. **Animal sounds attenuate.** Purring, mewing, dooking — all reduced by -8 dB and low-passed. They are still present (the animals are right on the other side of the rack) but feel distant and muffled, like hearing a cat purr through a wall.

**Returning to front view** reverses the process: filter sweeps open, reverb widens, fan noise drops, cable hum disappears, animal sounds return to full presence.

### Front View to Interior View (zoom into rack slot)

The player clicks a rack slot and the camera zooms into the drawer.

**Transition (400 ms):**

1. **All sounds except the occupant's sounds duck by -10 dB.** The world recedes. You are focused on this one space.

2. **The occupant's sounds gain +3 dB and lose spatial panning** (they move to center, because you are now "inside" with them). If it is a purring cat, the purr fills the stereo field. This should feel intimate — like pressing your ear against a sleeping cat.

3. **A subtle room tone shift:** the interior has a very short, boxy reverb (200 ms decay, small-room character). Think: the inside of a cardboard box. The outside room's reverb is muted.

4. **Status bar sounds become audible.** The side-panel indicators (heat, power, connectivity) emit faint tonal drones — pitched to their level. These are inaudible at room scale but in the interior view, you can hear the "health" of this specific unit. Low heat = low quiet tone. High heat = warmer, slightly higher tone. This gives the interior view its own sonic texture and reinforces the robot's datacenter interpretation.

**Returning to room view** reverses: occupant sounds re-spatialize to their rack position, world sounds fade back in, boxy reverb crossfades to room reverb.

---

## 6. Spatial Audio Attenuation Spec

### Attenuation Curve

**Shape:** Inverse-distance with a soft knee. Not linear (too quiet too fast) and not inverse-square (too extreme for a small space). The curve is:

```
volume_db = max_volume - attenuation_rate * max(0, distance - reference_distance)
```

Clamped to `[silence_threshold, max_volume]`.

**Parameters (all in mods/tcp_base/config/spatial.json):**

| Parameter | Value | Unit | Notes |
|---|---|---|---|
| `reference_distance` | 1 rack-width | ~0.6 m equivalent | Sound is at full volume within this radius of its source |
| `attenuation_rate` | 3.0 | dB per rack-width | Gentle falloff. At 5 racks away, sound is -12 dB (noticeably quieter but still present) |
| `max_audible_range` | 8 rack-widths | ~4.8 m equivalent | Beyond this, sound is culled entirely. Saves voice budget. |
| `silence_threshold` | -24 dB | dB | The volume at which a sound is considered inaudible and can be culled |
| `max_volume` | 0 dB | dB | Full volume at or within reference distance |

**Why 8 rack-widths max?** The prototype is 5 racks wide. At 8 rack-widths, a sound at the far left is barely audible at the far right. This means the player can always hear the loudest events across their entire habitat, but only clearly hears what is near the camera center. Multiplayer neighbor sounds fade in at the edges naturally.

### Vertical Attenuation (within a rack)

Rack units are much smaller than rack-widths. Vertical attenuation uses the same curve but at a different scale:

| Parameter | Value | Notes |
|---|---|---|
| `vertical_reference_distance` | 3 U | Sound is full volume within 3 rack units vertically |
| `vertical_attenuation_rate` | 2.0 dB per 3 U | Gentler than horizontal — racks are enclosed channels that carry sound well vertically |
| `vertical_max_range` | 42 U (full rack) | Sound from top of rack is audible at bottom, just quiet |

### Interior View Audio Behavior

When the player zooms into a rack slot (interior view), the spatial model changes:

1. **The viewed slot becomes the listener position.** All spatial calculations re-center on this slot. Sounds in adjacent slots are "nearby"; sounds across the room are "far."

2. **Attenuation rate doubles** for everything outside the viewed rack. This exaggerates the "inside looking out" feeling. The room recedes faster than it would at room-scale view.

3. **Sounds within the same rack** attenuate at half rate (1.5 dB per rack-width-equivalent instead of 3.0). You can hear what is above and below you in the rack more clearly than you can hear across the room. This is physically accurate — metal rack rails conduct vibration.

4. **The server in the viewed slot** is at zero distance. If it is running, you hear the fan at full volume. If a cat is there, the purr is intimate and room-filling. This is intentional — interior view is the "put your ear against it" perspective.

### Floor-Level Audio

Animals on the floor in front of the racks have the same horizontal attenuation as rack-mounted sources. However:

- Floor sounds have a slight high-frequency boost (+2 dB above 4 kHz) from tile reflections. Claw taps and can scraping sound bright and clicky on the hard floor.
- Rack-mounted sounds have a slight low-frequency boost (+1 dB below 200 Hz) from rack resonance. Servers and purring cats sound warmer when enclosed.

This frequency difference helps the player subconsciously locate sounds vertically even without explicit vertical panning.

### Panning

Horizontal panning maps linearly to screen position. A sound at the left edge of the visible area is panned hard left. A sound at center is center. Sounds offscreen are panned to the nearest edge and attenuated by distance.

No vertical panning (2D game, stereo output assumed for prototype). Vertical position is conveyed by the frequency coloring described above.

### Godot Implementation

- `AudioStreamPlayer2D.max_distance` = 8 rack-widths in pixels.
- `AudioStreamPlayer2D.attenuation` = custom curve via `AudioStreamPlayer2D.attenuation_model` set to `ATTENUATION_INVERSE_DISTANCE`, with `unit_size` = 1 rack-width in pixels.
- Interior view transition: re-parent the `AudioListener2D` node from the camera to the viewed rack slot, with a 400 ms interpolated move. Simultaneously adjust all `AudioStreamPlayer2D.max_distance` values via a global multiplier exposed on the audio bus.
- Floor vs. rack frequency coloring: two sub-buses ("floor_sources" and "rack_sources") with static EQ. All floor audio nodes route through the floor bus; all rack audio nodes route through the rack bus.

---

## 7. Prototype Sound Source Checklist

Every object and animal state has a defined sound. All sounds spatial unless noted.

| Source | Sound | Communicates |
|---|---|---|
| Server (running) | Low fan hum, steady | Infrastructure on, heat flowing |
| Cat (content) | Deep purr, 80-100Hz | Happy; aggregate = room health |
| Cat (uncomfortable) | Purr thins, pitch rises, micro-vocalizations | Something wrong, before meters show it |
| Cat (relocating) | Thud, paw padding, annoyed mew | Disruption happened |
| Cat (ambient) | Squeak-yawn, soft lick, fabric press, sigh | Life is happening |
| Ferret (exploring) | Snuffling, claw taps on tile | Curious, moving |
| Ferret (excited) | Dooking, rapid scrabbling | Having a great time |
| Ferret (dragging can) | Metal-on-tile scraping, rhythmic | Directional cue toward arm |
| Ferret (in tubes) | Rubbery scrabbling, hollow resonance | Traversing infrastructure |
| Ferret (dead sleep) | Complete silence | Alarming absence (comedy) |
| Robot arm (idle) | Faint servo hum | Spatial anchor, alive |
| Robot arm (activating) | Rising tone → chunk-whirr-scoop → wash → hose | Processing a can |
| Cardboard box (intact) | Deep hollow bonk, muffled rustle | Sturdy, enclosed |
| Cardboard box (worn) | Thin papery bonk, light tearing | Degrading |
| Bedding scraps | Soft dry whisper | Material transformed |
| Feather + fan | Fan whir + feather flutter | Stimulation active |
| Furballs (many) | Faint dry rustling | Accumulation happening |
| Furball pickup | Tiny *fwip* | Ferret cleaning up |
| Cooling pipes | Occasional drip | Water available |

### Aggregate Soundscape Progression

- **Empty room:** Server hum only. Cold. Lonely.
- **One cat settling:** First purr joins hum. Warmth enters the sound.
- **Multiple cats + ferrets:** Layered purrs at different pitches, occasional dooking. Room feels alive.
- **Thriving:** Rich harmony — purrs, grooming, can-scraping, drips. Auditory "buried in fluffy joy."
- **After disruption:** Purring drops. Scrabbling, mews, thuds. Gradual return as animals resettle.

### Playtest Validation

Can a blindfolded player tell when a cat is happy vs. unhappy? When a ferret is near the arm vs. across the room? If yes, the sound system works.
