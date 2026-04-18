# Sound Asset Tracker

Living list of all sound assets — what exists, what's needed, and what's placeholder. See `.claude/rules/asset-pipeline.md` for naming conventions, format specs, and directory structure.

**Format specs:** WAV 16-bit 48kHz, normalize to -1 dBFS peak. `.ogg` for loops/music (compressed), `.wav` for short SFX (low latency). See asset-pipeline.md for sox command and import settings.

---

## Existing Sounds

### Cat (`mods/tcp_base/sounds/cat/`)

| Sound | File | Type | Notes |
|---|---|---|---|
| Purr loop 01 | `purr_loop_01.wav` | Loop | Core metric — satisfaction-driven pitch |
| Purr loop 02 | `purr_loop_02.wav` | Loop | Variation |

### Ferret (`mods/tcp_base/sounds/ferret/`)

| Sound | File | Type | Notes |
|---|---|---|---|
| Dook 01 | `ferret_dook_01.wav` | One-shot | Excited/alert vocalization |

### Objects (`mods/tcp_base/sounds/objects/`)

| Sound | File | Type | Notes |
|---|---|---|---|
| Footsteps 01 | `animal_footsteps_01.wav` | One-shot | Generic animal footsteps |
| Clothing rustle 01 | `clothing_rustle_01.wav` | One-shot | Soft fabric contact |

### Ambient (`mods/tcp_base/sounds/ambient/`)

| Sound | File | Type | Notes |
|---|---|---|---|
| Datacenter hum | `datacenter_hum_loop.wav` | Loop | Base ambient layer |

---

## Needed Sounds

### Resting-On Feature (Ring 1)

| # | Sound | File | Duration | Type | Priority | Description |
|---|---|---|---|---|---|---|
| 1 | Ferret content churr | `ferret/ferret_churr_settle_01.wav` | 1-2 sec | One-shot | **High** | Soft, breathy, content vocalization. Lower pitch than dook — like a tiny motor winding down. The "I found the perfect spot" sound. **Search terms:** "ferret clucking," "ferret chuckling," "ferret happy sound" (NOT dooking). **Synthesis ref:** dook pitch-shifted down 4 semitones, 0.85x speed, low-pass at 1.2 kHz. **V1 placeholder:** `clothing_rustle_01.wav` at -8 dB. |
| 2 | Ferret sleep breathing loop | `ferret/ferret_breathing_sleep_loop.wav` | 2-4 sec loop | Loop | **High** | Very faint rhythmic breathing at ~2 Hz rate (two breaths per second). 200-300 Hz range, mixed at -12 dB relative to cat purr. Layered on cat purr to create a polyrhythm — this is the audible indicator of stacking. Could potentially be synthesized (soft rhythmic filtered noise pulse). **V1 placeholder:** none (visual-only indicator). |
| 3 | Cat mrrp (neutral) | `cat/cat_mrrp_01.wav` | 0.3-0.5 sec | One-shot | **Medium** | Classic cat "mrrp" acknowledgment chirp. Short rising tone. Not annoyed, not excited — just "oh, okay." Broadly useful beyond resting-on — the general "cat notices a thing" sound. **Note:** Listed in asset-pipeline.md prototype spec as `cat_mrrp.ogg` but not yet created. |
| 4 | Cat mrrp (annoyed) | `cat/cat_mrrp_annoyed_01.wav` | 0.5-0.8 sec | One-shot | **Medium** | Slightly longer, flatter "mrrrrp" with descending tone. The "I'm getting up now" sound. Played when cat dumps a ferret. Comedy moment — pairs with ferret dook/squeak. |
| 5 | Ferret alarmed squeak | `ferret/ferret_squeak_alarmed_01.wav` | 0.2-0.3 sec | One-shot | **Low** | Short, high-pitched surprise squeak. Not distressed — just "whoa!" Higher pitch than dook, shorter duration. **V1 placeholder:** `ferret_dook_01.wav`. |
| 6 | Deep content purr | `cat/purr_loop_03.wav` | 2-4 sec loop | Loop | **Low** | Deeper, richer purr with low-mid warmth (100-200 Hz emphasis). The "extra content" purr for when a cat has something warm sleeping on it. **V1 placeholder:** existing purr loops. |

### Prototype Gaps (from asset-pipeline.md spec)

Sounds listed in the pipeline spec's "Must-Have" list that don't exist yet:

| # | Sound | File | Type | Priority | Description |
|---|---|---|---|---|---|
| 7 | Cat meow | `cat/cat_meow_01.wav` | One-shot | **High** | Calling attention / unhappy. Core cat vocabulary. |
| 8 | Robot arm servo | `robot/arm_servo_move.wav` | One-shot | **High** | Repositioning mechanical sound |
| 9 | Robot arm scan beep | `robot/arm_scan_beep.wav` | One-shot | **High** | Scanning an animal |
| 10 | Can scrape loop | `objects/can_scrape_loop.wav` | Loop | **Medium** | Ferret dragging a tuna can |
| 11 | Can open chunk | `objects/can_open_chunk.wav` | One-shot | **Medium** | Robot arm opening can. Satisfying pop. |
| 12 | Server fan loop | `infrastructure/server_fan_loop.wav` | Loop | **Medium** | Per-server ambient. Pitch/volume varies with heat. |
| 13 | Cable plug | `infrastructure/cable_plug.wav` | One-shot | **Medium** | Satisfying click on connection |
| 14 | Box shred | `objects/box_shred.wav` | One-shot | **Low** | Ferret destroying a box |
| 15 | Drawer open/close | `ui/drawer_open.wav`, `ui/drawer_close.wav` | One-shot | **Low** | HUD interaction |
| 16 | Place confirm | `ui/place_confirm.wav` | One-shot | **Low** | Object placement feedback |
| 17 | Pipe drip | `infrastructure/pipe_drip.wav` | One-shot | **Low** | Condensation ambient |

### Ambient Behavior Sounds (Ring 0)

| # | Sound | File | Duration | Type | Priority | Description |
|---|---|---|---|---|---|---|
| S1 | Cat yawn | `cat/cat_yawn_01.wav` | 0.5-1 sec | One-shot | **Medium** | Tiny squeak-yawn during STRETCHING. Quiet, endearing. |
| S2 | Cat lick/groom | `cat/cat_groom_01.wav` | 1-2 sec | One-shot | **Medium** | Soft rhythmic licking sound during GROOMING. Subtle, not wet. |
| S3 | Fabric kneading | `objects/fabric_knead_01.wav` | 1-2 sec | Loop | **Low** | Soft fabric pressing/pulling sound during KNEADING on soft surfaces. |
| S4 | Ferret dook (excited) | `ferret/ferret_dook_excited_01.wav` | 0.5 sec | One-shot | **Low** | Faster, higher-pitched variant of dook for high-energy moments. |

### HUM Cable System (Phase 2)

Deferred from the cable system PR. Wired into `sound_manager.gd` on `Events.cable_connected` / `Events.cable_disconnected` and HUM brownout signals.

| # | Sound | File | Duration | Type | Priority | Description |
|---|---|---|---|---|---|---|
| C1 | Cable pop | `infrastructure/cable_pop_01.wav` | ~0.2 sec | One-shot | **High** | RJ45-clip release — the satisfying plastic "tick-pop" of a network cable latching or unlatching. Plays on `cable_connected` and `cable_disconnected`. Supersedes the older `cable_plug` entry (#13). **Search terms:** "RJ45 click," "ethernet plug," "plastic latch release." |
| C2 | Cable lift | `infrastructure/cable_lift_01.wav` | ~0.1 sec | One-shot | **High** | Dry 2-3 kHz click on pickup — distinct from cable_pop, shorter and drier. Plays when a cable end is picked up in wiring mode (before the new endpoint is chosen). **Search terms:** "dry click," "short tick," "plastic tap." |
| C3 | HUM brownout enter | `ambient/hum_brownout_enter_01.wav` | ~0.4 sec | One-shot | **High** | Detune-and-die tone — the ambient hum dropping out of harmonic lock. Played once on HUM reserve crossing the brownout threshold downward. Should feel regretful, not alarming. **Synthesis ref:** sine wave at ~27 Hz's third harmonic (~80 Hz) with pitch detune down 30 cents over the duration, amplitude tail. |
| C4 | HUM brownout recover | `ambient/hum_brownout_recover_01.wav` | ~0.4 sec | One-shot | **High** | Soft re-engage swell — the ambient hum pulling back into lock. Played once on HUM reserve crossing the brownout threshold upward. Pairs with C3 as the recovery inverse. **Synthesis ref:** reverse of C3's pitch curve, amplitude swell rather than tail. |

### Social Desire Feature (Ring 1)

| # | Sound | File | Duration | Type | Priority | Description |
|---|---|---|---|---|---|---|
| 18 | Cat chirp (social) | `cat/cat_chirp_social_01.wav` | 0.3-0.5 sec | One-shot | **Medium** | Short friendly chirp when cat acknowledges a nearby companion. Distinct from mrrp — lighter, more musical. |

---

## Sourcing Notes

- **Freesound.org** is the primary source for CC0/CC-BY sounds
- Every imported sound gets an entry in `../game_assets/Credits.md` with author name and source URL
- Original files (pre-normalization) are kept in `../game_assets/`
- Normalize with: `sox input.wav -b 16 -r 48000 output.wav gain -n -1`
- Import settings: `.import` files must have `compress/mode=2` (QOA) and `edit/loop_mode=0`
